"""Counts the screens of v3 (v3.2.11) and pure_live_TV and assigns every UI
file to a task of docs/ui/TASKS.md, so no screen is left out.

A UI file is a Dart file that declares a widget class or opens a dialog,
sheet or menu. RULES maps path prefixes to task ids, first match wins; a UI
file no rule matches is printed as unassigned and the script exits 1.

usage: python3 tools/ui/inventory.py [--v3 ~/ref/v3ref] [--tv ~/ref/pure_live_TV] [--files]
  default output: per-task counts as a Markdown table
  --files: Markdown list of files per task (docs/ui/TASK_FILES.md)
"""
import argparse, os, re, sys
from collections import Counter, defaultdict

WIDGET = re.compile(r'^class\s+(\w+)\s+extends\s+(?:StatelessWidget|StatefulWidget|GetView<|GetWidget<|ConsumerWidget|ConsumerStatefulWidget|HookWidget)', re.M)
DIALOG = re.compile(r'\b(?:showDialog|Get\.dialog|showGeneralDialog|showAdaptiveDialog)\b|\b(?:TvDialog|TvConfirmDialog|TvInputDialog|TvSelectDialog|TvMultiSelectDialog|TvMenuDialog)\(')
SHEET = re.compile(r'\b(?:showModalBottomSheet|Get\.bottomSheet|showBottomSheet)\b')
MENU = re.compile(r'\b(?:PopupMenuButton|showMenu|MenuAnchor|DropdownButton|DropdownMenu)\b')

V3 = [
    ('get/', None), ('gen/', None),
    ('main.dart', 'U.1'), ('plugins/utils.dart', 'U.1'), ('plugins/update.dart', 'U.3d'), ('core/iptv/', 'U.9'),
    ('common/base/desktop_components.dart', 'U.13'), ('common/global/platform/', 'U.13'),
    ('common/widgets/adaptive_refresh_rate_scope.dart', 'U.2i'),
    ('common/widgets/common_appbar_actions.dart', 'U.3a'), ('common/widgets/menu_button.dart', 'U.3a'),
    ('common/widgets/search_button.dart', 'U.3a'),
    ('common/widgets/download_apk_dialog.dart', 'U.3d'), ('common/widgets/download_directory_dialog.dart', 'U.3d'),
    ('common/widgets/share_command_import_dialog.dart', 'U.3d'),
    ('common/widgets/room_card', 'U.4a'),
    ('common/', 'U.1'),
    ('modules/home/tablet_view.dart', 'U.3b'), ('modules/home/', 'U.3a'), ('modules/splash/', 'U.3c'),
    ('modules/popular/', 'U.4b'), ('modules/favorite/', 'U.4c'),
    ('modules/areas/favorite_areas_page.dart', 'U.4f'), ('modules/hot_areas/', 'U.4f'),
    ('modules/areas/', 'U.4d'), ('modules/area_rooms/', 'U.4e'),
    ('modules/search/web_search_page.dart', 'U.5b'), ('modules/search/', 'U.5a'), ('modules/history/', 'U.5c'),
    ('modules/settings/settings_page.dart', 'U.6a'),
    *[(f'modules/settings/pages/{p}', 'U.6b') for p in ('theme_settings', 'font_settings', 'font_family_manager', 'loading_style', 'room_card_settings', 'page_settings', 'navigation_settings')],
    ('modules/settings/widgets/app_color_picker', 'U.6b'),
    *[(f'modules/settings/pages/{p}', 'U.6c') for p in ('video_settings', 'portrait_live', 'player_kernel', 'mpv_option', 'pip_danmaku', 'audience_metric')],
    *[(f'modules/settings/pages/{p}', 'U.6d') for p in ('general_settings', 'platform_settings', 'refresh_settings', 'network_proxy', 'local_interaction_settings')],
    *[(f'modules/settings/pages/{p}', 'U.6e') for p in ('cache_data', 'local_config')],
    ('recorder/pages/record_settings/', 'U.7b'), ('recorder/', 'U.7a'),
    ('modules/multiview/', 'U.8'), ('modules/iptv/', 'U.9'),
    ('modules/account/account_page.dart', 'U.10a'), ('modules/account/', 'U.10b'),
    ('modules/auth/', 'U.10c'),
    ('modules/backup/', 'U.11a'), ('modules/web_dav/', 'U.11b'), ('modules/remote_receiver/', 'U.11c'),
    ('modules/toolbox/', 'U.12a'), ('modules/about/', 'U.12b'), ('modules/version/', 'U.12b'),
    ('modules/tags/', 'U.12c'), ('modules/shield/', 'U.12d'),
    # live room
    ('modules/live_play/widgets/layout/portrait_fullscreen_interaction.dart', 'U.2b'),
    ('modules/live_play/widgets/video_player/portrait_playback_picker_dialog.dart', 'U.2b'),
    ('modules/live_play/widgets/content_first_panel_layout.dart', 'U.2c'),
    ('modules/live_play/widgets/keyboard/', 'U.2c'),
    ('modules/live_play/widgets/video_player/video_controller', 'U.2c'),
    ('modules/live_play/widgets/video_player/volume_control.dart', 'U.2c'),
    ('modules/live_play/widgets/layout/control_hover_region.dart', 'U.2d'),
    ('modules/live_play/widgets/danmaku/compact_danmaku_overlay.dart', 'U.2j'),
    ('modules/live_play/widgets/danmaku/danmaku_message_actions.dart', 'U.2f'),
    ('modules/live_play/widgets/danmaku/', 'U.2e'), ('modules/live_play/widgets/layout/super_chat_card.dart', 'U.2e'),
    ('modules/live_play/pages/super_chat_page.dart', 'U.2e'), ('modules/live_play/pages/danmaku_settings_page.dart', 'U.2e'),
    ('modules/live_play/pages/keyword_block_page.dart', 'U.2e'),
    ('modules/live_play/widgets/button/live_play_menu_button.dart', 'U.2f'), ('modules/live_play/widgets/button/record_action', 'U.2f'),
    ('modules/live_play/widgets/resolution_selector/line_selector.dart', 'U.2f'),
    ('modules/live_play/widgets/resolution_selector/resolution_selector.dart', 'U.2f'),
    ('modules/live_play/dialogs/', 'U.2f'), ('modules/live_play/widgets/local_interaction/', 'U.2f'),
    ('modules/live_play/widgets/placeholder/', 'U.2g'), ('modules/live_play/widgets/video_player/playback_failure_overlay.dart', 'U.2g'),
    ('modules/live_play/widgets/video_player/video_loading.dart', 'U.2g'), ('modules/live_play/widgets/video_player/iptv_', 'U.2g'),
    ('player/utils/pip_window_widget.dart', 'U.2j'),
    ('modules/live_play/', 'U.2a'), ('player/', 'U.2a'),
]

TV = [
    ('app/', 'U.15a'), ('core/', 'U.15a'), ('domains/', 'U.15a'),
    ('features/home/', 'U.15b'), ('features/agreement/', 'U.15b'),
    ('modules/live/playback/', 'U.15d'), ('modules/live/iptv/', 'U.15e'), ('modules/live/movie_playback/', 'U.15e'),
    ('modules/live/', 'U.15c'),
    ('modules/video/', 'U.15f'), ('modules/vod/', 'U.15f'), ('modules/music/', 'U.15g'),
    ('features/wallpaper/', 'U.15h'), ('features/settings/', 'U.15i'),
]


def assign(rel, rules):
    for prefix, task in rules:
        if rel.startswith(prefix):
            return task or 'skip'
    return None


def scan(lib, rules, label):
    """Returns ({task: Counter}, {task: [files]}, [unassigned])."""
    counts, files, missing = defaultdict(Counter), defaultdict(list), []
    for root, _, names in os.walk(lib):
        for name in sorted(names):
            if not name.endswith('.dart') or name.endswith(('.g.dart', '.freezed.dart')):
                continue
            path = os.path.join(root, name)
            rel = os.path.relpath(path, lib).replace(os.sep, '/')
            text = re.sub(r'//[^\n]*', '', open(path, encoding='utf-8', errors='ignore').read())
            widgets = WIDGET.findall(text)
            pops = [len(DIALOG.findall(text)), len(SHEET.findall(text)), len(MENU.findall(text))]
            if label == 'tv' and rel.startswith('core/dialog/'):
                pops = [0, 0, 0]  # the dialog widgets themselves, not uses
            if not widgets and not any(pops):
                continue
            task = assign(rel, rules)
            if task is None:
                missing.append(f'{label}:{rel}')
                continue
            if task == 'skip':
                continue
            c = counts[task]
            c['files'] += 1
            c['pages'] += sum(1 for w in widgets if not w.startswith('_') and re.search(r'(Page|Screen|View)$', w))
            c['dialogs'] += pops[0]
            c['sheets'] += pops[1]
            c['menus'] += pops[2]
            files[task].append(f'{label}:{rel}')
    return counts, files, missing


def order(task):
    m = re.match(r'U\.(\d+)([a-z]?)', task)
    return (int(m.group(1)), m.group(2))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--v3', default=os.path.expanduser('~/ref/v3ref'))
    ap.add_argument('--tv', default=os.path.expanduser('~/ref/pure_live_TV'))
    ap.add_argument('--files', action='store_true')
    args = ap.parse_args()
    counts, files, missing = defaultdict(Counter), defaultdict(list), []
    for lib, rules, label in ((os.path.join(args.v3, 'lib'), V3, 'v3'), (os.path.join(args.tv, 'lib'), TV, 'tv')):
        c, f, m = scan(lib, rules, label)
        for k, v in c.items():
            counts[k].update(v)
        for k, v in f.items():
            files[k] += v
        missing += m
    if args.files:
        print('# 界面文件对照（生成）\n\n由 `tools/ui/inventory.py --files` 生成，不要手改。`v3:` 是 `v3.2.11` 的 `lib/`，`tv:` 是 pure_live_TV 的 `lib/`。\n')
        for task in sorted(files, key=order):
            print(f'## {task}\n')
            print('\n'.join(f'- `{p}`' for p in files[task]) + '\n')
    else:
        keys = ('files', 'pages', 'dialogs', 'sheets', 'menus')
        print('| 任务 | 界面文件 | 页面 | 对话框 | 底部面板 | 菜单 |')
        print('|---|---:|---:|---:|---:|---:|')
        total = Counter()
        for task in sorted(counts, key=order):
            print(f'| {task} | ' + ' | '.join(str(counts[task][k]) for k in keys) + ' |')
            total.update(counts[task])
        print('| 合计 | ' + ' | '.join(str(total[k]) for k in keys) + ' |')
    for m in missing:
        print(f'unassigned: {m}', file=sys.stderr)
    return 1 if missing else 0


if __name__ == '__main__':
    sys.exit(main())
