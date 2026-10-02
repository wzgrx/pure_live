"""U.11b WebDAV mockups: v3 restored and the new design.

v3 (tag v3.2.11): lib/modules/web_dav/web_dav_page.dart (app bar and menu
:248-296, breadcrumbs :310-386, states :388-470, file rows :472-550, drawer
:116-176, dialogs :178-246 and :579-759), web_dav_controller.dart (feedback
:29-44, load :197-225), web_dav_help.dart (help page).
Server address, user name and server names are placeholders; the help page's
real service address is replaced too.
    python3 docs/ui/compare/U.11b/src/gen.py && python3 tools/ui/mock/render.py docs/ui/compare/U.11b/src/ --annotate"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from skit import *  # noqa: E402,F401,F403
from skit import composite as _composite  # noqa: E402

CSS2 = '''
.crumb{height:50px;display:flex;align-items:center;padding-left:8px;font-size:13px;font-weight:500;white-space:nowrap;overflow:hidden;flex:none;background:var(--surface)}
.crumb .c{height:48px;display:flex;align-items:center;padding:0 8px}
.crumb .c.on{color:var(--primary)}
.crumb .mi{font-size:24px;margin:0 4px}
.fr3{display:flex;align-items:center;gap:16px;min-height:88px;padding:8px 8px 8px 16px}
.fr3 .ic{font-size:28px;color:var(--primary);flex:none}
.fr3 .x{flex:1;min-width:0}
.fr3 .t{font-size:15px;font-weight:500;line-height:1.4;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden;word-break:break-all}
.fr3 .s{font-size:13px;color:var(--onv);margin-top:2px}
.fr3 .mv{width:48px;height:48px;display:grid;place-items:center;flex:none}
.fr4{display:flex;align-items:center;gap:16px;min-height:72px;padding:8px 4px 8px 16px}
.fr4 .ic{font-size:28px;color:var(--primary);flex:none}
.fr4 .x{flex:1;min-width:0}
.fr4 .t{font-size:15px;line-height:1.4;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden;word-break:break-all}
.fr4 .s{font-size:12px;color:var(--onv);margin-top:2px;font-feature-settings:'tnum'}
.fr4 .mv{width:48px;height:48px;display:grid;place-items:center;flex:none;color:var(--onv)}
.fr4.dis{opacity:.38}
.fab{position:absolute;right:16px;bottom:24px;z-index:6;width:56px;height:56px;border-radius:16px;background:var(--pc);color:var(--opc);display:grid;place-items:center;box-shadow:0 3px 8px rgba(0,0,0,.2)}
.fab .mi,.fab .mr{font-size:24px}
.efab{position:absolute;right:16px;bottom:24px;z-index:6;height:56px;border-radius:16px;background:var(--pc);color:var(--opc);display:flex;align-items:center;gap:10px;padding:0 20px 0 16px;font-size:14px;font-weight:600;box-shadow:0 3px 8px rgba(0,0,0,.2)}
.efab .mi,.efab .mr{font-size:24px}
.drawer{position:absolute;top:0;right:0;bottom:0;width:304px;z-index:21;background:var(--scc);box-shadow:-4px 0 16px rgba(0,0,0,.2);display:flex;flex-direction:column}
.drawer.r16{border-radius:16px 0 0 16px;width:320px}
.dr3{padding:12px 16px}
.dr3 .n{font-size:15px;font-weight:500}
.dr3 .r{display:flex;justify-content:flex-end}
.dr3 .r span{width:48px;height:48px;display:grid;place-items:center}
.dr3.sel{background:rgba(54,97,142,.06);color:var(--primary)}
.dr3.sel .r{color:var(--onv)}
.dadd{display:flex;align-items:center;gap:16px;height:56px;padding:0 16px;font-size:15px}
.dh{padding:20px 20px 8px;font-size:16px;font-weight:700}
.dr4{display:flex;align-items:center;gap:12px;padding:8px 4px 8px 16px;min-height:64px;margin:0 8px;border-radius:12px}
.dr4.sel{background:var(--sc);color:var(--osc)}
.dr4 .ic{font-size:22px;flex:none;color:var(--onv)}.dr4.sel .ic{color:var(--osc)}
.dr4 .x{flex:1;min-width:0}.dr4 .t{font-size:15px;font-weight:600}.dr4 .s{font-size:12px;color:var(--onv);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.dr4 .b2{width:44px;height:48px;display:grid;place-items:center;color:var(--onv);flex:none}
.dr4 .b2.e{color:var(--error)}
.statusrow{padding:8px 16px 12px;text-align:center;font-size:13px;flex:none}
.statusrow .lp{height:4px;background:color-mix(in srgb,var(--primary) 18%,transparent);margin-top:6px;position:relative}.statusrow .lp i{position:absolute;left:20%;width:35%;top:0;bottom:0;background:var(--primary)}
.snack{position:absolute;left:12px;right:12px;bottom:20px;z-index:30;border-radius:4px;padding:14px 16px;font-size:14px;box-shadow:0 3px 8px rgba(0,0,0,.2)}
.snack.v3{background:var(--schh);color:var(--onv)}
.snack.v3e{background:#FFDAD6;color:#410002}
.st3{display:flex;flex-direction:column;align-items:center;justify-content:center;text-align:center;height:100%;padding:24px 24px 96px;font-size:14px}
.st3 .tb{margin-top:4px}
.v3f{height:52px;border-radius:4px;box-shadow:inset 0 0 0 1px var(--outline);background:var(--scl);display:flex;align-items:center;gap:12px;padding:0 12px;font-size:15px;color:var(--onv);margin-bottom:16px}
.v3f .rx{font-size:20px}
.v3f.dis{opacity:.5}
/* help page */
.hp{padding:12px 16px 40px}
.hp>.w{max-width:960px;margin:0 auto}
.hs{padding:0 0 10px 4px;font-size:16px;font-weight:600;line-height:1.2}
.hc{padding:16px;border-radius:20px;background:#F5F6FC;box-shadow:inset 0 0 0 .5px rgba(0,0,0,.08);font-size:13.5px;line-height:1.6;white-space:pre-line}
.hc.n4{background:var(--scl);border-radius:16px;box-shadow:none;font-size:14px;color:var(--on)}
.prm{display:flex;align-items:center;gap:16px;padding:12px 8px 12px 16px;min-height:64px}
.prm .ic{color:var(--primary);font-size:22px;flex:none}
.prm .x{flex:1}.prm .t{font-size:14px;font-weight:600}.prm .s{font-size:12px;margin-top:2px}
.prm .a{color:var(--primary);text-decoration:underline;font-size:13px}
.prm .cp{width:48px;height:48px;display:grid;place-items:center;color:rgba(0,0,0,.6)}
.shot{margin-top:14px;height:200px;border-radius:8px;background:repeating-linear-gradient(135deg,#E6E8EE 0 12px,#ECEEF4 12px 24px);display:grid;place-items:center;color:var(--onv);font-size:12px}
.hdiv{height:.6px;background:var(--ov);margin:0 16px}
'''


def composite(phones, **kw):
    return _composite(phones, css=CSS2, **kw)


def p(html):
    return page('393x852@3', html, css=CSS2)


RXC = dict(server='f0e0', shield='ed09', delete='ec2a', question='f045', editbox='ec82', addbox='ea0f', bookmark='eae5',
           user='f256', lock='eed0', globe='edcf', copy='ecd5', links='eeb8', mail='eef6', eye='ecb5', eyeoff='ecb7',
           heart='ee11', up='ed15', cloudoff='eb9f', heart_l='ee0f')

ADDR = 'https://dav.example.com/dav/'
SERVERS = [('我的网盘', ADDR), ('家里的 NAS', 'https://nas.example.lan:5006/webdav/')]
ENTRIES = [  # (dir, name, v3 time, v4 info, backup kind)
    (True, '电视', '2026-09-30 20:11:05.000', '2026-09-30 20:11', None),
    (False, 'purelive_2026-10-01T21_30_12_3f2b9c1e-7d4a-4b8e-9a51-0c6e2f8d1b7a.txt', '2026-10-01 21:30:12.000', '2026-10-01 21:30 · 48.2 KB', 'all'),
    (False, 'purelive_favorites_2026-09-28T09_12_40_a81c0d2e-5b6f-4c3a-8e7d-91f2b3c4d5e6.txt', '2026-09-28 09:12:40.000', '2026-09-28 09:12 · 6.1 KB', 'fav'),
    (False, 'purelive_2026-09-15T22_05_03_c47e8a90-1b2d-4e3f-a5b6-7c8d9e0f1a2b.txt', '2026-09-15 22:05:03.000', '2026-09-15 22:05 · 45.7 KB', 'all'),
    (False, '说明.txt', '2026-08-02 10:00:00.000', '2026-08-02 10:00 · 1.2 KB', None),
]


# ---------------------------------------------------------------- v3
def v3_bar():
    return bar('<span style="font-weight:400">WebDav</span>', act(mi('more_vert', 24, 'var(--opc)')))


def v3_crumb(parts=('PureLive',)):
    out = '<div class="crumb"><span style="width:40px;flex:none"></span><span class="c' + ('' if parts else ' on') + '">我的文件</span>'
    for i, part in enumerate(parts):
        out += mi('navigate_next') + f'<span class="c{" on" if i == len(parts) - 1 else ""}">{part}</span>'
    return out + '</div>'


def v3_rows(entries=ENTRIES):
    out = ''
    for d, name, t, _, kind in entries:
        icon = 'folder_open' if d else ('text_snippet' if name.endswith('.txt') else 'insert_drive_file')
        out += (f'<div class="fr3">{mi("folder" if d else "text_snippet", 28).replace("class=\"mi\"", "class=\"mi ic\"")}'
                f'<div class="x"><div class="t">{name}</div><div class="s">{t}</div></div><span class="mv">{mi("more_vert")}</span></div>')
    return out


def v3_page(body, extra='', crumb=True, fab=True):
    f = f'<div class="fab">{mi("cloud_upload")}</div>' if fab else ''
    return STATUS + v3_bar() + (v3_crumb() if crumb else '') + f'<div class="body">{body}</div>' + f + extra + GESTURE


def v3_menu():
    it = lambda ic, t: f'<div class="it">{ic}<span style="font-size:12px">{t}</span></div>'
    return ('<div class="pm" style="top:92px;right:8px;width:190px">' + it(mi('refresh'), '刷新') + it(mi('menu'), '打开配置列表')
            + it(rx(RXC['question']), '使用帮助教程') + '<div class="it" style="font-size:13px">仅上传关注列表</div></div>')


def v3_drawer():
    rows = ''
    for i, (name, _) in enumerate(SERVERS):
        rows += (f'<div class="dr3{" sel" if i == 0 else ""}"><div class="n">{name}</div><div class="r"><span>{mi("edit")}</span>'
                 f'<span>{mi("delete")}</span></div></div>')
    return ('<div class="dim" style="background:rgba(0,0,0,.54)"></div><div class="drawer"><div style="height:56px"></div>' + rows
            + f'<div class="dadd">{mi("add")}<span>添加新配置</span></div></div>')


def v3_file_menu(top):
    return (f'<div class="pm" style="top:{top}px;right:16px;width:168px"><div class="it">恢复全部设置</div><div class="it">仅恢复关注列表</div>'
            '<div class="it">删除</div></div>')


def v3_config_dialog(top=150, edit=False):
    f = lambda ic, lab, val='', dis=False: f'<div class="v3f{" dis" if dis else ""}">{rx(ic)}<span>{val or lab}</span></div>'
    title = '编辑配置: 我的网盘' if edit else '添加新配置'
    return ('<div class="dim"></div><div class="dlg2" style="top:' + str(top) + 'px;border-radius:16px;padding:24px 24px 16px">'
            f'<h3 style="font-weight:700">{rx(RXC["editbox" if edit else "addbox"])}{title}</h3><div style="margin-top:20px">'
            + f(RXC['bookmark'], '配置名称', '我的网盘' if edit else '', edit) + f(RXC['globe'], '地址', ADDR if edit else '')
            + f(RXC['user'], '用户名', 'user@example.com' if edit else '') + f(RXC['lock'], '密码', '••••••••••' if edit else '')
            + '</div><div class="acts" style="margin-top:8px"><span class="ol">取消</span><span class="sq">' + ('更新' if edit else '添加') + '</span></div></div>')


def v3_confirm(title, msg, act_, danger=True, top=290):
    return ('<div class="dim"></div><div class="dlg2" style="top:' + str(top) + 'px"><h3>' + title + '</h3><div class="c">' + msg + '</div>'
            '<div class="acts"><span class="big">取消</span><span class="' + ('err' if danger else 'fb2') + ' big">' + act_ + '</span></div></div>')


def v3_help(n=False, full=False):
    sec = lambda t: f'<div class="hs">{t}</div>'
    card = lambda t: f'<div class="hc">{t}</div>'
    params = ('<div class="hc" style="padding:0;white-space:normal">'
              f'<div class="prm"><span class="ic">{rx(RXC["links"])}</span><div class="x"><div class="t">WebDAV 服务器地址</div><div class="s a">{ADDR}</div></div><span class="cp">{rx(RXC["copy"], 18)}</span></div><div class="hdiv"></div>'
              f'<div class="prm"><span class="ic">{rx(RXC["mail"])}</span><div class="x"><div class="t">用户名</div><div class="s">坚果云账号邮箱</div></div></div><div class="hdiv"></div>'
              f'<div class="prm"><span class="ic">{rx(RXC["lock"])}</span><div class="x"><div class="t">WebDAV 应用密码</div><div class="s">使用独立的应用密码，不是账号登录密码</div></div></div></div>')
    step = lambda t, i: f'<div class="hc">{t}<div class="shot">坚果云网页截图 {i}（示意）</div></div>'
    body = (sec('开始前说明') + card('坚果云支持通过 WebDAV 备份和管理文件。本页以坚果云个人账号为示例。\n免费版当前每月上传流量 1 GB、下载流量 3 GB，空间随上传的数据增长。套餐规则可能调整，依赖额度前请查看官方页面。')
            + '<div style="height:22px"></div>' + sec('连接参数') + params + '<div style="height:24px"></div>'
            + sec('注册坚果云账号') + step('1. 在浏览器打开坚果云官网。\n2. 选择注册并使用邮箱创建账号。\n3. 按页面提示完成账号验证。', 1))
    if full:
        body += ('<div style="height:16px"></div>' + step('在注册页面完成要求的账号信息。', 2) + '<div style="height:24px"></div>'
                 + sec('在网页端登录') + step('1. 应用密码需要在坚果云网页端管理。\n2. 使用已注册账号和账号密码登录。', 3) + '<div style="height:24px"></div>'
                 + sec('生成独立应用密码') + step('1. 打开账号菜单并选择“账户信息”。', 4) + '<div style="height:16px"></div>' + step('2. 打开“安全选项”。', 5)
                 + '<div style="height:16px"></div>' + step('3. 找到“第三方应用管理”。\n4. 添加应用密码，使用 Pure Live 等易识别名称，然后生成密码。', 6)
                 + '<div style="height:16px"></div>' + step('5. 立即复制并妥善保存生成的密码；密码丢失或被撤销后重新创建。', 7) + '<div style="height:24px"></div>'
                 + sec('在 Pure Live 中填写配置') + card(f'名称：用于识别此配置的任意名称\n地址：{ADDR} 或已存在的子目录地址\n用户名：坚果云账号邮箱\n密码：独立的应用密码\n\n使用其他 WebDAV 服务时，请填写对应服务商的目录地址和凭据；Pure Live 会分别保存每项配置。')
                 + '<div style="height:24px"></div>' + sec('常见问题') + '<div class="hc" style="white-space:normal">'
                 + ''.join(f'<div style="padding:7px 0"><div style="font-weight:600;color:var(--primary)">{q}</div><div style="font-size:12.5px;color:var(--onv);line-height:1.5;margin-top:5px">{a}</div></div>' for q, a in [
                     ('1. 服务器拒绝账号或密码', '核对账号邮箱并使用独立应用密码；应用密码被撤销后需要重新生成。'),
                     ('2. 浏览器打开地址时显示异常', 'WebDAV 地址用于 WebDAV 客户端，普通浏览器可能显示认证提示或错误；请在 Pure Live 内验证。'),
                     ('3. 上传或恢复失败', '检查账号额度、目录写入权限、当前网络连接，以及远端文件是否仍然存在。'),
                     ('4. 连接超时', '重新核对完整的 HTTPS 目录地址和当前网络或代理路径，再使用页面内的重试操作。'),
                     ('5. 撤销访问或重置密码', '在“第三方应用管理”中删除对应条目，生成新应用密码，并更新 Pure Live 配置。')]) + '</div>'
                 + '<div style="height:24px"></div>' + sec('当前服务限制') + card('坚果云官方 WebDAV 帮助目前列出：默认单文件上传上限 500 MB；免费账号每 30 分钟最多 600 次请求，付费账号 1500 次；单次目录响应最多 750 项。服务规则可能调整，请以最新官方帮助为准。')
                 + '<div style="height:24px"></div>' + sec('快速参考') + card(f'地址：{ADDR}\n用户名：坚果云账号邮箱\n密码：坚果云生成的独立应用密码')
                 + '<div style="height:20px"></div><div class="ob" style="width:100%;height:48px;border-radius:24px">打开官方 WebDAV 帮助</div>')
    return f'<div class="hp"><div class="w">{body}</div></div>'


# ---------------------------------------------------------------- new
def v4_bar(n=False, server='我的网盘'):
    N = (lambda k, t: (k, t)) if n else (lambda k, t: (None, None))
    acts = act(rx(RXC['server']), *N(2, 'chg')) + act(mi('refresh'), *N(3, 'chg')) + act(mi('more_vert'), *N(4, 'keep'))
    return bar_sub('WebDAV', server, acts, n_back=N(1, 'keep')[0], n_title=N(5, 'add')[0], tag_title='add')


def v4_crumb(parts=('PureLive',), n=False):
    out = f'<div class="crumb" style="max-width:720px;width:100%;margin:0 auto"><span class="c{"" if parts else " on"}"{dn(6 if n else None, "keep")}>我的文件</span>'
    for i, part in enumerate(parts):
        out += mi('navigate_next', 18) + f'<span class="c{" on" if i == len(parts) - 1 else ""}">{part}</span>'
    return out + '</div>'


def v4_rows(entries=ENTRIES, n=False, dis=False, hover=None):
    out = ''
    for i, (d, name, _, info, kind) in enumerate(entries):
        icon = mi('folder', 28) if d else (rx(RXC['shield'], 28) if kind else mi('insert_drive_file', 28))
        k = 7 if n and i == 0 else (8 if n and i == 1 else None)
        mk = 9 if n and i == 1 else None
        cls = 'fr4' + (' dis' if dis else '') + (' nr hov' if hover == i else '')
        out += (f'<div class="{cls}"{dn(k, "chg" if k == 8 else "keep", "tl")}><span class="ic">{icon}</span>'
                f'<div class="x"><div class="t">{name}</div><div class="s">{info}</div></div><span class="mv"{dn(mk, "keep", "tr")}>{mi("more_vert")}</span></div>')
    return f'<div class="ln" style="padding:0"><div class="w">{out}</div></div>'


def v4_fab(n=False, busy=False):
    icon = SPIN if busy else mi('cloud_upload')
    text = '正在上传备份' if busy else '备份到当前目录'
    return f'<div class="efab"{dn(10 if n else None, "chg", "tl")}>{icon}<span>{text}</span></div>'


def v4_page(body, extra='', crumb=True, fab=True, n=False, server='我的网盘', busy=False, status_row=''):
    return (STATUS + v4_bar(n, server) + (v4_crumb(n=n) if crumb else '') + status_row + f'<div class="body">{body}</div>'
            + (v4_fab(n, busy) if fab else '') + extra + GESTURE)


def v4_menu():
    return ('<div class="menu2" style="top:92px;right:8px;width:200px">'
            f'<div class="it">{rx(RXC["heart_l"])}<span>仅上传关注列表</span></div>'
            f'<div class="it">{rx(RXC["question"])}<span>使用帮助教程</span></div></div>')


def v4_drawer(n=False):
    rows = ''
    for i, (name, addr) in enumerate(SERVERS):
        rows += (f'<div class="dr4{" sel" if i == 0 else ""}"{dn(11 if n and i == 0 else None, "chg", "tl")}><span class="ic">{mi("cloud_done" if i == 0 else "cloud_queue")}</span>'
                 f'<div class="x"><div class="t">{name}</div><div class="s">{addr}</div></div>'
                 f'<span class="b2"{dn(12 if n and i == 0 else None, "keep", "tr")}>{mi("edit")}</span><span class="b2 e"{dn(13 if n and i == 0 else None, "keep", "tr")}>{mi("delete_outline")}</span></div>')
    return ('<div class="dim" style="background:rgba(0,0,0,.4)"></div><div class="drawer r16"><div style="height:36px"></div><div class="dh">WebDAV 服务器</div>' + rows
            + f'<div class="dadd" style="margin:4px 8px"{dn(14 if n else None, "keep", "tl")}>{mi("add")}<span>添加新配置</span></div></div>')


def v4_file_menu(top):
    return (f'<div class="menu2" style="top:{top}px;right:16px;width:200px">'
            f'<div class="it">{rx(RXC["up"])}<span>恢复全部设置</span></div>'
            f'<div class="it">{rx(RXC["heart_l"])}<span>仅恢复关注列表</span></div><div class="sep"></div>'
            f'<div class="it danger">{rx(RXC["delete"])}<span>删除</span></div></div>')


def v4_config_dialog(top=110, check='ok'):
    def fld(ic, lab, val, foc=False, eye=False, dis=False):
        trail = rx(RXC['eye'], 20) if eye else ''
        return (f'<div class="fld{" foc" if foc else ""}" style="background:var(--sch);margin-top:16px;{"opacity:.5;" if dis else ""}">'
                f'<span class="lab">{lab}</span>{rx(ic, 20)}<span class="x">{val}</span>{trail}</div>')
    res = {'ok': ('check_circle', 'var(--ok)', '连接成功'), 'bad': ('error_outline', 'var(--error)', '账号或密码错误（坚果云请使用应用密码）'),
           'run': (None, None, '正在连接…')}[check]
    rl = (f'<div style="display:flex;gap:8px;align-items:center;margin-top:12px;font-size:13px;color:{res[1] or "var(--onv)"}">'
          + (mr(res[0], 18) if res[0] else SPIN) + f'<span>{res[2]}</span></div>')
    return ('<div class="dim"></div><div class="dlg2" style="top:' + str(top) + 'px">'
            f'<h3>{rx(RXC["addbox"])}添加新配置</h3>'
            + fld(RXC['bookmark'], '配置名称', '我的网盘') + fld(RXC['globe'], '地址', ADDR) + fld(RXC['user'], '用户名', 'user@example.com')
            + fld(RXC['lock'], '密码', '••••••••••', foc=True, eye=True) + rl
            + '<div class="acts"><span style="margin-right:auto;padding-left:0">测试连接</span><span>取消</span><span class="fb2">添加</span></div></div>')


def preview_dialog(top=150):
    li = lambda t: f'<div class="li"><i></i><span>{t}</span></div>'
    return ('<div class="dim"></div><div class="dlg2" style="top:' + str(top) + 'px"><h3 style="font-size:16px;font-weight:700">恢复备份</h3>'
            '<div class="c" style="margin-top:14px"><div style="font-size:14px;font-weight:600;word-break:break-all">purelive_2026-10-01T21_30_12_3f2b9c1e-7d4a-4b8e-9a51-0c6e2f8d1b7a.txt</div>'
            '<div style="font-size:12px;color:var(--onv);margin-top:2px">3.x 备份（版本 3）</div>'
            '<div style="font-size:13px;font-weight:600;margin-top:12px">恢复后会这样变化：</div>'
            + li('设置：文件中 86 项，其中 4 项与当前不同') + li('关注的直播间：42 → 44（新增 2，移除 0）') + li('屏蔽词：12 → 12（无变化）')
            + '<div style="font-size:12px;color:var(--onv);margin-top:8px">恢复会替换上面列出的内容，无法撤销；需要时先创建一份备份。</div></div>'
            '<div class="acts"><span>取消</span><span class="fb2">恢复</span></div></div>')


def v4_confirm(title, msg, act_, top=300):
    return ('<div class="dim"></div><div class="dlg2" style="top:' + str(top) + 'px"><h3>' + title + '</h3><div class="c v4">' + msg + '</div>'
            '<div class="acts"><span>取消</span><span class="err">' + act_ + '</span></div></div>')


def sv(icon, title, sub=None, acts=''):
    return (f'<div class="sv" style="padding-bottom:96px"><div class="svc">{icon}</div><h4>{title}</h4>' + (f'<p>{sub}</p>' if sub else '')
            + (f'<div class="acts">{acts}</div>' if acts else '') + '</div>')


def v4_help():
    sec = lambda t: f'<div class="ns" style="padding-left:20px">{t}</div>'
    card = lambda t: f'<div class="hc n4" style="margin:0 12px">{t}</div>'
    params = ('<div class="ncd">'
              f'<div class="prm"><span class="ic">{rx(RXC["links"])}</span><div class="x"><div class="t" style="font-weight:400;font-size:15px">WebDAV 服务器地址</div><div class="s a">{ADDR}</div></div><span class="cp" style="color:var(--onv)">{rx(RXC["copy"], 20)}</span></div>'
              f'<div class="prm"><span class="ic">{rx(RXC["mail"])}</span><div class="x"><div class="t" style="font-weight:400;font-size:15px">用户名</div><div class="s" style="color:var(--onv)">坚果云账号邮箱</div></div></div>'
              f'<div class="prm"><span class="ic">{rx(RXC["lock"])}</span><div class="x"><div class="t" style="font-weight:400;font-size:15px">WebDAV 应用密码</div><div class="s" style="color:var(--onv)">使用独立的应用密码，不是账号登录密码</div></div></div></div>')
    step = lambda t, i: f'<div class="hc n4" style="margin:0 12px">{t}<div class="shot">坚果云网页截图 {i}（示意）</div></div>'
    body = (sec('开始前说明') + card('坚果云支持通过 WebDAV 备份和管理文件。本页以坚果云个人账号为示例。\n免费版当前每月上传流量 1 GB、下载流量 3 GB，空间随上传的数据增长。套餐规则可能调整，依赖额度前请查看官方页面。')
            + sec('连接参数') + params + sec('注册坚果云账号') + step('1. 在浏览器打开坚果云官网。\n2. 选择注册并使用邮箱创建账号。\n3. 按页面提示完成账号验证。', 1))
    return ln(body)


OUT = {}
FILEROWS3 = v3_rows()
# ---- v3
OUT['v3-webdav'] = p(v3_page(FILEROWS3))
OUT['v3-webdav-nav'] = composite([
    (v3_page(FILEROWS3, v3_menu()), '右上角 ⋮：刷新、配置列表、帮助、仅上传关注'),
    (v3_page(FILEROWS3, v3_drawer()), '“打开配置列表”：右侧抽屉'),
    (v3_page(FILEROWS3, v3_file_menu(290)), '文件的 ⋮（点文件本身没反应）'),
])
OUT['v3-webdav-states'] = composite([
    (v3_page('<div class="st3">' + mi('add_circle_outline', 48) + '<div style="margin-top:16px">暂无配置，请先创建WebDAV配置</div><span class="tb">创建新配置</span></div>', crumb=True, fab=True), '还没有配置'),
    (v3_page('<div class="st3">' + mi('error', 64, 'var(--opc)') + '<div style="margin-top:16px;font-size:12px;word-break:break-all">无法加载目录: DioException [bad response]: This exception was thrown because the response has a status code of 401 and RequestOptions.validateStatus was configured to throw for this status code.</div><span class="tb">重试</span></div>'), '加载失败：原样显示异常'),
    (v3_page('<div class="st3">暂无数据</div>'), '空目录'),
    (v3_page('<div class="statusrow">正在下载并恢复配置<div class="lp"><i></i></div></div>' + FILEROWS3), '恢复中'),
    (v3_page(FILEROWS3, '<div class="snack v3">同步成功</div>'), '完成：浅灰提示条'),
])
OUT['v3-webdav-dialogs'] = composite([
    (v3_page(FILEROWS3, v3_config_dialog(150)), '添加新配置'),
    (v3_page(FILEROWS3, v3_config_dialog(150, edit=True)), '编辑配置（名称不能改）'),
    (v3_page(FILEROWS3, v3_confirm('恢复备份', '确定要使用“purelive_2026-10-01T21_30_12_3f2b9c1e-7d4a-4b8e-9a51-0c6e2f8d1b7a.txt”恢复并覆盖本机设置吗？恢复将应用备份中的全部配置。', '恢复备份', False, 250)), '恢复确认：不说会改什么'),
    (v3_page(FILEROWS3, v3_confirm('确定要删除吗？', '确定要删除配置 "我的网盘" 吗？', '删除')), '删除配置'),
])
OUT['v3-help'] = p(STATUS + bar('WebDAV 设置帮助') + f'<div class="body">{v3_help()}</div>' + GESTURE)
OUT['v3-help-full'] = page('393x4000@2 crop', bar('WebDAV 设置帮助') + v3_help(full=True), 'long', css=CSS2)
OUT['v3-webdav-land'] = page('852x393@2', SB24 + v3_bar() + v3_crumb() + f'<div class="body">{FILEROWS3}</div><div class="fab">{mi("cloud_upload")}</div>',
                             'win', '--w:852px;--h:393px', css=CSS2)
OUT['v3-webdav-wide'] = page('1280x800@1.5', v3_bar() + v3_crumb() + f'<div class="body">{FILEROWS3}</div><div class="fab">{mi("cloud_upload")}</div>',
                             'win', '--w:1280px;--h:800px', css=CSS2)

# ---- new
ROWS4 = v4_rows()
OUT['v4-webdav'] = p(v4_page(v4_rows(n=True), n=True))
OUT['v4-webdav-nav'] = composite([
    (v4_page(ROWS4, v4_menu()), '⋮：仅上传关注列表、使用帮助教程'),
    (v4_page(ROWS4, v4_drawer(n=False)), '顶栏“服务器”：右侧抽屉，写地址'),
    (v4_page(ROWS4, v4_file_menu(300)), '文件的 ⋮（点文件本身：预览后恢复）'),
])
OUT['v4-drawer'] = p(v4_page(ROWS4, v4_drawer(n=True)))
OUT['v4-webdav-states'] = composite([
    (v4_page(sv(rx(RXC['cloudoff']), '暂无配置，请先创建WebDAV配置', '添加坚果云、Nextcloud 等 WebDAV 网盘后，可以把备份上传到网盘，在其他设备上恢复',
                '<span class="fb">' + mr('add') + '创建新配置</span><span class="tb">使用帮助教程</span>'), crumb=False, fab=False, server='还没有服务器'), '还没有配置：说明 + 帮助'),
    (v4_page(sv(mr('error_outline'), '无法加载目录', '账号或密码错误（坚果云请使用应用密码）',
                '<span class="fb">' + mr('refresh') + '重试</span><span class="ob">' + mr('edit') + '编辑配置</span>'), fab=False), '加载失败：说原因，能直接改配置'),
    (v4_page(sv(mr('folder_open'), '这个目录是空的', '点右下角按钮把当前数据备份到这里')), '空目录：告诉下一步'),
    (v4_page(v4_rows(dis=True), status_row='<div class="statusrow" style="color:var(--onv);font-size:12px">正在下载并恢复配置<div class="lp"><i></i></div></div>'), '恢复中：列表变灰'),
    (v4_page(ROWS4, busy=True), '上传中：按钮转圈'),
])
OUT['v4-webdav-dialogs'] = composite([
    (v4_page(ROWS4, v4_config_dialog(110, 'ok')), '添加配置：可以先测试连接'),
    (v4_page(ROWS4, v4_config_dialog(110, 'bad')), '测试失败：说原因'),
    (v4_page(ROWS4, preview_dialog(170)), '恢复：同备份页的预览'),
    (v4_page(ROWS4, v4_confirm('确定要删除吗？', '确定要从 WebDAV 删除“purelive_2026-09-15T22_05_03_c47e8a90-1b2d-4e3f-a5b6-7c8d9e0f1a2b.txt”吗？', '删除', 290)), '删除文件'),
])
OUT['v4-help'] = p(STATUS + bar('WebDAV 设置帮助') + f'<div class="body">{v4_help()}</div>' + GESTURE)
OUT['v4-webdav-land'] = page('852x393@2', SB24 + v4_bar() + v4_crumb() + f'<div class="body">{ROWS4}</div>' + v4_fab(),
                             'win', '--w:852px;--h:393px', css=CSS2)
OUT['v4-webdav-wide'] = page('1280x800@1.5', v4_bar() + v4_crumb() + f'<div class="body">{v4_rows(hover=1)}</div>' + v4_fab()
                             + '<div class="tip" style="left:700px;top:262px">点一下预览后恢复；右键或 ⋮ 有更多操作</div>', 'win', '--w:1280px;--h:800px', css=CSS2)

write(HERE, OUT)
