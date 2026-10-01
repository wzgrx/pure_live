"""U.0: move apps/pure_live/lib/pages and lib/home into lib/features/<v3 module>,
split the live room by v3's sub-folders, move feature tests under
test/features/<feature>, and rewrite imports. Behaviour is unchanged.

Run once from the repository root (idempotence is not a goal: it is a one-off
migration kept for the record)."""
import os, re, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / 'apps/pure_live'
LIB = APP / 'lib'
TEST = APP / 'test'

LIVE = {
    'live_play_page.dart': 'live_play_page.dart',
    'room_controller.dart': 'logic/room_controller.dart',
    'background_playback.dart': 'logic/background_playback.dart',
    'player_view.dart': 'player/player_view.dart',
    'player_gestures.dart': 'player/player_gestures.dart',
    'chat_feed.dart': 'danmaku/chat_feed.dart',
    'chat_panel.dart': 'danmaku/chat_panel.dart',
    'danmaku_templates.dart': 'danmaku/danmaku_templates.dart',
    'record_button.dart': 'buttons/record_button.dart',
    'room_menu_button.dart': 'buttons/room_menu_button.dart',
    'room_dialogs.dart': 'dialogs/room_dialogs.dart',
    'room_switcher.dart': 'dialogs/room_switcher.dart',
    'stream_dialogs.dart': 'dialogs/stream_dialogs.dart',
    'iptv_guide.dart': 'dialogs/iptv_guide.dart',
    'room_panels.dart': 'layout/room_panels.dart',
}

def lib_map():
    """old lib-relative path -> new lib-relative path."""
    m = {}
    for p in sorted((LIB / 'pages').rglob('*.dart')):
        rel = p.relative_to(LIB).as_posix()
        parts = rel.split('/')
        if len(parts) == 2:  # pages/under_construction.dart
            m[rel] = 'shared/' + parts[1]
            continue
        feature, rest = parts[1], '/'.join(parts[2:])
        if feature == 'live_play':
            if rest not in LIVE:
                sys.exit(f'unmapped live room file: {rest}')
            m[rel] = f'features/live_play/{LIVE[rest]}'
        else:
            m[rel] = f'features/{feature}/{rest}'
    for p in sorted((LIB / 'home').rglob('*.dart')):
        rel = p.relative_to(LIB).as_posix()
        m[rel] = 'features/home/' + rel[len('home/'):]
    return m

TEST_MAP = {
    'areas_test.dart': 'features/areas/areas_test.dart',
    'favorite_test.dart': 'features/favorite/favorite_test.dart',
    'home_test.dart': 'features/home/home_test.dart',
    'live_play_controller_test.dart': 'features/live_play/live_play_controller_test.dart',
    'live_play_more_page_test.dart': 'features/live_play/live_play_more_page_test.dart',
    'live_play_more_test.dart': 'features/live_play/live_play_more_test.dart',
    'live_play_page_test.dart': 'features/live_play/live_play_page_test.dart',
    'live_play_support.dart': 'features/live_play/live_play_support.dart',
    'popular_test.dart': 'features/popular/popular_test.dart',
    'search_test.dart': 'features/search/search_test.dart',
}

def test_map():
    m = dict(TEST_MAP)
    for p in sorted((TEST / 'pages').rglob('*.dart')):
        rel = p.relative_to(TEST).as_posix()
        m[rel] = 'features/' + rel[len('pages/'):]
    return m

def git_mv(src: Path, dst: Path):
    dst.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(['git', 'mv', str(src), str(dst)], check=True, cwd=ROOT)

IMPORT = re.compile(r"""^(\s*(?:import|export|part)\s+')([^']+)(')""", re.M)

def main():
    lm, tm = lib_map(), test_map()
    pkg = {f'package:pure_live/{o}': f'package:pure_live/{n}' for o, n in lm.items()}
    # 1. move lib files
    for old, new in lm.items():
        git_mv(LIB / old, LIB / new)
    # 2. move test files, remembering where each came from
    moved_tests = {}
    for old, new in tm.items():
        git_mv(TEST / old, TEST / new)
        moved_tests[TEST / new] = TEST / old
    # 3. rewrite imports in every Dart file of the app
    for f in list(LIB.rglob('*.dart')) + list(TEST.rglob('*.dart')):
        text = f.read_text(encoding='utf-8')
        old_dir = moved_tests.get(f, f).parent
        def fix(match):
            target = match.group(2)
            if target.startswith('package:'):
                return match.group(1) + pkg.get(target, target) + match.group(3)
            if target.startswith('dart:'):
                return match.group(0)
            # a relative import: resolve against where the file used to be
            abs_old = (old_dir / target).resolve()
            rel_old = None
            if abs_old.is_relative_to(TEST):
                rel_old = abs_old.relative_to(TEST).as_posix()
                abs_new = TEST / tm.get(rel_old, rel_old)
            else:
                return match.group(0)
            new_rel = os.path.relpath(abs_new, f.parent).replace(os.sep, '/')
            return match.group(1) + new_rel + match.group(3)
        new_text = IMPORT.sub(fix, text)
        if new_text != text:
            f.write_text(new_text, encoding='utf-8')
    # 4. rewrite paths mentioned in docs (exact files first, then the folder prefix)
    doc_pairs = [(f'apps/pure_live/lib/{o}', f'apps/pure_live/lib/{n}') for o, n in lm.items()]
    doc_pairs += [(f'pages/live_play/{o}', f'features/live_play/{n}') for o, n in LIVE.items()]
    doc_pairs += [('apps/pure_live/lib/pages/', 'apps/pure_live/lib/features/'), ('apps/pure_live/lib/home/', 'apps/pure_live/lib/features/home/')]
    for f in list((ROOT / 'docs').rglob('*.md')) + [ROOT / 'AGENTS.md']:
        text = f.read_text(encoding='utf-8')
        new_text = text
        for o, n in doc_pairs:
            new_text = new_text.replace(o, n)
        if new_text != text:
            f.write_text(new_text, encoding='utf-8')
    print(f'moved {len(lm)} lib files and {len(tm)} test files')

main()
