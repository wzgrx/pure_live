"""U.11c device sync mockups: v3 restored and the new design.

v3 (tag v3.2.11): lib/modules/remote_receiver/remote_sync_page.dart (app bar
:184-215, my device :217-262, discovered :264-344, manual :346-396, dialogs
:36-182, scanner :399-447), remote_sync_service.dart (names, start :68-171).
Addresses, pairing codes and the QR code are made up.
    python3 docs/ui/compare/U.11c/src/gen.py && python3 tools/ui/mock/render.py docs/ui/compare/U.11c/src/ --annotate"""
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from skit import *  # noqa: E402,F401,F403
from skit import composite as _composite  # noqa: E402

CSS2 = '''
.cd{background:var(--scl);border-radius:16px;margin-bottom:16px}
.cd .in{padding:20px;display:flex;flex-direction:column;align-items:center;text-align:center}
.cd .in.l{align-items:stretch;text-align:left;padding:16px}
.h20{font-size:20px;font-weight:700}.h18{font-size:18px;font-weight:700}
.qr{width:180px;height:180px;padding:12px;background:#fff;display:grid;grid-template-columns:repeat(25,1fr)}
.qr i{background:#000}.qr b{background:#fff}
.addr{font-size:18px;font-weight:600;margin-top:12px}
.code{font-size:28px;font-weight:700;letter-spacing:6px;font-feature-settings:'tnum'}
.sw3{display:flex;align-items:center;gap:12px;width:100%;text-align:left;padding:8px 0}
.sw3 .x{flex:1}.sw3 .t{font-size:15px}.sw3 .s{font-size:13px;color:var(--onv);line-height:1.45}
.run{display:flex;align-items:center;justify-content:center;gap:6px;font-size:14px;margin-top:12px}
.dev3{background:var(--scl);border-radius:16px;padding:12px;margin-bottom:8px}
.dev3 .r1{display:flex;gap:12px;align-items:center}
.dev3 .n{font-weight:700;font-size:14px}.dev3 .a{font-size:14px;margin-top:4px}
.bt2{display:flex;gap:8px;margin-top:10px}.bt2>span{flex:1}
.o3{height:40px;border-radius:20px;box-shadow:inset 0 0 0 1px var(--outline);color:var(--primary);font-size:14px;font-weight:500;display:flex;align-items:center;justify-content:center;gap:8px}
.f3{height:40px;border-radius:20px;background:var(--primary);color:var(--onPrimary);font-size:14px;font-weight:500;display:flex;align-items:center;justify-content:center;gap:8px}
.o3 .mi,.f3 .mi,.o3 .mr,.f3 .mr{font-size:18px}
.f3.dis,.o3.dis{opacity:.38}
.tf3{height:56px;border-radius:4px;box-shadow:inset 0 0 0 1px var(--outline);display:flex;align-items:center;gap:12px;padding:0 12px;font-size:15px;color:var(--onv)}
.lp2{height:2px;background:color-mix(in srgb,var(--primary) 18%,transparent);position:relative;flex:none}.lp2 i{position:absolute;left:30%;width:30%;top:0;bottom:0;background:var(--primary)}
.desc{font-size:12px;color:var(--onv);padding:0 4px 12px}
.ndev{display:flex;align-items:center;gap:14px;padding:12px 4px 4px 16px}
.ndev .ic{color:var(--onv);font-size:24px}.ndev .x{flex:1;min-width:0}.ndev .t{font-size:15px;font-weight:600}.ndev .s{font-size:12px;color:var(--onv);margin-top:2px}
.nbt{display:flex;gap:8px;padding:6px 16px 14px}.nbt>span{flex:1;justify-content:center}
.nsep{height:1px;background:color-mix(in srgb,var(--ov) 60%,transparent);margin:0 16px}
.cols{display:grid;grid-template-columns:1fr 1fr;gap:16px;max-width:1040px;margin:0 auto;padding:16px 24px}
.codebox{display:flex;gap:8px;justify-content:center;margin-top:16px}
.codebox span{width:40px;height:52px;border-radius:12px;box-shadow:inset 0 0 0 1px var(--outline);display:grid;place-items:center;font-size:22px;font-weight:600;font-feature-settings:'tnum'}
.codebox span.foc{box-shadow:inset 0 0 0 2px var(--primary)}
.cam{position:absolute;inset:0;background:#000 url(.cache/img/274.jpg) center/cover}
.cam::after{content:'';position:absolute;inset:0;background:rgba(0,0,0,.25)}
.frame{position:absolute;left:50%;top:44%;width:230px;height:230px;transform:translate(-50%,-50%);z-index:2}
.frame i{position:absolute;width:34px;height:34px;border:4px solid #fff}
.frame i:nth-child(1){left:0;top:0;border-right:0;border-bottom:0;border-radius:10px 0 0 0}
.frame i:nth-child(2){right:0;top:0;border-left:0;border-bottom:0;border-radius:0 10px 0 0}
.frame i:nth-child(3){left:0;bottom:0;border-right:0;border-top:0;border-radius:0 0 0 10px}
.frame i:nth-child(4){right:0;bottom:0;border-left:0;border-top:0;border-radius:0 0 10px 0}
.camfoot{position:absolute;left:0;right:0;bottom:0;z-index:3;padding:14px 16px 28px;display:flex;flex-direction:column;align-items:center;gap:10px;background:linear-gradient(0deg,rgba(0,0,0,.7),transparent)}
.camfoot .h{color:#fff;font-size:14px;text-align:center;line-height:1.5}
.camfoot .ob{color:#fff;box-shadow:inset 0 0 0 1px rgba(255,255,255,.7)}
.blk{background:#000}
'''


def composite(phones, **kw):
    return _composite(phones, css=CSS2, **kw)


def p(html):
    return page('393x852@3', html, css=CSS2)


ADDR = '192.168.1.100:39888'
CODE = '482916'
DEVICES = [('computer', 'PureLive Windows', '192.168.1.101:39888', 'v4'), ('phone_android', 'PureLive Android', '192.168.1.102:39888', '3.x 版本的设备')]


def qr(size=180):
    rnd = random.Random(7)
    n = 25
    cells = [[rnd.random() < 0.48 for _ in range(n)] for _ in range(n)]
    for oy, ox in ((0, 0), (0, n - 7), (n - 7, 0)):
        for y in range(7):
            for x in range(7):
                ring = max(abs(y - 3), abs(x - 3))
                cells[oy + y][ox + x] = ring != 2
        for k in range(-1, 8):
            for yy, xx in ((oy + k, ox - 1), (oy + k, ox + 7), (oy - 1, ox + k), (oy + 7, ox + k)):
                if 0 <= yy < n and 0 <= xx < n:
                    cells[yy][xx] = False
    body = ''.join('<i></i>' if c else '<b></b>' for row in cells for c in row)
    return f'<div class="qr" style="width:{size}px;height:{size}px">{body}</div>'


# ---------------------------------------------------------------- v3
def v3_bar(running=True, mobile=True):
    acts = (act(mi('qr_code_scanner')) if mobile else '') + act(rx('f19f' if running else 'f009'))
    return bar('设备同步', acts)


def v3_body(state='ok', devices=DEVICES, syncing=False):
    if state == 'noaddr':
        mine = ('<div class="cd"><div class="in"><div class="h20">我的设备</div><div style="height:16px"></div>'
                '<div class="addr" style="margin-top:12px">未获取到本机地址</div><div style="height:8px"></div>'
                '<div style="font-size:14px">使用另一台设备扫描此二维码</div>'
                f'<div class="sw3"><div class="x"><div class="t">同步账号 Cookie</div><div class="s">开启后会发送或提供各平台登录 Cookie，只在信任的设备之间开启</div></div>{sw(False)}</div>'
                f'<div class="run">{mi("error", 18)}同步服务未运行</div></div></div>')
    else:
        mine = ('<div class="cd"><div class="in"><div class="h20">我的设备</div><div style="height:16px"></div>' + qr()
                + f'<div class="addr">{ADDR}</div><div style="height:8px"></div><div style="font-size:14px">配对码</div><div class="code">{CODE}</div>'
                '<div style="height:8px"></div><div style="font-size:14px">使用另一台设备扫描此二维码</div>'
                f'<div class="sw3"><div class="x"><div class="t">同步账号 Cookie</div><div class="s">开启后会发送或提供各平台登录 Cookie，只在信任的设备之间开启</div></div>{sw(False)}</div>'
                f'<div class="run">{mi("check_circle", 18)}同步服务运行中</div></div></div>')
    dis = ' dis' if syncing else ''
    if devices:
        devs = ''.join(f'<div class="dev3"><div class="r1">{mi("devices")}<div><div class="n">{name}</div><div class="a">{addr}</div></div></div>'
                       f'<div class="bt2"><span class="o3{dis}">{mi("download")}接收配置</span><span class="f3{dis}">{mi("upload")}发送配置</span></div></div>'
                       for _, name, addr, _ in devices)
    else:
        devs = '<div style="padding:24px 0;text-align:center;font-size:14px">未发现其他设备</div>'
    spin = '<span class="spin" style="width:18px;height:18px"></span>' if state != 'noaddr' else ''
    found = (f'<div class="cd"><div class="in l"><div style="display:flex;align-items:center"><span class="h18" style="flex:1">发现的设备</span>{spin}</div>'
             f'<div style="height:12px"></div>{devs}</div></div>')
    manual = ('<div class="cd"><div class="in l"><div class="h18">手动输入</div><div style="height:12px"></div>'
              f'<div class="tf3">{mi("lan")}<span>192.168.1.100:39888</span></div><div style="height:12px"></div>'
              f'<span class="f3{dis}">{mi("upload")}发送配置</span><div style="height:8px"></div><span class="o3{dis}">{mi("download")}接收配置</span></div></div>')
    return f'<div style="padding:16px">{mine}{found}{manual}</div>'


def v3_dialog(title, content, acts, top=300):
    return (f'<div class="dim"></div><div class="dlg2" style="top:{top}px"><h3>{title}</h3><div class="c">{content}</div>'
            f'<div class="acts">{acts}</div></div>')


# ---------------------------------------------------------------- new
def v4_bar(running=True, mobile=True, n=False):
    N = (lambda k, t: (k, t)) if n else (lambda k, t: (None, None))
    acts = (act(mi('qr_code_scanner'), *N(2, 'keep')) if mobile else '') + act(rx('f19f' if running else 'f009'), *N(3, 'keep'))
    return bar('设备同步', acts, n_back=N(1, 'keep')[0])


def v4_mine(state='ok', n=False):
    N = (lambda k, t: (k, t)) if n else (lambda k, t: (None, None))
    k4, t4 = N(4, 'add')
    k5, t5 = N(5, 'keep')
    if state == 'noaddr':
        top = (f'<div class="svc" style="width:120px;height:120px;border-radius:60px">{mr("wifi_off", 56)}</div>'
               '<div style="font-size:16px;font-weight:600;margin-top:16px">未获取到本机地址</div>'
               '<div style="font-size:13px;color:var(--onv);margin-top:6px;line-height:1.5">请连接 Wi-Fi 或有线网络；Android 需要允许“附近设备 / 局域网”权限，然后点右上角开始</div>')
        status = f'<div class="run" style="color:var(--error)">{mr("error_outline", 18)}同步服务未运行</div>'
    else:
        top = (qr(168) + f'<div style="display:flex;align-items:center;gap:2px;margin-top:12px"><span style="font-size:17px;font-weight:600;font-feature-settings:\'tnum\'">{ADDR}</span>'
               f'<span class="ib2" style="width:40px;height:40px;color:var(--onv)"{dn(k4, t4)}>{mr("content_copy", 18)}</span></div>'
               f'<div style="font-size:12px;color:var(--onv);margin-top:4px">配对码</div><div class="code" style="font-size:26px">{CODE}</div>'
               '<div style="font-size:12px;color:var(--onv);margin-top:6px">使用另一台设备扫描此二维码</div>')
        status = (f'<div class="run" style="color:{"var(--primary)" if state != "stopped" else "var(--error)"}">'
                  + (mr('check_circle', 18) + '<span style="color:var(--on)">同步服务运行中</span>' if state != 'stopped' else mr('error_outline', 18) + '<span style="color:var(--on)">同步服务未运行</span>') + '</div>')
    acc = (f'<div class="sw3" style="padding:12px 0 0"><div class="x"><div class="t">同步账号 Cookie</div><div class="s" style="font-size:12px">开启后会发送或提供各平台登录 Cookie，只在信任的设备之间开启</div></div>{sw(False, k5, t5)}</div>')
    return ns('我的设备') + f'<div class="ncd"><div class="in" style="padding:16px;display:flex;flex-direction:column;align-items:center;text-align:center">{top}{acc}{status}</div></div>'


def v4_found(devices=DEVICES, searching=True, syncing=False, n=False):
    N = (lambda k, t: (k, t)) if n else (lambda k, t: (None, None))
    dis = ' dis' if syncing else ''
    right = (SPIN.replace('spin', 'spin" style="width:16px;height:16px') + '正在搜索') if searching else ''
    if devices:
        rows = ''
        for i, (ic, name, addr, ver) in enumerate(devices):
            k6, t6 = N(6, 'chg') if i == 0 else (None, None)
            k7, t7 = N(7, 'chg') if i == 0 else (None, None)
            rows += ('<div class="nsep"></div>' if i else '') + (
                f'<div class="ndev"><span class="ic">{mr(ic)}</span><div class="x"><div class="t">{name}</div><div class="s">{addr} · {ver}</div></div></div>'
                f'<div class="nbt"><span class="ob{dis}"{dn(k6, t6)}>{mr("download")}接收配置</span><span class="fb{dis}"{dn(k7, t7)}>{mr("upload")}发送配置</span></div>')
        body = rows
    else:
        body = (f'<div style="padding:24px 16px;text-align:center;font-size:13px;color:var(--onv)">'
                + ('正在搜索局域网设备...' if searching else '未发现其他设备') + '</div>')
    return ns('发现的设备', right) + f'<div class="ncd">{body}</div>'


def v4_manual(n=False, syncing=False):
    N = (lambda k, t: (k, t)) if n else (lambda k, t: (None, None))
    k8, t8 = N(8, 'chg')
    k9, t9 = N(9, 'chg')
    k10, t10 = N(10, 'chg')
    k11, t11 = N(11, 'chg')
    dis = ' dis' if syncing else ''
    return (ns('手动输入') + '<div class="ncd"><div style="padding:12px 16px 4px;font-size:12px;color:var(--onv);line-height:1.5">输入对方设备的地址，或粘贴对方二维码里的同步链接（含配对码，不用再输入）</div>'
            f'<div style="padding:8px 16px 0"><div class="fld"{dn(k8, t8, "tl")}>{mr("lan")}<span class="x ph2">192.168.1.100:39888</span><span{dn(k9, t9, "tr")}>{mr("qr_code_scanner")}</span></div></div>'
            f'<div class="nbt" style="padding-top:12px"><span class="ob{dis}"{dn(k10, t10)}>{mr("download")}接收配置</span><span class="fb{dis}"{dn(k11, t11)}>{mr("upload")}发送配置</span></div></div>')


def v4_body(state='ok', devices=DEVICES, searching=True, syncing=False, n=False):
    return ln('<div style="padding:12px 20px 0;font-size:12px;color:var(--onv)">请确保两台设备连接到同一个局域网</div>'
              + v4_mine(state, n) + v4_found(devices, searching and state != 'stopped', syncing, n) + v4_manual(n, syncing))


def v4_dialog(title, content, acts, top=300):
    return (f'<div class="dim"></div><div class="dlg2" style="top:{top}px"><h3>{title}</h3><div class="c v4">{content}</div>'
            f'<div class="acts">{acts}</div></div>')


def preview(top=170):
    li = lambda t: f'<div class="li"><i></i><span>{t}</span></div>'
    return ('<div class="dim"></div><div class="dlg2" style="top:' + str(top) + 'px"><h3>接收配置</h3>'
            '<div class="c" style="margin-top:14px"><div style="font-size:14px;font-weight:600">来自 PureLive Windows</div>'
            '<div style="font-size:12px;color:var(--onv);margin-top:2px">192.168.1.101:39888 · v4</div>'
            '<div style="font-size:13px;font-weight:600;margin-top:12px">接收后会这样变化：</div>'
            + li('设置：对方 92 项，其中 11 项与本机不同') + li('关注的直播间：42 → 57（新增 15，移除 0）') + li('屏蔽词：12 → 20（新增 8，移除 0）')
            + li('账号：对方没有开“同步账号 Cookie”，本机账号不变')
            + '<div style="font-size:12px;color:var(--onv);margin-top:8px">接收会替换上面列出的内容，无法撤销；需要时先在“备份与恢复”创建一份备份。</div></div>'
            '<div class="acts"><span>取消</span><span class="fb2">接收</span></div></div>')


def scanner():
    actions = act(mi('flash_off')) + act(mi('camera_rear'))
    body = ('<div class="cam"></div><div class="frame"><i></i><i></i><i></i><i></i></div>'
            '<div class="camfoot"><div class="h">扫描另一台设备“设备同步”页上的二维码</div>'
            f'<span class="ob">{mr("keyboard")}手动输入地址</span></div>')
    return STATUS + bar('扫描二维码', actions) + f'<div class="body blk">{body}</div>' + syn(pos='left:8px;top:100px') + GESTURE


OUT = {}
# ---- v3
OUT['v3-sync'] = p(phone(v3_body(), v3_bar()))
OUT['v3-sync-full'] = page('393x1700@2 crop', v3_bar() + v3_body(), 'long', css=CSS2)
OUT['v3-sync-states'] = composite([
    (phone(v3_body('noaddr', devices=[]), v3_bar(False)), '拿不到本机地址：不说为什么'),
    (phone('<div style="margin-top:-560px">' + v3_body(devices=[]) + '</div>', v3_bar()), '还没发现设备'),
    (phone('<div style="margin-top:-560px">' + v3_body(syncing=True) + '</div>', v3_bar()), '同步中：按钮变灰，没有进度'),
])
OUT['v3-sync-dialogs'] = composite([
    (phone(v3_body(), v3_bar(), v3_dialog('设备同步', '设备 192.168.1.101 请求用它的设置覆盖本机设置，是否允许？', '<span>取消</span><span class="fb2">确认</span>')), '对方要覆盖本机（点外面不能关）'),
    (phone(v3_body(), v3_bar(), v3_dialog('配对码', '<div style="height:48px;border-bottom:2px solid var(--primary);display:flex;align-items:center;color:var(--onv)">输入对方设备上显示的 6 位配对码</div><div style="text-align:right;font-size:12px;color:var(--onv);margin-top:4px">0/6</div>', '<span>取消</span><span class="fb2">确认</span>', 260)), '发送或接收前输入对方的配对码'),
    (phone(v3_body(), v3_bar(), v3_dialog('接收配置', '是否接收远程同步的配置？', '<span>取消</span><span class="fb2">确认</span>')), '接收：不说会覆盖什么'),
    (phone(v3_body(), v3_bar(), v3_dialog('选择同步操作', '192.168.1.101:39888', '<span>接收配置</span><span class="fb2">发送配置</span>')), '扫码以后选方向'),
])
OUT['v3-scan'] = p(STATUS + bar('扫描二维码') + '<div class="body blk"><div class="cam"></div></div>' + syn(pos='left:8px;top:100px') + GESTURE)
OUT['v3-sync-land'] = page('852x393@2', land(v3_body(), v3_bar()), 'win', '--w:852px;--h:393px', css=CSS2)
OUT['v3-sync-wide'] = page('1280x800@1.5', wide(v3_body(), v3_bar(mobile=False)), 'win', '--w:1280px;--h:800px', css=CSS2)

# ---- new
OUT['v4-sync'] = p(phone(v4_body(), v4_bar()))
OUT['v4-sync-full'] = page('393x1700@2 crop', v4_bar(n=True) + v4_body(n=True), 'long', css=CSS2)
OUT['v4-sync-states'] = composite([
    (phone(v4_body('noaddr', devices=[], searching=False), v4_bar(False)), '拿不到本机地址：说原因和下一步'),
    (phone(v4_body('stopped', devices=[], searching=False), v4_bar(False)), '停止了：状态红色，右上角开始'),
    (phone('<div style="margin-top:-380px">' + v4_body(devices=[]) + '</div>', v4_bar()), '正在搜索'),
    (phone('<div style="margin-top:-380px">' + v4_body(syncing=True) + '</div>', '' if False else v4_bar() + '<div class="lp2"><i></i></div>'), '同步中：顶栏下进度条，按钮变灰'),
])
CODEBOX = ('输入“PureLive Windows”上显示的 6 位配对码<div class="codebox"><span>4</span><span>8</span><span>2</span>'
           '<span class="foc"></span><span></span><span></span></div>')
OUT['v4-sync-dialogs'] = composite([
    (phone(v4_body(), v4_bar(), v4_dialog('发送配置', '确定要将当前设备的全部配置发送到“PureLive Windows”吗？对方确认后会覆盖它的配置。', '<span>取消</span><span class="fb2">发送</span>')), '发送：写清发给谁、会覆盖对方'),
    (phone(v4_body(), v4_bar(), v4_dialog('配对码', CODEBOX, '<span>取消</span><span class="fb2">确认</span>', 260)), '配对码：写清是哪台设备的'),
    (phone(v4_body(), v4_bar(), preview(170)), '接收：先看会改变什么（同备份页）'),
    (phone(v4_body(), v4_bar(), v4_dialog('设备同步', '设备 192.168.1.101（PureLive Windows）请求用它的设置覆盖本机设置，是否允许？', '<span>拒绝</span><span class="fb2">允许</span>')), '对方要覆盖本机：拒绝 / 允许'),
])
OUT['v4-scan'] = composite([
    (scanner(), '扫码：同备份页的扫码页'),
    (phone(v4_body(), v4_bar(), v4_dialog('选择同步操作', 'PureLive Windows · 192.168.1.101:39888', '<span>接收配置</span><span class="fb2">发送配置</span>')), '扫到以后选方向（照 v3）'),
])
OUT['v4-sync-land'] = page('852x393@2', land(v4_body(), v4_bar()), 'win', '--w:852px;--h:393px', css=CSS2)
WIDE = ('<div class="cols"><div>' + v4_mine() + '</div><div>' + v4_found() + v4_manual() + '</div></div>')
OUT['v4-sync-wide'] = page('1280x800@1.5', wide('<div style="padding:4px 24px 0;max-width:1040px;margin:0 auto;font-size:12px;color:var(--onv)">请确保两台设备连接到同一个局域网</div>' + WIDE,
                                                v4_bar(mobile=False)), 'win', '--w:1280px;--h:800px', css=CSS2)

write(HERE, OUT)
