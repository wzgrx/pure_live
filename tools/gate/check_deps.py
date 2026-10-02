"""Dependency-direction check for the workspace (docs/specs/ENGINEERING.md §4).

Reads every workspace member's pubspec.yaml and Dart imports and fails when a
member depends on a live_* package it is not allowed to, or when a pure-Dart
package depends on or imports Flutter. Standard library only, so it runs in
hooks without extra setup.
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]

# Allowed internal (live_*) dependencies per member, following the layering in
# docs/specs/ENGINEERING.md §4. A member missing from this table fails the check, so adding
# a package forces a decision here. Entries for packages that do not exist yet
# document the intended direction.
ALLOWED = {
    'packages/live_net': set(),
    'packages/live_core': {'live_net'},
    'packages/live_danmaku': {'live_core', 'live_net'},
    'packages/live_iptv': {'live_core', 'live_net'},
    'packages/live_media': {'live_core', 'live_net'},
    'packages/live_player': {'live_media', 'live_core', 'live_net'},
    'packages/live_record': {'live_media', 'live_core', 'live_net'},
    'packages/live_store': {'live_core'},
    'packages/live_cast': set(),
    'packages/live_ui': set(),
    'packages/live_vod': {'live_core', 'live_net'},
    'apps/pure_live': {
        'live_ui', 'live_media', 'live_player', 'live_record', 'live_danmaku', 'live_iptv', 'live_store', 'live_core',
        'live_net', 'live_cast', 'live_vod',
    },
    'tools/live_cli': {'live_core', 'live_net', 'live_danmaku', 'live_media', 'live_record'},
    'tools/check_latest': set(),
}

# Must run under plain `dart test` and be callable from live_cli.
PURE_DART = {
    'packages/live_net', 'packages/live_core', 'packages/live_danmaku', 'packages/live_iptv', 'packages/live_media',
    'packages/live_record', 'packages/live_cast', 'packages/live_store', 'packages/live_vod', 'tools/live_cli',
    'tools/check_latest',
}

IMPORT = re.compile(r"""^\s*(?:import|export)\s+['"]package:([a-z0-9_]+)/""", re.M)
SECTION = re.compile(r'^(dependencies|dev_dependencies|dependency_overrides):\s*$')
ENTRY = re.compile(r'^  ([a-z0-9_]+):')


def workspace_members(root):
    members, inside = [], False
    for line in (root / 'pubspec.yaml').read_text(encoding='utf-8').splitlines():
        if line.startswith('workspace:'):
            inside = True
            continue
        if inside:
            match = re.match(r'^\s+-\s+(\S+)', line)
            if match:
                members.append(match.group(1).rstrip('/'))
            elif line.strip() and not line.startswith(' '):
                break
    return members


def pubspec_dependencies(pubspec):
    """Returns {section: {name: raw block}} for the three dependency sections."""
    sections, current, name = {}, None, None
    for line in pubspec.read_text(encoding='utf-8').splitlines():
        header = SECTION.match(line)
        if header:
            current = sections.setdefault(header.group(1), {})
            continue
        if line and not line.startswith(' ') and not line.startswith('#'):
            current = None
            continue
        if current is None:
            continue
        entry = ENTRY.match(line)
        if entry:
            name = entry.group(1)
            current[name] = line
        elif name and line.startswith('    '):
            current[name] += '\n' + line
    return sections


def dart_files(member_dir, member):
    folders = ['lib', 'bin', 'test', 'tool', 'integration_test']
    for folder in folders:
        base = member_dir / folder
        if base.is_dir():
            yield from base.rglob('*.dart')


def check(root=ROOT):
    errors = []
    members = workspace_members(root)
    for member in members:
        member_dir = root / member
        pubspec = member_dir / 'pubspec.yaml'
        if member not in ALLOWED:
            errors.append(f'{member}: not in tool/check_deps.py ALLOWED; decide its dependency direction first')
            continue
        if not pubspec.is_file():
            errors.append(f'{member}: listed in the workspace but has no pubspec.yaml')
            continue
        allowed = ALLOWED[member]
        own_name = f'live_{Path(member).name[5:]}' if Path(member).name.startswith('live_') else None
        sections = pubspec_dependencies(pubspec)
        for section in ('dependencies', 'dev_dependencies'):
            for name, block in sections.get(section, {}).items():
                if name.startswith('live_') and name not in allowed:
                    errors.append(f'{member}/pubspec.yaml: {section} on {name} is not allowed')
                if member in PURE_DART and section == 'dependencies' and (name == 'flutter' or 'sdk: flutter' in block):
                    errors.append(f'{member}/pubspec.yaml: pure-Dart package depends on {name} (Flutter SDK)')
        for path in dart_files(member_dir, member):
            text = path.read_text(encoding='utf-8', errors='replace')
            rel = path.relative_to(root).as_posix()
            for match in IMPORT.finditer(text):
                package = match.group(1)
                line = text.count('\n', 0, match.start()) + 1
                if package.startswith('live_') and package != own_name and package not in allowed:
                    errors.append(f'{rel}:{line}: imports package:{package}, not allowed for {member}')
                if member in PURE_DART and package in {'flutter', 'flutter_test'}:
                    errors.append(f'{rel}:{line}: pure-Dart package imports package:{package}')
    return errors, members


def main():
    errors, members = check()
    for error in errors:
        print(f'check_deps: {error}', file=sys.stderr)
    print(f'check_deps: {len(members)} workspace members, {len(errors)} errors')
    return 1 if errors else 0


if __name__ == '__main__':
    sys.exit(main())
