"""U.4c favourites page mockups. v3 restored from ~/ref/v3ref/lib (v3.2.11):
modules/favorite/favorite_page.dart (status tabs in the title :22-37,
platform tabs :125-131, tag strip :182-273, empty states :275-319),
modules/favorite/room_grid_view.dart (columns :38-41, grid :65-98),
favorite_controller.dart (platforms with follows :67-76, sorting :456-473).
Cards, shell and helpers come from ../../U.4a/src/cards.py.
    python3 docs/ui/compare/U.4c/src/gen.py && python3 tools/ui/mock/render.py docs/ui/compare/U.4c/src/ --annotate"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', 'U.4a', 'src'))
from cards import *  # noqa: E402,F401,F403

CSS2 = '''
.tags3.slim{height:48px;padding:0 12px}
.hbar .mid.left{justify-content:flex-start;padding:0 8px 0 4px}
.sep{width:1px;height:24px;background:var(--ov);margin:0 8px;flex:none;align-self:center}
.tb.nat .t{padding:0 14px}
'''
LIVE = list('aijbmgnepk')          # sorted by audience (tag "全部")
OFF = list('cdfhloqstuvw')
ST_LABELS = ['已开播', '录播', '未开播']
ST_N = [10, 1, 36]
PLATS = ['全部', '哔哩哔哩', '斗鱼', '虎牙', '抖音']
PLATS_N = [10, 4, 2, 2, 2]
TAGS = ['全部', '常看', '睡前听', '唱歌']


def css(html):
    return html.replace('</style>', CSS2 + '</style>', 1)


def tagstrip3(slim=False, n=None):
    chips = ''.join(f'<div class="ch{" on" if i == 0 else ""}">{t}</div>' for i, t in enumerate(TAGS))
    return f'<div class="tags3{" slim" if slim else ""}"{at(n, "chg", "tl")}>{chips}</div>'


# ---------- v3 ----------
def v3_body(cols, state='live', pad=12):
    if state == 'empty':
        return ('<div class="fill" style="display:grid;place-items:center">'
                + status3(r('heart_3_fill', 42), '当前筛选暂无已开播直播', '关注数据仍在，共 36 个；可左右滑动切换平台或下拉刷新', '查看未开播') + '</div>')
    if state == 'nofollow':
        return ('<div class="fill" style="display:grid;place-items:center">'
                + status3(r('heart_3_fill', 42), '无已开播直播间', '在热门、分区或搜索里关注主播后，会显示在这里', '重试') + '</div>')
    if state == 'offline':
        items = [card3(x, 'offline', cap_h=72) for x in OFF]
    else:
        items = [card3(x, 'verify' if state == 'verify' else 'live', cap_h=72) for x in LIVE]
    return f'<div class="fill">{grid(items, cols, pad, 6)}</div>'


def v3(form, state='live'):
    sel = 2 if state in ('offline',) else 0
    st = tabs(ST_LABELS, sel, 'fillw')
    plats = PLATS if state != 'nofollow' else ['全部']
    prow = tabs(plats, 0, 'center')
    tagrow = tagstrip3() if state in ('live', 'verify') else ''
    if form == 'phone':
        body = STATUS + home_bar(st) + prow + tagrow + v3_body(2, state) + navbar('关注')
        return css(page(393, 852, 3, body))
    if form == 'land':
        main = f'<div class="col fill">{home_bar(st, phone=False)}{prow}{tagrow}{v3_body(3, state)}</div>'
        return css(page(852, 393, 2, STATUS_LAND + f'<div class="row fill" style="align-items:stretch">{rail("关注")}{main}</div>',
                        frame='fs', style='background:var(--surface)'))
    main = f'<div class="col fill">{home_bar(st, phone=False)}{prow}{tagrow}{v3_body(4, state)}{pager3(pages=(1,), more=False, has_next=False) if state == "live" else ""}</div>'
    return css(page(1280, 800, 1.5, f'<div class="row fill" style="align-items:stretch">{rail("关注")}{main}</div>', frame='win'))


# ---------- new ----------
def v4_body(cols, state='live', n=False, row_cols=1):
    N = (lambda k: k) if n else (lambda k: None)
    if state == 'empty':
        return ('<div class="fill" style="display:grid;place-items:center">'
                + status4(r('heart_3_fill', 42), '当前筛选暂无已开播直播', '关注的 36 个直播间现在都没有开播。可以左右滑动切换平台，或下拉刷新', '查看未开播', 'visibility') + '</div>')
    if state == 'nofollow':
        return ('<div class="fill" style="display:grid;place-items:center">'
                + status4(r('heart_3_fill', 42), '无关注直播', '在热门、分区或搜索里关注主播后，会显示在这里', '搜索直播', 'search', fill=True) + '</div>')
    if state == 'offline':
        items = [row4(x, n=(N(8) if i == 0 else None), status=None) for i, x in enumerate(OFF)]
        return f'<div class="fill">{grid(items, row_cols, 6, 6)}</div>'
    items = [card4(x, 'verify' if state == 'verify' else 'live', plat=True, nmap=({'card': N(6)} if i == 0 else None)) for i, x in enumerate(LIVE)]
    return f'<div class="fill">{grid(items, cols, 6, 6)}</div>'


def v4_status(sel, n, nat=False, state='live'):
    counts = {'empty': [0, 1, 36], 'nofollow': [0, 0, 0]}.get(state, ST_N)
    return tabs(ST_LABELS, sel, 'nat' if nat else 'fillw', counts=counts, extra_attr=(lambda i: at(n, 'chg') if i == 0 else ''))


def v4_plats(state, n, mode='center'):
    if state == 'nofollow':
        return tabs(['全部'], 0, mode, counts=[0])
    counts = {'offline': [36, 24, 4, 5, 3], 'empty': [0, 0, 0, 0, 0]}.get(state, PLATS_N)
    return tabs(PLATS, 0, "start" if mode == "center" else mode, counts=counts, extra_attr=(lambda i: at(n, 'chg') if i == 0 else ''))


def v4(form, state='live', n=False):
    N = (lambda k: k) if n else (lambda k: None)
    sel = 2 if state == 'offline' else 0
    tagrow = tagstrip3(True, N(5)) if state in ('live', 'verify') else ''
    if form == 'phone':
        bar = (f'<div class="hbar"><div class="lead"{at(N(1), "keep")}>{mr("menu")}</div><div class="mid">{v4_status(sel, N(2), state=state)}</div>'
               f'<div class="act"{at(N(3), "keep")}>{r("menu_search_line")}</div></div>')
        body = STATUS + bar + v4_plats(state, N(4)) + tagrow + v4_body(2, state, n) + navbar('关注')
        return css(page(393, 852, 3, body))
    # 840 and wider: the platform tabs join the status tabs in the top bar
    bar = (f'<div class="hbar"><div class="mid left">{v4_status(sel, N(2), nat=True, state=state)}<span class="sep"></span>'
           f'<div style="flex:1;min-width:0;overflow:hidden">{v4_plats(state, N(4), "start nat")}</div></div></div>')
    if form == 'land':
        main = f'<div class="col fill">{bar}{tagrow}{v4_body(4, state, n, 2)}</div>'
        return css(page(852, 393, 2, STATUS_LAND + f'<div class="row fill" style="align-items:stretch">{rail("关注")}{main}</div>',
                        frame='fs', style='background:var(--surface)'))
    pg = pager3(pages=(1,), more=False, has_next=False) if state == 'live' else ''
    if n and pg:
        pg = pg.replace('<div class="pager">', '<div class="pager" data-n="9" data-tag="keep" data-at="tl">', 1)
    main = f'<div class="col fill">{bar}{tagrow}{v4_body(5, state, n, 3)}{pg}</div>'
    return css(page(1280, 800, 1.5, f'<div class="row fill" style="align-items:stretch">{rail("关注")}{main}</div>', frame='win'))


TOAST = '<div class="toast" style="bottom:116px;white-space:normal;width:330px;text-align:center">2 个直播间暂时获取失败，已标为“状态待确认”</div>'

OUT = {
    'v3-phone': v3('phone'),
    'v3-phone-offline': v3('phone', 'offline'),
    'v3-phone-verifying': v3('phone', 'verify'),
    'v3-phone-empty': v3('phone', 'empty'),
    'v3-phone-nofollow': v3('phone', 'nofollow'),
    'v3-land': v3('land'),
    'v3-wide': v3('wide'),
    'v4-phone': v4('phone', n=True),
    'v4-phone-offline': v4('phone', 'offline', n=True),
    'v4-phone-verifying': v4('phone', 'verify'),
    'v4-phone-empty': v4('phone', 'empty'),
    'v4-phone-nofollow': v4('phone', 'nofollow'),
    'v4-land': v4('land'),
    'v4-wide': v4('wide', n=True),
    'v4-wide-offline': v4('wide', 'offline'),
}
# The refresh-failure toast (c11) on the new phone page.
OUT['v4-phone-refresh-failed'] = OUT['v4-phone'].replace('<div class="syn">', TOAST + '<div class="syn">', 1).replace(' data-n=', ' data-x=')
write(HERE, OUT)
