"""U.3a phone home mockups: v3 restored and the new design.

v3 (tag v3.2.11):
  lib/modules/home/home_page.dart        shell, 680 split (LayoutBuilder :232)
  lib/modules/home/mobile_view.dart      NavigationBar, four destinations (:28-64)
  lib/common/widgets/menu_button.dart    top-left menu (:15-62)
  lib/common/widgets/common_appbar_actions.dart  top-right menu (:15-157)
  lib/modules/favorite/favorite_page.dart  the first tab's bar (:21-38)
  lib/recorder/pages/recorder/recorder_page.dart  record tab bar (:35-53)
Defaults: ColorScheme.fromSeed(Colors.blue); font sizes 12/13/14/15/20.

U.3b imports this file for the shared pieces (cards, menus, page bodies).
    python3 docs/ui/compare/U.3a/src/gen.py && python3 tools/ui/mock/render.py docs/ui/compare/U.3a/src/ --annotate"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))

CSS = '''
.ph{display:flex;flex-direction:column}
.main{position:relative;flex:1;min-height:0;display:flex;flex-direction:column;overflow:hidden}
.appbar{flex:none}
.lead{width:56px;height:56px;display:grid;place-items:center;flex:none}
.act{display:flex;align-items:center;flex:none}
.ttl{flex:1;min-width:0;text-align:center;font-size:20px;font-weight:600}
/* favourites status tabs in the title (TabBar, fill) */
.st{flex:1;min-width:0;display:flex;height:46px;margin:0 16px}
.st div{flex:1;display:flex;align-items:center;justify-content:center;font-size:15px;color:rgba(67,71,78,.8);position:relative;white-space:nowrap}
.st .on{color:var(--primary);font-weight:600}
.st .on::after{content:'';position:absolute;bottom:0;left:50%;transform:translateX(-50%);width:var(--iw,46px);height:3px;border-radius:3px 3px 0 0;background:var(--primary)}
/* platform tabs (ScrollableTabBar, scrollable) */
.pt{height:46px;display:flex;flex:none;overflow:hidden;white-space:nowrap}
.pt div{padding:0 16px;display:flex;align-items:center;font-size:15px;color:rgba(67,71,78,.8);position:relative;flex:none}
.pt .on{color:var(--primary);font-weight:600}
.pt .on::after{content:'';position:absolute;bottom:0;left:16px;right:16px;height:2px;background:var(--primary)}
/* room grid (RoomGridView dense, RoomCard dense) */
.grid{display:grid;gap:6px;padding:12px;align-content:start}
.card{background:#fff;border-radius:20px;overflow:hidden}
.cov{position:relative;aspect-ratio:16/9;border-radius:20px;background:#eee center/cover}
.pb{position:absolute;left:8px;top:8px;padding:3px 6px;border-radius:8px;background:rgba(0,0,0,.58);color:#fff;font:700 10px/1.2 'Geist','Noto Sans SC'}
.aud{position:absolute;right:8px;bottom:8px;display:flex;align-items:center;gap:4px;padding:4px 6px;border-radius:10px;background:rgba(0,0,0,.48);color:#fff;font:700 11px/1 'Geist','Noto Sans SC'}
.aud .mr{font-size:14px}
.tile{display:flex;align-items:center;gap:8px;padding:6px 10px 8px}
.tile .a{width:34px;height:34px;border-radius:17px;background:center/cover;flex:none}
.tile .x{min-width:0;flex:1}
.tile .t{font-size:13px;font-weight:600;color:rgba(0,0,0,.87);white-space:nowrap;overflow:hidden;text-overflow:ellipsis;line-height:18px}
.tile .n{font-size:12px;font-weight:500;color:#616161;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;line-height:17px;margin-top:2px}
[data-theme=dark] .card{background:#212121}[data-theme=dark] .tile .t{color:#fff}[data-theme=dark] .tile .n{color:#BDBDBD}
/* bottom NavigationBar (M3 defaults: 80 high, surfaceContainer) */
.nb{flex:none;height:100px;padding-bottom:20px;background:var(--scc);display:flex;position:relative}
.nd{flex:1;display:flex;flex-direction:column;align-items:center;padding-top:12px;gap:4px}
.nd .ind{width:64px;height:32px;border-radius:16px;display:grid;place-items:center;color:var(--onv)}
.nd .l{font-size:12px;font-weight:500;color:var(--onv);line-height:16px}
.nd.on .ind{background:var(--sc);color:var(--osc)}.nd.on .l{color:var(--on)}
/* v3 popup menus (M3 PopupMenu: surfaceContainer, items 48 high, width steps of 56) */
.pm{position:absolute;z-index:21;background:var(--scc);box-shadow:0 2px 6px rgba(0,0,0,.18),0 1px 2px rgba(0,0,0,.12);padding:8px 0}
.pm .it{height:48px;display:flex;align-items:center;gap:12px;white-space:nowrap}
/* recorder tab body */
.rs{display:grid;grid-template-columns:repeat(3,1fr);gap:6px;padding:9px 13px}
.rs div{height:48px;border-radius:11px;background:rgba(225,226,232,.46);display:grid;place-items:center;font-size:12px;font-weight:500;color:var(--onv)}
.rs .on{background:var(--pc);color:var(--opc);font-weight:700}
.empty{flex:1;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:0}
.empty .c{width:92px;height:92px;border-radius:46px;background:rgba(54,97,142,.08);display:grid;place-items:center;color:var(--primary);margin-bottom:24px}
.empty .h{font-size:15px;font-weight:700}.empty .s{font-size:13px;color:var(--onv);margin-top:8px}
.tip{font-family:'Noto Sans SC'}
'''

mr = lambda n, s=24: f'<span class="mr" style="font-size:{s}px">{n}</span>'
mi = lambda n, s=24: f'<span class="mi" style="font-size:{s}px">{n}</span>'
rx = lambda c, s=24: f'<span class="rx" style="font-size:{s}px">&#x{c};</span>'
ci = lambda c, s=24: f'<span class="ci" style="font-size:{s}px">&#x{c};</span>'

# Remix code points (remixicon 4.9.3)
RX = dict(heart_l='ee0b', heart_f='ee0a', fire_l='ed33', fire_f='ed32', apps2_l='ea42', apps2_f='ea41',
          shapes_l='f3da', shapes_f='f3d9', dl2_l='ec54', dl2_f='ec53', grid_l='ee90', link='eeb2',
          menu_search='f3d0', search='f0d1', settings5='f0ea', info='ee59', history='ee17', cloud='eb9d',
          more2='ef76', folder_video='f3cc', menu2_f='ef31')
CI_SEARCH = 'e804'


def attrs(n=None, tag=None, at=None):
    return (f' data-n="{n}"' if n else '') + (f' data-tag="{tag}"' if tag else '') + (f' data-at="{at}"' if at else '')


def ib(inner, n=None, tag=None, at=None, cls='ib'):
    return f'<div class="{cls}"{attrs(n, tag, at)}>{inner}</div>'


ROOMS = [
    ('1', '深夜电台 · 点歌接龙到天亮', '晚风', 'BILIBILI', 'people_alt', '1.2万', '65'),
    ('225', '王者上分，今晚冲国服', '一只小熊', 'HUYA', 'whatshot', '86.4万', '111'),
    ('237', '川西自驾第 3 天，雪山日出', '路过的风', 'DOUYU', 'whatshot', '34.1万', '133'),
    ('250', '手工皮具，慢慢做一只钱包', '清欢', 'DOUYIN', 'people_alt', '2301', '169'),
    ('287', '钢琴即兴，弹你点的歌', '月亮邮差', 'BILIBILI', 'people_alt', '5620', '183'),
    ('292', '深夜食堂，煮一碗面', '橘子汽水', 'KUAISHOU', 'people_alt', '1.1万', '206'),
    ('304', '围棋复盘：今天的三局', '不吃香菜', 'BILIBILI', 'people_alt', '3488', '219'),
    ('319', '城市夜跑 10 公里', '星河长明', 'DOUYU', 'whatshot', '12.7万', '274'),
]


def card(room):
    cover, title, nick, plat, icon, count, av = room
    return (f'<div class="card"><div class="cov" style="background-image:url(.cache/img/{cover}.jpg)">'
            f'<span class="pb">{plat}</span><span class="aud">{mr(icon, 14)}{count}</span></div>'
            f'<div class="tile"><span class="a" style="background-image:url(.cache/img/{av}.jpg)"></span>'
            f'<div class="x"><div class="t">{title}</div><div class="n">{nick}</div></div></div></div>')


def grid(cols, rooms=ROOMS):
    return f'<div class="grid" style="grid-template-columns:repeat({cols},1fr)">' + ''.join(card(r) for r in rooms) + '</div>'


def status_bar():
    return ('<div class="status"><span>21:36</span><span class="r">' + mi('signal_cellular_alt', 16) + mi('wifi', 16)
            + mi('battery_full', 16) + '</span></div>')


def page(w, h, scale, body, frame='ph', extra=''):
    style = '' if frame == 'ph' else f' style="--w:{w}px;--h:{h}px"'
    return (f'<!doctype html><html><head><meta charset="utf-8"><meta name="mock-size" content="{w}x{h}@{scale}">'
            f'<link rel="stylesheet" href="kit/kit.css"><style>{CSS}{extra}</style></head>'
            f'<body><div class="{frame}"{style}>{body}<div class="syn">示意图片</div></div></body></html>')


# ---------- page pieces shared by v3 and the new design ----------
STATUS_TABS = ['已开播', '录播', '未开播']           # favorite_page.dart:33-35
PLATFORMS = ['全部', '哔哩哔哩', '斗鱼', '虎牙', '抖音', '快手', '网易CC']


def status_tabs(margin=16):
    return (f'<div class="st" style="margin:0 {margin}px">' + ''.join(
        f'<div class="{"on" if i == 0 else ""}">{t}</div>' for i, t in enumerate(STATUS_TABS)) + '</div>')


def platform_tabs():
    return '<div class="pt">' + ''.join(f'<div class="{"on" if i == 0 else ""}">{p}</div>' for i, p in enumerate(PLATFORMS)) + '</div>'


def favorites_body(cols=2):
    return platform_tabs() + grid(cols)


RECORD_TABS = ['全部', '录制中', '等待开播', '排队中', '重连中', '处理中', '已完成', '失败', '已停止']


def record_body(cols=3):
    sel = '<div class="rs" style="grid-template-columns:repeat(%d,1fr)">' % cols + ''.join(
        f'<div class="{"on" if i == 0 else ""}">{t}</div>' for i, t in enumerate(RECORD_TABS)) + '</div>'
    return (sel + '<hr><div class="empty"><div class="c">' + mr('video_collection', 42) + '</div>'
            '<div class="h">暂无录制任务</div><div class="s">添加直播间后将在这里显示</div></div>')


# ---------- navigation ----------
def nav_items(areas_icon='apps2'):
    a = RX[areas_icon + '_l'], RX[areas_icon + '_f']
    return [('关注', RX['heart_l'], RX['heart_f']), ('热门', RX['fire_l'], RX['fire_f']),
            ('分区', a[0], a[1]), ('录制中心', RX['dl2_l'], RX['dl2_f'])]


def nav_bar(selected=0, areas_icon='apps2', n0=None):
    out = ''
    for i, (label, line, fill) in enumerate(nav_items(areas_icon)):
        n = (n0 + i) if n0 else None
        tag = 'chg' if (areas_icon != 'apps2' and i == 2) else 'keep'
        out += (f'<div class="nd{" on" if i == selected else ""}"{attrs(n, tag if n else None)}><div class="ind">'
                + rx(fill if i == selected else line) + f'</div><div class="l">{label}</div></div>')
    return f'<div class="nb">{out}<div class="gesture"></div></div>'


# ---------- top bars ----------
def v3_bar_favorites():
    return ('<div class="appbar"><div class="lead">' + mr('menu') + '</div>' + status_tabs()
            + '<div class="act">' + ib(rx(RX['menu_search'])) + '<div style="width:4px"></div></div></div>')


def v3_bar_record():
    return ('<div class="appbar"><div class="lead">' + mr('menu') + '</div><div class="ttl">录制中心</div>'
            '<div class="act">' + ib(rx(RX['folder_video'], 22)) + ib(rx(RX['settings5'], 22)) + '<div style="width:8px"></div></div></div>')


def v4_actions(n=True):
    """Search (one tap) and the "more" menu: the same pair on every home tab."""
    return (ib(ci(CI_SEARCH), 2 if n else None, 'add' if n else None) + ib(rx(RX['more2']), 3 if n else None)
            + '<div style="width:4px"></div>')


def v4_bar_favorites(n=True):
    return ('<div class="appbar"><div class="lead"' + attrs(1 if n else None, 'keep' if n else None) + '>' + mr('menu') + '</div>'
            + status_tabs(16) + '<div class="act">' + v4_actions(n) + '</div></div>')


def v4_bar_record(n=False):
    return ('<div class="appbar"><div class="lead"' + attrs(1 if n else None, 'keep' if n else None) + '>' + mr('menu')
            + '</div><div class="ttl" style="text-align:left;padding-left:41px">录制中心</div>'
            '<div class="act">' + ib(rx(RX['folder_video'], 22)) + ib(rx(RX['settings5'], 22))
            + (ib(ci(CI_SEARCH), 2, 'add') + ib(rx(RX['more2']), 3, 'add') if n else v4_actions(False)) + '</div></div>')


# ---------- menus ----------
def v3_menu_left(left=12, top=0, windows=False):
    """menu_button.dart: shape radius 8, offset (12, 0), items padding 12,
    icon 24 (onSurfaceVariant), text labelMedium = 12."""
    items = [(RX['settings5'], '设置'), (RX['info'], '关于'), (RX['history'], '历史记录'), (RX['cloud'], '备份与恢复')]
    rows = ''.join(f'<div class="it" style="padding:0 12px"><span style="color:var(--onv)">{rx(c)}</span>'
                   f'<span style="font-size:12px;font-weight:500">{t}</span></div>' for c, t in items)
    if windows:
        rows += ('<div class="it" style="padding:0 12px"><span style="color:var(--onv)">' + mi('add_to_photos')
                 + '</span><span style="font-size:12px;font-weight:500">新建独立播放窗口</span></div>')
    return f'<div class="pm" style="left:{left}px;top:{top}px;width:168px;border-radius:8px">{rows}</div>'


def v3_menu_right(left=217, top=6, multiview=True):
    """common_appbar_actions.dart: radius 14, offset (0, 10), padding 14,
    icon 20 in the primary colour, text t14."""
    items = [(RX['search'], '搜索直播'), (RX['link'], '链接访问')] + ([(RX['grid_l'], '多画面')] if multiview else [])
    rows = ''.join(f'<div class="it" style="padding:0 14px"><span style="color:var(--primary)">{rx(c, 20)}</span>'
                   f'<span style="font-size:14px">{t}</span></div>' for c, t in items)
    return f'<div class="pm" style="left:{left}px;top:{top}px;width:168px;border-radius:14px">{rows}</div>'


def menu(items, left=None, right=None, top=0, width=None, n0=None):
    """The one small menu (U.2f): radius 8, 48 rows, icon 24, text 14."""
    pos = (f'left:{left}px;' if left is not None else '') + (f'right:{right}px;' if right is not None else '')
    rows = ''
    for i, (icon, text) in enumerate(items):
        if icon == '-':
            rows += '<div class="sep"></div>'
            continue
        rows += f'<div class="it"><span style="flex:none;color:var(--onv)">{icon}</span><span>{text}</span></div>'
    w = f'width:{width}px;' if width else ''
    return f'<div class="menu" style="{pos}top:{top}px;{w}">{rows}</div>'


V4_LEFT = [(rx(RX['settings5']), '设置'), (rx(RX['info']), '关于'), (rx(RX['cloud']), '备份与恢复')]
V4_MORE = [(rx(RX['history']), '历史记录'), (rx(RX['link']), '链接解析'), (rx(RX['grid_l']), '多画面')]


# ---------- pages ----------
def phone(bar, body, nav):
    return page(393, 852, 3, status_bar() + bar + f'<div class="main">{body}</div>' + nav)


def build():
    out = {}
    # v3
    out['v3-home'] = phone(v3_bar_favorites(), favorites_body(), nav_bar(0))
    out['v3-menu'] = phone(v3_bar_favorites(), favorites_body() + v3_menu_left(), nav_bar(0))
    out['v3-search-menu'] = phone(v3_bar_favorites(), favorites_body() + v3_menu_right(), nav_bar(0))
    out['v3-record-tab'] = phone(v3_bar_record(), record_body(), nav_bar(3))
    # new design
    out['v4-home'] = phone(v4_bar_favorites(), favorites_body(), nav_bar(0, 'shapes', n0=4))
    out['v4-menu'] = phone(v4_bar_favorites(False), favorites_body() + menu(V4_LEFT, left=12, top=0, width=180), nav_bar(0, 'shapes'))
    out['v4-more-menu'] = phone(v4_bar_favorites(False), favorites_body() + menu(V4_MORE, right=8, top=0, width=180), nav_bar(0, 'shapes'))
    out['v4-record-tab'] = phone(v4_bar_record(True), record_body(), nav_bar(3, 'shapes'))
    return out


if __name__ == '__main__':
    pages = build()
    for name, html in pages.items():
        open(os.path.join(HERE, name + '.html'), 'w', encoding='utf-8').write(html)
    print(len(pages), 'pages')
