"""U.2d wide live room mockups: v3 restored and the new design.
v3: lib/modules/live_play/widgets/layout/live_play_content.dart:58-110 (split
above 680: video + chat column 34% clamped 300-400), live_play_header.dart
(wide header: filled follow button, labelled record button),
video_controller_panel.dart BottomActionBar inline (:1546-1578).
    python3 docs/ui/compare/U.2d/src/gen.py && python3 tools/ui/mock/render.py docs/ui/compare/U.2d/src/ --annotate"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
CSS = '''
.win{display:flex;flex-direction:column}
.body{flex:1;display:flex;min-height:0}
.stage{position:relative;flex:1;background:#000;display:flex;align-items:center;justify-content:center;overflow:hidden}
.stage .pic{width:100%;aspect-ratio:16/9;background:#000 url(.cache/img/158.jpg) center 55%/cover}
.col{flex:none;display:flex;flex-direction:column;background:var(--surface);border-left:1px solid var(--ov);position:relative;overflow:hidden}
.list{flex:1;overflow:hidden;display:flex;flex-direction:column;justify-content:flex-end;padding:6px 0 10px}
/* v3 */
.v3h .nick{font-size:11px;line-height:15px}.v3h .area{font-size:11px;line-height:15px}
.v3fol{height:40px;padding:0 14px;border-radius:6px;background:var(--primary);color:#fff;font-size:12px;display:flex;align-items:center;margin:0 5px 0 2px}
.v3fol.on{background:rgba(54,97,142,.49)}
.v3rec{height:48px;padding:0 8px;border-radius:12px;background:var(--schh);color:var(--onv);display:flex;align-items:center;gap:4px;font-size:11px;font-weight:600}
.v3top{position:absolute;left:0;right:0;top:0;height:56px;display:flex;align-items:center;padding:0 8px;background:linear-gradient(0deg,transparent,rgba(0,0,0,.45));z-index:5;color:#fff}
.v3top .title{flex:1;padding:0 12px;font:700 16px 'Noto Sans SC';white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.v3bot{position:absolute;left:0;right:0;bottom:0;height:56px;display:flex;align-items:center;padding:0 8px;background:linear-gradient(180deg,transparent,rgba(0,0,0,.45));color:#fff;z-index:5}
.pill{display:flex;align-items:center;gap:2px;padding:0 6px;height:48px;font-size:14px;flex:none}
.fit{flex:none;padding:0 6px;font-size:15px;white-space:nowrap}
.res{height:56px;display:flex;align-items:center;padding:4px}
.res .aud{flex:3;padding:0 8px;display:flex;align-items:center;gap:4px;font-size:12px}
.res .sel{flex:2;text-align:right;font-size:11px;color:var(--primary);padding-right:12px}
.res .line{flex:1;text-align:right;font-size:11px;color:var(--primary);padding-right:12px}
.it{margin:4px 8px;background:rgba(255,255,255,.72);border:.5px solid rgba(0,0,0,.08);border-radius:10px;padding:8px 12px;display:flex;align-items:flex-start}
.it i{width:8px;height:8px;border-radius:4px;margin:6px 10px 0 0;flex:none}.it p{font-size:14px;line-height:1.45;font-weight:500}.it b{font-weight:700}
.tabs.v3t div{font-size:15px}
/* new */
.vvol{display:flex;align-items:center;gap:6px;color:#fff;margin:0 4px}.vvol .t{width:80px;height:4px;border-radius:2px;background:rgba(255,255,255,.35);position:relative}.vvol .t i{position:absolute;left:0;top:0;bottom:0;width:70%;background:#fff;border-radius:2px}.vvol .t u{position:absolute;left:calc(70% - 7px);top:-5px;width:14px;height:14px;border-radius:7px;background:#fff}
.collapse{position:absolute;top:50%;width:22px;height:56px;border-radius:8px 0 0 8px;background:var(--schh);color:var(--onv);display:grid;place-items:center;z-index:8;transform:translateY(-50%)}
.r-card{margin:0 16px;border-radius:16px;padding:14px 16px 16px;background:var(--recbg);box-shadow:inset 0 0 0 1px #F2C4C0}
.r-st{display:flex;align-items:center;gap:8px;font-size:15px;font-weight:600;color:#B3261E}.r-st small{margin-left:auto;font-size:12px;color:var(--onv);font-weight:500}
.r-dot{width:10px;height:10px;border-radius:5px;background:var(--rec);box-shadow:0 0 0 4px rgba(217,45,32,.18)}
.r-time{font:600 34px/1.15 'Geist','Noto Sans SC';font-feature-settings:'tnum';margin:6px 0 2px}
.r-stats{display:flex;gap:6px;margin:8px 0 14px;flex-wrap:wrap}.r-stats span{height:26px;padding:0 10px;border-radius:13px;background:rgba(255,255,255,.75);font-size:12px;display:flex;align-items:center}
'''
mr = lambda n, s=24: f'<span class="mr" style="font-size:{s}px">{n}</span>'
mi = lambda n, s=24: f'<span class="mi" style="font-size:{s}px">{n}</span>'
rx = lambda c, s=24: f'<span class="rx" style="font-size:{s}px">&#x{c};</span>'
ci = lambda c, s=24: f'<span class="ci" style="font-size:{s}px">&#x{c};</span>'


def ib(inner, n=None, cls='ib', tag=None):
    a = (f' data-n="{n}"' if n else '') + (f' data-tag="{tag}"' if tag else '')
    return f'<div class="{cls}"{a}>{inner}</div>'


CHAT = [('#C2410C', 'Aki', '打卡第 52 天，晚安前来听歌'), ('#000', '路过的风', '主播声音太温柔了'), ('#1971C2', '夜猫子', '可以点《晴天》吗'),
        ('#000', '一只小熊', '这首歌好好听'), ('#C2255C', '星河长明', '前排支持！'), ('#2F9E44', '清欢', '下一首想听《晚风》'),
        ('#000', '风吹麦浪', '来了来了'), ('#000', '小林同学', '今天也是被治愈的一天'), ('#000', '橘子汽水', '晚风晚上好～'),
        ('#000', '不吃香菜', '上一首是什么歌？'), ('#000', '月亮邮差', '这个混响调得真舒服')]
STATUS = '<div class="status" style="height:0;display:none"></div>'


def page(w, h, scale, body):
    return (f'<!doctype html><html><head><meta charset="utf-8"><meta name="mock-size" content="{w}x{h}@{scale}">'
            f'<link rel="stylesheet" href="kit/kit.css"><style>{CSS}</style></head>'
            f'<body><div class="win" style="--w:{w}px;--h:{h}px">{body}<div class="syn" style="top:6px">示意图片</div></div></body></html>')


def col_width(w):
    return max(300, min(400, round(w * 0.34)))


# ---------- v3 ----------
def v3_header(w):
    return ('<div class="appbar v3h"><div class="back">' + mi('arrow_back') + '</div><span class="av" style="background-image:url(.cache/img/65.jpg)"></span>'
            '<div class="tt" style="margin-left:8px"><div class="nick">晚风</div><div class="area">哔哩哔哩 / 唱见电台</div></div>'
            '<div class="v3fol on">已关注</div><div class="v3rec">' + rx('f05a', 14) + '录制</div>' + ib(rx('ea42')) + '<div style="width:4px"></div></div>')


def v3_stage(windows=True):
    top = ('<div class="v3top"><div class="title">深夜电台 · 点歌接龙到天亮</div>' + ib(rx('ee05', 21)) + ('' if windows else ib(rx('f235'))) + ib(ci('e806')) + '</div>')
    left = ib(mr('pause', 28)) + ib(mr('refresh')) + '<div class="pill">' + mr('check', 15) + '已关注</div>' + ib('<span class="dmk open"></span>') + ib('<span class="dmk set"></span>')
    right = (('' if windows else ib(mr('screen_rotation_alt', 21))) + '<div class="fit">默认比例</div>'
             + (ib(mr('volume_up', 22)) + ib(mr('unfold_more', 26)) if windows else '') + ib(mr('fullscreen', 26)))
    bot = f'<div class="v3bot"><div style="display:flex;align-items:center">{left}</div><div style="flex:1"></div><div style="display:flex;align-items:center">{right}</div></div>'
    return f'<div class="stage"><div class="pic"></div>{top}{bot}</div>'


def v3_chat():
    items = ''.join(f'<div class="it"><i style="background:{c}"></i><p><b>{u}: </b>{t}</p></div>' for c, u, t in CHAT[:7])
    return ('<div class="res"><div class="aud">' + mr('people_alt', 14) + '在线 1.2万</div><div class="sel">原画</div><div class="line">线路1</div></div><hr>'
            '<div class="tabs v3t"><div class="on">弹幕列表</div><div>醒目留言</div><div>弹幕设置</div><div>屏蔽管理</div></div>'
            f'<div class="list" style="flex-direction:column-reverse;justify-content:flex-start">{items}</div>')


def v3(w, h, scale, windows=True):
    if w <= 680:
        raise ValueError
    cw = col_width(w)
    body = v3_header(w) + f'<div class="body">{v3_stage(windows)}<div class="col" style="width:{cw}px">{v3_chat()}</div></div>'
    return page(w, h, scale, body)


# ---------- new ----------
def v4_header(recording=False):
    rec = '<span class="recon"><i></i></span>' if recording else '<span class="ring"><i></i></span>'
    return ('<div class="appbar"><div class="back" data-n="1">' + mi('arrow_back') + '</div><span class="av" data-n="2" style="background-image:url(.cache/img/65.jpg)"></span>'
            '<div class="tt"><div class="n">晚风</div><div class="s">哔哩哔哩 · 唱见电台</div></div>'
            '<div class="fol on" data-n="3">' + rx('eb7b') + '已关注</div><div class="recbtn" data-n="4">' + rec + '</div>'
            + ib(rx('ea42'), 5) + '<div style="width:4px"></div></div>')


def v4_stage(windows=True, collapsed=False, recording=False, n=True):
    N = (lambda k: k) if n else (lambda k: None)
    top = ('<div class="vtop"><div class="title">深夜电台 · 点歌接龙到天亮</div>' + ib(rx('ee05', 21), N(6), 'ib vic') + ('' if windows else ib(rx('f235'), N(7), 'ib vic'))
           + ib(ci('e806'), N(8), 'ib vic') + '</div>')
    left = ib(mr('pause', 28), N(9), 'ib vic') + ib(mr('refresh'), N(10), 'ib vic') + ib('<span class="dmk open"></span>', N(11), 'ib vic') + ib('<span class="dmk set"></span>', N(12), 'ib vic')
    right = (('<div class="vvol" data-n="13"><span class="mr" style="font-size:22px">volume_up</span><div class="t"><i></i><u></u></div></div>' if windows and n else
              ('<div class="vvol"><span class="mr" style="font-size:22px">volume_up</span><div class="t"><i></i><u></u></div></div>' if windows else ib(mr('screen_rotation_alt', 21), None, 'ib vic')))
             + ib(mr('vertical_split', 24), N(14), 'ib vic', 'add')
             + (ib(mr('unfold_more', 26), N(15), 'ib vic') if windows else '') + ib(mr('fullscreen', 26), N(16), 'ib vic'))
    bot = f'<div class="vbot"><div style="display:flex;align-items:center">{left}</div><div style="flex:1"></div><div style="display:flex;align-items:center">{right}</div></div>'
    badge = '<div class="vbadge" style="top:60px"><i></i>录制中 12:34</div>' if recording else ''
    return f'<div class="stage"><div class="pic"></div>{top}{bot}{badge}</div>'


def v4_info(n=True):
    return ('<div class="info"><div class="l1"><span class="t">深夜电台 · 点歌接龙到天亮</span><span class="more"' + (' data-n="17"' if n else '') + '>详情' + rx('ea4e', 18) + '</span></div>'
            '<div class="l2"><div class="figs"><span class="fg"><span class="mr">people_alt</span><b>1.2万</b></span><span class="fg"><span class="mr">whatshot</span><b>84.7万</b></span><span class="fg"><span class="mr">schedule</span><b>2:18</b></span></div>'
            '<div class="chip"' + (' data-n="18"' if n else '') + '>原画' + rx('ea4e', 18) + '</div><div class="chip"' + (' data-n="19"' if n else '') + '>线路1' + rx('ea4e', 18) + '</div></div></div><hr>')


def v4_chat(n=True):
    rows = ''.join(f'<div class="row"><span class="u" style="{"" if c == "#000" else "color:" + c}">{u}：</span>{t}</div>' for c, u, t in CHAT)
    return (v4_info(n) + '<div class="tabs"' + (' data-n="20"' if n else '') + '><div class="on">弹幕列表</div><div>醒目留言<span class="badge">2</span></div><div>弹幕设置</div><div>屏蔽管理</div></div>'
            f'<div class="list"><div class="sys">弹幕服务器连接正常</div>{rows}</div>')


def record_panel():
    return ('<div class="p-h"><span class="t">录制</span><span class="lk">录制中心' + rx('ea6e', 18) + '</span><span class="x">' + mr('close', 22) + '</span></div>'
            '<div class="r-card"><div class="r-st"><i class="r-dot"></i>录制中<small>第 3 段 · 每 5 分钟一段</small></div><div class="r-time">00:12:34</div>'
            '<div class="r-stats"><span>已录 356 MB</span><span>3.2 Mbps</span><span>原画</span><span>弹幕 1,284 条</span></div><div class="btn stop"><i></i>停止录制</div></div>'
            '<div class="sec">这次录制</div><div class="swr"><div class="x"><div class="a">录制清晰度</div></div><span style="font-size:12px;color:var(--onv)">原画（录制中不能改）</span></div>'
            '<div class="swr"><div class="x"><div class="a">同时录弹幕</div><div class="b">在录像旁保存同名 .xml 弹幕文件（录制中不能改）</div></div><span class="sw on"></span></div>'
            '<div class="sec">自动录</div><div class="swr"><div class="x"><div class="a">开播自动录</div><div class="b">主播开播时自动开始录，下播后自动停止</div></div><span class="sw on"></span></div>')


def v4(w, h, scale, windows=True, collapsed=False, recording=False, panel=False, n=True):
    if w < 840:   # medium: the phone layout (video on top, chat below), centred
        body = (v4_header(recording) + '<div class="body" style="flex-direction:column">'
                + f'<div class="stage" style="flex:none;aspect-ratio:16/9">{v4_stage(windows, n=False)[19:-6]}</div>'
                + f'<div style="flex:1;display:flex;flex-direction:column;min-height:0">{v4_chat(False)}</div></div>')
        return page(w, h, scale, body)
    cw = col_width(w)
    col = '' if collapsed else (f'<div class="col" style="width:{cw}px">' + (record_panel() if panel else v4_chat(n)) + '</div>')
    handle = f'<div class="collapse" style="right:{0 if collapsed else cw}px">' + mr('chevron_left' if collapsed else 'chevron_right', 20) + '</div>'
    body = v4_header(recording) + f'<div class="body" style="position:relative">{v4_stage(windows, collapsed, recording, n)}{col}{handle}</div>'
    return page(w, h, scale, body)


OUT = {
    'v3-wide': v3(1280, 800, 1.5), 'v3-medium': v3(720, 1000, 1.5, windows=False),
    'v4-wide': v4(1280, 800, 1.5), 'v4-medium': v4(720, 1000, 1.5, windows=False),
    'v4-wide-collapsed': v4(1280, 800, 1.5, collapsed=True, n=False),
    'v4-wide-record': v4(1280, 800, 1.5, recording=True, panel=True, n=False),
    'v4-desktop': v4(1920, 1080, 1, n=False),
}
for name, html in OUT.items():
    open(os.path.join(HERE, name + '.html'), 'w', encoding='utf-8').write(html)
print(len(OUT), 'pages')
