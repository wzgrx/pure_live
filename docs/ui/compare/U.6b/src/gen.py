"""U.6b appearance settings: v3 restored and the new design.
v3: lib/modules/settings/pages/theme_settings_page.dart, font_family_manager_page.dart,
font_settings_page.dart, loading_style_settings_page.dart, navigation_settings_page.dart,
page_settings.dart, room_card_settings_page.dart, widgets/app_color_picker_dialog.dart;
texts from assets/translations/zh.json, loading style names from common/consts/app_consts.dart.
The settings row and the two-pane layout are shared with U.6a (../../U.6a/src/skit.py).
    python3 docs/ui/compare/U.6b/src/gen.py && python3 tools/ui/mock/render.py docs/ui/compare/U.6b/src/ --annotate"""
import os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', 'U.6a', 'src'))
from skit import *  # noqa: E402,F401,F403

CSS6 = r'''
.tip3{display:flex;gap:12px;padding:12px 16px;border-radius:16px;background:color-mix(in srgb,var(--primary) 5%,var(--surface));font-size:13px;line-height:1.4;color:color-mix(in srgb,var(--onv) 80%,var(--surface))}
.tip3 .rx{font-size:18px;color:color-mix(in srgb,var(--primary) 80%,var(--surface))}
.fc3{margin:8px 0;border-radius:24px;padding:16px 20px 10px;background:linear-gradient(135deg,color-mix(in srgb,var(--primary) 6%,var(--scl)),var(--scl));box-shadow:inset 0 0 0 1.2px rgba(0,0,0,.05),0 4px 12px rgba(0,0,0,.03)}
.fc3.on{box-shadow:inset 0 0 0 1.8px var(--primary),0 4px 24px color-mix(in srgb,var(--primary) 6%,transparent)}
.fc3 .nm{font-size:15px;font-weight:800}.fc3 .bg{display:flex;gap:6px;flex-wrap:wrap;margin-top:8px}
.bdg{padding:3px 8px;border-radius:8px;font-size:11px;font-weight:700;background:rgba(0,0,0,.05);color:var(--onv)}
.bdg.sz{background:color-mix(in srgb,var(--primary) 8%,transparent);color:var(--primary);font-weight:800}
.fc3 .ds{font-size:13px;line-height:1.4;color:rgba(0,0,0,.48);margin-top:8px}
.fc3 .un{font-size:12px;font-weight:500;color:rgba(0,0,0,.36);margin-top:12px}
.fc3 .acts{display:flex;justify-content:flex-end;align-items:center;gap:10px;margin-top:12px}
.eb{height:44px;padding:0 20px;border-radius:30px;background:var(--pc);color:var(--opc);display:inline-flex;align-items:center;gap:6px;font-size:13px;font-weight:700}
.del3{width:38px;height:38px;border-radius:19px;background:color-mix(in srgb,var(--error) 5%,transparent);display:grid;place-items:center;color:color-mix(in srgb,var(--error) 80%,transparent)}
.actpill{display:flex;align-items:center;gap:6px;padding:6px 6px 6px 14px;border-radius:30px;background:color-mix(in srgb,var(--primary) 10%,transparent);color:var(--primary);font-size:12px;font-weight:700}
.fc{margin-bottom:12px;border-radius:16px;padding:14px 12px 12px 16px;background:var(--scl)}
.fc.on{box-shadow:inset 0 0 0 2px var(--primary)}
.fc .top{display:flex;align-items:center;gap:8px}.fc .nm{flex:1;font-size:16px;font-weight:600}
.fc .ds{font-size:12px;line-height:1.5;color:var(--onv);margin-top:6px}
.fc .meta{display:flex;align-items:center;gap:8px;margin-top:10px;font-size:12px;color:var(--onv)}
.fc .meta .sp{flex:1}
.tb2{height:40px;padding:0 16px;border-radius:20px;display:inline-flex;align-items:center;gap:6px;font-size:14px;font-weight:600;background:var(--sc);color:var(--osc)}
.tb2.txt{background:transparent;color:var(--primary);padding:0 10px}
.using{height:28px;padding:0 10px 0 8px;border-radius:14px;display:inline-flex;align-items:center;gap:4px;background:var(--pc);color:var(--opc);font-size:12px;font-weight:600}
.prog{height:4px;border-radius:2px;background:color-mix(in srgb,var(--primary) 18%,transparent);position:relative;flex:1;margin-right:12px}.prog i{position:absolute;left:0;top:0;bottom:0;border-radius:2px;background:var(--primary)}
.lg{display:grid;gap:12px}
.lc{position:relative;border-radius:16px;background:var(--scl);display:flex;flex-direction:column;align-items:center;justify-content:center;padding-top:6px}
.lc.on{background:color-mix(in srgb,var(--pc) 25%,var(--surface));box-shadow:inset 0 0 0 2px var(--primary)}
.lc .an{flex:1;display:grid;place-items:center}.lc .lb{padding:0 4px 12px;font-size:11px;font-weight:700;text-align:center;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:100%}
.lc.on .lb{color:var(--primary)}.lc .ok{position:absolute;top:8px;right:8px;color:var(--primary)}
.gl{width:36px;height:36px;position:relative;color:var(--primary)}
.seg{display:flex;background:rgba(118,118,128,.12);border-radius:9px;padding:2px;margin:0}
.seg div{flex:1;height:30px;display:grid;place-items:center;font-size:13px;border-radius:7px;white-space:nowrap}
.seg .on{background:#fff;box-shadow:0 3px 8px rgba(0,0,0,.12),0 3px 1px rgba(0,0,0,.04);font-weight:600}
.sws{display:grid;grid-template-columns:repeat(5,48px);gap:5px;justify-content:start}
.sws i{width:48px;height:48px;border-radius:4px;display:grid;place-items:center;color:#fff;font-style:normal}
.fld{border-radius:12px;background:var(--scl);box-shadow:inset 0 -1px 0 var(--outline);padding:8px 16px 8px;position:relative}
.fld .l{font-size:12px;color:var(--onv)}.fld .v{font-size:16px;margin-top:2px}
.fld.ol{background:transparent;box-shadow:inset 0 0 0 1px var(--outline);border-radius:8px}
.hlp{font-size:12px;color:var(--onv);padding:4px 16px 0}
.rc{border-radius:20px;overflow:hidden;background:var(--scl);max-width:420px;margin:0 auto}
.rc .cv{aspect-ratio:16/9;background:#3a3f4a center/cover;position:relative}
.rc .cc{position:absolute;right:8px;bottom:8px;height:24px;padding:0 8px;border-radius:12px;background:rgba(0,0,0,.55);color:#fff;font-size:12px;display:flex;align-items:center;gap:3px}
.rc .inf{display:flex;gap:8px;padding:8px}.rc .av2{width:34px;height:34px;border-radius:17px;background:var(--pc);color:var(--opc);display:grid;place-items:center;font-size:14px;font-weight:600;flex:none}
.rc .tt2{font-size:13px;font-weight:600}.rc .nk{font-size:12px;color:var(--onv);margin-top:2px}
.syn2{position:absolute;left:8px;top:8px;font:500 9px 'Noto Sans SC';padding:2px 5px;border-radius:4px;background:rgba(0,0,0,.5);color:rgba(255,255,255,.85)}
.mn{position:absolute;z-index:22;background:var(--schh);border-radius:8px;box-shadow:0 4px 14px rgba(0,0,0,.2);padding:8px 0;min-width:180px}
.mn .it{height:48px;display:flex;align-items:center;gap:12px;padding:0 16px;font-size:14px}.mn .it .rx{font-size:20px;color:var(--onv)}
.mn .it.err,.mn .it.err .rx{color:var(--error)}
'''

GRAY = 'color:rgba(0,0,0,.24)'
CHEV24 = mr('chevron_right', 24, 'color:var(--onv)')
RING = '<span class="ring" style="width:22px;height:22px;display:inline-block;border-width:3px"></span>'


def P(body, crop=True, h=2400, css=CSS6):
    return doc(393, h if crop else 852, 2 if crop else 3, body, css=css, crop=crop)


def C(phones, caps, h=852):
    return canvas(phones, caps, h=h, css=CSS6)


# =====================================================================
# 1. the appearance page (theme_settings_page.dart:21-192)
# =====================================================================
def v3_appearance_content(wide=False):
    out = [gt3('主题定制'), card3([
        t3(rx('ef6f'), '主题模式', '切换系统/亮色/暗色模式'),
        t3(rx('efc5'), '主题颜色', '切换软件的主题颜色', trailing='<span class="ind3" style="background:#2196F3"></span>'),
        t3(rx('eeea'), '动态取色', '启用Monet壁纸动态取色', sw=False),
        t3(RING, '修改加载动画', '自定义全局界面的加载和刷新样式', trailing='<span class="tv">默认圆环</span>')]),
        '<div class="g3"></div>', gt3('房间卡片设置'),
        card3([t3(rx('ee90'), '房间卡片设置', '分别定制移动端和桌面端房间卡片的可见信息', trailing=CHEV24)]),
        '<div class="g3"></div>', gt3('网格间距设置'),
        card3([t3(rx('ea62'), '列间距 (横向)', '调整同一行中左右卡片之间的水平缝隙'),
               t3(rx('ea74'), '行间距 (纵向)', '调整同一列中上下卡片之间的垂直缝隙')])]
    if wide:  # Get.width > 680 (:119)
        out += ['<div class="g3"></div>', gt3('分页设置'),
                card3([t3(rx('efbf'), '分页设置', '自定义全局页面切片与分页交互参数', trailing=CHEV24)])]
    out += ['<div class="g3"></div>', gt3('区域与语言'), card3([t3(rx('edcf'), '切换语言', '切换软件的显示语言')]),
            '<div class="g3"></div>', gt3('字体样式设置'), card3([t3(rx('ed8b'), '更换系统默认字体', '当前字体: Default')]),
            '<div class="g3"></div>', gt3('界面字号调节'),
            card3([t3(rx('ed8d'), '精细化字号微调', '微调系统各项组件的专属预设字号基础值'),
                   sl3(rx('f1ff'), '全局字体缩放比例', '1.00', 33.3),
                   f'<div style="padding:0 16px 16px;text-align:center;font-size:13px;color:var(--outline)">{PREVIEW_TEXT}</div>'])]
    return ''.join(out)


def v3_appearance():
    return P(STATUS + ab3('主题定制') + f'<div class="b3">{v3_appearance_content()}</div>')


def v3_appearance_land():
    body = STATUS_LAND + ab3('主题定制') + f'<div class="b3">{v3_appearance_content(wide=True)}</div>'
    return doc(852, 1900, 2, body, css=CSS6, crop=True, root='win')


def v3_appearance_wide():
    body = ab3('主题定制') + f'<div class="b3"><div style="max-width:960px;margin:0 auto">{v3_appearance_content(wide=True)}</div></div>'
    return doc(1280, 1700, 1.5, body, css=CSS6, crop=True, root='win')


def v4_appearance():
    return P(STATUS + ab('外观', n_back=1) + f'<div class="sb">{appearance_v4(n=True)}</div>')


def v4_appearance_wide():
    return two_pane(1280, 800, 1.5, '外观', appearance_v4(n=True, desktop=True), n_left=False)


def v4_appearance_land():
    return two_pane(852, 393, 2, '外观', appearance_v4(desktop=False), status=STATUS_LAND, n_left=False)


# =====================================================================
# 2. theme mode, language, grid spacing dialogs
# =====================================================================
def v3_theme_bg():
    return STATUS + ab3('主题定制') + f'<div class="b3">{v3_appearance_content()}</div>' + scrim()


def v4_theme_bg():
    return STATUS + ab('外观') + f'<div class="sb">{appearance_v4()}</div>' + scrim()


def v3_choice(title, items, on, top):
    # ThemeChoiceDialog (theme_settings_page.dart:276-337): width < 420 -> inset 12, padding 12/20/12/12, radius 16
    rows = ''.join(f'<div class="ro" style="min-height:56px;font-weight:400"><span class="rad{" on" if i == on else ""}"></span>{t}</div>' for i, t in enumerate(items))
    return (f'<div class="dg" style="left:12px;right:12px;top:{top}px;border-radius:16px;padding:20px 12px 12px">'
            f'<div style="padding:0 12px;font-size:20px;font-weight:700">{title}</div><div style="height:12px"></div>{rows}</div>')


def v4_choice(title, items, on, top, n=None):
    rows = ''.join(f'<div class="ro{" on" if i == on else ""}" style="min-height:52px;font-size:15px;padding:0 24px"{attrs(n if i == 1 else None, "keep")}>'
                   f'<span class="rad{" on" if i == on else ""}"></span>{t}</div>' for i, t in enumerate(items))
    return (f'<div class="dg" style="left:24px;right:24px;top:{top}px;padding-bottom:12px"><div class="h">{title}</div>'
            f'<div style="height:12px"></div>{rows}</div>')


def v3_spacing():
    chips_ = ''.join(f'<span style="height:32px;padding:0 12px;border-radius:8px;display:inline-flex;align-items:center;font-size:14px;'
                     f'{"background:var(--sc);color:var(--osc)" if v == 6 else ""}">{v} px</span>' for v in (0, 4, 6, 8, 12, 16))
    arrows = (f'<div style="position:absolute;right:0;top:0;bottom:0;width:48px;display:flex;flex-direction:column;align-items:center;justify-content:center">'
              f'<div style="height:48px;display:grid;place-items:center">{mi("arrow_drop_up")}</div><div style="height:48px;display:grid;place-items:center">{mi("arrow_drop_down")}</div></div>')
    return ('<div class="dg" style="left:12px;right:12px;top:190px;border-radius:16px;padding:16px">'
            '<div style="font-size:20px;font-weight:700">列间距 (横向)</div><div style="height:16px"></div>'
            f'<div style="display:flex;flex-wrap:wrap;gap:8px">{chips_}</div><div style="height:20px"></div>'
            '<div style="font-size:13px;font-weight:500">调整同一行中左右卡片之间的水平缝隙</div><div style="height:8px"></div>'
            f'<div style="position:relative;height:96px;border-radius:8px;background:var(--scl);box-shadow:inset 0 0 0 1px var(--outline);display:flex;align-items:center;padding:0 12px;font-size:16px">6{arrows}</div>'
            '<div style="height:24px"></div><div class="ac" style="padding:0"><span>取消</span><span class="elev">确认</span></div></div>')


def v4_spacing():
    chips_ = ''.join(f'<span class="chip{" on" if v == 6 else ""}" style="height:36px">{mr("check", 18) if v == 6 else ""}{v} px</span>' for v in (0, 4, 6, 8, 12, 16))
    return ('<div class="dg" style="left:24px;right:24px;top:220px"><div class="h">列间距 (横向)</div>'
            '<div class="bd" style="padding-top:8px">调整同一行中左右卡片之间的水平缝隙</div>'
            f'<div style="display:flex;flex-wrap:wrap;gap:8px;padding:16px 24px 0"{attrs(21, "chg")}>{chips_}</div>'
            '<div style="padding:16px 24px 0"><div class="fld ol" style="display:flex;align-items:center;height:56px;padding:0 16px"'
            f'{attrs(22, "chg")}><span style="flex:1;font-size:16px">6</span><span style="color:var(--onv);font-size:14px">px</span></div>'
            '<div class="hlp">0 到 64 之间</div></div>'
            f'<div class="ac"><span>取消</span><span class="fill"{attrs(23, "keep")}>确认</span></div></div>')


def v3_dialogs():
    return C([v3_theme_bg() + v3_choice('主题模式', ['跟随系统', '深色模式', '浅色模式'], 0, 300),
              v3_theme_bg() + v3_choice('切换语言', ['English', '简体中文'], 1, 330),
              v3_theme_bg() + v3_spacing()],
             ['主题模式（ThemeChoiceDialog）', '切换语言（同一个对话框）', '列间距 / 行间距（ThemeSpacingDialog）'])


def v4_dialogs():
    return C([v4_theme_bg() + v4_choice('主题模式', ['跟随系统', '深色模式', '浅色模式'], 0, 290, n=None),
              v4_theme_bg() + v4_choice('切换语言', ['English', '简体中文'], 1, 320),
              v4_theme_bg() + v4_spacing()],
             ['主题模式：选完就关', '切换语言：同一个对话框', '点计数行的数字：直接输入'])


# =====================================================================
# 3. colour picker (app_color_picker_dialog.dart:194-283)
# =====================================================================
PRIMARIES = ['F44336', 'E91E63', '9C27B0', '673AB7', '3F51B5', '2196F3', '03A9F4', '00BCD4', '009688', '4CAF50',
             '8BC34A', 'CDDC39', 'FFEB3B', 'FFC107', 'FF9800', 'FF5722', '795548', '607D8B', '9E9E9E']
BLUE_SHADES = ['E3F2FD', 'BBDEFB', '90CAF9', '64B5F6', '42A5F5', '2196F3', '1E88E5', '1976D2', '1565C0', '0D47A1']
APP_COLORS = [('Crimson', 'DC143C'), ('Orange', 'FF9800'), ('Chrome', 'E6B800'), ('Grass', '8BC34A'), ('Teal', '009688'),
              ('SeaFoam', '70C1CF'), ('Ice', '739BD0'), ('Blue', '2196F3'), ('Indigo', '3F51B5'), ('Violet', '673AB7'),
              ('Primary', '6200EE'), ('Orchid', 'DA70D6'), ('Variant', '3700B3'), ('Secondary', '03DAC6')]


def swatch(hexv, on=False, size=48, radius=4):
    dark_check = hexv in ('FFEB3B', 'CDDC39', 'FFC107', 'E3F2FD', 'BBDEFB', '90CAF9')
    ck = mi('check', 24, f'color:{"#000" if dark_check else "#fff"}') if on else ''
    return f'<i style="background:#{hexv};width:{size}px;height:{size}px;border-radius:{radius}px">{ck}</i>'


def v3_color():
    grid = ''.join(swatch(h, h == '2196F3') for h in PRIMARIES)
    shades = ''.join(swatch(h, h == '2196F3') for h in BLUE_SHADES)
    dlg = ('<div class="dg" style="left:40px;right:40px;top:80px"><div class="h" style="padding-bottom:16px">主题颜色</div>'
           '<div style="padding:0 16px">'
           '<div class="seg"><div class="on">常用色</div><div>鲜艳色</div><div>自定义</div><div>调色盘</div></div><div style="height:12px"></div>'
           f'<div class="sws">{grid}</div><div style="height:12px"></div>'
           '<div style="font-size:14px;font-weight:500">选择色阶</div><div style="height:8px"></div>'
           f'<div class="sws">{shades}</div><div style="height:12px"></div>'
           '<div class="fld"><div class="l">RGB 颜色代码</div><div class="v">#2196F3</div></div><div class="hlp">#RRGGBB / 0xRRGGBB</div></div>'
           '<div class="ac" style="padding-top:16px"><span>取消</span><span class="fill">确定</span></div></div>')
    return P(v3_theme_bg() + dlg, crop=False)


def v4_color():
    rec = [('2E6FE0', '品牌蓝')] + [(h, n) for n, h in APP_COLORS]
    cells = ''.join(f'<div style="display:grid;place-items:center"{attrs(26 if i == 0 else None, "add")}>'
                    f'<i style="width:44px;height:44px;border-radius:22px;background:#{h};display:grid;place-items:center;'
                    f'{"box-shadow:0 0 0 3px var(--sch),0 0 0 5px var(--on)" if h == "2196F3" else ""}">'
                    f'{mi("check", 22, "color:#fff") if h == "2196F3" else ""}</i></div>' for i, (h, n) in enumerate(rec))
    shades = ''.join(f'<i style="width:26px;height:40px;border-radius:6px;background:#{h};display:grid;place-items:center;'
                     f'{"box-shadow:0 0 0 2px var(--sch),0 0 0 4px var(--on)" if h == "2196F3" else ""}"></i>' for h in BLUE_SHADES)
    dlg = ('<div class="dg" style="left:24px;right:24px;top:96px"><div class="h" style="padding-bottom:16px">主题颜色</div>'
           '<div style="padding:0 20px">'
           f'<div class="seg"{attrs(24, "chg")}><div class="on">推荐</div><div>常用色</div><div>鲜艳色</div><div>调色盘</div></div><div style="height:16px"></div>'
           f'<div style="display:grid;grid-template-columns:repeat(5,1fr);row-gap:8px"{attrs(25, "chg")}>{cells}</div><div style="height:14px"></div>'
           '<div style="font-size:14px;font-weight:600">选择色阶</div><div style="height:8px"></div>'
           f'<div style="display:flex;justify-content:space-between"{attrs(27, "keep")}>{shades}</div><div style="height:16px"></div>'
           f'<div class="fld"{attrs(28, "keep")}><div class="l">RGB 颜色代码</div><div class="v">#2196F3</div></div><div class="hlp">#RRGGBB / 0xRRGGBB</div></div>'
           f'<div class="ac"><span{attrs(29, "keep")}>取消</span><span class="fill">确定</span></div></div>')
    return P(v4_theme_bg() + dlg, crop=False)


# =====================================================================
# 4. font manager (font_family_manager_page.dart:90-361)
# =====================================================================
FONTS = [
    ('苹方', 'Apple字体许可协议', '苹方（PingFang）是苹果平台使用的系统字体，主要用于简体中文、繁体中文及其他东亚文字的界面显示。', 1),
    ('句读黑体 UI Hans', 'SIL OFL 1.1', '句读黑体，基于思源黑体和 FiraGO 等字体，商用免费的多文种混排字体。', 6),
    ('句读黑体 UI Hant', 'SIL OFL 1.1', '句读黑体 传承字形版本', 6),
    ('械黑', 'SIL OFL 1.1', '将 IBM Plex Sans SC 中成部件的大量不必要修改还原成字体的原有风格，并修复了其中的一部分错形，部分零碎的字形也已恢复到繁体版和日文版原本的设计。', 7),
]


def v3_font_card(f, state, size=None):
    name, lic, desc, files = f
    badges = (f'<span class="bdg sz">{size}</span>' if size else '') + f'<span class="bdg">{lic}</span>'
    if state == 'active':
        act = f'<div class="actpill">当前正使用{mi("check_circle", 16)}<span class="eb" style="height:40px">应用</span></div>'
    elif state == 'local':
        act = f'<span class="del3">{rx("ec26", 18)}</span><span class="eb">应用</span>'
    else:
        act = f'<span class="eb" style="padding:0 18px">{rx("ec56", 15)}点击下载</span>'
    return (f'<div class="fc3{" on" if state == "active" else ""}"><div class="nm">{name}</div><div class="bg">{badges}</div>'
            f'<div class="ds">{desc}</div><div class="un">{files} 个字重组件文件</div><div class="acts">{act}</div></div>')


def v3_fonts():
    preset = ('<div style="border-radius:16px;background:var(--scl);box-shadow:inset 0 0 0 1px rgba(0,0,0,.05);display:flex;align-items:center;gap:16px;padding:10px 16px">'
              f'<span style="width:34px;height:34px;border-radius:17px;background:color-mix(in srgb,var(--schh) 50%,transparent);display:grid;place-items:center">{mi("settings_suggest", 18, "color:rgba(0,0,0,.6)")}</span>'
              '<div style="flex:1"><div style="font-size:14px;font-weight:600">系统默认</div><div style="font-size:11px;color:rgba(0,0,0,.42);margin-top:2px">恢复至系统原生默认字体家族渲染</div></div></div>')
    body = (STATUS + ab3('<span style="font-weight:700">字体样式设置</span>', f'<div class="ib">{rx("ed70", 20)}</div><div style="width:8px"></div>')
            + '<div style="padding:8px 20px 32px">' + gt3('系统预设环境') + preset + '<div style="height:28px"></div>' + gt3('扩展个性化字库')
            + v3_font_card(FONTS[0], 'cloud') + v3_font_card(FONTS[1], 'active', '38.6 MB') + v3_font_card(FONTS[2], 'local', '38.2 MB')
            + v3_font_card(FONTS[3], 'cloud') + '</div>')
    return P(body)


def v4_font_card(f, state, size=None, n=None, busy=False):
    name, lic, desc, files = f
    more = f'<span class="ib" style="width:40px;height:40px"{attrs(n and n + 2, "chg")}>{mr("more_vert", 22, "color:var(--onv)")}</span>'
    if state == 'active':
        right = f'<span class="using">{mr("check", 16)}正在使用</span>'
        tail = f'<span class="tb2 txt"{attrs(n, "chg")}>换字重</span>{more}'
    elif state == 'local':
        right = ''
        tail = f'<span class="tb2"{attrs(n, "keep")}>应用</span>{more}'
    elif state == 'dl':
        right = ''
        tail = f'<div class="prog"><i style="width:43%"></i></div><span style="font-size:12px;color:var(--onv);white-space:nowrap" class="tnum">下载中 3/{files}</span>'
    else:
        right = ''
        tail = f'<span class="tb2"{attrs(n, "chg")}>{rx("ec56", 18)}下载</span>'
    meta = (f'<span>{files} 个字重</span><span>·</span><span>{lic}</span>' + (f'<span>·</span><span class="tnum">{size}</span>' if size else '')
            + '<span class="sp"></span>')
    if state == 'dl':
        meta = f'<span>{files} 个字重</span><span>·</span><span>{lic}</span><span class="sp"></span>'
        return (f'<div class="fc"><div class="top"><span class="nm">{name}</span></div><div class="ds">{desc}</div>'
                f'<div class="meta">{meta}</div><div class="meta" style="margin-top:12px">{tail}</div></div>')
    if busy:
        tail = f'<span style="opacity:.38;display:inline-flex;align-items:center">{tail}</span>'
    return (f'<div class="fc{" on" if state == "active" else ""}"><div class="top"><span class="nm">{name}</span>{right}</div>'
            f'<div class="ds">{desc}</div><div class="meta">{meta}{tail}</div></div>')


def v4_fonts_body(n=True, downloading=False):
    N = (lambda k: k) if n else (lambda k: None)
    preset = card([row(mi('settings_suggest', 22, 'color:var(--primary)'), '系统默认', '恢复至系统原生默认字体家族渲染', 'none',
                       value=f'<span class="rad"></span>', n=N(31), tag='chg')])
    return (STATUS + ab('字体', f'<div class="ib"{attrs(N(32), "keep")}>{rx("ed70", 22)}</div>', n_back=N(30))
            + '<div class="sb">' + sgt('系统字体') + preset + sgt('可下载的字体（57 种）')
            + v4_font_card(FONTS[1], 'active', '38.6 MB', n=N(33), busy=downloading) + v4_font_card(FONTS[2], 'local', '38.2 MB', n=N(34), busy=downloading)
            + v4_font_card(FONTS[0], 'cloud', n=N(37), busy=downloading) + v4_font_card(FONTS[3], 'dl' if downloading else 'cloud') + '</div>')


def v4_fonts():
    return P(v4_fonts_body())


# weight selector (FontWeightSelectorDialog :625-779), more menu, delete confirm
def v3_weight_dialog(top=40):
    opt = lambda ic, t, s: (f'<div style="display:flex;gap:12px;padding:10px 8px">{mi(ic, 24)}<div><div style="font-size:15px;font-weight:500">{t}</div>'
                            f'<div style="font-size:13px;margin-top:2px;color:var(--onv)">{s}</div></div></div>')
    files = ['ExtraLight', 'Light', 'Regular', 'Medium', 'Bold', 'Heavy']
    return (f'<div class="dg" style="left:12px;right:12px;top:{top}px;border-radius:20px;padding:16px;background:var(--sch)">'
            '<div style="font-size:20px;font-weight:700">请选择「句读黑体 UI Hans」的样式</div><div style="height:8px"></div>'
            '<div style="font-size:13px;color:var(--onv)">该字体包含多个样式文件，请选择一个应用：</div><div style="height:16px"></div>'
            + opt('auto_awesome', '智能跟随系统粗细 (推荐)', '不同界面会自动展示常规或加粗效果') + '<div style="height:1px;background:var(--ov);margin:7px 0"></div>'
            + ''.join(opt('font_download', f'锁定使用 - {w} 体', '全应用文字将强制锁定为此效果') for w in files)
            + '<div style="text-align:right;padding-top:8px"><span style="display:inline-flex;height:40px;align-items:center;padding:0 12px;color:var(--primary);font-size:14px">取消</span></div></div>')


def v4_weight_dialog(top=60):
    files = ['ExtraLight', 'Light', 'Regular', 'Medium', 'Bold', 'Heavy']
    ro = lambda t, s, on, n=None: (f'<div class="ro{" on" if on else ""}" style="align-items:flex-start;padding:10px 24px;min-height:56px"{attrs(n, "chg")}>'
                                   f'<span class="rad{" on" if on else ""}" style="margin-top:2px"></span><div><div style="font-size:15px">{t}</div>'
                                   f'<div style="font-size:12px;color:var(--onv);font-weight:400;margin-top:2px">{s}</div></div></div>')
    return (f'<div class="dg" style="left:24px;right:24px;top:{top}px"><div class="h" style="font-size:18px">请选择「句读黑体 UI Hans」的样式</div>'
            '<div class="bd" style="padding-top:6px">该字体包含多个样式文件，请选择一个应用：</div><div style="height:4px"></div>'
            + ro('智能跟随系统粗细 (推荐)', '不同界面会自动展示常规或加粗效果', True, 41)
            + ''.join(ro(f'锁定使用 - {w} 体', '全应用文字将强制锁定为此效果', False, 42 if w == 'Regular' else None) for w in files)
            + f'<div class="ac"><span{attrs(43, "keep")}>取消</span></div></div>')


def v3_fontweight():
    body = (STATUS + ab3('<span style="font-weight:700">字体样式设置</span>', f'<div class="ib">{rx("ed70", 20)}</div>')
            + '<div style="padding:8px 20px">' + gt3('扩展个性化字库') + v3_font_card(FONTS[1], 'local', '38.6 MB') + v3_font_card(FONTS[2], 'cloud') + '</div>'
            + scrim() + v3_weight_dialog())
    return P(body, crop=False)


def v4_font_popups():
    menu = (v4_fonts_body(n=False)
            + '<div class="mn" style="right:28px;top:440px"><div class="it">' + rx('ed70') + '打开所在文件夹</div>'
            '<div class="it err">' + rx('ec26') + '删除</div></div>')
    menu = menu.replace('<div class="mn"', f'<div class="mn"{attrs(38, "chg")}', 1)
    confirm = (v4_fonts_body(n=False) + scrim() + '<div class="dg" style="left:24px;right:24px;top:300px"><div class="h">删除字体？</div>'
               '<div class="bd">将删除“句读黑体 UI Hant”的 6 个字重文件（38.2 MB）。删除后要用时可以再下载。</div>'
               f'<div class="ac"><span>取消</span><span class="err"{attrs(39, "add")}>删除</span></div></div>')
    weight = v4_fonts_body(n=False) + scrim() + v4_weight_dialog()
    dl = v4_fonts_body(n=False, downloading=True)
    return C([menu, confirm, weight, dl], ['点“⋮”：打开文件夹、删除', '删除先确认', '多字重：点“应用”或“换字重”', '下载中：显示第几个文件'])


# =====================================================================
# 5. text sizes (font_settings_page.dart:16-170)
# =====================================================================
SIZES = [  # icon, title, desc, value, min, max, sample
    ('ed8d', '微型辅助文本 (Body Small)', '用于弹幕计数、时间戳、卡片热度值等微小标识', 12, 9, 15, '1.2万 · 02:18 · 已开播 3 小时'),
    ('f201', '标准正文大小 (Body Medium)', '用于全局绝大多数常规描述、副标题与主设置文本', 13, 11, 17, '切换软件的显示语言'),
    ('f200', '加粗段落正文 (Body Large)', '用于列表项目名称、弹窗输入描述等加粗长文本', 14, 12, 18, '列间距 (横向)'),
    ('ee03', '中号卡片标题 (Title Medium)', '用于直播房间卡片标题、弹窗输入栏主要标题', 15, 13, 20, '深夜电台 · 点歌接龙到天亮'),
    ('ead1', '大号顶栏标题 (Title Large)', '用于页面顶栏(AppBar)大标题、警告对话框主体抬头', 20, 16, 26, '精细化字号微调'),
]


def v3_fontsizes_page():
    rows = [sl3(rx(ic), t, f'{v}px', (v - lo) / (hi - lo) * 100, d) for ic, t, d, v, lo, hi, _ in SIZES]
    return (STATUS + ab3('精细化字号微调', f'<div class="ib">{rx("f07e", 24)}</div><div style="width:16px"></div>')
            + '<div class="b3">' + gt3('正文及次要文本层级') + card3(rows[:3]) + '<div class="g3"></div>' + gt3('标题及核心组件层级') + card3(rows[3:]) + '</div>')


def v3_fontsizes():
    dlg = ('<div class="dg" style="left:16px;right:16px;top:320px"><div class="h" style="font-size:15px;font-weight:700">重置</div>'
           '<div class="bd" style="color:var(--on)">将五项精细字号全部恢复为默认值？</div>'
           '<div class="ac"><span style="color:rgba(0,0,0,.6)">取消</span><span class="err">重置</span></div></div>')
    return C([v3_fontsizes_page(), v3_fontsizes_page() + scrim() + dlg], ['精细化字号微调', '点右上角重置'])


def v4_fontsizes():
    def srow(i, n=None):
        ic, t, d, v, lo, hi, sample = SIZES[i]
        weight = 600 if i in (2, 3, 4) else 400
        below = f'<div style="margin:0 6px 2px 40px;font-size:{v}px;font-weight:{weight};line-height:1.4;color:var(--on)">{sample}</div>'
        return slider(rx(ic), t, f'{v}px', (v - lo) / (hi - lo) * 100, sub=d, n=n, tag='add' if n else None, below=below)
    body = (STATUS + ab('精细化字号微调', f'<div class="ib"{attrs(51, "chg")}>{rx("f07e", 22)}</div>', n_back=None)
            + '<div class="sb"><div class="note" style="margin:4px 4px 0">一般调外观页的“文字大小”就够了；这里分别调整五种字号，每一项下面是用这个字号显示的示例。</div>'
            + sgt('正文及次要文本层级') + card([srow(0, 52), srow(1), srow(2)]) + sgt('标题及核心组件层级') + card([srow(3), srow(4)]) + '</div>')
    return P(body)


# =====================================================================
# 6. loading style (loading_style_settings_page.dart:390-548)
# =====================================================================
STYLES = [('default', '默认圆环', 'ring'), ('rotatingPlain', '旋转方块', 'square'), ('doubleBounce', '双重大圆', 'double'),
          ('wave', '波浪跳跃', 'bars'), ('wanderingCubes', '双块漫游', 'cubes'), ('fadingFour', '交替隐藏', 'four'),
          ('fadingCube', '渐隐方块', 'four'), ('pulse', '脉冲水波', 'pulse'), ('chasingDots', '追逐双圆', 'chase'),
          ('threeBounce', '三点弹跳', 'dots3'), ('circle', '时钟小点', 'clock'), ('cubeGrid', '九宫方格', 'grid'),
          ('fadingCircle', '渐隐圆圈', 'clock'), ('rotatingCircle', '旋转大圆', 'disc'), ('foldingCube', '折叠魔方', 'four'),
          ('pumpingHeart', '心跳波动', 'heart'), ('hourGlass', '翻转沙漏', 'glass'), ('pouringHourGlass', '流动沙漏', 'glass')]


def glyph(kind):
    c = 'var(--primary)'
    if kind == 'ring':
        return f'<div class="gl"><div style="position:absolute;inset:4px;border-radius:50%;border:3px solid {c};border-right-color:transparent;border-bottom-color:color-mix(in srgb,{c} 30%,transparent)"></div></div>'
    if kind == 'square':
        return f'<div class="gl"><div style="position:absolute;inset:7px;background:{c};transform:perspective(60px) rotateX(35deg)"></div></div>'
    if kind == 'double':
        return f'<div class="gl"><div style="position:absolute;inset:2px;border-radius:50%;background:{c};opacity:.45"></div><div style="position:absolute;inset:10px;border-radius:50%;background:{c};opacity:.6"></div></div>'
    if kind == 'bars':
        bars = ''.join(f'<i style="width:4px;height:{h}px;background:{c};border-radius:1px"></i>' for h in (14, 24, 32, 22, 12))
        return f'<div class="gl" style="display:flex;align-items:center;justify-content:center;gap:2px">{bars}</div>'
    if kind == 'cubes':
        return f'<div class="gl"><i style="position:absolute;left:2px;top:2px;width:12px;height:12px;background:{c}"></i><i style="position:absolute;right:2px;bottom:2px;width:12px;height:12px;background:{c}"></i></div>'
    if kind == 'four':
        q = ''.join(f'<i style="width:14px;height:14px;background:{c};opacity:{o}"></i>' for o in (1, .5, .5, 1))
        return f'<div class="gl" style="display:grid;grid-template-columns:14px 14px;gap:4px;place-content:center;transform:rotate(45deg) scale(.8)">{q}</div>'
    if kind == 'pulse':
        return f'<div class="gl"><div style="position:absolute;inset:2px;border-radius:50%;background:{c};opacity:.35"></div></div>'
    if kind == 'chase':
        return f'<div class="gl"><i style="position:absolute;left:12px;top:0;width:14px;height:14px;border-radius:7px;background:{c}"></i><i style="position:absolute;left:10px;bottom:2px;width:10px;height:10px;border-radius:5px;background:{c}"></i></div>'
    if kind == 'dots3':
        d = ''.join(f'<i style="width:9px;height:9px;border-radius:5px;background:{c};opacity:{o}"></i>' for o in (.4, 1, .7))
        return f'<div class="gl" style="display:flex;align-items:center;justify-content:center;gap:3px">{d}</div>'
    if kind == 'clock':
        d = ''.join(f'<i style="position:absolute;left:16px;top:1px;width:4px;height:4px;border-radius:2px;background:{c};opacity:{.25 + k * .06};transform-origin:2px 17px;transform:rotate({k * 30}deg)"></i>' for k in range(12))
        return f'<div class="gl">{d}</div>'
    if kind == 'grid':
        q = ''.join(f'<i style="width:9px;height:9px;background:{c};opacity:{o}"></i>' for o in (1, .7, .4, .7, 1, .7, .4, .7, 1))
        return f'<div class="gl" style="display:grid;grid-template-columns:repeat(3,9px);gap:2px;place-content:center">{q}</div>'
    if kind == 'disc':
        return f'<div class="gl"><div style="position:absolute;inset:3px;border-radius:50%;background:{c};transform:perspective(60px) rotateY(50deg)"></div></div>'
    if kind == 'heart':
        return f'<div class="gl" style="display:grid;place-items:center">{mi("favorite", 32, "color:" + c)}</div>'
    return f'<div class="gl" style="display:grid;place-items:center">{mi("hourglass_bottom", 32, "color:" + c)}</div>'


def lgrid(sel=0, label=11, n=None):
    cells = ''.join(f'<div class="lc{" on" if i == sel else ""}" style="height:118px"{attrs(n if i == 3 else None, "keep")}>'
                    + (f'<span class="ok">{mi("check_circle", 16)}</span>' if i == sel else '')
                    + f'<div class="an">{glyph(k)}</div><div class="lb" style="font-size:{label}px">{zh}</div></div>'
                    for i, (_, zh, k) in enumerate(STYLES))
    return f'<div class="lg" style="grid-template-columns:repeat(3,1fr)">{cells}</div>'


def v3_loading():
    body = (STATUS + ab3('修改加载动画', f'<div class="ib">{rx("ea58", 24)}</div><div style="width:8px"></div>')
            + '<div style="padding:16px">' + gt3('修改加载颜色')
            + card3([t3(rx('efc5'), '修改加载颜色', '自定义网络加载动画的颜色', trailing='<span class="ind3" style="background:var(--primary)"></span>')])
            + '</div><div style="padding:0 16px 16px">' + lgrid() + '</div><div class="syn" style="top:216px;left:auto;right:16px;transform:none">动画示意</div>')
    return P(body, crop=False)


def v4_loading_page(n=True):
    N = (lambda k: k) if n else (lambda k: None)
    return (STATUS + ab('修改加载动画', f'<div class="ib"{attrs(N(61), "chg")}>{rx("ea58", 22)}</div>')
            + '<div class="sb" style="padding-bottom:16px">' + card([row(rx('efc5'), '修改加载颜色', '自定义网络加载动画的颜色', 'color', 'var(--primary)', n=N(62), tag='keep',
                                                       extra='<div class="b" style="margin-top:4px">现在：跟随主题色</div>')])
            + '<div style="height:16px"></div>' + lgrid(label=12, n=N(63)) + '</div><div class="syn" style="top:204px;left:auto;right:16px;transform:none">动画示意</div>')


def v4_loading():
    confirm = ('<div class="dg" style="left:24px;right:24px;top:300px"><div class="h">恢复默认？</div>'
               '<div class="bd">加载动画换回“默认圆环”，颜色换回跟随主题色。</div>'
               f'<div class="ac"><span>取消</span><span class="fill"{attrs(64, "add")}>恢复默认</span></div></div>')
    return C([v4_loading_page(), v4_loading_page(False) + scrim() + confirm], ['修改加载动画', '右上角“恢复默认”先确认'])


# =====================================================================
# 7. room card settings (room_card_settings_page.dart:32-310)
# =====================================================================
def preview_card():
    return ('<div class="rc"><div class="cv" style="background-image:url(.cache/img/111.jpg)"><span class="syn2">示意图片</span>'
            f'<span class="cc">{mr("people_alt", 14)}1.3万</span></div>'
            '<div class="inf"><span class="av2">预</span><div style="min-width:0"><div class="tt2">Pure Live · 直播间预览</div><div class="nk">预览主播</div></div></div></div>')


def v3_chip(label, on, icon=None):
    lead = mi('check', 18) if on else (rx(icon, 18) if icon else '')
    return f'<span class="chip3{" on" if on else ""}">{lead}{label}</span>'


def v3_toggle(icon, title, sub, on=True):
    return (f'<div class="t3 sw3"><span class="ic" style="color:var(--onv)">{icon}</span><div class="x"><div class="a">{title}</div>'
            f'<div class="b" style="color:var(--on);white-space:normal">{sub}</div></div><span class="sw{" on" if on else ""}"></span></div>')


def v3_roomcard():
    gap = '<div class="g3"></div>'
    badge = ('<div class="t3" style="align-items:flex-start;padding:12px 8px 12px 16px"><span class="ic" style="color:var(--onv)">' + rx('ee90', 24) + '</span>'
             '<div class="x"><div class="a">显示平台徽章</div><div class="b" style="color:var(--on);white-space:normal">可让宽卡片自动显示、始终在封面显示或保持隐藏</div>'
             f'<div style="display:flex;gap:8px;flex-wrap:wrap;margin-top:10px">{v3_chip("自动", True)}{v3_chip("始终显示", False)}{v3_chip("隐藏", False)}</div></div></div>')
    layout = ('<div class="t3" style="align-items:flex-start;padding:12px 8px 12px 16px"><span class="ic" style="color:var(--onv)">' + mi('view_agenda', 24) + '</span>'
              '<div class="x"><div class="a">卡片布局</div><div class="b" style="color:var(--on);white-space:normal">选择大图封面卡片，或不显示大封面的紧凑主播信息行</div>'
              f'<div style="display:flex;gap:8px;flex-wrap:wrap;margin-top:10px">{v3_chip("封面卡片", True)}{v3_chip("紧凑信息行", False)}</div></div></div>')
    body = (STATUS + ab3('房间卡片设置', f'<div class="ib">{rx("f080", 24)}</div>')
            + '<div style="padding:12px 16px 32px">' + gt3('应用到')
            + f'<div style="display:flex;gap:8px">{v3_chip("移动端", True)}{v3_chip("桌面端", False, "ebca")}</div>' + gap
            + gt3('实时预览') + preview_card() + gap
            + gt3('快捷预设') + f'<div style="display:flex;gap:8px">{v3_chip("简洁", False)}{v3_chip("标准", True)}{v3_chip("详细", False)}</div>' + gap
            + gt3('显示内容') + '<div class="cd3">' + v3_toggle(rx('f256', 24), '显示主播头像', '在房间标题旁保留主播身份图片') + '<div class="dv3"></div>'
            + v3_toggle(rx('ea09', 24), '显示主播名称', '在房间标题下方显示主播名称') + badge
            + v3_toggle(rx('ede3', 24), '显示观众指标', '在直播卡片上显示平台支持的观众数据') + '<div class="dv3"></div>'
            + v3_toggle(rx('f282', 24), '显示回放徽章', '标记回放和录播房间') + '</div>' + gap
            + gt3('外观') + '<div class="cd3">' + layout + sl3(rx('f099'), '圆角大小', '20', 62.5, '同步调整卡片和封面圆角') + '</div>'
            + '<div style="height:16px"></div><div style="font-size:12px;color:var(--outline)">移动端和桌面端设置分别保存；状态核验与历史删除控件会在需要时继续显示。</div></div>')
    return P(body)


def v4_roomcard_body(n=True):
    N = (lambda k: k) if n else (lambda k: None)
    return (STATUS + ab('房间卡片设置', f'<div class="ib"{attrs(N(71), "chg")}>{rx("f080", 22)}</div>')
            + '<div class="sb">' + sgt('应用到')
            + f'<div style="padding:0 4px">{chips(["移动端（手机、平板）", "桌面端（电脑）"], on=0, n=N(72), tag="keep", indent=0)}</div>'
            + sgt('实时预览') + preview_card()
            + sgt('快捷预设') + f'<div style="padding:0 4px;display:flex;align-items:center;gap:12px">{chips(["简洁", "标准", "详细"], on=1, n=N(73), tag="keep", indent=0)}</div>'
            + '<div class="note" style="margin-top:6px">改了下面任何一项，就显示“当前：自定义”，点一个预设回到它的样子。</div>'
            + sgt('显示内容') + card([
                row(rx('f256'), '显示主播头像', '在房间标题旁保留主播身份图片', 'switch', sw=True, n=N(74), tag='keep'),
                row(rx('ea09'), '显示主播名称', '在房间标题下方显示主播名称', 'switch', sw=True),
                row(rx('ee90'), '显示平台徽章', '可让宽卡片自动显示、始终在封面显示或保持隐藏', 'none', extra=chips(['自动', '始终显示', '隐藏'], on=0, indent=0), n=N(75), tag='keep'),
                row(rx('ede3'), '显示观众指标', '在直播卡片上显示平台支持的观众数据', 'switch', sw=True),
                row(rx('f282'), '显示回放徽章', '标记回放和录播房间', 'switch', sw=True)])
            + sgt('外观') + card([
                row(mi('view_agenda', 22, 'color:var(--primary)'), '卡片布局', '选择大图封面卡片，或不显示大封面的紧凑主播信息行', 'none',
                    extra=chips(['封面卡片', '紧凑信息行'], on=0, indent=0), n=N(76), tag='keep'),
                slider(rx('f099'), '圆角大小', '20', 62.5, sub='同步调整卡片和封面圆角', n=N(77), tag='keep')])
            + '<div class="note">移动端和桌面端设置分别保存；状态核验与历史删除控件会在需要时继续显示。</div></div>')


def v4_roomcard():
    return P(v4_roomcard_body())


# =====================================================================
# 8. navigation (navigation_settings_page.dart:10-206)
# =====================================================================
def v3_nav():
    def r(ic, t):
        return (f'<div class="t3" style="min-height:60px;padding:6px 16px"><span class="ic">{ic}</span><div class="x"><div class="a">{t}</div></div>'
                f'<span class="sw on"></span><span style="width:8px"></span><span class="ib">{rx("f15f", 20)}</span></div>')
    body = (STATUS + ab3('导航栏显示控制') + '<div class="b3">'
            + f'<div class="tip3">{rx("ee59")}<span>长按右侧图标并上下拖动，即可自定义底部菜单栏的功能展示顺序。</span></div><div style="height:16px"></div>'
            + gt3('导航栏显示控制') + '<div class="cd3">'
            + r(rx('ee0a'), '关注') + r(f'<span class="ci" style="font-size:22px">&#xe803;</span>', '热门') + r(rx('ea42'), '分区') + r(rx('ec53'), '录制中心')
            + '</div></div>')
    return P(body, crop=False)


def v4_nav():
    def r(ic, t, on=True, n=None, hn=None):
        handle = f'<span class="ib" style="width:44px;height:48px;margin-right:-8px"{attrs(hn, "chg")}>{mr("drag_handle", 24, "color:var(--onv)")}</span>' if on else '<span style="width:36px"></span>'
        return (f'<div class="sr one"><span class="ic">{ic}</span><div class="x"><div class="a">{t}</div>'
                + ('' if on else '<div class="b">已隐藏</div>') + f'</div><span class="sw{" on" if on else ""}"{attrs(n, "keep")}></span>{handle}</div>')
    body = (STATUS + ab('导航栏显示控制', n_back=None) + '<div class="sb">'
            + sgt('首页入口') + card([row(rx('ee90'), '多画面', '在首页显示多画面入口（手机在右上角菜单里，宽屏在侧边栏）', 'switch', sw=True, n=81, tag='chg')])
            + sgt('底部导航栏')
            + '<div class="note" style="margin:0 4px 10px">按住右侧把手上下拖动可以调整顺序；隐藏的排在最后，至少保留一个。</div>'
            + card([r(rx('ee0b'), '关注', n=82), r(rx('ed33'), '热门', hn=83), r(rx('ea42'), '分区'), r(rx('ec54'), '录制中心', on=False)])
            + '<div class="note" style="margin-top:14px">宽屏时同样的顺序用在左侧的导航栏。</div></div>')
    return P(body, crop=False)


# =====================================================================
# 9. page settings, only on desktops (page_settings.dart:9-205)
# =====================================================================
def v3_page():
    page = (ab3('分页设置') + '<div class="b3"><div style="max-width:960px;margin:0 auto">' + gt3('通用分页控制条') + card3([
        t3(rx('eebd'), '显示单页数量选择器', '在列表控制条显示每页显示行数下拉选单', sw=True),
        t3(rx('f146'), '显示页码跳转按钮', '开启后支持手动输入页码进行快速跳转', sw=True),
        t3(rx('ea72'), '显示一键置顶按钮', '列表滑动超过设定距离后在右下角悬浮置顶按钮', sw=True),
        t3(rx('eeb9'), '单页可选数量列表', '20, 40, 60, 80', trailing=CHEV24)]) + '</div></div>')
    chip = lambda v: f'<span class="chip3" style="background:var(--scl);box-shadow:inset 0 0 0 1px var(--ov);font-size:12px">{v}{mi("cancel", 16, "color:var(--onv)")}</span>'
    dlg = ('<div class="dg" style="left:calc(50% - 184px);width:368px;top:200px"><div class="h" style="font-size:15px;font-weight:700">单页可选数量列表</div>'
           '<div style="padding:16px 24px 0"><div style="display:flex;justify-content:space-between;align-items:center"><span style="font-size:12px;color:rgba(0,0,0,.6)">当前已启用的可选项</span>'
           f'<span style="display:flex;align-items:center;gap:6px;color:var(--primary);font-size:12px;font-weight:600">{mi("screen_rotation", 14)}自适应推荐</span></div>'
           f'<div style="display:flex;gap:8px;flex-wrap:wrap;margin-top:8px">{chip(20)}{chip(40)}{chip(60)}{chip(80)}</div>'
           '<div style="height:24px"></div><div style="font-size:13px;font-weight:500">自定义输入尺寸</div><div style="height:12px"></div>'
           '<div style="display:flex;gap:8px;align-items:flex-start"><div style="flex:1"><div style="height:40px;border-radius:4px;box-shadow:inset 0 0 0 1px var(--outline);display:flex;align-items:center;padding:0 12px;font-size:14px;color:var(--onv)">'
           '<span style="flex:1">20</span><span style="font-size:12px">条/页</span></div><div class="hlp" style="padding-left:12px">请输入 1 至 100 的整数</div></div>'
           '<span style="height:40px;padding:0 20px;border-radius:12px;background:var(--scl);color:var(--primary);display:flex;align-items:center;font-size:13px;font-weight:500">添加</span></div></div>'
           '<div class="ac"><span style="color:rgba(0,0,0,.6)">取消</span><span>确认</span></div></div>')
    return doc(1280, 800, 1.5, page + scrim() + dlg, css=CSS6, root='win')


def v4_page(dialog=False):
    content = (sgt('分页条（电脑）') + card([
        row(rx('eebd'), '显示单页数量选择器', '在列表控制条显示每页显示行数下拉选单', 'switch', sw=True, n=91, tag='keep'),
        row(rx('f146'), '显示页码跳转按钮', '开启后支持手动输入页码进行快速跳转', 'switch', sw=True, n=92, tag='chg'),
        row(rx('eeb9'), '单页可选数量列表', '20, 40, 60, 80', 'link', n=93, tag='keep'),
        row(rx('ee95'), '默认每页条数', '进入列表时每页显示多少条；分页条上也能临时改', 'choice', '20', n=94, tag='add')])
        + '<div class="note">“显示一键置顶按钮”手机上也有，已经放在外观页的“房间卡片和列表”里。</div>')
    chip = lambda v: f'<span class="chip" style="height:32px;padding:0 6px 0 12px">{v}{mr("close", 18, "color:var(--onv)")}</span>'
    dlg = ('<div class="dg" style="left:calc(50% - 200px + 180px);width:400px;top:170px"><div class="h">单页可选数量列表</div>'
           '<div style="padding:12px 24px 0"><div style="display:flex;justify-content:space-between;align-items:center"><span style="font-size:13px;color:var(--onv)">当前已启用的可选项</span>'
           f'<span class="tb2 txt" style="height:36px"{attrs(95, "chg")}>{rx("f080", 18)}恢复推荐</span></div>'
           f'<div style="display:flex;gap:8px;flex-wrap:wrap;margin-top:8px"{attrs(96, "keep")}>{chip(20)}{chip(40)}{chip(60)}{chip(80)}</div>'
           '<div style="height:20px"></div><div style="display:flex;gap:8px;align-items:flex-start"><div style="flex:1">'
           f'<div class="fld ol" style="display:flex;align-items:center;height:48px;padding:0 12px"{attrs(97, "keep")}><span style="flex:1;color:var(--onv);font-size:15px">输入 1–100</span><span style="font-size:13px;color:var(--onv)">条/页</span></div></div>'
           '<span class="tb2" style="height:48px;border-radius:24px;flex:none;white-space:nowrap">添加</span></div></div>'
           '<div class="ac"><span>取消</span><span class="fill">确认</span></div></div>')
    back = f'<span class="ib" style="width:40px;height:40px;margin-left:-12px">{mi("arrow_back", 22)}</span>'
    title = back + '<span style="margin-left:4px">分页设置</span>'
    if not dialog:
        return two_pane(1280, 800, 1.5, title, content, n_left=False, title_attrs=' style="display:flex;align-items:center"', css=CSS6)
    import re
    plain = re.sub(r' data-(n|tag|at)="[^"]*"', '', content)
    return two_pane(1280, 800, 1.5, title, plain, n_left=False,
                    title_attrs=' style="display:flex;align-items:center"', overlay=scrim() + dlg, css=CSS6)


# =====================================================================
# 10. theme colours: v3 default, brand blue (C-3), dark, pure black (C-4)
# =====================================================================
BRAND = ('--primary:#0056C2;--onPrimary:#FFFFFF;--pc:#2E6FE0;--opc:#FCFAFF;--sc:#B8CBFE;--osc:#425580;--surface:#FAF8FF;--on:#191B22;'
         '--onv:#424753;--outline:#737785;--ov:#C2C6D6;--scl:#F2F3FD;--scc:#EDEDF7;--sch:#E7E7F1;--schh:#E1E2EC;')
DARK = ('--primary:#A0CAFD;--onPrimary:#003258;--pc:#194975;--opc:#D1E4FF;--sc:#3B4858;--osc:#D7E3F7;--surface:#111418;--on:#E1E2E8;'
        '--onv:#C3C7CF;--outline:#8D9199;--ov:#43474E;--scl:#191C20;--scc:#1D2024;--sch:#272A2F;--schh:#32353A;')
BLACK = ('--primary:#AFC6FF;--onPrimary:#002D6D;--pc:#2E6FE0;--opc:#FCFAFF;--sc:#354873;--osc:#A5B8E9;--surface:#000000;--on:#E6E6E8;'
         '--onv:#C2C6D6;--outline:#8C909F;--ov:#424753;--scl:#0E0E10;--scc:#161618;--sch:#1E1E21;--schh:#1E1E21;')


def theme_phone(vars_, swatch, black=False, dark=False):
    sample = ('<div style="display:flex;gap:8px;align-items:center;padding:12px 4px 4px">'
              '<span style="height:40px;padding:0 18px;border-radius:20px;background:var(--primary);color:var(--onPrimary);display:flex;align-items:center;font-size:14px;font-weight:600">确认</span>'
              '<span class="chip on">' + mr('check', 18) + '标准</span><span class="sw on"></span>'
              '<span style="font-size:14px;color:var(--primary);font-weight:600">链接文字</span></div>')
    body = (STATUS + ab('外观') + '<div class="sb">' + sample + appearance_v4(swatch=swatch, black=black) + '</div>')
    gesture = '<div class="gesture"></div>'
    return f'<div style="{vars_}background:var(--surface);color:var(--on);position:absolute;inset:0">{body}</div>' + gesture


def v4_theme_options():
    phones = [theme_phone('', '#2196F3'), theme_phone(BRAND, '#2E6FE0'), theme_phone(DARK, '#2196F3', dark=True),
              theme_phone(BLACK, '#2E6FE0', black=True)]
    caps = ['v3 默认：种子 #2196F3，主色 #36618E', 'C-3 品牌蓝：种子 #2E6FE0，主色 #0056C2', '深色（v3 已有）', 'C-4 纯黑背景（配品牌蓝）']
    return C(phones, caps)


OUT = {
    'v3-appearance': v3_appearance(), 'v3-appearance-land': v3_appearance_land(), 'v3-appearance-wide': v3_appearance_wide(),
    'v4-appearance': v4_appearance(), 'v4-appearance-land': v4_appearance_land(), 'v4-appearance-wide': v4_appearance_wide(),
    'v3-dialogs': v3_dialogs(), 'v4-dialogs': v4_dialogs(),
    'v3-color': v3_color(), 'v4-color': v4_color(),
    'v3-fonts': v3_fonts(), 'v4-fonts': v4_fonts(), 'v3-fontweight': v3_fontweight(), 'v4-font-popups': v4_font_popups(),
    'v3-fontsizes': v3_fontsizes(), 'v4-fontsizes': v4_fontsizes(),
    'v3-loading': v3_loading(), 'v4-loading': v4_loading(),
    'v3-roomcard': v3_roomcard(), 'v4-roomcard': v4_roomcard(),
    'v3-nav': v3_nav(), 'v4-nav': v4_nav(),
    'v3-page': v3_page(), 'v4-page': v4_page(), 'v4-page-dialog': v4_page(dialog=True),
    'v4-theme-options': v4_theme_options(),
}
for name, html in OUT.items():
    open(os.path.join(HERE, name + '.html'), 'w', encoding='utf-8').write(html)
print(len(OUT), 'pages')
