"""Generates the U.2c mockups (v3 restored and the new design, landscape
fullscreen at four sizes) as HTML next to this file. Then:
    python3 tools/ui/mock/render.py docs/ui/compare/U.2c/src/ --annotate
v3 follows lib/modules/live_play/widgets/video_player/video_controller_panel.dart
(TopActionBar :299, BottomActionBar :1394, LockButton :1009)."""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
CSS = '''
.fs{background-image:url(.cache/img/274.jpg);background-position:center 40%}
.fs .ib{color:#fff}
.dm{font-size:18px}
.title{flex:1;min-width:0;padding:0 12px;color:#fff;font:700 16px 'Noto Sans SC';white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.time{padding:0 4px}.bat{margin:0 8px}
.lock{position:absolute;right:20px;top:50%;transform:translateY(-50%);width:50px;height:50px;border-radius:25px;background:rgba(0,0,0,.38);display:grid;place-items:center;color:#fff;z-index:6}
.comp{flex:1;max-width:420px;height:40px;border-radius:20px;background:rgba(0,0,0,.54);border:1px solid rgba(255,255,255,.24);display:flex;align-items:center;color:rgba(255,255,255,.6);font-size:13px;white-space:nowrap;overflow:hidden;min-width:0}
.comp .a{width:40px;display:grid;place-items:center;color:#FFD166;flex:none}.comp .s{margin-left:auto;width:40px;display:grid;place-items:center;color:#fff;flex:none}
.mid{flex:1;display:flex;justify-content:center;align-items:center;min-width:0;padding:0 8px;height:48px}
.g{display:flex;align-items:center;height:48px;flex:none}
/* v3 */
.v3top{position:absolute;left:0;right:0;top:0;height:56px;display:flex;align-items:center;padding:0 8px;background:linear-gradient(0deg,transparent,rgba(0,0,0,.45));z-index:5}
.v3bot{position:absolute;left:0;right:0;bottom:0;height:56px;display:flex;align-items:center;padding:0 16px;background:linear-gradient(180deg,transparent,rgba(0,0,0,.45));color:#fff;z-index:5}
.swap{width:40px;height:40px;border-radius:20px;background:rgba(0,0,0,.26);display:grid;place-items:center;color:#fff;margin:0 4px;flex:none}
.pill{display:flex;align-items:center;gap:2px;padding:0 6px;height:48px;font-size:14px;flex:none;color:#fff}
.sel{display:flex;align-items:center;gap:6px;height:36px;padding:0 10px;border-radius:18px;background:rgba(255,255,255,.13);color:#fff;font-size:13px;font-weight:600;flex:none}
.fit{flex:none;padding:0 6px;color:#fff;font-size:15px;white-space:nowrap}
/* new */
.vtop .time{margin:14px 6px 0 2px}.vtop .bat{margin-top:16px}
.vfol{height:32px;border-radius:16px;display:flex;align-items:center;gap:3px;padding:0 12px 0 9px;font-size:13px;font-weight:500;background:rgba(255,255,255,.18);color:#fff;margin:0 4px;flex:none}.vfol .rx{font-size:16px}
.vring{width:22px;height:22px;border-radius:11px;border:2px solid #fff;display:grid;place-items:center}.vring i{width:9px;height:9px;border-radius:5px;background:#FF5449}
.vbadge{top:60px;left:16px}
.cbtn{width:40px;height:40px;border-radius:20px;background:rgba(0,0,0,.54);border:1px solid rgba(255,255,255,.24);display:grid;place-items:center;color:#FFD166;flex:none}
.vol{display:flex;align-items:center;gap:6px;flex:none;margin:0 4px;color:#fff}.vol .t{width:90px;height:4px;border-radius:2px;background:rgba(255,255,255,.35);position:relative}.vol .t i{position:absolute;left:0;top:0;bottom:0;width:70%;background:#fff;border-radius:2px}.vol .t u{position:absolute;left:calc(70% - 7px);top:-5px;width:14px;height:14px;border-radius:7px;background:#fff}
'''
mr = lambda n, s=24: f'<span class="mr" style="font-size:{s}px">{n}</span>'
mi = lambda n, s=24: f'<span class="mi" style="font-size:{s}px">{n}</span>'
rx = lambda c, s=24: f'<span class="rx" style="font-size:{s}px">&#x{c};</span>'
ci = lambda c, s=24: f'<span class="ci" style="font-size:{s}px">&#x{c};</span>'
ib = lambda inner, n=None, cls='ib': f'<div class="{cls}"' + (f' data-n="{n}"' if n else '') + f'>{inner}</div>'
DMS = [(0.35, 0.30, '前排支持！'), (0.10, 0.42, '这条街好热闹'), (0.55, 0.52, '主播带我们去时代广场'), (0.22, 0.21, '晚上好～')]
TITLE = '纽约时代广场，夜游直播'
COMP = '<div class="comp" data-n="14" data-at="tl"><span class="a">' + mr('auto_awesome', 18) + '</span>发送一条本地字幕<span class="s">' + mr('send', 18) + '</span></div>'


def page(w, h, scale, body):
    dm = ''.join(f'<div class="dm" style="left:{x * w:.0f}px;top:{y * h:.0f}px">{t}</div>' for x, y, t in DMS)
    return (f'<!doctype html><html><head><meta charset="utf-8"><meta name="mock-size" content="{w}x{h}@{scale}">'
            f'<link rel="stylesheet" href="kit/kit.css"><style>{CSS}</style></head>'
            f'<body><div class="fs" style="--w:{w}px;--h:{h}px"><div class="syn">示意图片</div>{dm}{body}'
            f'<div class="lock" data-n="20" data-at="tl">{mr("lock_open", 28)}</div></div></body></html>')


def v3(w, h, scale, android=True, compact=False):
    lead = ib(mi('arrow_back')) + ('<div class="time">21:36</div><div class="bat">76</div>' if android else '')
    trail = ('<div class="swap">' + mr('swap_horiz') + '</div>' + ('' if android else '<div class="time">21:36</div><div class="bat">76</div>')
             + ib(rx('ee05', 21)) + (ib(rx('f235')) if android else '') + ib(ci('e806')))
    left = (ib(mr('pause', 28)) + ('' if compact else ib(mr('refresh')) + '<div class="pill">' + mr('check', 15) + '已关注</div>')
            + ib('<span class="dmk open"></span>') + ib('<span class="dmk set"></span>'))
    right = ('<div class="sel">' + mr('tune', 17) + '原画 · 线路1</div>' + (ib(mr('screen_rotation_alt', 21)) if android else '')
             + ('' if compact else '<div class="fit">默认比例</div>') + ('' if android else ib(mr('volume_up', 22))) + ib(mr('fullscreen_exit', 26)))
    body = (f'<div class="v3top">{lead}<div class="title">{TITLE}</div>{trail}</div>'
            f'<div class="v3bot"><div class="g">{left}</div><div class="mid">{COMP.replace(" data-n=\"14\" data-at=\"tl\"", "")}</div><div class="g">{right}</div></div>')
    return page(w, h, scale, body).replace(' data-n="20" data-at="tl"', '')


def v4(w, h, scale, android=True, compact=False, recording=False):
    lead = ib(mi('arrow_back'), 1, 'ib vic') + '<div class="time" data-n="2">21:36</div>' + ('<div class="bat">76</div>' if android else '')
    rec = '<div class="ib" data-n="7" data-tag="add">' + ('<span class="recon"><i></i></span>' if recording else '<span class="vring"><i></i></span>') + '</div>'
    trail = (ib(mr('swap_horiz'), 3, 'ib vic') + ib(rx('ee05', 21), 4, 'ib vic') + (ib(rx('f235'), 5, 'ib vic') if android else '')
             + ib(ci('e806'), 6, 'ib vic') + rec + '<div class="ib vic" data-n="8" data-tag="add">' + rx('ea42') + '</div>')
    left = (ib(mr('pause', 28), 9, 'ib vic') + ib(mr('refresh'), 10, 'ib vic') + '<div class="vfol" data-n="11">' + rx('eb7b') + '已关注</div>'
            + ib('<span class="dmk open"></span>', 12, 'ib vic') + ib('<span class="dmk set"></span>', 13, 'ib vic'))
    mid = '<div class="cbtn" data-n="14">' + mr('auto_awesome', 18) + '</div>' if compact else COMP
    right = ('<div class="vchip" data-n="15" style="margin:0 3px">原画' + rx('ea4e', 18) + '</div><div class="vchip" data-n="16" style="margin:0 3px">线路1' + rx('ea4e', 18) + '</div>'
             + (ib(mr('screen_rotation_alt', 21), 17, 'ib vic') if android else '') + ib(rx('ea80', 22), 18, 'ib vic')
             + ('' if android else '<div class="vol" data-n="21">' + mr('volume_up', 22) + '<div class="t"><i></i><u></u></div></div>')
             + ib(mr('fullscreen_exit', 26), 19, 'ib vic'))
    body = (f'<div class="vtop">{lead}<div class="title">{TITLE}</div>{trail}</div>'
            f'<div class="vbot" style="padding:0 12px 4px"><div class="g">{left}</div><div class="mid">{mid}</div><div class="g">{right}</div></div>'
            + ('<div class="vbadge"><i></i>录制中 12:34</div>' if recording else ''))
    return page(w, h, scale, body)


OUT = {
    'v3-phone': v3(852, 393, 2), 'v3-narrow': v3(740, 360, 2, compact=True),
    'v3-tablet': v3(1280, 800, 1.5), 'v3-desktop': v3(1920, 1080, 1, android=False),
    'v4-phone': v4(852, 393, 2, recording=True), 'v4-narrow': v4(740, 360, 2, compact=True),
    'v4-tablet': v4(1280, 800, 1.5), 'v4-desktop': v4(1920, 1080, 1, android=False),
}
for name, html in OUT.items():
    open(os.path.join(HERE, name + '.html'), 'w', encoding='utf-8').write(html)
print(len(OUT), 'pages')
