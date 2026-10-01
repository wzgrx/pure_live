"""U.5c watch history mockups: v3 restored and the new design.

v3 (tag v3.2.11): lib/modules/history/history_page.dart (AppBar :168-192,
grid :193-233, dialogs :74-163 and :248-407), common/widgets/room_card.dart
(dense cover card with the delete button :1150-1169),
common/services/settings/history_controller.dart (limit, lastWatchedAt).
The room card is v3's as is; its new look is U.4a's.
    python3 docs/ui/compare/U.5c/src/gen.py && python3 tools/ui/mock/render.py docs/ui/compare/U.5c/src/ --annotate"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
IMG = '.cache/img/'

CSS = '''
.ph .status{background:var(--surface)}
.sb24{height:24px;display:flex;align-items:center;justify-content:space-between;padding:0 16px;font:600 12px 'Geist','Noto Sans SC';background:var(--surface)}
.sb24 .mi{font-size:13px}
.bar{height:56px;display:flex;align-items:center;background:var(--surface);position:relative;flex:none;z-index:3}
.bar .b{width:56px;height:56px;display:grid;place-items:center;flex:none}
.bar .b .mi,.bar .b .mr{font-size:24px}
.bar .ct{position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);font-size:20px;font-weight:600;white-space:nowrap}
.bar .tt{flex:1;min-width:0;padding-left:4px}
.bar .tt .n{font-size:17px;font-weight:600;line-height:22px}
.bar .tt .s{font-size:12px;color:var(--onv);line-height:16px;white-space:nowrap}
.bar .ib2{width:48px;height:48px;display:grid;place-items:center;flex:none;color:var(--on)}
.bar .ib2 .mi,.bar .ib2 .mr{font-size:24px}
.col2{display:flex;flex-direction:column;height:100%}
.body{flex:1;overflow:hidden;position:relative}
/* v3's dense cover card with the delete button (RoomCard showDelete) */
.grid{display:grid}
.card{background:#fff;border-radius:20px;overflow:hidden;position:relative}
.cv{position:relative;aspect-ratio:16/9;border-radius:20px;background:#F5F5F5 center/cover}
.mb{position:absolute;right:8px;bottom:8px;display:flex;align-items:center;gap:4px;padding:3px 6px;border-radius:10px;background:rgba(0,0,0,.48);color:#fff;font:700 11px 'Geist','Noto Sans SC'}
.mb .mr{font-size:14px}
.del{position:absolute;right:10px;top:10px;width:28px;height:28px;border-radius:14px;background:rgba(0,0,0,.6);display:grid;place-items:center;color:#fff}
.del .rx{font-size:16px}
.lt{display:flex;align-items:center;gap:8px;padding:8px 10px;min-height:58px}
.lt .av{width:34px;height:34px;border-radius:17px}
.lt .tx{flex:1;min-width:0}
.lt .t{font-size:13px;line-height:18px;font-weight:600;color:rgba(0,0,0,.87);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.lt .s{font-size:12px;line-height:17px;font-weight:500;color:#616161;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.sec{padding:12px 12px 6px;font-size:13px;font-weight:600;color:var(--primary)}
.prog{height:2px;background:rgba(54,97,142,.18);position:relative}.prog i{position:absolute;left:0;top:0;bottom:0;width:40%;background:var(--primary)}
.filt{padding:0 12px 10px;background:var(--surface)}
.filt .f{height:44px;border-radius:22px;border:2px solid var(--primary);background:var(--scl);display:flex;align-items:center;gap:8px;padding:0 14px 0 12px;font-size:14px}
.filt .f .mr{font-size:20px;color:var(--onv)}.filt .f .x{flex:1}.filt .f small{font-size:12px;color:var(--onv)}
/* status view */
.sv{display:flex;flex-direction:column;align-items:center;justify-content:center;text-align:center;height:100%}
.svc{width:86px;height:86px;border-radius:43px;background:rgba(225,226,232,.15);border:1px solid rgba(54,97,142,.05);display:grid;place-items:center}
.svc .mr{font-size:42px;color:rgba(54,97,142,.6)}
.sv h4{margin-top:20px;font-size:15px;font-weight:600}
.sv p{padding:6px 28px 0;max-width:376px;font-size:13px;line-height:1.5;color:rgba(0,0,0,.6);min-height:26px}
/* dialogs */
.dim{position:absolute;inset:0;background:rgba(0,0,0,.4);z-index:20}
.dlg2{position:absolute;z-index:21;left:16px;right:16px;background:var(--sch);border-radius:24px;padding:24px 24px 16px}
.dlg2 h3{font-size:15px;font-weight:700;line-height:1.3}
.dlg2 .c{margin-top:16px;font-size:14px;line-height:1.5}
.dlg2 .acts{display:flex;justify-content:flex-end;gap:8px;margin-top:20px;align-items:center}
.dlg2 .acts span{height:48px;display:flex;align-items:center;padding:0 12px;font-size:14px;color:rgba(0,0,0,.6)}
.dlg2 .acts span.p{color:var(--primary)}
.dlg2 .acts span.err{background:var(--error);color:#fff;border-radius:24px;padding:0 24px;font-size:13px;font-weight:500}
.lab{font-size:12px;color:rgba(0,0,0,.6)}
.chips{display:flex;flex-wrap:wrap;gap:8px;margin-top:12px}
.ch{height:32px;border-radius:8px;border:1px solid var(--ov);display:flex;align-items:center;gap:4px;padding:0 12px;font-size:12px;font-weight:500;color:var(--onv)}
.ch.on{background:var(--sc);border-color:transparent;color:var(--osc);padding-left:8px}.ch.on .mr{font-size:16px}
.tf{margin-top:12px;height:46px;border:1px solid var(--outline);border-radius:4px;display:flex;align-items:center;padding:0 12px;font-size:14px;color:rgba(67,71,78,.6)}
.tf .x{flex:1}.tf small{font-size:12px;color:rgba(0,0,0,.6)}
.eb{margin-top:8px;height:48px;border-radius:12px;background:var(--scl);box-shadow:0 1px 2px rgba(0,0,0,.18);display:grid;place-items:center;font-size:13px;font-weight:500;color:var(--primary)}
.warn{display:flex;gap:6px;align-items:flex-start;margin-top:8px;font-size:12px;color:var(--error)}.warn .mr{font-size:16px}
.multi{display:flex;gap:24px;background:#E9EBF0}
.multi .col{display:flex;flex-direction:column;gap:8px}
.multi .cap{height:34px;display:flex;align-items:center;justify-content:center;font-size:15px;font-weight:600;color:#191C20}
.multi .ph{box-shadow:0 0 0 1px #C3C7CF}
'''

mr = lambda n, s=None: f'<span class="mr"{f" style=\"font-size:{s}px\"" if s else ""}>{n}</span>'
mi = lambda n, s=None: f'<span class="mi"{f" style=\"font-size:{s}px\"" if s else ""}>{n}</span>'
rx = lambda c, s=None: f'<span class="rx"{f" style=\"font-size:{s}px\"" if s else ""}>&#x{c};</span>'


def dn(n, tag=None, at=None):
    if n is None:
        return ''
    return f' data-n="{n}"' + (f' data-tag="{tag}"' if tag else '') + (f' data-at="{at}"' if at else '')


STATUS = ('<div class="status"><span>21:36</span><span class="r"><span class="mi">signal_cellular_alt</span>'
          '<span class="mi">wifi</span><span class="mi">battery_full</span></span></div>')
SB24 = ('<div class="sb24"><span>21:36</span><span style="display:flex;gap:4px"><span class="mi">wifi</span>'
        '<span class="mi">battery_full</span></span></div>')
SYN = '<div class="syn" style="top:auto;bottom:10px">示意图片</div>'


def page(size, body, cls='ph', style=''):
    return (f'<!doctype html><html><head><meta charset="utf-8"><meta name="mock-size" content="{size}">'
            f'<link rel="stylesheet" href="kit/kit.css"><style>{CSS}</style></head><body>'
            f'<div class="{cls}" style="{style}">{body}</div></body></html>')


# (cover, avatar, title, streamer, metric icon, value or None when not live, section)
ROOMS = [
    ('1', '65', '晚风电台｜深夜点歌', '晚风', 'people_alt', '1.2万', 0),
    ('319', '319', '周末开黑，冲分到天亮', '小七游戏', 'whatshot', '9.3万', 0),
    ('237', '237', '海边的晚风 · 日落直播', '海边晚风', None, None, 0),
    ('183', '183', 'KTV 点歌，来就唱', '晚风KTV', 'people_alt', '5.6万', 1),
    ('292', '292', '钢琴陪伴｜轻音乐', '晚风钢琴', None, None, 1),
    ('250', '250', '读书会：一起读《瓦尔登湖》', '书房', 'whatshot', '1.1万', 1),
    ('304', '304', '小厨房做宵夜', '晚风厨房', None, None, 1),
    ('342', '342', '露营夜 · 星空慢直播', '露营的晚风', 'people_alt', '1876', 2),
    ('169', '169', '户外徒步第三天', '山野', None, None, 2),
    ('133', '133', '原创歌曲首发', '晚风同学', 'people_alt', '3.4万', 2),
    ('360', '360', '茶话会，聊聊天', '晚风茶馆', None, None, 2),
    ('206', '206', '听故事｜睡前频道', '讲故事的人', None, None, 3),
    ('219', '219', '周末合唱', '晚风合唱团', None, None, 3),
    ('287', '287', '城市骑行', '骑行晚风', None, None, 3),
    ('367', '367', '猫咖日常', '晚风猫咖', 'people_alt', '5280', 3),
    ('111', '111', '吉他弹唱', '晚风小屋', None, None, 3),
    ('338', '338', '水彩画室', '晚风画画', None, None, 3),
    ('225', '225', '录播间', '晚风录播', None, None, 3),
]
SECTIONS = ['今天', '昨天', '近 7 天', '更早']


def card(r, n=None, del_n=None):
    cover, av, title, nick, icon, val, _ = r
    badge = f'<div class="mb">{mr(icon)}{val}</div>' if val else ''
    return (f'<div class="card"{dn(n, "keep", "tl")}><div class="cv" style="background-image:url({IMG}{cover}.jpg)">{badge}'
            f'<div class="del"{dn(del_n, "keep", "tr")}>{rx("ec2a")}</div></div>'
            f'<div class="lt"><span class="av" style="background-image:url({IMG}{av}.jpg)"></span>'
            f'<div class="tx"><div class="t">{title}</div><div class="s">{nick}</div></div></div></div>')


def grid(cols, rooms, gap=6, n=False):
    cells = ''.join(card(r, 8 if n and i == 0 else None, 9 if n and i == 0 else None) for i, r in enumerate(rooms))
    return f'<div class="grid" style="grid-template-columns:repeat({cols},minmax(0,1fr));gap:{gap}px;padding:6px">{cells}</div>'


def sectioned(cols, rooms, n=False):
    out = ''
    first = True
    for s, name in enumerate(SECTIONS):
        group = [r for r in rooms if r[6] == s]
        if not group:
            continue
        out += f'<div class="sec"{dn(7 if n and first else None, "add", "tr")}>{name} · {len(group)}</div>'
        cells = ''.join(card(r, 8 if n and first and i == 0 else None, 9 if n and first and i == 0 else None) for i, r in enumerate(group))
        out += f'<div class="grid" style="grid-template-columns:repeat({cols},minmax(0,1fr));gap:6px;padding:0 6px">{cells}</div>'
        first = False
    return out


# ---------- v3 ----------
def v3_bar(count='18/50', clear=True):
    return (f'<div class="bar"><div class="b">{mi("arrow_back")}</div><div class="ct">历史记录 ({count})</div><div style="flex:1"></div>'
            f'<div class="ib2">{mr("settings")}</div>' + (f'<div class="ib2" style="margin-right:4px">{mi("delete_forever")}</div>' if clear else '') + '</div>')


def v3_empty():
    return f'<div class="sv"><div class="svc">{mr("history")}</div><h4>无观看历史记录</h4><p></p></div>'


def limit_dialog(v4=False, top=150):
    chips = ''.join(f'<span class="ch{" on" if v == (20 if v4 else 50) else ""}">{mr("check") if v == (20 if v4 else 50) else ""}{v}</span>' for v in (20, 50, 100, 200, 500))
    chips += '<span class="ch">不限</span>'
    warn = (f'<div class="warn">{mr("warning_amber")}<span>保存后将删除最早的 28 条记录</span></div>' if v4 else '')
    cur = 20 if v4 else 50
    return (f'<div class="dim"></div><div class="dlg2" style="top:{top}px"><h3>观看记录保留数量</h3><div class="c" style="font-size:13px">'
            f'<div class="lab">预设数量</div><div class="chips">{chips}</div>'
            f'<div style="margin-top:24px;font-size:13px;font-weight:500">自定义数量</div>'
            f'<div class="tf"><span class="x">50</span><small>条</small></div><div class="eb">应用</div>'
            f'<div class="lab" style="margin-top:16px">当前值: {cur}</div>{warn}'
            f'<div class="lab" style="margin-top:6px">可选择固定数量或“不限”。固定数量只保留最近记录；不限会持续保留，仍可随时手动清空。</div></div>'
            f'<div class="acts"><span>取消</span><span class="p">确认</span></div></div>')


def confirm_dialog(title, msg, action, top=300):
    return (f'<div class="dim"></div><div class="dlg2" style="top:{top}px"><h3>{title}</h3><div class="c">{msg}</div>'
            f'<div class="acts"><span>取消</span><span class="err">{action}</span></div></div>')


def phone_v3(body_html, count='18/50', clear=True, extra=''):
    return (STATUS + '<div class="col2" style="height:816px">' + v3_bar(count, clear) + f'<div class="body">{body_html}</div></div>' + extra)


# ---------- new ----------
def v4_bar(n=True, sub='18 / 50 条', filtering=False):
    return (f'<div class="bar"><div class="b"{dn(1 if n else None, "keep")}>{mi("arrow_back")}</div>'
            f'<div class="tt"{dn(2 if n else None, "chg", "tl")}><div class="n">观看记录</div><div class="s">{sub}</div></div>'
            f'<div class="ib2"{dn(3 if n else None, "add")}>{mr("search_off" if filtering else "search")}</div>'
            f'<div class="ib2"{dn(4 if n else None, "add")}>{mr("refresh")}</div>'
            f'<div class="ib2"{dn(5 if n else None, "keep")}>{mr("settings")}</div>'
            f'<div class="ib2" style="margin-right:4px"{dn(6 if n else None, "keep")}>{mi("delete_forever")}</div></div>')


def phone_v4(body_html, n=False, sub='18 / 50 条', extra='', top_extra='', filtering=False):
    return (STATUS + '<div class="col2" style="height:816px">' + v4_bar(n, sub, filtering) + top_extra + f'<div class="body">{body_html}</div></div>' + extra)


def composite(phones):
    w = 393 * len(phones) + 24 * (len(phones) - 1)
    body = ''.join(f'<div class="col"><div class="cap">{c}</div><div class="ph">{p}</div></div>' for p, c in phones)
    return page(f'{w}x894@1.5', body, 'multi', f'width:{w}px;height:894px')


OUT = {}
# v3
OUT['v3-history'] = page('393x852@3', phone_v3(grid(2, ROOMS)) + SYN)
OUT['v3-history-empty'] = page('393x852@3', phone_v3(v3_empty(), '0/50', clear=False))
OUT['v3-history-dialogs'] = composite([
    (phone_v3(grid(2, ROOMS), extra=limit_dialog(False)), '观看记录保留数量（齿轮）'),
    (phone_v3(grid(2, ROOMS), extra=confirm_dialog('清空历史', '确定清空这 18 条历史记录吗？此操作不可撤销。', '清除')), '清空历史'),
    (phone_v3(grid(2, ROOMS), extra=confirm_dialog('删除', '要从观看记录中删除“晚风电台｜深夜点歌”吗？仅删除这一条记录。', '删除')), '删除一条（卡片右上角）'),
])
OUT['v3-history-land'] = page('852x393@2', SB24 + '<div class="col2" style="height:369px">' + v3_bar() + f'<div class="body">{grid(3, ROOMS)}</div></div>' + SYN,
                              'win', '--w:852px;--h:393px')
OUT['v3-history-wide'] = page('1280x800@1.5', '<div class="col2" style="height:800px">' + v3_bar() + f'<div class="body">{grid(4, ROOMS)}</div></div>' + SYN,
                              'win', '--w:1280px;--h:800px')
# new
OUT['v4-history'] = page('393x852@3', phone_v4(sectioned(2, ROOMS, True), n=True) + SYN)
OUT['v4-history-refresh'] = page('393x852@3', phone_v4(sectioned(2, ROOMS), top_extra='<div class="prog"><i></i></div>') + SYN)
FILT = ('<div class="filt"><div class="f">' + mr('search') + '<span class="x">晚风</span><small>4 条</small></div></div>')
OUT['v4-history-filter'] = page('393x852@3', phone_v4(sectioned(2, [r for r in ROOMS if '晚风' in r[3]][:4]), top_extra=FILT, filtering=True) + SYN)
OUT['v4-history-empty'] = page('393x852@3', STATUS + '<div class="col2" style="height:816px">' + v4_bar(False, '0 / 50 条').replace(
    f'<div class="ib2" style="margin-right:4px">{mi("delete_forever")}</div>', '') +
    f'<div class="body"><div class="sv"><div class="svc">{mr("history")}</div><h4>无观看历史记录</h4><p>看过的直播间会按观看时间出现在这里</p></div></div></div>')
OUT['v4-history-dialogs'] = composite([
    (phone_v4(sectioned(2, ROOMS), extra=limit_dialog(True, 130)), '保留数量：改小时提醒删几条'),
    (phone_v4(sectioned(2, ROOMS), extra=confirm_dialog('清空历史', '确定清空这 18 条历史记录吗？此操作不可撤销。', '清除')), '清空历史'),
    (phone_v4(sectioned(2, [r for r in ROOMS if '晚风' in r[3]][:4]), top_extra=FILT, filtering=True,
              extra=confirm_dialog('清空历史', '确定删除筛选出的 4 条观看记录吗？其他记录不受影响，此操作不可撤销。', '清除')), '筛选时清空：只删筛出来的'),
])
OUT['v4-history-land'] = page('852x393@2', SB24 + '<div class="col2" style="height:369px">' + v4_bar(False) + f'<div class="body">{sectioned(4, ROOMS)}</div></div>' + SYN,
                              'win', '--w:852px;--h:393px')
OUT['v4-history-wide'] = page('1280x800@1.5', '<div class="col2" style="height:800px">' + v4_bar(True) + f'<div class="body">{sectioned(6, ROOMS, True)}</div></div>' + SYN +
                              '<div class="tip" style="right:120px;top:52px">刷新开播状态</div>', 'win', '--w:1280px;--h:800px')

for name, html in OUT.items():
    open(os.path.join(HERE, name + '.html'), 'w', encoding='utf-8').write(html)
print(len(OUT), 'pages')
