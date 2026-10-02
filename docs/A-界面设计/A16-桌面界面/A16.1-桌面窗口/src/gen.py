"""U.13 desktop window (Windows, Linux): v3 restored and the new design.

v3 (tag v3.2.11):
  lib/common/global/platform/desktop_manager.dart
      DesktopManager.initialize :48-99   size from the setting, min 400x300, centred,
                                          TitleBarStyle.hidden, Mica (Windows) :78-83
      buildWithTitleBar :121-137          the title bar is drawn on Windows only
      tray :139-173, :185-239             click shows, right click opens the menu
      CustomTitleBar :263-381             32 high, splash gradient :270-280, dark = black
                                          :284-285, icon 16 + app name t13 w600 + [w x h]
                                          while tracking :480-490, buttons 46x32 icon 16
                                          remove / crop_square / close, close hover #E81123
  lib/common/global/platform/desktop_tray_service.dart :17-76   window item, separator, exit
  lib/plugins/utils.dart _showExitDialog :242-281, _ExitDecisionDialog :321-393,
      _minimizeOrHideDesktopWindow :96-108 (hide = gone from the taskbar)
  lib/common/services/settings/window_size_controller.dart :97-100 (1280x720, min 400x300)
  lib/common/widgets/menu_button.dart :56-61, live_play_menu_button.dart :186-207 (new window)
  lib/common/global/initialized.dart :126-128 (every instance makes its own tray)
  windows/runner/main.cpp :18 (every window is titled 纯粹直播); linux/my_application.cc :43-46
The window content (home page, rail) comes from ../../U.3b/src/gen.py.
    python3 docs/ui/compare/U.13/src/gen.py && python3 tools/ui/mock/render.py docs/ui/compare/U.13/src/ --annotate"""
import importlib.util
import os
import sys

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))


def _load(name, task):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, '..', '..', task, 'src', 'gen.py'))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


A = _load('u3a', 'U.3a')
B = _load('u3b', 'U.3b')
C = _load('u3c', 'U.3c')
D = _load('u3d', 'U.3d')
mr, mi, rx, ci, attrs = A.mr, A.mi, A.rx, A.ci, A.attrs
ICON = '../../../apps/pure_live/assets/icons/icon.png'

CSS = '''
.win.u-col{display:flex;flex-direction:column}
.u-main{flex:1;min-height:0;display:flex;position:relative;overflow:hidden}
/* title bar */
.u-tb{height:32px;flex:none;display:flex;align-items:center;position:relative;z-index:8}
.u-tb .l{flex:1;min-width:0;height:32px;display:flex;align-items:center;padding-left:12px}
.u-tb .app{display:flex;align-items:center;gap:6px;height:32px;padding:0 4px;white-space:nowrap}
.u-ico{width:16px;height:16px;background:url(%(icon)s) center/contain no-repeat;flex:none;display:inline-block}
.u-tb .nm{font-size:13px;font-weight:600}
.u-tb .sz{font-size:12px;opacity:.6;font-feature-settings:'tnum'}
.u-tb .room{font-size:13px;font-weight:400;opacity:.75}
.u-wb{width:46px;height:32px;display:grid;place-items:center;flex:none}
.u-wb .mi,.u-wb .mr{font-size:16px}
.u-tb.v3l{background:var(--surface);color:#000}.u-tb.v3l .u-wb.hv{background:rgba(54,97,142,.08)}
.u-tb.v3d{background:#000;color:rgba(255,255,255,.75)}.u-tb.v3d .u-wb.hv{background:rgba(255,255,255,.08)}
.u-tb.v3s{background:linear-gradient(135deg,#E8FAFC,#C8F1F5 50%%,#9BE7F0);color:#000}
.u-tb.v4{background:var(--surface);color:var(--on)}.u-tb.v4 .u-wb.hv{background:rgba(127,127,127,.14)}
.u-wb.x.hv{background:#E81123 !important;color:#fff}
.u-tb.v4 .app.hv{background:rgba(127,127,127,.14);border-radius:4px}
/* a whole window inside a picture */
.u-w{position:absolute;display:flex;flex-direction:column;overflow:hidden;background:var(--surface);box-shadow:0 12px 40px rgba(0,0,0,.35),0 0 0 1px rgba(0,0,0,.12)}
.u-w.gn{border-radius:12px 12px 0 0}
/* desktop surroundings (illustration) */
.u-desk{position:absolute;inset:0;background:url(.cache/img/287.jpg) center/cover}
.u-task{position:absolute;left:0;right:0;bottom:0;height:48px;background:rgba(28,28,30,.9);display:flex;align-items:center;justify-content:center;gap:6px;z-index:30;color:#fff}
.u-task .g{width:40px;height:40px;border-radius:6px;display:grid;place-items:center;position:relative}
.u-task .g i{width:26px;height:26px;border-radius:6px;background:rgba(255,255,255,.5);display:block}
.u-task .g .u-ico{width:26px;height:26px}
.u-task .g.hv{background:rgba(255,255,255,.12)}
.u-task .g u{position:absolute;bottom:2px;left:50%%;transform:translateX(-50%%);height:3px;width:6px;border-radius:2px;background:rgba(255,255,255,.6)}
.u-task .g u.two{width:16px;background:#4CC2FF}
.u-tray{position:absolute;right:6px;top:0;height:48px;display:flex;align-items:center;gap:2px}
.u-tray .t{width:28px;height:40px;display:grid;place-items:center;border-radius:4px;color:#fff}
.u-tray .t.hv{background:rgba(255,255,255,.14)}
.u-tray .t .mi,.u-tray .t .mr{font-size:17px}
.u-tray .ime{font-size:13px;width:24px}
.u-tray .clk{font:12px/16px 'Geist','Noto Sans SC';text-align:right;padding:0 6px 0 8px;font-feature-settings:'tnum'}
.u-gtop{position:absolute;left:0;right:0;top:0;height:28px;background:#000;color:#fff;display:flex;align-items:center;font-size:13px;font-weight:600;z-index:30;padding:0 12px}
.u-gtop .c{position:absolute;left:50%%;transform:translateX(-50%%)}
.u-gtop .r{margin-left:auto;display:flex;gap:10px;align-items:center}
.u-gtop .r .mi,.u-gtop .r .mr{font-size:16px}
/* native menus and tooltips (drawn by the system) */
.u-nm{position:absolute;z-index:40;background:#F9F9F9;color:#1A1A1A;border-radius:8px;padding:4px;min-width:180px;box-shadow:0 8px 20px rgba(0,0,0,.22),0 0 0 1px rgba(0,0,0,.08);font-size:14px}
.u-nm .i{height:34px;display:flex;align-items:center;gap:10px;padding:0 12px;border-radius:4px;white-space:nowrap}
.u-nm .i.hv{background:rgba(0,0,0,.06)}
.u-nm .i.dis{color:rgba(0,0,0,.42)}
.u-nm .i .k{margin-left:auto;padding-left:24px;color:rgba(0,0,0,.55);font-size:13px}
.u-nm .i .g{width:16px;display:grid;place-items:center;flex:none}
.u-nm .s{height:1px;background:rgba(0,0,0,.09);margin:4px 2px}
.u-nm .rec{width:8px;height:8px;border-radius:4px;background:var(--rec);display:block}
.u-tt{position:absolute;z-index:40;background:#F9F9F9;color:#1A1A1A;font-size:12px;padding:6px 9px;border-radius:5px;box-shadow:0 4px 12px rgba(0,0,0,.2),0 0 0 1px rgba(0,0,0,.08);white-space:nowrap}
.u-thumb{position:absolute;z-index:40;display:flex;gap:8px;padding:8px;border-radius:8px;background:rgba(44,44,46,.96);box-shadow:0 8px 24px rgba(0,0,0,.35)}
.u-thumb .c{width:200px;color:#fff;font-size:12px}
.u-thumb .c .h{display:flex;align-items:center;gap:6px;height:24px;white-space:nowrap;overflow:hidden}
.u-thumb .c .p{height:118px;border-radius:4px;background:#ddd center/cover;margin-top:4px}
.u-cap{position:absolute;z-index:44;font:500 12px 'Noto Sans SC';padding:4px 8px;border-radius:5px;background:rgba(0,0,0,.62);color:#fff;white-space:nowrap}
/* the simplified live room in a new window */
.u-room{flex:1;min-height:0;display:flex}
.u-room .vid{flex:1;min-width:0;display:flex;flex-direction:column;background:var(--surface)}
.u-room .pic{aspect-ratio:16/9;background:#000 url(.cache/img/158.jpg) center 55%%/cover;position:relative}
.u-room .chat{width:300px;flex:none;border-left:1px solid var(--ov);background:var(--surface);padding-top:8px;overflow:hidden}
.u-room .hd{display:flex;align-items:center;gap:10px;padding:12px 16px}
.u-room .hd .n{font-size:15px;font-weight:600}.u-room .hd .s{font-size:12px;color:var(--onv)}
/* rows on the state sheets */
.u-sheet{position:absolute;inset:0;background:var(--scc)}
.u-lab{font-size:13px;line-height:18px;color:var(--on);margin:18px 0 6px}
.u-lab small{color:var(--onv);font-size:12px;margin-left:8px}
.u-strip{position:relative;border-radius:6px;overflow:hidden;box-shadow:0 0 0 1px rgba(0,0,0,.12)}
.u-strip .u-pgb{height:30px}
/* the close dialog */
.u-ov{position:absolute;inset:0;z-index:20;display:flex;align-items:center;justify-content:center;background:rgba(0,0,0,.54)}
.u-d3 .q{font-size:15px;font-weight:500;line-height:22px}
.u-d3 hr{margin:12px 0 0}
.u-d3 .cb{display:flex;align-items:center;height:56px;font-size:14px;font-weight:500}
.u-d3 .cb .bx{margin-left:auto;margin-right:12px;width:18px;height:18px;border-radius:2px;box-shadow:inset 0 0 0 2px var(--onv)}
.u-d3 .acts{justify-content:space-between !important}
.u-fbe{height:48px;padding:0 24px;border-radius:24px;display:flex;align-items:center;font-size:13px;font-weight:500;background:var(--error);color:#fff}
.u-warn{display:flex;gap:10px;align-items:flex-start;margin-top:16px;padding:12px 14px;border-radius:12px;background:var(--recbg);color:var(--error);font-size:14px;line-height:1.5}
.u-warn i{width:8px;height:8px;border-radius:4px;background:var(--rec);flex:none;margin-top:7px}
.u-hint{font-size:12px;color:var(--onv);margin:-6px 0 0 28px;line-height:1.5}
.fb4.err{background:var(--error);color:#fff}
.u-desktop .nb{height:80px;padding-bottom:0}.u-desktop .gesture{display:none}
''' % {'icon': ICON}

CURSOR = ('<svg style="position:absolute;z-index:50;left:{x}px;top:{y}px;width:18px;height:26px" viewBox="0 0 18 26">'
          '<path d="M1 1 L1 21 L6 16.5 L9.5 24.5 L12.5 23 L9 15.2 L15.5 15.2 Z" fill="#fff" stroke="#000" stroke-width="1.3" stroke-linejoin="round"/></svg>')


def page(w, h, scale, body, col=False, syn=True, extra_cls='', crop=False, syn_pos='left:auto;right:12px;top:auto;bottom:8px'):
    cls = 'win' + (' u-col' if col else '') + (' ' + extra_cls if extra_cls else '')
    s = f'<div class="syn" style="z-index:46;{syn_pos};transform:none">示意图片</div>' if syn else ''
    return (f'<!doctype html><html><head><meta charset="utf-8"><meta name="mock-size" content="{w}x{h}@{scale}{" crop" if crop else ""}">'
            f'<link rel="stylesheet" href="kit/kit.css"><style>{A.CSS}{B.CSS}{C.CSS}{D.CSS}{CSS}</style></head>'
            f'<body><div class="{cls}" style="--w:{w}px;--h:{h}px">{body}{s}</div></body></html>')


# ---------- title bars ----------
def v3_bar(mode='l', size=None, hover=None):
    """CustomTitleBar (desktop_manager.dart:291-378): mode l = light, d = dark
    (black, white 75%), s = splash route gradient. hover: 'min' | 'max' | 'x'."""
    sz = f'<span class="sz">[{size}]</span>' if size else ''
    btn = lambda key, icon, cls='': (f'<div class="u-wb{cls}{" hv" if hover == key else ""}">' + mi(icon, 16) + '</div>')
    return (f'<div class="u-tb v3{mode}"><div class="l"><div class="app"><span class="u-ico"></span><span class="nm">纯粹直播</span>{sz}</div></div>'
            + btn('min', 'remove') + btn('max', 'crop_square') + btn('x', 'close', ' x') + '</div>')


def v4_bar(n=False, size=None, hover=None, maximized=False, room=None, tip=None):
    """New title bar: same 32 high and same buttons; the name is not a link;
    maximized shows "restore"; a window showing a room says whose."""
    N = (lambda k: k) if n else (lambda k: None)
    T = (lambda t: t) if n else (lambda t: None)
    sz = f'<span class="sz">[{size}]</span>' if size else ''
    rm = f'<span class="room">· {room}</span>' if room else ''
    icon = f'<span class="u-ico"{attrs(N(1), T("chg"), "bl" if n else None)} style="width:24px;height:24px;background-size:16px"></span>'
    name = f'<div class="l"{attrs(N(2), T("keep"), "tc" if n else None)}><div class="app" style="padding-left:0">{icon}<span class="nm">纯粹直播</span>{rm}{sz}</div></div>'
    btn = lambda key, k, tag, icon, cls='': (f'<div class="u-wb{cls}{" hv" if hover == key else ""}"{attrs(N(k), T(tag), "bc" if n else None)}>' + mi(icon, 16) + '</div>')
    out = (f'<div class="u-tb v4">{name}' + btn('min', 3, 'keep', 'remove') + btn('max', 4, 'chg', 'filter_none' if maximized else 'crop_square')
           + btn('x', 5, 'keep', 'close', ' x') + '</div>')
    if tip:
        text, right = tip
        out = out[:-6] + f'<div class="tip" style="right:{right}px;top:36px">{text}</div></div>'
    return out


def wide_content(v4, cols=4, w=1280):
    rail = B.v4_rail(0, n=False) if v4 else B.v3_rail(0)
    return f'<div class="u-main">{rail}<div class="body">{B.fav_page(cols)}</div></div>'


# ---------- 1. the window ----------
def window(v4, n=False):
    bar = v4_bar(n=n) if v4 else v3_bar()
    return page(1280, 800, 1.5, bar + wide_content(v4), col=True)


# ---------- 2. title bar states ----------
def strip(bar, below='var(--surface)', theme=None, extra=''):
    t = f' data-theme="{theme}"' if theme else ''
    return f'<div class="u-strip"{t}>{bar}<div class="u-pgb" style="background:{below}"></div>{extra}</div>'


V3_SPLASH_PAGE = 'linear-gradient(135deg,#E0F7FA,#B2EBF2 50%,#80DEEA)'
V4_SPLASH_PAGE = 'linear-gradient(160deg,var(--surface),var(--surface) 45%,rgba(209,228,255,.7))'


def titlebar_states(v4):
    W = 860
    rows = []
    if not v4:
        rows = [
            ('普通（浅色）', '页面是表面色', strip(v3_bar())),
            ('鼠标在“关闭”上', '红底白字；没有按钮名称提示', strip(v3_bar(hover='x'))),
            ('拖动窗口边改大小时', '名字后面显示尺寸，停下 2 秒后消失', strip(v3_bar(size='1280 × 800'))),
            ('最大化以后', '中间的按钮还是“最大化”的方框', strip(v3_bar(hover='max'))),
            ('深色', '标题栏纯黑，下面的页面是深灰', strip(v3_bar('d'), below='#111418')),
            ('启动页', '标题栏的渐变和启动页的渐变不是同一组颜色，接缝处看得出', strip(v3_bar('s'), below=V3_SPLASH_PAGE)),
            ('在新窗口打开的直播间', '和主窗口一模一样，看不出是哪个', strip(v3_bar())),
        ]
    else:
        rows = [
            ('普通（浅色）', '同 v3', strip(v4_bar())),
            ('鼠标在“关闭”上', '红底白字；停一会儿显示名称', strip(v4_bar(hover='x', tip=('关闭', 4)), extra='<div style="height:30px"></div>')),
            ('拖动窗口边改大小时', '同 v3', strip(v4_bar(size='1280 × 800'))),
            ('最大化以后', '换成“向下还原”的图标', strip(v4_bar(hover='max', maximized=True, tip=('向下还原', 40)), extra='<div style="height:30px"></div>')),
            ('深色', '和页面同一个深色表面', strip(v4_bar(), below='var(--surface)', theme='dark')),
            ('启动页', '和启动页同一个底色（U.3c）', strip(v4_bar(), below=V4_SPLASH_PAGE)),
            ('直播间里（主窗口或新窗口）', '名字后面是主播名；任务栏和 Alt+Tab 里是“晚风 - 纯粹直播”', strip(v4_bar(room='晚风'))),
        ]
    body = '<div class="u-sheet"></div><div style="position:relative;width:100%;padding:4px 24px 24px">'
    for lab, sub, html in rows:
        body += f'<div class="u-lab">{lab}<small>{sub}</small></div>{html}'
    body += '</div>'
    return page(W, 1200, 2, body, syn=False, crop=True)


def sysmenu():
    """Clicking the icon or right-clicking the bar opens Windows' own window menu."""
    items = [('filter_none', '还原', True), ('', '移动', False), ('', '大小', False), ('remove', '最小化', False), ('crop_square', '最大化', False)]
    rows = ''.join(f'<div class="i{" dis" if dis else ""}"><span class="g">{mi(g, 14) if g else ""}</span>{t}</div>' for g, t, dis in items)
    rows += '<div class="s"></div><div class="i hv"><span class="g">' + mi('close', 14) + '</span>关闭<span class="k">Alt+F4</span></div>'
    menu = f'<div class="u-nm" style="left:14px;top:30px;width:220px">{rows}</div>'
    body = (v4_bar(hover=None) + wide_content(True, 2) + menu + CURSOR.format(x=22, y=14)
            + '<div class="u-cap" style="left:250px;top:300px">点图标或右键标题栏：Windows 自己的窗口菜单（系统画的，示意）</div>')
    return page(640, 400, 2.5, body, col=True)


# ---------- 3. Linux ----------
def linux(v4):
    top = ('<div class="u-gtop"><span>活动</span><span class="c">10月1日 21:40</span><span class="r">'
           + ('<span class="u-ico"></span>' if v4 else '') + mr('wifi', 16) + mr('volume_up', 16) + mr('power_settings_new', 16) + '</span></div>')
    x, y, w, h = 90, 64, 1100, 690
    if v4:
        win = f'<div class="u-w gn" style="left:{x}px;top:{y}px;width:{w}px;height:{h}px">' + v4_bar() + wide_content(True, 4) + '</div>'
        cap = ('<div class="u-cap" style="left:90px;top:762px">新设计：和 Windows 同一个标题栏，拖动、双击最大化、三个按钮都有</div>'
               '<div class="u-cap" style="right:12px;top:34px">托盘图标（桌面支持托盘时）</div>')
    else:
        win = f'<div class="u-w gn" style="left:{x}px;top:{y}px;width:{w}px;height:{h}px">' + wide_content(False, 4) + '</div>'
        cap = '<div class="u-cap" style="left:90px;top:762px">v3：系统标题栏被藏起来，自绘的标题栏只在 Windows 画，Linux 上没有标题栏（按代码推算）</div>'
    return page(1280, 800, 1.5, '<div class="u-desk"></div>' + top + win + cap)


# ---------- 4. close dialog ----------
def v3_close():
    """_ExitDecisionDialog (utils.dart:346-391): title 提示 (titleLarge), 确定要退出吗？
    (titleMedium 15 w500), divider, 不再询问 (CheckboxListTile, titleSmall 14 w500),
    actions spaceBetween: 最小化 (TextButton) / 退出应用 (FilledButton, error)."""
    dlg = ('<div class="d3 u-d3" style="width:468px"><div class="t">提示</div><div class="q">确定要退出吗？</div><hr>'
           '<div class="cb">不再询问<span class="bx"></span></div>'
           '<div class="acts" style="padding:20px 0 24px"><div class="tb3" style="height:48px">最小化</div><div class="u-fbe">退出应用</div></div></div>')
    return page(1280, 800, 1.5, v3_bar() + wide_content(False) + f'<div class="u-ov" style="top:32px">{dlg}</div>', col=True)


def v4_close_dialog(n=False, recording=False, tray=True):
    N = (lambda k: k) if n else (lambda k: None)
    T = (lambda t: t) if n else (lambda t: None)
    warn = ('<div class="u-warn"><i></i><span><b>正在录制 2 个直播间</b><br>退出会停止录制，已经录下的部分会保存。</span></div>' if recording else '')
    minimize = '最小化到托盘' if tray else '最小化'
    msg = '退出应用，还是最小化到托盘继续运行？' if tray else '退出应用，还是最小化到任务栏继续运行？'
    return (f'<div class="d4" style="width:440px"><div class="t">关闭窗口</div><div class="msg">{msg}</div>{warn}'
            '<div class="ck"' + attrs(N(6), T('keep'), 'tl' if n else None) + '><span class="bx"></span>不再询问</div>'
            '<div class="u-hint">以后可以在“设置 → 通用 → 关闭窗口时”里改</div>'
            '<div class="acts"><div class="tb4"' + attrs(N(7), T('chg'), 'bc' if n else None) + f'>{minimize}</div><div class="gap"></div>'
            '<div class="fb4 err"' + attrs(N(8), T('keep'), 'bc' if n else None) + '>退出应用</div></div></div>')


def v4_close(n=False, recording=False):
    return page(1280, 800, 1.5, v4_bar() + wide_content(True) + f'<div class="u-ov" style="top:32px">{v4_close_dialog(n, recording)}</div>', col=True)


# ---------- 5. tray ----------
def taskbar_tray(icons=1, hover=False):
    ours = ''.join('<div class="t' + (' hv' if hover and i == icons - 1 else '') + '"><span class="u-ico"></span></div>' for i in range(icons))
    return (f'<div class="u-tray"><div class="t">{mr("expand_less", 18)}</div>{ours}<div class="t">{mr("wifi")}</div>'
            f'<div class="t">{mr("volume_up")}</div><div class="t ime">中</div><div class="clk">21:40<br>2026/10/01</div></div>')


def tray_panel(left, w, h, inner):
    return (f'<div style="position:absolute;left:{left}px;top:0;width:{w}px;height:{h}px;overflow:hidden">'
            f'<div class="u-desk" style="background-position:{"20% 80%" if left else "70% 80%"}"></div>'
            f'<div class="u-task" style="justify-content:flex-start;padding-left:16px"><div class="g"><i></i></div><div class="g"><i></i></div>{taskbar_tray(1, True)}</div>{inner}</div>')


def tray(v4, n=False):
    N = (lambda k: k) if n else (lambda k: None)
    T = (lambda t: t) if n else (lambda t: None)
    W, H, PW = 1080, 340, 520
    # our icon sits 4th from the right of the tray: clock ~76, ime 24, volume 28, wifi 28
    icon_x = PW - 6 - 76 - 24 - 28 - 28 - 28 + 14
    tip_text = '纯粹直播 · 正在录制 2 个' if v4 else '纯粹直播'
    tip = f'<div class="u-tt" style="left:{icon_x - 40}px;bottom:58px">{tip_text}</div>' + CURSOR.format(x=icon_x - 9, y=H - 32)
    if v4:
        rows = ('<div class="i dis"><span class="g"><i class="rec"></i></span>正在录制 2 个直播间</div><div class="s"></div>'
                '<div class="i hv"' + attrs(N(10), T('keep'), 'tr' if n else None) + '><span class="g"></span>显示窗口</div><div class="s"></div>'
                '<div class="i"' + attrs(N(11), T('chg'), 'tr' if n else None) + '><span class="g"></span>退出应用</div>')
        mw = 230
    else:
        rows = '<div class="i hv">隐藏窗口</div><div class="s"></div><div class="i">退出应用</div>'
        mw = 180
    menu = f'<div class="u-nm" style="left:{icon_x - mw + 30}px;bottom:56px;width:{mw}px">{rows}</div>' + CURSOR.format(x=icon_x - 9, y=H - 32)
    a = tray_panel(0, PW, H, tip + '<div class="u-cap" style="left:12px;top:12px">鼠标停在托盘图标上：提示文字</div>')
    b = tray_panel(W - PW, PW, H, menu + '<div class="u-cap" style="left:12px;top:12px">右键托盘图标：菜单</div>')
    mark = (f'<div style="position:absolute;left:{W - PW + icon_x - 14}px;top:{H - 44}px;width:28px;height:40px"'
            + attrs(N(9), T('keep'), 'tc' if n else None) + '></div>') if v4 else ''
    return page(W, H, 2, a + b + mark, syn=False)


# ---------- 6. new window ----------
def room_window(v4):
    bar = v4_bar(room='晚风') if v4 else v3_bar()
    chat = ''.join(f'<div class="row"><span class="u">{u}：</span>{t}</div>' for u, t in [
        ('路过的风', '主播声音太温柔了'), ('夜猫子', '可以点《晴天》吗'), ('一只小熊', '这首歌好好听'), ('清欢', '下一首想听《晚风》'),
        ('风吹麦浪', '来了来了'), ('小林同学', '今天也是被治愈的一天'), ('月亮邮差', '这个混响调得真舒服'), ('Aki', '打卡第 52 天')])
    return (bar + '<div class="u-room"><div class="vid"><div class="hd"><span class="av" style="background-image:url(.cache/img/65.jpg)"></span>'
            '<div><div class="n">晚风</div><div class="s">哔哩哔哩 · 唱见电台</div></div></div><div class="pic"></div></div>'
            f'<div class="chat">{chat}</div></div>')


def newwin(v4):
    main = '<div class="u-w" style="left:40px;top:28px;width:900px;height:560px">' + (v4_bar() if v4 else v3_bar()) + wide_content(v4, 3) + '</div>'
    room = '<div class="u-w" style="left:330px;top:150px;width:900px;height:540px">' + room_window(v4) + '</div>'
    titles = ['纯粹直播', '晚风 - 纯粹直播'] if v4 else ['纯粹直播', '纯粹直播']
    pics = ['.cache/img/1.jpg', '.cache/img/158.jpg']
    thumbs = ''.join(f'<div class="c"><div class="h"><span class="u-ico"></span>{t}</div><div class="p" style="background-image:url({p})"></div></div>'
                     for t, p in zip(titles, pics))
    task = ('<div class="u-task">' + '<div class="g"><i></i></div>' * 3 + '<div class="g hv"><span class="u-ico"></span><u class="two"></u></div>'
            + '<div class="g"><i></i></div>' * 2 + taskbar_tray(1 if v4 else 2) + '</div>')
    th = f'<div class="u-thumb" style="left:{640 - 216 + 22}px;bottom:56px">{thumbs}</div>'
    cap = ('<div class="u-cap" style="right:12px;bottom:58px">托盘：' + ('只有主窗口有图标' if v4 else '每个窗口各一个，一模一样') + '</div>'
           + '<div class="u-cap" style="left:446px;top:420px">新窗口里的直播间（简化示意）</div>'
           + '<div class="u-cap" style="left:446px;bottom:256px">鼠标停在任务栏图标上：' + ('标题看得出是哪个窗口' if v4 else '两个窗口都叫“纯粹直播”') + '</div>')
    return page(1280, 800, 1.5, '<div class="u-desk"></div>' + main + room + task + th + cap)


# ---------- 7. live-room menu (Windows) ----------
ROOM_BAR_V3 = ('<div class="appbar" style="width:100%;position:absolute;left:0;top:0"><div class="back">' + mi('arrow_back') + '</div>'
               '<span class="av" style="background-image:url(.cache/img/65.jpg)"></span><div class="tt"><div class="n">晚风</div>'
               '<div class="s">哔哩哔哩 · 唱见电台</div></div><div class="ib">' + rx('ea42') + '</div></div>'
               '<div class="u-cap" style="left:12px;bottom:12px">直播间右上角的菜单（顶栏只画了菜单按钮）</div>')
ROOM_BAR = ('<div class="appbar" style="width:100%;position:absolute;left:0;top:0"><div class="back">' + mi('arrow_back') + '</div>'
            '<span class="av" style="background-image:url(.cache/img/65.jpg)"></span><div class="tt"><div class="n">晚风</div>'
            '<div class="s">哔哩哔哩 · 唱见电台</div></div><div class="fol on">' + rx('eb7b') + '已关注</div>'
            '<div class="recbtn"><span class="ring"><i></i></span></div><div class="ib">' + rx('ea42') + '</div></div>'
            '<div class="u-cap" style="left:12px;bottom:12px">直播间顶栏右上角的菜单（宽屏，背景简化）</div>')


def v3_room_menu():
    """live_play_menu_button.dart:186-207: icon 20, MenuListTile labelMedium 12;
    two items share Icons.open_in_new_rounded."""
    items = [(mr('open_in_new', 20), '打开直播间'), (mr('swap_horiz', 20), '切换直播间'), (rx('f235', 20), '投屏'), (rx('f20f', 20), '定时关闭'),
             (rx('f2a2', 20), '房间音量'), (rx('eeaf', 20), '获取直链'), (rx('f0fd', 20), '分享'), (mr('auto_awesome', 20), '本地互动体验'),
             (mr('open_in_new', 20), '在新窗口播放此直播间')]
    rows = ''.join(f'<div class="it" style="padding:0 12px"><span style="color:var(--onv)">{i}</span><span style="font-size:12px;font-weight:400">{t}</span></div>' for i, t in items)
    return page(520, 560, 2, ROOM_BAR_V3 + f'<div class="pm" style="right:8px;top:56px;width:236px;border-radius:8px">{rows}</div>', syn=False)


def v4_room_menu(n=False):
    items = [(rx('ea62'), '切换直播间'), (rx('f20f'), '定时关闭'), (rx('f2a2'), '房间音量'), (rx('ea80'), '画面比例'), ('-', ''),
             (rx('f235'), '投屏'), (rx('eeaf'), '获取直链'), (rx('f0fd'), '分享'), (rx('ecaf'), '在哔哩哔哩打开'), ('new', '在新窗口打开'), ('-', ''),
             (mr('auto_awesome'), '本地互动体验')]
    rows = ''
    for icon, text in items:
        if icon == '-':
            rows += '<div class="sep"></div>'
        elif icon == 'new':
            rows += ('<div class="it"' + attrs(12 if n else None, 'chg' if n else None, 'tr' if n else None) + '><span style="flex:none;color:var(--onv)">'
                     + mo('add_to_photos') + f'</span><span>{text}</span></div>')
        else:
            rows += f'<div class="it"><span style="flex:none;color:var(--onv)">{icon}</span><span>{text}</span></div>'
    return page(520, 640, 2, ROOM_BAR + f'<div class="menu" style="right:8px;top:56px;width:240px">{rows}</div>', syn=False)


mo = lambda n, s=24: f'<span class="mo" style="font-size:{s}px">{n}</span>'


# ---------- 8. the smallest window ----------
def min_window(v4):
    w, h = (360, 400) if v4 else (400, 300)
    bar = v4_bar() if v4 else v3_bar()
    if v4:
        body = A.v4_bar_favorites(False) + '<div class="main">' + A.favorites_body() + '</div>' + A.nav_bar(0, 'shapes')
    else:
        body = A.v3_bar_favorites() + '<div class="main">' + A.favorites_body() + '</div>' + A.nav_bar(0)
    return page(w, h, 3, bar + f'<div class="u-main" style="flex-direction:column">{body}</div>', col=True, extra_cls='u-desktop', syn_pos='left:auto;right:28px;top:158px')


def build():
    out = {
        'v3-window': window(False), 'v4-window': window(True, n=True),
        'v3-titlebars': titlebar_states(False), 'v4-titlebars': titlebar_states(True),
        'v4-sysmenu': sysmenu(),
        'v3-linux': linux(False), 'v4-linux': linux(True),
        'v3-close': v3_close(), 'v4-close': v4_close(n=True), 'v4-close-rec': v4_close(recording=True),
        'v3-tray': tray(False), 'v4-tray': tray(True, n=True),
        'v3-newwin': newwin(False), 'v4-newwin': newwin(True),
        'v3-room-menu': v3_room_menu(), 'v4-room-menu': v4_room_menu(n=True),
        'v3-min': min_window(False), 'v4-min': min_window(True),
    }
    return out


if __name__ == '__main__':
    pages = build()
    for name, html in pages.items():
        open(os.path.join(HERE, name + '.html'), 'w', encoding='utf-8').write(html)
    print(len(pages), 'pages')
