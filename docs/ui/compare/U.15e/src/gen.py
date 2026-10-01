"""U.15e TV IPTV settings and link playback: pure_live_TV restored (v3-*) and
the new design (v4-*), 960x540 logical. Shared TV pieces: ../../U.15d/src/tvkit.py.

pure_live_TV (~/ref/pure_live_TV/lib/):
  modules/live/iptv/pages/iptv_{manage,resources,import,sync,headers}_section.dart
  modules/live/iptv/services/iptv_confirm_dialog.dart, core/dialog/tv_dialog.dart
  features/settings/tv_settings_page.dart (SettingsSectionScaffold), core/widgets/tv_settings_*.dart,
  core/widgets/remote_sync_qr_card.dart, tv_qr_card.dart
  modules/live/movie_playback/movie_playback_page.dart (链接放映)
Phone baseline for the same functions: v3 modules/iptv/iptv_page.dart, iptv_manage.dart,
modules/toolbox/toolbox_page.dart; the IPTV guide in the room is U.2g.

    python3 docs/ui/compare/U.15e/src/gen.py
    python3 tools/ui/mock/render.py docs/ui/compare/U.15e/src/ --annotate
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', 'U.15d', 'src'))
from tvkit import *  # noqa: E402,F403

OUT = {}
QR_URL = 'http://192.168.1.5:8080/#/sync'

# =====================================================================
# pure_live_TV settings pages (design px / 2)
# =====================================================================
P_CSS = '''
.pp{position:absolute;inset:0;background:#121212;color:#fff;font-family:'Noto Sans SC'}
.pp .bd{position:absolute;left:0;right:0;top:33px;bottom:0;padding:8px;overflow:hidden}
.p-back.s{background:#00A1FF;box-shadow:0 0 6px rgba(0,161,255,.75)}
.p-ch{font-size:15px;color:#fff;flex:none}
.p-qrw{width:140px;margin:0 auto;display:flex;flex-direction:column;align-items:center;background:#1F1F1F;border-radius:12px;padding:5px 5px 6px;box-shadow:0 2px 6px rgba(0,0,0,.3)}
.p-qrw .u{font:600 8px 'Noto Sans SC';margin-top:5px;white-space:nowrap}
.p-st{font:400 8px 'Noto Sans SC';color:#00A1FF;padding:5px 8px 0}
.p-rail{position:absolute;left:0;top:0;bottom:0;width:80px;background:rgba(31,31,31,.6);display:flex;flex-direction:column;align-items:center;padding:12px 0;gap:4px}
.p-rail .ri{width:56px;padding:5px 0;border-radius:8px;display:flex;flex-direction:column;align-items:center;gap:2px;font:400 7px 'Noto Sans SC';color:#fff}
.p-rail .ri.on{background:#00A1FF}
.p-chipx{padding:2px 5px;border-radius:4px;background:rgba(18,18,18,.5);font:500 8px 'Noto Sans SC';color:#fff}
'''


def p_page(title, body, back_focus=True):
    return (f'<div class="pp"><div class="p-app"><span class="p-back{" s" if back_focus else ""}">{mr("arrow_back_ios_new", 11)}返回</span>'
            f'<span class="t">{title}</span></div><div class="bd">{body}</div></div>')


def p_qr():
    return f'<div class="p-qrw">{qr(82)}<div class="u">{QR_URL}</div></div>'


def p_set(icon, title, sub=None, trail='chev', sel=False):
    t = {'chev': mr('chevron_right', 15, 'color:#fff'), None: ''}.get(trail, trail)
    s = f'<div class="b">{sub}</div>' if sub else ''
    return (f'<div class="p-set{" s" if sel else ""}"><span class="ic">{mr(icon, 15)}</span>'
            f'<div class="tx"><div class="a">{title}</div>{s}</div>{t}</div>')


def p_group(title, rows):
    return f'<div style="height:12px"></div><div class="p-gt">{title}</div><div class="p-card">{rows}</div>'


def ptv(body, css=''):
    return page(960, 540, 2, f'<div class="fs p" style="--w:960px;--h:540px">{body}</div>', P_CSS + css)


# ---- v3-iptv: IPTV 设置 (QR on top, four entries); the page opens on 返回
rows = (p_set('playlist_play', '资源列表', '查看已导入的直播源，支持同步与删除')
        + p_set('playlist_add', '导入直播源', '网络导入，或扫码在手机网页上传播放列表')
        + p_set('sync', '自动化周期同步设置', '自动同步开关、周期与一键同步')
        + p_set('vpn_key', '直播源请求头', 'User-Agent / Referer / Cookie'))
OUT['v3-iptv'] = ptv(p_page('IPTV 设置', p_qr() + p_group('IPTV 设置', rows)))

# ---- v3-resources: 资源列表
mb = lambda label, icon, on=False: f'<span class="p-mb{" on" if on else ""}">{mr(icon, 9)}{label}</span>'
acts = mb('同步', 'cloud_download') + mb('自动同步', 'autorenew', True) + mb('删除', 'delete_outline')
res_rows = ('<div class="p-gt" style="padding-top:4px">网络资源</div>' + p_set('cloud_sync', '同步')
            + p_set('playlist_play', '央视频道', 'm3u', f'<span style="display:flex;gap:4px">{acts}</span>')
            + p_set('playlist_play', '卫视合集', 'm3u', f'<span style="display:flex;gap:4px">{acts}</span>')
            + '<div style="height:6px"></div><div class="p-gt">本地资源</div>'
            + p_set('playlist_play', '本地导入的列表', 'txt', f'<span style="display:flex;gap:4px">{mb("删除", "delete_outline")}</span>'))
hot = p_set('live_tv', '热门资源地址', '自定义“热门”频道的订阅地址，留空使用内置默认源\nhttps://raw.githubusercontent.com/…/hot.m3u', mb('编辑', 'edit'))
res_body = p_qr() + p_group('热门资源地址', hot) + p_group('资源列表', res_rows)
OUT['v3-resources'] = ptv(p_page('资源列表', res_body))
OUT['v3-resources-full'] = page(960, 760, 2, f'<div class="fs p" style="--w:960px;--h:760px">{p_page("资源列表", res_body + "<div class=\"p-st\">同步成功</div>")}</div>', P_CSS)

# ---- v3-import: 导入直播源
imp = ('<div style="padding:4px 8px"><div class="p-in">播放列表地址（http/https）</div></div>'
       '<div style="padding:4px 8px"><div class="p-in">名称（留空则用地址命名）</div></div>'
       + p_set('link', '从 URL 导入播放列表', '下载网络播放列表并导入，请求头会写入该源的每个频道'))
OUT['v3-import'] = ptv(p_page('导入直播源', p_qr() + p_group('从 URL 导入播放列表', imp)
                              + p_group('手机网页导入', p_set('qr_code_scanner', '手机网页导入', '扫码打开远程页面，填写地址或上传 m3u/txt 文件推送到电视', None))))

# ---- v3-sync: 自动化周期同步设置
sw = '<span class="p-psw on"><i></i></span>'
val = f'<span style="display:flex;align-items:center;gap:4px;font:600 10px \'Noto Sans SC\'">6 小时{mr("expand_more", 14)}</span>'
sync = (p_set('sync', '启动时全自动同步', '应用冷启动时自动在后台静默检查并更新网络资源', sw)
        + p_set('schedule', '自动同步检查间隔', '当前每隔 6 小时进行一次同步', val)
        + p_set('cloud_sync', '同步', '同步所有开启了自动同步的网络资源'))
OUT['v3-sync'] = ptv(p_page('自动化周期同步设置', p_qr() + p_group('自动化周期同步设置', sync)))

# ---- v3-headers: 直播源请求头
hd = (p_set('tv', '自定义直播源请求头', '未设置') + p_set('link', 'Referer 请求头', '未设置') + p_set('cookie', 'Cookie 请求头', '未设置'))
OUT['v3-headers'] = ptv(p_page('直播源请求头', p_qr() + p_group('直播源请求头', hd)))

# ---- v3-confirm: delete a source (TvDialog, confirm has autofocus)
dlg = ('<div class="p-scrim"></div><div class="p-dlg" style="left:280px;top:150px;width:400px">'
       '<div class="h">确认删除</div><div style="font:400 12px/1.5 \'Noto Sans SC\';color:#fff;white-space:pre-line">"央视频道"\n\n你确定要删除这个订阅源吗？这将连带清空其下的所有频道和节目数据，且无法撤销。</div>'
       '<div style="display:flex;justify-content:flex-end;gap:8px;margin-top:16px"><span class="p-mb" style="font-size:7px;padding:3px 7px">取消</span>'
       '<span class="p-mb on" style="font-size:7px;padding:3px 7px;box-shadow:0 0 6px rgba(0,161,255,.75)">确认</span></div></div>')
OUT['v3-confirm'] = ptv(p_page('资源列表', res_body, back_focus=False) + dlg)

# ---- v3-link: 链接放映 in the home shell (rail collapsed)
RAIL = [('favorite_border', '关注'), ('local_fire_department', '热门'), ('category', '分区'), ('collections_bookmark', '关注分区'),
        ('movie_creation', '链接放映'), ('search', '搜索'), ('history', '历史'), ('settings', '设置')]
rail = '<div class="p-rail">' + ''.join(f'<div class="ri{" on" if l == "链接放映" else ""}">{mo(i, 13)}{l}</div>' for i, l in RAIL) + '</div>'
sites = ['哔哩哔哩', '斗鱼', '虎牙', '抖音', '快手', '网易CC', 'Twitch', 'Soop', 'YY', 'AcFun 直播', 'Picarto', 'TwitCasting', '猫耳 FM', '映客',
         '克拉克拉', '小红书', 'SHOWROOM', 'CHZZK', 'Kick', 'LiveMe', 'TikTok LIVE', 'YouTube Live', 'Bigo Live', 'PandaTV', 'FC2 Live',
         'Steam Broadcasts', '京东直播', '酷狗直播', '百度直播', '六间房直播', 'LOOK 直播', '17LIVE', 'niconico', '微博直播', '网络']
link = (rail + '<div style="position:absolute;left:80px;right:0;top:0;bottom:0;padding:8px 0">'
        '<div style="display:flex;align-items:center;padding:0 16px"><span style="font:500 9px \'Noto Sans SC\'">在此粘贴或输入链接地址</span><span style="flex:1"></span>'
        '<span style="display:flex;align-items:center;gap:4px;padding:4px 8px;border-radius:10px;background:rgba(0,161,255,.1);font:400 10px \'Noto Sans SC\';color:#00A1FF">'
        '<i style="width:5px;height:5px;border-radius:3px;background:#00A1FF"></i>局域网服务已启动</span></div>'
        f'<div style="display:flex;justify-content:center;margin-top:30px"><div class="p-qr" style="padding:4px 4px 6px">{qr(120)}'
        f'<div style="font:600 12px \'Noto Sans SC\';margin-top:5px">http://192.168.1.5:8080/#/movie</div></div></div>'
        '<div style="padding:24px 16px 0"><div class="p-gt">支持的平台</div><div style="display:flex;flex-wrap:wrap;gap:4px">'
        + ''.join(f'<span class="p-chipx">{s}</span>' for s in sites) + '</div></div></div>')
OUT['v3-link'] = ptv(link)

# =====================================================================
# new design
# =====================================================================
N_CSS = '''
.t-page .col{position:absolute;left:48px;width:556px;top:84px;bottom:0;overflow:hidden;padding:0 8px;margin-left:-8px;-webkit-mask-image:linear-gradient(180deg,#000 calc(100% - 40px),transparent);mask-image:linear-gradient(180deg,#000 calc(100% - 40px),transparent)}
.t-page .qrc{position:absolute;right:48px;width:276px;top:84px}
.t-card .t-row{border-radius:12px}
.t-stat{display:inline-flex;align-items:center;gap:6px;height:32px;padding:0 12px;border-radius:16px;background:var(--scl);font:400 14px 'Noto Sans SC';color:var(--onv)}
.t-stat b{color:var(--on);font-weight:600;font-feature-settings:'tnum'}
.t-tagn{display:inline-flex;align-items:center;height:22px;padding:0 7px;border-radius:6px;font:600 13px 'Noto Sans SC'}
.t-tagn.net{background:rgba(110,200,140,.16);color:#8FD9A8}.t-tagn.loc{background:rgba(255,180,90,.16);color:#FFC27A}
.t-tagn.fmt{background:var(--sch);color:var(--onv)}
.t-sbtn{height:40px;padding:0 14px;border-radius:20px;display:inline-flex;align-items:center;gap:6px;font:500 15px 'Noto Sans SC';box-shadow:inset 0 0 0 1px var(--ov);color:var(--on);position:relative;white-space:nowrap;flex:none}
.t-sbtn .rx{font-size:18px}
.t-sbtn.fo{transform:scale(1.05)}
.t-sbtn.on{background:var(--sc);color:var(--osc);box-shadow:none}
.t-src{background:var(--scl);border-radius:16px;padding:12px 14px;margin-bottom:10px}
.t-src .h{display:flex;align-items:center;gap:10px}
.t-src .nm{font:600 17px 'Noto Sans SC'}
.t-src .u{font:400 14px 'Noto Sans SC';color:var(--onv);white-space:nowrap;overflow:hidden;text-overflow:ellipsis;margin-top:2px}
.t-src .ac{display:flex;gap:8px;margin-top:10px}
.t-dlgx{position:absolute;z-index:21;background:var(--sch);color:var(--on);border-radius:24px;padding:24px;box-shadow:0 8px 28px rgba(0,0,0,.5)}
.t-dlgx .h{display:flex;align-items:center;gap:10px;font:600 20px 'Noto Sans SC';margin-bottom:12px}
.t-dlgx .m{font:400 16px/1.5 'Noto Sans SC';color:var(--onv)}
.t-dlgx .bt{display:flex;justify-content:flex-end;gap:10px;margin-top:20px}
.t-tb{height:44px;padding:0 20px;border-radius:22px;display:inline-flex;align-items:center;font:600 16px 'Noto Sans SC';color:var(--primary);position:relative}
.t-tb.fo{transform:scale(1.05);background:rgba(160,202,253,.1)}
.t-tb.red{color:#FFB4AB}
.t-lab{font:400 14px 'Noto Sans SC';color:var(--onv);margin:10px 2px 6px}
.t-chipq{display:inline-flex;align-items:center;height:34px;padding:0 12px;border-radius:8px;box-shadow:inset 0 0 0 1px var(--ov);font:400 15px 'Noto Sans SC';color:var(--on)}
'''


def n_page(title, body, focus_back=False, action=''):
    bk = f'<span class="bk{" fo" if focus_back else ""}"{attrs(0 if False else None)}>{rx("ea64", 20)}返回</span>'
    return (f'<div class="t-page"><div class="t-appbar">{bk}<span class="t1">{title}</span><span style="flex:1"></span>{action}</div>{body}</div>')


def ntv(body, css=''):
    return page(960, 540, 2, f'<div class="fs t" style="--w:960px;--h:540px">{body}</div>', N_CSS + css)


def qr_card(n=None):
    return (f'<div class="qrc"><div class="t-qr"{attrs(n)}><div class="h">用手机编辑</div>{qr(150)}'
            '<div class="u">扫码打开手机网页：填写订阅地址、上传 m3u / txt 文件、填写请求头</div>'
            f'<div class="u" style="color:var(--on);margin-top:6px">{QR_URL}</div>'
            '<div style="display:flex;align-items:center;gap:6px;margin-top:10px;font:400 14px \'Noto Sans SC\';color:#8FD9A8"><i style="width:8px;height:8px;border-radius:4px;background:#8FD9A8;display:inline-block"></i>局域网服务已启动</div></div></div>')


def srow(icon, title, sub=None, trail='chev', n=None, focus=False, tag=None, subcls=''):
    t = {'chev': rx('ea6e', 22, 'color:var(--onv)'), 'on': '<div class="t-sw on"></div>', 'off': '<div class="t-sw"></div>'}.get(trail, trail or '')
    s = f'<div class="b{subcls}">{sub}</div>' if sub else ''
    return (f'<div class="t-row{" fo" if focus else ""}"{attrs(n, tag)}><span class="ic">{icon}</span>'
            f'<div class="x"><div class="a">{title}</div>{s}</div>{t}</div>')


def sgroup(title, rows):
    return f'<div class="t-sec">{title}</div><div class="t-card">{rows}</div>'


def iptv_body(focus=1):
    f = lambda k: focus == k
    return (sgroup('IPTV管理', srow(rx('eb9d', 22), '订阅源管理', '3 个订阅源 · 查看、同步、删除', n=1, focus=f(1))
                   + srow(mr('live_tv', 22), '热门资源地址', '自定义“热门”频道的订阅地址，留空使用内置默认源', n=2, focus=f(2), tag='keep'))
            + sgroup('自动化周期同步设置', srow(rx('f064', 22), '启动时全自动同步', '应用冷启动时自动在后台静默检查并更新网络资源', 'on', n=3, focus=f(3))
                     + srow(rx('f20f', 22), '自动同步检查间隔', '当前每隔 6 小时进行一次同步', n=4, focus=f(4))
                     + srow(mr('cloud_sync', 22), '同步', '同步所有开启了自动同步的网络资源', n=5, focus=f(5), tag='keep'))
            + sgroup('直播源请求头', srow(rx('f237', 22), '自定义直播源请求头', 'Mozilla/5.0 (Linux; Android 12) …', n=6, focus=f(6))
                     + srow(rx('eeaf', 22), 'Referer 请求头', '未设置', n=7, focus=f(7), tag='keep')
                     + srow(rx('f67c', 22), 'Cookie 请求头', '未设置', n=8, focus=f(8), tag='keep'))
            + sgroup('播放源设置', srow(rx('ec54', 22), '导入播放源', 'M3U / TXT', n=9, focus=f(9)))
            + sgroup('EPG 电视节目单设置', srow(rx('ecc9', 22), '导入节目单源', 'XML / GZ / JSON', n=10, focus=f(10), tag='add')
                     + srow(rx('f235', 22), '当前启用的 EPG 数据源', '点击选择一个节目单源', n=11, focus=f(11), tag='add', subcls='" style="color:#FFC27A')))


# ---- v4-iptv: one page, the phone's groups; the QR column stays on the right
OUT['v4-iptv'] = ntv(n_page('IPTV 设置', f'<div class="col">{iptv_body(1)}</div>' + qr_card()))
OUT['v4-iptv-full'] = page(620, 1400, 2, f'<div class="win t" style="--w:620px;--h:1400px;height:auto;background:var(--surface);padding:28px 32px 24px">'
                           f'<div style="font:600 22px \'Noto Sans SC\';margin-bottom:6px">IPTV 设置</div>{iptv_body(None)}</div>', N_CSS, crop=True)


# ---- v4-sources: 订阅源管理 (v3 IptvManagePage, TV size)
def src(name, url, net=True, fmt='M3U', kind='IPTV', auto=True, focus=None, n0=None):
    icon = rx('f00d', 24) if kind == 'IPTV' else rx('f235', 24)
    tags = (f'<span class="t-tagn {"net" if net else "loc"}">{"网络" if net else "本地"}</span><span class="t-tagn fmt">{kind} · {fmt}</span>')
    acts = ''
    if net:
        acts += f'<span class="t-sbtn{" fo" if focus == 0 else ""}"{attrs(n0)}>{rx("ec56")}同步</span>'
        acts += f'<span class="t-sbtn{" on" if auto else ""}{" fo" if focus == 1 else ""}"{attrs(n0 + 1 if n0 else None)}>{rx("f074")}自动同步{" 开" if auto else " 关"}</span>'
    acts += f'<span class="t-sbtn{" fo" if focus == 2 else ""}"{attrs(n0 + 2 if n0 else None)}>{rx("ec26")}删除</span>'
    return (f'<div class="t-src"><div class="h"><span style="color:var(--primary)">{icon}</span><span class="nm">{name}</span>{tags}</div>'
            f'<div class="u">{url}</div><div class="ac">{acts}</div></div>')


stats = ('<div style="display:flex;gap:8px;margin:2px 0 4px"><span class="t-stat">IPTV <b>2</b></span><span class="t-stat">EPG <b>1</b></span>'
         '<span class="t-stat">网络 <b>2</b></span></div>')
srcs = (stats + f'<div class="t-sec">{rx("edcf", 16)} 网络资源</div>'
        + src('央视频道', 'https://example.com/iptv/cctv.m3u', focus=0, n0=2)
        + src('全国节目单', 'https://example.com/epg/e.xml.gz', fmt='XML', kind='EPG', auto=False)
        + f'<div class="t-sec">{rx("ed52", 16)} 本地资源</div>' + src('本地导入的列表', '/storage/emulated/0/Download/live.txt', net=False, fmt='TXT'))
sync_all = f'<span class="t-sbtn"{attrs(1)}>{rx("f064")}全部同步</span>'
OUT['v4-sources'] = ntv(n_page('订阅源管理', f'<div class="col">{srcs}</div>' + qr_card(), action=sync_all))

# ---- v4-import: 导入播放源 -> the phone's choice dialog; TV has no file picker, so the file comes from the phone
scrim = '<div class="scrim"></div>'
imp_dlg = (scrim + '<div class="t-dlgx" style="left:230px;top:118px;width:500px">'
           f'<div class="h">{rx("f00f", 24, "color:var(--primary)")}导入播放列表 (M3U / TXT)</div>'
           '<div class="t-card" style="background:transparent;padding:0">'
           + srow(rx('edcf', 22, 'color:var(--primary)'), '网络导入', '输入播放列表地址（遥控器）', n=1, focus=True)
           + srow(rx('f15a', 22, 'color:var(--primary)'), '用手机导入', '扫码，在手机上填写地址或上传文件', n=2, tag='chg')
           + f'</div><div class="bt"><span class="t-tb"{attrs(3)}>取消</span></div></div>')
OUT['v4-import'] = ntv(n_page('IPTV 设置', f'<div class="col">{iptv_body(9)}</div>' + qr_card()) + imp_dlg)

# ---- v4-import-url: the phone's 网络导入 dialog (请输入下载地址; 下载地址, 文件名)
url_dlg = (scrim + '<div class="t-dlgx" style="left:190px;top:76px;width:580px">'
           f'<div class="h">{rx("edcf", 24, "color:var(--primary)")}请输入下载地址</div>'
           '<div class="t-lab">下载地址</div>'
           f'<div class="t-in fo"{attrs(1)} style="color:var(--on)">https://example.com/iptv/cctv.m3u<span style="width:2px;height:22px;background:var(--primary);margin-left:2px"></span></div>'
           '<div class="t-lab">文件名</div>'
           f'<div class="t-in"{attrs(2)}>央视频道</div>'
           '<div style="display:flex;align-items:center;gap:10px;margin-top:14px;font:400 14px/1.45 \'Noto Sans SC\';color:var(--onv)">'
           f'{rx("f15a", 20)}遥控器打字不方便时，扫右边的码在手机上填写，填好会自动出现在这里</div>'
           f'<div class="bt"><span class="t-tb"{attrs(3)}>取消</span><span class="t-tb"{attrs(4)}>确认</span></div></div>')
OUT['v4-import-url'] = ntv(n_page('IPTV 设置', f'<div class="col">{iptv_body(9)}</div>' + qr_card()) + url_dlg)

# ---- v4-ua: the phone's User-Agent dialog (修改请求头 (User-Agent)) with 清除 / 取消 / 确认
ua_dlg = (scrim + '<div class="t-dlgx" style="left:190px;top:90px;width:580px">'
          f'<div class="h">修改请求头 (User-Agent)</div>'
          '<div class="m">设置自定义UA以解决部分直播源返回444或403拒绝访问的问题</div>'
          f'<div class="t-in fo" style="margin-top:14px;color:var(--on);height:auto;min-height:48px;padding:10px 14px;line-height:1.45"{attrs(1)}>Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36</div>'
          f'<div class="bt"><span class="t-tb red" style="margin-right:auto"{attrs(2)}>清除</span><span class="t-tb"{attrs(3)}>取消</span><span class="t-tb"{attrs(4)}>确认</span></div></div>')
OUT['v4-ua'] = ntv(n_page('IPTV 设置', f'<div class="col">{iptv_body(6)}</div>' + qr_card()) + ua_dlg)

# ---- v4-confirm: delete a source; focus starts on 取消
cf = (scrim + '<div class="t-dlgx" style="left:250px;top:150px;width:460px">'
      '<div class="h">确认删除</div><div class="m">“央视频道”<br><br>你确定要删除这个订阅源吗？这将连带清空其下的所有频道和节目数据，且无法撤销。</div>'
      '<div class="bt"><span class="t-tb fo">取消</span><span class="t-tb red">确认</span></div></div>')
OUT['v4-confirm'] = ntv(n_page('订阅源管理', f'<div class="col">{srcs}</div>' + qr_card(), action=sync_all.replace(attrs(1), '')).replace(' fo"', '"') + cf)


# ---- v4-guide: an IPTV channel in the TV room: 播放设置 -> 节目单 (U.2g component, TV size), watching catch-up
def gd_row(t, title, kind, cur=False, focus=False, n=None):
    right = {'cb': f'<span style="display:flex;align-items:center;gap:4px;color:var(--onv);font:400 15px \'Noto Sans SC\'">{rx("ee17", 20)}回看</span>',
             'now': '<span style="font:600 15px \'Noto Sans SC\';color:var(--primary)">回看中</span>',
             'live': f'<span class="t-tag live" style="height:26px">{rx("eec0", 16)}正在直播</span>',
             'next': ''}[kind]
    st = 'background:rgba(160,202,253,.1);box-shadow:inset 3px 0 0 var(--primary)' if cur else ''
    return (f'<div class="t-row{" fo" if focus else ""}" style="{st}"{attrs(n)}><span style="font:400 16px \'Noto Sans SC\';color:var(--onv);width:52px;font-feature-settings:\'tnum\'">{t}</span>'
            f'<div class="x"><div class="a" style="font-size:16px">{title}</div></div>{right}</div>')


gbody = ('<div class="t-grp" style="background:var(--pc);color:var(--opc);display:flex;align-items:center;padding:12px 14px;gap:10px;margin-top:4px">'
         '<div style="flex:1"><div style="font:400 14px \'Noto Sans SC\'">正在回看 · 今天 19:30</div><div style="font:600 16px \'Noto Sans SC\';margin-top:2px">候鸟迁徙（第 2 集）</div></div>'
         f'<span class="t-btn fill" style="height:40px;padding:0 14px;font-size:15px;flex:none"{attrs(1)}>{rx("eec0", 18)}返回直播</span></div>'
         '<div style="font:600 15px \'Noto Sans SC\';padding:12px 4px 4px">今天 · 10月1日 周四</div>'
         + gd_row('18:30', '城市的夜晚', 'cb', focus=True, n=2) + gd_row('19:30', '候鸟迁徙（第 2 集）', 'now', cur=True)
         + gd_row('20:30', '海岸线（第 2 集）', 'cb') + gd_row('21:30', '江河万里（第 3 集）', 'live', n=3) + gd_row('22:20', '森林的秘密（第 2 集）', 'next'))
gpanel = (f'<div class="t-side"><div class="t-ph"><span class="bk">{rx("ea64", 22)}</span><span class="t1">节目单</span><span class="lk">可回看 2 天</span></div>'
          f'<div class="t-body">{gbody}</div><div class="t-hint">↑↓ 选择 · OK 回看或返回直播 · 返回 回到播放设置</div></div>')
badge = (f'<div style="position:absolute;left:48px;top:28px;z-index:6;display:flex;align-items:center;gap:6px;height:34px;padding:0 6px 0 10px;border-radius:17px;background:rgba(0,0,0,.6);color:#fff;font:600 15px \'Noto Sans SC\'">'
         f'{rx("ee17", 18)}回看 19:30<span style="height:26px;padding:0 10px;border-radius:13px;background:#fff;color:#191C20;display:flex;align-items:center;font-size:14px">返回直播</span></div>')
OUT['v4-guide'] = page(960, 540, 2, frame(badge + gpanel, img=IMG_TV, pos='center'), N_CSS)

# ---- v4-link: 链接放映 (TV only), the phone toolbox's parser behind it
NRAIL = [('favorite_border', '关注'), ('local_fire_department', '热门'), ('category', '分区'), ('movie_creation', '链接放映'),
         ('search', '搜索'), ('history', '历史'), ('settings', '设置')]
nrail = '<div class="t-rail">' + ''.join(f'<div class="ri{" on" if l == "链接放映" else ""}">{mo(i, 22)}<span>{l}</span></div>' for i, l in NRAIL) + '</div>'
PHONE_SITES = ['哔哩哔哩', '虎牙直播', '斗鱼直播', '抖音直播/视频', '快手直播', '网易CC直播', 'Twitch直播', 'SOOP直播', 'YY直播', 'AcFun直播', 'Picarto',
               'TwitCasting', 'CHZZK', 'Kick', '17LIVE']


def link_page(state='idle', focus='in'):
    status = {'idle': ('#8FD9A8', '局域网服务已启动'), 'starting': ('var(--onv)', '正在启动服务...'), 'stopped': ('#FFB4AB', '服务未启动')}
    col, txt = status['stopped' if state == 'stopped' else ('starting' if state == 'starting' else 'idle')]
    qrblock = (qr(170) if state not in ('stopped', 'starting') else
               f'<div style="width:182px;height:182px;border-radius:10px;background:var(--sch);display:grid;place-items:center;color:var(--onv)">'
               + ('<div class="t-spin" style="width:32px;height:32px"></div>' if state == 'starting' else rx('f2c2', 40)) + '</div>')
    msg = ''
    if state == 'parsing':
        msg = '<div style="display:flex;align-items:center;gap:8px;margin-top:10px;font:400 15px \'Noto Sans SC\';color:var(--on)"><div class="t-spin" style="width:18px;height:18px"></div>收到手机发来的链接，正在解析…</div>'
    if state == 'failed':
        msg = f'<div style="display:flex;align-items:center;gap:8px;margin-top:10px;font:400 15px \'Noto Sans SC\';color:#FFB4AB">{rx("eca1", 20)}解析失败，请检查链接格式</div>'
    infield = ('https://live.bilibili.com/21452505' if state in ('parsing', 'failed') else '请在此处粘贴平台链接...')
    retry = f'<span class="t-sbtn fo" style="margin-top:12px"{attrs(3)}>{rx("f064")}重试</span>' if state == 'stopped' else ''
    body = (nrail + '<div style="position:absolute;left:136px;right:48px;top:28px;bottom:28px">'
            '<div style="display:flex;align-items:center;gap:12px"><span style="font:600 22px \'Noto Sans SC\'">链接放映</span>'
            f'<span style="display:flex;align-items:center;gap:6px;font:400 14px \'Noto Sans SC\';color:{col}"><i style="width:8px;height:8px;border-radius:4px;background:{col};display:inline-block"></i>{txt}</span></div>'
            '<div style="display:flex;gap:28px;margin-top:18px">'
            f'<div class="t-qr" style="width:250px;flex:none"><div class="h">用手机发送链接</div>{qrblock}'
            '<div class="u">扫码打开手机网页，粘贴直播间链接后发送，电视直接打开</div>'
            f'<div class="u" style="color:var(--on);margin-top:6px">http://192.168.1.5:8080/#/movie</div>{retry}</div>'
            '<div style="flex:1;min-width:0"><div class="t-lab" style="margin-top:0">或者用遥控器输入</div>'
            f'<div class="t-in{" fo" if focus == "in" else ""}" style="{"color:var(--on)" if state in ("parsing", "failed") else ""}"{attrs(1)}>{infield}</div>{msg}'
            f'<div class="t-lab" style="margin-top:18px">支持解析列表</div><div style="display:flex;flex-wrap:wrap;gap:6px"{attrs(2)}>'
            + ''.join(f'<span class="t-chipq">{s}</span>' for s in PHONE_SITES) + '</div></div></div></div>')
    return frame(f'<div class="t-page">{body}</div>', img=None)


OUT['v4-link'] = page(960, 540, 2, link_page(), N_CSS)
cells = [('服务启动中', '二维码位置先转圈', link_page('starting', None)),
         ('正在解析', '手机发来链接，或遥控器输入后按 OK', link_page('parsing', None)),
         ('解析失败', '写在输入框下面，不只弹提示条', link_page('failed', 'in')),
         ('服务未启动', '端口被占用等；可以重试', link_page('stopped', None))]
OUT['v4-link-states'] = sheet('新设计：链接放映的几种状态', cells).replace('</style>', N_CSS + '</style>', 1)

for name, html in OUT.items():
    open(os.path.join(HERE, name + '.html'), 'w', encoding='utf-8').write(html)
print(len(OUT), 'pages')
