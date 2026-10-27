#!/usr/bin/env bash
# Fresh Ubuntu 22.04/24.04, x86_64/aarch64. VLESS + REALITY + Vision.
set -Eeuo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C
umask 077
die() { echo "ERROR: $*" >&2; exit 1; }
[[ $EUID == 0 ]] || die "Use sudo bash."
PORT=443
SNI=www.ibm.com
CONF=/usr/local/etc/xray/config.json
LINK=/root/xray-reality-link.txt
if (( $# )) && [[ $1 == --show-link ]]; then cat "$LINK"; exit; fi
[[ $# == 0 && -d /run/systemd/system ]] || die "Requires Linux systemd; no arguments."
. /etc/os-release
[[ $ID == ubuntu && ( $VERSION_ID == 22.04 || $VERSION_ID == 24.04 ) ]] || die "Requires Ubuntu 22.04/24.04."
case "$(uname -m)" in x86_64|aarch64) ;; *) die "Unsupported architecture." ;; esac
exec 9>/run/lock/xray-reality-deploy.lock
flock -n 9 || die "Another deployment is running."
for p in /usr/local/etc/xray /etc/xray /etc/v2ray /usr/local/etc/v2ray /usr/local/x-ui /etc/x-ui "$LINK"; do
  [[ ! -e $p && ! -L $p ]] || die "Existing state: $p. Refusing overwrite."
done
for name in xray v2ray x-ui; do
  ! command -v "$name" >/dev/null || die "Already installed: $name."
  [[ $(systemctl show "$name.service" -p LoadState --value) == not-found ]] || die "Existing service: $name."
done
LISTEN=$(ss -H -ltn "sport = :$PORT")
[[ -z $LISTEN ]] || die "TCP 443 is occupied."
WORK=$(mktemp -d /tmp/xray-reality.XXXXXXXX)
STARTED=0
DONE=0
cleanup() {
  local rc=$?
  if (( rc != 0 )); then
    echo "FAILED. Inspect logs; partial installation is retained." >&2
    if (( STARTED && ! DONE )); then systemctl stop xray.service >/dev/null 2>&1 || true; fi
  fi
  rm -rf -- "$WORK"
}
trap cleanup EXIT
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl unzip python3
fetch() { curl -fLsS --proto '=https' --tlsv1.2 --retry 2 --connect-timeout 10 --max-time 180 "$@"; }
TOKEN=$(curl --noproxy '*' -fsS --connect-timeout 1 --max-time 2 -X PUT \
  -H 'X-aws-ec2-metadata-token-ttl-seconds: 60' http://169.254.169.254/latest/api/token 2>/dev/null || true)
IP=''
if [[ -n $TOKEN ]]; then
  IP=$(curl --noproxy '*' -fsS --connect-timeout 1 --max-time 2 \
    -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || true)
fi
[[ -n $IP ]] || IP=$(fetch -4 https://checkip.amazonaws.com)
IP=$(printf '%s' "$IP" | tr -d '[:space:]')
python3 - "$IP" "$SNI" <<'PY'
import ipaddress, socket, ssl, sys
ip=ipaddress.ip_address(sys.argv[1])
if ip.version!=4 or not ip.is_global:
    raise SystemExit("Public IPv4 required.")
ctx=ssl.create_default_context()
ctx.minimum_version=ctx.maximum_version=ssl.TLSVersion.TLSv1_3
ctx.set_alpn_protocols(["h2"])
with socket.create_connection((sys.argv[2],443),timeout=10) as sock:
    with ctx.wrap_socket(sock,server_hostname=sys.argv[2]) as tls:
        if tls.version()!="TLSv1.3" or tls.selected_alpn_protocol()!="h2":
            raise SystemExit("REALITY target must support TLS 1.3 and h2.")
PY
fetch https://raw.githubusercontent.com/XTLS/Xray-install/main/install-release.sh -o "$WORK/install.sh"
bash -n "$WORK/install.sh"
STARTED=1
bash "$WORK/install.sh" install --without-geodata --without-logfiles
systemctl stop xray.service
/usr/local/bin/xray x25519 > "$WORK/keys.txt"
python3 - "$WORK" "$IP" "$PORT" "$SNI" <<'PY'
import base64, json, pathlib, re, secrets, sys, uuid
from urllib.parse import urlencode, quote
work,ip,port,sni=pathlib.Path(sys.argv[1]),sys.argv[2],int(sys.argv[3]),sys.argv[4]
keys={}
for line in (work/"keys.txt").read_text().splitlines():
    label,sep,value=line.partition(":")
    label=label.lower().replace(" ","")
    if label=="privatekey": name="private"
    elif label in ("publickey","password","password(publickey)"): name="public"
    else: continue
    value=value.strip()
    if name in keys or not re.fullmatch(r"[A-Za-z0-9_-]{43}",value):
        raise SystemExit("Unexpected x25519 output.")
    if len(base64.urlsafe_b64decode(value+"="))!=32:
        raise SystemExit("Invalid x25519 key.")
    keys[name]=value
if set(keys)!={"private","public"}:
    raise SystemExit("Missing x25519 key pair.")
uid=str(uuid.uuid4())
sid=secrets.token_hex(8)
flow="xtls-rprx-vision"
cfg={"log":{"loglevel":"warning"},"inbounds":[{
 "listen":"0.0.0.0","port":port,"protocol":"vless",
 "settings":{"clients":[{"id":uid,"flow":flow}],"decryption":"none"},
 "streamSettings":{"network":"tcp","security":"reality","realitySettings":{
 "show":False,"target":sni+":443","xver":0,"serverNames":[sni],
 "privateKey":keys["private"],"shortIds":[sid]}}
}],"outbounds":[{"protocol":"freedom","tag":"direct"}]}
query=urlencode({"encryption":"none","flow":flow,"security":"reality",
 "sni":sni,"fp":"chrome","pbk":keys["public"],"sid":sid,"type":"tcp","spx":"/"})
(work/"config.json").write_text(json.dumps(cfg,indent=2)+"\n")
(work/"link.txt").write_text(f"vless://{uid}@{ip}:{port}?{query}#"+
 quote("VLESS-REALITY-"+ip,safe="")+"\n")
PY
/usr/local/bin/xray run -test -config "$WORK/config.json"
USER_NAME=$(systemctl show xray.service -p User --value)
[[ -n $USER_NAME && $USER_NAME != root ]] || die "Expected non-root service."
GROUP_NAME=$(id -gn "$USER_NAME")
chown root:"$GROUP_NAME" /usr/local/etc/xray
chmod 750 /usr/local/etc/xray
install -o root -g "$GROUP_NAME" -m 640 "$WORK/config.json" "$CONF"
if command -v ufw >/dev/null && ufw status | grep -q '^Status: active'; then ufw allow "$PORT/tcp"; fi
systemctl enable xray.service
systemctl restart xray.service
sleep 2
systemctl is-active --quiet xray.service || die "Service failed."
LISTEN=$(ss -H -ltn "sport = :$PORT")
[[ -n $LISTEN ]] || die "No listener."
install -m 600 "$WORK/link.txt" "$LINK"
if [[ -f $0 ]]; then install -m 700 "$0" /root/xray-reality-deploy.sh; fi
DONE=1
echo "LOCAL SERVICE READY | VLESS + REALITY + Vision | $IP:443 | SNI: $SNI"
echo "Allow inbound TCP 443 in AWS security group. Client connectivity is not tested."
echo "Import this private link into v2rayN / v2rayNG:"
cat "$LINK"
echo "Show again: sudo cat $LINK"
