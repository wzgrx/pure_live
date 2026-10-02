"""U.15a TV design system and shared components: pure_live_TV restored (v3-*)
and the new design (v4-*), 960x540 logical (1920x1080 TV).

pure_live_TV sources (~/ref/pure_live_TV/lib):
  core/widgets/tv_focusable.dart, tv_focus_style.dart, tv_button.dart, tv_icon_button.dart,
  tv_tab_bar.dart, tv_room_card.dart, tv_cover_chip.dart, tv_area_card.dart,
  tv_settings_row.dart (+ switch / nav / option / slider / menu tiles), tv_app_bar.dart,
  app_status_view.dart, empty_scene.dart, core/dialog/*.dart,
  core/utils/favorite_operation_util.dart (card long press), domains/device/global_room_push.dart.
Shared builders: tvkit.py (also used by U.15b and U.15c).
    python3 docs/ui/compare/U.15a/src/gen.py && python3 tools/ui/mock/render.py docs/ui/compare/U.15a/src/ --annotate"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from tvkit import *  # noqa: E402,F401,F403

CSS = '''
.lbl{font:400 10px/1.35 'Noto Sans SC';color:#9AA0A6;margin-top:8px;text-align:center}
.lbl4{font:400 12px/1.4 'Noto Sans SC';color:var(--onv);margin-top:10px;text-align:center}
.sec3{font:600 11px 'Noto Sans SC';color:#9AA0A6;margin:0 0 22px}
.sec4{font:600 14px 'Noto Sans SC';color:var(--onv);margin:0 0 22px}
.cell{display:flex;flex-direction:column;align-items:center}
.rowx{display:flex;align-items:flex-start;gap:22px}
'''


def lbl(t, v4=False):
    return f'<div class="{"lbl4" if v4 else "lbl"}">{t}</div>'


def cell(inner, label, v4=False, w=None):
    st = f' style="width:{w}px"' if w else ''
    return f'<div class="cell"{st}>{inner}{lbl(label, v4)}</div>'


# ---------------- 1. focus / buttons / tabs / rail tiles / cards ----------------
def parts3():
    b = (cell(btn3('确定', size='l'), 'large') + cell(btn3('确定', size='m'), 'medium') + cell(btn3('确定', size='s'), 'small')
         + cell(btn3('确定'), 'mini') + cell(btn3('确定', size='m', kind='f fmk'), '焦点：变主色 65%<br>放大 1.08 + 描边 + 光晕')
         + cell(btn3('确定', size='m', kind='on'), '选中：主色实心') + cell(btn3('取消', size='m', kind='sec'), '次要：45% 底'))
    tabs = (cell(f'<div class="pl on">{mr("apps", 12)}全部</div>', '选中：主色实心')
            + cell(f'<div class="pl f fmk"><img src="{LOGO("bilibili")}">哔哩哔哩</div>', '焦点：主色 50%')
            + cell(f'<div class="pl"><img src="{LOGO("douyu")}">斗鱼</div>', '默认')
            + cell(f'<div class="pl on f">{mr("apps", 12)}全部</div>', '选中且有焦点<br>（和选中几乎一样）'))
    rail = (cell(f'<div class="rt on">{mr("favorite_border", 14)}<b>关注</b></div>', '选中')
            + cell(f'<div class="rt f fmk">{mo("local_fire_department", 14)}<b>热门</b></div>', '焦点')
            + cell(f'<div class="rt">{r("function_line", 14)}<b>分类</b></div>', '默认'))
    cards = (cell(f'<div style="width:190px">{card3("a")}</div>', '房间卡片：默认', w=190)
             + cell(f'<div style="width:190px">{card3("b", focused=True)}</div>', '焦点：放大 1.01<br>描边 + 光晕 + 底色变蓝', w=190)
             + cell(f'<div style="width:110px;height:120px;display:flex">{area3("英雄联盟", 237)}</div>', '分区卡片：默认<br>（底色同页面）', w=110)
             + cell(f'<div style="width:110px;height:120px;display:flex">{area3("王者荣耀", 250, True)}</div>', '焦点：放大 1.04', w=110))
    body = (f'<div class="t3" style="padding:26px 48px">'
            f'<div class="sec3">按钮（TvButton）</div><div class="rowx" style="align-items:flex-start">{b}</div>'
            f'<div style="display:flex;gap:40px;margin-top:22px"><div><div class="sec3">标签（TvTabBar）</div><div class="rowx" style="gap:14px">{tabs}</div></div>'
            f'<div><div class="sec3">导航栏图标（TvIconButton）</div><div class="rowx" style="gap:14px">{rail}</div></div></div>'
            f'<div class="sec3" style="margin-top:18px">卡片</div><div class="rowx" style="gap:26px">{cards}</div></div>')
    return page(body, CSS, dark=False, bg='#121212')


def parts4():
    b = (cell(btn4('确定', nn=1, tag='chg'), '默认', True) + cell(btn4('确定', focused=True), '焦点：近白描边 + 放大 1.05', True)
         + cell(btn4('下载并安装', kind='pri'), '主要动作：主色字', True) + cell(btn4('取消关注', kind='err'), '删除类：红字', True)
         + cell(btn4('确定', extra=' style="opacity:.38"'), '不可用：38%，焦点跳过', True))
    tabs = (cell(f'<div class="pl4 on"{at(2, "chg")}>{mr("apps", 20)}全部<span class="n">36</span></div>', '选中：主色容器', True)
            + cell(f'<div class="pl4 f4 fmk"><img src="{LOGO("bilibili")}">哔哩哔哩<span class="n">20</span></div>', '焦点：近白描边', True)
            + cell(f'<div class="pl4"><img src="{LOGO("douyu")}">斗鱼<span class="n">8</span></div>', '默认', True)
            + cell(f'<div class="pl4 on f4">{mr("apps", 20)}全部<span class="n">36</span></div>', '选中且有焦点', True))
    rail = ('<div class="t4" style="position:relative;inset:auto;background:transparent;overflow:visible;display:flex;gap:14px">'
            + cell(f'<div class="ri on"{at(3, "chg")}><span>{r("heart_3_fill", 24)}</span></div>', '选中', True)
            + cell(f'<div class="ri f4 ns fmk"><span>{r("fire_line", 24)}</span></div>', '焦点', True)
            + cell(f'<div class="ri"><span>{r("shapes_line", 24)}</span></div>', '默认', True) + '</div>')
    cards = (cell(f'<div style="width:184px">{card4("a", nn=4)}</div>', '房间卡片：默认', True, 184)
             + cell(f'<div style="width:184px">{card4("b", focused=True, marquee=True)}</div>', '焦点：近白描边 + 放大 1.05<br>标题滚动显示全文', True, 184)
             + cell(f'<div style="width:117px">{area4("英雄联盟", 237, nn=5)}</div>', '分区卡片：默认', True, 117)
             + cell(f'<div style="width:117px">{area4("王者荣耀", 250, True, followed=True)}</div>', '焦点；右上心形 = 已关注', True, 117))
    body = (f'<div class="t4" style="padding:24px 48px">'
            f'<div class="sec4">按钮</div><div class="rowx">{b}</div>'
            f'<div style="display:flex;gap:44px;margin-top:20px"><div><div class="sec4">标签</div><div class="rowx" style="gap:14px">{tabs}</div></div>'
            f'<div><div class="sec4">导航栏</div>{rail}</div></div>'
            f'<div class="sec4" style="margin-top:16px">卡片</div><div class="rowx" style="gap:26px">{cards}</div></div>')
    return page(body, CSS)


# ---------------- 2. room card states ----------------
def cards3():
    rows = [
        (card3('a'), '直播中'), (card3('b', focused=True), '焦点'), (card3('c', followed=True), '已关注（热门、分区、搜索）'),
        (card3('d', replay=True), '重播'),
        (card3('e', state='loading'), '封面加载中：转圈'), (card3('f', state='error'), '封面加载失败：断网图标'),
        (card3('g', chan=12), '网络电视：频道号代替头像'), (card3('i'), '平台标一直是英文 id（DOUYU）'),
    ]
    cells = ''.join(f'<div>{c}{lbl(t)}</div>' for c, t in rows)
    body = (f'<div class="t3" style="padding:22px 44px"><div class="sec3">房间卡片（TvRoomCard），4 列时的大小</div>'
            f'<div style="display:grid;grid-template-columns:repeat(4,1fr);gap:14px 18px">{cells}</div>'
            '<div class="ab" style="left:50%;bottom:22px;transform:translateX(-50%);background:rgba(0,0,0,.7);color:#fff;font:14px Noto Sans SC;padding:8px 14px;border-radius:6px">该平台已下线，无法再打开，可在关注列表中取消关注</div></div>')
    return page(body, CSS, dark=False, bg='#121212')


def cards4():
    rows = [
        (card4('a'), '直播中（单个平台的列表不标平台）'),
        (card4('b', focused=True, marquee=True), '焦点：标题滚动'),
        (card4('i', plat=True, followed=True), '混合列表标平台；心形 = 已关注'),
        (card4('d', replay=True), '录播'),
        (card4('e', offline=True), '未开播：压暗 + “未开播”'),
        (card4('m', restricted='需登录'), '受限：锁 + 原因'),
        (card4('f', state='loading'), '封面加载中、失败：同一占位'),
        (card4('g', chan=12, title='CCTV-13 新闻', nick='央视'), '网络电视：频道号'),
    ]
    cells = ''.join(f'<div>{c}{lbl(t, True)}</div>' for c, t in rows)
    body = (f'<div class="t4" style="padding:20px 48px"><div class="sec4">房间卡片，4 列时的大小（184 宽）</div>'
            f'<div class="g4" style="gap:6px 16px">{cells}</div>'
            '<div class="toast4" style="bottom:20px">该平台已下线，无法再打开；可以在关注里取消关注</div></div>')
    return page(body, CSS)


# ---------------- 3. settings rows ----------------
SW3 = lambda on, f=False: ('<span style="width:31px;height:17px;border-radius:3px;border:1px solid ' + ('#00A1FF' if on else 'rgba(255,255,255,.6)')
                           + ';background:' + ('rgba(0,161,255,.22)' if on else 'transparent') + ';display:flex;align-items:center;padding:1.5px;justify-content:'
                           + ('flex-end' if on else 'flex-start') + '"><i style="width:12px;height:100%;border-radius:1.5px;background:' + ('#00A1FF' if on else 'rgba(255,255,255,.6)') + '"></i></span>')


def row3(icon, title, sub, trail, focused=False, footer=''):
    st = ('background:#1E3948;border:1px solid #00A1FF;box-shadow:0 0 9px .75px rgba(0,161,255,.75)' if focused else 'border:1px solid transparent')
    return (f'<div class="{"fmk" if focused else ""}" style="border-radius:7px;padding:7px 8px;{st}"><div style="display:flex;align-items:center;gap:8px;min-height:28px">'
            f'<span style="font-size:15px;color:#fff">{icon}</span><div style="flex:1"><div style="font:600 11px Noto Sans SC">{title}</div>'
            + (f'<div style="font:500 8px Noto Sans SC;margin-top:2px">{sub}</div>' if sub else '') + f'</div>{trail}</div>{footer}</div>')


def rows3():
    chev = mr('chevron_right', 15)
    val = '<span style="font:600 10px Noto Sans SC;display:flex;align-items:center;gap:4px">简体中文' + mr('expand_more', 14) + '</span>'
    bar = '<div style="height:4px;border-radius:2px;background:rgba(255,255,255,.22);margin-top:5px"><i style="display:block;width:28%;height:100%;border-radius:2px;background:#00A1FF"></i></div>'
    card = lambda inner: f'<div style="border-radius:10px;background:rgba(31,31,31,.05);border:.5px solid rgba(31,31,31,.1);padding:2px">{inner}</div>'
    g = lambda t: f'<div style="font:600 8px Noto Sans SC;color:rgba(0,161,255,.85);letter-spacing:.5px;padding:0 0 4px 4px;margin-top:10px">{t}</div>'
    body = ('<div class="t3"><div style="height:33px;display:flex;align-items:center;padding:0 8px;gap:8px">'
            + btn3('返回', mr('arrow_back_ios_new', 12)) + '<span style="font:700 12px Noto Sans SC">主题定制</span></div>'
            '<div style="padding:4px 24px 0 24px;width:620px">'
            + g('导航栏显示方式') + card(row3(mo('view_sidebar', 15), '展开导航栏', '开启后显示完整菜单名称，关闭仅显示图标', SW3(False), True))
            + g('主题定制') + card(row3(r('function_line', 15), '主题外观', None, chev) + row3(mo('image', 15), '背景设置', '壁纸、动态壁纸、纯色渐变', chev))
            + g('区域与语言') + card(row3(mr('language', 15), '切换语言', '切换软件的显示语言', val))
            + g('界面字号调节') + card(row3(mr('format_size', 15), '全局文字缩放', None, '<span style="font:600 10px Noto Sans SC">100%</span>', footer=bar))
            + '</div><div class="ab" style="right:40px;top:60px;width:240px;font:400 10px/1.6 Noto Sans SC;color:#9AA0A6">各行取自 pure_live_TV 的主题定制和导航栏设置页，放在一起对照各种行的样子。<br>焦点行：底色变 #1E3948，主色描边加光晕；不放大。<br>开关：方形，打开时主色描边；←→ 也能切换。<br>滑块：←→ 调节，到头后焦点才离开。</div></div>')
    return page(body, CSS, dark=False, bg='#121212')


def rows4(n=True):
    N = (lambda k: k + 10) if n else (lambda k: None)
    chev = mr('chevron_right', 24)
    body = ('<div class="t4"><div style="position:absolute;left:48px;top:28px"><div class="ttl4">主题定制</div><div class="sub4">设置 · 主题设置</div></div>'
            '<div style="position:absolute;left:48px;top:96px;width:600px">'
            '<div class="sg4">导航栏显示方式</div><div class="sc4">'
            f'<div class="sr4 f4 ns fmk"{at(N(1), "chg", "tl")}>{mo("view_sidebar", 24)}<div class="x"><div class="a">导航栏始终展开</div><div class="b">关闭时导航栏只显示图标，焦点移过去时展开</div></div><span class="sw4"></span></div></div>'
            '<div class="sg4">主题定制</div><div class="sc4">'
            f'<div class="sr4"{at(N(2), "keep", "tl")}>{r("function_line", 24)}<div class="x"><div class="a">主题外观</div></div><span class="v">{chev}</span></div>'
            f'<div class="sr4">{mo("image", 24)}<div class="x"><div class="a">背景设置</div><div class="b">壁纸、动态壁纸、纯色渐变</div></div><span class="v">{chev}</span></div></div>'
            '<div class="sg4">区域与语言</div><div class="sc4">'
            f'<div class="sr4"{at(N(3), "keep", "tl")}>{mr("language", 24)}<div class="x"><div class="a">切换语言</div><div class="b">切换软件的显示语言</div></div><span class="v">简体中文{mr("arrow_drop_down", 24)}</span></div></div>'
            '</div>'
            '<div style="position:absolute;left:672px;top:96px;width:240px">'
            '<div class="sg4">界面字号调节</div><div class="sc4">'
            f'<div class="sr4" style="display:block"{at(N(4), "keep", "tl")}><div style="display:flex;align-items:center;gap:16px">{mr("format_size", 24)}<div class="x"><div class="a">全局文字缩放</div></div><span class="v tnum" style="color:var(--on)">100%</span></div>'
            '<div class="sl4"><i style="width:28%"></i><u style="left:28%"></u></div></div></div>'
            '<div style="font:400 14px/1.6 Noto Sans SC;color:var(--onv);padding:4px 4px 0">焦点行：近白描边，不放大（整行放大会出屏）。<br>开关、选择、滑块、跳转和手机的设置行同一个组件。</div></div></div>')
    return page(body, CSS)


# ---------------- 4. dialogs ----------------
def grid3_bg(focus=None, sel='hot'):
    cards = ''.join(card3(k, focused=(k == focus)) for k in 'abcdefgh')
    return (rail3(sel) + '<div class="pane">' + tabs3([('哔哩哔哩', 'bilibili'), ('斗鱼', 'douyu'), ('虎牙', 'huya'), ('抖音', 'douyin'), ('快手', 'kuaishou')])
            + f'<div style="height:8px"></div><div class="grid3">{cards}</div></div>')


def grid4_bg(sel='hot'):
    cards = ''.join(card4(k) for k in 'abcdefgh')
    tabs = tabs4([('哔哩哔哩', 'bilibili'), ('斗鱼', 'douyu'), ('虎牙', 'huya'), ('抖音', 'douyin'), ('快手', 'kuaishou'), ('网易CC', 'cc')])
    return rail4(sel) + f'<div class="content">{tabs}<div class="g4" style="margin-top:16px">{cards}</div></div>'


def confirm3():
    body = '<div class="m">确定要取消关注主播“晚风”吗？</div>'
    return page('<div class="t3">' + grid3_bg() + dialog3('取消关注', body, btn3('取消', kind='sec') + btn3('取消关注', kind='f fmk')) + '</div>', CSS, dark=False, bg='#121212')


def confirm4(n=True):
    N = (lambda k: k + 50) if n else (lambda k: None)
    body = '<div class="m">确定要取消关注晚风吗？</div>'
    return page('<div class="t4">' + grid4_bg() + dialog4('取消关注', body, btn4('取消', focused=True, nn=N(1), tag='chg') + btn4('取消关注', kind='err', nn=N(2), tag='keep'),
                                                      width=480) + '</div>', CSS)


def select3():
    items = [('20', 'numbers'), ('50', 'numbers'), ('100', 'numbers'), ('200', 'numbers'), ('不限', 'all_inclusive'), ('自定义数量', 'edit')]
    rows = ''.join(f'<div class="o3{" on" if t == "50" else ""}{" f fmk fl" if t == "100" else ""}">{mr(i, 12)}<span class="x">{t}</span>'
                   + (mr('check_circle', 13) if t == '50' else '') + '</div>' for t, i in items)
    return page('<div class="t3">' + grid3_bg() + dialog3('观看记录保留数量', rows, btn3('关闭', kind='sec'), top='50%') + '</div>', CSS, dark=False, bg='#121212')


def select4(n=True):
    N = (lambda k: k + 40) if n else (lambda k: None)
    items = [('20', 'numbers'), ('50', 'numbers'), ('100', 'numbers'), ('200', 'numbers'), ('不限', 'all_inclusive'), ('自定义数量…', 'edit')]
    rows = ''.join(f'<div class="o4{" cur" if t == "50" else ""}{" f4 ns fmk fl" if t == "100" else ""}"{at(N(1) if t == "50" else (N(2) if t == "100" else None), "chg", "l")}>{mr(i, 22)}<span class="x">{t}</span>'
                   + (mr('check', 22) if t == '50' else '') + '</div>' for t, i in items)
    return page('<div class="t4">' + grid4_bg() + dialog4('观看记录保留数量', f'<div class="list4">{rows}</div>', btn4('关闭', nn=N(3), tag='keep'),
                                                      sub='现在 50 条', width=440) + '</div>', CSS)


def tags3():
    body = '<div class="m" style="color:#fff">暂无自定义标签。<br>点击右上角 “+” 按钮即可创建。</div>'
    return page('<div class="t3">' + grid3_bg() + dialog3('设置房间标签 / 分类', body, btn3('取消', kind='sec') + btn3('完成', kind='f fmk')) + '</div>', CSS, dark=False, bg='#121212')


def tags3_list():
    tags = [('常看', '', True), ('睡前听', '助眠的电台和弹唱', False), ('游戏', '', False), ('学习', '陪伴学习', True)]
    rows = ''.join(f'<div class="o3{" f fmk fl" if i == 0 else ""}">{mr("check_circle" if on else "radio_button_unchecked", 12)}<span class="x">{t}' + (f'<small>{d}</small>' if d else '') + '</span></div>'
                   for i, (t, d, on) in enumerate(tags))
    return page('<div class="t3">' + grid3_bg() + dialog3('设置房间标签 / 分类', rows, btn3('取消', kind='sec') + btn3('完成')) + '</div>', CSS, dark=False, bg='#121212')


def tags4(n=True):
    N = (lambda k: k + 30) if n else (lambda k: None)
    tags = [('常看', '', True), ('睡前听', '助眠的电台和弹唱', False), ('游戏', '', False), ('学习', '陪伴学习', True)]
    rows = ''.join(f'<div class="o4{" f4 ns fmk fl" if i == 1 else ""}"{at(N(1) if i == 1 else None, "chg", "l")}><span class="ck{" on" if on else ""}">{mr("check", 16) if on else ""}</span><span class="x">{t}'
                   + (f'<small>{d}</small>' if d else '') + '</span></div>' for i, (t, d, on) in enumerate(tags))
    rows += f'<div class="o4" style="color:var(--primary)"{at(N(2), "add", "l")}>{mr("add", 22).replace("font-size:22px", "font-size:22px;color:var(--primary)")}<span class="x">新建标签</span></div>'
    return page('<div class="t4">' + grid4_bg() + dialog4('设置房间标签 / 分类', f'<div class="list4">{rows}</div>',
                                                      btn4('取消', nn=N(3)) + btn4('确认', nn=N(4)), sub='晚风 · 哔哩哔哩', width=480) + '</div>', CSS)


def input3():
    field = ('<div style="height:28px;border-radius:14px;background:rgba(31,31,31,.47);border:1px solid #00A1FF;display:flex;align-items:center;padding:0 14px;font:400 11px Noto Sans SC">80'
             '<span style="width:1px;height:12px;background:#fff;margin-left:2px"></span></div>')
    return page('<div class="t3">' + grid3_bg() + dialog3('自定义数量', field, btn3('取消', kind='sec') + btn3('确定')) + '</div>', CSS, dark=False, bg='#121212')


def input4(n=True):
    N = (lambda k: k + 60) if n else (lambda k: None)
    field = (f'<div class="f4 ns fmk fl" style="margin-top:18px;height:52px;border-radius:12px;background:var(--scl);display:flex;align-items:center;padding:0 16px;font:400 18px Geist"{at(N(1), "chg", "l")}>80'
             '<span style="width:2px;height:22px;background:var(--primary);margin-left:2px"></span><span style="flex:1"></span>'
             '<span style="font:400 14px Noto Sans SC;color:var(--onv)">条</span></div>'
             '<div style="font:400 14px Noto Sans SC;color:var(--onv);margin-top:8px">用屏幕键盘输入；遥控器有数字键也可以直接按</div>')
    return page('<div class="t4">' + grid4_bg() + dialog4('自定义数量', field, btn4('取消', nn=N(2)) + btn4('确定', kind='pri', nn=N(3)),
                                                      sub='观看记录保留数量', width=480) + '</div>', CSS)


# ---------------- 5. status views (four quarters) ----------------
def halves(cells, v4):
    q = ''
    border = 'var(--ov)' if v4 else '#2A2A2A'
    for i, (title, inner) in enumerate(cells):
        q += (f'<div class="ab" style="left:{i * 480}px;top:0;width:480px;height:540px;overflow:hidden;border-right:1px solid {border}">'
              f'<div class="ab" style="left:16px;top:12px;font:600 {14 if v4 else 11}px Noto Sans SC;color:#9AA0A6;z-index:3">{title}</div>'
              f'<div class="ab" style="inset:0;display:flex;align-items:center;justify-content:center">{inner}</div></div>')
    return q


def status3_pages():
    small = lambda t, icon, f=True: btn3(t, icon, size='s', kind='f fmk fb' if f else '')
    a = [('第一次加载：整页一个转圈', '<div style="width:24px;height:24px;border-radius:12px;border:2px solid #00A1FF;border-right-color:rgba(0,161,255,.1)"></div>'),
         ('空（热门）', status3('empty', '该平台暂无直播', '请切换平台或稍后重试', mo('local_fire_department', 32), small('重新加载', mr('refresh', 11))))]
    b = [('出错：直接显示报错原文', status3('error', '网络请求失败', 'DioException [connection timeout]: The request<br>connection took longer than 0:00:15.000000', mr('wifi_off', 32),
                                     small('重新加载', mr('refresh', 11)))),
         ('需要登录', status3('login', '需要登录账号', '该平台数据已被风控隐藏，请登录账号后重试', mo('account_circle', 32), small('前往登录', r('login_box_fill', 11))))]
    return (page('<div class="t3">' + halves(a, False) + '</div>', CSS, dark=False, bg='#121212', syn=False),
            page('<div class="t3">' + halves(b, False) + '</div>', CSS, dark=False, bg='#121212', syn=False))


def status4_pages(n=True):
    N = (lambda k: k + 80) if n else (lambda k: None)
    sk = ''.join(skel4() for _ in range(4))
    a = [('第一次加载：静态骨架（不扫光）', f'<div class="g4" style="grid-template-columns:repeat(2,1fr);gap:16px;width:400px">{sk}</div>'),
         ('空（热门）', status4(r('fire_fill', 44), '未发现直播', '这个平台暂时没有直播。<br>按上键回到平台标签换个平台，或者刷新',
                              btn4('刷新', mr('refresh', 20), focused=True, nn=N(1), tag='keep')))]
    b = [('出错：按原因写一句话', status4(mr('wifi_off', 44), '网络请求失败', '连不上哔哩哔哩，请检查网络或代理后重试',
                                    btn4('重试', mr('refresh', 20), focused=True, nn=N(2), tag='keep'))),
         ('需要登录', status4(mo('account_circle', 44), '需要登录账号', '这个平台要登录后才显示内容，请在设置里登录账号',
                            btn4('前往登录', mr('login', 20), focused=True, nn=N(3), tag='chg')))]
    return page('<div class="t4">' + halves(a, True) + '</div>', CSS, syn=False), page('<div class="t4">' + halves(b, True) + '</div>', CSS, syn=False)


# ---------------- 6. room pushed from the phone ----------------
def push3():
    body = ('<div class="d3" style="width:260px;padding:16px;border-radius:12px;border-color:rgba(0,161,255,.4);box-shadow:none">'
            f'<div style="display:flex;align-items:center;gap:6px;font:600 10px Noto Sans SC"><span style="color:#00A1FF">{mr("live_tv", 14)}</span>手机推送了一个直播间</div>'
            '<div style="font:500 8px/1.4 Noto Sans SC;margin-top:8px;color:#fff;word-break:break-all">https://live.bilibili.com/21452505?broadcast_type=0&amp;is_room_feed=1&amp;spm_id_from=333.1007</div>'
            '<div style="display:flex;justify-content:flex-end;gap:8px;margin-top:14px">' + btn3('取消', size='m', kind='sec') + btn3('打开直播间', size='m', kind='f fmk') + '</div></div>')
    return page('<div class="t3">' + grid3_bg() + '<div class="scr3"></div>' + body + '</div>', CSS, dark=False, bg='#121212')


def push4(n=True):
    N = (lambda k: k + 70) if n else (lambda k: None)
    _, p, title, nick, img, kind, fig = R['a']
    body = ('<div style="display:flex;gap:14px;margin-top:18px;align-items:center">'
            f'<span style="width:56px;height:56px;border-radius:28px;background:url({avatar("a")}) center/cover;flex:none"></span>'
            f'<div style="min-width:0"><div style="font:600 16px/1.4 Noto Sans SC">{title}</div>'
            f'<div style="font:400 14px/1.5 Noto Sans SC;color:var(--onv);display:flex;align-items:center;gap:6px;margin-top:2px">{nick} · <img src="{LOGO(p)}" style="width:16px;height:16px;border-radius:3px">哔哩哔哩 · 房间号 21452505</div></div></div>')
    return page('<div class="t4">' + grid4_bg() + dialog4('打开分享的直播间', body, btn4('取消', nn=N(1)) + btn4('进入房间', kind='pri', focused=True, nn=N(2)),
                                                      sub='从手机推送', width=520) + '</div>', CSS)


# ---------------- 7. card long press ----------------
def cardmenu3():
    rows = (f'<div class="o3 f fmk fl">{mr("favorite_border", 12)}<span class="x">取消关注</span></div>'
            f'<div class="o3">{mo("sell", 12)}<span class="x">设置房间标签 / 分类</span></div>')
    return page('<div class="t3">' + grid3_bg(sel='favorite') + dialog3('晚风', rows, btn3('关闭', kind='sec')) + '</div>', CSS, dark=False, bg='#121212')


def cardmenu4(n=True):
    N = (lambda k: k + 20) if n else (lambda k: None)
    _, p, title, nick, img, kind, fig = R['a']
    head = (f'<div style="display:flex;align-items:center;gap:12px;margin:-4px 0 0"><img src="{LOGO(p)}" style="width:36px;height:36px;border-radius:8px">'
            f'<div><div class="h" style="font-size:20px">{nick}</div><div class="hs" style="margin:0">哔哩哔哩 · 房间号 21452505</div></div></div>')
    box = f'<div style="margin-top:16px;border-radius:12px;background:var(--scl);padding:12px 16px;font:400 16px/1.55 Noto Sans SC">{title}</div>'
    acts = (f'<div style="display:flex;gap:12px;margin-top:16px">{btn4("设置标签", r("price_tag_3_line", 20), focused=True, nn=N(1), tag="chg")}'
            f'{btn4("删除这条记录", r("delete_bin_line", 20), nn=N(2), tag="add")}</div>')
    d = ('<div class="scr4"></div><div class="d4" style="width:520px">' + head + box + acts
         + f'<div class="ac"><span class="b4 l"{at(N(3), "keep")}>关闭</span>{btn4("已关注", r("check_line", 20), nn=N(4), tag="chg")}</div></div>')
    return page('<div class="t4">' + grid4_bg('history') + d + '</div>', CSS)


OUT = {
    'v3-parts': parts3(), 'v4-parts': parts4(),
    'v3-cards': cards3(), 'v4-cards': cards4(),
    'v3-rows': rows3(), 'v4-rows': rows4(),
    'v3-confirm': confirm3(), 'v4-confirm': confirm4(),
    'v3-select': select3(), 'v4-select': select4(),
    'v3-tags-empty': tags3(), 'v3-tags': tags3_list(), 'v4-tags': tags4(),
    'v3-input': input3(), 'v4-input': input4(),
    'v3-status': status3_pages()[0], 'v3-status-err': status3_pages()[1],
    'v4-status': status4_pages()[0], 'v4-status-err': status4_pages()[1],
    'v3-push': push3(), 'v4-push': push4(),
    'v3-cardmenu': cardmenu3(), 'v4-cardmenu': cardmenu4(),
}
write(OUT, HERE)
