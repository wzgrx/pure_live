"""U.2k local interaction mockups: v3 restored and the new design, as HTML next
to this file. Then:
    python3 docs/ui/compare/U.2k/src/gen.py && python3 tools/ui/mock/render.py docs/ui/compare/U.2k/src/ --annotate

v3 (tag v3.2.11), every text from assets/translations/zh.json:
  widgets/local_interaction/local_interaction_sheet.dart      the room panel (bottom sheet)
  widgets/local_interaction/local_danmaku_style_editor.dart   style editor (sheet / right dialog)
  widgets/local_interaction/local_interaction_controller.dart presets, colours, gifts, packs, defaults
  widgets/danmaku/danmaku_list_view.dart:386-436             portrait composer
  widgets/video_player/video_controller_panel.dart:1584-1750 fullscreen composer
  pages/live_play_page.dart:47-92                            gift effect
  modules/settings/pages/local_interaction_settings_page.dart settings page
Gift and badge emoji are drawn with emoji.woff2, a Noto Color Emoji subset
(OFL, from Google Fonts with text=...), because the render machine has no
colour emoji font."""
import os

HERE = os.path.dirname(os.path.abspath(__file__))

CSS = '''
@font-face{font-family:'Emo';src:url('../../../docs/ui/compare/U.2k/src/emoji.woff2') format('woff2')}
.e{font-family:'Emo';font-style:normal;font-weight:400}
.ph{display:flex;flex-direction:column}
.abs{position:absolute}
.grow{flex:1;min-height:0}
/* ---------- v3 portrait room ---------- */
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
.it{margin:4px 8px;background:rgba(255,255,255,.72);border:.5px solid rgba(0,0,0,.08);border-radius:10px;padding:8px 12px;display:flex;align-items:flex-start;flex:none}
.it i{width:8px;height:8px;border-radius:4px;margin:6px 10px 0 0;flex:none}.it p{font-size:14px;line-height:1.45;font-weight:400}.it b{font-weight:700}
/* v3 composer (danmaku_list_view.dart:390-433) */
.cmp3{background:var(--scl);padding:8px 8px 8px 10px;display:flex;align-items:center;gap:6px;flex:none}
.fld{flex:1;min-width:0;height:48px;border:1px solid var(--outline);border-radius:22px;display:flex;align-items:center;font-size:13px;color:rgba(67,71,78,.6);white-space:nowrap;overflow:hidden;background:var(--scl)}
.fld .p{width:48px;height:46px;display:grid;place-items:center;color:var(--primary);flex:none}
.fld .tx{color:var(--on);font-size:14px}
.fab{width:40px;height:40px;border-radius:20px;background:var(--primary);color:var(--onPrimary);display:grid;place-items:center;flex:none;margin:4px}
.toast3{position:absolute;left:50%;transform:translateX(-50%);z-index:40;background:rgba(0,0,0,.72);color:#fff;font-size:14px;padding:9px 18px;border-radius:8px;white-space:nowrap}
/* v3 modal pieces */
.bs3{position:absolute;left:0;right:0;bottom:0;background:var(--scc);border-radius:24px 24px 0 0;z-index:21;overflow:hidden;display:flex;flex-direction:column}
.handle{height:48px;display:grid;place-items:center;flex:none}.handle i{width:32px;height:4px;border-radius:2px;background:rgba(67,71,78,.4)}
.t20{font-size:20px;font-weight:600}.t15{font-size:15px;font-weight:500}.t14m{font-size:14px;font-weight:500}.t13{font-size:13px}.t12{font-size:12px;line-height:1.45}.onv{color:var(--onv)}
.ibx{width:48px;height:48px;display:grid;place-items:center;flex:none;color:var(--onv)}
.wrap{display:flex;flex-wrap:wrap;align-items:center}
.ch3{height:32px;border-radius:8px;border:1px solid var(--ov);padding:0 12px;display:inline-flex;align-items:center;gap:6px;font-size:13px;font-weight:500;color:var(--onv);white-space:nowrap;margin:8px 0;flex:none}
.ch3 .mr{font-size:17px}.ch3.on{background:var(--sc);border-color:var(--sc);color:var(--osc)}.ch3 .dot{width:10px;height:10px;border-radius:5px;flex:none}
.tf3{position:relative;height:56px;border:1px solid var(--outline);border-radius:12px;background:var(--scl);display:flex;align-items:center;padding:0 16px;font-size:14px}
.tf3 label{position:absolute;left:12px;top:-9px;padding:0 4px;font-size:12px;color:var(--onv);background:var(--scc)}
.chip3{height:32px;border-radius:8px;border:1px solid var(--ov);display:inline-flex;align-items:center;gap:6px;padding:0 10px 0 8px;font-size:13px;font-weight:500;color:var(--onv);white-space:nowrap;flex:none}
.lt3{display:flex;align-items:center;gap:16px;min-height:64px}
.lt3 .x{flex:1;min-width:0}.lt3 .a{font-size:14px;font-weight:500}.lt3 .b{font-size:13px;color:var(--onv);margin-top:2px;line-height:1.4}
.ob3{height:40px;padding:0 18px;border-radius:20px;border:1px solid var(--outline);color:var(--primary);font-size:13px;font-weight:500;display:inline-flex;align-items:center;flex:none;white-space:nowrap}
.grid4{display:grid;grid-template-columns:repeat(4,1fr);gap:8px}
.gt3{background:var(--schh);border-radius:14px;display:flex;flex-direction:column;align-items:center;justify-content:center;aspect-ratio:.9;font-size:13px}
.gt3 .e{font-size:28px;line-height:34px}.gt3 small{font-size:11px;color:var(--onv)}
/* v3 style editor */
.pv{position:relative;border-radius:16px;background:linear-gradient(135deg,#27344D,#101623 55%,#06080E);overflow:hidden;flex:none}
.pv .tv{position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);color:rgba(255,255,255,.1)}
.pv .tx{position:absolute;white-space:nowrap;color:#fff;font-size:19px;font-weight:600;text-shadow:1.5px 0 #000,-1.5px 0 #000,0 1.5px #000,0 -1.5px #000}
.pv .badge3{position:absolute;left:9px;top:8px;display:flex;align-items:center;gap:4px;padding:3px 7px;border-radius:10px;background:rgba(0,0,0,.38);color:rgba(255,255,255,.7);font-size:11px}
.st3{display:flex;align-items:flex-start;gap:6px;font-size:14px;font-weight:500}.st3 .mr{font-size:17px;color:var(--primary);margin-top:2px}
.lab3{font-size:13px;font-weight:500}
.sw3{display:flex;flex-wrap:wrap;column-gap:9px;row-gap:8px}
.swc{width:48px;height:48px;display:grid;place-items:center;flex:none}
.swc i{width:36px;height:36px;border-radius:18px;border:1px solid var(--ov);display:grid;place-items:center;font-style:normal}
.swc.on i{border:2.5px solid var(--primary);box-shadow:0 0 5px rgba(54,97,142,.22)}
.swc.sm i{width:29px;height:29px}
.sl3{flex:1;min-width:0}.sl3 .h{display:flex;justify-content:space-between;font-size:13px}.sl3 .h b{font-weight:400;color:var(--primary)}
.trk{height:48px;position:relative}.trk s{position:absolute;left:10px;right:10px;top:22px;height:4px;border-radius:2px;background:var(--sc)}
.trk s i{position:absolute;left:0;top:0;bottom:0;border-radius:2px;background:var(--primary)}.trk s u{position:absolute;top:-8px;width:20px;height:20px;border-radius:10px;background:var(--primary);margin-left:-10px}
.twocol{display:flex;gap:12px}
.dlg3{position:absolute;z-index:21;background:var(--sch);border-radius:16px;overflow:hidden;display:flex;flex-direction:column}
/* gift effect */
.gfx{position:absolute;z-index:25;transform:translate(-50%,-50%);border-radius:24px;border:1px solid rgba(255,255,255,.45);color:#fff;font-weight:700;text-align:center;line-height:1.4}
/* local flying danmaku */
.ldm{position:absolute;white-space:nowrap;color:#fff;font:600 19px 'Noto Sans SC';text-shadow:1.5px 0 #000,-1.5px 0 #000,0 1.5px #000,0 -1.5px #000,1px 1px #000,-1px -1px #000;z-index:4}
/* ---------- new ---------- */
.cmp{background:var(--scl);border-top:1px solid var(--ov);padding:8px 8px 8px 10px;display:flex;align-items:center;gap:6px;flex:none}
.ltag{display:inline-block;font-size:11px;line-height:18px;padding:0 6px;border-radius:9px;background:var(--pc);color:var(--opc);margin-right:5px;font-weight:600;vertical-align:1px}
.bdg{display:inline-block;font-size:11px;line-height:18px;padding:0 6px;border-radius:9px;background:rgba(0,174,236,.14);color:#00658A;margin-right:5px;font-weight:600;vertical-align:1px}
.list{flex:1;min-height:0;overflow:hidden;display:flex;flex-direction:column;justify-content:flex-end;padding:6px 0 8px}
.under{position:absolute;left:0;right:0;bottom:0;background:var(--surface);border-radius:16px 16px 0 0;box-shadow:0 -4px 16px rgba(0,0,0,.12);z-index:21;display:flex;flex-direction:column;overflow:hidden}
.pbody{flex:1;min-height:0;overflow:hidden}
.desc{padding:0 20px 10px;font-size:12px;line-height:1.5;color:var(--onv)}
.idc{margin:0 16px;border-radius:16px;padding:12px 14px;display:flex;align-items:center;gap:12px;background:linear-gradient(90deg,rgba(0,174,236,.16),rgba(0,174,236,.05));box-shadow:inset 0 0 0 1px rgba(0,174,236,.25)}
.idc .av2{width:40px;height:40px;border-radius:20px;background:#fff;display:grid;place-items:center;font-size:22px;flex:none}
.idc .n{font-size:15px;font-weight:600}.idc .m{font-size:12px;color:#00658A;font-weight:600;margin-top:2px}
.pcmp{margin:12px 16px 0;display:flex;align-items:center;gap:6px}
.gt{background:var(--scc);border-radius:14px;display:flex;flex-direction:column;align-items:center;justify-content:center;height:88px;font-size:13px}
.gt .e{font-size:28px;line-height:34px}.gt small{font-size:12px;color:var(--onv);display:flex;align-items:center;gap:2px}.gt small .mr{font-size:13px}
.gt.dim{opacity:.45}
.rch{display:flex;align-items:center;gap:8px;padding:12px 16px 0}.rch .l{flex:1;font-size:14px}
.ob{height:36px;padding:0 14px;border-radius:18px;box-shadow:inset 0 0 0 1px var(--ov);color:var(--primary);font-size:14px;font-weight:600;display:inline-flex;align-items:center;flex:none}
.tf{position:relative;margin:6px 16px 0;height:52px;border:1px solid var(--outline);border-radius:12px;display:flex;align-items:center;padding:0 14px;font-size:15px}
.tf label{position:absolute;left:10px;top:-9px;padding:0 4px;font-size:12px;color:var(--onv);background:var(--surface)}.tf small{margin-left:auto;font-size:12px;color:var(--onv)}
.wrp{display:flex;flex-wrap:wrap;gap:8px;padding:8px 16px 0}
.navr{display:flex;align-items:center;gap:12px;padding:8px 8px 8px 20px;min-height:56px}.navr .x{flex:1}.navr .a{font-size:15px}.navr .v{font-size:14px;color:var(--onv)}.navr .rx{font-size:20px;color:var(--onv)}
.hist{padding:2px 20px 0}.hist div{font-size:13px;color:var(--onv);padding:7px 0;border-bottom:1px solid var(--scc);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.pvn{position:relative;margin:0 16px;height:82px;border-radius:16px;background:linear-gradient(135deg,#27344D,#101623 55%,#06080E);overflow:hidden;flex:none}
.pvn .tv{position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);color:rgba(255,255,255,.1)}
.pvn .tx{position:absolute;white-space:nowrap;color:#fff;font-size:19px;font-weight:600;text-shadow:1.5px 0 #000,-1.5px 0 #000,0 1.5px #000,0 -1.5px #000}
.pvn .badge3{position:absolute;left:9px;top:8px;display:flex;align-items:center;gap:4px;padding:3px 7px;border-radius:10px;background:rgba(0,0,0,.38);color:rgba(255,255,255,.75);font-size:11px}
.lab{padding:12px 20px 0;font-size:14px}
.sws{display:flex;flex-wrap:wrap;gap:0 4px;padding:2px 12px 0}
.sws .swc{width:44px;height:44px}.sws .swc i{width:32px;height:32px;border-radius:16px}
.sws .swc.on i{border:2.5px solid var(--primary)}
.slr{padding:10px 20px 0}.slr .h{display:flex;justify-content:space-between;align-items:center;font-size:15px}
.slr .t{height:32px;position:relative}.slr .t s{position:absolute;left:2px;right:2px;top:14px;height:4px;border-radius:2px;background:rgba(54,97,142,.15)}
.slr .t s i{position:absolute;left:0;top:0;bottom:0;border-radius:2px;background:var(--primary)}.slr .t s u{position:absolute;top:-8px;width:20px;height:20px;border-radius:10px;background:var(--primary);margin-left:-10px}
.gray{opacity:.38}
.p-h .bk{width:48px;height:48px;display:grid;place-items:center;margin-left:-16px;color:var(--on)}
.tlk{font-size:14px;color:var(--primary);padding:0 8px;display:flex;align-items:center;height:48px}
/* settings */
.gt12{padding:0 0 8px 8px;font-size:12px;font-weight:700;letter-spacing:.5px;color:rgba(54,97,142,.65)}
.card3{background:#F6F7FC;border:.5px solid rgba(0,0,0,.05);border-radius:20px;overflow:hidden}
.st{padding:0 0 8px 8px;font-size:13px;font-weight:600;color:var(--primary)}
.cardn{background:var(--scl);border-radius:16px;overflow:hidden}
.swt{display:flex;align-items:center;gap:14px;padding:10px 8px 10px 16px;min-height:64px}
.swt .mr,.swt .mi{color:var(--primary);font-size:22px;flex:none}.swt .x{flex:1;min-width:0}.swt .a{font-size:15px;font-weight:600}.swt .b{font-size:12px;color:rgba(67,71,78,.75);margin-top:2px;line-height:1.45}
.swtn .a{font-weight:400}.swtn .b{color:var(--onv)}
.dv{height:.5px;background:rgba(0,0,0,.06);margin:0 16px}
.pack{border-radius:16px;padding:14px;background:linear-gradient(90deg,rgba(0,174,236,.18),rgba(0,174,236,.05));border:1px solid rgba(0,174,236,.25)}
.gch{height:32px;border-radius:8px;border:1px solid var(--ov);padding:0 10px;display:inline-flex;align-items:center;font-size:13px;font-weight:500;color:var(--onv);white-space:nowrap;background:rgba(255,255,255,.5)}
.apb{height:56px;display:flex;align-items:center;background:var(--surface);flex:none;position:relative}
.apb .c{position:absolute;left:0;right:0;text-align:center;font-size:20px;font-weight:600;pointer-events:none}
.appbar .fol{padding:0 10px 0 8px}.appbar .tt{margin-left:8px}
.tb{display:inline-flex;align-items:center;gap:8px;height:40px;padding:0 12px;color:var(--primary);font-size:13px;font-weight:500}
'''

mr = lambda n, s=24, st='': f'<span class="mr" style="font-size:{s}px;{st}">{n}</span>'
mi = lambda n, s=24, st='': f'<span class="mi" style="font-size:{s}px;{st}">{n}</span>'
rx = lambda c, s=24: f'<span class="rx" style="font-size:{s}px">&#x{c};</span>'
ci = lambda c, s=24: f'<span class="ci" style="font-size:{s}px">&#x{c};</span>'
e = lambda s, sz=None: f'<span class="e"' + (f' style="font-size:{sz}px"' if sz else '') + f'>{s}</span>'


def N(n, at=None, tag=None):
    """data-n attribute string (empty when numbering is off)."""
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

# ---------- data from v3 ----------
CHAT = [('#C2255C', '星河长明', '前排支持！'), ('#000', '一只小熊', '这首歌好好听'), ('#1971C2', '夜猫子', '可以点《晴天》吗'),
        ('#000', '路过的风', '主播声音太温柔了'), ('#C2410C', 'Aki', '打卡第 52 天，晚安前来听歌'), ('#000', '橘子汽水', '晚风晚上好～'),
        ('#000', '不吃香菜', '上一首是什么歌？'), ('#000', '月亮邮差', '这个混响调得真舒服')]
# local_interaction_controller.dart:194-207, :209
DM_COLORS = ['FFFFFF', 'FFE45C', '72E6FF', 'FF69D4', '8CFF98', 'FF9D66', 'BCA7FF', 'FF5C77', '4EA1FF', '00D8B0', 'FFB7E7', 'B8FF67']
FX_COLORS = ['000000', 'FFFFFF', '173A5E', '6D1F45', '00C8FF', 'FF2DC6', 'FF8A00']
# :116-192 (label, colour)
PRESETS = [('清爽', 'FFFFFF'), ('醒目', 'FFE45C'), ('霓虹', 'FF69D4'), ('极简', '72E6FF'), ('底部字幕', 'FFFFFF'), ('赛博', '58F5FF')]
PLACES = [('滚动', 'trending_flat'), ('顶部固定', 'vertical_align_top'), ('底部固定', 'vertical_align_bottom')]
FONTS = [('系统', "'Noto Sans SC'"), ('圆润', "'Noto Sans SC'"), ('衬线', "serif"), ('等宽', "monospace")]
TITLES = ['听众', '守夜人', '应援团', '守护者']
# Bilibili pack (:249-256) and gifts (:524-547)
BILI_GIFTS = [('🌶️', '辣条', 10), ('📺', '小电视', 100), ('⚓', '大航海', 1980)]
# platformPacks :248-521 (badge, name)
PACKS = [('📺', '哔哩哔哩'), ('🐟', '斗鱼'), ('🐯', '虎牙'), ('🎵', '抖音'), ('🎬', '快手'), ('🎮', '网易CC'), ('💜', 'Twitch'), ('🎈', 'Soop'),
         ('🎤', 'YY'), ('🅰️', 'AcFun 直播'), ('🎨', 'Picarto'), ('📡', 'TwitCasting'), ('🎧', '猫耳 FM'), ('✨', '映客'), ('💫', '克拉克拉'),
         ('📕', '小红书'), ('📹', 'niconico'), ('🟠', '微博直播'), ('🎟️', 'SHOWROOM'), ('🎮', 'CHZZK'), ('17', '17LIVE'), ('LM', 'LiveMe'),
         ('TT', 'TikTok LIVE'), ('YT', 'YouTube Live'), ('BG', 'Bigo Live'), ('PD', 'PandaTV'), ('FC', 'FC2 Live'), ('ST', 'Steam Broadcasts'),
         ('JD', '京东直播'), ('KG', '酷狗直播'), ('BD', '百度直播'), ('6R', '六间房直播'), ('LK', 'LOOK 直播'), ('🌐', '网络')]
HINT3 = '发送一条本地字幕'
HINT4 = '发送本地弹幕，只有你看得到'
SYNC = '所有选项实时保存，并同步用于竖屏、横屏、小窗、发送框和本地互动页。'
HIST = ['📺 📺 舰队等级 · 听众 · Pure Live 送出 小电视 ×1', '🌶️ 📺 舰队等级 · 听众 · Pure Live 送出 辣条 ×1', '增加本地体验币 +500']  # newest first; 1000 + 500 - 10 - 100 = 1390


def badge_text(s):
    return ''.join(e(ch) if ord(ch[0]) > 0x2000 else ch for ch in [s])


# =====================================================================
# v3
# =====================================================================
def v3_appbar():
    return ('<div class="appbar"><div class="back">' + mi('arrow_back') + '</div><span class="av" style="background-image:url(.cache/img/65.jpg)"></span>'
            '<div class="tt" style="margin-left:8px"><div class="v3nick">晚风</div><div class="v3area">哔哩哔哩 / 唱见电台</div></div>'
            '<div class="v3heart">' + mr('favorite_border', 22) + '</div><div class="v3recsq">' + mr('radio_button_checked', 22) + '</div>'
            + ib(rx('ea42')) + '<div style="width:4px"></div></div>')


def v3_video(fly=''):
    top = '<div class="v3top"><div class="title">' + TITLE + '</div>' + ib(rx('ee05', 21)) + ib(rx('f235')) + ib(ci('e806')) + '</div>'
    bot = ('<div class="v3bot">' + ib(mr('pause', 28)) + ib(mr('refresh')) + '<div class="pill">' + mr('check', 15) + '已关注</div>'
           + ib('<span class="dmk open"></span>') + ib('<span class="dmk set"></span>') + ib(mr('screen_rotation_alt', 21))
           + '<div style="flex:1"></div>' + ib(mr('fullscreen', 26)) + '</div>')
    dms = '<div class="dm" style="left:150px;top:60px">前排支持！</div><div class="dm" style="left:24px;top:96px">这首好好听</div>'
    return f'<div class="video" style="background-image:url(.cache/img/158.jpg);flex:none">{dms}{fly}{top}{bot}</div>'


def v3_res():
    return ('<div class="res"><div class="aud">' + mr('people_alt', 16) + '在线 1.2万</div><div class="q">原画</div><div class="l">线路1</div></div><hr>'
            '<div class="tabs v3t" style="flex:none"><div class="on">弹幕列表</div><div>醒目留言</div><div>弹幕设置</div><div>屏蔽管理</div></div>')


def v3_cards(extra=()):
    rows = [(c, f'{u}', t) for c, u, t in CHAT[:5]] + list(extra)
    return ''.join(f'<div class="it"><i style="background:{c}"></i><p><b>{u}: </b>{t}</p></div>' for c, u, t in rows)


def v3_composer(text=None):
    inner = f'<span class="tx">{text}</span>' if text else HINT3
    return ('<div class="cmp3"><div class="fld"><span class="p">' + mr('auto_awesome', 19) + f'</span>{inner}</div>'
            '<div class="fab">' + mr('send', 22) + '</div></div>')


def v3_room(list_extra=(), fly='', overlay='', composer=True):
    body = (STATUS + v3_appbar() + v3_video(fly) + v3_res() + f'<div class="list3">{v3_cards(list_extra)}</div>'
            + (v3_composer() if composer else '') + '<div style="height:14px;background:var(--scl);flex:none"></div>' + overlay + SYN + GEST)
    return body


LOCAL3_CHAT = ('#000', '<span class="e">📺</span> 舰队等级 · 听众 · Pure Live', '主播晚上好')
LOCAL3_GIFT = ('#FF6392', 'Pure Live', '<span class="e">⚓</span> <span class="e">📺</span> 舰队等级 · 听众 · Pure Live 送出 大航海 ×1')


def gfx3(x, y, full, text, color):
    """live_play_page.dart:58-89: card centred on the whole page; blurred glow."""
    pad = '24px 28px' if full else '14px 20px'
    return (f'<div class="gfx" style="left:{x}px;top:{y}px;max-width:{440 if full else 320}px;width:max-content;padding:{pad};font-size:{20 if full else 16}px;'
            f'background:linear-gradient(90deg,{color}F0,rgba(0,0,0,.78));box-shadow:0 0 {42 if full else 24}px {color}8C">{text}</div>')


def v3_room_page():
    # the moment after Send: the toast is up, the line itself arrives 2 s later (live_play_controller.dart:105)
    toast = '<div class="toast3" style="bottom:96px">发送成功，将在 2 秒后同步显示</div>'
    body = v3_room(overlay=toast)
    return page(393, 852, 3, body)


def v3_gift_page():
    """Gift sent from the sheet; after closing it the card sits in the middle of the page."""
    fly = '<div class="ldm" style="left:12px;top:112px;font-size:19px">' + LOCAL3_GIFT[2] + '</div>'
    eff = gfx3(196, 426, True, LOCAL3_GIFT[2], '#FF6392')
    body = v3_room(list_extra=[LOCAL3_CHAT, LOCAL3_GIFT], fly=fly, overlay=eff)
    return page(393, 852, 3, body)


def v3_style_controls(compact=False, dense=False, full=False, width=365):
    """_StyleControls (local_danmaku_style_editor.dart:376-666)."""
    cu = compact or dense
    gap = 11 if cu else 17
    sp = 5 if cu else 8
    pre = 'custom' if full else '清爽'
    place = '底部固定' if full else '滚动'
    stroke, shadow = True, full
    o = ['<div class="st3">' + mr('auto_awesome') + '样式模板</div>', f'<div class="wrap" style="column-gap:{sp}px;margin-top:{sp - 8}px">']
    for name, col in PRESETS:
        on = name == pre
        o.append(f'<span class="ch3{" on" if on else ""}">' + (mr('check', 18) if on else f'<i class="dot" style="background:#{col};box-shadow:0 0 0 1px rgba(0,0,0,.15)"></i>') + f'{name}</span>')
    o.append(f'</div><div style="height:{gap - 8}px"></div><div class="st3">' + mr('vertical_align_center') + '显示位置</div>'
             f'<div class="wrap" style="column-gap:6px;margin-top:{sp - 8}px">')
    for name, icon in PLACES:
        on = name == place
        o.append(f'<span class="ch3{" on" if on else ""}">' + mr('check' if on else icon, 17) + f'{name}</span>')
    o.append(f'</div><div style="height:{gap - 8}px"></div><div class="st3">' + mr('text_fields') + '字体与颜色</div>'
             f'<div class="wrap" style="column-gap:6px;margin-top:{sp - 8}px">')
    for i, (name, fam) in enumerate(FONTS):
        on = i == 0
        o.append(f'<span class="ch3{" on" if on else ""}" style="font-family:{fam}">' + (mr('check', 18) if on else '') + f'{name}</span>')
    sel = 'FFE45C' if full else 'FFFFFF'
    o.append(f'</div><div style="height:{0 if cu else 3}px"></div><div class="lab3">弹幕颜色</div><div class="sw3" style="margin-top:6px;column-gap:{7 if cu else 9}px">')
    for c in DM_COLORS:
        on = c == sel
        fg = '#000000DD' if c not in ('173A5E', '6D1F45', '000000') else '#fff'
        o.append(f'<span class="swc{" on" if on else ""}{" sm" if cu else ""}"><i style="background:#{c}">' + (mr('check', 16 if cu else 19, f'color:{fg}') if on else '') + '</i></span>')
    o.append('</div>')

    def sl(label, val, frac):
        return (f'<div class="sl3"><div class="h"><span>{label}</span><b>{val}</b></div><div class="trk"><s><i style="width:{frac * 100:.0f}%"></i>'
                f'<u style="left:{frac * 100:.0f}%"></u></s></div></div>')
    two = width >= 340
    sz = '22 px' if full else '19 px'
    sliders = [sl('字体大小', sz, (22 - 14) / 18 if full else (19 - 14) / 18), sl('滚动速度', '130 px/s', (130 - 60) / 200),
               sl('不透明度', '100%', 1), sl('字间距', '0.0', .5 / 3.5)]
    o.append(f'<div style="height:{8 if cu else 12}px"></div>')
    if two:
        o.append(f'<div class="twocol">{sliders[0]}{sliders[1]}</div><div class="twocol">{sliders[2]}{sliders[3]}</div>')
    else:
        o.append(''.join(sliders))
    o.append(f'<div style="height:{3 if cu else 8}px"></div><div class="st3">' + mr('auto_fix_high') + '文字效果</div>'
             f'<div class="wrap" style="column-gap:6px;margin-top:{sp - 8}px">')
    for name, icon, on in [('粗体', 'format_bold', False), ('斜体', 'format_italic', False), ('描边', 'border_color', stroke), ('阴影 / 微光', 'blur_on', shadow)]:
        o.append(f'<span class="ch3{" on" if on else ""}">' + mr('check' if on else icon, 18) + f'{name}</span>')
    o.append('</div>')
    if stroke:
        o.append(f'<div style="height:{8 if cu else 12}px"></div><div class="lab3">描边颜色</div><div class="sw3" style="margin-top:6px;column-gap:7px">')
        for c in FX_COLORS:
            on = c == '000000'
            o.append(f'<span class="swc sm{" on" if on else ""}"><i style="background:#{c}">' + (mr('check', 16, 'color:#fff') if on else '') + '</i></span>')
        o.append('</div>' + sl('描边宽度', '1.5', 1 / 3.5))
    if shadow:
        o.append(f'<div style="height:{8 if cu else 12}px"></div><div class="lab3">阴影颜色</div><div class="sw3" style="margin-top:6px;column-gap:7px">')
        for c in FX_COLORS:
            on = c == '000000'
            o.append(f'<span class="swc sm{" on" if on else ""}"><i style="background:#{c}">' + (mr('check', 16, 'color:#fff') if on else '') + '</i></span>')
        sh = [sl('模糊强度', '2.0', 2 / 6), sl('阴影偏移', '1.0', 1 / 4)]
        o.append('</div>' + (f'<div class="twocol">{sh[0]}{sh[1]}</div>' if two else ''.join(sh)))
    if place != '滚动':
        o.append(f'<div style="height:{7 if cu else 11}px"></div>' + sl('固定弹幕停留时间', '4.0 s', 2 / 8))
    if not dense:
        o.append('<div style="height:8px"></div><div style="display:flex;gap:6px;align-items:flex-start">' + mr('sync', 16, 'color:var(--primary)')
                 + f'<span class="t12 onv">{SYNC}</span></div>')
    return ''.join(o)


def v3_preview(h=112, expanded=False, bottom=False):
    tx_top = f'top:{(h - 28) / 2 + (11 if expanded else 0):.0f}px'
    if bottom:  # placement bottom: AnimatedAlign bottomCenter, the custom state of v3-style-full (yellow, 22 px)
        tx_top = 'bottom:12px;left:50%!important;transform:translateX(-50%);color:#FFE45C;font-size:22px'
    o = f'<div class="pv" style="height:{h}px">' + f'<span class="tv">{mr("live_tv", 54 if expanded else 38)}</span>'
    if expanded:
        o += '<span class="badge3">' + mr('play_circle_filled', 12) + '实时预览</span>'
    o += f'<span class="tx" style="left:{38 if expanded else 120}px;{tx_top}">Pure Live 本地弹幕预览</span>'
    if expanded:
        o += f'<span class="tx" style="left:12px;bottom:38px;opacity:.45">Pure Live 本地弹幕预览</span>'
    return o + '</div>'


def v3_style_header(compact=False):
    return ('<div style="height:48px;display:flex;align-items:center;padding-left:' + ('10' if compact else '14') + 'px;flex:none">'
            + mr('auto_awesome', 18 if compact else 20, 'color:var(--primary)') + f'<span class="{"t14m" if compact else "t15"}" style="margin-left:{6 if compact else 8}px;flex:1">本地弹幕样式</span>'
            '<span class="ibx">' + mr('restart_alt', 19 if compact else 20) + '</span><span class="ibx">' + mr('close', 19 if compact else 20) + '</span></div><hr>')


def v3_style_page():
    sheet = ('<div class="bs3" style="top:116px"><div class="handle"><i></i></div>' + v3_style_header()
             + '<div style="padding:14px;flex:1;overflow:hidden">' + v3_preview() + '<div style="height:16px"></div>' + v3_style_controls() + '</div></div>')
    body = v3_room() + '<div class="scrim"></div>' + sheet
    return page(393, 852, 3, body)


def v3_style_full_page():
    body = ('<div style="background:var(--scc);border-radius:24px 24px 0 0"><div class="handle"><i></i></div>' + v3_style_header()
            + '<div style="padding:14px 14px 24px">' + v3_preview(bottom=True) + '<div style="height:16px"></div>' + v3_style_controls(full=True) + '</div></div>')
    return page(393, 2600, 2, body, crop=True, extra='.ph{height:auto;background:#fff}')


def v3_fs_bars(focused_text=None, star_color='#fff'):
    lead = ib(mi('arrow_back')) + '<div class="time" style="padding:0 4px">21:36</div><div class="bat" style="margin:0 8px">76</div>'
    trail = ('<div style="width:40px;height:40px;border-radius:20px;background:rgba(0,0,0,.26);display:grid;place-items:center;margin:0 4px">' + mr('swap_horiz') + '</div>'
             + ib(rx('ee05', 21)) + ib(rx('f235')) + ib(ci('e806')))
    left = (ib(mr('pause', 28)) + ib(mr('refresh')) + '<div class="pill">' + mr('check', 15) + '已关注</div>' + ib('<span class="dmk open"></span>') + ib('<span class="dmk set"></span>'))
    right = ('<div style="display:flex;align-items:center;gap:6px;height:36px;padding:0 10px;border-radius:18px;background:rgba(255,255,255,.13);font-size:13px;font-weight:600">'
             + mr('tune', 17) + '原画 · 线路1</div>' + ib(mr('screen_rotation_alt', 21)) + '<div style="padding:0 6px;font-size:15px;white-space:nowrap">默认比例</div>' + ib(mr('fullscreen_exit', 26)))
    border = '1.3px solid var(--primary)' if focused_text else '1px solid rgba(255,255,255,.24)'
    inner = (f'<span style="color:#fff;font-size:13px;font-weight:600">{focused_text}<span style="display:inline-block;width:1.5px;height:15px;background:var(--primary);vertical-align:-3px;margin-left:1px"></span></span>'
             if focused_text else '<span style="color:rgba(255,255,255,.6);font-size:13px">' + HINT3 + '</span>')
    comp = (f'<div style="flex:1;max-width:420px;height:48px;border-radius:20px;background:rgba(0,0,0,.54);border:{border};display:flex;align-items:center;overflow:hidden">'
            f'<span style="width:48px;display:grid;place-items:center;flex:none">' + mr('auto_awesome', 18, f'color:{star_color}') + f'</span>{inner}'
            '<span style="margin-left:auto;width:48px;display:grid;place-items:center;flex:none">' + mr('send', 18, 'color:#fff') + '</span></div>')
    return (f'<div class="v3top">{lead}<div class="title">{FS_TITLE}</div>{trail}</div>'
            '<div class="v3bot" style="padding:0 16px"><div style="display:flex;align-items:center">' + left + '</div>'
            f'<div style="flex:1;display:flex;justify-content:center;padding:0 8px;min-width:0">{comp}</div>'
            '<div style="display:flex;align-items:center">' + right + '</div></div>')


FS_DMS = '<div class="dm" style="left:120px;top:96px;font-size:18px">晚上好～</div><div class="dm" style="left:300px;top:120px;font-size:18px">前排支持！</div>'


def v3_fullscreen_page():
    body = (SYN + FS_DMS + '<div class="ldm" style="left:460px;top:190px">主播晚上好</div>' + v3_fs_bars('今晚唱哪首')
            + '<div style="position:absolute;right:20px;top:50%;transform:translateY(-50%);width:50px;height:50px;border-radius:25px;background:rgba(0,0,0,.38);display:grid;place-items:center;color:#fff">' + mr('lock_open', 28) + '</div>')
    return page(852, 393, 2, body, frame='fs', extra='.fs{background-image:url(.cache/img/274.jpg);background-position:center 40%}')


def v3_style_landscape_page():
    w, h = 418, 377
    pane = 209
    dlg = (f'<div class="dlg3" style="right:8px;top:8px;width:{w}px;height:{h}px">' + v3_style_header(compact=True)
           + '<div style="flex:1;display:flex;min-height:0"><div style="width:' + str(pane) + 'px;padding:8px;display:flex">'
           + '<div style="flex:1;display:flex">' + v3_preview(h=377 - 49 - 16, expanded=True).replace('class="pv"', 'class="pv" ').replace(f'height:{377 - 49 - 16}px', f'height:{377 - 49 - 16}px;flex:1') + '</div></div>'
           + f'<div style="width:1px;background:var(--ov)"></div><div style="flex:1;padding:7px 8px 10px;overflow:hidden">' + v3_style_controls(dense=True, width=193) + '</div></div></div>')
    body = SYN + FS_DMS + v3_fs_bars() + '<div class="scrim"></div>' + dlg
    return page(852, 393, 2, body, frame='fs', extra='.fs{background-image:url(.cache/img/274.jpg);background-position:center 40%}.dlg3 .pv .tx{font-size:19px}')


def v3_sheet_body(long=False):
    """LocalInteractionSheet (local_interaction_sheet.dart:46-219), Bilibili room."""
    tiles = ''.join(f'<div class="gt3">{e(em)}<span>{nm}</span><small>{pr}</small></div>' for em, nm, pr in BILI_GIFTS)
    chips = ''.join(f'<span class="ch3{" on" if i == 0 else ""}">' + (mr('check', 18) if i == 0 else '') + f'{t}</span>' for i, t in enumerate(TITLES))
    style = ('<div class="lt3">' + mr('auto_awesome', 24, 'color:var(--onv)') + '<div class="x"><div class="a">本地弹幕样式</div><div class="b">' + SYNC + '</div></div>'
             + mr('expand_less' if long else 'expand_more', 24, 'color:var(--onv)') + '</div>')
    if long:
        style += '<div style="padding-bottom:16px">' + v3_preview(h=82) + '<div style="height:12px"></div>' + v3_style_controls(compact=True, width=361) + '</div>'
    hist = ('<div class="lt3" style="min-height:56px"><div class="x"><div class="a">本地互动记录</div></div>' + mr('expand_less' if long else 'expand_more', 24, 'color:var(--onv)') + '</div>')
    if long:
        hist += ''.join(f'<div style="font-size:13px;padding:8px 0">{h}</div>' for h in [x.replace('🌶️', e('🌶️')).replace('📺', e('📺')) for x in HIST])
    return ('<div style="padding:12px 16px 16px">'
            '<div style="display:flex;align-items:center"><span class="t20" style="flex:1">本地互动体验</span><span class="ibx">' + mr('close', 24, 'color:var(--on)') + '</span></div>'
            '<div class="t12">资料、体验币、礼物和记录只保存在本机，不会向直播平台提交。</div><div style="height:12px"></div>'
            '<div style="display:flex;align-items:center;gap:12px"><div class="tf3" style="flex:1"><label>本地昵称</label>Pure Live</div>'
            '<span class="chip3">' + mr('toll', 18) + f'{1390 if long else 1000} 电池 · 用户等级 1</span></div><div style="height:10px"></div>'
            f'<div class="t14m">本地头衔</div><div class="wrap" style="column-gap:8px;margin-top:-2px">{chips}</div>'
            '<div class="lt3"><div class="x"><div class="a">在画面显示本地字幕与礼物特效</div><div class="b">关闭后仍会保留在本地弹幕列表</div></div><span class="sw on"></span></div>'
            + style +
            '<div style="display:flex;align-items:center;gap:4px"><div class="tf3" style="flex:1;height:48px;color:rgba(67,71,78,.6);font-size:13px">' + HINT3 + '</div>'
            '<div class="fab">' + mr('send', 22) + '</div></div><div style="height:16px"></div>'
            f'<div class="t14m">本地礼物</div><div class="grid4" style="margin-top:8px">{tiles}</div><div style="height:12px"></div>'
            '<div style="display:flex;align-items:center;gap:6px"><span class="t14m" style="flex:1">本地体验币</span><span class="ob3">+500</span><span class="ob3">+2000</span><span class="ob3">+10000</span></div>'
            f'<div style="height:8px"></div>{hist}</div>')


def v3_sheet_page():
    body = v3_room() + '<div class="scrim"></div><div class="bs3"><div class="handle"><i></i></div>' + v3_sheet_body() + '</div>'
    return page(393, 852, 3, body)


def v3_sheet_long_page():
    body = '<div style="background:var(--scc);border-radius:24px 24px 0 0"><div class="handle"><i></i></div>' + v3_sheet_body(long=True) + '</div>'
    return page(393, 2600, 2, body, crop=True, extra='.ph{height:auto;background:#fff}')


def v3_sheet_wide_page():
    """Wide (> 680, live_play_content.dart): the same modal sheet, capped at 640 and centred."""
    w, h = 1280, 800
    cw = 400
    hdr = ('<div class="appbar"><div class="back">' + mi('arrow_back') + '</div><span class="av" style="background-image:url(.cache/img/65.jpg)"></span>'
           '<div class="tt" style="margin-left:8px"><div class="v3nick" style="font-size:11px">晚风</div><div class="v3area" style="font-size:11px">哔哩哔哩 / 唱见电台</div></div>'
           '<div style="height:40px;padding:0 14px;border-radius:6px;background:rgba(54,97,142,.49);color:#fff;font-size:12px;display:flex;align-items:center;margin:0 5px 0 2px">已关注</div>'
           '<div style="height:48px;padding:0 8px;border-radius:12px;background:var(--schh);color:var(--onv);display:flex;align-items:center;gap:4px;font-size:11px;font-weight:600">' + rx('f05a', 14) + '录制</div>'
           + ib(rx('ea42')) + '<div style="width:4px"></div></div>')
    stage = ('<div style="flex:1;position:relative;background:#000;display:flex;align-items:center"><div style="width:100%;aspect-ratio:16/9;background:#000 url(.cache/img/158.jpg) center 55%/cover"></div>'
             '<div class="v3top"><div class="title">' + TITLE + '</div>' + ib(rx('ee05', 21)) + ib(ci('e806')) + '</div>'
             '<div class="v3bot">' + ib(mr('pause', 28)) + ib(mr('refresh')) + '<div class="pill">' + mr('check', 15) + '已关注</div>' + ib('<span class="dmk open"></span>') + ib('<span class="dmk set"></span>')
             + '<div style="flex:1"></div><div style="padding:0 6px;font-size:15px">默认比例</div>' + ib(mr('volume_up', 22)) + ib(mr('unfold_more', 26)) + ib(mr('fullscreen', 26)) + '</div></div>')
    col = (f'<div style="width:{cw}px;display:flex;flex-direction:column;border-left:1px solid var(--ov)">' + v3_res() + f'<div class="list3">{v3_cards()}</div>' + v3_composer() + '</div>')
    sheet = (f'<div class="bs3" style="left:{(w - 640) / 2:.0f}px;right:auto;width:640px"><div class="handle"><i></i></div>' + v3_sheet_body() + '</div>')
    body = hdr + f'<div style="flex:1;display:flex;min-height:0">{stage}{col}</div><div class="scrim"></div>{sheet}<div class="syn" style="top:6px">示意图片</div>'
    return page(w, h, 1.5, body, frame='win', extra='.win{display:flex;flex-direction:column}')


# ---------- v3 settings ----------
def v3_switch(icon, title, sub, on=True):
    return ('<div class="swt">' + mr(icon) + f'<div class="x"><div class="a">{title}</div><div class="b">{sub}</div></div><span class="sw{" on" if on else ""}"></span></div>')


def v3_settings_body(enabled=True):
    o = ['<div style="padding:12px 16px 32px">', '<div class="gt12">本地用户与互动</div><div class="card3">'
         + v3_switch('auto_awesome', '启用本地互动体验', '关闭后隐藏直播间入口并停止生成本地字幕和礼物效果', enabled) + '</div>']
    if enabled:
        packs = ''.join(f'<span class="ch3{" on" if i == 0 else ""}" style="{"background:rgba(0,174,236,.18);border-color:transparent" if i == 0 else ""}">'
                        + (mr('check', 18) if i == 0 else (e(b, 15) if ord(b[0]) > 0x2000 else f'<b style="font-size:11px">{b}</b>')) + f'{n}</span>' for i, (b, n) in enumerate(PACKS))
        gifts = ''.join(f'<span class="gch">{e(em)}&nbsp;{nm} · {pr}</span>' for em, nm, pr in BILI_GIFTS)
        o.append('<div style="height:20px"></div><div class="gt12">平台体验资源包</div><div class="card3" style="padding:14px">'
                 '<div class="t12 onv">切换预览各平台的主题色、等级称呼、体验币和礼物目录；直播间会自动使用当前平台资源包。</div><div style="height:2px"></div>'
                 f'<div class="wrap" style="column-gap:8px;row-gap:0">{packs}</div><div style="height:6px"></div>'
                 '<div class="pack"><div class="t15">' + e('📺') + ' 哔哩哔哩</div><div style="height:4px"></div>'
                 '<div style="font-size:13px;font-weight:600;color:#00AEEC">用户等级 Lv.1 · 1000 电池</div><div style="height:10px"></div>'
                 f'<div class="wrap" style="gap:8px 10px">{gifts}</div></div></div>')
        chips = ''.join(f'<span class="ch3{" on" if i == 0 else ""}">' + (mr('check', 18) if i == 0 else '') + f'{t}</span>' for i, t in enumerate(TITLES))
        o.append('<div style="height:20px"></div><div class="gt12">本地用户资料</div><div class="card3">'
                 '<div style="padding:10px 16px 4px"><div class="tf3" style="background:var(--scl)"><label style="background:#F6F7FC">本地昵称</label>Pure Live</div></div>'
                 f'<div style="padding:8px 16px 14px"><div class="t14m">本地头衔</div><div class="wrap" style="column-gap:8px;margin-top:-2px">{chips}</div></div>'
                 + v3_switch('subtitles', '在画面显示本地字幕与礼物特效', '关闭后仍会保留在本地弹幕列表') + '<div class="dv"></div>'
                 + v3_switch('workspace_premium', '显示平台身份徽章', '在本地弹幕昵称前显示当前平台样式徽章') + '<div class="dv"></div>'
                 + v3_switch('military_tech', '显示本地体验等级', '在本地弹幕和礼物中显示按体验值计算的等级') + '<div class="dv"></div>'
                 + v3_switch('celebration', '显示本地礼物特效', '礼物在画面中显示平台主题横幅；高价值礼物使用大特效') + '<div class="dv"></div>'
                 '<div class="swt">' + mr('toll') + '<div class="x"><div class="a">体验币与等级</div><div class="b">1000 · Lv.1</div></div></div></div>')
        o.append('<div style="height:20px"></div><div class="gt12">本地弹幕样式</div><div class="card3" style="padding:14px">'
                 + v3_preview() + '<div style="height:16px"></div>' + v3_style_controls(width=333) + '</div>'
                 '<div style="height:12px"></div><div class="t12 onv" style="padding:0 4px">启用后可从直播间右上角菜单进入本地互动面板。</div>')
        o.append('<div style="height:20px"></div><div class="gt12">本地体验币与记录</div><div class="card3" style="padding:14px">'
                 '<div class="t12 onv">体验币仅保存在本机，用于预览礼物、等级和头衔效果。</div><div style="height:10px"></div>'
                 '<div class="wrap" style="gap:8px"><span class="ob3">+500</span><span class="ob3">+2000</span><span class="ob3">+10000</span></div>'
                 '<div class="tb">' + mi('delete_sweep', 18) + '清空本地互动记录</div></div>')
    o.append('</div>')
    return ''.join(o)


def v3_settings_appbar():
    return '<div class="apb"><div class="back" style="width:56px;height:56px;display:grid;place-items:center">' + mi('arrow_back') + '</div><div class="c">本地用户与互动</div></div>'


def v3_settings_page():
    return page(393, 4200, 2, STATUS + v3_settings_appbar() + v3_settings_body(), crop=True, extra='.ph{height:auto}')


def v3_settings_off_page():
    return page(393, 852, 3, STATUS + v3_settings_appbar() + v3_settings_body(enabled=False) + GEST)


# =====================================================================
# new design
# =====================================================================
def v4_appbar(n=True):
    return ('<div class="appbar"><div class="back">' + mi('arrow_back') + '</div><span class="av" style="background-image:url(.cache/img/65.jpg)"></span>'
            '<div class="tt"><div class="n">晚风</div><div class="s">哔哩哔哩 · 唱见电台</div></div>'
            '<div class="fol on">' + rx('eb7b') + '已关注</div><div class="recbtn"><span class="ring"><i></i></span></div>'
            + ib(rx('ea42'), 5 if n else None) + '<div style="width:4px"></div></div>')


def v4_video(fly='', overlay=''):
    top = ('<div class="vtop"><div class="title">' + TITLE + '</div>' + ib(rx('ee05', 21), cls='ib vic') + ib(rx('f235'), cls='ib vic') + ib(ci('e806'), cls='ib vic') + '</div>')
    bot = ('<div class="vbot">' + ib(mr('pause', 28), cls='ib vic') + ib(mr('refresh'), cls='ib vic') + ib('<span class="dmk open"></span>', cls='ib vic')
           + ib('<span class="dmk set"></span>', cls='ib vic') + '<div style="flex:1"></div>' + ib(mr('screen_rotation_alt', 21), cls='ib vic') + ib(mr('fullscreen', 26), cls='ib vic') + '</div>')
    dms = '<div class="dm" style="left:150px;top:62px">前排支持！</div><div class="dm" style="left:24px;top:98px">这首好好听</div>'
    return f'<div class="video" style="background-image:url(.cache/img/158.jpg);flex:none">{dms}{fly}{top}{bot}{overlay}</div>'


def v4_info():
    return ('<div class="info" style="flex:none"><div class="l1"><span class="t">' + TITLE + '</span><span class="more">详情' + rx('ea4e', 18) + '</span></div>'
            '<div class="l2"><div class="figs"><span class="fg"><span class="mr">people_alt</span><b>1.2万</b></span><span class="fg"><span class="mr">whatshot</span><b>84.7万</b></span>'
            '<span class="fg"><span class="mr">schedule</span><b>2:18</b></span></div><div class="chip">原画' + rx('ea4e', 18) + '</div><div class="chip">线路 1' + rx('ea4e', 18) + '</div></div></div><hr>'
            '<div class="tabs" style="flex:none"><div class="on">弹幕列表</div><div>醒目留言<span class="badge">2</span></div><div>弹幕设置</div><div>屏蔽管理</div></div>')


def v4_rows(local=(), k=6):
    rows = ''.join(f'<div class="row"><span class="u" style="{"" if c == "#000" else "color:" + c}">{u}：</span>{t}</div>' for c, u, t in CHAT[:k])
    return '<div class="sys">弹幕服务器连接正常</div>' + rows + ''.join(local)


def local_row(n=None, gift=False):
    who = '<span class="ltag">本地</span><span class="bdg">' + e('📺') + ' 舰队等级 Lv.1</span><span class="u">听众 · Pure Live：</span>'
    msg = ('送出 ' + e('🌶️') + ' <b style="color:#D93636;font-weight:600">辣条</b> ×1') if gift else '主播晚上好'
    return f'<div class="row"{N(n, "tr")}>{who}{msg}</div>'


def composer(n=True, text=None, star='var(--primary)', cls='cmp'):
    inner = f'<span class="tx">{text}</span>' if text else HINT4
    return (f'<div class="{cls}"><div class="fld"{N(2 if n else None, "tc")}><span class="p"{N(1 if n else None, "tl")}>' + mr('auto_awesome', 19, f'color:{star}') + f'</span>{inner}</div>'
            f'<div class="fab"{N(3 if n else None, "tr")}>' + mr('send', 22) + '</div></div>')


def v4_room(local=(), fly='', overlay='', video_overlay='', comp=True, n=True, k=6):
    return (STATUS + v4_appbar(n) + v4_video(fly, video_overlay) + v4_info() + f'<div class="list">{v4_rows(local, k)}</div>'
            + (composer(n) if comp else '') + '<div style="height:14px;background:var(--scl);flex:none"></div>' + overlay + SYN + GEST)


def gfx4(x, y, full, color=None, n=None):
    color = color or ('#FF6392' if full else '#FF6666')  # gift colours, local_interaction_controller.dart:530,544
    """New gift effect: centred on the visible picture, two lines, a solid ring instead of a blurred glow."""
    em, name = ('⚓', '大航海') if full else ('🌶️', '辣条')
    big = 44 if full else 30
    return (f'<div class="gfx" style="left:{x}px;top:{y}px;display:flex;align-items:center;gap:12px;text-align:left;padding:{"14px 22px 14px 16px" if full else "10px 18px 10px 12px"};'
            f'background:linear-gradient(90deg,{color}F0,rgba(0,0,0,.78));box-shadow:0 0 0 {4 if full else 3}px {color}59;white-space:nowrap">'
            f'{e(em, big)}<div><div style="font-size:{19 if full else 16}px">Pure Live 送出 {name} ×1</div>'
            f'<div style="font-size:12px;font-weight:500;opacity:.88">{e("📺")} 舰队等级 Lv.{4 if full else 1} · 听众</div></div></div>')


def v4_room_page():
    fly = '<div class="ldm" style="left:96px;top:128px">主播晚上好</div>'
    body = v4_room(local=[local_row(4), local_row(gift=True)], fly=fly, k=5)
    return page(393, 852, 3, body)


def p_header(title, back=False, link=None, n_link=None, n_close=7, n_back=None, n=True, link_tag=None):
    nn = (lambda k: k) if n else (lambda k: None)
    return ('<div class="p-h">' + (f'<span class="bk"{N(nn(n_back))}>' + mi('arrow_back') + '</span>' if back else '')
            + f'<span class="t">{title}</span>'
            + (f'<span class="lk"{N(nn(n_link), None, link_tag)}>{link}' + rx('ea6e', 18) + '</span>' if link else '')
            + f'<span class="x"{N(nn(n_close))}>' + mr('close', 22) + '</span></div>')


def panel_body(n=True, full=False, history=True, coins=1000, lv=1):
    nn = (lambda k: k) if n else (lambda k: None)
    tiles = ''.join(f'<div class="gt{" dim" if pr > coins else ""}"' + (N(nn(8)) if i == 0 else '') + f'>{e(em)}<span>{nm}</span><small>' + mr('toll', 13) + f'{pr}</small></div>'
                    for i, (em, nm, pr) in enumerate(BILI_GIFTS))
    o = ['<div class="desc">资料、体验币、礼物和记录只保存在本机，不会向直播平台提交。</div>',
         '<div class="idc"><span class="av2">' + e('📺') + '</span><div style="flex:1;min-width:0"><div class="n">听众 · Pure Live</div>'
         f'<div class="m">哔哩哔哩 · 用户等级 Lv.{lv} · {coins} 电池</div></div></div>',
         '<div class="pcmp">' + composer(n, cls='grow" style="display:flex;align-items:center;gap:6px').replace('class="grow"', 'class="grow"') + '</div>',
         '<div class="sec">本地礼物</div>',
         f'<div class="grid4" style="padding:0 16px">{tiles}</div>',
         f'<div class="rch"><span class="l">本地体验币</span><span class="ob"{N(nn(9))}>+500</span><span class="ob">+2000</span><span class="ob">+10000</span></div>',
         '<div class="sec" style="padding-top:20px">我的资料</div>',
         f'<div class="tf"{N(nn(10))}><label>本地昵称</label>Pure Live<small>9 / 20</small></div>',
         f'<div class="lab" style="padding-top:14px">本地头衔</div><div class="wrp"{N(nn(11), "tr")}>'
         + ''.join(f'<span class="tag2{" on" if i == 0 else ""}">' + (rx('eb7b', 16) if i == 0 else '') + f'{t}</span>' for i, t in enumerate(TITLES)) + '</div>']
    if full:
        o += ['<div class="sec" style="padding-top:20px">画面上</div>',
              f'<div class="swr"{N(nn(12))}><div class="x"><div class="a">本地弹幕在画面上飞过</div><div class="b">关闭后只出现在弹幕列表</div></div><span class="sw on"></span></div>',
              f'<div class="swr"{N(nn(13))}><div class="x"><div class="a">显示本地礼物特效</div><div class="b">礼物在画面中间显示平台主题横幅；高价值礼物使用大特效</div></div><span class="sw on"></span></div>',
              f'<div class="navr"{N(nn(14))}><div class="x"><div class="a">本地弹幕样式</div></div><span class="v">清爽</span>' + rx('ea6e', 20) + '</div>',
              f'<div class="sec" style="padding-top:20px;display:flex;align-items:center">本地互动记录<span style="margin-left:auto;font-weight:500;color:var(--onv)">3 条</span></div>']
        if history:
            o.append('<div class="hist">' + ''.join(f'<div>{h}</div>' for h in [x.replace('🌶️', e('🌶️')).replace('📺', e('📺')) for x in HIST]) + '</div>'
                     f'<div style="padding:4px 12px 20px"><span class="tlk" style="display:inline-flex"{N(nn(15))}>' + mi('delete_sweep', 18) + '&nbsp;清空记录</span></div>')
        else:
            o.append('<div class="hist"><div style="border:0">还没有互动记录</div></div><div style="height:20px"></div>')
    return ''.join(o)


def v4_panel_page(n=True, gift=False):
    coins, lv = (1020, 4) if gift else (1000, 1)
    under = ('<div class="under" style="top:313px">' + p_header('本地互动体验', link='设置', n_link=6, n=n)
             + '<div class="pbody">' + panel_body(n, coins=coins, lv=lv) + '</div></div>')
    vo = gfx4(196, 120, True) if gift else ''
    body = v4_room(overlay=under, video_overlay=vo, comp=False, n=False)
    return page(393, 852, 3, body)


def v4_panel_full_page():
    body = ('<div style="background:var(--surface)">' + p_header('本地互动体验', link='设置', n_link=6)
            + panel_body(True, full=True, coins=1390) + '</div>')
    return page(393, 2400, 2, body, crop=True, extra='.ph{height:auto;background:#fff}')


# ---------- new style panel ----------
def style_preview(placement='scroll'):
    top = {'scroll': 'top:30px;left:40px', 'bottom': 'bottom:10px;left:50%;transform:translateX(-50%)'}[placement]
    return ('<div class="pvn"><span class="tv">' + mr('live_tv', 38) + '</span><span class="badge3">' + mr('play_circle_filled', 12) + '实时预览</span>'
            f'<span class="tx" style="{top}">Pure Live 本地弹幕预览</span></div>')


def style_body(n=True, full=False, preview=True):
    nn = (lambda k: k) if n else (lambda k: None)
    o = []
    if preview:
        o.append(style_preview())
    o.append('<div class="sec" style="padding-top:12px">样式模板</div>')
    o.append(f'<div class="wrp" style="padding-top:2px"{N(nn(18), "tr")}>' + ''.join(
        f'<span class="tag2{" on" if i == 0 else ""}">' + (rx('eb7b', 16) if i == 0 else f'<i style="width:10px;height:10px;border-radius:5px;background:#{c};box-shadow:0 0 0 1px rgba(0,0,0,.2)"></i>') + f'{nm}{"（默认）" if i == 0 else ""}</span>'
        for i, (nm, c) in enumerate(PRESETS)) + '</div>')
    o.append('<div class="sec" style="padding-top:18px">显示位置</div>')
    o.append(f'<div class="wrp" style="padding-top:2px"{N(nn(19), "tr")}>' + ''.join(
        f'<span class="tag2{" on" if i == 0 else ""}">' + (rx('eb7b', 16) if i == 0 else mr(ic, 17)) + f'{nm}</span>' for i, (nm, ic) in enumerate(PLACES)) + '</div>')
    o.append('<div class="sec" style="padding-top:18px">字体与颜色</div>')
    o.append(f'<div class="wrp" style="padding-top:2px"{N(nn(20), "tr")}>' + ''.join(
        f'<span class="tag2{" on" if i == 0 else ""}" style="font-family:{fam}">' + (rx('eb7b', 16) if i == 0 else '') + f'{nm}</span>' for i, (nm, fam) in enumerate(FONTS)) + '</div>')
    o.append(f'<div class="lab">弹幕颜色</div><div class="sws"{N(nn(21), "tr")}>' + ''.join(
        f'<span class="swc{" on" if i == 0 else ""}"><i style="background:#{c}{";border-color:var(--outline)" if c == "FFFFFF" and i else ""}">' + (mr('check', 17, 'color:#000000CC') if i == 0 else '') + '</i></span>'
        for i, c in enumerate(DM_COLORS)) + '</div>')

    def sl(label, val, frac, nn_=None, gray=False):
        return (f'<div class="slr{" gray" if gray else ""}"{N(nn_, "tr")}><div class="h"><span>{label}</span><span class="vpill">{val}</span></div>'
                f'<div class="t"><s><i style="width:{frac * 100:.0f}%"></i><u style="left:{frac * 100:.0f}%"></u></s></div></div>')
    o.append(f'<div class="grp" style="margin-top:10px;padding-bottom:6px"{N(nn(22), "tr")}>' + sl('字体大小', '19 px', 5 / 18) + sl('滚动速度', '130 px/s', 70 / 200)
             + sl('不透明度', '100%', 1) + sl('字间距', '0.0', .5 / 3.5) + '</div>')
    if full:
        o.append('<div class="sec" style="padding-top:18px">文字效果</div>')
        o.append(f'<div class="wrp" style="padding-top:2px"{N(nn(23), "tr")}>' + ''.join(
            f'<span class="tag2{" on" if on else ""}">' + (rx('eb7b', 16) if on else mr(ic, 17)) + f'{nm}</span>'
            for nm, ic, on in [('粗体', 'format_bold', False), ('斜体', 'format_italic', False), ('描边', 'border_color', True), ('阴影 / 微光', 'blur_on', False)]) + '</div>')

        def pal(sel, gray=False):
            return (f'<div class="sws{" gray" if gray else ""}">' + ''.join(
                f'<span class="swc{" on" if c == sel else ""}"><i style="background:#{c};width:28px;height:28px">' + (mr('check', 15, 'color:#fff') if c == sel else '') + '</i></span>' for c in FX_COLORS) + '</div>')
        o.append(f'<div class="grp" style="margin-top:10px;padding-bottom:6px"><div{N(nn(24), "tr")}><div class="lab">描边颜色</div>' + pal('000000') + sl('描边宽度', '1.5', 1 / 3.5) + '</div></div>')
        o.append(f'<div class="grp gray" style="margin-top:10px;padding-bottom:6px"><div{N(nn(25), "tr")}><div class="lab">阴影颜色<span style="font-size:12px;color:var(--onv);margin-left:8px">打开“阴影 / 微光”后可调</span></div>'
                 + pal('000000') + sl('模糊强度', '2.0', 2 / 6) + sl('阴影偏移', '1.0', 1 / 4) + '</div></div>')
        o.append(f'<div class="grp gray" style="margin-top:10px;padding-bottom:6px"><div{N(nn(26), "tr")}>' + sl('固定弹幕停留时间', '4.0 s', 2 / 8)
                 + '<div style="padding:0 20px 8px;font-size:12px;color:var(--onv)">显示位置选“顶部固定”或“底部固定”时可调</div></div></div>')
        o.append('<div style="display:flex;gap:6px;align-items:flex-start;padding:16px 20px 24px">' + mr('sync', 16, 'color:var(--primary)') + f'<span class="t12 onv">{SYNC}</span></div>')
    return ''.join(o)


def style_header(n=True, back=False):
    nn = (lambda k: k) if n else (lambda k: None)
    return ('<div class="p-h">' + (f'<span class="bk"{N(nn(17))}>' + mi('arrow_back') + '</span>' if back else '')
            + '<span class="t">本地弹幕样式</span>' + f'<span class="tlk"{N(nn(16))}>恢复默认</span>'
            + f'<span class="x"{N(nn(7))}>' + mr('close', 22) + '</span></div>')


def v4_style_page():
    under = ('<div class="under" style="top:313px">' + style_header() + style_preview()
             + '<div class="pbody">' + style_body(preview=False) + '</div></div>')
    fly = '<div class="ldm" style="left:96px;top:128px">主播晚上好</div>'
    body = v4_room(overlay=under, fly=fly, comp=False, n=False)
    return page(393, 852, 3, body)


def v4_style_full_page():
    body = '<div style="background:var(--surface)">' + style_header(back=True) + style_body(full=True) + '</div>'
    return page(393, 2400, 2, body, crop=True, extra='.ph{height:auto;background:#fff}')


# ---------- new fullscreen (U.2c bars) ----------
def v4_fs_bars(w, compact=False, focused=None, n=False, opened=False):
    nn = (lambda k: k) if n else (lambda k: None)
    lead = ib(mi('arrow_back'), cls='ib vic') + '<div class="time" style="margin:14px 6px 0 2px">21:36</div><div class="bat" style="margin-top:16px">76</div>'
    trail = (ib(mr('swap_horiz'), cls='ib vic') + ib(rx('ee05', 21), cls='ib vic') + ib(rx('f235'), cls='ib vic') + ib(ci('e806'), cls='ib vic')
             + '<div class="ib"><span class="ring" style="border-color:#fff"><i></i></span></div>' + ib(rx('ea42'), cls='ib vic'))
    left = (ib(mr('pause', 28), cls='ib vic') + ib(mr('refresh'), cls='ib vic')
            + '<div style="height:32px;border-radius:16px;display:flex;align-items:center;gap:3px;padding:0 12px 0 9px;font-size:13px;font-weight:500;background:rgba(255,255,255,.18);color:#fff;margin:0 4px;flex:none">' + rx('eb7b', 16) + '已关注</div>'
            + ib('<span class="dmk open"></span>', cls='ib vic') + ib('<span class="dmk set"></span>', cls='ib vic'))
    if compact:
        mid = f'<div style="width:40px;height:40px;border-radius:20px;background:{"rgba(160,202,253,.35)" if opened else "rgba(0,0,0,.54)"};border:1px solid {"#A0CAFD" if opened else "rgba(255,255,255,.24)"};display:grid;place-items:center;color:#fff;flex:none"{N(nn(27))}>' + mr('auto_awesome', 18) + '</div>'
    else:
        mid = fs_composer(focused, n)
    right = ('<div class="vchip" style="margin:0 3px">原画' + rx('ea4e', 18) + '</div><div class="vchip" style="margin:0 3px">线路1' + rx('ea4e', 18) + '</div>'
             + ib(mr('screen_rotation_alt', 21), cls='ib vic') + ib(rx('ea80', 22), cls='ib vic') + ib(mr('fullscreen_exit', 26), cls='ib vic'))
    return (f'<div class="vtop">{lead}<div class="title">{FS_TITLE}</div>{trail}</div>'
            '<div class="vbot" style="padding:0 12px 4px"><div style="display:flex;align-items:center;height:48px;flex:none">' + left + '</div>'
            f'<div style="flex:1;display:flex;justify-content:center;align-items:center;min-width:0;padding:0 8px;height:48px">{mid}</div>'
            '<div style="display:flex;align-items:center;height:48px;flex:none">' + right + '</div></div>')


def fs_composer(text=None, n=False, maxw=420, star='#fff'):
    nn = (lambda k: k) if n else (lambda k: None)
    border = '1.3px solid #A0CAFD' if text else '1px solid rgba(255,255,255,.24)'
    inner = (f'<span style="color:#fff;font-size:14px;font-weight:600">{text}<span style="display:inline-block;width:1.5px;height:16px;background:#A0CAFD;vertical-align:-3px;margin-left:1px"></span></span>'
             if text else f'<span style="color:rgba(255,255,255,.65);font-size:13px">{HINT4}</span>')
    return (f'<div style="flex:1;max-width:{maxw}px;height:40px;border-radius:20px;background:rgba(0,0,0,.54);border:{border};display:flex;align-items:center;overflow:hidden;white-space:nowrap;min-width:0"{N(nn(2), "tc")}>'
            f'<span style="width:44px;display:grid;place-items:center;flex:none"{N(nn(1), "tl")}>' + mr('auto_awesome', 18, f'color:{star}') + f'</span>{inner}'
            f'<span style="margin-left:auto;width:44px;display:grid;place-items:center;flex:none"{N(nn(3), "tr")}>' + mr('send', 18, 'color:#fff') + '</span></div>')


LOCK = '<div style="position:absolute;right:20px;top:50%;transform:translateY(-50%);width:50px;height:50px;border-radius:25px;background:rgba(0,0,0,.38);display:grid;place-items:center;color:#fff;z-index:6">' + mr('lock_open', 28) + '</div>'
FS_EXTRA = '.fs{background-image:url(.cache/img/274.jpg);background-position:center 40%}'


def v4_fullscreen_page():
    body = SYN + FS_DMS + '<div class="ldm" style="left:460px;top:190px">主播晚上好</div>' + v4_fs_bars(852, focused='今晚唱哪首', n=True) + LOCK
    return page(852, 393, 2, body, frame='fs', extra=FS_EXTRA)


def v4_narrow_open_page():
    row = ('<div style="position:absolute;left:12px;right:12px;bottom:64px;z-index:7;display:flex;justify-content:center">'
           + fs_composer('今晚唱哪首', True, maxw=520) + '</div>')
    body = SYN + FS_DMS + v4_fs_bars(740, compact=True, n=True, opened=True) + row + LOCK
    return page(740, 360, 2, body, frame='fs', extra=FS_EXTRA + '.vbot{height:120px}')


def v4_landscape_panel_page(kind='panel'):
    if kind == 'panel':
        side = '<div class="side">' + p_header('本地互动体验', link='设置', n=False) + '<div class="pbody">' + panel_body(False, coins=990) + '</div></div>'
        eff = gfx4(246, 196, False)
    else:
        side = '<div class="side">' + style_header(n=False) + style_preview() + '<div class="pbody">' + style_body(n=False, preview=False) + '</div></div>'
        eff = ''
    body = SYN + FS_DMS + v4_fs_bars(852) + side + eff
    return page(852, 393, 2, body, frame='fs', extra=FS_EXTRA)


# ---------- new wide (U.2d) ----------
def v4_wide_page(panel=False):
    w, h = 1280, 800
    cw = 400
    hdr = ('<div class="appbar"><div class="back">' + mi('arrow_back') + '</div><span class="av" style="background-image:url(.cache/img/65.jpg)"></span>'
           '<div class="tt"><div class="n">晚风</div><div class="s">哔哩哔哩 · 唱见电台</div></div>'
           '<div class="fol on">' + rx('eb7b') + '已关注</div><div class="recbtn"><span class="ring"><i></i></span></div>' + ib(rx('ea42')) + '<div style="width:4px"></div></div>')
    vo = gfx4((w - cw) / 2, 372, True) if panel else ''
    stage = ('<div style="flex:1;position:relative;background:#000;display:flex;align-items:center;overflow:hidden"><div style="width:100%;aspect-ratio:16/9;background:#000 url(.cache/img/158.jpg) center 55%/cover"></div>'
             '<div class="vtop"><div class="title">' + TITLE + '</div>' + ib(rx('ee05', 21), cls='ib vic') + ib(ci('e806'), cls='ib vic') + '</div>'
             '<div class="ldm" style="left:300px;top:250px">主播晚上好</div>'
             '<div class="vbot">' + ib(mr('pause', 28), cls='ib vic') + ib(mr('refresh'), cls='ib vic') + ib('<span class="dmk open"></span>', cls='ib vic') + ib('<span class="dmk set"></span>', cls='ib vic')
             + '<div style="flex:1"></div><div style="display:flex;align-items:center;gap:6px;color:#fff;margin:0 4px">' + mr('volume_up', 22) + '<div style="width:80px;height:4px;border-radius:2px;background:rgba(255,255,255,.35);position:relative"><i style="position:absolute;left:0;top:0;bottom:0;width:70%;background:#fff;border-radius:2px"></i></div></div>'
             + ib(mr('vertical_split', 24), cls='ib vic') + ib(mr('unfold_more', 26), cls='ib vic') + ib(mr('fullscreen', 26), cls='ib vic') + '</div>' + vo + '</div>')
    if panel:
        col = (f'<div class="col" style="width:{cw}px;display:flex;flex-direction:column;border-left:1px solid var(--ov);position:relative;background:var(--surface)">'
               + p_header('本地互动体验', link='设置', n=False) + '<div class="pbody">' + panel_body(False, coins=1020, lv=4) + '</div></div>')
    else:
        info = ('<div class="info" style="flex:none"><div class="l1"><span class="t">' + TITLE + '</span><span class="more">详情' + rx('ea4e', 18) + '</span></div>'
                '<div class="l2"><div class="figs"><span class="fg"><span class="mr">people_alt</span><b>1.2万</b></span><span class="fg"><span class="mr">whatshot</span><b>84.7万</b></span>'
                '<span class="fg"><span class="mr">schedule</span><b>2:18</b></span></div><div class="chip">原画' + rx('ea4e', 18) + '</div><div class="chip">线路1' + rx('ea4e', 18) + '</div></div></div><hr>'
                '<div class="tabs" style="flex:none"><div class="on">弹幕列表</div><div>醒目留言<span class="badge">2</span></div><div>弹幕设置</div><div>屏蔽管理</div></div>')
        col = (f'<div style="width:{cw}px;display:flex;flex-direction:column;border-left:1px solid var(--ov);background:var(--surface)">' + info
               + f'<div class="list">{v4_rows([local_row(), local_row(gift=True)], 8)}</div>' + composer(False) + '</div>')
    body = hdr + f'<div style="flex:1;display:flex;min-height:0">{stage}{col}</div><div class="syn" style="top:6px">示意图片</div>'
    return page(w, h, 1.5, body, frame='win', extra='.win{display:flex;flex-direction:column}')


# ---------- new settings ----------
def n_switch(icon, title, sub, on=True, n=None):
    return (f'<div class="swt swtn"{N(n, "tr")}>' + mr(icon) + f'<div class="x"><div class="a">{title}</div><div class="b">{sub}</div></div><span class="sw{" on" if on else ""}"></span></div>')


def v4_settings_body(enabled=True, n=True, maxw=None):
    nn = (lambda k: k) if n else (lambda k: None)
    o = [f'<div style="padding:12px 16px 32px;{"max-width:%dpx;margin:0 auto" % maxw if maxw else ""}">',
         '<div class="st">本地互动</div><div class="cardn">' + n_switch('auto_awesome', '启用本地互动体验', '关闭后隐藏直播间入口并停止生成本地弹幕和礼物特效', enabled, nn(28)) + '</div>'
         '<div class="t12 onv" style="padding:8px 8px 0">开着时，直播间弹幕列表下方和全屏下栏有本地弹幕输入框，右上角菜单里有“本地互动体验”。</div>']
    if not enabled:
        o.append('</div>')
        return ''.join(o)
    chips = ''.join(f'<span class="tag2{" on" if i == 0 else ""}">' + (rx('eb7b', 16) if i == 0 else '') + f'{t}</span>' for i, t in enumerate(TITLES))
    o.append('<div style="height:20px"></div><div class="st">本地用户资料</div><div class="cardn" style="padding-bottom:6px">'
             f'<div class="tf" style="margin:16px 16px 0"{N(nn(10))}><label style="background:var(--scl)">本地昵称</label>Pure Live<small>9 / 20</small></div>'
             f'<div class="lab" style="padding:14px 16px 0">本地头衔</div><div class="wrp" style="padding-bottom:8px"{N(nn(11), "tr")}>{chips}</div>'
             '<div class="dv"></div><div class="swt swtn">' + mr('toll') + '<div class="x"><div class="a">体验币与等级</div><div class="b">本地等级 Lv.1 · 1390 本地体验币</div></div></div></div>')
    o.append('<div style="height:20px"></div><div class="st">画面上</div><div class="cardn">'
             + n_switch('subtitles', '本地弹幕在画面上飞过', '关闭后只出现在弹幕列表', True, nn(12)) + '<div class="dv"></div>'
             + n_switch('workspace_premium', '显示平台身份徽章', '在本地弹幕昵称前显示当前平台样式徽章', True, nn(29)) + '<div class="dv"></div>'
             + n_switch('military_tech', '显示本地体验等级', '在本地弹幕和礼物中显示按体验值计算的等级', True, nn(30)) + '<div class="dv"></div>'
             + n_switch('celebration', '显示本地礼物特效', '礼物在画面中间显示平台主题横幅；高价值礼物使用大特效', True, nn(13)) + '<div class="dv"></div>'
             f'<div class="swt swtn"{N(nn(14), "tr")}>' + mr('auto_awesome') + '<div class="x"><div class="a">本地弹幕样式</div><div class="b">模板、位置、字体、颜色、大小、速度、描边和阴影</div></div>'
             '<span style="font-size:14px;color:var(--onv)">清爽</span>' + rx('ea6e', 20) + '</div></div>')
    packs = ''.join(f'<span class="tag2{" on" if i == 0 else ""}" style="height:32px;{"background:rgba(0,174,236,.18);color:#00658A" if i == 0 else ""}">'
                    + (rx('eb7b', 16) if i == 0 else (e(b, 15) if ord(b[0]) > 0x2000 else f'<b style="font-size:11px;color:var(--onv)">{b}</b>')) + f'{nm}</span>' for i, (b, nm) in enumerate(PACKS))
    gifts = ''.join(f'<span class="gch">{e(em)}&nbsp;{nm} · {pr}</span>' for em, nm, pr in BILI_GIFTS)
    o.append('<div style="height:20px"></div><div class="st">平台体验资源包</div><div class="cardn" style="padding:14px">'
             '<div class="t12 onv">切换预览各平台的主题色、等级称呼、体验币和礼物目录；直播间会自动使用当前平台资源包。</div><div style="height:10px"></div>'
             f'<div class="wrap" style="gap:8px"{N(nn(31), "tr")}>{packs}</div><div style="height:14px"></div>'
             '<div class="pack"><div class="t15">' + e('📺') + ' 哔哩哔哩</div><div style="height:4px"></div>'
             '<div style="font-size:13px;font-weight:600;color:#00658A">用户等级 Lv.1 · 1390 电池</div><div style="height:10px"></div>'
             f'<div class="wrap" style="gap:8px 10px">{gifts}</div></div></div>')
    o.append('<div style="height:20px"></div><div class="st">本地体验币与记录</div><div class="cardn" style="padding:14px">'
             '<div class="t12 onv">体验币仅保存在本机，用于预览礼物、等级和头衔效果。</div><div style="height:10px"></div>'
             f'<div class="wrap" style="gap:8px"><span class="ob"{N(nn(9))}>+500</span><span class="ob">+2000</span><span class="ob">+10000</span></div>'
             '<div style="margin-top:14px;font-size:14px;font-weight:600">本地互动记录 <span style="font-weight:400;color:var(--onv);font-size:13px">3 条</span></div>'
             '<div class="hist" style="padding:2px 0 0">' + ''.join(f'<div style="border-color:var(--ov)">{h}</div>' for h in [x.replace('🌶️', e('🌶️')).replace('📺', e('📺')) for x in HIST]) + '</div>'
             f'<div class="tb" style="padding:0;margin-top:6px"{N(nn(15))}>' + mi('delete_sweep', 18) + '清空本地互动记录</div></div>')
    o.append('</div>')
    return ''.join(o)


def v4_settings_page():
    return page(393, 4200, 2, STATUS + v3_settings_appbar() + v4_settings_body(), crop=True, extra='.ph{height:auto}')


def v4_settings_off_page():
    return page(393, 852, 3, STATUS + v3_settings_appbar() + v4_settings_body(enabled=False, n=False) + GEST)


def v4_settings_wide_page():
    body = ('<div class="apb" style="border-bottom:1px solid var(--ov)"><div class="back" style="width:56px;height:56px;display:grid;place-items:center">' + mi('arrow_back') + '</div><div class="c">本地用户与互动</div></div>'
            '<div style="flex:1;overflow:hidden">' + v4_settings_body(n=False, maxw=720) + '</div>')
    return page(1280, 800, 1.5, body, frame='win', extra='.win{display:flex;flex-direction:column}')


OUT = {
    'v3-room': v3_room_page(), 'v3-gift': v3_gift_page(), 'v3-sheet': v3_sheet_page(), 'v3-sheet-long': v3_sheet_long_page(),
    'v3-sheet-wide': v3_sheet_wide_page(), 'v3-style': v3_style_page(), 'v3-style-full': v3_style_full_page(),
    'v3-style-landscape': v3_style_landscape_page(), 'v3-fullscreen': v3_fullscreen_page(),
    'v3-settings': v3_settings_page(), 'v3-settings-off': v3_settings_off_page(),
    'v4-room': v4_room_page(), 'v4-panel': v4_panel_page(), 'v4-panel-full': v4_panel_full_page(), 'v4-gift': v4_panel_page(n=False, gift=True),
    'v4-style': v4_style_page(), 'v4-style-full': v4_style_full_page(),
    'v4-fullscreen': v4_fullscreen_page(), 'v4-narrow-open': v4_narrow_open_page(),
    'v4-landscape-panel': v4_landscape_panel_page('panel'), 'v4-landscape-style': v4_landscape_panel_page('style'),
    'v4-wide': v4_wide_page(), 'v4-wide-panel': v4_wide_page(panel=True),
    'v4-settings': v4_settings_page(), 'v4-settings-off': v4_settings_off_page(), 'v4-settings-wide': v4_settings_wide_page(),
}
if __name__ == '__main__':
    for name, html in OUT.items():
        open(os.path.join(HERE, name + '.html'), 'w', encoding='utf-8').write(html)
    print(len(OUT), 'pages')
