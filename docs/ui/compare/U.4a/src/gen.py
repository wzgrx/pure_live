"""U.4a room card mockups: the card in every state, the long-press dialog,
follow / unfollow, and room tags. v3 restored from
~/ref/v3ref/lib/common/widgets/room_card.dart (v3.2.11):
  card :1053-1229, long press :177-316, follow ask :125-175,
  tag dialog :318-856, FollowButton and unfollow :1232-1310.
    python3 docs/ui/compare/U.4a/src/gen.py && python3 tools/ui/mock/render.py docs/ui/compare/U.4a/src/ --annotate"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from cards import *  # noqa: E402,F401,F403

CSS2 = '''
.sheetpg{padding:28px 12px 16px;background:var(--surface)}
.sh{font-size:13px;font-weight:600;color:var(--primary);padding:14px 2px 8px}
.lbl{font-size:12px;color:var(--onv);margin:0 2px 4px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.item{position:relative;min-width:0}
.dwrap{position:absolute;inset:0;z-index:21;display:flex;align-items:center;justify-content:center}
/* v3 dialogs */
.d3{width:100%;background:var(--surface);border-radius:24px;box-shadow:0 6px 18px rgba(0,0,0,.18);overflow:hidden}
.d3h{display:flex;align-items:center;padding:20px 16px 0 24px}
.lg{width:36px;height:36px;border-radius:18px;background:rgba(225,226,232,.2);display:grid;place-items:center;flex:none}
.lg img{width:28px;height:28px;border-radius:7px}
.nm{flex:1;min-width:0;margin-left:12px;font-size:15px;font-weight:700;letter-spacing:.3px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.i48{width:48px;height:48px;display:grid;place-items:center;flex:none}
.tbox{padding:14px;border-radius:16px;background:var(--scl);border:.8px solid rgba(115,119,127,.04);font-size:14px;font-weight:500;line-height:1.45}
.rid{padding:14px 0 0 4px;font-size:12px;font-weight:700;letter-spacing:.5px;color:rgba(67,71,78,.5)}
.d3a{display:flex;justify-content:flex-end;align-items:center;gap:8px;padding:0 16px 16px}
.tonal{height:48px;padding:0 20px;border-radius:12px;background:var(--sc);color:var(--osc);font-size:14px;font-weight:600;display:flex;align-items:center}
.tbtn{height:40px;padding:0 12px;border-radius:8px;display:flex;align-items:center;font-size:13px;font-weight:600;color:var(--onv)}
.dlgA{width:100%;background:var(--surface);border-radius:16px;box-shadow:0 6px 18px rgba(0,0,0,.18);padding:24px 24px 20px}
.dlgA .h{font-size:15px;font-weight:700}.dlgA .c{margin-top:16px;font-size:14px;color:var(--onv)}
.dlgA .a{display:flex;justify-content:flex-end;gap:8px;margin-top:24px;align-items:center}
.fbtn{height:40px;padding:0 16px;border-radius:8px;background:var(--primary);color:var(--onPrimary);font-size:14px;font-weight:700;display:flex;align-items:center}
.dlgT{width:100%;background:var(--sch);border-radius:24px;padding:24px 24px 18px}
.dlgT .h{font-size:20px;font-weight:600}.dlgT .c{margin-top:16px;font-size:13px;color:var(--onv)}
.dlgT .a{display:flex;justify-content:flex-end;gap:8px;margin-top:22px}.dlgT .a span{height:40px;padding:0 12px;display:flex;align-items:center;color:var(--primary);font-size:13px;font-weight:500}
.tg3{width:100%;background:var(--surface);border-radius:26px;box-shadow:0 8px 20px rgba(0,0,0,.2);display:flex;flex-direction:column}
.tg3 .th{display:flex;align-items:center;padding:24px 16px 0}
.tg3 .th .x{flex:1;padding-left:12px;font-size:15px;font-weight:800;letter-spacing:.4px}
.tg3 .tc{padding:20px 28px 12px;position:relative;overflow:hidden}
.tg3 .ta{display:flex;gap:6px;padding:0 20px 20px}
.tg3 .ta div{flex:1;height:48px;border-radius:12px;display:grid;place-items:center;font-size:14px;font-weight:600}
.tg3 .ta .ok{background:var(--primary);color:var(--onPrimary);font-weight:700}
.tg3 .ta .ok.dis{background:rgba(25,28,32,.12);color:rgba(25,28,32,.38)}
.tg3 .ta .no{color:var(--onv)}
.tl3{display:grid;gap:10px;padding:4px 10px 4px 2px}
.tt3{height:68px;padding:10px 14px;border-radius:14px;background:rgba(242,243,250,.6);border:.6px solid rgba(115,119,127,.05);display:flex;align-items:center;gap:6px}
.tt3 .x{flex:1;min-width:0}.tt3 .a{font-size:13px;font-weight:600}.tt3 .b{font-size:12px;color:rgba(67,71,78,.5);font-weight:500;margin-top:3px}
.tt3.on{background:rgba(54,97,142,.06);border:1.4px solid var(--primary);box-shadow:0 2px 8px rgba(54,97,142,.04)}.tt3.on .a{color:var(--primary);font-weight:700}
.ck3{width:18px;height:18px;border-radius:9px;border:1.5px solid rgba(67,71,78,.25);flex:none}
.ck3.on{border:0;background:var(--primary);color:var(--onPrimary);display:grid;place-items:center}
.sbar{position:absolute;right:30px;top:24px;width:4px;height:120px;border-radius:4px;background:rgba(0,0,0,.25)}
.form3{padding:14px;border-radius:18px;background:rgba(242,243,250,.7);border:.5px solid rgba(115,119,127,.03)}
.form3 .l{font-size:12px;font-weight:800;color:var(--primary);letter-spacing:.5px}
.in3{height:40px;margin-top:10px;border-radius:10px;background:var(--surface);border:1px solid rgba(115,119,127,.05);display:flex;align-items:center;padding:0 12px;font-size:13px;color:rgba(67,71,78,.5)}
.in3.foc{border:1.2px solid rgba(54,97,142,.5);color:var(--on)}
.in3+.in3{margin-top:8px}
/* new dialogs (theme dialog: surfaceContainerHigh, radius 24) */
.d4{width:100%;background:var(--sch);border-radius:24px;box-shadow:0 6px 18px rgba(0,0,0,.18);overflow:hidden}
.d4h{display:flex;align-items:center;gap:12px;padding:20px 24px 0}
.d4h .x{flex:1;min-width:0}.d4h .n{font-size:16px;font-weight:600;line-height:22px}.d4h .s{font-size:12px;color:var(--onv);line-height:17px;font-feature-settings:'tnum'}
.tbox4{margin:14px 24px 0;padding:12px 14px;border-radius:12px;background:var(--surface);font-size:14px;font-weight:500;line-height:1.45}
.acts4{display:flex;gap:8px;padding:14px 24px 0}
.ob4{flex:1;height:40px;border-radius:20px;background:var(--surface);box-shadow:inset 0 0 0 1px var(--ov);color:var(--primary);font-size:14px;font-weight:500;display:flex;align-items:center;justify-content:center;gap:6px}
.foot4{display:flex;justify-content:flex-end;align-items:center;gap:8px;padding:16px 16px 16px}
.t4{height:40px;padding:0 14px;border-radius:20px;display:flex;align-items:center;font-size:14px;font-weight:500;color:var(--primary)}
.t4.mute{color:var(--onv)}
.f4{height:40px;padding:0 18px 0 14px;border-radius:20px;background:var(--primary);color:var(--onPrimary);font-size:14px;font-weight:600;display:flex;align-items:center;gap:4px}
.f4.err{background:var(--error);color:#fff;padding:0 18px}
.g4{height:40px;padding:0 16px 0 12px;border-radius:20px;background:var(--schh);color:var(--onv);font-size:14px;font-weight:500;display:flex;align-items:center;gap:4px}
.dq{width:100%;background:var(--sch);border-radius:24px;box-shadow:0 6px 18px rgba(0,0,0,.18);padding:24px 24px 16px}
.dq .h{font-size:20px;font-weight:600}.dq .c{margin-top:14px;font-size:14px;line-height:1.5;color:var(--onv)}
.dq .a{display:flex;justify-content:flex-end;gap:8px;margin-top:22px}
.tg4{width:100%;background:var(--sch);border-radius:24px;box-shadow:0 8px 20px rgba(0,0,0,.2);display:flex;flex-direction:column;overflow:hidden}
.tg4 .th{padding:22px 24px 10px}.tg4 .th .h{font-size:18px;font-weight:600}.tg4 .th .s{font-size:13px;color:var(--onv);margin-top:2px}
.tg4 .tc{padding:4px 24px 4px;overflow:hidden}
.tl4{display:grid;gap:8px}
.tt4{height:60px;padding:0 12px 0 14px;border-radius:12px;background:var(--surface);box-shadow:inset 0 0 0 1px var(--ov);display:flex;align-items:center;gap:8px}
.tt4 .x{flex:1;min-width:0}.tt4 .a{font-size:14px;font-weight:500}.tt4 .b{font-size:12px;color:var(--onv);margin-top:2px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.tt4.on{background:var(--sc);box-shadow:none}.tt4.on .a{font-weight:600;color:var(--osc)}
.ck4{width:22px;height:22px;border-radius:11px;border:2px solid var(--outline);flex:none}
.ck4.on{border:0;background:var(--primary);color:var(--onPrimary);display:grid;place-items:center}
.new4{height:48px;margin-top:8px;border-radius:12px;border:1.5px dashed var(--outline);display:flex;align-items:center;justify-content:center;gap:6px;color:var(--primary);font-size:14px;font-weight:500}
.form4{margin-top:8px;padding:12px;border-radius:12px;background:var(--surface);box-shadow:inset 0 0 0 1px var(--ov)}
.form4 .l{display:flex;align-items:center;font-size:13px;font-weight:600;color:var(--primary)}.form4 .l span{flex:1}
.in4{height:44px;margin-top:8px;border-radius:8px;background:var(--scl);box-shadow:inset 0 -1px 0 var(--outline);display:flex;align-items:center;padding:0 4px 0 12px;font-size:14px;color:var(--onv)}
.in4.foc{box-shadow:inset 0 -2px 0 var(--primary);color:var(--on)}.in4 .v{flex:1}.in4 .cnt{font-size:12px;color:var(--onv);padding-right:8px;font-feature-settings:'tnum'}
.form4 .fa{display:flex;justify-content:flex-end;gap:8px;margin-top:10px}
.tg4 .ta{display:flex;gap:8px;padding:16px 24px 20px}
.tg4 .ta div{flex:1;height:48px;border-radius:24px;display:grid;place-items:center;font-size:15px;font-weight:600}
.tg4 .ta .ok{background:var(--primary);color:var(--onPrimary)}.tg4 .ta .no{color:var(--primary);box-shadow:inset 0 0 0 1px var(--ov)}
.emp4{display:flex;flex-direction:column;align-items:center;padding:14px 0 6px;color:var(--onv);font-size:13px;text-align:center}
.emp4 .h{font-size:15px;font-weight:600;color:var(--on);margin-top:8px}
'''
SCRIM = '<div class="scrim"></div>'
ROOM_ID = '21452505'
TAGS = [('常看', '每天都会看的', True), ('唱歌', '唱见、弹唱', False), ('游戏', '', False), ('学习', '外语、读书', False), ('睡前听', '适合睡前开着', True)]


def pg(w, h, scale, body, frame='ph', crop=False, style=''):
    return page(w, h, scale, body, frame=frame, extra_css=CSS2, crop=crop, style=style)


def wrap(inner, pad):
    return f'<div class="dwrap" style="padding:{pad}">{inner}</div>'


# ---------- card sheets ----------
def item(label, html, span=1):
    return f'<div class="item" style="grid-column:span {span}"><div class="lbl">{label}</div>{html}</div>'


def sheet3():
    cards = [
        item('直播中（人数口径看设置）', card3('a')),
        item('录播', card3('g', 'replay')),
        item('启动时核验状态', card3('b', 'verify')),
        item('刷新失败', card3('c', 'unknown')),
        item('未开播（只是没有人数）', card3('d', 'offline')),
        item('封面图加载中', card3('e', cover_state='loading')),
        item('封面图加载失败', card3('f', cover_state='error')),
        item('平台标“始终显示”', card3('h', plat='always')),
        item('观看历史（可删除）', card3('l', delete=True)),
        item('混合平台也不标平台（默认）', card3('i')),
    ]
    big = item('关注页关掉“紧凑模式”时一列；“自动”平台标只在这里出现', card3('a', big=True, plat='auto'), 2)
    cmp_ = [item('“简洁”预设，两列时没有人数', compact3('b')), item('“简洁”预设', compact3('c')),
            item('“简洁”预设，宽度够 260 才显示人数', compact3('a', wide=True), 2)]
    body = ('<div class="sheetpg"><div class="sh">封面卡片（默认“标准”预设；热门、关注、分区、搜索、历史都是小号）</div>'
            + grid(cards, 2, 0, 10, 'row-gap:14px') + '<div class="sh">大号卡片</div>' + grid([big], 2, 0, 10)
            + '<div class="sh">紧凑信息行</div>' + grid(cmp_, 2, 0, 10, 'row-gap:14px') + '</div>')
    return pg(393, 2000, 2, body, crop=True, style='height:auto')


def sheet4():
    tip = '<div class="tipx" style="left:18px;top:96px;width:230px">深夜电台 · 点歌接龙到天亮，今晚聊聊你的故事</div>'
    cards = [
        item('直播中', card4('a', nmap={'card': 1, 'aud': 3})),
        item('录播', card4('g', 'replay', nmap={'rep': 4})),
        item('启动时核验状态', card4('b', 'verify')),
        item('刷新失败', card4('c', 'unknown')),
        item('未开播：压暗并标出', card4('d', 'offline', nmap={'off': 6})),
        item('受限（付费、需登录等）', card4('m', mark='付费', nmap={'mark': 5})),
        item('混合平台的列表', card4('k', plat=True, nmap={'plat': 2})),
        item('第一次加载（静态骨架）', card4(None, 'skeleton')),
        item('封面图加载中或失败', card4('e', cover_state='placeholder')),
        item('观看历史（可删除）', card4('l').replace('<div class="chipc br">', f'<div class="del3" style="z-index:2" data-n="7" data-tag="keep">{r("delete_bin_line", 16)}</div><div class="chipc br">', 1)),
        item('鼠标悬停（电脑）：显示完整标题', f'<div style="position:relative">{card4("a", hover=True)}{tip}</div>'),
        item('键盘焦点（电脑、电视）', card4('h', focus=True)),
    ]
    big = item('大号卡片（关注页关掉“紧凑模式”）', card4('j', plat=True).replace('class="c4"', 'class="c4 big"', 1).replace('height:64px', 'height:72px'), 2)
    cmp_ = [item('“简洁”预设', compact3('b').replace('c3', 'c4')), item('“简洁”预设', compact3('c').replace('c3', 'c4')),
            item('“简洁”预设，宽度够时显示人数', compact3('a', wide=True).replace('c3', 'c4'), 2)]
    body = ('<div class="sheetpg"><div class="sh">封面卡片（默认“标准”预设，小号）</div>' + grid(cards, 2, 0, 10, 'row-gap:14px')
            + '<div class="sh">大号卡片</div>' + grid([big], 2, 0, 10)
            + '<div class="sh">紧凑信息行（照 v3）</div>' + grid(cmp_, 2, 0, 10, 'row-gap:14px') + '</div>')
    return pg(393, 2100, 2, body, crop=True, style='height:auto')


# ---------- v3 dialogs ----------
def menu3(followed=False):
    tag_color = 'var(--primary)' if followed else 'rgba(25,28,32,.6)'
    return (f'<div class="d3"><div class="d3h"><span class="lg"><img src="{LOGO("bilibili")}"></span><span class="nm">晚风</span>'
            f'<span class="i48" style="color:var(--primary)">{r("share_forward_line", 20)}</span><span style="width:6px"></span>'
            f'<span class="i48" style="color:{tag_color}">{r("price_tag_3_line", 20)}</span></div>'
            f'<div style="padding:16px 24px 16px"><div class="tbox">{R["a"][2]}</div><div class="rid">房间号: {ROOM_ID}</div></div>'
            f'<div class="d3a"><span class="tonal">{"取消关注" if followed else "关注"}</span><span class="tbtn">关闭</span></div></div>')


def follow_ask3():
    return ('<div class="dlgA"><div class="h">关注</div><div class="c">是否关注 晚风？</div>'
            '<div class="a"><span class="tbtn" style="color:#535F70;font-weight:500;font-size:14px">取消</span><span class="fbtn">关注</span></div></div>')


def unfollow3():
    return ('<div class="dlgT"><div class="h">取消关注</div><div class="c">确定要取消关注晚风吗？</div>'
            '<div class="a"><span>取消</span><span>确认</span></div></div>')


def tags3(mode='list', cols=1, list_h=460, wide=False):
    head_btns = (f'<span class="i48" style="color:var(--on)">{mr("close")}</span><span class="i48" style="color:var(--on)">{mr("check")}</span>'
                 if mode == 'add' else f'<span class="i48" style="color:var(--primary)">{r("add_circle_line", 20)}</span>')
    if mode == 'list':
        tiles = ''.join(f'<div class="tt3{" on" if on else ""}"><div class="x"><div class="a">{n}</div>' + (f'<div class="b">{d}</div>' if d else '')
                        + f'</div><span class="ck3{" on" if on else ""}">{mr("check", 12) if on else ""}</span></div>' for n, d, on in TAGS)
        content = f'<div class="tl3" style="grid-template-columns:repeat({cols},1fr)">{tiles}</div>' + ('<div class="sbar"></div>' if list_h < 380 else '')
    elif mode == 'empty':
        content = (f'<div style="display:flex;flex-direction:column;align-items:center;padding:8px 0;color:rgba(25,28,32,.38)">{r("price_tag_3_line", 36)}'
                   '<div style="margin-top:10px;font-size:13px;text-align:center;line-height:1.5">暂无自定义标签。<br>点击右上角 “+” 按钮即可创建。</div></div>')
    else:
        content = ('<div class="form3"><div class="l">添加标签</div><div class="in3 foc">户外<span style="flex:1"></span>' + mr('clear', 18)
                   + '</div><div class="in3">请输入备注/描述（可选）...</div></div>')
    return (f'<div class="tg3"><div class="th"><span class="x" style="padding-left:{4 if mode == "add" else 12}px">设置房间标签 / 分类</span>{head_btns}</div>'
            f'<div class="tc" style="height:{list_h + 32}px">{content}</div>'
            f'<div class="ta"><div class="no">取消</div><div class="ok{" dis" if mode == "add" else ""}">确认</div></div></div>')


# ---------- new dialogs ----------
def menu4(followed=False, n=True):
    N = (lambda k: k + 10) if n else (lambda k: None)
    fol = (f'<span class="g4"{at(N(3), "chg")}>{r("check_line", 18)}已关注</span>' if followed
           else f'<span class="f4"{at(N(3), "chg")}>{r("add_line", 18)}关注</span>')
    return (f'<div class="d4"><div class="d4h"><span class="lg" style="background:var(--surface)"><img src="{LOGO("bilibili")}"></span>'
            f'<div class="x"><div class="n">晚风</div><div class="s">哔哩哔哩 · 房间号 {ROOM_ID}</div></div></div>'
            f'<div class="tbox4">{R["a"][2]}</div>'
            f'<div class="acts4"><span class="ob4"{at(N(1), "chg")}>{r("share_forward_line", 18)}分享</span>'
            f'<span class="ob4"{at(N(2), "chg")}>{r("price_tag_3_line", 18)}设置标签</span></div>'
            f'<div class="foot4"><span class="t4 mute"{at(N(4), "keep")}>关闭</span>{fol}</div></div>')


def ask4():
    return ('<div class="dq"><div class="h">先关注再设置标签</div><div class="c">标签只能加在关注的直播间上。现在关注晚风吗？</div>'
            '<div class="a"><span class="t4">取消</span><span class="f4" style="padding:0 18px">关注并设置标签</span></div></div>')


def unfollow4():
    return ('<div class="dq"><div class="h">取消关注</div><div class="c">确定要取消关注晚风吗？</div>'
            '<div class="a"><span class="t4">取消</span><span class="f4 err">取消关注</span></div></div>')


def tags4(mode='list', cols=1, n=True, list_h=None):
    N = (lambda k: k + 20) if n else (lambda k: None)
    tiles = ''
    for i, (name, desc, on) in enumerate(TAGS):
        tiles += (f'<div class="tt4{" on" if on else ""}"{at(N(1) if i == 0 else None, "keep", "tl")}><div class="x"><div class="a">{name}</div>'
                  + (f'<div class="b">{desc}</div>' if desc else '') + f'</div><span class="ck4{" on" if on else ""}">{mr("check", 16) if on else ""}</span></div>')
    lst = f'<div class="tl4" style="grid-template-columns:repeat({cols},minmax(0,1fr))">{tiles}</div>'
    form = (f'<div class="form4"><div class="l"><span>新建标签</span><span class="i48" style="flex:none;width:40px;height:32px;color:var(--onv)"{at(N(8), "chg")}>{mr("close", 20)}</span></div>'
            f'<div class="in4 foc"{at(N(5), "chg", "tl")}><span class="v">户外</span><span class="cnt">2/15</span>{mr("cancel", 18)}</div>'
            f'<div class="in4"{at(N(6), "chg", "tl")}><span class="v">备注（可选）</span></div>'
            f'<div class="fa"><span class="f4" style="height:36px"{at(N(7), "chg")}>{r("add_line", 18)}添加</span></div></div>')
    if mode == 'list':
        content = lst + f'<div class="new4"{at(N(2), "chg")}>{r("add_line", 20)}新建标签</div>'
    elif mode == 'add':
        content = lst + form
    else:
        content = (f'<div class="emp4"><span style="color:var(--primary)">{r("price_tag_3_line", 32)}</span><div class="h">还没有标签</div>'
                   '<div>输入名称新建一个，例如“常看”“睡前听”</div></div>' + form.replace('户外', '常看').replace('2/15', '2/15'))
    style = f' style="max-height:{list_h}px"' if list_h else ''
    return (f'<div class="tg4"><div class="th"><div class="h">设置房间标签 / 分类</div><div class="s">晚风 · 哔哩哔哩</div></div>'
            f'<div class="tc"{style}>{content}</div>'
            f'<div class="ta"><div class="no"{at(N(3), "keep")}>取消</div><div class="ok"{at(N(4), "keep")}>确认</div></div></div>')


TOAST = '<div class="toast" style="bottom:130px">需要先关注</div>'

OUT = {
    'v3-cards': sheet3(),
    'v4-cards': sheet4(),
    # v3: long press, follow, unfollow, tags
    'v3-menu': popular3('phone', scrim=SCRIM + wrap(menu3(), '24px 40px')),
    'v3-menu-followed': popular3('phone', scrim=SCRIM + wrap(menu3(True), '24px 40px')),
    'v3-follow-ask': popular3('phone', scrim=SCRIM + wrap(follow_ask3(), '24px 16px') + TOAST),
    'v3-unfollow': popular3('phone', scrim=SCRIM + wrap(menu3(True), '24px 40px') + SCRIM + wrap(unfollow3(), '24px 20px')),
    'v3-tags': popular3('phone', scrim=SCRIM + wrap(tags3(), '24px 19.65px')),
    'v3-tags-add': popular3('phone', scrim=SCRIM + wrap(tags3('add'), '24px 19.65px')),
    'v3-tags-empty': popular3('phone', scrim=SCRIM + wrap(tags3('empty'), '24px 19.65px')),
    'v3-wide-menu': popular3('wide', scrim=SCRIM + wrap('<div style="width:428px">' + menu3() + '</div>', '24px 40px')),
    'v3-wide-tags': popular3('wide', scrim=SCRIM + wrap('<div style="width:496px">' + tags3(cols=2, list_h=390) + '</div>', '24px 40px')),
    'v3-land-tags': popular3('land', scrim=SCRIM + wrap('<div style="width:496px">' + tags3(cols=2, list_h=133) + '</div>', '24px 40px')),
    # new
    'v4-menu': popular4('phone', scrim=SCRIM + wrap(menu4(), '24px 40px')),
    'v4-menu-followed': popular4('phone', scrim=SCRIM + wrap(menu4(True, n=False), '24px 40px')),
    'v4-follow-ask': popular4('phone', scrim=SCRIM + wrap(ask4(), '24px 24px')),
    'v4-unfollow': popular4('phone', scrim=SCRIM + wrap(menu4(True, n=False), '24px 40px') + SCRIM + wrap(unfollow4(), '24px 24px')),
    'v4-tags': popular4('phone', scrim=SCRIM + wrap(tags4(), '24px 20px')),
    'v4-tags-add': popular4('phone', scrim=SCRIM + wrap(tags4('add'), '24px 20px')),
    'v4-tags-empty': popular4('phone', scrim=SCRIM + wrap(tags4('empty', n=False), '24px 20px')),
    'v4-wide-menu': popular4('wide', hover=0, scrim=SCRIM + wrap('<div style="width:428px">' + menu4(n=False) + '</div>', '24px 40px')),
    'v4-wide-tags': popular4('wide', scrim=SCRIM + wrap('<div style="width:520px">' + tags4(cols=2, n=False) + '</div>', '24px 40px')),
    'v4-land-tags': popular4('land', scrim=SCRIM + wrap('<div style="width:520px">' + tags4(cols=2, n=False, list_h=170) + '</div>', '12px 40px')),
}
for k in list(OUT):
    OUT[k] = OUT[k].replace('<style>', '<style>' + CSS2, 1) if CSS2 not in OUT[k] else OUT[k]
write(HERE, OUT)
