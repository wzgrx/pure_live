"""UI structure check for apps/pure_live (docs/specs/UI.md §5.2).

Three rules:

1. A feature does not import another feature's internals: a file under
   lib/features/<a>/ may import lib/features/<b>/ only for b's entry page
   (<b>/<b>_page.dart). Shared code lives in lib/shared/ or packages/live_ui.
2. Features and the TV shell take colours and icons from live_ui (theme roles,
   AppIcons), never as raw `Color(0x…)`, `Colors.*`, `Icons.*` or `Remix.*`.
3. Files under a feature's logic/ do not import Flutter's material library.

Rules 1 and 2 are ratchets: tools/gate/ui_baseline.json lists what existed
when the rule arrived (U.0). The check fails when a feature gains a violation
the baseline does not list, and when the baseline lists something that is gone
(so it shrinks as screens are rebuilt). Standard library only.
"""
from pathlib import Path
import json
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
LIB = ROOT / 'apps/pure_live/lib'
BASELINE = Path(__file__).with_name('ui_baseline.json')

FEATURE_IMPORT = re.compile(r"""^\s*(?:import|export)\s+'package:pure_live/features/([a-z0-9_]+)/([^']+)'""", re.M)
RAW_STYLE = re.compile(r'\bColor\(0x|\bColors\.[a-z]|\bIcons\.[a-z]|\bRemix(?:Icons)?\.[a-z]')
MATERIAL = re.compile(r"""^\s*import\s+'package:flutter/material\.dart'""", re.M)


def strip_comments(text):
    """Drops // comments so documentation may name a colour or an icon."""
    return re.sub(r'//[^\n]*', '', text)


def scan(lib=LIB):
    """Returns (cross imports, raw style counts per area, logic files using material)."""
    cross, raw, logic = set(), {}, []
    for path in sorted(lib.glob('features/**/*.dart')) + sorted(lib.glob('tv/**/*.dart')):
        rel = path.relative_to(lib).as_posix()
        area = path.relative_to(lib).parts[1] if rel.startswith('features/') else 'tv'
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


def check(baseline, cross, raw, logic):
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
    return problems


def main():
    baseline = json.loads(BASELINE.read_text(encoding='utf-8'))
    problems = check(baseline, *scan())
    for line in problems:
        print(f'ui structure: {line}')
    return 1 if problems else 0


if __name__ == '__main__':
    if sys.argv[1:] == ['--write-baseline']:
        cross, raw, _ = scan()
        BASELINE.write_text(json.dumps({'cross_feature_imports': sorted(cross), 'raw_styles': dict(sorted(raw.items()))}, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        sys.exit(0)
    sys.exit(main())
