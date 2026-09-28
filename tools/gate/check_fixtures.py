"""Privacy check for recorded fixtures (fixtures/README.md).

Several platforms echo the caller's address back in a response header
(`x-ksclient-ip`, `xhs-real-ip`, Baidu's Base64 `x-bfe-svbbrers`, ...). The
archive's scrubber missed some of them, and real exit addresses reached git.
This fails when any header whose name says it carries the client address holds
an IPv4 address outside the reserved and documentation ranges, in plain text
or Base64. Server addresses (load balancers, CDN nodes) are not client data
and are not checked. Standard library only, so it runs in hooks.
"""
from pathlib import Path
import base64
import binascii
import ipaddress
import json
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]

CLIENT_HEADER = re.compile(
    r'(real[-_]?ip|client[-_]?ip|public[-_]?ip|forwarded|remote[-_]?addr|connecting[-_]?ip|originating[-_]?ip|svbbrers)',
    re.IGNORECASE,
)
IPV4 = re.compile(r'(?<![\d.])(?:\d{1,3}\.){3}\d{1,3}(?![\d.])')
BASE64 = re.compile(r'[A-Za-z0-9+/_-]{8,}={0,2}')

# Addresses that may appear: unspecified, private, loopback, link-local, CGNAT
# and the three documentation ranges used as scrub replacements.
ALLOWED = [ipaddress.ip_network(n) for n in (
    '0.0.0.0/8', '10.0.0.0/8', '100.64.0.0/10', '127.0.0.0/8', '169.254.0.0/16',
    '172.16.0.0/12', '192.168.0.0/16', '192.0.2.0/24', '198.51.100.0/24', '203.0.113.0/24',
)]


def _public(text):
    for match in IPV4.findall(text):
        try:
            address = ipaddress.ip_address(match)
        except ValueError:
            continue
        if not any(address in network for network in ALLOWED):
            yield match


def _decoded(text):
    for token in BASE64.findall(text):
        padded = token + '=' * (-len(token) % 4)
        for decode in (base64.b64decode, base64.urlsafe_b64decode):
            try:
                yield decode(padded).decode('ascii')
                break
            except (binascii.Error, UnicodeDecodeError, ValueError):
                continue


def leaks(value):
    """Public IPv4 addresses in one client-address header value."""
    found = list(_public(value))
    for decoded in _decoded(value):
        found.extend(_public(decoded))
    return found


def _walk(node, path):
    if isinstance(node, dict):
        for key, value in node.items():
            if isinstance(value, str) and CLIENT_HEADER.search(key):
                yield f'{path}.{key}', value
            yield from _walk(value, f'{path}.{key}')
    elif isinstance(node, list):
        for index, value in enumerate(node):
            yield from _walk(value, f'{path}[{index}]')


def check(files):
    problems = []
    for file in files:
        try:
            data = json.loads(Path(file).read_text(encoding='utf-8'))
        except (OSError, ValueError):
            continue
        for where, value in _walk(data, ''):
            for address in leaks(value):
                problems.append(f'{file}: {where.lstrip(".")} holds client address {address}')
    return problems


def main():
    listed = subprocess.run(
        ['git', 'ls-files', '--cached', '--others', '--exclude-standard', '--', 'fixtures/*.json'],
        cwd=ROOT, capture_output=True, text=True, check=True,
    ).stdout.split()
    problems = check(ROOT / name for name in listed)
    for problem in problems:
        print(problem)
    if problems:
        print('replace them with 203.0.113.x (see fixtures/README.md)')
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
