"""U.4d areas page (分区) mockups: v3 restored and the new design.

v3: lib/modules/areas/areas_page.dart (platform tabs in the app bar title,
"关注分区" floating pill :42-82), areas_grid_view.dart (category tabs :180-191,
grid 3/5/7/9 columns :259-288, empty states :146-150, :167-173, :204-208),
widgets/area_card.dart (square picture on white, radius 15, dense ListTile
name t12 w600 + parent category t11 w500, extent itemWidth + 72), shell from
modules/home/mobile_view.dart / tablet_view.dart, desktop pager from
common/base/desktop_components.dart, status views from
common/widgets/app_status_view.dart. Theme: common/style/theme.dart:115-136.

    python3 docs/ui/compare/U.4d/src/gen.py
    python3 tools/ui/mock/render.py docs/ui/compare/U.4d/src/ --annotate
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))

CSS = '''
.col{display:flex;flex-direction:column}
.fill{flex:1;min-height:0;position:relative;overflow:hidden}
.row{display:flex;align-items:center}
.ab{height:56px;flex:none;display:flex;align-items:center;background:var(--surface);position:relative}
.ab .lead{width:56px;height:56px;display:grid;place-items:center;flex:none}
.ab .ttl{flex:1;min-width:0;text-align:center;font-size:20px;font-weight:600}
/* TabBar (v3 theme): 15 px, selected primary semi-bold, others onSurfaceVariant 80 %,
   indicator 2 px under the label only, no divider */
.tb{display:flex;height:46px;flex:none;overflow:hidden;white-space:nowrap}
.tb .t{position:relative;flex:none;height:46px;line-height:46px;padding:0 16px;font-size:15px;color:color-mix(in srgb,var(--onv) 80%,transparent)}
.tb .t.on{color:var(--primary);font-weight:600}
.tb .t.on::after{content:'';position:absolute;left:16px;right:16px;bottom:0;height:2px;border-radius:2px 2px 0 0;background:var(--primary)}
/* new: secondary tabs for the categories (14 px, full-width indicator, divider) */
.tb2{display:flex;height:46px;flex:none;overflow:hidden;white-space:nowrap;box-shadow:inset 0 -1px 0 var(--ov)}
.tb2 .t{position:relative;flex:none;height:46px;line-height:46px;padding:0 14px;font-size:14px;color:var(--onv)}
.tb2 .t.on{color:var(--on);font-weight:600}
.tb2 .t.on::after{content:'';position:absolute;left:0;right:0;bottom:0;height:2px;background:var(--primary)}
/* grid */
.grid{position:absolute;left:0;right:0;top:0;padding:6px;display:grid;gap:6px;align-content:start}
.ac{background:var(--scl);border-radius:15px;overflow:hidden;display:flex;flex-direction:column;position:relative}
.ac .pic{aspect-ratio:1;border-radius:15px;background:#fff center/cover;position:relative}
.ac .cap{height:72px;padding:0 10px;display:flex;flex-direction:column;justify-content:center;gap:2px}
.ac .cap.one{height:40px}
.ac .n{font-size:12px;line-height:16px;font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.ac .s{font-size:12px;line-height:16px;font-weight:500;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.ac .s2{font-size:12px;line-height:16px;color:var(--onv);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.ac.hov{background:var(--sch)}
.ac.press{box-shadow:0 0 0 2px var(--primary)}
.fav{position:absolute;right:6px;top:6px;width:22px;height:22px;border-radius:11px;background:color-mix(in srgb,var(--surface) 92%,transparent);display:grid;place-items:center;color:var(--primary)}
.skel{background:var(--scl);border-radius:15px;overflow:hidden}
.skel .pic{aspect-ratio:1;border-radius:15px;background:var(--sch)}
.skel .b{height:10px;border-radius:5px;background:var(--sch);margin:15px 10px 0}
/* "关注分区" floating pill (areas_page.dart:42-82) */
.fab{position:absolute;right:16px;min-height:48px;padding:0 16px;border-radius:16px;z-index:8;background:color-mix(in srgb,var(--surface) 95%,transparent);
 border:1px solid color-mix(in srgb,var(--primary) 15%,transparent);box-shadow:0 4px 12px rgba(0,0,0,.06);display:flex;align-items:center;gap:8px;color:var(--primary);font-size:12px;font-weight:700;letter-spacing:.5px}
/* M3 NavigationBar / NavigationRail (home shell, U.3a / U.3b) */
.nav{height:80px;flex:none;background:var(--scc);display:flex;position:relative;z-index:9}
.nav .d{flex:1;display:flex;flex-direction:column;align-items:center;padding-top:12px;gap:4px;font-size:12px;font-weight:500;color:var(--onv)}
.nav .d .ic{width:64px;height:32px;border-radius:16px;display:grid;place-items:center}
.nav .d.on{color:var(--on);font-weight:600}.nav .d.on .ic{background:var(--sc);color:var(--osc)}
.rail{width:80px;flex:none;display:flex;flex-direction:column;align-items:center;padding-top:12px;background:var(--surface);overflow:hidden}
.rail .ib{margin-bottom:12px}
.rail .d{display:flex;flex-direction:column;align-items:center;gap:4px;font-size:12px;font-weight:500;color:var(--onv);margin-bottom:14px}
.rail .d .ic{width:56px;height:32px;border-radius:16px;display:grid;place-items:center}
.rail .d.on{color:var(--on);font-weight:600}.rail .d.on .ic{background:var(--sc);color:var(--osc)}
.vdiv{width:1px;flex:none;background:var(--ov)}
.sbar{height:24px;flex:none;display:flex;align-items:center;justify-content:space-between;padding:0 16px;font:600 12px 'Geist','Noto Sans SC'}
.sbar .mi{font-size:14px}
/* desktop pager (desktop_components.dart:94-188) */
.pager{height:68px;flex:none;display:flex;align-items:center;justify-content:center;background:var(--surface);border-top:1px solid color-mix(in srgb,var(--on) 6%,transparent);font-size:13px;position:relative;z-index:3}
.pager .ob{height:36px;padding:0 12px;border-radius:6px;border:1px solid var(--outline);color:var(--primary);display:flex;align-items:center;gap:6px;font-weight:500}
.pager .tbn{height:40px;padding:0 12px;display:flex;align-items:center;gap:6px;color:var(--primary);font-weight:500}
.pager .tbn.dis{color:color-mix(in srgb,var(--on) 38%,transparent)}
.pager .pg{min-width:48px;height:48px;margin:0 3px;border-radius:6px;border:1px solid color-mix(in srgb,var(--on) 10%,transparent);display:grid;place-items:center}
.pager .pg.on{background:var(--primary);border-color:var(--primary);color:var(--onPrimary);font-weight:700}
.pager .mut{color:color-mix(in srgb,var(--on) 60%,transparent)}
.pager .sel{height:30px;padding:0 6px 0 10px;border-radius:6px;background:color-mix(in srgb,var(--on) 5%,transparent);display:flex;align-items:center;margin:0 24px 0 6px}
.pager .inp{width:50px;height:32px;border-radius:6px;border:1px solid var(--outline);margin:0 6px}
/* AppStatusView (app_status_view.dart:404-470) */
.sv{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;padding-bottom:40px}
.sv .c{width:86px;height:86px;border-radius:43px;display:grid;place-items:center;background:color-mix(in srgb,var(--schh) 25%,transparent);border:1px solid color-mix(in srgb,var(--primary) 6%,transparent);color:color-mix(in srgb,var(--primary) 60%,transparent)}
.sv .h{margin-top:20px;font-size:15px;font-weight:600}
.sv .p{margin-top:6px;max-width:320px;padding:0 28px;text-align:center;font-size:13px;line-height:1.5;color:color-mix(in srgb,var(--on) 60%,transparent)}
.sv .a{margin-top:16px;height:40px;padding:0 12px;display:flex;align-items:center;gap:8px;color:var(--primary);font-size:14px;font-weight:500}
.sv .a.fill{background:var(--primary);color:var(--onPrimary);border-radius:20px;padding:0 20px 0 16px}
.spin{width:24px;height:24px;border-radius:12px;border:3.5px solid var(--primary);border-right-color:color-mix(in srgb,var(--primary) 15%,transparent)}
/* composite of several phones */
.multi{display:flex;gap:28px;padding:56px 28px 28px;background:#E9EBF0}
.multi .cell{position:relative}
.multi .lab{position:absolute;left:0;right:0;top:-40px;text-align:center;font:600 20px 'Noto Sans SC';color:#191C20}
.menu .hd{padding:6px 16px 8px;font-size:12px;color:var(--onv)}
'''

mr = lambda n, s=24: f'<span class="mr" style="font-size:{s}px">{n}</span>'
mi = lambda n, s=24: f'<span class="mi" style="font-size:{s}px">{n}</span>'
rx = lambda c, s=24: f'<span class="rx" style="font-size:{s}px">&#x{c};</span>'
ci = lambda c, s=24: f'<span class="ci" style="font-size:{s}px">&#x{c};</span>'


def attrs(n=None, tag=None, at=None):
    return (f' data-n="{n}"' if n else '') + (f' data-tag="{tag}"' if n and tag else '') + (f' data-at="{at}"' if n and at else '')


def ib(inner, n=None, tag=None, at=None, cls='ib', style=''):
    return f'<div class="{cls}"{attrs(n, tag, at)}' + (f' style="{style}"' if style else '') + f'>{inner}</div>'


STATUS = ('<div class="status"><span>21:36</span><span class="r"><span class="mi">signal_cellular_alt</span>'
          '<span class="mi">wifi</span><span class="mi">battery_full</span></span></div>')
SBAR = '<div class="sbar"><span>21:36</span><span class="r"><span class="mi">wifi</span> <span class="mi">battery_full</span></span></div>'

# Sites.supportSites order (lib/core/sites.dart:217-266), zh names from assets/translations/zh.json
PLATFORMS = ['哔哩哔哩', '斗鱼', '虎牙', '抖音', '快手', '网易CC', 'Twitch', 'Soop', 'YY', 'AcFun 直播', 'Picarto', 'TwitCasting',
             '猫耳 FM', '映客', '克拉克拉', '小红书', 'niconico', '微博直播', 'SHOWROOM', 'CHZZK', 'LiveMe', 'TikTok LIVE']
CATS = ['网游', '手游', '单机游戏', '虚拟主播', '娱乐', '电台', '赛事', '聊天室', '生活', '知识', '帮我玩', '互动玩法']
AREAS = ['英雄联盟', '无畏契约', '穿越火线', 'CS2', '守望先锋', '魔兽世界', '永劫无间', 'DOTA2', '逆水寒', '剑网3', '梦幻西游', '坦克世界',
         '命运方舟', '最终幻想14', '冒险岛', '洛奇', '彩虹岛', '天涯明月刀', '使命召唤', '战争雷霆', '暗区突围', '三角洲行动', '流放之路', '星际战甲']
PICS = ['1', '111', '133', '158', '169', '183', '206', '219', '225', '237', '250', '274', '287', '292', '304', '319', '338', '342', '360', '367', '65']
FOLLOWED = {'英雄联盟', '永劫无间'}
PICARTO = ['公开直播（不含成人内容）', 'Art', 'Comics', 'Design', 'Gaming', 'Music', 'Photography', 'Education', 'Animation', '3D', 'Crafting', 'Writing', 'Tattoo', 'Fashion', 'Painting']


def tabs(names, sel=0, cls='tb', n=None, tag=None, style='', at=None):
    inner = ''.join(f'<div class="t{" on" if i == sel else ""}">{t}</div>' for i, t in enumerate(names))
    return f'<div class="{cls}"{attrs(n, tag, at)} style="{style}">{inner}</div>'


def area_card(i, name, sub=None, one=False, followed=False, extra='', n=None, tag=None, at=None, cls=''):
    pic = f'.cache/img/{PICS[i % len(PICS)]}.jpg'
    badge = f'<div class="fav">{rx("ee0a", 13)}</div>' if followed else ''
    cap = (f'<div class="cap one"><div class="n">{name}</div></div>' if one else
           f'<div class="cap"><div class="n">{name}</div><div class="{"s2" if sub and "·" in sub else "s"}">{sub}</div></div>')
    return f'<div class="ac {cls}"{attrs(n, tag, at)}><div class="pic" style="background-image:url({pic})">{badge}</div>{cap}{extra}</div>'


def grid(cols, cards, style=''):
    return f'<div class="grid" style="grid-template-columns:repeat({cols},minmax(0,1fr));{style}">{"".join(cards)}</div>'


def fab(bottom, n=None, tag=None):
    return f'<div class="fab"{attrs(n, tag, "tl")} style="bottom:{bottom}px">{rx("f4e6", 16)}关注分区</div>'


def nav(n=None, tag=None):
    items = [('ee0b', '关注', False), ('ed33', '热门', False), ('ea41', '分区', True), ('ec54', '录制中心', False)]
    inner = ''.join(f'<div class="d{" on" if on else ""}"><div class="ic">{rx(c)}</div>{t}</div>' for c, t, on in items)
    return f'<div class="nav"{attrs(n, tag)}>{inner}</div>'


def rail(n=None, tag=None):
    lead = (ib(mr('menu')) + ib(rx('ee90')) + ib(rx('eeb2')) + ib(ci('e804')) + ib(rx('ec54')))
    dest = ''.join(f'<div class="d{" on" if on else ""}"><div class="ic">{rx(c)}</div>{t}</div>'
                   for c, t, on in [('ee0b', '关注', False), ('ed33', '热门', False), ('ea41', '分区', True)])
    return f'<div class="rail"{attrs(n, tag, "tr")}>{lead}{dest}</div><div class="vdiv"></div>'


def pager(n=None, tag=None):
    return (f'<div class="pager"{attrs(n, tag)}><div class="ob">{mr("refresh", 16)}刷新</div>'
            f'<div class="tbn dis" style="margin-left:4px">{mr("arrow_back_ios_new", 12)}上一页</div><div style="width:8px"></div>'
            '<div class="pg on">1</div><div class="pg">2</div><div class="pg">3</div><div style="width:8px"></div>'
            f'<div class="tbn">下一页{mr("arrow_forward_ios", 12)}</div>'
            f'<span class="mut" style="margin-left:4px">每页: </span><div class="sel">20{mr("arrow_drop_down", 18)}</div>'
            '<span class="mut">跳转至</span><div class="inp"></div><span class="mut">页</span></div>')


def doc(w, h, scale, body, frame='win', crop=False):
    cls = 'ph' if frame == 'ph' else 'win'
    style = '' if frame == 'ph' else f' style="--w:{w}px;--h:{h}px"'
    return (f'<!doctype html><html><head><meta charset="utf-8"><meta name="mock-size" content="{w}x{h}@{scale}{" crop" if crop else ""}">'
            f'<link rel="stylesheet" href="kit/kit.css"><style>{CSS}</style></head>'
            f'<body><div class="{cls} col"{style}>{body}<div class="syn">示意图片</div></div></body></html>')


# ---------------------------------------------------------------- v3
def v3_cards(k, cat='网游'):
    return [area_card(i, AREAS[i], cat) for i in range(k)]


def v3_phone():
    appbar = ('<div class="ab"><div class="lead">' + mr('menu') + '</div>'
              '<div style="position:absolute;left:72px;width:253px;top:5px">' + tabs(PLATFORMS) + '</div>'
              '<div style="flex:1"></div>' + ib(rx('f3d0')) + '<div style="width:4px"></div></div>')
    body = (STATUS + appbar + tabs(CATS) +
            f'<div class="fill">{grid(3, v3_cards(12))}{fab(16)}</div>' + nav() + '<div class="gesture"></div>')
    return doc(393, 852, 3, body, 'ph')


def v3_land():
    appbar = '<div class="ab" style="padding-left:16px">' + tabs(PLATFORMS) + '</div>'
    body = (SBAR + '<div class="row" style="flex:1;min-height:0;align-items:stretch">' + rail() +
            '<div class="col" style="flex:1;min-width:0">' + appbar + tabs(CATS) +
            f'<div class="fill">{grid(5, v3_cards(10))}{fab(40)}</div></div></div>')
    return doc(852, 393, 2, body)


def v3_wide():
    appbar = '<div class="ab" style="padding-left:16px">' + tabs(PLATFORMS) + '</div>'
    body = ('<div class="row" style="flex:1;min-height:0;align-items:stretch">' + rail() +
            '<div class="col" style="flex:1;min-width:0">' + appbar +
            '<div class="row" style="justify-content:center">' + tabs(CATS) + '</div>' +
            f'<div class="fill">{grid(7, v3_cards(21))}</div>' + pager() + f'{fab(40)}</div></div>')
    return doc(1280, 800, 1.5, body)


def phone_appbar(names=None, sel=0, shift=0):
    t = tabs(names or PLATFORMS, sel=sel, style=f'margin-left:{-shift}px' if shift else '')
    return ('<div class="ab"><div class="lead">' + mr('menu') + '</div>'
            f'<div style="position:absolute;left:72px;width:253px;top:5px;overflow:hidden">{t}</div>'
            '<div style="flex:1"></div>' + ib(rx('f3d0')) + '<div style="width:4px"></div></div>')


def phone_shell(content, cat_row, appbar=None, fab_on=True):
    """A phone-sized areas page for the state composites."""
    return (f'<div class="ph col">{STATUS}{appbar or phone_appbar()}{cat_row}<div class="fill">{content}{fab(16) if fab_on else ""}</div>{nav()}'
            '<div class="gesture"></div></div>')


def status_view(icon, title, sub='', action=None):
    a = f'<div class="a">{mr("refresh", 18)}{action}</div>' if action else ''
    p = f'<div class="p">{sub}</div>' if sub else ''
    return f'<div class="sv"><div class="c">{icon}</div><div class="h">{title}</div>{p}{a}</div>'


def multi(cells, scale=1):
    w = len(cells) * 393 + (len(cells) - 1) * 28 + 56
    inner = ''.join(f'<div class="cell"><div class="lab">{lab}</div>{ph}</div>' for lab, ph in cells)
    return (f'<!doctype html><html><head><meta charset="utf-8"><meta name="mock-size" content="{w}x936@{scale}">'
            f'<link rel="stylesheet" href="kit/kit.css"><style>{CSS}</style></head>'
            f'<body style="background:#E9EBF0"><div class="multi">{inner}</div><div class="syn" style="position:fixed;left:auto;right:10px;transform:none">示意图片</div></body></html>')


ERR = '当前无网络连接，请检查网络设置'   # network_disconnected_msg
DOUYIN = [('王者荣耀', 'MOBA'), ('和平精英', '射击'), ('英雄联盟', 'MOBA'), ('原神', '角色扮演'), ('金铲铲之战', '策略'), ('穿越火线', '射击'),
          ('三角洲行动', '射击'), ('无畏契约', '射击'), ('我的世界', '休闲益智'), ('第五人格', '竞技'), ('蛋仔派对', '休闲益智'), ('永劫无间', '动作'),
          ('颜值', '娱乐'), ('聊天', '娱乐'), ('户外', '生活')]


def pic_appbar():
    return phone_appbar(['Twitch', 'Soop', 'YY', 'AcFun 直播', 'Picarto', 'TwitCasting'], sel=4, shift=292)


def dy_appbar():
    return phone_appbar(PLATFORMS, sel=3, shift=118)


def v3_states():
    loading = phone_shell('<div class="sv"><div class="spin"></div></div>', '')
    error = phone_shell(status_view(mr('wifi_off', 42), '网络请求失败', ERR, '重试'), '')
    empty = phone_shell(status_view(rx('ea42', 42), '未发现分区', '请点击上方按钮切换平台', '刷新'), '')
    return multi([('加载中', loading), ('出错', error), ('没有分区', empty)])


def v3_flat():
    one = phone_shell(grid(3, [area_card(i + 3, PICARTO[i], 'Picarto') for i in range(12)]),
                      '<div class="row" style="justify-content:center">' + tabs(['Picarto']) + '</div>', pic_appbar())
    dy = phone_shell(grid(3, [area_card(i + 5, a, t) for i, (a, t) in enumerate(DOUYIN[:12])]), '', dy_appbar())
    return multi([('只有一个分类（Picarto）', one), ('不分分类（抖音）', dy)])


# ---------------------------------------------------------------- new
def v4_cards(k, n=True, hover=None, press=None):
    out = []
    for i in range(k):
        name = AREAS[i]
        nn = 5 if (n and i == 0) else None
        cls = 'hov' if i == hover else ('press' if i == press else '')
        out.append(area_card(i, name, one=True, followed=name in FOLLOWED, n=nn, at='tl', cls=cls))
    return out


def v4_appbar(n=True):
    N = (lambda k: k) if n else (lambda k: None)
    return ('<div class="ab"><div class="lead"' + attrs(N(1), 'keep') + '>' + mr('menu') + '</div>'
            '<div style="position:absolute;left:72px;width:253px;top:5px;overflow:hidden">' + tabs(PLATFORMS, n=N(2), tag='keep') + '</div>'
            '<div style="flex:1"></div>' + ib(rx('f3d0'), N(3), 'keep') + '<div style="width:4px"></div></div>')


def menu_item(icon, text, n=None, tag=None, cls=''):
    return f'<div class="it {cls}"{attrs(n, tag)}><span style="flex:none;display:flex">{icon}</span><span style="flex:1">{text}</span></div>'


def v4_phone(menu=False):
    n = not menu
    body = (STATUS + v4_appbar(n) + tabs(CATS, cls='tb2', n=4 if n else None) +
            f'<div class="fill">{grid(3, v4_cards(15, n=n, press=4 if menu else None))}{fab(16, 6 if n else None, "keep")}</div>'
            + nav(7 if n else None, 'keep'))
    if menu:
        body += ('<div class="menu" style="left:150px;top:500px;min-width:210px">'
                 '<div class="hd">守望先锋 · 哔哩哔哩 · 网游</div>' + menu_item(rx('f4e6', 20), '关注分区', 8, 'add') + '</div>')
    return doc(393, 852, 3, body + '<div class="gesture"></div>', 'ph')


def v4_land():
    appbar = '<div class="ab" style="padding-left:16px">' + tabs(PLATFORMS) + '</div>'
    body = (SBAR + '<div class="row" style="flex:1;min-height:0;align-items:stretch">' + rail() +
            '<div class="col" style="flex:1;min-width:0">' + appbar + tabs(CATS, cls='tb2') +
            f'<div class="fill">{grid(5, v4_cards(15, n=False))}{fab(40)}</div></div></div>')
    return doc(852, 393, 2, body)


def v4_wide():
    appbar = '<div class="ab" style="padding-left:16px">' + tabs(PLATFORMS, n=2, tag='keep', at='tl') + '</div>'
    cards = v4_cards(21, n=False, hover=9, press=3)
    cards[0] = cards[0].replace('class="ac "', 'class="ac " data-n="5" data-at="tl"', 1)
    menu = ('<div class="menu" style="left:520px;top:300px;min-width:220px">'
            '<div class="hd">CS2 · 哔哩哔哩 · 网游</div>' + menu_item(rx('f4e6', 20), '关注分区', 8, 'add', 'hov') + '</div>')
    body = ('<div class="row" style="flex:1;min-height:0;align-items:stretch">' + rail() +
            '<div class="col" style="flex:1;min-width:0;position:relative">' + appbar + tabs(CATS, cls='tb2', n=4, at='tl') +
            f'<div class="fill">{grid(7, cards)}</div>' + pager(9, 'keep') + fab(84, 6, 'keep') + '</div></div>' + menu)
    return doc(1280, 800, 1.5, body)


def skel_tabs():
    bars = ''.join(f'<div style="width:{w}px;height:14px;border-radius:7px;background:var(--sch);margin:16px 14px 0;flex:none"></div>' for w in (30, 30, 58, 58, 30))
    return f'<div style="display:flex;height:46px;overflow:hidden;box-shadow:inset 0 -1px 0 var(--ov)">{bars}</div>'


def v4_states():
    sk = ''.join('<div class="skel"><div class="pic"></div><div class="b" style="width:60%"></div></div>' for _ in range(12))
    loading = phone_shell(f'<div class="grid" style="grid-template-columns:repeat(3,minmax(0,1fr))">{sk}</div>', skel_tabs())
    error = phone_shell(status_view(mr('wifi_off', 42), '网络请求失败', ERR, '重试'), '')
    empty = phone_shell(status_view(rx('ea42', 42), '未发现分区', '请点击上方按钮切换平台', '刷新'), '')
    return multi([('加载中', loading), ('出错', error), ('没有分区', empty)])


def v4_flat():
    line = '<div style="height:1px;background:var(--ov)"></div>'
    one = phone_shell(grid(3, [area_card(i + 3, PICARTO[i], one=True) for i in range(15)]), line, pic_appbar())
    dy = phone_shell(grid(3, [area_card(i + 5, a, t, followed=(a == '英雄联盟')) for i, (a, t) in enumerate(DOUYIN[:12])]), line, dy_appbar())
    return multi([('只有一个分类（Picarto）', one), ('不分分类（抖音）', dy)])


OUT = {
    'v3-phone': v3_phone(), 'v3-land': v3_land(), 'v3-wide': v3_wide(), 'v3-states': v3_states(), 'v3-flat': v3_flat(),
    'v4-phone': v4_phone(), 'v4-phone-menu': v4_phone(menu=True), 'v4-land': v4_land(), 'v4-wide': v4_wide(),
    'v4-states': v4_states(), 'v4-flat': v4_flat(),
}
for name, html in OUT.items():
    open(os.path.join(HERE, name + '.html'), 'w', encoding='utf-8').write(html)
print(len(OUT), 'pages')
