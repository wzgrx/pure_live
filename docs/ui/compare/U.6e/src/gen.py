"""U.6e data settings: v3 restored and the new design.
v3 (tag v3.2.11): lib/modules/settings/pages/cache_data_settings_page.dart,
local_config_preveiw.dart (flutter_json 0.2.0 JsonWidget defaults:
32 px rows, bold, keys primary, numbers #199B4D, strings #CD44D9, booleans
orange, objects grey), common/widgets/app_status_view.dart, the GetX
snackbar defaults in lib/get/get_navigation/src/extension_navigation.dart:413-433.
    python3 docs/ui/compare/U.6e/src/gen.py && python3 tools/ui/mock/render.py docs/ui/compare/U.6e/src/ --annotate"""
import os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from smock import *  # noqa: E402,F401,F403

EXTRA = '''
.spin{width:18px;height:18px;border-radius:50%;border:2px solid var(--primary);border-right-color:transparent;flex:none}
.spin.err{border-color:var(--error);border-right-color:transparent}
.gsnack{position:absolute;left:10px;right:10px;bottom:24px;border-radius:15px;background:rgba(158,158,158,.2);padding:16px;color:#000;box-shadow:inset 0 0 0 1px rgba(0,0,0,.03)}
.gsnack b{display:block;font-weight:800;font-size:14px}.gsnack span{font-weight:300;font-size:14px}
.blurbg{position:absolute;inset:0;background:linear-gradient(180deg,#F8F9FF,#ECEEF4)}
.v3sum{margin:12px 16px 8px;padding:12px;background:var(--surface);border-radius:16px;box-shadow:inset 0 0 0 .5px rgba(195,199,207,.6)}
.v3sum .hd{display:flex;gap:10px;align-items:flex-start}
.v3sum .av{width:40px;height:40px;border-radius:20px;background:var(--pc);color:var(--opc);display:grid;place-items:center}
.v3sum .vt{font-size:11px;font-weight:700;color:var(--osc);background:var(--sc);border-radius:6px;padding:2px 6px;display:inline-block;margin-top:4px}
.v3sum .ln{height:.5px;background:rgba(195,199,207,.8);margin:12px 0}
.v3sum .grid{display:grid;gap:8px}
.v3sum .m{display:flex;gap:8px;padding:8px 10px;border-radius:10px;background:var(--scl)}
.v3sum .m b{display:block;font-size:12px;font-weight:700;color:var(--primary)}.v3sum .m span{font-size:11px;color:rgba(0,0,0,.6);line-height:1.2}
.jbox{margin:0 16px;padding:16px;background:var(--surface);border-radius:24px;box-shadow:0 2px 8px rgba(0,0,0,.03),inset 0 0 0 .5px rgba(195,199,207,.9);overflow:hidden}
.jn{display:flex;align-items:center;min-height:32px;font-size:13px;font-weight:700;padding-right:8px;white-space:nowrap;overflow:hidden}
.jn .k{color:var(--primary)}.jn .n{color:#199B4D}.jn .s{color:#CD44D9}.jn .b{color:#FF9800}.jn .o{color:#9E9E9E}
.jn .mi{font-size:24px;color:var(--on)}
.sum4{display:grid;gap:8px;padding:0 12px}
.stat{background:var(--scl);border-radius:16px;padding:12px 14px}
.stat b{display:block;font:600 22px/1.2 'Geist','Noto Sans SC';font-feature-settings:'tnum'}.stat span{font-size:12px;color:var(--onv)}
.jn4{display:flex;align-items:center;min-height:32px;font-size:13px;padding:0 20px;white-space:nowrap;overflow:hidden;font-family:'Geist','Noto Sans SC'}
.jn4 .k{color:var(--primary);font-weight:600}.jn4 .n{color:#1E7B3A}.jn4 .s{color:#8E3A96}.jn4 .b{color:#B26A00}.jn4 .o{color:var(--onv)}
.jn4 .mr{font-size:20px;color:var(--onv);margin-left:-4px;margin-right:2px}
.stv{display:flex;flex-direction:column;align-items:center;justify-content:center;text-align:center;gap:6px;padding:0 28px}
.stv .ring{width:86px;height:86px;border-radius:43px;background:#F5F6FC;display:grid;place-items:center;border:none;margin-bottom:14px}
.toastcell{position:relative;height:140px;width:361px}
.swr .x{min-width:0}.path{word-break:break-all}
'''


def P(w, h, s, body, **k):
    return page(w, h, s, body, extra_css=EXTRA, **k)


C = {
    'clear_d': '删除临时缩略图和表情文件；保留录制、下载、字体和 IPTV 数据',
    'thumb_d': '清除图片缓存并重新加载当前页面封面',
    'confirm_t': '确认清空本地缓存？', 'confirm_d': '将删除临时缩略图和表情文件；录制、下载、字体和 IPTV 数据会完整保留。',
    'path': '/storage/emulated/0/Android/data/com.mystyle.purelive/files/Download/pure_live',
}


# ======================================================================
# 缓存与数据管理 (cache_data_settings_page.dart)
# ======================================================================
def v3_cache_groups(custom=False):
    size = ('<span style="display:flex;align-items:center;gap:8px;flex:none"><span style="font-size:12px;font-weight:600;color:var(--primary)">12.34 MB</span>'
            + rx('f064', 16, 'color:rgba(0,0,0,.6)') + '</span>')
    rows = [v3tile(rx('ec16', 22), '当前缓存大小', None, size),
            v3tile(rx('ee45', 22), '刷新直播缩略图', C['thumb_d'], mr('refresh', 24, 'color:var(--onv)')),
            v3tile(rx('ec26', 22), '清空本地缓存', C['clear_d'], rx('ec26', 24, 'color:var(--error)'), long=True),
            v3tile(rx('ed52', 22), '下载目录', 'D:/Videos/PureLive' if custom else '当前使用默认目录', long=True)]
    if custom:
        rows.append(v3tile(rx('f064', 22), '恢复默认', None))
    return v3gt('缓存与数据管理') + v3card(rows)


def v4_cache_groups(n=True, custom=False):
    N = (lambda k: k) if n else (lambda k: None)
    size = (f'<div class="swr"{nattr(N(1), "chg", "tl")}><div class="x"><div class="a">当前缓存大小</div><div class="b">临时缩略图和表情文件；点一下重新计算</div></div>'
            '<span class="val">12.34 MB</span>' + rx('f064', 20, 'color:var(--onv)') + '</div>')
    b = sec('缓存') + grp([
        size,
        link('刷新直播缩略图', C['thumb_d'], '', N(2), chev=False),
        link('清空本地缓存', C['clear_d'], '', N(3), 'chg', chev=False, cls='danger'),
    ])
    path = 'D:/Videos/PureLive' if custom else C['path']
    b += sec('下载') + grp([
        link('下载目录', f'<span class="path">{path}</span>', '自定义' if custom else '默认', N(4), 'chg'),
        link('恢复默认下载目录', None, '', N(5), 'chg', chev=False, dis=not custom, why=None if custom else '现在用的就是默认目录'),
    ])
    b += note('下载目录用于安装包、下载的文件和字体；录制文件的位置在录制设置里。')
    return b


def v3_cache():
    return P(393, 852, 3, v3bar('缓存与数据管理') + f'<div class="v3body">{v3_cache_groups()}</div>')


def v4_cache():
    return P(393, 852, 3, bar('缓存与数据管理') + f'<div class="nbody">{v4_cache_groups()}</div>')


def v3_cache_wide():
    return P(1280, 800, 1.5, v3bar('缓存与数据管理') + f'<div class="v3body"><div class="v3wrap">{v3_cache_groups(custom=True)}</div></div>', frame='win')


def v4_cache_wide():
    return P(1280, 800, 1.5, bar('缓存与数据管理') + f'<div class="nbody"><div class="nwrap">{v4_cache_groups(n=False, custom=True)}</div></div>', frame='win')


def v3_cache_land():
    return P(852, 393, 2, v3bar('缓存与数据管理') + f'<div class="v3body" style="overflow:hidden">{v3_cache_groups()}</div>', frame='win')


def v4_cache_land():
    return P(852, 393, 2, bar('缓存与数据管理') + f'<div class="nbody" style="overflow:hidden"><div class="nwrap">{v4_cache_groups(n=False)}</div></div>', frame='win')


# ======================================================================
# 本地配置预览 (local_config_preveiw.dart)
# ======================================================================
JSON = [  # (depth, key, value, kind, expanded)
    (0, None, 'Object', 'o', True),
    (1, 'backupVersion', '3', 'n', None), (1, 'sensitiveDataIncluded', 'false', 'b', None),
    (1, 'app', 'Object', 'o', True),
    (2, 'autoRefreshTime', '3', 'n', None), (2, 'enableDenseFavorites', 'true', 'b', None), (2, 'enableBackgroundPlay', 'false', 'b', None),
    (2, 'enableAsmrSleepMode', 'false', 'b', None), (2, 'asmrSleepMinutes', '60', 'n', None), (2, 'enableRotateScreen', 'false', 'b', None),
    (2, 'enableScreenKeepOn', 'true', 'b', None), (2, 'enableAutoCheckUpdate', 'true', 'b', None), (2, 'useGitHubOriginForUpdates', 'false', 'b', None),
    (2, 'enableFullScreenDefault', 'false', 'b', None), (2, 'showSplashPage', 'true', 'b', None), (2, 'refreshRateMode', '"powerSaving"', 's', None),
    (2, 'enableHighRefreshRate', 'false', 'b', None), (2, 'preferRealOnlineCounts', 'false', 'b', None),
    (2, 'realOnlinePlatforms', 'Array&lt;String&gt;[8]', 'o', False), (2, 'savedMenuIds', 'Array&lt;String&gt;[4]', 'o', False),
    (2, 'enableMultiView', 'true', 'b', None), (2, 'enableNewWindowPlay', 'true', 'b', None),
    (1, 'theme', 'Object', 'o', True),
    (2, 'themeMode', '"system"', 's', None), (2, 'enableDynamicTheme', 'false', 'b', None), (2, 'themeColorSwitch', '"#2196F3"', 's', None),
    (2, 'language', '"zh"', 's', None), (2, 'crossAxisSpacing', '8.0', 'n', None), (2, 'mainAxisSpacing', '8.0', 'n', None),
    (1, 'roomCard', 'Object', 'o', True),
]


def v3_json_rows(limit=None):
    out = ''
    for d, k, v, kind, exp in JSON[:limit]:
        leaf = exp is None
        pad = 10 * d + (24 if leaf and d > 0 else 0)
        icon = '' if leaf else mi('keyboard_arrow_down' if exp else 'keyboard_arrow_right', 24)
        kk = f'<span class="k">{k}: </span>' if k else ''
        out += f'<div class="jn" style="padding-left:{pad + 8}px">{icon}<span>{kk}<span class="{kind}">{v}</span></span></div>'
    return out


def v4_json_rows(limit=None):
    out = ''
    for d, k, v, kind, exp in JSON[1:limit]:
        leaf = exp is None
        pad = 16 * (d - 1) + (20 if leaf else 0)
        icon = '' if leaf else mr('expand_more' if exp else 'chevron_right', 20)
        kk = f'<span class="k">{k}</span>: ' if k else ''
        out += f'<div class="jn4" style="padding-left:{20 + pad}px">{icon}<span>{kk}<span class="{kind}">{v}</span></span></div>'
    return out


def v3_summary(cols=1):
    items = [(rx('ee0b', 16, 'color:var(--primary)'), '128', '收藏直播间'), (rx('ee17', 16, 'color:var(--primary)'), '57', '历史记录'),
             (rx('f023', 16, 'color:var(--primary)'), '6', '标签'), (rx('ecef', 16, 'color:rgba(0,0,0,.6)'), '17', '配置模块')]
    m = ''.join(f'<div class="m"><span style="padding-top:2px">{ic}</span><div><b style="{"color:var(--on)" if lb == "配置模块" else ""}">{v}</b><span>{lb}</span></div></div>' for ic, v, lb in items)
    return (f'<div class="v3sum"><div class="hd"><span class="av">{rx("f0e6", 18)}</span><div><div style="font-size:14px;font-weight:700">本地备份配置</div>'
            f'<span class="vt">backup v3</span></div></div><div class="ln"></div><div class="grid" style="grid-template-columns:repeat({cols},1fr)">{m}</div></div>')


def v3_preview(w=393, h=852, scale=3, cols=1, box_h=525, frame='ph'):
    bar3 = '<div class="v3bar"><div class="bk">' + mi('arrow_back') + '</div><div class="t">本地配置预览</div></div>'
    body = (bar3 + f'<div style="background:#FFFFFF;height:{h}px">' + v3_summary(cols)
            + '<div style="padding:4px 16px 0">' + v3gt('本地配置原始预览') + '</div>'
            + f'<div class="jbox" style="height:{box_h}px">{v3_json_rows()}</div></div>')
    return P(w, h, scale, body, frame=frame)


def v4_summary(cols=2, n=True):
    items = [('128', '收藏直播间'), ('57', '历史记录'), ('6', '标签'), ('17', '配置模块')]
    st = ''.join(f'<div class="stat"><b>{v}</b><span>{lb}</span></div>' for v, lb in items)
    return (sec('概况') + f'<div class="sum4" style="grid-template-columns:repeat({cols},1fr)">{st}</div>'
            + note('备份格式 v3；这里不显示账号 Cookie 和 WebDAV 设置。'))


def v4_preview(w=393, h=852, scale=3, cols=2, n=True, frame='ph', limit=None):
    N = (lambda k: k) if n else (lambda k: None)
    acts = f'<div class="ib"{nattr(N(1), "add", "tr")}>{mr("settings_backup_restore", 24, "color:var(--onv)")}</div>'
    body = (bar('本地配置预览', acts) + '<div class="nbody"><div class="nwrap">' + v4_summary(cols, n)
            + sec('全部内容') + f'<div class="grp"{nattr(N(2), "chg", "tl")}><div style="padding:6px 0">{v4_json_rows(limit)}</div></div></div></div>')
    return P(w, h, scale, body, frame=frame)


def v4_preview_long():
    return P(393, 2400, 2, bar('本地配置预览', '<div class="ib">' + mr('settings_backup_restore', 24, 'color:var(--onv)') + '</div>')
             + '<div class="nbody">' + v4_summary(2) + sec('全部内容') + f'<div class="grp"><div style="padding:6px 0">{v4_json_rows()}</div></div></div>',
             crop=True, long=True)


# ======================================================================
# states and feedback
# ======================================================================
def board(cells, w=1290, h=2000):
    inner = ''.join(f'<div class="cell"><div class="cap">{cap}</div><div class="scr" style="padding:0;overflow:hidden">{html}</div></div>' for cap, html in cells)
    return P(w, h, 1.5, f'<div class="board" style="width:{w}px">{inner}</div>', crop=True, frame='none')


def phone_mini(content, title='', height=420, bg='var(--surface)'):
    t = '<div class="v3bar"><div class="bk">' + mi('arrow_back') + f'</div><div class="t">{title}</div></div>'
    return f'<div style="position:relative;width:393px;height:{height}px;background:{bg};overflow:hidden">{t}{content}</div>'


def v3_states():
    loading = phone_mini('<div style="position:absolute;inset:64px 0 0 0;display:grid;place-items:center"><span class="spin" style="width:24px;height:24px"></span></div>')
    err = phone_mini('<div class="stv" style="position:absolute;inset:64px 0 0 0"><div class="ring">' + mr('wifi_off', 42, 'color:rgba(54,97,142,.6)') + '</div>'
                     '<div style="font-size:15px;font-weight:600">FormatException: Unexpected character (at character 1)</div>'
                     '<div style="font-size:13px;color:rgba(0,0,0,.6);line-height:1.5">请检查您的网络连接或稍后再试</div></div>')
    confirm = ('<div style="padding:24px 16px;display:flex;justify-content:center;width:393px;background:rgba(0,0,0,.32)"><div class="dl3" style="width:361px"><div class="h">确认清空本地缓存？</div>'
               f'<div class="c" style="font-size:13px">{C["confirm_d"]}</div><div class="acts"><div class="tb">取消</div><div class="fb err">清除</div></div></div></div>')
    ok = phone_mini(v3_cache_groups() .replace('12.34 MB', '0.00 MB') + '<div class="gsnack"><b>完成</b><span>缓存已清除</span></div>', '缓存与数据管理', 620)
    part = phone_mini('<div class="blurbg"></div><div class="gsnack"><b>错误</b><span>部分缓存文件正在使用，剩余缓存：1.20 MB</span></div>', '缓存与数据管理', 200)
    dark = phone_mini('<div class="gsnack" style="background:rgba(158,158,158,.2)"><b>完成</b><span>缓存已清除</span></div>', '缓存与数据管理', 200, '#111418').replace('class="v3bar"', 'class="v3bar" style="background:#111418"').replace('class="t"', 'class="t" style="color:#E1E2E8"').replace('class="mi"', 'class="mi" style="color:#E1E2E8"', 1)
    return board([('本地配置预览：加载中（顶栏没有标题）', loading), ('本地配置预览：出错（原始报错当标题，“网络”提示不对，没有重试）', err),
                  ('清空本地缓存：确认', confirm), ('清除后：GetX 提示条，带“完成”标题，模糊底', ok),
                  ('部分没清掉', part), ('深色主题下：提示条的字固定是黑色', dark)])


def v4_states():
    loading = phone_mini('<div style="position:absolute;inset:64px 0 0 0;display:grid;place-items:center"><span class="spin" style="width:24px;height:24px"></span></div>', '本地配置预览')
    err = phone_mini('<div class="stv" style="position:absolute;inset:64px 0 0 0"><div class="ring">' + mr('error_outline', 42, 'color:var(--error)') + '</div>'
                     '<div style="font-size:15px;font-weight:600">读取本地配置失败</div>'
                     '<div style="font-size:13px;color:var(--onv);line-height:1.5">FormatException: Unexpected character (at character 1)</div>'
                     '<div data-n="3" data-tag="chg" style="margin-top:10px;height:40px;padding:0 16px;border-radius:20px;display:flex;align-items:center;gap:6px;color:var(--primary);font-size:14px;font-weight:600">'
                     + mr('refresh', 18) + '重新读取</div></div>', '本地配置预览')
    confirm = ('<div style="padding:24px 16px;display:flex;justify-content:center;width:393px;background:rgba(0,0,0,.32)">'
               + confirm_dialog('确认清空本地缓存？', C['confirm_d'] + '<br>现在约 12.34 MB。', ok='清除') + '</div>')
    busy = phone_mini('<div class="nbody">' + sec('缓存') + grp([
        link('当前缓存大小', '临时缩略图和表情文件', '12.34 MB', chev=False),
        link('刷新直播缩略图', C['thumb_d'], '', chev=False),
        '<div class="swr"><div class="x"><div class="a" style="color:var(--error)">清空本地缓存</div><div class="b">正在清除…</div></div><span class="spin err"></span></div>']) + '</div>', '缓存与数据管理', 420)
    ok = phone_mini('<div class="toast" style="bottom:28px">缓存已清除，释放 12.34 MB</div>', '缓存与数据管理', 200)
    part = phone_mini('<div class="toast" style="bottom:28px">部分缓存文件正在使用，剩余缓存：1.20 MB</div>', '缓存与数据管理', 200)
    return board([('本地配置预览：加载中（有标题）', loading), ('本地配置预览：出错（说清是什么、能重试）', err),
                  ('清空本地缓存：确认（写出现在多大）', confirm), ('清除中：这一行转圈，其他行照常', busy),
                  ('清除后：统一的提示条（深色主题跟着变）', ok), ('部分没清掉', part)])


OUT = {
    'v3-cache': v3_cache(), 'v4-cache': v4_cache(),
    'v3-cache-wide': v3_cache_wide(), 'v4-cache-wide': v4_cache_wide(),
    'v3-cache-land': v3_cache_land(), 'v4-cache-land': v4_cache_land(),
    'v3-preview': v3_preview(), 'v4-preview': v4_preview(),
    'v4-preview-full': v4_preview_long(),
    'v3-preview-wide': v3_preview(1280, 800, 1.5, cols=4, box_h=520, frame='win'),
    'v4-preview-wide': v4_preview(1280, 800, 1.5, cols=4, n=False, frame='win'),
    'v3-states': v3_states(), 'v4-states': v4_states(),
}
if __name__ == '__main__':
    for name, html in OUT.items():
        open(os.path.join(HERE, name + '.html'), 'w', encoding='utf-8').write(html)
    print(len(OUT), 'pages')
