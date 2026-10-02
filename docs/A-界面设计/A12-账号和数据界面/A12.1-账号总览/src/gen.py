"""U.10a account overview mockups: v3 restored and the new design.
v3: lib/modules/account/account_page.dart (list :9-186, row :188-242, sign-out
dialog :244-287), account_controller.dart, routes/app_navigation.dart:96-108
(Bilibili login method), plugins/utils.dart:447-505 (option dialog). Account
names and ids in the pictures are made-up placeholders.
    python3 docs/ui/compare/U.10a/src/gen.py && python3 tools/ui/mock/render.py docs/ui/compare/U.10a/src/ --annotate"""
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
RX.update(logout='eeda', access='f5cd')
LOGO = lambda p, s=24: f'<img src="../../../packages/live_ui/assets/platforms/{p}.png" style="width:{s}px;height:{s}px;flex:none;border-radius:{s // 5}px">'
CSS += '''
.acc{display:flex;align-items:center;gap:16px;padding:6px 4px 6px 16px;min-height:72px}
.acc .tx{flex:1;min-width:0}.acc .t{font-size:15px;font-weight:600;line-height:1.35}
.acc .s{font-size:12px;margin-top:2px;line-height:1.4;color:var(--hint);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.acc .s.on{color:var(--primary);font-weight:500}
.n .acc .s{white-space:normal;color:var(--onv)}.n .acc .s.on{color:var(--primary)}.n .acc .s.warn{color:var(--warn)}.n .acc .s.err{color:var(--error)}
.acc .lo{width:48px;height:48px;display:grid;place-items:center;flex:none;color:rgba(186,26,26,.8)}
.acc .cv{width:48px;height:48px;display:grid;place-items:center;flex:none;color:rgba(0,0,0,.24)}
.n .acc .cv{color:var(--outline)}
.intro{font-size:13px;color:var(--onv);line-height:1.55;padding:0 8px 16px}
.banner{border-radius:16px;padding:12px 16px;display:flex;gap:12px;background:var(--warnbg);margin-bottom:16px;font-size:13px;line-height:1.5}
'''


def acc(logo, name, status, kind='', trail='chev', n=None, tag=None, n_lo=None):
    tr = (f'<span class="lo"{A(n_lo)}>' + rx(RX['logout'], 18) + '</span>') if trail == 'out' else ('<span class="cv">' + mr('chevron_right', 20) + '</span>')
    return (f'<div class="acc"{A(n, tag)}>{LOGO(logo)}<div class="tx"><div class="t">{name}</div><div class="s {kind}">{status}</div></div>{tr}</div>')


# ---------------- v3
V3_ROWS = [('bilibili', '哔哩哔哩', '示例用户', 'on', 'out'), ('huya', '虎牙', '已登录', 'on', 'out'), ('yy', 'YY', '设置cookie', '', 'chev'),
           ('douyin', '抖音', '示例昵称', 'on', 'out'), ('kuaishou', '快手', '设置cookie', '', 'chev'), ('twitch', 'Twitch', '设置cookie', '', 'chev'),
           ('soop', 'Soop', '设置cookie', '', 'chev'), ('douyu', '斗鱼', '登录态已过期，播放时自动续期', 'on', 'out')]


def v3_body():
    return '<div class="bd">' + gt('三方认证') + card(*[acc(*r) for r in V3_ROWS]) + '</div>'


def v3_dialogs():
    logout = dialog('退出登录', '<div class="dc">确定退出“哔哩哔哩”账号吗？</div>',
                    '<span class="tb">取消</span><span class="fb err">退出登录</span>')
    method = dialog('请选择登陆方式', '<div style="margin:8px -16px 0">' + ''.join(
        f'<div style="min-height:48px;display:flex;align-items:center;gap:16px;padding:4px 16px"><span class="radio"></span><span style="font-size:14px">{t}</span></div>'
        for t in ('短信登陆', '二维码登陆')) + '</div>', '')
    return sheet([('点已登录的平台（或行尾按钮）：退出确认（account_page.dart:244）', logout),
                  ('哔哩哔哩没登录时点它（只在手机上；app_navigation.dart:96）', method)])


# ---------------- new
def new_rows(n=False, unreadable=False):
    N = (lambda k: k) if n else (lambda k: None)
    bad = '无法在本机读取已保存的 Cookie，请重新填写'
    dom = [acc('bilibili', '哔哩哔哩', '已登录：示例用户', 'on', 'out', N(2), 'chg', N(3)),
           acc('douyu', '斗鱼', bad if unreadable else '登录有效，到期前自动续期', 'err' if unreadable else 'on', 'out'),
           acc('huya', '虎牙', bad if unreadable else '已保存 · 账号 ID 12345678', 'err' if unreadable else 'on', 'out'),
           acc('douyin', '抖音', '登录已失效，请重新登录或更换 Cookie', 'err', 'out'),
           acc('kuaishou', '快手', '未设置', '', 'chev', N(4)),
           acc('yy', 'YY', '未设置'),
           acc('cc', '网易 CC', '未设置', '', 'chev', N(5), 'add')]
    sea = [acc('twitch', 'Twitch', '已保存 · 聊天身份 example_user', 'on', 'out'), acc('soop', 'SOOP', '未设置')]
    return dom, sea


def new_body(n=False, banner=False):
    dom, sea = new_rows(n, unreadable=banner)
    bn = ('<div class="banner">' + rx(RX['info'], 20, 'var(--warn)') + '<div>斗鱼、虎牙的 Cookie 无法在本机读取（换了设备或重装后会这样），请重新填写。</div></div>') if banner else ''
    intro = '<div class="intro">部分平台登录后可以看更高画质、用账号身份连接弹幕。Cookie 只加密保存在本机；点平台可以查看、填写或核验。</div>'
    if banner:  # only the part that changes
        return f'<div class="bd n"><div class="col">{bn}{gt("国内平台")}{card(*dom[:4])}</div></div>'
    return (f'<div class="bd n"><div class="col">{intro}'
            + gt('国内平台') + card(*dom) + '<div class="gap"></div>' + gt('海外平台') + card(*sea) + '</div></div>')


def new_states():
    rows = [('bilibili', '哔哩哔哩', '正在核验账号…', '', 'out'), ('bilibili', '哔哩哔哩', '已保存，暂时无法核验账号（网络或平台异常）', 'warn', 'out'),
            ('douyu', '斗鱼', '登录有效，预计 10-08 21:30 到期', 'on', 'out'), ('douyu', '斗鱼', '登录态已失效，点按重新粘贴 Cookie', 'err', 'out'),
            ('huya', '虎牙', '已保存，但没有找到账号 ID（yyuid），可能不是登录后的 Cookie', 'warn', 'out'),
            ('twitch', 'Twitch', '已保存，但缺少 auth-token 或 login，聊天以游客身份连接', 'warn', 'out'),
            ('cc', '网易 CC', '已保存，暂未用于请求（登录后加入弹幕待验证）', 'warn', 'out'),
            ('yy', 'YY', '无法在本机读取已保存的 Cookie，请重新填写', 'err', 'out'), ('soop', 'SOOP', '已保存', 'on', 'out')]
    status = '<div class="pg n" style="padding:12px 16px">' + card(*[acc(*r) for r in rows]) + '</div>'
    banner = '<div class="pg n">' + new_bar() + new_body(banner=True).replace('<div class="gap"></div>', '<div style="display:none">', 0) + '</div>'
    logout = dialog('退出登录', '<div class="dc">确定退出“哔哩哔哩”账号吗？</div>',
                    '<span class="tb">取消</span><span class="fb err">退出登录</span>')
    method = dialog('选择登录方式', '<div style="margin:8px -16px 0">' + ''.join(
        f'<div style="min-height:56px;display:flex;align-items:center;gap:16px;padding:4px 16px">{rx(ic, 22, "var(--primary)")}<div><div style="font-size:15px;font-weight:500">{t}</div><div style="font-size:13px;color:var(--onv)">{s}</div></div></div>'
        for ic, t, s in (('f03d', '扫码登录', '用哔哩哔哩手机客户端扫一扫'), ('edcf', '网页登录', '短信验证码或密码'))) + '</div>', '')
    tst = toasts(['已退出哔哩哔哩', ('哔哩哔哩登录已失效，请重新登录', '启动后核验发现失效时（照 v3），自动退出')])
    return sheet([('状态一览（每种只在需要时出现）', status), ('本机读不出已存的 Cookie（换设备、重装）', banner),
                  ('退出确认（文字照 v3，正文 14 号）', logout), ('待选 K2 选 B 时：哔哩哔哩的登录方式（改了错字，给出说明）', method),
                  ('提示条', tst)])


def new_bar(n=False):
    return sbar('平台账号', '', 1 if n else None)


OUT = {
    'v3-accounts': doc(393, 852, 3, STATUS + sbar('三方认证') + v3_body() + '<div class="gesture"></div>'),
    'v3-dialogs': doc(425, 1400, 2, v3_dialogs(), crop=True, root_cls=''),
    'v3-wide': doc(1280, 800, 1.5, sbar('三方认证') + '<div style="max-width:992px;margin:0 auto">' + v3_body() + '</div>', root_cls='win'),
    'v3-land': doc(852, 393, 2, sbar('三方认证') + v3_body(), root_cls='win', root_style='--w:852px;--h:393px'),
    'v4-accounts': doc(393, 1400, 2, STATUS + new_bar(True) + new_body(True), crop=True, root_cls='pg'),
    'v4-states': doc(425, 3000, 2, new_states(), crop=True, root_cls=''),
    'v4-wide': doc(1280, 800, 1.5, new_bar() + new_body(), root_cls='win'),
    'v4-land': doc(852, 393, 2, new_bar() + new_body(), root_cls='win', root_style='--w:852px;--h:393px'),
}
for name, html in OUT.items():
    write(name, html)
print(len(OUT), 'pages')
