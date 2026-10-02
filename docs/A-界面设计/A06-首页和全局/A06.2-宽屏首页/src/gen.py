"""U.3b wide home mockups: v3 restored and the new design.

v3 (tag v3.2.11):
  lib/modules/home/tablet_view.dart   NavigationRail with the menu, multi-view,
                                      link, search and record actions (:95-170)
  lib/modules/home/home_page.dart     split above 680 (:232), record removed
                                      from the destinations (:237-239)
  lib/recorder/pages/recorder/recorder_page.dart  record opened as a page
Shared pieces (cards, menus, page bodies) come from ../../U.3a/src/gen.py.
    python3 docs/ui/compare/U.3b/src/gen.py && python3 tools/ui/mock/render.py docs/ui/compare/U.3b/src/ --annotate"""
import importlib.util
import os
import sys

sys.dont_write_bytecode = True

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location('u3a', os.path.join(HERE, '..', '..', 'U.3a', 'src', 'gen.py'))
A = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(A)
mr, mi, rx, ci, ib, attrs, RX = A.mr, A.mi, A.rx, A.ci, A.ib, A.attrs, A.RX

CSS = '''
.win{display:flex}
.rail{width:80px;flex:none;background:var(--surface);display:flex;flex-direction:column;align-items:center;overflow:hidden}
.vd{width:1px;flex:none;background:var(--ov)}
.body{flex:1;min-width:0;display:flex;flex-direction:column;position:relative;overflow:hidden}
.ra{width:48px;height:48px;display:grid;place-items:center;flex:none;border-radius:24px}
.rd{width:80px;display:flex;flex-direction:column;align-items:center;padding:4px 0 12px;gap:4px;flex:none}
.rd .ind{width:56px;height:32px;border-radius:16px;display:grid;place-items:center;color:var(--onv)}
.rd .l{font-size:12px;font-weight:500;line-height:16px;color:var(--on)}
.rd.on .ind{background:var(--sc);color:var(--osc)}
.rt{width:80px;display:flex;flex-direction:column;align-items:center;flex:none;padding-bottom:6px}
.rt .l{font-size:12px;line-height:16px;color:var(--onv);margin-top:-4px}
.rsep{width:40px;height:1px;background:var(--ov);margin:6px 0 14px;flex:none}
.hov{background:rgba(25,28,32,.08)}
.tipw{position:absolute;z-index:30;background:rgba(25,28,32,.9);color:#fff;font-size:12px;padding:6px 8px;border-radius:4px;white-space:nowrap}
'''


def page(w, h, scale, body):
    return (f'<!doctype html><html><head><meta charset="utf-8"><meta name="mock-size" content="{w}x{h}@{scale}">'
            f'<link rel="stylesheet" href="kit/kit.css"><style>{A.CSS}{CSS}</style></head>'
            f'<body><div class="win" style="--w:{w}px;--h:{h}px">{body}<div class="syn" style="left:auto;right:12px;top:auto;bottom:10px;transform:none">示意图片</div></div></body></html>')


def dest(label, line, fill, on=False, n=None, tag=None):
    return (f'<div class="rd{" on" if on else ""}"{attrs(n, tag, "tr" if n else None)}><div class="ind">' + rx(fill if on else line)
            + f'</div><div class="l">{label}</div></div>')


# ---------- v3 rail: tablet_view.dart:100-157 ----------
def v3_rail(selected=0, show_record=True, destinations=True):
    lead = ('<div style="padding:12px">' + ib(A.mr('menu'), cls='ra') + '</div>'
            + '<div style="padding:0 12px 12px">' + ib(rx(RX['grid_l']), cls='ra') + '</div>'
            + '<div style="padding:0 12px 12px">' + ib(rx(RX['link']), cls='ra') + '</div>'
            + '<div style="padding:0 12px 12px">' + ib(ci(A.CI_SEARCH), cls='ra') + '</div>'
            + ('<div style="padding:0 12px 12px">' + ib(rx(RX['dl2_l']), cls='ra') + '</div>' if show_record else ''))
    dests = ''
    if destinations:
        for i, (label, line, fill) in enumerate(A.nav_items('apps2')[:3]):
            dests += dest(label, line, fill, i == selected)
    return f'<div class="rail">{lead}<div style="height:8px"></div>{dests}</div><div class="vd"></div>'


# ---------- new rail ----------
def tool(icon, label, n=None, tag=None, hover=False):
    return (f'<div class="rt"{attrs(n, tag, "tr" if n else None)}>' + ib(icon, cls='ra' + (' hov' if hover else '')) + f'<div class="l">{label}</div></div>')


def v4_rail(selected=0, n=True, hover=None):
    N = (lambda k: k) if n else (lambda k: None)
    T = (lambda t: t) if n else (lambda t: None)
    tools = [(ci(A.CI_SEARCH), '搜索直播', 2, None), (rx(RX['history']), '历史记录', 3, 'add'),
             (rx(RX['link']), '链接解析', 4, None), (rx(RX['grid_l']), '多画面', 5, None)]
    out = '<div style="padding:12px 12px 8px"' + attrs(N(1), T('keep'), 'tr' if n else None) + '>' + ib(A.mr('menu'), cls='ra') + '</div>'
    for icon, label, k, tag in tools:
        out += tool(icon, label, N(k), T(tag), hover == k)
    out += '<div class="rsep"></div>'
    for i, (label, line, fill) in enumerate(A.nav_items('shapes')):
        tag = 'keep' if i < 2 else ('chg' if i == 2 else 'add')
        out += dest(label, line, fill, i == selected, N(6 + i), T(tag))
    return f'<div class="rail">{out}</div><div class="vd"></div>'


def fav_page(cols):
    """The favourites page as v3 draws it above 680: no menu buttons, the
    status tabs fill the whole title (favorite_page.dart:22-38)."""
    return ('<div class="appbar">' + A.status_tabs(16) + '</div>' + A.platform_tabs()
            + A.grid(cols, A.ROOMS + A.ROOMS[:4]))


def record_page(back, cols=9):
    lead = '<div class="lead">' + (A.mi('arrow_back') if back else '') + '</div>'
    bar = ('<div class="appbar">' + lead + '<div class="ttl">录制中心</div><div class="act">'
           + ib(rx(RX['folder_video'], 22)) + ib(rx(RX['settings5'], 22)) + '<div style="width:8px"></div></div></div>')
    return bar + A.record_body(cols)


def empty_menu_page():
    return ('<div class="empty"><div class="c" style="background:rgba(225,226,232,.15);border:1px solid rgba(54,97,142,.05)">'
            + rx(RX['menu2_f'], 42) + '</div><div class="h" style="font-size:15px;font-weight:600">尚未选择任何菜单</div>'
            '<div class="s" style="max-width:320px;text-align:center;line-height:1.5">请点击左上角菜单按钮，添加需要展示的功能菜单</div></div>')


def build():
    out = {}
    W, H, S = 1280, 800, 1.5
    out['v3-wide'] = page(W, H, S, v3_rail(0) + '<div class="body">' + fav_page(4) + '</div>')
    out['v4-wide'] = page(W, H, S, v4_rail(0) + '<div class="body">' + fav_page(4) + '</div>')
    # record centre: v3 pushes a full page over the rail; new design keeps it a destination
    out['v3-wide-record'] = page(W, H, S, '<div class="body">' + record_page(True) + '</div>')
    out['v4-wide-record'] = page(W, H, S, v4_rail(3, n=False) + '<div class="body">' + record_page(False) + '</div>')
    # v3 with only "record" chosen: an empty page
    out['v3-wide-empty'] = page(W, H, S, v3_rail(-1, destinations=False) + '<div class="body">' + empty_menu_page() + '</div>')
    # the menu: same component as the phone, opens under the button
    menu = A.menu(A.V4_LEFT + [(mi('add_to_photos'), '新建独立播放窗口')], left=28, top=60, width=220)
    out['v4-wide-menu'] = page(W, H, S, v4_rail(0, n=False) + '<div class="body">' + fav_page(4) + '</div>' + menu)
    # medium width 640: v3 still uses the phone layout, the new design the rail
    mw, mh = 640, 900
    out['v3-medium'] = A.page(mw, mh, 2, A.v3_bar_favorites() + '<div class="main">' + A.favorites_body(2)
                              + '</div>' + A.nav_bar(0), frame='win', extra='.win{display:flex;flex-direction:column}.syn{left:auto;right:12px;top:auto;bottom:110px;transform:none}')
    out['v4-medium'] = page(mw, mh, 2, v4_rail(0, n=False) + '<div class="body">' + fav_page(2) + '</div>')
    return out


if __name__ == '__main__':
    pages = build()
    for name, html in pages.items():
        open(os.path.join(HERE, name + '.html'), 'w', encoding='utf-8').write(html)
    print(len(pages), 'pages')
