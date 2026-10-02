"""U.4e area rooms page (分区房间) mockups: v3 restored and the new design.

v3: lib/modules/area_rooms/area_rooms_page.dart (AppBar title = area name :35,
grid 2/3/4/5 columns :52, RoomCard(dense) :76, empty "无数据" :45, the follow
pill FavoriteAreaFloatingButton :90-288, unfollow dialog :115-141), list shell
common/base/base_page_view.dart (status views, back-to-top / bottom :179,
desktop pager), room card common/widgets/room_card.dart (standard preset:
white card radius 20, 16:9 cover, audience badge, dense ListTile with avatar
34, title 13 w600, anchor 12 w500; extent width * 9 / 16 + 72).
The room card follows U.4a (designed in parallel); here it is v3's card as is.

    python3 docs/ui/compare/U.4e/src/gen.py
    python3 tools/ui/mock/render.py docs/ui/compare/U.4e/src/ --annotate
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))

CSS = '''
.col{display:flex;flex-direction:column}
.fill{flex:1;min-height:0;position:relative;overflow:hidden}
.row{display:flex;align-items:center}
.ab{height:56px;flex:none;display:flex;align-items:center;background:var(--surface);position:relative}
.ab .lead{width:56px;height:56px;display:grid;place-items:center;flex:none}
.ab .ttl{position:absolute;left:72px;right:72px;top:0;height:56px;display:flex;flex-direction:column;align-items:center;justify-content:center;pointer-events:none}
.ab .ttl .a{font-size:20px;line-height:26px;font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:100%}
.ab .ttl .b{font-size:12px;line-height:16px;color:var(--onv);white-space:nowrap}
.ab .trail{margin-left:auto;height:48px;display:flex;align-items:center;padding:0 12px 0 4px}
.grid{position:absolute;left:0;right:0;top:0;padding:6px;display:grid;gap:6px;align-content:start}
/* v3 RoomCard, standard preset, dense (room_card.dart:1054-1229) */
.rc{background:#fff;border-radius:20px;overflow:hidden;display:flex;flex-direction:column}
.rc .cv{aspect-ratio:16/9;border-radius:20px;background:#F5F5F5 center/cover;position:relative}
.rc .aud{position:absolute;right:8px;bottom:8px;height:22px;padding:0 6px;border-radius:10px;background:rgba(0,0,0,.48);border:.6px solid rgba(54,97,142,.12);color:#fff;display:flex;align-items:center;gap:4px;font:700 11px 'Geist','Noto Sans SC';letter-spacing:.1px}
.rc .cap{height:72px;display:flex;align-items:center;gap:8px;padding:4px 10px}
.rc .av{width:34px;height:34px;border-radius:17px;background:center/cover;flex:none}
.rc .tx{flex:1;min-width:0}
.rc .t{font-size:13px;line-height:18px;font-weight:600;color:rgba(0,0,0,.87);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.rc .nk{font-size:12px;line-height:17px;font-weight:500;color:#616161;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.rc.sk .cv{background:var(--sch)}.rc.sk .av{background:var(--sch)}
.rc .bar{height:10px;border-radius:5px;background:var(--sch)}
/* v3 follow pill (area_rooms_page.dart:204-283) */
.afab{position:absolute;right:16px;min-height:48px;padding:8px 12px;border-radius:16px;z-index:8;background:color-mix(in srgb,var(--surface) 95%,transparent);
 border:1px solid color-mix(in srgb,var(--primary) 15%,transparent);box-shadow:0 4px 12px rgba(0,0,0,.06);display:flex;align-items:center;gap:8px}
.afab.on{border-radius:24px;border-color:color-mix(in srgb,var(--ov) 50%,transparent)}
.afab .pic{width:32px;height:32px;border-radius:16px;background:var(--pc) center/cover;flex:none}
.afab .k{font-size:12px;line-height:13px;color:rgba(0,0,0,.6)}
.afab .nm{font-size:12px;line-height:15px;font-weight:700;color:var(--primary);max-width:80px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
/* mini FABs: back to top / bottom (base_page_view_extension.dart:64-99) */
.mfab{position:absolute;right:16px;width:40px;height:40px;border-radius:12px;background:#fff;color:var(--opc);display:grid;place-items:center;z-index:7;
 box-shadow:0 2px 4px rgba(0,0,0,.18),0 3px 8px rgba(0,0,0,.12)}
.sbar{height:24px;flex:none;display:flex;align-items:center;justify-content:space-between;padding:0 16px;font:600 12px 'Geist','Noto Sans SC'}
.sbar .mi{font-size:14px}
.pager{height:68px;flex:none;display:flex;align-items:center;justify-content:center;background:var(--surface);border-top:1px solid color-mix(in srgb,var(--on) 6%,transparent);font-size:13px;position:relative;z-index:3}
.pager .ob{height:36px;padding:0 12px;border-radius:6px;border:1px solid var(--outline);color:var(--primary);display:flex;align-items:center;gap:6px;font-weight:500}
.pager .tbn{height:40px;padding:0 12px;display:flex;align-items:center;gap:6px;color:var(--primary);font-weight:500}
.pager .tbn.dis{color:color-mix(in srgb,var(--on) 38%,transparent)}
.pager .pg{min-width:48px;height:48px;margin:0 3px;border-radius:6px;border:1px solid color-mix(in srgb,var(--on) 10%,transparent);display:grid;place-items:center}
.pager .pg.on{background:var(--primary);border-color:var(--primary);color:var(--onPrimary);font-weight:700}
.pager .mut{color:color-mix(in srgb,var(--on) 60%,transparent)}
.pager .sel{height:30px;padding:0 6px 0 10px;border-radius:6px;background:color-mix(in srgb,var(--on) 5%,transparent);display:flex;align-items:center;margin:0 24px 0 6px}
.pager .inp{width:50px;height:32px;border-radius:6px;border:1px solid var(--outline);margin:0 6px}
.sv{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;padding-bottom:40px}
.sv .c{width:86px;height:86px;border-radius:43px;display:grid;place-items:center;background:color-mix(in srgb,var(--schh) 25%,transparent);border:1px solid color-mix(in srgb,var(--primary) 6%,transparent);color:color-mix(in srgb,var(--primary) 60%,transparent)}
.sv .h{margin-top:20px;font-size:15px;font-weight:600}
.sv .p{margin-top:6px;max-width:320px;padding:0 28px;text-align:center;font-size:13px;line-height:1.5;color:color-mix(in srgb,var(--on) 60%,transparent)}
.sv .a{margin-top:16px;height:40px;padding:0 12px;display:flex;align-items:center;gap:8px;color:var(--primary);font-size:14px;font-weight:500}
.spin{width:24px;height:24px;border-radius:12px;border:3.5px solid var(--primary);border-right-color:color-mix(in srgb,var(--primary) 15%,transparent)}
.multi{display:flex;gap:28px;padding:56px 28px 28px;background:#E9EBF0}
.multi .cell{position:relative}
.multi .lab{position:absolute;left:0;right:0;top:-40px;text-align:center;font:600 20px 'Noto Sans SC';color:#191C20}
/* v3 AlertDialog (theme.dart:177-183) */
.adlg{position:absolute;z-index:21;left:50%;top:50%;transform:translate(-50%,-50%);width:280px;background:var(--sch);border-radius:24px;padding:24px 24px 16px}
.adlg .h{font-size:20px;font-weight:600;line-height:28px}
.adlg .p{font-size:13px;line-height:1.5;margin:16px 0 20px}
.adlg .acts{display:flex;justify-content:flex-end;gap:8px}
.adlg .tb{height:48px;padding:0 12px;display:flex;align-items:center;color:var(--primary);font-size:13px;font-weight:500}
.adlg .eb{height:48px;padding:0 24px;border-radius:12px;display:flex;align-items:center;background:var(--scl);color:var(--primary);font-size:13px;font-weight:600}
'''

mr = lambda n, s=24: f'<span class="mr" style="font-size:{s}px">{n}</span>'
mi = lambda n, s=24: f'<span class="mi" style="font-size:{s}px">{n}</span>'
rx = lambda c, s=24: f'<span class="rx" style="font-size:{s}px">&#x{c};</span>'


def attrs(n=None, tag=None, at=None):
    return (f' data-n="{n}"' if n else '') + (f' data-tag="{tag}"' if n and tag else '') + (f' data-at="{at}"' if n and at else '')


STATUS = ('<div class="status"><span>21:36</span><span class="r"><span class="mi">signal_cellular_alt</span>'
          '<span class="mi">wifi</span><span class="mi">battery_full</span></span></div>')
SBAR = '<div class="sbar"><span>21:36</span><span class="r"><span class="mi">wifi</span> <span class="mi">battery_full</span></span></div>'
PICS = ['158', '274', '1', '111', '133', '169', '183', '206', '219', '225', '237', '250', '287', '292', '304', '319', '338', '342', '360', '367']
AVS = ['65', '360', '338', '225', '169', '206', '287', '319', '1', '111', '133', '183', '219', '237', '250', '292', '304', '342', '367', '158']
# bilibili 英雄联盟 (sample data); bilibili shows platform heat (Icons.whatshot_rounded)
ROOMS = [('LPL 春季赛 BLG vs TES 第二局', '哔哩哔哩英雄联盟赛事', '312.5万'), ('峡谷之巅王者局，冲分中', '小明不是小明', '8.6万'),
         ('新版本卡莎上分教学', '下路小卡', '5.2万'), ('深夜排位，来聊天', '夜猫子打野', '2.1万'), ('大乱斗一起玩', '阿狸今天也很甜', '1.8万'),
         ('黄金局教学，一个月上钻', '教练小王', '1.3万'), ('云顶之弈新赛季阵容', '棋手阿杰', '9864'), ('辅助位视野教学', '宝石骑士', '7210'),
         ('单排上分，不开黑', '孤独的中单', '6533'), ('新英雄首玩', '版本答案', '5120'), ('灵活组排，水友赛', '今天也要赢', '4088'),
         ('打野路线讲解', '野区霸主', '3712'), ('白银局欢乐多', '快乐上单', '2950'), ('听歌打排位', '一只咸鱼', '2311'),
         ('复盘昨天的比赛', '赛事解说老周', '1980'), ('五排开黑', '开黑小队', '1502'), ('练习新英雄', '萌新报道', '1220'), ('通宵冲分', '熬夜冠军', '980')]
AREA_PIC = '.cache/img/1.jpg'


def room_card(i, n=None, tag=None, at=None):
    t, nk, h = ROOMS[i % len(ROOMS)]
    return (f'<div class="rc"{attrs(n, tag, at)}><div class="cv" style="background-image:url(.cache/img/{PICS[i % len(PICS)]}.jpg)">'
            f'<div class="aud">{mr("whatshot", 14)}{h}</div></div>'
            f'<div class="cap"><span class="av" style="background-image:url(.cache/img/{AVS[i % len(AVS)]}.jpg)"></span>'
            f'<div class="tx"><div class="t">{t}</div><div class="nk">{nk}</div></div></div></div>')


def skel_card():
    return ('<div class="rc sk"><div class="cv"></div><div class="cap"><span class="av"></span><div class="tx">'
            '<div class="bar" style="width:80%"></div><div class="bar" style="width:45%;margin-top:8px"></div></div></div></div>')


def grid(cols, cards, top=0):
    return f'<div class="grid" style="grid-template-columns:repeat({cols},minmax(0,1fr));top:{top}px">{"".join(cards)}</div>'


def pager(n=None, tag=None):
    return (f'<div class="pager"{attrs(n, tag)}><div class="ob">{mr("refresh", 16)}刷新</div>'
            f'<div class="tbn dis" style="margin-left:4px">{mr("arrow_back_ios_new", 12)}上一页</div><div style="width:8px"></div>'
            '<div class="pg on">1</div><div class="pg">2</div><div class="pg">3</div><span class="mut" style="padding:0 4px">...</span><div style="width:8px"></div>'
            f'<div class="tbn">下一页{mr("arrow_forward_ios", 12)}</div>'
            f'<span class="mut" style="margin-left:4px">每页: </span><div class="sel">20{mr("arrow_drop_down", 18)}</div>'
            '<span class="mut">跳转至</span><div class="inp"></div><span class="mut">页</span></div>')


def doc(w, h, scale, body, frame='win'):
    cls = 'ph' if frame == 'ph' else 'win'
    style = '' if frame == 'ph' else f' style="--w:{w}px;--h:{h}px"'
    syn = '' if frame == 'ph' else ' style="top:auto;bottom:76px;left:auto;right:12px;transform:none"'
    return (f'<!doctype html><html><head><meta charset="utf-8"><meta name="mock-size" content="{w}x{h}@{scale}">'
            f'<link rel="stylesheet" href="kit/kit.css"><style>{CSS}</style></head>'
            f'<body><div class="{cls} col"{style}>{body}<div class="syn"{syn}>示意图片</div></div></body></html>')


def multi(cells):
    w = len(cells) * 393 + (len(cells) - 1) * 28 + 56
    inner = ''.join(f'<div class="cell"><div class="lab">{lab}</div>{ph}</div>' for lab, ph in cells)
    return (f'<!doctype html><html><head><meta charset="utf-8"><meta name="mock-size" content="{w}x936@1">'
            f'<link rel="stylesheet" href="kit/kit.css"><style>{CSS}</style></head>'
            f'<body style="background:#E9EBF0"><div class="multi">{inner}</div>'
            '<div class="syn" style="position:fixed;left:auto;right:10px;transform:none">示意图片</div></body></html>')


def status_view(icon, title, sub='', action=None, aicon='refresh'):
    a = f'<div class="a">{mr(aicon, 18)}{action}</div>' if action else ''
    return f'<div class="sv"><div class="c">{icon}</div><div class="h">{title}</div><div class="p">{sub}</div>{a}</div>'


ERR = '当前无网络连接，请检查网络设置'   # network_disconnected_msg


# ---------------------------------------------------------------- v3
def v3_appbar():
    return ('<div class="ab"><div class="lead">' + mi('arrow_back') + '</div>'
            '<div class="ttl"><div class="a">英雄联盟</div></div></div>')


def v3_fab(followed, bottom=40):
    if followed:
        return f'<div class="afab on" style="bottom:{bottom}px"><span class="pic" style="background-image:url({AREA_PIC})"></span></div>'
    return (f'<div class="afab" style="bottom:{bottom}px"><span class="pic" style="background-image:url({AREA_PIC})"></span>'
            '<div><div class="k">关注</div><div class="nm">英雄联盟</div></div></div>')


def mini_fabs(bottom, n=None):
    a = attrs(n, 'keep', 'tl') if n else ''
    b = attrs(n + 1, 'keep', 'tl') if n else ''
    return (f'<div class="mfab"{a} style="bottom:{bottom + 48}px">{mr("arrow_upward")}</div>'
            f'<div class="mfab"{b} style="bottom:{bottom}px">{mr("arrow_downward")}</div>')


def v3_phone(scrolled=False):
    first = 8 if scrolled else 0
    cards = [room_card(first + i) for i in range(10)]
    extra = mini_fabs(85) if scrolled else ''
    body = (STATUS + v3_appbar() + f'<div class="fill">{grid(2, cards, -80 if scrolled else 0)}{extra}</div>'
            + v3_fab(scrolled) + '<div class="gesture"></div>')
    return doc(393, 852, 3, body, 'ph')


def v3_unfollow():
    cards = [room_card(i) for i in range(10)]
    body = (STATUS + v3_appbar() + f'<div class="fill">{grid(2, cards)}</div>' + v3_fab(True)
            + '<div class="scrim"></div><div class="adlg"><div class="h">取消关注</div><div class="p">确定要取消关注英雄联盟吗？</div>'
            '<div class="acts"><div class="tb">取消</div><div class="eb">确认</div></div></div><div class="gesture"></div>')
    return doc(393, 852, 3, body, 'ph')


def v3_land():
    body = (SBAR + v3_appbar() + f'<div class="fill">{grid(3, [room_card(i) for i in range(9)])}</div>' + v3_fab(False, 28))
    return doc(852, 393, 2, body)


def v3_wide():
    body = (v3_appbar() + f'<div class="fill">{grid(4, [room_card(i) for i in range(12)])}</div>' + pager() + v3_fab(False, 40))
    return doc(1280, 800, 1.5, body)


def phone_shell(appbar, content, fab=''):
    return f'<div class="ph col">{STATUS}{appbar}<div class="fill">{content}</div>{fab}<div class="gesture"></div></div>'


def v3_states():
    ab = v3_appbar()
    return multi([
        ('加载中', phone_shell(ab, '<div class="sv"><div class="spin"></div></div>', v3_fab(False))),
        ('没有直播', phone_shell(ab, status_view(mr('live_tv', 42), '无数据'), v3_fab(False))),
        ('出错', phone_shell(ab, status_view(mr('wifi_off', 42), '网络请求失败', ERR, '重试'), v3_fab(False))),
        ('需要登录（哔哩哔哩风控）', phone_shell(ab, status_view(mi('account_circle', 42), '需要登录账号', '该平台数据已被风控隐藏，请登录账号后重试', '前往登录'), v3_fab(False))),
    ])


# ---------------------------------------------------------------- new
def pill(followed, n=None):
    inner = f"{rx('eb7b', 16)}已关注" if followed else f"{rx('ea13', 16)}关注"
    return f'<div class="trail"{attrs(n, None, "tc")}><div class="fol {"on" if followed else "off"}">{inner}</div></div>'


def v4_appbar(followed=False, n=True, title='英雄联盟', sub='哔哩哔哩 · 网游'):
    return ('<div class="ab"><div class="lead"' + attrs(1 if n else None, 'keep') + '>' + mi('arrow_back') + '</div>'
            f'<div class="ttl"><div class="a">{title}</div><div class="b">{sub}</div></div>' + pill(followed, 2 if n else None) + '</div>')


def v4_phone(scrolled=False):
    first = 8 if scrolled else 0
    cards = [room_card(first + i, 3 if (i == 0 and not scrolled) else None, 'keep', 'tl') for i in range(10)]
    extra = mini_fabs(24, 4 if scrolled else None) if scrolled else ''
    body = (STATUS + v4_appbar(scrolled, n=True) + f'<div class="fill">{grid(2, cards, -80 if scrolled else 0)}{extra}</div>'
            + '<div class="gesture"></div>')
    return doc(393, 852, 3, body, 'ph')


def v4_land():
    body = (SBAR + v4_appbar(n=False) + f'<div class="fill">{grid(4, [room_card(i) for i in range(12)])}</div>')
    return doc(852, 393, 2, body)


def v4_wide():
    cards = [room_card(i, 3 if i == 0 else None, 'keep', 'tl') for i in range(24)]
    body = (v4_appbar() + f'<div class="fill">{grid(6, cards)}</div>' + pager(6, 'keep'))
    return doc(1280, 800, 1.5, body)


def v4_states():
    ab = v4_appbar(n=False)
    return multi([
        ('加载中', phone_shell(ab, grid(2, [skel_card() for _ in range(10)]))),
        ('没有直播', phone_shell(ab, status_view(mr('live_tv', 42), '未发现直播', '这个分区现在没有人在播，可以稍后刷新', '刷新'))),
        ('出错', phone_shell(ab, status_view(mr('wifi_off', 42), '网络请求失败', ERR, '重试'))),
        ('需要登录（哔哩哔哩风控）', phone_shell(ab, status_view(mi('account_circle', 42), '需要登录账号', '该平台数据已被风控隐藏，请登录账号后重试', '前往登录', 'login'))),
    ])


OUT = {
    'v3-phone': v3_phone(), 'v3-phone-scrolled': v3_phone(True), 'v3-unfollow': v3_unfollow(), 'v3-land': v3_land(), 'v3-wide': v3_wide(),
    'v3-states': v3_states(),
    'v4-phone': v4_phone(), 'v4-phone-scrolled': v4_phone(True), 'v4-land': v4_land(), 'v4-wide': v4_wide(), 'v4-states': v4_states(),
}
for name, html in OUT.items():
    open(os.path.join(HERE, name + '.html'), 'w', encoding='utf-8').write(html)
print(len(OUT), 'pages')
