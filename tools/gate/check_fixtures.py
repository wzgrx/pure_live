"""Privacy check for recorded fixtures (fixtures/README.md).

Several platforms echo the caller's address back in a response header
(`x-ksclient-ip`, `xhs-real-ip`, Baidu's Base64 `x-bfe-svbbrers`, ...). The
archive's scrubber missed some of them, and real exit addresses reached git.
Headers are checked deny-by-default because the names vary (LOOK's
`x-from-src` echoes it too): a recorded request or response header holding an
IPv4 address outside the reserved and documentation ranges, in plain text or
Base64, fails unless the header is a known server address (SERVER_HEADERS) or
the match is a version number (`Chrome/140.0.0.0`). In response bodies only
fields whose name says they carry the client address are checked: their text,
and their number when the address is written as a 32-bit integer (BIGO's
`clientIp`, either byte order). Danmaku frames (`*.jsonl`, one record per
line) are checked too, including such fields inside the frame text, inside
JSON carried as a string and inside Base64 payloads (gzip or zlib ones
unpacked). Standard library only, so it runs in hooks.
"""
from pathlib import Path
import base64
import binascii
import ipaddress
import json
import re
import subprocess
import sys
import zlib

ROOT = Path(__file__).resolve().parents[2]

CLIENT_HEADER = re.compile(
    r'(real[-_]?ip|client[-_]?ip|public[-_]?ip|forwarded|remote[-_]?addr|connecting[-_]?ip|originating[-_]?ip|svbbrers)',
    re.IGNORECASE,
)
# Headers whose addresses belong to the platform (load balancers, CDN edges,
# internal app servers), not to the caller.
SERVER_HEADERS = frozenset({
    'akamai-request-bc', 'lb', 'x-app-server-addr', 'x-route-server-addr',
    'x-origin-response-time', 'x-parent-response-time',
})
# A client-address field inside text: JSON (escaped or not) or `name=value`.
KEYED = re.compile(
    r'(?i)(real[-_]?ip|client[-_]?ip|public[-_]?ip|forwarded(?:[-_]?for)?|remote[-_]?addr|connecting[-_]?ip'
    r'|originating[-_]?ip|svbbrers)\\?["\']?\s*[:=]\s*\\?["\']?((?:\d{1,3}\.){3}\d{1,3}|\d{5,10})(?![\d.])'
)
IPV4 = re.compile(r'(?<![\d.])(?:\d{1,3}\.){3}\d{1,3}(?![\d.])')
BASE64 = re.compile(r'[A-Za-z0-9+/_-]{8,}={0,2}')

# Addresses that may appear: unspecified, private, loopback, link-local, CGNAT
# and the three documentation ranges used as scrub replacements.
ALLOWED = [ipaddress.ip_network(n) for n in (
    '0.0.0.0/8', '10.0.0.0/8', '100.64.0.0/10', '127.0.0.0/8', '169.254.0.0/16',
    '172.16.0.0/12', '192.168.0.0/16', '192.0.2.0/24', '198.51.100.0/24', '203.0.113.0/24',
)]


def _public(text, versions=False):
    for found in IPV4.finditer(text):
        match = found.group()
        if versions and text[max(0, found.start() - 1):found.start()] == '/':
            continue
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


def _integer(number):
    """The address a 32-bit integer spells, or None when either byte order
    gives an allowed one (zero, a small counter, a scrub replacement)."""
    if isinstance(number, bool) or not 0 <= number < 2**32:
        return None
    readings = [ipaddress.ip_address(number), ipaddress.ip_address(number.to_bytes(4, 'little'))]
    if any(any(address in network for network in ALLOWED) for address in readings):
        return None
    return f'{readings[1]} (or {readings[0]}) as the integer {number}'


def _unpacked(text):
    """Base64 payloads in [text], decoded as bytes, and unpacked when they are
    gzip or zlib streams."""
    for token in BASE64.findall(text):
        if len(token) < 16:
            continue
        padded = token + '=' * (-len(token) % 4)
        for decode in (base64.b64decode, base64.urlsafe_b64decode):
            try:
                data = decode(padded)
                break
            except (binascii.Error, ValueError):
                continue
        else:
            continue
        yield data.decode('latin-1')
        if data[:2] == b'\x1f\x8b' or (len(data) > 1 and data[0] & 0x0F == 8 and int.from_bytes(data[:2], 'big') % 31 == 0):
            try:
                yield zlib.decompress(data, 47).decode('utf-8', 'replace')
            except zlib.error:
                pass


def embedded(text):
    """Client-address fields written inside [text] (frame text, JSON carried
    as a string, Base64 payloads) whose value is a public address."""
    found = []
    for body in (text, *_unpacked(text)):
        for match in KEYED.finditer(body):
            value = match.group(2)
            if '.' in value:
                found.extend(_public(value))
            else:
                address = _integer(int(value))
                if address:
                    found.append(address)
    return found


def leaks(value, versions=False):
    """Public IPv4 addresses in one value, plain or Base64; with [versions],
    `name/1.2.3.4` version numbers are skipped."""
    found = list(_public(value, versions))
    for decoded in _decoded(value):
        found.extend(_public(decoded))
    return found


def _walk(node, path):
    """Yields (where, address) for every client address in [node]."""
    if isinstance(node, dict):
        for key, value in node.items():
            if CLIENT_HEADER.search(key):
                if isinstance(value, str):
                    for address in leaks(value):
                        yield f'{path}.{key}', address
                    if value.isdigit() and len(value) <= 10:
                        address = _integer(int(value))
                        if address:
                            yield f'{path}.{key}', address
                elif isinstance(value, int):
                    address = _integer(value)
                    if address:
                        yield f'{path}.{key}', address
            yield from _walk(value, f'{path}.{key}')
    elif isinstance(node, list):
        for index, value in enumerate(node):
            yield from _walk(value, f'{path}[{index}]')
    elif isinstance(node, str):
        for address in embedded(node):
            yield f'{path} (inside the text)', address


def _documents(file):
    """The JSON documents of a fixture: the file, or each line of a `.jsonl`."""
    text = Path(file).read_text(encoding='utf-8')
    if str(file).endswith('.jsonl'):
        for number, line in enumerate(text.splitlines(), 1):
            if line.strip():
                try:
                    yield f':{number}', json.loads(line)
                except ValueError:
                    continue
    else:
        try:
            yield '', json.loads(text)
        except ValueError:
            return


def check(files):
    problems = []
    for file in files:
        try:
            documents = list(_documents(file))
        except OSError:
            continue
        for line, data in documents:
            problems.extend(_check(f'{file}{line}', data))
    return problems


def _check(file, data):
    problems = []
    for where, address in _walk(data, ''):
        problems.append(f'{file}: {where.lstrip(".")} holds client address {address}')
    if isinstance(data, dict):
        for side in ('request', 'response'):
            headers = (data.get(side) or {}).get('headers') if isinstance(data.get(side), dict) else None
            if not isinstance(headers, dict):
                continue
            for name, value in headers.items():
                if not isinstance(value, str) or name.lower() in SERVER_HEADERS or CLIENT_HEADER.search(name):
                    continue
                for address in leaks(value, versions=True):
                    problems.append(f'{file}: {side}.headers.{name} holds address {address} (add to SERVER_HEADERS only if it is the platform\'s)')
    return problems


def main():
    listed = subprocess.run(
        ['git', 'ls-files', '--cached', '--others', '--exclude-standard', '--', 'fixtures/*.json', 'fixtures/*.jsonl'],
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
