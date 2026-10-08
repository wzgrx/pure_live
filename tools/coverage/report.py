#!/usr/bin/env python3
"""Coverage inventory of the workspace members (S01.2).

  python3 tools/coverage/report.py OUT            Markdown tables on stdout
  python3 tools/coverage/report.py OUT --json     the same numbers as JSON

OUT is the directory `tools/coverage/run.sh` wrote: `<name>.lcov` and
`<name>.log` for every member (name = last path segment, e.g. `pure_live`,
`live_core`). The report lists, per member: test files, the test count the
runner printed (`+N: All tests passed!`), line coverage (LH/LF) of the files the
tests loaded, and the library files the tests never loaded (they are missing
from lcov, so they count as 0% but their line count is unknown; files of
directives only, such as barrel files, are left out). Then the
app by directory, directories under 30%, files at 0%, and fixed waits followed
directly by an assertion in the tests.

Standard library only; reads the repository, writes nothing.
"""

import json
import re
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
APP = 'apps/pure_live'
LOW = 30.0
LOWEST = 10
MIN_LINES = 50

# A real-time wait: Future.delayed with a fixed duration, or a local helper
# around one (`settle()` in the live_play tests).
DELAY = re.compile(r'Future(?:<[^>]*>)?\.delayed\(\s*(?:const\s+)?Duration\(\s*'
                   r'(milliseconds|seconds|microseconds)\s*:\s*(\d+)')
ANY_DELAY = re.compile(r'Future(?:<[^>]*>)?\.delayed\(')
HELPER = re.compile(r'^\s*Future<void>\s+(\w+)\s*\(')
# A helper that polls a condition (until, _eventually), not a fixed wait.
POLL_NAME = re.compile(r'^_?(?:until|eventually|settleSettings|waitFor|waitUntil)', re.IGNORECASE)
POLL = re.compile(r'\bwhile\s*\(|\bif\s*\(.*\b(?:return|break|fail)\b|isAfter|elapsed|deadline')
# Waiting on a condition instead of a fixed time.
UNTIL = re.compile(r'\b(?:_?until|_?eventually|settleSettings)\(')
EXPECT = re.compile(r'\bexpect(?:Later)?\(')
RUN_COUNT = re.compile(r'\+(\d+)(?: ~(\d+))?(?: -(\d+))?: (All tests passed!|Some tests failed\.|.*)$')


def members(root=ROOT):
    """Workspace members from the root pubspec.yaml, in order."""
    found, inside = [], False
    for line in (root / 'pubspec.yaml').read_text(encoding='utf-8').splitlines():
        if line.startswith('workspace:'):
            inside = True
            continue
        if inside:
            if line and not line[0].isspace() and not line.startswith('#'):
                break
            match = re.match(r'\s+-\s+(\S+?)/?\s*$', line)
            if match:
                found.append(match.group(1))
    return found


def parse_lcov(text):
    """{source file: (lines found, lines hit)} from lcov text."""
    files, current, found, hit = {}, None, 0, 0
    lines = {}
    for line in text.splitlines():
        if line.startswith('SF:'):
            current, found, hit, lines = line[3:].strip(), 0, 0, {}
        elif line.startswith('DA:') and current is not None:
            number, count = line[3:].split(',')[:2]
            lines[number] = lines.get(number, 0) + int(count)
        elif line.startswith('LF:'):
            found = int(line[3:])
        elif line.startswith('LH:'):
            hit = int(line[3:])
        elif line.strip() == 'end_of_record' and current is not None:
            if not found and lines:  # some writers leave out LF/LH
                found = len(lines)
                hit = sum(1 for count in lines.values() if count > 0)
            old = files.get(current, (0, 0))
            files[current] = (max(old[0], found), max(old[1], hit))
            current = None
    return files


def normalise(member, source):
    """lcov paths are relative to the member (`lib/...`) or absolute."""
    source = source.replace('\\', '/')
    marker = f'/{member}/'
    if marker in source:
        source = source.split(marker, 1)[1]
    return source


def run_count(log_text):
    """(passed, skipped, failed, finished) from the last `+N` line of a test run."""
    for line in reversed(log_text.splitlines()):
        match = RUN_COUNT.search(line.strip())
        if match:
            passed, skipped, failed, tail = match.groups()
            return int(passed), int(skipped or 0), int(failed or 0), tail == 'All tests passed!'
    return None


def group_of(member, path):
    """Directory a file is counted under."""
    parts = path.split('/')
    if member == APP:
        if len(parts) >= 3 and parts[1] == 'features':
            return '/'.join(parts[:3])
        return '/'.join(parts[:2]) if len(parts) > 2 else path
    return '/'.join(parts[:min(len(parts) - 1, 3)]) or path


def pct(hit, found):
    return 100.0 * hit / found if found else 0.0


DIRECTIVE = re.compile(r'^\s*(?:export|import|library|part)\b')


def has_code(path):
    """False for files of directives and comments only (barrel files): never in lcov."""
    inside = False
    for line in Path(path).read_text(encoding='utf-8').splitlines():
        text = line.strip()
        if inside:
            inside = '*/' not in text
            continue
        if not text or text.startswith('//'):
            continue
        if text.startswith('/*'):
            inside = '*/' not in text
            continue
        if DIRECTIVE.match(text) or text.startswith(("'", '"', 'show ', 'hide ', ';')):
            continue
        return True
    return False


def library_files(member_dir):
    """Library files with code, relative to the member."""
    return sorted(p.relative_to(member_dir).as_posix() for p in (member_dir / 'lib').rglob('*.dart')
                  if has_code(p))


def test_files(member_dir):
    test = member_dir / 'test'
    return sorted(test.rglob('*_test.dart')) if test.is_dir() else []


def collect(out, root=ROOT):
    out = Path(out)
    result = []
    for member in members(root):
        name = member.rsplit('/', 1)[-1]
        member_dir = root / member
        lcov_path, log_path = out / f'{name}.lcov', out / f'{name}.log'
        covered = {}
        if lcov_path.is_file():
            for source, numbers in parse_lcov(lcov_path.read_text(encoding='utf-8')).items():
                covered[normalise(member, source)] = numbers
        libs = library_files(member_dir)
        files = []
        for path in libs:
            found, hit = covered.get(path, (None, None))
            files.append({'path': path, 'found': found, 'hit': hit, 'group': group_of(member, path)})
        count = run_count(log_path.read_text(encoding='utf-8', errors='replace')) if log_path.is_file() else None
        result.append({
            'member': member,
            'test_files': len(test_files(member_dir)),
            'ran': lcov_path.is_file(),
            'tests': count,
            'files': files,
        })
    return result


def totals(files):
    loaded = [f for f in files if f['found'] is not None]
    found = sum(f['found'] for f in loaded)
    hit = sum(f['hit'] for f in loaded)
    return {'files': len(files), 'loaded': len(loaded), 'found': found, 'hit': hit, 'pct': pct(hit, found)}


def groups(entry):
    by = defaultdict(list)
    for f in entry['files']:
        by[f['group']].append(f)
    return {name: totals(files) for name, files in sorted(by.items())}


def zero_files(entry):
    return [f for f in entry['files'] if f['found'] is None or (f['found'] and not f['hit'])]


def wait_helpers(lines):
    """Local helpers that call Future.delayed: {name: (first line, last line, fixed)}.

    `fixed` is false when the helper polls a condition (until, _eventually);
    a fixed number of rounds is still a fixed wait. A helper like `settle() => pumpEventQueue()` only drains
    microtasks and is not listed.
    """
    helpers = {}
    for index, line in enumerate(lines):
        match = HELPER.match(line)
        if not match:
            continue
        indent = len(line) - len(line.lstrip())
        end = index
        if '=>' not in line or line.rstrip().endswith('{'):
            for later in range(index + 1, min(len(lines), index + 30)):
                text = lines[later]
                if text.strip().startswith('}') and len(text) - len(text.lstrip()) == indent:
                    end = later
                    break
        body = lines[index:end + 1]
        if any(ANY_DELAY.search(text) for text in body):
            name = match.group(1)
            polls = POLL_NAME.match(name) or any(POLL.search(text) for text in body)
            helpers[name] = (index, end, not polls)
    return helpers


def scan_waits(test_dir, root=ROOT, window=3):
    """Fixed waits in test files, and whether an assertion follows directly.

    A fixed wait is a Future.delayed with a fixed duration, or a call of a
    local helper that wraps one (see [wait_helpers]). Returns
    [{'file', 'line', 'wait', 'direct'}]: `direct` when one of the next
    `window` non-blank lines is an expect(...) with no condition wait before
    it. Also returns the files that already use a condition wait.
    """
    test_dir = Path(test_dir)
    hits, conditional = [], set()
    for path in sorted(test_dir.rglob('*.dart')):
        rel = path.relative_to(root).as_posix() if path.is_relative_to(root) else path.as_posix()
        lines = path.read_text(encoding='utf-8').splitlines()
        if any(UNTIL.search(line) for line in lines):
            conditional.add(rel)
        helpers = wait_helpers(lines)
        inside = {i for first, last, _ in helpers.values() for i in range(first, last + 1)}
        fixed = [name for name, (_, _, is_fixed) in helpers.items() if is_fixed]
        call = re.compile(r'\bawait\s+(' + '|'.join(map(re.escape, fixed)) + r')\(') if fixed else None
        for index, line in enumerate(lines):
            if index in inside or line.lstrip().startswith('//'):
                continue
            match = DELAY.search(line)
            called = call.search(line) if call else None
            before = [text for text in lines[max(0, index - 3):index] if text.strip()][-2:]
            if match and any(POLL.search(text) for text in before):
                continue  # inside a loop that polls a condition
            if match:
                wait = f'{match.group(2)} {match.group(1)}'
            elif called:
                wait = f'{called.group(1)}()'
            else:
                continue
            direct, seen = False, 0
            for following in lines[index + 1:]:
                if not following.strip():
                    continue
                seen += 1
                if UNTIL.search(following):
                    break
                if EXPECT.search(following):
                    direct = True
                    break
                if seen >= window:
                    break
            hits.append({'file': rel, 'line': index + 1, 'wait': wait, 'direct': direct})
    return hits, sorted(conditional)


def markdown(data, waits=None, conditional=()):
    out = []
    add = out.append
    add('## 各成员\n')
    add('| 成员 | 测试文件 | 用例（运行器 `+N`） | 行覆盖率 | 行（命中/总数） | 库文件 | 测试没加载的文件 |')
    add('|---|---:|---:|---:|---:|---:|---:|')
    for entry in data:
        t = totals(entry['files'])
        tests = entry['tests']
        if not entry['ran']:
            count, rate, lines = '没跑', '—', '—'
        else:
            count = '—' if tests is None else (f'{tests[0]}' + (f'（跳过 {tests[1]}）' if tests[1] else '')
                                               + ('' if tests[3] else f'（失败 {tests[2]}）'))
            rate, lines = f"{t['pct']:.1f}%", f"{t['hit']}/{t['found']}"
        add(f"| `{entry['member']}` | {entry['test_files']} | {count} | {rate} | {lines} | {t['files']} | "
            f"{t['files'] - t['loaded']} |")
    app = next((e for e in data if e['member'] == APP and e['ran']), None)
    if app:
        add('\n## 应用按目录\n')
        add('| 目录 | 文件 | 测试加载的 | 行覆盖率 | 行（命中/总数） | 0% 的文件 |')
        add('|---|---:|---:|---:|---:|---:|')
        zero_by = defaultdict(int)
        for f in zero_files(app):
            zero_by[f['group']] += 1
        for name, t in groups(app).items():
            add(f"| `{name}` | {t['files']} | {t['loaded']} | {t['pct']:.1f}% | {t['hit']}/{t['found']} | "
                f"{zero_by[name]} |")
    add(f'\n## 低于 {LOW:.0f}% 的目录（按行覆盖率从低到高，没加载的文件不计行数）\n')
    add('| 成员 | 目录 | 行覆盖率 | 行（命中/总数） | 文件（加载/全部） |')
    add('|---|---|---:|---:|---:|')
    low = []
    for entry in data:
        if not entry['ran']:
            continue
        for name, t in groups(entry).items():
            if t['pct'] < LOW:
                low.append((t['pct'], entry['member'], name, t))
    for rate, member, name, t in sorted(low, key=lambda x: (x[0], x[1], x[2])):
        add(f"| `{member}` | `{name}` | {rate:.1f}% | {t['hit']}/{t['found']} | {t['loaded']}/{t['files']} |")
    add(f'\n## 覆盖率最低的 {LOWEST} 个目录（至少 {MIN_LINES} 行）\n')
    add('| 成员 | 目录 | 行覆盖率 | 行（命中/总数） | 文件（加载/全部） |')
    add('|---|---|---:|---:|---:|')
    ranked = sorted(((t['pct'], entry['member'], name, t) for entry in data if entry['ran']
                     for name, t in groups(entry).items() if t['found'] >= MIN_LINES),
                    key=lambda x: (x[0], x[1], x[2]))
    for rate, member, name, t in ranked[:LOWEST]:
        add(f"| `{member}` | `{name}` | {rate:.1f}% | {t['hit']}/{t['found']} | {t['loaded']}/{t['files']} |")
    add('\n## 0% 的文件（测试没加载，或加载了一行都没跑到）\n')
    add('| 成员 | 文件 | 情况 |')
    add('|---|---|---|')
    for entry in data:
        if not entry['ran']:
            continue
        for f in zero_files(entry):
            state = '没加载' if f['found'] is None else f"0/{f['found']} 行"
            add(f"| `{entry['member']}` | `{f['path']}` | {state} |")
    if waits is not None:
        direct = [w for w in waits if w['direct']]
        add(f'\n## 固定等待（{len(waits)} 处，其中后面直接断言的 {len(direct)} 处）\n')
        add('| 文件 | 处数 | 直接断言 | 直接断言的行 | 已有按条件等 |')
        add('|---|---:|---:|---|---|')
        by = defaultdict(list)
        for w in waits:
            by[w['file']].append(w)
        for name, items in sorted(by.items(), key=lambda kv: (-sum(w['direct'] for w in kv[1]), -len(kv[1]), kv[0])):
            rows = [w for w in items if w['direct']]
            where = '、'.join(f"{w['line']}（{w['wait']}）" for w in rows)
            add(f"| `{name}` | {len(items)} | {len(rows)} | {where or '—'} | {'是' if name in conditional else '—'} |")
    return '\n'.join(out) + '\n'


def main(argv):
    if not argv or argv[0] in ('-h', '--help'):
        print(__doc__.strip())
        return 0 if argv else 2
    out = Path(argv[0])
    if not out.is_dir():
        print(f'report: no such directory: {out}', file=sys.stderr)
        return 2
    data = collect(out)
    waits, conditional = [], set()
    for member in members():
        test = ROOT / member / 'test'
        if test.is_dir():
            found, uses = scan_waits(test)
            waits += found
            conditional |= set(uses)
    if '--json' in argv[1:]:
        print(json.dumps({'members': data, 'waits': waits, 'conditional': sorted(conditional)},
                         ensure_ascii=False, indent=1))
    else:
        sys.stdout.write(markdown(data, waits, conditional))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
