"""U.2b portrait streams: the three-stop panel of a portrait live room, the
portrait fullscreen with its display-mode and orientation pickers, and how a
portrait stream sits in landscape fullscreen and in the wide room. v3 restored
from v3.2.11, then the new design.

v3 sources (lib/modules/live_play/):
  widgets/layout/live_play_content.dart  PortraitLiveRoomLayout :123-440,
      portraitPanelRange :463-477, PortraitFullscreenPresentation :623-679
  widgets/layout/portrait_fullscreen_interaction.dart  gestures, entry hint
  widgets/video_player/video_controller_panel.dart  TopActionBar :299-458,
      PortraitOrientationButton :603, PortraitFullscreenDisplayModeButton :658,
      LockButton :1009, BottomActionBar._buildPortraitFullscreenLayout :1508
  widgets/video_player/portrait_playback_picker_dialog.dart  both dialogs

    python3 docs/ui/compare/U.2b/src/gen.py
    python3 tools/ui/mock/render.py docs/ui/compare/U.2b/src/ --annotate

Pictures: .cache/img/1027.jpg and 1011.jpg are 720x1280 portrait pictures
(picsum ids 1027 and 1011) that tools/ui/mock/images.txt does not list yet;
65.jpg is the avatar. Sizes follow a 393x852 phone: status bar 36, app bar
56, room area 740 (bottom inset 20), so v3's panel stops are 200 / 326 / 503
(27 %, 44 %, 68 % of 740) and the 9:16 picture is 393x699, centred."""
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
IMG, NEXT, AV = '.cache/img/1027.jpg', '.cache/img/1011.jpg', '.cache/img/65.jpg'
V3STOPS = {'low': 200, 'mid': 326, 'high': 503}
V4STOPS = {'low': 250, 'mid': 326, 'high': 503}   # low: v3's 27 % (200), raised until two danmaku rows show
NAME, PLAT3, PLAT4 = '鹿鹿', '抖音 / 聊天', '抖音 · 聊天'
TITLE = '晚安电台，陪你聊聊天'

CSS = '''
.ph{background:var(--surface)}
.cv{position:absolute;left:0;right:0;top:92px;height:760px;background:#000;overflow:hidden;z-index:1}
.cv .pic{position:absolute;left:0;right:0;top:20px;height:699px;background:url(.cache/img/1027.jpg) center/cover}
.ov{position:absolute;left:0;right:0;z-index:4}
.dm{font-size:17px}
/* v3 bars (45 % gradients) */
.b3t{position:absolute;left:0;right:0;top:0;height:56px;display:flex;align-items:center;padding:0 8px;background:linear-gradient(0deg,transparent,rgba(0,0,0,.45));color:#fff;z-index:5}
.b3b{position:absolute;left:0;right:0;bottom:0;height:56px;display:flex;align-items:center;padding:0 8px;background:linear-gradient(180deg,transparent,rgba(0,0,0,.45));color:#fff;z-index:5}
.t3{flex:1;min-width:0;padding:0 12px;color:#fff;font:700 16px 'Noto Sans SC';white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.ib.w{color:#fff}
.t13{color:#fff;font-size:13px;padding:0 4px;flex:none}
.bat{margin:0 12px}
.swap{width:40px;height:40px;border-radius:20px;background:rgba(0,0,0,.26);display:grid;place-items:center;color:#fff;margin:0 4px;flex:none}
.lock{position:absolute;right:20px;top:50%;transform:translateY(-50%);width:50px;height:50px;border-radius:25px;background:rgba(0,0,0,.38);display:grid;place-items:center;color:#fff;z-index:6;opacity:.9}
/* v3 app bar (compact header) */
.v3n{font-size:11px;line-height:16px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.v3heart{width:40px;height:40px;border-radius:20px;background:var(--sc);color:var(--osc);display:grid;place-items:center;margin:0 9px 0 6px;flex:none}
.v3recb{width:48px;height:48px;border-radius:12px;background:var(--schh);color:var(--onv);display:grid;place-items:center;flex:none}
/* panels */
.sh3,.sh4{position:absolute;left:0;right:0;bottom:0;z-index:10;background:var(--surface);overflow:hidden;display:flex;flex-direction:column;padding-bottom:20px}
.sh3{border-radius:22px 22px 0 0;box-shadow:0 -3px 14px rgba(0,0,0,.30)}
.sh4{border-radius:16px 16px 0 0;box-shadow:0 -4px 16px rgba(0,0,0,.18)}
.hdl{height:48px;flex:none;display:flex;align-items:center;justify-content:center;position:relative}
.hint{display:flex;align-items:center;gap:4px;color:var(--primary);font-size:12px;font-weight:600;height:40px;padding:0 6px}.hint .mr{font-size:20px}
.landbtn{position:absolute;right:12px;top:8px;height:32px;border-radius:16px;padding:0 12px 0 9px;display:flex;align-items:center;gap:4px;background:var(--schh);color:var(--onv);font-size:13px;font-weight:500}.landbtn .mr{font-size:17px}
.v3land{position:absolute;right:12px;height:48px;border-radius:24px;background:rgba(0,0,0,.68);color:#fff;display:flex;align-items:center;gap:6px;padding:0 14px;font-size:13px;font-weight:600;z-index:9}.v3land .mr{font-size:20px}
.res{height:56px;display:flex;align-items:center;padding:4px;flex:none}
.res .aud{flex:3;padding:0 8px;display:flex;align-items:center;gap:4px;font-size:12px}
.res .sel{flex:2;text-align:right;font-size:11px;color:var(--primary);padding-right:12px}
.res .line{flex:1;text-align:right;font-size:11px;color:var(--primary);padding-right:12px}
.tabs{flex:none}
.lst{flex:1;min-height:0;overflow:hidden;display:flex;flex-direction:column;justify-content:flex-end;padding-bottom:4px}
.sh4 .lst,.col .lst{-webkit-mask-image:linear-gradient(transparent,#000 14px)}
.it{margin:4px 8px;background:rgba(255,255,255,.72);border:.5px solid rgba(0,0,0,.08);border-radius:10px;padding:8px 12px;display:flex;align-items:flex-start;flex:none}
.it i{width:8px;height:8px;border-radius:4px;margin:6px 10px 0 0;flex:none}.it p{font-size:14px;line-height:1.45;font-weight:500}.it b{font-weight:700}
.row{flex:none}
.info{flex:none}
/* portrait fullscreen */
.ambf{position:absolute;inset:0;background:linear-gradient(135deg,#342B3A,#171B27,#2A202B)}
.amb{position:absolute;inset:-60px;background:url(.cache/img/1027.jpg) center/cover;filter:blur(28px);transform:scale(1.14)}
.veil{position:absolute;inset:0;background:rgba(0,0,0,.15)}
.pv{position:absolute;left:0;right:0;top:76px;height:699px;background:url(.cache/img/1027.jpg) center/cover}
.b3f{position:absolute;left:0;right:0;bottom:0;height:112px;padding:4px 16px;display:flex;flex-direction:column;gap:2px;background:linear-gradient(180deg,transparent,rgba(0,0,0,.45));z-index:5;color:#fff}
.rw{height:48px;display:flex;align-items:center}
.cmp3{height:48px;border-radius:20px;background:rgba(0,0,0,.54);border:1px solid rgba(255,255,255,.24);display:flex;align-items:center;color:rgba(255,255,255,.6);font-size:13px;white-space:nowrap;overflow:hidden;min-width:0}
.cmp3 .h{flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis}
.cmp3 .a,.cmp3 .s{width:48px;display:grid;place-items:center;color:#fff;flex:none}.cmp3 .s{margin-left:auto}
.sel3{height:48px;border-radius:18px;background:rgba(255,255,255,.13);padding:0 8px;display:flex;align-items:center;gap:6px;color:#fff;font-size:13px;font-weight:600;flex:none;white-space:nowrap}
.ehint{position:absolute;left:50%;transform:translateX(-50%);display:flex;align-items:center;gap:6px;padding:10px 16px;border-radius:24px;background:rgba(0,0,0,.66);border:1px solid rgba(255,255,255,.16);color:#fff;font-size:13px;font-weight:600;white-space:nowrap;z-index:7}.ehint .mr{font-size:20px}
.ptop{position:absolute;left:0;right:0;top:0;height:156px;background:linear-gradient(180deg,rgba(0,0,0,.6),rgba(0,0,0,.25) 62%,transparent);z-index:5}
.r1{height:48px;display:flex;align-items:center;padding:0 4px;margin-top:4px}
.r2{height:48px;display:flex;align-items:center;padding:0 4px 0 14px}
.t4{flex:1;min-width:0;padding:0 6px 0 2px;color:#fff;font:600 16px 'Noto Sans SC';white-space:nowrap;overflow:hidden;text-overflow:ellipsis;text-shadow:0 1px 3px rgba(0,0,0,.6)}
.vfol{height:32px;border-radius:16px;display:flex;align-items:center;gap:3px;padding:0 12px 0 9px;font-size:13px;font-weight:500;background:rgba(255,255,255,.18);color:#fff;margin:0 2px;flex:none}.vfol .rx{font-size:16px}
.vring{width:22px;height:22px;border-radius:11px;border:2px solid #fff;display:grid;place-items:center}.vring i{width:9px;height:9px;border-radius:5px;background:#FF5449}
.pbot{position:absolute;left:0;right:0;bottom:0;height:176px;padding:0 8px 8px;display:flex;flex-direction:column;justify-content:flex-end;gap:4px;background:linear-gradient(0deg,rgba(0,0,0,.6),rgba(0,0,0,.25) 62%,transparent);z-index:5;color:#fff}
.comp{flex:1;height:40px;border-radius:20px;background:rgba(0,0,0,.54);border:1px solid rgba(255,255,255,.24);display:flex;align-items:center;color:rgba(255,255,255,.6);font-size:13px;white-space:nowrap;overflow:hidden;min-width:0;margin-right:6px}
.comp .a{width:40px;display:grid;place-items:center;color:#FFD166;flex:none}.comp .s{margin-left:auto;width:40px;display:grid;place-items:center;color:#fff;flex:none}
.vchip{margin:0 3px}
.open{background:rgba(255,255,255,.2);border-radius:24px}
/* pickers */
.dwrap{position:absolute;inset:0;z-index:21;display:flex;align-items:center;justify-content:center;padding:0 40px}
.dlg3{width:313px;background:var(--sch);border-radius:24px;overflow:hidden;color:var(--on)}
.dlg3 .dt{padding:24px 24px 12px;font-size:20px;font-weight:600}
.dlg3 .op{display:flex;align-items:flex-start;gap:12px;padding:8px 24px;font-size:13px;line-height:1.5}
.dlg3 .op .mr{font-size:24px;color:var(--onv);flex:none}.dlg3 .op .mr.on{color:var(--primary)}
.dlg3 .op small{display:block;font-size:12px;color:var(--onv);line-height:1.45;margin-top:2px}
.dlg3 .act{display:flex;justify-content:flex-end;padding:8px 24px 20px;color:var(--primary);font-size:13px;font-weight:600}
.dlg3 .sw3{display:flex;align-items:center;gap:16px;padding:8px 24px}.dlg3 .sw3 .x{flex:1}.dlg3 .sw3 .a{font-size:14px;font-weight:500}.dlg3 .sw3 .b{font-size:13px;color:var(--onv);line-height:1.45;margin-top:2px}
.dlg4{width:329px;background:var(--sch);border-radius:24px;overflow:hidden;color:var(--on);padding-bottom:8px}
.dlg4 .dt{padding:24px 24px 10px;font-size:20px;font-weight:600}
.dlg4 .op{display:flex;align-items:center;gap:12px;padding:8px 20px 8px 24px;min-height:60px}
.dlg4 .op .x{flex:1}.dlg4 .op .a{font-size:15px}.dlg4 .op .b{font-size:12px;color:var(--onv);margin-top:2px;line-height:1.45}
.dlg4 .op.on .a{color:var(--primary);font-weight:600}.dlg4 .op .rx{font-size:22px;color:var(--primary)}
.dlg4 .swr{padding:8px 20px 8px 24px}
.dlg4 .act{display:flex;justify-content:flex-end;padding:4px 16px 8px}.dlg4 .act span{height:40px;padding:0 12px;display:grid;place-items:center;color:var(--primary);font-size:14px;font-weight:600}
.mm{padding:6px 0}.mm .mh{padding:8px 16px 6px;font-size:13px;color:var(--onv);font-weight:600}
.mm .it2{display:flex;align-items:center;gap:12px;padding:8px 14px 8px 16px;min-height:60px}
.mm .it2 .x{flex:1}.mm .it2 .a{font-size:14px}.mm .it2 .b{font-size:12px;color:var(--onv);margin-top:2px;line-height:1.45}
.mm .it2.on .a{color:var(--primary);font-weight:600}.mm .it2 .rx{font-size:20px;color:var(--primary)}
/* swipe to switch (candidate C-9) */
.zone{position:absolute;z-index:8;border:2px dashed rgba(255,255,255,.85);border-radius:12px;display:flex;align-items:center;justify-content:center}
.zone span{padding:6px 10px;border-radius:14px;background:rgba(0,0,0,.6);color:#fff;font-size:13px;font-weight:600;white-space:nowrap;text-align:center;line-height:1.5}
.slide{position:absolute;left:0;right:0;height:852px;overflow:hidden}
.nxt{position:absolute;left:0;right:0;top:0;bottom:0;background:url(.cache/img/1011.jpg) center/cover}
.ncard{position:absolute;left:50%;top:120px;transform:translateX(-50%);display:flex;align-items:center;gap:10px;padding:10px 16px 10px 10px;border-radius:28px;background:rgba(0,0,0,.6);color:#fff;z-index:3;white-space:nowrap}
.ncard .av{width:36px;height:36px;border-radius:18px}.ncard b{font-size:15px}.ncard small{display:block;font-size:12px;color:rgba(255,255,255,.75)}
/* landscape and wide */
.fsb{position:relative;overflow:hidden;background:#000;font-family:'Noto Sans SC'}
.pvl{position:absolute;top:0;bottom:0;background:url(.cache/img/1027.jpg) center/cover}
.comp3l{flex:1;max-width:420px;height:48px;border-radius:20px;background:rgba(0,0,0,.54);border:1px solid rgba(255,255,255,.24);display:flex;align-items:center;color:rgba(255,255,255,.6);font-size:13px;white-space:nowrap;overflow:hidden;min-width:0}
.comp3l .a,.comp3l .s{width:48px;display:grid;place-items:center;color:#fff;flex:none}.comp3l .s{margin-left:auto}
.mid{flex:1;display:flex;justify-content:center;align-items:center;min-width:0;padding:0 8px;height:48px}
.g{display:flex;align-items:center;height:48px;flex:none}
.pill{display:flex;align-items:center;gap:2px;padding:0 6px;height:48px;font-size:13px;flex:none;color:#fff}
.fit{flex:none;padding:0 6px;color:#fff;font-size:15px;white-space:nowrap}
.win{display:flex;flex-direction:column}
.body{flex:1;display:flex;min-height:0}
.stage{position:relative;flex:1;background:#000;overflow:hidden}
.col{flex:none;display:flex;flex-direction:column;background:var(--surface);border-left:1px solid var(--ov);position:relative;overflow:hidden}
.collapse{position:absolute;top:50%;width:22px;height:56px;border-radius:8px 0 0 8px;background:var(--schh);color:var(--onv);display:grid;place-items:center;z-index:8;transform:translateY(-50%)}
.vvol{display:flex;align-items:center;gap:6px;color:#fff;margin:0 4px}.vvol .t{width:80px;height:4px;border-radius:2px;background:rgba(255,255,255,.35);position:relative}.vvol .t i{position:absolute;left:0;top:0;bottom:0;width:70%;background:#fff;border-radius:2px}.vvol .t u{position:absolute;left:calc(70% - 7px);top:-5px;width:14px;height:14px;border-radius:7px;background:#fff}
.v3fol{height:40px;padding:0 14px;border-radius:6px;background:rgba(54,97,142,.49);color:#fff;font-size:12px;display:flex;align-items:center;margin:0 5px 0 2px}
.v3rec{height:48px;padding:0 8px;border-radius:12px;background:var(--schh);color:var(--onv);display:flex;align-items:center;gap:4px;font-size:11px;font-weight:600}
'''

mr = lambda n, s=24: f'<span class="mr" style="font-size:{s}px">{n}</span>'
mi = lambda n, s=24: f'<span class="mi" style="font-size:{s}px">{n}</span>'
rx = lambda c, s=24: f'<span class="rx" style="font-size:{s}px">&#x{c};</span>'
ci = lambda c, s=24: f'<span class="ci" style="font-size:{s}px">&#x{c};</span>'


def ib(inner, n=None, cls='ib vic', tag=None, style='', at=None):
    a = (f' data-n="{n}"' if n else '') + (f' data-tag="{tag}"' if tag else '') + (f' data-at="{at}"' if at and n else '') + (f' style="{style}"' if style else '')
    return f'<div class="{cls}"{a}>{inner}</div>'


def N(n, on):
    return n if on else None


STATUS = ('<div class="status" style="position:relative;z-index:12;background:var(--surface)"><span>21:36</span><span class="r">'
          '<span class="mi">signal_cellular_alt</span><span class="mi">wifi</span><span class="mi">battery_full</span></span></div>')
CHAT3 = [('#000', '系统消息', '开始连接弹幕服务器'), ('#000', '系统消息', '弹幕服务器连接正常'), ('#C2255C', '星河长明', '晚上好～'),
         ('#000', '一只小熊', '主播今天好好看'), ('#1971C2', '夜猫子', '聊聊最近看的书吧'), ('#000', '路过的风', '来了来了'),
         ('#2F9E44', '清欢', '晚安电台打卡第 30 天'), ('#000', '小林同学', '声音好温柔'), ('#000', '橘子汽水', '今天也辛苦啦')]
CHAT4 = [('#C2255C', '星河长明', '晚上好～'), ('#000', '一只小熊', '主播今天好好看'), ('#1971C2', '夜猫子', '聊聊最近看的书吧'),
         ('#000', '路过的风', '来了来了'), ('#2F9E44', '清欢', '晚安电台打卡第 30 天'), ('#000', '小林同学', '声音好温柔'),
         ('#000', '橘子汽水', '今天也辛苦啦'), ('#C2410C', 'Aki', '想听你唱一首'), ('#000', '不吃香菜', '前排支持！')]
FLY = [(0.30, '前排支持！'), (0.06, '晚上好～'), (0.44, '主播今天好好看'), (0.18, '来了来了')]
FLYLAND = [(0.10, 0.30, '前排支持！'), (0.62, 0.20, '晚上好～'), (0.40, 0.52, '主播今天好好看')]


def page(w, h, scale, body, frame='ph', syn=10):
    # numbered controls without a tag are unchanged from v3 (grey callouts)
    body = re.sub(r'(data-n="\d+")(?! data-tag)', r'\1 data-tag="keep"', body)
    st = f' style="--w:{w}px;--h:{h}px;width:{w}px;height:{h}px"' if frame != 'ph' else ''
    return (f'<!doctype html><html><head><meta charset="utf-8"><meta name="mock-size" content="{w}x{h}@{scale}">'
            f'<link rel="stylesheet" href="kit/kit.css"><style>{CSS}</style></head>'
            f'<body><div class="{frame}"{st}>{body}<div class="syn" style="top:{syn}px">示意图片</div></div></body></html>')


def fly(y0, y1, items=FLY):
    return ''.join(f'<div class="dm" style="left:{18 + (k * 97) % 210}px;top:{y0 + k * 34:.0f}px">{t}</div>'
                   for k, (_, t) in enumerate(items) if y0 + k * 34 + 24 < y1)


# ---------------------------------------------------------------- app bars
def header3():
    return ('<div class="appbar" style="position:relative;z-index:12"><div class="back">' + mi('arrow_back') + '</div>'
            f'<span class="av" style="background-image:url({AV})"></span>'
            f'<div class="tt" style="margin-left:8px"><div class="v3n">{NAME}</div><div class="v3n">{PLAT3}</div></div>'
            '<div class="v3heart">' + rx('ee0a', 19) + '</div><div class="v3recb">' + rx('f05a', 18) + '</div>'
            + ib(rx('ea42'), cls='ib') + '<div style="width:4px"></div></div>')


def header4(n=False):
    return ('<div class="appbar" style="position:relative;z-index:12"><div class="back"' + (' data-n="1"' if n else '') + '>' + mi('arrow_back') + '</div>'
            f'<span class="av"' + (' data-n="2"' if n else '') + f' style="background-image:url({AV})"></span>'
            f'<div class="tt"><div class="n">{NAME}</div><div class="s">{PLAT4}</div></div>'
            '<div class="fol on"' + (' data-n="3"' if n else '') + '>' + rx('eb7b') + '已关注</div>'
            '<div class="recbtn"' + (' data-n="4"' if n else '') + '><span class="ring"><i></i></span></div>'
            + ib(rx('ea42'), N(5, n), 'ib') + '<div style="width:4px"></div></div>')


def info4(n=False):
    return ('<div class="info"><div class="l1"><span class="t">' + TITLE + '</span><span class="more"' + (' data-n="17" data-at="tr"' if n else '') + '>详情' + rx('ea4e', 18) + '</span></div>'
            '<div class="l2"><div class="figs"><span class="fg"><span class="mr">people_alt</span><b>3.6万</b></span><span class="fg"><span class="mr">schedule</span><b>1:05</b></span></div>'
            '<div class="chip"' + (' data-n="18"' if n else '') + '>原画' + rx('ea4e', 18) + '</div><div class="chip"' + (' data-n="19"' if n else '') + '>线路1' + rx('ea4e', 18) + '</div></div></div><hr>')


def tabs(n=False, v3=False):
    return ('<div class="tabs' + (' v3t' if v3 else '') + '"' + (' data-n="20"' if n else '') + '><div class="on">弹幕列表</div><div>醒目留言'
            + ('' if v3 else '<span class="badge">2</span>') + '</div><div>弹幕设置</div><div>屏蔽管理</div></div>')


# ---------------------------------------------------------------- portrait-stream room
def room3(stop, controls=True):
    h = V3STOPS[stop]
    top = 832 - h
    vis = top - 92
    bars = ''
    if controls:
        bars = ('<div class="b3t" style="top:92px"><div class="t3">' + TITLE + '</div>'
                + ib(rx('ee05', 21), cls='ib w') + ib(rx('f235', 21), cls='ib w') + ib(ci('e806'), cls='ib w') + '</div>')
    pill = f'<div class="v3land" style="top:{top - 12 - 48}px">' + mr('screen_rotation', 20) + '横屏全屏</div>'
    cards = ''.join(f'<div class="it"><i style="background:{c}"></i><p><b>{u}: </b>{t}</p></div>' for c, u, t in CHAT3)
    sheet = (f'<div class="sh3" style="top:{top}px"><div class="hdl"><span class="hint">' + mr('keyboard_arrow_down', 20) + '下滑进入竖屏全屏</span></div>'
             '<div class="res"><div class="aud">' + mr('people_alt', 14) + '在线 3.6万</div><div class="sel">原画</div><div class="line">线路1</div></div><hr>'
             + tabs(v3=True) + f'<div class="lst">{cards}</div></div>')
    body = (STATUS + header3() + '<div class="cv"><div class="pic"></div></div>'
            + f'<div class="ov" style="top:92px;height:{vis}px;overflow:hidden">{fly(70, vis)}</div>'
            + bars + pill + sheet + '<div class="gesture"></div>')
    return page(393, 852, 3, body)


def room4(stop, controls=True, n=False):
    h = V4STOPS[stop]
    top = 832 - h
    vis = top - 92
    bars = ''
    if controls:
        left = (ib(mr('pause', 28), N(9, n), tag='chg' if n else None) + ib(mr('refresh'), N(10, n), tag='chg' if n else None)
                + ib('<span class="dmk open"></span>', N(11, n), tag='chg' if n else None) + ib('<span class="dmk set"></span>', N(12, n), tag='chg' if n else None))
        right = ib(mr('screen_rotation_alt', 21), N(13, n), tag='chg' if n else None) + ib(mr('fullscreen', 26), N(14, n), tag='chg' if n else None)
        bars = ('<div class="vtop"><div class="title">' + TITLE + '</div>' + ib(rx('ee05', 21), N(6, n)) + ib(rx('f235', 21), N(7, n)) + ib(ci('e806'), N(8, n)) + '</div>'
                f'<div class="vbot"><div style="display:flex">{left}</div><div style="flex:1"></div><div style="display:flex">{right}</div></div>')
    rows = ''.join(f'<div class="row"><span class="u" style="{"" if c == "#000" else "color:" + c}">{u}：</span>{t}</div>' for c, u, t in CHAT4)
    sheet = (f'<div class="sh4" style="top:{top}px"><div class="hdl"><span class="hint"' + (' data-n="15"' if n else '') + '>'
             + mr('keyboard_arrow_down', 20) + '下滑进入竖屏全屏</span>'
             '<div class="landbtn"' + (' data-n="16" data-tag="chg"' if n else '') + '>' + mr('screen_rotation', 17) + '横屏全屏</div></div>'
             + info4(n) + tabs(n) + f'<div class="lst"><div class="sys">弹幕服务器连接正常</div>{rows}</div></div>')
    body = (STATUS + header4(n) + '<div class="cv"><div class="pic"></div></div>'
            + f'<div class="ov" style="top:92px;height:{vis}px">{fly(84 if controls else 40, vis - (80 if controls else 10))}{bars}</div>'
            + sheet + '<div class="gesture"></div>')
    return page(393, 852, 3, body)


# ---------------------------------------------------------------- portrait fullscreen
def backdrop(mode='ambient'):
    if mode == 'complete':
        return '<div style="position:absolute;inset:0;background:#000"></div><div class="pv"></div>'
    amb = '<div class="ambf"></div><div class="amb"></div><div class="veil"></div>'
    if mode == 'balanced':   # scale 1.08, clipped to the screen
        return amb + '<div class="pv" style="left:-16px;right:-16px;top:49px;height:755px"></div>'
    if mode == 'cover':
        return '<div class="pv" style="left:-43px;right:-43px;top:0;height:852px"></div>'
    return amb + '<div class="pv"></div>'


def pfs_fly(y0=150, y1=640):
    return ''.join(f'<div class="dm" style="left:{20 + (k * 89) % 200}px;top:{y0 + k * 40}px">{t}</div>' for k, (_, t) in enumerate(FLY) if y0 + k * 40 < y1)


def pfs3(dialog=None, hint=True):
    top = ('<div class="b3t">' + ib(mi('arrow_back'), cls='ib w') + '<div class="t13">21:36</div><div class="bat">76</div>'
           f'<div class="t3">{TITLE}</div><div class="swap">' + mr('swap_horiz') + '</div>'
           + ib(rx('ee05', 21), cls='ib w') + ib(rx('f235', 21), cls='ib w') + ib(ci('e806'), cls='ib w') + '</div>')
    r1 = ('<div class="rw"><div class="cmp3" style="flex:1"><span class="a">' + mr('auto_awesome', 18) + '</span><span class="h">发送一条本地字幕</span><span class="s">' + mr('send', 18) + '</span></div>'
          '<div style="width:6px"></div><div style="flex:1;display:flex;justify-content:flex-end"><div class="sel3">' + mr('tune', 17) + '原画 · 线路1</div></div></div>')
    r2 = ('<div class="rw">' + ib(mr('pause', 28), cls='ib w') + ib('<span class="dmk open"></span>', cls='ib w') + ib('<span class="dmk set"></span>', cls='ib w')
          + '<div style="flex:1"></div>' + ib(mr('blur_on', 21), cls='ib w') + ib(mr('screen_rotation_alt', 21), cls='ib w') + ib(mr('fullscreen_exit', 26), cls='ib w') + '</div>')
    bot = f'<div class="b3f">{r1}{r2}</div>'
    eh = ('<div class="ehint" style="bottom:124px">' + mr('keyboard_arrow_up', 20) + '已进入竖屏全屏 · 上滑恢复弹幕栏</div>') if hint else ''
    body = backdrop() + pfs_fly() + top + bot + '<div class="lock">' + mr('lock_open', 28) + '</div>' + eh + (dialog or '')
    return page(393, 852, 3, body, syn=112)


def pfs4(n=False, menu=False, dialog=None, hint=True, controls=True, mode='ambient', extra=''):
    if not controls:
        return page(393, 852, 3, backdrop(mode) + pfs_fly(170, 700) + extra, syn=112)
    T = (lambda k, tag=None: (f' data-n="{k}"' + (f' data-tag="{tag}"' if tag else '')) if n else '')
    r1 = ('<div class="r1">' + ib(mi('arrow_back'), N(1, n)) + f'<div class="t4">{TITLE}</div>'
          '<div class="vfol"' + T(3, 'chg') + '>' + rx('eb7b') + '已关注</div>'
          '<div class="ib vic"' + T(4, 'add') + '><span class="vring"><i></i></span></div>'
          '<div class="ib vic"' + T(5, 'add') + '>' + rx('ea42') + '</div></div>')
    r2 = ('<div class="r2"><div class="time">21:36</div><div class="bat" style="margin:0 10px">76</div><div style="flex:1"></div>'
          + ib(mr('swap_horiz'), N(21, n), tag='chg' if n else None, at='bl') + ib(rx('ee05', 21), N(6, n), at='bl') + ib(rx('f235', 21), N(7, n), at='bl') + ib(ci('e806'), N(8, n), at='bl') + '</div>')
    ra = ('<div class="rw"><div class="comp"' + T(22) + '><span class="a">' + mr('auto_awesome', 18) + '</span>发送一条本地字幕<span class="s">' + mr('send', 18) + '</span></div>'
          '<div class="vchip"' + T(18, 'chg') + '>原画' + rx('ea4e', 18) + '</div><div class="vchip"' + T(19, 'chg') + '>线路1' + rx('ea4e', 18) + '</div></div>')
    disp = ib(rx('ea80', 22), N(23, n), 'ib vic' + (' open' if menu else ''), 'chg' if n else None)
    rb = ('<div class="rw">' + ib(mr('pause', 28), N(9, n)) + ib(mr('refresh'), N(10, n), tag='add' if n else None)
          + ib('<span class="dmk open"></span>', N(11, n)) + ib('<span class="dmk set"></span>', N(12, n)) + '<div style="flex:1"></div>'
          + disp + ib(mr('screen_rotation_alt', 21), N(13, n)) + ib(mr('fullscreen_exit', 26), N(14, n)) + '</div>')
    eh = ('<div class="ehint" style="bottom:124px">' + mr('keyboard_arrow_up', 20) + '已进入竖屏全屏 · 上滑恢复弹幕栏</div>') if hint else ''
    mn = ''
    if menu:
        items = [('完整画面', '完整保留直播内容，空白区域保持纯色', False), ('沉浸背景（推荐）', '完整保留画面，以封面模糊延展填充空白区域', True),
                 ('平衡填充', '最多轻微放大 8%，剩余空白使用沉浸背景', False), ('铺满裁剪', '铺满整个屏幕，可能裁掉左右部分内容', False)]
        mn = ('<div class="menu mm" style="left:12px;bottom:64px;width:330px"><div class="mh">竖屏全屏画面模式</div>'
              + ''.join(f'<div class="it2{" on" if on else ""}"><div class="x"><div class="a">{a}</div><div class="b">{b}</div></div>'
                        + (rx('eb7b') if on else '') + '</div>' for a, b, on in items) + '</div>')
    body = (backdrop(mode) + pfs_fly() + f'<div class="ptop">{r1}{r2}</div><div class="pbot">{ra}{rb}</div>'
            + '<div class="lock"' + T(24) + '>' + mr('lock_open', 28) + '</div>' + eh + mn + (dialog or '') + extra)
    return page(393, 852, 3, body, syn=112)


DM3 = ('<div class="scrim"></div><div class="dwrap"><div class="dlg3"><div class="dt">竖屏全屏画面模式</div><div style="padding-top:8px">'
       + ''.join(f'<div class="op"><span class="mr{" on" if on else ""}">{ic}</span><div>{a}<small>{b}</small></div></div>' for ic, on, a, b in [
           ('crop_free', False, '完整画面', '完整保留直播内容，空白区域保持纯色'),
           ('radio_button_checked', True, '沉浸背景（推荐）', '完整保留画面，以封面模糊延展填充空白区域'),
           ('fit_screen', False, '平衡填充', '最多轻微放大 8%，剩余空白使用沉浸背景'),
           ('fullscreen', False, '铺满裁剪', '铺满整个屏幕，可能裁掉左右部分内容')])
       + '</div><div class="act">取消</div></div></div>')
OR3 = ('<div class="scrim"></div><div class="dwrap"><div class="dlg3"><div class="dt">本直播间画面方向</div><div style="padding-top:8px">'
       '<div class="op" style="align-items:center"><span class="mr on">radio_button_checked</span><div>自动识别</div></div>'
       '<div class="op" style="align-items:center"><span class="mr">radio_button_unchecked</span><div>强制竖屏</div></div>'
       '<div class="op" style="align-items:center"><span class="mr">radio_button_unchecked</span><div>强制横屏</div></div>'
       '<hr style="margin-top:8px"><div class="sw3"><div class="x"><div class="a">记住单个直播间方向</div><div class="b">在播放器中手动指定方向后，下次进入同一直播间继续使用</div></div><span class="sw on"></span></div>'
       '</div><div class="act">取消</div></div></div>')
OR4 = ('<div class="scrim"></div><div class="dwrap" style="padding:0 32px"><div class="dlg4"><div class="dt">本直播间画面方向</div>'
       + ''.join(f'<div class="op{" on" if on else ""}"><div class="x"><div class="a">{a}</div><div class="b">{b}</div></div>' + (rx('eb7b') if on else '') + '</div>'
                 for a, b, on in [('自动识别', '按画面的实际尺寸判断是竖屏还是横屏直播', True),
                                  ('强制竖屏', '当作竖屏直播：画面加高、下面是可拖的面板，能进竖屏全屏', False),
                                  ('强制横屏', '当作普通横屏直播：16:9 画面，全屏时转成横屏', False)])
       + '<hr style="margin:6px 0"><div class="swr"><div class="x"><div class="a">记住单个直播间方向</div><div class="b">在播放器中手动指定方向后，下次进入同一直播间继续使用</div></div><span class="sw on"></span></div>'
       '<div class="act"><span>关闭</span></div></div></div>')

ZONES = ('<div class="zone" style="left:8px;top:120px;width:118px;height:600px"><span>上下滑<br>调亮度</span></div>'
         '<div class="zone" style="left:137px;top:120px;width:119px;height:600px;border-color:#7CE0A3"><span>上滑下一个<br>下滑上一个</span></div>'
         '<div class="zone" style="left:267px;top:120px;width:118px;height:600px"><span>上下滑<br>调音量</span></div>'
         '<div class="zone" style="left:8px;top:752px;width:377px;height:88px"><span>从这里上滑：回到弹幕面板</span></div>')
SWIPE = ('<div class="slide" style="top:-300px">' + backdrop() + '</div>'
         '<div class="slide" style="top:552px"><div class="nxt"></div><div style="position:absolute;inset:0;background:rgba(0,0,0,.2)"></div>'
         f'<div class="ncard"><span class="av" style="background-image:url({NEXT})"></span><div><b>小舟</b><small>抖音 · 户外 · 松手换到这个直播间</small></div></div></div>')


# ---------------------------------------------------------------- landscape fullscreen of a portrait stream (852x393)
def land(kind):
    w, h = 852, 393
    pw = round(h * 9 / 16)
    bg = (f'<div class="ambf"></div><div class="amb"></div><div class="veil"></div>'
          f'<div class="pvl" style="left:{(w - pw) / 2:.0f}px;width:{pw}px"></div>')
    dm = ''.join(f'<div class="dm" style="left:{x * w:.0f}px;top:{y * h:.0f}px">{t}</div>' for x, y, t in FLYLAND)
    lock = '<div class="lock">' + mr('lock_open', 28) + '</div>'
    if kind == 'v3':
        top = ('<div class="b3t">' + ib(mi('arrow_back'), cls='ib w') + '<div class="t13">21:36</div><div class="bat">76</div>'
               f'<div class="t3">{TITLE}</div><div class="swap">' + mr('swap_horiz') + '</div>'
               + ib(rx('ee05', 21), cls='ib w') + ib(rx('f235', 21), cls='ib w') + ib(ci('e806'), cls='ib w') + '</div>')
        left = (ib(mr('pause', 28), cls='ib w') + ib(mr('refresh'), cls='ib w') + '<div class="pill">' + mr('check', 15) + '已关注</div>'
                + ib('<span class="dmk open"></span>', cls='ib w') + ib('<span class="dmk set"></span>', cls='ib w'))
        right = ('<div class="sel3" style="margin:0 3px">' + mr('tune', 17) + '原画 · 线路1</div>' + ib(mr('screen_rotation_alt', 21), cls='ib w')
                 + '<div class="fit">默认比例</div>' + ib(mr('fullscreen_exit', 26), cls='ib w'))
        comp = '<div class="comp3l"><span class="a">' + mr('auto_awesome', 18) + '</span>发送一条本地字幕<span class="s">' + mr('send', 18) + '</span></div>'
        bot = f'<div class="b3b" style="padding:0 16px"><div class="g">{left}</div><div class="mid">{comp}</div><div class="g">{right}</div></div>'
    else:
        top = ('<div class="vtop">' + ib(mi('arrow_back')) + '<div class="time" style="margin:14px 6px 0 2px">21:36</div><div class="bat" style="margin-top:16px">76</div>'
               f'<div class="title">{TITLE}</div>' + ib(mr('swap_horiz')) + ib(rx('ee05', 21)) + ib(rx('f235', 21)) + ib(ci('e806'))
               + '<div class="ib vic"><span class="vring"><i></i></span></div>' + ib(rx('ea42')) + '</div>')
        left = (ib(mr('pause', 28)) + ib(mr('refresh')) + '<div class="vfol">' + rx('eb7b') + '已关注</div>'
                + ib('<span class="dmk open"></span>') + ib('<span class="dmk set"></span>'))
        right = ('<div class="vchip">原画' + rx('ea4e', 18) + '</div><div class="vchip">线路1' + rx('ea4e', 18) + '</div>'
                 + ib(mr('screen_rotation_alt', 21)) + ib(rx('ea80', 22)) + ib(mr('fullscreen_exit', 26)))
        comp = '<div class="comp" style="max-width:420px;margin:0"><span class="a">' + mr('auto_awesome', 18) + '</span>发送一条本地字幕<span class="s">' + mr('send', 18) + '</span></div>'
        bot = f'<div class="vbot" style="padding:0 12px 4px"><div class="g">{left}</div><div class="mid">{comp}</div><div class="g">{right}</div></div>'
    return page(w, h, 2, bg + dm + top + bot + lock, frame='fsb')


# ---------------------------------------------------------------- wide room (1280x800)
CHATW = [('#C2255C', '星河长明', '晚上好～'), ('#000', '一只小熊', '主播今天好好看'), ('#1971C2', '夜猫子', '聊聊最近看的书吧'),
         ('#000', '路过的风', '来了来了'), ('#2F9E44', '清欢', '晚安电台打卡第 30 天'), ('#000', '小林同学', '声音好温柔'),
         ('#000', '橘子汽水', '今天也辛苦啦'), ('#C2410C', 'Aki', '想听你唱一首'), ('#000', '不吃香菜', '前排支持！'),
         ('#000', '月亮邮差', '这个灯光好舒服'), ('#000', '风吹麦浪', '晚安～')]


def wide(kind):
    w, h, cw = 1280, 800, 400
    sw, shh = w - cw, h - 56
    if kind == 'v3':
        bh = round(sw * 9 / 16)
        pw = round(bh * 9 / 16)
        hdr = ('<div class="appbar"><div class="back">' + mi('arrow_back') + f'</div><span class="av" style="background-image:url({AV})"></span>'
               f'<div class="tt" style="margin-left:8px"><div class="v3n">{NAME}</div><div class="v3n">{PLAT3}</div></div>'
               '<div class="v3fol">已关注</div><div class="v3rec">' + rx('f05a', 14) + '录制</div>' + ib(rx('ea42'), cls='ib') + '<div style="width:4px"></div></div>')
        left = (ib(mr('pause', 28), cls='ib w') + ib(mr('refresh'), cls='ib w') + '<div class="pill" style="font-size:14px">' + mr('check', 15) + '已关注</div>'
                + ib('<span class="dmk open"></span>', cls='ib w') + ib('<span class="dmk set"></span>', cls='ib w'))
        right = ('<div class="fit">默认比例</div>' + ib(mr('volume_up', 22), cls='ib w') + ib('<span class="mr" style="font-size:26px;transform:rotate(90deg)">unfold_more</span>', cls='ib w')
                 + ib(mr('fullscreen', 26), cls='ib w'))
        box = (f'<div style="position:absolute;left:0;right:0;top:{(shh - bh) / 2:.0f}px;height:{bh}px;background:#000">'
               f'<div class="pvl" style="left:{(sw - pw) / 2:.0f}px;width:{pw}px"></div>'
               f'<div class="dm" style="left:{sw * 0.44:.0f}px;top:90px">前排支持！</div><div class="dm" style="left:{sw * 0.30:.0f}px;top:150px">晚上好～</div>'
               '<div class="b3t"><div class="t3">' + TITLE + '</div>' + ib(rx('ee05', 21), cls='ib w') + ib(ci('e806'), cls='ib w') + '</div>'
               f'<div class="b3b"><div class="g">{left}</div><div style="flex:1"></div><div class="g">{right}</div></div></div>')
        items = ''.join(f'<div class="it"><i style="background:{c}"></i><p><b>{u}: </b>{t}</p></div>' for c, u, t in CHATW[:8])
        col = ('<div class="res" style="border-bottom:1px solid var(--ov)"><div class="aud">' + mr('people_alt', 14) + '在线 3.6万</div><div class="sel">原画</div><div class="line">线路1</div></div>'
               + tabs(v3=True) + f'<div class="lst">{items}</div>')
        body = hdr + f'<div class="body"><div class="stage">{box}</div><div class="col" style="width:{cw}px">{col}</div></div>'
    else:
        pw = round(shh * 9 / 16)
        hdr = header4().replace('style="position:relative;z-index:12"', '')
        left = ib(mr('pause', 28)) + ib(mr('refresh')) + ib('<span class="dmk open"></span>') + ib('<span class="dmk set"></span>')
        right = ('<div class="vvol"><span class="mr" style="font-size:22px">volume_up</span><div class="t"><i></i><u></u></div></div>'
                 + ib(mr('vertical_split', 24)) + ib('<span class="mr" style="font-size:26px;transform:rotate(90deg)">unfold_more</span>') + ib(mr('fullscreen', 26)))
        stage = ('<div class="ambf"></div><div class="amb"></div><div class="veil"></div>'
                 f'<div class="pvl" style="left:{(sw - pw) / 2:.0f}px;width:{pw}px"></div>'
                 f'<div class="dm" style="left:{sw * 0.44:.0f}px;top:110px">前排支持！</div><div class="dm" style="left:{sw * 0.30:.0f}px;top:170px">晚上好～</div>'
                 '<div class="vtop"><div class="title">' + TITLE + '</div>' + ib(rx('ee05', 21)) + ib(ci('e806')) + '</div>'
                 f'<div class="vbot"><div class="g">{left}</div><div style="flex:1"></div><div class="g">{right}</div></div>')
        rows = ''.join(f'<div class="row"><span class="u" style="{"" if c == "#000" else "color:" + c}">{u}：</span>{t}</div>' for c, u, t in CHATW)
        col = info4() + tabs() + f'<div class="lst"><div class="sys">弹幕服务器连接正常</div>{rows}</div>'
        body = (hdr + f'<div class="body" style="position:relative"><div class="stage">{stage}</div><div class="col" style="width:{cw}px">{col}</div>'
                f'<div class="collapse" style="right:{cw}px">' + mr('chevron_right', 20) + '</div></div>')
    return page(w, h, 1.5, body, frame='win')


OUT = {
    'v3-stream-low': room3('low'), 'v3-stream-mid': room3('mid'), 'v3-stream-high': room3('high'),
    'v4-stream-low': room4('low', controls=False), 'v4-stream-mid': room4('mid', n=True), 'v4-stream-high': room4('high'),
    'v3-pfs': pfs3(), 'v4-pfs': pfs4(n=True),
    'v3-pfs-mode': pfs3(dialog=DM3, hint=False), 'v4-pfs-mode': pfs4(menu=True, hint=False),
    'v3-pfs-orientation': pfs3(dialog=OR3, hint=False), 'v4-pfs-orientation': pfs4(dialog=OR4, hint=False),
    'v4-mode-complete': pfs4(controls=False, mode='complete'), 'v4-mode-ambient': pfs4(controls=False, mode='ambient'),
    'v4-mode-balanced': pfs4(controls=False, mode='balanced'), 'v4-mode-cover': pfs4(controls=False, mode='cover'),
    'v4-swipe-zones': pfs4(controls=False, extra=ZONES), 'v4-swipe': page(393, 852, 3, SWIPE, syn=112),
    'v3-land': land('v3'), 'v4-land': land('v4'),
    'v3-wide': wide('v3'), 'v4-wide': wide('v4'),
}
for name, html in OUT.items():
    open(os.path.join(HERE, name + '.html'), 'w', encoding='utf-8').write(html)
print(len(OUT), 'pages')
