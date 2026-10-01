"""Settings-page mockup pieces shared by U.6c, U.6d and U.6e (each task folder
keeps its own copy, so a task can be regenerated on its own).

v3 side: lib/common/widgets/widget_extensions.dart (buildGroupTitle,
buildModernCard, buildSwitchTile, buildTile, buildSliderTile), the
AppBar/dialog theme in lib/common/style/theme.dart (centred 20 px semibold
title, dialogs on surfaceContainerHigh with 24 radius) and the five font sizes
(12, 13, 14, 15, 20; t16 resolves to 15).
New side: the rows of the confirmed U.2f danmaku settings (.sec, .grp, .swr,
.sl in tools/ui/mock/kit/kit.css), plus a link row (value + chevron) and a
counter, until U.6a fixes the shared settings row component."""

CSS = '''
@font-face{font-family:'Material Icons Outlined';src:url('.cache/fonts/MaterialIconsOutlined.woff2') format('woff2')}
.mo{font-family:'Material Icons Outlined';font-weight:normal;font-style:normal;line-height:1;display:inline-block;font-feature-settings:'liga';white-space:nowrap}
.ph.long{height:auto;min-height:852px;padding-bottom:24px}
/* ---------- v3 ---------- */
.v3bar{height:64px;display:flex;align-items:center;position:relative;background:var(--surface);flex:none}
.v3bar .bk{width:56px;height:56px;display:grid;place-items:center}.v3bar .bk .mi{font-size:24px}
.v3bar .t{position:absolute;left:72px;right:72px;text-align:center;font-size:20px;font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.v3bar .acts{margin-left:auto;display:flex;align-items:center;padding-right:8px;color:var(--onv)}
.v3body{padding:12px 16px 32px}
.v3wrap{max-width:960px;margin:0 auto}
.v3gt{padding:0 0 8px 8px;font-size:12px;font-weight:700;color:rgba(54,97,142,.65);letter-spacing:.5px;line-height:16px}
.v3card{background:#F5F6FC;border-radius:20px;overflow:hidden;box-shadow:inset 0 0 0 .5px rgba(195,199,207,.25)}
.v3gap{height:20px}
.v3t{display:flex;align-items:center;gap:12px;padding:8px 16px;min-height:56px}
.v3t.two{min-height:72px}.v3t.three{min-height:88px}
.v3t.swt{padding:2px 8px 2px 16px;gap:16px}
.v3t .ic{width:22px;flex:none;color:var(--primary);display:grid;place-items:center}
.v3t .x{flex:1;min-width:0}
.v3t .a{font-size:15px;font-weight:600;line-height:22px}
.v3t .b{font-size:12px;line-height:16px;color:rgba(0,0,0,.75);margin-top:2px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.v3t .b.long{white-space:normal}
.v3t .b.err{color:var(--error)}
.v3t .tv{font-size:12px;font-weight:600;color:var(--primary);flex:none;max-width:130px;text-align:right}
.v3t .chev{font-size:20px;color:rgba(0,0,0,.4)}.v3t .chev24{font-size:24px;color:var(--onv)}
.v3t.dis .a,.v3t.dis .b{color:rgba(25,28,32,.38)}.v3t.dis .ic{color:rgba(25,28,32,.38)}
.v3t .sw{margin-left:4px}
.v3t.dis .sw{opacity:.38}
.v3hr{height:.5px;margin:0 16px;background:rgba(195,199,207,.25)}
.v3sl{display:flex;gap:12px;padding:10px 16px}
.v3sl .ic{width:24px;flex:none;color:var(--primary);padding-top:2px}
.v3sl .x{flex:1}
.v3sl .h{display:flex;align-items:flex-start;gap:12px}.v3sl .h .a{flex:1;font-size:15px;font-weight:600;line-height:22px}
.v3sl .bd{padding:2px 8px;border-radius:6px;background:rgba(54,97,142,.1);font-size:13px;font-weight:700;color:var(--primary);font-feature-settings:'tnum'}
.v3sl .bd.r20{border-radius:20px;padding:4px 10px;font-size:12px}
.v3trk{position:relative;height:36px;margin-left:-4px}
.v3trk .bg{position:absolute;left:0;right:0;top:16px;height:4px;border-radius:2px;background:rgba(54,97,142,.15)}
.v3trk .fg{position:absolute;left:0;top:15px;height:6px;border-radius:3px;background:var(--primary)}
.v3trk .th{position:absolute;top:8px;width:20px;height:20px;border-radius:10px;background:var(--primary);margin-left:-10px}
.v3cnt{display:flex;align-items:center;flex:none}
.v3cnt i{width:48px;height:48px;background:var(--primary);color:#fff;display:grid;place-items:center;font-style:normal}
.v3cnt i:first-child{border-radius:12px 0 0 12px}.v3cnt i:last-child{border-radius:0 12px 12px 0}
.v3cnt b{height:48px;padding:0 8px;display:grid;place-items:center;border-top:2px solid var(--primary);border-bottom:2px solid var(--primary);color:var(--primary);font-size:14px;min-width:30px}
.v3note{font-size:12px;line-height:16px;color:var(--onv);padding:8px 4px 0}
/* v3 dialogs */
.dl3{background:var(--sch);border-radius:24px;padding:24px 0 0;box-shadow:0 6px 20px rgba(0,0,0,.18);position:relative}
.dl3 .h{padding:0 24px 16px;font-size:20px;font-weight:600;line-height:28px}.dl3 .h.s{font-size:15px;font-weight:700;line-height:22px}
.dl3 .c{padding:0 24px 0;font-size:13px;line-height:20px;color:var(--onv)}
.dl3 .opt{display:flex;align-items:center;gap:16px;padding:0 24px;height:48px;font-size:14px}
.dl3 .rd{width:20px;height:20px;border-radius:10px;border:2px solid var(--onv);display:grid;place-items:center;flex:none}
.dl3 .rd.on{border-color:var(--primary)}.dl3 .rd.on::after{content:'';width:10px;height:10px;border-radius:5px;background:var(--primary)}
.dl3 .acts{display:flex;justify-content:flex-end;gap:8px;padding:16px 24px 24px}
.dl3 .tb{height:40px;padding:0 12px;display:grid;place-items:center;font-size:14px;font-weight:500;color:var(--primary);border-radius:20px}
.dl3 .tb.mut{color:rgba(0,0,0,.6)}
.dl3 .fb{height:40px;padding:0 24px;display:grid;place-items:center;font-size:14px;font-weight:500;color:#fff;background:var(--primary);border-radius:20px}
.dl3 .fb.err{background:var(--error)}
.fld{position:relative;margin:0 24px 16px;height:56px;border:1px solid var(--outline);border-radius:12px;background:var(--scl);display:flex;align-items:center;gap:12px;padding:0 12px;font-size:15px}
.fld .lb{position:absolute;left:10px;top:-9px;padding:0 4px;font-size:12px;color:var(--onv);background:linear-gradient(var(--sch) 50%,var(--scl) 50%)}
.fld.dis{opacity:.45}
.fld .sx{margin-left:auto;color:var(--onv);font-size:14px}
.fhelp{margin:-12px 24px 12px;font-size:12px;color:var(--onv)}
.achip{display:inline-flex;align-items:center;height:32px;padding:0 12px;border-radius:8px;border:1px solid var(--ov);font-size:13px;margin:0 8px 8px 0;background:var(--sch)}
.achip.on{background:var(--sc);border-color:var(--sc);color:var(--osc);font-weight:600}
/* ---------- new ---------- */
.nbody{padding:4px 0 32px}
.nwrap{max-width:720px;margin:0 auto}
.grp{overflow:hidden}
.grp .swr+.swr,.grp .swr+.sl,.grp .sl+.swr,.grp .sl+.sl{box-shadow:inset 0 1px 0 rgba(195,199,207,.45)}
.swr .val{font-size:14px;color:var(--onv);white-space:nowrap;flex:none;font-feature-settings:'tnum'}
.swr .chev{font-size:20px;color:var(--onv);margin-left:-8px}
.swr .a b{font-weight:600}
.swr .b.err{color:var(--error)}
.swr.dis .a,.swr.dis .b,.swr.dis .val,.swr.dis .sw,.swr.dis .chev{opacity:.38}
.swr .why{font-size:12px;color:var(--warn);margin-top:3px}
.sl.dis .h,.sl.dis .tr{opacity:.38}
.sl .b{font-size:12px;color:var(--onv);margin-top:2px}
.sl .why{font-size:12px;color:var(--warn);margin-top:3px}
.danger .a{color:var(--error)}
.rad{width:20px;height:20px;border-radius:10px;border:2px solid var(--onv);display:grid;place-items:center;flex:none}
.rad.on{border-color:var(--primary)}.rad.on::after{content:'';width:10px;height:10px;border-radius:5px;background:var(--primary)}
.cnt{display:flex;align-items:center;height:40px;border-radius:12px;box-shadow:inset 0 0 0 1px var(--ov);flex:none}
.cnt span{width:40px;display:grid;place-items:center;color:var(--onv)}.cnt b{min-width:28px;text-align:center;font-size:15px;font-weight:500;font-feature-settings:'tnum'}
.note{padding:8px 24px 0;font-size:12px;line-height:1.5;color:var(--onv)}
.note a{color:var(--primary);font-weight:600;text-decoration:none}
.logo{width:28px;height:28px;border-radius:7px;background:center/cover;flex:none}
.tagd{font-size:11px;padding:1px 6px;border-radius:6px;background:var(--sc);color:var(--osc);margin-left:6px;font-weight:600;vertical-align:2px}
/* new dialogs: one component for every choice, one for every confirm */
.dl4{background:var(--sch);border-radius:24px;padding:24px 0 8px;box-shadow:0 6px 20px rgba(0,0,0,.18);position:relative}
.dl4 .h{padding:0 24px 8px;font-size:20px;font-weight:600;line-height:28px}
.dl4 .c{padding:0 24px 8px;font-size:14px;line-height:1.55;color:var(--onv)}
.dl4 .c ul{margin:6px 0 0 18px}
.dl4 .opt{display:flex;align-items:center;gap:12px;padding:0 24px;min-height:48px;font-size:15px}
.dl4 .opt .x{flex:1;padding:8px 0}.dl4 .opt .d{font-size:12px;color:var(--onv);margin-top:2px;line-height:1.45}
.dl4 .opt.on{color:var(--primary);font-weight:600}.dl4 .opt.on .d{font-weight:400}
.dl4 .opt .ck{width:20px;font-size:20px;color:var(--primary)}
.dl4 .acts{display:flex;justify-content:flex-end;gap:8px;padding:8px 16px 8px}
.dl4 .tb{height:48px;padding:0 16px;display:grid;place-items:center;font-size:15px;font-weight:500;color:var(--primary);border-radius:24px}
.dl4 .fb{height:40px;margin:4px 0;padding:0 24px;display:grid;place-items:center;font-size:15px;font-weight:600;color:var(--onPrimary);background:var(--primary);border-radius:20px}
.dl4 .fb.err{background:var(--error);color:#fff}
.dl4 .fld .lb{background:linear-gradient(var(--sch) 50%,var(--scl) 50%)}
/* shared */
.board{display:flex;flex-wrap:wrap;gap:28px;padding:24px;align-items:flex-start;background:#D9DBE2}
.board .cell{width:393px}
.board .cap{font-size:13px;color:#43474E;margin:0 0 8px 4px;font-weight:600}
.board .scr{position:relative;width:393px;background:rgba(0,0,0,.32);border-radius:16px;padding:16px;display:flex;justify-content:center}
'''

# icons
mi = lambda n, s=24, st='': f'<span class="mi" style="font-size:{s}px;{st}">{n}</span>'
mr = lambda n, s=24, st='': f'<span class="mr" style="font-size:{s}px;{st}">{n}</span>'
mo = lambda n, s=24, st='': f'<span class="mo" style="font-size:{s}px;{st}">{n}</span>'
rx = lambda c, s=24, st='': f'<span class="rx" style="font-size:{s}px;{st}">&#x{c};</span>'
STATUS = '<div class="status"><span>21:36</span><span class="r"><span class="mi">signal_cellular_alt</span><span class="mi">wifi</span><span class="mi">battery_full</span></span></div>'


def page(w, h, scale, body, crop=False, frame='ph', extra_css='', long=False, status=True, gesture=True):
    size = f'{w}x{h}@{scale}' + (' crop' if crop else '')
    if frame == 'ph':
        inner = (STATUS if status else '') + body + ('<div class="gesture"></div>' if gesture and not long else '')
        frame_html = f'<div class="ph{" long" if long else ""}">{inner}</div>'
    elif frame == 'win':
        frame_html = f'<div class="win" style="--w:{w}px;--h:{h}px;display:flex;flex-direction:column">{body}</div>'
    else:
        frame_html = body
    return (f'<!doctype html><html><head><meta charset="utf-8"><meta name="mock-size" content="{size}">'
            f'<link rel="stylesheet" href="kit/kit.css"><style>{CSS}{extra_css}</style></head><body>{frame_html}</body></html>')


def nattr(n, tag=None, at=None):
    return (f' data-n="{n}"' if n else '') + (f' data-tag="{tag}"' if n and tag else '') + (f' data-at="{at}"' if n and at else '')


# ---------- v3 pieces ----------
def v3bar(title, acts=''):
    return f'<div class="v3bar"><div class="bk">{mi("arrow_back")}</div><div class="t">{title}</div><div class="acts">{acts}</div></div>'


def v3gt(t):
    return f'<div class="v3gt">{t}</div>'


def v3card(rows):
    return '<div class="v3card">' + '<div class="v3hr"></div>'.join(rows) + '</div>'


def v3tile(icon, title, sub=None, trail='chev', long=False, cls='', sub_cls=''):
    """buildTile: trail is 'chev' (default chevron 20, 40 % black), 'chev24'
    (an explicit Icon(Icons.chevron_right_rounded)), 'rxchev' (Remix
    arrow_right_s_line), None, or html for a trailing value."""
    two = 'two' if sub else ''
    t = ''
    if trail == 'chev':
        t = mr('chevron_right', 20, 'color:rgba(0,0,0,.4)')
    elif trail == 'chev24':
        t = mr('chevron_right', 24, 'color:var(--onv)')
    elif trail == 'rxchev':
        t = rx('ea6e', 24, 'color:var(--onv)')
    elif trail:
        t = trail
    s = f'<div class="b{" long" if long else ""} {sub_cls}">{sub}</div>' if sub else ''
    ic = f'<div class="ic">{icon}</div>' if icon else ''
    return f'<div class="v3t {two} {cls}">{ic}<div class="x"><div class="a">{title}</div>{s}</div>{t}</div>'


def v3val(text, size=12, color='var(--primary)'):
    return f'<span class="tv" style="font-size:{size}px;color:{color}">{text}</span>'


def v3sw(icon, title, sub, on, long=False, cls='', sub_cls=''):
    s = f'<div class="b{" long" if long else ""} {sub_cls}">{sub}</div>' if sub else ''
    ic = f'<div class="ic">{icon}</div>' if icon else ''
    return (f'<div class="v3t swt {"two" if sub else ""} {cls}">{ic}<div class="x"><div class="a">{title}</div>{s}</div>'
            f'<span class="sw{" on" if on else ""}"></span></div>')


def v3slider(icon, title, value, frac, sub=None, badge='', pad='10px 16px'):
    ic = f'<div class="ic">{icon}</div>' if icon else ''
    s = f'<div style="font-size:12px;color:rgba(0,0,0,.75);margin-top:4px">{sub}</div>' if sub else ''
    return (f'<div class="v3sl" style="padding:{pad}">{ic}<div class="x"><div class="h"><div class="a">{title}</div><span class="bd {badge}">{value}</span></div>{s}'
            f'<div class="v3trk"><div class="bg"></div><div class="fg" style="width:{frac * 100:.0f}%"></div><div class="th" style="left:{frac * 100:.0f}%"></div></div></div></div>')


# ---------- new pieces ----------
def bar(title, acts=''):
    return v3bar(title, acts)


def sec(t, n=None):
    return f'<div class="sec"{nattr(n)}>{t}</div>'


def grp(rows):
    return '<div class="grp">' + ''.join(rows) + '</div>'


def note(t):
    return f'<div class="note">{t}</div>'


def sw(title, desc=None, on=False, n=None, tag=None, dis=False, why=None, err=False, lead=''):
    d = f'<div class="b{" err" if err else ""}">{desc}</div>' if desc else ''
    w = f'<div class="why">{why}</div>' if why else ''
    return (f'<div class="swr{" dis" if dis else ""}"{nattr(n, tag, "tl")}>{lead}<div class="x"><div class="a">{title}</div>{d}{w}</div>'
            f'<span class="sw{" on" if on else ""}"></span></div>')


def link(title, desc=None, val='', n=None, tag=None, dis=False, why=None, chev=True, lead='', cls=''):
    d = f'<div class="b">{desc}</div>' if desc else ''
    w = f'<div class="why">{why}</div>' if why else ''
    v = f'<span class="val">{val}</span>' if val else ''
    c = mr('chevron_right', 20, '') .replace('class="mr"', 'class="mr chev"') if chev else ''
    return f'<div class="swr{" dis" if dis else ""} {cls}"{nattr(n, tag, "tl")}>{lead}<div class="x"><div class="a">{title}</div>{d}{w}</div>{v}{c}</div>'


def sl(title, value, frac, n=None, tag=None, dis=False, desc=None, why=None):
    d = f'<div class="b">{desc}</div>' if desc else ''
    w = f'<div class="why">{why}</div>' if why else ''
    return (f'<div class="sl{" dis" if dis else ""}" style="padding:12px 20px"{nattr(n, tag, "tl")}><div class="h"><span>{title}</span><span class="vpill">{value}</span></div>{d}{w}'
            f'<div class="tr"><i style="width:{frac * 100:.0f}%"></i><u style="left:calc({frac * 100:.0f}% - 10px)"></u></div></div>')


def cnt(title, value, n=None, tag=None, dis=False, desc=None):
    d = f'<div class="b">{desc}</div>' if desc else ''
    return (f'<div class="swr{" dis" if dis else ""}"{nattr(n, tag, "tl")}><div class="x"><div class="a">{title}</div>{d}</div>'
            f'<div class="cnt"><span>{mr("remove", 20)}</span><b>{value}</b><span>{mr("add", 20)}</span></div></div>')


def radio(title, desc, on, n=None, tag=None):
    d = f'<div class="b">{desc}</div>' if desc else ''
    return (f'<div class="swr"{nattr(n, tag, "tl")}><span class="rad{" on" if on else ""}"></span><div class="x"><div class="a">{title}</div>{d}</div></div>')


def choice_dialog(title, options, hint=None, width=361, n=None):
    """options: [(label, desc or None, selected)]"""
    rows = ''.join(f'<div class="opt{" on" if on else ""}"><div class="x">{lb}' + (f'<div class="d">{d}</div>' if d else '') + '</div>'
                   + (f'<span class="ck">{rx("eb7b", 20)}</span>' if on else '<span class="ck"></span>') + '</div>' for lb, d, on in options)
    h = f'<div class="c">{hint}</div>' if hint else ''
    return f'<div class="dl4" style="width:{width}px"{nattr(n)}><div class="h">{title}</div>{h}{rows}<div class="acts"><div class="tb">取消</div></div></div>'


def confirm_dialog(title, body, ok='重置', danger=True, width=361):
    return (f'<div class="dl4" style="width:{width}px"><div class="h">{title}</div><div class="c">{body}</div>'
            f'<div class="acts"><div class="tb">取消</div><div class="fb{" err" if danger else ""}">{ok}</div></div></div>')
