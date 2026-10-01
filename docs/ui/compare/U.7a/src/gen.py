"""U.7a recording centre: v3 restored and the new design.

v3 (tag v3.2.11):
  page            lib/recorder/pages/recorder/recorder_page.dart (AppBar :35-53, 9 tabs :15-25,
                  card :448-711, status colours :111-140, texts :142-171, actions :341-446,
                  remove dialog :764-800, empty :811-841)
  status selector lib/recorder/widgets/recorder_bounded_scroll.dart:10-91 (3 / 5 / 9 columns)
  ordering        lib/recorder/models/recorder_task_ordering.dart, record_status.dart:17-38
  entries         modules/home/mobile_view.dart:56-63 (tab), tablet_view.dart:138-146 (rail action),
                  common/widgets/menu_button.dart (leading menu on the phone tab)
New design: the status card of the room's record panel (U.2f, confirmed;
apps/pure_live/lib/features/live_play/record/record_panel.dart) in a compact size.

    python3 docs/ui/compare/U.7a/src/gen.py && python3 tools/ui/mock/render.py docs/ui/compare/U.7a/src/ --annotate
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
LOGO = '../../../packages/live_ui/assets/platforms/{}.png'
CSS = '''
.col{display:flex;flex-direction:column}
.ab{height:56px;display:flex;align-items:center;position:relative;flex:none;background:var(--surface)}
.ab .ttl{position:absolute;left:0;right:0;text-align:center;font-size:20px;font-weight:600;pointer-events:none}
.ab .sp{flex:1}
.ab .ib{color:var(--onv)}
.ab .ib.lead{color:var(--on);margin-left:4px}
.body{flex:1;min-height:0;overflow:hidden;position:relative}
.nav{height:80px;flex:none;background:var(--scc);display:flex}
.nav>div{flex:1;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:4px;font-size:12px;font-weight:500;color:var(--onv)}
.nav i{width:64px;height:32px;border-radius:16px;display:grid;place-items:center;font-style:normal}
.nav .on{color:var(--on)}.nav .on i{background:var(--sc);color:var(--osc)}
/* ---------- v3 ---------- */
.sel{padding:6px 10px;background:var(--surface)}
.sel .r{display:flex}
.sel .c{flex:1;padding:3px}
.sel .c b{display:flex;height:48px;border-radius:11px;align-items:center;justify-content:center;font-size:12px;font-weight:500;color:var(--onv);background:rgba(225,226,232,.46);white-space:nowrap;overflow:hidden}
.sel .c b.on{background:var(--pc);color:var(--opc);font-weight:700}
.sel .c.e b{background:none}
.v3list{padding:12px 16px 24px}
.v3c{background:var(--surface);border-radius:18px;border:1px solid rgba(115,119,127,.08);box-shadow:0 6px 18px rgba(0,0,0,.04);padding:14px;margin-bottom:14px}
.v3cov{position:relative;width:150px;height:90px;border-radius:14px;background:center/cover;flex:none}
.v3cov .st{position:absolute;left:8px;top:8px;padding:4px 10px;border-radius:8px;border:.5px solid rgba(255,255,255,.2);color:#fff;font-size:12px;font-weight:700;line-height:16px}
.v3t{font-size:15px;font-weight:700;line-height:1.2;letter-spacing:.1px;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden}
.v3n{display:flex;align-items:center;gap:7px;margin-top:8px;font-size:14px;font-weight:600;color:var(--onv)}
.v3n i{width:24px;height:24px;border-radius:12px;background:center/cover;flex:none}
.v3w{display:flex;flex-wrap:wrap;gap:6px 14px;margin-top:10px;align-items:center}
.v3tag{display:inline-flex;align-items:center;gap:4px;padding:4px 7px;border-radius:999px;font-size:12px;font-weight:700;letter-spacing:.2px;line-height:14px}
.v3tag .rx{font-size:11px}
.mini{display:inline-flex;align-items:center;gap:4px;font-size:12px;font-weight:500;color:var(--onv);line-height:16px}
.mini .mr{font-size:13px}
.v3stats{margin-top:14px;padding:14px;border-radius:14px;background:rgba(54,97,142,.05);border:1px solid rgba(54,97,142,.08)}
.v3stats .w{display:flex;flex-wrap:wrap;gap:10px 16px}
.v3stats .it{display:inline-flex;align-items:center;gap:5px;padding:7px 10px;border-radius:10px;background:rgba(67,71,78,.06);font-size:12px;font-weight:600;color:var(--onv);line-height:16px}
.v3stats .it .mr{font-size:14px}
.v3stats .bar{height:4px;border-radius:999px;background:var(--primary);margin-top:8px}
.v3ban{margin-top:12px;padding:10px 12px;border-radius:12px;display:flex;gap:8px;align-items:flex-start;font-size:12px;font-weight:700;line-height:1.3}
.v3ban .mr{font-size:17px;flex:none}
.v3ban.err{background:rgba(255,218,214,.52);font-weight:400;color:#410002}
.v3ban.err .mr{color:var(--error)}
.v3ban.warn{background:#F2DAFF;font-weight:400;color:#251431}
.v3foot{display:flex;flex-wrap:wrap;justify-content:space-between;align-items:center;gap:8px 12px;margin-top:14px}
.v3acts{display:flex;flex-wrap:wrap;justify-content:flex-end;gap:4px 6px;align-items:center}
.v3b{height:48px;padding:0 14px;border-radius:12px;display:inline-flex;align-items:center;font-size:12px;font-weight:700}
.v3b.danger{background:#FF5252;color:#fff}.v3b.pri{background:var(--primary);color:#fff}
.v3b.out{box-shadow:inset 0 0 0 1px rgba(115,119,127,.2);color:var(--primary)}
.v3b.del{color:#F44336;font-size:15px;font-weight:500;padding:0 12px;height:40px}
.v3empty{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center}
.v3empty .ci2{width:92px;height:92px;border-radius:46px;background:rgba(54,97,142,.08);display:grid;place-items:center;color:var(--primary)}
.v3empty .t{margin-top:24px;font-size:15px;font-weight:700}
.v3empty .s{margin-top:8px;font-size:13px;color:var(--onv)}
/* ---------- dialogs (v3 AlertDialog; new: same) ---------- */
.scrim{z-index:40}
.dlg{z-index:41}
.dlg .h{padding:24px 24px 0;font-size:20px;font-weight:600;line-height:1.35}
.dlg .b{padding:16px 24px 0;font-size:14px;line-height:1.6;color:var(--onv)}
.dlg .a{display:flex;justify-content:flex-end;gap:8px;padding:24px 24px 24px}
.dlg .a span{height:48px;min-width:48px;padding:0 16px;border-radius:24px;display:flex;align-items:center;justify-content:center;font-size:14px;font-weight:600;color:var(--primary)}
.dlg .a .red{background:#F44336;color:#fff}
.dlg .a .red2{background:var(--error);color:#fff}
/* ---------- new ---------- */
.fl{padding:6px 10px;background:var(--surface);display:flex}
.fl .c{flex:1;padding:3px;min-width:0}
.fl .c b{display:flex;height:44px;border-radius:11px;align-items:center;justify-content:center;gap:4px;font-size:13px;font-weight:500;color:var(--onv);background:rgba(225,226,232,.46);white-space:nowrap;overflow:hidden}
.fl .c b small{font-size:12px;font-weight:500;font-feature-settings:'tnum';opacity:.8}
.fl .c b.on{background:var(--pc);color:var(--opc);font-weight:600}
.list{padding:12px 16px 24px}
.gh{display:flex;align-items:center;gap:6px;height:36px;padding:8px 4px 0;font-size:13px;font-weight:600;color:var(--onv)}
.gh small{font-size:12px;font-weight:500;font-feature-settings:'tnum'}
.card{background:var(--scl);border-radius:16px;padding:12px;margin-bottom:12px}
.hd{display:flex;gap:10px;align-items:flex-start;position:relative}
.cov{width:96px;height:54px;border-radius:8px;background:center/cover;flex:none}
.hd .tx{flex:1;min-width:0;padding-right:4px}
.hd .n{display:flex;align-items:center;gap:6px;font-size:15px;font-weight:600;line-height:20px}
.hd .n span:first-child{white-space:nowrap;overflow:hidden;text-overflow:ellipsis;min-width:0}
.hd .t{font-size:13px;color:var(--onv);line-height:18px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;margin-top:1px}
.hd .m{font-size:12px;color:var(--onv);line-height:17px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;margin-top:1px;display:flex;align-items:center;gap:4px}
.hd .m img{width:13px;height:13px;border-radius:3px}
.hd .more{width:40px;height:40px;margin:-6px -6px 0 0;display:grid;place-items:center;color:var(--onv);flex:none}
.ar{height:22px;border-radius:11px;display:inline-flex;align-items:center;gap:3px;padding:0 8px 0 6px;background:var(--pc);color:var(--opc);font-size:12px;font-weight:600;flex:none}
.ar .rx{font-size:13px}
.sb{margin-top:10px;border-radius:12px;padding:12px 12px 12px}
.sb.neutral{background:var(--sch)}
.sb.red{background:var(--recbg);box-shadow:inset 0 0 0 1px rgba(217,45,32,.3)}
.sb.yellow{background:var(--warnbg);box-shadow:inset 0 0 0 1px rgba(145,86,0,.3)}
.sb.green{background:var(--okbg);box-shadow:inset 0 0 0 1px rgba(27,114,54,.3)}
.sb.error{background:#FBEBEA;box-shadow:inset 0 0 0 1px rgba(186,26,26,.3)}
[data-theme=dark] .sb.error{background:#3A1F1E}
.sh{display:flex;align-items:center;gap:8px;min-height:22px}
.sh .ic{width:22px;height:22px;display:grid;place-items:center;flex:none}
.sh .tt{margin-left:0;display:block;font-size:15px;font-weight:600;flex:1;min-width:0;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.sh .me{font-size:12px;color:var(--onv);font-feature-settings:'tnum';flex:none}
.red .sh .tt{color:#B3261E}.yellow .sh .tt,.yellow .sh .ic{color:#915600}.green .sh .tt,.green .sh .ic{color:#1B7236}.error .sh .tt,.error .sh .ic{color:var(--error)}
.sd{margin-top:6px;font-size:13px;line-height:1.5;color:var(--onv);font-feature-settings:'tnum'}
.clock{font:600 24px/1.2 'Geist','Noto Sans SC';font-feature-settings:'tnum';margin-top:6px}
.chips{display:flex;flex-wrap:wrap;gap:6px;margin-top:6px}
.chips span{height:26px;padding:0 10px;border-radius:8px;background:var(--surface);font-size:13px;display:flex;align-items:center;font-feature-settings:'tnum'}
.bt{display:flex;gap:8px;margin-top:10px}
.bt>div{flex:1;height:40px;border-radius:20px;display:flex;align-items:center;justify-content:center;gap:6px;font-size:14px;font-weight:600;white-space:nowrap}
.bt .go{background:var(--rec);color:#fff}.bt .go i{width:8px;height:8px;border-radius:4px;background:#fff}
.bt .stop{background:var(--surface);color:#B3261E;box-shadow:inset 0 0 0 1.5px var(--rec)}.bt .stop i{width:10px;height:10px;border-radius:2px;background:#B3261E}
.bt .pl{background:var(--surface);color:var(--primary);box-shadow:inset 0 0 0 1px var(--ov)}
.bt .er{background:var(--error);color:#fff}
.dot{width:10px;height:10px;border-radius:5px;background:var(--rec);box-shadow:0 0 0 4px rgba(217,45,32,.18)}
.ring2{width:18px;height:18px;border-radius:9px;border:2px solid var(--onv);display:grid;place-items:center}.ring2 i{width:8px;height:8px;border-radius:4px;background:var(--rec)}
.spin{width:16px;height:16px;border-radius:8px;border:2px solid rgba(54,97,142,.25);border-top-color:var(--primary);border-right-color:var(--primary)}
.warnrow{margin-top:8px;display:flex;gap:6px;align-items:flex-start;font-size:12px;line-height:1.45;color:#915600}
.warnrow .mr{font-size:16px;flex:none}
.pban{margin:8px 0 4px;border-radius:12px;background:var(--warnbg);display:flex;align-items:center;gap:8px;padding:6px 4px 6px 12px;font-size:13px;line-height:1.45;color:#5C3B00}
.pban .mr{color:#915600;font-size:18px;flex:none}
.pban .x{flex:1}
.pban .lk{height:40px;padding:0 12px;display:grid;place-items:center;color:var(--primary);font-weight:600;font-size:14px;flex:none}
.empty{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;padding:0 40px;text-align:center}
.empty .ci2{width:72px;height:72px;border-radius:36px;background:var(--sch);display:grid;place-items:center;color:var(--onv)}
.empty .t{margin-top:16px;font-size:16px;font-weight:600}
.empty .s{margin-top:8px;font-size:13px;line-height:1.55;color:var(--onv)}
.grid2{display:grid;gap:12px;align-items:start}
.grid2 .card{margin-bottom:0}
.wide .cov{width:160px;height:90px}
.menu .it .sw{transform:scale(.8);margin-right:-6px}
.menu .it.red{color:var(--error)}
.note{margin:20px 4px 8px;padding:6px 10px;border:1px dashed var(--outline);border-radius:8px;font-size:12px;color:var(--onv)}
.lbl{position:absolute;left:12px;font-size:12px;font-weight:600;color:var(--onv)}
'''
mr = lambda n, s=24: f'<span class="mr" style="font-size:{s}px">{n}</span>'
mi = lambda n, s=24: f'<span class="mi" style="font-size:{s}px">{n}</span>'
rx = lambda c, s=24: f'<span class="rx" style="font-size:{s}px">&#x{c};</span>'
STATUS_BAR = '<div class="status"><span>21:36</span><span class="r"><span class="mi">signal_cellular_alt</span><span class="mi">wifi</span><span class="mi">battery_full</span></span></div>'


STATUS_LAND = ('<div class="status" style="height:24px;font-size:12px;padding:0 24px"><span>21:36</span>'
               '<span class="r"><span class="mi">wifi</span><span class="mi">battery_full</span></span></div>')


def page(w, h, scale, body, root='ph', crop=False):
    return (f'<!doctype html><html><head><meta charset="utf-8"><meta name="mock-size" content="{w}x{h}@{scale}{" crop" if crop else ""}">'
            f'<link rel="stylesheet" href="kit/kit.css"><style>{CSS}</style></head>'
            f'<body><div class="{root} col" style="--w:{w}px;--h:{h}px;width:{w}px;height:{"auto" if crop else f"{h}px"}">{body}'
            + ('<div class="syn" style="top:auto;bottom:8px;left:8px;transform:none">示意图片</div>' if root == 'win' else '<div class="syn">示意图片</div>')
            + '</div></body></html>')


def n(k, tag=None):
    return (f' data-n="{k}"' if k else '') + (f' data-tag="{tag}"' if tag and k else '')


# ---------------------------------------------------------------- data
# (id, cover, nick, avatar?, title, platform id, platform name, audience)
ROOMS = {
    'wf': ('158', '晚风', '深夜电台 · 点歌接龙到天亮', 'bilibili', '哔哩哔哩', '热度 84.7万'),
    'cs': ('274', '城市漫游', '纽约时代广场，夜游直播', 'douyu', '斗鱼', '热度 52.3万'),
    'lw': ('304', '录音棚老王', '调音台教学 第 12 课', 'bilibili', '哔哩哔哩', '热度 3.1万'),
    'cg': ('225', '茶馆小周', '下午茶时间 聊聊天', 'huya', '虎牙', '热度 8,842'),
    'cj': ('111', '车库阿杰', '周末老爷车巡游现场', 'douyu', '斗鱼', '热度 12.6万'),
    'ch': ('169', '柴柴日记', '小狗满草地跑一下午', 'bilibili', '哔哩哔哩', '热度 6.4万'),
    'hj': ('360', '花间小铺', '花店开门 今天进了新货', 'huya', '虎牙', '热度 2.2万'),
    'yy': ('219', '野生镜头', '草原上的猎豹妈妈', 'bilibili', '哔哩哔哩', '热度 21.8万'),
    'jp': ('250', '胶片修理铺', '老相机修复全过程', 'douyu', '斗鱼', '热度 9,410'),
}

# ---------------------------------------------------------------- v3
V3_STATUS = {  # recorder_page.dart:111-171
    'running': ('录制中', '#4CAF50'), 'preparing': ('准备中', '#FFC107'), 'queued': ('排队中', '#673AB7'),
    'waitingLive': ('等待开播', '#FFAB40'), 'reconnecting': ('重连中', '#FF9800'), 'processing': ('处理中', '#00BCD4'),
    'completed': ('已完成', '#2196F3'), 'failed': ('失败', '#F44336'), 'stopped': ('已停止', '#9E9E9E'),
}
V3_PLATFORM = {'bilibili': '#FB7299', 'douyu': '#FF7700', 'huya': '#FFB000'}  # :173-197
V3_TABS = ['全部', '录制中', '等待开播', '排队中', '重连中', '处理中', '已完成', '失败', '已停止']


def rgba(hex_, a):
    h = hex_.lstrip('#')
    return f'rgba({int(h[0:2], 16)},{int(h[2:4], 16)},{int(h[4:6], 16)},{a})'


def v3_selector(cols, sel=0):
    rows = ''
    for s in range(0, len(V3_TABS), cols):
        cells = ''
        for c in range(cols):
            i = s + c
            cells += (f'<div class="c"><b class="{"on" if i == sel else ""}">{V3_TABS[i]}</b></div>' if i < len(V3_TABS) else '<div class="c e"><b></b></div>')
        rows += f'<div class="r">{cells}</div>'
    return f'<div class="sel">{rows}</div><hr>'


def v3_actions(status):  # :341-446
    d = '<span class="v3b del">删除</span>'
    if status in ('running', 'reconnecting', 'preparing'):
        return d + '<span class="v3b danger">停止</span>'
    if status == 'queued':
        return d + '<span class="v3b pri">启动</span><span class="v3b out">取消</span>'
    text = {'failed': '重试', 'waitingLive': '立即检测', 'completed': '重新录制'}.get(status, '启动')
    return d + f'<span class="v3b pri">{text}</span>'


def v3_card(key, status, stats=None, error=None, quality='原画', line='线路1', start='10-01 21:18', wide=False):
    cover, nick, title, pid, _, aud = ROOMS[key]
    text, color = V3_STATUS[status]
    cov = (f'<div class="v3cov" style="background-image:url(.cache/img/{cover}.jpg)">'
           f'<span class="st" style="background:{rgba(color, .82)}">{text}</span></div>')
    pc = V3_PLATFORM[pid]
    tags = (f'<span class="v3tag" style="background:{rgba(pc, .1)};color:{pc}">{rx("f006", 11)}{pid.upper()}</span>'
            f'<span class="mini">{mr("high_quality", 13)}{quality}</span>'
            + (f'<span class="mini">{mr("alt_route", 13)}{line}</span>' if line else '')
            + f'<span class="mini">{mr("whatshot", 13)}{aud}</span>')
    details = (f'<div style="flex:1;min-width:0"><div class="v3t">{title}</div>'
               f'<div class="v3n"><i style="background-image:url(.cache/img/65.jpg)"></i>{nick}</div>'
               f'<div class="v3w">{tags}</div></div>')
    top = (f'<div style="display:flex;gap:14px;align-items:flex-start">{cov}{details}</div>' if wide
           else f'{cov}<div style="height:12px"></div>{details}')
    out = top
    if stats:
        items = ''.join(f'<span class="it">{mr(i, 14)}{t}</span>' for i, t in zip(('timer', 'storage', 'speed', 'graphic_eq'), stats))
        out += f'<div class="v3stats"><div class="w">{items}</div><div class="bar"></div></div>'
    if status in ('reconnecting', 'preparing'):
        out += f'<div class="v3ban" style="background:{rgba(color, .08)};box-shadow:inset 0 0 0 1px {rgba(color, .14)};color:{color}">{mr("sync", 17)}{text}</div>'
    if error:
        out += f'<div class="v3ban err">{mr("error_outline", 17)}<span>{error}</span></div>'
    out += (f'<div class="v3foot"><span class="mini">{mr("schedule", 13)}{start}</span>'
            f'<span class="v3acts">{v3_actions(status)}</span></div>')
    return f'<div class="v3c">{out}</div>'


V3_CARDS = [  # one per status, in the 全部 order (record_status.dart:17-38)
    ('wf', 'running', dict(stats=('00:12:34', '356.21 MB', '1.0x', '3.2 Mbps'))),
    ('cs', 'reconnecting', dict(stats=('00:41:08', '1.10 GB', '0.0x', '--'))),
    ('lw', 'processing', dict(stats=('00:19:52', '612.40 MB', '1.0x', '4.1 Mbps'))),
    ('yy', 'preparing', dict(line=None)),
    ('cg', 'queued', dict(line=None)),
    ('cj', 'waitingLive', dict(line=None, start='09-28 19:02')),
    ('ch', 'failed', dict(line=None, start='10-01 20:31', error='最近失败（线路解析）：获取直播流超时')),
    ('hj', 'completed', dict(stats=('01:02:45', '2.11 GB', '1.0x', '4.5 Mbps'), start='10-01 19:07')),
    ('jp', 'stopped', dict(line=None, start='09-30 22:40')),
]


def v3_appbar(lead):
    lead_icon = mr('menu') if lead == 'menu' else mr('arrow_back')
    return (f'<div class="ab"><div class="ib lead">{lead_icon}</div><div class="ttl">录制中心</div><div class="sp"></div>'
            f'<div class="ib">{rx("f3cc", 22)}</div><div class="ib">{rx("f0ea", 22)}</div><div style="width:8px"></div></div>')


def home_nav():
    items = [('ee0b', '关注', False), ('ed33', '热门', False), ('ea42', '分区', False), ('ec53', '录制中心', True)]
    return '<div class="nav">' + ''.join(f'<div class="{"on" if on else ""}"><i>{rx(c, 24)}</i>{t}</div>' for c, t, on in items) + '</div>'


def v3_phone():
    cards = ''.join(v3_card(k, s, **kw) for k, s, kw in V3_CARDS[:2])
    body = f'<div class="body"><div class="v3list">{cards}</div></div>'
    return page(393, 852, 3, STATUS_BAR + v3_appbar('menu') + v3_selector(3) + body + home_nav() + '<div class="gesture"></div>')


def v3_states():
    cards = ''.join(v3_card(k, s, **kw) for k, s, kw in V3_CARDS)
    return page(393, 4000, 2, f'<div class="v3list" style="padding-top:16px">{cards}</div>', crop=True)


def v3_empty():
    body = (f'<div class="body"><div class="v3empty"><div class="ci2">{mr("video_collection", 42)}</div>'
            '<div class="t">暂无录制任务</div><div class="s">添加直播间后将在这里显示</div></div></div>')
    return page(393, 852, 3, STATUS_BAR + v3_appbar('menu') + v3_selector(3, 7) + body + home_nav() + '<div class="gesture"></div>')


def v3_remove():
    cards = ''.join(v3_card(k, s, **kw) for k, s, kw in V3_CARDS[:2])
    body = f'<div class="body"><div class="v3list">{cards}</div></div>'
    dlg = ('<div class="scrim"></div><div class="dlg" style="top:300px">'
           '<div class="h">取消监控</div><div class="b">确定停止监控“深夜电台 · 点歌接龙到天亮”？已经保存的录制文件会保留。</div>'
           '<div class="a"><span>取消</span><span class="red">确认</span></div></div>')
    return page(393, 852, 3, STATUS_BAR + v3_appbar('menu') + v3_selector(3) + body + home_nav() + dlg + '<div class="gesture"></div>')


def v3_landscape():
    cards = ''.join(v3_card(k, s, wide=True, **kw) for k, s, kw in V3_CARDS[:2])
    body = f'<div class="body"><div class="v3list">{cards}</div></div>'
    return page(852, 393, 2, STATUS_LAND + v3_appbar('back') + v3_selector(5) + body, root='win')


def v3_wide():
    cards = ''.join(v3_card(k, s, wide=True, **kw) for k, s, kw in V3_CARDS[:3])
    body = f'<div class="body"><div class="v3list">{cards}</div></div>'
    return page(1280, 800, 1.5, v3_appbar('back') + v3_selector(9) + body, root='win')


# ---------------------------------------------------------------- new
FILTERS = [('全部', 9), ('进行中', 5), ('等待开播', 1), ('已保存', 1), ('失败', 1)]


def filters(sel=0, nums=None, counts=True, items=None):
    cells = ''
    for i, (t, c) in enumerate(items or FILTERS):
        a = n(nums) if (nums and i == 0) else ''
        cells += f'<div class="c"{a}><b class="{"on" if i == sel else ""}">{t}' + (f'<small>{c}</small>' if counts else '') + '</b></div>'
    return f'<div class="fl">{cells}</div><hr>'


def v4_appbar(lead, nums=True):
    k = (lambda x: x) if nums else (lambda x: None)
    lead_icon = mr('menu') if lead == 'menu' else mr('arrow_back')
    return (f'<div class="ab"><div class="ib lead"{n(k(1))}>{lead_icon}</div><div class="ttl">录制中心</div><div class="sp"></div>'
            f'<div class="ib"{n(k(2))}>{rx("f3cc", 22)}</div><div class="ib"{n(k(3))}>{rx("f0ea", 22)}</div><div style="width:8px"></div></div>')


ICON = {
    'idle': '<span class="ring2"><i></i></span>',
    'waiting': f'<span style="color:var(--primary)">{rx("f215", 20)}</span>',
    'preparing': '<span class="spin"></span>', 'processing': '<span class="spin"></span>',
    'queued': rx('f339', 20), 'reconnecting': rx('f33f', 20),
    'recording': '<span class="dot"></span>', 'saved': mr('check_circle', 20), 'failed': mr('error_outline', 20),
}
TONE = {'recording': 'red', 'queued': 'yellow', 'reconnecting': 'yellow', 'saved': 'green', 'failed': 'error'}
TITLE = {'idle': '没在录制', 'waiting': '等待开播', 'preparing': '准备中', 'queued': '排队中', 'recording': '录制中',
         'reconnecting': '连接断开，正在重连', 'processing': '正在整理文件', 'saved': '已保存', 'failed': '录制失败'}


def btn(kind, text, num=None, tag=None):
    inner = {'go': '<i></i>', 'stop': '<i></i>'}.get(kind, '')
    return f'<div class="{kind}"{n(num, tag)}>{inner}{text}</div>'


def status_block(state, nb=None, polling_on=True, extra=''):
    """The record panel's status card (U.2f) in the compact size: the same icon, colour,
    title and buttons; the explanatory sentence of 没在录制 / 等待开播 is left to the panel."""
    nb = nb or {}
    meta, body, buttons = '', '', ''
    if state == 'idle':
        buttons = btn('go', '开始录制', nb.get('main'))
    elif state == 'waiting':
        body = (f'<div class="sd">每 30 秒检查一次是否开播 · 上次检查 21:35</div>' if polling_on else
                '<div class="sd" style="color:#915600">“开播检测”关着，到时不会自动开始。</div>')
        buttons = btn('go', '现在就录', nb.get('main'))
    elif state == 'preparing':
        body = '<div class="sd">正在获取直播流（原画）…</div>'
        buttons = btn('pl', '取消', nb.get('main'))
    elif state == 'queued':
        body = '<div class="sd">同时最多录 3 个，现在正在录 3 个；有空位就自动开始。</div>'
        buttons = btn('pl', '取消', nb.get('main')) + btn('pl', '改上限', nb.get('limit'))
    elif state == 'recording':
        meta = '第 3 段 · 每 5 分钟一段'
        body = ('<div class="clock">00:12:34</div><div class="chips"><span>已录 356 MB</span><span>3.2 Mbps</span>'
                '<span>原画</span><span>弹幕 1,284 条</span></div>')
        buttons = btn('stop', '停止录制', nb.get('main'))
    elif state == 'reconnecting':
        meta = '第 2 次，共 5 次'
        body = '<div class="sd">28 秒后重试。已录的 00:41:08 · 1.1 GB 不会丢。</div>'
        buttons = btn('stop', '停止录制', nb.get('main'))
    elif state == 'processing':
        body = '<div class="sd">把 4 段合成一个 MP4，完成后就能播放。</div>'
    elif state == 'saved':
        meta = '今天 20:10'
        body = '<div class="sd">时长 01:02:45 · 2.1 GB · 原画</div>'
        buttons = btn('pl', '播放', nb.get('main')) + btn('pl', '打开文件夹', nb.get('folder'), 'add') + btn('go', '再录一次', nb.get('again'))
    elif state == 'failed':
        body = '<div class="sd">获取直播流时超时（第 5 次，已不再重试）。可以换个清晰度再试。</div>'
        buttons = btn('pl', '查看原因', nb.get('main')) + btn('er', '重试', nb.get('retry'))
    head = (f'<div class="sh"><span class="ic">{ICON[state]}</span><span class="tt">{TITLE[state]}</span>'
            + (f'<span class="me">{meta}</span>' if meta else '') + '</div>')
    return f'<div class="sb {TONE.get(state, "neutral")}">{head}{body}{extra}' + (f'<div class="bt">{buttons}</div>' if buttons else '') + '</div>'


def card(key, state, auto=False, nb=None, polling_on=True, extra=''):
    cover, nick, title, pid, pname, aud = ROOMS[key]
    nb = nb or {}
    pill = f'<span class="ar">{rx("f215", 13)}自动录</span>' if auto else ''
    hd = (f'<div class="hd"><div class="cov"{n(nb.get("card"))} style="background-image:url(.cache/img/{cover}.jpg)"></div>'
          f'<div class="tx"><div class="n"><span>{nick}</span>{pill}</div><div class="t">{title}</div>'
          f'<div class="m"><img src="{LOGO.format(pid)}">{pname} · {aud}</div></div>'
          f'<div class="more"{n(nb.get("more"))}>{mr("more_vert", 22)}</div></div>')
    return f'<div class="card">{hd}{status_block(state, nb, polling_on, extra)}</div>'


GROUPS = [  # 全部: the panel's states in the 3.x order (running, reconnecting, processing, preparing, queued, waiting, failed, done)
    ('录制中', [('wf', 'recording', True)]), ('重连中', [('cs', 'reconnecting', True)]), ('整理文件', [('lw', 'processing', False)]),
    ('准备中', [('yy', 'preparing', False)]), ('排队中', [('cg', 'queued', False)]), ('等待开播', [('cj', 'waiting', True)]),
    ('失败', [('ch', 'failed', False)]), ('已保存', [('hj', 'saved', False)]), ('没在录制', [('jp', 'idle', False)]),
]


def group(title, cards):
    # No group headings: every card's status block already names its state, and
    # the filters carry the counts. Cards keep the 3.x order of the states.
    return ''.join(cards)


def v4_phone():
    nb = dict(card=5, more=6, main=7)
    body = (group('录制中', [card('wf', 'recording', True, nb)])
            + group('重连中', [card('cs', 'reconnecting', True)]) + group('整理文件', [card('lw', 'processing')]))
    return page(393, 852, 3, STATUS_BAR + v4_appbar('menu') + filters(0, 4) + f'<div class="body"><div class="list">{body}</div></div>'
                + home_nav() + '<div class="gesture"></div>')


def v4_states():
    rows = ''
    for title, items in GROUPS:
        rows += group(title, [card(k, s, a) for k, s, a in items])
    # a saved recording that missed segments (3.x warning, kept)
    warn = (f'<div class="warnrow">{mr("warning_amber", 16)}<span>录制中已跳过缺失或过期的直播片段，录像内容不完整；已有的有效片段仍可保留和合并。</span></div>')
    rows += ('<div class="note">另一种样子：已保存，但录像有缺失（3.x 的提示，保留）</div>' + card('hj', 'saved', extra=warn))
    return page(393, 4400, 2, f'<div class="list" style="padding-top:8px">{rows}</div>', crop=True)


def v4_waiting_off():
    ban = (f'<div class="pban" data-n="8" data-tag="add">{mr("warning_amber", 18)}<span class="x">“开播检测”关着，等待开播的任务到时不会自动开始。</span><span class="lk">打开</span></div>')
    cards = card('cj', 'waiting', True, polling_on=False)
    body = f'<div class="list">{ban}<div style="height:8px"></div>{cards}</div>'
    return page(393, 852, 3, STATUS_BAR + v4_appbar('menu', False) + filters(2) + f'<div class="body">{body}</div>' + home_nav() + '<div class="gesture"></div>')


def v4_menu():
    body = (group('录制中', [card('wf', 'recording', True)]) + group('重连中', [card('cs', 'reconnecting', True)]))
    menu = ('<div class="menu" style="right:14px;top:226px;min-width:208px">'
            f'<div class="it">{mr("open_in_new", 20)}<span>进入直播间</span></div>'
            f'<div class="it">{rx("f215", 20)}<span>开播自动录</span><span class="sw on"></span></div>'
            '<div class="sep"></div>'
            f'<div class="it red">{rx("ec2a", 20)}<span>删除任务</span></div></div>')
    return page(393, 852, 3, STATUS_BAR + v4_appbar('menu', False) + filters(0) + f'<div class="body"><div class="list">{body}</div></div>'
                + home_nav() + '<div class="scrim" style="background:transparent"></div>' + menu + '<div class="gesture"></div>')


def v4_remove():
    body = (group('录制中', [card('wf', 'recording', True)]) + group('重连中', [card('cs', 'reconnecting', True)]))
    dlg = ('<div class="scrim"></div><div class="dlg" style="top:290px">'
           '<div class="h">删除“晚风”的录制任务？</div><div class="b">正在录的会先停止并保存；已经录好的文件会留在文件夹里。'
           '只想不再自动录，可以关掉“开播自动录”。</div>'
           '<div class="a"><span>取消</span><span class="red2">删除</span></div></div>')
    return page(393, 852, 3, STATUS_BAR + v4_appbar('menu', False) + filters(0) + f'<div class="body"><div class="list">{body}</div></div>'
                + home_nav() + dlg + '<div class="gesture"></div>')


def v4_empty():
    bar = filters(0, items=[(t, 0) for t, _ in FILTERS])
    body = (f'<div class="body"><div class="empty"><div class="ci2">{mr("video_collection", 34)}</div>'
            '<div class="t">暂无录制任务</div>'
            '<div class="s">在直播间点“录制”即可添加。打开“开播检测”后，等待开播的任务会在主播开播时自动开始。</div></div></div>')
    return page(393, 852, 3, STATUS_BAR + v4_appbar('menu', False) + bar + body + home_nav() + '<div class="gesture"></div>')


def v4_landscape():
    a = card('wf', 'recording', True)
    b = card('cs', 'reconnecting', True)
    body = f'<div class="body"><div class="list"><div class="grid2" style="grid-template-columns:1fr 1fr;padding-top:10px">{a}{b}</div></div></div>'
    return page(852, 393, 2, STATUS_LAND + v4_appbar('back', False) + filters(0) + body, root='win')


def v4_wide():
    nb = dict(card=5, more=6, main=7)
    order = [('wf', 'recording', True, nb), ('cs', 'reconnecting', True, None), ('lw', 'processing', False, None),
             ('yy', 'preparing', False, None), ('cg', 'queued', False, None), ('cj', 'waiting', True, None)]
    heads = [('录制中', 1), ('重连中', 1), ('整理文件', 1), ('准备中', 1), ('排队中', 1), ('等待开播', 1)]
    cells = ''
    for (h, c), (k, s, a, nn) in zip(heads, order):
        cells += card(k, s, a, nn)
    grid = f'<div class="grid2" style="grid-template-columns:repeat(3,1fr);padding-top:12px">{cells}</div>'
    body = f'<div class="body wide"><div class="list" style="padding:4px 24px 24px">{grid}</div></div>'
    bar = filters(0, 4).replace('<div class="fl">', '<div class="fl" style="padding:6px 21px;max-width:660px">')
    return page(1280, 800, 1.5, v4_appbar('back') + bar + body, root='win')


OUT = {
    'v3-phone': v3_phone(), 'v3-states': v3_states(), 'v3-empty': v3_empty(), 'v3-remove': v3_remove(),
    'v3-landscape': v3_landscape(), 'v3-wide': v3_wide(),
    'v4-phone': v4_phone(), 'v4-states': v4_states(), 'v4-waiting-off': v4_waiting_off(), 'v4-menu': v4_menu(),
    'v4-remove': v4_remove(), 'v4-empty': v4_empty(), 'v4-landscape': v4_landscape(), 'v4-wide': v4_wide(),
}
for name, html in OUT.items():
    open(os.path.join(HERE, name + '.html'), 'w', encoding='utf-8').write(html)
print(len(OUT), 'pages')
