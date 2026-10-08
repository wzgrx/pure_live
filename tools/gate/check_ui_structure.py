"""UI structure check for apps/pure_live (docs/specs/UI.md §5.2, §8).

Five rules:

1. A feature does not import another feature's internals: a file under
   lib/features/<a>/ may import lib/features/<b>/ only for b's entry page
   (<b>/<b>_page.dart). Shared code lives in lib/shared/ or packages/live_ui.
2. Features, shared code and the TV shell take colours and icons from
   live_ui (theme roles, AppIcons), never as raw `Color(0x…)`, `Colors.*`,
   `Icons.*` or `Remix.*`; live_ui's own components take their icons from
   AppIcons too (A01.3).
3. Files under a feature's logic/ do not import Flutter's material library.
4. Every `AppIcons` name is used somewhere (A01.3), so the list stays the
   icons the app shows.
5. Text takes its size from the theme's five font roles and its weight is
   400 or 600 (UI.md §8.2, A01.2): no `fontSize: <number>` and no
   `FontWeight.w500/w700/w800/w900/bold` in pages, shared code, the app
   shell and live_ui's components. The live room (features/live_play/), the
   TV shell (A17) and the text drawn over the video are not checked yet.

Rules 1 and 2 are ratchets: tools/gate/ui_baseline.json lists what existed
when the rule arrived (U.0). The check fails when an area gains a violation
the baseline does not list, and when the baseline lists something that is gone
(so it shrinks as screens are rebuilt). Rules 3–5 allow nothing. Standard
library only.
"""
from pathlib import Path
import json
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
LIB = ROOT / 'apps/pure_live/lib'
LIVE_UI = ROOT / 'packages/live_ui/lib'
BASELINE = Path(__file__).with_name('ui_baseline.json')

FEATURE_IMPORT = re.compile(r"""^\s*(?:import|export)\s+'package:pure_live/features/([a-z0-9_]+)/([^']+)'""", re.M)
RAW_STYLE = re.compile(r'\bColor\(0x|\bColors\.[a-z]|\bIcons\.[a-z]|\bRemix(?:Icons)?\.[a-z]')
RAW_ICON = re.compile(r'\bIcons\.[a-z]|\bRemix(?:Icons)?\.[a-z]')
MATERIAL = re.compile(r"""^\s*import\s+'package:flutter/material\.dart'""", re.M)
# `fontSize: 12` and `fontSize: tv ? 17 : 15`.
TEXT_ROLE = re.compile(r'\bfontSize:\s*(?:\d|[^,;()]*\?\s*\d)|\bFontWeight\.(?:w500|w700|w800|w900|bold)\b')
ICON_NAME = re.compile(r'static const IconData (\w+) =')

# Rule 5 leaves these alone: the live room and the TV shell (their own
# tasks), and text over the video (UI.md §8.2 caps it at 1.3 times the
# system size; whether it follows the five sizes is the live room's call).
TEXT_ROLE_SKIP_LIB = ('features/live_play/', 'tv/')
TEXT_ROLE_SKIP_FILES = {
    # Danmaku templates: the size is the template's data, not a text style.
    'apps/pure_live/lib/shared/danmaku/danmaku_templates.dart',
    # The desktop title bar: window chrome 32 high that ignores text scaling
    # like the system's own (A16.1).
    'apps/pure_live/lib/app/desktop/title_bar.dart',
    'packages/live_ui/lib/src/widgets/video_state_view.dart',
    'packages/live_ui/lib/src/widgets/record_glyph.dart',
    'packages/live_ui/lib/src/widgets/pip_danmaku_preview.dart',
}


def strip_comments(text):
    """Drops // comments so documentation may name a colour or an icon."""
    return re.sub(r'//[^\n]*', '', text)


def scan(lib=LIB):
    """Returns (cross imports, raw style counts per area, logic files using material)."""
    cross, raw, logic = set(), {}, []
    files = sorted(lib.glob('features/**/*.dart')) + sorted(lib.glob('shared/**/*.dart')) + sorted(lib.glob('tv/**/*.dart'))
    for path in files:
        rel = path.relative_to(lib).as_posix()
        area = path.relative_to(lib).parts[1] if rel.startswith('features/') else rel.split('/')[0]
        text = path.read_text(encoding='utf-8')
        if rel.startswith('features/'):
            for other, file in FEATURE_IMPORT.findall(text):
                if other != area and file != f'{other}_page.dart':
                    cross.add(f'{area} -> {other}/{file}')
            if '/logic/' in rel and MATERIAL.search(text):
                logic.append(rel)
        count = len(RAW_STYLE.findall(strip_comments(text)))
        if count:
            raw[area] = raw.get(area, 0) + count
    return cross, raw, logic


def _lines(path, pattern):
    """(line number, line) of each uncommented line of [path] matching [pattern]."""
    found = []
    for number, line in enumerate(path.read_text(encoding='utf-8').splitlines(), 1):
        if pattern.search(strip_comments(line)):
            found.append((number, line.strip()))
    return found


def scan_component_icons(live_ui=LIVE_UI):
    """`file:line` of each raw icon in live_ui's components (rule 2)."""
    hits = []
    for path in sorted((live_ui / 'src/widgets').glob('**/*.dart')):
        for number, _ in _lines(path, RAW_ICON):
            hits.append(f'{path.relative_to(live_ui.parent).as_posix()}:{number}')
    return hits


def unused_icons(live_ui=LIVE_UI, roots=None):
    """The `AppIcons` names no library code uses (rule 4)."""
    icons = live_ui / 'src/icons/app_icons.dart'
    names = ICON_NAME.findall(icons.read_text(encoding='utf-8'))
    roots = roots if roots is not None else [LIB, *sorted((ROOT / 'packages').glob('*/lib'))]
    used = set()
    pattern = re.compile(r'\bAppIcons\.(\w+)')
    for root in roots:
        for path in root.glob('**/*.dart'):
            if path == icons:
                continue
            used.update(pattern.findall(path.read_text(encoding='utf-8')))
    return [name for name in names if name not in used]


def scan_text_roles(lib=LIB, live_ui=LIVE_UI, root=ROOT):
    """`file:line: code` of each fixed font size or off-scale weight (rule 5)."""
    files = []
    for area in ('features', 'shared', 'app'):
        for path in sorted(lib.glob(f'{area}/**/*.dart')):
            if not path.relative_to(lib).as_posix().startswith(TEXT_ROLE_SKIP_LIB):
                files.append(path)
    files += sorted((live_ui / 'src/widgets').glob('**/*.dart'))
    hits = []
    for path in files:
        try:
            rel = path.relative_to(root).as_posix()
        except ValueError:
            rel = path.as_posix()
        if rel in TEXT_ROLE_SKIP_FILES:
            continue
        for number, line in _lines(path, TEXT_ROLE):
            hits.append(f'{rel}:{number}: {line}')
    return hits


def check(baseline, cross, raw, logic, component_icons=(), unused=(), text_roles=()):
    """Returns the list of failure messages."""
    problems = [f'logic/ imports material: {f}' for f in logic]
    allowed = set(baseline.get('cross_feature_imports', []))
    problems += [f'new cross-feature import: {c} (move the shared part to lib/shared/ or live_ui)' for c in sorted(cross - allowed)]
    problems += [f'baseline lists a cross-feature import that is gone, remove it: {c}' for c in sorted(allowed - cross)]
    limits = baseline.get('raw_styles', {})
    for area, count in sorted(raw.items()):
        limit = limits.get(area, 0)
        if count > limit:
            problems.append(f'{area}: {count} raw colours/icons, baseline allows {limit} (use live_ui theme roles and AppIcons)')
    for area, limit in sorted(limits.items()):
        count = raw.get(area, 0)
        if count < limit:
            problems.append(f'{area}: raw colours/icons dropped to {count}, lower the baseline from {limit}')
    problems += [f'raw icon in a live_ui component, name it in AppIcons: {h}' for h in component_icons]
    problems += [f'AppIcons.{name} is not used anywhere: use it or remove it' for name in unused]
    problems += [f'fixed font size or a weight other than 400/600 (use the theme\'s font roles, UI.md §8.2): {h}' for h in text_roles]
    return problems


def main():
    baseline = json.loads(BASELINE.read_text(encoding='utf-8'))
    problems = check(baseline, *scan(), scan_component_icons(), unused_icons(), scan_text_roles())
    for line in problems:
        print(f'ui structure: {line}')
    return 1 if problems else 0


if __name__ == '__main__':
    if sys.argv[1:] == ['--write-baseline']:
        cross, raw, _ = scan()
        BASELINE.write_text(json.dumps({'cross_feature_imports': sorted(cross), 'raw_styles': dict(sorted(raw.items()))}, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        sys.exit(0)
    sys.exit(main())
