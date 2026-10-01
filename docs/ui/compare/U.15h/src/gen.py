"""U.15h TV wallpaper mockups: pure_live_TV restored (v3-*) and the new
design (v4-*). Shared TV pieces come from ../../U.15f/src/tvkit.py.
    python3 docs/ui/compare/U.15h/src/gen.py && python3 tools/ui/mock/render.py docs/ui/compare/U.15h/src/ --annotate
pure_live_TV sources (~/ref/pure_live_TV/lib):
  features/wallpaper/wallpaper_page.dart, wallpaper_library_page.dart, wallpaper_api_page.dart,
  wallpaper_api_group_page.dart, wallpaper_gallery_page.dart, wallpaper_items_page.dart, wallpaper_tile.dart,
  wallpaper_preview_page_parts.dart, wallpaper_immersive_page.dart, wallpaper_display_options.dart
  core/widgets/tv_settings_row.dart, tv_settings_option_tile.dart, tv_scaffold_background.dart
  services/background_config/background_config_model.dart (cover, mask 0.35, blur 0)
"""
import os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', 'U.15f', 'src'))
from tvkit import *  # noqa: E402,F401,F403

WP = 274
CSS = '''
.wp{position:absolute;inset:0;background:#000 center/cover}
.wpm{position:absolute;inset:0;background:rgba(0,0,0,.35)}
.srow3{display:flex;align-items:center;gap:16px;padding:14px 16px;border-radius:14px}
.srow3.foc{background:#1E3948;box-shadow:0 0 18px 1.5px rgba(0,161,255,.75),0 0 0 2px #00A1FF}
.srow3 .a{font-size:22px;font-weight:600}.srow3 .b{font-size:16px;margin-top:4px}
.scard3{background:rgba(31,31,31,.05);border:1px solid rgba(31,31,31,.10);border-radius:20px;padding:4px}
.sgt3{font-size:16px;color:rgba(0,161,255,.85);padding:0 0 8px 8px;font-weight:600}
.pb3{height:56px;padding:0 24px;border-radius:26px;background:#1F1F1F;display:inline-flex;align-items:center;gap:10px;font-size:20px;font-weight:600;color:#fff}
.pb3.foc{background:#00A1FF}
.sl{display:flex;align-items:center;gap:10px}
.sl .tk{width:160px;height:4px;border-radius:2px;background:rgba(255,255,255,.25);position:relative}
.sl .tk i{position:absolute;left:0;top:0;bottom:0;border-radius:2px;background:#4D9BFF}
.sl .tk u{position:absolute;top:50%;width:16px;height:16px;border-radius:8px;background:#fff;transform:translate(-50%,-50%)}
.wt{position:relative;border-radius:12px;background:#16243A center/cover;aspect-ratio:16/9}
.wt.f{transform:scale(1.05);box-shadow:0 0 0 3px #F2F5FA,0 6px 18px rgba(0,0,0,.5)}
'''
WALLS = [274, 1, 158, 169, 225, 250, 287, 292, 304, 319, 338, 360]


def wall(img=WP, mask=.35):
    return f'<div class="wp" style="background-image:url({IMG(img)})"></div><div class="wpm" style="background:rgba(0,0,0,{mask})"></div>'


# ======================================================================
#  v3
# ======================================================================
def srow3(icon, title, sub=None, value=None, focus=False, lead=None, fam='mo'):
    ic = lead if lead is not None else (mr if fam == 'mr' else mo)(icon, 30)
    trail = (f'<span style="font-size:20px;font-weight:600">{value}</span>{mr("expand_more", 28)}' if value is not None else mr('chevron_right', 30))
    sb = f'<div class="b">{sub}</div>' if sub else ''
    return (f'<div class="srow3{" foc" if focus else ""}">{ic}<div style="flex:1;min-width:0"><div class="a">{title}</div>{sb}</div>{trail}</div>')


def v3_settings():
    src = (srow3('gradient', '纯色', '纯色与渐变填充') + srow3('movie', '视频壁纸', '动态视频背景') + srow3('photo_library', '壁纸库', '官方、Wallhaven、必应等图库')
           + srow3('auto_awesome', '随机壁纸 API', '每次打开随机取一张图'))
    disp = (srow3('aspect_ratio', '填充模式', value='等比覆盖') + srow3('brightness_6', '遮罩', value='35%') + srow3('blur_on', '高斯模糊', value='关闭')
            + srow3('layers_clear', '清除背景'))
    body = (wall() + '<div style="position:relative">' + hdr3('背景设置', focus_back=True) + '<div style="padding:12px 16px">'
            f'<div class="sgt3">背景来源</div><div class="scard3">{src}</div><div style="height:20px"></div>'
            f'<div class="sgt3">显示设置</div><div class="scard3">{disp}</div></div></div>')
    return page(body, CSS, restore=True)


GROUPS = [('必应壁纸', 6), ('栗次元', 12), ('无铭 API', 8), ('UAPI 随机图', 14), ('360壁纸', 16), ('其他图源', 6), ('性感美女', 20)]


def v3_api():
    rows = ''.join(srow3(None, g, f'{n} 个来源', lead=f'<span style="width:30px;text-align:center;font-size:18px;font-weight:600">{i + 1}</span>')
                   for i, (g, n) in enumerate(GROUPS))
    body = wall() + '<div style="position:relative">' + hdr3('随机壁纸 API', focus_back=True) + f'<div style="padding:12px 16px">{rows}</div></div>'
    return page(body, CSS, restore=True)


def v3_items():
    def tile(img, size, cur=False, focus=False):
        st = 'transform:scale(1.04);box-shadow:0 0 0 3px #00A1FF,0 0 16px rgba(0,161,255,.8)' if focus else ''
        chk = f'<span style="position:absolute;right:6px;top:6px">{mi("check_circle", 20, "#00A1FF")}</span>' if cur else ''
        return (f'<div style="border-radius:12px;background:#1F1F1F url({IMG(img)}) center/cover;position:relative;{st}">{chk}'
                f'<span style="position:absolute;right:6px;bottom:6px">{chip3(size)}</span></div>')
    sizes = ['2.4M', '1.8M', '3.1M', '980K', '2.2M', '1.6M', '4.0M', '2.7M', '1.1M', '3.3M', '2.0M', '1.4M']
    grid = ('<div style="display:grid;grid-template-columns:repeat(4,minmax(0,1fr));grid-auto-rows:323px;gap:6px;padding:24px">'
            + ''.join(tile(w, sizes[i], cur=(i == 0), focus=(i == 0)) for i, w in enumerate(WALLS)) + '</div>')
    body = wall() + '<div style="position:relative">' + hdr3('风景', focus_back=True) + grid + '</div>'
    return page(body, CSS, restore=True)


def v3_preview():
    top = ('<div style="position:absolute;left:0;right:0;top:0;padding:32px 40px 60px;background:linear-gradient(rgba(0,0,0,.6),transparent);display:flex;align-items:center;gap:18px">'
           '<span style="flex:1;font-size:20px;font-weight:600">风景</span><span style="font-size:20px;color:rgba(255,255,255,.7)" class="t">3/24</span></div>')
    acts = [('chevron_left', '上一个'), ('chevron_right', '下一个'), ('aspect_ratio', '等比覆盖'), ('blur_on', '关闭'), ('brightness_6', '35%'),
            ('check', '设为背景'), ('fullscreen', '沉浸式')]
    btns = ''.join(f'<span class="pb3{" foc" if i == 0 else ""}">{(mo if n in ("aspect_ratio", "blur_on", "brightness_6") else mr)(n, 24)}{l}</span>' for i, (n, l) in enumerate(acts))
    bot = ('<div style="position:absolute;left:0;right:0;bottom:0;padding:60px 24px 40px;background:linear-gradient(transparent,rgba(0,0,0,.72));text-align:center">'
           '<div style="font-size:18px;color:rgba(255,255,255,.7)">←→ 选择按钮 · OK 确认 · 返回退出</div>'
           f'<div style="display:flex;flex-wrap:wrap;justify-content:center;gap:10px;margin-top:18px">{btns}</div></div>')
    body = wall(158) + top + bot
    return page(body, CSS, restore=True)


def v3_immersive():
    hint = ('<div style="position:absolute;left:50%;bottom:64px;transform:translateX(-50%);padding:14px 28px;border-radius:28px;background:rgba(0,0,0,.65);'
            'font-size:20px;white-space:nowrap">↑↓ 切换 · OK 设为壁纸 · 返回退出</div>')
    return page(wall(158) + hint, CSS, restore=True)


def v3_applied():
    cards = [vcard3(v, focus=(i == 0)) for i, v in enumerate(VIDEOS)]
    rail = rail3('video', 2)
    body = (wall() + rail + '<div class="pane">' + tabs3(['动态', '推荐', '热门'], 1)
            + '<div class="grid3" style="grid-template-columns:repeat(4,minmax(0,1fr));grid-auto-rows:323px;padding-top:24px">' + ''.join(cards) + '</div></div>')
    return page(body, CSS, restore=True)


# ======================================================================
#  new design
# ======================================================================
def srow4(icon, title, sub=None, value=None, focus=False, n=None, tag='keep', lead=None, slider=None, red=False):
    ic = lead if lead is not None else mo(icon, 22, '#FF8A80' if red else 'rgba(243,245,247,.8)')
    if slider is not None:
        pct, label = slider
        trail = (f'<span class="sl"><span class="sub" style="font-size:13px">←</span><span class="tk"><i style="width:{pct}%"></i><u style="left:{pct}%"></u></span>'
                 f'<span class="sub" style="font-size:13px">→</span><span class="v tnum" style="width:44px;text-align:right">{label}</span></span>')
    elif value is not None:
        trail = f'<span class="v">{value}</span>{mr("arrow_drop_down", 22, "rgba(243,245,247,.72)")}'
    else:
        trail = mr('chevron_right', 22, 'rgba(243,245,247,.72)')
    sb = f'<div class="b">{sub}</div>' if sub else ''
    st = 'color:#FF8A80' if red else ''
    return (f'<div class="nrow{" fr" if focus else ""}" style="margin-bottom:8px;background:{"#1E3148" if focus else "rgba(16,26,38,.88)"}"{at(n, tag)}>{ic}'
            f'<div class="x"><div class="a" style="{st}">{title}</div>{sb}</div>{trail}</div>')


def v4_settings(n=True, clear=False):
    N = (lambda k: k) if n else (lambda k: None)
    rows = ('<div class="nsec">背景来源</div>'
            + srow4('gradient', '纯色', '纯色与渐变填充') + srow4('movie', '视频壁纸', '动态视频背景')
            + srow4('photo_library', '壁纸库', '官方、Wallhaven、必应等图库', n=N(2)) + srow4('auto_awesome', '随机壁纸 API', '每次打开随机取一张图', n=N(3))
            + '<div class="nsec" style="margin-top:14px">显示设置</div>'
            + srow4('aspect_ratio', '填充模式', value='等比覆盖', n=N(4)) + srow4('brightness_6', '遮罩', slider=(35, '35%'), focus=not clear, n=N(5), tag='chg')
            + srow4('blur_on', '高斯模糊', '视频壁纸不能模糊', slider=(0, '关闭'), n=N(6), tag='chg')
            + srow4('layers_clear', '清除背景', '恢复主题色的纯色背景', red=True, n=N(7), tag='chg'))
    body = (wall() + '<div class="ncontent" style="left:48px;right:192px">' + hdr4('背景设置', n=N(1))
            + f'<div style="position:absolute;left:-8px;right:-8px;top:76px;bottom:0;overflow:hidden;padding:4px 8px">'
            f'<div style="position:relative;top:-150px">{rows}</div></div></div>')
    if clear:
        body += ('<div class="nscrim"></div><div class="ndlg" style="width:400px"><div class="h">清除背景？</div>'
                 '<div class="p">清除后恢复主题色的纯色背景；填充、遮罩、模糊的设置保留。</div>'
                 f'<div class="btns">{nb("取消", "", "f", n=N(10), tag="keep")}{nb("清除", "", "pri", n=N(11), tag="add")}</div></div>')
    return page(body, CSS)


def v4_api(n=True):
    N = (lambda k: k) if n else (lambda k: None)
    rows = ''.join(srow4(None, g, f'{c} 个来源', focus=(i == 0), n=N(2) if i == 0 else None,
                         lead=f'<span class="sub" style="width:22px;text-align:center;font-size:15px;font-weight:600">{i + 1}</span>')
                   for i, (g, c) in enumerate(GROUPS))
    body = (wall() + '<div class="ncontent" style="left:48px;right:192px">' + hdr4('随机壁纸 API', n=N(1))
            + f'<div style="position:absolute;left:0;right:0;top:76px">{rows}</div></div>')
    return page(body, CSS)


def v4_items(n=True):
    N = (lambda k: k) if n else (lambda k: None)
    sizes = ['2.4M', '1.8M', '3.1M', '980K', '2.2M', '1.6M', '4.0M', '2.7M', '1.1M', '3.3M', '2.0M', '1.4M']
    tiles = ''
    for i, w in enumerate(WALLS):
        cur = f'<span class="nchip" style="left:6px;top:6px;background:#1079F9">{mr("check", 14)}当前</span>' if i == 0 else ''
        tiles += (f'<div class="wt{" f" if i == 1 else ""}"{at(N(2) if i == 1 else None, "keep")} style="background-image:url({IMG(w)})">{cur}'
                  f'<span class="nchip" style="right:6px;bottom:6px">{sizes[i]}</span></div>')
    body = (wall() + '<div class="ncontent" style="left:48px">' + hdr4('Wallhaven · 风景', n=N(1), actions='<span class="sub" style="font-size:14px">24 张</span>')
            + f'<div class="ngrid" style="top:76px">{tiles}</div></div>')
    return page(body, CSS)


def v4_preview(n=True, popup=False):
    N = (lambda k: k) if n else (lambda k: None)
    F = lambda k: ' f' if (not popup and k == 0) else ''
    top = ('<div class="vtopg"></div><div class="vtitle"><span class="t">Wallhaven · 风景</span><span class="m">3 / 24</span></div>')
    acts = [('chevron_left', '上一张', 'keep'), ('chevron_right', '下一张', 'keep'), ('aspect_ratio', '填充 · 等比覆盖', 'chg'), ('blur_on', '模糊 · 关闭', 'chg'),
            ('brightness_6', '遮罩 · 35%', 'chg'), ('check', '设为背景', 'keep'), ('fullscreen', '沉浸式', 'keep')]
    pills = ''
    for i, (ic, l, tag) in enumerate(acts):
        cls = 'vp' + F(i) + (' pri' if l == '设为背景' else '')
        st = ' style="background:#1079F9"' if l == '设为背景' else (' style="background:rgba(255,255,255,.34)"' if (popup and i == 4) else '')
        if popup and i == 4:
            l = '遮罩 · 40%'
        pills += f'<span class="{cls}"{at(N(i + 1), tag)}{st}>{(mo if ic in ("aspect_ratio", "blur_on", "brightness_6") else mr)(ic)}{l}</span>'
    hint = '<div class="nhint" style="position:absolute;left:48px;bottom:80px;z-index:6;color:rgba(255,255,255,.75)">←→ 选按钮 · 确认 执行 · 返回 退出</div>'
    body = (wall(158) + top + '<div class="vbotg"></div>' + hint + f'<div class="vpills" style="gap:8px">{pills}</div>')
    if popup:
        body += ('<div class="nmenu" style="left:470px;bottom:76px;width:260px;padding:12px 14px"><div class="mh" style="padding:0 0 8px">遮罩 · 只改预览，设为背景时保存</div>'
                 '<div class="sl" style="justify-content:space-between"><span class="sub" style="font-size:13px">←</span><span class="tk" style="width:170px">'
                 '<i style="width:40%"></i><u style="left:40%;box-shadow:0 0 0 3px #F2F5FA"></u></span><span class="sub" style="font-size:13px">→</span>'
                 '<b class="tnum" style="font-size:15px;width:40px;text-align:right">40%</b></div><div class="nhint" style="margin-top:8px">←→ 调整 5% · 确认 / 返回 关闭</div></div>')
    return page(body, CSS)


def v4_immersive():
    hint = ('<div class="ntoast" style="bottom:40px;font-size:15px;background:rgba(0,0,0,.65)">←→ 或 ↑↓ 换一张 · 确认 设为背景 · 返回 退出</div>')
    return page(wall(158) + hint, CSS)


def v4_applied():
    cards = [vcard4(v, focus=(i == 0)) for i, v in enumerate(VIDEOS)]
    body = (wall() + rail4('video', 2) + '<div class="ncontent">' + tabs4(['动态', '推荐', '热门'], 1)
            + '<div class="ngrid" style="top:76px">' + ''.join(cards) + '</div></div>')
    return page(body, CSS)


OUT = {
    'v3-settings': v3_settings(), 'v4-settings': v4_settings(),
    'v4-clear': v4_settings(clear=True, n=False),
    'v3-api': v3_api(), 'v4-api': v4_api(),
    'v3-items': v3_items(), 'v4-items': v4_items(),
    'v3-preview': v3_preview(), 'v4-preview': v4_preview(), 'v4-preview-mask': v4_preview(n=False, popup=True),
    'v3-immersive': v3_immersive(), 'v4-immersive': v4_immersive(),
    'v3-applied': v3_applied(), 'v4-applied': v4_applied(),
}
if __name__ == '__main__':
    write(HERE, OUT)
