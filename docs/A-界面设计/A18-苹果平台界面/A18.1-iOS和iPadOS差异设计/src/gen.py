"""U.17a iOS and iPadOS: how the confirmed screens look on iPhone and iPad.

Only what the platform needs changes; the screens themselves come from the
other tasks' generators, which this file runs for their pieces (their own page
writes are discarded):
  U.2g/src/gen.py  live room in portrait (U.2a), landscape (U.2c) and wide
  U.2d/src/gen.py  wide live room with the 16:9 frame, the record panel (U.2f)
  U.3a/src/gen.py, U.3b/src/gen.py  home (phone, wide)

v3 (tag v3.2.11) on iOS, from code:
  ios/Runner/Info.plist  orientations :93-104, pointer events :87, no
      UIBackgroundModes; ShareExtension/ShareViewController.swift:11-32 (Xcode
      template), main.dart:105-106 (shares received on Android only)
  video_controller_panel.dart:52-61 (top bar slots: cast Android, PiP Android
      and Windows; time and battery on the right off Android), :321 :1425 (no
      safe area in fullscreen), lock button right 20 / middle
  live_play_back_scope.dart:120-121 (fullscreen blocks the route pop, so the
      iOS edge swipe does nothing), common/style/theme.dart:4-13 (no iOS
      builder: Flutter falls back to the Cupertino swipe-back transition)
  common/utils/share_command_handler.dart:64-66 (share sheet without a source
      rect), :217-220 ("分享失败，请重试")
  common/global/platform/desktop_manager.dart:597-625 + main.dart:53 (reads the
      clipboard at launch and on every resume, on every platform)
Sizes: iPhone 393x852 (safe area 59 / 34; landscape 59 left and right, 21
bottom), Dynamic Island 126x37 at 11; iPad 1180x820 (status bar 24, home
indicator 20), half split 585.

    python3 docs/ui/compare/U.17a/src/gen.py
    python3 tools/ui/mock/render.py docs/ui/compare/U.17a/src/ --annotate
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


G = load('U.2g')   # live room pieces (portrait, landscape, wide)
D = load('U.2d')   # wide room on the 16:9 frame, record panel
A = load('U.3a')   # phone home
B = load('U.3b')   # wide home
mr, mi, rx, ci, attrs = G.mr, G.mi, G.rx, G.ci, G.attrs
mo = lambda n, s=24: f'<span class="mo" style="font-size:{s}px">{n}</span>'


def ib(inner, n=None, cls='ib', tag=None, at=None):
    return f'<div class="{cls}"{attrs(n, tag, at)}>{inner}</div>'


ICON = '../../../apps/pure_live/assets/icons/icon.png'
TITLE = '深夜电台 · 点歌接龙到天亮'
LAND_TITLE = '纽约时代广场，夜游直播'

CSS = '''
html,body{background:#0E1014}
/* ---------- iPhone ---------- */
.ph.iph{border-radius:55px;display:flex;flex-direction:column}
.fs.ifs{border-radius:55px}
.ipad{border-radius:18px}
.isl{position:absolute;left:50%;top:11px;width:126px;height:37px;margin-left:-63px;border-radius:19px;background:#000;z-index:70}
.isl.r{left:auto;right:11px;top:50%;width:37px;height:126px;margin:-63px 0 0}
.ist{position:absolute;left:0;right:0;top:0;height:54px;z-index:69;display:flex;align-items:center;justify-content:space-between;font:600 16px/1 'Geist','Noto Sans SC';color:var(--on);pointer-events:none}
.ist .l{width:136px;text-align:center;padding-top:5px;font-feature-settings:'tnum'}
.ist .r{width:136px;display:flex;align-items:center;justify-content:center;gap:6px;padding-top:5px}
.ist.w,.ipst.w{color:#fff}
.sig{display:flex;align-items:flex-end;gap:1.5px;height:11px}.sig i{width:3px;border-radius:1px;background:currentColor}
.bt{position:relative;width:25px;height:12px;border-radius:4px;border:1px solid currentColor;padding:1.5px;opacity:.95}.bt i{display:block;height:100%;width:72%;border-radius:2px;background:currentColor}
.bt::after{content:'';position:absolute;right:-4px;top:3px;width:2px;height:4px;border-radius:0 1px 1px 0;background:currentColor;opacity:.5}
.hind{position:absolute;left:50%;bottom:8px;width:134px;height:5px;margin-left:-67px;border-radius:3px;background:#111;z-index:70}
.hind.w{background:rgba(255,255,255,.85)}
.hind.l{width:200px;margin-left:-100px}
.hind.p{width:320px;margin-left:-160px}
.top59{height:59px;flex:none}
.syn{top:auto !important;bottom:18px;left:44px;transform:none}
.cbtn{width:40px;height:40px;border-radius:20px;background:rgba(0,0,0,.54);border:1px solid rgba(255,255,255,.24);display:grid;place-items:center;color:#fff;flex:none}
.edge{position:absolute;z-index:8;border-radius:6px}
.capx{position:absolute;z-index:80;font:500 12px/1.45 'Noto Sans SC';padding:5px 9px;border-radius:7px;background:rgba(25,28,32,.82);color:#fff;max-width:300px}
/* ---------- safe area diagram ---------- */
.sa{position:absolute;z-index:66;background:repeating-linear-gradient(45deg,rgba(217,45,32,.30) 0 6px,rgba(217,45,32,.12) 6px 12px)}
.sal{position:absolute;z-index:75;font:600 12px/1.3 'Noto Sans SC';color:#B42318;background:#fff;padding:3px 7px;border-radius:5px;box-shadow:0 1px 4px rgba(0,0,0,.25);white-space:nowrap}
/* ---------- system UI (drawn by iOS; shown only to place our parts) ---------- */
.home-ios{position:absolute;inset:0;background:url(.cache/img/338.jpg) center/cover}
.home-ios::before{content:'';position:absolute;inset:0;background:rgba(0,0,0,.15)}
.apps{position:absolute;left:28px;right:28px;top:84px;display:grid;grid-template-columns:repeat(4,1fr);gap:28px 0;justify-items:center;z-index:1}
.apps div,.dock div{display:flex;flex-direction:column;align-items:center;gap:6px;font-size:11px;color:#fff;text-shadow:0 1px 2px rgba(0,0,0,.4)}
.apps i,.dock i{width:62px;height:62px;border-radius:15px;display:block;background:center/cover}
.dock{position:absolute;left:14px;right:14px;bottom:24px;height:94px;border-radius:32px;background:rgba(255,255,255,.35);display:flex;justify-content:space-around;align-items:center;z-index:1}
.pipw{position:absolute;z-index:40;border-radius:12px;overflow:hidden;background:#000 url(.cache/img/158.jpg) center 55%/cover;box-shadow:0 10px 30px rgba(0,0,0,.4)}
.pipw .dim{position:absolute;inset:0;background:rgba(0,0,0,.32)}
.pipw .b{position:absolute;color:#fff;display:grid;place-items:center}
.alert{position:absolute;z-index:61;left:50%;top:50%;width:270px;transform:translate(-50%,-50%);border-radius:14px;background:#F2F2F7;text-align:center;overflow:hidden;color:#000}
.alert .h{padding:19px 16px 2px;font-size:16px;font-weight:600;line-height:1.35}.alert .m{padding:0 16px 18px;font-size:13px;line-height:1.4}
.alert .a{display:flex;border-top:1px solid #C7C7CC}.alert .a span{flex:1;height:44px;display:grid;place-items:center;font-size:16px;color:#0A64D6}
.alert .a span+span{border-left:1px solid #C7C7CC;font-weight:600}
.shs{position:absolute;left:0;right:0;bottom:0;z-index:61;background:#F2F2F7;border-radius:28px 28px 0 0;color:#000;padding:18px 16px 40px}
.shs .hd{display:flex;align-items:center;gap:12px;padding:0 2px 14px;border-bottom:1px solid #D1D1D6}
.shs .hd i{width:46px;height:46px;border-radius:10px;background:#fff center/80% no-repeat;flex:none;box-shadow:0 0 0 .5px rgba(0,0,0,.12)}
.shs .hd .x{flex:1;min-width:0}.shs .hd .t{font-size:15px;font-weight:600}.shs .hd .s{font-size:12px;color:#6C6C70;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;margin-top:2px}
.shs .hd .c{width:30px;height:30px;border-radius:15px;background:#E3E3E8;display:grid;place-items:center;color:#6C6C70;flex:none}
.shs .ap{display:flex;justify-content:space-between;padding:16px 4px 14px}
.shs .ap div{width:68px;display:flex;flex-direction:column;align-items:center;gap:6px;font-size:11px;color:#3C3C43;text-align:center;line-height:1.25}
.shs .ap i{width:60px;height:60px;border-radius:14px;display:grid;place-items:center;color:#fff;font-style:normal;background:center/80% no-repeat}
.shs .grp{background:#fff;border-radius:12px;overflow:hidden}
.shs .grp div{height:46px;display:flex;align-items:center;justify-content:space-between;padding:0 16px;font-size:15px;border-bottom:1px solid #E5E5EA}
.shs .grp div:last-child{border:0}.shs .grp .mo,.shs .grp .mr{color:#3C3C43}
.hl{box-shadow:0 0 0 3px #0A64D6;border-radius:16px}
.sbar{position:absolute;z-index:62;left:12px;right:12px;display:flex;align-items:center;gap:8px;min-height:48px;padding:6px 6px 6px 16px;border-radius:12px;background:#2E3135;color:#EFF0F7;font-size:14px;box-shadow:0 3px 10px rgba(0,0,0,.25)}
.sbar .x{flex:1;line-height:1.4}.sbar .go{height:36px;padding:0 12px;border-radius:18px;display:flex;align-items:center;color:#A0CAFD;font-weight:600;flex:none}
.sbar .cl{width:36px;height:36px;display:grid;place-items:center;color:#C3C7CF;flex:none}
.cmp{position:absolute;z-index:61;left:20px;right:20px;top:120px;border-radius:14px;background:#fff;overflow:hidden;box-shadow:0 10px 30px rgba(0,0,0,.25);color:#000}
.cmp .nb2{height:46px;display:flex;align-items:center;justify-content:space-between;padding:0 14px;border-bottom:1px solid #D1D1D6;font-size:16px}
.cmp .nb2 span:first-child,.cmp .nb2 span:last-child{color:#0A64D6}.cmp .nb2 b{font-weight:600}
.cmp .bd{display:flex;gap:10px;padding:12px 14px;height:150px}.cmp .bd p{flex:1;font-size:15px;line-height:1.4;word-break:break-all}
.cmp .bd i{width:64px;height:64px;border-radius:6px;background:#E5E5EA;flex:none;display:grid;place-items:center;color:#8E8E93;font-style:normal}
/* ---------- iPad ---------- */
.ipst{position:absolute;left:0;right:0;top:0;height:24px;z-index:69;display:flex;align-items:center;justify-content:space-between;padding:0 20px 0 24px;font:600 13px/1 'Geist','Noto Sans SC';color:var(--on);pointer-events:none}
.ipst .r{display:flex;align-items:center;gap:6px}
.ptr{position:absolute;z-index:75;width:20px;height:20px;border-radius:10px;background:rgba(60,60,67,.55);box-shadow:0 0 0 1px rgba(255,255,255,.6)}
.hovc{position:relative}.hovc::after{content:'';position:absolute;inset:0;border-radius:20px;background:rgba(25,28,32,.07);box-shadow:inset 0 0 0 1px rgba(25,28,32,.12)}
.wctl{position:absolute;z-index:72;display:flex;gap:8px}.wctl i{width:12px;height:12px;border-radius:6px;display:block}
.wctl .c{background:#FF5F57;box-shadow:inset 0 0 0 .5px #E0443E}.wctl .m{background:#FEBC2E;box-shadow:inset 0 0 0 .5px #DEA123}.wctl .z{background:#28C840;box-shadow:inset 0 0 0 .5px #1AAB29}
.hud{position:absolute;z-index:65;border-radius:22px;background:#fff;box-shadow:0 18px 50px rgba(0,0,0,.35);color:#000;padding:18px 22px 20px}
.hud .h{display:flex;align-items:center;gap:10px;font-size:15px;font-weight:600;padding-bottom:12px;border-bottom:1px solid #E5E5EA}
.hud .h i{width:28px;height:28px;border-radius:7px;background:center/90% no-repeat;display:block}
.hud .cols{display:grid;grid-template-columns:repeat(4,1fr);gap:0 26px;padding-top:12px}
.hud .g{font-size:12px;font-weight:600;color:#6C6C70;margin:8px 0 4px}
.hud .hk{display:flex;justify-content:space-between;gap:10px;font-size:13px;line-height:25px;white-space:nowrap}.hud .hk b{font-weight:400;color:#6C6C70;font-family:'Geist','Noto Sans SC'}
.pop{position:absolute;z-index:62;width:360px;border-radius:14px;background:#F2F2F7;box-shadow:0 12px 40px rgba(0,0,0,.28);color:#000;padding:14px 14px 16px}
.pop::before{content:'';position:absolute;top:-9px;right:var(--ar,24px);width:18px;height:18px;background:#F2F2F7;transform:rotate(45deg);border-radius:3px}
.gsnack{position:absolute;z-index:62;left:10px;right:10px;border-radius:15px;background:#FFDAD6;color:#410002;padding:14px 18px}
.gsnack b{display:block;font-size:16px;font-weight:800;margin-bottom:4px}.gsnack span{font-size:14px}
.split{position:absolute;top:0;bottom:0;width:10px;background:#000;z-index:68;display:grid;place-items:center}.split i{width:4px;height:44px;border-radius:2px;background:#8E8E93;display:block}
.other{position:absolute;top:0;bottom:0;background:#fff;z-index:2;overflow:hidden}
.other .ln2{height:12px;border-radius:6px;background:#E5E5EA;margin:16px 28px}
.stg{position:absolute;inset:0;background:url(.cache/img/287.jpg) center/cover}
.stg::before{content:'';position:absolute;inset:0;background:rgba(0,0,0,.12)}
.shelf{position:absolute;left:18px;width:120px;border-radius:10px;background:rgba(255,255,255,.55);box-shadow:0 6px 18px rgba(0,0,0,.25);z-index:3}
.idock{position:absolute;left:50%;bottom:10px;transform:translateX(-50%);height:74px;padding:0 12px;border-radius:26px;background:rgba(255,255,255,.4);display:flex;gap:12px;align-items:center;z-index:4}
.idock i{width:54px;height:54px;border-radius:13px;display:block;background:center/cover}
.iwin{position:absolute;z-index:10;border-radius:16px;overflow:hidden;box-shadow:0 18px 50px rgba(0,0,0,.35);background:var(--surface)}
'''


def doc(w, h, scale, body, *css, crop=False):
    """css: the other tasks' style sheets this page needs (they disagree on
    shared class names such as .win, so each page takes only its own)."""
    style = ''.join(css) + CSS
    return (f'<!doctype html><html><head><meta charset="utf-8"><meta name="mock-size" content="{w}x{h}@{scale}{" crop" if crop else ""}">'
            f'<link rel="stylesheet" href="kit/kit.css"><style>{style}</style></head><body>{body}</body></html>')


# ======================================================================
# iPhone frame
# ======================================================================
def ios_status(white=False):
    sig = '<span class="sig">' + ''.join(f'<i style="height:{h}px"></i>' for h in (4, 6, 8, 10)) + '</span>'
    return (f'<div class="ist{" w" if white else ""}"><span class="l">21:36</span><span class="r">{sig}'
            + mi('wifi', 17) + '<span class="bt"><i></i></span></span></div>')


def iphone(inner, extra='', white=False, syn=True, root_extra=''):
    """393x852 with the Dynamic Island, the status bar and the home indicator;
    inner starts below the 59-pt top safe area."""
    s = '<div class="syn">示意图片</div>' if syn else ''
    return (f'<div class="ph iph"{root_extra}>{ios_status(white)}<div class="top59"></div>{inner}{extra}'
            f'<div class="isl"></div><div class="hind{" w" if white else ""}"></div>{s}</div>')


def iphone_land(inner, island='r'):
    """852x393 landscape: island on the right (the phone turned the other way
    puts it on the left; the safe area is 59 on both sides either way)."""
    return (f'<div class="fs ifs" style="--w:852px;--h:393px">{inner}<div class="isl r"></div>'
            '<div class="hind w l"></div><div class="syn" style="top:66px !important;left:auto;right:86px;bottom:auto">示意图片</div></div>')


# ---------- live room, portrait (U.2a) ----------
def ios_bars_portrait(ver, n=False):
    """Top bar: v3 on iOS has only the audio button (cast is Android, PiP
    Android and Windows); the new design adds PiP (U.2j c5), no cast."""
    N = (lambda k: k) if n else (lambda k: None)
    T = (lambda t: t) if n else (lambda t: None)
    if ver == 3:
        top = f'<div class="v3top"><div class="title"><b>{TITLE}</b></div>' + ib(rx('ee05', 21)) + '</div>'
        bot = ('<div class="v3bot">' + ib(mr('pause', 28)) + ib(mr('refresh')) + '<div class="v3pill">' + mr('check', 15) + '已关注</div>'
               + ib('<span class="dmk open"></span>') + ib('<span class="dmk set"></span>') + ib(mr('screen_rotation_alt', 21))
               + '<div style="flex:1"></div>' + ib(mr('fullscreen', 26)) + '</div>')
        return top + bot
    top = (f'<div class="vtop"><div class="title">{TITLE}</div>' + ib(rx('ee05', 21), N(3), 'ib vic', T('keep'))
           + ib(ci('e806'), N(4), 'ib vic', T('add')) + '</div>')
    bot = ('<div class="vbot">' + ib(mr('pause', 28), None, 'ib vic') + ib(mr('refresh'), None, 'ib vic') + ib('<span class="dmk open"></span>', None, 'ib vic')
           + ib('<span class="dmk set"></span>', None, 'ib vic') + '<div style="flex:1"></div>' + ib(mr('screen_rotation_alt', 21), N(7), 'ib vic', T('keep'))
           + ib(mr('fullscreen', 26), N(6), 'ib vic', T('keep')) + '</div>')
    return top + bot


def v4_header_ios(n=False):
    h = G.v4_header()
    if n:
        h = h.replace('<div class="back">', '<div class="back" data-n="2" data-tag="keep">', 1)
        h = h.replace('<div class="ib" style="width:44px">', '<div class="ib" style="width:44px" data-n="5" data-tag="chg">', 1)
    return h


def chat_ios(k=11):
    # the list may run under the home indicator, its last line stays above it (34)
    return G.chat_live(k).replace('padding:4px 0 14px', 'padding:4px 0 40px')


def room_v4(n=False, extra=''):
    edge = '<div class="edge" style="left:0;top:59px;bottom:34px;width:18px"' + (' data-n="1" data-tag="keep" data-at="c"' if n else '') + '></div>'
    body = (v4_header_ios(n) + '<div class="vbox">' + G.pic() + ios_bars_portrait(4, n) + '</div>' + G.v4_info()
            + '<div style="flex:1;min-height:0;display:flex;flex-direction:column;overflow:hidden">' + chat_ios() + '</div>')
    return iphone(body, edge + extra)


def room_v3():
    body = (G.v3_header() + '<div class="vbox">' + G.pic() + ios_bars_portrait(3) + '</div>' + G.v3_res_row()
            + '<hr>' + G.TABS0 + '<div style="flex:1;min-height:0;display:flex;flex-direction:column;justify-content:flex-end;overflow:hidden;padding-bottom:40px">'
            + G.v3_cards(6) + '</div>')
    return iphone(body)


# ---------- live room, landscape fullscreen (U.2c) ----------
LAND_PIC = '<div class="pic" style="background-image:url(.cache/img/274.jpg);background-position:center 40%"></div>'
def land_dm(shift=0):
    return ''.join(f'<div class="dm" style="left:{x + shift}px;top:{y}px">{t}</div>'
                   for x, y, t in ((300, 96, '前排支持！'), (150, 150, '这条街好热闹'), (470, 206, '主播带我们去时代广场'), (230, 252, '晚上好～')))


def full_v3():
    """v3 on iPhone: no safe area; time and battery on the right (not
    Android); no cast, no PiP; composer full because the screen is 852 wide."""
    top = ('<div class="v3top">' + ib(mi('arrow_back')) + f'<div class="title"><b>{LAND_TITLE}</b></div>'
           + '<div class="v3swap">' + mr('swap_horiz') + '</div><div class="time" style="padding:0 4px">21:36</div><div class="bat" style="margin:0 8px">76</div>'
           + ib(rx('ee05', 21)) + '</div>')
    comp = '<div class="v3comp"><span class="a" style="color:#fff">' + mr('auto_awesome', 18) + '</span>发送一条本地字幕<span class="s">' + mr('send', 18) + '</span></div>'
    bot = ('<div class="v3bot" style="padding:0 16px">' + ib(mr('pause', 28)) + ib(mr('refresh')) + '<div class="v3pill">' + mr('check', 15) + '已关注</div>'
           + ib('<span class="dmk open"></span>') + ib('<span class="dmk set"></span>') + '<div style="flex:1;display:flex;justify-content:center">' + comp + '</div>'
           + '<div class="v3sel">' + mr('tune', 17) + '原画 · 线路1</div>' + ib(mr('screen_rotation_alt', 21)) + '<div class="v3fit">默认比例</div>'
           + ib(mr('fullscreen_exit', 26)) + '</div>')
    lock = '<div class="lock">' + mr('lock_open', 28) + '</div>'
    return iphone_land(LAND_PIC + land_dm() + top + bot + lock)


SIDE, LBOT = 59, 21


def full_v4(n=False, recording=True):
    """U.2c inside the safe area: 59 left and right, 21 at the bottom; the
    composer collapses to its button there (U.2c's narrow rule)."""
    N = (lambda k: k) if n else (lambda k: None)
    T = (lambda t: t) if n else (lambda t: None)
    lead = ib(mi('arrow_back'), N(1), 'ib vic', T('chg')) + '<div class="time">21:36</div><div class="bat">76</div>'
    trail = (ib(mr('swap_horiz'), None, 'ib vic') + ib(rx('ee05', 21), None, 'ib vic') + ib(ci('e806'), N(3), 'ib vic', T('add'))
             + '<div class="ib">' + ('<span class="recon"><i></i></span>' if recording else '<span class="vring"><i></i></span>') + '</div>' + ib(rx('ea42'), None, 'ib vic'))
    top = f'<div class="vtop" style="padding:4px {SIDE}px 0">{lead}<div class="title">{LAND_TITLE}</div>{trail}</div>'
    bot = (f'<div class="vbot" style="padding:0 {SIDE}px {LBOT}px;height:{76 + LBOT}px">' + ib(mr('pause', 28), None, 'ib vic') + ib(mr('refresh'), None, 'ib vic')
           + '<div class="vfol">' + rx('eb7b') + '已关注</div>' + ib('<span class="dmk open"></span>', None, 'ib vic') + ib('<span class="dmk set"></span>', None, 'ib vic')
           + '<div style="flex:1;display:flex;justify-content:center;height:48px;align-items:center"><div class="cbtn"' + attrs(N(4), T('chg')) + '>' + mr('auto_awesome', 18) + '</div></div>'
           + '<div class="vchip" style="margin:0 3px">原画' + rx('ea4e', 18) + '</div><div class="vchip" style="margin:0 3px">线路1' + rx('ea4e', 18) + '</div>'
           + ib(mr('screen_rotation_alt', 21), None, 'ib vic') + ib(rx('ea80', 22), None, 'ib vic') + ib(mr('fullscreen_exit', 26), N(6), 'ib vic', T('keep')) + '</div>')
    lock = f'<div class="lock" style="right:{SIDE + 12}px"' + attrs(N(5), T('chg')) + '>' + mr('lock_open', 28) + '</div>'
    badge = f'<div class="vbadge" style="top:60px;left:{SIDE + 8}px"><i></i>录制中 12:34</div>' if recording else ''
    edge = '<div class="edge" style="left:0;top:70px;bottom:110px;width:18px"' + attrs(N(2), T('add'), 'c' if n else None) + '></div>'
    return iphone_land(LAND_PIC + land_dm() + top + bot + lock + badge + edge)


# ---------- safe area diagram ----------
def safe_diagram():
    portrait = room_v4().replace('<div class="syn">示意图片</div>', '')
    bands_p = ('<div class="sa" style="left:0;right:0;top:0;height:59px"></div><div class="sa" style="left:0;right:0;bottom:0;height:34px"></div>')
    land = full_v4(recording=False).replace('<div class="syn" style="top:66px !important;left:auto;right:86px;bottom:auto">示意图片</div>', '')
    bands_l = ('<div class="sa" style="left:0;top:0;bottom:0;width:59px"></div><div class="sa" style="right:0;top:0;bottom:0;width:59px"></div>'
               '<div class="sa" style="left:59px;right:59px;bottom:0;height:21px"></div>')
    portrait = portrait.replace('<div class="isl"></div>', bands_p + '<div class="isl"></div>', 1)
    land = land.replace('<div class="isl r"></div>', bands_l + '<div class="isl r"></div>', 1)
    labels = ('<div class="sal" style="left:436px;top:40px">← 上 59：状态栏和灵动岛</div>'
              '<div class="sal" style="left:436px;top:852px">← 下 34：主屏指示条</div>'
              '<div class="sal" style="left:460px;top:262px">左右各 59：圆角和灵动岛（转向哪边都一样）</div>'
              '<div class="sal" style="left:860px;top:704px">↑ 下 21：主屏指示条</div>'
              '<div class="sal" style="left:460px;top:752px;color:#191C20;font-weight:400;white-space:normal;width:840px;font-size:14px;line-height:1.6">画面照常铺满（16:9 的画面左右本来就有黑边）；'
              '只有按钮、文字、锁定键放进安全区。竖屏时内容从灵动岛下面开始，弹幕列表可以滚到指示条下面，最后一行留在它上面。</div>')
    body = (f'<div style="position:relative;width:1340px;height:900px;background:#E7E9EC">'
            f'<div style="position:absolute;left:24px;top:24px">{portrait}</div>'
            f'<div style="position:absolute;left:460px;top:300px">{land}</div>{labels}</div>')
    return doc(1340, 900, 1.25, body, G.CSS)


# ---------- home (U.3a) ----------
HOME_CSS = '.nb{height:114px;padding-bottom:34px}.ph.iph .main{flex:1}'


def home_ios(extra=''):
    nav = A.nav_bar(0, 'shapes').replace('<div class="gesture"></div>', '')
    inner = A.v4_bar_favorites(False) + '<div class="main">' + A.favorites_body() + '</div>' + nav
    return iphone(inner, extra)


# ---------- PiP on the home screen ----------
def pip_ios():
    names = ['相机', '照片', '日历', '天气', '时钟', '地图', '备忘录', '设置', '提醒事项', '音乐', '文件', '纯粹直播']
    cols = ['#9AA5B1', '#F2C1D6', '#F4C7B8', '#BFD8F2', '#2F3237', '#C8E6C9', '#FFE0A3', '#8E8E93', '#FFFFFF', '#F28CA0', '#9EC5F2', '#FFFFFF']
    apps = ''.join(f'<div><i style="background-color:{c}' + (f';background-image:url({ICON});background-size:80%;background-repeat:no-repeat;background-position:center' if nm == '纯粹直播' else '') + f'"></i>{nm}</div>'
                   for nm, c in zip(names, cols))
    dock = ''.join(f'<div><i style="background:{c}"></i></div>' for c in ('#7BD389', '#5AA9F0', '#9EC5F2', '#F2994A'))
    w, h, x, y = 240, 135, 393 - 16 - 240, 468
    pip = (f'<div class="pipw" style="left:{x}px;top:{y}px;width:{w}px;height:{h}px"><div class="dim"></div>'
           f'<div class="b" style="left:8px;top:8px;width:30px;height:30px">' + mr('open_in_full', 20) + '</div>'
           f'<div class="b" style="right:8px;top:8px;width:30px;height:30px">' + mr('close', 22) + '</div>'
           f'<div class="b" style="left:50%;top:50%;width:48px;height:48px;margin:-24px 0 0 -24px">' + mr('pause', 40) + '</div></div>')
    cap = ('<div class="capx" style="left:16px;top:640px;max-width:361px">系统画中画（窗口、圆角、三个按钮由系统画）：左上回到应用，右上关闭（停止播放），中间暂停；'
           '直播没有快进快退。可以拖到屏幕边上藏起来，双指缩放大小。里面只有画面，没有弹幕和录制角标。</div>')
    inner = f'<div class="home-ios"></div><div class="apps">{apps}</div><div class="dock">{dock}</div>{pip}{cap}'
    return doc(393, 852, 3, iphone(inner, white=True, syn=False).replace('<div class="top59"></div>', '') + '')


# ---------- share sheet (system) ----------
def share_sheet(mode):
    if mode == 'out':
        head = ('<div class="hd"><i style="background-image:url(' + ICON + ')"></i><div class="x"><div class="t">纯粹直播分享口令</div>'
                '<div class="s">gqFtqXB1cmVfbGl2ZaFwqGJpbGliaWxp…</div></div><div class="c">' + mr('close', 18) + '</div></div>')
        apps = [('#34C759', mr('sms', 30), '信息'), ('#0A84FF', mr('mail', 28), '邮件'), ('#FFCC00', mr('sticky_note_2', 28), '备忘录'), ('#E5E5EA', '<span style="color:#3C3C43">' + mr('more_horiz', 30) + '</span>', '更多')]
        acts = [('拷贝', mo('content_copy', 22)), ('存储到“文件”', mo('folder', 22)), ('编辑操作…', '')]
    else:
        head = ('<div class="hd"><i style="background:#8E8E93;display:grid;place-items:center;color:#fff">' + mr('link', 26) + '</i><div class="x"><div class="t">深夜电台 · 点歌接龙到天亮</div>'
                '<div class="s">live.bilibili.com/1234567</div></div><div class="c">' + mr('close', 18) + '</div></div>')
        apps = [('#34C759', mr('sms', 30), '信息'), ('#0A84FF', mr('mail', 28), '邮件'), ('#FFFFFF', '', '纯粹直播'), ('#E5E5EA', '<span style="color:#3C3C43">' + mr('more_horiz', 30) + '</span>', '更多')]
        acts = [('拷贝', mo('content_copy', 22)), ('用 Safari 浏览器打开', mo('explore', 22)), ('编辑操作…', '')]
    ap = ''
    for col, icon, label in apps:
        st = f'background-color:{col}' + (f';background-image:url({ICON})' if label == '纯粹直播' else '')
        hl = ' class="hl"' if (mode == 'in' and label == '纯粹直播') else ''
        ap += f'<div><i style="{st}"{hl}>{icon}</i>{label}</div>'
    grp = ''.join(f'<div><span>{t}</span>{ic}</div>' for t, ic in acts)
    return f'<div class="shs">{head}<div class="ap">{ap}</div><div class="grp">{grp}</div></div>'


def share_out():
    return doc(393, 852, 3, room_v4(extra='<div class="scrim" style="z-index:60;background:rgba(0,0,0,.35)"></div>' + share_sheet('out')), G.CSS)


def other_app():
    lines = ''.join(f'<div style="height:12px;border-radius:6px;background:#E5E5EA;margin:14px 20px;width:{w}%"></div>' for w in (60, 88, 92, 70, 84, 66, 90, 58))
    return ('<div style="position:absolute;left:0;right:0;top:59px;bottom:0;background:#fff"><div style="height:200px;margin:12px 16px;border-radius:12px;background:#000 url(.cache/img/158.jpg) center/cover"></div>'
            + lines + '<div class="capx" style="left:16px;top:6px">其他应用（示意）</div></div>')


def share_in():
    cap = ('<div class="capx" style="left:16px;top:208px;max-width:361px;z-index:90">选“纯粹直播”：直接打开应用；直播间链接进直播间，'
           '分享口令弹“口令导入”（U.3d），播放列表和节目单文件走导入（U.9），和 Android 收到分享一样（U.14）</div>')
    return doc(393, 852, 3, iphone(other_app() + '<div class="scrim" style="z-index:60;background:rgba(0,0,0,.35)"></div>' + share_sheet('in') + cap, syn=False))


def share_in_v3():
    cmp = ('<div class="cmp"><div class="nb2"><span>取消</span><b>ShareExtension</b><span>发布</span></div>'
           '<div class="bd"><p>深夜电台 · 点歌接龙到天亮 https://live.bilibili.com/1234567</p><i>' + mr('link', 26) + '</i></div></div>')
    cap = ('<div class="capx" style="left:16px;top:320px;max-width:361px;z-index:90">v3：选“纯粹直播”后弹出 Xcode 模板的发布框，'
           '点“发布”什么也不做（ShareViewController.swift:18-23）；应用本身也只在 Android 接收分享（main.dart:105-106）</div>')
    return doc(393, 852, 3, iphone(other_app() + '<div class="scrim" style="z-index:60;background:rgba(0,0,0,.35)"></div>' + cmp + cap, syn=False))


# ---------- clipboard share codes ----------
def paste_v3():
    alert = ('<div class="scrim" style="z-index:60;background:rgba(0,0,0,.25)"></div><div class="alert"><div class="h">“纯粹直播”想从“哔哩哔哩”粘贴</div>'
             '<div class="m">是否允许？</div><div class="a"><span>不允许粘贴</span><span>允许粘贴</span></div></div>')
    cap = '<div class="capx" style="left:16px;top:560px;max-width:361px;z-index:90">v3：每次回到前台都读剪贴板（desktop_manager.dart:612-625），iOS 16 起每次都弹这个系统提示（示意）</div>'
    return doc(393, 852, 3, home_ios(alert + cap), A.CSS, HOME_CSS)


def paste_v4(n=False):
    bar = ('<div class="sbar" style="bottom:126px"><span class="x">剪贴板里有新内容，要识别分享口令吗？</span>'
           '<span class="go"' + attrs(1 if n else None, 'add' if n else None) + '>识别</span><span class="cl">' + mr('close', 20) + '</span></div>')
    return doc(393, 852, 3, home_ios(bar), A.CSS, HOME_CSS)


# ---------- record panel in landscape (U.2f) ----------
def panel_land():
    pw = 360 + SIDE
    top = f'<div class="vtop" style="padding:4px {pw}px 0 {SIDE}px">' + ib(mi('arrow_back'), None, 'ib vic') + '<div class="time">21:36</div><div class="bat">76</div><div class="title">' + LAND_TITLE + '</div></div>'
    side = (f'<div class="side" style="width:{pw}px;padding-right:{SIDE}px;padding-bottom:{LBOT}px;border-radius:16px 0 0 16px">' + D.record_panel() + '</div>')
    badge = f'<div class="vbadge" style="top:60px;left:{SIDE + 8}px"><i></i>录制中 12:34</div>'
    return doc(852, 393, 2, iphone_land(LAND_PIC + land_dm(-60) + top + badge + side), G.CSS, D.CSS)


# ======================================================================
# iPad
# ======================================================================
def ipad_status(white=False):
    return (f'<div class="ipst{" w" if white else ""}"><span>21:36&nbsp;&nbsp;10月1日周三</span><span class="r">' + mi('wifi', 15)
            + '<span style="font-weight:500">100%</span><span class="bt"><i style="width:100%"></i></span></span></div>')


def ipad_home():
    body = (B.v4_rail(0, n=False) + '<div class="body">' + B.fav_page(4) + '</div>')
    # pointer over a card: the same hover as the desktop (U.4a), the pointer is the system's
    body = body.replace('<div class="card">', '<div class="card hovc">', 2).replace('<div class="card hovc">', '<div class="card">', 1)
    ptr = '<div class="ptr" style="left:600px;top:250px"></div>'
    tip = '<div class="tip" style="left:520px;top:276px;z-index:76">王者上分，今晚冲国服 · 一只小熊</div>'
    inner = (f'<div class="win ipad" style="--w:1180px;--h:820px;padding-top:24px">{ipad_status()}{body}{ptr}{tip}'
             '<div class="hind p"></div><div class="syn" style="left:auto;right:16px;bottom:30px;transform:none">示意图片</div></div>')
    return doc(1180, 820, 1.5, inner, A.CSS, B.CSS)


def strip_n(html):
    return re.sub(r' data-(n|tag|at)="[^"]*"', '', html)


def d_body(w, h, windows, recording=False, panel=False):
    """U.2d's page body (header + 16:9 stage + chat column) without the html shell."""
    page = D.v4(w, h, 1.5, windows=windows, recording=recording, panel=panel, n=False)
    m = re.search(r'<div class="win" style="[^"]*">(.*)<div class="syn"', page, re.S)
    return strip_n(m.group(1))   # U.2d numbers its own header; not ours to number here


def ipad_room():
    body = d_body(1180, 796, windows=False)
    body = body.replace(D.ib(D.rx('f235'), None, 'ib vic'), '', 1)   # no cast on iPad
    body = body.replace('<div class="list">', '<div class="list" style="padding-bottom:30px">')
    inner = (f'<div class="win ipad" style="--w:1180px;--h:820px;padding-top:24px">{ipad_status()}{body}'
             '<div class="hind p"></div><div class="syn" style="left:auto;right:16px;bottom:30px;transform:none">示意图片</div></div>')
    return doc(1180, 820, 1.5, inner, D.CSS)


def phone_room_body(w):
    """The phone arrangement at any width below 600 (U.2a): header, 16:9, info, chat."""
    return (G.v4_header() + '<div class="vbox">' + G.pic(w=w, h=w * 9 / 16) + ios_bars_portrait(4) + '</div>' + G.v4_info()
            + '<div style="flex:1;min-height:0;display:flex;flex-direction:column;overflow:hidden">' + chat_ios(14) + '</div>')


def ipad_split():
    lw = 585
    left = (f'<div style="position:absolute;left:0;top:0;bottom:0;width:{lw}px;display:flex;flex-direction:column;background:var(--surface)">'
            f'<div style="height:24px;flex:none"></div>{phone_room_body(lw)}</div>')
    lines = ''.join(f'<div class="ln2" style="width:{w}%"></div>' for w in (50, 86, 92, 72, 84, 64, 90, 58, 80, 70, 88, 62, 76, 90, 54, 82))
    right = (f'<div class="other" style="left:{lw + 10}px;right:0;padding-top:40px">{lines}'
             '<div class="capx" style="left:24px;top:36px">另一个应用（示意）</div></div>')
    cap = ('<div class="capx" style="left:24px;top:640px;z-index:80;max-width:520px">纯粹直播占一半（585 宽，小于 600）：按手机排法（U.2a），'
           '和 iPhone 一样；拖动中间的分隔条变宽到 600 以上换成宽屏排法，播放不中断。</div>')
    inner = (f'<div class="win ipad" style="--w:1180px;--h:820px;background:#000">{left}<div class="split" style="left:{lw}px"><i></i></div>{right}'
             f'{ipad_status()}{cap}<div class="hind p"></div><div class="syn" style="left:16px;bottom:30px;transform:none">示意图片</div></div>')
    return doc(1180, 820, 1.5, inner, G.CSS)


def ipad_stage():
    ww, wh, wx, wy = 760, 600, 220, 70
    rail = B.v4_rail(0, n=False).replace('<div class="rail">', '<div class="rail"><div style="height:38px;flex:none"></div>', 1)
    page = rail + '<div class="body">' + B.fav_page(3) + '</div>'
    win = (f'<div class="iwin" style="left:{wx}px;top:{wy}px;width:{ww}px;height:{wh}px"><div class="win" style="--w:{ww}px;--h:{wh}px">{page}</div>'
           '<div class="wctl" style="left:14px;top:14px"><i class="c"></i><i class="m"></i><i class="z"></i></div></div>')
    shelf = ''.join(f'<div class="shelf" style="top:{y}px;height:86px;background:rgba(255,255,255,.65) url(.cache/img/{img}.jpg) center/cover"></div>'
                    for y, img in ((150, 304), (270, 319), (390, 342)))
    dock = '<div class="idock">' + ''.join(f'<i style="background:{c}"></i>' for c in ('#7BD389', '#5AA9F0', '#FFFFFF', '#F2994A', '#9EC5F2', '#F28CA0')) + '</div>'
    dock = dock.replace('background:#FFFFFF', f'background:#fff url({ICON}) center/80% no-repeat', 1)
    cap = (f'<div class="capx" style="left:{wx}px;top:{wy + wh + 14}px;max-width:{ww}px;z-index:80">台前调度的窗口（760×600）：按宽度排（600–839 是侧边导航，U.3b）；'
           '窗口左上角是系统的三个窗口按钮（iPadOS 26 起），侧边栏顶部给它们留出位置，和 macOS 同一个做法（U.17b）。</div>')
    inner = (f'<div class="win ipad" style="--w:1180px;--h:820px"><div class="stg"></div>{shelf}{win}{dock}{ipad_status(white=True)}{cap}'
             '<div class="hind p w"></div><div class="syn" style="left:auto;right:16px;bottom:96px;transform:none">示意图片</div></div>')
    return doc(1180, 820, 1.5, inner, A.CSS, B.CSS)


SHORTCUTS = [
    ('纯粹直播', [('设置…', '⌘,')]),
    ('文件', [('链接解析…', '⌘L')]),
    ('编辑', [('搜索直播…', '⌘F')]),
    ('显示', [('关注', '⌘1'), ('热门', '⌘2'), ('分区', '⌘3'), ('录制中心', '⌘4'), ('历史记录', '⌘Y'), ('返回', '⌘['), ('全屏', '⌃⌘F')]),
    ('播放', [('播放 / 暂停', '空格'), ('刷新', '⌘R'), ('调高音量', '↑'), ('调低音量', '↓'), ('显示弹幕', '—'), ('纯音频', '—'), ('小窗', '—')]),
]


def ipad_keys():
    body = d_body(1180, 796, windows=False)
    body = body.replace(D.ib(D.rx('f235'), None, 'ib vic'), '', 1)
    cols = {0: [], 1: [], 2: [], 3: []}
    place = {'纯粹直播': 0, '文件': 0, '编辑': 0, '显示': 1, '播放': 2}
    for g, items in SHORTCUTS:
        items = [(t, k) for t, k in items if k != '—']   # the list shows only commands with a key
        cols[place[g]].append(f'<div class="g">{g}</div>' + ''.join(f'<div class="hk"><span>{t}</span><b>{k}</b></div>' for t, k in items))
    cols[3].append('<div class="g">v3 的单键（照旧）</div>' + ''.join(f'<div class="hk"><span>{t}</span><b>{k}</b></div>' for t, k in
                   (('播放 / 暂停', '空格'), ('刷新', 'R'), ('音量', '↑ ↓'), ('翻页', '← →'), ('关弹层、退全屏、返回', 'Esc'))))
    hud = ('<div class="hud" style="left:150px;top:190px;width:880px"><div class="h"><i style="background-image:url(' + ICON + ')"></i>纯粹直播</div><div class="cols">'
           + ''.join(f'<div>{"".join(c)}</div>' for c in cols.values()) + '</div></div>')
    cap = '<div class="capx" style="left:150px;top:150px;z-index:80">按住 ⌘ 时系统显示的快捷键列表（示意）；和 macOS 菜单栏同一套（U.17b）</div>'
    inner = (f'<div class="win ipad" style="--w:1180px;--h:820px;padding-top:24px">{ipad_status()}{body}'
             f'<div class="scrim" style="z-index:60;background:rgba(0,0,0,.25)"></div>{hud}{cap}<div class="hind p"></div></div>')
    return doc(1180, 820, 1.5, inner, D.CSS)


def d3_body(w):
    """U.2d's v3 wide room as it draws on iOS: no cast, no PiP in the top bar."""
    page = D.v3(w, 796, 1.5, windows=False)
    m = re.search(r'<div class="win" style="[^"]*">(.*)<div class="syn"', page, re.S)
    return strip_n(m.group(1)).replace(D.ib(D.rx('f235')), '', 1).replace(D.ib(D.ci('e806')), '', 1)


def ipad_share(ver):
    if ver == 3:
        body = d3_body(1180)
    else:
        body = d_body(1180, 796, windows=False).replace(D.ib(D.rx('f235'), None, 'ib vic'), '', 1)
    if ver == 3:
        over = ('<div class="gsnack" style="bottom:28px"><b>Error</b><span>分享失败，请重试</span></div>'
                '<div class="capx" style="left:24px;top:94px;z-index:80;max-width:520px">v3：菜单里点“分享”，iPad 上系统分享面板要知道从哪个按钮弹出，'
                'v3 没给位置（share_command_handler.dart:64-66），弹出“分享失败”（:217-220）。按 share_plus 13 的说明推断</div>')
    else:
        sheet = share_sheet('out').replace('class="shs"', 'class="shs" style="position:static;border-radius:0;padding:0;background:none"', 1)
        over = (f'<div class="pop" style="right:14px;top:84px;--ar:22px">{sheet}</div>'
                '<div class="capx" style="left:24px;top:94px;z-index:80;max-width:520px">新：iPad 上从点的那个按钮旁边弹出系统的分享气泡（菜单里点“分享”时，从右上角的菜单按钮弹出）；iPhone 照旧从底部弹出</div>')
    inner = (f'<div class="win ipad" style="--w:1180px;--h:820px;padding-top:24px">{ipad_status()}{body}{over}<div class="hind p"></div></div>')
    return doc(1180, 820, 1.5, inner, D.CSS)


# ======================================================================
OUT = {
    'v3-iphone-room': doc(393, 852, 3, room_v3(), G.CSS),
    'v4-iphone-room': doc(393, 852, 3, room_v4(n=True), G.CSS),
    'v3-iphone-full': doc(852, 393, 2, full_v3(), G.CSS),
    'v4-iphone-full': doc(852, 393, 2, full_v4(n=True), G.CSS),
    'v4-iphone-safe': safe_diagram(),
    'v4-iphone-home': doc(393, 852, 3, home_ios(), A.CSS, HOME_CSS),
    'v4-iphone-panel': panel_land(),
    'v4-iphone-pip': pip_ios(),
    'v4-iphone-share': share_out(),
    'v3-iphone-share-in': share_in_v3(),
    'v4-iphone-share-in': share_in(),
    'v3-iphone-paste': paste_v3(),
    'v4-iphone-paste': paste_v4(),
    'v4-ipad-home': ipad_home(),
    'v4-ipad-room': ipad_room(),
    'v4-ipad-split': ipad_split(),
    'v4-ipad-stage': ipad_stage(),
    'v4-ipad-keys': ipad_keys(),
    'v3-ipad-share': ipad_share(3),
    'v4-ipad-share': ipad_share(4),
}

if __name__ == '__main__':
    for name, html in OUT.items():
        open(os.path.join(HERE, name + '.html'), 'w', encoding='utf-8').write(html)
    print(len(OUT), 'pages')
