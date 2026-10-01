"""U.15i TV settings mockups: pure_live_TV restored (v3-*) and the new design (v4-*).

Baseline: ~/ref/pure_live_TV/lib/features/settings/ (tv_settings_page.dart and
pages/*), rows from lib/core/widgets/tv_settings_row.dart and friends. Every
pure_live_TV size is a 1920x1080 design pixel (`.sp`, `.ts`): on a 1080p TV the
logical canvas is 960x540, so each size is halved here (row title t22 -> 11 px,
subtitle t16 -> 8 px, group title t16 -> 8 px, back button t14 -> 7 px).
Default palette (core/theme/themes/dark_theme.dart): background #121212, accent
#00A1FF, card #1F1F1F at 5 %, focused row = accent hue at L 0.20 (#1E3948).

New side: the phone settings rows (U.2f confirmed rows, U.6c draft) in the TV
style of UI_PLAN 5.5: 48/28 safe margins, text one step larger (row title 18,
subtitle 14, group title 15), dark only, focus = 3 px near-white ring + scale.

    python3 docs/ui/compare/U.15i/src/gen.py
    python3 tools/ui/mock/render.py docs/ui/compare/U.15i/src/ --annotate
"""
import os
import random
import re

HERE = os.path.dirname(os.path.abspath(__file__))
ICON = '../../../apps/pure_live/assets/icons/icon.png'

CSS = '''
body{background:#000}
.ftag{position:absolute;z-index:40;background:#E8590C;color:#fff;font:700 11px/16px 'Noto Sans SC';padding:0 6px;border-radius:4px;white-space:nowrap;box-shadow:0 0 0 1.5px #fff}
.syn2{position:absolute;z-index:40;font:500 9px 'Noto Sans SC';padding:1px 5px;border-radius:4px;background:rgba(0,0,0,.55);color:rgba(255,255,255,.85)}
/* ---------------- pure_live_TV (halved design pixels) ---------------- */
.o{position:relative;width:960px;height:540px;overflow:hidden;background:#121212;color:#fff;font-family:'Noto Sans SC'}
.o.long{height:auto}
.o-bar{height:33px;display:flex;align-items:center;padding:0 8px;flex:none}
.o-btn{position:relative;display:inline-flex;align-items:center;gap:3px;padding:3px 7px;border-radius:6px;background:rgba(31,31,31,.75);font-size:7px;font-weight:500;color:#fff;white-space:nowrap}
.o-btn .mr,.o-btn .rx,.o-btn .mi{font-size:10px}
.o-btn.foc{background:rgba(0,161,255,.65)}.o-btn.sel{background:#00A1FF}.o-btn.sec{background:rgba(31,31,31,.45)}
.o-btn.md{padding:5px 12px;font-size:9px;gap:5px}.o-btn.md .rx,.o-btn.md .mr{font-size:12px}
.o-btn.sm{padding:4px 9px;font-size:8px;gap:4px}.o-btn.sm .mr,.o-btn.sm .rx{font-size:11px}
.o-h{font-size:12px;font-weight:700;margin-left:8px;flex:1}
.o-body{padding:8px}
.o-gt{padding:0 0 4px 4px;font-size:8px;font-weight:600;color:rgba(0,161,255,.85);letter-spacing:.25px}
.o-card{background:rgba(31,31,31,.05);border:.5px solid rgba(31,31,31,.1);border-radius:10px;padding:2px}
.o-gap{height:10px}.o-gap4{height:4px}
.o-row{position:relative;display:flex;align-items:center;padding:7px 8px;border-radius:7px;border:1px solid transparent;min-height:42px}
.o-row .ic{font-size:15px;margin-right:8px;flex:none;width:15px;text-align:center}
.o-row .x{flex:1;min-width:0}
.o-row .a{font-size:11px;font-weight:600;line-height:1.3;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.o-row .b{font-size:8px;font-weight:500;margin-top:2px;line-height:1.35}
.o-row .t{margin-left:6px;display:flex;align-items:center;gap:4px;flex:none}
.o-row .chev{font-size:15px}.o-row .exp{font-size:14px}
.o-row .val{font-size:10px;font-weight:600;white-space:nowrap}
.o-row .txt{font-size:8px;font-weight:600}
.o-row.foc{background:#1E3948;border-color:#00A1FF;box-shadow:0 0 9px .75px rgba(0,161,255,.75)}
.o-row.col{flex-direction:column;align-items:stretch}.o-row.col .r1{display:flex;align-items:center}
.o-sw{width:31px;height:17px;border:1px solid rgba(255,255,255,.6);border-radius:3px;padding:1.5px;display:flex;flex:none}
.o-sw i{width:12px;border-radius:1.5px;background:rgba(255,255,255,.6)}
.o-sw.on{background:rgba(0,161,255,.22);border-color:#00A1FF;justify-content:flex-end}.o-sw.on i{background:#00A1FF}
.o-trk{height:4px;border-radius:2px;background:rgba(255,255,255,.22);margin-top:5px;position:relative}
.o-trk i{position:absolute;left:0;top:0;bottom:0;background:#00A1FF;border-radius:2px}
.o-scrim{position:absolute;inset:0;background:rgba(0,0,0,.54);z-index:20}
.o-dlg{position:absolute;z-index:21;left:50%;top:50%;transform:translate(-50%,-50%);width:400px;padding:16px;background:#1F1F1F;border-radius:12px;border:.5px solid #00A1FF;box-shadow:0 0 6px .5px rgba(0,161,255,.75)}
.o-dlg .h{font-size:12px;font-weight:700;padding-bottom:12px}
.o-opt{position:relative;display:flex;align-items:center;min-height:30px;padding:5px 10px;border-radius:6px;background:rgba(255,255,255,.04);border:.5px solid rgba(255,255,255,.25);font-size:10px;font-weight:500;margin:1px 0}
.o-opt.hl{background:#00A1FF;color:#fff}.o-opt.foc{border-color:#00A1FF}
.o-opt .ck{margin-left:auto;font-size:13px}
.o-dlg .acts{display:flex;justify-content:flex-end;padding-top:12px}
.o-qr{background:#1F1F1F;border-radius:12px;padding:4px;box-shadow:0 2px 6px rgba(0,0,0,.3);display:inline-block}
.o-qr svg{display:block;border-radius:8px}
/* ---------------- new: TV style of the phone settings components ---------------- */
.tv{position:relative;width:960px;height:540px;overflow:hidden;background:var(--surface);color:var(--on);font-family:'Noto Sans SC'}
.tv.long{height:auto;padding-bottom:28px}
.t-col{position:relative;width:720px;margin:0 auto;padding-top:28px}
.t-col.wide{width:864px}
.t-head{height:48px;display:flex;align-items:center;gap:16px;margin-bottom:4px}
.t-btn{position:relative;height:40px;padding:0 16px;border-radius:20px;display:inline-flex;align-items:center;gap:6px;font-size:16px;color:var(--on);background:var(--scc);white-space:nowrap;flex:none}
.t-btn .mr,.t-btn .rx,.t-btn .mo{font-size:20px;color:var(--onv)}
.t-btn.pri{background:var(--primary);color:var(--onPrimary)}.t-btn.pri .mr,.t-btn.pri .rx{color:var(--onPrimary)}
.t-btn.foc{box-shadow:0 0 0 3px #F1F3F7,0 6px 16px rgba(0,0,0,.5);transform:scale(1.05)}
.t-h1{font-size:24px;font-weight:700;flex:1;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.t-path{font-size:14px;color:var(--onv);font-weight:400;margin-right:8px}
.t-gt{font-size:15px;font-weight:600;color:var(--primary);padding:10px 4px 6px}
.t-card{background:var(--scc);border-radius:16px;padding:4px}
.t-row{position:relative;display:flex;align-items:center;gap:16px;min-height:60px;padding:8px 16px;border-radius:12px}
.t-row.two{min-height:64px}
.t-row .ic{font-size:24px;color:var(--primary);width:24px;flex:none;text-align:center}
.t-row .x{flex:1;min-width:0}
.t-row .a{font-size:18px;font-weight:600;line-height:1.35;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.t-row .b{font-size:14px;color:var(--onv);line-height:1.45;margin-top:2px}
.t-row .v{font-size:16px;color:var(--onv);white-space:nowrap;flex:none;font-feature-settings:'tnum'}
.t-row .v.pri{color:var(--primary);font-weight:600}
.t-row .chev{font-size:24px;color:var(--onv);margin-left:-10px;flex:none}
.t-row+.t-row::before{content:'';position:absolute;left:56px;right:16px;top:0;height:1px;background:rgba(255,255,255,.07)}
.t-row.noic+.t-row::before,.t-row.noic::before{left:16px}
.t-row.foc{background:#3A3F47;box-shadow:0 0 0 3px #F1F3F7,0 8px 20px rgba(0,0,0,.55);transform:scale(1.02);z-index:3}
.t-row.foc::before,.t-row.foc+.t-row::before{display:none}
.t-row.dis .a,.t-row.dis .b,.t-row.dis .v,.t-row.dis .ic,.t-row.dis .chev,.t-row.dis .sw,.t-row.dis .pill,.t-row.dis .t-trk,.t-row.dis .t-pos{opacity:.38}
.t-row .why{font-size:13px;color:#E8B04B;margin-top:2px}
.t-row.danger .a{color:var(--error)}
.t-row .sw{transform:scale(1.08)}
.t-row.lift{background:#2C4A6B;box-shadow:0 0 0 3px #F1F3F7,0 14px 30px rgba(0,0,0,.6);transform:scale(1.03) translateY(-2px);z-index:4}
.t-pos{display:flex;align-items:center;gap:2px;font-size:16px;color:var(--onv);font-feature-settings:'tnum';flex:none}
.t-pos .mr{font-size:22px}
.t-sl .h{display:flex;align-items:center;gap:12px}
.t-sl .pill{padding:3px 12px;border-radius:14px;background:rgba(160,202,253,.14);font-size:15px;font-weight:700;color:var(--primary);font-feature-settings:'tnum';flex:none}
.t-trk{position:relative;height:6px;border-radius:3px;background:rgba(160,202,253,.18);margin:14px 6px 6px 0}
.t-trk i{position:absolute;left:0;top:0;bottom:0;border-radius:3px;background:var(--primary)}
.t-trk u{position:absolute;top:-7px;width:20px;height:20px;border-radius:10px;background:var(--primary);margin-left:-10px}
.t-row.foc .t-trk u{box-shadow:0 0 0 4px rgba(160,202,253,.3)}
.t-note{font-size:14px;color:var(--onv);padding:10px 8px 0;line-height:1.55}
.t-note b{color:var(--primary);font-weight:600}
.t-keys{position:absolute;right:48px;bottom:28px;z-index:30;display:flex;gap:16px;font-size:13px;color:var(--onv);background:rgba(17,20,24,.92);padding:6px 12px;border-radius:10px;box-shadow:inset 0 0 0 1px rgba(255,255,255,.08)}
.t-keys b{color:var(--on);font-weight:600;margin-right:4px}
.t-fade{position:absolute;left:0;right:0;bottom:0;height:48px;background:linear-gradient(rgba(17,20,24,0),var(--surface));z-index:5}
.t-fold{position:absolute;left:0;right:0;top:540px;border-top:2px dashed rgba(232,89,12,.8);z-index:50}
.t-fold span{position:absolute;left:8px;top:-18px;font:600 11px 'Noto Sans SC';color:#F08C4C}
.t-chip{position:relative;height:44px;padding:0 16px;border-radius:12px;display:inline-flex;align-items:center;gap:6px;font-size:16px;box-shadow:inset 0 0 0 1px var(--ov);white-space:nowrap}
.t-chip.on{background:var(--sc);box-shadow:none;color:var(--osc);font-weight:600}
.t-chip.foc{box-shadow:0 0 0 3px #F1F3F7,0 6px 16px rgba(0,0,0,.5);transform:scale(1.05);z-index:3}
.t-link{position:relative;display:inline-flex;align-items:center;gap:6px;height:40px;padding:0 10px;border-radius:10px;font-size:16px;color:var(--primary)}
.t-scrim{position:absolute;inset:0;background:rgba(0,0,0,.62);z-index:20}
.t-dlg{position:absolute;z-index:21;left:50%;top:50%;transform:translate(-50%,-50%);width:480px;background:var(--sch);border-radius:24px;padding:24px 16px 12px;box-shadow:0 14px 36px rgba(0,0,0,.55)}
.t-dlg .h{font-size:22px;font-weight:600;padding:0 12px 12px}
.t-dlg .d{font-size:15px;color:var(--onv);padding:0 12px 12px;line-height:1.5}
.t-opt{position:relative;display:flex;align-items:center;gap:12px;min-height:56px;padding:0 16px;border-radius:12px;font-size:18px}
.t-opt.on{color:var(--primary);font-weight:600}
.t-opt .ck{margin-left:auto;font-size:24px;color:var(--primary)}
.t-opt.foc{background:#454A53;box-shadow:0 0 0 3px #F1F3F7;transform:scale(1.02);z-index:2}
.t-dlg .acts{display:flex;justify-content:flex-end;gap:8px;padding:8px 4px 4px}
.t-tb{position:relative;height:44px;padding:0 20px;border-radius:22px;display:grid;place-items:center;font-size:17px;color:var(--primary);font-weight:500}
.t-qrbox{display:flex;gap:28px;align-items:center;background:var(--scc);border-radius:16px;padding:20px 24px}
.t-qr{background:#fff;border-radius:12px;padding:8px;flex:none;position:relative}
.t-qr svg{display:block}
.t-qrbox .x{flex:1;min-width:0}
.t-qrbox .tt{font-size:20px;font-weight:600}
.t-qrbox .st{display:inline-flex;align-items:center;gap:6px;height:28px;padding:0 12px;border-radius:14px;font-size:14px;font-weight:600;margin-top:10px}
.t-qrbox .st.ok{background:var(--okbg);color:#7CD992}.t-qrbox .st.wait{background:rgba(160,202,253,.14);color:var(--primary)}
.t-qrbox .st.err{background:rgba(255,180,171,.14);color:var(--error)}
.t-steps{margin-top:14px;display:flex;flex-direction:column;gap:10px}
.t-steps div{display:flex;gap:10px;font-size:15px;line-height:1.5;color:var(--on)}
.t-steps i{font-style:normal;flex:none;width:22px;height:22px;border-radius:11px;background:rgba(160,202,253,.16);color:var(--primary);font:700 13px/22px 'Geist','Noto Sans SC';text-align:center;margin-top:1px}
.t-addr{margin-top:14px;font:600 17px 'Geist','Noto Sans SC';color:var(--on);letter-spacing:.2px}
.t-addr small{display:block;font:400 13px 'Noto Sans SC';color:var(--onv);margin-bottom:2px;letter-spacing:0}
'''

mr = lambda n, s=None: f'<span class="mr"{f" style=font-size:{s}px" if s else ""}>{n}</span>'
mo = lambda n, s=None: f'<span class="mo"{f" style=font-size:{s}px" if s else ""}>{n}</span>'
rx = lambda c, s=None: f'<span class="rx"{f" style=font-size:{s}px" if s else ""}>&#x{c};</span>'
FTAG = '<span class="ftag" style="{}">焦点</span>'


def ftag(pos='top:-9px;right:-8px'):
    return FTAG.format(pos)


def qr(px, seed=7, n=29):
    """A QR-looking pattern (not a real code): three finders and seeded modules."""
    rnd = random.Random(seed)
    m = px / n
    cells = []

    def finder(x0, y0):
        cells.append(f'<rect x="{x0 * m}" y="{y0 * m}" width="{7 * m}" height="{7 * m}" fill="#101014"/>')
        cells.append(f'<rect x="{(x0 + 1) * m}" y="{(y0 + 1) * m}" width="{5 * m}" height="{5 * m}" fill="#fff"/>')
        cells.append(f'<rect x="{(x0 + 2) * m}" y="{(y0 + 2) * m}" width="{3 * m}" height="{3 * m}" fill="#101014"/>')

    for y in range(n):
        for x in range(n):
            if (x < 8 and y < 8) or (x > n - 9 and y < 8) or (x < 8 and y > n - 9):
                continue
            if rnd.random() < 0.47:
                cells.append(f'<rect x="{x * m:.2f}" y="{y * m:.2f}" width="{m + .3:.2f}" height="{m + .3:.2f}" fill="#101014"/>')
    finder(0, 0), finder(n - 7, 0), finder(0, n - 7)
    return f'<svg width="{px}" height="{px}" viewBox="0 0 {px} {px}" xmlns="http://www.w3.org/2000/svg"><rect width="{px}" height="{px}" fill="#fff"/>{"".join(cells)}</svg>'


# First-screen pictures whose numbered twin is the full-length one (numbers below the fold would pile up at the edge).
NO_N = {'v4-catalog', 'v4-kernel', 'v4-about', 'v4-update'}


def strip_n(html):
    return re.sub(r' data-(?:n|tag)="[^"]*"', '', html)


def write(name, body, size='960x540@2', new=True, extra=''):
    if name in NO_N:
        body = strip_n(body)
    theme = ' data-theme="dark"' if new else ''
    html = (f'<!doctype html><html{theme}><head><meta charset="utf-8"><meta name="mock-size" content="{size}">'
            f'<link rel="stylesheet" href="kit/kit.css"><style>{CSS}{extra}</style></head><body>{body}</body></html>')
    open(os.path.join(HERE, name + '.html'), 'w', encoding='utf-8').write(html)


# =====================================================================
# pure_live_TV pieces (v3-*)
# =====================================================================
def o_bar(title, back_focus=True, actions=''):
    tag = ftag('top:-10px;right:-14px') if back_focus else ''
    return (f'<div class="o-bar"><span class="o-btn{" foc" if back_focus else ""}">{mr("arrow_back_ios_new")}返回{tag}</span>'
            f'<span class="o-h">{title}</span>{actions}</div>')


def o_row(icon, title, sub=None, trail='chev', focus=False, extra='', footer=''):
    t = {'chev': mr('chevron_right'), None: ''}.get(trail, trail) if isinstance(trail, (str, type(None))) else trail
    if trail == 'chev':
        t = f'<span class="chev mr">chevron_right</span>'
    sub_html = f'<div class="b">{sub}</div>' if sub else ''
    tag = ftag('top:-9px;right:6px') if focus else ''
    inner = f'<span class="ic">{icon}</span><div class="x"><div class="a">{title}</div>{sub_html}</div><div class="t">{t}</div>'
    if footer:
        return f'<div class="o-row col{" foc" if focus else ""}"{extra}><div class="r1">{inner}</div>{footer}{tag}</div>'
    return f'<div class="o-row{" foc" if focus else ""}"{extra}>{inner}{tag}</div>'


def o_val(v):
    return f'<span class="val">{v}</span><span class="exp mr">expand_more</span>'


def o_sw(on):
    return f'<span class="o-sw{" on" if on else ""}"><i></i></span>'


def o_trk(p):
    return f'<div class="o-trk"><i style="width:{p}%"></i></div>'


def o_group(title, rows, card=True):
    gt = f'<div class="o-gt">{title}</div>' if title else ''
    return gt + (f'<div class="o-card">{"".join(rows)}</div>' if card else ''.join(rows))


def o_page(title, content, back_focus=True, actions='', pad='8px', long=False):
    return (f'<div class="o{" long" if long else ""}">{o_bar(title, back_focus, actions)}'
            f'<div class="o-body" style="padding:{pad}">{content}</div></div>')


# =====================================================================
# new pieces (v4-*)
# =====================================================================
def head(title, n_back='1', actions='', path='', back_focus=False):
    tag = ftag('top:-10px;right:-8px') if back_focus else ''
    p = f'<span class="t-path">{path}</span>' if path else ''
    return (f'<div class="t-head"><span class="t-btn{" foc" if back_focus else ""}" data-n="{n_back}">{mr("arrow_back")}返回{tag}</span>'
            f'<div class="t-h1">{p}{title}</div>{actions}</div>')


def row(icon, title, sub=None, trail='chev', n=None, focus=False, value=None, cls='', tag=None, why=None):
    """One settings row: the phone row (icon, title, subtitle, value / switch) in the TV style."""
    if trail == 'chev':
        t = (f'<span class="v">{value}</span>' if value else '') + '<span class="chev mr">chevron_right</span>'
    elif trail == 'sw-on':
        t = '<span class="sw on"></span>'
    elif trail == 'sw-off':
        t = '<span class="sw"></span>'
    elif trail is None:
        t = ''
    else:
        t = trail
    ic = f'<span class="ic">{icon}</span>' if icon else ''
    sub_html = f'<div class="b">{sub}</div>' if sub else ''
    why_html = f'<div class="why">{why}</div>' if why else ''
    two = ' two' if sub else ''
    attrs = (f' data-n="{n}"' if n else '') + (f' data-tag="{tag}"' if tag else '')
    ft = ftag('top:-10px;right:14px') if focus else ''
    noic = '' if icon else ' noic'
    return (f'<div class="t-row{two}{noic}{" foc" if focus else ""}{(" " + cls) if cls else ""}"{attrs}>{ic}'
            f'<div class="x"><div class="a">{title}</div>{sub_html}{why_html}</div>{t}{ft}</div>')


def slider(icon, title, value, pct, n=None, focus=False, sub=None, cls='', tag=None):
    attrs = (f' data-n="{n}"' if n else '') + (f' data-tag="{tag}"' if tag else '')
    ft = ftag('top:-10px;right:14px') if focus else ''
    ic = f'<span class="ic" style="align-self:flex-start;margin-top:4px">{icon}</span>' if icon else ''
    sub_html = f'<div class="b">{sub}</div>' if sub else ''
    return (f'<div class="t-row t-sl{" foc" if focus else ""}{"" if icon else " noic"}{(" " + cls) if cls else ""}"{attrs} style="align-items:stretch">{ic}'
            f'<div class="x"><div class="h"><div class="a" style="flex:1">{title}</div><span class="pill">{value}</span></div>{sub_html}'
            f'<div class="t-trk"><i style="width:{pct}%"></i><u style="left:{pct}%"></u></div></div>{ft}</div>')


def group(title, rows):
    gt = f'<div class="t-gt">{title}</div>' if title else ''
    return f'{gt}<div class="t-card">{"".join(rows)}</div>'


def tv(content, long=False, keys=None, fold=False, fade=True, col='', extra=''):
    k = ''
    if keys:
        k = '<div class="t-keys">' + ''.join(f'<span><b>{a}</b>{b}</span>' for a, b in keys) + '</div>'
    fd = '<div class="t-fade"></div>' if (fade and not long) else ''
    fo = '<div class="t-fold"><span>一屏到这里</span></div>' if fold else ''
    return f'<div class="tv{" long" if long else ""}"><div class="t-col{(" " + col) if col else ""}">{content}</div>{fd}{fo}{k}{extra}</div>'


STEP = lambda v: f'<span class="t-pos">{mr("chevron_left")}<b style="color:var(--on);min-width:28px;text-align:center">{v}</b>{mr("chevron_right")}</span>'
KEYS_LIST = [('确认', '打开 / 切换'), ('返回', '上一级')]

# =====================================================================
# 1. settings catalogue
# =====================================================================
CATALOG_TV = [  # pure_live_TV settingsCatalog, live mode (tv_settings_page.dart:21-171)
    ('模式设置', [(rx('f1c9'), '切换模式', '在直播、视频、音乐之间切换')]),
    ('主题设置', [(rx('efc5'), '主题定制', '自定义应用皮肤、夜间模式与主色调'),
              (rx('ef3e'), '导航栏显示控制', '自由定制隐藏或显示底部导航栏特定功能板块')]),
    ('IPTV 设置', [(rx('f237'), 'IPTV 设置', '管理您的播放列表和 EPG 订阅源')]),
    ('刷新设置', [(rx('f064'), '刷新设置', '配置关注状态和直播缩略图的自动刷新')]),
    ('播放内核设置', [(rx('ebf0'), '播放器内核', '切换播放器内核')]),
    ('网络与代理设置', [(rx('edcf'), '自定义网络代理', '配置全应用核心数据请求与视频流播放代理')]),
    ('通用设置', [(rx('f0e8'), '通用', '修改自动开机自启、弹窗提示设置')]),
    ('平台设置', [(rx('ea42'), '平台显示与授权', '修改直播平台显示')]),
    ('数据管理', [(rx('ec16'), '缓存与数据管理', '清理图片缓存、视频缓存')]),
    ('备份管理', [(mr('settings_backup_restore'), '备份与恢复', '一键导出您的本地配置或从云端导入')]),
    ('关于', [(mr('info_outline'), '纯粹直播 TV', '检查更新')]),
]


def v3_catalog():
    body = ''
    for i, (g, rows) in enumerate(CATALOG_TV):
        body += o_group(g, [o_row(ic, t, s) for ic, t, s in rows]) + '<div class="o-gap"></div>'
    write('v3-catalog', o_page('设置', body, pad='6px 8px'), new=False)


# phone order (v3 settings_page.dart:56-178) with the TV entries kept where pure_live_TV has them
def catalog_groups(n0=3, focus_first=True):
    n = [n0]

    def nn():
        n[0] += 1
        return str(n[0] - 1)
    g = []
    g.append(group('模式设置', [row(rx('f1c9'), '切换模式', '在直播、视频、音乐之间切换', value='直播', n=nn(), focus=focus_first)]))
    g.append(group('主题设置', [row(rx('efc5'), '主题定制', '自定义应用皮肤、夜间模式与主色调', n=nn())]))
    g.append(group('IPTV 设置', [row(rx('f237'), 'IPTV 设置', '管理您的播放列表和 EPG 订阅源', n=nn())]))
    g.append(group('刷新设置', [row(rx('f064'), '刷新设置', '配置关注状态和直播缩略图的自动刷新', n=nn())]))
    g.append(group('视频设置', [row(rx('ed21'), '视频', '调整解码器、弹幕、屏幕比例与亮度性能', n=nn(), tag='add')]))
    g.append(group('播放内核设置', [row(rx('ebf0'), '播放器内核', '切换播放器内核', value='Mpv播放器', n=nn())]))
    g.append(group('网络与代理设置', [row(rx('edcf'), '自定义网络代理', '配置全应用核心数据请求与视频流播放代理', n=nn())]))
    g.append(group('通用设置', [row(rx('f0e8'), '通用', '修改自动开机自启、弹窗提示设置', n=nn()),
                            row(rx('ef3e'), '导航栏显示控制', '选择侧边菜单显示哪些入口、顺序和图标', n=nn(), tag='chg'),
                            row(rx('ea42'), '平台显示与授权', '修改直播平台显示', n=nn())]))
    g.append(group('数据管理', [row(rx('ec16'), '缓存与数据管理', '清理图片缓存、视频缓存', n=nn())]))
    g.append(group('备份管理', [row(rx('eb9d'), '备份与恢复', '一键导出您的本地配置或从云端导入', n=nn())]))
    g.append(group('关于', [row(mr('info_outline'), '关于', '检查更新', value='v4.0.0', n=nn())]))
    return ''.join(g)


def v4_catalog():
    act = f'<span class="t-btn" data-n="2">{rx("ed0f")}配置预览</span>'
    write('v4-catalog', tv(head('设置', actions=act) + catalog_groups(), keys=KEYS_LIST))
    write('v4-catalog-full', tv(head('设置', actions=act) + catalog_groups() +
                                '<div class="t-note">音乐模式多“音乐设置”一组，视频模式多“视频设置（点播）”一组，位置照 pure_live_TV（模式下面）。</div>',
                                long=True, fold=True), size='960x1700@2 crop')


# =====================================================================
# 2. switch list: refresh settings
# =====================================================================
def v3_refresh():
    body = (o_group('主页缓存', [o_row(mr('cached'), '主页缓存', '开启后主页各页面保持状态，切换不重新加载；关闭后每次进入都重新加载', o_sw(True))])
            + '<div class="o-gap"></div>'
            + o_group('自动刷新设置', [o_row(mr('sync'), '开启关注自动刷新', '定时刷新关注列表的在线状态', o_sw(True)),
                                  o_row(rx('f20f'), '刷新间隔时间', '自动刷新的时间间隔', o_val('10 分钟')),
                                  o_row(rx('f0e0'), '首页并发刷新任务', '同时刷新的请求数量，过大可能触发风控', o_val('4 · 推荐'))]))
    write('v3-refresh', o_page('刷新设置', body), new=False)


def v4_refresh():
    rows = [row(rx('f064'), '开启关注自动刷新', '定时自动拉取关注直播间状态', 'sw-on', n='3', tag='chg'),
            row(rx('f064'), '返回应用时刷新收藏', '从后台返回应用时自动刷新收藏列表', 'sw-on', n='4', tag='add'),
            row(rx('f20f'), '刷新间隔时间', None, value='10 分钟', n='5', tag='chg'),
            row(rx('f0e0'), '首页并发刷新任务', '完成一个任务后立即领取下一个，避免慢接口拖住整批刷新', value='4 个任务', n='6', tag='chg'),
            row(rx('ee45'), '自动刷新直播缩略图', '按设定周期清理旧封面并重新请求当前缩略图', 'sw-off', n='7', tag='add'),
            row(rx('f20f'), '缩略图刷新间隔', None, value='30 分钟', n='8', cls='dis', why='打开“自动刷新直播缩略图”后生效', tag='add')]
    content = (head('刷新设置')
               + group('主页缓存', [row(mr('cached'), '主页缓存', '开启后主页各页面保持状态，切换不重新加载；关闭后每次进入都重新加载', 'sw-on', n='2', focus=True)])
               + group('自动刷新设置', rows))
    write('v4-refresh', tv(content, long=True, fold=True, keys=None), size='960x900@2 crop')


# =====================================================================
# 3. choice list: player kernel + its select dialog
# =====================================================================
def v3_kernel_body(focus_row=False):
    return (o_group('核心内核设置', [
        o_row(rx('f219'), '内核切换', '不同内核影响解码性能与兼容性', o_val('Mpv播放器'), focus=focus_row),
        o_row(rx('edcf'), '网络代理设置', '配置播放器的网络请求代理', '<span class="txt">未开启</span>'),
        o_row(rx('f371'), '开启硬解码', '优先使用 GPU 硬件解码', o_sw(True))])
        + '<div class="o-gap"></div>'
        + o_row(rx('f108'), '兼容模式', '旧设备播放卡顿时请尝试开启', o_sw(False))
        + '<div class="o-gap4"></div><div class="o-gt">MPV 高级设置</div>'
        + o_row(rx('eadb'), 'MPV 官方文档', '调整内核参数可能导致播放异常，详情请参考 ')
        + o_row(rx('f080'), '重置', '恢复 MPV 播放器全部高级设置为默认值')
        + '<div class="o-gap4"></div>'
        + '<div class="o-card">' + o_row(rx('ec9d'), '自定义驱动与硬件加速', None, o_sw(False))
        + o_row(rx('ebf0'), '硬件解码器(--hwdec)', '启用任意可用解码器')
        + o_row(rx('f237'), '视频输出驱动(--vo)', 'GPU') + '</div>'
        + '<div class="o-gap"></div><div class="o-gt">音频设置</div><div class="o-card">'
        + o_row(rx('f2a2'), '音频输出驱动(--ao)', '自动选择') + '</div>')


def v3_kernel():
    write('v3-kernel', o_page('播放内核设置', v3_kernel_body()), new=False)
    opts = ['Mpv播放器', 'IJK播放器', 'Exo播放器', 'Fvp播放器']
    dlg = ''.join(f'<div class="o-opt{" hl foc" if i == 0 else ""}">{o}{"<span class=ck><span class=mr>check_circle</span></span>" if i == 0 else ""}'
                  f'{ftag("top:-9px;right:-8px") if i == 0 else ""}</div>' for i, o in enumerate(opts))
    dlg = (f'<div class="o-scrim"></div><div class="o-dlg"><div class="h" style="font-size:16px">内核切换</div>{dlg}'
           f'<div class="acts"><span class="o-btn">关闭</span></div></div>')
    page = o_page('播放内核设置', v3_kernel_body(focus_row=False), back_focus=False)
    write('v3-kernel-select', page[:-len('</div>')] + dlg + '</div>', new=False)


def v4_kernel_body(focus=True):
    return (head('播放内核设置', path='设置 ›')
            + group('内核', [row(rx('f219'), '内核切换', '不同内核影响解码性能与兼容性', value='Mpv播放器', n='2', focus=focus),
                           row(rx('f126'), '播放器强制销毁', '彻底关闭播放进程以节省资源', 'sw-off', n='3', tag='add')])
            + group('解码', [row(rx('f371'), '开启硬解码', '优先使用 GPU 硬件解码', 'sw-on', n='4'),
                           row(rx('f100'), '兼容模式', '旧设备播放卡顿时请尝试开启；打开后由系统解码，下面的硬解码和驱动设置不再起作用', 'sw-off', n='5', tag='chg')])
            + group('网络', [row(rx('edcf'), '网络代理设置', '配置播放器的网络请求代理；在“网络与代理设置”里修改', value='未开启', n='6', tag='chg')])
            + group('MPV 高级设置', [row(rx('eba7'), '自定义驱动与硬件加速', '打开后用下面三项，代替“开启硬解码”', 'sw-off', n='7'),
                                 row(rx('ef81'), '视频输出驱动(--vo)', None, value='GPU', n='8', cls='dis', why='打开“自定义驱动与硬件加速”后生效'),
                                 row(rx('f2a2'), '音频输出驱动(--ao)', None, value='自动选择', n='9', cls='dis', why='打开“自定义驱动与硬件加速”后生效'),
                                 row(rx('ebf0'), '硬件解码器(--hwdec)', None, value='启用任意可用解码器', n='10', cls='dis', why='打开“自定义驱动与硬件加速”后生效')])
            + '<div class="t-note">调整内核参数可能导致播放异常，详情请参考 <span class="t-link" data-n="11" data-tag="chg" style="height:auto;padding:0 4px">MPV 官方文档（扫码在手机上看）</span></div>'
            + '<div class="t-card" style="margin-top:12px">' + row(rx('f080'), '恢复默认设置', '恢复本页的设置；视频设置里的首选清晰度不受影响', None, n='12', cls='danger', tag='chg') + '</div>')


def v4_kernel():
    write('v4-kernel', tv(v4_kernel_body(), keys=KEYS_LIST))
    write('v4-kernel-full', tv(v4_kernel_body(), long=True, fold=True), size='960x1300@2 crop')
    opts = ['Mpv播放器', 'IJK播放器', 'Exo播放器', 'Fvp播放器']
    o = ''.join(f'<div class="t-opt{" on foc" if i == 0 else ""}" data-n="{13 + i}">{x}'
                f'{"<span class=ck><span class=mr>check</span></span>" if i == 0 else ""}{ftag("top:-10px;right:-8px") if i == 0 else ""}</div>'
                for i, x in enumerate(opts))
    dlg = (f'<div class="t-scrim"></div><div class="t-dlg"><div class="h">内核切换</div>{o}'
           f'<div class="acts"><span class="t-tb" data-n="17">取消</span></div></div>')
    write('v4-kernel-select', tv(strip_n(v4_kernel_body(focus=False)), extra=dlg, keys=[('确认', '选用并关闭'), ('返回', '不改')]))


# =====================================================================
# 4. slider page: danmaku settings
# =====================================================================
def v3_danmaku():
    rows = [o_row(mr('subtitles'), '弹幕开关', '开启后在直播间显示弹幕', o_sw(True)),
            o_row(rx('ed8d'), '更换弹幕字体', '使用应用内置默认字体'),
            o_row(mr('format_size'), '弹幕字号', None, '<span class="val">16</span>', footer=o_trk(25)),
            o_row(mr('speed'), '弹幕速度', None, '<span class="val">120 px/s</span>', footer=o_trk(26)),
            o_row(mr('opacity'), '弹幕透明度', None, '<span class="val">100%</span>', footer=o_trk(100)),
            o_row(mr('format_bold'), '弹幕字重', None, '<span class="val">500</span>', footer=o_trk(33)),
            o_row(mr('border_color'), '弹幕描边', None, o_sw(True)),
            o_row(mr('line_weight'), '描边宽度', None, '<span class="val">4.0</span>', footer=o_trk(50)),
            o_row(mr('vertical_align_top'), '画面顶部占用高度', None, '<span class="val">100%</span>', footer=o_trk(100))]
    write('v3-danmaku', o_page('弹幕设置', o_group('弹幕观看模板', rows)), new=False)


def danmaku_body(full=False):
    chips = (f'<div style="display:flex;flex-wrap:wrap;gap:10px;padding:4px 4px 0">'
             f'<span class="t-chip on foc" data-n="2">{mr("check", 20)}顶部 20% · 均衡{ftag("top:-10px;right:-8px")}</span>'
             f'<span class="t-chip" data-n="3">顶部 35% · 舒适</span><span class="t-chip" data-n="4">顶部 55% · 高密度</span>'
             f'<span class="t-chip" data-n="5">重置</span></div>'
             f'<div class="t-note" style="padding:10px 4px 0">弹幕只占画面顶部约 20%，速度与密度适中，避免遮挡主体内容。</div>'
             f'<div style="display:flex;gap:8px;padding:6px 0 0"><span class="t-link" data-n="6">{mr("save", 20)}把当前设置存为我的模板</span>'
             f'<span class="t-link" data-n="7">{mr("history", 20)}用我的模板</span></div>')
    out = head('弹幕设置', path='设置 › 视频 ›') + '<div class="t-gt">观看模板</div>' + chips
    out += group('显示范围', [slider(None, '画面顶部占用高度', '20%', 18, n='8'),
                          row(None, '顶部留白（像素）', None, STEP('0'), n='9'),
                          row(None, '区域底部留白（像素）', None, STEP('0'), n='10')])
    if full:
        out += group('样式', [slider(None, '透明度', '92%', 91, n='11'), slider(None, '滚动速度（像素/秒）', '118 px/s', 26, n='12'),
                            slider(None, '字体大小', '16.0 px', 30, n='13'), slider(None, '字体粗细', '稍粗', 50, n='14'),
                            row(None, '弹幕描边', None, 'sw-on', n='15'), slider(None, '描边宽度', '1.5 px', 37, n='16'),
                            row(None, '纯文字模式（隐藏表情）', None, 'sw-off', n='17')])
        out += group('重复弹幕', [row(None, '合并短时间内的相同弹幕', '不同用户发送相同内容时只保留第一条；本地弹幕和系统消息不受影响。', 'sw-off', n='18'),
                              row(None, '相同内容合并时间（秒）', None, STEP('5'), n='19', cls='dis')])
        out += group('画面弹幕交互', [row(None, '点击画面弹幕查看操作', None, 'sw-on', n='20'), row(None, '长按画面弹幕打开屏蔽操作', None, 'sw-on', n='21')])
        out += group('流畅度', [row(None, '弹幕帧率跟随界面刷新率', '跟随“通用”里的省电、均衡或最高档位；关闭后可以手动设帧率。', 'sw-on', n='22'),
                             slider(None, '弹幕帧率', '120 FPS', 50, n='23', cls='dis')])
        out += ('<div class="t-note">以上和手机的弹幕设置（U.2f 已确认）一项一项对应。pure_live_TV 另有的弹幕阴影、阴影模糊半径、字符间距、固定弹幕停留时长、'
                '防重叠安全间距、全量实时模式、高峰排队上限、排队超时丢弃，v4 的弹幕引擎没有，见选择 D1；相似弹幕过滤在“弹幕关键词屏蔽”页（和手机一样）。</div>')
    return out


def v4_danmaku():
    write('v4-danmaku', tv(danmaku_body(), keys=[('←→', '在模板间移动 / 调数值'), ('确认', '选用'), ('返回', '上一级')]))
    write('v4-danmaku-full', tv(danmaku_body(True), long=True, fold=True), size='960x2300@2 crop')


# =====================================================================
# 5. editors: colour picker, navigation order
# =====================================================================
NAMED = [('Crimson', '#DC143C'), ('Orange', '#FF9800'), ('Chrome', '#E6B800'), ('Grass', '#8BC34A'), ('Teal', '#009688'),
         ('SeaFoam', '#70C1CF'), ('Ice', '#739BD0'), ('Blue', '#2196F3'), ('Indigo', '#3F51B5'), ('Violet', '#673AB7'),
         ('Primary', '#6200EE'), ('Orchid', '#DA70D6'), ('Variant', '#3700B3'), ('Secondary', '#03DAC6'),
         ('White', '#FFFFFF'), ('Black', '#000000'), ('Grey', '#9E9E9E')]
HUES = [('Red', ['#EF9A9A', '#EF5350', '#D32F2F']), ('Pink', ['#F48FB1', '#EC407A', '#C2185B']),
        ('Purple', ['#CE93D8', '#AB47BC', '#7B1FA2']), ('Deep Purple', ['#B39DDB', '#7E57C2', '#512DA8']),
        ('Indigo', ['#9FA8DA', '#5C6BC0', '#303F9F']), ('Blue', ['#90CAF9', '#42A5F5', '#1976D2']),
        ('Light Blue', ['#81D4FA', '#29B6F6', '#0288D1']), ('Cyan', ['#80DEEA', '#26C6DA', '#0097A7']),
        ('Teal', ['#80CBC4', '#26A69A', '#00796B']), ('Green', ['#A5D6A7', '#66BB6A', '#388E3C']),
        ('Light Green', ['#C5E1A5', '#9CCC65', '#689F38']), ('Lime', ['#E6EE9C', '#D4E157', '#AFB42B']),
        ('Yellow', ['#FFF59D', '#FFEE58', '#FBC02D']), ('Amber', ['#FFE082', '#FFCA28', '#FFA000']),
        ('Orange', ['#FFCC80', '#FFA726', '#F57C00']), ('Deep Orange', ['#FFAB91', '#FF7043', '#E64A19']),
        ('Brown', ['#BCAAA4', '#8D6E63', '#5D4037']), ('Blue Grey', ['#B0BEC5', '#78909C', '#455A64'])]


def all_colors():
    out = [('跟随主题', '#00A1FF')] + NAMED
    for name, shades in HUES:
        for s, c in zip((200, 400, 700), shades):
            out.append((f'{name} {s}', c))
    return out


def v3_color():
    tiles = ''
    for i, (label, c) in enumerate(all_colors()[:78]):
        focus = i == 0
        brd = '1.5px solid #00A1FF' if (focus or i == 0) else '.5px solid rgba(255,255,255,.3)'
        tiles += (f'<div style="position:relative;border:{brd};padding:3px;display:flex;flex-direction:column;height:66px">'
                  f'<div style="flex:1;background:{c}"></div><div style="font-size:7px;font-weight:500;margin-top:2px;'
                  f'white-space:nowrap;overflow:hidden;text-overflow:ellipsis;color:{"#00A1FF" if focus else "#fff"}">{label}</div>'
                  f'{ftag("top:-9px;right:-8px") if focus else ""}</div>')
    grid = f'<div style="display:grid;grid-template-columns:repeat(13,1fr);gap:5px;padding:8px">{tiles}</div>'
    write('v3-color', f'<div class="o">{o_bar("选择颜色", back_focus=False)}{grid}</div>', new=False)


def v4_color():
    cols = all_colors()
    first = cols[:18]
    def sw(c, n=None, cur=False, foc=False, label=None):
        attrs = f' data-n="{n}"' if n else ''
        ring = 'box-shadow:0 0 0 3px #F1F3F7,0 6px 14px rgba(0,0,0,.5);transform:scale(1.12);' if foc else ''
        inner = (f'<span class="mr" style="font-size:22px;color:{"#000" if c in ("#FFFFFF", "#FFF59D", "#E6EE9C", "#FFEE58") else "#fff"}">check</span>' if cur else '')
        edge = 'box-shadow:inset 0 0 0 1px rgba(255,255,255,.35);' if c in ('#000000',) and not foc else ''
        lab = f'<span style="position:absolute;left:50%;top:44px;transform:translateX(-50%);font-size:12px;color:var(--onv);white-space:nowrap">{label}</span>' if label else ''
        return (f'<div style="position:relative;display:grid;place-items:center;height:62px"{attrs}>'
                f'<div style="width:36px;height:36px;border-radius:18px;background:{c};display:grid;place-items:center;{ring}{edge}">{inner}</div>'
                f'{lab}{ftag("top:-4px;right:-2px") if foc else ""}</div>')
    row1 = ''.join(sw(c, n='2' if i == 0 else ('3' if i == 1 else None), cur=(i == 0), foc=(i == 1), label=('跟随主题' if i == 0 else None))
                   for i, (lab, c) in enumerate(first))
    shades = ''
    for k in range(3):
        shades += ''.join(sw(sh[k], n='4' if (k == 0 and j == 0) else None) for j, (nm, sh) in enumerate(HUES))
    body = (head('选择颜色', path='主题定制 › 修改加载颜色 ›')
            + '<div class="t-gt">常用</div>'
            + f'<div class="t-card" style="padding:4px 8px 20px"><div style="display:grid;grid-template-columns:repeat(18,1fr)">{row1}</div></div>'
            + '<div class="t-gt">色板</div>'
            + f'<div class="t-card" style="padding:4px 8px"><div style="display:grid;grid-template-columns:repeat(18,1fr)">{shades}</div></div>'
            + '<div style="display:flex;align-items:center;gap:14px;padding:14px 8px 0">'
              '<div style="width:44px;height:44px;border-radius:12px;background:#DC143C"></div>'
              '<div><div style="font-size:18px;font-weight:600;font-feature-settings:\'tnum\'">#DC143C</div>'
              '<div style="font-size:14px;color:var(--onv)">当前：跟随主题 · 确认后用这个颜色，返回不改</div></div></div>')
    write('v4-color', tv(body, col='wide', keys=[('←↑→↓', '选颜色'), ('确认', '选用'), ('返回', '不改')], fade=False))


NAV = [('关注', None, 'favorite_border'), ('热门', None, 'local_fire_department'), ('分区', None, 'category'),
       ('关注分区', '关注分区', 'collections_bookmark'), ('链接放映', '链接放映', 'movie_creation'),
       ('搜索直播', '搜索', 'search'), ('观看记录', '历史记录', 'history')]


def v3_nav():
    rows = [o_row(mo('view_sidebar'), '展开导航栏', '开启后显示完整菜单名称，关闭仅显示图标', o_sw(True))]
    vis = [o_row(mo(ic) if ic not in ('category', 'search', 'history') else mr(ic), t, s, o_sw(i != 4)) for i, (t, s, ic) in enumerate(NAV)]
    body = o_group('导航栏显示方式', rows) + '<div class="o-gap"></div>' + o_group('显示项目', vis)
    write('v3-nav-visibility', o_page('显示项目', body), new=False)
    order = [x for i, x in enumerate(NAV) if i != 4]
    rows = []
    for i, (t, s, ic) in enumerate(order):
        up = 'rgba(255,255,255,.35)' if i == 0 else '#fff'
        dn = 'rgba(255,255,255,.35)' if i == len(order) - 1 else '#fff'
        trail = (f'<span class="mr" style="font-size:13px;color:{up}">keyboard_arrow_up</span><span class="val">{i + 1}/{len(order)}</span>'
                 f'<span class="mr" style="font-size:13px;color:{dn}">keyboard_arrow_down</span>')
        rows.append(o_row(mo(ic) if ic not in ('category', 'search', 'history') else mr(ic), t, '移动到指定位置', trail))
    body = (o_group('排序', rows)
            + '<div style="padding:6px 2px;font-size:7px;font-weight:500">已在侧边菜单中隐藏，需先在上方开启才能调整顺序: 链接放映</div>')
    write('v3-nav-order', o_page('排序', body), new=False)


def nav_rows(moving=False):
    order = [0, 1, 2, 3, 5, 6]
    if moving:
        order = [0, 2, 1, 3, 5, 6]
    out = []
    vis_total = 6
    for pos, i in enumerate(order):
        t, s, ic = NAV[i]
        icon = mo(ic) if ic not in ('category', 'search', 'history') else mr(ic)
        lifted = moving and i == 1
        if lifted:
            trail = (f'<span class="t-pos">{mr("keyboard_arrow_up")}<b style="color:var(--on)">{pos + 1}/{vis_total}</b>{mr("keyboard_arrow_down")}</span>'
                     '<span class="sw on"></span>')
            out.append(f'<div class="t-row lift" data-n="4"><span class="ic">{icon}</span><div class="x"><div class="a">{t}</div>'
                       f'<div class="b" style="color:var(--on)">上下键移动，确认放下</div></div>{trail}{ftag("top:-10px;right:14px")}</div>')
            continue
        trail = f'<span class="t-pos">{pos + 1}/{vis_total}</span><span class="sw on"></span>'
        out.append(row(icon, t, None, trail, n=('4' if pos == 0 else ('5' if pos == 1 else None)), focus=(not moving and pos == 0)))
    t, s, ic = NAV[4]
    out.append(row(mo(ic), t, None, '<span class="t-pos" style="opacity:.5">未显示</span><span class="sw"></span>', n='6'))
    return out


def v4_nav(moving=False):
    body = (head('导航栏显示控制', path='设置 ›')
            + group('导航栏显示方式', [row(mo('view_sidebar'), '展开导航栏', '开启后显示完整菜单名称，关闭仅显示图标', 'sw-on', n='2')])
            + '<div class="t-gt">显示项目和顺序</div>'
            + '<div class="t-note" style="padding:0 4px 8px">确认：显示或隐藏 · 长按确认（或菜单键）：调整顺序。至少保留一个入口。</div>'
            + f'<div class="t-card">{"".join(nav_rows(moving))}</div>'
            + group('图标', [row(mo('palette'), '图标', '更换侧边菜单每个入口使用的图标', n='7')]))
    keys = [('↑↓', '移动'), ('确认', '放下'), ('返回', '取消移动')] if moving else [('确认', '显示 / 隐藏'), ('长按确认', '调整顺序')]
    if moving:
        body = body.replace('data-n="2"', '').replace('data-n="5"', '').replace('data-n="6"', '').replace('data-n="7"', '')
    if moving:
        body = body.replace(body[body.index('<div class="t-gt">导航栏显示方式'):body.index('<div class="t-gt">显示项目和顺序')], '')
        write('v4-nav-moving', tv(body, keys=keys))
    else:
        write('v4-nav', tv(body, long=True, fold=True), size='960x900@2 crop')


# =====================================================================
# 6. account: bilibili QR login
# =====================================================================
def v3_bili():
    qrbox = (f'<div class="o-qr">{qr(120, 3)}</div>')
    body = (f'<div style="display:flex;justify-content:center;align-items:center;height:490px"><div style="width:330px">'
            f'<div class="o-gt">二维码登录</div><div class="o-card" style="padding:8px;display:flex;flex-direction:column;align-items:center">'
            f'<div style="height:150px;display:grid;place-items:center">{qrbox}</div>'
            f'<div style="font-size:10px;font-weight:500;text-align:center;padding:4px 0 6px">请使用哔哩哔哩手机客户端扫描二维码登录</div></div></div></div>'
            '<span class="syn2" style="left:375px;top:190px">示意二维码</span>')
    write('v3-bili', o_page('哔哩哔哩', body, pad='0 8px'), new=False)


def qr_block(title, status, steps, addr=None, qrsize=200, seed=5, n_btn=None, btn=None, st_cls='wait', extra=''):
    st = f'<div class="st {st_cls}">{status}</div>' if status else ''
    sp = '<div class="t-steps">' + ''.join(f'<div><i>{i + 1}</i><span>{s}</span></div>' for i, s in enumerate(steps)) + '</div>' if steps else ''
    ad = f'<div class="t-addr"><small>或在同一局域网的浏览器打开</small>{addr}</div>' if addr else ''
    b = f'<div style="margin-top:16px">{btn}</div>' if btn else ''
    return (f'<div class="t-qrbox"><div class="t-qr">{qr(qrsize, seed)}<span class="syn2" style="left:8px;bottom:-18px;background:none;color:var(--onv);padding:0">示意二维码</span></div>'
            f'<div class="x"><div class="tt">{title}</div>{st}{sp}{ad}{b}{extra}</div></div>')


def v4_bili():
    blk = qr_block('扫码登录', f'{mr("hourglass_empty", 16)}等待扫码', ['请使用哔哩哔哩手机客户端扫描二维码登录', '在手机上确认登录', '登录后这里列出账号，可以添加多个、随时切换'],
                   btn=f'<span class="t-btn foc" data-n="2">{rx("f064")}刷新二维码{ftag("top:-10px;right:-8px")}</span>')
    body = head('哔哩哔哩', path='设置 › 平台显示与授权 › 三方认证 ›') + '<div class="t-gt">二维码登录</div>' + blk
    write('v4-bili', tv(body, fade=False, keys=[('确认', '刷新二维码'), ('返回', '上一级')]))


def v4_bili_states():
    def cell(title, inner, cap):
        return (f'<div style="background:var(--scc);border-radius:16px;padding:16px;display:flex;flex-direction:column;gap:10px">'
                f'<div style="font-size:13px;font-weight:600;color:#F08C4C">{cap}</div><div style="font-size:18px;font-weight:600">{title}</div>{inner}</div>')
    load = ('<div style="display:flex;gap:16px;align-items:center"><div style="width:120px;height:120px;border-radius:12px;background:var(--sch);display:grid;place-items:center">'
            '<div style="width:36px;height:36px;border-radius:18px;border:4px solid rgba(160,202,253,.25);border-top-color:var(--primary)"></div></div>'
            '<div style="font-size:15px;color:var(--onv)">正在加载二维码…</div></div>')
    scanned = ('<div style="display:flex;gap:16px;align-items:center"><div class="t-qr" style="padding:6px;opacity:.25">' + qr(108, 9) + '</div>'
               '<div><div class="st wait" style="display:inline-flex;align-items:center;gap:6px;height:28px;padding:0 12px;border-radius:14px;font-size:14px;font-weight:600;background:rgba(160,202,253,.14);color:var(--primary)">'
               + mr('phonelink_ring', 16) + '已扫描，请在手机上确认</div><div style="font-size:14px;color:var(--onv);margin-top:8px">正在核验账号…</div></div></div>')
    expired = ('<div style="display:flex;gap:16px;align-items:center"><div style="width:120px;height:120px;border-radius:12px;background:var(--sch);display:grid;place-items:center">'
               + mr('qr_code_2', 44) + '</div><div><div style="font-size:16px;font-weight:600;color:var(--error)">二维码已失效</div>'
               '<div style="font-size:14px;color:var(--onv);margin:4px 0 10px">请点击下方按钮重新获取二维码</div>'
               f'<span class="t-btn foc" data-n="3">{rx("f064")}刷新二维码{ftag("top:-10px;right:-8px")}</span></div></div>')
    acc = ('<div class="t-card" style="background:var(--sch)">'
           + row('<span style="display:block;width:28px;height:28px;border-radius:14px;background:url(.cache/img/65.jpg) center/cover"></span>', '晚风', '当前账号', f'{mr("lock_outline", 20)}', n='4', focus=True)
           + row('<span style="display:block;width:28px;height:28px;border-radius:14px;background:url(.cache/img/111.jpg) center/cover"></span>', '小熊', 'UID 3546xxxx', n='5')
           + row(mr('add'), '添加账号', None, n='6') + '</div>')
    grid = (f'<div style="display:grid;grid-template-columns:1fr 1fr;gap:14px">'
            + cell('加载中', load, '状态 1') + cell('已扫描', scanned, '状态 2') + cell('二维码已失效', expired, '状态 3')
            + cell('已登录账号', acc + '<div style="font-size:13px;color:var(--onv)">确认：切换到此账号 / 账号密码锁 / 删除账号</div>', '状态 4（登录后）') + '</div>')
    write('v4-bili-states', tv(head('哔哩哔哩').replace(' data-n="1"', '') + grid, col='wide', fade=False, long=True), size='960x1000@2 crop')


# =====================================================================
# 7. QR to the phone: backup browser, log viewer
# =====================================================================
ADDR = 'http://192.168.1.12:8787/#/sync'


def v3_backup_browser():
    body = (f'<div style="display:flex;flex-direction:column;align-items:center;padding-top:30px">'
            f'<div class="o-qr" style="padding:4px">{qr(120, 11)}</div>'
            f'<div style="font-size:12px;font-weight:600;margin-top:5px">{ADDR}</div>'
            f'<div style="font-size:9px;font-weight:500;margin-top:10px">用手机相机扫码打开网页，在浏览器里下载或导入备份文件（与本地备份是同一种文件）</div></div>'
            '<span class="syn2" style="left:376px;top:66px">示意二维码</span>')
    write('v3-backup-browser', o_page('手机扫码导入 / 导出备份', body), new=False)


def v4_backup_browser():
    blk = qr_block('手机扫码导入 / 导出备份', f'{mr("check_circle", 16)}局域网服务运行中',
                   ['用手机相机扫码打开网页', '在浏览器里下载或导入备份文件', '和“本地备份”是同一种文件'], addr=ADDR, st_cls='ok', seed=11)
    body = head('手机扫码导入 / 导出备份', path='备份与恢复 ›', back_focus=True) + '<div style="height:16px"></div>' + blk
    write('v4-backup-browser', tv(body, fade=False, keys=[('确认 / 返回', '回到备份与恢复')]))


def v3_log():
    step = lambda ic, t: f'<div style="display:flex;gap:5px;margin-bottom:5px"><span class="mr" style="font-size:9px;color:#00A1FF">{ic}</span><span style="font-size:7px;font-weight:500">{t}</span></div>'
    body = (f'<div class="o-gt">在浏览器中查看日志</div><div style="background:#1F1F1F;border-radius:10px;padding:12px;display:flex;gap:14px">'
            f'<div style="display:flex;flex-direction:column;align-items:center"><div class="o-qr">{qr(120, 13)}</div>'
            f'<div style="font-size:12px;font-weight:600;margin-top:5px">http://192.168.1.12:8787/#/log</div></div>'
            f'<div style="flex:1">{step("qr_code_scanner", "用手机扫描二维码，或在同一局域网的电脑浏览器打开上方地址")}'
            f'{step("visibility", "页面可在线查看运行日志，并提供日志下载")}{step("description", "需先在日志管理中开启本地日志，否则页面没有内容")}</div></div>'
            '<span class="syn2" style="left:46px;top:66px">示意二维码</span>')
    write('v3-log', o_page('在浏览器中查看日志', body), new=False)


def v4_log():
    blk = qr_block('在浏览器中查看日志', f'{mr("check_circle", 16)}局域网服务运行中',
                   ['用手机扫描二维码，或在同一局域网的电脑浏览器打开下方地址', '页面可在线查看运行日志，并提供日志下载'],
                   addr='http://192.168.1.12:8787/#/log', st_cls='ok', seed=13)
    body = (head('在浏览器中查看日志', path='设置 › 日志管理 ›') + '<div style="height:12px"></div>' + blk
            + '<div style="height:12px"></div><div class="t-card">'
            + row(rx('ed0f'), '启用本地日志', '开启后将日志写入本地文件；不开的话网页上没有内容', 'sw-off', n='2', focus=True, tag='add') + '</div>')
    write('v4-log', tv(body, fade=False, keys=[('确认', '开 / 关本地日志'), ('返回', '上一级')]))


# =====================================================================
# 8. about and update
# =====================================================================
def v3_about():
    body = (o_group('关于', [o_row(mr('system_update_alt'), '在线更新', '当前版本： v1.6.2+162')]) + '<div class="o-gap"></div>'
            + o_group('项目', [o_row(mo('cloud'), '使用 GitHub 直连更新', '不经过镜像加速，直连 GitHub 检查更新', o_sw(True))]))
    write('v3-about', o_page('纯粹直播 TV', body), new=False)


def v3_update():
    hero = (f'<div style="display:flex;flex-direction:column;align-items:center;padding:6px 0 12px">'
            f'<div style="width:48px;height:48px;border-radius:12px;background:#1F1F1F;border:.5px solid rgba(0,161,255,.35);box-shadow:0 0 9px 1px rgba(0,161,255,.25);padding:7px">'
            f'<div style="width:100%;height:100%;background:url({ICON}) center/contain no-repeat"></div></div>'
            f'<div style="font-size:11px;font-weight:700;margin-top:7px">纯粹直播 TV</div>'
            f'<div style="margin-top:4px;padding:2px 7px;border-radius:99px;background:rgba(0,161,255,.14);color:#00A1FF;font-size:8px;font-weight:600">v1.6.2+162</div></div>')
    status = ('<div style="height:90px;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:4px">'
              '<span class="mr" style="font-size:22px;opacity:.6">inbox</span><div style="font-size:9px;font-weight:600">已是最新版本</div>'
              '<div style="font-size:7px;opacity:.7">v1.6.2+162</div></div>')
    body = (hero + o_group('关于', [o_row(mr('info_outline'), '当前版本：', 'v1.6.2+162 · 直连 GitHub', o_val('已是最新版本')), status])
            + '<div class="o-gap"></div>'
            + o_group('更新历史', [o_row(rx('ee17'), '版本历史', '12 · 已是最新版本 v1.6.2'),
                                o_row(mr('article'), 'v1.6.2', '2026-09-28', o_val('使用中')),
                                o_row(mr('article'), 'v1.6.1', '2026-09-20', o_val('查看更新内容'))]))
    act = f'<span class="o-btn">{rx("f064")}检查更新</span>'
    write('v3-update', o_page('在线更新', body, actions=act, pad='6px 12px'), new=False)


def v4_about():
    hero = (f'<div style="display:flex;align-items:center;gap:18px;padding:6px 4px 4px">'
            f'<div style="width:64px;height:64px;border-radius:16px;background:url({ICON}) center/cover"></div>'
            f'<div><div style="font-size:22px;font-weight:700">纯粹直播</div><div style="font-size:15px;color:var(--onv);margin-top:2px;font-feature-settings:\'tnum\'">v4.0.0+400</div></div></div>')
    body = (head('关于', path='设置 ›') + hero
            + group('关于', [row(rx('ec56'), '在线更新', '发现新版本 v4.1.0', value='去更新', n='2', focus=True),
                           row(rx('ee17'), '历史记录', '历史版本更新记录', n='3'),
                           row(rx('f10c'), '开源许可证', None, n='4')])
            + group('项目', [row(rx('ebad'), '项目主页', 'https://github.com/wzgrx/pure_live · 确认后扫码在手机上打开', n='5', tag='chg'),
                           row(f'<span style="color:var(--error)">{rx("eca1")}</span>', '项目声明', '本程序为纯本地客户端应用，直接请求媒体平台官方公开接口……（确认后看全文）', n='6')]))
    write('v4-about', tv(body, keys=KEYS_LIST))
    write('v4-about-full', tv(body, long=True, fold=True), size='960x900@2 crop')


def v4_update():
    status = ('<div class="t-card" style="padding:16px 20px;display:flex;align-items:center;gap:18px">'
              f'<div style="width:56px;height:56px;border-radius:14px;background:url({ICON}) center/cover;flex:none"></div>'
              '<div style="flex:1"><div style="font-size:20px;font-weight:600">发现新版本 v4.1.0</div>'
              '<div style="font-size:14px;color:var(--onv);margin-top:2px">当前 v4.0.0+400 · 发布于 2026-10-08 · 镜像加速</div></div>'
              f'<span class="t-btn pri foc" data-n="2">{mr("download")}下载并安装{ftag("top:-10px;right:-8px")}</span></div>')
    body = (head('在线更新', path='关于 ›', actions=f'<span class="t-btn" data-n="7">{rx("f064")}检查更新</span>') + status
            + group('安装包', [row(mr('memory'), 'ARM64 (64位)', '适用于 Android TV 系统 · 按设备自动选择', None, n=None),
                             row(rx('eeb2'), '下载源', None, value='下载源 1', n='3'),
                             row(mr('bolt'), '渲染器', '画面异常或黑屏时改用 Skia 版；选择会记住，下载源按所选变体解析', value='Impeller（新渲染器）', n='4')])
            + group('更新日志', [row(mr('article'), 'v4.1.0', '更新说明（示意）……确认后看全文', value='查看更新内容', n='5'),
                              row(rx('ee17'), '版本历史', '本机更新记录和全部版本', n='6')]))
    write('v4-update', tv(body, keys=[('确认', '下载并安装'), ('返回', '上一级')]))
    write('v4-update-full', tv(body, long=True, fold=True), size='960x900@2 crop')


if __name__ == '__main__':
    v3_catalog(); v4_catalog()
    v3_refresh(); v4_refresh()
    v3_kernel(); v4_kernel()
    v3_danmaku(); v4_danmaku()
    v3_color(); v4_color()
    v3_nav(); v4_nav(); v4_nav(True)
    v3_bili(); v4_bili(); v4_bili_states()
    v3_backup_browser(); v4_backup_browser()
    v3_log(); v4_log()
    v3_about(); v3_update(); v4_about(); v4_update()
