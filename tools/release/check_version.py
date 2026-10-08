#!/usr/bin/env python3
"""Refuses a release whose version name is the one already published (Y02.1).

The installed apps compare version names only (3.x always, 4.x before
Y02.1), so a new package under the old name reaches nobody: 4.0.0 build 5001
replaced build 5000 that way (D-008). Run before tagging (docs/PROCESS.md
section 11): it compares apps/pure_live/pubspec.yaml with the
assets/version.json on origin/master (what the installed apps read).

usage: python3 tools/release/check_version.py [--allow-same-version] [--published FILE]
  --allow-same-version  a deliberate exception like D-008 (say why in the release notes)
  --published FILE      read this version.json instead of origin/master's
"""
import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def pubspec_version(text: str) -> tuple[str, int]:
    m = re.search(r'^version:\s*([0-9][0-9.]*)\+(\d+)\s*$', text, re.M)
    if not m:
        raise ValueError('apps/pure_live/pubspec.yaml has no version like 4.0.0+5001')
    return m.group(1), int(m.group(2))


def published_version(data: dict, platform: str = 'android') -> tuple[str, int]:
    own = data.get('platforms', {}).get(platform, {})
    merged = {**data, **own}
    return str(merged['version']).lstrip('vV'), int(merged['build_number'])


def check(local: tuple[str, int], published: tuple[str, int], allow_same: bool) -> list[str]:
    (version, build), (old_version, old_build) = local, published
    problems = []
    if build <= old_build:
        problems.append(f'构建号 {build} 没有比已发布的 {old_build} 大')
    if version == old_version and not allow_same:
        problems.append(f'版本号 {version} 和已发布的一样：已安装的应用只比版本号，收不到这个包'
                        '（D-008 以后换包一律改版本号；确实要例外时加 --allow-same-version）')
    return problems


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--allow-same-version', action='store_true')
    ap.add_argument('--published')
    args = ap.parse_args()
    local = pubspec_version((ROOT / 'apps' / 'pure_live' / 'pubspec.yaml').read_text(encoding='utf-8'))
    if args.published:
        text = Path(args.published).read_text(encoding='utf-8')
    else:
        text = subprocess.run(['git', '-C', str(ROOT), 'show', 'origin/master:assets/version.json'],
                              capture_output=True, text=True, check=True).stdout
    problems = check(local, published_version(json.loads(text)), args.allow_same_version)
    for p in problems:
        print(f'release: {p}', file=sys.stderr)
    if not problems:
        print(f'release: {local[0]}+{local[1]} 可以发布')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
