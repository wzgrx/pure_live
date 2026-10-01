"""U.14 system surfaces (Android first; Windows and Linux notes): v3 restored and the new design.
Everything here is drawn by the system (notification shade, picture-in-picture menu,
launcher, share sheet, splash screen), so the pictures are illustrations in stock
Android 15 style; what the app decides (texts, icons, actions) follows the code.

v3 (tag v3.2.11):
  media notification   lib/player/core/live_audio_service.dart:50-67 (channel 纯粹直播播放, no
                       notification icon -> audio_service default mipmap/ic_launcher, colour blue),
                       :157-170 (title = room title, artist = streamer, album = app name, art = cover);
                       live_audio_handler.dart:177-201 (controls play/pause + stop)
  recording service    android/.../RecorderForegroundService.kt:28-35 (channel "Recording"),
                       :216-248 (small icon ic_launcher_foreground, no actions);
                       recorder/services/recorder_background_service.dart:117-121 (title/text)
  picture-in-picture   plugins/built_in_kotlin/floating/.../FloatingPlugin.kt:88-110 (no actions)
  icon and splash      res/mipmap-anydpi-v26/ic_launcher.xml (white background, foreground inset 16%),
                       res/values*/styles.xml + drawable*/launch_background.xml (white / black, no logo)
  share                AndroidManifest.xml SEND text/plain and playlist types; main.dart:105-131;
                       common/utils/shared_media_intake.dart:70-130; shared_live_link_opener.dart:30-63
  permissions          live_audio_service.dart:207-261 (explain dialogs), video_settings_page.dart:355-380
The phone pages behind come from ../../U.3a, U.3c (splash) and U.3d (dialog styles).
    python3 docs/ui/compare/U.14/src/gen.py && python3 tools/ui/mock/render.py docs/ui/compare/U.14/src/ --annotate"""
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
C = _load('u3c', 'U.3c')
D = _load('u3d', 'U.3d')
mr, mi, rx, ci, attrs = A.mr, A.mi, A.rx, A.ci, A.attrs
ICON = '../../../apps/pure_live/assets/icons/icon.png'
FG = '../../../apps/pure_live/android/app/src/main/res/drawable-xxxhdpi/ic_launcher_foreground.png'

# the proposed monochrome glyph (notification small icon, themed icon): TV with
# antennas and a play triangle cut out, same shape as the launcher picture
GLYPH = ('<svg viewBox="0 0 24 24" style="width:{s}px;height:{s}px;display:block"><g fill="currentColor">'
         '<path fill-rule="evenodd" d="M6 7.5h12a3 3 0 0 1 3 3v7a3 3 0 0 1-3 3H6a3 3 0 0 1-3-3v-7a3 3 0 0 1 3-3Z'
         'M10 11v6l5.2-3Z"/></g><g stroke="currentColor" stroke-width="1.9" stroke-linecap="round">'
         '<path d="M7.6 3.2 10.6 7"/><path d="M16.4 3.2 13.4 7"/></g></svg>')
glyph = lambda s=24: GLYPH.format(s=s)

CSS = '''

/* silhouettes: what Android makes of a colour picture used as a small icon (alpha only) */
.sil{display:inline-block;background:currentColor;-webkit-mask:url(%(icon)s) center/contain no-repeat;mask:url(%(icon)s) center/contain no-repeat}
.silfg{display:inline-block;background:currentColor;-webkit-mask:url(%(fg)s) center/contain no-repeat;mask:url(%(fg)s) center/contain no-repeat}
/* ---------- notification shade (illustration) ---------- */
.sh-bg{position:absolute;inset:0;background:url(.cache/img/338.jpg) center/cover}
.sh{position:absolute;inset:0;background:rgba(236,238,244,.95)}
.sh .status{position:relative;z-index:2}
.sh-ni{display:flex;align-items:center;gap:6px;margin-left:8px;color:#1B1B1F}
.sh-date{padding:6px 24px 0;font-size:14px;color:#44474F}
.qqs{display:flex;gap:14px;padding:14px 24px 6px}
.qqs i{width:64px;height:52px;border-radius:26px;display:grid;place-items:center;background:#E1E2EC;color:#44474F;font-style:normal}
.qqs i.on{background:#D8E2FF;color:#001A41}
.mc{position:absolute;left:12px;right:12px;height:176px;border-radius:28px;overflow:hidden;color:#fff;background:#222 url(.cache/img/158.jpg) center 55%%/cover}
.mc::before{content:'';position:absolute;inset:0;background:linear-gradient(90deg,rgba(0,0,0,.72),rgba(0,0,0,.45))}
.mc>*{position:absolute;z-index:1}
.mc .ic{left:18px;top:16px;width:28px;height:28px;display:grid;place-items:center;color:#fff}
.mc .out{right:16px;top:14px;height:32px;padding:0 12px 0 10px;border-radius:16px;background:rgba(255,255,255,.22);display:flex;align-items:center;gap:6px;font-size:13px}
.mc .tt{left:20px;right:96px;top:70px}
.mc .tt b{display:block;font-size:16px;font-weight:600;line-height:22px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.mc .tt span{display:block;font-size:14px;line-height:20px;opacity:.75;margin-top:2px}
.mc .pp{right:18px;top:66px;width:56px;height:56px;border-radius:18px;background:#D8E2FF;color:#001A41;display:grid;place-items:center}
.mc .acts{left:12px;bottom:10px;display:flex;gap:4px}
.mc .acts>div{width:44px;height:40px;display:grid;place-items:center}
.nc{position:absolute;left:12px;right:12px;border-radius:24px;background:#FFFFFF;padding:14px 16px 14px;color:#1B1B1F;box-shadow:0 1px 2px rgba(0,0,0,.06)}
.nc .hd{display:flex;align-items:center;gap:8px;font-size:12px;color:#5D5E66;height:24px}
.nc .hd .ci2{width:24px;height:24px;border-radius:12px;display:grid;place-items:center;color:#fff;background:#2E6FE0;flex:none}
.nc .hd .ci2.gr{background:#6C6F78}
.nc .hd .ex{margin-left:auto;width:28px;height:24px;border-radius:12px;background:#ECEEF4;display:grid;place-items:center;color:#44474F}
.nc .t{font-size:14px;font-weight:600;margin:8px 0 0 32px;line-height:20px}
.nc .x{font-size:14px;color:#44474F;margin:2px 0 0 32px;line-height:20px}
.nc .ac{display:flex;gap:6px;margin:10px 0 0 22px}
.nc .ac span{height:36px;padding:0 10px;border-radius:18px;display:flex;align-items:center;font-size:14px;font-weight:600;color:#2E6FE0}
.nc.dash{background:transparent;border:1.5px dashed #9AA0AA;box-shadow:none;color:#5D5E66;font-size:13px;line-height:1.5}
.handle{position:absolute;left:50%%;transform:translateX(-50%%);width:36px;height:4px;border-radius:2px;background:#9AA0AA}
/* app notification categories (system settings, illustration) */
.cat{position:absolute;left:12px;right:12px;border-radius:24px;background:#fff;overflow:hidden}
.cat .h{padding:14px 18px 6px;font-size:13px;font-weight:600;color:#2E6FE0}
.cat .r{display:flex;align-items:center;gap:12px;padding:12px 18px;font-size:15px;color:#1B1B1F}
.cat .r small{display:block;font-size:12px;color:#5D5E66;margin-top:2px}
.cat .r .sw{margin-left:auto}
.newtag{font-size:11px;font-weight:600;color:#1E7A43;background:#E3F3E8;border-radius:6px;padding:1px 6px;margin-left:6px}
/* ---------- launcher (illustration) ---------- */
.ln{position:absolute;inset:0;background:url(.cache/img/338.jpg) center/cover}
.ln::before{content:'';position:absolute;inset:0;background:rgba(0,0,0,.18)}
.ln .status{position:relative;z-index:2;color:#fff}
.apps{position:absolute;left:30px;right:30px;top:118px;display:grid;grid-template-columns:repeat(4,1fr);gap:30px 0;justify-items:center}
.apps .a{width:64px;display:flex;flex-direction:column;align-items:center;gap:6px;font-size:12px;color:#fff;text-shadow:0 1px 2px rgba(0,0,0,.5)}
.apps .a i{width:56px;height:56px;border-radius:28px;display:block}
.dock{position:absolute;left:30px;right:30px;bottom:44px;display:flex;justify-content:space-between}
.dock i{width:56px;height:56px;border-radius:28px;display:block}
.sbar{position:absolute;left:24px;right:24px;bottom:124px;height:48px;border-radius:24px;background:rgba(255,255,255,.82)}
.ai{position:relative;border-radius:50%%;overflow:hidden;background:#fff;flex:none}
.ai.v3{background:#fff url(%(fg)s) center/102%% no-repeat}
.ai.v4{background:#fff url(%(icon)s) 50%% 46%%/82%% no-repeat}
.ai.sq{border-radius:28%%}.ai.rr{border-radius:18%%}
.ai.th{background:#D3E3FD;color:#0B3D91;display:grid;place-items:center}
.ai.th3{background:#D3E3FD}
.lp{position:absolute;z-index:30;width:236px;border-radius:24px;background:#F3F4F9;box-shadow:0 8px 28px rgba(0,0,0,.28);padding:8px 0;color:#1B1B1F}
.lp .r{height:48px;display:flex;align-items:center;gap:14px;padding:0 16px;font-size:14px}
.lp .r .g{width:32px;height:32px;border-radius:16px;display:grid;place-items:center;background:#D8E2FF;color:#0B3D91;flex:none}
.lp .r .av2{width:32px;height:32px;border-radius:16px;background:center/cover;flex:none}
.lp .sep{height:1px;background:#D7D9E0;margin:6px 16px}
.lp .r.u-sysi{color:#44474F}
/* ---------- picture-in-picture (illustration) ---------- */
.pip{position:absolute;z-index:30;border-radius:14px;overflow:hidden;box-shadow:0 6px 18px rgba(0,0,0,.4);background:#000 url(.cache/img/158.jpg) center 55%%/cover}
.pip .dim{position:absolute;inset:0;background:rgba(0,0,0,.45)}
.pip .b{position:absolute;display:grid;place-items:center;color:#fff;width:40px;height:40px}
.pip .d{position:absolute;white-space:nowrap;color:#fff;font-weight:500;font-size:10px;text-shadow:0 0 1px #000,0 0 2px #000}
/* ---------- share sheet (illustration) ---------- */
.web{position:absolute;inset:0;background:#fff}
.web .bar{height:56px;margin:4px 12px;border-radius:28px;background:#EEF0F5;display:flex;align-items:center;gap:10px;padding:0 16px;font-size:14px;color:#44474F}
.web .hero{margin:8px 12px;height:210px;border-radius:16px;background:#000 url(.cache/img/158.jpg) center 55%%/cover}
.web .l{height:12px;border-radius:6px;background:#E6E8EE;margin:12px 16px}
.ss{position:absolute;left:0;right:0;bottom:0;z-index:21;background:#F3F4F9;border-radius:28px 28px 0 0;padding:10px 0 28px;color:#1B1B1F}
.ss .hd2{font-size:16px;font-weight:600;text-align:center;margin:14px 0 10px}
.ss .pv{margin:0 16px;border-radius:16px;background:#fff;padding:12px 14px;font-size:13px;line-height:1.5;color:#44474F}
.ss .pv b{display:block;color:#1B1B1F;font-weight:600;margin-bottom:2px}
.ss .lab{font-size:13px;color:#5D5E66;margin:16px 20px 8px}
.ss .row4{display:grid;grid-template-columns:repeat(4,1fr);justify-items:center;gap:14px 0;padding:0 8px}
.ss .ap{display:flex;flex-direction:column;align-items:center;gap:6px;font-size:12px;width:80px;text-align:center}
.ss .ap i{width:52px;height:52px;border-radius:26px;display:grid;place-items:center;font-style:normal;color:#fff}
.ss .scrim2{position:absolute}
.n-spin{width:16px;height:16px;border-radius:8px;border:2px solid rgba(255,255,255,.35);border-top-color:#fff;display:inline-block;vertical-align:-3px;margin-right:10px}
/* ---------- settings page behind the permission dialogs (simplified) ---------- */
.st-row{display:flex;align-items:center;gap:16px;padding:12px 16px 12px 20px;min-height:64px}
.st-row .ic3{color:var(--onv);flex:none}
.st-row .x{flex:1;min-width:0}.st-row .a{font-size:15px}.st-row .b{font-size:12px;color:var(--onv);margin-top:2px;line-height:1.45}
/* v3 SmartDialog permission explanation (live_audio_service.dart:229-261) */
.sd-mask{position:absolute;inset:0;z-index:20;background:rgba(0,0,0,.35);display:flex;align-items:center;justify-content:center}
.sd{width:300px;padding:20px;border-radius:15px;background:#fff;color:var(--on);text-align:center}
.sd .t{font-size:18px;font-weight:700;line-height:25px}
.sd .c{font-size:14px;line-height:1.5;margin-top:12px}
.sd .r{display:flex;justify-content:space-evenly;align-items:center;margin-top:20px}
.sd .tb{height:40px;padding:0 12px;display:flex;align-items:center;font-size:13px;font-weight:500;color:var(--primary)}
.sd .eb{height:40px;padding:0 24px;border-radius:20px;display:flex;align-items:center;font-size:13px;font-weight:500;color:var(--primary);background:var(--scl);box-shadow:0 1px 3px rgba(0,0,0,.25)}
/* ---------- sheets of states ---------- */
.sheet2{position:absolute;inset:0;background:#E4E6EC}
.lab2{position:absolute;left:12px;right:12px;font-size:13px;font-weight:600;color:#30333A}
.lab2 small{font-weight:400;color:#5D5E66;margin-left:6px}
.capx{position:absolute;z-index:44;font:500 12px 'Noto Sans SC';padding:4px 8px;border-radius:5px;background:rgba(0,0,0,.6);color:#fff;white-space:nowrap}
.frame{position:absolute;overflow:hidden;border-radius:18px;box-shadow:0 0 0 6px #0E1014,0 8px 24px rgba(0,0,0,.25)}
.frame>.ph{transform-origin:0 0}
.seqlab{position:absolute;font-size:13px;line-height:1.45;color:var(--on);text-align:center}
.seqlab b{display:block;font-size:14px}
.seqarr{position:absolute;color:var(--onv)}
''' % {'icon': ICON, 'fg': FG}


def page(w, h, scale, body, root='ph', syn=True, crop=False, syn_pos=None):
    style = '' if root == 'ph' else f' style="--w:{w}px;--h:{h}px"'
    pos = syn_pos or 'top:auto;bottom:22px'
    s = f'<div class="syn" style="z-index:46;{pos}">示意图片</div>' if syn else ''
    return (f'<!doctype html><html><head><meta charset="utf-8"><meta name="mock-size" content="{w}x{h}@{scale}{" crop" if crop else ""}">'
            f'<link rel="stylesheet" href="kit/kit.css"><style>{A.CSS}{C.CSS}{D.CSS}{CSS}</style></head>'
            f'<body><div class="{root}"{style}>{body}{s}</div></body></html>')


def cap(text, style):
    return f'<div class="capx" style="{style}">{text}</div>'


# ---------- small icons ----------
def small(v4, kind, s=16):
    """Status-bar / notification small icon. v3: the colour pictures as Android
    draws them (alpha only); new: monochrome glyphs."""
    if v4:
        return glyph(s) if kind == 'media' else rx('f05a', s)
    if kind == 'media':   # mipmap/ic_launcher is the adaptive icon on API 26+: opaque white layer -> a solid blob
        return f'<span style="width:{s - 2}px;height:{s - 2}px;border-radius:50%;background:currentColor;display:inline-block"></span>'
    return f'<span class="silfg" style="width:{s}px;height:{s}px"></span>'


# ---------- 1. notification shade ----------
def media_card(v4, top, n=False, playing=True):
    N = (lambda k: k) if n else (lambda k: None)
    T = (lambda t: t) if n else (lambda t: None)
    return (f'<div class="mc" style="top:{top}px"' + attrs(N(1), T('keep'), 'tl' if n else None) + '>'
            f'<div class="ic">{small(v4, "media", 22)}</div>'
            '<div class="out">' + mr('volume_up', 16) + '此手机</div>'
            '<div class="tt"><b>深夜电台 · 点歌接龙到天亮</b><span>晚风</span></div>'
            '<div class="pp"' + attrs(N(2), T('keep'), 'tr' if n else None) + '>' + mr('pause' if playing else 'play_arrow', 30) + '</div>'
            '<div class="acts"><div' + attrs(N(3), T('keep'), 'tc' if n else None) + '>' + mr('stop', 26) + '</div></div></div>')


def rec_card(v4, top, n=False, state='one'):
    """state: one | two | stopped (new design); v3 always shows the same text."""
    N = (lambda k: k) if n else (lambda k: None)
    T = (lambda t: t) if n else (lambda t: None)
    if not v4:
        return (f'<div class="nc" style="top:{top}px"><div class="hd"><span class="ci2 gr">{small(False, "rec", 18)}</span>纯粹直播 · 现在'
                '<span class="ex">' + mr('expand_more', 18) + '</span></div>'
                '<div class="t">直播录制进行中</div><div class="x">录制与封装由独立后台服务保护，点按返回应用</div></div>')
    if state == 'stopped':
        return (f'<div class="nc" style="top:{top}px"><div class="hd"><span class="ci2">{small(True, "rec", 16)}</span>纯粹直播 · 现在'
                '<span class="ex">' + mr('expand_less', 18) + '</span></div>'
                '<div class="t">录制已停止 · 晚风</div><div class="x">系统给后台录制的时间用完了。已录下的 5:52:10 已保存，回到应用可以重新开始。</div>'
                '<div class="ac"><span>打开录制中心</span></div></div>')
    if state == 'two':
        head, title, text, stop = '1:05:12', '正在录制 2 个直播间', '晚风、星河长明', '全部停止'
    else:
        head, title, text, stop = '12:34', '正在录制 · 晚风', '深夜电台 · 点歌接龙到天亮 · 原画', '停止录制'
    return (f'<div class="nc" style="top:{top}px"' + attrs(N(4), T('chg'), 'tl' if n else None) + f'><div class="hd"><span class="ci2">{small(True, "rec", 16)}</span>'
            f'纯粹直播 · <span class="tnum">{head}</span><span class="ex">' + mr('expand_less', 18) + '</span></div>'
            f'<div class="t">{title}</div><div class="x">{text}</div>'
            '<div class="ac"><span' + attrs(N(5), T('add'), 'tc' if n else None) + f'>{stop}</span><span'
            + attrs(N(6), T('add'), 'tc' if n else None) + '>录制中心</span></div></div>')


def shade(v4, n=False):
    icons = small(v4, 'media', 16) + small(v4, 'rec', 16)
    status = ('<div class="status"><span style="display:flex;align-items:center">21:40<span class="sh-ni">' + icons + '</span></span>'
              '<span class="r"><span class="mi">signal_cellular_alt</span><span class="mi">wifi</span><span class="mi">battery_full</span></span></div>')
    qqs = '<div class="qqs">' + ''.join(f'<i class="{c}">{mr(g, 22)}</i>' for g, c in
                                       [('wifi', 'on'), ('bluetooth', 'on'), ('flashlight_on', ''), ('do_not_disturb_on', '')]) + '</div>'
    body = ('<div class="sh-bg"></div><div class="sh">' + status + '<div class="sh-date">10月1日 周三</div>' + qqs
            + media_card(v4, 156, n) + rec_card(v4, 348, n) + '<div class="handle" style="top:820px"></div></div>'
            + cap('通知栏（系统画的，Android 15 原生样式示意）', 'left:12px;top:' + ('520' if v4 else '480') + 'px'))
    return page(393, 852, 3, body)


def notify_states(v4):
    W = 393
    parts, y = '<div class="sheet2"></div>', 16
    def lab(text, sub=''):
        nonlocal parts, y
        parts += f'<div class="lab2" style="top:{y}px">{text}<small>{sub}</small></div>'
        y += 26
    if v4:
        lab('录制 1 个直播间', '计时由系统走，不用每秒刷新')
        parts += rec_card(True, y, state='one'); y += 166
        lab('录制 2 个直播间', '计时从第一个开始算')
        parts += rec_card(True, y, state='two'); y += 166
        lab('后台录制被系统停掉（新）', '选择 X2')
        parts += rec_card(True, y, state='stopped'); y += 190
        lab('暂停时的媒体卡片', '同 v3')
        parts += media_card(True, y, playing=False); y += 196
        lab('通知类别', '系统设置 → 应用 → 纯粹直播 → 通知')
        parts += ('<div class="cat" style="top:%dpx"><div class="r"><div>纯粹直播播放<small>后台播放时的媒体控制</small></div><span class="sw on"></span></div>'
                  '<div class="r"><div>录制<small>正在录制时一直显示</small></div><span class="sw on"></span></div>'
                  '<div class="r"><div>录制提醒<span class="newtag">新</span><small>录制被系统停掉、失败时提醒</small></div><span class="sw on"></span></div></div>' % y)
        y += 206
    else:
        lab('录制中（不管几个）', '文字一样，看不出录的是谁、录了多久')
        parts += rec_card(False, y); y += 120
        lab('后台录制被系统停掉', 'Android 15 起后台累计 6 小时')
        parts += (f'<div class="nc dash" style="top:{y}px">没有通知：录制通知直接消失，只在应用的录制列表里标成失败（“Android 后台数据同步时限已到，录制正在收尾……”）</div>')
        y += 104
        lab('暂停时的媒体卡片')
        parts += media_card(False, y, playing=False); y += 196
        lab('通知类别', '系统设置 → 应用 → 纯粹直播 → 通知')
        parts += ('<div class="cat" style="top:%dpx"><div class="r"><div>纯粹直播播放<small></small></div><span class="sw on"></span></div>'
                  '<div class="r"><div>Recording<small>Active live-stream recording</small></div><span class="sw on"></span></div></div>' % y)
        y += 150
    return page(W, y + 16, 2, parts, root='win', syn=False)


# ---------- 2. picture-in-picture ----------
def launcher(icons=True):
    cols = ['#F4C7B8', '#BFD8F2', '#C8E6C9', '#FFE0A3', '#D7C8F0', '#F2C1D6', '#B9E2E0', '#E8E0D0']
    apps = ''.join(f'<div class="a"><i style="background:{c}"></i>&nbsp;</div>' for c in cols)
    return ('<div class="ln"><div class="status"><span>21:40</span><span class="r"><span class="mi">signal_cellular_alt</span><span class="mi">wifi</span><span class="mi">battery_full</span></span></div>'
            f'<div class="apps">{apps}</div><div class="sbar"></div>'
            '<div class="dock">' + ''.join(f'<i style="background:{c}"></i>' for c in cols[:4]) + '</div></div>'
            '<div class="gesture" style="background:rgba(255,255,255,.7)"></div>')


def pip(v4, n=False, paused=False):
    N = (lambda k: k) if n else (lambda k: None)
    T = (lambda t: t) if n else (lambda t: None)
    w, h = 288, 162
    x, y = 393 - 12 - w, 852 - 200 - h
    dms = ''.join(f'<div class="d" style="left:{l}px;top:{t}px">{s}</div>' for l, t, s in [(150, 8, '前排支持！'), (20, 24, '晚风今天状态好好'), (110, 40, '来了来了')])
    ctl = ('<div class="dim"></div>'
           '<div class="b" style="left:6px;top:6px"' + attrs(N(10), T('keep'), 'tl' if n else None) + '>' + mr('settings', 20) + '</div>'
           '<div class="b" style="right:6px;top:6px"' + attrs(N(9), T('keep'), 'tr' if n else None) + '>' + mr('close', 22) + '</div>'
           f'<div class="b" style="left:{w / 2 - 22:.0f}px;top:{h / 2 - 30:.0f}px;width:44px;height:44px"' + attrs(N(8), T('keep'), 'tc' if n else None) + '>' + mr('fullscreen', 30) + '</div>')
    if v4:
        ctl += (f'<div class="b" style="left:{w / 2 - 22:.0f}px;bottom:6px;width:44px;height:44px"' + attrs(N(7), T('add'), 'bc' if n else None) + '>'
                + mr('play_arrow' if paused else 'pause', 28) + '</div>')
    win = f'<div class="pip" style="left:{x}px;top:{y}px;width:{w}px;height:{h}px">{dms}{ctl}</div>'
    note = ('点一下：系统的设置、关闭、全屏' + ('，下面的暂停是我们加的' if v4 else '；v3 没有自己的按钮'))
    return page(393, 852, 3, launcher() + win + cap('系统画中画（安卓原生样式示意，各厂商不同）', 'left:12px;top:44px')
                + cap(note, f'left:12px;top:{y - 34}px'))


# ---------- 3. launcher icon and long press ----------
def icon_cell(v4, d=56, shape=''):
    cls = 'ai ' + ('v4' if v4 else 'v3') + (' ' + shape if shape else '')
    return f'<span class="{cls}" style="width:{d}px;height:{d}px;display:block"></span>'


def home_with_icon(v4, menu='', n=False):
    cols = ['#BFD8F2', '#C8E6C9', '#FFE0A3', '#D7C8F0', '#F2C1D6', '#B9E2E0', '#E8E0D0']
    first = ('<div class="a"' + attrs(11 if n else None, 'chg' if n else None, 'tr' if n else None) + '>' + icon_cell(v4) + '纯粹直播</div>')
    apps = first + ''.join(f'<div class="a"><i style="background:{c}"></i>&nbsp;</div>' for c in cols)
    return ('<div class="ln"><div class="status"><span>21:40</span><span class="r"><span class="mi">signal_cellular_alt</span><span class="mi">wifi</span><span class="mi">battery_full</span></span></div>'
            f'<div class="apps">{apps}</div><div class="sbar"></div>'
            '<div class="dock">' + ''.join(f'<i style="background:{c}"></i>' for c in cols[:4]) + '</div></div>'
            '<div class="gesture" style="background:rgba(255,255,255,.7)"></div>' + menu)


def long_press(v4, n=False):
    N = (lambda k: k) if n else (lambda k: None)
    T = (lambda t: t) if n else (lambda t: None)
    if v4:
        rows = ('<div class="r"' + attrs(N(12), T('add'), 'tr' if n else None) + '><span class="g">' + ci(A.CI_SEARCH, 18) + '</span>搜索直播</div>'
                '<div class="r"' + attrs(N(13), T('add'), 'tr' if n else None) + '><span class="g">' + rx('ec54', 18) + '</span>录制中心</div>'
                '<div class="r"' + attrs(N(14), T('add'), 'tr' if n else None) + '><span class="av2" style="background-image:url(.cache/img/65.jpg)"></span>晚风</div>'
                '<div class="r"><span class="av2" style="background-image:url(.cache/img/111.jpg)"></span>一只小熊</div>'
                '<div class="sep"></div><div class="r u-sysi">' + mr('info', 22) + '应用信息</div>')
    else:
        rows = '<div class="r u-sysi">' + mr('info', 22) + '应用信息</div>'
    menu = f'<div class="lp" style="left:22px;top:212px">{rows}</div>'
    note = ('长按图标：搜索、录制中心、最近看过的两个直播间（选择 X3）' if v4 else '长按图标：只有系统自己的项')
    return page(393, 852, 3, home_with_icon(v4, menu, n) + cap('桌面（系统画的，示意）', 'left:12px;top:44px')
                + cap(note, 'left:12px;top:' + ('530' if v4 else '300') + 'px'))


def icons_sheet(v4):
    W, H = 760, 290
    row = lambda y, label, cells: (f'<div class="lab2" style="top:{y}px;left:24px">{label}</div>'
                                   f'<div style="position:absolute;left:24px;top:{y + 28}px;display:flex;gap:28px;align-items:flex-end">{cells}</div>')
    cell = lambda inner, text: f'<div style="display:flex;flex-direction:column;align-items:center;gap:8px;font-size:12px;color:#44474F">{inner}<span>{text}</span></div>'
    masks = ''.join(cell(icon_cell(v4, 72, s), t) for s, t in [('', '圆形'), ('sq', '方圆'), ('rr', '圆角方')])
    if v4:
        themed = cell('<span class="ai th" style="width:72px;height:72px">' + glyph(44) + '</span>', '主题图标（单色版）')
    else:
        themed = cell(icon_cell(False, 72), '主题图标（没有单色版，不变色）')
    neighbours = cell('<span class="ai th3" style="width:72px;height:72px;display:grid;place-items:center;color:#0B3D91">' + mr('photo_camera', 36) + '</span>', '别的应用（示意）')
    win = (cell(f'<span style="width:32px;height:32px;background:url({ICON}) center/contain no-repeat;display:block"></span>', '任务栏 32')
           + cell(f'<span style="width:16px;height:16px;background:url({ICON}) center/contain no-repeat;display:block"></span>', '标题栏 16')
           + cell('<span style="width:24px;height:24px;display:grid;place-items:center;color:#1B1B1F">' + small(v4, 'media', 22) + '</span>', '通知小图标（播放）')
           + cell('<span style="width:24px;height:24px;display:grid;place-items:center;color:#1B1B1F">' + small(v4, 'rec', 22) + '</span>', '通知小图标（录制）'))
    body = ('<div class="sheet2" style="background:#EEF0F5"></div>'
            + row(16, 'Android 桌面（不同桌面的形状）', masks + '<div style="width:8px"></div>' + themed + neighbours)
            + row(176, 'Windows（同一张图）和通知栏', win))
    return page(W, H, 2, body, root='win', syn=False)


# ---------- 4. splash sequence ----------
def phone_frame(x, inner, scale=0.62):
    w, h = 393 * scale, 852 * scale
    return (f'<div class="frame" style="left:{x}px;top:20px;width:{w:.0f}px;height:{h:.0f}px">'
            f'<div class="ph" style="transform:scale({scale})">{inner}</div></div>')


def sys_splash(v4):
    if v4:
        return ('<div style="position:absolute;inset:0;background:var(--surface)"></div>'
                f'<div style="position:absolute;left:50%;top:50%;width:150px;height:150px;transform:translate(-50%,-50%);background:url({ICON}) center/contain no-repeat"></div>')
    d = 160  # Android 12+: the adaptive icon in a 160 dp circle on windowBackground
    return ('<div style="position:absolute;inset:0;background:#FFFFFF"></div>'
            f'<div style="position:absolute;left:50%;top:50%;transform:translate(-50%,-50%)">{icon_cell(False, d)}</div>')


def splash_seq(v4):
    W, H = 900, 640
    s = 0.62
    fw = 393 * s
    xs = [20, 20 + fw + 60, 20 + 2 * (fw + 60)]
    frames = [sys_splash(v4),
              C.v4_splash(phone=True, n=False) if v4 else C.v3_splash(opacity=0.05, scale=0.84),
              (D.home_v4() if v4 else C.home_v3())]
    labs = ([('系统启动画面', '表面色底，中间是应用图标（没有白圈），和启动页的 Logo 一样大'),
             ('启动页（U.3c）', '同一个底色和 Logo；Logo 比正中略高，交给 U.3c 对齐'), ('首页', '')] if v4 else
            [('系统启动画面（Android 12 起）', '白底（深色时黑底），中间是带白圈的图标（白圈和白底连成一片），电视只占四成'),
             ('启动页第一帧（U.3c）', '换成青色渐变，Logo 从透明开始淡入'), ('首页', '')])
    body = '<div style="position:absolute;inset:0;background:#EEF0F5"></div>'
    for x, inner, (t, sub) in zip(xs, frames, labs):
        body += phone_frame(x, inner, s)
        body += f'<div class="seqlab" style="left:{x - 10:.0f}px;width:{fw + 20:.0f}px;top:{20 + 852 * s + 14:.0f}px"><b>{t}</b>{sub}</div>'
    for i in range(2):
        body += f'<div class="seqarr" style="left:{xs[i] + fw + 18:.0f}px;top:{20 + 852 * s / 2 - 14:.0f}px">' + mr('arrow_forward', 28) + '</div>'
    return page(W, H, 2, body, root='win', syn=False)


# ---------- 5. share ----------
def share_sheet(n=False):
    N = (lambda k: k) if n else (lambda k: None)
    T = (lambda t: t) if n else (lambda t: None)
    apps = [('#07C160', rx('f2b5', 26), '微信'), ('#12B7F5', rx('f03a', 26), 'QQ'), ('ours', '', '纯粹直播'), ('#5F6368', rx('ecd5', 24), '复制'),
            ('#1A73E8', rx('eb8c', 26), '浏览器'), ('#E1E2EC', mr('more_horiz', 26), '更多')]
    cells = ''
    for bg, icon, label in apps:
        if bg == 'ours':
            cells += ('<div class="ap"' + attrs(N(15), T('keep'), 'tr' if n else None) + '>' + icon_cell(False, 52) + label + '</div>')
        else:
            color = '#44474F' if bg == '#E1E2EC' else '#fff'
            cells += f'<div class="ap"><i style="background:{bg};color:{color}">{icon}</i>{label}</div>'
    web = ('<div class="web"><div class="status"><span>21:40</span><span class="r"><span class="mi">signal_cellular_alt</span><span class="mi">wifi</span><span class="mi">battery_full</span></span></div>'
           '<div class="bar">' + mr('lock', 16) + 'live.bilibili.com/21452505</div><div class="hero"></div>'
           + ''.join(f'<div class="l" style="width:{w}%"></div>' for w in (80, 92, 60, 85)) + '</div>')
    sheet = ('<div class="scrim" style="z-index:20;background:rgba(0,0,0,.32)"></div><div class="ss"><div class="handle" style="top:10px;background:#BFC2CA"></div>'
             '<div class="hd2">分享</div><div class="pv"><b>晚风的直播间</b>深夜电台 · 点歌接龙到天亮 https://b23.tv/AbCd12</div>'
             f'<div class="lab">应用</div><div class="row4">{cells}</div></div>')
    return page(393, 852, 3, web + sheet + cap('别的应用里点“分享”：系统的分享面板（示意，v3 和新设计一样）', 'left:12px;top:400px'), syn_pos='top:226px;bottom:auto')


def share_result(v4, opening=False):
    home = D.home_v4() if v4 else C.home_v3()
    if opening:
        text = '<span class="n-spin"></span>正在打开分享的直播间…'
    elif v4:
        text = '分享的内容里没有能打开的直播间链接'
    else:
        text = '不支持的文件格式，仅限 M3U 或 TXT'
    return page(393, 852, 3, home + f'<div class="toast" style="bottom:120px">{text}</div>')


# ---------- 6. permission explanation ----------
def settings_behind(v4):
    bar = ('<div class="appbar"><div class="back">' + mi('arrow_back') + '</div><div style="font-size:20px;font-weight:600;flex:1">视频设置</div></div>')
    rows = [(rx('f29e'), '全局静音', '所有直播间统一静音', 'sw'), (rx('ee02'), '首选清晰度', '当进入直播播放页，首选的视频清晰度', ''),
            (rx('ef83'), '后台播放', '暂时切出 APP 时继续播放；手动纯音频同样遵循此开关，自动助眠会话按计时继续', 'sw'),
            (rx('ef6f'), '新直播间自动助眠', '', 'sw')]
    body = ''.join(f'<div class="st-row"><span class="ic3">{i}</span><div class="x"><div class="a">{a}</div>'
                   + (f'<div class="b">{b}</div>' if b else '') + '</div>' + ('<span class="sw"></span>' if s else mr('chevron_right')) + '</div>' for i, a, b, s in rows)
    return A.status_bar() + bar + body + '<div class="gesture"></div>'


def v3_perm():
    dlg = ('<div class="sd-mask"><div class="sd"><div class="t">需要通知权限</div>'
           '<div class="c">为了在后台播放时显示控制条并防止直播中断，我们需要开启通知权限。</div>'
           '<div class="r"><div class="tb">取消</div><div class="eb">去开启</div></div></div></div>')
    return page(393, 852, 3, settings_behind(False) + dlg, syn=False)


def v4_perm(denied=False, n=False):
    N = (lambda k: k) if n else (lambda k: None)
    T = (lambda t: t) if n else (lambda t: None)
    if denied:
        t, msg, ok = '通知权限已关闭', '系统设置里关掉了“纯粹直播”的通知，后台播放要用它显示控制条。打开后回到这里再开一次。', '去设置'
    else:
        t, msg, ok = '需要通知权限', '为了在后台播放时显示控制条并防止直播中断，我们需要开启通知权限。', '去开启'
    dlg = (f'<div class="d4" style="width:361px"><div class="t">{t}</div><div class="msg">{msg}</div>'
           '<div class="acts"><div class="gap"></div><div class="tb4"' + attrs(N(16), T('keep'), 'bc' if n else None) + '>取消</div>'
           '<div class="fb4"' + attrs(N(17), T('chg' if denied else 'keep'), 'bc' if n else None) + f'>{ok}</div></div></div>')
    return page(393, 852, 3, settings_behind(True) + C.overlay(dlg), syn=False)


def build():
    return {
        'v3-shade': shade(False), 'v4-shade': shade(True, n=True),
        'v3-notify-states': notify_states(False), 'v4-notify-states': notify_states(True),
        'v3-pip': pip(False), 'v4-pip': pip(True, n=True),
        'v3-launcher': long_press(False), 'v4-launcher': long_press(True, n=True),
        'v3-icons': icons_sheet(False), 'v4-icons': icons_sheet(True),
        'v3-splash-seq': splash_seq(False), 'v4-splash-seq': splash_seq(True),
        'v3-share-sheet': share_sheet(), 'v4-share-sheet': share_sheet(n=True),
        'v3-share-result': share_result(False), 'v4-share-result': share_result(True), 'v4-share-opening': share_result(True, opening=True),
        'v3-perm': v3_perm(), 'v4-perm': v4_perm(n=True), 'v4-perm-denied': v4_perm(denied=True),
    }


if __name__ == '__main__':
    pages = build()
    for name, html in pages.items():
        open(os.path.join(HERE, name + '.html'), 'w', encoding='utf-8').write(html)
    print(len(pages), 'pages')
