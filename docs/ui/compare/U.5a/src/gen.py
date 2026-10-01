"""U.5a search page mockups: v3 restored and the new design.

v3 (tag v3.2.11): lib/modules/search/search_page.dart (AppBar with the field
:20-48, platform strip :49-58, options :225-307, status :185-222, results
grid :76-167), search_platform_strip.dart (ChoiceChips :79-90),
search_controller.dart (capability text :440-498, WebView2 dialog :559-613),
common/widgets/room_card.dart (dense cover card, standard preset),
common/widgets/app_status_view.dart, common/style/theme.dart (input
decoration :160-174, dialog :177-183).
The room card is v3's as is; its new look is U.4a's.
    python3 docs/ui/compare/U.5a/src/gen.py && python3 tools/ui/mock/render.py docs/ui/compare/U.5a/src/ --annotate"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
IMG = '.cache/img/'
LOGO = '../../../packages/live_ui/assets/platforms/'

CSS = '''
.ph .status{background:var(--surface)}
.sb24{height:24px;display:flex;align-items:center;justify-content:space-between;padding:0 16px;font:600 12px 'Geist','Noto Sans SC';background:var(--surface)}
.sb24 .mi{font-size:13px}
/* top bar with the search field */
.top{height:56px;display:flex;align-items:center;padding:0 16px;background:var(--surface);flex:none;gap:12px}
.fld{flex:1;min-width:0;height:48px;border:1px solid var(--outline);border-radius:24px;background:var(--scl);display:flex;align-items:center}
.fld.foc{border:1.5px solid var(--primary);border-radius:12px}
.fld.v4.foc{border:2px solid var(--primary);border-radius:24px}
.fld .ic{width:48px;height:48px;display:grid;place-items:center;color:var(--onv);flex:none}
.fld .ic .mi,.fld .ic .mr{font-size:24px}.fld .ic .rx{font-size:22px}
.fld .tx{flex:1;min-width:0;font-size:14px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.fld .tx.hint{font-size:13px;color:rgba(67,71,78,.6)}
.fld .tx.hint4{font-size:14px;color:var(--onv)}
.caret{display:inline-block;width:2px;height:18px;background:var(--primary);vertical-align:-3px;margin:0 1px}
/* platform strip */
.strip{height:56px;display:flex;align-items:center;gap:8px;padding:0 12px;overflow:hidden;background:var(--surface);flex:none;white-space:nowrap}
.cc{height:32px;border-radius:8px;border:1px solid var(--ov);display:flex;align-items:center;gap:6px;padding:0 12px;font-size:13px;font-weight:500;color:var(--onv);flex:none}
.cc.on{background:var(--sc);border-color:var(--primary);color:var(--osc)}
.cc img{width:18px;height:18px;border-radius:4px;margin-left:-4px}.cc .mr{font-size:18px;margin-left:-4px}
/* options */
.opts{background:var(--scl);padding:8px 12px 9px;flex:none}
.crow{display:flex;gap:8px;align-items:center;min-height:48px;white-space:nowrap;overflow:hidden}
.crow.wrap{flex-wrap:wrap;row-gap:0}
.fc{height:32px;border-radius:8px;border:1px solid var(--ov);display:flex;align-items:center;gap:8px;padding:0 12px 0 8px;font-size:13px;font-weight:500;color:var(--onv);flex:none;margin:8px 0}
.fc.on{background:var(--sc);border-color:transparent;color:var(--osc)}
.fc .mr{font-size:18px}.fc .rx{font-size:18px;margin:0 -4px 0 -4px}
.seg{height:32px;border-radius:16px;border:1px solid var(--outline);display:flex;overflow:hidden;flex:none;margin:8px 0}
.seg div{display:flex;align-items:center;padding:0 14px;font-size:13px;font-weight:500;color:var(--on)}
.seg div+div{border-left:1px solid var(--outline)}.seg .on{background:var(--sc);color:var(--osc)}
.note{display:flex;gap:6px;align-items:flex-start;font-size:12px;line-height:1.3;color:var(--onv)}
.note>.mr{color:var(--primary);font-size:16px;flex:none}
.note .x{flex:1;min-width:0}
.note .one{white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.tbtn{color:var(--primary);font-size:13px;font-weight:500;height:32px;display:flex;align-items:center}
.note4{display:flex;gap:6px;align-items:center;font-size:12px;line-height:1.3;color:var(--onv);min-height:32px}
.note4>.mr{color:var(--primary);font-size:16px;flex:none}.note4 .x{flex:1;min-width:0;overflow:hidden;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical}
.crow .note4 .x{display:block;white-space:nowrap;text-overflow:ellipsis}
.note4 .go{flex:none;color:var(--onv);font-size:18px}
/* results: v3's dense cover card (RoomCard, standard preset) */
.grid{display:grid;gap:8px;padding:8px}
.card{background:#fff;border-radius:20px;overflow:hidden;position:relative}
.cv{position:relative;aspect-ratio:16/9;border-radius:20px;background:#F5F5F5 center/cover}
.mb{position:absolute;right:8px;bottom:8px;display:flex;align-items:center;gap:4px;padding:3px 6px;border-radius:10px;background:rgba(0,0,0,.48);color:#fff;font:700 11px 'Geist','Noto Sans SC'}
.mb .mr{font-size:14px}
.lt{display:flex;align-items:center;gap:8px;padding:8px 10px;min-height:58px}
.lt .av{width:34px;height:34px;border-radius:17px}
.lt .tx{flex:1;min-width:0}
.lt .t{font-size:13px;line-height:18px;font-weight:600;color:rgba(0,0,0,.87);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.lt .s{font-size:12px;line-height:17px;font-weight:500;color:#616161;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.skel .cv{background:var(--sch)}.skel .av{background:var(--sch)}
.skel .t{height:12px;width:80%;border-radius:6px;background:var(--sch);margin:3px 0 7px}.skel .s{height:10px;width:50%;border-radius:5px;background:var(--sch)}
.foot{display:flex;justify-content:center;padding:8px 16px 20px}
.foot .tb{display:flex;align-items:center;gap:6px;color:var(--primary);font-size:13px;font-weight:500;height:40px;padding:0 12px}
/* status view (AppStatusView) */
.sv{display:flex;flex-direction:column;align-items:center;justify-content:center;text-align:center}
.svc{width:86px;height:86px;border-radius:43px;background:rgba(225,226,232,.15);border:1px solid rgba(54,97,142,.05);display:grid;place-items:center}
.svc .mr{font-size:42px;color:rgba(54,97,142,.6)}
.sv h4{margin-top:20px;font-size:15px;font-weight:600}
.sv p{padding:6px 28px 0;max-width:376px;text-wrap:balance;font-size:13px;line-height:1.5;color:rgba(0,0,0,.6)}
.sv .tb{margin-top:16px;display:flex;align-items:center;gap:8px;color:var(--primary);font-size:13px;font-weight:500;height:40px;padding:0 12px}
.sv .tb .mr{font-size:18px}
.spin{width:40px;height:40px;border-radius:20px;border:4px solid var(--primary);border-right-color:transparent;border-bottom-color:transparent;transform:rotate(30deg)}
.lin{height:2px;background:rgba(54,97,142,.2);position:relative;overflow:hidden}.lin i{position:absolute;left:18%;width:38%;top:0;bottom:0;background:var(--primary)}
/* keyboard placeholder */
.kb{position:absolute;left:0;right:0;bottom:0;height:290px;background:#D3D6DC;z-index:30;padding:10px 4px 28px;display:flex;flex-direction:column;gap:9px}
.kb .r{display:flex;gap:5px;justify-content:center;flex:1}.kb .r i{flex:1;max-width:34px;border-radius:5px;background:#fff;box-shadow:0 1px 0 rgba(0,0,0,.25)}
.kb .r i.w{max-width:none;flex:5}.kb .r i.d{background:#ADB3BC}
.kb .lab{position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);font-size:12px;color:#40454D;background:rgba(255,255,255,.75);padding:3px 8px;border-radius:6px}
/* banners and notes */
.mban{background:var(--scl);padding:16px 16px 0;border-bottom:1px solid var(--ov)}
.mban p{font-size:13px;line-height:1.45}
.mban .acts{display:flex;justify-content:flex-end;gap:8px;padding:8px 0}
.mban .acts span{color:var(--primary);font-size:13px;font-weight:500;padding:0 12px;height:40px;display:flex;align-items:center}
.fnote{margin:8px 12px 0;padding:8px 4px 2px 12px;border-radius:12px;background:var(--sch)}
.fnote .h{display:flex;gap:8px;align-items:flex-start;font-size:13px;line-height:1.45}.fnote .h .mr{font-size:18px;color:var(--onv);flex:none;margin-top:1px}
.fnote .h .x{width:32px;height:28px;display:grid;place-items:center;color:var(--onv);flex:none;margin-top:-4px}
.fnote .a{display:flex;flex-wrap:wrap}.fnote .a span{color:var(--primary);font-size:13px;font-weight:500;padding:0 10px;height:36px;display:flex;align-items:center}
.pend{padding:6px 12px 0}.pend p{font-size:12px;color:var(--onv);margin-top:4px}
.lbanner{margin:8px 12px 0;border-radius:12px;background:var(--sc);color:var(--osc);display:flex;align-items:center;gap:14px;padding:10px 12px 10px 16px}
.lbanner .x{flex:1}.lbanner b{display:block;font-size:14px;font-weight:600}.lbanner small{font-size:12px}
.lbanner .go{height:40px;padding:0 18px;border-radius:20px;background:var(--primary);color:var(--onPrimary);font-size:13px;font-weight:600;display:flex;align-items:center}
.hist{padding:12px 16px 4px}.hist .hh{display:flex;align-items:center;gap:6px;font-size:14px;font-weight:500}
.hist .hh .mr{font-size:18px;color:var(--onv)}.hist .hh .cl{margin-left:auto;color:var(--primary);font-size:13px;display:flex;align-items:center;gap:4px;height:40px}
.hist .ws{display:flex;flex-wrap:wrap;gap:8px}
.ic2{height:32px;border-radius:8px;border:1px solid var(--ov);display:flex;align-items:center;gap:6px;padding:0 6px 0 12px;font-size:13px;font-weight:500;color:var(--onv)}
.ic2 .mr{font-size:18px}
/* menus, dialogs, panels */
.pmenu{position:absolute;z-index:21;background:var(--sc2,#ECEEF4);border-radius:4px;box-shadow:0 3px 10px rgba(0,0,0,.22);padding:8px 0;min-width:112px}
.pmenu div{height:48px;display:flex;align-items:center;padding:0 12px;font-size:13px;font-weight:500}
.pmenu div.sel{background:rgba(25,28,32,.08)}
.dlg2{position:absolute;z-index:21;background:var(--sch);border-radius:24px;padding:24px}
.dlg2 h3{font-size:20px;font-weight:600;display:flex;gap:8px;align-items:flex-start;line-height:1.3}
.dlg2 .c{margin-top:16px;font-size:13px;line-height:1.4;white-space:pre-line}
.dlg2 .acts{display:flex;justify-content:flex-end;gap:8px;margin-top:24px;align-items:center}
.dlg2 .acts span{height:48px;display:flex;align-items:center;padding:0 12px;font-size:13px;font-weight:500;color:var(--primary)}
.dlg2 .acts span.fill{background:var(--primary);color:var(--onPrimary);border-radius:12px;padding:0 24px;font-weight:600}
.shd{position:absolute;left:0;right:0;bottom:0;z-index:21;background:var(--scc);border-radius:24px 24px 0 0;overflow:hidden}
.shd .hd{width:32px;height:4px;border-radius:2px;background:var(--onv);opacity:.4;margin:22px auto 14px}
.shd h3{font-size:16px;font-weight:600;padding:0 20px}.shd .d{font-size:12px;color:var(--onv);padding:4px 20px 0;line-height:1.45}
.shd .qb{display:flex;gap:8px;padding:12px 20px 4px}.shd .qb span{height:32px;border-radius:8px;border:1px solid var(--ov);font-size:13px;font-weight:500;padding:0 12px;display:flex;align-items:center;color:var(--primary)}
.shd .gh{padding:14px 20px 4px;font-size:13px;font-weight:600;color:var(--primary);display:flex}.shd .gh small{margin-left:auto;color:var(--onv);font-weight:500;font-size:12px}
.prow{display:flex;align-items:center;gap:12px;padding:6px 20px;min-height:52px}
.prow .cb{width:18px;height:18px;border-radius:3px;background:var(--primary);display:grid;place-items:center;color:#fff;flex:none}.prow .cb .mr{font-size:16px}
.prow .cb.off{background:transparent;border:2px solid var(--onv)}
.prow img{width:24px;height:24px;border-radius:6px;flex:none}
.prow .x{flex:1;min-width:0}.prow .n{font-size:14px}.prow .s{font-size:12px;color:var(--onv);margin-top:1px}
.prow .tg{font-size:11px;padding:1px 6px;border-radius:4px;background:var(--sch);color:var(--onv);margin-left:4px}
.dim{position:absolute;inset:0;background:rgba(0,0,0,.4);z-index:20}
.tip{z-index:40}
/* composite pages */
.multi{display:flex;gap:24px;padding:0;background:#E9EBF0}
.multi .col{display:flex;flex-direction:column;gap:8px}
.multi .cap{height:34px;display:flex;align-items:center;justify-content:center;font-size:15px;font-weight:600;color:#191C20}
.multi .ph{box-shadow:0 0 0 1px #C3C7CF}
.col2{display:flex;flex-direction:column;height:100%}
'''

mr = lambda n, s=None: f'<span class="mr"{f" style=\"font-size:{s}px\"" if s else ""}>{n}</span>'
mi = lambda n, s=None: f'<span class="mi"{f" style=\"font-size:{s}px\"" if s else ""}>{n}</span>'
rx = lambda c, s=None: f'<span class="rx"{f" style=\"font-size:{s}px\"" if s else ""}>&#x{c};</span>'


def dn(n, tag=None, at=None):
    if n is None:
        return ''
    return f' data-n="{n}"' + (f' data-tag="{tag}"' if tag else '') + (f' data-at="{at}"' if at else '')


SITES = [('bilibili', '哔哩哔哩'), ('douyu', '斗鱼'), ('huya', '虎牙'), ('douyin', '抖音'), ('kuaishou', '快手'), ('cc', '网易CC'),
         ('twitch', 'Twitch'), ('soop', 'Soop'), ('yy', 'YY'), ('acfun', 'AcFun 直播'), ('picarto', 'Picarto'),
         ('twitcasting', 'TwitCasting'), ('missevan', '猫耳 FM'), ('inke', '映客'), ('kilakila', '克拉克拉'), ('xiaohongshu', '小红书'),
         ('niconico', 'niconico'), ('weibo', '微博直播'), ('showroom', 'SHOWROOM'), ('chzzk', 'CHZZK')]

# (cover, avatar, title, streamer, metric icon, value); value None = not live
ROOMS = [
    ('1', '65', '晚风电台｜深夜点歌', '晚风', 'people_alt', '1.2万'),
    ('111', '111', '晚风吹过的夏天 · 吉他弹唱', '晚风小屋', 'whatshot', '8765'),
    ('133', '133', '【晚风】原创歌曲首发', '晚风同学', 'people_alt', '3.4万'),
    ('169', '169', '晚风与夜空 户外慢直播', '夜空里的晚风', 'whatshot', '2013'),
    ('183', '183', '晚风 KTV 等你来点歌', '晚风KTV', 'people_alt', '5.6万'),
    ('206', '206', '听晚风讲故事', '讲故事的晚风', 'whatshot', '980'),
    ('219', '219', '晚风｜周末合唱', '晚风合唱团', 'people_alt', '1.5万'),
    ('225', '225', '晚风的录播间', '晚风录播', None, None),
    ('237', '237', '海边的晚风 · 日落直播', '海边晚风', 'people_alt', '6421'),
    ('250', '250', '晚风读书会', '晚风书房', 'whatshot', '1.1万'),
    ('287', '287', '晚风里的城市骑行', '骑行晚风', 'people_alt', '3355'),
    ('292', '292', '晚风钢琴｜轻音乐陪伴', '晚风钢琴', 'whatshot', '2.7万'),
    ('304', '304', '晚风小厨房', '晚风厨房', 'people_alt', '742'),
    ('319', '319', '晚风打游戏', '晚风电竞', 'whatshot', '9.3万'),
    ('338', '338', '晚风画室 · 水彩', '晚风画画', None, None),
    ('342', '342', '晚风露营夜', '露营的晚风', 'people_alt', '1876'),
    ('360', '360', '晚风茶话会', '晚风茶馆', 'whatshot', '4410'),
    ('367', '367', '晚风猫咖', '晚风猫咖', 'people_alt', '5280'),
]

ALL_NOTE = ('App 内原生搜索覆盖全部 34 个平台；未开播结果仅在平台接口返回时显示。 TikTok LIVE、YouTube Live 仅支持精确频道号或频道直播链接，'
            '可查询未开播频道；暂不支持昵称和关键词搜索。 小红书、百度直播、LOOK 直播 当前仅支持直播房间号或官网直播链接查询……')
OVERSEAS_FAILED = 'Twitch、Soop、Picarto、TwitCasting、niconico、SHOWROOM、CHZZK、LiveMe、TikTok LIVE、YouTube Live、Bigo Live、PandaTV'


def page(size, body, cls='ph', style=''):
    return (f'<!doctype html><html><head><meta charset="utf-8"><meta name="mock-size" content="{size}">'
            f'<link rel="stylesheet" href="kit/kit.css"><style>{CSS}</style></head><body>'
            f'<div class="{cls}" style="{style}">{body}</div></body></html>')


STATUS = ('<div class="status"><span>21:36</span><span class="r"><span class="mi">signal_cellular_alt</span>'
          '<span class="mi">wifi</span><span class="mi">battery_full</span></span></div>')
SB24 = ('<div class="sb24"><span>21:36</span><span style="display:flex;gap:4px"><span class="mi">wifi</span>'
        '<span class="mi">battery_full</span></span></div>')
SYN = '<div class="syn" style="top:auto;bottom:10px">示意图片</div>'


def keyboard():
    rows = ['<i></i>' * 10, '<i></i>' * 9, '<i class="d"></i>' + '<i></i>' * 7 + '<i class="d"></i>',
            '<i class="d"></i><i class="d"></i><i class="w"></i><i class="d"></i><i class="d" style="background:#36618E"></i>']
    return '<div class="kb">' + ''.join(f'<div class="r">{r}</div>' for r in rows) + '<span class="lab">输入法键盘</span></div>'


# ---------- shared pieces ----------
def card(r, n=None, delete=False):
    cover, av, title, nick, icon, val = r
    badge = f'<div class="mb">{mr(icon)}{val}</div>' if val else ''
    dele = f'<div class="del">{rx("ec2a")}</div>' if delete else ''
    return (f'<div class="card"{dn(n, "keep")}><div class="cv" style="background-image:url({IMG}{cover}.jpg)">{badge}{dele}</div>'
            f'<div class="lt"><span class="av" style="background-image:url({IMG}{av}.jpg)"></span>'
            f'<div class="tx"><div class="t">{title}</div><div class="s">{nick}</div></div></div></div>')


def skel_card():
    return '<div class="card skel"><div class="cv"></div><div class="lt"><span class="av"></span><div class="tx"><div class="t"></div><div class="s"></div></div></div></div>'


def grid(cols, rooms, n_first=None, start=0):
    cells = ''.join(card(r, n_first if i == 0 else None) for i, r in enumerate(rooms[start:]))
    return f'<div class="grid" style="grid-template-columns:repeat({cols},minmax(0,1fr))">{cells}</div>'


def status_view(icon, title, sub='', btn=None, btn_icon='refresh', style='flex:1'):
    s = f'<p>{sub}</p>' if sub is not None else ''
    b = f'<div class="tb">{mr(btn_icon)}{btn}</div>' if btn else ''
    return f'<div class="sv" style="{style}"><div class="svc">{mr(icon)}</div><h4>{title}</h4>{s}{b}</div>'


def strip(sel=0, logos=False, n=None, count=None):
    items = [('all', '全部')] + SITES[:count or len(SITES)]
    out = []
    for i, (pid, name) in enumerate(items):
        lead = ''
        if logos:
            lead = mr('apps') if pid == 'all' else f'<img src="{LOGO}{pid}.png">'
        out.append(f'<div class="cc{" on" if i == sel else ""}"{dn(n) if i == 1 else ""}>{lead}{name}</div>')
    return f'<div class="strip">{"".join(out)}</div>'


# ---------- v3 ----------
def v3_top(text='晚风', focused=False):
    tx = (f'<span class="tx">{text}{"<i class=caret></i>" if focused else ""}</span>' if text
          else f'<span class="tx hint">{"<i class=caret></i>" if focused else ""}输入直播关键字</span>')
    return (f'<div class="top"><div class="fld{" foc" if focused else ""}"><span class="ic">{mi("arrow_back")}</span>'
            f'{tx}<span class="ic">{mi("search")}</span></div></div>')


def v3_opts(site=None, expanded=False):
    chips = (f'<div class="fc on">{mr("check")}包含未开播</div>'
             f'<div class="fc">{mr("sort")}综合：直播→观众→粉丝</div>')
    if site in ('bilibili', 'huya'):
        chips += f'<div class="fc">{mr("open_in_browser")}继续网页搜索</div>'
    if site is None:
        text, more = ALL_NOTE, True
    elif site == 'bilibili':
        text, more = '哔哩哔哩 原生搜索会返回直播中及部分未开播房间，可用上方开关筛选。', True
    else:
        text, more = '虎牙 原生接口只返回正在直播的房间。', False
    body = f'<div class="one">{text}</div>' + ('<div class="tbtn">展开说明</div>' if more else '')
    return (f'<div class="opts"><div class="crow">{chips}</div><div style="height:6px"></div>'
            f'<div class="note">{mr("info_outline")}<div class="x">{body}</div></div></div>')


def v3_banner():
    return (f'<div class="mban"><p>部分平台请求失败：{OVERSEAS_FAILED}</p>'
            '<div class="acts"><span>关闭</span></div></div>')


def v3_phone_results(site=None, sel=0, keyword='晚风', banner=False, rooms=ROOMS, body_extra=''):
    content = v3_opts(site) + (v3_banner() if banner else '') + grid(2, rooms)
    return (STATUS + v3_top(keyword) + strip(sel) +
            f'<div style="overflow:hidden;height:704px">{content}</div>' + body_extra)


def v3_phone_status(site, sel, keyword, inner, pending=False):
    return (STATUS + v3_top(keyword) + strip(sel) +
            '<div class="col2" style="height:704px">' + v3_opts(site) + ('<div class="lin"><i></i></div>' if pending else '') + inner + '</div>')


def v3_spinner():
    return '<div style="flex:1;display:grid;place-items:center"><div class="spin"></div></div>'


# ---------- new design ----------
def v4_top(text='晚风', focused=False, n=True, empty_paste=False, wide_field=None, strip_html=''):
    if text:
        tx = f'<span class="tx">{text}{"<i class=caret></i>" if focused else ""}</span>'
        side = f'<span class="ic"{dn(3 if n else None, "add")}>{mr("close")}</span>'
    else:
        tx = f'<span class="tx hint4">{"<i class=caret></i>" if focused else ""}搜索直播间、主播或粘贴链接</span>'
        side = f'<span class="ic"{dn(3 if n else None, "add")}>{mr("content_paste")}</span>'
    fstyle = f' style="flex:none;width:{wide_field}px"' if wide_field else ''
    fld = (f'<div class="fld v4{" foc" if focused else ""}"{fstyle}{dn(2 if n else None, "chg", "tc")}>'
           f'<span class="ic"{dn(1 if n else None, "keep", "bl")}>{mi("arrow_back")}</span>{tx}{side}'
           f'<span class="ic"{dn(4 if n else None, "keep", "br")}>{mi("search")}</span></div>')
    if strip_html:
        return f'<div class="top" style="padding:0 0 0 16px;gap:4px">{fld}<div style="flex:1;min-width:0;overflow:hidden">{strip_html}</div></div>'
    return f'<div class="top">{fld}</div>'


def v4_opts(site=None, n=True, one_line=False, mode='rooms', excluded=0):
    seg = (f'<div class="seg"{dn(6 if n else None, "add")}><div class="{"on" if mode == "rooms" else ""}">直播间</div>'
           f'<div class="{"on" if mode == "anchors" else ""}">主播</div></div>')
    chips = (seg + f'<div class="fc on"{dn(7 if n else None, "keep")}>{mr("check")}包含未开播</div>'
             f'<div class="fc"{dn(8 if n else None)}>{mr("sort")}综合{rx("ea4e")}</div>')
    if site in ('bilibili', 'huya'):
        chips += f'<div class="fc"{dn(11 if n else None, "keep")}>{mr("open_in_browser")}继续网页搜索</div>'
    if site is None:
        total = 34 - excluded
        text = f'同时搜索 {total} 个平台，各平台能搜到的范围不同，点此查看。' if not excluded else f'同时搜索 {total} 个平台（共 34 个，已排除 {excluded} 个），点此查看或修改。'
    elif site == 'bilibili':
        text = '哔哩哔哩：能搜到直播中和部分未开播的房间，可用“包含未开播”筛选。'
    else:
        text = '虎牙：只能搜到正在直播的房间。'
    note = f'<div class="note4"{dn(9 if n else None, None, "bl")}>{mr("info_outline")}<span class="x">{text}</span>{mr("chevron_right")}</div>'
    if one_line:
        return f'<div class="opts" style="padding:0 12px"><div class="crow" style="gap:8px">{chips}<div style="flex:1;min-width:0;margin-left:8px">{note}</div></div></div>'
    return f'<div class="opts" style="padding:2px 12px 6px"><div class="crow wrap">{chips}</div>{note}</div>'


def v4_pending(count):
    return f'<div class="pend"><div class="lin"><i></i></div><p>还有 {count} 个平台在搜索…</p></div>'


def v4_fail_note(all_sites=True):
    acts = '<span>查看是哪些</span><span>重试</span>' + ('<span>搜索范围</span>' if all_sites else '') + '<span>代理设置</span>'
    return (f'<div class="fnote"><div class="h">{mr("info_outline")}<span style="flex:1">有 12 个平台连接失败，海外平台可能需要在设置里配置代理</span>'
            f'<span class="x">{mr("close", 18)}</span></div><div class="a">{acts}</div></div>')


def v4_history():
    words = ['晚风', '唱见电台', '英雄联盟', '户外徒步', '吉他弹唱']
    ws = ''.join(f'<div class="ic2">{w}{mr("close")}</div>' for w in words)
    return (f'<div class="hist"><div class="hh">{mr("history")}搜索历史<span class="cl">{mr("delete_sweep", 18)}清空</span></div>'
            f'<div class="ws">{ws}</div></div>')


def v4_link_banner():
    return ('<div class="lbanner"><div class="x"><b>识别到直播链接</b><small>点“进入”直接打开这个直播间</small></div>'
            '<span class="go">进入</span></div>')


def v4_phone_results(site=None, sel=0, keyword='晚风', n=True, extra='', rooms=ROOMS, before_grid=''):
    content = v4_opts(site, n) + before_grid + grid(2, rooms, 10 if n else None)
    return (STATUS + v4_top(keyword, n=n) + strip(sel, True, 5 if n else None) +
            f'<div style="overflow:hidden;height:704px">{content}</div>' + extra)


def v4_phone_col(site, sel, keyword, inner, focused=False):
    return (STATUS + v4_top(keyword, focused=focused, n=False) + strip(sel, True) +
            '<div class="col2" style="height:704px">' + v4_opts(site, False) + inner + '</div>')


def composite(phones):
    """phones: [(inner html, caption)]"""
    w = 393 * len(phones) + 24 * (len(phones) - 1)
    body = ''.join(f'<div class="col"><div class="cap">{c}</div><div class="ph">{p}</div></div>' for p, c in phones)
    return page(f'{w}x894@1.5', body, 'multi', f'width:{w}px;height:894px')


# ---------- the pages ----------
OUT = {}

# v3 portrait: all platforms, results
OUT['v3-phone'] = page('393x852@3', v3_phone_results() + SYN)
# v3 portrait: one platform chosen; the web search chip is cut off
OUT['v3-phone-platform'] = page('393x852@3', v3_phone_results('bilibili', 1, rooms=ROOMS[2:]) + SYN)
# v3 just opened: keyboard up
OUT['v3-start'] = page('393x852@3', STATUS + v3_top('', focused=True) + strip(0) +
                       '<div class="col2" style="height:704px">' + v3_opts() +
                       status_view('travel_explore', '全平台原生搜索', '输入关键词后汇总各平台直播间，可筛选未开播结果并切换综合、平台、观众或粉丝排序', style='height:250px') +
                       '</div>' + keyboard())
# v3 states
OUT['v3-states'] = composite([
    (v3_phone_status(None, 0, '晚风', v3_spinner()), '正在搜索'),
    (v3_phone_results(banner=True) + SYN, '部分平台失败'),
    (v3_phone_status('huya', 3, '晚风小镇', status_view('search_off', '没有找到直播间', '', '继续网页搜索', 'refresh')), '没有结果（单个平台）'),
    (v3_phone_status(None, 0, '晚风小镇', status_view('search_off', '结果里暂时没有正在直播的房间', '', '显示未开播结果', 'refresh')), '结果都没开播（关了包含未开播）'),
])

# v3 landscape phone 852x393: AppBar + strip pinned, options scroll
OUT['v3-land'] = page('852x393@2', SB24 + v3_top() + strip(0) +
                      f'<div style="overflow:hidden;height:257px">{v3_opts()}{grid(3, ROOMS)}</div>' + SYN,
                      'win', '--w:852px;--h:393px')
# v3 wide 1280x800: the field spans the window, 4 columns
OUT['v3-wide'] = page('1280x800@1.5', v3_top() + strip(0) +
                      f'<div style="overflow:hidden;height:688px">{v3_opts()}{grid(4, ROOMS)}</div>' + SYN,
                      'win', '--w:1280px;--h:800px')
# v3 WebView2 dialog (Windows, every time the search page opens)
DLG_V3 = (f'<div class="dim"></div><div class="dlg2" style="left:430px;top:250px;width:420px">'
          f'<h3><span class="mr" style="font-size:24px;color:var(--error)">report_problem</span><span>系统组件缺失</span></h3>'
          '<div class="c">您的 Windows 系统缺少网页核心组件 (WebView2 Runtime)。如果不安装，应用内的网页搜索功能将完全无法使用。\n\n是否立即前往微软官网下载安装？</div>'
          '<div class="acts"><span>取消</span><span class="fill">打开下载页</span></div></div>')
OUT['v3-webview2'] = page('1280x800@1.5', v3_top('', focused=True) + strip(0) +
                          f'<div class="col2" style="height:688px">{v3_opts()}' +
                          status_view('travel_explore', '全平台原生搜索', '输入关键词后汇总各平台直播间，可筛选未开播结果并切换综合、平台、观众或粉丝排序') +
                          '</div>' + DLG_V3, 'win', '--w:1280px;--h:800px')

# new: portrait, all platforms
OUT['v4-phone'] = page('393x852@3', v4_phone_results() + SYN)
# new: one platform; every chip visible (row wraps)
OUT['v4-phone-platform'] = page('393x852@3', STATUS + v4_top('晚风', n=False) + strip(1, True) +
                                f'<div style="overflow:hidden;height:704px">{v4_opts("bilibili", True)}{grid(2, ROOMS[2:])}</div>' + SYN)
# new: sort menu open
OUT['v4-sort'] = page('393x852@3', v4_phone_results(n=False) +
                      '<div class="menu" style="left:170px;top:206px;min-width:200px">'
                      '<div class="it on"><span>综合：直播→观众→粉丝</span>' + rx('eb7b') + '</div>'
                      '<div class="it"><span>平台优先：按主页顺序</span></div><div class="it"><span>观众优先</span></div>'
                      '<div class="it"><span>粉丝优先</span></div></div>' + SYN)
# new: just opened (recent searches above the keyboard) / a room link pasted
OUT['v4-start'] = page('393x852@3', STATUS + v4_top('', focused=True, n=False) + strip(0, True) + '<div class="col2" style="height:704px">' + v4_opts(None, False) +
                       v4_history() + status_view('travel_explore', '搜索全平台直播', '输入关键词搜索各平台的直播间或主播；粘贴直播链接可直接进入直播间', style='height:190px;margin-top:4px') +
                       '</div>' + keyboard())
OUT['v4-link'] = page('393x852@3', STATUS + v4_top('https://live.bilibili.com/21452505', n=False) + strip(0, True) + '<div class="col2" style="height:704px">' +
                      v4_opts(None, False) + v4_link_banner() + v4_history() + '</div>')
# new: states
OUT['v4-states'] = composite([
    (v4_phone_col(None, 0, '晚风', v4_pending(34) + f'<div class="grid" style="grid-template-columns:repeat(2,minmax(0,1fr))">{skel_card() * 6}</div>'), '正在搜索：骨架卡片'),
    (v4_phone_col(None, 0, '晚风', v4_pending(3) + v4_fail_note() + grid(2, ROOMS)) + SYN, '部分平台失败，还有 3 个在搜'),
    (v4_phone_col('huya', 3, '晚风小镇', status_view('search_off', '没有找到直播间', '换个关键词试试，或者切换到其他平台', '继续网页搜索', 'open_in_browser')), '没有结果（单个平台）'),
    (v4_phone_col(None, 0, '晚风小镇', status_view('search_off', '结果里暂时没有正在直播的房间', '找到的都是未开播的房间，已被“包含未开播”筛选隐藏', '显示未开播结果', 'visibility')), '结果都没开播'),
])


# new: scope panel ("all": which platforms, what each finds)
def prow(pid, name, sub, tags=(), on=True):
    t = ''.join(f'<span class="tg">{x}</span>' for x in tags)
    cb = f'<span class="cb">{mr("check")}</span>' if on else '<span class="cb off"></span>'
    return f'<div class="prow">{cb}<img src="{LOGO}{pid}.png"><div class="x"><div class="n">{name}{t}</div><div class="s">{sub}</div></div></div>'


SCOPE = ('<div class="dim"></div><div class="shd" style="height:640px"><div class="hd"></div>'
         '<span style="position:absolute;right:8px;top:36px;width:48px;height:48px;display:grid;place-items:center;color:var(--onv)">' + mr('close') + '</span>'
         '<h3>“全部”搜索哪些平台</h3><div class="d">没选中的平台不参加“全部”搜索，单独选它时仍然可以搜。设置会记住。<br>“主播”：能搜主播；“网页”：能打开平台的网页搜索。</div>'
         '<div class="qb"><span>只搜国内平台</span><span>全选</span></div>'
         '<div class="gh">国内平台<small>已选 19 / 19</small></div>'
         + prow('bilibili', '哔哩哔哩', '能搜到直播中和部分未开播的房间', ('主播', '网页'))
         + prow('douyu', '斗鱼', '能搜到直播中和部分未开播的房间', ('主播', '网页'))
         + prow('huya', '虎牙', '只能搜到正在直播的房间', ('主播', '网页'))
         + prow('douyin', '抖音', '只能搜到正在直播的房间', ('网页',))
         + prow('xiaohongshu', '小红书', '只能用房间号或直播链接查找')
         + '<div class="gh">海外平台<small>已选 15 / 15</small></div>'
         + prow('twitch', 'Twitch', '能搜到直播中和部分未开播的房间', ('网页',))
         + prow('youtube', 'YouTube Live', '关键词只能搜到正在直播的频道') + '</div>')
OUT['v4-scope'] = page('393x852@3', v4_phone_results(n=False) + SCOPE)

# new: landscape phone: field and platforms share the top row; options in one line
OUT['v4-land'] = page('852x393@2', SB24 + v4_top('晚风', n=False, wide_field=330, strip_html=strip(0, True)) +
                      f'<div style="overflow:hidden;height:313px">{v4_opts(None, False, True)}{grid(4, ROOMS)}</div>' + SYN,
                      'win', '--w:852px;--h:393px')
# new: landscape after scrolling down: the options row slid away
OUT['v4-land-scrolled'] = page('852x393@2', SB24 + v4_top('晚风', n=False, wide_field=330, strip_html=strip(0, True)) +
                               f'<div style="overflow:hidden;height:313px;position:relative"><div style="margin-top:-96px">{grid(4, ROOMS[4:])}</div></div>' + SYN,
                               'win', '--w:852px;--h:393px')
# new: wide 1280x800
FOOT = f'<div class="foot"><div class="tb"{dn(12, "keep")}>{mr("expand_more")}加载更多结果</div></div>'
OUT['v4-wide'] = page('1280x800@1.5', v4_top('晚风', wide_field=480, strip_html=strip(0, True, 5)) +
                      f'<div style="overflow:hidden;height:744px">{v4_opts(None, True, True)}{grid(6, ROOMS, 10)}{FOOT}</div>' + SYN +
                      '<div class="tip" style="left:300px;top:100px">排序</div>',
                      'win', '--w:1280px;--h:800px')
# new: WebView2 missing, only when web search is tapped (Windows)
DLG_V4 = (f'<div class="dim"></div><div class="dlg2" style="left:420px;top:240px;width:440px">'
          f'<h3><span class="mr" style="font-size:24px;color:var(--error)">report_problem</span><span>系统组件缺失</span></h3>'
          '<div class="c">缺少网页核心组件 (WebView2 Runtime)，网页搜索不能在应用里打开。\n可以先用系统浏览器打开；装好组件后就能在应用里搜索，并在打开直播间页面时直接进入。</div>'
          '<div class="acts"><span>取消</span><span>打开下载页</span><span class="fill">用系统浏览器打开</span></div></div>')
OUT['v4-webview2'] = page('1280x800@1.5', v4_top('晚风', wide_field=480, n=False, strip_html=strip(1, True)) +
                          f'<div style="overflow:hidden;height:744px">{v4_opts("bilibili", False, True)}{grid(6, ROOMS[2:14])}</div>' + DLG_V4,
                          'win', '--w:1280px;--h:800px')

for name, html in OUT.items():
    open(os.path.join(HERE, name + '.html'), 'w', encoding='utf-8').write(html)
print(len(OUT), 'pages')
