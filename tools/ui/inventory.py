"""Counts the screens of v3 (v3.2.11) and pure_live_TV and assigns every UI
file to a task of docs/TASKS.md, so no screen is left out.

The rules below keep the old U ids of the first inventory (2026-10-01); the
output names the tasks by their docs v2 ids, looked up in the `old` field of
docs/tasks.toml (Z03.3).

A UI file is a Dart file that declares a widget class or opens a dialog,
sheet or menu. RULES maps path prefixes to task ids, first match wins; a UI
file no rule matches is printed as unassigned and the script exits 1.

usage: python3 tools/ui/inventory.py [--v3 ~/ref/v3ref] [--tv ~/ref/pure_live_TV] [--tv-ref COMMIT] [--files | --items]
  --tv-ref: scan that commit of the TV repository (git archive, the work tree is left alone)
  default output: per-task counts as a Markdown table
  --files: Markdown list of files per task (docs/inventory/UI_FILES.md)
  --items: every page, dialog, sheet, menu and overlay per task, with the
           Chinese title found next to it (docs/inventory/UI.md)
"""
import argparse, os, re, subprocess, sys, tarfile, tempfile, tomllib
from collections import Counter, defaultdict

WIDGET = re.compile(r'^class\s+(\w+)\s+extends\s+(?:StatelessWidget|StatefulWidget|GetView<|GetWidget<|ConsumerWidget|ConsumerStatefulWidget|HookWidget)', re.M)
DIALOG = re.compile(r'\b(?:showDialog|Get\.dialog|showGeneralDialog|showAdaptiveDialog)\b|\b(?:TvDialog|TvConfirmDialog|TvInputDialog|TvSelectDialog|TvMultiSelectDialog|TvMenuDialog)\(')
SHEET = re.compile(r'\b(?:showModalBottomSheet|Get\.bottomSheet|showBottomSheet)\b')
MENU = re.compile(r'\b(?:PopupMenuButton|showMenu|MenuAnchor|DropdownButton|DropdownMenu)\b')
TOAST = re.compile(r'\b(?:ToastUtil\.show|SmartDialog\.showToast|showSnackBar|Get\.snackbar|showToast)\b')
I18N = re.compile(r"""\bi18n\(\s*['"]([a-zA-Z0-9_]+)['"]""")
METHOD = re.compile(r'^\s*(?:static\s+)?(?:Future<[^>]*>|void|Widget|bool|[A-Z]\w*(?:<[^>]*>)?\??)\s+(\w+)\s*\(', re.M)
SKIP_KEYS = {'cancel', 'confirm', 'close', 'ok', 'done', 'save', 'delete', 'remove', 'retry', 'clear', 'reset', 'back'}
KINDS = (('对话框', DIALOG), ('底部面板', SHEET), ('菜单', MENU))
COMPONENT = re.compile(r'^class\s+(_?\w*?(Page|Screen|View|Dialog|Sheet|Panel|Overlay))\s+extends\s+', re.M)

V3 = [
    ('get/', None), ('gen/', None),
    ('main.dart', 'U.1a'), ('plugins/utils.dart', 'U.1d'), ('plugins/update.dart', 'U.3d'), ('core/iptv/', 'U.9'),
    ('common/base/desktop_components.dart', 'U.13'), ('common/global/platform/', 'U.13'),
    ('common/widgets/adaptive_refresh_rate_scope.dart', 'U.2i'),
    ('common/widgets/common_appbar_actions.dart', 'U.3a'), ('common/widgets/menu_button.dart', 'U.3a'),
    ('common/widgets/search_button.dart', 'U.3a'),
    ('common/widgets/download_apk_dialog.dart', 'U.3d'), ('common/widgets/download_directory_dialog.dart', 'U.3d'),
    ('common/widgets/share_command_import_dialog.dart', 'U.3d'),
    ('common/widgets/room_card', 'U.4a'),
    ('common/', 'U.1c'),
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
    ('modules/live_play/dialogs/', 'U.2f'), ('modules/live_play/widgets/local_interaction/', 'U.2k'),
    ('modules/live_play/widgets/placeholder/', 'U.2g'), ('modules/live_play/widgets/video_player/playback_failure_overlay.dart', 'U.2g'),
    ('modules/live_play/widgets/video_player/video_loading.dart', 'U.2g'), ('modules/live_play/widgets/video_player/iptv_', 'U.2g'),
    ('player/utils/pip_window_widget.dart', 'U.2j'),
    ('modules/live_play/', 'U.2a'), ('player/', 'U.2a'),
]

# Single popups that live in a shared file but belong to another task:
# (file, enclosing method or class) -> task. Only the item list uses it.
ITEM_TASK = {
    ('v3:plugins/utils.dart', '_showExitDialog'): 'U.13',
    ('v3:plugins/utils.dart', '_ExitDecisionDialog'): 'U.13',
}

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


def load_zh(root):
    path = os.path.join(root, 'assets', 'translations', 'zh.json')
    try:
        import json
        return json.load(open(path, encoding='utf-8'))
    except (OSError, ValueError):
        return {}


def title_near(text, start, zh, span=2400):
    """The first meaningful translated string after [start]."""
    for key in I18N.findall(text[start:start + span]):
        if key not in SKIP_KEYS and key in zh:
            return zh[key]
    return ''


def method_at(text, pos):
    names = [m.group(1) for m in METHOD.finditer(text[:pos])]
    names = [n for n in names if n not in ('build', 'if', 'switch', 'return')]
    return names[-1] if names else ''


def items_of(rel, raw, text, label, zh):
    """Pages, popups and overlays in one file: (kind, name, line)."""
    found = []
    line = lambda pos: text.count('\n', 0, pos) + 1
    for m in COMPONENT.finditer(text):
        name, suffix = m.group(1), m.group(2)
        kind = {'Page': '页面', 'Screen': '页面', 'View': '页面'}.get(suffix, {'Dialog': '对话框', 'Sheet': '底部面板'}.get(suffix, '覆盖层'))
        if name.startswith('_') and kind == '页面':
            continue
        found.append((kind, f'{name}' + (f'（{t}）' if (t := title_near(text, m.start(), zh)) else ''), line(m.start()), name))
    if not (label == 'tv' and rel.startswith('core/dialog/')):
        for kind, rx in KINDS:
            for m in rx.finditer(text):
                where = method_at(text, m.start())
                t = title_near(text, m.start(), zh)
                found.append((kind, (t or where or '（无标题）') + (f' · `{where}`' if where and t else ''), line(m.start()), where))
    return sorted(found, key=lambda f: f[2])


def scan(lib, rules, label, zh=None):
    """Returns ({task: Counter}, {task: [files]}, [unassigned], {task: [items]})."""
    counts, files, missing = defaultdict(Counter), defaultdict(list), []
    items = defaultdict(list)
    # Directories in the file system's order, as when the inventory was first
    # made: the docs cite its item numbers (A11.3-11 ...), which follow it.
    for root, _, names in os.walk(lib):
        for name in sorted(names):
            if not name.endswith('.dart') or name.endswith(('.g.dart', '.freezed.dart')):
                continue
            path = os.path.join(root, name)
            rel = os.path.relpath(path, lib).replace(os.sep, '/')
            raw = open(path, encoding='utf-8', errors='ignore').read()
            text = re.sub(r'//[^\n]*', lambda m: ' ' * len(m.group(0)), raw)
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
            c['toasts'] += len(TOAST.findall(text))
            files[task].append(f'{label}:{rel}')
            for kind, name, ln, owner in items_of(rel, raw, text, label, zh or {}):
                items[ITEM_TASK.get((f'{label}:{rel}', owner), task)].append((kind, name, f'{label}:{rel}:{ln}'))
    return counts, files, missing, items


REGISTRY = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'docs', 'tasks.toml')


def new_ids(registry=REGISTRY):
    """{old U id: task id} from the `old` field of the task registry."""
    with open(registry, 'rb') as f:
        data = tomllib.load(f)
    ids = {}
    for task in data.get('task', []):
        for old in task.get('old', []):
            if old.startswith('U.'):
                if old in ids:
                    raise ValueError(f'{old} is the old id of both {ids[old]} and {task["id"]}')
                ids[old] = task['id']
    return ids


def renamed(table, ids, empty):
    """[table] ({old id: value}) under the new ids; an old id without one is an error."""
    unknown = sorted(k for k in table if k not in ids)
    if unknown:
        raise KeyError('no task has the old id ' + ', '.join(unknown))
    out = defaultdict(empty)
    for old, value in table.items():
        out[ids[old]] = value
    return out


def order(task):
    """Group letter, sub-category, number: A07.6 before A08.1, R02.1 after the A group."""
    m = re.fullmatch(r'([A-Z])(\d\d)\.(\d+)', task)
    return (m.group(1), int(m.group(2)), int(m.group(3)))


def commit(repo, ref='HEAD'):
    try:
        return subprocess.run(['git', '-C', repo, 'rev-parse', '--short=8', ref], capture_output=True, text=True,
                              check=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return '?'


def checkout(repo, ref, into):
    """The `lib/` and translations of [ref] in [repo], unpacked under [into]."""
    archive = subprocess.run(['git', '-C', repo, 'archive', ref, 'lib', 'assets/translations'], capture_output=True,
                             check=True).stdout
    path = os.path.join(into, 'tv.tar')
    with open(path, 'wb') as f:
        f.write(archive)
    with tarfile.open(path) as tar:
        tar.extractall(into, filter='data')
    return into


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--v3', default=os.path.expanduser('~/ref/v3ref'))
    ap.add_argument('--tv', default=os.path.expanduser('~/ref/pure_live_TV'))
    ap.add_argument('--tv-ref')
    ap.add_argument('--files', action='store_true')
    ap.add_argument('--items', action='store_true')
    args = ap.parse_args()
    counts, files, missing, items = defaultdict(Counter), defaultdict(list), [], defaultdict(list)
    # Next to the TV repository: the same file system lists directories in the same order.
    tmp = tempfile.TemporaryDirectory(dir=os.path.dirname(os.path.abspath(args.tv)))
    tv = checkout(args.tv, args.tv_ref, tmp.name) if args.tv_ref else args.tv
    versions = f'v3 `{commit(args.v3)}`（`v3.2.11`），pure_live_TV `{commit(args.tv, args.tv_ref or "HEAD")}`'
    for root, rules, label in ((args.v3, V3, 'v3'), (tv, TV, 'tv')):
        c, f, m, it = scan(os.path.join(root, 'lib'), rules, label, load_zh(root))
        for k, v in c.items():
            counts[k].update(v)
        for k, v in f.items():
            files[k] += v
        for k, v in it.items():
            items[k] += v
        missing += m
    ids = new_ids()
    counts, files, items = renamed(counts, ids, Counter), renamed(files, ids, list), renamed(items, ids, list)
    if args.items:
        print('# 界面清单（逐项，生成）\n\n由 `tools/ui/inventory.py --items` 生成，不要手改。每个任务列出 v3（`v3.2.11`）和 pure_live_TV 代码里的页面、对话框、底部面板、菜单和覆盖层，名称取代码旁边的中文文案（取不到时用方法名或类名），位置是“文件:行”。同一个弹窗可能在两处出现（组件类和调用处），设计时按实际界面合并。\n')
        print(f'扫描的提交：{versions}。\n')
        kinds = ('页面', '对话框', '底部面板', '菜单', '覆盖层')
        print('| 任务 | ' + ' | '.join(kinds) + ' | 提示条 |')
        print('|---|' + '---:|' * (len(kinds) + 1))
        for task in sorted(items, key=order):
            n = Counter(k for k, _, _ in items[task])
            print(f'| [{task}](#{task.lower().replace(".", "")}) | ' + ' | '.join(str(n[k]) for k in kinds) + f' | {counts[task]["toasts"]} |')
        print()
        for task in sorted(items, key=order):
            print(f'## {task}\n')
            print('| 编号 | 类型 | 名称 | 位置 |')
            print('|---|---|---|---|')
            for i, (kind, name, where) in enumerate(items[task], 1):
                print(f'| {task}-{i:02d} | {kind} | {name} | `{where}` |')
            print()
    elif args.files:
        print('# 界面文件对照（生成）\n\n由 `tools/ui/inventory.py --files` 生成，不要手改。`v3:` 是 `v3.2.11` 的 `lib/`，`tv:` 是 pure_live_TV 的 `lib/`。\n')
        print(f'扫描的提交：{versions}。\n')
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
