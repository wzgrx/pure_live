"""Shared pieces for the U.4a / U.4b / U.4c mockups (room card, home shell,
tabs, grids). U.4b and U.4c import this file from ../../U.4a/src.

v3 sources (tag v3.2.11, ~/ref/v3ref/lib):
  common/widgets/room_card.dart          card :1053-1229, badges :858-908, :1312-1411
  common/widgets/room_card_layout.dart   caption heights
  common/services/settings/room_card_settings_controller.dart   presets :41-73
  common/widgets/common_avatar.dart      avatar 34 (dense) / 40
  modules/home/mobile_view.dart, tablet_view.dart   bottom bar / rail
  common/base/desktop_components.dart    pagination bar
  common/style/theme.dart                tab bar, card, dialog themes
Colours are ColorScheme.fromSeed(Colors.blue) (kit/kit.css); v3's own
hard-coded white / grey[700] / grey[900] are kept on the v3 side.
"""
import os

# ---------- icons ----------
mr = lambda n, s=24: f'<span class="mr" style="font-size:{s}px">{n}</span>'
mi = lambda n, s=24: f'<span class="mi" style="font-size:{s}px">{n}</span>'
rx = lambda c, s=24: f'<span class="rx" style="font-size:{s}px">&#x{c};</span>'
ci = lambda c, s=24: f'<span class="ci" style="font-size:{s}px">&#x{c};</span>'
RX = {  # remixicon 4.9.3 code points used here
    'heart_3_line': 'ee0b', 'heart_3_fill': 'ee0a', 'fire_line': 'ed33', 'fire_fill': 'ed32',
    'apps_2_line': 'ea42', 'apps_2_fill': 'ea41', 'download_2_line': 'ec54', 'download_2_fill': 'ec53',
    'menu_search_line': 'f3d0', 'search_line': 'f0d1', 'link': 'eeb2', 'layout_grid_line': 'ee90',
    'share_forward_line': 'f0fd', 'price_tag_3_line': 'f023', 'add_circle_line': 'ea11', 'delete_bin_line': 'ec2a',
    'arrow_down_s_line': 'ea4e', 'arrow_right_s_line': 'ea6e', 'check_line': 'eb7b', 'add_line': 'ea13',
    'refresh_line': 'f064', 'arrow_up_line': 'ea76', 'settings_5_line': 'f0ea',
}
r = lambda name, s=24: rx(RX[name], s)


def at(n=None, tag=None, pos=None):
    """data-n attributes for the numbered picture."""
    return ((f' data-n="{n}"' if n else '') + (f' data-tag="{tag}"' if tag and n else '')
            + (f' data-at="{pos}"' if pos and n else ''))


# ---------- sample rooms (fictional; pictures are picsum samples) ----------
# id, platform, title, nick, cover, audience kind, figure
ROOMS = [
    ('a', 'bilibili', '深夜电台 · 点歌接龙到天亮，今晚聊聊你的故事', '晚风', 1, 'whatshot', '84.7万'),
    ('b', 'bilibili', '【原神】深渊满星挑战，萌新也能看懂的配队思路', '一只小熊', 111, 'whatshot', '12.3万'),
    ('c', 'bilibili', '手绘板绘练习｜今天画一只橘猫', '清欢画画', 133, 'whatshot', '3.6万'),
    ('d', 'bilibili', '周末露营直播，带你看山里的星空', '山野', 169, 'whatshot', '2.1万'),
    ('e', 'bilibili', '英语口语陪练，零基础也能开口', 'Aki老师', 183, 'whatshot', '1.8万'),
    ('f', 'bilibili', '复古游戏通关：魂斗罗一命通关挑战', '像素老王', 206, 'whatshot', '9812'),
    ('g', 'bilibili', '古筝弹唱｜点歌请发弹幕', '弦月', 219, 'whatshot', '5.2万'),
    ('h', 'bilibili', '城市夜跑直播，今天挑战十公里', '风吹麦浪', 225, 'whatshot', '7301'),
    ('i', 'douyu', '英雄联盟 钻石冲大师 今晚不上分不下播', '夜猫子', 237, 'whatshot', '46.2万'),
    ('j', 'huya', '王者荣耀巅峰赛 打野思路教学', '星河长明', 250, 'whatshot', '31.5万'),
    ('k', 'douyin', '凌晨的夜市小吃探店', '橘子汽水', 287, 'people_alt', '3415'),
    ('l', 'bilibili', '读书会：一起读《额尔古纳河右岸》', '月亮邮差', 292, 'whatshot', '6188'),
    ('m', 'douyu', '主机游戏 艾尔登法环 全收集', '不吃香菜', 304, 'whatshot', '8.8万'),
    ('n', 'huya', '户外钓鱼 水库夜钓', '路过的风', 319, 'whatshot', '2.4万'),
    ('o', 'bilibili', '编程直播：从零写一个小游戏', '小林同学', 338, 'whatshot', '4521'),
    ('p', 'douyin', '街头弹唱 听歌的进来', '阿远', 342, 'people_alt', '1.1万'),
    ('q', 'bilibili', '晨练八段锦 跟着做二十分钟', '早起的鸟', 360, 'whatshot', '3307'),
    ('s', 'huya', '象棋残局 每日一题', '楚河汉界', 367, 'whatshot', '1.6万'),
    ('t', 'bilibili', '吉他教学：一周学会扫弦', '六弦琴', 250, 'whatshot', '2.7万'),
    ('u', 'bilibili', '深夜自习室 陪你学习两小时', '番茄钟', 304, 'whatshot', '1.3万'),
    ('v', 'bilibili', '海边日落 慢直播', '潮汐', 319, 'whatshot', '8436'),
    ('w', 'bilibili', '猫咖日常：七只猫的下午', '喵星人', 367, 'whatshot', '3.9万'),
]
R = {x[0]: x for x in ROOMS}
SITE = {'bilibili': '哔哩哔哩', 'douyu': '斗鱼', 'huya': '虎牙', 'douyin': '抖音', 'kuaishou': '快手', 'cc': '网易CC'}
LOGO = lambda p: f'../../../packages/live_ui/assets/platforms/{p}.png'
cover = lambda img: f'.cache/img/{img}.jpg'
# Avatars: the one avatar sample plus crops of other samples.
AV = {'a': '65', 'b': '111', 'c': '133', 'd': '169', 'e': '183', 'f': '206', 'g': '219', 'h': '225', 'i': '237',
      'j': '250', 'k': '287', 'l': '292', 'm': '304', 'n': '319', 'o': '338', 'p': '342', 'q': '360', 's': '367', 't': '250', 'u': '304', 'v': '319', 'w': '367'}
avatar = lambda rid: f'.cache/img/{AV[rid]}.jpg'

# v3 popular platform tabs (Sites.supportSites order, zh names; hotAreasList default = all)
POPULAR_SITES = ['哔哩哔哩', '斗鱼', '虎牙', '抖音', '快手', '网易CC', 'Twitch', 'Soop', 'YY', 'AcFun 直播', 'Picarto',
                 'TwitCasting', '猫耳 FM', '映客', '克拉克拉', '小红书', 'niconico', '微博直播', 'SHOWROOM', 'CHZZK', 'LiveMe',
                 'TikTok LIVE', 'YouTube Live', 'Bigo Live', 'PandaTV', 'FC2 Live', 'Steam Broadcasts', '京东直播', '酷狗直播',
                 '百度直播', '六间房直播', 'LOOK 直播', '17LIVE', '网络']
POPULAR_IDS = ['bilibili', 'douyu', 'huya', 'douyin', 'kuaishou', 'cc', 'twitch', 'soop', 'yy', 'acfun', 'picarto',
               'twitcasting', 'missevan', 'inke', 'kilakila', 'xiaohongshu', 'niconico', 'weibo', 'showroom', 'chzzk', 'liveme',
               'tiktok', 'youtube', 'bigo', 'pandalive', 'fc2live', 'steambroadcast', 'jdlive', 'kugoulive', 'baidulive', 'sixroom',
               'looklive', '17live', 'iptv']

CSS = '''
.col{display:flex;flex-direction:column}
.ph.col,.win.col,.fs.col{display:flex;flex-direction:column}
.fill{flex:1;min-height:0;position:relative;overflow:hidden}
.row{display:flex;align-items:center}
/* ---- home shell (v3, U.3 decides the new one) ---- */
.nav{height:100px;background:var(--scc);display:flex;padding-top:12px;flex:none}
.nav .d{flex:1;display:flex;flex-direction:column;align-items:center;gap:4px;font-size:12px;color:var(--onv)}
.nav .d i{width:64px;height:32px;border-radius:16px;display:grid;place-items:center;font-style:normal}
.nav .d.on{color:var(--on);font-weight:600}.nav .d.on i{background:var(--sc);color:var(--osc)}
.rail{width:80px;flex:none;background:var(--surface);display:flex;flex-direction:column;align-items:center;padding-top:8px;overflow:hidden;color:var(--onv)}
.rail .lead{width:48px;height:48px;display:grid;place-items:center;margin:0 0 12px;flex:none}.rail .lead:first-child{margin-top:12px}
.rail .gap{height:8px;flex:none}
.rail .d{display:flex;flex-direction:column;align-items:center;gap:4px;font-size:12px;height:64px;justify-content:center;flex:none;width:80px}
.rail .d i{width:56px;height:32px;border-radius:16px;display:grid;place-items:center;font-style:normal}
.rail .d.on{color:var(--on);font-weight:600}.rail .d.on i{background:var(--sc);color:var(--osc)}
.vdiv{width:1px;background:var(--ov);flex:none}
.hbar{height:56px;display:flex;align-items:center;flex:none;background:var(--surface)}
.hbar .lead{width:56px;height:56px;display:grid;place-items:center;flex:none;color:var(--on)}
.hbar .act{width:48px;height:48px;display:grid;place-items:center;flex:none;margin-right:4px;color:var(--on)}
.hbar .mid{flex:1;min-width:0;height:56px;display:flex;align-items:center;justify-content:center;padding:0 16px;overflow:hidden}
/* ---- tab bars (v3 theme: 15, selected primary 600, unselected onSurfaceVariant 80%) ---- */
.tb{display:flex;height:46px;align-items:stretch;flex:none;white-space:nowrap;overflow:hidden;max-width:100%;min-width:0}
.tb.start,.tb.fillw{width:100%}
.tb.start{justify-content:flex-start}.tb.center{justify-content:center}
.tb .t{padding:0 16px;display:flex;align-items:center;font-size:15px;color:rgba(67,71,78,.8);position:relative;flex:none}
.tb.fillw .t{flex:1;justify-content:center;padding:0 4px}
.tb .t.on{color:var(--primary);font-weight:600}
.tb .t.on b{font-weight:600;position:relative;display:inline-flex;align-items:center;height:100%}
.tb .t.on b::after{content:'';position:absolute;left:0;right:0;bottom:0;height:3px;border-radius:3px 3px 0 0;background:var(--primary)}
.tb .t b{font-weight:inherit}
.tb .cnt{font-size:12px;font-weight:500;margin-left:4px;color:var(--onv);font-feature-settings:'tnum'}
.tb .t.on .cnt{color:var(--primary)}
[data-theme=dark] .tb .t{color:rgba(195,199,207,.8)}
/* ---- grids ---- */
.grid{display:grid;align-content:start}
/* ---- v3 card (room_card.dart) ---- */
.c3{background:#fff;border-radius:20px;overflow:hidden;position:relative}
[data-theme=dark] .c3{background:#212121}
.cv{position:relative;aspect-ratio:16/9;border-radius:20px;background:#F5F5F5 center/cover;overflow:hidden}
.cap{display:flex;align-items:center;gap:8px;padding:0 10px}
.cap .av{width:34px;height:34px;border-radius:17px;background:center/cover;flex:none}
.cap .tx{flex:1;min-width:0}
.cap .t{font-size:13px;font-weight:600;line-height:18px;color:rgba(0,0,0,.87);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.cap .s{font-size:12px;font-weight:500;line-height:17px;color:#616161;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.big .cap{gap:12px;padding:0 12px}.big .cap .av{width:40px;height:40px;border-radius:20px}
.big .cap .t{font-size:15px;line-height:21px}.big .cap .s{font-size:13px;line-height:18px}
.aud3{position:absolute;right:8px;bottom:8px;display:flex;align-items:center;gap:4px;padding:4px 6px;border-radius:10px;background:rgba(0,0,0,.48);color:#fff;font-size:11px;font-weight:700;line-height:14px}
.aud3 .mr{font-size:14px!important}
.big .aud3{padding:5px 8px;border-radius:12px;font-size:12px}.big .aud3 .mr{font-size:16px!important}
.rep3{position:absolute;right:8px;top:8px;display:flex;align-items:center;gap:4px;padding:4px 10px;border-radius:14px;background:var(--primary);color:#fff;font-size:12px;font-weight:600;line-height:17px}
.rep3 .mr{font-size:16px!important}
.plat3{position:absolute;left:8px;top:8px;padding:3px 6px;border-radius:8px;background:rgba(0,0,0,.58);color:#fff;font-size:10px;font-weight:700;line-height:14px}
.ptag3{flex:none;padding:4px 8px;border-radius:8px;background:#F5F5F5;color:#424242;font-size:12px;font-weight:600}
.del3{position:absolute;right:10px;top:10px;width:28px;height:28px;border-radius:14px;background:rgba(0,0,0,.6);color:#fff;display:grid;place-items:center}
.ph0{position:absolute;inset:0;display:grid;place-items:center;color:rgba(0,0,0,.12)}
.err0{position:absolute;inset:0;display:grid;place-items:center}
.err0 i{width:32px;height:32px;border-radius:16px;background:rgba(225,226,232,.15);border:1px solid rgba(54,97,142,.05);display:grid;place-items:center;color:rgba(54,97,142,.6)}
.cmp3{display:flex;align-items:center;gap:8px;padding:8px;height:56px}
.cmp3 .av{width:34px;height:34px;border-radius:17px;background:center/cover;flex:none}
/* ---- new card ---- */
.c4{background:#fff;border-radius:20px;overflow:hidden;position:relative}
[data-theme=dark] .c4{background:var(--scc)}
.c4 .cap .t{color:var(--on)}.c4 .cap .s{color:var(--onv)}
.c4.hov{background:var(--sch)}
.c4.foc{box-shadow:0 0 0 3px var(--primary)}
.chipc{position:absolute;display:flex;align-items:center;gap:4px;height:22px;padding:0 7px;border-radius:11px;background:rgba(0,0,0,.55);color:#fff;font-size:12px;font-weight:600;line-height:1;white-space:nowrap}
.chipc .mr{font-size:14px!important}
.chipc.tl{left:8px;top:8px;padding-left:3px}.chipc.tr{right:8px;top:8px}.chipc.br{right:8px;bottom:8px}.chipc.bl{left:8px;bottom:8px}
.chipc img{width:16px;height:16px;border-radius:4px}
.chipc.pri{background:var(--primary);color:var(--onPrimary)}
.chipc .n{font-feature-settings:'tnum'}
.dim{position:absolute;inset:0;background:rgba(0,0,0,.38)}
.sk,.cap .av.sk{background:var(--sch)}
.c4.skel .cv{background:var(--sch)}
.bar{height:10px;border-radius:5px;background:var(--sch)}
.row4{display:flex;align-items:center;gap:12px;padding:0 12px;height:64px;background:#fff;border-radius:12px;position:relative}
[data-theme=dark] .row4{background:var(--scc)}
.row4 .av{width:40px;height:40px;border-radius:20px;background:center/cover;flex:none;position:relative}
.row4 .av img{position:absolute;right:-3px;bottom:-3px;width:18px;height:18px;border-radius:5px;border:2px solid #fff}
.row4 .tx{flex:1;min-width:0}
.row4 .t{font-size:15px;font-weight:600;line-height:21px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.row4 .s{font-size:13px;line-height:18px;color:var(--onv);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.row4 .st{flex:none;font-size:12px;color:var(--onv);padding:3px 8px;border-radius:10px;background:var(--scc)}
.tipx{position:absolute;z-index:30;background:rgba(25,28,32,.92);color:#fff;font-size:12px;line-height:1.4;padding:6px 8px;border-radius:4px;max-width:260px}
/* ---- v3 desktop pagination bar ---- */
.pager{height:68px;flex:none;display:flex;align-items:center;justify-content:center;border-top:1px solid rgba(115,119,127,.15);background:var(--surface);font-size:13px;color:var(--on);white-space:nowrap}
.pager .ob{display:flex;align-items:center;gap:6px;height:36px;padding:0 12px;border:1px solid var(--outline);border-radius:6px;color:var(--primary);font-size:14px;font-weight:500}
.pager .tbn{display:flex;align-items:center;gap:6px;padding:0 12px;height:40px;color:var(--primary);font-size:14px;font-weight:500}
.pager .tbn.dis{color:rgba(25,28,32,.38)}
.pager .pn{min-width:48px;height:48px;margin:0 3px;border-radius:6px;display:grid;place-items:center;border:1px solid rgba(115,119,127,.1);font-size:13px}
.pager .pn.on{background:var(--primary);color:var(--onPrimary);font-weight:700;border-color:var(--primary)}
.pager .mut{color:#6B6E75}
.pager .sel{min-width:48px;height:48px;padding:0 6px 0 10px;border:1px solid rgba(115,119,127,.2);border-radius:6px;display:flex;align-items:center;gap:4px}
.pager .fld{width:50px;height:36px;border:1px solid var(--outline);border-radius:6px;margin:0 6px}
/* ---- floating to-top buttons (v3 mini FAB) ---- */
.fab{position:absolute;right:16px;width:40px;height:40px;border-radius:12px;background:var(--surface);box-shadow:0 2px 6px rgba(0,0,0,.25);display:grid;place-items:center;color:var(--opc);z-index:8}
/* ---- status views (AppStatusView) ---- */
.stv{display:flex;flex-direction:column;align-items:center;text-align:center;padding:0 28px}
.stv .ic{width:86px;height:86px;border-radius:43px;background:rgba(225,226,232,.15);border:1px solid rgba(54,97,142,.05);display:grid;place-items:center;color:rgba(54,97,142,.6)}
.stv .h{margin-top:20px;font-size:15px;font-weight:600}
.stv .p{margin-top:6px;font-size:13px;line-height:1.5;color:#6B6E75;max-width:320px}
.stv .b{margin-top:16px;display:flex;align-items:center;gap:8px;height:40px;padding:0 12px;color:var(--primary);font-size:13px;font-weight:500}
.stv4 .ic{background:var(--scc);border:0;color:var(--primary)}
.stv4 .p{color:var(--onv)}
.stv4 .b.filled{background:var(--primary);color:var(--onPrimary);border-radius:20px;padding:0 20px}
/* ---- tag chips (favorite_page.dart FavoriteTagStrip) ---- */
.tags3{height:60px;display:flex;align-items:center;gap:6px;padding:0 16px;flex:none;overflow:hidden;white-space:nowrap}
.tags3 .ch{height:32px;padding:0 16px;border-radius:10px;display:flex;align-items:center;font-size:12px;color:var(--onv);background:rgba(225,226,232,.15);box-shadow:inset 0 0 0 .5px rgba(115,119,127,.04);flex:none}
.tags3 .ch.on{background:var(--primary);color:var(--onPrimary);font-weight:700}
.tags4{height:48px;display:flex;align-items:center;gap:8px;padding:0 12px;flex:none;overflow:hidden;white-space:nowrap}
.tags4 .ch{height:32px;padding:0 12px;border-radius:8px;display:flex;align-items:center;gap:4px;font-size:13px;color:var(--onv);box-shadow:inset 0 0 0 1px var(--ov);flex:none}
.tags4 .ch.on{background:var(--sc);color:var(--osc);font-weight:600;box-shadow:none}
.tags4 .ch .cnt{font-size:12px;font-feature-settings:'tnum';opacity:.8}
/* ---- notices ---- */
.ntc{padding:8px 12px 4px;font-size:12px;line-height:1.45;color:var(--on)}
.cell{margin:12px 16px 4px;padding:10px 14px 4px;border-radius:12px;background:rgba(209,228,255,.25);border:1px solid rgba(54,97,142,.15)}
.cell .row{align-items:flex-start;gap:12px}.cell .ico{width:34px;height:34px;border-radius:17px;background:rgba(54,97,142,.1);display:grid;place-items:center;color:var(--primary);flex:none}
.cell .m{font-size:13px;font-weight:500;color:var(--onv);line-height:1.3;padding-top:2px}
.cell .nb{text-align:right;font-size:13px;font-weight:700;color:var(--primary);padding:10px 4px 6px}
.note4{display:flex;align-items:flex-start;gap:8px;margin:6px 12px 2px;padding:8px 10px;border-radius:12px;background:var(--scl);font-size:12px;line-height:1.5;color:var(--onv)}
.note4 .mr{font-size:16px;color:var(--primary);margin-top:1px}
.prog{position:absolute;left:0;right:0;top:0;height:3px;background:linear-gradient(90deg,var(--primary) 0 38%,transparent 38%);z-index:6}
'''


def page(w, h, scale, body, frame='ph', extra_css='', crop=False, syn=True, style=''):
    """A mockup page; frame is the kit's .ph (phone), .win (window) or .fs."""
    size = f'{w}x{h}@{scale}' + (' crop' if crop else '')
    label = '<div class="syn">示意图片</div>' if syn else ''
    dims = f'--w:{w}px;--h:{h}px;' if frame != 'ph' else ''
    return (f'<!doctype html><html><head><meta charset="utf-8"><meta name="mock-size" content="{size}">'
            f'<link rel="stylesheet" href="kit/kit.css"><style>{CSS}{extra_css}</style></head>'
            f'<body><div class="{frame} col" style="{dims}{style}">{body}{label}</div></body></html>')


def write(here, pages):
    for name, html in pages.items():
        open(os.path.join(here, name + '.html'), 'w', encoding='utf-8').write(html)
    print(len(pages), 'pages')


# ---------- shell ----------
STATUS = '<div class="status" style="flex:none"><span>21:36</span><span class="r"><span class="mi">signal_cellular_alt</span><span class="mi">wifi</span><span class="mi">battery_full</span></span></div>'
STATUS_LAND = '<div class="status" style="flex:none;height:24px;font-size:12px;padding:0 16px"><span>21:36</span><span class="r"><span class="mi" style="font-size:14px">wifi</span><span class="mi" style="font-size:14px">battery_full</span></span></div>'
NAV_ITEMS = [('关注', 'heart_3'), ('热门', 'fire'), ('分区', 'apps_2'), ('录制中心', 'download_2')]


def navbar(sel):
    """v3 HomeMobileView NavigationBar (mobile_view.dart:21-80)."""
    out = ''
    for label, icon in NAV_ITEMS:
        on = label == sel
        out += f'<div class="d{" on" if on else ""}"><i>{r(icon + ("_fill" if on else "_line"))}</i>{label}</div>'
    return f'<div class="nav">{out}<div class="gesture"></div></div>'


def rail(sel, record=True):
    """v3 HomeTabletView NavigationRail (tablet_view.dart:85-150): menu, multiview,
    toolbox, search, record, then the destinations (record is not one on wide)."""
    lead = (f'<div class="lead">{mr("menu")}</div>' + f'<div class="lead">{r("layout_grid_line")}</div>'
            + f'<div class="lead">{r("link")}</div>' + f'<div class="lead">{ci("e804")}</div>'
            + (f'<div class="lead">{r("download_2_line")}</div>' if record else ''))
    dest = ''
    for label, icon in NAV_ITEMS[:3]:
        on = label == sel
        dest += f'<div class="d{" on" if on else ""}"><i>{r(icon + ("_fill" if on else "_line"))}</i>{label}</div>'
    return f'<div class="rail">{lead}<div class="gap"></div>{dest}</div><div class="vdiv"></div>'


def home_bar(mid_html, phone=True):
    """v3 home page AppBar: menu and search menu only when Get.width <= 680."""
    lead = f'<div class="lead">{mr("menu")}</div>' if phone else ''
    act = f'<div class="act">{r("menu_search_line")}</div>' if phone else ''
    return f'<div class="hbar">{lead}<div class="mid">{mid_html}</div>{act}</div>'


def tabs(labels, sel=0, mode='start', counts=None, extra_attr=None):
    """Tab bar: mode start (scrollable, overflowing), center, or fillw (fixed, equal)."""
    out = ''
    for i, label in enumerate(labels):
        cnt = f'<span class="cnt">{counts[i]}</span>' if counts and counts[i] is not None else ''
        a = extra_attr(i) if extra_attr else ''
        if i == sel:
            out += f'<div class="t on"{a}><b>{label}{cnt}</b></div>'
        else:
            out += f'<div class="t"{a}>{label}{cnt}</div>'
    return f'<div class="tb {mode}">{out}</div>'


def grid(items, cols, pad=6, gap=6, extra=''):
    return (f'<div class="grid" style="grid-template-columns:repeat({cols},minmax(0,1fr));gap:{gap}px;padding:{pad}px;{extra}">'
            + ''.join(items) + '</div>')


# ---------- v3 card ----------
def _aud3(rm):
    return f'<div class="aud3">{mr(rm[5])}<span>{rm[6]}</span></div>'


def card3(rid, state='live', big=False, cap_h=None, plat='hidden', delete=False, cover_state=None):
    """v3 RoomCard, cover layout. state: live | replay | verify | unknown | offline.
    plat: hidden | always (cover badge) | auto (caption tag, non-dense and >= 280 wide)."""
    rm = R[rid]
    if cover_state == 'loading':
        cv = f'<div class="cv"><div class="ph0">{mr("live_tv")}</div>'
    elif cover_state == 'error':
        cv = f'<div class="cv"><div class="err0"><i>{mr("wifi_off", 16)}</i></div>'
    else:
        cv = f'<div class="cv" style="background-image:url({cover(rm[4])})">'
    if plat == 'always':
        cv += f'<div class="plat3">{rm[1].upper()}</div>'
    if state == 'replay':
        cv += f'<div class="rep3" style="{"right:44px" if delete else ""}">{mr("videocam")}录播</div>'
    if state == 'verify':
        cv += f'<div class="aud3">{mr("sync")}<span>正在核验</span></div>'
    elif state == 'unknown':
        cv += f'<div class="aud3">{mr("sync")}<span>状态待确认</span></div>'
    elif state == 'live':
        cv += _aud3(rm)
    if delete:
        cv += f'<div class="del3">{r("delete_bin_line", 16)}</div>'
    cv += '</div>'
    h = cap_h or (72 if big else 64)
    ptag = f'<span class="ptag3">{rm[1].upper()}</span>' if plat == 'auto' else ''
    cap = (f'<div class="cap" style="height:{h}px"><span class="av" style="background-image:url({avatar(rid)})"></span>'
           f'<div class="tx"><div class="t">{rm[2]}</div><div class="s">{rm[3]}</div></div>{ptag}</div>')
    return f'<div class="c3{" big" if big else ""}">{cv}{cap}</div>'


def compact3(rid, wide=False):
    """v3 _buildCompactLayout (简洁 preset): no cover; metrics only when >= 260 wide."""
    rm = R[rid]
    trail = f'<span class="aud3" style="position:static">{mr(rm[5])}<span>{rm[6]}</span></span>' if wide else ''
    return (f'<div class="c3" style="border-radius:12px"><div class="cmp3"><span class="av" style="background-image:url({avatar(rid)})"></span>'
            f'<div class="tx" style="flex:1;min-width:0"><div class="cap" style="padding:0"><div class="tx"><div class="t">{rm[2]}</div><div class="s">{rm[3]}</div></div></div></div>{trail}</div></div>')


# ---------- new card ----------
def card4(rid, state='live', plat=False, mark=None, hover=False, focus=False, n=None, tag=None, cap_h=64, nmap=None, cover_state=None):
    """New RoomCard. state: live | replay | verify | unknown | offline | skeleton.
    plat: platform chip (logo + name) on the cover, shown where the list mixes platforms.
    nmap: data-n for the parts {'card','plat','aud','rep','mark','off'}."""
    nmap = nmap or {}
    if state == 'skeleton':
        return ('<div class="c4 skel"><div class="cv"></div><div class="cap" style="height:64px"><span class="av sk"></span>'
                '<div class="tx"><div class="bar" style="width:86%"></div><div class="bar" style="width:46%;margin-top:8px"></div></div></div></div>')
    rm = R[rid]
    cv = (f'<div class="cv" style="background:var(--scc)"><div class="ph0" style="color:var(--outline)">{mr("live_tv")}</div>' if cover_state else f'<div class="cv" style="background-image:url({cover(rm[4])})">')
    if state == 'offline':
        cv += '<div class="dim"></div>'
    if plat:
        cv += f'<div class="chipc tl"{at(nmap.get("plat"), "add", "tl")}><img src="{LOGO(rm[1])}">{SITE.get(rm[1], rm[1])}</div>'
    if state == 'replay':
        cv += f'<div class="chipc tr pri"{at(nmap.get("rep"), "keep")}>{mr("videocam")}录播</div>'
    if mark:
        cv += f'<div class="chipc bl"{at(nmap.get("mark"), "add", "bl")}>{mr("lock")}{mark}</div>'
    if state == 'verify':
        cv += f'<div class="chipc br">{mr("sync")}正在核验</div>'
    elif state == 'unknown':
        cv += f'<div class="chipc br">{mr("sync")}状态待确认</div>'
    elif state == 'offline':
        cv += f'<div class="chipc br"{at(nmap.get("off"), "add", "br")}>未开播</div>'
    elif state == 'live':
        cv += f'<div class="chipc br"{at(nmap.get("aud"), "chg", "br")}>{mr(rm[5])}<span class="n">{rm[6]}</span></div>'
    cv += '</div>'
    cap = (f'<div class="cap" style="height:{cap_h}px"><span class="av" style="background-image:url({avatar(rid)})"></span>'
           f'<div class="tx"><div class="t">{rm[2]}</div><div class="s">{rm[3]}</div></div></div>')
    cls = 'c4' + (' hov' if hover else '') + (' foc' if focus else '')
    return f'<div class="{cls}"{at(n or nmap.get("card"), tag or "keep", "tl")}>{cv}{cap}</div>'


def row4(rid, n=None, tag=None, status='未开播'):
    """New compact row (the card's compact layout) for rooms that are not live (C-5)."""
    rm = R[rid]
    st = f'<span class="st">{status}</span>' if status else ''
    return (f'<div class="row4"{at(n, tag or "add", "tl")}><span class="av" style="background-image:url({avatar(rid)})"><img src="{LOGO(rm[1])}"></span>'
            f'<div class="tx"><div class="t">{rm[3]}</div><div class="s">{rm[2]}</div></div>{st}</div>')


# ---------- v3 desktop pagination bar (desktop_components.dart:44-185) ----------
def pager3(pages=(1, 2, 3), current=1, more=True, size=20, has_next=True):
    nodes = ''.join(f'<div class="pn{" on" if p == current else ""}">{p}</div>' for p in pages)
    if more:
        nodes += '<span class="mut" style="padding:0 4px">...</span>'
    return ('<div class="pager">'
            f'<div class="ob">{mr("refresh", 16)}刷新</div>'
            f'<div class="tbn dis">{mr("arrow_back_ios_new", 12)}上一页</div><div style="width:8px"></div>{nodes}<div style="width:8px"></div>'
            f'<div class="tbn{"" if has_next else " dis"}">下一页{mr("arrow_forward_ios", 12)}</div>'
            f'<span class="mut">每页: </span><div style="width:6px"></div><div class="sel">{size}{mr("arrow_drop_down", 18)}</div><div style="width:24px"></div>'
            '<span class="mut">跳转至</span><div class="fld"></div><span class="mut">页</span></div>')


def status3(icon_html, title, sub, btn=None):
    b = f'<div class="b">{mr("refresh", 18)}{btn}</div>' if btn else ''
    return f'<div class="stv"><div class="ic">{icon_html}</div><div class="h">{title}</div><div class="p">{sub}</div>{b}</div>'


def status4(icon_html, title, sub, btn=None, btn_icon='refresh', fill=False, n=None):
    b = f'<div class="b{" filled" if fill else ""}"{at(n, "chg")}>{mr(btn_icon, 18)}{btn}</div>' if btn else ''
    return f'<div class="stv stv4"><div class="ic">{icon_html}</div><div class="h">{title}</div><div class="p">{sub}</div>{b}</div>'


# ---------- columns ----------
def v3_cols(w):
    return 5 if w > 1280 else 4 if w > 960 else 3 if w > 640 else 2


def new_cols(window, w, pad=6, gap=6, min_w=None):
    """UI_PLAN 5.3: clamp(floor((W + gap) / (min + gap)), 2, 8)."""
    if min_w is None:
        min_w = 160 if window < 600 else 180 if window < 1200 else 200
    W = w - 2 * pad
    return max(2, min(8, (W + gap) // (min_w + gap)))


def card_w(w, cols, pad=6, gap=6):
    return (w - 2 * pad - gap * (cols - 1)) / cols


# ---------- popular page (U.4b; also the backdrop of U.4a's dialogs) ----------
POP_ROOMS = list('abcdefghloqtuvw')
SPINNER = ('<div style="position:absolute;inset:0;display:grid;place-items:center"><span style="width:24px;height:24px;border-radius:12px;'
           'background:conic-gradient(var(--primary),rgba(54,97,142,.1) 85%);-webkit-mask:radial-gradient(circle,transparent 8px,#000 8.5px)"></span></div>')


def popular3_body(cols, state='list', tab=0, n_rooms=10):
    if state == 'empty':
        return ('<div class="fill" style="display:grid;place-items:center">'
                + status3(r('fire_fill', 42), '未发现直播', '请点击上方按钮切换平台', '刷新') + '</div>')
    if state == 'loading':
        return f'<div class="fill">{SPINNER}</div>'
    cards = [card3(x) for x in POP_ROOMS[:n_rooms]]
    return f'<div class="fill">{grid(cards, cols)}</div>'


def popular3(form, state='list', tab=0, scrim='', fab=False, notice=None, cellular=False):
    """v3 PopularPage inside the home shell. form: phone | land | wide (Windows)."""
    t = tabs(POPULAR_SITES, tab, 'start')
    head = ''
    if notice:
        head += f'<div class="ntc">{notice}</div>'
    if cellular:
        head += (f'<div class="cell"><div class="row"><span class="ico">{mr("signal_cellular_alt", 18)}</span>'
                 '<span class="m">您当前正在使用移动蜂窝流量，请注意流量消耗。</span></div><div class="nb">不再显示</div></div>')
    fabs = f'<div class="fab" style="bottom:{20 if form != "wide" else 70 + 68}px">{mr("arrow_upward")}</div>' if fab else ''
    if form == 'phone':
        if state == 'blank':   # popular_page.dart:19-21: no platforms -> an empty Scaffold
            return page(393, 852, 3, STATUS + '<div class="fill"></div>' + navbar('热门') + scrim, syn=False)
        body = popular3_body(2, state, tab)
        return page(393, 852, 3, STATUS + home_bar(t) + head + body.replace('<div class="fill">', '<div class="fill">' + fabs, 1) + navbar('热门') + scrim)
    if form == 'land':
        main = f'<div class="col fill">{home_bar(t, phone=False)}{head}{popular3_body(3, state, tab)}</div>'
        return page(852, 393, 2, STATUS_LAND + f'<div class="row fill" style="align-items:stretch">{rail("热门")}{main}</div>' + scrim, frame='fs',
                    style='background:var(--surface)')
    main = f'<div class="col fill">{home_bar(t, phone=False)}{head}{popular3_body(4, state, tab, 12)}{pager3() if state == "list" else ""}{fabs}</div>'
    return page(1280, 800, 1.5, f'<div class="row fill" style="align-items:stretch">{rail("热门")}{main}</div>' + scrim, frame='win')


def picker_btn(n=None):
    return f'<div class="ib" style="width:44px;height:46px;color:var(--onv);flex:none"{at(n, "add")}>{r("arrow_down_s_line", 22)}</div>'


def popular4_body(cols, state='list', n_rooms=10, hover=None, nmap=None, skeleton_n=10):
    if state == 'empty':
        return ('<div class="fill" style="display:grid;place-items:center">'
                + status4(r('fire_fill', 42), '未发现直播', '这个平台暂时没有直播。左右滑动或点上方的平台名切换平台，也可以下拉刷新', '刷新') + '</div>')
    if state == 'noplatform':
        return ('<div class="fill" style="display:grid;place-items:center">'
                + status4(mr('live_tv', 42), '没有要显示的平台', '在“平台显示”里选择要在热门页显示的平台', '平台显示', 'tune', fill=True) + '</div>')
    if state == 'loading':
        return f'<div class="fill">{grid([card4(None, "skeleton") for _ in range(skeleton_n)], cols)}</div>'
    cards = []
    for i, x in enumerate(POP_ROOMS[:n_rooms]):
        cards.append(card4(x, hover=(hover == i), nmap=(nmap if i == 0 else None)))
    return f'<div class="fill">{grid(cards, cols)}</div>'


def popular4(form, state='list', scrim='', n=False, notice=None, cellular=False, hover=None, panel='', tab=0, tip=''):
    """New popular page (U.4b): v3 layout, tabs keep the title position, a
    platform picker at the end of the tabs, cards from U.4a, columns by UI_PLAN 5.3."""
    N = (lambda k: k) if n else (lambda k: None)
    t = tabs(POPULAR_SITES, tab, 'start', extra_attr=(lambda i: at(N(2), 'keep') if i == 0 else ''))
    mid = (f'<div class="row" style="width:100%;min-width:0;height:56px"><div style="flex:1;min-width:0;overflow:hidden">{t}</div>'
           f'{picker_btn(N(3))}</div>')
    head = ''
    if notice:
        head += f'<div class="note4"{at(N(6), "chg", "tl")}>{mr("info_outline")}<span>{notice}</span></div>'
    if cellular:
        head += (f'<div class="cell"><div class="row"><span class="ico">{mr("signal_cellular_alt", 18)}</span>'
                 '<span class="m">您当前正在使用移动蜂窝流量，请注意流量消耗。</span></div><div class="nb">不再显示</div></div>')
    nmap = {'card': N(5)}
    if form == 'phone':
        if state == 'noplatform':
            bar = f'<div class="hbar"><div class="lead">{mr("menu")}</div><div class="mid"></div><div class="act">{r("menu_search_line")}</div></div>'
        else:
            bar = (f'<div class="hbar"><div class="lead"{at(N(1), "keep")}>{mr("menu")}</div><div class="mid" style="padding:0 0 0 4px">{mid}</div>'
                   f'<div class="act"{at(N(4), "keep")}>{r("menu_search_line")}</div></div>')
        body = popular4_body(2, state, nmap=nmap)
        return page(393, 852, 3, STATUS + bar + head + body + navbar('热门') + panel + scrim)
    bar = f'<div class="hbar"><div class="mid" style="padding:0 8px 0 16px">{mid}</div></div>'
    if form == 'land':
        main = f'<div class="col fill">{bar}{head}{popular4_body(4, state, 8, nmap=nmap, skeleton_n=8)}</div>'
        return page(852, 393, 2, STATUS_LAND + f'<div class="row fill" style="align-items:stretch">{rail("热门")}{main}</div>' + panel + scrim,
                    frame='fs', style='background:var(--surface)')
    pg = pager3() if state == 'list' else ''
    if n and pg:
        pg = (pg.replace('<div class="ob">', '<div class="ob" data-n="7" data-tag="keep">', 1)
                .replace('<div class="tbn">', '<div class="tbn" data-n="8" data-tag="keep">', 1)
                .replace('<div class="pn">2</div>', '<div class="pn" data-n="9" data-tag="keep">2</div>', 1)
                .replace('<div class="sel">', '<div class="sel" data-n="10" data-tag="keep">', 1)
                .replace('<div class="fld">', '<div class="fld" data-n="11" data-tag="keep">', 1))
    main = f'<div class="col fill">{bar}{head}{popular4_body(5, state, 15, hover=hover, nmap=nmap, skeleton_n=15)}{pg}{tip}</div>'
    return page(1280, 800, 1.5, f'<div class="row fill" style="align-items:stretch">{rail("热门")}{main}</div>' + panel + scrim, frame='win')
