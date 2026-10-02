"""U.17b macOS: how the confirmed wide screens look in a macOS window.

Only what the platform needs changes; the screens come from the other tasks'
generators, which this file runs for their pieces (their own page writes are
discarded):
  U.3a/src/gen.py, U.3b/src/gen.py  wide home (rail, favourites)
  U.2d/src/gen.py  wide live room on the 16:9 frame
  U.2c/src/gen.py  fullscreen controls (desktop)

v3 (tag v3.2.11) on macOS, from code:
  common/global/platform/desktop_manager.dart:57-64 (TitleBarStyle.hidden: the
      three window buttons stay at the standard place over the app),
      :85-92 (hudWindow blur), :121-137 (custom title bar on Windows only),
      :139-155 + desktop_tray_service.dart:17-63 (tray: colour icon, left click
      focuses the window, right click opens 隐藏窗口 / 退出应用),
      :729 (onWindowLeaveFullScreen does nothing)
  plugins/utils.dart:97-108, :242-385 (close button -> 提示 / 确定要退出吗？ /
      不再询问 / 最小化 / 退出应用; minimise goes to the Dock)
  macos/Runner/Base.lproj/MainMenu.xib (Flutter's English template menus;
      Preferences… has no action), macos/Runner/AppDelegate.swift:6
  video_controller_panel.dart:52-61, :1571-1573 (no PiP, no volume slider, no
      window fullscreen on macOS)
Window 1280x800; buttons 12 across, 20 apart: standard title bar at 8/8,
unified (52-56 high toolbar row) at 20 and centred.

    python3 docs/ui/compare/U.17b/src/gen.py
    python3 tools/ui/mock/render.py docs/ui/compare/U.17b/src/ --annotate
"""
import builtins
import io
import os
import re
import sys
import types

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
COMPARE = os.path.normpath(os.path.join(HERE, '..', '..'))


def load(task):
    """Runs another task's gen.py for its functions and CSS; its writes go nowhere."""
    path = os.path.join(COMPARE, task, 'src', 'gen.py')
    real_open = builtins.open

    def quiet_open(f, mode='r', *a, **k):
        return io.StringIO() if ('w' in mode or 'a' in mode) else real_open(f, mode, *a, **k)

    ns = {'__file__': path, '__name__': 'gen_' + task.replace('.', '_'), 'open': quiet_open, 'print': lambda *a, **k: None}
    exec(compile(real_open(path, encoding='utf-8').read(), path, 'exec'), ns)
    return types.SimpleNamespace(**ns)


A = load('U.3a')   # cards, menus
B = load('U.3b')   # wide home
D = load('U.2d')   # wide live room
C = load('U.2c')   # fullscreen controls
mr, mi, rx, ci = A.mr, A.mi, A.rx, A.ci
ICON = '../../../apps/pure_live/assets/icons/icon.png'
W, H = 1280, 800

CSS = '''
html,body{background:#0E1014}
.win.mac{border-radius:10px;box-shadow:inset 0 0 0 1px rgba(0,0,0,.25)}
.tl{position:absolute;z-index:72;display:flex;gap:8px}
.tl i{width:12px;height:12px;border-radius:6px;display:block}
.tl .c{background:#FF5F57;box-shadow:inset 0 0 0 .5px #E0443E}.tl .m{background:#FEBC2E;box-shadow:inset 0 0 0 .5px #DEA123}.tl .z{background:#28C840;box-shadow:inset 0 0 0 .5px #1AAB29}
.drag{position:absolute;z-index:9}
.capx{position:absolute;z-index:80;font:500 12px/1.45 'Noto Sans SC';padding:5px 9px;border-radius:7px;background:rgba(25,28,32,.82);color:#fff;max-width:420px}
.mac>.appbar{padding-left:72px}
/* ---------- screen, menu bar and menus (drawn by macOS; shown to place ours) ---------- */
.scr{position:relative;width:1280px;overflow:hidden;background:#3B4252 url(.cache/img/287.jpg) center/cover}
.mb{position:absolute;left:0;right:0;top:0;height:24px;z-index:50;display:flex;align-items:center;gap:2px;padding:0 10px;background:rgba(246,246,248,.96);color:#1D1D1F;font:400 13px/24px 'Noto Sans SC'}
.mb .sys{width:14px;height:14px;border-radius:4px;background:#1D1D1F;margin:0 12px 0 6px;flex:none}
.mb span{padding:0 9px;border-radius:5px;white-space:nowrap}
.mb .app{font-weight:700}.mb .on{background:rgba(0,0,0,.12)}
.mb .mbr{margin-left:auto;display:flex;align-items:center;gap:12px;padding-right:4px}
.mb .mbr span{padding:0}
.mb .bt{position:relative;width:22px;height:11px;border-radius:3px;border:1px solid #1D1D1F;padding:1.5px}.mb .bt i{display:block;height:100%;width:80%;border-radius:1.5px;background:#1D1D1F}
.ti{width:18px;height:18px;display:block;background:#1D1D1F;-webkit-mask:url(../../../apps/pure_live/assets/icons/icon.png) center/contain no-repeat;mask:url(../../../apps/pure_live/assets/icons/icon.png) center/contain no-repeat;position:relative}
.tic{width:18px;height:18px;display:block;background:url(../../../apps/pure_live/assets/icons/icon.png) center/contain no-repeat}
.tdot{position:absolute;right:-3px;bottom:-1px;width:7px;height:7px;border-radius:4px;background:#FF3B30;box-shadow:0 0 0 1.5px rgba(246,246,248,.96)}
.trayon{border-radius:5px;background:rgba(0,0,0,.12);padding:3px 6px !important}
.mm{position:absolute;z-index:60;min-width:230px;padding:5px;border-radius:8px;background:rgba(246,246,248,.98);box-shadow:0 0 0 .5px rgba(0,0,0,.25),0 10px 30px rgba(0,0,0,.28);color:#1D1D1F;font:400 13px/22px 'Noto Sans SC'}
.mm .i{display:flex;align-items:center;height:22px;padding:0 12px 0 20px;border-radius:4px;white-space:nowrap;gap:24px}
.mm .i span:first-child{flex:1}.mm .i b{font-weight:400;color:#8A8A8E;font-family:'Geist','Noto Sans SC'}
.mm .i.dis{color:#B0B0B5}.mm .i.hi{background:#0A64D6;color:#fff}.mm .i.hi b{color:rgba(255,255,255,.85)}
.mm .i{position:relative}.mm .i.ck::before{content:'✓';position:absolute;left:6px;font-size:12px}
.mm .s{height:1px;background:rgba(0,0,0,.12);margin:5px 10px}
.mm .i .ar{color:#8A8A8E}
.ttl{position:absolute;z-index:61;font:600 13px/20px 'Noto Sans SC';color:#1D1D1F;padding:0 9px;border-radius:5px;background:rgba(0,0,0,.12)}
.board{position:relative;width:1280px;background:#E7E9EC;padding:22px 24px 26px;display:grid;grid-template-columns:repeat(3,1fr);gap:22px 24px;align-items:start}
.board .col{position:relative}
.board .mm{position:relative;min-width:0}
.board h4{font:600 13px/20px 'Noto Sans SC';color:#1D1D1F;margin:0 0 6px 2px}
.board h4 small{font-weight:400;color:#6C6C70;margin-left:6px}
/* ---------- dialogs (the app's own dialog component) ---------- */
.mdlg{position:absolute;z-index:62;left:50%;top:50%;transform:translate(-50%,-50%);border-radius:28px;background:var(--sch);color:var(--on);box-shadow:0 12px 40px rgba(0,0,0,.25)}
.mdlg .h{padding:24px 24px 0;font-size:22px;line-height:28px}
.mdlg .b{padding:16px 24px 0;font-size:14px;line-height:1.6;color:var(--onv)}
.mdlg .q{padding:16px 24px 0;font-size:16px;font-weight:500}
.mdlg .dv{height:1px;background:var(--ov);margin:12px 24px 0}
.mdlg .cb{display:flex;align-items:center;justify-content:space-between;margin:0 24px;height:48px;font-size:14px;font-weight:500}
.mdlg .cb i{width:18px;height:18px;border-radius:2px;border:2px solid var(--onv);display:block}
.mdlg .a{display:flex;gap:8px;padding:24px 24px 24px}
.mdlg .a span{height:48px;padding:0 16px;border-radius:24px;display:flex;align-items:center;font-size:14px;font-weight:600;color:var(--primary)}
.mdlg .a .er{background:var(--error);color:#fff;padding:0 24px}
.cur{position:absolute;z-index:90;width:18px;height:26px}
.fsbar{position:absolute;left:0;right:0;top:24px;height:28px;z-index:49;background:rgba(236,236,238,.96);border-bottom:1px solid rgba(0,0,0,.12)}
'''
CURSOR = ('<svg class="cur" style="left:{x}px;top:{y}px" viewBox="0 0 18 26"><path d="M1 1 L1 21 L6 16.5 L9.5 24.5 L12.5 23 L9 15.2 L15.5 15.2 Z" '
          'fill="#000" stroke="#fff" stroke-width="1.3" stroke-linejoin="round"/></svg>')


def doc(w, h, scale, body, *css, crop=False):
    style = ''.join(css) + CSS
    return (f'<!doctype html><html><head><meta charset="utf-8"><meta name="mock-size" content="{w}x{h}@{scale}{" crop" if crop else ""}">'
            f'<link rel="stylesheet" href="kit/kit.css"><style>{style}</style></head><body>{body}</body></html>')


def strip_n(html):
    return re.sub(r' data-(n|tag|at)="[^"]*"', '', html)


def lights(x, y, n=False):
    a = ' data-n="1" data-tag="keep" data-at="bl"' if n else ''
    return f'<div class="tl" style="left:{x}px;top:{y}px"{a}><i class="c"></i><i class="m"></i><i class="z"></i></div>'


V3_LIGHTS = lights(8, 8)          # standard title bar (window_manager hidden style)


def window(body, extra='', css_root=''):
    return f'<div class="win mac" style="--w:{W}px;--h:{H}px;{css_root}">{body}{extra}</div>'


# ---------- home (U.3b) ----------
def home_v3():
    body = B.v3_rail(0) + '<div class="body">' + B.fav_page(4) + '</div>'
    cap = ('<div class="capx" style="left:96px;top:66px">v3：窗口按钮在标准位置，压在侧边栏的菜单按钮上'
           '（desktop_manager.dart:57-64；自绘标题栏只在 Windows，:121-137）</div>')
    return window(body, V3_LIGHTS + cap + '<div class="syn" style="left:auto;right:12px;top:auto;bottom:10px;transform:none">示意图片</div>')


def home_v4(n=False):
    rail = B.v4_rail(0, n=False)
    spacer = '<div style="height:44px;flex:none;align-self:stretch"' + '></div>'
    rail = rail.replace('<div class="rail">', '<div class="rail">' + spacer, 1)
    if n:
        rail = rail.replace('<div style="padding:12px 12px 8px">', '<div style="padding:12px 12px 8px" data-n="2" data-tag="chg" data-at="bl">', 1)
    body = rail + '<div class="body">' + B.fav_page(4) + '</div>'
    return window(body, lights(20, 22, n) + '<div class="syn" style="left:auto;right:12px;top:auto;bottom:10px;transform:none">示意图片</div>')


# ---------- live room (U.2d) ----------
def inner_of(page):
    m = re.search(r'<div class="win" style="[^"]*">(.*)<div class="syn"', page, re.S)
    return strip_n(m.group(1))


def room_v3():
    """v3 on macOS: U.2d's v3 wide room without PiP, the volume slider and
    window fullscreen (Windows only)."""
    body = inner_of(D.v3(W, H, 1.5, windows=True))
    for piece in (D.ib(D.ci('e806')), D.ib(D.mr('volume_up', 22)), D.ib(D.mr('unfold_more', 26))):
        body = body.replace(piece, '', 1)
    cap = '<div class="capx" style="left:96px;top:62px">v3：窗口按钮压在返回键和头像上</div>'
    return window(body, V3_LIGHTS + cap + '<div class="syn" style="left:auto;right:12px;top:auto;bottom:10px;transform:none">示意图片</div>')


def room_v4(n=False, recording=False):
    body = inner_of(D.v4(W, H, 1.5, windows=True, recording=recording, n=False))
    if n:
        body = body.replace('<div class="back">', '<div class="back" data-n="2" data-tag="chg">', 1)
        body = body.replace(D.ib(D.ci('e806'), None, 'ib vic'), D.ib(D.ci('e806'), 4, 'ib vic', 'add'), 1)
        body = body.replace('<div class="vvol">', '<div class="vvol" data-n="5" data-tag="add">', 1)
        body = body.replace(D.ib(D.mr('unfold_more', 26), None, 'ib vic'), D.ib(D.mr('unfold_more', 26), 6, 'ib vic', 'add'), 1)
    drag = '<div class="drag" style="left:300px;width:640px;top:0;height:56px"' + (' data-n="3" data-tag="add"' if n else '') + '></div>'
    return window(body, lights(20, 22, n) + drag + '<div class="syn" style="left:auto;right:12px;top:auto;bottom:10px;transform:none">示意图片</div>')


# ---------- menu bar ----------
def menu(items, left, top, width=None):
    rows = ''
    for it in items:
        if it == '-':
            rows += '<div class="s"></div>'
            continue
        label, key, *flags = it
        cls = 'i' + (' dis' if 'dis' in flags else '') + (' hi' if 'hi' in flags else '') + (' ck' if 'ck' in flags else '')
        right = f'<b>{key}</b>' if key not in ('', '>') else ('<b class="ar">›</b>' if key == '>' else '')
        rows += f'<div class="{cls}"><span>{label}</span>{right}</div>'
    w = f'width:{width}px;' if width else ''
    pos = f'left:{left}px;top:{top}px;' if left is not None else ''
    return f'<div class="mm" style="{pos}{w}">{rows}</div>'


def menubar(titles, open_idx=None, tray='', right_extra=''):
    t = ''.join(f'<span class="{"app" if i == 0 else ""}{" on" if i == open_idx else ""}">{x}</span>' for i, x in enumerate(titles))
    return (f'<div class="mb"><i class="sys"></i>{t}<div class="mbr">{tray}<span>' + mi('wifi', 16) + '</span><span class="bt"><i></i></span>'
            f'<span>10月1日 周三 21:36</span></div></div>')


V3_TITLES = ['纯粹直播', 'Edit', 'View', 'Window', 'Help']
V4_TITLES = ['纯粹直播', '文件', '编辑', '显示', '播放', '窗口', '帮助']
V3_APP = [('About 纯粹直播', ''), '-', ('Preferences…', '⌘,', 'dis'), '-', ('Services', '>'), '-',
          ('Hide 纯粹直播', '⌘H'), ('Hide Others', '⌥⌘H'), ('Show All', ''), '-', ('Quit 纯粹直播', '⌘Q')]
V4_APP = [('关于纯粹直播', ''), ('检查更新…', ''), '-', ('设置…', '⌘,', 'hi'), '-', ('服务', '>'), '-',
          ('隐藏纯粹直播', '⌘H'), ('隐藏其他', '⌥⌘H'), ('全部显示', ''), '-', ('退出纯粹直播', '⌘Q')]
V4_MENUS = [
    ('文件', '', [('链接解析…', '⌘L'), ('多画面', ''), '-', ('关闭窗口', '⌘W')]),
    ('编辑', '系统会在末尾加自动填充、听写、表情与符号', [('撤销', '⌘Z'), ('重做', '⇧⌘Z'), '-', ('剪切', '⌘X'), ('拷贝', '⌘C'), ('粘贴', '⌘V'), ('全选', '⌘A'), '-', ('搜索直播…', '⌘F')]),
    ('显示', '', [('关注', '⌘1', 'ck'), ('热门', '⌘2'), ('分区', '⌘3'), ('录制中心', '⌘4'), '-', ('历史记录', '⌘Y'), ('返回', '⌘['), '-', ('进入全屏幕', '⌃⌘F')]),
    ('播放', '在直播间里可用，其他页面变灰', [('暂停', '空格'), ('刷新', '⌘R'), '-', ('调高音量', '↑'), ('调低音量', '↓'), '-', ('显示弹幕', '', 'ck'), ('弹幕设置…', ''), ('纯音频', ''),
                                    '-', ('清晰度', '>'), ('线路', '>'), ('画面比例', '>'), '-', ('录制…', ''), ('小窗', ''), ('窗口内全屏', '')]),
    ('窗口', '系统的', [('最小化', '⌘M'), ('缩放', ''), '-', ('前置全部窗口', '')]),
    ('帮助', '', [('项目主页', ''), ('更新日志', '')]),
]


def screen_with_window(win_html, h, extra):
    """Top of the screen: the menu bar and the app window under it."""
    return f'<div class="scr" style="height:{h}px">{extra}<div style="position:absolute;left:70px;top:44px;z-index:1">{win_html}</div></div>'


def menubar_v3():
    win = home_v3().replace('v3：窗口按钮在标准位置', 'v3：窗口按钮在标准位置').replace('<div class="capx"', '<div class="capx" style="display:none"', 1)
    m = menubar(V3_TITLES, 0) + menu(V3_APP, 10, 25, 250)
    cap = ('<div class="capx" style="left:300px;top:40px;max-width:520px">v3：Flutter 模板的英文菜单（MainMenu.xib），只有应用名换成了“纯粹直播”；'
           '“Preferences… ⌘,”没有接功能，是灰的；Edit、View、Window、Help 里也没有应用自己的命令</div>')
    return doc(W, 420, 1.5, screen_with_window(win, 420, m + cap), A.CSS, B.CSS)


def menubar_v4():
    win = home_v4()
    m = menubar(V4_TITLES, 0) + menu(V4_APP, 10, 25, 250)
    cap = ('<div class="capx" style="left:300px;top:40px;max-width:520px">新：中文菜单；“设置… ⌘,”打开设置，“关于”“检查更新”在应用菜单里；'
           '隐藏、服务、退出照系统的标准位置和快捷键</div>')
    return doc(W, 420, 1.5, screen_with_window(win, 420, m + cap), A.CSS, B.CSS)


def menus_board():
    cols = ''
    for title, note, items in V4_MENUS:
        cols += (f'<div class="col"><h4>{title}<small>{note}</small></h4>' + menu(items, None, None) + '</div>')
    return doc(W, 900, 1.5, f'<div class="board">{cols}</div>', 'html,body{background:#E7E9EC !important}', crop=True)


# ---------- menu bar icon (tray) ----------
def tray(ver):
    if ver == 3:
        icon = '<span class="trayon"><i class="tic"></i></span>'
        m = menu([('隐藏窗口', ''), '-', ('退出应用', '')], 1010, 25, 170)
        cap = ('<div class="capx" style="left:620px;top:90px;max-width:380px">v3：彩色应用图标；左键只把窗口拉到前面，右键才出这个菜单'
               '（desktop_manager.dart:213-239，desktop_tray_service.dart:28-56）</div>')
    else:
        icon = '<span class="trayon"><i class="ti"><i class="tdot"></i></i></span>'
        m = menu([('正在录制 2 个直播间', '', 'dis'), ('录制中心…', ''), '-', ('隐藏窗口', ''), '-', ('退出纯粹直播', '⌘Q')], 1000, 25, 200)
        cap = ('<div class="capx" style="left:600px;top:90px;max-width:380px">新：单色图标（跟着菜单栏深浅变），录制中右下角一个红点；'
               '左键或右键都出菜单；录制中才有前两行</div>')
    body = f'<div class="scr" style="height:300px">{menubar(V4_TITLES if ver == 4 else V3_TITLES, None, icon)}{m}{cap}</div>'
    return doc(W, 300, 1.5, body)


# ---------- close and quit ----------
def close_v3():
    dlg = ('<div class="scrim" style="z-index:61"></div><div class="mdlg" style="width:468px"><div class="h">提示</div><div class="q">确定要退出吗？</div>'
           '<div class="dv"></div><div class="cb"><span>不再询问</span><i></i></div>'
           '<div class="a" style="justify-content:space-between"><span>最小化</span><span class="er">退出应用</span></div></div>')
    cap = ('<div class="capx" style="left:96px;top:62px;z-index:90">v3：点左上角红色的关闭按钮弹这个框（utils.dart:242-385）；'
           '“最小化”在 Mac 上是缩到程序坞；⌘Q 走系统退出，不弹框，录制中也直接退出</div>')
    return doc(W, H, 1.5, window(B.v3_rail(0) + '<div class="body">' + B.fav_page(4) + '</div>', V3_LIGHTS + dlg + cap), A.CSS, B.CSS)


def quit_v4():
    body = inner_of(D.v4(W, H, 1.5, windows=True, recording=True, n=False))
    dlg = ('<div class="scrim" style="z-index:61"></div><div class="mdlg" style="width:420px"><div class="h">要退出纯粹直播吗？</div>'
           '<div class="b">正在录制 2 个直播间，退出会停止录制，已经录下的部分会保存。</div>'
           '<div class="a" style="justify-content:flex-end"><span>取消</span><span class="er">退出</span></div></div>')
    cap = ('<div class="capx" style="left:96px;top:62px;z-index:90;max-width:520px">新：红色按钮和 ⌘W 只关窗口，应用留在程序坞里继续录制；'
           '⌘Q 或菜单“退出纯粹直播”才退出，有录制或开播自动录时先问这一句，没有就直接退出</div>')
    return doc(W, H, 1.5, window(body, lights(20, 22) + dlg + cap), D.CSS)


# ---------- full screen space ----------
def full_v4():
    page = strip_n(C.v4(W, H, 1.5, android=False))
    over = ('<div class="mb" style="z-index:70"><i class="sys"></i><span class="app">纯粹直播</span><span>文件</span><span>编辑</span><span>显示</span>'
            '<span>播放</span><span>窗口</span><span>帮助</span></div><div class="fsbar" style="z-index:69"></div>'
            '<div class="tl" style="left:12px;top:32px;z-index:72"><i class="c"></i><i class="m"></i><i class="z"></i></div>'
            + CURSOR.format(x=640, y=4) +
            '<div class="capx" style="left:400px;top:120px;max-width:480px;z-index:90">全屏空间：指针移到屏幕顶端，系统的菜单栏和窗口按钮从上面滑下来盖住上栏，移开后收起（系统行为）；'
            'Esc、⌃⌘F、绿色按钮、画面上的退出全屏都回到窗口，直播间同时退出全屏</div>')
    page = page.replace('</style>', CSS + '</style>', 1)
    i = page.rindex('</div></body>')
    return page[:i] + over + page[i:]


OUT = {
    'v3-mac-home': doc(W, H, 1.5, home_v3(), A.CSS, B.CSS),
    'v4-mac-home': doc(W, H, 1.5, home_v4(n=True), A.CSS, B.CSS),
    'v3-mac-room': doc(W, H, 1.5, room_v3(), D.CSS),
    'v4-mac-room': doc(W, H, 1.5, room_v4(n=True), D.CSS),
    'v3-mac-menu': menubar_v3(),
    'v4-mac-menu': menubar_v4(),
    'v4-mac-menus': menus_board(),
    'v3-mac-tray': tray(3),
    'v4-mac-tray': tray(4),
    'v3-mac-close': close_v3(),
    'v4-mac-quit': quit_v4(),
    'v4-mac-full': full_v4(),
}

if __name__ == '__main__':
    for name, html in OUT.items():
        open(os.path.join(HERE, name + '.html'), 'w', encoding='utf-8').write(html)
    print(len(OUT), 'pages')
