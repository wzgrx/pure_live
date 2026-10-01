"""U.10b login and cookie pages: v3 restored and the new design.
v3: lib/modules/account/widgets/account_cookie_editor.dart (the page every
cookie platform uses), douyu/douyu_cookie_page.dart (+ controller),
huya|douyin|kuaishou|yy|twitch|soop/*_cookie_page.dart (hint and tip only),
bilibili/qr_login_page.dart, bilibili_login_qr_code.dart, web_login_page.dart.
Huya stands for the seven cookie pages; the per-platform differences are a
table in page.json. Cookies, names and ids are obviously fake placeholders;
the QR code is a random pattern, not a real login code.
    python3 docs/ui/compare/U.10b/src/gen.py && python3 tools/ui/mock/render.py docs/ui/compare/U.10b/src/ --annotate"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))

# ---------------------------------------------------------------- shared look
CSS = '''
:root{--hint:rgba(0,0,0,.45);--gt:rgba(54,97,142,.65);--mcbg:#F1F2F8;--gc:#FFDDB8;--ogc:#4A2800;--tag:#E1E2E8}
[data-theme=dark]{--hint:rgba(255,255,255,.38);--gt:rgba(160,202,253,.65);--mcbg:#1C1F23;--gc:#5C3A12;--ogc:#FFDDB8;--tag:#32353A}
.pg{width:393px;background:var(--surface)}
.sbar{height:56px;display:flex;align-items:center;position:relative;background:var(--surface);flex:none}
.sbar .back{width:56px;height:56px;display:grid;place-items:center;flex:none}
.sbar .ttl{position:absolute;left:96px;right:96px;text-align:center;font-size:20px;font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;pointer-events:none}
.sbar .act{margin-left:auto;display:flex;align-items:center;padding-right:4px}
.bd{padding:12px 16px 28px}
.col{max-width:720px;margin:0 auto}
.gt{padding:0 0 8px 8px;font-size:12px;font-weight:700;color:var(--gt);letter-spacing:.5px}
.gt2{padding:4px 0 8px 4px;font-size:13px;font-weight:600;color:var(--primary);display:flex;align-items:center;gap:6px}
.gap{height:20px}
.mc{background:var(--mcbg);border-radius:20px;box-shadow:inset 0 0 0 .5px rgba(0,0,0,.05);overflow:hidden}
.mc2{background:var(--scl);border-radius:16px;overflow:hidden}
.tile{display:flex;align-items:center;gap:12px;padding:8px 16px;min-height:72px}
.tile.one{min-height:56px}
.tile .ic{color:var(--primary);font-size:22px;flex:none;width:22px;text-align:center}
.tile .tx{flex:1;min-width:0}
.tile .t{font-size:15px;font-weight:600;line-height:1.35}
.tile .s{font-size:12px;color:var(--hint);margin-top:2px;line-height:1.35;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.tile .s.wrap{white-space:normal}
.tile .s.on{color:var(--primary);font-weight:500}.tile .s.warn{color:#FF9800}.tile .s.err{color:var(--error)}
.tile .chev{color:rgba(0,0,0,.24);font-size:20px;flex:none}
[data-theme=dark] .tile .chev{color:rgba(255,255,255,.3)}
.n .tile .s{color:var(--onv);white-space:normal}.n .tile .chev{color:var(--outline)}
.dv{height:.5px;margin:0 16px;background:rgba(0,0,0,.08)}
[data-theme=dark] .dv{background:rgba(255,255,255,.08)}
.scrimw{position:relative}
.dlg2{background:var(--sch);border-radius:24px;padding:24px 24px 16px;margin:0 auto;box-shadow:0 8px 28px rgba(0,0,0,.28)}
.dlg2 .dt{font-size:20px;font-weight:600;line-height:1.3;display:flex;align-items:center;gap:12px}
.dlg2 .dc{font-size:13px;line-height:1.5;margin-top:14px;color:var(--on)}
.n .dlg2 .dc{font-size:14px}
.dlg2 .acts{display:flex;justify-content:flex-end;gap:8px;margin-top:20px;align-items:center}
.tb{height:40px;padding:0 12px;border-radius:8px;display:inline-flex;align-items:center;gap:6px;color:var(--primary);font-size:13px;font-weight:500;white-space:nowrap}
.n .tb{font-size:14px}
.tb.err{color:var(--error)}.tb.dim{opacity:.38}
.fb{height:40px;padding:0 20px;border-radius:12px;display:inline-flex;align-items:center;gap:6px;background:var(--primary);color:var(--onPrimary);font-size:14px;font-weight:600;white-space:nowrap}
.fb.err{background:var(--error);color:#fff}.fb.tonal{background:var(--sc);color:var(--osc)}
.ob{height:40px;padding:0 16px;border-radius:20px;display:inline-flex;align-items:center;gap:6px;box-shadow:inset 0 0 0 1px var(--outline);color:var(--primary);font-size:14px;font-weight:500;white-space:nowrap}
.inp{border-radius:12px;box-shadow:inset 0 0 0 1px var(--outline);padding:12px;font-size:14px;color:var(--on);background:transparent;line-height:1.4}
.inp.hint{color:var(--hint)}
.inp.foc{box-shadow:inset 0 0 0 2px var(--primary)}
.lab{font-size:12px;color:var(--primary);margin:0 0 -8px 10px;padding:0 4px;background:var(--sch);display:inline-block;position:relative;z-index:1}
.help{font-size:12px;color:var(--onv);margin:6px 4px 0;line-height:1.45}
.help.err{color:var(--error)}
.prog{height:4px;border-radius:2px;background:rgba(54,97,142,.18);position:relative;overflow:hidden}.prog i{position:absolute;left:0;top:0;bottom:0;width:38%;background:var(--primary);border-radius:2px}
.spin{width:20px;height:20px;border-radius:50%;border:2.5px solid rgba(54,97,142,.2);border-top-color:var(--primary);flex:none;display:inline-block}
.sheetbg{background:#D5D8DE;padding:20px 16px 8px}
[data-theme=dark] .sheetbg{background:#050607}
.cap{font-size:13px;font-weight:600;color:#3B3F46;margin:0 0 10px 4px}
[data-theme=dark] .cap{color:#C3C7CF}
.blk{margin-bottom:22px}
.toast2{background:#2E3135;color:#EFF0F7;font-size:14px;padding:12px 16px;border-radius:8px;box-shadow:0 3px 8px rgba(0,0,0,.25);display:inline-block;max-width:100%;line-height:1.4}
.pm{background:var(--schh);border-radius:8px;box-shadow:0 4px 14px rgba(0,0,0,.2);padding:8px 0;width:220px}
.pm .it{height:48px;display:flex;align-items:center;gap:12px;padding:0 16px;font-size:14px}
.pm .it .rx,.pm .it .mr{font-size:20px;color:var(--onv)}
.radio{width:20px;height:20px;border-radius:10px;border:2px solid var(--onv);flex:none;display:grid;place-items:center}
.radio.on{border-color:var(--primary)}.radio.on::after{content:'';width:10px;height:10px;border-radius:5px;background:var(--primary)}
'''

_col = lambda c: f'color:{c};' if c else ''
mr = lambda n, s=24, c=None: f'<span class="mr" style="{_col(c)}font-size:{s}px">{n}</span>'
mi = lambda n, s=24, c=None: f'<span class="mi" style="{_col(c)}font-size:{s}px">{n}</span>'
rx = lambda code, s=24, c=None: f'<span class="rx" style="{_col(c)}font-size:{s}px">&#x{code};</span>'
RX = dict(cloud='eb9d', refresh='f064', time='f20f', tv='f237', dl2='ec54', fileadd='ecc9', tv2='f235', pladd='f00f', folderopen='ed70',
          globe='edcf', draft='ec5c', cloudwindy='eba1', closec='eb97', warn='eca1', pl2='f00d', folder2='ed52', dlcloud2='ec56',
          del6='ec26', repeat='f074', chkfill='eb80', blankc='eb7d', info='ee59', more='ef77', copy='ecd5', ext='ecaf', check='eb7b',
          clip='eb91', arrowr='ea6e')


def A(n=None, tag=None, at=None):
    return (f' data-n="{n}"' if n else '') + (f' data-tag="{tag}"' if tag else '') + (f' data-at="{at}"' if at else '')


def doc(w, h, scale, body, crop=False, root_cls='ph', root_style=''):
    board = 'body{background:#D5D8DE}[data-theme=dark] body{background:#050607}' if 'sheetbg' in body else ''
    return (f'<!doctype html><html><head><meta charset="utf-8"><meta name="mock-size" content="{w}x{h}@{scale}{" crop" if crop else ""}">'
            f'<link rel="stylesheet" href="kit/kit.css"><style>{CSS}{board}</style></head>'
            f'<body><div class="{root_cls}" style="{root_style}">{body}</div></body></html>')


STATUS = '<div class="status"><span>21:36</span><span class="r"><span class="mi">wifi</span><span class="mi">battery_full</span></span></div>'


def sbar(title, actions='', n_back=None):
    return (f'<div class="sbar"><div class="back"{A(n_back)}>' + mi('arrow_back') + f'</div><div class="ttl">{title}</div>'
            f'<div class="act">{actions}</div></div>')


def gt(text):
    return f'<div class="gt">{text}</div>'


def tile(icon, title, sub=None, trail='chev', sub_cls='', n=None, tag=None, one=False, icon_color=None):
    ic = f'<span class="ic"' + (f' style="color:{icon_color}"' if icon_color else '') + f'>{icon}</span>' if icon else ''
    s = f'<div class="s {sub_cls}">{sub}</div>' if sub else ''
    if trail == 'chev':
        tr = mr('chevron_right', 20).replace('class="mr"', 'class="mr chev"')
    elif trail == 'on':
        tr = '<span class="sw on"></span>'
    elif trail == 'off':
        tr = '<span class="sw"></span>'
    else:
        tr = trail or ''
    return f'<div class="tile{" one" if one or not sub else ""}"{A(n, tag)}>{ic}<div class="tx"><div class="t">{title}</div>{s}</div>{tr}</div>'


def card(*tiles):
    return '<div class="mc">' + '<div class="dv"></div>'.join(tiles) + '</div>'


def dialog(title, content, actions, width=345, icon=None, extra_style=''):
    ic = icon or ''
    acts = f'<div class="acts">{actions}</div>' if actions else '<div style="height:8px"></div>'
    return (f'<div class="dlg2" style="width:{width}px;{extra_style}"><div class="dt">{ic}<span style="flex:1">{title}</span></div>'
            f'{content}{acts}</div>')


SHEET_W = 425


def sheet(blocks):
    """Several pieces on a grey board, each with a caption; phone-wide pieces stay 393."""
    inner = ''.join(f'<div class="blk"><div class="cap">{cap}</div>{html}</div>' for cap, html in blocks)
    return f'<div class="sheetbg" style="width:{SHEET_W}px">{inner}</div>'


def toasts(items):
    """Toasts with an optional note beside them (the note is not part of the toast)."""
    out = ''
    for it in items:
        text, note = (it, '') if isinstance(it, str) else it
        out += (f'<div style="margin-bottom:8px"><span class="toast2">{text}</span>'
                + (f'<div class="cap" style="font-weight:400;margin:4px 0 0 4px">{note}</div>' if note else '') + '</div>')
    return out


def write(name, html):
    open(os.path.join(HERE, name + '.html'), 'w', encoding='utf-8').write(html)



# ---------------------------------------------------------------- task
import random

RX.update(logout='eeda', qr='f03d', chkc='eb81', save='f0b3', eraser='ec9f')
LOGO = lambda p, s=24: f'<img src="../../../packages/live_ui/assets/platforms/{p}.png" style="width:{s}px;height:{s}px;flex:none;border-radius:{s // 5}px">'
CSS += '''
.tipb{border-radius:16px;padding:12px 16px;background:rgba(54,97,142,.05);display:flex;gap:12px;font-size:13px;line-height:1.4;color:rgba(67,71,78,.85)}
.tipb .rx{flex:none;margin-top:1px}
.n .tipb{color:var(--onv)}
.cin{border-radius:12px;background:#fff;box-shadow:inset 0 0 0 1px rgba(0,0,0,.06);padding:14px;font-size:14px;line-height:1.45;min-height:89px;color:var(--on);word-break:break-all}
[data-theme=dark] .cin{background:#0C0E11}
.cin.hint{color:rgba(0,0,0,.3)}.cin.one{min-height:0}
.cin.lbl{color:rgba(0,0,0,.6)}
.cin.foc{box-shadow:inset 0 0 0 1.5px var(--primary)}
.cin.bad{box-shadow:inset 0 0 0 1.5px var(--error)}
.sv{height:48px;border-radius:12px;background:var(--primary);color:var(--onPrimary);display:flex;align-items:center;justify-content:center;gap:8px;font-size:14px;font-weight:600;letter-spacing:.5px}
.sv.dis{background:rgba(25,28,32,.12);color:rgba(25,28,32,.38)}
.obtn{white-space:nowrap;flex:none;height:40px;border-radius:20px;box-shadow:inset 0 0 0 1px var(--outline);color:var(--primary);display:inline-flex;align-items:center;justify-content:center;gap:8px;font-size:14px;font-weight:500;padding:0 18px}
.obtn.err{color:var(--error);box-shadow:inset 0 0 0 1px rgba(186,26,26,.5)}
.chipb{height:36px;border-radius:8px;box-shadow:inset 0 0 0 1px var(--ov);display:inline-flex;align-items:center;gap:6px;padding:0 12px;font-size:14px;color:var(--on)}
.stc{background:var(--scl);border-radius:16px;padding:14px 8px 14px 16px;display:flex;gap:14px;align-items:center}
.stc .t{font-size:15px;font-weight:600}.stc .s{font-size:13px;margin-top:2px;line-height:1.45;color:var(--onv)}
.stc .s.on{color:var(--primary)}.stc .s.err{color:var(--error)}.stc .s.warn{color:var(--warn)}
.lnk{display:inline-flex;align-items:center;gap:6px;color:var(--primary);font-size:13px;min-height:36px}
.note{font-size:12px;color:var(--onv);line-height:1.5;padding:12px 8px 0}
.qrbox{background:#fff;padding:12px;border-radius:12px;display:inline-block;position:relative}
.qrcard{background:var(--mcbg);border-radius:20px;padding:16px;display:inline-block;box-shadow:inset 0 0 0 .5px rgba(0,0,0,.05)}
.qrov{position:absolute;inset:0;border-radius:12px;background:rgba(255,255,255,.9);display:flex;flex-direction:column;align-items:center;justify-content:center;gap:8px;text-align:center;font-size:14px;color:#191C20}
.stm{display:flex;gap:8px;padding:12px 16px;border-radius:16px;font-size:13px;line-height:1.35;color:var(--hint)}
.stm.hi{background:rgba(54,97,142,.1);color:var(--primary);font-weight:600}
.web{flex:1;background:repeating-linear-gradient(135deg,#EEF0F4 0 14px,#E6E9EE 14px 28px);display:flex;align-items:center;justify-content:center;color:#6B7079;font-size:14px;text-align:center;line-height:1.6}
.errbar{position:absolute;left:12px;right:12px;bottom:28px;background:#FFDAD6;color:#410002;border-radius:16px;padding:14px 16px;display:flex;gap:10px;font-size:13px;line-height:1.35;box-shadow:0 2px 6px rgba(0,0,0,.18)}
.sw.dimsw{opacity:.38}
'''


def qr_svg(size, seed=7):
    """A random QR-like pattern (finder squares in three corners); not a real code."""
    rnd = random.Random(seed)
    n = 29
    cell = size / n
    on = [[rnd.random() < 0.48 for _ in range(n)] for _ in range(n)]
    for (r0, c0) in ((0, 0), (0, n - 7), (n - 7, 0)):
        for r in range(-1, 8):
            for c in range(-1, 8):
                rr, cc = r0 + r, c0 + c
                if 0 <= rr < n and 0 <= cc < n:
                    ring = max(abs(r - 3), abs(c - 3))
                    on[rr][cc] = ring in (0, 1, 3) and 0 <= r < 7 and 0 <= c < 7
    rects = ''.join(f'<rect x="{c * cell:.2f}" y="{r * cell:.2f}" width="{cell + .3:.2f}" height="{cell + .3:.2f}"/>'
                    for r in range(n) for c in range(n) if on[r][c])
    return f'<svg width="{size}" height="{size}" viewBox="0 0 {size} {size}" fill="#000">{rects}</svg>'


def qr_block(size, overlay=''):
    return (f'<div class="qrbox">{qr_svg(size - 24)}{overlay}'
            '<span style="position:absolute;right:4px;bottom:2px;font-size:8px;color:#999">示意二维码</span></div>')


HUYA_COOKIE = 'yyuid=12345678; udb_passport=xxxxxxxx; udb_biztoken=xxxxxxxxxxxxxxxx; udb_status=1; …'


# ================================================================ v3
def v3_cookie_body(hint='输入虎牙直播cookie',
                   tip='登陆后,进入直播间,浏览器F12,复制和浏览器一样地址请求头cookie(一般是第一个),复制cookie到下方输入框，点击设置按钮即可设置虎牙直播cookie',
                   value=None, extra='', tipbody=None):
    tipc = tipbody or tip
    box = f'<div class="cin">{value}</div>' if value else f'<div class="cin hint">{hint}</div>'
    return ('<div class="bd">'
            f'<div class="tipb">{rx(RX["info"], 18, "rgba(54,97,142,.8)")}<div>{tipc}</div></div><div class="gap"></div>'
            + gt('Cookie') + f'<div class="mc" style="padding:16px">{box}{extra}<div style="height:16px"></div>'
            f'<div class="sv">{mr("save", 18)}保存</div></div></div>')


def v3_douyu_body():
    p = lambda t: f'<div style="margin-bottom:8px">{t}</div>'
    tip = (p('第 1 步 · 页面 Cookie：随便打开一个斗鱼页面按 F12，在任意请求里复制完整 Cookie（含 dy_auth，约 7 天有效）。')
           + p('第 2 步 · 续期凭据：F12 → Network 面板搜索 passport.douyu.com，打开该请求，从它的 Cookie 里复制 LTP0 和 dy_did（粘到下面的输入框会自动匹配填入）。')
           + '<div style="color:var(--primary);display:flex;align-items:center;gap:6px;margin-bottom:8px">' + mi('open_in_new', 14)
           + '<u>https://passport.douyu.com/</u></div>'
           + '<div>Cookie 有 7 天时效；LTP0 与 dy_did 配好后，失效前会自动刷新，无需再手动粘贴。填完可点「立即续期」当场验证。Cookie 仅保存在本机。</div>')
    extra = ('<div style="height:12px"></div><div class="cin one lbl">LTP0（用于自动续期）</div>'
             '<div style="height:12px"></div><div class="cin one lbl">dy_did（登录所属设备）</div>'
             '<div style="height:12px"></div><div class="obtn" style="width:100%">' + mi('refresh', 18) + '立即续期</div>')
    return v3_cookie_body('粘贴斗鱼完整 Cookie（含 dy_auth）', extra=extra, tipbody=tip)


def v3_qr_body(state='wait'):
    banner = (f'<div class="tipb">{rx(RX["info"], 18, "rgba(54,97,142,.8)")}<div>请使用哔哩哔哩手机客户端扫描二维码登录</div></div>'
              '<div style="height:28px"></div>')
    return '<div class="bd">' + banner + '<div style="text-align:center">' + v3_qr_state(state) + '</div></div>'


def v3_qr_state(state):
    prog = lambda t: (f'<div style="padding:56px 12px;display:flex;flex-direction:column;align-items:center;gap:20px">'
                      f'<span class="spin" style="width:28px;height:28px;border-width:3px"></span><div style="font-size:14px">{t}</div></div>')
    err = lambda t, b: (f'<div style="padding:32px 12px;display:flex;flex-direction:column;align-items:center;gap:12px">'
                        + rx(RX['warn'], 40, 'rgba(0,0,0,.24)') + f'<div style="font-size:14px;color:rgba(0,0,0,.6)">{t}</div>'
                        f'<div class="tb" style="font-weight:600">{rx(RX["refresh"], 18)}{b}</div></div>')
    stm = lambda t, hi: (f'<div class="stm{" hi" if hi else ""}" style="text-align:left">'
                         + rx(RX['chkc'] if hi else RX['qr'], 18) + f'<span>{t}</span></div>')
    if state == 'loading':
        return prog('正在加载二维码…')
    if state == 'verifying':
        return prog('正在核验账号…')
    if state == 'expired':
        return err('二维码已失效', '刷新二维码')
    if state == 'failed':
        return err('二维码加载失败', '重试')
    if state == 'verified':
        return stm('账号核验成功，正在完成登录…', True)
    scanned = state == 'scanned'
    return (f'<div class="qrcard">{qr_block(180)}</div><div style="height:20px"></div>'
            + stm('已扫描，请在手机上确认登录' if scanned else '请使用 哔哩哔哩 手机客户端扫码登录', scanned))


def v3_web(error=True):
    act = '<div class="ib" style="color:var(--primary)">' + rx(RX['qr']) + '</div>'
    body = ('<div style="position:absolute;left:0;right:0;top:92px;bottom:0;display:flex;flex-direction:column">'
            '<div class="web">passport.bilibili.com/login<br>哔哩哔哩的网页登录页（短信、密码）<br>在应用内置浏览器里打开（示意）</div></div>')
    bar = ('<div class="errbar">' + rx(RX['warn'], 20) + '<span>账号核验尚未完成，请继续登录或重试</span></div>') if error else ''
    return STATUS + sbar('哔哩哔哩账号登录', act) + body + bar


def v3_sheet():
    discard = dialog('舍弃 Cookie 修改？', '<div class="dc">编辑后的 Cookie 尚未保存。确定舍弃修改并离开此页面吗？</div>',
                     '<span class="tb">继续编辑</span><span class="tb err">舍弃</span>')
    double = ('<div style="background:#2E3135;color:#EFF0F7;font-size:14px;padding:14px 16px;border-radius:4px;margin-bottom:10px">Cookie 已保存在本机</div>'
              + toasts([('登录态有效（约 7 天，预计 2026-10-08 21:30 到期）；已配置 LTP0，到期前会自动续期', '同一下保存：底部 SnackBar 和中间的提示同时出现（斗鱼）')]))
    empty = ('<div style="background:#2E3135;color:#EFF0F7;font-size:14px;padding:14px 16px;border-radius:4px">Cookie 已保存在本机</div>'
             '<div class="cap" style="font-weight:400;margin:4px 0 0 4px">清空输入框再点保存（等于退出），也是这一句</div>')
    qr = lambda st: f'<div class="pg" style="padding:16px 16px 20px;text-align:center">{v3_qr_state(st)}</div>'
    return sheet([('改了没保存就返回（account_cookie_editor.dart:112）', discard), ('保存后的提示', double), ('', empty),
                  ('扫码：加载中', qr('loading')), ('扫码：已扫描', qr('scanned')), ('扫码：二维码失效（二维码整个换成文字）', qr('expired')),
                  ('扫码：加载失败', qr('failed')), ('扫码：核验中', qr('verifying')), ('扫码：核验成功', qr('verified'))])


# ================================================================ new design
def status_card(logo, name, status, kind='on', action='', n=None):
    return (f'<div class="stc"{A(n)}>{LOGO(logo, 32)}<div style="flex:1;min-width:0"><div class="t">{name}</div>'
            f'<div class="s {kind}">{status}</div></div>{action}</div>')


def new_cookie_body(logo='huya', name='虎牙', status='已保存 · 账号 ID 12345678', kind='on', action='',
                    tip='登录虎牙网页并进入任意直播间，在浏览器开发者工具的网络请求中复制完整 Cookie。',
                    site='打开虎牙网页', value=HUYA_COOKIE, extra='', saved=True, n=False, dirty=True, err=None):
    N = (lambda k: k) if n else (lambda k: None)
    box_cls = 'cin' + (' bad' if err else ' foc' if dirty else '') + ('' if value else ' hint')
    box = f'<div class="{box_cls}"{A(N(3))}>{value or "粘贴 " + name + " Cookie"}</div>'
    errl = f'<div class="help err" style="font-size:12px">{err}</div>' if err else ''
    tools = (f'<div style="display:flex;gap:8px;margin-top:10px"><span class="chipb"{A(N(4), "add")}>{rx(RX["clip"], 18)}粘贴</span>'
             f'<span class="chipb"{A(N(5), "add")}>{rx(RX["eraser"], 18)}清空</span></div>')
    sv = f'<div class="sv{"" if dirty else " dis"}"{A(N(6))}>{mr("save", 18)}保存</div>'
    out = (f'<div style="margin-top:12px;text-align:center"><span class="obtn err"{A(N(7), "add")}>{rx(RX["logout"], 18)}退出登录</span></div>' if saved else '')
    return ('<div class="bd n"><div class="col">'
            + status_card(logo, name, status, kind, action) + '<div style="height:12px"></div>'
            + f'<div class="tipb">{rx(RX["info"], 18, "var(--primary)")}<div>{tip}<div><span class="lnk"{A(N(2), "add")}>{rx(RX["ext"], 16)}{site}</span></div></div></div>'
            + '<div class="gap"></div>' + gt('Cookie')
            + f'<div class="mc" style="padding:16px">{box}{errl}{tools}{extra}<div style="height:16px"></div>{sv}</div>{out}'
            + '<div class="note">Cookie 只加密保存在本机，不会上传；导出备份时只有选择“包含账号”才会写入。</div></div></div>')


def new_douyu_body(n=False):
    N = (lambda k: k) if n else (lambda k: None)
    p = lambda t: f'<div style="margin-bottom:6px">{t}</div>'
    tip = (p('第 1 步 · 页面 Cookie：随便打开一个斗鱼页面按 F12，在任意请求里复制完整 Cookie（含 dy_auth，约 7 天有效）。')
           + p('第 2 步 · 续期凭据：F12 → Network 面板搜索 passport.douyu.com，打开该请求，从它的 Cookie 里复制 LTP0 和 dy_did（粘到 Cookie 框会自动填入下面）。'))
    renew = ('<div class="gap"></div>' + gt('续期')
             + '<div class="mc" style="padding:16px">'
             '<div style="font-size:12px;color:var(--primary);margin:0 0 4px 4px">LTP0（用于自动续期）</div><div class="cin one">xxxxxxxxxxxxxxxxxxxxxxxx</div>'
             '<div style="font-size:12px;color:var(--primary);margin:12px 0 4px 4px">dy_did（登录所属设备）</div><div class="cin one">0000000000000000000000000000000x</div>'
             f'<div style="display:flex;align-items:center;gap:12px;margin-top:14px"><span class="obtn"{A(N(9))}>{mi("refresh", 18)}立即续期</span>'
             '<span style="font-size:12px;color:var(--onv);line-height:1.45">用 LTP0 与 dy_did 马上续期一次，确认它们可用</span></div></div>'
             '<div style="height:12px"></div>'
             + card(tile(None, '登录后强制续期', '打开后，播放中的斗鱼大约每 5 分钟在关键帧处静默换一次地址，避免“每 5 分钟断一次”。只在遇到这种情况时打开。', 'off', n=N(10), tag='add')))
    body = new_cookie_body('douyu', '斗鱼', '登录有效（约 7 天，预计 10-08 21:30 到期）；已配置 LTP0，到期前会自动续期', 'on',
                           tip=tip, site='打开 passport.douyu.com', value='dy_auth=xxxxxxxxxxxxxxxx; acf_uid=12345678; acf_auth=xxxxxxxx; …',
                           extra='', dirty=False)
    # the renewal group goes after the cookie card, before the sign-out button
    i = body.index('<div style="margin-top:12px;text-align:center">')
    return body[:i] + renew + body[i:]


def new_qr_body(state='wait', n=False, wide=False):
    N = (lambda k: k) if n else (lambda k: None)
    size = 220 if wide else 200
    ov = {
        'scanned': '<div class="qrov" style="background:rgba(255,255,255,.88)">' + rx(RX['chkc'], 44, '#36618E') + '<b style="font-size:15px">已扫描</b></div>',
        'expired': '<div class="qrov">' + rx(RX['warn'], 32, '#43474E') + '<div>二维码已失效</div><span class="fb" style="height:36px;padding:0 14px">' + rx(RX['refresh'], 16) + '刷新二维码</span></div>',
        'failed': '<div class="qrov">' + rx(RX['warn'], 32, '#BA1A1A') + '<div>二维码加载失败</div><span class="fb" style="height:36px;padding:0 14px">' + rx(RX['refresh'], 16) + '重试</span></div>',
        'verifying': '<div class="qrov"><span class="spin" style="width:28px;height:28px;border-width:3px"></span><div>正在核验账号…</div></div>',
        'loading': '<div class="qrov" style="background:#F1F2F6"><span class="spin" style="width:28px;height:28px;border-width:3px"></span><div>正在加载二维码…</div></div>',
    }.get(state, '')
    msg = {'scanned': ('已扫描，请在手机上确认登录', True), 'verifying': ('正在核验账号…', False), 'expired': ('二维码已失效，刷新后重新扫', False),
           'failed': ('二维码状态刷新中断，请检查网络后重试', False), 'loading': ('正在加载二维码…', False)}.get(state, ('请使用哔哩哔哩手机客户端扫码登录', False))
    stm = (f'<div class="stm{" hi" if msg[1] else ""}" style="display:inline-flex;color:{"" if msg[1] else "var(--onv)"}">'
           + rx(RX['chkc'] if msg[1] else RX['qr'], 18) + f'<span>{msg[0]}</span></div>')
    alt = ('<div style="margin-top:28px;display:flex;flex-direction:column;align-items:center;gap:4px">'
           '<div style="font-size:12px;color:var(--onv)">扫不了？</div>'
           f'<div style="display:flex;gap:8px;flex-wrap:wrap;justify-content:center"><span class="tb"{A(N(12), "chg")}>{rx(RX["globe"], 18)}网页登录（短信、密码）</span>'
           f'<span class="tb"{A(N(13), "add")}>{rx(RX["clip"], 18)}填写 Cookie</span></div></div>')
    return ('<div class="bd n"><div class="col" style="text-align:center;padding-top:12px">'
            f'<div class="qrcard"{A(N(11))}>{qr_block(size, ov)}</div><div style="height:16px"></div>{stm}{alt}</div></div>')


def new_sheet():
    q = lambda st: f'<div class="pg" style="padding-bottom:4px">{new_qr_body(st).replace("扫不了？", "").split("<div style=\"margin-top:28px")[0]}</div></div></div>'
    sc = lambda *a: f'<div class="pg n" style="padding:12px 16px">{status_card(*a)}</div>'
    recheck = f'<span class="tb">{rx(RX["refresh"], 18)}重新核验</span>'
    err_box = ('<div class="pg n" style="padding:12px 16px"><div class="mc" style="padding:16px"><div class="cin bad">sessdata xxxxxxxx</div>'
               '<div class="help err">这不像 Cookie：应为 name=value; name2=value2 的形式</div>'
               '<div style="height:16px"></div><div class="sv dis">' + mr('save', 18) + '保存</div></div></div>')
    saving = ('<div class="pg n" style="padding:12px 16px"><div class="sv"><span class="spin" style="border-color:rgba(255,255,255,.35);border-top-color:#fff"></span>正在核验并保存…</div></div>')
    discard = dialog('舍弃 Cookie 修改？', '<div class="dc">编辑后的 Cookie 尚未保存。确定舍弃修改并离开此页面吗？</div>',
                     '<span class="tb">继续编辑</span><span class="fb err">舍弃</span>')
    clear = dialog('退出虎牙？', '<div class="dc">将删除本机保存的虎牙 Cookie。确定退出“虎牙”账号吗？</div>',
                   '<span class="tb">取消</span><span class="fb err">退出登录</span>')
    tst = toasts(['Cookie 已保存在本机', '已保存，已登录：示例用户', '这段 Cookie 没有登录或已失效，未保存', '已从粘贴内容填入 LTP0 / dy_did，并保留了原来的登录 Cookie',
                  '续期成功，新 Cookie 已保存并生效（预计 10-15 21:30 到期）'])
    return sheet([('状态卡：未设置', sc('huya', '虎牙', '未设置：粘贴登录后的 Cookie', '')),
                  ('状态卡：问平台核验的（哔哩哔哩、抖音）', sc('douyin', '抖音', '已登录：示例昵称', 'on', recheck)),
                  ('', sc('douyin', '抖音', '正在核验账号…', '')),
                  ('', sc('douyin', '抖音', '登录已失效，请重新登录或更换 Cookie', 'err', recheck)),
                  ('', sc('bilibili', '哔哩哔哩', '已保存，暂时无法核验账号（网络或平台异常）', 'warn', recheck)),
                  ('状态卡：本机判断的（Twitch、虎牙）', sc('twitch', 'Twitch', '已保存，但缺少 auth-token 或 login，聊天以游客身份连接', 'warn')),
                  ('粘的不是 Cookie：框下说明，不能保存', err_box), ('保存中（要核验的平台先问平台）', saving),
                  ('改了没保存就返回（照 v3）', discard), ('页面里的“退出登录”（和列表上的退出同一个确认）', clear),
                  ('提示条：一次只出一条', tst),
                  ('扫码：加载中（二维码位置不跳）', q('loading')), ('扫码：已扫描', q('scanned')), ('扫码：二维码失效', q('expired')),
                  ('扫码：加载失败', q('failed')), ('扫码：核验中', q('verifying'))])


OUT = {
    'v3-cookie': doc(393, 852, 3, STATUS + sbar('设置cookie') + v3_cookie_body() + '<div class="gesture"></div>'),
    'v3-douyu': doc(393, 1600, 2, STATUS + sbar('设置cookie') + v3_douyu_body(), crop=True, root_cls='pg'),
    'v3-qr': doc(393, 852, 3, STATUS + sbar('哔哩哔哩账号登录') + v3_qr_body() + '<div class="gesture"></div>'),
    'v3-web': doc(393, 852, 3, v3_web() + '<div class="gesture"></div>'),
    'v3-sheet': doc(425, 4000, 2, v3_sheet(), crop=True, root_cls=''),
    'v3-wide': doc(1280, 800, 1.5, sbar('设置cookie') + '<div style="max-width:992px;margin:0 auto">' + v3_cookie_body() + '</div>', root_cls='win'),
    'v3-land': doc(852, 393, 2, sbar('设置cookie') + v3_cookie_body(), root_cls='win', root_style='--w:852px;--h:393px'),
    'v3-qr-wide': doc(1280, 800, 1.5, sbar('哔哩哔哩账号登录') + '<div style="max-width:992px;margin:0 auto">' + v3_qr_body() + '</div>', root_cls='win'),
    'v4-cookie': doc(393, 1600, 2, STATUS + sbar('虎牙账号', '', 1) + new_cookie_body(n=True), crop=True, root_cls='pg'),
    'v4-douyu': doc(393, 2400, 2, STATUS + sbar('斗鱼账号') + new_douyu_body(n=True).replace(' data-n="3"', '').replace(' data-n="4"', '').replace(' data-n="5"', '').replace(' data-n="6"', '').replace(' data-n="7"', '').replace(' data-n="8"', ''), crop=True, root_cls='pg'),
    'v4-qr': doc(393, 852, 3, STATUS + sbar('哔哩哔哩账号登录', '', 1) + new_qr_body(n=True) + '<div class="gesture"></div>'),
    'v4-sheet': doc(425, 5000, 2, new_sheet(), crop=True, root_cls=''),
    'v4-wide': doc(1280, 800, 1.5, sbar('虎牙账号') + new_cookie_body(dirty=False), root_cls='win'),
    'v4-land': doc(852, 393, 2, sbar('虎牙账号') + new_cookie_body(dirty=False), root_cls='win', root_style='--w:852px;--h:393px'),
    'v4-qr-wide': doc(1280, 800, 1.5, sbar('哔哩哔哩账号登录') + new_qr_body(wide=True), root_cls='win'),
}
for name, html in OUT.items():
    write(name, html)
print(len(OUT), 'pages')
