"""U.8 multi-view: v3 restored and the new design.

v3 (tag v3.2.11):
  page        lib/modules/multiview/multiview_page.dart (display modes :22-27 :353-419,
              toolbar :436-556, side panel :558-574, grid :576-612, 1+3 :614-698,
              big control bar :700-790, sheets :249-339 :792-883, cell :933-1220,
              chips :1231-1286, add slot :1321-1358, immersive restore :1360-1390)
  picker      lib/modules/multiview/widgets/multiview_room_picker.dart
  fullscreen  lib/modules/multiview/widgets/multiview_fullscreen_surface.dart
  controller  lib/modules/multiview/multiview_controller.dart (quad by default :291, 4 cells on
              mobile / 9 on desktop :73 :84, danmaku off :419)
New design: the U.2f quality / line buttons and menus, danmaku settings panel and panel
positions (portrait below the picture, landscape and wide on the right).

    python3 docs/ui/compare/U.8/src/gen.py && python3 tools/ui/mock/render.py docs/ui/compare/U.8/src/ --annotate
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
LOGO = '../../../packages/live_ui/assets/platforms/{}.png'
CSS = '''
.col{display:flex;flex-direction:column}
.ab{height:56px;display:flex;align-items:center;position:relative;flex:none;background:var(--surface)}
.ab .ttl{position:absolute;left:0;right:0;text-align:center;font-size:20px;font-weight:600;pointer-events:none}
.ab .sp{flex:1}.ab .ib{color:var(--onv)}.ab .ib.lead{color:var(--on);margin-left:4px}
.body{flex:1;min-height:0;position:relative;overflow:hidden}
/* ---------- v3 toolbar ---------- */
.seg{display:inline-flex;height:40px;border-radius:20px;box-shadow:inset 0 0 0 1px var(--outline);overflow:hidden}
.seg>span{display:flex;align-items:center;gap:8px;padding:0 12px;font-size:13px;font-weight:500;color:var(--on);border-left:1px solid var(--outline)}
.seg>span:first-child{border-left:0}
.seg>span.on{background:var(--sc);color:var(--osc)}
.seg .rx{font-size:18px}
.acts{display:flex;align-items:center}
.acts .ib{color:var(--onv)}
.acts .ib.dis{color:rgba(25,28,32,.38)}
/* ---------- grid and cells ---------- */
.grid{display:grid;gap:6px;padding:6px;height:100%}
.cell{position:relative;overflow:hidden;background:#000}
.cell.lt{background:var(--scl)}
.vid{position:absolute;inset:0;background:#000 center/contain no-repeat}
.chip3{position:absolute;left:8px;top:8px;display:flex;gap:6px;z-index:3}
.chip3>span{display:flex;align-items:center;gap:5px;height:22px;padding:0 8px;border-radius:10px;background:rgba(0,0,0,.55);color:#fff;font-size:12px;font-weight:600;white-space:nowrap}
.chip3 img{width:13px;height:13px}
.chip3 .af{background:var(--primary);color:#fff;font-weight:700}
.chip3 .af .rx{font-size:13px}
.cc{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:10px;text-align:center;padding:0 12px}
.cc .t{font-size:14px;font-weight:500}.cc .tb{font-size:14px;font-weight:700}.cc .m{font-size:12px;color:rgba(0,0,0,.6)}
.lt .cc .ad{width:54px;height:54px;border-radius:27px;background:rgba(225,226,232,.6);display:grid;place-items:center;color:var(--onv)}
.spin{width:30px;height:30px;border-radius:15px;border:2.5px solid rgba(54,97,142,.2);border-top-color:var(--primary);border-right-color:var(--primary)}
.tonal{height:40px;padding:0 16px 0 12px;border-radius:20px;background:var(--sc);color:var(--osc);display:flex;align-items:center;gap:6px;font-size:13px;font-weight:600}
.qe{position:absolute;left:8px;bottom:8px;z-index:3;display:flex;align-items:center;gap:4px;padding:4px 8px;border-radius:10px;background:rgba(0,0,0,.55);color:#fff;font-size:12px;font-weight:600}
.cbar{position:absolute;left:8px;right:8px;bottom:8px;z-index:4;background:rgba(0,0,0,.55);border-radius:10px;padding:2px;display:flex;overflow:hidden;color:rgba(255,255,255,.92)}
.cbar .ib{width:48px;height:48px}
.dm{position:absolute;white-space:nowrap;color:#fff;font:600 15px 'Noto Sans SC';text-shadow:0 0 1px #000,0 0 1px #000,0 0 2px #000;z-index:2}
/* ---------- sheets (v3 theme: surfaceContainer, drag handle, top radius 24) ---------- */
.scrim{z-index:40}
.bs{position:absolute;left:0;right:0;bottom:0;z-index:41;background:var(--scc);border-radius:24px 24px 0 0;display:flex;flex-direction:column;overflow:hidden}
.bs .hd{height:22px;flex:none;display:grid;place-items:center}.bs .hd i{width:32px;height:4px;border-radius:2px;background:var(--onv);opacity:.4}
.lt2{display:flex;align-items:center;gap:16px;min-height:56px;padding:8px 24px 8px 16px;font-size:16px}
.lt2 .rx,.lt2 .mr{color:var(--onv)}
.lt2.dis{opacity:.38}
.lt2.err .rx{color:var(--error)}
.lt2 .trl{margin-left:auto;color:var(--onv)}
.bs>*{flex:none}
.srch{margin:4px 16px 8px;height:44px;border-radius:12px;background:var(--scl);box-shadow:inset 0 0 0 1px var(--outline);display:flex;align-items:center;gap:8px;padding:0 12px;color:var(--onv);font-size:13px}
.seg2{margin:0 16px 8px;display:flex;justify-content:center}
.pr{display:flex;align-items:center;gap:16px;padding:8px 16px 8px 16px;min-height:64px}
.pr .av{position:relative;width:38px;height:38px;border-radius:19px;background:center/cover;flex:none}
.pr .av img{position:absolute;right:-3px;bottom:-3px;width:18px;height:18px;border-radius:9px;padding:2px;background:#fff}
.pr .x{flex:1;min-width:0}
.pr .n{font-size:14px;font-weight:500;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.pr .s{font-size:12px;color:rgba(0,0,0,.6);white-space:nowrap;overflow:hidden;text-overflow:ellipsis;margin-top:2px}
.pr .st{display:flex;align-items:center;gap:5px;font-size:12px;font-weight:600;flex:none}
.pr .st i{width:7px;height:7px;border-radius:4px;display:block}
.pr .in{font-size:12px;font-weight:600;color:var(--primary);background:var(--pc);height:22px;padding:0 8px;border-radius:11px;display:flex;align-items:center;flex:none}
.side3{flex:none;border-left:1px solid var(--ov);display:flex;flex-direction:column;background:var(--surface)}
.side3 .pt{padding:12px 16px 4px;font-size:15px;font-weight:700}
.restore{position:absolute;right:16px;bottom:16px;width:48px;height:48px;border-radius:14px;background:rgba(230,232,238,.92);display:grid;place-items:center;color:var(--on);box-shadow:0 2px 6px rgba(0,0,0,.2);z-index:10}
.exit{position:absolute;left:12px;top:12px;width:48px;height:48px;border-radius:24px;background:rgba(0,0,0,.68);display:grid;place-items:center;color:#fff;box-shadow:0 2px 6px rgba(0,0,0,.4);z-index:10}
.vol{padding:12px 20px 24px}
.vol .r1{display:flex;justify-content:space-between;align-items:center;font-size:15px;font-weight:500}
.vol .r2{display:flex;align-items:center;gap:8px;color:var(--onv);margin-top:8px}
.vol .r2 .trk{flex:1}
.vol .cap2{font-size:12px;color:var(--onv);margin-top:2px}
.trk{height:4px;border-radius:2px;background:rgba(54,97,142,.2);position:relative}
.trk i{position:absolute;left:0;top:0;bottom:0;border-radius:2px;background:var(--primary)}
.trk u{position:absolute;top:-8px;width:20px;height:20px;border-radius:10px;background:var(--primary);margin-left:-10px}
.sheetbg{background:var(--surface)}
.capx{padding:18px 16px 8px;font-size:13px;font-weight:600;color:var(--onv)}
.bsx{margin:0 0 4px;background:var(--scc);border-radius:24px 24px 0 0;overflow:hidden}
/* ---------- new ---------- */
.tb2{display:flex;align-items:center;gap:2px;padding:6px 8px 6px 12px;flex:none;background:var(--surface)}
.seg3{display:inline-flex;height:36px;border-radius:18px;box-shadow:inset 0 0 0 1px var(--outline);overflow:hidden;flex:none}
.seg3>span{display:flex;align-items:center;gap:6px;padding:0 10px;font-size:14px;font-weight:500;color:var(--on);border-left:1px solid var(--outline);font-feature-settings:'tnum'}
.seg3>span:first-child{border-left:0}
.seg3>span.on{background:var(--sc);color:var(--osc);font-weight:600}
.seg3 .rx{font-size:18px}
.tg{width:38px;height:38px;border-radius:19px;display:grid;place-items:center;color:var(--onv);flex:none}
.tg.on{background:var(--pc);color:var(--opc)}
.tg .dmk{width:22px;height:22px}
.wall{background:#000;flex:none;position:relative}
.wall .grid{gap:3px;padding:3px;height:auto}
.n2{display:grid;place-items:center;min-width:20px;height:20px;padding:0 5px;border-radius:6px;background:rgba(0,0,0,.6);color:#fff;font:700 12px 'Geist','Noto Sans SC'}
.chip4{position:absolute;left:6px;top:6px;display:flex;gap:4px;z-index:3;align-items:center;max-width:calc(100% - 12px)}
.chip4 .nm{display:flex;align-items:center;gap:4px;height:20px;padding:0 7px 0 5px;border-radius:6px;background:rgba(0,0,0,.6);color:#fff;font-size:12px;font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;min-width:0}
.chip4 img{width:12px;height:12px}
.chip4 .af{display:flex;align-items:center;gap:3px;height:20px;padding:0 6px;border-radius:6px;background:var(--primary);color:var(--onPrimary);font-size:12px;font-weight:700;white-space:nowrap;flex:none}
.chip4 .af .rx{font-size:12px}
.cell.focus::after{content:'';position:absolute;inset:0;box-shadow:inset 0 0 0 2px #A0CAFD;z-index:5;pointer-events:none}
.cell.target::after{content:'';position:absolute;inset:3px;border:2px dashed #A0CAFD;border-radius:4px;z-index:5;pointer-events:none}
.cc.dk{color:#fff}
.cc.dk .m{color:rgba(255,255,255,.7)}
.cc.dk .ad{width:40px;height:40px;border-radius:20px;background:rgba(255,255,255,.12);display:grid;place-items:center;color:#fff}
.cc.dk .spin{border-color:rgba(255,255,255,.25);border-top-color:#fff;border-right-color:#fff;width:24px;height:24px}
.cc.dk .t{font-size:13px}
.pz{position:absolute;inset:0;display:grid;place-items:center;z-index:2;background:rgba(0,0,0,.35)}
.pz div{display:flex;align-items:center;gap:6px;height:32px;padding:0 12px 0 8px;border-radius:16px;background:rgba(0,0,0,.6);color:#fff;font-size:13px;font-weight:600}
.lq{position:absolute;right:6px;bottom:6px;z-index:3;height:20px;padding:0 6px;border-radius:6px;background:rgba(0,0,0,.6);color:#fff;font-size:11px;font-weight:600;display:flex;align-items:center}
.sec2{flex:none;padding:6px 8px 6px 12px;background:var(--surface)}
.sr1{display:flex;align-items:center;gap:10px;min-height:52px}
.sr1 .avs{width:32px;height:32px;border-radius:16px;background:center/cover;flex:none}
.sr1 .x{flex:1;min-width:0}
.sr1 .nn{display:flex;align-items:center;gap:6px;font-size:15px;font-weight:600;white-space:nowrap;overflow:hidden}
.sr1 .nn .n2{background:var(--sch);color:var(--on)}
.sr1 .ss{font-size:12px;color:var(--onv);white-space:nowrap;overflow:hidden;text-overflow:ellipsis;margin-top:1px}
.chip{flex:none}
.chip.open{background:var(--schh);border-color:var(--primary)}
.sr2{display:flex;align-items:center;gap:2px;min-height:48px}
.sr2 .ib{width:40px;height:40px;color:var(--onv)}
.sr2 .ib.err{color:var(--error)}
.sr2 .vl{flex:1;display:flex;align-items:center;gap:8px;padding:0 4px 0 8px;color:var(--onv);min-width:0}
.sr2 .vl .trk{flex:1}
.sr2 .vl b{font-size:13px;font-weight:500;color:var(--onv);font-feature-settings:'tnum';min-width:34px;text-align:right}
.ph2{flex:1;min-height:0;display:flex;flex-direction:column;background:var(--surface);border-top:1px solid var(--ov);overflow:hidden}
.ph2 .pt{display:flex;align-items:center;gap:8px;padding:10px 16px 6px;font-size:15px;font-weight:600}
.ph2 .pt small{font-size:12px;font-weight:400;color:var(--onv)}
.srch2{margin:2px 16px 6px;height:40px;border-radius:12px;background:var(--scl);box-shadow:inset 0 0 0 1px var(--ov);display:flex;align-items:center;gap:8px;padding:0 12px;color:var(--onv);font-size:14px;flex:none}
.tabs2{display:flex;gap:8px;padding:0 16px 4px;flex:none}
.tabs2 span{height:32px;padding:0 14px;border-radius:8px;box-shadow:inset 0 0 0 1px var(--ov);display:flex;align-items:center;font-size:14px}
.tabs2 span.on{background:var(--sc);box-shadow:none;color:var(--osc);font-weight:600}
.pr2{display:flex;align-items:center;gap:12px;padding:6px 16px;min-height:56px}
.pr2 .av{position:relative;width:36px;height:36px;border-radius:18px;background:center/cover;flex:none}
.pr2 .av img{position:absolute;right:-3px;bottom:-3px;width:16px;height:16px;border-radius:8px;padding:2px;background:var(--surface)}
.pr2 .x{flex:1;min-width:0}
.pr2 .n{font-size:14px;font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.pr2 .s{font-size:12px;color:var(--onv);white-space:nowrap;overflow:hidden;text-overflow:ellipsis;margin-top:1px}
.pr2 .st{display:flex;align-items:center;gap:5px;font-size:12px;font-weight:600;flex:none}
.pr2 .st i{width:7px;height:7px;border-radius:4px;display:block}
.pr2 .in{font-size:12px;font-weight:600;color:var(--opc);background:var(--pc);height:22px;padding:0 8px;border-radius:11px;display:flex;align-items:center;flex:none}
.col3{flex:none;display:flex;flex-direction:column;background:var(--surface);border-left:1px solid var(--ov);position:relative;min-height:0}
.hdl{position:absolute;top:50%;width:22px;height:56px;border-radius:8px 0 0 8px;background:var(--schh);color:var(--onv);display:grid;place-items:center;z-index:8;transform:translateY(-50%)}
.side{border-radius:16px 0 0 16px}
.p-h .lk{gap:2px}
.menu{z-index:50}
.cap5{position:absolute;z-index:60;font:500 11px 'Noto Sans SC';padding:3px 7px;border-radius:5px;background:rgba(0,0,0,.6);color:#fff}
.stt{display:grid;gap:12px;padding:12px}
.stt .lab{font-size:13px;font-weight:600;color:var(--onv);margin:6px 2px 4px}
'''
mr = lambda n, s=24: f'<span class="mr" style="font-size:{s}px">{n}</span>'
mi = lambda n, s=24: f'<span class="mi" style="font-size:{s}px">{n}</span>'
rx = lambda c, s=24: f'<span class="rx" style="font-size:{s}px">&#x{c};</span>'
ci = lambda c, s=24: f'<span class="ci" style="font-size:{s}px">&#x{c};</span>'
STATUS_BAR = '<div class="status"><span>21:36</span><span class="r"><span class="mi">signal_cellular_alt</span><span class="mi">wifi</span><span class="mi">battery_full</span></span></div>'
STATUS_LAND = ('<div class="status" style="height:24px;font-size:12px;padding:0 24px"><span>21:36</span>'
               '<span class="r"><span class="mi">wifi</span><span class="mi">battery_full</span></span></div>')

ROOMS = {  # cover, nick, title, platform id, platform name
    'wf': ('158', '晚风', '深夜电台 · 点歌接龙到天亮', 'bilibili', '哔哩哔哩'),
    'cs': ('274', '城市漫游', '纽约时代广场，夜游直播', 'douyu', '斗鱼'),
    'yy': ('219', '野生镜头', '草原上的猎豹妈妈', 'bilibili', '哔哩哔哩'),
    'cg': ('225', '茶馆小周', '下午茶时间 聊聊天', 'huya', '虎牙'),
    'cj': ('111', '车库阿杰', '周末老爷车巡游现场', 'douyu', '斗鱼'),
    'ch': ('169', '柴柴日记', '小狗满草地跑一下午', 'bilibili', '哔哩哔哩'),
    'hj': ('360', '花间小铺', '花店开门 今天进了新货', 'huya', '虎牙'),
    'lw': ('304', '录音棚老王', '调音台教学 第 12 课', 'bilibili', '哔哩哔哩'),
}


def page(w, h, scale, body, root='ph', crop=False, syn=True):
    tag = ''
    if syn:
        tag = ('<div class="syn" style="top:auto;bottom:8px;left:8px;transform:none">示意图片</div>' if root in ('win', 'fs')
               else '<div class="syn">示意图片</div>')
    return (f'<!doctype html><html><head><meta charset="utf-8"><meta name="mock-size" content="{w}x{h}@{scale}{" crop" if crop else ""}">'
            f'<link rel="stylesheet" href="kit/kit.css"><style>{CSS}</style></head>'
            f'<body><div class="{root} col" style="--w:{w}px;--h:{h}px;width:{w}px;height:{"auto" if crop else f"{h}px"}">{body}{tag}'
            '</div></body></html>')


def n(k, tag=None):
    return (f' data-n="{k}"' if k else '') + (f' data-tag="{tag}"' if tag and k else '')


# ================================================================ v3
def v3_appbar():
    return (f'<div class="ab"><div class="ib lead">{mr("arrow_back")}</div><div class="ttl">多画面</div><div class="sp"></div>'
            f'<div class="ib">{rx("f4d1")}</div><div class="ib">{rx("ed9c")}</div><div style="width:4px"></div></div>')


LAYOUTS = [('ea80', '1×1'), ('ee8d', '1×2'), ('ee90', '2×2'), ('ed4c', '1+3')]


def v3_seg(sel):
    return '<div class="seg">' + ''.join(f'<span class="{"on" if i == sel else ""}">{rx(c, 18)}{t}</span>' for i, (c, t) in enumerate(LAYOUTS)) + '</div>'


def v3_actions(focus=False, dm=False):
    dmc = 'color:var(--primary)' if dm else ''
    return ('<div class="acts">'
            f'<div class="ib" style="{dmc}">{ci("e801", 22)}</div>'
            f'<div class="ib">{rx("f2a4", 22)}</div>'
            f'<div class="ib">{rx("f2a2", 22)}</div>'
            f'<div class="ib{"" if focus else " dis"}">{rx("f179", 22)}</div></div>')


def v3_toolbar(sel=2, compact=True, focus=False, dm=False):
    if compact:
        return (f'<div style="padding:6px 12px 4px;flex:none"><div style="display:flex;justify-content:center">{v3_seg(sel)}</div>'
                f'<div style="height:2px"></div><div style="display:flex;justify-content:flex-end">{v3_actions(focus, dm)}</div></div>')
    return (f'<div style="padding:8px 16px 4px;display:flex;align-items:center;flex:none"><div style="flex:1;display:flex;justify-content:center">{v3_seg(sel)}</div>'
            f'<div style="width:8px"></div>{v3_actions(focus, dm)}</div>')


def v3_chip(key, focus=False):
    _, nick, _, pid, _ = ROOMS[key]
    af = f'<span class="af">{rx("f2a2", 13)}声音来源</span>' if focus else ''
    return f'<div class="chip3"><span><img src="{LOGO.format(pid)}">{nick}</span>{af}</div>'


def v3_cell(state, key=None, focus=False, dark_bg=False, extra=''):
    if state == 'playing':
        cov = ROOMS[key][0]
        return f'<div class="cell"><div class="vid" style="background-image:url(.cache/img/{cov}.jpg)"></div>{v3_chip(key, focus)}{extra}</div>'
    lt = '' if dark_bg else ' lt'
    if state == 'empty':
        return f'<div class="cell{lt}"><div class="cc"><div class="ad">{rx("ea11", 26)}</div><div class="t">点击选台</div></div></div>'
    if state == 'resolving':
        return f'<div class="cell{lt}"><div class="cc"><div class="spin"></div><div class="m">{ROOMS[key][1]}</div></div></div>'
    if state == 'offline':
        return (f'<div class="cell{lt}"><div class="cc" style="gap:4px"><span style="color:var(--onv)">{rx("eec0", 30)}</span>'
                f'<div class="tb" style="margin-top:6px">该直播间未开播</div><div class="m">{ROOMS[key][1]}</div><div class="m" style="margin-top:2px">点击此格可重新选台</div></div></div>')
    if state == 'error':
        return (f'<div class="cell{lt}"><div class="cc" style="gap:6px"><span style="color:var(--error)">{rx("eca1", 30)}</span>'
                '<div class="tb">播放失败</div><div class="m">解析播放地址失败：网络请求超时</div>'
                f'<div class="tonal" style="margin-top:10px">{rx("f064", 16)}重试</div></div></div>')


def v3_grid(cells, cols=2, rows=2):
    return f'<div class="grid" style="grid-template-columns:repeat({cols},1fr);grid-template-rows:repeat({rows},1fr)">{"".join(cells)}</div>'


V3_QUAD = [('playing', 'wf', True), ('playing', 'cs', False), ('resolving', 'yy', False), ('empty', None, False)]


def v3_quad_cells(dark=False):
    return [v3_cell(s, k, f, dark) for s, k, f in V3_QUAD]


def v3_phone():
    body = f'<div class="body">{v3_grid(v3_quad_cells())}</div>'
    return page(393, 852, 3, STATUS_BAR + v3_appbar() + v3_toolbar() + body + '<div class="gesture"></div>')


def v3_focus():
    big = v3_cell('playing', 'wf', True, extra=(
        '<div class="dm" style="left:20px;top:200px">前排支持！</div><div class="dm" style="left:80px;top:250px">这首好好听</div>'
        f'<div class="cbar">{"".join(f"<div class=ib>{x}</div>" for x in [rx("efd8", 20), rx("f064", 20), "<span style=color:var(--primary)>" + ci("e801", 20) + "</span>", rx("f0e6", 20), rx("ee02", 20), rx("f09b", 20), rx("f29c", 20), rx("ed9c", 20)])}</div>'))
    small = [v3_cell('playing', 'cs'), v3_cell('resolving', 'yy'), v3_cell('playing', 'cg')]
    rail = ''.join(f'<div style="height:calc((100% - 12px)/3);display:flex">{c.replace(chr(60) + 'div class="cell', chr(60) + 'div style="flex:1" class="cell', 1)}</div>' for c in small)
    grid = (f'<div style="display:flex;gap:6px;padding:6px;height:100%"><div style="flex:3;display:flex">{big}</div>'
            f'<div style="flex:1;display:flex;flex-direction:column;gap:6px">{rail}</div></div>')
    grid = grid.replace('<div class="cell">', '<div class="cell" style="flex:1;height:100%">', 1)
    body = f'<div class="body">{grid}</div>'
    return page(393, 852, 3, STATUS_BAR + v3_appbar() + v3_toolbar(3, focus=True, dm=True) + body + '<div class="gesture"></div>')


def pick_rows(rows, v4=False, shown=None):
    shown = shown or {}
    out = ''
    for key, live in rows:
        cov, nick, title, pid, _ = ROOMS[key]
        color = '#31C24C' if live else 'rgba(67,71,78,.35)'
        text = '正在直播' if live else '未直播'
        st = f'<span class="st" style="color:{color}"><i style="background:{color}"></i>{text}</span>'
        if v4 and key in shown:
            st = f'<span class="in">第 {shown[key]} 格</span>'
        cls = 'pr2' if v4 else 'pr'
        out += (f'<div class="{cls}"><span class="av" style="background-image:url(.cache/img/65.jpg)"><img src="{LOGO.format(pid)}"></span>'
                f'<div class="x"><div class="n">{nick}</div><div class="s">{title}</div></div>{st}</div>')
    return out


PICK = [('wf', True), ('cs', True), ('yy', True), ('cg', True), ('cj', True), ('hj', True), ('ch', False), ('lw', False)]


def v3_picker_body(seg=True):
    return (f'<div class="srch">{rx("f0d1", 20)}搜索主播或标题</div>'
            '<div class="seg2"><div class="seg"><span class="on" style="padding:0 24px">关注</span><span style="padding:0 24px">历史记录</span></div></div>'
            + pick_rows(PICK))


def v3_picker():
    body = f'<div class="body">{v3_grid(v3_quad_cells())}</div>'
    sheet = f'<div class="scrim"></div><div class="bs" style="height:613px"><div class="hd"><i></i></div>{v3_picker_body()}</div>'
    return page(393, 852, 3, STATUS_BAR + v3_appbar() + v3_toolbar() + body + sheet + '<div class="gesture"></div>')


def v3_sheets():
    s = '<div class="capx">长按播放中的格子（右键同）</div>'
    s += (f'<div class="bsx"><div class="hd" style="height:22px;display:grid;place-items:center"><i style="width:32px;height:4px;border-radius:2px;background:var(--onv);opacity:.4;display:block"></i></div>'
          f'<div class="lt2">{rx("f235", 24)}<span>换台</span></div>'
          f'<div class="lt2">{rx("ec9d", 24)}<span>选择清晰度</span></div>'
          f'<div class="lt2 err">{rx("eb97", 24)}<span>关闭该格</span></div><div style="height:12px"></div></div>')
    s += '<div class="capx">选择清晰度（长按菜单和大画面控制条）</div>'
    s += ('<div class="bsx"><div style="height:22px"></div>'
          + ''.join(f'<div class="lt2"><span>{q}</span>{"<span class=trl>" + mr("check", 24) + "</span>" if i == 0 else ""}</div>' for i, q in enumerate(['原画', '蓝光', '超清', '高清', '流畅']))
          + '<div style="height:12px"></div></div>')
    s += '<div class="capx">线路（大画面控制条，线路多于 1 条时）</div>'
    s += ('<div class="bsx"><div style="height:22px"></div>'
          + ''.join(f'<div class="lt2"><span>线路 {i + 1}</span>{"<span class=trl>" + mr("check", 24) + "</span>" if i == 0 else ""}</div>' for i in range(3))
          + '<div style="height:12px"></div></div>')
    s += '<div class="capx">音量（工具条，或大画面控制条）</div>'
    s += (f'<div class="bsx"><div style="height:22px"></div><div class="vol"><div class="r1"><span>晚风</span><span style="font-size:14px">70%</span></div>'
          f'<div class="r2">{rx("f29c", 24)}<div class="trk"><i style="width:70%"></i><u style="left:70%"></u></div>{rx("f2a2", 24)}</div>'
          '<div class="cap2">房间音量</div></div></div>')
    return page(393, 2600, 2, f'<div class="sheetbg">{s}<div style="height:12px"></div></div>', crop=True, syn=False)


def v3_cells():
    items = [('空', v3_cell('empty')), ('解析中', v3_cell('resolving', 'yy')), ('播放中 · 声音来源', v3_cell('playing', 'wf', True)),
             ('未开播', v3_cell('offline', 'ch')), ('播放失败', v3_cell('error', 'lw'))]
    out = ''.join(f'<div><div class="lab">{t}</div><div style="height:169px;display:flex">{c.replace("<div class=\"cell", "<div style=\"flex:1\" class=\"cell", 1)}</div></div>' for t, c in items)
    return page(330, 1400, 2, f'<div class="stt" style="background:var(--surface)">{out}</div>', crop=True)


def v3_landscape():
    body = f'<div class="body">{v3_grid(v3_quad_cells())}</div>'
    return page(852, 393, 2, STATUS_LAND + v3_appbar() + v3_toolbar(compact=False) + body, root='win')


def v3_fullscreen():
    grid = v3_grid(v3_quad_cells())
    body = f'<div class="body" style="background:#000">{grid}<div class="exit">{rx("ed9a", 22)}</div></div>'
    return page(852, 393, 2, body, root='fs')


def v3_immersive():
    grid = v3_grid(v3_quad_cells())
    body = f'<div class="body" style="background:#000">{grid}<div class="restore">{rx("f4cb", 20)}</div></div>'
    return page(393, 852, 3, STATUS_BAR.replace('class="status"', 'class="status" style="background:#000;color:#fff"') + body, root='ph')


def v3_wide():
    side = (f'<div class="side3" style="width:320px"><div class="pt">为格子 4 选台</div>{v3_picker_body()}</div>')
    body = f'<div class="body" style="display:flex"><div style="flex:1;min-width:0">{v3_grid(v3_quad_cells())}</div>{side}</div>'
    return page(1280, 800, 1.5, v3_appbar() + v3_toolbar(compact=False) + body, root='win')


# ================================================================ new
def appbar4(nums=True, land=False, toolbar=''):
    k = (lambda x: x) if nums else (lambda x: None)
    mid = f'<div style="margin-left:4px;font-size:20px;font-weight:600">多画面</div><div style="width:16px"></div>{toolbar}' if land else '<div class="ttl">多画面</div>'
    return (f'<div class="ab"><div class="ib lead"{n(k(1))}>{mr("arrow_back")}</div>{mid}<div class="sp"></div>'
            f'<div class="ib"{n(k(2))}>{rx("f4d1")}</div><div class="ib"{n(k(3))}>{rx("ed9c")}</div><div style="width:4px"></div></div>')


def seg4(sel, icons=False, num=None):
    return (f'<div class="seg3"{n(num)}>' + ''.join(f'<span class="{"on" if i == sel else ""}">{rx(c, 18) if icons else ""}{t}</span>'
                                                   for i, (c, t) in enumerate(LAYOUTS)) + '</div>')


def toggles(dm=False, muted=False, focus=False, nums=True, base=5):
    k = (lambda x: x) if nums else (lambda x: None)
    d = f'<div class="tg{" on" if dm else ""}"{n(k(base), "chg")}><span class="dmk {"open" if dm else "close"}"></span></div>'
    s = f'<div class="tg"{n(k(base + 1), "add")}><span class="dmk set"></span></div>'
    m = f'<div class="tg{" on" if muted else ""}"{n(k(base + 2))}>{rx("f29e" if muted else "f2a2", 22)}</div>'
    lq = f'<div class="tg"{n(k(base + 3))}>{rx("f179", 22)}</div>' if focus else ''
    return d + s + m + lq


def toolbar4(sel=2, icons=False, dm=False, muted=False, nums=True):
    k = (lambda x: x) if nums else (lambda x: None)
    return (f'<div class="tb2">{seg4(sel, icons, k(4))}<div style="flex:1"></div>{toggles(dm, muted, sel == 3, nums)}</div>')


def chip4(key, num, focus=False):
    _, nick, _, pid, _ = ROOMS[key]
    af = f'<span class="af">{rx("f2a2", 12)}声音来源</span>' if focus else ''
    return f'<div class="chip4"><span class="n2">{num}</span><span class="nm"><img src="{LOGO.format(pid)}">{nick}</span>{af}</div>'


def cell4(state, key=None, num=1, focus=False, extra='', style=''):
    st = f' style="{style}"' if style else ''
    if state == 'playing':
        cov = ROOMS[key][0]
        return (f'<div class="cell{" focus" if focus else ""}"{st}><div class="vid" style="background-image:url(.cache/img/{cov}.jpg)"></div>'
                f'{chip4(key, num, focus)}{extra}</div>')
    if state == 'paused':
        cov = ROOMS[key][0]
        return (f'<div class="cell"{st}><div class="vid" style="background-image:url(.cache/img/{cov}.jpg)"></div>{chip4(key, num)}'
                f'<div class="pz"><div>{rx("efd8", 18)}已暂停</div></div></div>')
    head = f'<div class="chip4"><span class="n2">{num}</span></div>'
    if state == 'empty':
        return f'<div class="cell"{st}>{head}<div class="cc dk"><div class="ad">{rx("ea11", 22)}</div><div class="t">点击选台</div></div></div>'
    if state == 'target':
        return (f'<div class="cell target"{st}>{head}<div class="cc dk"><div class="ad" style="background:rgba(160,202,253,.25)">{rx("ea11", 22)}</div>'
                '<div class="t">正在为这一格选台</div></div></div>')
    if state == 'resolving':
        return f'<div class="cell"{st}>{chip4(key, num)}<div class="cc dk"><div class="spin"></div><div class="m">正在打开…</div></div></div>'
    if state == 'offline':
        return (f'<div class="cell"{st}>{chip4(key, num)}<div class="cc dk" style="gap:4px"><span style="opacity:.8">{rx("eec0", 26)}</span>'
                '<div class="t" style="font-weight:600">该直播间未开播</div><div class="m">点击此格可重新选台</div></div></div>')
    if state == 'error':
        return (f'<div class="cell"{st}>{chip4(key, num)}<div class="cc dk" style="gap:4px"><span style="color:#FFB4AB">{rx("eca1", 26)}</span>'
                '<div class="t" style="font-weight:600">播放失败</div><div class="m">解析播放地址失败：网络请求超时</div>'
                f'<div class="tonal" style="margin-top:6px;height:32px;font-size:13px">{rx("f064", 16)}重试</div></div></div>')


def wall(cells, cols, rows, w, ratio=16 / 9, gap=3):
    cw = (w - gap * (cols + 1)) / cols
    ch = cw / ratio
    h = ch * rows + gap * (rows + 1)
    grid = f'<div class="grid" style="grid-template-columns:repeat({cols},{cw:.1f}px);grid-template-rows:repeat({rows},{ch:.1f}px)">{"".join(cells)}</div>'
    return f'<div class="wall" style="height:{h:.1f}px">{grid}</div>', h


QUAD4 = [('playing', 'wf', True), ('playing', 'cs', False), ('resolving', 'yy', False), ('target', None, False)]


def quad4_cells():
    return [cell4(s, k, i + 1, f) for i, (s, k, f) in enumerate(QUAD4)]


def section(key='wf', num=1, nums=True, compact=False, open_menu=False):
    """The selected cell: the room, quality and line (U.2f), playback, room volume.
    compact (a narrow column): the buttons and the volume on rows of their own."""
    k = (lambda x: x) if nums else (lambda x: None)
    cov, nick, title, pid, pname = ROOMS[key]
    chips = (f'<div class="chip{" open" if open_menu else ""}"{n(k(11), "chg")}>原画{rx("ea4e" if not open_menu else "ea78", 18)}</div>'
             f'<div class="chip"{n(k(12), "chg")}>线路1{rx("ea4e", 18)}</div>')
    r1 = (f'<div class="sr1"><span class="avs" style="background-image:url(.cache/img/65.jpg)"></span>'
          f'<div class="x"><div class="nn"><span class="n2">{num}</span>{nick}</div><div class="ss">{pname} · {title}</div></div>'
          + ('' if compact else chips) + '</div>')
    icons = (f'<div class="ib"{n(k(13))}>{rx("efd8", 22)}</div><div class="ib"{n(k(14))}>{rx("f064", 22)}</div>'
             f'<div class="ib"{n(k(15))}>{rx("f235", 22)}</div>'
             f'<div class="ib"{n(k(16), "add")}>{rx("ecaf", 22)}</div><div class="ib err"{n(k(17))}>{rx("eb97", 22)}</div>')
    vol = f'<div class="vl"{n(k(18), "chg")}>{rx("f29c", 20)}<div class="trk"><i style="width:70%"></i><u style="left:70%"></u></div><b>70%</b></div>'
    if compact:
        return (f'<div class="sec2">{r1}<div class="sr2" style="gap:8px;padding-left:2px">{chips}</div>'
                f'<div class="sr2">{icons}</div><div class="sr2" style="margin-left:-8px">{vol}</div></div>')
    return f'<div class="sec2">{r1}<div class="sr2">{icons}{vol}</div></div>'


def picker4(target=4, nums=True, shown=None, rows=None, close=False, replace=None):
    k = (lambda x: x) if nums else (lambda x: None)
    shown = shown if shown is not None else {'wf': 1, 'cs': 2, 'yy': 3}
    # rooms already in a cell go last (3.x order otherwise: live first, then audience)
    rows = rows or [('cg', True), ('cj', True), ('hj', True), ('ch', False), ('lw', False), ('wf', True), ('cs', True), ('yy', True)]
    x = f'<span style="margin-left:auto;margin-right:-8px;width:40px;height:40px;display:grid;place-items:center;color:var(--onv)">{mr("close", 22)}</span>' if close else ''
    sub = '' if close else (f'<small>点直播间换掉“{replace}”</small>' if replace else '<small>点直播间放进这一格</small>')
    head = f'第 {target} 格换台' if replace else f'为第 {target} 格选台'
    border = ' style="border-top:0"' if close else ''
    return (f'<div class="ph2"{border}><div class="pt">{head}{sub}{x}</div>'
            f'<div class="srch2"{n(k(19))}>{rx("f0d1", 20)}搜索主播或标题</div>'
            f'<div class="tabs2"{n(k(20))}><span class="on">关注</span><span>历史记录</span></div>'
            f'<div{n(k(21))}>{pick_rows(rows, True, shown)}</div></div>')


def tag_cell(html_, num):
    return html_.replace('<div class="cell', f'<div data-n="{num}" class="cell', 1) if num else html_


def v4_phone(nums=True):
    cells = quad4_cells()
    if nums:
        cells[0] = tag_cell(cells[0], 9)
        cells[3] = tag_cell(cells[3], 10)
    w, h = wall(cells, 2, 2, 393)
    body = (f'<div class="body col">{w}{section(nums=nums)}{picker4(nums=nums)}</div>')
    return page(393, 852, 3, STATUS_BAR + appbar4(nums) + toolbar4(nums=nums) + body + '<div class="gesture"></div>')


def v4_menu():
    w, h = wall(quad4_cells(), 2, 2, 393)
    body = f'<div class="body col">{w}{section(nums=False, open_menu=True)}{picker4(nums=False)}</div>'
    menu = ('<div class="menu" style="left:236px;top:418px">'
            + ''.join(f'<div class="it{" on" if i == 0 else ""}"><span>{q}</span>{mr("check", 20) if i == 0 else ""}</div>' for i, q in enumerate(['原画', '蓝光', '超清', '高清', '流畅']))
            + '</div>')
    return page(393, 852, 3, STATUS_BAR + appbar4(False) + toolbar4(nums=False) + body
                + '<div class="scrim" style="background:transparent"></div>' + menu + '<div class="gesture"></div>')


def v4_focus():
    big = cell4('playing', 'wf', 1, True, extra='<div class="dm" style="left:24px;top:70px">前排支持！</div><div class="dm" style="left:150px;top:118px">这首好好听</div>')
    W = 393
    bw = W - 6
    bh = bw * 9 / 16
    sw = (W - 3 * 4) / 3
    sh = sw * 9 / 16
    smalls = [cell4('playing', 'cs', 2, extra='<span class="lq">省流</span>'), cell4('resolving', 'yy', 3), cell4('playing', 'cg', 4, extra='<span class="lq">省流</span>')]
    wallh = bh + sh + 9
    w = (f'<div class="wall" style="height:{wallh:.1f}px"><div style="position:absolute;left:3px;top:3px;width:{bw:.1f}px;height:{bh:.1f}px;display:flex">{big.replace("<div class=\"cell", "<div style=\"flex:1\" class=\"cell", 1)}</div>'
         + ''.join(f'<div style="position:absolute;left:{3 + i * (sw + 3):.1f}px;top:{bh + 6:.1f}px;width:{sw:.1f}px;height:{sh:.1f}px;display:flex">{c.replace("<div class=\"cell", "<div style=\"flex:1\" class=\"cell", 1)}</div>' for i, c in enumerate(smalls))
         + '</div>')
    body = f'<div class="body col">{w}{section(nums=False)}{picker4(nums=False, target=1, shown={"wf": 1, "cs": 2, "yy": 3, "cg": 4}, replace="晚风", rows=[("cj", True), ("hj", True), ("ch", False), ("lw", False), ("wf", True), ("cs", True), ("yy", True), ("cg", True)])}</div>'
    return page(393, 852, 3, STATUS_BAR + appbar4(False) + toolbar4(3, dm=True, nums=False) + body + '<div class="gesture"></div>')


def v4_danmaku():
    """The U.2f danmaku settings panel, below the picture (as in the portrait room)."""
    w, h = wall(quad4_cells(), 2, 2, 393)
    rows = ('<div class="sec">观看模板</div>'
            '<div style="display:flex;flex-wrap:wrap;gap:8px;padding:4px 20px 8px"><span class="tag2 on">' + mr('check', 16) + '顶部 20% · 均衡</span><span class="tag2">顶部 35% · 舒适</span><span class="tag2">顶部 55% · 高密度</span></div>'
            '<div class="sec">显示范围</div>'
            '<div class="sl"><div class="h"><span>画面顶部占用高度</span><span class="vpill">20%</span></div><div class="tr"><i style="width:20%"></i><u style="left:calc(20% - 10px)"></u></div></div>'
            '<div class="sl"><div class="h"><span>透明度</span><span class="vpill">90%</span></div><div class="tr"><i style="width:90%"></i><u style="left:calc(90% - 10px)"></u></div></div>')
    panel = (f'<div class="sheet" style="top:{92 + 52 + h:.0f}px;border-radius:16px 16px 0 0"><div class="p-h"><span class="t">弹幕设置</span>'
             f'<span style="font-size:12px;color:var(--onv);margin-right:4px">只在声音来源这一格显示 · 改动立即生效</span><span class="x">{mr("close", 22)}</span></div>{rows}</div>')
    body = f'<div class="body col">{w}{section(nums=False)}{picker4(nums=False)}</div>'
    return page(393, 852, 3, STATUS_BAR + appbar4(False) + toolbar4(dm=True, nums=False) + body + panel + '<div class="gesture"></div>')


def v4_cells():
    items = [('空', cell4('empty', num=4)), ('选台目标（新：虚线框）', cell4('target', num=4)), ('解析中', cell4('resolving', 'yy', 3)),
             ('播放中 · 声音来源（新：描边、编号）', cell4('playing', 'wf', 1, True)), ('已暂停（新）', cell4('paused', 'cs', 2)),
             ('未开播', cell4('offline', 'ch', 3)), ('播放失败', cell4('error', 'lw', 4))]
    out = ''.join(f'<div><div class="lab">{t}</div><div style="height:169px;display:flex">{c.replace("<div class=\"cell", "<div style=\"flex:1\" class=\"cell", 1)}</div></div>' for t, c in items)
    return page(330, 1800, 2, f'<div class="stt" style="background:var(--surface)">{out}</div>', crop=True)


def column(width, nums=True, target=4, mode='both'):
    """The right column: the selected cell above the picker (wide); on a landscape phone
    it holds one of them: the cell, or the picker while choosing (closed with its X)."""
    k = (lambda x: x) if nums else (lambda x: None)
    inner = {'both': section(nums=nums, compact=True) + picker4(target, nums=nums),
             'section': section(nums=nums, compact=True),
             'pick': picker4(target, nums=nums, close=True)}[mode]
    return (f'<div class="col3" style="width:{width}px">{inner}'
            f'<div class="hdl" style="right:{width}px"{n(k(22), "add")}>{mr("chevron_right", 20)}</div></div>')


def v4_landscape(nums=True, pick=False):
    tb = f'{seg4(2, num=4 if nums else None)}<div style="width:8px"></div>{toggles(nums=nums)}'
    H = 393 - 24 - 56
    gap = 3
    ch = (H - gap * 3) / 2
    cw = ch * 16 / 9
    gw = cw * 2 + gap * 3
    q = list(QUAD4)
    if not pick:
        q[3] = ('empty', None, False)
    cells = [cell4(s_, k_, i + 1, f_) for i, (s_, k_, f_) in enumerate(q)]
    if nums:
        cells[0] = tag_cell(cells[0], 9)
        cells[3] = tag_cell(cells[3], 10)
    grid = f'<div class="grid" style="grid-template-columns:repeat(2,{cw:.1f}px);grid-template-rows:repeat(2,{ch:.1f}px);gap:3px;padding:3px">{"".join(cells)}</div>'
    body = (f'<div class="body" style="display:flex"><div class="wall" style="width:{gw:.1f}px;height:100%">{grid}</div>'
            f'{column(852 - gw, nums, mode="pick" if pick else "section")}</div>')
    return page(852, 393, 2, STATUS_LAND + appbar4(nums, land=True, toolbar=tb) + body, root='win')


def v4_wide(nums=True):
    W, H = 1280 - 360, 800 - 56 - 52
    gap = 4
    cw = (W - 40 - gap * 3) / 2
    ch = cw * 9 / 16
    cells = quad4_cells()
    if nums:
        cells[0] = tag_cell(cells[0], 9)
        cells[3] = tag_cell(cells[3], 10)
    grid = (f'<div class="grid" style="grid-template-columns:repeat(2,{cw:.1f}px);grid-template-rows:repeat(2,{ch:.1f}px);gap:{gap}px;padding:{gap}px;'
            f'position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);height:auto">{"".join(cells)}</div>')
    body = (f'<div class="body" style="display:flex"><div class="wall" style="flex:1;height:100%">{grid}</div>{column(360, nums)}</div>')
    tb = f'<div class="tb2" style="padding:6px 16px">{seg4(2, True, 4 if nums else None)}<div style="flex:1"></div>{toggles(nums=nums)}</div>'
    return page(1280, 800, 1.5, appbar4(nums) + tb + body, root='win')


def fs_grid(cells, W=852, H=393, gap=3):
    ch = (H - gap * 3) / 2
    cw = ch * 16 / 9
    return (f'<div class="grid" style="grid-template-columns:repeat(2,{cw:.1f}px);grid-template-rows:repeat(2,{ch:.1f}px);gap:{gap}px;padding:{gap}px;'
            f'position:absolute;left:50%;top:0;transform:translateX(-50%);height:auto">{"".join(cells)}</div>')


def v4_fullscreen():
    cells = [cell4('playing', 'wf', 1, True), cell4('playing', 'cs', 2), cell4('paused', 'yy', 3), cell4('playing', 'cg', 4)]
    body = f'<div class="body" style="background:#000">{fs_grid(cells)}<div class="exit" data-n="23" data-tag="chg">{rx("ed9a", 22)}</div></div>'
    return page(852, 393, 2, body, root='fs')


def v4_fullscreen_panel():
    cells = [cell4('playing', 'wf', 1, True), cell4('playing', 'cs', 2), cell4('paused', 'yy', 3), cell4('playing', 'cg', 4)]
    sec = section(nums=False, compact=True)
    panel = (f'<div class="side"><div class="p-h"><span class="t">第 1 格</span><span class="x">{mr("close", 22)}</span></div>{sec}'
             '</div>')
    body = f'<div class="body" style="background:#000">{fs_grid(cells)}<div class="exit">{rx("ed9a", 22)}</div>{panel}</div>'
    return page(852, 393, 2, body, root='fs')


def v4_immersive():
    cells = quad4_cells()[:3] + [cell4('empty', num=4)]
    w, h = wall(cells, 2, 2, 393)
    body = (f'<div class="body" style="background:#000;display:flex;flex-direction:column;justify-content:center">{w}'
            f'<div class="exit" style="top:12px">{rx("f4cb", 20)}</div></div>')
    return page(393, 852, 3, STATUS_BAR.replace('class="status"', 'class="status" style="background:#000;color:#fff"') + body, root='ph')


OUT = {
    'v3-phone': v3_phone(), 'v3-focus': v3_focus(), 'v3-picker': v3_picker(), 'v3-sheets': v3_sheets(), 'v3-cells': v3_cells(),
    'v3-landscape': v3_landscape(), 'v3-fullscreen': v3_fullscreen(), 'v3-immersive': v3_immersive(), 'v3-wide': v3_wide(),
    'v4-phone': v4_phone(), 'v4-menu': v4_menu(), 'v4-focus': v4_focus(), 'v4-danmaku': v4_danmaku(), 'v4-cells': v4_cells(),
    'v4-landscape': v4_landscape(), 'v4-landscape-pick': v4_landscape(False, True), 'v4-fullscreen': v4_fullscreen(), 'v4-fullscreen-panel': v4_fullscreen_panel(),
    'v4-immersive': v4_immersive(), 'v4-wide': v4_wide(),
}
for name, html in OUT.items():
    open(os.path.join(HERE, name + '.html'), 'w', encoding='utf-8').write(html)
print(len(OUT), 'pages')
