"""U.10c cloud account retirement: v3's Firebase screens restored and the one
page that replaces them.
v3: lib/modules/auth/sign_in_page.dart + components/firebase_email_auth.dart
(sign in), mine_page.dart ("我的"), user_manage_page.dart ("管理用户"), and the
entry row in modules/backup/backup_page.dart:86-147. v4 now:
apps/pure_live/lib/features/auth/auth_page.dart. E-mail addresses are fake
placeholders (example.com).
    python3 docs/ui/compare/U.10c/src/gen.py && python3 tools/ui/mock/render.py docs/ui/compare/U.10c/src/ --annotate"""
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
RX.update(acct='ea09', fdl='ecd9', ful='ed15', save3='f0b1', cloudoff='eb9f', mail='eef6', lock='eece', eyeoff='ecb7', github='edca',
          shield='f10c', dlcloud='ec58', ulcloud='f24e', filetext='ed0f', search='f0d1', ustarf='f275', u3f='f255', shieldf='f10b',
          ustar='f276', qrscan='f03f', qr='f03d', logout='eeda')
CSS += '''
.fc{background:var(--mcbg);border-radius:20px;padding:16px;box-shadow:inset 0 0 0 .5px rgba(0,0,0,.05)}
.fin{height:50px;border-radius:12px;background:#fff;box-shadow:inset 0 0 0 1px rgba(0,0,0,.05);display:flex;align-items:center;gap:12px;padding:0 12px;font-size:14px;color:rgba(0,0,0,.3)}
.fbtn{height:48px;border-radius:14px;background:var(--primary);color:#fff;display:flex;align-items:center;justify-content:center;font-size:15px;font-weight:600;letter-spacing:1px}
.gbtn{height:48px;border-radius:14px;box-shadow:inset 0 0 0 1px rgba(0,0,0,.1);display:flex;align-items:center;justify-content:center;gap:8px;font-size:14px;color:var(--primary)}
.orl{display:flex;align-items:center;gap:16px;font-size:12px;color:var(--hint)}.orl i{flex:1;height:1px;background:rgba(0,0,0,.1)}
.ust{border-radius:20px;padding:16px 12px;background:rgba(54,97,142,.04);box-shadow:inset 0 0 0 1px rgba(54,97,142,.06);display:flex}
.ust .it{flex:1;display:flex;flex-direction:column;align-items:center;gap:2px}.ust .b{width:42px;height:42px;border-radius:12px;display:grid;place-items:center;margin-bottom:6px}
.ucard{background:#fff;border-radius:22px;box-shadow:0 0 0 1px rgba(0,0,0,.06),0 4px 12px rgba(0,0,0,.03);padding:16px;margin-bottom:14px}
.ubdg{padding:3px 8px;border-radius:6px;font-size:12px}
.retired{border-radius:20px;padding:16px;background:rgba(54,97,142,.05)}
'''


def v3_backup():
    return ('<div class="bd">' + gt('云端备份')
            + card(tile(rx(RX['acct'], 22), '登录', '点击登录，同步配置数据', sub_cls='wrap'),
                   tile(rx(RX['cloud'], 22), 'WebDav', '备份到WebDav服务器', sub_cls='wrap'),
                   tile(rx(RX['qrscan'], 22), '设备同步', '通过局域网在设备之间同步配置'),
                   tile(rx(RX['qr'], 22), '同步TV数据', '将数据远程同步到TV', sub_cls='wrap'))
            + '<div class="gap"></div>' + gt('本地备份')
            + card(tile(rx(RX['fdl'], 22), '创建备份', '可用于恢复当前数据'), tile(rx(RX['ful'], 22), '恢复备份', '从备份文件中恢复'))
            + '</div>')


def v3_backup_states():
    one = lambda ic, t, s, col=None, sc='': '<div class="pg" style="padding:12px 16px">' + card(tile(ic, t, s, sub_cls='wrap ' + sc, icon_color=col)) + '</div>'
    return [('正在连接', one(rx(RX['refresh'], 22), '正在连接 Firebase...', '正在初始化 Firebase 服务，请稍候...')),
            ('连不上（很多设备一直是这样）', one(rx(RX['acct'], 22), 'Firebase 初始化失败', 'Firebase 服务初始化失败，请检查应用配置和网络后点击重试', 'var(--error)', 'err')),
            ('已登录', one(rx(RX['acct'], 22), '我的', '已登录，点击查看个人中心'))]


def v3_signin():
    return ('<div style="padding:24px">'
            '<div class="fc"><div class="fin">' + rx(RX['mail'], 20) + '请输入邮箱</div><div style="height:16px"></div>'
            '<div class="fin">' + rx(RX['lock'], 20) + '<span style="flex:1">请输入密码</span>' + rx(RX['eyeoff'], 18) + '</div></div>'
            '<div style="height:24px"></div><div class="fbtn">登录</div><div style="height:16px"></div>'
            '<div class="orl"><i></i>或者<i></i></div><div style="height:16px"></div>'
            '<div class="gbtn">' + rx(RX['github'], 20) + '<span>GitHub 登录</span></div>'
            '<div style="height:12px"></div><div class="tb" style="width:100%;justify-content:center">忘记密码？</div>'
            '<div class="tb" style="width:100%;justify-content:center">没有账号？立即注册</div></div>')


def v3_mine():
    return ('<div class="bd">' + gt('我的')
            + card(tile(rx(RX['filetext'], 22), '配置预览', '查看当前保存在云端的配置', sub_cls='wrap'),
                   tile(rx(RX['shield'], 22), '管理用户', '允许用户上传配置文件', sub_cls='wrap'),
                   tile(rx(RX['dlcloud'], 22), '下载用户配置', '使用云端副本覆盖本机设置', sub_cls='wrap'),
                   tile(rx(RX['ulcloud'], 22), '上传配置', '使用本机设置覆盖云端副本', sub_cls='wrap'),
                   tile(rx(RX['logout'], 22), '退出登录', '断开此云端账号与应用的连接', sub_cls='wrap', icon_color='rgba(186,26,26,.8)'))
            + '<div class="note" style="font-size:12px;color:var(--hint);padding:10px 8px">“管理用户”只有管理员看得到</div></div>')


def v3_users():
    stat = lambda ic, col, v, l: (f'<div class="it"><div class="b" style="background:{col}14;color:{col}">{rx(ic, 20)}</div>'
                                  f'<b style="font-size:12px">{v}</b><span style="font-size:12px;color:var(--onv)">{l}</span></div>')
    stats = ('<div class="ust">' + stat(RX['shieldf'], '#36618E', '1', '超级管理员') + stat(RX['ustarf'], '#FFA000', '2', '运营管理员')
             + stat(RX['u3f'], '#73777F', '37', '普通用户') + '</div>')
    search = ('<div style="height:50px;border-radius:16px;background:rgba(225,226,232,.4);display:flex;align-items:center;gap:10px;padding:0 14px;margin:20px 0 12px;font-size:14px;color:var(--hint)">'
              + rx(RX['search'], 18) + '搜索用户邮箱</div>')
    btn = lambda ic, t, col: (f'<div style="flex:1;min-height:48px;border-radius:14px;background:{col}14;color:{col};display:flex;align-items:center;justify-content:center;gap:6px;font-size:14px;font-weight:600">'
                              + rx(ic, 16) + t + '</div>')
    def user(i, email, role, rc, ric, ok):
        return (f'<div class="ucard"><div style="display:flex;gap:14px;align-items:center"><div style="position:relative;width:52px;height:52px;border-radius:16px;background:{rc}1a;color:{rc};display:grid;place-items:center">'
                + rx(ric) + f'<span style="position:absolute;left:-6px;top:-6px;min-width:20px;height:20px;border-radius:10px;background:var(--primary);color:#fff;font:700 10px/20px Geist;text-align:center">{i}</span></div>'
                f'<div><div style="font-size:15px;font-weight:700">{email}</div><div style="display:flex;gap:6px;margin-top:6px"><span class="ubdg" style="background:{rc}1f;color:{rc}">{role}</span>'
                + (f'<span class="ubdg" style="background:#4CAF501f;color:#4CAF50">上传正常</span>' if ok else '<span class="ubdg" style="background:#BA1A1A1f;color:#BA1A1A">上传禁用</span>')
                + '</div></div></div><div style="display:flex;gap:10px;margin-top:16px">'
                + btn(RX['ustar'], '设为运营', '#009688') + btn('ec26', '删除账号', '#BA1A1A') + '</div>'
                '<div style="display:flex;gap:10px;margin-top:10px">' + btn('eb97', '禁用上传', '#BA1A1A') + '</div></div>')
    return ('<div style="padding:12px 16px">' + stats + search + user(1, 'user01@example.com', '普通用户', '#36618E', RX['user'] if 'user' in RX else 'f264', True)
            + user(2, 'user02@example.com', '普通用户', '#36618E', 'f264', True) + '</div>')


def v3_sheet():
    dl = dialog('覆盖本机设置？', '<div class="dc">云端副本将覆盖此设备上的设置，是否继续？</div>', '<span class="tb">取消</span><span class="fb">确认</span>')
    so = dialog('退出登录？', '<div class="dc">此云端账号将与应用断开连接，是否继续？</div>', '<span class="tb">取消</span><span class="fb">确认</span>')
    op = dialog('操作确认', '<div class="dc">确定对 user01@example.com 执行【设为运营】操作吗？</div>', '<span class="tb">取消</span><span class="tb">确认</span>')
    tst = toasts(['云端操作未完成，请重试。', 'Email 登录成功 (user01@example.com)', '请打开邮箱重置密码'])
    return sheet(v3_backup_states() + [('“我的”：下载用户配置', dl), ('“我的”：退出登录', so), ('“管理用户”：每个操作', op), ('提示条', tst)])


# ---------------- new
def new_body(n=False):
    N = (lambda k: k) if n else (lambda k: None)
    retired = ('<div class="retired"><div style="display:flex;align-items:center;gap:12px">' + rx(RX['cloudoff'], 24, 'var(--primary)')
               + '<b style="font-size:16px">云端账号已停用</b></div>'
               '<div style="font-size:14px;line-height:1.55;margin-top:12px">旧版的云端账号基于 Firebase（谷歌服务），很多设备连不上，新版不再提供。关注、历史和设置都保存在本机，可以用下面的方式在设备之间同步或备份。</div>'
               '<div style="font-size:13px;line-height:1.55;margin-top:8px;color:var(--onv)">云端已有的配置不会自动导入。需要的话，先在旧版的“我的”里把配置下载到本机，再导出备份文件，然后在新版的“备份与恢复”里导入。</div></div>')
    return ('<div class="bd n"><div class="col">' + retired + '<div class="gap"></div>' + gt('同步与备份')
            + card(tile(rx(RX['cloud'], 22), 'WebDav', '备份到自己的 WebDav 网盘，在其他设备上恢复', n=N(2)),
                   tile(rx(RX['qrscan'], 22), '设备同步', '通过局域网在设备之间同步配置', n=N(3)),
                   tile(rx(RX['save3'], 22), '备份与恢复', '导出或导入备份文件', n=N(4)))
            + '<div class="gap"></div>' + gt('平台账号')
            + card(tile(rx(RX['access'] if 'access' in RX else 'f5cd', 22), '平台账号', '哔哩哔哩、斗鱼、虎牙等平台的登录，和云端账号无关', n=N(5)))
            + '</div></div>')


def new_backup_entry():
    return ('<div class="pg n">' + sbar('备份与恢复') + '<div class="bd n" style="padding-bottom:16px">' + gt('云端备份')
            + card(tile(rx(RX['cloudoff'], 22, 'var(--onv)'), '云端账号（已停用）', '改用 WebDav 或设备同步；点这里看怎么迁移旧的云端配置'),
                   tile(rx(RX['cloud'], 22), 'WebDav', '备份到WebDav服务器'),
                   tile(rx(RX['qrscan'], 22), '设备同步', '通过局域网在设备之间同步配置'))
            + '</div></div>')


OUT = {
    'v3-backup': doc(393, 852, 3, STATUS + sbar('备份与恢复') + v3_backup() + '<div class="gesture"></div>'),
    'v3-signin': doc(393, 852, 3, STATUS + sbar('登录') + v3_signin() + '<div class="gesture"></div>'),
    'v3-mine': doc(393, 852, 3, STATUS + sbar('我的') + v3_mine() + '<div class="gesture"></div>'),
    'v3-users': doc(393, 852, 3, STATUS + sbar('管理用户') + v3_users() + '<div class="gesture"></div>'),
    'v3-sheet': doc(425, 3000, 2, v3_sheet(), crop=True, root_cls=''),
    'v4-auth': doc(393, 852, 3, STATUS + sbar('云端账号', '', 1) + new_body(True) + '<div class="gesture"></div>'),
    'v4-backup-entry': doc(425, 1200, 2, sheet([('备份页“云端备份”一组（待选 X1 选 A 时；页面本身在 U.11a）', new_backup_entry())]), crop=True, root_cls=''),
    'v4-wide': doc(1280, 800, 1.5, sbar('云端账号') + new_body(), root_cls='win'),
    'v4-land': doc(852, 393, 2, sbar('云端账号') + new_body(), root_cls='win', root_style='--w:852px;--h:393px'),
}
for name, html in OUT.items():
    write(name, html)
print(len(OUT), 'pages')
