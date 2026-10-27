import base64
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest
import uuid

ROOT = Path(__file__).parent
SCRIPT = (ROOT / 'vmess.sh').read_text(encoding='utf-8')
BASH = os.environ.get('BASH_EXE', r'C:\Program Files\Git\bin\bash.exe' if os.name == 'nt' else 'bash')
BLOCKS = re.findall(r"<<'PY'\n(.*?)\nPY", SCRIPT, re.S)


def bash(source):
    return subprocess.run([BASH, '-c', source], text=True, capture_output=True)


def generate(ip='8.8.8.8'):
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run([sys.executable, '-c', BLOCKS[1], tmp, ip, '443'], check=True)
        cfg = json.loads((Path(tmp) / 'config.json').read_text())
        link = (Path(tmp) / 'link.txt').read_text().strip()
        assert link.startswith('vmess://')
        share = json.loads(base64.b64decode(link[8:], validate=True))
        return cfg, share


class VMessTests(unittest.TestCase):
    def test_bash_syntax(self):
        result = subprocess.run([BASH, '-n'], input=SCRIPT, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_python_syntax(self):
        self.assertEqual(len(BLOCKS), 2)
        for block in BLOCKS:
            compile(block, '<embedded>', 'exec')

    def test_config_and_share_roundtrip(self):
        cfg, share = generate()
        inbound = cfg['inbounds'][0]
        self.assertEqual(inbound['protocol'], 'vmess')
        self.assertEqual(inbound['port'], 443)
        self.assertEqual(inbound['streamSettings'], {'network': 'tcp', 'security': 'none'})
        self.assertEqual(share['id'], inbound['settings']['clients'][0]['id'])
        self.assertEqual(uuid.UUID(share['id']).version, 4)
        self.assertEqual(share['add'], '8.8.8.8')
        self.assertEqual(share['port'], '443')
        for key, value in {'v':'2', 'aid':'0', 'scy':'auto', 'net':'tcp', 'type':'none', 'tls':'', 'sni':''}.items():
            self.assertEqual(share[key], value)
        self.assertEqual(cfg['outbounds'][0]['protocol'], 'freedom')

    def test_unique_credentials(self):
        self.assertNotEqual(generate()[1]['id'], generate()[1]['id'])

    def test_ip_validation(self):
        for ip in ['127.0.0.1', '10.0.0.1', '::1', '2606:4700:4700::1111', 'bad']:
            with self.subTest(ip=ip):
                r = subprocess.run([sys.executable, '-c', BLOCKS[0], ip], capture_output=True)
                self.assertNotEqual(r.returncode, 0)
        self.assertEqual(subprocess.run([sys.executable, '-c', BLOCKS[0], '8.8.8.8']).returncode, 0)

    def test_existing_directory_stops(self):
        block = SCRIPT[SCRIPT.index('for p in '):SCRIPT.index('for name in ')]
        block = re.sub(r'for p in .*?; do', 'for p in "$TEST_EXISTING"; do', block)
        r = bash('die() { echo "$*"; exit 1; }; TEST_EXISTING=$(mktemp -d); trap \'rmdir "$TEST_EXISTING"\' EXIT; ' + block)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('Refusing overwrite', r.stdout)

    def test_existing_binary_stops(self):
        block = SCRIPT[SCRIPT.index('for name in '):SCRIPT.index('LISTEN=')]
        r = bash('die() { echo "$*"; exit 1; }; xray() { :; }; ' + block)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('Already installed: xray', r.stdout)

    def test_port_occupied_stops(self):
        block = SCRIPT[SCRIPT.index('LISTEN='):SCRIPT.index('# VMess authentication')]
        r = bash('die() { echo "$*"; exit 1; }; PORT=443; ss() { echo LISTEN; }; ' + block)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('443 is occupied', r.stdout)

    def test_clock_not_synced_stops(self):
        block = SCRIPT[SCRIPT.index('# VMess authentication'):SCRIPT.index('WORK=$(mktemp')]
        r = bash('die() { echo "$*"; exit 1; }; sleep() { :; }; timedatectl() { if [[ $1 == show ]]; then echo no; fi; }; ' + block)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('Clock is not synchronized', r.stdout)

    def test_clock_synced_passes_without_changes(self):
        block = SCRIPT[SCRIPT.index('# VMess authentication'):SCRIPT.index('WORK=$(mktemp')]
        r = bash('die() { echo "$*"; exit 1; }; timedatectl() { if [[ $1 == show ]]; then echo yes; else echo UNEXPECTED >&2; return 1; fi; }; ' + block)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertNotIn('UNEXPECTED', r.stderr)


if __name__ == '__main__':
    unittest.main(verbosity=2)
