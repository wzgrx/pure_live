"""U.15c TV live browsing: popular, follows, areas, area rooms, followed areas,
watch history, search. pure_live_TV restored (v3-*) and the new design (v4-*).

pure_live_TV sources (~/ref/pure_live_TV/lib/modules/live):
  hot/hot_page.dart, favorite/favorite_page.dart, areas/areas_page.dart, areas/area_grid_view.dart,
  areas/area_display_config.dart, areas/area_rooms_page.dart, favorite_areas/favorite_areas_page.dart,
  history/history_page.dart, search/tv_search_page.dart, search/tv_search_result_page.dart,
  core/pagination/base_paged_tv_view.dart, core/widgets/empty_scene.dart, core/utils/favorite_operation_util.dart
Shared builders: ../../U.15a/src/tvkit.py.
    python3 docs/ui/compare/U.15c/src/gen.py && python3 tools/ui/mock/render.py docs/ui/compare/U.15c/src/ --annotate"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', 'U.15a', 'src'))
from tvkit import *  # noqa: E402,F401,F403

CSS = '''
.ct4{display:flex;gap:4px;height:40px;border-bottom:1px solid var(--ov);flex:none}
.ct4 .c{padding:0 14px;display:flex;align-items:center;font:400 16px 'Noto Sans SC';color:var(--onv);position:relative;border-radius:8px 8px 0 0}
.ct4 .c.on{color:var(--primary);font-weight:600}.ct4 .c.on::after{content:'';position:absolute;left:0;right:0;bottom:-1px;height:3px;border-radius:2px;background:var(--primary)}
.mn4{position:absolute;z-index:21;background:var(--sch);border-radius:12px;box-shadow:0 8px 24px rgba(0,0,0,.5);padding:6px;width:280px}
.mn4 .hd{font:400 14px 'Noto Sans SC';color:var(--onv);padding:8px 12px 6px}
.sf4{height:48px;border-radius:24px;background:var(--scc);display:flex;align-items:center;gap:10px;padding:0 18px;font:400 16px 'Noto Sans SC';color:var(--onv);flex:none}
.sf4 .v{color:var(--on)}
.seg4{display:flex;height:40px;border-radius:20px;background:var(--scc);padding:4px;gap:4px;flex:none}
.seg4 span{border-radius:16px;padding:0 16px;display:flex;align-items:center;font:400 16px 'Noto Sans SC';color:var(--onv)}
.seg4 .on{background:var(--pc);color:var(--opc);font-weight:600}
.chip4{height:36px;border-radius:18px;background:var(--scc);padding:0 16px;display:inline-flex;align-items:center;gap:6px;font:400 16px 'Noto Sans SC';flex:none}
.gl4{font:600 14px 'Noto Sans SC';color:var(--onv);margin:16px 0 10px}
.pk4{display:grid;grid-template-columns:repeat(3,1fr);gap:8px;padding:0 20px}
.pk4 .p{height:72px;border-radius:12px;background:var(--scc);display:flex;flex-direction:column;align-items:center;justify-content:center;gap:6px;font:400 14px 'Noto Sans SC';position:relative}
.pk4 .p img{width:24px;height:24px;border-radius:5px}
.pk4 .p.on{background:var(--pc);color:var(--opc);font-weight:600}
.side4{position:absolute;top:0;right:0;bottom:0;width:420px;z-index:21;background:var(--sch);box-shadow:-8px 0 24px rgba(0,0,0,.45);border-radius:16px 0 0 16px;padding:28px 28px 0 0}
.bar3{height:33px;display:flex;align-items:center;gap:8px;padding:0 8px}
'''

PLATS = [('哔哩哔哩', 'bilibili'), ('斗鱼', 'douyu'), ('虎牙', 'huya'), ('抖音', 'douyin'), ('快手', 'kuaishou'), ('网易CC', 'cc'), ('Twitch', 'twitch')]
CATS = ['网游', '手游', '单机游戏', '虚拟主播', '娱乐', '电台', '赛事', '聊天室', '生活', '知识']
AREAS = ['英雄联盟', '无畏契约', '穿越火线', 'CS2', '守望先锋', '魔兽世界', '永劫无间', 'DOTA2', '逆水寒', '剑网3', '梦幻西游', '坦克世界',
         '命运方舟', '最终幻想14', '冒险岛', '洛奇', '彩虹岛', '天涯明月刀']
PICS = ['1', '111', '133', '158', '169', '183', '206', '219', '225', '237', '250', '274', '287', '292', '304', '319', '338', '342']
FOLLOWED = {'英雄联盟', '永劫无间'}
FAV_AREAS = [('英雄联盟', 'bilibili', '网游', '1'), ('永劫无间', 'bilibili', '网游', '206'), ('王者荣耀', 'huya', '手游', '250'),
             ('主机游戏', 'douyu', '单机游戏', '158'), ('颜值', 'douyu', '娱乐', '338')]


def t3(inner):
    return page(f'<div class="t3">{inner}</div>', CSS, dark=False, bg='#121212')


def t4(inner, syn=True):
    return page(f'<div class="t4">{inner}</div>', CSS, syn=syn)


def N_(n, off):
    return (lambda k: k + off) if n else (lambda k: None)


def grid3(ids, focus=None, **kw):
    return f'<div class="grid3">{"".join(card3(k, focused=(k == focus), **kw) for k in ids)}</div>'


def grid4(ids, focus=None, plat=False, nn=None, **kw):
    return ('<div class="g4">' + ''.join(card4(k, focused=(k == focus), marquee=(k == focus), plat=plat, nn=(nn if i == 0 else None), **kw)
                                         for i, k in enumerate(ids)) + '</div>')


# ---------------- popular ----------------
def hot3():
    return t3(rail3('hot') + '<div class="pane">' + tabs3(PLATS, 0) + '<div style="height:8px"></div>' + grid3('abcdefghlo', focus='b') + '</div>')


def hot4(n=True, picker=False):
    N = N_(n and not picker, 0)
    tabs = tabs4([(a, b) for a, b in PLATS[:5]], 0, n=N(1), tag='keep')
    allp = f'<div class="pl4"{at(N(2), "add")}>{mr("apps", 20)}全部平台{mr("expand_more", 20)}</div>'
    body = (f'<div style="display:flex;align-items:center;gap:8px;height:40px"><div style="flex:1;min-width:0;overflow:hidden">{tabs}</div>{allp}</div>'
            f'<div style="height:16px"></div>{grid4("abcdefghlouq", focus=(None if picker else "b"), nn=N(3))}')
    side = ''
    if picker:
        P = N_(n, 3)
        tiles = ''
        for i, pid in enumerate(['bilibili', 'douyu', 'huya', 'douyin', 'kuaishou', 'cc', 'twitch', 'soop', 'yy', 'acfun', 'picarto', 'twitcasting', 'missevan', 'inke', 'kilakila']):
            nm = {'soop': 'Soop', 'yy': 'YY', 'acfun': 'AcFun 直播', 'picarto': 'Picarto', 'twitcasting': 'TwitCasting', 'missevan': '猫耳 FM', 'inke': '映客', 'kilakila': '克拉克拉'}.get(pid, SITE.get(pid, pid))
            cls = 'p' + (' on' if i == 0 else '') + (' f4 fmk fl' if i == 3 else '')
            tiles += f'<div class="{cls}"{at(P(3) if i == 3 else None, "add")}><img src="{LOGO(pid)}">{nm}</div>'
        side = ('<div class="scr4" style="background:rgba(0,0,0,.45)"></div><div class="side4">'
                f'<div style="display:flex;align-items:center;padding:0 0 4px 28px"><span class="ttl4" style="flex:1">全部平台</span>'
                f'<span class="b4 sm" style="background:transparent;color:var(--primary)"{at(P(1), "add")}>{mr("tune", 20)}平台显示</span>'
                f'<span class="b4 sm" style="width:40px;padding:0;margin-left:4px"{at(P(2), "add")}>{mr("close", 22)}</span></div>'
                '<div class="sub4" style="padding:0 0 14px 28px">34 个平台，按 OK 直接切过去；在“平台显示”里可以隐藏和排序</div>'
                f'<div class="pk4" style="padding-left:28px">{tiles}</div></div>')
    return t4(rail4('hot') + f'<div class="content">{body}</div>' + side)


# ---------------- follows ----------------
def fav3_page(offline=False):
    if not offline:
        return t3(rail3('favorite') + f'<div class="pane">{fav3(focus="i")}</div>')
    cards = ''.join(card3(k, focused=(k == 'e'), audience=False) for k in 'efghlouq')
    pane = (tabs3(FAV_STATUS3, 2) + '<div style="height:6px"></div>' + tabs3(FAV_PLATS3, 0) + '<div style="height:6px"></div>' + tagrow3()
            + f'<div style="height:8px"></div><div class="grid3">{cards}</div>')
    return t3(rail3('favorite') + f'<div class="pane">{pane}</div>')


def fav4_page(n=True):
    return t4(rail4('favorite') + f'<div class="content">{fav4(focus="i", n=n)}</div>')


OFF = [('e', '3 天前'), ('f', '昨天'), ('g', '5 天前'), ('h', '2 周前'), ('l', '今天 14:20'), ('o', '昨天'), ('u', '1 个月前'), ('q', '4 天前'),
       ('t', '3 天前'), ('w', '6 天前')]


def fav4_offline(n=True):
    N = N_(n, 0)
    status = tabs4([('已开播', None, 12), ('录播', None, 1), ('未开播', None, 23)], 2)
    plats = tabs4([('全部', 'all', 23), ('哔哩哔哩', 'bilibili', 14), ('斗鱼', 'douyu', 5), ('虎牙', 'huya', 4)], 0)
    rows = ''
    for i, (rid, when) in enumerate(OFF):
        _, p, title, nick, img, kind, fig = R[rid]
        rows += (f'<div class="cr4{" f4 ns fmk" if i == 0 else ""}"{at(N(15) if i == 0 else None, "chg", "tl")}>'
                 f'<span class="a" style="background-image:url({avatar(rid)})"></span><div class="t"><div class="x">{nick}</div>'
                 f'<div class="y"><img src="{LOGO(p)}" style="width:14px;height:14px;border-radius:3px;vertical-align:-2px;margin-right:4px">{title}</div></div></div>')
    body = (f'<div style="display:flex;align-items:center;gap:8px;height:40px">{status}<span class="vsep"></span>{plats}</div>'
            f'<div style="height:12px"></div>{tagrow4()}'
            f'<div style="display:grid;grid-template-columns:1fr 1fr;gap:12px 16px;margin-top:16px">{rows}</div>')
    return t4(rail4('favorite') + f'<div class="content">{body}</div>')


# ---------------- areas ----------------
def areas3(confirm=False):
    cells = ''.join(area3(a, PICS[i], focused=(i == 0 and not confirm), h=93) for i, a in enumerate(AREAS))
    pane = (tabs3(PLATS, 0) + '<div style="height:8px"></div>' + tabs3([(c, None) for c in CATS], 0)
            + f'<div style="height:10px"></div><div class="grid3" style="grid-template-columns:repeat(6,1fr)">{cells}</div>')
    dlg = ''
    if confirm:
        dlg = dialog3('关注提示', '<div class="m">确定要关注“英雄联盟”分区吗？</div>', btn3('取消', kind='sec') + btn3('确定关注', kind='f fmk'))
    return t3(rail3('areas') + f'<div class="pane">{pane}</div>' + dlg)


def areas4(n=True, menu=False):
    N = N_(n, 20)
    tabs = tabs4([(a, b) for a, b in PLATS[:6]], 0, n=N(1))
    cats = ''.join(f'<span class="c{" on" if i == 0 else ""}"{at(N(2) if i == 0 else None, "chg", "tl")}>{c}</span>' for i, c in enumerate(CATS))
    cells = ''.join(area4(a, PICS[i], focused=(i == 0 and not menu), followed=(a in FOLLOWED), nn=(N(3) if i == 1 else None)) for i, a in enumerate(AREAS))
    body = (f'{tabs}<div style="height:12px"></div><div class="ct4">{cats}</div>'
            f'<div class="ga4" style="margin-top:16px">{cells}</div>')
    mn = ''
    if menu:
        mn = ('<div class="scr4" style="background:rgba(0,0,0,.35)"></div>'
              '<div class="mn4" style="left:262px;top:150px"><div class="hd">英雄联盟 · 哔哩哔哩 · 网游</div>'
              f'<div class="o4 f4 ns fmk fr"{at(N(4), "add", "l")}>{r("heart_add_2_line", 22)}<span class="x">关注分区</span></div></div>')
    return t4(rail4('areas') + f'<div class="content">{body}</div>' + mn)


# ---------------- area rooms ----------------
def arearooms3():
    bar = f'<div class="bar3">{btn3("返回", mr("arrow_back_ios_new", 12), kind="f fmk fr")}<span style="font:700 12px Noto Sans SC">英雄联盟</span></div>'
    return t3(f'{bar}<div class="grid3" style="padding:0 8px">{"".join(card3(k) for k in "ibjmcdkn")}</div>')


def arearooms4(n=True):
    N = N_(n, 30)
    head = (f'<div style="display:flex;align-items:center;height:56px"><div style="flex:1"><div class="ttl4">英雄联盟</div><div class="sub4">哔哩哔哩 · 网游</div></div>'
            f'<span class="b4" style="background:var(--primary);color:var(--onPrimary)"{at(N(1), "chg")}>{r("add_line", 20)}关注</span></div>')
    grid = grid4('ibjmcdknao', focus='i', nn=N(2))
    return t4(f'<div class="ab" style="left:48px;right:48px;top:28px">{head}<div style="height:16px"></div>{grid}</div>')


# ---------------- followed areas ----------------
def favareas3():
    cells = ''.join(area3(a, img, focused=(i == 0), h=93) for i, (a, p, c, img) in enumerate(FAV_AREAS))
    pane = (tabs3([('全部', 'all')] + PLATS[:5], 0) + f'<div style="height:8px"></div><div class="grid3" style="grid-template-columns:repeat(6,1fr)">{cells}</div>')
    return t3(rail3('favareas') + f'<div class="pane">{pane}</div>')


def favareas4(n=True):
    N = N_(n, 40)
    tabs = tabs4([('全部', 'all', 5), ('哔哩哔哩', 'bilibili', 2), ('斗鱼', 'douyu', 2), ('虎牙', 'huya', 1)], 0, n=N(1))
    cells = ''.join(area4(a, img, focused=(i == 0), sub=f'<img src="{LOGO(p)}" style="width:16px;height:16px;border-radius:4px;vertical-align:-3px;margin-right:6px">{c}', nn=(N(2) if i == 1 else None)) for i, (a, p, c, img) in enumerate(FAV_AREAS))
    return t4(rail4('favareas') + f'<div class="content">{tabs}<div class="ga4" style="margin-top:16px">{cells}</div></div>')


# ---------------- watch history ----------------
def history3():
    tool = ('<div style="display:flex;gap:6px;padding:4px 0 0 4px">' + btn3('清空历史', mo('delete_sweep', 10), kind='sec')
            + btn3('观看记录保留数量: 50', mr('history_toggle_off', 10), kind='sec') + '</div>')
    pane = tool + '<div style="height:6px"></div>' + tabs3([('全部', 'all')] + PLATS[:5], 0) + '<div style="height:8px"></div>' + grid3('aibjkdmn', focus='a')
    return t3(rail3('history') + f'<div class="pane" style="top:4px">{pane}</div>')


def history4(n=True):
    N = N_(n, 50)
    head = (f'<div style="display:flex;align-items:center;gap:12px;height:40px"><span class="ttl4">观看记录</span><span class="sub4 tnum" style="flex:1">18 / 50 条</span>'
            f'{btn4("刷新", mr("refresh", 20), nn=N(1), tag="add")}{btn4("保留数量 50", mr("history_toggle_off", 20), nn=N(2))}{btn4("清空", r("delete_bin_line", 20), kind="err", nn=N(3))}</div>')
    tabs = tabs4([('全部', 'all', 18), ('哔哩哔哩', 'bilibili', 9), ('斗鱼', 'douyu', 5), ('虎牙', 'huya', 3), ('抖音', 'douyin', 1)], 0, n=N(4))
    g1 = grid4('aibj', focus='a', plat=True, nn=N(5))
    g2 = grid4('kdmn', plat=True)
    body = f'{head}<div style="height:12px"></div>{tabs}<div class="gl4">今天</div>{g1}<div class="gl4">昨天</div>{g2}'
    return t4(rail4('history') + f'<div class="content">{body}</div>')


# ---------------- search ----------------
def search3():
    qr_card = (f'<div style="width:120px;display:flex;flex-direction:column;align-items:center"><div style="background:#1F1F1F;border-radius:11px;padding:4px;box-shadow:0 2px 6px rgba(0,0,0,.3)">'
               f'{qr(104)}</div><div style="font:600 9px Noto Sans SC;margin-top:5px;white-space:nowrap">http://192.168.1.5:23234/#/search</div></div>')
    seg = ('<div style="padding:2.5px;border-radius:14px;background:rgba(31,31,31,.65);border:1px solid rgba(0,161,255,.4);display:flex;gap:3px">'
           + btn3('主播', mr('person', 11), size='s', kind='on') + btn3('直播间', mr('live_tv', 11), size='s') + '</div>')
    field = ('<div class="fmk" style="width:390px;height:40px;border-radius:19px;background:#1F1F1F;border:1px solid #00A1FF;display:flex;align-items:center;padding:0 14px;'
             'font:400 12px Noto Sans SC;color:rgba(255,255,255,.6)"><span style="flex:1">输入主播/直播间名称搜索</span>' + mr('search', 14) + '</div>')
    chips = ''.join(f'<span style="height:22px;border-radius:11px;border:.75px solid #00A1FF;background:#1F1F1F;padding:0 11px;display:inline-flex;align-items:center;gap:4px;font:400 10px Noto Sans SC">{t}</span>'
                    for t in ['晚风', '英雄联盟', '21452505', '古筝'])
    chips += f'<span style="height:22px;border-radius:11px;border:.75px solid #00A1FF;background:#1F1F1F;padding:0 11px;display:inline-flex;align-items:center;gap:4px;font:400 10px Noto Sans SC"><span style="color:#00A1FF">{mr("delete_outline", 12)}</span>清空</span>'
    hist = (f'<div style="width:380px"><div style="font:400 10px Noto Sans SC;color:#00A1FF;padding:0 0 5px 4px">搜索历史（长按删除）</div>'
            f'<div style="display:flex;gap:5px;padding-left:4px">{chips}</div></div>')
    col = (f'<div style="display:flex;flex-direction:column;align-items:center">{qr_card}<div style="height:12px"></div>{seg}<div style="height:10px"></div>'
           f'<div style="width:100%">{tabs3(PLATS[:5], 0, style="justify-content:center;margin-top:0")}</div><div style="height:18px"></div>{field}<div style="height:12px"></div>{hist}</div>')
    return t3(rail3('search') + f'<div class="pane" style="display:flex;align-items:center;justify-content:center">{col}</div>')


def search_head4(N, keyword=None):
    sf = (f'<div class="sf4{" f4 ns fmk" if keyword is None else ""}" style="width:420px"{at(N(1), "chg", "tl")}>{SEARCH_CI(22)}'
          + (f'<span class="v" style="flex:1">{keyword}</span>{mr("close", 20)}' if keyword else '<span style="flex:1">搜索直播间、主播或房间号</span>')
          + '</div>')
    seg = f'<div class="seg4"{at(N(2), "chg")}><span class="on">直播间</span><span>主播</span></div>'
    tabs = tabs4([('全部', 'all')] + [(a, b) for a, b in PLATS[:4]], 0, n=N(3), tag='chg')
    inc = f'<div class="pl4" style="gap:10px"{at(N(4), "add")}>包含未开播<span class="sw4 on" style="transform:scale(.8)"></span></div>'
    sort = f'<div class="pl4"{at(N(5), "add")}>综合{mr("expand_more", 20)}</div>'
    tip = (f'<div class="sub4" style="margin-top:10px;display:flex;align-items:center;gap:6px"{at(N(6), "add", "l")}>{mr("info_outline", 18)}'
           '同时搜索 34 个平台，各平台能搜到的范围不同，按 OK 查看。</div>')
    return (f'<div style="display:flex;gap:12px;align-items:center">{sf}{seg}</div>'
            f'<div style="display:flex;align-items:center;gap:8px;margin-top:12px"><div style="flex:1;min-width:0;overflow:hidden">{tabs}</div>{inc}{sort}</div>{tip}')


def search4(n=True):
    N = N_(n, 60)
    chips = ''.join(f'<span class="chip4"{at(N(7) if i == 0 else None, "keep")}>{t}</span>' for i, t in enumerate(['晚风', '英雄联盟', '21452505', '古筝']))
    chips += f'<span class="chip4" style="color:var(--error)"{at(N(8), "chg")}>{r("delete_bin_line", 18)}清空</span>'
    left = (f'<div style="flex:1"><div class="gl4" style="margin-top:0">最近搜索 · 长按 OK 删除一条</div><div style="display:flex;flex-wrap:wrap;gap:10px">{chips}</div></div>')
    right = (f'<div style="width:300px;border-radius:16px;background:var(--scl);padding:16px;display:flex;gap:14px;align-items:center">'
             f'<div style="background:#fff;border-radius:8px;padding:5px;flex:none">{qr(96)}</div>'
             '<div><div style="font:600 16px Noto Sans SC">用手机输入</div><div class="sub4" style="margin-top:6px;line-height:1.5">手机和电视连同一个网络，扫码打开遥控页，在手机上打字，内容会出现在搜索框里</div></div></div>')
    body = search_head4(N) + f'<div style="display:flex;gap:24px;margin-top:24px">{left}{right}</div>'
    return t4(rail4('search') + f'<div class="content">{body}</div>')


def search4_results(n=True):
    N = N_(n, 70)
    body = (search_head4(N_(False, 0), keyword='晚风')
            + '<div class="sub4" style="margin:12px 0 0;display:flex;align-items:center;gap:8px"><span style="width:14px;height:14px;border-radius:7px;border:2px solid var(--primary);border-right-color:transparent"></span>还有 2 个平台在搜索…</div>'
            + f'<div style="height:20px"></div>{grid4("adcgbk", focus="a", plat=True, nn=N(1))}')
    return t4(rail4('search') + f'<div class="content">{body}</div>')


def search3_results():
    bar = f'<div class="bar3">{btn3("返回", mr("arrow_back_ios_new", 12), kind="f fmk fr")}<span style="font:700 12px Noto Sans SC">搜索: 晚风 (哔哩哔哩)</span></div>'
    cards = ''
    for rid, nick in [('a', '晚风'), ('g', '晚风电台'), ('l', '晚风吹过'), ('t', '晚风小狗')]:
        _, p, title, nk, img, kind, fig = R[rid]
        av = avatar(rid)
        cards += (f'<div class="c3"><div class="cv" style="background-image:url({av})">{chip3(p.upper(), pos="left:6px;top:6px")}{chip3(fig, "whatshot", pos="right:6px;bottom:6px")}</div>'
                  f'<div class="inf"><div class="a" style="background-image:url({av})"></div><div class="t"><div class="x">{nick}</div><div class="y">{nick}</div></div></div></div>')
    return t3(f'{bar}<div class="grid3" style="padding:0 8px">{cards}</div>')


# ---------------- empty states (two halves) ----------------
def halves(cells, v4):
    q = ''
    border = 'var(--ov)' if v4 else '#2A2A2A'
    for i, (title, inner) in enumerate(cells):
        q += (f'<div class="ab" style="left:{i * 480}px;top:0;width:480px;height:540px;overflow:hidden;border-right:1px solid {border}">'
              f'<div class="ab" style="left:16px;top:12px;font:600 {14 if v4 else 11}px Noto Sans SC;color:#9AA0A6;z-index:3">{title}</div>'
              f'<div class="ab" style="inset:0;display:flex;align-items:center;justify-content:center;padding:0 24px">{inner}</div></div>')
    return q


def empty3_a():
    a = status3('e', '无已开播直播间', '请先关注其他直播间', r('heart_3_fill', 32),
                btn3('重试', mr('refresh', 11), size='s', kind='f fmk fb') + btn3('去搜索', mr('search', 11), size='s', kind='sec'))
    b = status3('e', '暂无收藏夹', '收藏分类后可整组查看直播', r('apps_2_line', 32), btn3('重试', mr('refresh', 11), size='s', kind='f fmk fb'))
    return page('<div class="t3">' + halves([('关注：一个都没关注', a), ('关注分区：一个都没关注', b)], False) + '</div>', CSS, dark=False, bg='#121212', syn=False)


def empty4_a(n=True):
    N = N_(n, 80)
    a = status4(r('heart_3_fill', 44), '无关注直播', '在热门、分区或搜索里关注主播后，会显示在这里',
                btn4('搜索直播', SEARCH_CI(20), focused=True, nn=N(1), tag='chg'))
    b = status4(r('apps_2_line', 44), '未发现分区', '在分区页长按 OK（或按菜单键）关注分区，<br>或打开分区后按顶上的“关注”',
                btn4('去分区', r('shapes_line', 20), focused=True, nn=N(2), tag='add'))
    return page('<div class="t4">' + halves([('关注：一个都没关注', a), ('关注分区：一个都没关注', b)], True) + '</div>', CSS, syn=False)


def empty3_b():
    b = status3('e', '暂无观看记录', '观看记录将自动保存', mr('history', 32), btn3('浏览热门', mr('refresh', 11), size='s', kind='f fmk fb'))
    return page('<div class="t3">' + halves([('热门：“平台显示”里平台全关了（整页空白）', ''), ('观看记录：没有记录', b)], False) + '</div>', CSS, dark=False, bg='#121212', syn=False)


def empty4_b(n=True):
    N = N_(n, 80)
    a = status4(mr('tune', 44), '没有要显示的平台', '在“平台显示”里选择要在热门页显示的平台',
                btn4('平台显示', mr('tune', 20), focused=True, nn=N(3), tag='add'))
    b = status4(r('history_line', 44), '暂无观看记录', '看过的直播间会自动出现在这里',
                btn4('浏览热门', r('fire_line', 20), focused=True, nn=N(4), tag='keep'))
    return page('<div class="t4">' + halves([('热门：“平台显示”里平台全关了', a), ('观看记录：没有记录', b)], True) + '</div>', CSS, syn=False)


OUT = {
    'v3-hot': hot3(), 'v4-hot': hot4(), 'v4-hot-picker': hot4(picker=True),
    'v3-fav': fav3_page(), 'v4-fav': fav4_page(), 'v3-fav-offline': fav3_page(True), 'v4-fav-offline': fav4_offline(),
    'v3-areas': areas3(), 'v4-areas': areas4(), 'v3-areas-follow': areas3(True), 'v4-areas-menu': areas4(menu=True),
    'v3-arearooms': arearooms3(), 'v4-arearooms': arearooms4(),
    'v3-favareas': favareas3(), 'v4-favareas': favareas4(),
    'v3-history': history3(), 'v4-history': history4(),
    'v3-search': search3(), 'v4-search': search4(), 'v3-search-results': search3_results(), 'v4-search-results': search4_results(),
    'v3-empty': empty3_a(), 'v4-empty': empty4_a(), 'v3-empty-b': empty3_b(), 'v4-empty-b': empty4_b(),
}
write(OUT, HERE)
