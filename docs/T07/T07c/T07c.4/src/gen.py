"""U.4f followed areas (关注分区) and platform display (平台显示, v3's HotAreasPage)
mockups: v3 restored and the new design.

v3: lib/modules/areas/favorite_areas_page.dart (AppBar "关注分区", platform
tabs with "全部" :97-104, waterfall 3/5/7/9 columns :16, :124-139, empty
:140), area card from areas/widgets/area_card.dart (see U.4d);
lib/modules/hot_areas/hot_areas_page.dart (tip :107-131, group title :20,
reorderable rows :25-99: logo 24, name t15 w600, switch, drag handle
RemixIcons.sort_asc only for shown platforms when more than one is shown),
hot_areas_controller.dart (hidden platforms sink to the bottom :53-65),
group title width common/widgets/widget_extensions.dart:12-36.

    python3 docs/ui/compare/U.4f/src/gen.py
    python3 tools/ui/mock/render.py docs/ui/compare/U.4f/src/ --annotate
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))

CSS = '''
.col{display:flex;flex-direction:column}
.fill{flex:1;min-height:0;position:relative;overflow:hidden}
.row{display:flex;align-items:center}
.ab{height:56px;flex:none;display:flex;align-items:center;background:var(--surface);position:relative}
.ab .lead{width:56px;height:56px;display:grid;place-items:center;flex:none}
.ab .ttl{position:absolute;left:72px;right:72px;top:0;height:56px;display:flex;align-items:center;justify-content:center;font-size:20px;font-weight:600}
.tb{display:flex;height:46px;flex:none;overflow:hidden;white-space:nowrap}
.tb .t{position:relative;flex:none;height:46px;line-height:46px;padding:0 16px;font-size:15px;color:color-mix(in srgb,var(--onv) 80%,transparent)}
.tb .t.on{color:var(--primary);font-weight:600}
.tb .t.on::after{content:'';position:absolute;left:16px;right:16px;bottom:0;height:2px;border-radius:2px 2px 0 0;background:var(--primary)}
.grid{position:absolute;left:0;right:0;top:0;padding:6px;display:grid;gap:6px;align-content:start}
.ac{background:var(--scl);border-radius:15px;overflow:hidden;display:flex;flex-direction:column;position:relative}
.ac .pic{aspect-ratio:1;border-radius:15px;background:#fff center/cover;position:relative}
.ac .cap{height:72px;padding:0 10px;display:flex;flex-direction:column;justify-content:center;gap:2px}
.ac .n{font-size:12px;line-height:16px;font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.ac .s{font-size:12px;line-height:16px;font-weight:500;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.ac.press{box-shadow:0 0 0 2px var(--primary)}
.menu .hd{padding:6px 16px 8px;font-size:12px;color:var(--onv)}
.sv{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;padding-bottom:40px}
.sv .c{width:86px;height:86px;border-radius:43px;display:grid;place-items:center;background:color-mix(in srgb,var(--schh) 25%,transparent);border:1px solid color-mix(in srgb,var(--primary) 6%,transparent);color:color-mix(in srgb,var(--primary) 60%,transparent)}
.sv .h{margin-top:20px;font-size:15px;font-weight:600}
.sv .p{margin-top:6px;max-width:320px;padding:0 28px;text-align:center;font-size:13px;line-height:1.5;color:color-mix(in srgb,var(--on) 60%,transparent)}
.sv .a{margin-top:16px;height:40px;padding:0 12px;display:flex;align-items:center;gap:8px;color:var(--primary);font-size:14px;font-weight:500}
/* platform display (hot_areas_page.dart) */
.lv{padding:12px 16px 32px}
.tipb{display:flex;gap:12px;padding:12px 16px;border-radius:16px;background:color-mix(in srgb,var(--primary) 5%,transparent)}
.tipb .ic{color:color-mix(in srgb,var(--primary) 80%,transparent);flex:none;padding-top:1px}
.tipb .x{font-size:13px;line-height:1.4;color:color-mix(in srgb,var(--onv) 80%,transparent)}
.gt{padding:0 0 8px 8px;font-size:12px;font-weight:700;letter-spacing:.5px;color:color-mix(in srgb,var(--primary) 65%,transparent)}
.box{border-radius:20px;background:color-mix(in srgb,var(--schh) 15%,transparent);border:.5px solid color-mix(in srgb,var(--on) 5%,transparent);overflow:hidden}
.pr{display:flex;align-items:center;height:64px;padding:0 4px 0 16px;gap:16px}
.pr .lg{width:24px;height:24px;border-radius:6px;background:center/contain no-repeat;flex:none}
.pr .nm{flex:1;font-size:15px;font-weight:600;white-space:nowrap}
.pr .h48{width:48px;height:48px;display:grid;place-items:center;flex:none;color:var(--onv)}
.pr .sw{margin-right:8px}
.pr.drag{background:var(--surface);box-shadow:0 6px 18px rgba(0,0,0,.18);border-radius:12px;position:relative;z-index:2}
'''

mr = lambda n, s=24: f'<span class="mr" style="font-size:{s}px">{n}</span>'
mi = lambda n, s=24: f'<span class="mi" style="font-size:{s}px">{n}</span>'
rx = lambda c, s=24: f'<span class="rx" style="font-size:{s}px">&#x{c};</span>'


def attrs(n=None, tag=None, at=None):
    return (f' data-n="{n}"' if n else '') + (f' data-tag="{tag}"' if n and tag else '') + (f' data-at="{at}"' if n and at else '')


STATUS = ('<div class="status"><span>21:36</span><span class="r"><span class="mi">signal_cellular_alt</span>'
          '<span class="mi">wifi</span><span class="mi">battery_full</span></span></div>')
PICS = ['1', '206', '219', '111', '360', '183', '274', '287', '342', '304', '158', '237']
# Sites.supportSites order (lib/core/sites.dart:217-266) with asset ids
SITES = [('bilibili', '哔哩哔哩'), ('douyu', '斗鱼'), ('huya', '虎牙'), ('douyin', '抖音'), ('kuaishou', '快手'), ('cc', '网易CC'),
         ('twitch', 'Twitch'), ('soop', 'Soop'), ('yy', 'YY'), ('acfun', 'AcFun 直播'), ('picarto', 'Picarto'), ('twitcasting', 'TwitCasting'),
         ('missevan', '猫耳 FM'), ('inke', '映客'), ('kilakila', '克拉克拉'), ('xiaohongshu', '小红书'), ('niconico', 'niconico'),
         ('weibo', '微博直播'), ('showroom', 'SHOWROOM'), ('chzzk', 'CHZZK'), ('liveme', 'LiveMe'), ('tiktok', 'TikTok LIVE'),
         ('youtube', 'YouTube Live'), ('bigo', 'Bigo Live'), ('pandalive', 'PandaTV'), ('fc2live', 'FC2 Live'),
         ('steambroadcast', 'Steam Broadcasts'), ('jdlive', '京东直播'), ('kugoulive', '酷狗直播'), ('baidulive', '百度直播'),
         ('sixroom', '六间房直播'), ('looklive', 'LOOK 直播'), ('17live', '17LIVE'), ('iptv', '网络')]
HIDDEN = {'xiaohongshu', 'liveme'}
SHOWN = [s for s in SITES if s[0] not in HIDDEN]
HID = [s for s in SITES if s[0] in HIDDEN]
LOGO = '../../../packages/live_ui/assets/platforms/{}.png'
# followed areas (sample): name, platform, parent category (typeName)
FAV = [('英雄联盟', '哔哩哔哩', '网游'), ('英雄联盟', '斗鱼', '网游竞技'), ('原神', '哔哩哔哩', '手游'), ('王者荣耀', '虎牙', '手游'),
       ('永劫无间', '哔哩哔哩', '网游'), ('和平精英', '抖音', '射击'), ('颜值', '斗鱼', '娱乐天地'), ('户外', '快手', '生活'),
       ('视频唱见', '哔哩哔哩', '电台'), ('星秀', '虎牙', '娱乐'), ('三角洲行动', '斗鱼', '网游竞技')]


def tabs(names, sel=0, n=None, tag=None, style=''):
    inner = ''.join(f'<div class="t{" on" if i == sel else ""}">{t}</div>' for i, t in enumerate(names))
    return f'<div class="tb"{attrs(n, tag)} style="{style}">{inner}</div>'


def appbar(title, n=None):
    return f'<div class="ab"><div class="lead"{attrs(n, "keep")}>{mi("arrow_back")}</div><div class="ttl">{title}</div></div>'


def card(i, name, sub, n=None, tag=None, cls=''):
    return (f'<div class="ac {cls}"{attrs(n, tag, "tl")}><div class="pic" style="background-image:url(.cache/img/{PICS[i % len(PICS)]}.jpg)"></div>'
            f'<div class="cap"><div class="n">{name}</div><div class="s">{sub}</div></div></div>')


def grid(cols, cards):
    return f'<div class="grid" style="grid-template-columns:repeat({cols},minmax(0,1fr))">{"".join(cards)}</div>'


def doc(w, h, scale, body, frame='win', crop=False):
    cls = 'ph' if frame == 'ph' else 'win'
    style = '' if frame == 'ph' else f' style="--w:{w}px;--h:{h}px"'
    if frame == 'ph' and crop:
        style = ' style="height:auto;min-height:852px"'
    syn = '' if frame == 'ph' else ' style="top:auto;bottom:12px;left:auto;right:12px;transform:none"'
    return (f'<!doctype html><html><head><meta charset="utf-8"><meta name="mock-size" content="{w}x{h}@{scale}{" crop" if crop else ""}">'
            f'<link rel="stylesheet" href="kit/kit.css"><style>{CSS}</style></head>'
            f'<body><div class="{cls} col"{style}>{body}<div class="syn"{syn}>示意图片</div></div></body></html>')


def status_view(icon, title, sub='', action=None, aicon='refresh'):
    a = f'<div class="a"{" data-n=\"5\" data-tag=\"add\"" if action else ""}>{rx(aicon, 18)}{action}</div>' if action else ''
    p = f'<div class="p">{sub}</div>' if sub is not None else ''
    return f'<div class="sv"><div class="c">{icon}</div><div class="h">{title}</div>{p}{a}</div>'


# ---------------------------------------------------------------- followed areas
V3_TABS = ['全部'] + [s[1] for s in SITES]
V4_TABS = ['全部', '哔哩哔哩', '斗鱼', '虎牙', '抖音', '快手']


def v3_fav(cols=3, w=393, h=852, scale=3, frame='ph'):
    cards = [card(i, a, t) for i, (a, p, t) in enumerate(FAV)]
    body = (STATUS if frame == 'ph' else '') + appbar('关注分区') + tabs(V3_TABS, style='justify-content:flex-start' if frame == 'ph' else '') + f'<div class="fill">{grid(cols, cards)}</div>'
    return doc(w, h, scale, body + ('<div class="gesture"></div>' if frame == 'ph' else ''), frame)


def v4_fav(cols=3, w=393, h=852, scale=3, frame='ph', menu=False, n=True):
    N = (lambda k: k) if n and not menu else (lambda k: None)
    cards = [card(i, a, f'{p} · {t}', N(3) if i == 0 else None, 'chg', 'press' if (menu and i == 3) else '') for i, (a, p, t) in enumerate(FAV)]
    body = ((STATUS if frame == 'ph' else '') + appbar('关注分区', N(1)) + tabs(V4_TABS, n=N(2)) + f'<div class="fill">{grid(cols, cards)}</div>')
    if menu:
        body += ('<div class="menu" style="left:140px;top:470px;min-width:220px"><div class="hd">王者荣耀 · 虎牙 · 手游</div>'
                 f'<div class="it" data-n="4" data-tag="add"><span style="flex:none;display:flex">{rx("ec3c", 20)}</span><span style="flex:1">取消关注</span></div></div>')
    return doc(w, h, scale, body + ('<div class="gesture"></div>' if frame == 'ph' else ''), frame)


def fav_empty(v4):
    if v4:
        sv = status_view(rx('ea42', 42), '未发现分区', '在分区页长按分区卡片，或打开分区后点右上角的“关注”', '去分区', 'ea42')
        t = ''
    else:
        sv = status_view(rx('ea42', 42), '未发现分区', '')
        t = tabs(V3_TABS)
    body = STATUS + appbar('关注分区') + t + f'<div class="fill">{sv}</div><div class="gesture"></div>'
    return doc(393, 852, 3, body, 'ph')


# ---------------------------------------------------------------- platform display
def prow(site, shown, v4, handle, n_sw=None, n_dr=None, drag=False):
    sid, name = site
    sw = f'<span class="sw{" on" if shown else ""}"{attrs(n_sw, "keep", "tl")}></span>'
    if v4:
        h = f'<div class="h48"{attrs(n_dr, None, "tr")}>{mr("drag_indicator", 22)}</div>' if handle else '<div style="width:48px;flex:none"></div>'
    else:
        h = f'<div class="h48">{rx("f15f", 20)}</div>' if handle else ''
    return (f'<div class="pr{" drag" if drag else ""}"><span class="lg" style="background-image:url({LOGO.format(sid)})"></span>'
            f'<span class="nm">{name}</span>{sw}{h}</div>')


V3_TIP = '长按右侧图标并上下拖动，即可自定义主页直播平台的展示顺序。<br>请至少保留一个可见直播平台。'
V4_TIP = '按住右侧把手上下拖动调整顺序；这里的顺序和开关用于热门、分区、关注和搜索的平台标签。<br>请至少保留一个可见直播平台。'


def platforms(v4, w=393, h=2600, scale=2, frame='ph', limit=None):
    tip = f'<div class="tipb"><span class="ic">{rx("ee59", 18)}</span><div class="x">{V4_TIP if v4 else V3_TIP}</div></div>'
    if v4:
        shown = ''.join(prow(s, True, True, True, 7 if i == 0 else None, 8 if i == 0 else None, drag=(i == 2 and frame == 'win'))
                        for i, s in enumerate(SHOWN[:limit] if limit else SHOWN))
        hidden = ''.join(prow(s, False, True, False) for s in HID)
        content = (tip + '<div style="height:16px"></div>' + f'<div class="gt">显示（{len(SHOWN)}）</div><div class="box">{shown}</div>'
                   + (f'<div class="row" style="justify-content:center;height:40px;color:var(--onv);font-size:13px">（下面还有 {len(SHOWN) - limit} 个，图里省略）</div>' if limit else '')
                   + '<div style="height:20px"></div>' + f'<div class="gt">隐藏（{len(HID)}）</div><div class="box">{hidden}</div>')
        if frame == 'win':
            content = f'<div style="max-width:720px;margin:0 auto">{content}</div>'
    else:
        rows = ''.join(prow(s, True, False, True) for s in (SHOWN[:limit] if limit else SHOWN)) + ('' if limit else ''.join(prow(s, False, False, False) for s in HID))
        title = '<div class="gt">平台显示</div>'
        if frame == 'win':
            title = f'<div style="max-width:960px;margin:0 auto">{title}</div>'
        content = tip + '<div style="height:16px"></div>' + title + f'<div class="box">{rows}</div>'
    body = (STATUS if frame == 'ph' else '') + appbar('平台显示', 6 if v4 else None) + f'<div class="lv">{content}</div>'
    return doc(w, h, scale, body, frame, crop=(frame == 'ph'))


OUT = {
    'v3-fav-phone': v3_fav(), 'v4-fav-phone': v4_fav(), 'v4-fav-menu': v4_fav(menu=True),
    'v3-fav-empty': fav_empty(False), 'v4-fav-empty': fav_empty(True),
    'v3-fav-wide': v3_fav(7, 1280, 800, 1.5, 'win'), 'v4-fav-wide': v4_fav(8, 1280, 800, 1.5, 'win', n=False),
    'v3-platforms': platforms(False), 'v4-platforms': platforms(True),
    'v3-platforms-wide': platforms(False, 1280, 800, 1.5, 'win', limit=9), 'v4-platforms-wide': platforms(True, 1280, 800, 1.5, 'win', limit=6),
}
for name, html in OUT.items():
    open(os.path.join(HERE, name + '.html'), 'w', encoding='utf-8').write(html)
print(len(OUT), 'pages')
