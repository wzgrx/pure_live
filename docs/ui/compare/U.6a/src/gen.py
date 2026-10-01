"""U.6a settings overview: v3 restored and the new design.
v3: lib/modules/settings/settings_page.dart (11 groups, 13 rows, config
preview in the app bar), lib/common/widgets/widget_extensions.dart (group
title, card, tile; content at most 960 wide).
    python3 docs/ui/compare/U.6a/src/gen.py && python3 tools/ui/mock/render.py docs/ui/compare/U.6a/src/ --annotate"""
import os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from skit import *  # noqa: E402,F401

# ---------- v3 (settings_page.dart:56-178, texts from zh.json) ----------
V3 = [
    ('主题设置', [(rx('efc5'), '主题定制', '自定义应用皮肤、夜间模式与主色调')]),
    ('IPTV 设置', [(rx('f237'), 'IPTV 设置', '管理您的播放列表和 EPG 订阅源')]),
    ('刷新设置', [(rx('f064'), '刷新设置', '配置关注状态和直播缩略图的自动刷新')]),
    ('视频设置', [(rx('ed21'), '视频', '调整解码器、弹幕、屏幕比例与亮度性能'),
              (rx('eff0'), '小窗弹幕', '配置 Android 系统画中画、Windows 小窗和应用内悬浮窗的弹幕样式')]),
    ('播放内核设置', [(rx('ebf0'), '播放器内核', '切换播放器内核')]),
    ('网络与代理设置', [(rx('edcf'), '自定义网络代理', '配置全应用核心数据请求与视频流播放代理')]),
    ('本地用户与互动', [(AUTO, '本地互动体验', '设置本地昵称、头衔、字幕、体验币与礼物效果')]),
    ('通用设置', [(rx('f0e8'), '通用', '修改自动开机自启、弹窗提示设置'),
              (rx('ef3e'), '导航栏显示控制', '自由定制隐藏或显示底部导航栏特定功能板块'),
              (rx('ea42'), '平台显示与授权', '修改直播平台显示')]),
    ('数据管理', [(rx('ec16'), '缓存与数据管理', '清理图片缓存、视频缓存')]),
    ('备份管理', [(rx('eb9d'), '备份与恢复', '一键导出您的本地配置或从云端导入')]),
]


def v3_list():
    out = []
    for i, (g, rows) in enumerate(V3):
        if i:
            out.append('<div class="g3"></div>')
        out.append(gt3(g) + card3([t3(ic, t, s) for ic, t, s in rows]))
    return ''.join(out)


def v3_action(compact):
    if compact:  # width < 520: icon only (settings_page.dart:35-41)
        return f'<div class="ib">{rx("ed0f", 20)}</div><div style="width:8px"></div>'
    return f'<div class="tb">{rx("ed0f", 18)}配置预览</div><div style="width:8px"></div>'


def v3_phone():
    body = STATUS + ab3('设置', v3_action(True)) + f'<div class="b3">{v3_list()}</div>'
    return doc(393, 2400, 2, body, crop=True)


def v3_land():
    body = (STATUS_LAND + ab3('设置', v3_action(False)) + f'<div class="b3" style="padding-top:12px">{v3_list()}</div>')
    return doc(852, 393, 2, body, root='win')


def v3_wide():
    body = ab3('设置', v3_action(False)) + f'<div class="b3"><div style="max-width:960px;margin:0 auto">{v3_list()}</div></div>'
    return doc(1280, 800, 1.5, body, root='win')


def v4_phone():
    body = (STATUS + ab('设置', n_back=1) + f'<div style="padding:4px 16px 4px">{search(n=2, tag="add")}</div>'
            + f'<div class="sb">{v4_list()}</div>')
    return doc(393, 2400, 2, body, crop=True)


def search_results():
    m = lambda s: f'<mark>{s}</mark>'
    res = (f'<div class="crumb"><b>外观</b> › 字体和字号</div>'
           + card([row(rx('ed8b'), m('字体'), '下载和切换应用使用的' + m('字体'), 'link', '系统默认', n=20, tag='add'),
                   slider(rx('f1ff'), '文字大小', '100%', 33.3, sub='在系统' + m('字体') + '大小的基础上放大或缩小', n=21, tag='add')])
           + f'<div class="crumb"><b>视频</b> › 弹幕设置</div>'
           + card([row(rx('ed8b'), '更换弹幕' + m('字体'), None, 'link', '系统默认')])
           + f'<div class="crumb"><b>弹幕</b> › 样式</div>'
           + card([slider(rx('ed8d'), m('字体') + '大小', '16', 40),
                   row(rx('ead1'), m('字体') + '粗细', None, 'choice', '稍粗')]))
    body = (STATUS + ab('设置') + f'<div style="padding:4px 16px 4px">{search("字体", n=2, tag="add", clear_n=19)}</div>'
            + f'<div class="sb" style="padding-top:0">{res}</div>')
    return body


def search_empty():
    empty = ('<div style="padding:72px 32px 0;text-align:center;color:var(--onv)">'
             f'<div style="width:72px;height:72px;border-radius:36px;background:var(--sch);display:grid;place-items:center;margin:0 auto 16px">{rx("f0d1", 32, "color:var(--onv)")}</div>'
             '<div style="font-size:16px;font-weight:600;color:var(--on)">没有找到相关设置</div>'
             '<div style="font-size:13px;margin-top:8px;line-height:1.6">换个说法试试，例如“弹幕速度”“代理”“画质”</div></div>')
    return STATUS + ab('设置') + f'<div style="padding:4px 16px 4px">{search("弹幕颜色渐变")}</div>' + empty


def v4_search():
    return canvas([search_results(), search_empty()], ['搜索“字体”：结果就是设置行本身', '没有结果'])


def pane(w, h, scale, status='', n=True):
    return two_pane(w, h, scale, '外观', appearance_v4(desktop=True), status=status, n_left=n,
                    title_attrs=attrs(22 if n else None, 'chg', 'tl'))


def v4_wide():
    return pane(1280, 800, 1.5)


def v4_land():
    return pane(852, 393, 2, STATUS_LAND, n=False)


def v4_desktop():
    return pane(1920, 1080, 1, n=False)


# ---------- the settings row (U.1c): kinds and states ----------
def rows_sheet():
    lab = lambda t: f'<div class="crumb" style="padding:18px 4px 8px">{t}</div>'
    tv = ('<div style="background:#111418;border-radius:16px;padding:20px 16px;margin-top:4px">'
          '<div style="background:#1D2024;border-radius:16px;overflow:visible">'
          '<div class="sr" style="transform:scale(1.05);background:#272A2F;border-radius:12px;box-shadow:0 0 0 3px rgba(255,255,255,.92);min-height:72px">'
          f'<span class="ic" style="color:#A0CAFD">{rx("ef6f", 24)}</span><div class="x"><div class="a" style="font-size:17px;color:#E1E2E8">主题模式</div>'
          '<div class="b" style="font-size:14px;color:#C3C7CF">切换系统/亮色/暗色模式</div></div><span class="v" style="font-size:15px;color:#C3C7CF">深色模式</span>'
          '<span class="chev mr" style="color:#C3C7CF">chevron_right</span></div>'
          '<div class="sr" style="min-height:72px"><span class="ic" style="color:#A0CAFD">' + rx('eeea', 24) + '</span><div class="x"><div class="a" style="font-size:17px;color:#E1E2E8">动态取色</div>'
          '<div class="b" style="font-size:14px;color:#C3C7CF">启用Monet壁纸动态取色</div></div><span class="sw" style="border-color:#8D9199;background:#32353A"></span></div>'
          '</div></div>')
    big = ('<div class="scd"><div class="sr" style="align-items:flex-start;padding-top:14px;padding-bottom:14px">'
           f'<span class="ic" style="font-size:30px;width:30px">{rx("ef6f", 30)}</span><div class="x"><div class="a" style="font-size:22px">主题模式</div>'
           '<div class="b" style="font-size:18px">切换系统/亮色/暗色模式</div>'
           '<div style="display:flex;align-items:center;gap:4px;margin-top:8px;font-size:20px;color:var(--onv)">跟随系统' + mr('chevron_right', 28, 'color:var(--onv)') + '</div></div></div></div>')
    body = (STATUS + ab('设置行（通用组件）') + '<div class="sb" style="padding-top:0">'
            + lab('1 跳转：打开子页，右边可以带当前值') + card([row(rx('ed8b'), '字体', '下载和切换应用使用的字体', 'link', '系统默认', n=1, tag='add')])
            + lab('2 开关：点整行就切换') + card([row(rx('eeea'), '动态取色', '启用Monet壁纸动态取色', 'switch', n=2, tag='add'),
                                         row(rx('ea72'), '显示一键置顶按钮', '列表滑动超过设定距离后在右下角悬浮置顶按钮', 'switch', sw=True)])
            + lab('3 选择：显示当前值，点开对话框选（照 v3）；颜色行显示色块') + card([row(rx('ef6f'), '主题模式', '切换系统/亮色/暗色模式', 'choice', '跟随系统', n=3, tag='add'),
                                                             row(rx('efc5'), '主题颜色', '切换软件的主题颜色', 'color', '#2196F3')])
            + lab('3′ 选择（行内）：两三个短选项直接摆出来（照 v3 房间卡片）') + card([row(rx('ee90'), '卡片布局', '选择大图封面卡片，或不显示大封面的紧凑主播信息行', 'none',
                                                                               extra=chips(['封面卡片', '紧凑信息行'], on=0, indent=0))])
            + lab('4 滑块：右边显示数值，拖动立即生效') + card([slider(rx('f1ff'), '文字大小', '100%', 33.3, sub='在系统字体大小的基础上放大或缩小', n=4, tag='add')])
            + lab('5 计数：− 和 + 一次改 1，点数字可以直接输入') + card([row(rx('ea62'), '列间距 (横向)', '调整同一行中左右卡片之间的水平缝隙', 'counter', '6 px', n=5, tag='add')])
            + lab('状态：按下 / 键盘焦点 / 鼠标悬停 / 不能用（写明原因）/ 处理中')
            + card([row(rx('ef6f'), '按下', None, 'choice', '跟随系统', cls='prs'),
                    row(rx('ef6f'), '键盘焦点（只在用键盘时显示）', None, 'choice', '跟随系统', cls='foc'),
                    row(rx('ef6f'), '鼠标悬停', None, 'choice', '跟随系统', cls='hov'),
                    row(rx('ebd4'), '纯黑背景', '浅色模式下不起作用：先把主题模式换成深色或跟随系统', 'switch', cls='dis'),
                    row(rx('ec16'), '清空本地缓存', '正在清理…', 'spin')])
            + lab('系统字体放大 1.5 倍、或宽度不到 360：右边的值换到标题下面') + big
            + lab('电视：同一个组件的电视样式（焦点放大 1.05 倍、近白描边、字大一级）') + tv
            + '</div>')
    return doc(393, 2600, 2, body, crop=True)


OUT = {
    'v3-settings': v3_phone(), 'v3-settings-land': v3_land(), 'v3-settings-wide': v3_wide(),
    'v4-settings': v4_phone(), 'v4-settings-search': v4_search(), 'v4-settings-land': v4_land(),
    'v4-settings-wide': v4_wide(), 'v4-settings-desktop': v4_desktop(), 'v4-rows': rows_sheet(),
}
for name, html in OUT.items():
    open(os.path.join(HERE, name + '.html'), 'w', encoding='utf-8').write(html)
print(len(OUT), 'pages')
