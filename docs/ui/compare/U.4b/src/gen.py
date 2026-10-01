"""U.4b popular page mockups. v3 restored from ~/ref/v3ref/lib (v3.2.11):
modules/popular/popular_page.dart (tabs in the title, :13-43),
popular_grid_view.dart (columns :16, empty :21-29, grid :31-85),
common/base/base_page_view.dart (notice, cellular banner, status, FABs),
base_page_view_extension.dart (desktop pagination bar, arrow keys),
common/base/desktop_components.dart (the bar).
Cards, shell and page builders come from ../../U.4a/src/cards.py.
    python3 docs/ui/compare/U.4b/src/gen.py && python3 tools/ui/mock/render.py docs/ui/compare/U.4b/src/ --annotate"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', 'U.4a', 'src'))
from cards import *  # noqa: E402,F401,F403
import cards  # noqa: E402

CSS2 = '''
.pkg{display:grid;gap:4px;padding:4px 12px 16px}
.pk{display:flex;flex-direction:column;align-items:center;gap:6px;padding:10px 2px 8px;border-radius:12px;font-size:12px;line-height:1.3;text-align:center;color:var(--on);position:relative}
.pk img{width:36px;height:36px;border-radius:9px}
.pk.on{background:var(--sc);color:var(--osc);font-weight:600}
.pk .ck{position:absolute;top:6px;right:calc(50% - 26px);width:16px;height:16px;border-radius:8px;background:var(--primary);color:var(--onPrimary);display:grid;place-items:center;box-shadow:0 0 0 2px var(--sc)}
.handle{width:32px;height:4px;border-radius:2px;background:var(--outline);opacity:.5;margin:12px auto 4px}
.pkh{display:flex;align-items:center;padding:0 4px 4px 20px}.pkh .t{flex:1;font-size:17px;font-weight:600}
.pkh .lk{display:flex;align-items:center;gap:4px;font-size:14px;color:var(--primary);padding:0 8px;height:48px}
.pkh .x{width:48px;height:48px;display:grid;place-items:center;color:var(--onv)}
.pks{padding:0 20px 8px;font-size:12px;color:var(--onv)}
.errmsg{font-family:'Geist','Noto Sans SC';word-break:break-all}
'''
CHZZK_V3 = '官方公开热门直播目录，使用包含边界项的游标分页；原生频道搜索同时返回开播和未开播频道。仅在 cvExposure 允许时展示 concurrentUserCount。'
CHZZK_V4 = '这里是 CHZZK 官方的热门直播；主播允许时才显示在线人数。'
ERR_V3 = ('DioException [bad response]: This exception was thrown because the response has a status code of 412 and '
          'RequestOptions.validateStatus was configured to throw for this status code.')


def css(html):
    return html.replace('</style>', CSS2 + '</style>', 1)


def picker(cols, cur=0, n=True, side=False):
    N = (lambda k: k) if n else (lambda k: None)
    cells = ''
    for i, (pid, name) in enumerate(zip(POPULAR_IDS, POPULAR_SITES)):
        on = i == cur
        ck = f'<span class="ck">{mr("check", 12)}</span>' if on else ''
        cells += f'<div class="pk{" on" if on else ""}"{at(N(12) if i == 1 else None, "add")}><img src="{LOGO(pid)}">{ck}<span>{name}</span></div>'
    head = (f'<div class="pkh"><span class="t">全部平台</span><span class="lk"{at(N(13), "add")}>{mr("tune", 18)}平台显示</span>'
            f'<span class="x"{at(N(14), "add")}>{mr("close", 22)}</span></div><div class="pks">34 个平台，点一个直接切过去；在“平台显示”里可以隐藏和排序</div>')
    body = f'<div class="pkg" style="grid-template-columns:repeat({cols},minmax(0,1fr))">{cells}</div>'
    if side:
        return f'<div class="side" style="width:360px;border-radius:16px 0 0 16px;padding-top:8px">{head}<div style="overflow:hidden">{body}</div></div>'
    return f'<div class="sheet" style="top:250px"><div class="handle"></div>{head}<div style="overflow:hidden">{body}</div></div>'


def v3_tab_slice(html, start, sel):
    """Show the tab strip scrolled so that tab `start` is first and `sel` is selected."""
    return html.replace(tabs(POPULAR_SITES, 0, 'start'), tabs(POPULAR_SITES[start:], sel - start, 'start'), 1)


def v4_tab_slice(html, start, sel, n=False):
    full = tabs(POPULAR_SITES, 0, 'start', extra_attr=(lambda i: at(2 if n else None, 'keep') if i == 0 else ''))
    return html.replace(full, tabs(POPULAR_SITES[start:], sel - start, 'start'), 1)


def v3_error():
    body = ('<div class="fill" style="display:grid;place-items:center">'
            + status3(mr('wifi_off', 42), '网络请求失败', f'<span class="errmsg">{ERR_V3}</span>', '重试') + '</div>')
    return css(popular3('phone').replace(popular3_body(2), body, 1))


def v4_error():
    body = ('<div class="fill" style="display:grid;place-items:center">'
            + status4(mr('wifi_off', 42), '网络请求失败', '平台拒绝了请求（风控），请稍后再试或登录账号', '重试') + '</div>')
    return css(popular4('phone').replace(popular4_body(2, nmap={'card': None}), body, 1))


TIP = '<div class="tipx" style="left:270px;top:262px;width:250px">【原神】深渊满星挑战，萌新也能看懂的配队思路</div>'
SCRIM = '<div class="scrim"></div>'

OUT = {
    'v3-phone': popular3('phone'),
    'v3-phone-notice': v3_tab_slice(popular3('phone', notice=CHZZK_V3, cellular=True), 17, 19),
    'v3-phone-loading': popular3('phone', state='loading'),
    'v3-phone-empty': popular3('phone', state='empty'),
    'v3-phone-error': v3_error(),
    'v3-phone-noplatform': popular3('phone', state='blank'),
    'v3-land': popular3('land'),
    'v3-wide': popular3('wide'),
    'v4-phone': popular4('phone', n=True),
    'v4-phone-picker': popular4('phone', panel=SCRIM + picker(4)),
    'v4-phone-notice': v4_tab_slice(popular4('phone', notice=CHZZK_V4, cellular=True, n=True), 17, 19, n=True),
    'v4-phone-loading': popular4('phone', state='loading'),
    'v4-phone-empty': popular4('phone', state='empty'),
    'v4-phone-error': v4_error(),
    'v4-phone-noplatform': popular4('phone', state='noplatform'),
    'v4-land': popular4('land'),
    'v4-wide': popular4('wide', n=True, hover=1, tip=TIP),
    'v4-wide-picker': popular4('wide', panel=SCRIM + picker(3, side=True, n=False)),
}
OUT = {k: css(v) if CSS2 not in v else v for k, v in OUT.items()}
write(HERE, OUT)
