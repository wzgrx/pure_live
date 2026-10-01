"""U.6d general and network settings: v3 restored and the new design.
v3 (tag v3.2.11, lib/modules/settings/pages/): general_settings_page.dart,
platform_settings_page.dart, refresh_settings.dart,
network_proxy_settings_page.dart; exit behaviour in plugins/utils.dart:241-330.
The local interaction page is U.2k.
    python3 docs/ui/compare/U.6d/src/gen.py && python3 tools/ui/mock/render.py docs/ui/compare/U.6d/src/ --annotate"""
import os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from smock import *  # noqa: E402,F401,F403

LOGO = '../../../packages/live_ui/assets/platforms/{}.png'
EXTRA = '''
.tmr{width:22px;height:22px;position:relative;display:inline-block}
.tmr::before{content:'';position:absolute;left:1px;top:1px;width:16px;height:16px;border:2px solid var(--primary);border-radius:50%}
.tmr i{position:absolute;left:10px;top:4px;width:2px;height:7px;background:var(--primary);border-radius:1px}
.tmr b{position:absolute;left:9px;top:9px;width:4px;height:4px;background:var(--primary);border-radius:2px}
.ec{display:inline-block;padding:3px 8px;border-radius:12px;background:var(--sc);color:var(--osc);font-size:11px;margin-left:8px;vertical-align:1px}
.flds{display:flex;gap:12px;padding:8px 20px 14px}.flds .fld{margin:0;flex:1}
.flds.stack{flex-direction:column}
.v3flds{display:flex;gap:12px;padding:16px}.v3flds.stack{flex-direction:column}
.v3flds .fld{margin:0;flex:1;border-radius:4px;background:var(--scl);height:48px}
.v3flds .fld .lb{background:linear-gradient(#F5F6FC 50%,var(--scl) 50%)}
.flds .fld .lb{background:linear-gradient(var(--scl) 50%,var(--scl) 50%)}
.flds.dis{opacity:.38}
.flds.stack .fld,.v3flds.stack .fld{flex:none}
.cellbox{height:700px;overflow:hidden;width:361px;display:flex;align-items:flex-start;justify-content:center}
.src{margin:0 24px 8px;height:48px;border:1px solid var(--outline);border-radius:12px;display:flex;align-items:center;gap:10px;padding:0 12px;color:var(--onv);font-size:14px;background:var(--scl)}
.dl4 .opt .logo{width:24px;height:24px;border-radius:6px}
.secd{padding:0 20px 6px;margin-top:-2px;font-size:12px;color:var(--onv)}
'''


def P(w, h, s, body, **k):
    return page(w, h, s, body, extra_css=EXTRA, **k)


TMR = '<span class="tmr"><i></i><b></b></span>'
G = {
    'rr_ps': '省电（默认）', 'rr_bal': '均衡', 'rr_perf': '最高（设备上限）',
    'rr_ps_d': '界面由系统动态调度；主画面弹幕上限 60 FPS，小窗弹幕上限 30 FPS，适合长时间观看。',
    'rr_bal_d': '触摸、滑动和转场时使用最高刷新率，操作结束后交还系统；主画面与小窗弹幕上限 60 FPS。',
    'rr_perf_d': '前台界面跟随当前设备或显示器上限；自动模式下主画面与小窗弹幕同步使用该上限，耗电和 GPU 占用可能更高。',
    'rr_hint': '应用会动态检测当前设备与分辨率支持的最高刷新率，切换后立即生效。启用弹幕的“跟随界面策略”时，主画面与小窗弹幕也会按此档位联动。',
    'win_rr_d': '跟随窗口所在显示器的系统刷新率；移动到其他显示器或系统切换模式后自动更新',
    'newwin_d': '在独立窗口中打开当前直播',
    'splash_d': '启动时显示 Logo',
    'gh_d': '开启后，版本检查和安装包下载仅连接 GitHub 官方地址，适合已配置网络代理的用户；关闭时自动提供镜像线路。',
    'cd_d': '开启后立即开始倒计时；到时关闭整个应用，与直播间停止播放、自动助眠相互独立',
    'startup_d': '登录 Windows 后自动启动 Pure Live。',
}


# ======================================================================
# 通用 (general_settings_page.dart)
# ======================================================================
def v3_general(windows=False, hz='60 / 120 Hz'):
    rows = [v3tile(rx('f371', 22), '界面刷新率', f'{G["rr_ps"]} · {G["rr_ps_d"]} · {hz}', 'chev24', long=True)]
    if windows:
        rows += [v3tile(rx('f371', 22), 'Windows 动态刷新率', G['win_rr_d'] + '<br>1920 × 1080 · 60 Hz (最高 144 Hz)', mr('refresh', 24, 'color:var(--onv)'), long=True),
                 v3sw(mo('add_to_photos', 22), '新建独立播放窗口', G['newwin_d'], True)]
    rows += [v3sw(rx('f094', 22), '启动动画', G['splash_d'], True),
             v3sw(rx('f064', 22), '自动检查更新', None, True),
             v3sw(rx('edcb', 22), '使用 GitHub 官方更新源', G['gh_d'], False, long=True),
             v3sw(rx('f215', 22), '应用定时退出', G['cd_d'], False),
             v3tile(TMR, '退出前等待时间', '120 分钟', 'chev24')]
    if windows:
        rows += [v3sw(rx('f2c8', 22), '开机启动', G['startup_d'], True),
                 v3tile(rx('ea80', 22), '开机窗口尺寸', '1080 × 720', 'chev24'),
                 v3sw(rx('eca1', 22), '退出不再询问', None, False)]
    return v3gt('通用') + v3card(rows)


def v4_general(windows=False, n=True, running=False):
    N = (lambda k: k) if n else (lambda k: None)
    rr_desc = '当前显示器 1920 × 1080 · 60 Hz（最高 144 Hz），换显示器时自动更新' if windows else '当前 60 Hz，最高 120 Hz'
    b = sec('显示') + grp([link('界面刷新率', rr_desc, '省电', N(1), 'chg')])
    start = []
    if windows:
        start += [sw('开机启动', G['startup_d'], True, N(7)), link('开机窗口尺寸', None, '1080 × 720', N(8))]
    start += [sw('启动动画', G['splash_d'], True, N(2))]
    b += sec('启动') + grp(start)
    b += sec('更新') + grp([sw('自动检查更新', None, True, N(3)), sw('使用 GitHub 官方更新源', G['gh_d'], False, N(4))])
    if windows:
        b += sec('窗口') + grp([link('关闭窗口时', '点窗口右上角关闭按钮时怎么做', '每次询问', N(9), 'chg'),
                               sw('新建独立播放窗口', G['newwin_d'], True, N(10))])
    cd_desc = '剩余时间 1:59:58' if running else None
    b += sec('定时退出') + grp([sw('应用定时退出', G['cd_d'], running, N(5)),
                             link('退出前等待时间', cd_desc, '120 分钟', N(6), 'chg')])
    return b


def v3_general_phone():
    return P(393, 1800, 2, v3bar('通用') + f'<div class="v3body">{v3_general()}</div>', crop=True, long=True)


def v4_general_phone():
    return P(393, 1800, 2, bar('通用') + f'<div class="nbody">{v4_general()}</div>', crop=True, long=True)


def v3_general_wide():
    return P(1280, 800, 1.5, v3bar('通用') + f'<div class="v3body" style="overflow:hidden"><div class="v3wrap">{v3_general(True, "60 / 144 Hz")}</div></div>', frame='win')


def v4_general_wide():
    return P(1280, 800, 1.5, bar('通用') + f'<div class="nbody" style="overflow:hidden"><div class="nwrap">{v4_general(True)}</div></div>', frame='win')


def v3_general_land():
    return P(852, 393, 2, v3bar('通用') + f'<div class="v3body" style="overflow:hidden">{v3_general()}</div>', frame='win')


def v4_general_land():
    return P(852, 393, 2, bar('通用') + f'<div class="nbody" style="overflow:hidden"><div class="nwrap">{v4_general(n=False)}</div></div>', frame='win')


# ======================================================================
# 平台显示与授权 (platform_settings_page.dart)
# ======================================================================
def v3_platform():
    val = ('<span style="display:flex;align-items:center;gap:4px;flex:none"><span style="font-size:14px;color:rgba(0,0,0,.75)">哔哩哔哩</span>'
           + mr('chevron_right', 20, 'color:rgba(0,0,0,.4)') + '</span>')
    b = v3gt('平台显示与授权') + v3card([
        v3tile(rx('ea42', 22), '平台显示', '管理首页直播平台排序'),
        v3tile(rx('ee0b', 22), '首选直播平台', '当进入热门/分区，首选的直播平台', val, long=True),
        v3tile(rx('f5cd', 22), '三方认证', '管理主流平台的绑定授权', long=True),
        v3tile(rx('f023', 22), '标签管理', '自定义和管理直播间的过滤标签', long=True),
    ])
    return P(393, 852, 3, v3bar('平台显示与授权') + f'<div class="v3body">{b}</div>')


def v4_platform():
    logo = f'<span class="logo" style="width:20px;height:20px;border-radius:5px;background-image:url({LOGO.format("bilibili")})"></span>'
    b = sec('平台') + grp([
        link('平台显示', '管理首页直播平台排序', '', 1),
        link('首选直播平台', '当进入热门/分区，首选的直播平台', '哔哩哔哩', 2, 'chg').replace('<span class="val">', logo + '<span class="val">'),
    ])
    b += sec('账号和标签') + grp([
        link('三方认证', '管理主流平台的绑定授权', '', 3),
        link('标签管理', '自定义和管理直播间的过滤标签', '', 4),
    ])
    return P(393, 852, 3, bar('平台显示与授权') + f'<div class="nbody">{b}</div>')


# ======================================================================
# 刷新设置 (refresh_settings.dart)
# ======================================================================
R = {
    'af_d': '定时自动拉取关注直播间状态', 'res_d': '从后台返回应用时自动刷新收藏列表',
    'cc_d': '完成一个任务后立即领取下一个，避免慢接口拖住整批刷新',
    'th_d': '按设定周期清理旧封面并重新请求当前缩略图',
    'cc_hint': '这是网络请求并发数，不是增加 CPU 线程。默认 4；建议 3–6，过高可能触发平台限流并增加耗电。',
}


def v3_refresh(on=False):
    rows = [v3sw(rx('f064', 22), '开启关注自动刷新', R['af_d'], on),
            v3sw(rx('f064', 22), '返回应用时刷新收藏', R['res_d'], True)]
    if on:
        rows.append(v3tile(rx('f20f', 22), '刷新间隔时间', '30 分钟'))
    rows += [v3tile(rx('f0e0', 22), '首页并发刷新任务', '4 个任务 · ' + R['cc_d'], long=True),
             v3sw(rx('ee45', 22), '自动刷新直播缩略图', R['th_d'], False)]
    b = v3gt('自动刷新设置') + v3card(rows)
    return P(393, 852, 3, v3bar('刷新设置') + f'<div class="v3body">{b}</div>')


def v4_refresh():
    why = '打开“开启关注自动刷新”后生效'
    b = sec('关注列表') + grp([
        sw('开启关注自动刷新', R['af_d'], False, 1),
        link('刷新间隔时间', None, '30 分钟', 2, 'chg', dis=True, why=why),
        sw('返回应用时刷新关注', '从后台返回应用时自动刷新关注列表', True, 3, 'chg'),
        cnt('首页并发刷新任务', '4', 4, 'chg', desc=R['cc_d'] + '；默认 4，<span style="white-space:nowrap">建议 3–6</span>'),
    ])
    b += sec('直播缩略图') + grp([
        sw('自动刷新直播缩略图', R['th_d'], False, 5),
        link('缩略图刷新间隔', None, '30 分钟', 6, 'chg', dis=True, why='打开“自动刷新直播缩略图”后生效'),
    ])
    return P(393, 852, 3, bar('刷新设置') + f'<div class="nbody">{b}</div>')


# ======================================================================
# 网络与代理设置 (network_proxy_settings_page.dart)
# ======================================================================
NP = {
    'app_g': '软件应用层代理 (解决启动、刷列表)', 'app': '启用应用层代理', 'app_d': '关闭时软件完全使用 DIRECT 直连，避免系统网络探测导致的启动慢',
    'pl_g': '播放器内核代理 (解决直播流拉取)', 'pl': '启用播放代理', 'pl_d': '控制 media_kit / mpv 播放器内核拉取直播源视频流时的网络设置',
}


def v3_net_tile(icon, title, desc, on):
    # raw SwitchListTile: default ListTile text (14 medium / 13 onSurfaceVariant), 24 px icon
    return (f'<div class="v3t two swt" style="gap:16px">{icon}<div class="x"><div style="font-size:14px;font-weight:500;line-height:21px">{title}</div>'
            f'<div style="font-size:13px;line-height:19px;color:var(--onv)">{desc}</div></div><span class="sw{" on" if on else ""}"></span></div>')


def v3_network(wide=False):
    st = '' if wide else 'stack'
    fields = (f'<div class="v3flds {st}"><div class="fld"><span class="lb">代理地址</span>127.0.0.1</div>'
              f'<div class="fld" style="{"flex:.66" if wide else ""}"><span class="lb">端口</span>7897</div></div>')
    b = v3gt(NP['app_g']) + v3card([v3_net_tile(rx('ea44', 24, 'color:var(--primary)'), NP['app'], NP['app_d'], True) + fields])
    b += '<div style="height:24px"></div>' + v3gt(NP['pl_g']) + v3card([v3_net_tile(rx('f282', 24, 'color:var(--primary)'), NP['pl'], NP['pl_d'], False)])
    if wide:
        return P(1280, 800, 1.5, v3bar('网络与代理设置') + f'<div class="v3body"><div class="v3wrap">{b}</div></div>', frame='win')
    return P(393, 852, 3, v3bar('网络与代理设置') + f'<div class="v3body">{b}</div>')


def v4_network(wide=False, n=True):
    N = (lambda k: k) if n else (lambda k: None)
    st = '' if wide else 'stack'

    def flds(host, port, dis=False, k=None):
        return (f'<div class="flds {st}{" dis" if dis else ""}"{nattr(k, "chg", "tl")}><div class="fld"><span class="lb">代理地址</span>{host}</div>'
                f'<div class="fld" style="{"flex:.66" if wide else ""}"><span class="lb">端口</span>{port}</div></div>')
    b = sec(NP['app_g']) + grp([sw(NP['app'], NP['app_d'], True, N(1)), flds('127.0.0.1', '7897', k=N(2))])
    b += sec(NP['pl_g']) + grp([sw(NP['pl'], NP['pl_d'], False, N(3)), flds('127.0.0.1', '7897', dis=True, k=N(4))])
    if wide:
        return P(1280, 800, 1.5, bar('网络与代理设置') + f'<div class="nbody"><div class="nwrap">{b}</div></div>', frame='win')
    return P(393, 852, 3, bar('网络与代理设置') + f'<div class="nbody">{b}</div>')


# ======================================================================
# Dialogs
# ======================================================================
def board(cells, w=1290):
    inner = ''.join(f'<div class="cell"><div class="cap">{cap}</div><div class="scr">{html}</div></div>' for cap, html in cells)
    return P(w, 2600, 1.5, f'<div class="board" style="width:{w}px">{inner}</div>', crop=True, frame='none')


def rl3(label, on, sub=None, extra=''):
    s = f'<div style="font-size:13px;color:var(--onv);line-height:19px;margin-top:3px">{sub}</div>' if sub else ''
    return (f'<div style="display:flex;gap:16px;padding:8px 24px 8px 16px;align-items:{"flex-start" if sub else "center"};min-height:48px">'
            f'<span class="rd{" on" if on else ""}" style="flex:none;margin:{"2px" if sub else "0"} 0 0 0"></span><div style="flex:1"><div style="font-size:15px;line-height:22px">{label}{extra}</div>{s}</div></div>')


def v3_dialogs():
    rr = ('<div class="dl3" style="width:361px;padding-bottom:12px"><div class="h">界面刷新率</div>'
          f'<div class="c" style="font-size:12px;line-height:16px;padding-bottom:10px">{G["rr_hint"]}</div>'
          + rl3('省电（默认）', True, G['rr_ps_d'], '<span class="ec">低耗电</span>') + rl3('均衡', False, G['rr_bal_d'], '<span class="ec">中等耗电</span>')
          + rl3('最高（设备上限）', False, G['rr_perf_d'], '<span class="ec">高耗电</span>') + '</div>')
    chips = ''.join(f'<span class="achip">{t}</span>' for t in ['1080 × 720 (默认)', '1280 × 720 (720P)', '1600 × 900', '1920 × 1080 (1080P)', '2560 × 1440 (2K)'])
    ws = ('<div class="dl3" style="width:361px"><div class="h">开机窗口尺寸</div>'
          '<div class="c" style="color:rgba(0,0,0,.6)">快捷预设选择</div>'
          f'<div style="padding:8px 24px 12px">{chips}</div><div class="c" style="color:rgba(0,0,0,.6);padding-bottom:12px">自定义输入尺寸</div>'
          '<div style="display:flex;align-items:center;gap:8px;padding:0 24px"><div class="fld" style="margin:0;flex:1;height:44px;border-radius:4px"><span class="lb">宽度</span>1080</div>'
          '<span style="font-size:20px">×</span><div class="fld" style="margin:0;flex:1;height:44px;border-radius:4px"><span class="lb">高度</span>720</div></div>'
          '<div class="c" style="font-size:12px;color:rgba(0,0,0,.6);padding-top:8px">宽度 400～16384 · 高度 300～16384</div>'
          '<div class="acts"><div class="tb">取消</div><div class="tb" style="font-weight:700">确认</div></div></div>')
    cd_chips = ''.join(f'<span class="achip{" on" if m == 120 else ""}">{m} 分钟</span>' for m in [15, 30, 45, 60, 90, 120, 180])
    cd = ('<div class="dl3" style="width:361px"><div class="h">设置应用退出等待时间</div>'
          '<div class="c" style="font-size:12px;line-height:16px">这是整个应用的退出计时。保存时长或打开开关后重新计时，到时关闭应用。</div>'
          f'<div style="padding:12px 24px 12px">{cd_chips}</div>'
          '<div class="fld"><span class="lb">自定义时长</span><span style="color:transparent">0</span><span class="sx">分钟</span></div><div class="fhelp">输入 1～525600 分钟</div>'
          '<div class="acts"><div class="tb">取消</div><div class="fb">保存</div></div></div>')
    sites = [('bilibili', '哔哩哔哩'), ('douyu', '斗鱼'), ('huya', '虎牙'), ('douyin', '抖音'), ('kuaishou', '快手'), ('cc', '网易CC'), ('twitch', 'Twitch'), ('soop', 'Soop')]
    pp = ('<div class="dl3" style="width:361px;padding-bottom:16px"><div class="h" style="font-weight:700">首选直播平台</div>'
          f'<div class="src" style="margin:0 24px 8px;border-radius:4px">{mr("search", 22)}搜索已显示的平台</div>'
          + ''.join(f'<div class="opt" style="height:52px;gap:16px;padding:0 24px"><span class="rd{" on" if i == 0 else ""}"></span><span style="font-size:15px;font-weight:500">{n}</span></div>' for i, (_, n) in enumerate(sites))
          + '<div style="text-align:center;color:var(--onv);font-size:12px">……共 34 个，向下滚动</div></div>')
    ivs = ['5 分钟', '10 分钟', '15 分钟', '20 分钟', '30 分钟', '45 分钟', '1 小时', '1.5 小时', '2 小时', '3 小时', '4 小时', '6 小时']
    iv = ('<div class="dl3" style="width:361px;padding-bottom:8px"><div class="h">刷新间隔时间</div>'
          + ''.join(rl3(t, t == '30 分钟') for t in ivs) + '</div>')
    cc = ('<div class="cellbox"><div class="dl3" style="width:361px;padding-bottom:8px"><div class="h">首页并发刷新任务</div>'
          f'<div class="c" style="font-size:12px;line-height:16px;padding-bottom:12px">{R["cc_hint"]}</div>'
          + ''.join(rl3(f'{i} · 推荐' if i == 4 else str(i), i == 4) for i in range(1, 21)) + '</div></div>')
    return board([('界面刷新率（Android、Windows）', rr), ('开机窗口尺寸（Windows）', ws), ('设置应用退出等待时间', cd),
                  ('首选直播平台', pp), ('刷新间隔时间、缩略图刷新间隔', iv), ('首页并发刷新任务：20 项，手机上要滚动', cc)])


def v4_dialogs():
    rr = choice_dialog('界面刷新率', [('省电（默认） · 低耗电', G['rr_ps_d'], True), ('均衡 · 中等耗电', G['rr_bal_d'], False),
                                    ('最高（设备上限） · 高耗电', G['rr_perf_d'], False)], hint=G['rr_hint'] + '<br>当前 60 Hz，最高 120 Hz。', n=1)
    rr = rr.replace('<div class="acts"><div class="tb">取消</div></div>', '<div class="acts"><div class="tb">重新检测</div><div style="flex:1"></div><div class="tb">取消</div></div>')
    chips = ''.join(f'<span class="achip{" on" if t.startswith("1080 × 720") else ""}">{t}</span>' for t in ['1080 × 720 (默认)', '1280 × 720 (720P)', '1600 × 900', '1920 × 1080 (1080P)', '2560 × 1440 (2K)'])
    ws = ('<div class="dl4" style="width:361px" data-n="2" data-tag="chg" data-at="tl"><div class="h">开机窗口尺寸</div><div class="c" style="font-size:13px">快捷预设选择</div>'
          f'<div style="padding:4px 24px 8px">{chips}</div><div class="c" style="font-size:13px">自定义输入尺寸</div>'
          '<div style="display:flex;align-items:center;gap:8px;padding:4px 24px 0"><div class="fld" style="margin:0;flex:1"><span class="lb">宽度</span>1080</div>'
          '<span style="font-size:20px">×</span><div class="fld" style="margin:0;flex:1"><span class="lb">高度</span>720</div></div>'
          '<div class="c" style="font-size:12px;padding-top:8px">宽度 400～16384 · 高度 300～16384；点“应用”后窗口立即变成这个大小</div>'
          '<div class="acts"><div class="tb">取消</div><div class="fb">应用</div></div></div>')
    cd_chips = ''.join(f'<span class="achip{" on" if m == 120 else ""}">{m} 分钟</span>' for m in [15, 30, 45, 60, 90, 120, 180])
    cd = ('<div class="dl4" style="width:361px" data-n="3" data-tag="chg" data-at="tl"><div class="h">退出前等待时间</div>'
          '<div class="c" style="font-size:13px">这是整个应用的退出计时。保存时长或打开开关后重新计时，到时关闭应用。点快捷时长立即生效。</div>'
          f'<div style="padding:4px 24px 8px">{cd_chips}</div>'
          '<div class="fld" style="border-color:var(--error)"><span class="lb" style="color:var(--error)">自定义时长</span>600000<span class="sx">分钟</span></div>'
          '<div class="fhelp" style="color:var(--error)">输入 1～525600 分钟</div>'
          '<div class="acts"><div class="tb">取消</div><div class="fb">保存</div></div></div>')
    sites = [('bilibili', '哔哩哔哩'), ('douyu', '斗鱼'), ('huya', '虎牙'), ('douyin', '抖音'), ('kuaishou', '快手'), ('cc', '网易CC'), ('twitch', 'Twitch')]
    opts = ''.join(f'<div class="opt{" on" if i == 0 else ""}"><span class="logo" style="background-image:url({LOGO.format(p)})"></span><div class="x">{nm}</div>'
                   + (f'<span class="ck">{rx("eb7b", 20)}</span>' if i == 0 else '<span class="ck"></span>') + '</div>' for i, (p, nm) in enumerate(sites))
    pp = (f'<div class="dl4" style="width:361px" data-n="4" data-tag="chg" data-at="tl"><div class="h">首选直播平台</div><div class="src">{mr("search", 22)}搜索已显示的平台</div>{opts}'
          '<div style="text-align:center;color:var(--onv);font-size:12px;padding:4px 0">……共 34 个，向下滚动</div><div class="acts"><div class="tb">取消</div></div></div>')
    ivs = ['5 分钟', '10 分钟', '15 分钟', '20 分钟', '30 分钟', '45 分钟', '1 小时', '1.5 小时', '2 小时', '3 小时', '4 小时', '6 小时']
    iv = choice_dialog('刷新间隔时间', [(t, None, t == '30 分钟') for t in ivs])
    ex = choice_dialog('关闭窗口时', [('每次询问', '弹出“最小化 / 退出应用”，可以勾选“不再询问”', True), ('最小化', '缩到托盘，直播照常', False), ('退出应用', None, False)])
    ex = ex.replace('class="dl4"', 'class="dl4" data-n="5" data-tag="add" data-at="tl"', 1)
    return board([('界面刷新率（同一个选项对话框，加“重新检测”）', rr), ('开机窗口尺寸（Windows）', ws), ('退出前等待时间（输入超出范围时）', cd),
                  ('首选直播平台（带图标和搜索）', pp), ('刷新间隔时间、缩略图刷新间隔', iv), ('关闭窗口时（Windows，新）', ex)])


OUT = {
    'v3-general': v3_general_phone(), 'v4-general': v4_general_phone(),
    'v3-general-wide': v3_general_wide(), 'v4-general-wide': v4_general_wide(),
    'v3-general-land': v3_general_land(), 'v4-general-land': v4_general_land(),
    'v3-platform': v3_platform(), 'v4-platform': v4_platform(),
    'v3-refresh': v3_refresh(), 'v3-refresh-on': v3_refresh(True), 'v4-refresh': v4_refresh(),
    'v3-network': v3_network(), 'v4-network': v4_network(),
    'v3-network-wide': v3_network(True), 'v4-network-wide': v4_network(True, n=False),
    'v3-dialogs': v3_dialogs(), 'v4-dialogs': v4_dialogs(),
}
if __name__ == '__main__':
    for name, html in OUT.items():
        open(os.path.join(HERE, name + '.html'), 'w', encoding='utf-8').write(html)
    print(len(OUT), 'pages')
