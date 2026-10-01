"""U.2j mini windows: v3 restored and the new design.

v3 (tag v3.2.11):
  in-app floating window  lib/player/core/player_manager.dart:2970-3156
      (size :2977 + resolveAppFloatingSize :4737-4757, 12 radius :3011-3014,
      right 16 / bottom inset+96 :3117-3118 :3150-3155, controls :3053-3114,
      touch first tap :3032-3050, hover only Windows/macOS :2999-3004)
  audio only in it        player_manager.dart:3289-3460 (buildAudioOnlyUI, compact < 500 high)
  system PiP surface      player_manager.dart:3215-3287 (buildPiPOverlay), live_play_content.dart:490-495
  Windows mini window     player/utils/window_helper.dart:217-337 (360 wide, bottom-right 20,
      always-on-top from the setting), pip_window_widget.dart (edge resize),
      common/global/platform/desktop_manager.dart:124-132 (no title bar)
  compact danmaku         modules/live_play/widgets/danmaku/compact_danmaku_overlay.dart,
      common/utils/compact_danmaku_metrics.dart (scale = width / 350 clamped 0.65-1),
      defaults common/services/settings/danmaku_settings_controller.dart:17-31
  background pages        modules/home/mobile_view.dart, tablet_view.dart, popular/popular_page.dart

    python3 docs/ui/compare/U.2j/src/gen.py && python3 tools/ui/mock/render.py docs/ui/compare/U.2j/src/ --annotate
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
CSS = '''
.bg{position:absolute;inset:0}
/* ---------- home page behind the in-app window (v3, simplified) ---------- */
.home{position:absolute;inset:0;background:var(--surface);display:flex;flex-direction:column}
.hb{height:56px;display:flex;align-items:center;flex:none;color:var(--onv)}
.htabs{flex:1;min-width:0;display:flex;gap:22px;padding:0 6px;font-size:15px;color:var(--onv);white-space:nowrap;overflow:hidden;align-self:stretch;align-items:stretch}
.htabs span{position:relative;display:flex;align-items:center}
.htabs .on{color:var(--primary);font-weight:600}
.htabs .on::after{content:'';position:absolute;left:0;right:0;bottom:0;height:3px;border-radius:3px 3px 0 0;background:var(--primary)}
.grid{display:grid;gap:10px;padding:6px 10px;align-content:start;grid-auto-rows:max-content;flex:1;min-height:0;overflow:hidden}
.card{border-radius:16px;background:var(--scl);overflow:hidden}
.card .img{aspect-ratio:16/9;background:center/cover}
.card .t{font-size:13px;line-height:18px;padding:6px 10px 0;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.card .s{font-size:12px;line-height:16px;color:var(--onv);padding:2px 10px 9px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.nav{height:80px;flex:none;background:var(--scc);display:flex}
.nav>div,.rail>div{flex:1;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:4px;font-size:12px;font-weight:500;color:var(--onv)}
.nav i,.rail i{width:64px;height:32px;border-radius:16px;display:grid;place-items:center;font-style:normal}
.nav .on,.rail .on{color:var(--on)}.nav .on i,.rail .on i{background:var(--sc);color:var(--osc)}
.inset{height:16px;flex:none;background:var(--scc)}
.body2{flex:1;display:flex;min-height:0}
.rail{width:88px;flex:none;display:flex;flex-direction:column;align-items:center;padding:16px 0;gap:6px;border-right:1px solid var(--ov)}
.rail>div{flex:none;height:64px}
.rail .lead{color:var(--onv);height:48px}
.main{flex:1;min-width:0;display:flex;flex-direction:column}
.cap{position:absolute;z-index:44;font:500 11px 'Noto Sans SC';padding:3px 7px;border-radius:5px;background:rgba(0,0,0,.55);color:#fff}
/* ---------- the mini window ---------- */
.mw{position:absolute;z-index:30;overflow:hidden;background:#000 url(.cache/img/158.jpg) center 55%/cover}
.mw.r12{border-radius:12px}
.mw.sh{box-shadow:0 8px 24px rgba(0,0,0,.38),0 0 0 1px rgba(255,255,255,.10)}
.mw .d{position:absolute;z-index:2;white-space:nowrap;color:#fff;font-weight:500;line-height:1;text-shadow:0 0 1px #000,0 0 1px #000,0 0 2px #000;opacity:.9}
.mw .c{position:absolute;display:grid;place-items:center;border-radius:50%;background:rgba(0,0,0,.45);color:#fff;z-index:3}
.mw .bare{position:absolute;display:grid;place-items:center;color:#fff;z-index:3}
.mw .c.on{background:var(--primary);color:var(--onPrimary)}
.mb{position:absolute;left:6px;bottom:6px;z-index:2;height:20px;padding:0 7px 0 6px;border-radius:10px;background:var(--rec);color:#fff;font:600 12px/20px 'Noto Sans SC';font-feature-settings:'tnum';display:flex;align-items:center;gap:4px}
.mb i{width:6px;height:6px;border-radius:3px;background:#fff}
.st{position:absolute;inset:0;z-index:1;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:6px;color:#fff;font-size:12px;background:rgba(0,0,0,.55)}
.st.solid{background:#000}
.spin{width:22px;height:22px;border-radius:50%;border:2.5px solid rgba(255,255,255,.3);border-top-color:#fff}
.vp{position:absolute;left:50%;bottom:10px;transform:translateX(-50%);z-index:3;height:28px;padding:0 12px 0 8px;border-radius:14px;background:rgba(0,0,0,.6);display:flex;align-items:center;gap:6px;color:#fff}
.vp .t{width:72px;height:4px;border-radius:2px;background:rgba(255,255,255,.35);position:relative}.vp .t i{position:absolute;left:0;top:0;bottom:0;width:70%;border-radius:2px;background:#fff}
/* audio only (v3 buildAudioOnlyUI, compact) */
.au{position:absolute;inset:0;z-index:1;background:linear-gradient(135deg,rgba(18,24,39,.91),rgba(11,14,22,.95),rgba(21,16,32,.94)),url(.cache/img/65.jpg) center/cover;overflow:hidden}
.au .col{position:absolute;left:0;right:0;top:4px;display:flex;flex-direction:column;align-items:center;padding:0 16px}
.au .av{border-radius:50%;background:url(.cache/img/65.jpg) center/cover;box-shadow:0 0 0 1.5px rgba(255,255,255,.15)}
.au .ti{color:#fff;font-weight:700;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:100%}
.au .ni{color:rgba(255,255,255,.75);font-weight:500;border-radius:20px;background:rgba(255,255,255,.06);border:1px solid rgba(255,255,255,.08)}
.au .bd{display:flex;align-items:center;gap:4px;color:#fff;font-weight:600;border-radius:30px;background:rgba(255,255,255,.08);border:1px solid rgba(255,255,255,.1)}
/* ---------- system surroundings ---------- */
.ln{position:absolute;inset:0;background:url(.cache/img/338.jpg) center/cover}
.ln::before{content:'';position:absolute;inset:0;background:rgba(0,0,0,.18)}
.ln .status{position:relative;z-index:2;color:#fff}
.apps{position:absolute;left:30px;right:30px;top:118px;display:grid;grid-template-columns:repeat(4,1fr);gap:34px 0;justify-items:center}
.apps i,.dock i{width:56px;height:56px;border-radius:18px;display:block}
.dock{position:absolute;left:30px;right:30px;bottom:44px;display:flex;justify-content:space-between}
.sbar{position:absolute;left:24px;right:24px;bottom:124px;height:48px;border-radius:24px;background:rgba(255,255,255,.82)}
.desk{position:absolute;inset:0;background:url(.cache/img/287.jpg) center/cover}
.app{position:absolute;background:#fff;border-radius:8px;box-shadow:0 12px 40px rgba(0,0,0,.35);overflow:hidden}
.app .tb{height:32px;background:#EEF0F3;display:flex;align-items:center;justify-content:flex-end;color:#333}
.app .tb span{width:46px;display:grid;place-items:center}
.app .ln2{height:10px;border-radius:5px;background:#E4E6EA;margin:14px 28px}
.task{position:absolute;left:0;right:0;bottom:0;height:48px;background:rgba(28,28,30,.88);display:flex;align-items:center;justify-content:center;gap:10px;z-index:20}
.task i{width:30px;height:30px;border-radius:6px;background:rgba(255,255,255,.55);display:block}
.task .clk{position:absolute;right:16px;color:#fff;font:12px/16px 'Geist','Noto Sans SC';text-align:right;font-feature-settings:'tnum'}
.cur{position:absolute;z-index:50;width:18px;height:26px}
/* ---------- room behind the PiP dialog (U.2a) ---------- */
.dlg .h{padding:24px 24px 0;font-size:16px;font-weight:700}
.dlg .b{padding:12px 24px 0;font-size:14px;line-height:1.6;color:var(--onv)}
.dlg .a{display:flex;justify-content:flex-end;gap:8px;padding:20px 16px 16px}
.dlg .a span{height:40px;padding:0 16px;border-radius:20px;display:flex;align-items:center;font-size:14px}
.dlg .a .ok{background:var(--primary);color:var(--onPrimary);font-weight:600}
/* ---------- states sheet ---------- */
.sheetbg{position:absolute;inset:0;background:var(--scc)}
.cell{position:absolute}
.cell .lab{position:absolute;left:0;right:0;font-size:13px;line-height:18px;color:var(--on);text-align:left}
.cell .lab small{display:block;font-size:12px;color:var(--onv)}
'''
mr = lambda n, s=24: f'<span class="mr" style="font-size:{s}px">{n}</span>'
mi = lambda n, s=24: f'<span class="mi" style="font-size:{s}px">{n}</span>'
rx = lambda c, s=24: f'<span class="rx" style="font-size:{s}px">&#x{c};</span>'
ci = lambda c, s=24: f'<span class="ci" style="font-size:{s}px">&#x{c};</span>'
CURSOR = ('<svg class="cur" style="left:{x}px;top:{y}px" viewBox="0 0 18 26"><path d="M1 1 L1 21 L6 16.5 L9.5 24.5 L12.5 23 L9 15.2 L15.5 15.2 Z" '
          'fill="#fff" stroke="#000" stroke-width="1.3" stroke-linejoin="round"/></svg>')

DMS = ['前排支持！', '这首好好听', '晚风今天状态好好', '来了来了', '晚上好～', '主播声音太温柔了']
CARDS = [('111', '周末老爷车巡游现场', '车库阿杰'), ('169', '小狗满草地跑一下午', '柴柴日记'), ('219', '草原上的猎豹妈妈', '野生镜头'),
         ('225', '下午茶时间 聊聊天', '茶馆小周'), ('274', '纽约时代广场，夜游直播', '城市漫游'), ('304', '调音台教学 第 12 课', '录音棚老王'),
         ('342', '台北夜市一路吃过去', '阿明在台北'), ('360', '花店开门 今天进了新货', '花间小铺'), ('250', '老相机修复全过程', '胶片修理铺'),
         ('292', '一人食 晚饭做什么', '厨房小林')]
TABS = ['哔哩哔哩', '斗鱼', '虎牙', '抖音', '快手', '网易CC']


def page(w, h, scale, body, root='win', crop=False, extra=''):
    return (f'<!doctype html><html><head><meta charset="utf-8"><meta name="mock-size" content="{w}x{h}@{scale}{" crop" if crop else ""}">'
            f'<link rel="stylesheet" href="kit/kit.css"><style>{CSS}{extra}</style></head>'
            f'<body><div class="{root}" style="--w:{w}px;--h:{h}px">{body}</div></body></html>')


# ---------- background pages ----------
def cards(n, cols):
    return (f'<div class="grid" style="grid-template-columns:repeat({cols},1fr)">'
            + ''.join(f'<div class="card"><div class="img" style="background-image:url(.cache/img/{i}.jpg)"></div><div class="t">{t}</div><div class="s">{s}</div></div>'
                      for i, t, s in CARDS[:n]) + '</div>')


def nav_items(rail=False):
    items = [('ee0b', '关注', False), ('ed33', '热门', True), ('ea42', '分区', False)] + ([] if rail else [('ec54', '录制中心', False)])
    out = ''
    for code, label, on in items:
        icon = rx({'ed33': 'ed32'}.get(code, code) if on else code, 24)
        out += f'<div class="{"on" if on else ""}"><i>{icon}</i>{label}</div>'
    return out


def home_phone(w=393, h=852):
    return ('<div class="home"><div class="status"><span>21:36</span><span class="r"><span class="mi">signal_cellular_alt</span><span class="mi">wifi</span><span class="mi">battery_full</span></span></div>'
            '<div class="hb"><div class="ib">' + mr('menu') + '</div><div class="htabs">' + ''.join(f'<span class="{"on" if i == 0 else ""}">{t}</span>' for i, t in enumerate(TABS))
            + '</div><div class="ib">' + rx('f3d0') + '</div></div>' + cards(10, 2) + f'<div class="nav">{nav_items()}</div><div class="inset"></div></div>'
            '<div class="gesture"></div>')


def home_wide(w, h, cols, status=True):
    st = ('<div class="status" style="flex:none"><span>21:36</span><span class="r"><span class="mi">wifi</span><span class="mi">battery_full</span></span></div>' if status else '')
    return (f'<div class="home">{st}<div class="body2"><div class="rail">{nav_items(rail=True)}</div><div class="main">'
            '<div class="hb"><div class="htabs" style="justify-content:center">' + ''.join(f'<span class="{"on" if i == 0 else ""}">{t}</span>' for i, t in enumerate(TABS)) + '</div></div>'
            + cards(10, cols) + '</div></div></div>')


# ---------- the mini window ----------
def danmaku(w, h, font, n=5, area=0.5):
    """Flying danmaku in the top [area] of the window, laid out like the
    barrage engine: track height max(1.8 x font, font + 10), no overlaps."""
    track = max(font * 1.8, font + 10)
    rows = max(1, int(h * area // track))
    starts = [0.42, 0.05, 0.26, 0.60]
    out, k = '', 0
    for r in range(rows):
        x = starts[r % len(starts)] * w
        while k < n and x < w * 0.95:
            text = DMS[k]
            out += f'<div class="d" style="font-size:{font:.1f}px;left:{x:.0f}px;top:{r * track + (track - font) / 2 + 2:.0f}px">{text}</div>'
            x += len(text) * font + font * 3
            k += 1
            if r == 0 and k >= 2:
                break
            if r > 0:
                break
    return out


def circ(x, y, d, inner, cls='c', n=None, tag=None, at=None):
    a = (f' data-n="{n}"' if n else '') + (f' data-tag="{tag}"' if tag else '') + (f' data-at="{at}"' if at else '')
    return f'<div class="{cls}" style="left:{x}px;top:{y}px;width:{d}px;height:{d}px"{a}>{inner}</div>'


def v3_controls(w, h, windows=False):
    """v3: centre play/pause (42 + 8 padding, 45% black) and top-right close
    (in-app: 48 with 45% black, icon 20; Windows mini window: no background, icon 24)."""
    cx, cy = w / 2 - 29, h / 2 - 29
    out = circ(round(cx), round(cy), 58, mi('pause_circle_filled', 42))
    if windows:
        out += circ(w - 8 - 48, 8, 48, mi('close', 24), cls='bare')
    else:
        out += circ(w - 4 - 48, 4, 48, mi('close', 20))
    return out


def v4_controls(w, h, n=False, desktop=False, paused=False, pinned=True, failed=False):
    N = (lambda k: k) if n else (lambda k: None)
    cx, cy = w / 2 - 29, h / 2 - 29
    centre = mr('refresh', 34) if failed else mi('play_circle_filled' if paused else 'pause_circle_filled', 42)
    out = (circ(4, 4, 48, mr('open_in_full', 20), n=N(1), tag='add', at='tl')
           + circ(w - 52, 4, 48, mi('close', 20), n=N(2), tag='chg', at='tr')
           + circ(round(cx), round(cy), 58, centre, n=N(3), tag='keep'))
    if desktop:
        out += circ(w - 52, h - 52, 48, rx('f038' if pinned else 'f039', 20), cls='c on' if pinned else 'c', n=N(4), tag='add', at='br')
    return out


def badge():
    return '<div class="mb"><i></i>12:34</div>'


def audio_v3(w, h):
    # compact (< 500 high): avatar (h*0.22).clamp(50,76), title 14 / 1 line, nick 11, badge 11; gaps 10/4/8; padding 4
    av = max(50, min(76, h * 0.22))
    return (f'<div class="au"><div class="col"><div class="av" style="width:{av:.0f}px;height:{av:.0f}px"></div>'
            '<div class="ti" style="font-size:14px;line-height:1.25;margin-top:10px">深夜电台 · 点歌接龙到天亮</div>'
            '<div class="ni" style="font-size:11px;line-height:1.35;padding:2px 8px;margin-top:4px">晚风</div>'
            '<div class="bd" style="font-size:11px;line-height:1.35;padding:5px 10px;margin-top:8px">' + rx('ee05', 12) + '纯音频模式</div></div></div>')


def audio_v4():
    return ('<div class="st solid" style="background:linear-gradient(135deg,rgba(18,24,39,.91),rgba(11,14,22,.95)),url(.cache/img/65.jpg) center/cover;gap:8px">'
            '<div style="width:44px;height:44px;border-radius:22px;background:url(.cache/img/65.jpg) center/cover;box-shadow:0 0 0 1.5px rgba(255,255,255,.18)"></div>'
            '<div style="display:flex;align-items:center;gap:4px;height:24px;padding:0 10px;border-radius:12px;background:rgba(255,255,255,.12);font-weight:600">'
            + rx('ee05', 14) + '纯音频模式</div></div>')


def mini(x, y, w, h, *, ver, font, inner='', controls='', dm=True, rec=False, img=None, pos=None, n=None, at='tc', state='', frame=None):
    # v3 in-app: 12 radius clip; new: square corners + floating shadow; system windows: drawn by the OS
    cls = {'r12': 'mw r12', 'sh': 'mw sh', 'os': 'mw', 'desk': 'mw'}[frame or ('r12' if ver == 3 else 'sh')]
    style = f'left:{x}px;top:{y}px;width:{w}px;height:{h}px'
    if frame == 'os':    # Android PiP: rounded by the system
        style += ';border-radius:14px;box-shadow:0 6px 18px rgba(0,0,0,.4)'
    if frame == 'desk':  # desktop mini window: the app window itself
        cls, style = 'mw', style + ';box-shadow:0 8px 28px rgba(0,0,0,.45)'
    if img:
        style += f';background-image:url(.cache/img/{img}.jpg)'
    if pos:
        style += f';background-position:{pos}'
    a = (f' data-n="{n}" data-tag="keep" data-at="{at}"' if n else '')
    return (f'<div class="{cls}" style="{style}"{a}>' + (danmaku(w, h, font) if dm else '') + state + (badge() if rec else '') + inner + controls + '</div>')


# phone geometry: bottom inset 16, NavigationBar 80; v3 lifts the window inset + 80 + 16
PW, PH = 220, 124  # v3 maxSide 220 (not Windows); new: 393 x 0.56


def v3_float_phone():
    x, y = 393 - 16 - PW, 852 - (16 + 96) - PH
    win = mini(x, y, PW, PH, ver=3, font=12 * 0.65, controls=v3_controls(PW, PH))
    return page(393, 852, 3, home_phone() + win + '<div class="cap" style="left:16px;top:104px">背景：v3 热门页（简化示意）</div><div class="syn">示意图片</div>', root='ph')


def v4_float_phone(n=True):
    x, y = 393 - 16 - PW, 852 - (16 + 96) - PH
    win = mini(x, y, PW, PH, ver=4, font=10, rec=True, controls=v4_controls(PW, PH, n=n), n=5 if n else None)
    return page(393, 852, 3, home_phone() + win + '<div class="cap" style="left:16px;top:104px">背景：v3 热门页（简化示意）</div><div class="syn">示意图片</div>', root='ph')


def v3_float_landscape():
    w, h = 852, 393
    x, y = w - 16 - PW, h - (16 + 96) - PH
    win = mini(x, y, PW, PH, ver=3, font=12 * 0.65, controls='')
    return page(w, h, 2, home_wide(w, h, 3, status=False) + win + '<div class="syn" style="top:auto;bottom:8px;left:50%">示意图片</div>', root='fs')


def v4_float_landscape():
    w, h = 852, 393
    x, y = w - 16 - PW, h - 16 - PH
    win = mini(x, y, PW, PH, ver=4, font=10, rec=True)
    return page(w, h, 2, home_wide(w, h, 3, status=False) + win + '<div class="syn" style="top:auto;bottom:8px;left:50%">示意图片</div>', root='fs')


def v3_float_wide():
    w, h = 1280, 800
    x, y = w - 16 - PW, h - 96 - PH
    win = mini(x, y, PW, PH, ver=3, font=12 * 0.65, controls=v3_controls(PW, PH))
    return page(w, h, 1.5, home_wide(w, h, 4) + win + '<div class="syn">示意图片</div>', root='win')


def v4_float_wide():
    w, h = 1280, 800
    fw, fh = 360, 203
    x, y = w - 16 - fw, h - 16 - fh
    win = mini(x, y, fw, fh, ver=4, font=12, rec=True, controls=v4_controls(fw, fh))
    return page(w, h, 1.5, home_wide(w, h, 4) + win + '<div class="syn">示意图片</div>', root='win')


def launcher(w=393, h=852):
    cols = ['#F4C7B8', '#BFD8F2', '#C8E6C9', '#FFE0A3', '#D7C8F0', '#F2C1D6', '#B9E2E0', '#E8E0D0']
    return ('<div class="ln"><div class="status"><span>21:40</span><span class="r"><span class="mi">signal_cellular_alt</span><span class="mi">wifi</span><span class="mi">battery_full</span></span></div>'
            '<div class="apps">' + ''.join(f'<i style="background:{c}"></i>' for c in cols) + '</div><div class="sbar"></div>'
            '<div class="dock">' + ''.join(f'<i style="background:{c}"></i>' for c in cols[:4]) + '</div></div>'
            '<div class="gesture" style="background:rgba(255,255,255,.7)"></div>')


def pip_android(ver):
    w, h = 240, 135
    x, y = 393 - 12 - w, 852 - 200 - h
    font = 12 * max(0.65, min(1, w / 350)) if ver == 3 else 10
    win = mini(x, y, w, h, ver=ver, font=font, rec=(ver == 4), frame='os')
    return page(393, 852, 3, launcher() + win + '<div class="cap" style="left:12px;top:44px">系统画中画：在主屏上（窗口大小、位置和点开后的按钮由系统决定）</div><div class="syn" style="top:auto;bottom:24px">示意图片</div>', root='ph')


def desktop_bg(w, h):
    return ('<div class="desk"></div><div class="app" style="left:110px;top:56px;width:860px;height:600px"><div class="tb">'
            + ''.join(f'<span>{mr(i, 16)}</span>' for i in ('remove', 'crop_square', 'close')) + '</div>'
            + ''.join(f'<div class="ln2" style="width:{wd}%"></div>' for wd in (40, 88, 92, 70, 84, 90, 60, 86, 78, 91, 55, 80, 88, 66)) + '</div>'
            '<div class="cap" style="left:126px;top:96px;background:rgba(0,0,0,.45)">另一个程序（示意）</div>'
            '<div class="task">' + '<i></i>' * 7 + '<div class="clk">21:40<br>2026/10/01</div></div>')


def desktop_window(ver, x, y, n):
    fw, fh = 360, 203
    if ver == 3:
        return mini(x, y, fw, fh, ver=3, font=12, controls=v3_controls(fw, fh, windows=True), pos='center 40%', frame='desk')
    return mini(x, y, fw, fh, ver=4, font=12, rec=True, pos='center 40%', n=5 if n else None, at='tc', frame='desk',
                controls=v4_controls(fw, fh, n=n, desktop=True)
                + '<div class="vp"' + (' data-n="6" data-tag="add" data-at="bl"' if n else '') + '>' + mr('volume_up', 18) + '<div class="t"><i></i></div></div>')


def desktop_mini(ver):
    """The whole screen: Windows 1280x800 with another program in front."""
    w, h, fw, fh = 1280, 800, 360, 203
    x, y = w - 20 - fw, h - 48 - 20 - fh
    win = desktop_window(ver, x, y, n=False)
    cur = CURSOR.format(x=x + 210, y=y + 120) if ver == 3 else CURSOR.format(x=x + fw - 30, y=y + fh - 26)
    tip = '' if ver == 3 else f'<div class="tip" style="left:{x + fw - 92}px;top:{y + fh - 86}px">取消置顶</div>'
    return page(w, h, 1.5, desktop_bg(w, h) + win + cur + tip + '<div class="syn">示意图片</div>', root='win')


def desktop_zoom(ver):
    """The mini window alone, enlarged, mouse over it."""
    w, h, fw, fh = 420, 263, 360, 203
    x, y = 30, 30
    win = desktop_window(ver, x, y, n=(ver == 4))
    cur = CURSOR.format(x=x + 210, y=y + 120) if ver == 3 else CURSOR.format(x=x + fw - 30, y=y + fh - 26)
    tip = '' if ver == 3 else f'<div class="tip" style="left:{x + fw - 92}px;top:{y + fh - 86}px">取消置顶</div>'
    return page(w, h, 3, '<div class="desk" style="background-position:80% 70%"></div>' + win + cur + tip, root='win')


# ---------- states ----------
def states(ver):
    W, pad, gap, lab_h = 760, 24, 24, 64
    st = lambda inner, cls='st': f'<div class="{cls}">{inner}</div>'
    spin = '<div class="spin"></div>'
    if ver == 3:
        f = 12 * 0.65
        items = [
            (mini(0, 0, PW, PH, ver=3, font=f), PH, '播放中', '按钮隐藏；弹幕 7.8 号字'),
            (mini(0, 0, PW, PH, ver=3, font=f, controls=v3_controls(PW, PH)), PH, '点一下：按钮出现 3 秒', '再点画面回到直播间'),
            (mini(0, 0, PW, PH, ver=3, font=f, state=audio_v3(PW, PH)), PH, '纯音频', '放不下，“纯音频模式”被截掉一半'),
            (mini(0, 0, PW, PH, ver=3, font=f, dm=False, state=st(spin, 'st solid')), PH, '加载中', '加载动画随设置'),
            (mini(0, 0, 149, 264, ver=3, font=f, img='65', pos='center'), 264, '竖屏直播', '149×264（高 = 220×1.2）'),
        ]
    else:
        centre = lambda icon, dy=0: circ(round(PW / 2 - 29), round(PH / 2 - 29) + dy, 58, icon)
        items = [
            (mini(0, 0, PW, PH, ver=4, font=10, rec=True), PH, '播放中', '按钮隐藏；左下角是录制角标'),
            (mini(0, 0, PW, PH, ver=4, font=10, rec=True, controls=v4_controls(PW, PH)), PH, '点一下：按钮出现 3 秒', '左上回到直播间，右上关闭'),
            (mini(0, 0, PW, PH, ver=4, font=10, controls=centre(mi('play_circle_filled', 42))), PH, '已暂停', '播放键一直显示，看得出停着'),
            (mini(0, 0, PW, PH, ver=4, font=10, state=audio_v4()), PH, '纯音频', '头像和“纯音频模式”，放得下'),
            (mini(0, 0, PW, PH, ver=4, font=10, dm=False, state=st(spin, 'st solid')), PH, '加载中', '同 v3'),
            (mini(0, 0, PW, PH, ver=4, font=10, dm=False, state=st(spin + '正在重连')), PH, '断流重连', '停在最后一帧，压暗，转圈'),
            (mini(0, 0, PW, PH, ver=4, font=10, dm=False, state='<div class="st" style="justify-content:flex-start;padding-top:10px">播放失败</div>',
                  controls=centre(mr('refresh', 34), 8)), PH, '播放失败', '中间的刷新键重试'),
            (mini(0, 0, 149, 264, ver=4, font=10, img='65', pos='center', rec=True), 264, '竖屏直播', '149×264，同 v3'),
        ]
    out, rows = '<div class="sheetbg"></div>', {}
    for i, (html, hh, lab, sub) in enumerate(items):
        r, c = divmod(i, 3)
        rows[r] = max(rows.get(r, 0), hh)
    y_of = {0: pad}
    for r in range(1, len(rows)):
        y_of[r] = y_of[r - 1] + rows[r - 1] + lab_h
    for i, (html, hh, lab, sub) in enumerate(items):
        r, c = divmod(i, 3)
        out += (f'<div class="cell" style="left:{pad + c * (PW + gap)}px;top:{y_of[r]}px;width:{PW}px;height:{hh}px">{html}'
                f'<div class="lab" style="top:{hh + 8}px">{lab}<small>{sub}</small></div></div>')
    H = y_of[len(rows) - 1] + rows[len(rows) - 1] + lab_h
    return page(W, H, 2, out, root='win')


# ---------- PiP refused (Android, new) ----------
def room_behind():
    return ('<div class="status"><span>21:36</span><span class="r"><span class="mi">signal_cellular_alt</span><span class="mi">wifi</span><span class="mi">battery_full</span></span></div>'
            '<div class="appbar"><div class="back">' + mi('arrow_back') + '</div><span class="av" style="background-image:url(.cache/img/65.jpg)"></span>'
            '<div class="tt"><div class="n">晚风</div><div class="s">哔哩哔哩 · 唱见电台</div></div>'
            '<div class="fol on">' + rx('eb7b') + '已关注</div><div class="recbtn"><span class="ring"><i></i></span></div><div class="ib">' + rx('ea42') + '</div></div>'
            '<div class="video" style="background-image:url(.cache/img/158.jpg)"><div class="vtop"><div class="title">深夜电台 · 点歌接龙到天亮</div>'
            '<div class="ib vic">' + rx('ee05', 21) + '</div><div class="ib vic">' + rx('f235') + '</div><div class="ib vic">' + ci('e806') + '</div></div>'
            '<div class="vbot"><div class="ib vic">' + mr('pause', 28) + '</div><div class="ib vic">' + mr('refresh') + '</div><div class="ib vic"><span class="dmk open"></span></div>'
            '<div class="ib vic"><span class="dmk set"></span></div><div style="flex:1"></div><div class="ib vic">' + mr('screen_rotation_alt', 21) + '</div><div class="ib vic">' + mr('fullscreen', 26) + '</div></div></div>'
            '<div class="info"><div class="l1"><span class="t">深夜电台 · 点歌接龙到天亮</span><span class="more">详情' + rx('ea4e', 18) + '</span></div>'
            '<div class="l2"><div class="figs"><span class="fg"><span class="mr">people_alt</span><b>1.2万</b></span><span class="fg"><span class="mr">whatshot</span><b>84.7万</b></span>'
            '<span class="fg"><span class="mr">schedule</span><b>2:18</b></span></div><div class="chip">原画' + rx('ea4e', 18) + '</div><div class="chip">线路1' + rx('ea4e', 18) + '</div></div></div><hr>'
            '<div class="tabs"><div class="on">弹幕列表</div><div>醒目留言<span class="badge">2</span></div><div>弹幕设置</div><div>屏蔽管理</div></div>'
            + ''.join(f'<div class="row"><span class="u">{u}：</span>{t}</div>' for u, t in [('路过的风', '主播声音太温柔了'), ('夜猫子', '可以点《晴天》吗'), ('一只小熊', '这首歌好好听'),
                                                                                         ('清欢', '下一首想听《晚风》'), ('风吹麦浪', '来了来了'), ('小林同学', '今天也是被治愈的一天')])
            + '<div class="gesture"></div>')


def v4_pip_denied():
    dlg = ('<div class="scrim"></div><div class="dlg" style="top:50%;transform:translateY(-50%);left:24px;right:24px"><div class="h">无法打开画中画</div>'
           '<div class="b">系统设置里关掉了“纯粹直播”的画中画。打开后再点小窗按钮。</div>'
           '<div class="a"><span style="color:var(--onv)">取消</span><span class="ok">去设置</span></div></div>')
    return page(393, 852, 3, room_behind() + dlg + '<div class="syn">示意图片</div>', root='ph')


OUT = {
    'v3-float-phone': v3_float_phone(), 'v4-float-phone': v4_float_phone(),
    'v3-float-landscape': v3_float_landscape(), 'v4-float-landscape': v4_float_landscape(),
    'v3-float-wide': v3_float_wide(), 'v4-float-wide': v4_float_wide(),
    'v3-float-states': states(3), 'v4-float-states': states(4),
    'v3-pip-android': pip_android(3), 'v4-pip-android': pip_android(4),
    'v3-desktop-mini': desktop_mini(3), 'v4-desktop-mini': desktop_mini(4),
    'v3-desktop-zoom': desktop_zoom(3), 'v4-desktop-zoom': desktop_zoom(4),
    'v4-pip-denied': v4_pip_denied(),
}
for name, html in OUT.items():
    open(os.path.join(HERE, name + '.html'), 'w', encoding='utf-8').write(html)
print(len(OUT), 'pages')
