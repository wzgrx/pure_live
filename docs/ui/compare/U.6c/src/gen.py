"""U.6c playback settings: v3 restored and the new design.
v3 (tag v3.2.11, lib/modules/settings/pages/): video_settings_page.dart,
player_kernel_settings_page.dart, mpv_option_page.dart,
portrait_live_settings_page.dart, pip_danmaku_settings_page.dart,
audience_metric_settings_page.dart; rows from
common/widgets/widget_extensions.dart; texts from assets/translations/zh.json.
    python3 docs/ui/compare/U.6c/src/gen.py && python3 tools/ui/mock/render.py docs/ui/compare/U.6c/src/ --annotate"""
import os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from smock import *  # noqa: E402,F401,F403

LOGO = '../../../packages/live_ui/assets/platforms/{}.png'
EXTRA = '''
.prev{position:relative;border-radius:16px;background:linear-gradient(135deg,#172033,#090B10);overflow:hidden}
.prev .dmw{position:absolute;white-space:nowrap;font-weight:500;text-shadow:0 0 1px #000,0 0 1px #000,0 0 1.5px #000}
.prev .off{position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);background:rgba(0,0,0,.54);color:#fff;border-radius:20px;padding:8px 14px;font-size:14px}
.prev .lbl{position:absolute;right:8px;bottom:6px;font-size:10px;color:rgba(255,255,255,.55)}
.swatch{width:22px;height:22px;border-radius:11px;background:#fff;box-shadow:inset 0 0 0 1px var(--ov);flex:none}
.vs{font-size:14px;color:var(--primary);margin-top:4px;font-weight:500}
.mini-logos{display:flex;flex-wrap:wrap;gap:6px;margin-top:8px}.mini-logos i{width:20px;height:20px;border-radius:5px;background:center/cover}
.cols{flex:1;display:flex;min-height:0}
.cols .l{flex:none;overflow:hidden;border-right:1px solid var(--ov)}
.cols .r{flex:1;overflow:hidden}
.v3cols .l{border-right:1px solid rgba(195,199,207,.6)}
.toastcell{position:relative;height:120px;width:361px}
.toastcell .toast{bottom:20px}
'''


def P(w, h, s, body, **k):
    return page(w, h, s, body, extra_css=EXTRA, **k)


def link_s(title, desc, val, n=None, tag=None, dis=False, why=None):
    """A choice row whose value does not fit on the right: the value moves under
    the description (v3 stacks trailing values on narrow rows the same way)."""
    d = f'<div class="b">{desc}</div>' if desc else ''
    w = f'<div class="why">{why}</div>' if why else ''
    return (f'<div class="swr{" dis" if dis else ""}"{nattr(n, tag, "tl")}><div class="x"><div class="a">{title}</div>{d}<div class="vs">{val}</div>{w}</div>'
            + mr('chevron_right', 20).replace('class="mr"', 'class="mr chev"') + '</div>')


# ======================================================================
# 视频设置 (video_settings_page.dart)
# ======================================================================
T = {
    'mute_sub': '所有直播间统一静音',
    'res_sub': '当进入直播播放页，首选的视频清晰度',
    'cell_sub': '使用流量时的默认画质',
    'portrait_sub': '自动识别直播源方向，并统一普通页、全屏和小窗的显示策略',
    'aud_sub': '在平台热度和真实在线人数之间切换，并单独管理支持的平台',
    'bg_sub': '暂时切出 APP 时继续播放；手动纯音频同样遵循此开关，自动助眠会话按计时继续',
    'asmr_sub': '开启后，进入新的直播间会自动切换为纯音频，并按下方时长停止播放；耳机按钮只切换当前直播间',
    'asmr_t_sub': '仅用于自动助眠；当前直播间的播放定时器在直播间菜单中单独设置',
    'float_sub': '返回时是否保留悬浮窗',
    'top_sub': '关闭后切换到其他应用时，小窗会按普通窗口层级被遮挡',
    'remember_sub': '下次进入小窗时恢复上次调整的尺寸与位置，并自动校正到当前可用显示器',
    'reset_sub': '清除已保存的小窗尺寸与位置，下次从应用所在显示器右下角打开',
    'fs_sub': '当进入直播播放页，自动进入全屏',
    'keep_sub': '当处于直播播放页，屏幕保持常亮',
    'dm_sub': '播放直播时默认开启弹幕显示',
    'pipdm_sub': '配置 Android 系统画中画、Windows 小窗和应用内悬浮窗的弹幕样式',
}


def v3_video_groups(android=True):
    g = v3gt('音频设置') + v3card([
        v3sw(rx('f2a2', 22), '全局静音', T['mute_sub'], False),
        v3slider(rx('efec', 22), '手机端默认音量', '50%', .5) if android else v3slider(rx('ebca', 22), '电脑端默认音量', '100%', 1),
    ]) + '<div class="v3gap"></div>'
    g += v3gt('画质设置') + v3card([
        v3tile(rx('ee02', 22), '首选清晰度', T['res_sub'], v3val('原画')),
        v3tile(rx('f12a', 22), '移动网络清晰度', T['cell_sub'], v3val('原画', 13)),
    ]) + '<div class="v3gap"></div>'
    beh = [v3tile(mr('stay_current_portrait', 22), '竖屏直播适配', T['portrait_sub'], 'chev24'),
           v3tile(mr('groups_2', 22), '观看数据与排行口径', T['aud_sub'], 'chev24')]
    if android:
        beh += [v3sw(rx('ef83', 22), '后台播放', T['bg_sub'], False, long=True),
                v3sw(rx('ef6f', 22), '新直播间自动助眠', T['asmr_sub'], False, long=True),
                v3tile(rx('f211', 22), '自动助眠播放时长', T['asmr_t_sub'], v3val('1 小时'))]
    beh.append(v3sw(rx('eff0', 22), '退出小窗播放', T['float_sub'], False))
    if not android:
        beh += [v3sw(rx('f039', 22), 'Windows 小窗始终置顶', T['top_sub'], False, long=True),
                v3sw(rx('f1f9', 22), '记住小窗位置和大小', T['remember_sub'], True),
                v3tile(rx('f07c', 22), '重置小窗位置和大小', T['reset_sub'])]
    beh.append(v3sw(rx('ed9c', 22), '自动全屏', T['fs_sub'], False))
    if android:
        beh.append(v3sw(rx('eea9', 22), '屏幕常亮', T['keep_sub'], True))
    g += v3gt('播放行为设置') + v3card(beh) + '<div class="v3gap"></div>'
    g += v3gt('弹幕设置') + v3card([
        v3sw(rx('eb6f', 22), '显示弹幕', T['dm_sub'], True),
        v3tile(rx('eff0', 22), '小窗弹幕', T['pipdm_sub'], 'chev24'),
        v3tile(rx('ed8d', 22), '更换弹幕字体', '当前字体: Default'),
        v3tile(rx('ed23', 22), '弹幕关键词过滤', None),
    ])
    return g


def v4_video_groups(android=True, n=True):
    N = (lambda k: k) if n else (lambda k: None)
    g = sec('音频设置') + grp([
        sw('全局静音', T['mute_sub'], False, N(1)),
        sl('手机端默认音量', '50%', .5, N(2)) if android else sl('电脑端默认音量', '100%', 1, N(2)),
    ])
    g += sec('画质设置') + grp([
        link('首选清晰度', T['res_sub'], '原画', N(3), 'chg'),
        link('移动网络清晰度', T['cell_sub'], '原画', N(4), 'chg'),
    ])
    beh = [sw('自动全屏', T['fs_sub'], False, N(5))]
    if android:
        beh.append(sw('屏幕常亮', T['keep_sub'], True, N(6)))
    beh += [link('竖屏直播适配', T['portrait_sub'], '', N(7)), link('观看数据与排行口径', T['aud_sub'], '', N(8))]
    g += sec('播放行为设置') + grp(beh)
    if android:
        g += sec('后台与助眠') + grp([
            sw('后台播放', T['bg_sub'], False, N(9)),
            sw('新直播间自动助眠', T['asmr_sub'], False, N(10)),
            link('自动助眠播放时长', T['asmr_t_sub'], '1 小时', N(11), 'chg', dis=True, why='打开“新直播间自动助眠”后生效'),
        ])
        mini = [sw('离开直播间时小窗播放', '返回离开直播间后，画面缩成应用内小窗继续播放', False, N(12), 'chg'),
                sw('离开应用时自动画中画', '切到桌面或其他应用时，正在播放的直播自动进入系统画中画', False, N(13), 'add'),
                link('小窗弹幕', '配置系统画中画、桌面小窗和应用内小窗的弹幕样式', '开', N(14), 'chg')]
        k = 15
    else:
        mini = [sw('离开直播间时小窗播放', '返回离开直播间后，画面缩成应用内小窗继续播放', False, N(9), 'chg'),
                sw('小窗始终置顶', T['top_sub'], False, N(10), 'chg'),
                sw('记住小窗位置和大小', T['remember_sub'], True, N(11), 'chg'),
                link('重置小窗位置和大小', T['reset_sub'], '', N(12), 'chg', chev=False),
                link('小窗弹幕', '配置系统画中画、桌面小窗和应用内小窗的弹幕样式', '开', N(13), 'chg')]
        k = 14
    g += sec('小窗') + grp(mini)
    g += sec('弹幕设置') + grp([
        sw('显示弹幕', T['dm_sub'], True, N(k)),
        link('弹幕样式', '字号、速度、透明度、显示范围；和直播间里的“弹幕设置”是同一个', '', N(k + 1), 'add'),
        link('更换弹幕字体', None, '默认', N(k + 2), 'chg'),
        link('弹幕关键词过滤', None, '', N(k + 3)),
    ])
    return g


def v3_video_phone():
    return P(393, 3200, 2, v3bar('视频设置') + f'<div class="v3body">{v3_video_groups(True)}</div>', crop=True, long=True)


def v4_video_phone():
    return P(393, 3200, 2, bar('视频设置') + f'<div class="nbody">{v4_video_groups(True)}</div>', crop=True, long=True)


def v3_video_wide():
    return P(1280, 800, 1.5, v3bar('视频设置') + f'<div class="v3body" style="overflow:hidden"><div class="v3wrap">{v3_video_groups(False)}</div></div>', frame='win')


def v4_video_wide():
    return P(1280, 800, 1.5, bar('视频设置') + f'<div class="nbody" style="overflow:hidden"><div class="nwrap">{v4_video_groups(False, n=False)}</div></div>', frame='win')


def v3_video_land():
    return P(852, 393, 2, v3bar('视频设置') + f'<div class="v3body" style="overflow:hidden">{v3_video_groups(True)}</div>', frame='win')


def v4_video_land():
    return P(852, 393, 2, bar('视频设置') + f'<div class="nbody" style="overflow:hidden"><div class="nwrap">{v4_video_groups(True, n=False)}</div></div>', frame='win')


# ======================================================================
# 播放内核设置 (player_kernel_settings_page.dart), Android with mpv
# ======================================================================
def v3_kernel():
    b = v3gt('核心内核设置') + v3card([
        v3tile(rx('f219', 22), '内核切换', '不同内核影响解码性能与兼容性', v3val('Mpv播放器')),
        v3tile(rx('edcf', 22), '网络代理设置', '配置播放器的网络请求代理', v3val('未开启', 13, 'rgba(0,0,0,.6)')),
        v3sw(rx('f371', 22), '开启硬解码', '优先使用 GPU 硬件解码', True),
        v3sw(rx('f126', 22), '播放器强制销毁', '彻底关闭播放进程以节省资源', False),
    ])
    b += '<div style="padding:12px 16px 0"><hr style="margin:8px 0;background:var(--ov)"></div>'
    b += v3sw(rx('f100', 22), '兼容模式', '旧设备播放卡顿时请尝试开启', False)
    b += (f'<div style="display:flex;align-items:center;gap:8px;padding:5px 12px 4px">{rx("ec9d", 18, "color:var(--primary)")}'
          '<span style="font-size:15px;font-weight:700;color:var(--primary)">MPV 高级设置</span></div>')
    b += ('<div style="padding:10px 16px"><div style="font-size:12px;line-height:16px;color:rgba(0,0,0,.65)">调整内核参数可能导致播放异常，详情请参考 '
          '<span style="display:inline-block;padding:16px 8px;color:var(--primary);font-weight:600;text-decoration:underline">MPV 官方文档</span></div>'
          f'<div style="height:12px"></div><div style="display:inline-flex;align-items:center;gap:4px;height:48px;padding:0 12px;color:#F44336;font-weight:600;font-size:14px">{rx("f064", 14)}重置</div></div>')
    b += v3card([
        v3sw(rx('eba7', 22), '自定义驱动与硬件加速', None, False),
        v3tile(rx('ef81', 22), '视频输出驱动(--vo)', 'GPU', 'rxchev'),
        v3tile(rx('f2a2', 22), '音频输出驱动(--ao)', '自动选择', 'rxchev'),
        v3tile(rx('ebf0', 22), '硬件解码器(--hwdec)', '启用任意可用解码器', 'rxchev'),
    ])
    return P(393, 2400, 2, v3bar('播放内核设置') + f'<div class="v3body">{b}</div>', crop=True, long=True)


def v4_kernel():
    why_cust = '打开“自定义驱动与硬件加速”后生效'
    b = sec('内核') + grp([
        link('内核切换', '不同内核影响解码性能与兼容性', 'Mpv播放器', 1),
        sw('播放器强制销毁', '彻底关闭播放进程以节省资源', False, 2),
    ])
    b += sec('解码') + grp([
        sw('开启硬解码', '优先使用 GPU 硬件解码', True, 3, 'chg'),
        sw('兼容模式', '旧设备播放卡顿时请尝试开启；打开后由系统解码，下面的硬解码和驱动设置不再起作用', False, 4, 'chg'),
    ])
    b += sec('网络') + grp([
        link('网络代理设置', '配置播放器的网络请求代理；在“网络与代理设置”里修改', '未开启', 5, 'chg'),
    ])
    b += sec('MPV 高级设置') + grp([
        sw('自定义驱动与硬件加速', '打开后用下面三项，代替“开启硬解码”', False, 6, 'chg'),
        link('视频输出驱动(--vo)', None, 'GPU', 7, 'chg', dis=True, why=why_cust),
        link('音频输出驱动(--ao)', None, '自动选择', 8, 'chg', dis=True, why=why_cust),
        link('硬件解码器(--hwdec)', None, '启用任意可用解码器', 9, 'chg', dis=True, why=why_cust),
    ])
    b += f'<div class="note"{nattr(10, "chg", "tl")}>调整内核参数可能导致播放异常，详情请参考 <a>MPV 官方文档</a></div>'
    b += '<div style="height:16px"></div>' + grp([link('恢复默认设置', '恢复本页的设置；视频设置里的首选清晰度不受影响', '', 11, 'chg', chev=False, cls='danger')])
    return P(393, 2400, 2, bar('播放内核设置') + f'<div class="nbody">{b}</div>', crop=True, long=True)


# ======================================================================
# MpvOptionPage: 硬件解码器(--hwdec) on Android
# ======================================================================
HWDEC = [('no', '关闭（软件解码）'), ('auto', '启用任意可用解码器'), ('auto-safe', '启用最佳解码器'), ('yes', '强制硬件解码'),
         ('auto-copy', '启用带拷贝功能的最佳解码器'), ('d3d11va', 'DirectX 11（Windows 8 及以上）'), ('d3d11va-copy', 'DirectX 11（非直通）'),
         ('videotoolbox', 'VideoToolbox（macOS / iOS）'), ('videotoolbox-copy', 'VideoToolbox（非直通）'), ('vaapi', 'VAAPI（Linux）'),
         ('vaapi-copy', 'VAAPI（非直通）'), ('nvdec', 'NVDEC（仅 NVIDIA）'), ('nvdec-copy', 'NVDEC（仅 NVIDIA，非直通）'), ('drm', 'DRM（Linux）'),
         ('drm-copy', 'DRM（非直通）'), ('vulkan', 'Vulkan（实验性）'), ('vulkan-copy', 'Vulkan（实验性，非直通）'), ('dxva2', 'DXVA2（Windows 7 及以上）'),
         ('dxva2-copy', 'DXVA2（非直通）'), ('vdpau', 'VDPAU（Linux）'), ('vdpau-copy', 'VDPAU（非直通）'), ('mediacodec', 'MediaCodec（Android）'),
         ('mediacodec-copy', 'MediaCodec（Android，非直通）'), ('cuda', 'CUDA（仅 NVIDIA，已过时）'), ('cuda-copy', 'CUDA（仅 NVIDIA，已过时，非直通）'),
         ('crystalhd', 'CrystalHD（已过时）'), ('rkmpp', 'Rockchip MPP（仅部分 Rockchip 芯片）')]
ANDROID_HWDEC = ['no', 'auto', 'auto-safe', 'yes', 'auto-copy', 'vulkan', 'vulkan-copy', 'mediacodec', 'mediacodec-copy']


def v3_mpv_option():
    rows = ''.join(f'<div style="display:flex;align-items:center;gap:14px;padding:14px 16px">'
                   + (mi('radio_button_checked', 22, 'color:var(--primary)') if k == 'auto' else mi('radio_button_unchecked', 22, 'color:var(--onv)'))
                   + f'<span style="font-size:14px;line-height:21px">{lb}</span></div>' for k, lb in HWDEC)
    return P(393, 2400, 2, v3bar('硬件解码器(--hwdec)') + f'<div class="v3body"><div class="v3card">{rows}</div></div>', crop=True, long=True)


def v4_mpv_option():
    lab = dict(HWDEC)
    rows = []
    for i, k in enumerate(ANDROID_HWDEC):
        on = k == 'auto'
        tag = '<span class="tagd">默认</span>' if k == 'auto' else ''
        rows.append(f'<div class="swr"' + (nattr(12, 'chg', 'tl') if i == 0 else '') + f'><div class="x"><div class="a" style="{"color:var(--primary);font-weight:600" if on else ""}">{lab[k]}{tag}</div></div>'
                    + (rx('eb7b', 20, 'color:var(--primary)') if on else '') + '</div>')
    b = note('只列出这台设备能用的解码器。打开“自定义驱动与硬件加速”后才生效。') + '<div style="height:8px"></div>' + grp(rows)
    return P(393, 1400, 2, bar('硬件解码器(--hwdec)') + f'<div class="nbody">{b}</div>', crop=True, long=True)


# ======================================================================
# 竖屏直播适配 (portrait_live_settings_page.dart)
# ======================================================================
PT = {
    'det': '根据解码后的真实画面尺寸稳定识别，切换线路和画质时自动防抖',
    'height': '竖屏源增大观看区域，同时保留足够的弹幕列表空间',
    'layout': '仅影响竖屏直播源，不改变普通横屏直播',
    'fs': '大屏和分屏设备自动交给系统布局，手机可跟随直播源',
    'disp': '仅影响竖屏直播的竖屏全屏，切换后立即生效，不改变横屏直播和小窗比例',
    'pip': '进入画中画前应用稳定比例，并限制在 Android 支持范围内',
    'dm': '独立限制竖屏源上的弹幕覆盖区域，不修改全局样式数值',
    'rem': '在播放器中手动指定方向后，下次进入同一直播间继续使用',
    'diag': '在画面上显示原始尺寸、比例、稳定状态和当前覆盖规则',
    'reset': '同时清除已记住的直播间方向',
}


def v3_portrait():
    b = v3gt('识别与普通页布局') + v3card([
        v3sw(mr('aspect_ratio', 22), '智能识别竖屏直播源', PT['det'], True, long=True),
        v3sw(mo('view_agenda', 22), '普通页自适应视频高度', PT['height'], True, long=True),
        v3tile(mo('dashboard_customize', 22), '普通页布局模式', PT['layout'], v3val('均衡（推荐）'), long=True),
    ]) + '<div class="v3gap"></div>'
    b += v3gt('全屏、小窗与弹幕') + v3card([
        v3tile(mr('fullscreen', 22), '进入全屏时的方向', PT['fs'], v3val('跟随直播源（推荐）'), long=True),
        v3tile(mr('fit_screen', 22), '竖屏全屏画面模式', PT['disp'], v3val('沉浸背景（推荐）'), long=True),
        v3sw(mr('picture_in_picture_alt', 22), '小窗跟随真实画面比例', PT['pip'], True, long=True),
        v3tile(mo('subtitles', 22), '竖屏弹幕布局', PT['dm'], v3val('跟随全局'), long=True),
        v3sw(mo('bookmark_added', 22), '记住单个直播间方向', PT['rem'], True, long=True),
    ]) + '<div class="v3gap"></div>'
    b += v3gt('诊断与恢复') + v3card([
        v3sw(mo('monitor_heart', 22), '显示识别状态', PT['diag'], False, long=True),
        v3tile(mr('restart_alt', 22), '恢复竖屏适配默认设置', PT['reset'], long=True),
    ])
    return P(393, 2400, 2, v3bar('竖屏直播适配') + f'<div class="v3body">{b}</div>', crop=True, long=True)


def v4_portrait():
    b = sec('识别与普通页布局') + grp([
        sw('智能识别竖屏直播源', PT['det'], True, 1),
        sw('普通页自适应视频高度', PT['height'], True, 2, 'chg'),
        link_s('普通页布局模式', PT['layout'], '均衡（推荐）', 3, 'chg'),
    ])
    b += sec('全屏、小窗与弹幕') + grp([
        link_s('进入全屏时的方向', PT['fs'], '跟随直播源（推荐）', 4, 'chg'),
        link_s('竖屏全屏画面模式', PT['disp'], '沉浸背景（推荐）', 5, 'chg'),
        sw('小窗跟随真实画面比例', PT['pip'], True, 6),
        link_s('竖屏弹幕布局', PT['dm'], '跟随全局', 7, 'chg'),
        sw('记住单个直播间方向', PT['rem'], True, 8),
    ])
    b += sec('诊断与恢复') + grp([
        sw('显示识别状态', PT['diag'], False, 9),
        link('恢复竖屏适配默认设置', PT['reset'], '', 10, 'chg', chev=False, cls='danger'),
    ])
    return P(393, 2400, 2, bar('竖屏直播适配') + f'<div class="nbody">{b}</div>', crop=True, long=True)


# ======================================================================
# 小窗弹幕 (pip_danmaku_settings_page.dart)
# ======================================================================
DM_COLORS = ['#FFFFFF', '#64B5F6', '#FFD54F', '#81C784']


def preview(w, h, size=12, disabled=False, n=None):
    """PipDanmakuPreview: the top half carries up to 6 lines; drawn as a still
    frame (the real one scrolls), laid out so no two lines overlap."""
    area = h * .5
    lane = size * 1.6
    lanes = max(1, int(area // lane))
    items = ''
    for i in range(6):
        col, row = divmod(i, lanes)
        x = (.04 + .52 * (col % 2) + .1 * (row % 3)) * w
        items += (f'<span class="dmw" style="left:{x:.0f}px;top:{row * lane + 2:.0f}px;font-size:{size}px;color:{DM_COLORS[i % 4]};opacity:.9">'
                  f'小窗弹幕预览 {i + 1}</span>')
    off = '<div class="off">小窗弹幕已关闭</div>' if disabled else ''
    return f'<div class="prev" style="width:{w}px;height:{h}px"{nattr(n)}>{items}{off}</div>'


def v3_pip_list():
    def s(title, on, sub=None):
        sb = f'<div style="font-size:12px;line-height:16px;color:var(--onv);margin-top:2px">{sub}</div>' if sub else ''
        return f'<div class="v3t swt" style="padding:0 8px 0 16px;min-height:{72 if sub else 56}px"><div class="x"><div class="a">{title}</div>{sb}</div><span class="sw{" on" if on else ""}"></span></div>'

    def sld(title, val, frac):
        return v3slider('', title, val, frac, badge='r20', pad='12px 16px')

    rows = [s('小窗显示弹幕', True), s('纯文字模式（隐藏表情）', False), s('根据小窗尺寸自动缩放', True), s('保留平台弹幕颜色', True)]
    card = '<div class="v3card">' + '<div class="v3hr"></div>'.join(rows)
    card += sld('字体大小', '12.0', .25) + sld('字体粗细', '稍粗', .5) + sld('滚动速度（像素/秒）', '90', .184) + sld('透明度', '90%', .889) + sld('画面顶部占用高度', '50%', .444)
    card += '<div class="v3t" style="padding:12px 16px"><div class="x"><div class="a">最大同时显示数量</div></div><div class="v3cnt"><i>' + mi('remove', 24) + '</i><b>6</b><i>' + mi('add', 24) + '</i></div></div>'
    card += sld('发送间隔', '0.35s', .154)
    card += s('弹幕帧率 · 跟随界面刷新率策略', True, '开启：小窗弹幕跟随同一全局档位；关闭：小窗使用独立手动帧率，不影响主画面。')
    card += '<div style="padding:0 16px 12px;color:var(--primary);font-weight:600;font-size:14px">30 FPS</div></div>'
    return v3gt('小窗弹幕') + '<div style="height:8px"></div>' + card


def v4_pip_list(n=True):
    N = (lambda k: k) if n else (lambda k: None)
    why_fps = '现在跟随“通用”里的“省电”档位'
    b = '<div style="height:8px"></div>' + grp([sw('小窗显示弹幕', None, True, N(1))])
    b += sec('样式') + grp([
        sl('透明度', '90%', .889, N(2)),
        sl('滚动速度（像素/秒）', '90 px/s', .184, N(3), 'chg'),
        sl('字体大小', '12.0 px', .25, N(4), 'chg'),
        sl('字体粗细', '稍粗', .5, N(5)),
        sw('根据小窗尺寸自动缩放', '小窗越小字越小，最小 10 px', True, N(6), 'chg'),
        sw('纯文字模式（隐藏表情）', None, False, N(7)),
        sw('保留平台弹幕颜色', None, True, N(8)),
        link('统一弹幕颜色', None, '#FFFFFFFF', N(9), 'chg', dis=True, why='关闭“保留平台弹幕颜色”后可选', lead='<span class="swatch"></span>'),
    ])
    b += sec('显示范围') + grp([
        sl('画面顶部占用高度', '50%', .444, N(10)),
        cnt('最大同时显示数量', '6', N(11), 'chg'),
        sl('发送间隔', '0.35 秒', .154, N(12), 'chg'),
    ])
    b += sec('流畅度') + grp([
        sw('弹幕帧率跟随界面刷新率', '开启：小窗弹幕跟随同一全局档位；关闭：小窗使用独立手动帧率，不影响主画面。', True, N(13), 'chg'),
        sl('弹幕帧率', '30 FPS', .067, N(14), 'chg', dis=True, why=why_fps),
    ])
    b += '<div style="height:16px"></div>' + grp([link('恢复小窗弹幕默认值', None, '', N(15), 'chg', chev=False, cls='danger')])
    return b


PIP_DESC3 = '配置 Android 系统画中画、Windows 小窗和应用内悬浮窗的弹幕样式'
PIP_DESC4 = '配置系统画中画、桌面小窗和应用内小窗的弹幕样式'


def v3_pip(full=False):
    top = (v3bar('小窗弹幕', mr('restart_alt', 24, 'margin:0 12px'))
           + f'<div style="padding:12px 16px 6px;font-size:12px;line-height:16px;color:var(--onv)">{PIP_DESC3}</div>'
           + '<div style="padding:4px 16px 8px">' + v3gt('样式预览') + '<div style="height:6px"></div>' + preview(361, 203) + '</div>'
           + '<div style="height:1px;background:var(--ov)"></div>')
    lst = f'<div style="padding:12px 16px 24px;{"" if full else "overflow:hidden"}">{v3_pip_list()}</div>'
    if full:
        return P(393, 2600, 2, top + lst, crop=True, long=True)
    return P(393, 852, 3, top + lst)


def v4_pip(full=False):
    top = (bar('小窗弹幕')
           + f'<div style="padding:8px 20px 6px;font-size:12px;line-height:16px;color:var(--onv)">{PIP_DESC4}</div>'
           + '<div style="padding:4px 16px 10px">' + preview(361, 203) + '</div>'
           + '<div style="height:1px;background:var(--ov)"></div>')
    lst = f'<div class="nbody" style="padding-top:0">{v4_pip_list(n=full)}</div>'
    if full:
        return P(393, 2600, 2, top + lst, crop=True, long=True)
    return P(393, 852, 3, '<div style="height:816px;overflow:hidden">' + top + lst + '</div>')


def v3_pip_wide():
    left = ('<div class="l" style="width:520px;padding:20px">'
            f'<div style="font-size:13px;line-height:20px;color:var(--onv)">{PIP_DESC3}</div><div style="height:20px"></div>'
            + v3gt('样式预览') + '<div style="height:8px"></div>' + preview(480, 270) + '</div>')
    right = f'<div class="r" style="padding:20px">{v3_pip_list()}</div>'
    return P(1280, 800, 1.5, v3bar('小窗弹幕', mr('restart_alt', 24, 'margin:0 12px')) + f'<div class="cols v3cols">{left}{right}</div>', frame='win')


def v4_pip_wide():
    left = (f'<div class="l" style="width:520px;padding:16px 20px"><div style="font-size:13px;line-height:20px;color:var(--onv)">{PIP_DESC4}</div>'
            '<div style="height:16px"></div>' + preview(480, 270) + '</div>')
    right = f'<div class="r"><div class="nwrap">{v4_pip_list(n=False)}</div></div>'
    return P(1280, 800, 1.5, bar('小窗弹幕') + f'<div class="cols">{left}{right}</div>', frame='win')


def v3_pip_narrow():
    top = (v3bar('小窗弹幕', mr('restart_alt', 24, 'margin:0 12px'))
           + f'<div style="padding:12px 16px 6px;font-size:12px;line-height:16px;color:var(--onv)">{PIP_DESC3}</div>'
           + '<div style="padding:4px 16px 8px">' + v3gt('样式预览') + '<div style="height:6px"></div><div style="display:flex;justify-content:center">' + preview(171, 96, 7.8) + '</div></div>'
           + '<div style="height:1px;background:var(--ov)"></div>')
    lst = f'<div style="padding:12px 16px;overflow:hidden;flex:1">{v3_pip_list()}</div>'
    return P(740, 360, 2, top + lst, frame='win')


def v4_pip_narrow():
    left = (f'<div class="l" style="width:300px;padding:8px 16px"><div style="font-size:12px;line-height:16px;color:var(--onv);margin-bottom:8px">{PIP_DESC4}</div>'
            + preview(268, 151, 10) + '</div>')
    right = f'<div class="r"><div class="nwrap">{v4_pip_list(n=False)}</div></div>'
    return P(740, 360, 2, bar('小窗弹幕') + f'<div class="cols">{left}{right}</div>', frame='win')


# ======================================================================
# 观看数据与排行口径 (audience_metric_settings_page.dart)
# ======================================================================
SRC = {'roomList': '来源：房间列表/详情，可直接排行', 'roomRealtime': '来源：进入直播间后的实时消息', 'no': '来源：平台公开接口未给出并发人数'}
V3_PLATFORMS = [  # (id, name, availability, detail)
    ('bilibili', '哔哩哔哩', 'no', '列表 online 与弹幕心跳是人气值；WATCHED_CHANGE 是本场累计看过，均与同时在线人数分开显示'),
    ('douyu', '斗鱼', 'no', '公开列表 ol/hot 按热度处理，暂不标记为真实人数'),
    ('huya', '虎牙', 'no', '当前列表/详情的 totalCount、userCount 与直播间 iAttendeeCount（URI 8006）实测均为热度；公开数据暂未提供独立并发人数'),
    ('douyin', '抖音', 'roomList', '推荐、搜索和房间数据优先读取顶层或嵌套 user_count 作为在线人数；display_value/total_user 只作为累计观看单独显示'),
    ('kuaishou', '快手', 'roomList', 'watchingCount 作为当前观看人数'),
    ('cc', '网易CC', 'roomList', 'webcc_visitor/hot_score/visitor 是同一平台热度口径；只有 vision_visitor/online_num 作为当前在线人数，两种数值分开保存和排行'),
    ('twitch', 'Twitch', 'roomList', '目录、搜索和直播间元数据的 viewersCount 均按当前并发观看人数显示'),
    ('soop', 'Soop', 'roomList', '推荐和搜索优先使用 total_view_cnt（PC + 移动端）；分类使用 view_cnt，缺少总数时才合并 PC/移动端字段，播放器详情缺值不写成 0'),
    ('yy', 'YY', 'no', '公开 users 字段按平台热度显示；当前网页接口未提供独立的并发在线人数'),
    ('acfun', 'AcFun 直播', 'roomList', '直播目录和房间详情使用 onlineCount；点赞和粉丝数单独保留，作者搜索不含在线人数'),
    ('picarto', 'Picarto', 'roomList', '目录和房间详情的 viewers 为在线人数，total_views 为累计观看，分别显示'),
    ('twitcasting', 'TwitCasting', 'roomList', '公开目录的 current_viewer_count 为在线人数；房间详情未提供该值，不与累计观看混用'),
    ('missevan', '猫耳 FM', 'no', '公开 score 是平台热度，未提供独立的并发在线人数'),
    ('inke', '映客', 'no', '公开目录与房间详情未提供已验证的观看人数，缺失值保持未知'),
    ('kilakila', '克拉克拉', 'no', 'watchNumber 尚无已验证的并发人数含义，不参与真实在线排行'),
    ('xiaohongshu', '小红书', 'no', '分享元数据可能包含展示文本，但不作为已验证的数值并发人数'),
    ('niconico', 'niconico', 'no', 'watchCount 是节目累计观看，与并发在线人数分开显示'),
    ('weibo', '微博直播', 'no', '目录与房间元数据未提供已验证的观看人数，缺失值保持未知'),
    ('looklive', 'LOOK 直播', 'roomList', '官网推荐的 onlineNumber 按当前观看人数展示，popularity 作为平台热度单独保留；房间详情缺值时保持未知'),
]
DEFAULT_ON = {'douyin', 'kuaishou', 'cc', 'twitch', 'soop', 'acfun', 'picarto', 'twitcasting'}
# platforms that report concurrent viewers, in Sites.supportSites order (live_room.dart audienceCapabilities)
SUPPORTED = [('douyin', '抖音', 'roomList'), ('kuaishou', '快手', 'roomList'), ('cc', '网易CC', 'roomList'), ('twitch', 'Twitch', 'roomList'),
             ('soop', 'Soop', 'roomList'), ('acfun', 'AcFun 直播', 'roomList'), ('picarto', 'Picarto', 'roomList'),
             ('twitcasting', 'TwitCasting', 'roomList'), ('chzzk', 'CHZZK', 'roomList'), ('liveme', 'LiveMe', 'roomList'),
             ('tiktok', 'TikTok LIVE', 'roomRealtime'), ('youtube', 'YouTube Live', 'roomRealtime'), ('bigo', 'Bigo Live', 'roomList'),
             ('pandalive', 'PandaTV', 'roomList'), ('fc2live', 'FC2 Live', 'roomList'), ('steambroadcast', 'Steam Broadcasts', 'roomList'),
             ('kugoulive', '酷狗直播', 'roomList'), ('baidulive', '百度直播', 'roomList'), ('looklive', 'LOOK 直播', 'roomList'),
             ('17live', '17LIVE', 'roomRealtime')]
NEW_IN_LIST = {'chzzk', 'liveme', 'tiktok', 'youtube', 'bigo', 'pandalive', 'fc2live', 'steambroadcast', 'kugoulive', 'baidulive', '17live'}
UNSUPPORTED = [('bilibili', '哔哩哔哩'), ('douyu', '斗鱼'), ('huya', '虎牙'), ('yy', 'YY'), ('missevan', '猫耳 FM'), ('inke', '映客'),
               ('kilakila', '克拉克拉'), ('xiaohongshu', '小红书'), ('niconico', 'niconico'), ('weibo', '微博直播'), ('showroom', 'SHOWROOM'),
               ('jdlive', '京东直播'), ('sixroom', '六间房直播')]
RANK = '排行规则：明确在线人数优先，其次是等待在线数据的平台，最后才是热度/累计观看；数值相同时按平台与房间号稳定排序，刷新时不乱跳。'
FALLBACK = '真实在线模式只使用明确的并发人数。支持平台尚未返回数据时显示“待刷新”，其余平台继续标明热度或累计观看，避免把几百万热度写成几百万人在线。'
MODE = [('平台热度优先', '使用各平台列表公开的热度或累计观看值；这些数值不等于同时在线人数'),
        ('真实在线人数优先', '只对已开启且返回明确并发人数的平台按在线人数显示和排行；其余房间保留原始口径标签')]


def v3_audience():
    def rt(title, desc, on):
        return (f'<div class="v3t two" style="gap:16px;align-items:flex-start;padding:10px 16px">{"<span class=\"rad on\" style=\"margin-top:2px\"></span>" if on else "<span class=\"rad\" style=\"margin-top:2px\"></span>"}'
                f'<div class="x"><div style="font-size:14px;font-weight:500;line-height:21px">{title}</div><div style="font-size:13px;line-height:19px;color:var(--onv)">{desc}</div></div></div>')
    b = v3gt('卡片显示与排行方式') + v3card([rt(MODE[0][0], MODE[0][1], False) + rt(MODE[1][0], MODE[1][1], True)])
    b += f'<div class="v3note" style="padding-top:8px">{RANK}</div><div class="v3gap"></div>'
    rows = []
    for pid, name, av, det in V3_PLATFORMS:
        sup = av != 'no'
        on = pid in DEFAULT_ON
        col = '' if sup else 'color:rgba(25,28,32,.38)'
        rows.append(f'<div class="v3t three" style="gap:16px;padding:8px 8px 8px 16px;align-items:center">'
                    + mr('people_alt' if sup else 'whatshot', 24, 'color:var(--onv);' + ('' if sup else 'opacity:.38'))
                    + f'<div class="x"><div style="font-size:14px;font-weight:500;line-height:21px;{col}">{name}</div>'
                    f'<div style="font-size:13px;line-height:19px;color:var(--onv);{col}">{SRC[av]}<br>{det}</div></div>'
                    f'<span class="sw{" on" if on else ""}" style="{"" if sup else "opacity:.38"}"></span></div>')
    b += v3gt('真实在线平台开关') + v3card(rows)
    b += f'<div class="v3note" style="padding-top:12px">{FALLBACK}</div>'
    return P(393, 5200, 2, v3bar('观看数据与排行口径') + f'<div class="v3body">{b}</div>', crop=True, long=True)


def v4_audience():
    b = sec('卡片显示与排行方式') + grp([radio(MODE[0][0], MODE[0][1], False, 1), radio(MODE[1][0], MODE[1][1], True, 2)])
    b += note(RANK)
    rows = []
    for i, (pid, name, av) in enumerate(SUPPORTED):
        on = pid in DEFAULT_ON
        lead = f'<span class="logo" style="background-image:url({LOGO.format(pid)})"></span>'
        rows.append(sw(name, SRC[av], on, 3 if i == 0 else None, 'chg', lead=lead) if i == 0 else
                    sw(name, SRC[av], on, (4 if pid == 'chzzk' else None), ('add' if pid == 'chzzk' else None), lead=lead))
    b += sec('真实在线平台开关') + grp(rows)
    logos = ''.join(f'<i style="background-image:url({LOGO.format(p)})"></i>' for p, _ in UNSUPPORTED)
    names = '、'.join(n for _, n in UNSUPPORTED)
    b += sec('只有热度或累计观看的平台') + grp([
        f'<div class="swr"><div class="x"><div class="a">{len(UNSUPPORTED)} 个平台</div><div class="b">{names}</div><div class="b">来源：平台公开接口未给出并发人数；卡片上照常标明热度或累计观看</div><div class="mini-logos">{logos}</div></div></div>',
        link('各平台口径说明', '每个平台的人数从哪来、是什么意思', '', 5, 'add'),
    ])
    b += note(FALLBACK)
    return P(393, 3600, 2, bar('观看数据与排行口径') + f'<div class="nbody">{b}</div>', crop=True, long=True)


def v4_audience_info():
    rows = []
    for pid, name, av, det in V3_PLATFORMS:
        lead = f'<span class="logo" style="background-image:url({LOGO.format(pid)})"></span>'
        rows.append(f'<div class="swr" style="align-items:flex-start">{lead}<div class="x"><div class="a">{name}</div><div class="b">{SRC[av]}</div><div class="b">{det}</div></div></div>')
    b = note('照 v3 的说明逐条保留；后加的平台只写来源。') + '<div style="height:8px"></div>' + grp(rows)
    return P(393, 4200, 2, bar('各平台口径说明') + f'<div class="nbody">{b}</div>', crop=True, long=True)


# ======================================================================
# Dialogs
# ======================================================================
def board(cells, w=1290):
    inner = ''.join(f'<div class="cell"><div class="cap">{cap}</div><div class="scr">{html}</div></div>' for cap, html in cells)
    return P(w, 2400, 1.5, f'<div class="board" style="width:{w}px">{inner}</div>', crop=True, frame='none')


def v3_dialogs():
    res = ('<div class="dl3" style="width:280px"><div class="h s">首选清晰度</div>'
           + ''.join(f'<div class="opt" style="padding:0 24px 0 12px;gap:4px"><span style="width:40px;display:grid;place-items:center"><span class="rd{" on" if i == 0 else ""}"></span></span>{t}</div>'
                     for i, t in enumerate(['原画', '蓝光8M', '蓝光4M', '超清', '流畅']))
           + '<div class="acts"><div class="tb mut">取消</div></div></div>')
    chips = ''.join(f'<span class="achip">{t}</span>' for t in ['15 分钟', '30 分钟', '45 分钟', '1 小时', '90 分钟', '2 小时', '4 小时', '8 小时', '12 小时', '1 天'])
    asmr = ('<div class="dl3" style="width:361px"><div class="h s">自动助眠播放时长</div>'
            '<div class="c" style="font-size:12px;line-height:16px">自动助眠启动时按此时长重新计时，到时停止播放。可选快捷时长，也可直接输入分钟数。</div>'
            f'<div style="padding:12px 24px 8px">{chips}</div>'
            '<div class="fld"><span class="lb">自定义播放时长</span>60<span class="sx">分钟</span></div><div class="fhelp">请输入 1 分钟至 365 天之间的分钟数</div>'
            '<div class="acts"><div class="tb mut">取消</div><div class="fb">保存</div></div></div>')
    pipreset = ('<div class="dl3" style="width:361px"><div class="h s">重置小窗位置和大小</div><div class="c" style="font-size:14px;color:var(--on)">确定要清除已保存的小窗位置和大小吗？</div>'
                '<div class="acts"><div class="tb mut">取消</div><div class="fb err">重置</div></div></div>')
    player = ('<div class="dl3" style="width:280px;padding-bottom:16px"><div class="h">切换播放器</div>'
              + ''.join(f'<div class="opt" style="height:56px;padding:0 16px;gap:16px"><span class="rd{" on" if i == 0 else ""}"></span><span style="font-size:15px">{t}</span></div>'
                        for i, t in enumerate(['Mpv播放器', 'IJK播放器', 'Exo播放器', 'Fvp播放器'])) + '</div>')
    proxy = ('<div class="dl3" style="width:340px"><div class="h">网络代理配置</div>'
             + '<div style="padding:0 8px">' + v3sw(rx('f107', 22), '启用播放代理', None, False) + '</div><div style="height:12px"></div>'
             + f'<div class="fld dis">{rx("edcf", 20, "color:var(--onv)")}<span class="lb">代理主机 (Host)</span>127.0.0.1</div>'
             + f'<div class="fld dis">{rx("eeb8", 20, "color:var(--onv)")}<span class="lb">端口 (Port)</span>1080</div>'
             + '<div class="acts" style="padding-top:0"><div class="tb">确认</div></div></div>')
    enum = ('<div class="dl3" style="width:280px;padding-bottom:12px"><div class="h">普通页布局模式</div>'
            + ''.join(f'<div class="opt" style="gap:12px">{mr("radio_button_checked" if i == 0 else "radio_button_unchecked", 24, "color:var(--primary)" if i == 0 else "color:var(--onv)")}<span style="font-size:14px">{t}</span></div>'
                      for i, t in enumerate(['均衡（推荐）', '沉浸', '兼容 16:9'])) + '</div>')
    pipdm = ('<div class="dl3" style="width:313px"><div class="h">恢复小窗弹幕默认值</div><div class="c">小窗弹幕开关、显示规则、颜色、字号和字重、速度、透明度、密度和帧率将全部恢复为默认值。</div>'
             '<div class="acts"><div class="tb">取消</div><div class="fb">重置</div></div></div>')
    toast = '<div class="toastcell"><div class="toast">已恢复默认设置</div></div>'
    return board([('首选清晰度、移动网络首选清晰度', res), ('切换播放器（Android、iOS）', player), ('普通页布局模式等竖屏选项', enum),
                  ('自动助眠播放时长（Android）', asmr), ('网络代理配置（播放内核页）', proxy), ('重置小窗位置和大小（Windows）', pipreset),
                  ('恢复小窗弹幕默认值', pipdm), ('恢复竖屏适配默认设置：不确认，直接恢复', toast),
                  ('MPV 的“重置”：不确认、没有提示', '<div style="color:#fff;font-size:13px;padding:30px 10px;text-align:center">点了立即恢复 10 项设置<br>（含首选清晰度），没有任何反馈</div>')])


def v4_dialogs():
    res = choice_dialog('首选清晰度', [(t, None, i == 0) for i, t in enumerate(['原画', '蓝光8M', '蓝光4M', '超清', '流畅'])], n=1)
    player = choice_dialog('切换播放器', [(t, None, i == 0) for i, t in enumerate(['Mpv播放器', 'IJK播放器', 'Exo播放器', 'Fvp播放器'])])
    enum = choice_dialog('普通页布局模式', [('均衡（推荐）', None, True), ('沉浸', None, False), ('兼容 16:9', None, False)], hint='仅影响竖屏直播源，不改变普通横屏直播')
    chips = ''.join(f'<span class="achip{" on" if t == "1 小时" else ""}">{t}</span>' for t in ['15 分钟', '30 分钟', '45 分钟', '1 小时', '90 分钟', '2 小时', '4 小时', '8 小时', '12 小时', '1 天'])
    asmr = ('<div class="dl4" style="width:361px" data-n="2" data-tag="chg" data-at="tl"><div class="h">自动助眠播放时长</div>'
            '<div class="c" style="font-size:13px">自动助眠启动时按此时长重新计时，到时停止播放。可选快捷时长，也可直接输入分钟数。点快捷时长立即生效。</div>'
            f'<div style="padding:4px 24px 8px">{chips}</div>'
            '<div class="fld"><span class="lb">自定义播放时长</span>60<span class="sx">分钟</span></div><div class="fhelp">请输入 1 分钟至 365 天之间的分钟数</div>'
            '<div class="acts"><div class="tb">取消</div><div class="fb">保存</div></div></div>')
    kreset = confirm_dialog('恢复播放内核默认设置', '下面这些恢复默认值：<ul><li>开启硬解码：开</li><li>兼容模式、播放器强制销毁：关</li><li>自定义驱动与硬件加速：关；三个驱动：默认</li><li>启用 RTX VSR：关（Windows）</li></ul>视频设置里的首选清晰度不变。')
    kreset = kreset.replace('class="dl4"', 'class="dl4" data-n="3" data-tag="chg" data-at="tl"', 1)
    pip = confirm_dialog('重置小窗位置和大小', '确定要清除已保存的小窗位置和大小吗？下次从应用所在显示器右下角打开。')
    preset = confirm_dialog('恢复竖屏适配默认设置', '本页的设置恢复默认，同时清除已记住的直播间方向。')
    pdm = confirm_dialog('恢复小窗弹幕默认值', '小窗弹幕开关、显示规则、颜色、字号和字重、速度、透明度、密度和帧率将全部恢复为默认值。')
    toast = '<div class="toastcell"><div class="toast">已恢复默认设置</div></div>'
    return board([('首选清晰度（所有选项对话框同一个）', res), ('切换播放器', player), ('普通页布局模式', enum),
                  ('自动助眠播放时长', asmr), ('恢复播放内核默认设置（新加确认）', kreset), ('重置小窗位置和大小（桌面）', pip),
                  ('恢复竖屏适配默认设置（新加确认）', preset), ('恢复小窗弹幕默认值（按钮改成红色）', pdm), ('确认后统一提示', toast)])


OUT = {
    'v3-video': v3_video_phone(), 'v4-video': v4_video_phone(),
    'v3-video-wide': v3_video_wide(), 'v4-video-wide': v4_video_wide(),
    'v3-video-land': v3_video_land(), 'v4-video-land': v4_video_land(),
    'v3-kernel': v3_kernel(), 'v4-kernel': v4_kernel(),
    'v3-mpv-option': v3_mpv_option(), 'v4-mpv-option': v4_mpv_option(),
    'v3-portrait': v3_portrait(), 'v4-portrait': v4_portrait(),
    'v3-pip': v3_pip(), 'v4-pip': v4_pip(), 'v3-pip-full': v3_pip(True), 'v4-pip-full': v4_pip(True),
    'v3-pip-wide': v3_pip_wide(), 'v4-pip-wide': v4_pip_wide(),
    'v3-pip-narrow': v3_pip_narrow(), 'v4-pip-narrow': v4_pip_narrow(),
    'v3-audience': v3_audience(), 'v4-audience': v4_audience(), 'v4-audience-info': v4_audience_info(),
    'v3-dialogs': v3_dialogs(), 'v4-dialogs': v4_dialogs(),
}
if __name__ == '__main__':
    for name, html in OUT.items():
        open(os.path.join(HERE, name + '.html'), 'w', encoding='utf-8').write(html)
    print(len(OUT), 'pages')
