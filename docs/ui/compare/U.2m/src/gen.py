"""U.2m switch-room panel mockups: v3 restored, v4.0.0 as it is, and the new
design, as HTML next to this file. Then:
    python3 docs/ui/compare/U.2m/src/gen.py && python3 tools/ui/mock/render.py docs/ui/compare/U.2m/src/ --annotate

v3 (tag v3.2.11), every text from assets/translations/zh.json:
  modules/live_play/dialogs/play_other.dart                      the dialog, _RoomSwitchCard, the tabs
  modules/live_play/widgets/content_first_panel_layout.dart:24-50 its size (half the width, right aligned)
  modules/live_play/widgets/content_first_panel_layout.dart:214-310 card height and columns
  modules/live_play/widgets/button/live_play_menu_button.dart:88-94 the portrait menu opens it as a dialog
  modules/live_play/widgets/video_player/video_controller_panel.dart:394-410 the fullscreen ⇄
v4.0.0: apps/pure_live/lib/features/live_play/dialogs/room_switcher.dart (70 % bottom sheet, ListTiles).

`python3 gen.py --counts` prints the card counts of the README's table (the
same formulas as apps/pure_live/lib/features/live_play/logic/room_switch.dart
and its test)."""
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

CSS = '''
.ph{display:flex;flex-direction:column}
.grow{flex:1;min-height:0}
/* ---------- v3 room (U.2a's v3 restore) ---------- */
.v3nick{font-size:12px;line-height:16px}.v3area{font-size:12px;line-height:16px;color:var(--onv)}
.v3heart{width:40px;height:40px;border-radius:20px;background:var(--pc);display:grid;place-items:center;color:var(--opc);margin-right:6px;flex:none}
.v3recsq{width:48px;height:48px;border-radius:12px;background:var(--schh);display:grid;place-items:center;color:var(--onv);flex:none}
.v3top{position:absolute;left:0;right:0;top:0;height:56px;display:flex;align-items:center;padding:0 8px;background:linear-gradient(0deg,transparent,rgba(0,0,0,.45));z-index:5;color:#fff}
.v3top .title{flex:1;min-width:0;padding:0 12px;font:700 16px 'Noto Sans SC';white-space:nowrap;overflow:hidden;text-overflow:ellipsis;color:#fff}
.v3bot{position:absolute;left:0;right:0;bottom:0;height:56px;display:flex;align-items:center;padding:0 8px;background:linear-gradient(180deg,transparent,rgba(0,0,0,.45));color:#fff;z-index:5}
.pill{display:flex;align-items:center;gap:2px;padding:0 6px;height:48px;font-size:14px;flex:none;color:#fff}
.res{height:56px;display:flex;align-items:center;padding:0 4px;flex:none}
.res .aud{flex:3;padding:0 8px;display:flex;align-items:center;gap:4px;font-size:12px}
.res .q{flex:2;text-align:right;font-size:11px;color:var(--primary);padding-right:12px}
.res .l{flex:1;text-align:right;font-size:11px;color:var(--primary);padding-right:12px}
.tabs.v3t div{font-size:15px}
.list3{flex:1;min-height:0;overflow:hidden;display:flex;flex-direction:column;justify-content:flex-end;padding:10px 6px}
.it3{margin:4px 8px;background:rgba(255,255,255,.72);border:.5px solid rgba(0,0,0,.08);border-radius:10px;padding:8px 12px;display:flex;align-items:flex-start;flex:none}
.it3 i{width:8px;height:8px;border-radius:4px;margin:6px 10px 0 0;flex:none}.it3 p{font-size:14px;line-height:1.45}.it3 b{font-weight:700}
/* ---------- v3 PlayOther dialog ---------- */
.d3{position:absolute;z-index:21;background:var(--sch);border-radius:16px;overflow:hidden;display:flex;flex-direction:column;box-shadow:0 6px 24px rgba(0,0,0,.25)}
.d3h{height:48px;display:flex;align-items:center;padding:0 2px 0 10px;flex:none}
.d3h .t{flex:1;font-size:14px;font-weight:600;margin-left:6px}
.d3h .b{width:48px;height:48px;display:grid;place-items:center;color:var(--onv)}
.d3t{height:48px;display:flex;flex:none;border-bottom:1px solid var(--ov)}
.d3t div{flex:1;display:flex;align-items:center;justify-content:center;gap:3px;font-size:12px;color:var(--onv);position:relative}
.d3t .on{color:var(--primary)}.d3t .on::after{content:'';position:absolute;bottom:0;left:18%;right:18%;height:3px;border-radius:3px 3px 0 0;background:var(--primary)}
.g3{flex:1;min-height:0;overflow:hidden;padding:6px;display:grid;gap:5px;align-content:start}
.c3{background:var(--scl);border:1px solid rgba(195,199,207,.55);border-radius:12px;overflow:hidden;display:flex;flex-direction:column}
.c3 .cv{flex:1;min-height:0;position:relative;background:#333 center/cover}
.c3 .pf{position:absolute;top:7px;right:7px;padding:3px 7px;border-radius:7px;background:rgba(0,0,0,.58);color:#fff;font-size:11px;font-weight:700;line-height:1}
.c3 .mt{position:absolute;left:0;right:0;bottom:0;padding:22px 8px 8px;background:linear-gradient(180deg,transparent,rgba(0,0,0,.87));color:#fff;font-size:11px;font-weight:600;line-height:1.1}
.c3 .ft{height:36px;padding:3px 3px 3px 7px;display:flex;flex-direction:column;flex:none}
.c3 .ft b{font-size:12px;font-weight:700;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;line-height:16px}
.c3 .ft span{display:flex;align-items:center;gap:3px;font-size:11px;color:var(--onv);margin-top:auto;line-height:14px}
/* ---------- v4.0.0 sheet ---------- */
.bs{position:absolute;left:0;right:0;bottom:0;z-index:21;background:var(--scl);border-radius:28px 28px 0 0;display:flex;flex-direction:column;overflow:hidden}
.handle{height:48px;display:grid;place-items:center;flex:none}.handle i{width:32px;height:4px;border-radius:2px;background:rgba(67,71,78,.4)}
.lt{display:flex;align-items:center;gap:16px;padding:8px 24px 8px 16px;min-height:64px}
.lt .x{flex:1;min-width:0}.lt .a{font-size:16px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.lt .b{font-size:12px;color:var(--onv);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.lt .av{width:40px;height:40px;border-radius:20px}
/* ---------- v4 room (U.2a) ---------- */
.list{flex:1;min-height:0;overflow:hidden;display:flex;flex-direction:column;justify-content:flex-end;padding:6px 0 8px}
.under{position:absolute;left:0;right:0;bottom:0;background:var(--surface);z-index:21;display:flex;flex-direction:column;overflow:hidden;box-shadow:0 -2px 8px rgba(0,0,0,.08)}
/* ---------- new switch panel ---------- */
.sp{display:flex;flex-direction:column;background:var(--surface);color:var(--on);overflow:hidden}
.sph{height:56px;display:flex;align-items:center;padding:4px 4px 0 16px;flex:none}
.sph .t{flex:1;min-width:0;font-size:16px;font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.sph .b{width:48px;height:48px;display:grid;place-items:center;color:var(--onv);flex:none}
.sph .b.on{color:var(--primary)}
.rf{height:32px;display:flex;align-items:center;gap:4px;padding:0 8px 0 6px;border-radius:16px;font-size:12px;color:var(--onv);flex:none;white-space:nowrap}
.rf.err{color:var(--error)}
.seg{height:40px;display:flex;align-items:center;gap:8px;padding:0 12px;flex:none;overflow:hidden;white-space:nowrap}
.seg span{height:32px;border-radius:16px;padding:0 12px;display:inline-flex;align-items:center;gap:4px;font-size:13px;color:var(--onv);box-shadow:inset 0 0 0 1px var(--ov);flex:none}
.seg span.on{background:var(--sc);color:var(--osc);box-shadow:none;font-weight:600}
.seg span small{font-size:12px;font-weight:500;opacity:.8}
.now{height:36px;display:flex;align-items:center;gap:6px;padding:0 12px;background:var(--scl);flex:none;white-space:nowrap;overflow:hidden}
.now b{font-size:12px;color:var(--primary);font-weight:600;flex:none}
.now span{font-size:12px;color:var(--onv);overflow:hidden;text-overflow:ellipsis;min-width:0}
.srch{height:48px;margin:0 12px 6px;border-radius:24px;background:var(--sch);display:flex;align-items:center;gap:8px;padding:0 6px 0 14px;flex:none;font-size:14px}
.srch .x{margin-left:auto;width:36px;height:36px;display:grid;place-items:center;color:var(--onv)}
.gr{flex:1;min-height:0;overflow:hidden;padding:6px;display:grid;gap:5px;align-content:start}
.cd{background:var(--scl);border:1px solid rgba(195,199,207,.55);border-radius:12px;overflow:hidden;display:flex;flex-direction:column}
.cd .cv{flex:1;min-height:0;position:relative;background:#333 center/cover}
.cd .tl{position:absolute;left:6px;top:6px;display:flex;gap:4px}
.cd .tr2{position:absolute;right:6px;top:6px}
.bdg{height:18px;border-radius:9px;padding:0 6px;display:inline-flex;align-items:center;gap:2px;font-size:10.5px;font-weight:700;color:#fff;background:rgba(0,0,0,.54);line-height:1;white-space:nowrap}
.bdg.live{background:var(--live)}.bdg .mr{font-size:12px}
.cd .bt{position:absolute;left:0;right:0;bottom:0;padding:16px 8px 5px;background:linear-gradient(180deg,transparent,rgba(0,0,0,.7));color:#fff;font-size:11px;line-height:14px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.cd .ft{height:26px;padding:0 8px;display:flex;align-items:center;flex:none;font-size:12px;font-weight:600;white-space:nowrap;overflow:hidden}
.cd .ft span{overflow:hidden;text-overflow:ellipsis;flex:1;min-width:0}.cd .ft small{font-size:11px;font-weight:400;color:var(--onv);margin-left:6px;flex:none}
.cd.off .cv::after{content:'';position:absolute;inset:0;background:rgba(0,0,0,.54)}
.cd.off .tl,.cd.off .bt{z-index:2}.cd.off .ft{color:var(--onv)}
.lr{height:75px;display:flex;align-items:center;gap:12px;padding:6px 12px;flex:none}
.lr .cv{width:112px;height:63px;border-radius:8px;background:#333 center/cover;position:relative;flex:none;overflow:hidden}
.lr .cv .tl{position:absolute;left:4px;top:4px;display:flex;gap:3px}
.lr .x{flex:1;min-width:0;display:flex;flex-direction:column;gap:2px}
.lr .a{font-size:14px;font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.lr .b{font-size:12.5px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.lr .c{font-size:12px;color:var(--onv);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.lr.off .cv::after{content:'';position:absolute;inset:0;background:rgba(0,0,0,.54)}.lr.off .cv .tl{z-index:2}.lr.off .a,.lr.off .b{color:var(--onv)}
.ls{flex:1;min-height:0;overflow:hidden;display:flex;flex-direction:column;padding:2px 0}
.empty{flex:1;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:8px;color:var(--onv);font-size:14px;text-align:center;padding:0 24px}
.empty .mr{font-size:40px;opacity:.6}.empty .ob{margin-top:6px;height:36px;padding:0 16px;border-radius:18px;box-shadow:inset 0 0 0 1px var(--ov);color:var(--primary);font-size:14px;font-weight:600;display:inline-flex;align-items:center}
.lbl{position:absolute;z-index:50;font:600 13px 'Noto Sans SC';color:#fff;background:#2F5FA8;padding:3px 8px;border-radius:6px}
.cnt{position:absolute;z-index:50;font:700 13px 'Noto Sans SC';color:#fff;background:#C2410C;padding:2px 8px;border-radius:10px}
/* menus */
.menu .it .rx,.menu .it .mr{font-size:20px;color:var(--onv)}
.menu .it.dup{background:rgba(194,65,12,.12)}
.menu .it small{display:block;font-size:12px;color:var(--onv)}
.vtop.fsb{height:84px}
'''

mr = lambda n, s=24, st='': f'<span class="mr" style="font-size:{s}px;{st}">{n}</span>'
mi = lambda n, s=24, st='': f'<span class="mi" style="font-size:{s}px;{st}">{n}</span>'
rx = lambda c, s=24, st='': f'<span class="rx" style="font-size:{s}px;{st}">&#x{c};</span>'
ci = lambda c, s=24: f'<span class="ci" style="font-size:{s}px">&#x{c};</span>'


def N(n, at=None, tag=None):
    if n is None:
        return ''
    return f' data-n="{n}"' + (f' data-at="{at}"' if at else '') + (f' data-tag="{tag}"' if tag else '')


def ib(inner, n=None, cls='ib', at=None, tag=None):
    return f'<div class="{cls}"{N(n, at, tag)}>{inner}</div>'


def page(w, h, scale, body, frame='ph', crop=False, extra=''):
    size = f'{w}x{h}@{scale}' + (' crop' if crop else '')
    style = '' if frame == 'ph' else f' style="--w:{w}px;--h:{h}px"'
    return (f'<!doctype html><html><head><meta charset="utf-8"><meta name="mock-size" content="{size}">'
            f'<link rel="stylesheet" href="kit/kit.css"><style>{CSS}{extra}</style></head>'
            f'<body><div class="{frame}"{style}>{body}</div></body></html>')


STATUS = '<div class="status"><span>21:36</span><span class="r"><span class="mi">signal_cellular_alt</span><span class="mi">wifi</span><span class="mi">battery_full</span></span></div>'
GEST = '<div class="gesture"></div>'
SYN = '<div class="syn">示意图片</div>'
TITLE = '深夜电台 · 点歌接龙到天亮'
FS_TITLE = '纽约时代广场，夜游直播'
FS_EXTRA = '.fs{background-image:url(.cache/img/274.jpg);background-position:center 40%}'

# The rooms of the lists (sample data; images are placeholders).
# (nick, platform, area, title, audience, image, state, watched)
ROOMS = [
    ('星河长明', '哔哩哔哩', '英雄联盟', '今晚冲分到王者，水友赛开放', '12.4万', 1, 'live', None),
    ('一只小熊', '斗鱼', '王者荣耀', '周末开黑，来！上分车', '8.6万', 111, 'live', None),
    ('夜猫子', '虎牙', '主机游戏', '通宵 · 艾尔登法环 DLC 全收集', '3.1万', 133, 'live', None),
    ('路过的风', '哔哩哔哩', '唱见电台', '深夜点歌，接龙到天亮', '2.2万', 169, 'live', None),
    ('橘子汽水', '抖音', '户外', '城市夜跑 10 公里', '1.8万', 183, 'live', None),
    ('Aki', '哔哩哔哩', '虚拟主播', '新衣装首播！', '9876', 206, 'live', None),
    ('不吃香菜', '斗鱼', '美食', '做一桌家常菜', '5432', 219, 'live', None),
    ('月亮邮差', '虎牙', '星秀', '唱歌聊天', '3210', 225, 'live', None),
    ('北岛', '快手', '聊天', '随便聊聊，今晚早点下', '1288', 237, 'live', None),
    ('阿七', '哔哩哔哩', '绘画', '画一张星空', '960', 250, 'live', None),
]
HISTORY = [
    ('星河长明', '哔哩哔哩', '英雄联盟', '今晚冲分到王者，水友赛开放', '12.4万', 1, 'live', '20 分钟前'),
    ('海边的猫', '哔哩哔哩', '生活', '海边日落，慢慢看', '', 287, 'off', '2 小时前'),
    ('一只小熊', '斗鱼', '王者荣耀', '周末开黑，来！上分车', '8.6万', 111, 'live', '昨天'),
    ('老周讲历史', '虎牙', '知识', '宋朝的一天', '', 292, 'off', '3 天前'),
    ('Aki', '哔哩哔哩', '虚拟主播', '新衣装首播！', '9876', 206, 'live', '5 天前'),
    ('山野', '抖音', '户外', '徒步虎跳峡', '', 304, 'off', '6 天前'),
]
REPLAYS = [
    ('小鹿', '哔哩哔哩', '单机游戏', '【回放】通关纪念', '3520', 319, 'replay', None),
    ('橙子', '斗鱼', '星秀', '【录播】生日会', '1102', 338, 'replay', None),
]
SOURCE = [  # opened from "热门 · 英雄联盟"
    ('星河长明', '哔哩哔哩', '英雄联盟', '今晚冲分到王者，水友赛开放', '12.4万', 1, 'live', None),
    ('夏天', '哔哩哔哩', '英雄联盟', '钻石局教学，讲细节', '6.7万', 342, 'live', None),
    ('冬瓜', '哔哩哔哩', '英雄联盟', '大乱斗一整晚', '4.4万', 360, 'live', None),
    ('东东', '哔哩哔哩', '英雄联盟', '新英雄首日', '2.9万', 367, 'live', None),
    ('Mika', '哔哩哔哩', '英雄联盟', '下饭局', '1.5万', 1011, 'live', None),
    ('风行', '哔哩哔哩', '英雄联盟', '峡谷之巅冲榜', '8800', 1027, 'live', None),
]
CURRENT = ('晚风', '哔哩哔哩', '唱见电台', TITLE)

# ---------------------------------------------------------------------
# sizes (dp) and the card count formulas
# ---------------------------------------------------------------------
PAD, GAP, MINW = 6.0, 5.0, 168.0
V3_FOOT, V3_CHROME = 36.0, 97.0          # play_other.dart: footer; header 48 + tabs 48 + divider 1
NEW_FOOT, NEW_CHROME = 26.0, 132.0       # nick line; header 56 + groups 40 + "正在观看" 36
NEW_ROW = 75.0                           # the list style's row: 63 cover + 12


def v3_columns(width):
    usable = max(0.0, width - PAD * 2)
    return 2 if usable >= MINW * 2 + GAP else 1


def new_columns(width):
    usable = max(0.0, width - PAD * 2)
    return max(1, int((usable + GAP) // (MINW + GAP)))


def v3_card_height(w, h, cols, foot=V3_FOOT):
    usable = max(0.0, w - PAD * 2 - GAP * (cols - 1))
    natural = usable / cols * 9 / 16 + foot
    acc = foot + 60
    if cols < 2:
        return min(max(natural, acc, 118), max(310, acc))
    two = (h - PAD * 2 - GAP) / 2
    compact = max(min(112, natural), min(natural, two))
    return min(max(acc, compact, 96), max(310, acc))


def new_card_height(w, h, cols, foot=NEW_FOOT):
    usable = max(0.0, w - PAD * 2 - GAP * (cols - 1))
    natural = usable / cols * 9 / 16 + foot
    floor = max(96.0, foot + 60)
    if cols < 2:
        return max(natural, floor)
    return max(floor, min(natural, (h - PAD * 2 - GAP) / 2))


def visible(h, card, cols, pad=PAD, gap=GAP):
    """(cards fully in view, cards at least half in view)."""
    full = half = 0
    y = pad
    while y < h:
        bottom = y + card
        if bottom <= h + .01:
            full += cols
        if y + card / 2 <= h + .01:
            half += cols
        y = bottom + gap
    return full, half


def v3_dialog(vw, vh):
    """content_first_panel_layout.dart:24-50 (roomHistory): the dialog's size."""
    compact = vw < 720 or vh < 520
    inset = 8.0 if compact else 20.0
    aw, ah = max(280.0, vw - inset * 2), max(240.0, vh - inset * 2)
    width = min(max(280.0, aw * .5), aw)
    height = min(max(240.0, min(max(vh, 240.0), 720.0)), ah)
    return width, height, inset


LAYOUTS = [
    # name, viewport, the new panel (width, height)
    ('竖屏手机 393×852', (393, 852), (393, 852 - 36 - 56 - 221 - 16)),
    ('竖屏全屏（底部 60%）', (393, 852), (393, 852 * .6 - 16)),
    ('横屏手机 852×393', (852, 393), (360, 393)),
    ('窄横屏 740×360', (740, 360), (360, 360)),
    ('平板横屏 1280×800（宽屏、全屏）', (1280, 800), (360, 800 - 24 - 56)),
    ('平板竖屏 800×1280', (800, 1280), (800, 1280 - 24 - 56 - 450 - 16)),
]


def counts():
    rows = []
    for name, (vw, vh), (pw, ph) in LAYOUTS:
        dw, dh, _ = v3_dialog(vw, vh)
        c3 = v3_columns(dw)
        g3 = dh - V3_CHROME
        k3 = v3_card_height(dw, g3, c3)
        v3 = visible(g3, k3, c3)
        cn = new_columns(pw)
        gn = ph - NEW_CHROME
        kn = new_card_height(pw, gn, cn)
        vn = visible(gn, kn, cn)
        ln = visible(gn, NEW_ROW, 1, pad=2, gap=0)
        rows.append((name, f'{dw:.0f}×{dh:.0f}', c3, v3, f'{pw:.0f}×{ph:.0f}', cn, vn, ln, k3, kn))
    return rows


# =====================================================================
# v3
# =====================================================================
def v3_appbar():
    return ('<div class="appbar"><div class="back">' + mi('arrow_back') + '</div><span class="av" style="background-image:url(.cache/img/65.jpg)"></span>'
            '<div class="tt" style="margin-left:8px"><div class="v3nick">晚风</div><div class="v3area">哔哩哔哩 / 唱见电台</div></div>'
            '<div class="v3heart">' + mr('favorite_border', 22) + '</div><div class="v3recsq">' + mr('radio_button_checked', 22) + '</div>'
            + ib(rx('ea42')) + '<div style="width:4px"></div></div>')


def v3_video():
    top = '<div class="v3top"><div class="title">' + TITLE + '</div>' + ib(rx('ee05', 21)) + ib(rx('f235')) + ib(ci('e806')) + '</div>'
    bot = ('<div class="v3bot">' + ib(mr('pause', 28)) + ib(mr('refresh')) + '<div class="pill">' + mr('check', 15) + '已关注</div>'
           + ib('<span class="dmk open"></span>') + ib('<span class="dmk set"></span>') + ib(mr('screen_rotation_alt', 21))
           + '<div style="flex:1"></div>' + ib(mr('fullscreen', 26)) + '</div>')
    return f'<div class="video" style="background-image:url(.cache/img/158.jpg);flex:none">{top}{bot}</div>'


CHAT = [('#C2255C', '星河长明', '前排支持！'), ('#000', '一只小熊', '这首歌好好听'), ('#1971C2', '夜猫子', '可以点《晴天》吗'),
        ('#000', '路过的风', '主播声音太温柔了'), ('#C2410C', 'Aki', '打卡第 52 天，晚安前来听歌'), ('#000', '橘子汽水', '晚风晚上好～')]


def v3_room(overlay=''):
    res = ('<div class="res"><div class="aud">' + mr('people_alt', 16) + '在线 1.2万</div><div class="q">原画</div><div class="l">线路1</div></div><hr>'
           '<div class="tabs v3t" style="flex:none"><div class="on">弹幕列表</div><div>醒目留言</div><div>弹幕设置</div><div>屏蔽管理</div></div>')
    cards = ''.join(f'<div class="it3"><i style="background:{c}"></i><p><b>{u}: </b>{t}</p></div>' for c, u, t in CHAT)
    return STATUS + v3_appbar() + v3_video() + res + f'<div class="list3">{cards}</div>' + overlay + SYN + GEST


def v3_card(room, history=False):
    nick, plat, area, title, aud, img, state, watched = room
    meta = (f'{watched}观看' if history else (aud or '人数未知'))
    return (f'<div class="c3"><div class="cv" style="background-image:url(.cache/img/{img}.jpg)"><span class="pf">{plat}</span>'
            f'<span class="mt">{meta}</span></div><div class="ft"><b>{title}</b><span>' + mr('person_outline', 12) + f'<i style="flex:1;font-style:normal;white-space:nowrap;overflow:hidden">{nick}</i>' + mr('chevron_right', 14) + '</span></div></div>')


def v3_dialog_html(x, y, w, h, rooms, history=False):
    cols = v3_columns(w)
    g = h - V3_CHROME
    card = v3_card_height(w, g, cols)
    tabs = ('<div class="d3t"><div class="on">' + mr('sensors', 14) + '已开播</div><div>' + mr('fiber_smart_record', 14) + '录播</div><div>'
            + mr('history', 14) + '观看记录</div></div>')
    head = ('<div class="d3h">' + mr('video_library', 17, 'color:var(--primary)') + '<span class="t">切换直播间</span>'
            '<span class="b">' + mr('refresh', 18) + '</span><span class="b">' + mr('close', 18) + '</span></div>')
    grid = (f'<div class="g3" style="grid-template-columns:repeat({cols},1fr);grid-auto-rows:{card:.1f}px">'
            + ''.join(v3_card(r, history) for r in rooms) + '</div>')
    return f'<div class="d3" style="left:{x}px;top:{y}px;width:{w}px;height:{h}px">{head}{tabs}{grid}</div>'


def v3_portrait_page():
    w, h, inset = v3_dialog(393, 852)
    dlg = v3_dialog_html(393 - inset - w, (852 - h) / 2, w, h, ROOMS)
    return page(393, 852, 3, v3_room('<div class="scrim"></div>' + dlg))


def v3_fs_bars():
    lead = ib(mi('arrow_back')) + '<div class="time" style="padding:0 4px">21:36</div><div class="bat" style="margin:0 8px">76</div>'
    trail = ('<div style="width:40px;height:40px;border-radius:20px;background:rgba(0,0,0,.26);display:grid;place-items:center;margin:0 4px">' + mr('swap_horiz') + '</div>'
             + ib(rx('ee05', 21)) + ib(rx('f235')) + ib(ci('e806')))
    left = (ib(mr('pause', 28)) + ib(mr('refresh')) + '<div class="pill">' + mr('check', 15) + '已关注</div>' + ib('<span class="dmk open"></span>') + ib('<span class="dmk set"></span>'))
    right = ('<div style="display:flex;align-items:center;gap:6px;height:36px;padding:0 10px;border-radius:18px;background:rgba(255,255,255,.13);font-size:13px;font-weight:600">'
             + mr('tune', 17) + '原画 · 线路1</div>' + ib(mr('screen_rotation_alt', 21)) + ib(mr('fullscreen_exit', 26)))
    return (f'<div class="v3top">{lead}<div class="title">{FS_TITLE}</div>{trail}</div>'
            '<div class="v3bot" style="padding:0 16px"><div style="display:flex;align-items:center">' + left + '</div><div style="flex:1"></div>'
            '<div style="display:flex;align-items:center">' + right + '</div></div>')


def v3_landscape_page():
    w, h, inset = v3_dialog(852, 393)
    dlg = v3_dialog_html(852 - inset - w, inset, w, h, ROOMS)
    body = SYN + v3_fs_bars() + '<div class="scrim"></div>' + dlg
    return page(852, 393, 2, body, frame='fs', extra=FS_EXTRA)


# =====================================================================
# v4.0.0 (as released)
# =====================================================================
def v4_appbar(n=None):
    return ('<div class="appbar"><div class="back">' + mi('arrow_back') + '</div><span class="av" style="background-image:url(.cache/img/65.jpg)"></span>'
            '<div class="tt"><div class="n">晚风</div><div class="s">哔哩哔哩 · 唱见电台</div></div>'
            '<div class="fol on">' + rx('eb7b') + '已关注</div><div class="recbtn"><span class="ring"><i></i></span></div>'
            + ib(rx('ea42'), n, tag='chg' if n else None) + '<div style="width:4px"></div></div>')


def v4_video():
    top = ('<div class="vtop"><div class="title">' + TITLE + '</div>' + ib(rx('ee05', 21), cls='ib vic') + ib(rx('f235'), cls='ib vic') + ib(ci('e806'), cls='ib vic') + '</div>')
    bot = ('<div class="vbot">' + ib(mr('pause', 28), cls='ib vic') + ib(mr('refresh'), cls='ib vic') + ib('<span class="dmk open"></span>', cls='ib vic')
           + ib('<span class="dmk set"></span>', cls='ib vic') + '<div style="flex:1"></div>' + ib(mr('screen_rotation_alt', 21), cls='ib vic') + ib(mr('fullscreen', 26), cls='ib vic') + '</div>')
    dms = '<div class="dm" style="left:150px;top:62px">前排支持！</div><div class="dm" style="left:24px;top:98px">这首好好听</div>'
    return f'<div class="video" style="background-image:url(.cache/img/158.jpg);flex:none">{dms}{top}{bot}</div>'


def v4_info():
    return ('<div class="info" style="flex:none"><div class="l1"><span class="t">' + TITLE + '</span><span class="more">详情' + rx('ea4e', 18) + '</span></div>'
            '<div class="l2"><div class="figs"><span class="fg"><span class="mr">people_alt</span><b>1.2万</b></span><span class="fg"><span class="mr">whatshot</span><b>84.7万</b></span>'
            '<span class="fg"><span class="mr">schedule</span><b>2:18</b></span></div><div class="chip">原画' + rx('ea4e', 18) + '</div><div class="chip">线路 1' + rx('ea4e', 18) + '</div></div></div><hr>'
            '<div class="tabs" style="flex:none"><div class="on">弹幕列表</div><div>醒目留言<span class="badge">2</span></div><div>弹幕设置</div><div>屏蔽管理</div></div>')


def v4_room(overlay='', n=None):
    rows = ''.join(f'<div class="row"><span class="u" style="{"" if c == "#000" else "color:" + c}">{u}：</span>{t}</div>' for c, u, t in CHAT)
    return (STATUS + v4_appbar(n) + v4_video() + v4_info() + f'<div class="list"><div class="sys">弹幕服务器连接正常</div>{rows}</div>'
            + '<div style="height:14px;flex:none"></div>' + overlay + SYN + GEST)


def now_portrait_page():
    tiles = ''.join(
        f'<div class="lt"><span class="av" style="background-image:url(.cache/img/{r[5]}.jpg)"></span><div class="x"><div class="a">{r[0]}</div>'
        f'<div class="b">{r[1]} · {r[3]}</div></div>' + mr('live_tv', 18, 'color:var(--primary)') + '</div>' for r in ROOMS[:7])
    sheet = ('<div class="bs" style="top:255px"><div class="handle"><i></i></div>'
             '<div style="display:flex;align-items:center;padding:0 4px 0 16px;height:48px"><span style="flex:1;font-size:16px;font-weight:500">切换直播间</span>'
             + ib(mr('refresh')) + '</div><div class="tabs" style="background:transparent"><div class="on">已开播</div><div>关注的回放</div><div>观看记录</div></div>'
             + '<hr><div style="flex:1;overflow:hidden">' + tiles + '</div></div>')
    return page(393, 852, 3, v4_room('<div class="scrim"></div>' + sheet))


def v4_fs_bars(n=False, menu_open=False, switch_n=None):
    nn = (lambda k: k) if n else (lambda k: None)
    lead = ib(mi('arrow_back'), cls='ib vic') + '<div class="time" style="margin:14px 6px 0 2px">21:36</div><div class="bat" style="margin-top:16px">76</div>'
    trail = (ib(mr('swap_horiz'), switch_n, cls='ib vic', tag='keep' if switch_n else None) + ib(rx('ee05', 21), cls='ib vic') + ib(rx('f235'), cls='ib vic') + ib(ci('e806'), cls='ib vic')
             + '<div class="ib"><span class="ring" style="border-color:#fff"><i></i></span></div>'
             + f'<div class="ib vic"{N(nn(9), tag="chg") if n else ""} style="{"background:rgba(255,255,255,.18);border-radius:24px" if menu_open else ""}">' + rx('ea42') + '</div>')
    left = (ib(mr('pause', 28), cls='ib vic') + ib(mr('refresh'), cls='ib vic')
            + '<div style="height:32px;border-radius:16px;display:flex;align-items:center;gap:3px;padding:0 12px 0 9px;font-size:13px;font-weight:500;background:rgba(255,255,255,.18);color:#fff;margin:0 4px;flex:none">' + rx('eb7b', 16) + '已关注</div>'
            + ib('<span class="dmk open"></span>', cls='ib vic') + ib('<span class="dmk set"></span>', cls='ib vic'))
    right = ('<div class="vchip" style="margin:0 3px">原画' + rx('ea4e', 18) + '</div><div class="vchip" style="margin:0 3px">线路1' + rx('ea4e', 18) + '</div>'
             + ib(mr('screen_rotation_alt', 21), cls='ib vic') + ib(rx('ea80', 22), cls='ib vic') + ib(mr('fullscreen_exit', 26), cls='ib vic'))
    return (f'<div class="vtop">{lead}<div class="title">{FS_TITLE}</div>{trail}</div>'
            '<div class="vbot" style="padding:0 12px 4px"><div style="display:flex;align-items:center;height:48px;flex:none">' + left + '</div>'
            '<div style="flex:1"></div><div style="display:flex;align-items:center;height:48px;flex:none">' + right + '</div></div>')


def menu_html(x, y, onbars=(), mark=False, n=False):
    items = [
        [(mr('swap_horiz', 20), '切换直播间', None, 'switchRoom'), (rx('f20f', 20), '定时关闭', None, 'timer'),
         (rx('f2a2', 20), '房间音量', None, 'volume'), (rx('ea80', 20), '画面比例', '默认比例', 'videoFit')],
        [(rx('f235', 20), '投屏', None, 'cast'), (rx('eeaf', 20), '获取直链', None, 'streamLink'), (rx('f0fd', 20), '分享', None, 'share'),
         (mr('open_in_new', 20), '在哔哩哔哩打开', None, 'external')],
    ]
    o = [f'<div class="menu" style="left:{x}px;top:{y}px;width:220px">']
    first = True
    for group in items:
        rows = [it for it in group if it[3] not in onbars]
        if not rows:
            continue
        if not first:
            o.append('<div class="sep"></div>')
        first = False
        for icon, text, sub, entry in rows:
            dup = mark and entry in ('switchRoom', 'cast', 'videoFit')
            label = f'<span>{text}' + (f'<small>{sub}</small>' if sub else '') + '</span>'
            o.append(f'<div class="it{" dup" if dup else ""}">{icon}{label}' + ('<span style="font-size:11px;color:#C2410C;font-weight:600;flex:none">栏上已有</span>' if dup else '') + '</div>')
    o.append('</div>')
    return ''.join(o)


def now_menu_page():
    body = SYN + v4_fs_bars(menu_open=True) + menu_html(852 - 228, 52, mark=True)
    body += ('<div style="position:absolute;left:556px;top:4px;width:48px;height:48px;border:2px dashed #C2410C;border-radius:24px;z-index:30"></div>'
             '<div style="position:absolute;left:652px;top:4px;width:48px;height:48px;border:2px dashed #C2410C;border-radius:24px;z-index:30"></div>')
    return page(852, 393, 2, body, frame='fs', extra=FS_EXTRA)


def new_menu_page():
    body = SYN + v4_fs_bars(n=True, menu_open=True, switch_n=11) + menu_html(852 - 228, 52, onbars=('switchRoom', 'cast', 'videoFit'))
    return page(852, 393, 2, body, frame='fs', extra=FS_EXTRA)


# =====================================================================
# the new panel
# =====================================================================
def badges(state, aud, small=False, watched=None):
    if state == 'live':
        b = '<span class="bdg live">直播中</span>' + (f'<span class="bdg">' + mr('people_alt', 11) + f'{aud}</span>' if aud else '')
    elif state == 'replay':
        b = '<span class="bdg">' + mr('videocam', 11) + '回放</span>' + (f'<span class="bdg">' + mr('people_alt', 11) + f'{aud}</span>' if aud else '')
    else:
        b = f'<span class="bdg">未开播 · 上次看 {watched}</span>' if watched and not small else '<span class="bdg">未开播</span>'
    return b


def card(room, mixed=True, n=None, history=False):
    nick, plat, area, title, aud, img, state, watched = room
    off = state == 'off'
    pf = f'<small>{plat}</small>' if mixed else ''
    return (f'<div class="cd{" off" if off else ""}"{N(n, "c", "add" if n else None)}><div class="cv" style="background-image:url(.cache/img/{img}.jpg)">'
            f'<span class="tl">{badges(state, aud, watched=watched)}</span><span class="bt">{title}</span></div>'
            f'<div class="ft"><span>{nick}</span>{pf}</div></div>')


def row(room, n=None):
    nick, plat, area, title, aud, img, state, watched = room
    off = state == 'off'
    line = f'未开播 · 上次看 {watched}' if off else f'{plat} · {area}'
    return (f'<div class="lr{" off" if off else ""}"{N(n, "c", "add" if n else None)}><div class="cv" style="background-image:url(.cache/img/{img}.jpg)">'
            f'<span class="tl">{badges(state, aud, small=True)}</span></div>'
            f'<div class="x"><div class="a">{nick}</div><div class="b">{title}</div><div class="c">{line}</div></div></div>')


GROUPS = [('onair', '关注在播', 10), ('source', '来源列表', 6), ('history', '观看记录', None), ('replays', '关注回放', 2)]


def panel(w, h, layout='grid', group='onair', source=False, n=False, refresh='2 分钟前', search=None, rooms=None, state=None, mixed=True, drag=False):
    nn = (lambda k: k) if n else (lambda k: None)
    rf_cls = 'rf err' if refresh == '刷新失败' else 'rf'
    rf_icon = mr('error_outline', 18) if refresh == '刷新失败' else ('<span style="width:16px;height:16px;border-radius:8px;border:2px solid var(--primary);border-right-color:transparent;display:inline-block"></span>' if refresh == '正在刷新' else mr('refresh', 18))
    head = (f'<div class="sph"{" style=&quot;&quot;" if drag else ""}><span class="t">切换直播间</span>'
            f'<span class="{rf_cls}"{N(nn(2), "tc", "add")}>{rf_icon}{refresh}</span>'
            f'<span class="b{" on" if search is not None else ""}"{N(nn(3), "tc", "add")}>' + mr('search', 22) + '</span>'
            f'<span class="b"{N(nn(4), "tc", "add")}>' + mr('view_list' if layout == 'grid' else 'grid_view', 22) + '</span>'
            f'<span class="b"{N(nn(5), "tc", "keep")}>' + mr('close', 22) + '</span></div>')
    pills = []
    for i, (key, label, count) in enumerate(GROUPS):
        if key == 'source' and not source:
            continue
        on = key == group
        pills.append(f'<span class="{"on" if on else ""}"{N(nn(6), "tc", "chg") if i == 0 else ""}>{label}' + (f'<small>{count}</small>' if count else '') + '</span>')
    seg = '<div class="seg">' + ''.join(pills) + '</div>'
    srch = ''
    if search is not None:
        srch = (f'<div class="srch"{N(nn(8), "tr", "add")}>' + mr('search', 20, 'color:var(--onv)') + (f'<span>{search}</span>' if search else '<span style="color:var(--onv)">按主播名筛选</span>')
                + '<span class="x">' + mr('close', 18) + '</span></div>')
    now = (f'<div class="now"{N(nn(7), "tl", "add")}>' + mr('graphic_eq', 16, 'color:var(--primary)') + f'<b>正在观看</b><span>{CURRENT[0]} · {CURRENT[3]}</span></div>')
    if rooms is None:
        rooms = {'onair': ROOMS, 'source': SOURCE, 'history': HISTORY, 'replays': REPLAYS}[group]
    chrome = 132 + (54 if search is not None else 0)
    gh = h - chrome
    if state == 'empty':
        body = ('<div class="empty">' + mr('live_tv') + '<div>关注的主播现在都没开播</div><div style="font-size:12px">看看观看记录，或者点刷新</div></div>')
    elif state == 'nomatch':
        body = f'<div class="empty">' + mr('search_off') + f'<div>没有名字包含“{search}”的主播</div></div>'
    elif state == 'error':
        body = '<div class="empty">' + mr('error_outline') + '<div>列表读取失败</div><span class="ob">重试</span></div>'
    elif layout == 'grid':
        cols = new_columns(w)
        k = new_card_height(w, gh, cols)
        body = (f'<div class="gr" style="grid-template-columns:repeat({cols},1fr);grid-auto-rows:{k:.1f}px">'
                + ''.join(card(r, mixed, nn(1) if i == 0 else None, history=group == 'history') for i, r in enumerate(rooms)) + '</div>')
    else:
        body = '<div class="ls">' + ''.join(row(r, nn(1) if i == 0 else None) for i, r in enumerate(rooms)) + '</div>'
    return head + seg + srch + now + body


def v4_portrait_page(layout='grid', n=True, group='onair', **kw):
    top = 36 + 56 + 221
    inner = panel(393, 852 - top - 16, layout=layout, n=n, group=group, **kw)
    under = f'<div class="under sp" style="top:{top}px;padding-bottom:16px">{inner}</div>'
    return page(393, 852, 3, v4_room(under, n=10 if n else None))


def v4_portrait_fullscreen_page():
    h = 852 * .6
    inner = panel(393, h - 16, n=False)
    sheet = f'<div class="under sp" style="height:{h:.0f}px;padding-bottom:16px;border-radius:16px 16px 0 0">{inner}</div>'
    top = ('<div class="vtop" style="height:120px;flex-direction:column;align-items:stretch;padding-top:40px"><div style="display:flex;align-items:center">'
           + ib(mi('arrow_back'), cls='ib vic') + '<div class="title" style="padding-top:0">晚风 · 深夜电台</div>'
           + '<div class="fol" style="background:rgba(255,255,255,.18);color:#fff">' + rx('eb7b', 16) + '已关注</div>'
           + '<div class="ib"><span class="ring" style="border-color:#fff"><i></i></span></div>' + ib(rx('ea42'), cls='ib vic') + '</div>'
           '<div style="display:flex;align-items:center;padding-left:14px"><div class="time">21:36</div><div class="bat" style="margin-left:8px">76</div><div style="flex:1"></div>'
           + ib(mr('swap_horiz'), cls='ib vic') + ib(rx('ee05', 21), cls='ib vic') + ib(rx('f235'), cls='ib vic') + ib(ci('e806'), cls='ib vic') + '</div></div>')
    body = (f'<div style="position:absolute;inset:0;background:url(.cache/img/319.jpg) center/cover"></div>{top}' + sheet + SYN + GEST)
    return page(393, 852, 3, body, extra='.ph{background:#000}')


def v4_portrait_stream_page():
    """U.2b: a portrait stream under the three-stop panel, at its middle stop."""
    area = 852 - 36 - 56
    middle = area * .44
    inner = panel(393, middle, n=False, refresh='刚刚')
    sheet = (f'<div class="under sp" style="height:{middle:.0f}px;border-radius:16px 16px 0 0">{inner}</div>')
    body = (STATUS + v4_appbar() + '<div style="position:relative;flex:1;background:url(.cache/img/319.jpg) center/cover">'
            '<div class="vtop"><div class="title">' + TITLE + '</div></div></div>' + sheet + SYN + GEST)
    return page(393, 852, 3, body)


def v4_landscape_page(layout='grid', n=False, group='onair', **kw):
    inner = panel(360, 393, layout=layout, n=n, group=group, **kw)
    side = f'<div class="side sp" style="border-radius:16px 0 0 16px">{inner}</div>'
    body = SYN + v4_fs_bars() + side
    return page(852, 393, 2, body, frame='fs', extra=FS_EXTRA)


def v4_narrow_page():
    inner = panel(360, 360, n=False)
    side = f'<div class="side sp" style="border-radius:16px 0 0 16px">{inner}</div>'
    body = SYN + v4_fs_bars() + side
    return page(740, 360, 2, body, frame='fs', extra=FS_EXTRA)


def v4_tablet_page():
    w, h = 1280, 800
    hdr = ('<div class="appbar"><div class="back">' + mi('arrow_back') + '</div><span class="av" style="background-image:url(.cache/img/65.jpg)"></span>'
           '<div class="tt"><div class="n">晚风</div><div class="s">哔哩哔哩 · 唱见电台</div></div>'
           '<div class="fol on">' + rx('eb7b') + '已关注</div><div class="recbtn"><span class="ring"><i></i></span></div>' + ib(rx('ea42')) + '<div style="width:4px"></div></div>')
    stage = ('<div style="flex:1;position:relative;background:#000;display:flex;align-items:center;overflow:hidden"><div style="width:100%;aspect-ratio:16/9;background:#000 url(.cache/img/158.jpg) center 55%/cover"></div>'
             '<div class="vtop"><div class="title">' + TITLE + '</div>' + ib(rx('ee05', 21), cls='ib vic') + ib(rx('f235'), cls='ib vic') + ib(ci('e806'), cls='ib vic') + '</div>'
             '<div class="vbot">' + ib(mr('pause', 28), cls='ib vic') + ib(mr('refresh'), cls='ib vic') + ib('<span class="dmk open"></span>', cls='ib vic') + ib('<span class="dmk set"></span>', cls='ib vic')
             + '<div style="flex:1"></div>' + ib(mr('screen_rotation_alt', 21), cls='ib vic') + ib(mr('vertical_split', 24), cls='ib vic') + ib(mr('fullscreen', 26), cls='ib vic') + '</div></div>')
    inner = panel(360, h - 36 - 56, n=False, refresh='刚刚')
    right = f'<div class="sp" style="width:400px;border-left:1px solid var(--ov);position:relative"><div class="sp" style="position:absolute;top:0;right:0;bottom:0;width:360px;box-shadow:-6px 0 20px rgba(0,0,0,.18)">{inner}</div></div>'
    body = STATUS + hdr + f'<div style="flex:1;display:flex;min-height:0">{stage}{right}</div>'
    return page(w, h, 1.5, body, frame='win', extra='.win{display:flex;flex-direction:column}')


def v4_states_page():
    """Five panel states side by side, each 360 × 520."""
    w, h = 360, 520
    cells = [
        ('关注在播是空的', panel(w, h, group='onair', source=False, state='empty', refresh='刚刚')),
        ('观看记录：未开播压暗', panel(w, h, group='history', source=False)),
        ('按主播名筛选', panel(w, h, group='onair', source=False, search='星', rooms=[ROOMS[0]])),
        ('筛选没有结果', panel(w, h, group='onair', source=False, search='阿狸', state='nomatch')),
        ('刷新失败（另有提示条）', panel(w, h, group='onair', source=False, refresh='刷新失败')),
        ('读取失败', panel(w, h, group='history', source=False, state='error')),
    ]
    o = ['<div style="display:flex;flex-wrap:wrap;gap:24px;padding:24px;background:var(--sch)">']
    for cap, inner in cells:
        o.append(f'<div><div style="font-size:15px;font-weight:600;margin:0 0 8px 4px">{cap}</div>'
                 f'<div class="sp" style="width:{w}px;height:{h}px;border-radius:16px;box-shadow:0 2px 10px rgba(0,0,0,.12)">{inner}</div></div>')
    o.append('</div>')
    return page(1176, 1220, 1.5, ''.join(o), frame='win', extra='.win{height:auto}')


def count_page():
    """v3's cards and the new ones in the same box, counted."""
    def box(title, w, h, html, label):
        return (f'<div><div style="font-size:15px;font-weight:600;margin:0 0 8px 4px">{title}</div><div style="position:relative;width:{w}px;height:{h}px;'
                f'border-radius:16px;overflow:hidden;box-shadow:0 2px 10px rgba(0,0,0,.12);display:flex;flex-direction:column;background:var(--sch)">{html}'
                f'<span class="cnt" style="right:10px;bottom:10px">{label}</span></div></div>')

    def v3box(w, h):
        cols = v3_columns(w)
        g = h - V3_CHROME
        k = v3_card_height(w, g, cols)
        full, half = visible(g, k, cols)
        return (v3_dialog_html(0, 0, w, h, ROOMS).replace('position:absolute', 'position:relative').replace('left:0px;top:0px;', ''), full, half)

    def newbox(w, h, layout='grid'):
        cols = new_columns(w)
        g = h - NEW_CHROME
        k = new_card_height(w, g, cols)
        full, half = visible(g, k, cols) if layout == 'grid' else visible(g, NEW_ROW, 1, pad=2, gap=0)
        return (f'<div class="sp" style="height:{h}px">' + panel(w, h, layout=layout, source=False) + '</div>', full, half)

    def lab(full, half):
        return f'完整 {full} 张' + (f' + 露出一半以上 {half - full} 张' if half > full else '')

    rows = []
    # Landscape phone: v3's dialog 418 wide; the new panel 360. Then both at 360.
    a, f1, h1 = v3box(418, 377)
    b, f2, h2 = newbox(360, 393)
    c, f3, h3 = v3box(360, 393)
    rows.append(('横屏手机 852×393', [box('v3：对话框 418×377', 418, 377, a, lab(f1, h1)), box('v3 的卡片放进 360×393', 360, 393, c, lab(f3, h3)),
                                      box('新设计：网格 360×393', 360, 393, b, lab(f2, h2))]))
    # Portrait phone: v3's dialog 280 wide (one column); the new panel 393 wide under the picture.
    a, f1, h1 = v3box(280, 720)
    b, f2, h2 = newbox(393, 523)
    c, f3, h3 = v3box(393, 523)
    rows.append(('竖屏手机 393×852', [box('v3：对话框 280×720（1 列）', 280, 720, a, lab(f1, h1)), box('v3 的卡片放进 393×523', 393, 523, c, lab(f3, h3)),
                                      box('新设计：网格 393×523（画面下方）', 393, 523, b, lab(f2, h2))]))
    o = ['<div style="padding:24px;background:var(--surface)">']
    for title, boxes in rows:
        o.append(f'<div style="font-size:18px;font-weight:700;margin:8px 0 12px">{title}</div><div style="display:flex;gap:24px;align-items:flex-start;margin-bottom:28px">' + ''.join(boxes) + '</div>')
    o.append('</div>')
    return page(1240, 1400, 1.5, ''.join(o), frame='win', extra='.win{height:auto}')


OUT = {
    'v3-portrait': v3_portrait_page(), 'v3-landscape': v3_landscape_page(),
    'now-portrait': now_portrait_page(), 'now-menu-landscape': now_menu_page(),
    'v4-portrait': v4_portrait_page(), 'v4-portrait-list': v4_portrait_page('list', n=False),
    'v4-portrait-source': v4_portrait_page(n=False, group='source', source=True, mixed=False),
    'v4-landscape': v4_landscape_page(n=True), 'v4-landscape-list': v4_landscape_page('list'),
    'v4-narrow': v4_narrow_page(), 'v4-portrait-fullscreen': v4_portrait_fullscreen_page(),
    'v4-portrait-stream': v4_portrait_stream_page(), 'v4-tablet': v4_tablet_page(),
    'v4-states': v4_states_page(), 'v4-menu-landscape': new_menu_page(), 'count': count_page(),
}

if __name__ == '__main__':
    if '--counts' in sys.argv:
        print('| 布局 | v3 对话框 | v3 列 | v3 完整/过半 | 新面板 | 新 列 | 新 网格 完整/过半 | 新 列表 完整/过半 | v3 卡高 | 新 卡高 |')
        for r in counts():
            name, d3, c3, v3, pn, cn, vn, ln, k3, kn = r
            print(f'| {name} | {d3} | {c3} | {v3[0]}/{v3[1]} | {pn} | {cn} | {vn[0]}/{vn[1]} | {ln[0]}/{ln[1]} | {k3:.0f} | {kn:.0f} |')
        sys.exit(0)
    for name, html in OUT.items():
        with open(os.path.join(HERE, name + '.html'), 'w', encoding='utf-8') as f:
            f.write(html)
    print(len(OUT), 'pages')
