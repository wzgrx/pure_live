"""Shared pieces of the settings mockups (U.6a overview, U.6b appearance).

v3 parts follow lib/common/widgets/widget_extensions.dart (group title, modern
card, tile, switch tile, slider tile) and lib/common/style/my_theme.dart
(centred 20 px app bar title, dialogs). The new settings row (U.1c) is one
component with five trailing kinds: link, switch, choice, slider, counter.
Imported by U.6a/src/gen.py and U.6b/src/gen.py."""

CSS = r'''
.status .mi{font-size:16px}
/* ---------- v3: widget_extensions.dart / my_theme.dart ---------- */
.ab3{height:56px;display:flex;align-items:center;position:relative;background:var(--surface);flex:none}
.ab3 .bk{width:56px;height:56px;display:grid;place-items:center}.ab3 .bk .mi{font-size:24px}
.ab3 .t{position:absolute;left:72px;right:72px;top:0;text-align:center;font-size:20px;font-weight:600;line-height:56px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.ab3 .act{margin-left:auto;display:flex;align-items:center;padding-right:8px;gap:0}
.ab3 .act .tb{display:flex;align-items:center;gap:8px;height:40px;padding:0 12px;color:var(--primary);font-size:13px;font-weight:500}
.b3{padding:12px 16px 32px}
.gt3{padding:0 0 8px 8px;font-size:12px;font-weight:700;letter-spacing:.5px;color:color-mix(in srgb,var(--primary) 65%,var(--surface))}
.cd3{border-radius:20px;background:color-mix(in srgb,var(--schh) 15%,var(--surface));box-shadow:inset 0 0 0 .5px rgba(0,0,0,.05);overflow:hidden}
.g3{height:20px}
.t3{display:flex;align-items:center;gap:12px;padding:8px 16px;min-height:72px}
.t3.sw3{padding-right:8px}
.t3 .ic{width:22px;font-size:22px;color:var(--primary);flex:none;text-align:center}
.t3 .x{flex:1;min-width:0}.t3 .a{font-size:15px;font-weight:600;line-height:1.35}
.t3 .b{font-size:12px;color:rgba(0,0,0,.45);margin-top:2px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.t3 .chev{font-size:20px;color:rgba(0,0,0,.24);flex:none}
.t3 .tv{font-size:13px;color:var(--outline);flex:none}
.dv3{height:.5px;margin:0 16px;background:rgba(0,0,0,.05)}
.sl3{display:flex;gap:12px;padding:10px 16px}.sl3 .ic{width:24px;font-size:22px;color:var(--primary);padding-top:2px;text-align:center}
.sl3 .x{flex:1}.sl3 .h{display:flex;align-items:flex-start;gap:12px}.sl3 .h .a{flex:1;font-size:15px;font-weight:600}
.badge3{padding:2px 8px;border-radius:6px;background:color-mix(in srgb,var(--primary) 10%,transparent);color:var(--primary);font:700 13px 'Geist','Noto Sans SC'}
.sl3 .b{font-size:12px;color:rgba(0,0,0,.45);margin-top:4px}
.trk3{height:4px;border-radius:2px;background:color-mix(in srgb,var(--primary) 15%,transparent);margin:16px 6px 10px 6px;position:relative}
.trk3 i{position:absolute;left:0;top:0;bottom:0;border-radius:2px;background:var(--primary)}.trk3 u{position:absolute;top:-8px;width:20px;height:20px;border-radius:10px;background:var(--primary);margin-left:-10px}
.ind3{width:28px;height:28px;border-radius:6px;flex:none}
.chip3{height:32px;padding:0 12px;border-radius:8px;display:inline-flex;align-items:center;gap:6px;font-size:14px;box-shadow:inset 0 0 0 1px var(--ov)}
.chip3.on{background:var(--sc);color:var(--osc);box-shadow:none}
/* dialogs (Dialog / AlertDialog with dialogTheme: surfaceContainerHigh, 24 radius) */
.dg{position:absolute;z-index:21;background:var(--sch);border-radius:24px;overflow:hidden;color:var(--on)}
.dg .h{padding:24px 24px 0;font-size:20px;font-weight:600}
.dg .h.b7{font-weight:700}
.dg .bd{padding:12px 24px 0;font-size:14px;line-height:1.6;color:var(--onv)}
.dg .ac{display:flex;justify-content:flex-end;gap:8px;padding:20px 16px 16px}
.dg .ac span{height:40px;padding:0 16px;border-radius:20px;display:flex;align-items:center;font-size:14px;font-weight:500;color:var(--primary)}
.dg .ac .fill{background:var(--primary);color:var(--onPrimary);font-weight:600}
.dg .ac .err{background:var(--error);color:#fff;font-weight:600}
.dg .ac .elev{background:var(--scl);box-shadow:0 1px 2px rgba(0,0,0,.2);border-radius:12px}
.rad{width:20px;height:20px;border-radius:10px;border:2px solid var(--onv);flex:none;display:grid;place-items:center}
.rad.on{border-color:var(--primary)}.rad.on::after{content:'';width:10px;height:10px;border-radius:5px;background:var(--primary)}
.ro{display:flex;align-items:center;gap:16px;min-height:48px;padding:0 8px;font-size:14px;font-weight:500}
.ro.on{color:var(--primary);font-weight:600}
/* ---------- new settings row (U.1c) ---------- */
.ab{height:56px;display:flex;align-items:center;position:relative;background:var(--surface);flex:none}
.ab .bk{width:56px;height:56px;display:grid;place-items:center}.ab .bk .mi{font-size:24px}
.ab .t{position:absolute;left:72px;right:72px;top:0;text-align:center;font-size:20px;font-weight:600;line-height:56px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.ab .act{margin-left:auto;display:flex;align-items:center;padding-right:4px}
.ab .act .ib{color:var(--on)}
.sb{padding:4px 16px 32px}
.sgt{padding:18px 16px 8px;font-size:13px;font-weight:600;color:var(--primary)}
.sgt:first-child{padding-top:8px}
.scd{border-radius:16px;background:var(--scl);overflow:hidden}
.sr{display:flex;align-items:center;gap:16px;padding:10px 12px 10px 16px;min-height:64px;position:relative}
.sr.one{min-height:56px}
.scd .sr+.sr::before,.scd .sr+.srb::before,.scd .srb+.sr::before,.scd .srb+.srb::before{content:'';position:absolute;left:56px;right:0;top:0;height:1px;background:color-mix(in srgb,var(--ov) 70%,transparent)}
.sr .ic,.srb .ic{width:24px;font-size:22px;color:var(--primary);flex:none;text-align:center;line-height:1}
.sr .ic .dmk{width:24px;height:24px}
.sr .x,.srb .x{flex:1;min-width:0}
.sr .a,.srb .a{font-size:15px;font-weight:600;line-height:1.4}
.sr .b,.srb .b{font-size:12px;color:var(--onv);line-height:1.45;margin-top:2px;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden}
.sr .v{font-size:14px;color:var(--onv);white-space:nowrap;flex:none}
.sr .chev{font-size:22px;color:var(--onv);flex:none;margin-left:-8px}
.sr .swc{width:28px;height:28px;border-radius:14px;flex:none;box-shadow:inset 0 0 0 1px rgba(0,0,0,.12)}
.sr.sel{background:var(--sc)}.sr.sel .a{color:var(--osc)}
.sr.dis,.srb.dis{opacity:.38}
.sr.foc{box-shadow:inset 0 0 0 2px var(--primary);border-radius:12px}
.sr.prs{background:color-mix(in srgb,var(--on) 10%,var(--scl))}
.sr.hov{background:color-mix(in srgb,var(--on) 6%,var(--scl))}
.srb{position:relative;padding:12px 16px 10px 16px}
.srb .top{display:flex;align-items:center;gap:16px}
.pill{padding:3px 10px;border-radius:12px;background:color-mix(in srgb,var(--primary) 12%,transparent);color:var(--primary);font:600 13px 'Geist','Noto Sans SC';font-feature-settings:'tnum';flex:none}
.trk{height:4px;border-radius:2px;background:color-mix(in srgb,var(--primary) 18%,transparent);margin:18px 10px 12px 50px;position:relative}
.trk i{position:absolute;left:0;top:0;bottom:0;border-radius:2px;background:var(--primary)}
.trk u{position:absolute;top:-8px;width:20px;height:20px;border-radius:10px;background:var(--primary);margin-left:-10px}
.trk b{position:absolute;top:-1px;width:6px;height:6px;border-radius:3px;background:color-mix(in srgb,var(--primary) 45%,transparent);margin-left:-3px}
.cnt{display:flex;align-items:center;flex:none}
.cnt .bt{width:40px;height:40px;border-radius:20px;display:grid;place-items:center;box-shadow:inset 0 0 0 1px var(--ov);color:var(--on)}
.cnt .bt .rx{font-size:20px}
.cnt .n{min-width:56px;height:40px;display:grid;place-items:center;font:600 14px 'Geist','Noto Sans SC';font-feature-settings:'tnum';text-decoration:underline dotted var(--outline);text-underline-offset:4px}
.chips{display:flex;flex-wrap:wrap;gap:8px;margin:10px 0 2px 40px}
.chip{height:36px;padding:0 14px;border-radius:8px;display:inline-flex;align-items:center;gap:6px;font-size:14px;box-shadow:inset 0 0 0 1px var(--ov);white-space:nowrap}
.chip.on{background:var(--sc);color:var(--osc);box-shadow:none;font-weight:600}
.chip .rx,.chip .mr{font-size:18px}
.note{margin:12px 4px 0;font-size:12px;line-height:1.5;color:var(--onv)}
.srch{height:48px;border-radius:24px;background:var(--sch);display:flex;align-items:center;gap:12px;padding:0 6px 0 16px;color:var(--onv);font-size:15px}
.srch .rx{font-size:20px}.srch .q{color:var(--on);flex:1}.srch .x{width:40px;height:40px;display:grid;place-items:center}
.crumb{padding:16px 16px 8px;font-size:13px;font-weight:600;color:var(--onv)}.crumb b{color:var(--primary);font-weight:600}
mark{background:color-mix(in srgb,var(--primary) 22%,transparent);color:inherit;border-radius:3px;padding:0 1px}
/* two panes (width >= 840) */
.pane-l{width:360px;flex:none;border-right:1px solid var(--ov);overflow:hidden;background:var(--surface)}
.pane-r{flex:1;min-width:0;overflow:hidden;position:relative}
.pane-r .ph2{height:56px;display:flex;align-items:center;padding:0 12px 0 24px;font-size:18px;font-weight:600}
.pane-r .ph2 .sp{flex:1}
.pane-r .in{max-width:720px;padding:0 24px 32px}
.pane-l .sb{padding:0 12px 24px}
.pane-l .sr{min-height:60px}
/* misc */
.cap{position:absolute;left:0;right:0;top:0;height:28px;font:600 14px 'Noto Sans SC';color:#333;display:flex;align-items:center}
.ring{width:24px;height:24px;border-radius:12px;border:3px solid var(--primary);border-right-color:transparent;flex:none}
.tnum{font-feature-settings:'tnum'}
'''

STATUS = ('<div class="status"><span>21:36</span><span class="r"><span class="mi">signal_cellular_alt</span>'
          '<span class="mi">wifi</span><span class="mi">battery_full</span></span></div>')
STATUS_LAND = ('<div class="status" style="height:24px;font-size:12px;padding:0 24px"><span>21:36</span><span class="r">'
               '<span class="mi" style="font-size:14px">wifi</span><span class="mi" style="font-size:14px">battery_full</span></span></div>')


def rx(code, s=22, style=''):
    return f'<span class="rx" style="font-size:{s}px;{style}">&#x{code};</span>'


def mi(name, s=24, style=''):
    return f'<span class="mi" style="font-size:{s}px;{style}">{name}</span>'


def mr(name, s=24, style=''):
    return f'<span class="mr" style="font-size:{s}px;{style}">{name}</span>'


def attrs(n=None, tag=None, at=None):
    return (f' data-n="{n}"' if n else '') + (f' data-tag="{tag}"' if tag and n else '') + (f' data-at="{at}"' if at and n else '')


def doc(w, h, scale, body, css='', crop=False, root='ph', vars_=''):
    """One mockup page. root 'ph' (phone), 'win' (window) or 'canvas' (several phones side by side)."""
    size = f'{w}x{h}@{scale}' + (' crop' if crop else '')
    if root == 'ph':
        frame = f'<div class="ph" style="height:{h}px;{vars_}">{body}</div>' if not crop else f'<div class="ph" style="height:auto;min-height:852px;{vars_}">{body}</div>'
    else:
        frame = f'<div class="win" style="--w:{w}px;--h:{h}px;{vars_}{"height:auto;" if crop else ""}">{body}</div>'
    return (f'<!doctype html><html><head><meta charset="utf-8"><meta name="mock-size" content="{size}">'
            f'<link rel="stylesheet" href="kit/kit.css"><style>{CSS}{css}</style></head><body>{frame}</body></html>')


def canvas(phones, caps, h=852, gap=24, css='', scale=2, vars_=''):
    """Several 393-wide phones in one picture, each with a caption above."""
    w = len(phones) * 393 + (len(phones) - 1) * gap
    cells = ''.join(
        f'<div style="position:absolute;left:{i * (393 + gap)}px;top:0;width:393px;height:{h + 32}px">'
        f'<div class="cap">{c}</div><div class="ph" style="position:absolute;top:32px;left:0;height:{h}px;box-shadow:0 0 0 1px #d0d3da">{p}</div></div>'
        for i, (p, c) in enumerate(zip(phones, caps)))
    body = f'<div style="position:relative;width:{w}px;height:{h + 32}px;background:#fff">{cells}</div>'
    return (f'<!doctype html><html><head><meta charset="utf-8"><meta name="mock-size" content="{w}x{h + 32}@{scale}">'
            f'<link rel="stylesheet" href="kit/kit.css"><style>{CSS}{css}</style></head><body>'
            f'<div class="win" style="--w:{w}px;--h:{h + 32}px;background:#fff;{vars_}">{body}</div></body></html>')


# ---------- v3 building blocks ----------
def ab3(title, actions=''):
    return f'<div class="ab3"><div class="bk">{mi("arrow_back")}</div><div class="t">{title}</div><div class="act">{actions}</div></div>'


def gt3(text):
    return f'<div class="gt3">{text}</div>'


def card3(rows):
    out = []
    for i, r in enumerate(rows):
        out.append(r)
        tile = ('<div class="t3', '<div class="sl3')
        if i < len(rows) - 1 and r.startswith(tile) and rows[i + 1].startswith(tile):
            out.append('<div class="dv3"></div>')
    return '<div class="cd3">' + ''.join(out) + '</div>'


def t3(icon, title, sub=None, trailing=None, chev=True, sw=None):
    """buildTile / buildSwitchTile. icon: html; trailing replaces the chevron."""
    if sw is not None:
        tail = f'<span class="sw{" on" if sw else ""}"></span>'
        cls = 't3 sw3'
    else:
        tail = trailing if trailing is not None else (mr('chevron_right', 20, 'color:rgba(0,0,0,.24)') if chev else '')
        cls = 't3'
    subh = f'<div class="b">{sub}</div>' if sub else ''
    return f'<div class="{cls}"><span class="ic">{icon}</span><div class="x"><div class="a">{title}</div>{subh}</div>{tail}</div>'


def sl3(icon, title, value, pct, sub=None):
    subh = f'<div class="b">{sub}</div>' if sub else ''
    return (f'<div class="sl3"><span class="ic">{icon}</span><div class="x"><div class="h"><div class="a">{title}</div><span class="badge3">{value}</span></div>'
            f'{subh}<div class="trk3"><i style="width:{pct}%"></i><u style="left:{pct}%"></u></div></div></div>')


# ---------- new settings row ----------
def ab(title, actions='', n_back=None):
    return (f'<div class="ab"><div class="bk"{attrs(n_back, "keep")}>{mi("arrow_back")}</div><div class="t">{title}</div>'
            f'<div class="act">{actions}</div></div>')


def sgt(text):
    return f'<div class="sgt">{text}</div>'


def card(rows):
    return '<div class="scd">' + ''.join(rows) + '</div>'


def row(icon, title, sub=None, kind='link', value=None, n=None, tag=None, cls='', at=None, sw=False, extra=''):
    """kind: link (value + chevron), choice (value + chevron, opens a dialog), switch, color (swatch),
    counter (value with - / +), none."""
    subh = f'<div class="b">{sub}</div>' if sub else ''
    if kind == 'switch':
        tail = f'<span class="sw{" on" if sw else ""}"></span>'
    elif kind == 'color':
        tail = f'<span class="swc" style="background:{value}"></span>' + mr('chevron_right', 22, 'color:var(--onv);margin-left:-8px')
    elif kind == 'counter':
        tail = (f'<div class="cnt"><span class="bt">{rx("f1af", 20)}</span><span class="n">{value}</span>'
                f'<span class="bt">{rx("ea13", 20)}</span></div>')
    elif kind == 'spin':
        tail = '<span class="ring"></span>'
    elif kind == 'none':
        tail = value or ''
    else:
        tail = (f'<span class="v">{value}</span>' if value else '') + f'<span class="chev mr">chevron_right</span>'
    one = '' if sub else ' one'
    return (f'<div class="sr{one} {cls}"{attrs(n, tag, at)}><span class="ic">{icon}</span>'
            f'<div class="x"><div class="a">{title}</div>{subh}{extra}</div>{tail}</div>')


def slider(icon, title, value, pct, sub=None, n=None, tag=None, marks=(), below='', cls=''):
    subh = f'<div class="b">{sub}</div>' if sub else ''
    mk = ''.join(f'<b style="left:{m}%"></b>' for m in marks)
    return (f'<div class="srb {cls}"{attrs(n, tag)}><div class="top"><span class="ic">{icon}</span><div class="x"><div class="a">{title}</div>{subh}</div>'
            f'<span class="pill">{value}</span></div><div class="trk">{mk}<i style="width:{pct}%"></i><u style="left:{pct}%"></u></div>{below}</div>')


def chips(items, on=None, n=None, tag=None, indent=40):
    cs = ''.join(f'<span class="chip{" on" if (on == i or (isinstance(on, (set, list)) and i in on)) else ""}">'
                 f'{"" if not (on == i or (isinstance(on, (set, list)) and i in on)) else mr("check", 18)}{t}</span>'
                 for i, t in enumerate(items))
    return f'<div class="chips" style="margin-left:{indent}px"{attrs(n, tag)}>{cs}</div>'


def search(q='', n=None, tag=None, clear_n=None):
    if q:
        inner = f'{rx("f0d1", 20)}<span class="q">{q}</span><span class="x"{attrs(clear_n, tag)}>{mr("close", 20)}</span>'
    else:
        inner = f'{rx("f0d1", 20)}<span>搜索设置</span>'
    return f'<div class="srch"{attrs(n, tag)}>{inner}</div>'


def scrim():
    return '<div class="scrim"></div>'


# ---------- the new appearance page (U.6b), also the right pane of the wide overview ----------
PREVIEW_TEXT = '这是用来预览全局字体大小变化的示例文字'


def appearance_v4(n=False, desktop=False, swatch='#2196F3', black=False):
    N = (lambda k, t=None: (k, t)) if n else (lambda k, t=None: (None, None))
    def R(*a, num=None, tag=None, **k):
        nn, tt = N(num, tag)
        return row(*a, n=nn, tag=tt, **k)
    theme = card([
        R(rx('ef6f'), '主题模式', '切换系统/亮色/暗色模式', 'choice', '跟随系统', num=2),
        R(rx('ebd4'), '纯黑背景', '深色时用纯黑背景，OLED 屏更省电', 'switch', sw=black, num=3, tag='add'),
        R(rx('efc5'), '主题颜色', '切换软件的主题颜色', 'color', swatch, num=4),
        R(rx('eeea'), '动态取色', '启用Monet壁纸动态取色', 'switch', num=5, tag='keep'),
        R('<span class="ring" style="width:22px;height:22px;display:inline-block"></span>', '修改加载动画', '自定义全局界面的加载和刷新样式', 'link', '默认圆环', num=6),
    ])
    lists = [
        R(rx('ee90'), '房间卡片设置', '分别定制移动端和桌面端房间卡片的可见信息', 'link', num=7, tag='keep'),
        R(rx('ea62'), '列间距 (横向)', '调整同一行中左右卡片之间的水平缝隙', 'counter', '6 px', num=8),
        R(rx('ea74'), '行间距 (纵向)', '调整同一列中上下卡片之间的垂直缝隙', 'counter', '6 px', num=9),
        R(rx('ea72'), '显示一键置顶按钮', '列表滑动超过设定距离后在右下角悬浮置顶按钮', 'switch', sw=True, num=10),
    ]
    if desktop:
        lists.append(R(rx('efbf'), '分页设置', '电脑上列表底部的分页条：每页条数、页码跳转', 'link', num=11))
    lang = card([
        R(rx('edcf'), '切换语言', '切换软件的显示语言', 'choice', '简体中文', num=12),
        R(rx('f235'), '界面模式', '手机/桌面界面，或适合遥控器的电视界面；切换后立即生效', 'choice', '自动', num=13, tag='keep'),
    ])
    nn, tt = N(15)
    text = card([
        R(rx('ed8b'), '字体', '下载和切换应用使用的字体', 'link', '系统默认', num=14),
        slider(rx('f1ff'), '文字大小', '100%', 33.3, sub='在系统字体大小的基础上放大或缩小', n=nn, tag=tt, marks=(0, 16.7, 33.3, 50, 66.7, 100),
               below=f'<div style="margin:2px 6px 4px 40px;padding:10px 12px;border-radius:12px;background:var(--surface);font-size:14px;line-height:1.5">{PREVIEW_TEXT}</div>'),
        R(rx('ed8d'), '精细化字号微调', '分别调整小字、正文、标题等五种字号', 'link', num=16),
    ])
    return (sgt('主题') + theme + sgt('房间卡片和列表') + card(lists) + sgt('语言和界面') + lang + sgt('字体和字号') + text)


AUTO = mr('auto_awesome', 22)
DMK = '<span class="dmk set" style="width:24px;height:24px;color:var(--primary)"></span>'

# ---------- new ----------
NEW = [
    ('界面', [
        (rx('efc5'), '外观', '主题模式和颜色、加载动画、房间卡片、列表间距、语言、字体和文字大小', 3, 'chg'),
        (rx('ef3e'), '导航栏显示控制', '底部导航栏显示哪些页面和顺序、多画面入口', 4, 'chg')]),
    ('直播来源', [
        (rx('ea42'), '平台显示与授权', '首页平台和顺序、首选平台、平台账号、标签', 5, 'chg'),
        (rx('f064'), '刷新设置', '配置关注状态和直播缩略图的自动刷新', 6, 'keep'),
        (rx('f237'), 'IPTV 设置', '管理您的播放列表和 EPG 订阅源', 7, 'keep')]),
    ('播放', [
        (rx('ed21'), '视频', '清晰度、音量、后台播放、自动全屏、竖屏直播', 8, 'chg'),
        (DMK, '弹幕', '弹幕样式、显示范围、屏蔽词；和直播间里的弹幕设置是同一页', 9, 'add'),
        (rx('eff0'), '小窗弹幕', '系统画中画、桌面小窗和应用内悬浮窗里的弹幕', 10, 'chg'),
        (rx('ebf0'), '播放器内核', '硬件解码、兼容模式、mpv 高级参数', 11, 'chg'),
        (rx('f05a'), '录制', '默认录制清晰度、录制目录、切片、同时录制数、自动重连', 12, 'add')]),
    ('通用和网络', [
        (rx('f0e8'), '通用', '界面刷新率、启动动画、检查更新、定时退出；电脑上还有开机启动和窗口大小', 13, 'chg'),
        (rx('edcf'), '自定义网络代理', '配置全应用核心数据请求与视频流播放代理', 14, 'keep'),
        (AUTO, '本地互动体验', '设置本地昵称、头衔、字幕、体验币与礼物效果', 15, 'keep')]),
    ('数据', [
        (rx('ec16'), '缓存与数据管理', '缓存大小和清理、刷新直播缩略图、下载目录', 16, 'chg'),
        (rx('eb9d'), '备份与恢复', '导出、导入本地配置，WebDAV 和设备同步', 17, 'chg'),
        (rx('ed0f'), '本地配置预览', '查看本机保存的关注、历史、标签和各项设置（只读）', 18, 'chg')]),
]


def v4_list(n=True, selected=None, compact=False):
    out = []
    for g, rows in NEW:
        out.append(sgt(g))
        out.append(card([row(ic, t, None if compact else s, 'link', n=(k if n else None), tag=tag,
                             cls=('sel' if t == selected else '')) for ic, t, s, k, tag in rows]))
    return ''.join(out)




def two_pane(w, h, scale, right_title, right_html, status='', n_left=True, right_actions='', title_attrs='', selected='外观', overlay='', css=''):
    """Width >= 840: the overview list on the left (360), the chosen page on the right (content at most 720)."""
    left = (f'<div class="ab" style="position:relative"><div class="bk"{attrs(1 if n_left else None, "keep")}>{mi("arrow_back")}</div>'
            '<div class="t" style="left:56px;right:56px">设置</div></div>'
            f'<div style="padding:4px 12px 4px">{search(n=2 if n_left else None, tag="add")}</div>'
            f'<div class="sb">{v4_list(n=False, selected=selected)}</div>')
    right = (f'<div class="ph2"><span{title_attrs}>{right_title}</span><span class="sp"></span>{right_actions}</div>'
             f'<div class="in">{right_html}</div>')
    body = (status + f'<div style="display:flex;height:{h - (24 if status else 0)}px"><div class="pane-l">{left}</div>'
            f'<div class="pane-r">{right}</div></div>' + overlay)
    return doc(w, h, scale, body, css=css, root='win')
