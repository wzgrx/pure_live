"""U.11a backup and restore mockups: v3 restored and the new design.

v3 (tag v3.2.11): lib/modules/backup/backup_page.dart (groups :87-313),
lib/modules/backup/scan_page.dart (TV sync scanner :130-264),
lib/plugins/backup_recovery_service.dart (pickers and toasts :14-117).
Rows from common/widgets/widget_extensions.dart (see skit.py).
New design: v4's additions (M12: file list, restore preview, default folder,
TV address) kept where they fix a v3 problem.
    python3 docs/ui/compare/U.11a/src/gen.py && python3 tools/ui/mock/render.py docs/ui/compare/U.11a/src/ --annotate"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from skit import *  # noqa: E402,F401,F403
import skit  # noqa: E402

CSS2 = '''
.cam{position:absolute;inset:0;background:#000 url(.cache/img/274.jpg) center/cover}
.cam::after{content:'';position:absolute;inset:0;background:rgba(0,0,0,.25)}
.camhint{position:absolute;left:16px;right:16px;bottom:28px;z-index:2;background:rgba(0,0,0,.72);border-radius:12px;padding:12px 16px;color:#fff;font-size:14px;text-align:center}
.frame{position:absolute;left:50%;top:44%;width:230px;height:230px;transform:translate(-50%,-50%);z-index:2}
.frame i{position:absolute;width:34px;height:34px;border:4px solid #fff}
.frame i:nth-child(1){left:0;top:0;border-right:0;border-bottom:0;border-radius:10px 0 0 0}
.frame i:nth-child(2){right:0;top:0;border-left:0;border-bottom:0;border-radius:0 10px 0 0}
.frame i:nth-child(3){left:0;bottom:0;border-right:0;border-top:0;border-radius:0 0 0 10px}
.frame i:nth-child(4){right:0;bottom:0;border-left:0;border-top:0;border-radius:0 0 10px 0}
.camfoot{position:absolute;left:0;right:0;bottom:0;z-index:3;padding:14px 16px 28px;display:flex;flex-direction:column;align-items:center;gap:10px;background:linear-gradient(0deg,rgba(0,0,0,.7),transparent)}
.camfoot .h{color:#fff;font-size:14px;text-align:center;line-height:1.5}
.camfoot .ob{color:#fff;box-shadow:inset 0 0 0 1px rgba(255,255,255,.7)}
.blk{background:#000;color:#fff}
.v3status{display:flex;flex-direction:column;align-items:center;justify-content:center;height:100%;text-align:center;padding:24px}
.v3status h4{font-size:16px;font-weight:700;margin-top:16px}
.v3eb{margin-top:20px;height:40px;padding:0 24px;border-radius:20px;background:var(--scl);box-shadow:0 1px 2px rgba(0,0,0,.25);color:var(--primary);font-size:13px;font-weight:600;display:grid;place-items:center}
.picker{position:absolute;left:0;right:0;bottom:0;top:120px;z-index:21;background:#fff;border-radius:16px 16px 0 0;box-shadow:0 -4px 16px rgba(0,0,0,.2);padding:20px;font-size:14px;color:#444}
.picker .row{display:flex;gap:12px;align-items:center;height:52px;border-bottom:1px solid #eee}
.picker .row .mr{color:#888}
'''

_composite = composite


def composite(phones, **kw):  # noqa: F811
    return _composite(phones, css=CSS2, **kw)


RX = dict(down='ecd9', up='ed15', folder='ed70', text='ed0f', globe='edcf', cloud='eb9d', scan='f03f', qr='f03d',
          account='ea09', arrow='ea6e', heart='ee0f', tv='f235', ext='ecaf', back='ea58', more=None)

FOLDER = '/storage/emulated/0/Download/PureLive'
FILES = [('purelive_2026-10-01T21_30_12.txt', '2026-10-01 21:30 · 48.2 KB · 完整备份', False),
         ('purelive_favorites_2026-09-28T09_12_40.txt', '2026-09-28 09:12 · 6.1 KB · 仅关注列表', True),
         ('purelive_2026-09-15T22_05_03.txt', '2026-09-15 22:05 · 45.7 KB · 完整备份', False)]


def p(html, css=CSS2):
    return page('393x852@3', html, css=css)


# ---------------------------------------------------------------- v3
def v3_list(busy=None, full=False):
    spin = lambda k: SPIN if busy == k else 'chev'
    cloud = cd3(
        t3(rx(RX['account'], 22), '登录', '点击登录，同步配置数据'),
        t3(rx(RX['cloud'], 22), 'WebDav', '备份到WebDav服务器'),
        t3(rx(RX['scan'], 22), '设备同步', '通过局域网在设备之间同步配置'),
        t3(rx(RX['qr'], 22), '同步TV数据', '将数据远程同步到TV'))
    local = cd3(
        t3(rx(RX['down'], 22), '创建备份', '可用于恢复当前数据', trailing=spin('create')),
        t3(rx(RX['up'], 22), '恢复备份', '从备份文件中恢复', trailing=spin('restore')),
        t3(rx(RX['down'], 22), '仅导出关注列表', '仅含关注的房间和分区，不影响其他设置'),
        t3(rx(RX['up'], 22), '仅导入关注列表', '仅含关注的房间和分区，不影响其他设置'))
    sett = cd3(t3(rx(RX['folder'], 22), '备份目录', FOLDER))
    log = cd3(t3(rx(RX['text'], 22), '启用本地日志', '开启后将日志写入本地文件', trailing=sw(True)),
              t3(rx(RX['globe'], 22), '在浏览器中查看日志', 'http://192.168.0.100:9100', trailing=rx(RX['arrow'], 24)),
              t3(rx(RX['folder'], 22), '打开日志目录', '查看并管理日志文件'))
    return l3(g3('云端备份') + cloud + g3('本地备份') + local + g3('备份设置') + sett + g3('日志管理') + log)


V3BAR = bar('备份与恢复')


def v3_scan_page(state):
    if state == 'scan':
        actions = act(mi('flash_off', 24, '#9E9E9E')) + act(mi('camera_rear'))
        body = '<div class="cam"></div><div class="frame"><i></i><i></i><i></i><i></i></div><div class="camhint">扫描电视端显示的服务器二维码</div>'
        return STATUS + bar('扫描二维码', actions) + f'<div class="body blk">{body}</div>' + syn(pos='left:8px;top:100px') + GESTURE
    if state == 'camerr':
        actions = act(mi('no_flash', 24, '#9E9E9E')) + act(mi('camera_rear'))
        body = ('<div class="v3status" style="background:#000;color:#fff">' + mi('no_photography', 44, '#fff') +
                '<div style="margin-top:16px;font-size:14px">相机当前不可用，请检查相机权限后重试。</div>'
                '<div class="fb" style="margin-top:20px">重试</div></div>')
        return STATUS + bar('扫描二维码', actions) + f'<div class="body">{body}</div>' + GESTURE
    if state == 'syncing':
        body = '<div class="v3status"><span class="spin big"></span><h4 style="margin-top:20px">正在同步</h4></div>'
    elif state == 'ok':
        body = ('<div class="v3status">' + mi('check_circle_outline', 44, '#4CAF50') + '<h4>同步成功</h4><div class="v3eb">重试</div></div>'
                '<div class="stoast">同步成功</div>')
    else:
        body = ('<div class="v3status">' + mi('error_outline', 44, 'var(--error)') + '<h4>同步失败</h4><div class="v3eb">重试</div></div>'
                '<div class="stoast">同步失败</div>')
    return STATUS + bar('扫描二维码') + f'<div class="body">{body}</div>' + GESTURE


# ---------------------------------------------------------------- new
def v4_list(n=False, busy=None, files=FILES, files_state=None, custom=True, desktop=False, scroll=0, hover=False):
    def N(k, tag=None):
        ok = n is True or (n and k in n)
        return (k, tag) if ok else (None, None)

    def row(icon, title, sub, key, num, tag='keep', trailing='chev'):
        k, t = N(num, tag)
        dis = 'dis' if busy and busy != key and key not in ('w', 's') else ''
        tr = SPIN if busy == key else trailing
        return nr(icon, title, sub, tr, n=k, tag=t, cls=dis)

    cloud = ncd(
        row(rx(RX['cloud'], 22), 'WebDAV', '备份到 WebDAV 服务器', 'w', 1),
        row(rx(RX['scan'], 22), '设备同步', '通过局域网在设备之间同步配置', 's', 2),
        row(rx(RX['qr'], 22), '同步TV数据', '将数据远程同步到TV', 't', 3, 'chg'))
    local = ncd(
        row(rx(RX['down'], 22), '创建备份', '保存设置、关注、历史、分组、屏蔽词和搜索记录（不含账号 Cookie 和 WebDAV 密码）', 'create', 4, 'chg'),
        row(rx(RX['up'], 22), '恢复备份', '选择备份文件，先预览会改变什么再恢复', 'restore', 5, 'chg'),
        row(rx(RX['down'], 22), '仅导出关注列表', '仅含关注的房间和分区，不影响其他设置', 'fexp', 6),
        row(rx(RX['up'], 22), '仅导入关注列表', '仅含关注的房间和分区，不影响其他设置', 'fimp', 7))
    # backups in the folder
    if files_state == 'loading':
        fl = ncd(nr(SPIN, '加载中...', None, ''))
        head = ns('目录中的备份')
    elif files_state == 'empty':
        fl = ncd(nr(mr('inventory_2', 22), '这个目录里还没有备份', '在这里创建的备份会列出来；也可以把 3.x 的备份文件放进这个目录', '', icon_mute=True))
        head = ns('目录中的备份')
    elif files_state == 'error':
        fl = ncd(nr(mr('error_outline', 22, 'var(--error)'), '无法读取备份目录', '在这里创建的备份会列出来；也可以把 3.x 的备份文件放进这个目录', '',
                    ) + '<div style="padding:0 16px 12px 54px"><span class="tb" style="padding:0 8px">' + mr('refresh') + '重试</span></div>')
        head = ns('目录中的备份')
    else:
        rows = ''
        for i, (name, sub, fav) in enumerate(files):
            k, t = N(8 if i == 0 else None, 'add')
            mk, mt = N(9 if i == 0 else None, 'add')
            more = f'<span class="more"{dn(mk, mt, "tr")}>{mi("more_vert")}</span>'
            rows += nr(rx(RX['heart'] if fav else RX['text'], 22), name, sub, more, n=k, tag=t,
                       cls=('dis ' if busy else '') + ('sep ' if i else '') + ('hov' if hover and i == 1 else ''))
        fl = ncd(rows)
        head = ns(f'目录中的备份 · {len(files)}')
    k, t = N(10, 'chg')
    folder = [nr(rx(RX['folder'], 22), '备份目录' if custom else '备份目录（默认）', FOLDER if not desktop else r'D:\Backup\PureLive', 'chev', n=k, tag=t,
                 cls='dis' if busy else '')]
    if custom:
        k, t = N(11, 'add')
        folder.append(nr(rx(RX['back'], 22), '改回默认目录', None, 'chev', n=k, tag=t, cls='dis' if busy else ''))
    if desktop:
        k, t = N(12, 'add')
        folder.append(nr(rx(RX['ext'], 22), '打开备份目录', None, 'chev', n=k, tag=t))
    inner = ns('云端和其他设备') + cloud + ns('本地备份') + local + head + fl + ns('备份目录') + ncd(*folder)
    return ln(f'<div style="margin-top:-{scroll}px">{inner}</div>' if scroll else inner)


V4BAR = bar('备份与恢复')


def preview_dialog(top=150):
    li = lambda t: f'<div class="li"><i></i><span>{t}</span></div>'
    return ('<div class="dim"></div><div class="dlg2" style="top:' + str(top) + 'px"><h3 style="font-size:16px;font-weight:700">恢复备份</h3>'
            '<div class="c" style="margin-top:14px"><div style="font-size:14px;font-weight:600">purelive_2026-09-15T22_05_03.txt</div>'
            '<div style="font-size:12px;color:var(--onv);margin-top:2px">3.x 备份（版本 3）</div>'
            '<div style="font-size:13px;font-weight:600;margin-top:12px">恢复后会这样变化：</div>'
            + li('设置：文件中 86 项，其中 7 项与当前不同') + li('关注的直播间：42 → 38（新增 1，移除 5）')
            + li('关注分组：4 → 4（无变化）') + li('屏蔽词：12 → 9（新增 0，移除 3）') + li('观看历史：50 → 50（新增 12，移除 12）')
            + '<div class="li" style="color:var(--onv)">' + mr('check', 14, 'var(--onv)') + '<span>文件中没有、保持不变：搜索记录</span></div>'
            '<div style="font-size:12px;color:var(--onv);margin-top:8px">恢复会替换上面列出的内容，无法撤销；需要时先创建一份备份。</div></div>'
            '<div class="acts"><span>取消</span><span class="fb2">恢复</span></div></div>')


def item_menu(top, right=16):
    return (f'<div class="menu2" style="top:{top}px;right:{right}px">'
            f'<div class="it">{rx(RX["up"], 20)}<span>恢复全部设置</span></div>'
            f'<div class="it">{rx(RX["heart"], 20)}<span>仅恢复关注列表</span></div><div class="sep"></div>'
            f'<div class="it danger">{rx("ec2a", 20)}<span>删除</span></div></div>')


def address_dialog(top=230, value='', err=None):
    cls = 'fld bad' if err else ('fld foc' if value else 'fld foc')
    txt = f'<span class="x">{value}</span>' if value else '<span class="x ph2">例如：192.168.1.100:8888</span>'
    return ('<div class="dim"></div><div class="dlg2" style="top:' + str(top) + 'px"><h3>同步TV数据</h3>'
            '<div class="c v4" style="font-size:13px">输入电视端同步页显示的地址，发送关注、历史、屏蔽词和弹幕设置（不含账号）</div>'
            f'<div class="{cls}" style="margin-top:16px;background:var(--sch)"><span class="lab">设备地址</span>{txt}{mr("qr_code_scanner")}</div>'
            + (f'<div class="fh err">{err}</div>' if err else '') +
            '<div class="acts"><span>取消</span><span class="fb2">发送配置</span></div></div>')


def v4_scan_page(state, n=False):
    N = (lambda k, tag=None: (k, tag)) if n else (lambda k, tag=None: (None, None))
    if state == 'scan':
        k1, t1 = N(13, 'chg')
        k2, t2 = N(14, 'keep')
        actions = act(mi('flash_off'), *N(15, 'chg')) + act(mi('camera_rear'), *N(16, 'keep'))
        body = ('<div class="cam"></div><div class="frame"><i></i><i></i><i></i><i></i></div>'
                f'<div class="camfoot"><div class="h">扫描电视端显示的服务器二维码</div>'
                f'<span class="ob"{dn(k1, t1)}>{mr("keyboard")}手动输入地址</span></div>')
        return STATUS + bar('扫描二维码', actions, n_back=N(14)[0]) + f'<div class="body blk">{body}</div>' + syn(pos='left:8px;top:100px') + GESTURE
    if state == 'camerr':
        body = ('<div class="sv"><div class="svc">' + mi('no_photography') + '</div><h4>相机当前不可用</h4>'
                '<p>请检查相机权限后重试，或者直接输入电视端同步页显示的地址。</p><div class="acts"><span class="fb">重试</span>'
                '<span class="ob">' + mr('keyboard') + '输入地址</span></div></div>')
        return STATUS + bar('扫描二维码') + f'<div class="body">{body}</div>' + GESTURE
    if state == 'syncing':
        body = ('<div class="sv"><span class="spin big"></span><h4>正在同步</h4><p>正在发送到电视 192.168.1.100:8888</p></div>')
    elif state == 'ok':
        body = ('<div class="sv"><div class="svc">' + mr('check_circle', None, 'var(--ok)') + '</div><h4>同步成功</h4>'
                '<p>关注、历史、屏蔽词和弹幕设置已发送到电视</p><div class="acts"><span class="fb">完成</span><span class="tb">再扫一次</span></div></div>')
    else:
        body = ('<div class="sv"><div class="svc">' + mr('error_outline', None, 'var(--error)') + '</div><h4>同步失败</h4>'
                '<p>同步失败，请确认电视端已打开同步页并在同一局域网</p><div class="acts"><span class="fb">重试</span>'
                '<span class="ob">' + mr('keyboard') + '输入地址</span></div></div>')
    return STATUS + bar('扫描二维码') + f'<div class="body">{body}</div>' + GESTURE


OUT = {}
# ---- v3
OUT['v3-backup'] = p(phone(v3_list(), V3BAR))
OUT['v3-backup-full'] = page('393x1500@2 crop', V3BAR + v3_list(), 'long', css=CSS2)
OUT['v3-backup-states'] = composite([
    (phone(v3_list(busy='create'), V3BAR), '点“创建备份”：选目录后行尾转圈；<br>其他行点了没反应，但样子不变'),
    (phone(v3_list(), V3BAR, '<div class="stoast">创建备份成功</div>'), '完成：只说“创建备份成功”'),
    (phone(v3_list(), V3BAR, '<div class="dim"></div><div class="picker"><div style="font-weight:600;font-size:16px;margin-bottom:8px">选择备份文件</div>'
           + ''.join(f'<div class="row">{mr("description")}<span>{f[0]}</span></div>' for f in FILES) + '<div style="margin-top:16px;font-size:12px;color:#999">（系统文件选择器，各系统样子不同）</div></div>'),
     '点“恢复备份”：系统文件选择器，<br>选完立刻覆盖，没有确认'),
])
OUT['v3-scan'] = composite([(v3_scan_page('scan'), '扫码（手电筒灰 / 黄写死）'), (v3_scan_page('syncing'), '正在同步'),
                            (v3_scan_page('ok'), '成功：按钮也叫“重试”'), (v3_scan_page('fail'), '失败：不说原因'),
                            (v3_scan_page('camerr'), '相机不可用：只能重试')])
OUT['v3-backup-land'] = page('852x393@2', land(v3_list(), V3BAR), 'win', '--w:852px;--h:393px', css=CSS2)
OUT['v3-backup-wide'] = page('1280x800@1.5', wide(v3_list(), V3BAR), 'win', '--w:1280px;--h:800px', css=CSS2)

# ---- new
OUT['v4-backup'] = p(phone(v4_list(), V4BAR))
OUT['v4-backup-full'] = page('393x1900@2 crop', V4BAR + v4_list(n=True), 'long', css=CSS2)
OUT['v4-backup-states'] = composite([
    (phone(v4_list(busy='create'), V4BAR), '创建中：行尾转圈，其他操作变灰'),
    (phone(v4_list(files=[('purelive_2026-10-01T21_36_08.txt', '2026-10-01 21:36 · 48.3 KB · 完整备份', False)] + FILES), V4BAR, '<div class="toast2"><span>已备份到 purelive_2026-10-01T21_36_08.txt</span></div>'), '完成：提示条写文件名，列表多一条'),
    (phone(v4_list(files_state='empty', custom=False), V4BAR), '目录里还没有备份（默认目录）'),
    (phone(v4_list(files_state='error'), V4BAR), '读不了备份目录'),
])
OUT['v4-restore'] = composite([
    (phone(v4_list(), V4BAR, item_menu(470)), '备份文件的 ⋮ 菜单'),
    (phone(v4_list(), V4BAR, preview_dialog(150)), '恢复前先预览会改变什么'),
    (phone(v4_list(), V4BAR, '<div class="toast2"><span>恢复备份成功</span></div>'), '恢复完成'),
])
OUT['v4-scan'] = composite([
    (v4_scan_page('scan'), '扫码：下面可以手动输入地址'),
    (v4_scan_page('syncing'), '正在同步：写出发到哪台电视'),
    (v4_scan_page('ok'), '成功：完成 / 再扫一次'),
    (v4_scan_page('fail'), '失败：写原因，可重试或输入地址'),
    (v4_scan_page('camerr'), '相机不可用：也能输入地址'),
])
OUT['v4-scanner'] = p(v4_scan_page('scan', n=True))
OUT['v4-tv-dialog'] = composite([
    (phone(v4_list(), V4BAR, address_dialog(250)), '电脑、没有相机时：输入地址对话框<br>（框里有扫码按钮）'),
    (phone(v4_list(), V4BAR, address_dialog(250, '192.168.1.100:88a', '设备地址无效')), '地址不对：框下面直接说'),
])
OUT['v4-backup-land'] = page('852x393@2', land(v4_list(), V4BAR), 'win', '--w:852px;--h:393px', css=CSS2)
OUT['v4-backup-wide'] = page('1280x800@1.5', wide(v4_list(n=set(range(4, 13)), desktop=True, scroll=250, hover=True), V4BAR,
                                                  '<div class="tip" style="left:720px;top:468px">点一下预览后恢复；右键或 ⋮ 有更多操作</div>'),
                             'win', '--w:1280px;--h:800px', css=CSS2)

write(HERE, OUT)
