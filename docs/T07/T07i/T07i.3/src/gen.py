"""U.12a toolbox (链接解析) mockups: v3 restored and the new design.

v3 (tag v3.2.11): lib/modules/toolbox/toolbox_page.dart (cards :51-126,
support list :128-149), toolbox_controller.dart (choice dialogs :161-240,
clipboard auto-fill :242-299), toolbox_direct_link_flow.dart (toasts).
Stream URLs are placeholders.
    python3 docs/ui/compare/U.12a/src/gen.py && python3 tools/ui/mock/render.py docs/ui/compare/U.12a/src/ --annotate"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from skit import *  # noqa: E402,F401,F403
from skit import composite as _composite  # noqa: E402

CSS2 = '''
.tc{background:#fff;border-radius:12px;box-shadow:0 0 10px rgba(0,0,0,.05);margin-bottom:16px}
.et{display:flex;align-items:center;gap:16px;min-height:56px;padding:0 16px 0 16px}
.et .x{flex:1;font-size:12px;font-weight:700}
.et .rx,.et .mi{color:var(--primary);font-size:24px}
.ta{margin:0 16px;min-height:96px;border-radius:8px;background:rgba(195,199,207,.18);padding:12px 44px 12px 12px;font-size:13px;color:var(--onv);position:relative;line-height:1.45;word-break:break-all}
.ta.v{color:var(--on)}
.ta .cl{position:absolute;right:4px;top:50%;transform:translateY(-50%);width:40px;height:40px;display:grid;place-items:center;color:var(--onv)}
.fbw{margin:12px 16px 0;height:44px;border-radius:8px;background:var(--primary);color:var(--onPrimary);display:flex;align-items:center;justify-content:center;gap:8px;font-size:13px;font-weight:600}
.fbw.dis{background:rgba(25,28,32,.12);color:rgba(25,28,32,.38)}
.fbw .rx{font-size:18px}
.sup{padding:0 16px 16px}
.sup .hr{height:1px;background:var(--ov);margin-bottom:16px}
.sup .h{display:flex;align-items:center;gap:6px;color:#9E9E9E;font-weight:700;font-size:14px}
.sup pre{font-family:inherit;white-space:pre-wrap;color:#9E9E9E;line-height:1.6;font-size:14px;margin-top:12px}
.gsnack{position:absolute;left:15px;right:15px;bottom:28px;z-index:30;border-radius:15px;background:rgba(48,48,48,.92);color:#fff;padding:14px 18px;box-shadow:0 4px 12px rgba(0,0,0,.2)}
.gsnack b{display:block;font-size:15px;margin-bottom:4px}
.gsnack span{font-size:13px}
.chd{position:absolute;z-index:21;left:16px;right:16px;background:var(--sch);border-radius:28px;padding:20px 24px 8px}
.chd h3{font-size:24px;font-weight:400}
.chd .li3{min-height:48px;display:flex;flex-direction:column;align-items:center;justify-content:center;font-size:15px;padding:6px 16px}
.chd .li3 small{font-size:13px;color:var(--onv);max-width:100%;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;align-self:stretch;text-align:left}
.chd .ft{display:flex;justify-content:flex-end;padding-top:8px}
/* new */
.lnk{padding:16px}
.lnk .t{font-size:15px;font-weight:600}.lnk .s{font-size:12px;color:var(--onv);margin-top:4px;line-height:1.5}
.ta4{margin-top:12px;min-height:96px;border-radius:12px;background:color-mix(in srgb,var(--schh) 60%,transparent);padding:12px 48px 12px 14px;font-size:14px;color:var(--onv);position:relative;line-height:1.5;word-break:break-all}
.ta4.v{color:var(--on)}
.ta4 .cl{position:absolute;right:4px;top:50%;transform:translateY(-50%);width:44px;height:44px;display:grid;place-items:center;color:var(--onv)}
.b2r{display:flex;gap:8px;margin-top:12px}.b2r>span{flex:1;height:48px;border-radius:12px}
.b2r .fb,.b2r .tonal{display:flex;align-items:center;justify-content:center}
.b2r .dis{opacity:.38}
.busy{display:flex;align-items:center;gap:8px;margin-top:8px;font-size:12px;color:var(--onv)}
.busy .x{flex:1}
.chips4{display:flex;flex-wrap:wrap;gap:8px;padding:4px 16px 16px}
.chip4{height:32px;border-radius:8px;box-shadow:inset 0 0 0 1px var(--ov);display:flex;align-items:center;gap:6px;padding:0 10px 0 6px;font-size:13px;white-space:nowrap;background:var(--surface)}
.chip4 i{width:18px;height:18px;border-radius:9px;display:grid;place-items:center;color:#fff;font:700 10px 'Geist';font-style:normal}
'''


def composite(phones, **kw):
    return _composite(phones, css=CSS2, **kw)


def p(html):
    return page('393x852@3', html, css=CSS2)


LINK = 'https://live.bilibili.com/12345'
SHARE = '【晚风电台｜深夜点歌】晚风的直播间，快来看！https://b23.tv/AbCdEf'
SUPPORT = ('支持以下类型的链接解析：\n\n哔哩哔哩：\nhttps://live.bilibili.com/xxxxx\nhttps://www.bilibili.com/xxxxx\nhttps://b23.tv/xxxxx\n\n虎牙直播：\nhttps://www.huya.com/xxxxx\n\n'
           '斗鱼直播：\nhttps://www.douyu.com/xxxxx\n\n抖音直播/视频：\nhttps://live.douyin.com/xxxxx\nhttps://www.douyin.com/xxxxx\nhttps://v.douyin.com/xxxxx\n'
           'https://webcast.amemv.com/douyin/webcast/reflow/xxxxx\n\n快手直播：\nhttps://live.kuaishou.com/u/xxxxx\nhttps://live.kuaishou.cn/u/xxxxx\n\n网易CC直播：\nhttps://cc.163.com/xxxxx\n\n'
           'Twitch直播：\nhttps://www.twitch.tv/xxxxx\nhttps://twitch.tv/xxxxx\n\nSOOP直播：\nhttps://www.sooplive.com/xxxxx\nhttps://sooplive.com/xxxxx\nhttps://play.sooplive.com/xxxxx\n'
           'https://www.sooplive.co.kr/xxxxx\nhttps://sooplive.co.kr/xxxxx\nhttps://play.sooplive.co.kr/xxxxx\n\nYY直播：\nhttps://www.yy.com/xxxxx\nhttps://yy.com/xxxxx\n\n'
           'AcFun直播:\nhttps://live.acfun.cn/live/123456\n\nPicarto:\nhttps://picarto.tv/ChannelName\n\nTwitCasting:\nhttps://twitcasting.tv/ChannelName\nhttps://twitcasting.tv/c:ChannelName\n\n'
           'CHZZK:\nhttps://chzzk.naver.com/live/0123456789abcdef0123456789abcdef\n\nKick:\nhttps://kick.com/ChannelName\n\n17LIVE:\nhttps://17.live/en/live/1234567')
SITES = [('哔哩哔哩', '#FB7299'), ('斗鱼', '#FF7700'), ('虎牙', '#FFA200'), ('抖音', '#161823'), ('快手', '#FF4906'), ('网易CC', '#2E66F6'),
         ('AcFun 直播', '#FD4C5C'), ('YY', '#FFC300'), ('花椒', '#FF5B8C'), ('映客', '#26C6DA'), ('百度直播', '#2932E1'), ('淘宝直播', '#FF5000'),
         ('京东直播', '#E1251B'), ('酷狗直播', '#2CA2F9'), ('六间房直播', '#E64A19'), ('Twitch', '#9146FF'), ('Soop', '#2A52BE'), ('CHZZK', '#00C73C'),
         ('Kick', '#53FC18'), ('TikTok LIVE', '#000000'), ('17LIVE', '#FF6A00'), ('TwitCasting', '#0EA5E9'), ('Picarto', '#1DA456')]


# ---------------------------------------------------------------- v3
def v3_card(title, icon, btn_icon, btn, text='', busy=False, dis=False, footer=''):
    ta = f'<div class="ta{" v" if text else ""}">{text or "请在此处粘贴平台链接..."}<span class="cl">{rx("eb97", 20)}</span></div>'
    bi = SPIN.replace('spin', 'spin" style="width:18px;height:18px;border-color:rgba(255,255,255,.35);border-top-color:#fff') if busy else rx(btn_icon, 18)
    b = f'<div class="fbw{" dis" if dis else ""}">{bi}{btn}</div>'
    cancel = '<div style="display:flex;justify-content:center;padding-top:4px"><span class="tb">取消</span></div>' if busy else ''
    return (f'<div class="tc"><div class="et">{rx(icon)}<span class="x">{title}</span>{mi("expand_less", 24, "var(--onv)")}</div>{ta}{b}{cancel}'
            f'<div style="height:16px"></div>{footer}</div>')


def v3_support():
    return (f'<div class="sup"><div class="hr"></div><div class="h">{rx("ee59", 14, "#757575")}支持解析列表</div><pre>{SUPPORT}</pre></div>')


def v3_body(t1='', t2='', busy=None):
    return ('<div style="padding:12px 16px">' + v3_card('直播间跳转', 'ecaf', 'f009', '链接跳转', t1, busy == 'jump', busy == 'link')
            + v3_card('获取直链', 'eeaf', 'ec54', '获取解析', t2, busy == 'link', busy == 'jump', v3_support()) + '</div>')


V3BAR = bar('链接解析')


def v3_choice(title, items, top=260):
    li = ''.join(f'<div class="li3">{a}' + (f'<small>{b}</small>' if b else '') + '</div>' for a, b in items)
    return (f'<div class="dim"></div><div class="chd" style="top:{top}px"><h3>{title}</h3><div style="height:12px"></div>{li}'
            '<div class="ft"><span class="tb">取消</span></div></div>')


# ---------------------------------------------------------------- new
def v4_body(text='', busy=None, expanded=False, n=False):
    N = (lambda k, t: (k, t)) if n else (lambda k, t: (None, None))
    k1, t1 = N(2, 'chg')
    k2, t2 = N(3, 'add' if not text else 'keep')
    k3, t3 = N(4, 'chg')
    k4, t4 = N(5, 'chg')
    k5, t5 = N(6, 'chg')
    suffix = mr('cancel', 20) if text else mr('content_paste', 20)
    ta = f'<div class="ta4{" v" if text else ""}"{dn(k1, t1, "tl")}>{text or "请在此处粘贴平台链接..."}<span class="cl"{dn(k2, t2, "tr")}>{suffix}</span></div>'
    sp = lambda: SPIN.replace('spin', 'spin" style="width:18px;height:18px')
    jump = f'<span class="fb{" dis" if busy == "link" else ""}"{dn(k3, t3)}>{sp() if busy == "jump" else mr("play_circle_outline", 18)}链接跳转</span>'
    link = f'<span class="tonal{" dis" if busy == "jump" else ""}"{dn(k4, t4)}>{sp() if busy == "link" else mr("link", 18)}获取直链</span>'
    busy_row = (f'<div class="busy"><span class="x">{"正在解析链接…" if busy == "jump" else "正在读取直播流地址…"}</span><span class="tb">取消</span></div>' if busy else '')
    card = (ns('平台链接') + '<div class="ncd"><div class="lnk" style="padding-top:12px"><div class="s" style="margin-top:0">粘贴直播间链接或分享文字，可以直接打开直播间，也可以获取直播流地址</div>'
            f'{ta}<div class="b2r">{jump}{link}</div>{busy_row}</div></div>')
    chips = ''.join(f'<span class="chip4"><i style="background:{c}">{nm[0]}</i>{nm}</span>' for nm, c in SITES)
    sup = (f'<div class="ncd" style="margin-top:16px"><div class="nr"{dn(k5, t5, "tl")}><span class="ic">{mr("info_outline")}</span><div class="x"><div class="t">支持解析列表</div>'
           f'<div class="s">共 45 个平台</div></div>{mr("expand_less" if expanded else "expand_more", 24, "var(--onv)")}</div>'
           + (f'<div class="hint" style="padding:0 16px 10px">可以粘贴这些平台的直播间链接、短链接或 App 分享文字</div><div class="chips4">{chips}</div>' if expanded else '') + '</div>')
    return ln(card + sup)


def v4_choice(title, items, top=250, on=0):
    li = ''.join(f'<div class="it{" on" if False else ""}" style="height:auto;min-height:56px;padding:8px 24px;flex-direction:column;align-items:flex-start;justify-content:center;gap:2px">'
                 f'<span style="font-size:15px">{a}</span>' + (f'<small style="font-size:12px;color:var(--onv);max-width:100%;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">{b}</small>' if b else '') + '</div>'
                 for a, b in items)
    return (f'<div class="dim"></div><div class="dlg2" style="top:{top}px;padding:24px 0 12px"><h3 style="padding:0 24px">{title}</h3>'
            f'<div class="menu2" style="position:static;box-shadow:none;background:transparent;margin-top:8px;padding:0">{li}</div>'
            '<div class="acts" style="padding:0 16px;margin-top:4px"><span>取消</span></div></div>')


QUAL = [('原画', None), ('蓝光', None), ('超清', None), ('高清', None)]
LINES = [('线路1', 'https://cdn-a.example.com/live/12345_bluray.flv?expires=…'), ('线路2', 'https://cdn-b.example.com/live/12345_bluray.flv?expires=…'),
         ('线路3', 'https://cdn-c.example.com/live/12345_bluray.m3u8?expires=…')]

OUT = {}
# ---- v3
OUT['v3-toolbox'] = p(phone(v3_body(), V3BAR))
OUT['v3-toolbox-full'] = page('393x2300@2 crop', V3BAR + v3_body(), 'long', css=CSS2)
OUT['v3-toolbox-states'] = composite([
    (phone(v3_body(LINK, LINK), V3BAR, '<div class="gsnack"><b>检测到链接</b><span>已自动填充剪贴板中的直播链接</span></div>'), '打开时读剪贴板：两个框都填上'),
    (phone(v3_body(LINK, LINK, busy='link'), V3BAR), '获取中：按钮转圈，下面“取消”'),
    (phone(v3_body(LINK, LINK), V3BAR, v3_choice('选择清晰度', QUAL)), '选清晰度'),
    (phone(v3_body(LINK, LINK), V3BAR, v3_choice('选择线路', LINES, 280) + '<div class="stoast" style="z-index:40;bottom:60px">已复制直链</div>'), '选线路：复制后提示'),
])
OUT['v3-toolbox-land'] = page('852x393@2', land(v3_body(), V3BAR), 'win', '--w:852px;--h:393px', css=CSS2)
OUT['v3-toolbox-wide'] = page('1280x800@1.5', wide(v3_body(), V3BAR), 'win', '--w:1280px;--h:800px', css=CSS2)

# ---- new
V4BAR = bar('链接解析', n_back=None)
OUT['v4-toolbox'] = p(phone(v4_body(n=True), bar('链接解析', n_back=1)))
OUT['v4-toolbox-full'] = page('393x1400@2 crop', V4BAR + v4_body(SHARE, expanded=True), 'long', css=CSS2)
OUT['v4-toolbox-states'] = composite([
    (phone(v4_body(LINK), V4BAR, '<div class="toast2"><span>已自动填充剪贴板中的直播链接</span></div>'), '打开时读剪贴板：只有一个框'),
    (phone(v4_body(LINK, busy='link'), V4BAR), '获取中：写在做什么，可以取消'),
    (phone(v4_body(LINK), V4BAR, v4_choice('选择清晰度', QUAL, 230)), '选清晰度'),
    (phone(v4_body(LINK), V4BAR, v4_choice('选择线路', LINES, 230) + '<div class="toast2" style="z-index:40"><span>已复制直链</span></div>'), '选线路：复制后提示'),
])
OUT['v4-toolbox-land'] = page('852x393@2', land(v4_body(), V4BAR), 'win', '--w:852px;--h:393px', css=CSS2)
OUT['v4-toolbox-wide'] = page('1280x800@1.5', wide(v4_body(LINK, expanded=True), V4BAR), 'win', '--w:1280px;--h:800px', css=CSS2)

write(HERE, OUT)
