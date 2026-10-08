"""Checks that everything in the project belongs to a sub-category (Z03.2).

docs/inventory/OWNERS.toml (hand-written) says which sub-category of
docs/tasks.toml looks after what:

- path:    code files by glob, first match wins (`**` any directories, `*` and
           `?` within one name, a trailing `/` everything under a directory);
- setting_sections, setting: every setting of `Settings.all` by its
           `section`, single settings overridden by key;
- site:    every source of `SiteIds.supported`, its playback and its
           danmaku sub-category (`danmaku = "无"`: the platform has none);
- channel: every `pure_live/...` method or event channel.

The script reports, one line each, and exits 1 on: a code file no rule
matches (`unowned: <path>`), a setting, source or channel without an owner, an
entry naming a sub-category the registry does not have, an entry that matches
nothing (a rule shadowed by earlier ones, a setting, source or channel that is
gone), a task id in the 依据 or 备注 column of docs/inventory/FEATURES.md that
the registry does not have, and a stale docs/inventory/OWNERS.md.

Code files: the Dart files of apps/pure_live/lib/ and packages/*/lib/, the
Kotlin files of apps/pure_live/android/, the Windows runner and the scripts
under tools/. Standard library only (the gate runs it).

usage:
  python3 tools/docs/owners.py            check, write docs/inventory/OWNERS.md
  python3 tools/docs/owners.py --check    write nothing; exit 1 on any problem (gate)
  python3 tools/docs/owners.py --who X    the sub-category of a path, setting key, source or channel
  python3 tools/docs/owners.py --files [SUB]
                                          the code files of every sub-category (or of SUB)
"""

from __future__ import annotations

import argparse
import os
import re
import sys
import tomllib
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TABLE = 'docs/inventory/OWNERS.toml'
OUTPUT = 'docs/inventory/OWNERS.md'
REGISTRY = 'docs/tasks.toml'
FEATURES = 'docs/inventory/FEATURES.md'
SETTINGS = 'packages/live_store/lib/src/settings/settings.dart'
SITES = 'packages/live_core/lib/src/sites.dart'
NO_DANMAKU = '无'

# (directory, file suffixes); `packages/*` is every package.
CODE = [
    ('apps/pure_live/lib', ('.dart',)),
    ('packages/*/lib', ('.dart',)),
    ('apps/pure_live/android', ('.kt',)),
    ('apps/pure_live/windows/runner', ('.cpp', '.h')),
    ('tools', ('.py', '.sh', '.dart', '.ps1', '.js', '.c')),
]
SKIP = {'build', 'node_modules', '__pycache__'}
# Where channel names are looked for.
CHANNEL_CODE = [('apps/pure_live/lib', '.dart'), ('packages/*/lib', '.dart'), ('apps/pure_live/android', '.kt')]
CHANNEL = re.compile(r"""['"](pure_live/[A-Za-z0-9_/]+)['"]""")
TASK_ID = re.compile(r'(?<![\w.])[A-Z]\d\d\.\d+(?!\w)')


def dirs(root: Path, pattern: str) -> list[Path]:
    head, _, tail = pattern.partition('/*/')
    if not tail:
        return [root / pattern]
    base = root / head
    return [p / tail for p in sorted(base.iterdir()) if p.is_dir()] if base.is_dir() else []


def walk(root: Path, pattern: str, suffixes: tuple[str, ...]) -> list[str]:
    found = []
    for top in dirs(root, pattern):
        for current, names, files in os.walk(top):
            names[:] = sorted(n for n in names if not n.startswith('.') and n not in SKIP)
            for name in sorted(files):
                if name.endswith(suffixes):
                    found.append((Path(current) / name).relative_to(root).as_posix())
    return found


def code_files(root: Path) -> list[str]:
    return sorted({f for pattern, suffixes in CODE for f in walk(root, pattern, suffixes)})


def glob_rx(pattern: str) -> re.Pattern:
    """`**` any directories, `*` and `?` within one name, a trailing `/` everything below."""
    if pattern.endswith('/'):
        pattern += '**'
    out, i = '', 0
    while i < len(pattern):
        if pattern.startswith('**/', i):
            out, i = out + '(?:.*/)?', i + 3
        elif pattern.startswith('**', i):
            out, i = out + '.*', i + 2
        elif pattern[i] == '*':
            out, i = out + '[^/]*', i + 1
        elif pattern[i] == '?':
            out, i = out + '[^/]', i + 1
        else:
            out, i = out + re.escape(pattern[i]), i + 1
    return re.compile(out + r'\Z')


def owner_of(path: str, rules: list[tuple[re.Pattern, dict]]) -> int | None:
    """The index of the first rule matching [path]."""
    for index, (rx, _) in enumerate(rules):
        if rx.match(path):
            return index
    return None


def strip_comments(text: str) -> str:
    return re.sub(r'//[^\n]*', '', text)


def call_args(text: str, start: int) -> str:
    """The text between the parenthesis before [start] and its partner."""
    depth, i = 1, start
    while i < len(text) and depth:
        depth += {'(': 1, ')': -1}.get(text[i], 0)
        i += 1
    return text[start:i - 1]


def parse_settings(text: str) -> tuple[list[tuple[str, str | None]], list[str]]:
    """[(key, section)] of `Settings.all` in its order, and problems."""
    text = strip_comments(text)
    defined = {}
    for m in re.finditer(r'static\s+const\s+(\w+)\s*=\s*\w*Setting\s*(?:<[^>]*>)?\s*\(', text):
        args = call_args(text, m.end())
        key = re.search(r"""^\s*['"]([^'"]+)['"]""", args)
        section = re.search(r"""\bsection:\s*['"]([^'"]+)['"]""", args)
        defined[m.group(1)] = (key.group(1) if key else m.group(1), section.group(1) if section else None)
    lists = {m.group(1): m.group(2) for m in re.finditer(
        r'static\s+const\s+List<Setting<Object>>\s+(\w+)\s*=\s*\[(.*?)\];', text, re.S)}
    problems, out = [], []

    def expand(name: str, seen: tuple[str, ...]) -> None:
        if name in seen:
            problems.append(f'settings: {name} includes itself')
            return
        for item in (i.strip() for i in lists[name].split(',')):
            if not item:
                continue
            if item.startswith('...'):
                if item[3:] in lists:
                    expand(item[3:], seen + (name,))
                else:
                    problems.append(f'settings: Settings.{name} spreads unknown list {item[3:]}')
            elif item in defined:
                out.append(defined[item])
            else:
                problems.append(f'settings: Settings.{name} lists unknown setting {item}')

    if 'all' not in lists:
        return [], ['settings: no `static const List<Setting<Object>> all` in ' + SETTINGS]
    expand('all', ())
    return out, problems


def parse_sites(text: str) -> list[str]:
    """The ids of `SiteIds.supported`, in order."""
    text = strip_comments(text)
    names = dict(re.findall(r"""static\s+const\s+String\s+(\w+)\s*=\s*['"]([^'"]+)['"]""", text))
    m = re.search(r'static\s+const\s+List<String>\s+supported\s*=\s*\[(.*?)\]', text, re.S)
    if not m:
        return []
    return [names.get(n.strip(), n.strip()) for n in m.group(1).split(',') if n.strip()]


def find_channels(root: Path) -> dict[str, list[str]]:
    """{channel name: [file:line where it is named]}."""
    found = defaultdict(list)
    for pattern, suffix in CHANNEL_CODE:
        for rel in walk(root, pattern, (suffix,)):
            for n, line in enumerate((root / rel).read_text(encoding='utf-8', errors='ignore').splitlines(), 1):
                for name in CHANNEL.findall(line):
                    found[name].append(f'{rel}:{n}')
    return dict(found)


def feature_ids(text: str) -> tuple[list[tuple[int, str, str]], list[str]]:
    """[(line, feature id, task id)] of the 依据 and 备注 columns, and problems."""
    header, out, problems, seen = [], [], [], {}
    for n, line in enumerate(text.splitlines(), 1):
        if not line.startswith('|'):
            continue
        cells = [c.strip() for c in line.strip().strip('|').split('|')]
        if cells[0] == '编号':
            header = cells
        elif re.fullmatch(r'F-[A-Z]+-\d+', cells[0]):
            fid = cells[0]
            if fid in seen:
                problems.append(f'{FEATURES}:{n}: {fid} also on line {seen[fid]}')
            seen.setdefault(fid, n)
            for column in ('依据', '备注'):
                if column in header and header.index(column) < len(cells):
                    out += [(n, fid, t) for t in TASK_ID.findall(cells[header.index(column)])]
    return out, problems


class Owners:
    def __init__(self, root: Path) -> None:
        self.root = root
        self.problems: list[str] = []
        with (root / REGISTRY).open('rb') as f:
            registry = tomllib.load(f)
        self.subs = {s['id']: s['title'] for s in registry.get('sub', [])}
        self.tasks = {t['id'] for t in registry.get('task', [])}
        with (root / TABLE).open('rb') as f:
            self.table = tomllib.load(f)
        self.rules = [(glob_rx(r['glob']), r) for r in self.table.get('path', [])]
        self.files = code_files(root)
        text = (root / SETTINGS).read_text(encoding='utf-8') if (root / SETTINGS).exists() else ''
        self.settings, problems = parse_settings(text)
        self.problems += problems
        self.sites = parse_sites((root / SITES).read_text(encoding='utf-8')) if (root / SITES).exists() else []
        self.channels = find_channels(root)
        self.check()

    def sub(self, sid: str, where: str) -> None:
        if sid not in self.subs:
            self.problems.append(f'{TABLE}: {where} names {sid}, which is not a sub-category of {REGISTRY}')

    def duplicates(self, entries: list[dict], key: str, kind: str) -> dict[str, dict]:
        out = {}
        for entry in entries:
            if entry[key] in out:
                self.problems.append(f'{TABLE}: {kind} {entry[key]} is listed twice')
            out.setdefault(entry[key], entry)
        return out

    def check(self) -> None:
        p = self.problems
        # Code files.
        used = [0] * len(self.rules)
        self.file_owner: dict[str, str] = {}
        for rx, rule in self.rules:
            self.sub(rule['sub'], f"path {rule['glob']!r}")
        for rel in self.files:
            index = owner_of(rel, self.rules)
            if index is None:
                p.append(f'unowned: {rel}')
            else:
                used[index] += 1
                self.file_owner[rel] = self.rules[index][1]['sub']
        p += [f"{TABLE}: path {rule['glob']!r} matches no file (gone, or every file taken by an earlier rule)"
              for (rx, rule), n in zip(self.rules, used) if not n]
        # Settings.
        sections = self.table.get('setting_sections', {})
        overrides = self.duplicates(self.table.get('setting', []), 'key', 'setting')
        for name, sid in sections.items():
            self.sub(sid, f'setting section {name!r}')
        for entry in overrides.values():
            self.sub(entry['sub'], f"setting {entry['key']!r}")
        keys = {k for k, _ in self.settings}
        p += [f'{TABLE}: setting {k!r} is not in Settings.all' for k in overrides if k not in keys]
        p += [f'{TABLE}: setting section {s!r} has no setting' for s in sections
              if not any(sec == s and k not in overrides for k, sec in self.settings)]
        self.setting_owner: dict[str, str] = {}
        for key, section in self.settings:
            if key in overrides:
                self.setting_owner[key] = overrides[key]['sub']
            elif section in sections:
                self.setting_owner[key] = sections[section]
            elif section is None:
                p.append(f'unowned setting: {key} (no section)')
            else:
                p.append(f'unowned setting: {key} (section {section!r} has no default in [setting_sections])')
        # Sources.
        sites = self.duplicates(self.table.get('site', []), 'id', 'site')
        for sid, entry in sites.items():
            if sid not in self.sites:
                p.append(f'{TABLE}: site {sid!r} is not in SiteIds.supported')
            if 'play' not in entry:
                p.append(f'{TABLE}: site {sid!r} has no play sub-category')
            else:
                self.sub(entry['play'], f'site {sid!r}')
            if 'danmaku' not in entry:
                p.append(f'{TABLE}: site {sid!r} has no danmaku sub-category (write danmaku = "{NO_DANMAKU}" if it has none)')
            elif entry['danmaku'] != NO_DANMAKU:
                self.sub(entry['danmaku'], f'site {sid!r}')
        p += [f'unowned site: {s}' for s in self.sites if s not in sites]
        # Channels.
        channels = self.duplicates(self.table.get('channel', []), 'name', 'channel')
        for name, entry in channels.items():
            self.sub(entry['sub'], f'channel {name!r}')
            if name not in self.channels:
                p.append(f'{TABLE}: channel {name!r} is not named in the code')
        p += [f'unowned channel: {name} ({where[0]})' for name, where in sorted(self.channels.items())
              if name not in channels]
        # Features.
        path = self.root / FEATURES
        if path.exists():
            ids, problems = feature_ids(path.read_text(encoding='utf-8'))
            p += problems
            p += [f'{FEATURES}:{n}: {fid} names {tid}, which is not a task of {REGISTRY}'
                  for n, fid, tid in ids if tid not in self.tasks]

    def who(self, thing: str) -> list[str]:
        out = []
        rel = thing.removeprefix('./')
        index = owner_of(rel, self.rules)
        if index is not None:
            rule = self.rules[index][1]
            out.append(f"{rule['sub']} {self.subs.get(rule['sub'], '?')}  (path {rule['glob']!r})")
        if thing in self.setting_owner:
            out.append(f'{self.setting_owner[thing]} {self.subs.get(self.setting_owner[thing], "?")}  (setting)')
        for entry in self.table.get('site', []):
            if entry['id'] == thing:
                out.append(f"play {entry.get('play')}, danmaku {entry.get('danmaku')}  (site)")
        for entry in self.table.get('channel', []):
            if entry['name'] in (thing, f'pure_live/{thing}'):
                out.append(f"{entry['sub']} {self.subs.get(entry['sub'], '?')}  (channel)")
        return out

    def markdown(self) -> str:
        per = defaultdict(lambda: defaultdict(list))
        for _, rule in self.rules:
            per[rule['sub']]['path'].append(f"`{rule['glob']}`" + (f"（{rule['note']}）" if rule.get('note') else ''))
        for key, section in self.settings:
            if key in self.setting_owner:
                per[self.setting_owner[key]]['setting'].append(f'`{key}`')
        for entry in self.table.get('site', []):
            per[entry.get('play')]['play'].append(f"`{entry['id']}`")
            if entry.get('danmaku') not in (None, NO_DANMAKU):
                per[entry['danmaku']]['danmaku'].append(f"`{entry['id']}`")
        for entry in self.table.get('channel', []):
            per[entry['sub']]['channel'].append(f"`{entry['name']}`")
        no_danmaku = [f"`{e['id']}`" for e in self.table.get('site', []) if e.get('danmaku') == NO_DANMAKU]
        lines = [
            '# 归属清单（生成）',
            '',
            f'<!-- 由 tools/docs/owners.py 根据 {TABLE} 生成，不要手改 -->',
            '',
            f'每个子分类管哪些代码、设置、平台和原生通道。由 `tools/docs/owners.py` 根据 [OWNERS.toml](OWNERS.toml) 生成，'
            '不要手改；规则怎么写见 OWNERS.toml 开头，查一个文件归谁用 `python3 tools/docs/owners.py --who <路径>`，'
            '列出某个子分类的全部文件用 `--files <子分类>`。门禁（`owners` 一步）检查每个代码文件、设置、平台、通道都有归属。',
            '',
            '路径规则按 OWNERS.toml 里的顺序第一条匹配的生效，所以一条目录规则只管前面的规则没拿走的文件。'
            '本页只随归属表、设置、来源和通道变化，加删代码文件不用重新生成。',
            '',
            f'路径规则 {len(self.rules)} 条；'
            f'设置 {len(self.settings)} 个（分节默认 {len(self.table.get("setting_sections", {}))} 条、'
            f'单独指定 {len(self.table.get("setting", []))} 个）；来源 {len(self.sites)} 个；通道 {len(self.channels)} 个。',
            '',
            '| 子分类 | 路径规则 | 设置 | 播放 | 弹幕 | 通道 |',
            '|---|---:|---:|---:|---:|---:|',
        ]
        order = [s for s in self.subs if s in per]
        for sid in order:
            k = per[sid]
            lines.append(f'| {sid} {self.subs[sid]} | {len(k["path"]) or ""} | {len(k["setting"]) or ""} | '
                         f'{len(k["play"]) or ""} | {len(k["danmaku"]) or ""} | {len(k["channel"]) or ""} |')
        lines.append('')
        names = {'path': '代码', 'setting': '设置', 'play': '播放', 'danmaku': '弹幕', 'channel': '通道'}
        for sid in order:
            lines += [f'## {sid} {self.subs[sid]}', '']
            for kind, title in names.items():
                if per[sid][kind]:
                    lines.append(f'- {title}：' + '、'.join(per[sid][kind]))
            lines.append('')
        if no_danmaku:
            lines += ['## 没有弹幕的来源', '', '、'.join(no_danmaku), '']
        return '\n'.join(lines)


def main(argv: list[str] | None = None, root: Path = ROOT) -> int:
    ap = argparse.ArgumentParser(description='Sub-category owners of code files, settings, sources and channels.')
    ap.add_argument('--check', action='store_true', help='write nothing; exit 1 on any problem')
    ap.add_argument('--who', metavar='THING', help='the owner of a path, setting key, source id or channel')
    ap.add_argument('--files', nargs='?', const='', metavar='SUB', help='list the code files per sub-category')
    args = ap.parse_args(argv)
    owners = Owners(root)
    if args.who:
        found = owners.who(args.who)
        print('\n'.join(found) if found else f'{args.who}: no owner')
        return 0 if found else 1
    if args.files is not None:
        by = defaultdict(list)
        for rel, sid in owners.file_owner.items():
            by[sid].append(rel)
        for sid in owners.subs:
            if by[sid] and args.files in ('', sid):
                print(f'{sid} {owners.subs[sid]}')
                print(''.join(f'  {rel}\n' for rel in by[sid]), end='')
        return 0
    problems = list(owners.problems)
    out = root / OUTPUT
    text = owners.markdown()
    if args.check:
        if not out.exists() or out.read_text(encoding='utf-8') != text:
            problems.append(f'{OUTPUT} is stale: run python3 tools/docs/owners.py')
    else:
        out.write_text(text, encoding='utf-8')
    for problem in problems:
        print(problem, file=sys.stderr)
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
