"""Compares every v4 setting with 3.x (J01.2); read-only, not part of the gate.

Reads the registry (packages/live_store/lib/src/settings/settings.dart), the
3.x sources at the tag v3.2.11 (`git archive`), the settings catalogue
(apps/pure_live/lib/features/settings/settings_catalog.dart) and the code
that reads each setting, and writes the per-setting table of the task J01.2
(`settings.md` in its folder). What a script cannot know (3.x defaults
computed at run time, 3.x ranges spread over pages, the verdicts) is in
settings_audit_notes.py next to this file, written by hand.

usage:
  python3 tools/docs/settings_audit.py           write the table
  python3 tools/docs/settings_audit.py --stdout  print it instead
  python3 tools/docs/settings_audit.py --dart    print the 3.x defaults as a
                                                 Dart map (for the test)
"""

from __future__ import annotations

import io
import re
import subprocess
import sys
import tarfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from settings_audit_notes import NOTES, V3_ONLY_NOTE  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
REGISTRY = ROOT / 'packages/live_store/lib/src/settings/settings.dart'
SITES = ROOT / 'packages/live_core/lib/src/sites.dart'
CATALOG = ROOT / 'apps/pure_live/lib/features/settings/settings_catalog.dart'
TASK = next((ROOT / 'docs').glob('*/*/J01.2-*'))
OUT = TASK / 'settings.md'
TAG = 'v3.2.11'

# ---- a little Dart reading -------------------------------------------------


def _skip_string(text: str, i: int) -> int:
    """The index after the string literal starting at [i]."""
    quote = text[i]
    if text.startswith(quote * 3, i):
        end = text.index(quote * 3, i + 3)
        return end + 3
    j = i + 1
    while text[j] != quote:
        j += 2 if text[j] == '\\' else 1
    return j + 1


def _line_end(text: str, i: int) -> int:
    end = text.find('\n', i)
    return len(text) if end < 0 else end


def closing(text: str, i: int) -> int:
    """The index of the bracket closing the one at [i]."""
    pairs = {'(': ')', '[': ']', '{': '}'}
    stack = [pairs[text[i]]]
    j = i + 1
    while stack:
        c = text[j]
        if c in '\'"':
            j = _skip_string(text, j)
            continue
        if text.startswith('//', j):
            j = _line_end(text, j)
            continue
        if c in pairs:
            stack.append(pairs[c])
        elif c == stack[-1]:
            stack.pop()
        j += 1
    return j - 1


def split_args(text: str) -> list[str]:
    """[text] (an argument list without its brackets) split at top-level commas."""
    args, depth, start, j = [], 0, 0, 0
    while j < len(text):
        c = text[j]
        if c in '\'"':
            j = _skip_string(text, j)
            continue
        if text.startswith('//', j):
            j = _line_end(text, j)
            continue
        if c in '([{':
            depth += 1
        elif c in ')]}':
            depth -= 1
        elif c == ',' and depth == 0:
            args.append(text[start:j].strip())
            start = j + 1
        j += 1
    tail = text[start:].strip()
    if tail:
        args.append(tail)
    return args


def named(args: list[str]) -> tuple[list[str], dict[str, str]]:
    """Positional and named arguments (comment lines before one dropped)."""
    positional, names = [], {}
    for arg in args:
        arg = re.sub(r'^(\s*//[^\n]*\n)+', '', arg).strip()
        m = re.match(r'^(\w+)\s*:\s*(.*)$', arg, re.S)
        if m and not arg.startswith(("'", '"')):
            names[m.group(1)] = m.group(2).strip()
        else:
            positional.append(arg)
    return positional, names


def line_of(text: str, index: int) -> int:
    return text.count('\n', 0, index) + 1


class Unknown:
    """A Dart expression that is not a plain literal."""

    def __init__(self, source: str):
        self.source = source

    def __repr__(self) -> str:
        return f'Unknown({self.source!r})'


def literal(expr: str, consts: dict[str, object] | None = None) -> object:
    """[expr] as a Python value, or an [Unknown]."""
    consts = consts or {}
    e = re.sub(r'\s+', ' ', expr.strip())
    e = re.sub(r'^const ', '', e)
    if e in ('true', 'false'):
        return e == 'true'
    if re.fullmatch(r'-?0x[0-9A-Fa-f]+', e):
        return int(e, 16)
    if re.fullmatch(r'-?\d+', e):
        return int(e)
    if re.fullmatch(r'-?\d+\.\d*(e-?\d+)?', e):
        return float(e)
    if re.fullmatch(r"'[^'\\]*'", e) or re.fullmatch(r'"[^"\\]*"', e):
        return e[1:-1]
    m = re.fullmatch(r'(<\w+>)?\[(.*)\]', e, re.S)
    if m:
        items = [literal(item, consts) for item in split_args(m.group(2))]
        return Unknown(expr) if any(isinstance(i, Unknown) for i in items) else items
    m = re.fullmatch(r'(<[\w, ]+>)?\{\s*\}', e)
    if m:
        return {}
    if e in consts:
        return consts[e]
    return Unknown(expr)


def same(a: object, b: object) -> bool:
    if isinstance(a, (int, float)) and isinstance(b, (int, float)) and not isinstance(a, bool):
        return float(a) == float(b)
    return a == b


def show(value: object) -> str:
    if isinstance(value, Unknown):
        return f'`{re.sub(r"\s+", " ", value.source)}`'
    if isinstance(value, bool):
        return '`true`' if value else '`false`'
    if isinstance(value, int) and value > 0xFFFFFF:
        return f'`0x{value:08X}`'
    if isinstance(value, float):
        return f'`{value:g}`'
    if isinstance(value, str):
        return f"`'{value}'`"
    if isinstance(value, list):
        if not value:
            return '`[]`'
        inner = ', '.join(str(v) for v in value)
        return f'`[{inner}]`' if len(value) <= 8 else f'{len(value)} 个：`{inner}`'
    if isinstance(value, dict):
        return '`{}`'
    return f'`{value}`'


# ---- v4 --------------------------------------------------------------------


def v4_settings() -> list[dict]:
    text = REGISTRY.read_text(encoding='utf-8')
    sites = SITES.read_text(encoding='utf-8')
    consts: dict[str, object] = {}
    for m in re.finditer(r"static const (?:String )?(\w+) = '([^']*)';", sites):
        consts[f'SiteIds.{m.group(1)}'] = m.group(2)
    m = re.search(r'static const List<String> supported = \[', sites)
    end = closing(sites, m.end() - 1)
    consts['SiteIds.supported'] = [consts[f'SiteIds.{n}'] for n in split_args(sites[m.end() : end])]
    for m in re.finditer(r"static const String (\w+) = '([^']*)';", text):
        consts[m.group(1)] = m.group(2)
    for m in re.finditer(r'static const Set<String> (\w+) = \{', text):
        end = closing(text, m.end() - 1)
        consts[m.group(1)] = sorted(literal(a) for a in split_args(text[m.end() : end]))

    found: dict[str, dict] = {}
    for m in re.finditer(r'static const (\w+) = (\w+Setting)\(', text):
        end = closing(text, m.end() - 1)
        positional, args = named(split_args(text[m.end() : end]))
        allowed = None
        if 'allowed' in args:
            raw = args['allowed']
            allowed = consts[raw] if raw in consts else [literal(a) for a in split_args(raw.strip('{}'))]
        found[m.group(1)] = {
            'name': m.group(1),
            'type': m.group(2).removesuffix('Setting'),
            'key': literal(positional[0]),
            'line': line_of(text, m.start()),
            'section': literal(args['section']),
            'default': literal(args['defaultValue'], consts),
            'min': literal(args['min']) if 'min' in args else None,
            'max': literal(args['max']) if 'max' in args else None,
            'allowed': allowed,
            'internal': args.get('scope') == 'SettingScope.internal',
        }

    def expand(list_name: str) -> list[str]:
        m = re.search(rf'static const List<Setting<Object>> {list_name} = \[', text)
        end = closing(text, m.end() - 1)
        names = []
        for item in split_args(text[m.end() : end]):
            names.extend(expand(item[3:]) if item.startswith('...') else [item])
        return names

    return [found[n] for n in expand('all')]


def v4_range(s: dict) -> str:
    if s['allowed']:
        return ' / '.join(f'`{a}`' for a in s['allowed'])
    if s['type'] not in ('Int', 'Double'):
        return ''
    if s['min'] is None and s['max'] is None:
        return '不限'
    low = '' if s['min'] is None else f'{s["min"]:g}' if isinstance(s['min'], float) else str(s['min'])
    high = '' if s['max'] is None else f'{s["max"]:g}' if isinstance(s['max'], float) else str(s['max'])
    return f'{low}～{high}' if low and high else (f'≥ {low}' if low else f'≤ {high}')


# ---- 3.x -------------------------------------------------------------------


def v3_sources() -> dict[str, str]:
    data = subprocess.run(['git', 'archive', TAG, 'lib'], cwd=ROOT, check=True, capture_output=True).stdout
    files = {}
    with tarfile.open(fileobj=io.BytesIO(data)) as tar:
        for member in tar.getmembers():
            if member.isfile() and member.name.endswith('.dart'):
                files[member.name] = tar.extractfile(member).read().decode('utf-8')
    return files


def file_consts(text: str) -> dict[str, object]:
    consts: dict[str, object] = {}
    pattern = r'(?:static )?const (?:[\w<>]+ )?(\w+) = ([^;]+);'
    for m in re.finditer(pattern, text):
        value = literal(m.group(2), consts)
        if not isinstance(value, Unknown):
            consts[m.group(1)] = value
    return consts


def v3_defaults(files: dict[str, str]) -> dict[str, dict]:
    """3.x key -> {'default', 'source', 'via'}."""
    keys_text = files['lib/recorder/consts/recorder_keys.dart']
    recorder_keys = dict(re.findall(r'static const (?:String )?(\w+) = [\'"]([^\'"]+)[\'"];', keys_text))
    config = files['lib/recorder/consts/recorder_config.dart']
    config_consts = file_consts(config)
    out: dict[str, dict] = {}
    for path, text in sorted(files.items()):
        if path.endswith('hive_rx.dart'):
            continue
        consts = {**file_consts(text), **{f'RecorderConfig.{k}': v for k, v in config_consts.items()}}
        for m in re.finditer(r'\bhive(Bool|Int|Double|String|StringList|Object)\s*(?:<[^>()]*>)?\(', text):
            end = closing(text, m.end() - 1)
            args = split_args(text[m.end() : end])
            if len(args) < 2:
                continue
            raw_key = args[0]
            key = literal(raw_key, consts)
            if isinstance(key, Unknown) and raw_key.startswith('RecorderKeys.'):
                key = recorder_keys.get(raw_key.split('.')[1], key)
            if isinstance(key, Unknown):
                continue
            source = f'{path.removeprefix("lib/").removeprefix("common/services/settings/")}:{line_of(text, m.start())}'
            if key in out:
                continue
            out[key] = {'default': literal(args[1], consts), 'source': source, 'via': 'hive'}
    for m in re.finditer(r'HivePrefUtil\.get\w+\(RecorderKeys\.(\w+)\)\s*\?\?\s*([\w.\']+)', config):
        key = recorder_keys[m.group(1)]
        value = literal(m.group(2), config_consts)
        entry = {'default': value, 'source': f'recorder/consts/recorder_config.dart:{line_of(config, m.start())}'}
        entry['via'] = 'recorder'
        out.setdefault(key, entry)
    return out


# ---- reads and the catalogue -----------------------------------------------


def readers() -> dict[str, list[tuple[str, int, str]]]:
    """Setting name -> [(path, line, text)] outside the registry."""
    out: dict[str, list[tuple[str, int, str]]] = {}
    roots = [ROOT / 'apps/pure_live/lib', *sorted((ROOT / 'packages').glob('*/lib'))]
    for root in roots:
        for path in sorted(root.rglob('*.dart')):
            if path == REGISTRY:
                continue
            rel = str(path.relative_to(ROOT))
            for number, line in enumerate(path.read_text(encoding='utf-8').splitlines(), 1):
                for m in re.finditer(r'\bSettings\.(\w+)\b', line):
                    out.setdefault(m.group(1), []).append((rel, number, line.strip()))
    return out


SETTINGS_UI = (
    'apps/pure_live/lib/features/settings/',
    'apps/pure_live/lib/shared/danmaku/danmaku_settings_content.dart',
    'apps/pure_live/lib/shared/danmaku/chat_list_settings.dart',
    'apps/pure_live/lib/shared/danmaku/block_manager.dart',
    'apps/pure_live/lib/features/record_settings/',
    'apps/pure_live/lib/features/live_play/local_interaction/local_style_panel.dart',
)

# A reader line that reacts to changes: a watched value, or a listener that
# compares the changed setting.
WATCHES = ('watchSetting(', '.watch(', '== Settings.', 'case Settings.')


def catalog() -> tuple[dict[str, str], dict[str, str]]:
    """Setting name -> catalogue entry id, and -> the row's range."""
    text = CATALOG.read_text(encoding='utf-8')
    lists: dict[str, list[str]] = {}
    for m in re.finditer(r'const List<Setting<Object>> (\w+) = \[', text):
        end = closing(text, m.end() - 1)
        lists[m.group(1)] = re.findall(r'Settings\.(\w+)', text[m.end() : end])
    entries: dict[str, str] = {}
    ranges: dict[str, str] = {}
    for m in re.finditer(r'\.\.(toggle|slider|choice|number|add|link)(?:<\w+>)?\(', text):
        end = closing(text, m.end() - 1)
        body = text[m.end() : end]
        positional, args = named(split_args(body))
        entry_id = literal(positional[0])
        kind = m.group(1)
        if kind in ('toggle', 'slider', 'choice', 'number'):
            names = re.findall(r'Settings\.(\w+)', positional[2])
        else:
            raw = args.get('settings', '')
            names = lists.get(raw, re.findall(r'Settings\.(\w+)', raw))
        for name in names:
            entries.setdefault(name, entry_id)
        if kind == 'slider':
            ranges[names[0]] = f'滑块 {args["min"]}～{args["max"]}' + (f'，步长 {args["step"]}' if 'step' in args else '')
        elif kind == 'number':
            presets = re.sub(r'^const ', '', args['presets'])
            ranges[names[0]] = f'数字框，预设 `{presets}`'
        else:
            counter = re.search(r'SettingCounterTile\(.*?min: ([\d.]+),\s*max: ([\d.]+)', body, re.S)
            if counter and names:
                ranges[names[0]] = f'加减 {counter.group(1)}～{counter.group(2)}'
    return entries, ranges


# ---- the table -------------------------------------------------------------


def short(path: str) -> str:
    """[path] without `apps/pure_live/lib/`; a package's as `<package>/<path>`."""
    if path.startswith('apps/pure_live/lib/'):
        return path.removeprefix('apps/pure_live/lib/')
    package, rest = path.removeprefix('packages/').split('/lib/', 1)
    return f'{package}/{rest}'


KINDS = {
    'same': '一样',
    'approved': '确认改动',
    'fixed': '不一样，已改',
    'open': '不一样，待处理',
}


def build() -> tuple[str, list[dict]]:
    settings = v4_settings()
    files = v3_sources()
    v3 = v3_defaults(files)
    reads = readers()
    entries, ui_ranges = catalog()
    rows = []
    for s in settings:
        note = NOTES.get(s['key'], {})
        hit = v3.get(s['key'])
        if 'v3' in note:
            v3_value = literal(note['v3']) if isinstance(note['v3'], str) else note['v3']
        else:
            v3_value = hit['default'] if hit else None
        v3_source = note.get('v3src') or (hit['source'] if hit else '')
        kind = note.get('kind')
        if kind is None:
            if v3_value is None or isinstance(v3_value, Unknown):
                kind = 'missing'
            else:
                kind = 'same' if same(v3_value, s['default']) else 'differs'
        outside = [r for r in reads.get(s['name'], []) if not r[0].startswith(SETTINGS_UI)]
        page = [r for r in reads.get(s['name'], []) if r[0].startswith(SETTINGS_UI)]
        if 'reads' in note:
            where = note['reads']
        elif outside:
            shown = [f'{short(p)}:{n}' for p, n, _ in outside[:3]]
            more = f' 等 {len(outside)} 处' if len(outside) > 3 else ''
            where = '、'.join(f'`{w}`' for w in shown) + more
        elif page:
            where = '只在设置页：' + '、'.join(f'`{short(p)}:{n}`' for p, n, _ in page[:2])
        else:
            where = '没有读取'
        if 'when' in note:
            when = note['when']
        elif any(w in t for _, _, t in outside for w in WATCHES):
            when = '立即'
        elif outside:
            when = '读取时'
        else:
            when = ''
        rows.append(
            {
                **s,
                'v3': v3_value,
                'v3src': v3_source,
                'v3range': note.get('v3range', ''),
                'ui': note.get('ui', ui_ranges.get(s['name'], '')),
                'where': where,
                'when': when,
                'entry': entries.get(s['name'], ''),
                'kind': kind,
                'verdict': note.get('verdict', ''),
                'new': note.get('new', False),
            }
        )
    return render(rows), rows


SECTION_TITLES = {
    'app': '应用（app）',
    'favorite': '平台（favorite）',
    'history': '历史（history）',
    'theme': '主题（theme）',
    'meta': '本机记录（meta）',
    'font': '字体（font）',
    'player': '播放（player）',
    'danmaku': '弹幕（danmaku）',
    'volume': '音量（volume）',
    'roomCard': '直播间卡片（roomCard）',
    'page': '翻页（page）',
    'refresh': '刷新（refresh）',
    'iptv': '网络电视（iptv）',
    'proxy': '代理（proxy）',
    'windowSize': '窗口（windowSize）',
    'exit': '退出（exit）',
    'startup': '开机启动（startup）',
    'recorder': '录制（recorder）',
    'localInteraction': '本地互动（localInteraction）',
    'backup': '备份（backup）',
    'cache': '下载目录（cache）',
    'log': '日志（log）',
    'cookie': '账号（cookie）',
}


def render(rows: list[dict]) -> str:
    counts = {k: 0 for k in KINDS}
    for r in rows:
        counts[r['kind']] = counts.get(r['kind'], 0) + 1
    unknown = [r['key'] for r in rows if r['kind'] not in KINDS]
    out = io.StringIO()
    w = out.write
    w('# J01.2 设置项对照表\n\n')
    w('<!-- 由 tools/docs/settings_audit.py 生成（手写的部分在 tools/docs/settings_audit_notes.py），不要手改 -->\n\n')
    w(f'v4 的 {len(rows)} 个设置（`Settings.all`），每个一行，和 3.x（`{TAG}`）比默认值、取值范围、设置页的范围、')
    w('读取位置和生效时机。返回 [README](README.md)。\n\n')
    w('## 结论\n\n')
    w('| 结论 | 个数 |\n|---|---:|\n')
    for k, label in KINDS.items():
        w(f'| {label} | {counts.get(k, 0)} |\n')
    if unknown:
        w(f'| 未核对 | {len(unknown)}（{", ".join(unknown)}） |\n')
    w('\n“一样”：默认值和 3.x 一样（3.x 的常量和表达式已经展开），数值的范围也一样（3.x 的范围是它启动时和导入备份时的修正）；')
    w('v4 新加的设置，“一样”指默认值和来源任务写的一致。“确认改动”写了依据（任务或决定）。')
    w('“不一样，已改”是本任务改了注册表（`settings.dart`），“不一样，待处理”开了后续任务。\n\n')
    w('列的意思：**3.x 默认**是 Android 手机新装时的值，后面是 3.x 的文件:行（`lib/` 下）；**v4 范围**是注册表的 `min`/`max` 或可选值，')
    w('存的值越界时夹紧、不在可选值里时用默认值；**设置页**是设置页这一行的滑块、加减或数字框的范围（空的是开关、选项或专门的页面）；')
    w('**读取**是设置页以外读它的代码（`apps/pure_live/lib` 或 `packages/*/lib` 下）；**生效**：“立即”是界面监听着它，“读取时”是用到时读一次（例如进房、启动）；')
    w('**目录**是设置页目录 `settings_catalog.dart` 里登记它的那一行的 id（`SettingsEntry.settings`；现在设置页还没有用它显示“已修改”，'
      '“恢复本页默认”用各页自己的列表），空的是没登记：本机记录、没有界面的、在自己的页面上设置的（网络电视、录制、本地互动、日志、电视界面、直播间里的状态）。\n')
    sections: dict[str, list[dict]] = {}
    for r in rows:
        sections.setdefault(r['section'], []).append(r)
    for section, items in sections.items():
        w(f'\n## {SECTION_TITLES.get(section, section)}\n\n')
        w('| 键 | 类型 | v4 默认 | 3.x 默认 | v4 范围 | 3.x 范围 | 设置页 | 读取 | 生效 | 目录 | 结论 |\n')
        w('|---|---|---|---|---|---|---|---|---|---|---|\n')
        for r in items:
            v3 = '—（新加）' if r['new'] else ('' if r['v3'] is None else show(r['v3']))
            if r['v3src']:
                v3 += f'（{r["v3src"]}）' if '`' in r['v3src'] else f'（`{r["v3src"]}`）'
            flags = '，本机' if r['internal'] else ''
            verdict = KINDS.get(r['kind'], '**未核对**')
            if r['verdict']:
                verdict += f'：{r["verdict"]}'
            cells = [
                f'`{r["key"]}`',
                r['type'] + flags,
                show(r['default']),
                v3,
                v4_range(r),
                r['v3range'],
                r['ui'],
                r['where'],
                r['when'],
                f'`{r["entry"]}`' if r['entry'] else '',
                verdict,
            ]
            w('| ' + ' | '.join(c.replace('|', '\\|').replace('\n', ' ') for c in cells) + ' |\n')
    w(f'\n## 3.x 有、v4 不作为设置的键\n\n{V3_ONLY_NOTE}\n')
    return out.getvalue()


def dart_map(rows: list[dict]) -> str:
    def dart(value: object) -> str:
        if isinstance(value, bool):
            return 'true' if value else 'false'
        if isinstance(value, int) and value > 0xFFFFFF:
            return f'0x{value:08X}'
        if isinstance(value, float):
            return repr(value)
        if isinstance(value, str):
            return "'" + value.replace("'", "\\'") + "'"
        if isinstance(value, list):
            return '[' + ', '.join(dart(v) for v in value) + ']'
        if isinstance(value, dict):
            return '<String, Object?>{}'
        return str(value)

    lines = []
    for r in rows:
        if r['new'] or r['v3'] is None or isinstance(r['v3'], Unknown):
            continue
        lines.append(f"  '{r['key']}': {dart(r['v3'])},")
    return '\n'.join(lines)


def main() -> int:
    text, rows = build()
    if '--dart' in sys.argv:
        print(dart_map(rows))
    elif '--stdout' in sys.argv:
        print(text)
    else:
        OUT.write_text(text, encoding='utf-8')
        print(f'wrote {OUT.relative_to(ROOT)} ({len(rows)} settings)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
