"""Shared pieces for the U.11 / U.12 settings-style mockups (backup, WebDAV,
device sync, toolbox, about, tags, danmaku block).  The same file is copied
into each task's src/ so a task folder stands alone.

v3 (tag v3.2.11) settings look, from common/widgets/widget_extensions.dart:
  buildGroupTitle  12 bold, primary 65 %, left 8 / bottom 8          (:21-36)
  buildModernCard  surfaceContainerHighest 15 %, radius 20, 0.5 border (:101-111)
  buildTile        icon 22 primary, title 15/600, subtitle 12 hint 75 %,
                   chevron_right_rounded 20 hint 40 %, padding 16/8   (:154-233)
  content max width 960, centred                                     (:8-18)
App bar: centred title, titleLarge (20) semi-bold (common/style/theme.dart:115-121).
New design: the settings rows of the U.2f / U.2e component (section title 13/600
primary, card surfaceContainerLow radius 16, title 15/400, subtitle 12
onSurfaceVariant), reading width 720 (plan 5.3)."""
import os

IMG = '.cache/img/'

CSS = '''
body{position:relative}
.ph{display:flex;flex-direction:column}
.ph>.status,.ph>.bar{flex:none}
.win{display:flex;flex-direction:column}
.sb24{height:24px;display:flex;align-items:center;justify-content:space-between;padding:0 16px;font:600 12px 'Geist','Noto Sans SC';background:var(--surface);flex:none}
.sb24 .mi{font-size:13px}
.bar{height:56px;display:flex;align-items:center;background:var(--surface);position:relative;flex:none;z-index:3}
.bar .b{width:56px;height:56px;display:grid;place-items:center;flex:none}
.bar .b .mi,.bar .b .mr{font-size:24px}
.bar .ct{position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);font-size:20px;font-weight:600;white-space:nowrap;max-width:60%;overflow:hidden;text-overflow:ellipsis}
.bar .lt{flex:1;min-width:0;padding-left:4px;font-size:20px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.bar .tt{flex:1;min-width:0;padding-left:4px}
.bar .tt .n{font-size:17px;font-weight:600;line-height:22px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.bar .tt .s{font-size:12px;color:var(--onv);line-height:16px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.bar .ib2{width:48px;height:48px;display:grid;place-items:center;flex:none;color:var(--on)}
.bar .ib2 .mi,.bar .ib2 .mr,.bar .ib2 .rx{font-size:24px}
.body{flex:1;min-height:0;overflow:hidden;position:relative}
.fill{position:absolute;inset:0}
/* ---------- v3 settings list ---------- */
.l3{padding:12px 16px 32px}
.l3>.w{max-width:960px;margin:0 auto}
.g3{padding:0 0 8px 8px;font-size:12px;font-weight:700;color:rgba(54,97,142,.65);letter-spacing:.5px}
.cd3{background:#F5F6FC;border-radius:20px;box-shadow:inset 0 0 0 .5px rgba(0,0,0,.05);margin-bottom:20px;overflow:hidden}
.t3{display:flex;align-items:center;gap:12px;padding:8px 16px;min-height:72px}
.t3.one{min-height:56px}
.t3 .ic{color:var(--primary);font-size:22px;flex:none;align-self:center;padding-top:2px}
.t3 .x{flex:1;min-width:0}
.t3 .t{font-size:15px;font-weight:600;color:rgba(0,0,0,.87);line-height:20px}
.t3 .s{font-size:12px;color:rgba(0,0,0,.45);margin-top:2px;line-height:17px;word-break:break-all}
.t3 .s.err{color:rgba(186,26,26,.8)}
.t3 .ch{color:rgba(0,0,0,.24);font-size:20px;flex:none}
.t3 .tr3{flex:none;display:flex;align-items:center}
/* ---------- new settings list (U.2f / U.2e component rows) ---------- */
.ln{padding:4px 0 32px}
.ln>.w{max-width:720px;margin:0 auto}
.ns{padding:18px 20px 8px;font-size:13px;font-weight:600;color:var(--primary);display:flex;align-items:center;gap:8px}
.ns .r{margin-left:auto;font-size:13px;font-weight:400;color:var(--onv);display:flex;align-items:center;gap:4px}
.ns .r.lk{color:var(--primary);font-weight:600}
.ncd{margin:0 12px;background:var(--scl);border-radius:16px;overflow:hidden}
.nr{display:flex;align-items:center;gap:16px;padding:10px 12px 10px 16px;min-height:56px;position:relative}
.nr .ic{color:var(--primary);font-size:22px;flex:none}
.nr .ic.mute{color:var(--onv)}
.nr .x{flex:1;min-width:0}
.nr .t{font-size:15px;line-height:21px}
.nr .t b{font-weight:600}
.nr .s{font-size:12px;color:var(--onv);line-height:17px;margin-top:2px;word-break:break-all}
.nr .s.err{color:var(--error)}
.nr .ch{color:var(--onv);font-size:20px;flex:none}
.nr .more{width:48px;height:48px;display:grid;place-items:center;color:var(--onv);flex:none;margin:-8px -4px -8px 0}
.nr.hov{background:rgba(127,127,127,.10)}
.nr+.nr.sep{border-top:1px solid color-mix(in srgb,var(--ov) 60%,transparent)}
.dis{opacity:.38}
.spin{width:20px;height:20px;border-radius:10px;border:2.5px solid color-mix(in srgb,var(--primary) 22%,transparent);border-top-color:var(--primary);transform:rotate(45deg);flex:none}
.spin.big{width:40px;height:40px;border-radius:20px;border-width:4px}
.prog{height:4px;background:color-mix(in srgb,var(--primary) 18%,transparent);position:relative;border-radius:2px}.prog i{position:absolute;left:0;top:0;bottom:0;width:40%;background:var(--primary);border-radius:2px}
.hint{padding:8px 20px 0;font-size:12px;color:var(--onv);line-height:1.5}
/* ---------- status view ---------- */
.sv{display:flex;flex-direction:column;align-items:center;justify-content:center;text-align:center;height:100%;padding:24px}
.svc{width:86px;height:86px;border-radius:43px;background:rgba(225,226,232,.15);border:1px solid rgba(54,97,142,.05);display:grid;place-items:center}
.svc .mr,.svc .mi,.svc .rx{font-size:42px;color:rgba(54,97,142,.6)}
.sv h4{margin-top:20px;font-size:15px;font-weight:600}
.sv p{padding:6px 28px 0;max-width:376px;font-size:13px;line-height:1.5;color:var(--onv)}
.sv .acts{display:flex;gap:8px;margin-top:16px;flex-wrap:wrap;justify-content:center}
/* ---------- buttons, fields ---------- */
.fb{height:40px;padding:0 20px;border-radius:20px;background:var(--primary);color:var(--onPrimary);font-size:14px;font-weight:600;display:inline-flex;align-items:center;justify-content:center;gap:6px;white-space:nowrap}
.fb.big{height:48px;border-radius:24px}
.fb.err{background:var(--error);color:#fff}
.tb{height:40px;padding:0 12px;border-radius:20px;color:var(--primary);font-size:14px;font-weight:600;display:inline-flex;align-items:center;gap:6px;white-space:nowrap}
.ob{height:40px;padding:0 18px;border-radius:20px;box-shadow:inset 0 0 0 1px var(--outline);color:var(--primary);font-size:14px;font-weight:600;display:inline-flex;align-items:center;justify-content:center;gap:6px;white-space:nowrap}
.ob.big,.tb.big{height:48px;border-radius:24px}
.tonal{height:40px;padding:0 18px;border-radius:20px;background:var(--sc);color:var(--osc);font-size:14px;font-weight:600;display:inline-flex;align-items:center;justify-content:center;gap:6px;white-space:nowrap}
.fb .mr,.tb .mr,.ob .mr,.tonal .mr,.fb .mi,.ob .mi,.tb .mi,.tonal .mi,.fb .rx,.ob .rx,.tb .rx,.tonal .rx{font-size:18px}
.fld{height:52px;border-radius:12px;box-shadow:inset 0 0 0 1px var(--outline);display:flex;align-items:center;gap:10px;padding:0 12px;font-size:15px;position:relative;background:var(--surface)}
.fld .ph2{color:var(--onv);opacity:.8}
.fld .mr,.fld .mi,.fld .rx{font-size:20px;color:var(--onv);flex:none}
.fld .x{flex:1;min-width:0;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.fld.foc{box-shadow:inset 0 0 0 2px var(--primary)}
.fld.bad{box-shadow:inset 0 0 0 2px var(--error)}
.fld .lab{position:absolute;left:10px;top:-8px;padding:0 4px;font-size:12px;color:var(--onv);background:inherit;line-height:16px}
.fld.foc .lab{color:var(--primary)}.fld.bad .lab{color:var(--error)}
.fh{font-size:12px;color:var(--onv);padding:4px 16px 0;line-height:1.4}.fh.err{color:var(--error)}
/* ---------- dialogs (AlertDialog: surfaceContainerHigh, radius 24) ---------- */
.dim{position:absolute;inset:0;background:rgba(0,0,0,.4);z-index:20}
.dlg2{position:absolute;z-index:21;left:16px;right:16px;background:var(--sch);border-radius:24px;padding:24px 24px 14px;box-shadow:0 6px 24px rgba(0,0,0,.18)}
.dlg2 h3{font-size:20px;font-weight:600;line-height:1.35;display:flex;align-items:center;gap:12px}
.dlg2 h3 .rx,.dlg2 h3 .mr{font-size:24px;color:var(--primary)}
.dlg2 .c{margin-top:16px;font-size:14px;line-height:1.55;color:rgba(0,0,0,.87)}
.dlg2 .c.v4{color:var(--onv)}
.dlg2 .acts{display:flex;justify-content:flex-end;gap:8px;margin-top:20px;align-items:center;flex-wrap:wrap}
.dlg2 .acts>span{height:40px;display:inline-flex;align-items:center;padding:0 12px;font-size:14px;font-weight:500;color:var(--primary);border-radius:20px}
.dlg2 .acts>span.fb2{background:var(--primary);color:var(--onPrimary);padding:0 20px;font-weight:600}
.dlg2 .acts>span.err{background:var(--error);color:#fff;padding:0 20px;font-weight:600}
.dlg2 .acts>span.big{height:48px;border-radius:24px}
.dlg2 .acts>span.ol{box-shadow:inset 0 0 0 1px var(--outline);border-radius:8px;padding:0 20px;height:48px}
.dlg2 .acts>span.sq{background:var(--primary);color:var(--onPrimary);border-radius:8px;padding:0 20px;height:48px}
.dlg2 .li{display:flex;gap:8px;align-items:flex-start;font-size:13px;line-height:1.5;padding:2px 0}
.dlg2 .li i{width:6px;height:6px;border-radius:3px;background:var(--primary);margin:8px 6px 0 6px;flex:none}
/* ---------- menus (PopupMenu) ---------- */
.pm{position:absolute;z-index:21;background:var(--sc2,#ECEEF4);border-radius:4px;box-shadow:0 4px 14px rgba(0,0,0,.2);padding:8px 0;min-width:112px;color:var(--on)}
.pm.r8{border-radius:8px}
.pm .it{height:48px;display:flex;align-items:center;gap:12px;padding:0 16px 0 12px;font-size:13px;white-space:nowrap}
.pm .it .mi,.pm .it .mr,.pm .it .rx{font-size:24px;color:var(--onv)}
.pm .it.lab12{font-size:12px}
.pm .it.dis{opacity:.38}
.pm .sep{height:1px;background:var(--ov);margin:6px 0}
.menu2{position:absolute;z-index:21;background:var(--schh);border-radius:8px;box-shadow:0 4px 14px rgba(0,0,0,.2);padding:8px 0;min-width:160px;color:var(--on)}
.menu2 .it{height:48px;display:flex;align-items:center;gap:12px;padding:0 16px;font-size:14px;white-space:nowrap}
.menu2 .it .mr,.menu2 .it .mi,.menu2 .it .rx{font-size:20px;color:var(--onv)}
.menu2 .it.danger{color:var(--error)}.menu2 .it.danger .mr,.menu2 .it.danger .rx{color:var(--error)}
.menu2 .sep{height:1px;background:var(--ov);margin:6px 0}
/* ---------- toasts ---------- */
.stoast{position:absolute;left:50%;bottom:90px;transform:translateX(-50%);z-index:30;background:rgba(0,0,0,.75);color:#fff;font-size:14px;padding:8px 14px;border-radius:8px;white-space:nowrap}
.toast2{position:absolute;left:12px;right:12px;bottom:20px;z-index:30;background:#2E3135;color:#EFF0F7;font-size:14px;padding:0 4px 0 16px;min-height:48px;border-radius:4px;display:flex;align-items:center;box-shadow:0 3px 8px rgba(0,0,0,.25);line-height:1.4}
.toast2 span{flex:1;padding:12px 0}.toast2 b{color:#A0CAFD;font-weight:600;padding:0 12px;height:48px;display:flex;align-items:center;white-space:nowrap}
.tip{position:absolute;z-index:30;background:rgba(25,28,32,.9);color:#fff;font-size:12px;padding:6px 8px;border-radius:4px;white-space:nowrap}
/* ---------- composite sheets ---------- */
.multi{display:flex;gap:24px;background:#E9EBF0;padding:0}
.multi .col{display:flex;flex-direction:column;gap:8px}
.multi .cap{min-height:34px;display:flex;align-items:center;justify-content:center;font-size:15px;font-weight:600;color:#191C20;text-align:center;line-height:1.3}
.multi .ph{box-shadow:0 0 0 1px #C3C7CF}
.multi .win{box-shadow:0 0 0 1px #C3C7CF}
.long{position:relative;width:393px;background:var(--surface)}
.syn2{position:absolute;z-index:45;font:500 9px 'Noto Sans SC';padding:2px 5px;border-radius:4px;background:rgba(0,0,0,.5);color:rgba(255,255,255,.85)}
'''

mr = lambda n, s=None, c=None: f'<span class="mr" style="{f"font-size:{s}px;" if s else ""}{f"color:{c};" if c else ""}">{n}</span>'
mi = lambda n, s=None, c=None: f'<span class="mi" style="{f"font-size:{s}px;" if s else ""}{f"color:{c};" if c else ""}">{n}</span>'
rx = lambda code, s=None, c=None: f'<span class="rx" style="{f"font-size:{s}px;" if s else ""}{f"color:{c};" if c else ""}">&#x{code};</span>'


def dn(n, tag=None, at=None):
    if n is None:
        return ''
    return f' data-n="{n}"' + (f' data-tag="{tag}"' if tag else '') + (f' data-at="{at}"' if at else '')


STATUS = ('<div class="status"><span>21:36</span><span class="r"><span class="mi">signal_cellular_alt</span>'
          '<span class="mi">wifi</span><span class="mi">battery_full</span></span></div>')
SB24 = ('<div class="sb24"><span>21:36</span><span style="display:flex;gap:4px"><span class="mi">wifi</span>'
        '<span class="mi">battery_full</span></span></div>')
GESTURE = '<div class="gesture"></div>'


def syn(text='示意图片', pos='left:8px;bottom:10px'):
    return f'<div class="syn2" style="{pos}">{text}</div>'


def page(size, body, cls='ph', style='', css=''):
    return (f'<!doctype html><html><head><meta charset="utf-8"><meta name="mock-size" content="{size}">'
            f'<link rel="stylesheet" href="kit/kit.css"><style>{CSS}{css}</style></head><body>'
            f'<div class="{cls}" style="{style}">{body}</div></body></html>')


# ---------------------------------------------------------------- app bars
def bar(title, actions='', back=True, centred=True, n_back=None, tag='keep', left_w400=False):
    b = f'<div class="b"{dn(n_back, tag)}>{mi("arrow_back")}</div>' if back else '<div style="width:16px"></div>'
    if centred:
        t = f'<div class="ct">{title}</div><div style="flex:1"></div>'
    else:
        t = f'<div class="lt"{" style=\"font-weight:400\"" if left_w400 else " style=\"font-weight:600\""}>{title}</div>'
    return f'<div class="bar">{b}{t}{actions}<div style="width:4px"></div></div>'


def bar_sub(title, sub, actions='', n_back=None, n_title=None, tag_title=None):
    return (f'<div class="bar"><div class="b"{dn(n_back, "keep")}>{mi("arrow_back")}</div>'
            f'<div class="tt"{dn(n_title, tag_title, "tl")}><div class="n">{title}</div><div class="s">{sub}</div></div>'
            f'{actions}<div style="width:4px"></div></div>')


def act(icon, n=None, tag=None, color=None):
    return f'<div class="ib2"{dn(n, tag)}{f" style=\"color:{color}\"" if color else ""}>{icon}</div>'


# ---------------------------------------------------------------- v3 rows
def g3(t):
    return f'<div class="g3">{t}</div>'


def t3(icon, title, sub=None, trailing='chev', one=False, sub_err=False, icon_color=None):
    ic = f'<span class="ic"{f" style=\"color:{icon_color}\"" if icon_color else ""}>{icon}</span>' if icon else ''
    s = f'<div class="s{" err" if sub_err else ""}">{sub}</div>' if sub else ''
    if trailing == 'chev':
        tr = f'<span class="ch">{mr("chevron_right")}</span>'
    elif trailing:
        tr = f'<span class="tr3">{trailing}</span>'
    else:
        tr = ''
    return f'<div class="t3{" one" if one or not sub else ""}">{ic}<div class="x"><div class="t">{title}</div>{s}</div>{tr}</div>'


def cd3(*rows):
    return f'<div class="cd3">{"".join(rows)}</div>'


def l3(inner):
    return f'<div class="l3"><div class="w">{inner}</div></div>'


# ---------------------------------------------------------------- new rows
def ns(t, right='', n=None, tag=None, cls='r'):
    r = f'<span class="{cls}"{dn(n, tag, "tr")}>{right}</span>' if right else ''
    return f'<div class="ns">{t}{r}</div>'


def nr(icon, title, sub=None, trailing='chev', n=None, tag=None, cls='', sub_err=False, icon_mute=False, at='tl'):
    ic = f'<span class="ic{" mute" if icon_mute else ""}">{icon}</span>' if icon else ''
    s = f'<div class="s{" err" if sub_err else ""}">{sub}</div>' if sub else ''
    if trailing == 'chev':
        tr = f'<span class="ch">{mr("chevron_right")}</span>'
    elif trailing:
        tr = trailing
    else:
        tr = ''
    return f'<div class="nr {cls}"{dn(n, tag, at)}>{ic}<div class="x"><div class="t">{title}</div>{s}</div>{tr}</div>'


def ncd(*rows, style=''):
    return f'<div class="ncd" style="{style}">{"".join(rows)}</div>'


def ln(inner):
    return f'<div class="ln"><div class="w">{inner}</div></div>'


def sw(on=False, n=None, tag=None):
    return f'<span class="sw{" on" if on else ""}"{dn(n, tag, "tl")}></span>'


SPIN = '<span class="spin"></span>'


# ---------------------------------------------------------------- frames
def phone(body_html, top=None, extra='', status=True):
    """A 393x852 phone page: status bar, app bar, scrolling body, overlays."""
    return (STATUS if status else '') + (top or '') + f'<div class="body">{body_html}</div>' + extra + GESTURE


def land(body_html, top, extra=''):
    return SB24 + top + f'<div class="body">{body_html}</div>' + extra


def wide(body_html, top, extra=''):
    return top + f'<div class="body">{body_html}</div>' + extra


def composite(phones, h=852, w=393, scale=1.5, css=''):
    """Phones side by side with a caption above each."""
    total = w * len(phones) + 24 * (len(phones) - 1)
    body = ''.join(f'<div class="col"><div class="cap">{c}</div><div class="ph" style="height:{h}px">{p}</div></div>'
                   for p, c in phones)
    return page(f'{total}x{h + 42}@{scale}', body, 'multi', f'width:{total}px;height:{h + 42}px', css=css)


def write(here, out):
    for name, html in out.items():
        open(os.path.join(here, name + '.html'), 'w', encoding='utf-8').write(html)
    print(len(out), 'pages')
