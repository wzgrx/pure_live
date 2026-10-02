"""U.1c common components: catalogue boards (v3 restored / new) and the
screens they sit in. U.1d imports the page pieces (settings page, rows).
Writes the HTML next to this file; then
    python3 tools/ui/mock/render.py docs/ui/compare/U.1c/src/ --annotate --dark

v3 (tag v3.2.11, ~/ref/v3ref/lib):
  common/widgets/app_status_view.dart, empty_view.dart     status
  common/base/base_page_view.dart, base_page_view_extension.dart, plugins/global.dart   list shell
  common/widgets/common_avatar.dart, count_button.dart, qr_code_widget.dart
  modules/account/bilibili/bilibili_login_qr_code.dart, qr_login_page.dart
  common/widgets/scrollable_tab_bar.dart, common/style/theme.dart (tabBarTheme, listTileTheme)
  common/widgets/widget_extensions.dart (settings rows), section_listtile.dart
  modules/settings/pages/video_settings_page.dart (the settings page shown)
New design: rows, switches, sliders, counters from U.2f (confirmed); status
pieces from U.2e / U.2g / U.4b (in review).
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from parts import (mr, mi, mo, rx, r, dn, IMG, LOGO, STATUS, GESTURE, page, board, cap, group, box, cell, qr_svg)  # noqa: E402

OUT = {}

# =====================================================================
# status
# =====================================================================
DIO_412 = ('DioException [bad response]: This exception was thrown because the response has a status code of 412 '
           'and RequestOptions.validateStatus was configured to throw for this status code.')
DIO_DNS = ("DioException [connection error]: The connection errored: Failed host lookup: 'api.live.bilibili.com' "
           'This indicates an error which most likely cannot be solved by the library.')


def s3(icon, title, sub=None, btn=None):
    return ('<div class="s3"><div class="o">' + icon + f'</div><div class="t">{title}</div>'
            + (f'<div class="s">{sub}</div>' if sub is not None else '')
            + (f'<div class="tb3">{mr("refresh", 18)}{btn}</div>' if btn else '') + '</div>')


def s4(icon, title, sub=None, btns=(), cls='', n=None):
    b = ''
    for i, (kind, ic, t) in enumerate(btns):
        nn = dn(n + i, 'chg') if n else ''
        b += f'<div class="xb {kind}{" nb" if not ic else ""}"{nn}>{ic}{t}</div>'
    return (f'<div class="s4 {cls}">' + (f'<div class="o">{icon}</div>' if icon and 'cp' not in cls else (icon or ''))
            + f'<div class="t">{title}</div>' + (f'<div class="s">{sub}</div>' if sub else '')
            + (f'<div class="bs">{b}</div>' if b else '') + '</div>')


def cover(inner, bg='var(--sch)', w=176):
    return (f'<div style="width:{w}px;aspect-ratio:16/9;border-radius:16px;background:{bg};display:grid;place-items:center;'
            f'position:relative;overflow:hidden">{inner}</div>')


def mini3():
    return ('<div style="padding:8px;border-radius:50%;background:color-mix(in srgb,var(--schh) 15%,transparent);'
            'border:1px solid color-mix(in srgb,var(--primary) 5%,transparent);color:color-mix(in srgb,var(--primary) 60%,transparent)">'
            + mr('wifi_off', 16) + '</div>')


def btn_states3():
    cells = [cell(f'<div class="tb3">{mr("refresh", 18)}重试</div>', '默认'),
             cell(f'<div class="tb3 st-h">{mr("refresh", 18)}重试</div>', '悬停'),
             cell(f'<div class="tb3 ov3">{mr("refresh", 18)}重试</div>', '键盘焦点'),
             cell(f'<div class="tb3 st-p">{mr("refresh", 18)}重试</div>', '按下'),
             cell(f'<div class="tb3" style="color:var(--on);opacity:.38">{mr("refresh", 18)}重试</div>', '禁用')]
    return '<div class="x-row" style="gap:6px">' + ''.join(cells) + '</div>'


def btn_states4(kind, ic, t):
    c = [('', '默认'), (' st-h', '悬停'), (' st-f', '键盘焦点'), (' st-p', '按下'), (' dis', '禁用')]
    cells = [cell(f'<div class="xb {kind}{x}">{ic}{t}</div>', lab) for x, lab in c]
    cells.append(cell(f'<div class="xb {kind}" style="opacity:.8"><span class="spin" style="width:16px;height:16px"></span>{t}</div>', '进行中'))
    return '<div class="x-row" style="gap:8px 10px">' + ''.join(cells) + '</div>'


def v3_status():
    c = group('整页（列表、页面）')
    c += cap('加载', '只有转圈（默认样式；手机 24，整屏宽 >680 时 32）。BasePageView 传了“加载中...”也不显示（app_status_view.dart:383-413、base_page_view.dart:170）')
    c += box('<div style="display:grid;place-items:center;height:130px"><div class="ring3"></div></div>')
    c += cap('空', '“无数据”，没有说明，没有按钮（base_page_view.dart:167）；圆圈底色 15% 透明、图标主色 60%（app_status_view.dart:433-445），还有 1 秒弹性放大入场')
    c += box(s3(mr('live_tv', 42), '无数据', ''))
    c += cap('出错', '一律断网图标，说明是原始报错，按钮固定刷新图标（base_page_view.dart:215-224、app_status_view.dart:470-477）')
    c += box(s3(mr('wifi_off', 42), '网络请求失败', DIO_412, '重试'))
    c += cap('受限（需要登录）', '按钮写“前往登录”，图标还是刷新（base_page_view.dart:204-213）')
    c += box(s3(mo('account_circle', 42), '需要登录账号', '该平台数据已被风控隐藏，请登录账号后重试', '前往登录'))
    c += cap('离线（没有网络）', '没有单独的样子：和出错一样，只是原始报错不同')
    c += box(s3(mr('wifi_off', 42), '网络请求失败', DIO_DNS, '重试'))
    c += group('区块里、卡片上')
    c += cap('卡片封面', '加载中是电视图标，失败是小圆圈断网图标（room_card.dart:102-119）')
    c += '<div class="x-row">' + cell(cover(mr('live_tv', 24, 'color:var(--onv)'), '#F5F5F5'), '加载中') + cell(cover(mini3(), '#F5F5F5'), '加载失败（isMini）') + '</div>'
    c += cap('各页自己画的状态', '同类状态，图标、字号、按钮各不相同：醒目留言空（super_chat_page.dart:12-34）、扫码登录失效（qr_login_page.dart:183-215）')
    sc = ('<div style="padding:22px 12px;text-align:center">' + r('chat_smile_3_line', 42, 'color:var(--primary)')
          + '<div style="font-size:18px;font-weight:700;margin-top:12px">暂无醒目留言</div>'
          + '<div style="font-size:13px;color:var(--onv);margin-top:8px;line-height:1.5">当前直播间的付费留言会显示在这里。</div></div>')
    qr = ('<div style="padding:22px 12px;text-align:center">' + r('error_warning_line', 40, 'color:color-mix(in srgb,var(--hint) 40%,transparent)')
          + '<div style="font-size:14px;color:var(--hint);margin-top:12px">二维码已失效</div>'
          + f'<div class="tb3" style="margin-top:12px;font-weight:600">{r("refresh_line", 18)}刷新二维码</div></div>')
    c += '<div style="display:grid;grid-template-columns:1fr 1fr;gap:8px">' + box(sc) + box(qr) + '</div>'
    c += group('有内容时出错')
    c += cap('出错横幅', 'MaterialBanner：错误容器色、信息图标、原始报错，按钮在下面（base_page_view.dart:103-132）')
    c += ('<div style="background:var(--ec);color:var(--oec);border-radius:4px;padding:16px 8px 8px 16px">'
          '<div style="display:flex;gap:16px;font-size:13px;line-height:1.5">' + mr('info_outline', 24)
          + '<div style="word-break:break-all">DioException [receive timeout]: The request took longer than 0:00:15.000000 to receive data.</div></div>'
          '<div style="display:flex;justify-content:flex-end;margin-top:4px"><div class="tb3 ni">重试</div></div></div>')
    c += group('状态里的按钮（TextButton.icon，13 号 500）')
    c += cap('状态', '按下只有底色（主题关了水波，theme.dart:114）；键盘焦点是一层底色，没有框；没有“进行中”的样子')
    c += btn_states3()
    return board('v3 · 状态页', 'AppStatusView、EmptyView 和列表外壳 BasePageView 的状态（app_status_view.dart、base_page_view.dart）', c)


def skel_card():
    return ('<div style="background:var(--scl);border-radius:20px;overflow:hidden"><div style="aspect-ratio:16/9;background:var(--sch);border-radius:20px"></div>'
            '<div style="display:flex;gap:10px;align-items:center;padding:10px 12px 12px"><span style="width:34px;height:34px;border-radius:17px;background:var(--sch);flex:none"></span>'
            '<div style="flex:1"><div style="height:10px;border-radius:5px;background:var(--sch);width:90%"></div>'
            '<div style="height:10px;border-radius:5px;background:var(--sch);width:50%;margin-top:8px"></div></div></div></div>')


def skel_row():
    return ('<div style="display:flex;gap:16px;align-items:center;padding:12px 16px"><span style="width:24px;height:24px;border-radius:6px;background:var(--sch)"></span>'
            '<div style="flex:1"><div style="height:11px;border-radius:6px;background:var(--sch);width:55%"></div>'
            '<div style="height:9px;border-radius:5px;background:var(--sch);width:80%;margin-top:9px"></div></div>'
            '<span style="width:44px;height:24px;border-radius:12px;background:var(--sch)"></span></div>')


def v4_status():
    ton = lambda ic, t: ('ton', ic, t)
    c = group('整页（列表、页面）')
    c += cap('骨架（列表第一次加载）', '形状跟内容（卡片、列表行、设置行）；静态，不扫光（计划书 9.3，U.4a c8、U.4b c7）')
    c += box('<div style="display:grid;grid-template-columns:1fr 1fr;gap:8px;padding:8px">' + skel_card() + skel_card() + '</div>'
             + '<div style="margin:0 8px 8px;background:var(--scl);border-radius:16px">' + skel_row() + skel_row() + '</div>')
    c += cap('加载（不是列表）', '转圈照旧随设置“加载样式”；下面一句说在等什么（默认用 v3 的“加载中...”，各页可换成具体的，如 U.2g“正在进入直播间…”）')
    c += box('<div style="display:flex;flex-direction:column;align-items:center;justify-content:center;gap:12px;height:130px">'
             '<div class="ring3" style="width:28px;height:28px"></div><div style="font-size:13px;color:var(--onv)">加载中...</div></div>')
    c += cap('空', '一句话说没有什么，一句说下一步，有下一步就给按钮（U.4e c5）；圆圈实色，图标主色，不弹跳')
    c += box(s4(mr('live_tv', 40), '未发现直播', '这个分区现在没有人在播，可以稍后刷新', [ton(mr('refresh'), '刷新')]))
    c += cap('出错', '按原因写一句人话；原始报错收进“详情”（看全文、可复制）；图标按原因')
    c += box(s4(mr('error_outline', 40), '加载失败', '平台拒绝了请求（412），可能是请求太频繁，稍后再试',
                [ton(mr('refresh'), '重试'), ('txt', '', '详情')]))
    c += cap('受限（需要登录）', '文字照 v3，按钮图标跟动作（U.4e c6）；第二个按钮重试')
    c += box(s4(mr('lock', 40), '需要登录账号', '该平台数据已被风控隐藏，请登录账号后重试',
                [ton(mr('login'), '前往登录'), ('txt', '', '重试')]))
    c += cap('离线（没有网络）', '单独的样子：说清是没网，连上网络后自动重试')
    c += box(s4(mr('wifi_off', 40), '没有网络连接', '检查网络后重试；连上网络后会自动刷新', [ton(mr('refresh'), '重试')]))
    c += group('区块里、卡片上、画面上（同一结构，小一号）')
    c += cap('区块（标签页、面板里）', '图标 32 不带圆圈，按钮同上（U.2e 弹幕列表、U.2g 节目单）')
    c += ('<div style="display:grid;grid-template-columns:1fr 1fr;gap:8px">'
          + box(s4(r('chat_smile_3_line', 32, 'color:var(--onv)'), '还没有弹幕', '弹幕服务器连接正常，新弹幕会显示在这里', cls='cp'))
          + box(s4(r('wifi_off_line', 32, 'color:var(--onv)'), '弹幕服务器连接超时', '已自动释放，可以重新连接', [ton(mr('refresh'), '重新连接')], cls='cp'))
          + '</div>')
    c += cap('卡片封面', '加载中和加载失败同一个占位，不显示断网图标（U.4a c5）')
    c += '<div class="x-row">' + cell(cover(mr('live_tv', 28, 'color:color-mix(in srgb,var(--onv) 60%,transparent)')), '加载中、加载失败') + '</div>'
    c += cap('画面上', '黑底白字；第一个按钮白色实心，第二个描边（U.2g，已出图）')
    c += box('<div class="s4 vd" style="background-image:linear-gradient(rgba(0,0,0,.6),rgba(0,0,0,.6)),url(' + IMG + '158.jpg)">'
             + mr('error_outline', 36) + '<div class="t" style="margin-top:8px">播放已中断</div><div class="s">网络连接失败</div>'
             + '<div class="bs"><span class="vb1">' + mr('refresh', 18) + '重试</span><span class="vb2">' + mi('alt_route', 18) + '换线路</span></div></div>')
    c += group('有内容时（页顶横幅，内容照常显示）')
    c += cap('说明', '浅色条加 ⓘ，最多两行（U.4b c6）')
    c += ('<div class="bn inf">' + r('information_line', 18) + '<div class="x">CHZZK：只能看到正在直播的房间，海外平台可能需要代理。</div>'
          + '<div class="cl">' + mr('chevron_right', 20) + '</div></div>')
    c += cap('提醒', '移动流量提醒，照 v3 的“不再显示”')
    c += ('<div class="bn warn">' + mr('signal_cellular_alt', 18) + '<div class="x">您当前正在使用移动蜂窝流量，请注意流量消耗。'
          '<div class="a"><span class="xb txt" style="height:32px">不再显示</span></div></div><div class="cl">' + mr('close', 20) + '</div></div>')
    c += cap('出错', '刷新失败但旧内容还在：错误容器色，“重试”和关闭（代替 v3 的 MaterialBanner）')
    c += ('<div class="bn err">' + mr('error_outline', 18) + '<div class="x">刷新失败：网络连接超时，下面是上次的内容。'
          '<div class="a"><span class="xb txt" style="height:32px">重试</span><span class="xb txt" style="height:32px">详情</span></div></div>'
          '<div class="cl">' + mr('close', 20) + '</div></div>')
    c += group('状态里的按钮')
    c += cap('第一个：浅色实心（次色容器）', '高 40，点击区域 48；键盘焦点主色框，只在用键盘时显示')
    c += btn_states4('ton', mr('refresh'), '重试')
    c += cap('第二个：文字按钮', '')
    c += btn_states4('txt', '', '详情')
    return board('新设计 · 状态页', '一个状态组件：六种状态（骨架、加载、空、出错、受限、离线），四种场合（整页、区块、卡片、画面上）；结构固定：图标、一句话、一句原因、最多两个按钮', c)


OUT['v3-status'] = v3_status()
OUT['v4-status'] = v4_status()

# =====================================================================
# avatar, counter, QR
# =====================================================================
AV = IMG + '1.jpg'


def av(sz, kind='img', st='', cls=''):
    if kind == 'img':
        return f'<span class="x-av {cls}" style="width:{sz}px;height:{sz}px;background-image:url({AV});{st}"></span>'
    if kind == 'load3':
        return f'<span class="x-av" style="width:{sz}px;height:{sz}px;background:color-mix(in srgb,var(--on) 7.5%,transparent);{st}"></span>'
    if kind == 'init3':
        return (f'<span class="x-av" style="width:{sz}px;height:{sz}px;background:color-mix(in srgb,var(--on) 12%,transparent);'
                f'font-size:{sz * 0.4:.0f}px;{st}">晚</span>')
    if kind == 'none3':
        return f'<span class="x-av" style="width:{sz}px;height:{sz}px;background:color-mix(in srgb,var(--on) 12%,transparent);{st}"></span>'
    if kind == 'load4':
        return f'<span class="x-av" style="width:{sz}px;height:{sz}px;background:var(--scc);{st}"></span>'
    if kind == 'init4':
        return (f'<span class="x-av {cls}" style="width:{sz}px;height:{sz}px;background:var(--sc);color:var(--osc);font-weight:600;'
                f'font-size:{sz * 0.42:.0f}px;{st}">晚</span>')
    if kind == 'none4':
        return f'<span class="x-av" style="width:{sz}px;height:{sz}px;background:var(--sc);color:var(--osc);{st}">{mr("person", sz * 0.6)}</span>'


def c3(v='0', st=''):
    return (f'<div class="c3" style="{st}"><span class="m">{mr("remove")}</span><span class="v">{v}</span>'
            f'<span class="p">{mr("add")}</span></div>')


def c4(v='0', m='', p='', st=''):
    return (f'<div class="c4" style="{st}"><span class="m {m}">{mr("remove", 20)}</span><b>{v}</b>'
            f'<span class="p {p}">{mr("add", 20)}</span></div>')


def crow(title, ctr, cls='r3', st=''):
    if cls == 'r3':
        return f'<div class="r3" style="align-items:center;padding:12px 16px;{st}"><div class="x"><div class="a">{title}</div></div>{ctr}</div>'
    return f'<div class="lr" style="{st}"><div class="x"><div class="a">{title}</div></div>{ctr}</div>'


def qr_tile(px=156, pad=12, radius=0, overlay=''):
    return (f'<div class="qr" style="padding:{pad}px;border-radius:{radius}px;width:{px + pad * 2}px;height:{px + pad * 2}px">'
            f'{qr_svg(px)}{overlay}</div>')


def v3_misc():
    c = group('头像 CommonAvatar（common_avatar.dart）')
    c += cap('尺寸', '顶栏 32、小卡片 34、大卡片 40、口令导入 48（live_play_header.dart:33、room_card.dart:1010、share_command_import_dialog.dart:83）')
    c += '<div class="x-row" style="gap:18px;align-items:flex-end">' + ''.join(cell(av(s), str(s)) for s in (32, 34, 40, 48)) + '</div>'
    c += cap('加载中 / 没头像 / 没名字 / 加载失败', '加载中是禁用色 20%；没头像时禁用色 31% 底加名字首字；没名字是一个空灰圈；加载失败同没头像（:22-35、:58-59）')
    c += ('<div class="x-row" style="gap:18px">' + cell(av(40, 'load3'), '加载中') + cell(av(40, 'init3'), '没头像') + cell(av(40, 'none3'), '没名字')
          + cell(av(40, 'init3'), '加载失败') + '</div>')
    c += cap('可点的头像', '头像本身不处理点击，没有悬停、焦点、按下的样子')
    c += group('计数按钮 CountButton（count_button.dart）')
    c += cap('默认', '两块主色实心按钮，图标写死白色（:69-71），中间主色粗体数字；每块 48×48')
    c += box(crow('顶部留白（像素）', c3('0')))
    c += cap('悬停 / 键盘焦点 / 按下', 'ElevatedButton 的叠层；焦点没有框')
    c += box('<div style="display:flex;gap:14px;padding:12px;justify-content:center">'
             + cell('<div class="c3"><span class="m">' + mr('remove') + '</span><span class="v">0</span><span class="p ov3">' + mr('add') + '</span></div>', '悬停 ＋')
             + cell('<div class="c3"><span class="m">' + mr('remove') + '</span><span class="v">0</span><span class="p st-p">' + mr('add') + '</span></div>', '按下 ＋') + '</div>')
    c += cap('到下限', '“−”看起来照样能点，点了没有反应（:173-178）')
    c += box(crow('相同内容合并时间（秒）', c3('1')))
    c += cap('长按', '每 100 毫秒加减一次（:180-204），样子不变')
    c += cap('不可用', '没有不可用的样子：“合并相同弹幕”关掉时，合并时间这一行直接不显示（U.2f D5）')
    c += group('二维码（两套实现）')
    c += cap('设备同步 QrCodeWidget', '白底黑码，直角，内边距 12，180（qr_code_widget.dart、remote_sync_page.dart:226）')
    c += '<div class="x-row" style="justify-content:center;padding:6px 0">' + qr_tile() + '</div>'
    c += cap('哔哩哔哩扫码登录 BilibiliLoginQrCode', '另一套实现：卡片里，圆角 12，边长 140–180；下面一行状态（qr_login_page.dart:72-100）')
    st3 = lambda ic, t, hi: (f'<div style="display:flex;gap:8px;padding:12px 16px;border-radius:16px;{"background:color-mix(in srgb,var(--primary) 10%,transparent);color:var(--primary);font-weight:600" if hi else "color:var(--hint)"};font-size:13px;line-height:1.35;margin-top:14px">'
                             f'{r(ic, 18)}<span>{t}</span></div>')
    c += ('<div style="display:grid;grid-template-columns:1fr 1fr;gap:8px">'
          + '<div><div class="cd3" style="padding:12px;display:grid;place-items:center">' + qr_tile(120, 10, 12) + '</div>' + st3('qr_code_line', '请使用 哔哩哔哩 手机客户端扫码登录', False) + '<div class="x-lb">等待扫码</div></div>'
          + '<div><div class="cd3" style="padding:12px;display:grid;place-items:center">' + qr_tile(120, 10, 12) + '</div>' + st3('checkbox_circle_line', '已扫描，请在手机上确认登录', True) + '<div class="x-lb">已扫描</div></div>'
          + '</div>')
    c += cap('加载中 / 失效', '失效时二维码整个换成文字和按钮（:59-65、:183-215），下面的内容往上跳')
    c += ('<div style="display:grid;grid-template-columns:1fr 1fr;gap:8px">'
          + box('<div style="display:flex;flex-direction:column;align-items:center;padding:40px 8px;gap:20px"><span class="spin" style="width:28px;height:28px;border-width:3px;color:var(--primary)"></span><span style="font-size:14px">正在加载二维码…</span></div>')
          + box('<div style="padding:30px 8px;text-align:center">' + r('error_warning_line', 40, 'color:color-mix(in srgb,var(--hint) 40%,transparent)')
                + '<div style="font-size:14px;color:var(--hint);margin-top:12px">二维码已失效</div>'
                + f'<div class="tb3" style="margin-top:12px;font-weight:600">{r("refresh_line", 18)}刷新二维码</div></div>')
          + '</div>')
    return board('v3 · 头像、计数按钮、二维码', 'common_avatar.dart、count_button.dart、qr_code_widget.dart、bilibili_login_qr_code.dart', c)


def v4_misc():
    c = group('头像')
    c += cap('尺寸', '照 v3：顶栏 32、小卡片 34、大卡片 40、口令导入 48')
    c += '<div class="x-row" style="gap:18px;align-items:flex-end">' + ''.join(cell(av(s), str(s)) for s in (32, 34, 40, 48)) + '</div>'
    c += cap('加载中 / 没头像 / 没名字 / 加载失败', '加载中浅灰底；没头像是次色容器底加首字；没名字显示人形图标；失败同没头像')
    c += ('<div class="x-row" style="gap:18px">' + cell(av(40, 'load4'), '加载中') + cell(av(40, 'init4'), '没头像') + cell(av(40, 'none4'), '没名字')
          + cell(av(40, 'init4'), '加载失败') + '</div>')
    c += cap('可点的头像（直播间顶栏，U.2a E1）', '悬停加一层暗，按下更暗，键盘焦点主色框')
    c += ('<div class="x-row" style="gap:22px">' + cell(av(40), '默认') + cell(av(40, st='box-shadow:inset 0 0 0 40px rgba(0,0,0,.10)'), '悬停')
          + cell(av(40, st='outline:2px solid var(--primary);outline-offset:2px'), '键盘焦点') + cell(av(40, st='box-shadow:inset 0 0 0 40px rgba(0,0,0,.18)'), '按下') + '</div>')
    c += group('计数（U.2f 已确认的描边样式）')
    c += cap('默认', '描边 36 高（点击区域 48），图标次要色，数字主色等宽；单位写在名字里')
    c += box('<div class="ncd" style="margin:10px">' + crow('顶部留白（像素）', c4('0', m='dis'), 'lr') + '</div>')
    c += cap('悬停 / 键盘焦点 / 按下', '只亮被指着的那一半')
    c += box('<div style="display:flex;gap:14px;padding:12px;justify-content:center">'
             + cell('<div class="c4"><span class="m">' + mr('remove', 20) + '</span><b>12</b><span class="p st-h">' + mr('add', 20) + '</span></div>', '悬停 ＋')
             + cell('<div class="c4"><span class="m">' + mr('remove', 20) + '</span><b>12</b><span class="p st-f">' + mr('add', 20) + '</span></div>', '键盘焦点 ＋')
             + cell('<div class="c4"><span class="m">' + mr('remove', 20) + '</span><b>12</b><span class="p st-p">' + mr('add', 20) + '</span></div>', '按下 ＋') + '</div>')
    c += cap('到上下限', '到了下限“−”变灰，到了上限“＋”变灰')
    c += box('<div class="ncd" style="margin:10px">' + crow('相同内容合并时间（秒）', c4('1', m='dis'), 'lr') + crow('最大同时显示数量', c4('20', p='dis'), 'lr') + '</div>')
    c += cap('长按 / 键盘', '长按每 100 毫秒加减一次（照 v3）；键盘焦点在上面时 ← → 也能加减')
    c += cap('不可用', '整行变灰，不消失（U.2f D5）')
    c += box('<div class="ncd" style="margin:10px">' + crow('相同内容合并时间（秒）', c4('5'), 'lr', 'opacity:.38') + '</div>')
    c += group('二维码（一个组件）')
    c += cap('等待扫码', '白底黑码、内边距 12、圆角 12，放在卡片里；深色主题也是白底（扫得出来）；下面一行状态')
    hint = lambda ic, t, hi=False: (f'<div style="display:flex;gap:8px;justify-content:center;font-size:13px;margin-top:12px;color:{"var(--primary)" if hi else "var(--onv)"};{"font-weight:600" if hi else ""}">{r(ic, 18)}<span>{t}</span></div>')
    card = lambda inner, h: f'<div class="ncd" style="padding:14px;display:grid;place-items:center">{inner}</div>{h}'
    over = lambda inner: (f'<div style="position:absolute;inset:0;border-radius:12px;background:rgba(255,255,255,.92);display:flex;flex-direction:column;'
                          f'align-items:center;justify-content:center;gap:8px;color:#191C20;font-size:13px;font-weight:600;text-align:center">{inner}</div>')
    c += ('<div style="display:grid;grid-template-columns:1fr 1fr;gap:10px">'
          + '<div>' + card(qr_tile(120, 12, 12), hint('qr_code_line', '请使用 哔哩哔哩 手机客户端扫码登录')) + '<div class="x-lb">等待扫码</div></div>'
          + '<div>' + card('<div class="qr" style="padding:12px;border-radius:12px;width:144px;height:144px;background:#fff;display:grid;place-items:center">'
                           '<span class="spin" style="width:26px;height:26px;border-width:3px;color:#36618E"></span></div>', hint('qr_code_line', '正在加载二维码…')) + '<div class="x-lb">加载中（占位同大小）</div></div>'
          + '<div>' + card(qr_tile(120, 12, 12, over(mr('check_circle', 32, 'color:#36618E') + '<span>已扫描</span>')), hint('checkbox_circle_line', '已扫描，请在手机上确认登录', True)) + '<div class="x-lb">已扫描</div></div>'
          + '<div>' + card(qr_tile(120, 12, 12, over('<span>二维码已失效</span><span class="xb ton" style="background:#D7E3F7;color:#3B4858;height:36px">' + mr('refresh', 18) + '刷新</span>')), hint('error_warning_line', '二维码已失效，刷新后重新扫码')) + '<div class="x-lb">已失效（位置不动）</div></div>'
          + '</div>')
    c += cap('出错', '同“已失效”，文字写原因，按钮“重试”')
    return board('新设计 · 头像、计数、二维码', '同一个组件在各处一样；状态盖在原位置上，不换掉', c)


OUT['v3-misc'] = v3_misc()
OUT['v4-misc'] = v4_misc()

# =====================================================================
# tabs and chips
# =====================================================================


def tb(items, on=0, eq=False, extra='', cls='x-tb', st=''):
    t = ''
    for i, it in enumerate(items):
        label, add, sc = (it + ('', ''))[:3] if isinstance(it, tuple) else (it, '', '')
        t += f'<div class="t{" on" if i == on else ""}{sc}"><i>{label}{add}</i></div>'
    return f'<div class="{cls}{" eq" if eq else ""}" style="{st}">{t}{extra}</div>'


def chip3_fav(t, on=False):
    return (f'<span style="height:32px;padding:0 12px;border-radius:10px;display:inline-flex;align-items:center;font-size:12px;'
            f'{"background:var(--primary);color:var(--onPrimary);font-weight:700" if on else "background:var(--scl);color:var(--onv)"}">{t}</span>')


def chip3_search(t, on=False, logo=None):
    lg = f'<img src="{LOGO}{logo}.png" style="width:18px;height:18px;border-radius:4px">' if logo else ''
    return (f'<span style="height:32px;padding:0 10px;border-radius:8px;display:inline-flex;align-items:center;gap:6px;font-size:13px;font-weight:500;'
            f'{"background:var(--sc);box-shadow:inset 0 0 0 1px var(--primary)" if on else "box-shadow:inset 0 0 0 1px var(--ov)"}">{lg}{t}</span>')


def chip3_tpl(t, on=False):
    return (f'<span style="height:32px;padding:0 12px 0 8px;border-radius:8px;display:inline-flex;align-items:center;gap:6px;font-size:13px;font-weight:600;'
            f'{"background:var(--primary);color:var(--onPrimary)" if on else "background:var(--schh);box-shadow:inset 0 0 0 1px rgba(115,119,127,.35)"}">'
            f'{mr("check", 18) if on else mr("auto_awesome", 18)}{t}</span>')


PLAT = ['哔哩哔哩', '斗鱼', '虎牙', '抖音', '快手', '网易CC']


def v3_tabs():
    c = group('一级标签（tabBarTheme，theme.dart:122-130）')
    c += cap('等宽（直播间四个标签）', '15 号；选中主色 600，未选次要色 80%；指示条和文字一样宽；没有分隔线')
    c += box(tb(['弹幕列表', '醒目留言', '弹幕设置', '屏蔽管理'], 0, True))
    c += cap('可横滑（热门、分区的平台）', 'ScrollableTabBar：电脑上滚轮、鼠标拖动也能滚（scrollable_tab_bar.dart）')
    c += box(tb(PLAT, 0))
    c += cap('悬停 / 键盘焦点 / 按下', '整个标签一块叠层；主题关了水波（theme.dart:114）；键盘焦点没有框')
    c += box(tb([('醒目留言', '', ' st-h'), ('弹幕设置', '', ' ov3'), ('屏蔽管理', '', ' st-p')], -1, True))
    c += '<div class="x-row" style="justify-content:space-around;margin-top:2px"><span class="x-lb">悬停</span><span class="x-lb">键盘焦点</span><span class="x-lb">按下</span></div>'
    c += cap('数量、角标', '没有：醒目留言、已开播等标签不显示条数')
    c += group('标签芯片（三种样子）')
    c += cap('关注的分组', 'ChoiceChip，12 号，选中主色底白字粗体，圆角 10，一行高 60（favorite_page.dart:182-273）')
    c += '<div class="x-row" style="gap:8px">' + chip3_fav('全部', True) + chip3_fav('常看') + chip3_fav('游戏') + chip3_fav('电台') + '</div>'
    c += cap('搜索的平台条', '13 号 500，描边；选中次色容器、主色描边，不带勾（search_platform_strip.dart:63-95）')
    c += '<div class="x-row" style="gap:8px">' + chip3_search('全部', True) + chip3_search('哔哩哔哩', logo='bilibili') + chip3_search('斗鱼', logo='douyu') + chip3_search('虎牙', logo='huya') + '</div>'
    c += cap('弹幕观看模板', '13 号 600；选中主色底白字加勾，未选浅灰底（danmaku_settings_page.dart:97-157）')
    c += '<div class="x-row" style="gap:8px">' + chip3_tpl('顶部 20% · 均衡', True) + chip3_tpl('顶部 35% · 舒适') + '</div>'
    c += cap('悬停 / 键盘焦点 / 禁用', '各用 Flutter 默认的叠层；三种芯片三种默认')
    return board('v3 · 标签栏和标签芯片', 'ScrollableTabBar、tabBarTheme、ChoiceChip / FilterChip', c)


def ch4(t, on=False, st='', ic=''):
    return f'<span class="x-ch{" on" if on else ""} {st}">{mr("check", 18) if on else ""}{ic}{t}</span>'


def v4_tabs():
    bd = '<span class="bdg" style="margin-left:2px">2</span>'
    cnt = lambda n: f'<span class="n">{n}</span>'
    c = group('一级标签（样子照 v3）')
    c += cap('等宽，带角标', '“醒目留言”带条数角标（U.2a、U.2e）')
    c += box(tb(['弹幕列表', ('醒目留言', bd), '弹幕设置', '屏蔽管理'], 0, True))
    c += cap('带数量', '状态和平台标签带数量，等宽数字（U.4c c4）')
    c += box(tb([('已开播', cnt(12)), ('录播', cnt(1)), ('未开播', cnt(36))], 0, True))
    c += cap('可横滑，末尾“全部平台”', '平台多时末尾 ⌄ 打开“全部平台”面板（U.4b c2）；电脑上滚轮、拖动照 v3')
    c += box(tb(PLAT[:4], 0, extra='<div class="dd" style="margin-left:auto;box-shadow:-16px 0 16px var(--surface);background:var(--surface)">' + mr('expand_more') + '</div>'))
    c += cap('悬停 / 键盘焦点 / 按下 / 禁用', '叠层是标签自己那一块（圆角 8）；键盘焦点主色框，只在用键盘时显示；平台不提供时变灰（U.2e c7）')
    c += box(tb([('醒目留言', '', ' st-h'), ('弹幕设置', '', ' st-fi'), ('屏蔽管理', '', ' st-p'), ('不提供', '', ' dis')], -1, True, st='padding:0 6px'))
    c += '<div class="x-row" style="justify-content:space-around;margin-top:2px"><span class="x-lb">悬停</span><span class="x-lb">键盘焦点</span><span class="x-lb">按下</span><span class="x-lb">禁用</span></div>'
    c += group('二级标签（U.4d c2）')
    c += cap('分类', '14 号；选中深色 600，未选次要色；指示条铺满整个标签；下面一条分隔线；从左排')
    c += box(tb(['网游', '手游', '单机游戏', '虚拟主播', '娱乐'], 0, cls='x-tb2'))
    c += group('标签芯片（一种）')
    c += cap('默认 / 选中', '高 36（点击区域 48），圆角 8，14 号；选中次色容器加勾；可带平台图标（U.5a）')
    lg = lambda n: f'<img src="{LOGO}{n}.png">'
    c += '<div class="x-row" style="gap:8px">' + ch4('全部', True) + ch4('哔哩哔哩', ic=lg('bilibili')) + ch4('斗鱼', ic=lg('douyu')) + ch4('常看') + '</div>'
    c += cap('悬停 / 键盘焦点 / 按下 / 禁用', '')
    c += ('<div class="x-row" style="gap:12px">' + cell(ch4('常看', st='st-h'), '悬停') + cell(ch4('常看', st='st-f'), '键盘焦点')
          + cell(ch4('常看', st='st-p'), '按下') + cell(ch4('常看', st='dis'), '禁用') + '</div>')
    c += cap('用在', '关注的分组（U.4c）、搜索平台条（U.5a）、录制清晰度和观看模板（U.2f）、保留数量预设（U.5c）')
    return board('新设计 · 标签栏和标签芯片', '一级标签照 v3；补数量、角标、“全部平台”、二级标签；三种芯片合成一种', c)


OUT['v3-tabs'] = v3_tabs()
OUT['v4-tabs'] = v4_tabs()

# =====================================================================
# list rows and settings rows
# =====================================================================


def r3(icon, title, sub=None, trail='', sw=False, sub_err=False, st='', cls=''):
    ic = f'<div class="ic">{icon}</div>' if icon else ''
    return (f'<div class="r3{" rsw" if sw else ""} {cls}" style="{st}">{ic}<div class="x"><div class="a">{title}</div>'
            + (f'<div class="b{" e" if sub_err else ""}">{sub}</div>' if sub else '') + f'</div>{trail}</div>')


def sw(on=False, alt=False, hl=False, cls=''):
    return f'<span class="x-sw{" on" if on else ""}{" alt" if alt else ""} {cls}">{"<i class=hl></i>" if hl else ""}</span>'


CHEV3 = f'<div class="tv chev">{mr("chevron_right", 20)}</div>'


def lt3(icon, title, sub=None, st='', cls=''):
    return (f'<div class="lt3 {cls}" style="{st}">' + (f'<div class="ic">{icon}</div>' if icon else '')
            + f'<div><div class="a">{title}</div>' + (f'<div class="b">{sub}</div>' if sub else '') + '</div></div>')


def v3_rows():
    c = group('列表行（ListTile 主题，theme.dart:151-158）')
    c += cap('长按弹幕面板的行', '图标 24，标题 14 号 500，说明 13 号次要色（danmaku_message_actions.dart:15-52）')
    c += box(lt3(mr('copy_all'), '复制') + lt3(mr('person_off'), '屏蔽该用户的弹幕', '星河长明') + lt3(mr('filter_alt'), '屏蔽弹幕关键词', '前排支持！'))
    c += cap('悬停 / 键盘焦点 / 按下 / 选中', 'ListTile 叠层，焦点没有框；选中是主色 6% 底、主色字（theme.dart:156-157）')
    c += box(lt3(mr('copy_all'), '悬停', cls='st-h') + lt3(mr('copy_all'), '键盘焦点', cls='ov3') + lt3(mr('copy_all'), '按下', cls='st-p')
             + lt3(mr('copy_all', st='color:var(--primary)'), '<span style="color:var(--primary)">选中</span>', st='background:color-mix(in srgb,var(--primary) 6%,transparent)'))
    c += group('设置行（widget_extensions.dart）')
    c += cap('组标题 + 卡片', '组标题 12 号粗体、主色 65% 透明（:21-36）；卡片是表面容器最高色 15% 透明、5% 细边、圆角 20（:101-111）；行间分隔线 5%（:88-96）')
    c += ('<div class="g3t">音频设置</div><div class="cd3">' + r3(r('volume_up_line', 22), '全局静音', '所有直播间统一静音', f'<div style="padding-right:8px">{sw()}</div>', True)
          + '<div style="height:.5px;margin:0 16px;background:rgba(0,0,0,.05)"></div>'
          + r3(r('lightbulb_line', 22), '屏幕常亮', '当处于直播播放页，屏幕保持常亮', f'<div style="padding-right:8px">{sw(True)}</div>', True) + '</div>')
    c += cap('开关行（buildSwitchTile）', '图标 22 主色，标题 15 号 600，说明 12 号提示色 75%；开关是 M3 默认：开着主色底白滑块（:114-152）')
    c += cap('开关的另一种样子', '弹幕设置、小窗弹幕、平台显示、屏蔽管理、房间音量、定时关闭、导航栏显示、网络电视 8 处写了 activeThumbColor: primary：开着时底是主色 50% 透明、滑块是主色（Flutter switch.dart:979），和设置页不一样，滑块对比约 2.8:1')
    c += ('<div class="cd3">' + r3('', '弹幕描边', None, f'<div style="padding-right:8px">{sw(True, alt=True)}</div>', True)
          + r3('', '纯文字模式（隐藏表情）', None, f'<div style="padding-right:8px">{sw(False, alt=True)}</div>', True) + '</div>')
    c += cap('不可用 / 处理中 / 出错', '不可用整行变灰；处理中也只是变灰（video_settings_page.dart:184）；出错说明换错误色（:180-181）')
    c += ('<div class="cd3">' + r3(r('pushpin_line', 22), 'Windows 小窗始终置顶', '关闭后切换到其他应用时，小窗会按普通窗口层级被遮挡', f'<div style="padding-right:8px">{sw()}</div>', True, st='opacity:.38')
          + r3(r('music_2_line', 22), '后台播放', '更新后台播放设置失败，请重试', f'<div style="padding-right:8px">{sw(True)}</div>', True, sub_err=True) + '</div>')
    c += cap('选择行', '视频设置：值主色加粗、没有 ›，两行字号还不一样（video_settings_page.dart:133-136、:148-151）；另有 buildMenuTile（值灰色加 ›），代码里没有用到（:260-301）')
    c += ('<div class="cd3">' + r3(r('hd_line', 22), '首选清晰度', '当进入直播播放页，首选的视频清晰度', '<div class="tv" style="color:var(--primary);font-weight:600;font-size:14px">原画</div>')
          + r3(r('signal_tower_line', 22), '移动网络清晰度', '使用流量时的默认画质', '<div class="tv" style="color:var(--primary);font-weight:600;font-size:13px">原画</div>') + '</div>')
    c += cap('滑块行（buildSliderTile）', '标题 16 号 600，右边数值小块，Syncfusion 滑块（:352-454）')
    c += ('<div class="cd3"><div style="display:flex;gap:12px;padding:10px 16px"><div class="ic" style="width:24px;color:var(--primary);padding-top:2px">' + r('phone_line', 22) + '</div>'
          '<div style="flex:1"><div style="display:flex;align-items:flex-start;gap:12px"><div style="flex:1;font-size:16px;font-weight:600">手机端默认音量</div><span class="vbadge3">100%</span></div>'
          '<div class="x-sl v3" style="margin-left:-4px"><div class="tk"></div><div class="ac" style="width:100%"></div><div class="th" style="left:100%"></div></div></div></div></div>')
    c += cap('计数行', '标题 15 号 600 加计数按钮（danmaku_settings_page.dart:578-610）')
    c += '<div class="cd3">' + crow('顶部留白（像素）', c3('0')) + '</div>'
    c += cap('跳转行', '› 两种：buildTile 默认是提示色 40%、20 号（:227）；页面自己传的是默认色、24 号（video_settings_page.dart:166、:276）')
    c += ('<div class="cd3">' + r3(mr('stay_current_portrait', 22), '竖屏直播适配', '自动识别直播源方向，并统一普通页、全屏和小窗的显示策略', f'<div class="tv">{mr("chevron_right")}</div>')
          + r3(r('filter_2_line', 22), '弹幕关键词过滤', None, CHEV3) + '</div>')
    c += cap('窄屏（<360）或字体放大 1.5 倍', '值换到标题下面（:235-257）')
    c += ('<div style="width:300px"><div class="cd3">' + r3(r('hd_line', 22), '首选清晰度', '当进入直播播放页，首选的视频清晰度<div style="margin-top:8px;color:var(--primary);font-weight:600;font-size:14px">原画</div>') + '</div></div>')
    c += cap('悬停 / 键盘焦点 / 按下', '整行叠层；没有焦点框，没有水波')
    c += ('<div class="cd3">' + r3(r('filter_2_line', 22), '悬停', None, CHEV3, cls='st-h') + r3(r('filter_2_line', 22), '键盘焦点', None, CHEV3, cls='ov3')
          + r3(r('filter_2_line', 22), '按下', None, CHEV3, cls='st-p') + '</div>')
    return board('v3 · 列表行和设置行', 'ListTile 主题；buildGroupTitle、buildModernCard、buildSwitchTile、buildTile、buildSliderTile；CountButton', c, h=5200)


def lr(icon, title, sub=None, trail='', cls='', st='', ip=False, n=None, tag=None, sub_err=False):
    ic = f'<div class="ic{" p" if ip else ""}">{icon}</div>' if icon else ''
    return (f'<div class="lr {cls}" style="{st}"{dn(n, tag)}>{ic}<div class="x"><div class="a">{title}</div>'
            + (f'<div class="b{" e" if sub_err else ""}">{sub}</div>' if sub else '') + f'</div>{trail}</div>')


CHEV4 = f'<div class="tv">{mr("chevron_right")}</div>'
SEL4 = lambda v: f'<div class="tv">{v}{mr("expand_more", 20)}</div>'


def slr(icon, title, v, pct, th='', dis=False, n=None, tag=None):
    ic = f'<div class="ic p" style="width:24px;color:var(--primary)">{icon}</div>' if icon else ''
    vt = f'<div class="vt" style="left:{pct}%">{v}</div>' if th == 'f' and False else ''
    return (f'<div class="slr" style="{"opacity:.38" if dis else ""}"{dn(n, tag)}><div class="h">{ic}<div class="a">{title}</div><span class="vpill2">{v}</span></div>'
            f'<div class="x-sl" style="{"margin-left:46px" if icon else ""}"><div class="tk"></div><div class="ac" style="width:{pct}%"></div>'
            f'<div class="th {th}" style="left:{pct}%"></div>{vt}</div></div>')


def v4_rows():
    c = group('列表行（列表、面板、设置共用一个行组件）')
    c += cap('一行 / 两行', '图标 24 次要色，标题 15 号 400，说明 12 号次要色；最小高 56（U.2f 长按弹幕面板）')
    c += box(lr(mr('content_copy'), '复制') + lr(mr('person_off'), '屏蔽此用户', '星河长明 的弹幕都不再显示') + lr(mr('block'), '屏蔽关键词…', '输入一个词，含这个词的弹幕都不再显示'))
    c += cap('带头像、带操作', '头像 40；右边图标按钮点击区域 48')
    c += box(lr(f'<span class="x-av" style="width:40px;height:40px;background-image:url({IMG}1.jpg)"></span>', '晚风', '哔哩哔哩 · 房间号 21452505',
                f'<div class="ib2">{r("delete_bin_line", 22)}</div>', st='gap:12px'))
    c += cap('悬停 / 键盘焦点 / 按下 / 选中 / 禁用 / 危险', '叠层 8%、12%；键盘焦点主色框（只在用键盘时）；选中次色容器；危险动作错误色')
    c += box(lr(mr('content_copy'), '悬停', cls='st-h') + lr(mr('content_copy'), '键盘焦点', cls='st-fi') + lr(mr('content_copy'), '按下', cls='st-p')
             + lr(mr('check', st='color:var(--osc)'), '选中', cls='sel') + lr(mr('content_copy'), '禁用', st='opacity:.38')
             + lr(r('delete_bin_line'), '删除这条记录', cls='dng'))
    c += group('设置行（同一个行组件，右边换成开关、值、滑块、计数）')
    c += cap('组标题 + 卡片', '组标题 13 号 600 主色；卡片表面容器低、圆角 16（U.2f）；左边图标 24 主色（照 v3），面板里不放图标（U.2f）')
    c += ('<div class="nsec">音频设置</div><div class="ncd">' + lr(r('volume_up_line'), '全局静音', '所有直播间统一静音', sw(), ip=True)
          + lr(r('lightbulb_line'), '屏幕常亮', '当处于直播播放页，屏幕保持常亮', sw(True), ip=True) + '</div>')
    c += cap('开关只有一种', '开着主色底、白滑块（M3 默认）；去掉 activeThumbColor 的写法（修 U.4f 提的问题）')
    c += ('<div class="x-row" style="gap:14px 16px">' + cell(sw(), '关') + cell(sw(True), '开') + cell(sw(hl=True), '悬停（关）')
          + cell(sw(True, hl=True), '悬停（开）') + cell(sw(True, cls='st-f'), '键盘焦点') + cell(f'<span style="opacity:.38">{sw(True)}</span>', '禁用（开）')
          + cell(f'<span style="opacity:.38">{sw()}</span>', '禁用（关）') + '</div>')
    c += cap('处理中 / 出错', '处理中开关左边转圈、不能再拨；出错说明换错误色（照 v3）')
    c += ('<div class="ncd">' + lr(r('music_2_line'), '后台播放', '暂时切出 APP 时继续播放', f'<span class="spin" style="color:var(--primary);margin-right:4px"></span><span style="opacity:.38">{sw(True)}</span>', ip=True)
          + lr(r('music_2_line'), '后台播放', '更新后台播放设置失败，请重试', sw(), ip=True, sub_err=True) + '</div>')
    c += cap('选择行', '值（次要色）加 ⌄；点了弹选项对话框（U.1d），当前项主色加勾')
    c += ('<div class="ncd">' + lr(r('hd_line'), '首选清晰度', '当进入直播播放页，首选的视频清晰度', SEL4('原画'), ip=True)
          + lr(r('signal_tower_line'), '移动网络清晰度', '使用流量时的默认画质', SEL4('原画'), ip=True) + '</div>')
    c += cap('滑块行', '数值小块（U.2f）；悬停、拖动时滑块外圈；键盘焦点外加主色圈，← → 调')
    c += ('<div class="ncd">' + slr(r('phone_line'), '手机端默认音量', '100%', 100) + slr(r('phone_line'), '悬停', '60%', 60, 'h')
          + slr(r('phone_line'), '键盘焦点', '60%', 60, 'f') + slr(r('phone_line'), '禁用', '60%', 60, dis=True) + '</div>')
    c += cap('计数行', 'U.2f 的描边计数（见“头像、计数、二维码”）')
    c += '<div class="ncd">' + crow('顶部留白（像素）', c4('0', m='dis'), 'lr') + '</div>'
    c += cap('跳转行', '› 次要色 24；可以带当前值')
    c += ('<div class="ncd">' + lr(mr('stay_current_portrait'), '竖屏直播适配', '自动识别直播源方向，并统一普通页、全屏和小窗的显示策略', CHEV4, ip=True)
          + lr(r('font_size'), '更换弹幕字体', '当前字体: 系统默认', CHEV4, ip=True) + '</div>')
    c += cap('窄屏（<360）或字体放大 1.5 倍', '值、滑块、计数换到标题下面（照 v3）')
    c += ('<div style="width:300px"><div class="ncd">' + lr(r('hd_line'), '首选清晰度', '当进入直播播放页，首选的视频清晰度'
          + '<div style="margin-top:6px;font-size:14px;color:var(--onv);display:flex;align-items:center">原画' + mr('expand_more', 20) + '</div>', ip=True) + '</div></div>')
    c += cap('悬停 / 键盘焦点 / 按下', '整行叠层；键盘焦点主色框')
    c += ('<div class="ncd">' + lr(r('filter_2_line'), '悬停', None, CHEV4, cls='st-h', ip=True) + lr(r('filter_2_line'), '键盘焦点', None, CHEV4, cls='st-fi', ip=True)
          + lr(r('filter_2_line'), '按下', None, CHEV4, cls='st-p', ip=True) + '</div>')
    return board('新设计 · 列表行和设置行', '一个行组件：左边图标或头像，中间标题和说明，右边开关、值、滑块、计数或 ›；样子照 U.2f 已确认的面板行', c, h=5200)


OUT['v3-rows'] = v3_rows()
OUT['v4-rows'] = v4_rows()

# =====================================================================
# list shell (scroll)
# =====================================================================


def lines(n=3):
    return ''.join('<div style="display:flex;gap:10px;padding:10px 14px"><span style="width:56px;height:32px;border-radius:8px;background:var(--scl)"></span>'
                   '<div style="flex:1"><div style="height:9px;border-radius:5px;background:var(--scl);width:70%"></div>'
                   '<div style="height:9px;border-radius:5px;background:var(--scl);width:40%;margin-top:8px"></div></div></div>' for _ in range(n))


def rf(icon, main, sub=None, rot=0):
    return (f'<div class="rf">{icon}<div class="w"><b>{main}</b>' + (f'<small>{sub}</small>' if sub else '') + '</div></div>')


def v3_scroll():
    arrow = lambda d, rot=0: mr(f'arrow_{d}ward', 24, f'color:var(--outline);transform:rotate({rot}deg)')
    c = group('刷新')
    c += cap('刷新进度条', '有内容时刷新：顶上 2.5 高的主色进度条（base_page_view.dart:180-198）')
    c += box('<div style="height:2.5px;background:linear-gradient(90deg,transparent 15%,var(--primary) 15% 55%,transparent 55%)"></div>' + lines(2))
    c += cap('下拉刷新（手指往下拉）', '写的是“上拉刷新”，字反了（plugins/global.dart:17-24）')
    c += box(rf(arrow('down'), '上拉刷新', '上次加载时间 21:36') + lines(1))
    c += cap('拉够了，松手前', '“松开加载”')
    c += box(rf(arrow('down', 180), '松开加载', '上次加载时间 21:36'))
    c += cap('正在刷新', '小转圈 + “正在刷新...”；完成后“加载成功”')
    c += box(rf('<div class="ring3"></div>', '正在刷新...', '上次加载时间 21:36'))
    c += cap('上拉加载（手指往上拉）', '写的是“下拉加载”，也反了（:40-48）；到底“没有更多数据了”')
    c += box(lines(1) + rf(arrow('up'), '下拉加载', '上次加载时间 21:36'))
    c += box(rf('', '没有更多数据了'), style='margin-top:8px')
    c += group('回到顶部 / 回到底部')
    c += cap('滚过 400 出现', '小号浮动按钮 40×40（点击区域不到 48），cardColor：浅色白、深色灰 #424242（base_page_view_extension.dart:64-99）')
    c += box('<div style="display:flex;justify-content:flex-end;gap:24px;padding:14px 20px">'
             + cell('<div class="fab3">' + mr('arrow_upward') + '</div>', '回到顶部') + cell('<div class="fab3">' + mr('arrow_downward') + '</div>', '回到底部')
             + cell('<div class="fab3 st-h">' + mr('arrow_upward') + '</div>', '悬停') + '</div>')
    c += group('页顶说明、流量提醒')
    c += cap('平台说明', '12 号，没有底色（base_page_view.dart:78-82）')
    c += box('<div style="padding:8px 12px 4px;font-size:12px;color:var(--on);line-height:1.5">CHZZK 仅返回正在直播的频道，海外平台需要可用的网络代理。</div>' + lines(1))
    c += cap('流量提醒', '主色容器 25% 底、圆形图标、“不再显示”（:258-307）')
    c += ('<div style="margin:4px 0;padding:10px 14px;border-radius:12px;background:color-mix(in srgb,var(--pc) 25%,transparent);border:1px solid color-mix(in srgb,var(--primary) 15%,transparent)">'
          '<div style="display:flex;gap:12px"><span style="padding:8px;border-radius:50%;background:color-mix(in srgb,var(--primary) 10%,transparent);color:var(--primary);display:grid">' + mr('signal_cellular_alt', 18) + '</span>'
          '<span style="font-size:13px;font-weight:500;color:var(--onv);line-height:1.3">您当前正在使用移动蜂窝流量，请注意流量消耗。</span></div>'
          '<div style="text-align:right"><span class="tb3 ni" style="font-weight:700">不再显示</span></div></div>')
    c += group('电脑翻页栏')
    c += cap('', '刷新、上一页、页码、下一页、每页、跳转至（desktop_components.dart:94-188）；样子见 U.4b、U.4e 的宽屏图，这一版照 v3 不改')
    return board('v3 · 滚动和列表外壳', 'BasePageView、EasyRefresh 的刷新头和加载尾、回到顶部 / 底部、页顶提示', c)


def v4_scroll():
    arrow = lambda d, rot=0: mr(f'arrow_{d}ward', 24, f'color:var(--onv);transform:rotate({rot}deg)')
    c = group('刷新')
    c += cap('刷新进度条', '照 v3')
    c += box('<div style="height:2.5px;background:linear-gradient(90deg,transparent 15%,var(--primary) 15% 55%,transparent 55%)"></div>' + lines(2))
    c += cap('下拉刷新（手指往下拉）', '“下拉刷新”（改对）；保留上次加载时间')
    c += box(rf(arrow('down'), '下拉刷新', '上次加载时间 21:36') + lines(1))
    c += cap('拉够了，松手前', '“松开刷新”')
    c += box(rf(arrow('down', 180), '松开刷新', '上次加载时间 21:36'))
    c += cap('正在刷新 / 刷新失败', '转圈随“加载样式”；失败写一句，并在页顶出错横幅（见“状态页”）')
    c += box(rf('<div class="ring3"></div>', '正在刷新...', '上次加载时间 21:36'))
    c += box(rf(mr('error_outline', 24, 'color:var(--error)'), '刷新失败', '网络连接超时'), style='margin-top:8px')
    c += cap('上拉加载（手指往上拉）', '“上拉加载”；到底“没有更多数据了”；失败“加载失败，点这里重试”')
    c += box(lines(1) + rf(arrow('up'), '上拉加载'))
    c += ('<div style="display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-top:8px">' + box(rf('', '没有更多数据了'))
          + box('<div class="rf" style="color:var(--primary)">' + mr('refresh', 20) + '<b style="font-size:14px;font-weight:600">加载失败，点这里重试</b></div>') + '</div>')
    c += group('回到顶部 / 回到底部')
    c += cap('滚过 400 出现', '看起来 40，点击区域 48（虚线是点击区域）；表面容器最高色加浮层阴影；电脑悬停、键盘焦点；设置里可关（照 v3）')
    c += box('<div style="display:flex;justify-content:flex-end;gap:16px;padding:14px 20px">'
             + cell('<div class="hit"><div class="fab4">' + mr('arrow_upward') + '</div></div>', '回到顶部')
             + cell('<div class="hit"><div class="fab4">' + mr('arrow_downward') + '</div></div>', '回到底部')
             + cell('<div class="hit"><div class="fab4 st-h">' + mr('arrow_upward') + '</div></div>', '悬停')
             + cell('<div class="hit"><div class="fab4 st-f">' + mr('arrow_upward') + '</div></div>', '键盘焦点') + '</div>')
    c += group('页顶说明、流量提醒、出错')
    c += cap('', '合成一个页顶横幅，三种颜色（见“状态页”最后一组）')
    c += group('电脑翻页栏')
    c += cap('', '照 v3（U.4b c1）；页码、上一页、下一页点击区域 48，键盘焦点主色框')
    return board('新设计 · 滚动和列表外壳', '刷新、加载更多、回到顶部 / 底部；滚动手感照 v3（Android 和电脑不回弹，苹果回弹，Windows 滚轮平滑）', c)


OUT['v3-scroll'] = v3_scroll()
OUT['v4-scroll'] = v4_scroll()

# =====================================================================
# screens: settings page (phone, wide), status in landscape
# =====================================================================
APPBAR3 = ('<div class="appbar"><div class="back">' + mi('arrow_back') + '</div>'
           '<div style="flex:1;text-align:center;font-size:20px;font-weight:600;margin-right:56px">视频设置</div></div>')


def appbar4(n=None):
    return ('<div class="appbar"><div class="back"' + dn(n, 'keep') + '>' + mi('arrow_back') + '</div>'
            '<div style="flex:1;text-align:center;font-size:20px;font-weight:600;margin-right:56px">视频设置</div></div>')


def settings3(maxw=None):
    sw8 = lambda on=False: f'<div style="padding-right:8px">{sw(on)}</div>'
    div = '<div style="height:.5px;margin:0 16px;background:rgba(0,0,0,.05)"></div>'
    body = ('<div class="g3t">音频设置</div><div class="cd3">' + r3(r('volume_up_line', 22), '全局静音', '所有直播间统一静音', sw8(), True) + div
            + '<div style="display:flex;gap:12px;padding:10px 16px"><div style="width:24px;color:var(--primary);padding-top:2px">' + r('phone_line', 22) + '</div>'
            '<div style="flex:1"><div style="display:flex;align-items:flex-start;gap:12px"><div style="flex:1;font-size:16px;font-weight:600">手机端默认音量</div><span class="vbadge3">100%</span></div>'
            '<div class="x-sl v3" style="margin-left:-4px"><div class="tk"></div><div class="ac" style="width:100%"></div><div class="th" style="left:100%"></div></div></div></div></div>'
            '<div style="height:20px"></div><div class="g3t">画质设置</div><div class="cd3">'
            + r3(r('hd_line', 22), '首选清晰度', '当进入直播播放页，首选的视频清晰度', '<div class="tv" style="color:var(--primary);font-weight:600;font-size:14px">原画</div>') + div
            + r3(r('signal_tower_line', 22), '移动网络清晰度', '使用流量时的默认画质', '<div class="tv" style="color:var(--primary);font-weight:600;font-size:13px">原画</div>') + '</div>'
            '<div style="height:20px"></div><div class="g3t">播放行为设置</div><div class="cd3">'
            + r3(mr('stay_current_portrait', 22), '竖屏直播适配', '自动识别直播源方向，并统一普通页、全屏和小窗的显示策略', f'<div class="tv">{mr("chevron_right")}</div>') + div
            + r3(mr('groups_2', 22), '观看数据与排行口径', '在平台热度和真实在线人数之间切换，并单独管理支持的平台', f'<div class="tv">{mr("chevron_right")}</div>') + div
            + r3(r('music_2_line', 22), '后台播放', '暂时切出 APP 时继续播放；手动纯音频同样遵循此开关，自动助眠会话按计时继续', sw8(), True) + div
            + r3(r('moon_clear_line', 22), '新直播间自动助眠', '开启后，进入新的直播间会自动切换为纯音频，并按下方时长停止播放；耳机按钮只切换当前直播间', sw8(), True) + '</div>')
    st = f'max-width:{maxw}px;margin:0 auto;' if maxw else ''
    return f'<div style="padding:12px 16px"><div style="{st}">{body}</div></div>'


def settings4(maxw=None, n=False):
    N = (lambda k: k) if n else (lambda k: None)
    body = ('<div class="nsec" style="padding-top:8px">音频设置</div><div class="ncd">'
            + lr(r('volume_up_line'), '全局静音', '所有直播间统一静音', sw(), ip=True, n=N(2), tag='chg')
            + slr(r('phone_line'), '手机端默认音量', '100%', 100, n=N(3), tag='chg') + '</div>'
            '<div class="nsec">画质设置</div><div class="ncd">'
            + lr(r('hd_line'), '首选清晰度', '当进入直播播放页，首选的视频清晰度', SEL4('原画'), ip=True, n=N(4), tag='chg')
            + lr(r('signal_tower_line'), '移动网络清晰度', '使用流量时的默认画质', SEL4('原画'), ip=True) + '</div>'
            '<div class="nsec">播放行为设置</div><div class="ncd">'
            + lr(mr('stay_current_portrait'), '竖屏直播适配', '自动识别直播源方向，并统一普通页、全屏和小窗的显示策略', CHEV4, ip=True, n=N(5), tag='chg')
            + lr(mr('groups_2'), '观看数据与排行口径', '在平台热度和真实在线人数之间切换，并单独管理支持的平台', CHEV4, ip=True)
            + lr(r('music_2_line'), '后台播放', '暂时切出 APP 时继续播放；手动纯音频同样遵循此开关，自动助眠会话按计时继续', sw(), ip=True)
            + lr(r('moon_clear_line'), '新直播间自动助眠', '开启后，进入新的直播间会自动切换为纯音频，并按下方时长停止播放；耳机按钮只切换当前直播间', sw(), ip=True) + '</div>')
    st = f'max-width:{maxw}px;margin:0 auto;' if maxw else ''
    return f'<div style="padding:4px 16px 12px"><div style="{st}">{body}</div></div>'


OUT['v3-settings-phone'] = page(393, 852, 3, STATUS + APPBAR3 + settings3() + GESTURE, frame='ph')
OUT['v4-settings-phone'] = page(393, 852, 3, STATUS + appbar4(1) + settings4(n=True) + GESTURE, frame='ph')

WIN_BAR = ('<div style="height:32px;display:flex;align-items:center;padding-left:14px;font-size:12px;color:var(--onv);background:var(--surface)">纯粹直播'
           '<span style="margin-left:auto;display:flex">' + ''.join(f'<span style="width:46px;height:32px;display:grid;place-items:center">{mr(i, 16)}</span>' for i in ('remove', 'crop_square', 'close')) + '</span></div>')
OUT['v3-settings-wide'] = page(1280, 800, 1.5, WIN_BAR + APPBAR3 + settings3(960), frame='win')
OUT['v4-settings-wide'] = page(1280, 800, 1.5, WIN_BAR + appbar4() + settings4(720), frame='win')


def rail(on=1):
    items = [('heart_3', '关注'), ('fire', '热门'), ('apps_2', '分区')]
    codes = {'heart_3': ('ee0b', 'ee0a'), 'fire': ('ed33', 'ed32'), 'apps_2': ('ea42', 'ea41')}
    out = '<div style="width:80px;flex:none;display:flex;flex-direction:column;align-items:center;gap:6px;padding-top:6px;border-right:1px solid var(--ov)">'
    out += f'<div class="ib">{mr("menu")}</div>'
    for i, (k, t) in enumerate(items):
        c0, c1 = codes[k]
        sel = i == on
        out += (f'<div style="display:flex;flex-direction:column;align-items:center;gap:2px;font-size:12px;{"font-weight:600" if sel else "color:var(--onv)"}">'
                f'<span style="width:56px;height:30px;border-radius:15px;display:grid;place-items:center;{"background:var(--sc)" if sel else ""}">{rx(c1 if sel else c0, 22)}</span>{t}</div>')
    return out + '</div>'


def land(status_html):
    tabs = tb(['哔哩哔哩', '斗鱼', '虎牙', '抖音', '快手', '网易CC', 'Twitch'], 0, st='justify-content:center;height:48px')
    return page(852, 393, 2, '<div style="display:flex;height:100%">' + rail() + '<div style="flex:1;display:flex;flex-direction:column;min-width:0">'
                + '<div style="height:24px"></div>' + tabs + f'<div style="flex:1;display:flex;align-items:center;justify-content:center;overflow:hidden">{status_html}</div></div></div>',
                frame='fs', style='background:var(--surface)')


OUT['v3-status-land'] = land(s3(mr('wifi_off', 42), '网络请求失败', DIO_412, '重试'))
OUT['v4-status-land'] = land('<div class="s4" style="flex-direction:row;text-align:left;gap:20px;padding:0 32px"><div class="o" style="width:64px;height:64px">' + mr('error_outline', 32)
                             + '</div><div><div class="t" style="margin-top:0">加载失败</div><div class="s" style="max-width:360px">平台拒绝了请求（412），可能是请求太频繁，稍后再试</div>'
                             + '<div class="bs" style="justify-content:flex-start;margin-top:12px"><div class="xb ton">' + mr('refresh') + '重试</div><div class="xb txt">详情</div></div></div></div>')

if __name__ == '__main__':
    for name, html in OUT.items():
        open(os.path.join(HERE, name + '.html'), 'w', encoding='utf-8').write(html)
    print(len(OUT), 'pages')
