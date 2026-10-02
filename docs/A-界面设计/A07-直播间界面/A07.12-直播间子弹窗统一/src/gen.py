"""U.2n the live room's other pop-ups (task B07): the sleep timer, the room
volume, casting, the stream address, the picture fit and orientation, the
unfollow confirmation, the long-pressed danmaku and the toast in fullscreen.
Writes HTML next to this file. Then:
    python3 docs/ui/compare/U.2n/src/gen.py && python3 tools/ui/mock/render.py docs/ui/compare/U.2n/src/ --annotate

The room around the pop-ups comes from U.2m's generator (same room, same
bars). Texts from apps/pure_live/assets/translations/zh.json; 4.0.0 (as
released) from apps/pure_live/lib/features/live_play/dialogs/*.dart, whose
forms are 3.x's (centred dialogs, the long press a bottom sheet):
  dialogs/room_dialogs.dart     _SleepTimerDialog (3.x RoomTimerDialog), _VolumeDialog
  dialogs/stream_dialogs.dart   _StreamPickerDialog (3.x KnownRoomLinkDialog), CastDialog (3.x LiveDlnaPage)
  dialogs/player_dialogs.dart   _ChoiceDialog (画面比例), _OrientationDialog (本直播间画面方向)
  buttons/follow_button.dart    AlertDialog 取消关注 / 确认
  danmaku/chat_list.dart        showChatMessageActions (bottom sheet), _KeywordDialog
"""
import importlib.util
import os

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location('u2m', os.path.join(HERE, '..', '..', 'U.2m', 'src', 'gen.py'))
u2m = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(u2m)

mr, mi, rx, ib, N = u2m.mr, u2m.mi, u2m.rx, u2m.ib, u2m.N
STATUS, SYN, GEST = u2m.STATUS, u2m.SYN, u2m.GEST
FS_EXTRA = u2m.FS_EXTRA

CSS = '''
/* panel (U.1d / U.2f: 52 header, 17/600, ✕ 48) */
.pnl{display:flex;flex-direction:column;background:var(--surface);color:var(--on);overflow:hidden}
.pnl .hd{height:52px;display:flex;align-items:center;padding:0 4px 0 20px;flex:none}
.pnl .hd.bk{padding-left:4px}
.pnl .hd .t{font-size:17px;font-weight:600;flex:1;min-width:0;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.pnl .hd .b{width:48px;height:48px;display:grid;place-items:center;color:var(--onv);flex:none}
.pnl .hd .lk{font-size:14px;color:var(--onv);padding:0 6px;white-space:nowrap}
.pnl .bd{flex:1;min-height:0;overflow:hidden}
.pnl .cap{padding:12px 20px 6px;font-size:13px;font-weight:600;color:var(--primary)}
.pnl .hint{padding:6px 20px 0;font-size:13px;line-height:1.5;color:var(--onv)}
.swr2{display:flex;align-items:center;gap:14px;padding:8px 16px 8px 20px;min-height:64px}
.swr2 .x{flex:1;min-width:0}.swr2 .a{font-size:15px}.swr2 .b{font-size:13px;color:var(--onv);margin-top:2px}
.swr2 .b.on{color:var(--primary);font-weight:600}
.chips{display:flex;flex-wrap:wrap;gap:8px;padding:4px 20px 8px}
.chips>span{height:34px;padding:0 12px;border-radius:8px;box-shadow:inset 0 0 0 1px var(--ov);font-size:14px;display:inline-flex;align-items:center;gap:4px}
.chips>span.on{background:var(--sc);box-shadow:none;color:var(--osc);font-weight:600}
.chips.dis>span{opacity:.38}
.fdr{display:flex;align-items:flex-start;gap:8px;padding:10px 20px 0}
.fd2{position:relative;flex:1;height:48px;border-radius:12px;box-shadow:inset 0 0 0 1px var(--outline);display:flex;align-items:center;padding:0 14px;font-size:15px}
.fd2 .lbl{position:absolute;left:10px;top:-9px;padding:0 4px;background:var(--surface);font-size:12px;color:var(--onv)}
.fd2 .sfx{margin-left:auto;color:var(--onv)}
.fbtn{height:48px;padding:0 20px;border-radius:24px;background:var(--primary);color:var(--onPrimary);font-size:14px;font-weight:600;display:flex;align-items:center;flex:none}
.fh2{padding:4px 34px 0;font-size:12px;color:var(--onv)}
.vol{display:flex;align-items:center;gap:6px;padding:8px 16px 4px 8px}
.vol .ib{color:var(--onv)}
.vol .trk{flex:1;height:4px;border-radius:2px;background:color-mix(in srgb,var(--primary) 22%,transparent);position:relative;margin:0 8px}
.vol .trk i{position:absolute;left:0;top:0;bottom:0;border-radius:2px;background:var(--primary)}
.vol .trk b{position:absolute;top:50%;width:20px;height:20px;margin:-10px 0 0 -10px;border-radius:10px;background:var(--primary)}
.vol .pc{width:48px;text-align:right;font-size:15px;font-weight:600;font-feature-settings:'tnum'}
.opr{display:flex;align-items:center;min-height:48px;padding:8px 20px 8px 24px;gap:12px}
.opr .x{flex:1;min-width:0}.opr .a{font-size:15px}.opr .b{font-size:13px;color:var(--onv);margin-top:2px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.opr.on .a{color:var(--primary);font-weight:600}.opr .ck{color:var(--primary)}
.opr .lead{color:var(--onv)}
.opr .spin{width:20px;height:20px;border-radius:10px;border:2.5px solid var(--primary);border-right-color:transparent}
.prog{height:4px;background:color-mix(in srgb,var(--primary) 22%,transparent);position:relative;overflow:hidden;flex:none}
.prog i{position:absolute;left:20%;width:35%;top:0;bottom:0;background:var(--primary)}
.msgc{margin:4px 16px 8px;padding:12px 16px;border-radius:12px;background:var(--scl);box-shadow:inset 0 0 0 1px var(--ov);font-size:15px;line-height:1.5}
.msgc .u{color:#C2255C}
.lt2{display:flex;align-items:center;gap:16px;min-height:56px;padding:6px 20px}
.lt2 .mr{color:var(--onv)}.lt2 .x{flex:1}.lt2 .a{font-size:15px}.lt2 .b{font-size:13px;color:var(--onv)}
/* small menu (U.1d) */
.mn4{position:absolute;z-index:22;background:var(--schh);border-radius:8px;padding:8px 0;box-shadow:0 4px 14px rgba(0,0,0,.25);min-width:128px;color:var(--on)}
.mn4 .it{min-height:48px;display:flex;align-items:center;gap:12px;padding:0 14px 0 16px;font-size:14px;white-space:nowrap}
.mn4 .it>.mr,.mn4 .it>.rx{color:var(--onv);font-size:24px}
.mn4 .it .tx{flex:1}
.mn4 .it .d{display:block;font-size:12px;color:var(--onv);font-weight:400;margin-top:1px}
.mn4 .it.two{padding-top:7px;padding-bottom:7px}
.mn4 .it.on{color:var(--primary);font-weight:600}
.mn4 .it.dng,.mn4 .it.dng>.mr{color:var(--error)}
.mn4 .hd{padding:6px 16px 8px;font-size:13px;font-weight:600;color:var(--onv);white-space:nowrap}
.mn4 .msep{height:1px;background:var(--ov);margin:6px 0}
.mn4 .swi{display:flex;align-items:center;gap:12px;padding:6px 14px 6px 16px;white-space:normal}
.mn4 .swi .x{flex:1;font-size:14px}.mn4 .swi .x small{display:block;font-size:12px;color:var(--onv)}
.swm{width:44px;height:26px;border-radius:13px;position:relative;flex:none;background:var(--primary)}
.swm::after{content:'';position:absolute;right:3px;top:3px;width:20px;height:20px;border-radius:10px;background:var(--onPrimary)}
.swm.off{background:var(--schh);box-shadow:inset 0 0 0 2px var(--outline)}.swm.off::after{left:5px;right:auto;top:5px;width:16px;height:16px;background:var(--outline)}
/* dialogs as released */
.scr{position:absolute;inset:0;background:rgba(0,0,0,.54);z-index:20}
.dg{position:absolute;z-index:21;background:var(--sch);border-radius:24px;color:var(--on);padding:24px 0 12px;overflow:hidden}
.dg .t{font-size:20px;font-weight:600;padding:0 24px 12px}
.dg .ac{display:flex;justify-content:flex-end;gap:8px;padding:8px 16px 0}
.dg .tb{height:40px;padding:0 12px;display:flex;align-items:center;color:var(--primary);font-size:14px;font-weight:500}
.dg .fb{height:40px;padding:0 24px;border-radius:20px;display:flex;align-items:center;background:var(--primary);color:var(--onPrimary);font-size:14px;font-weight:500}
.dg .li{height:52px;display:flex;align-items:center;padding:0 24px;font-size:16px}
.dg .li span{flex:1}
.toast2{display:flex;align-items:center;min-height:48px;padding:6px 6px 6px 16px;border-radius:8px;background:#2E3135;color:#EFF0F7;font-size:14px;box-shadow:0 3px 8px rgba(0,0,0,.25);gap:4px}
.toast2 .x{flex:1;padding:6px 0}.toast2 .ac{height:40px;padding:0 12px;display:flex;align-items:center;color:#A0CAFD;font-weight:600}
.lbl2{position:absolute;z-index:50;font:600 12px 'Noto Sans SC';color:#fff;background:#2F5FA8;padding:3px 8px;border-radius:6px}
.press{position:absolute;z-index:6;border-radius:8px;background:rgba(54,97,142,.14)}
'''

TOP = 36 + 56 + 221  # the portrait room: status, app bar, 16:9 picture


def page(w, h, scale, body, frame='ph', extra=''):
    return u2m.page(w, h, scale, body, frame=frame, extra=CSS + extra)


def header(title, back=False, actions='', n_close=None, n_back=None):
    lead = (f'<span class="b"{N(n_back, "tc", "add")}>' + mr('arrow_back') + '</span>') if back else ''
    return (f'<div class="hd{" bk" if back else ""}">{lead}<span class="t">{title}</span>{actions}'
            f'<span class="b"{N(n_close, "tc", "keep")}>' + mr('close') + '</span></div>')


def pnl(title, body, back=False, actions='', n=False, n_back=None, line=False):
    return (f'<div class="pnl" style="height:100%">{header(title, back, actions, 9 if n else None, n_back)}'
            + ('<div style="height:1px;background:var(--ov);flex:none"></div>' if line else '') + f'<div class="bd">{body}</div></div>')


# ---------------------------------------------------------------------
# panel contents
# ---------------------------------------------------------------------
PRESETS = [15, 30, 45, 60, 90, 120, 240, 480]


def timer_body(n=False, on=True, chosen=30, left='28 分钟后暂停（22:04）'):
    nn = (lambda k: k) if n else (lambda k: None)
    sub = left if on else '到时暂停当前直播并结束后台音频，不关闭应用'
    chips = ''.join(f'<span class="{"on" if on and p == chosen else ""}"{N(nn(2), "tc", "chg") if p == 15 else ""}>'
                    + (mr('check', 16) if on and p == chosen else '') + f'{p} 分钟</span>' for p in PRESETS)
    return (f'<div class="swr2"{N(nn(1), "tr", "chg")}><div class="x"><div class="a">启用当前直播间定时停止</div>'
            f'<div class="b{" on" if on else ""}">{sub}</div></div><span class="swm{"" if on else " off"}"></span></div>'
            '<div class="cap">停止前播放时长</div>'
            f'<div class="chips">{chips}</div>'
            f'<div class="fdr"><div class="fd2"{N(nn(3), "tl", "keep")}><span class="lbl">自定义</span><span>{chosen}</span><span class="sfx">分钟</span></div>'
            f'<span class="fbtn"{N(nn(4), "tc", "chg")}>开始</span></div>'
            '<div class="fh2">输入 1 分钟至 365 天之间的分钟数</div>')


def volume_body(value=30, n=False, phone=True, muted=False):
    nn = (lambda k: k) if n else (lambda k: None)
    icon = 'volume_off' if muted else ('volume_down' if value < 50 else 'volume_up')
    v = 0 if muted else value
    hint = ('调的是手机的媒体音量：和画面右侧上下滑、音量键是同一个音量' if phone
            else '只对这个直播间生效，下次进来还是这个音量')
    return (f'<div class="vol"><span class="ib"{N(nn(1), "tc", "chg")}>' + mr(icon) + '</span>'
            f'<div class="trk"{N(nn(2), "tc", "chg")}><i style="width:{v}%"></i><b style="left:{v}%"></b></div>'
            f'<span class="pc">{v}%</span></div>'
            f'<div class="hint">{hint}</div>'
            + ('<div class="hint" style="padding-top:10px">静音后再点 ' + mr('volume_off', 16, 'vertical-align:-3px') + ' 回到静音前的音量</div>' if muted else ''))


QUALITIES = ['原画', '蓝光 4M', '超清', '高清', '流畅']


def quality_body(current=0, n=False, use='copy'):
    nn = (lambda k: k) if n else (lambda k: None)
    rows = ''.join(f'<div class="opr{" on" if i == current else ""}"{N(nn(1), "tr", "chg") if i == 0 else ""}><div class="x"><div class="a">{q}</div>'
                   + ('<div class="b">正在播放</div>' if i == current else '') + '</div>'
                   + (mr('check', 22, 'color:var(--primary)') if i == current else '') + '</div>' for i, q in enumerate(QUALITIES))
    return '<div class="cap">选择清晰度</div>' + rows


LINES = ['https://d1--cn-gotcha04.bilivideo.com/live-bvc/482910/live_1050_bluray.flv?expires=…',
         'https://cn-hbwh-cm-01-12.bilivideo.com/live-bvc/482910/live_1050_bluray.flv?expires=…',
         'https://ov-gotcha07.bilivideo.com/live-bvc/482910/live_1050_bluray.m3u8?expires=…']


def line_body(current=0, n=False):
    nn = (lambda k: k) if n else (lambda k: None)
    rows = ''.join(f'<div class="opr{" on" if i == current else ""}"{N(nn(6), "tr", "chg") if i == 1 else ""}><div class="x"><div class="a">线路{i + 1}'
                   + ('<span style="font-size:13px;font-weight:400;margin-left:8px">正在播放</span>' if i == current else '') + f'</div><div class="b">{u}</div></div>'
                   + (mr('check', 22, 'color:var(--primary)') if i == current else '') + '</div>' for i, u in enumerate(LINES))
    return '<div class="cap">原画 · 选择线路</div>' + rows


DEVICES = [('客厅电视', '192.168.1.23'), ('小米盒子 4S', '192.168.1.41'), ('书房投影', '192.168.1.57')]


def cast_body(state='ready', n=False):
    nn = (lambda k: k) if n else (lambda k: None)
    prog = '<div class="prog"><i></i></div>' if state == 'searching' else '<div style="height:4px"></div>'
    refresh = (f'<span class="b" style="width:48px;height:40px;display:grid;place-items:center;color:var(--onv);{"opacity:.38;" if state == "searching" else ""}"'
               f'{N(nn(7), "tc", "keep")}>' + mr('refresh') + '</span>')
    caption = f'<div style="display:flex;align-items:center;padding-right:4px"><div class="cap" style="flex:1">原画 · 线路1 · 投屏到</div>{refresh}</div>'
    if state == 'empty':
        return (prog + caption + '<div style="padding:24px 24px;text-align:center;color:var(--onv);font-size:14px;line-height:1.6">' + mr('tv_off', 40, 'opacity:.6') +
                '<div style="margin-top:8px;color:var(--on)">未发现DLNA设备</div><div style="font-size:13px">请让本设备与接收器保持在同一局域网。</div></div>')
    rows = []
    for i, (name, ip) in enumerate(DEVICES if state != 'searching' else DEVICES[:1]):
        cur = state == 'cast' and i == 0
        trail = ('<span class="spin"></span>' if state == 'casting' and i == 0 else (mr('check', 22, 'color:var(--primary)') if cur else ''))
        rows.append(f'<div class="opr{" on" if cur else ""}"{N(nn(8), "tr", "chg") if i == 0 else ""}><span class="lead">' + mr('tv', 22) + f'</span><div class="x"><div class="a">{name}</div><div class="b">{ip}</div></div>{trail}</div>')
    return prog + caption + ''.join(rows) + ('<div class="hint">正在搜索 DLNA 设备……</div>' if state == 'searching' else '')


def message_body(n=False):
    nn = (lambda k: k) if n else (lambda k: None)
    return ('<div class="msgc"><span class="u">夜猫子：</span>可以点《晴天》吗，前排支持！</div>'
            f'<div class="lt2"{N(nn(1), "tl", "keep")}>' + mr('content_copy', 22) + '<div class="x"><div class="a">复制</div></div></div>'
            f'<div class="lt2"{N(nn(2), "tl", "keep")}>' + mr('person_off', 22) + '<div class="x"><div class="a">屏蔽此用户</div><div class="b">夜猫子 的弹幕都不再显示</div></div></div>'
            f'<div class="lt2"{N(nn(3), "tl", "keep")}>' + mr('block', 22) + '<div class="x"><div class="a">屏蔽关键词…</div><div class="b">输入一个词，含这个词的弹幕都不再显示</div></div></div>')


# ---------------------------------------------------------------------
# where a panel goes
# ---------------------------------------------------------------------
def portrait(inner, n_menu=None):
    under = f'<div class="under" style="top:{TOP}px;padding-bottom:16px;display:flex;flex-direction:column">{inner}</div>'
    return page(393, 852, 3, u2m.v4_room(under, n=n_menu))


def landscape(inner, bars=True, extra_body=''):
    side = f'<div class="side" style="border-radius:16px 0 0 16px;display:flex;flex-direction:column">{inner}</div>'
    return page(852, 393, 2, SYN + (u2m.v4_fs_bars() if bars else '') + side + extra_body, frame='fs', extra=FS_EXTRA)


def portrait_fullscreen(inner):
    h = 852 * .6
    sheet = f'<div class="under" style="height:{h:.0f}px;padding-bottom:16px;border-radius:16px 16px 0 0;display:flex;flex-direction:column">{inner}</div>'
    body = ('<div style="position:absolute;inset:0;background:url(.cache/img/319.jpg) center/cover"></div>'
            '<div class="vtop" style="height:120px"><div style="display:flex;align-items:center;width:100%;padding-top:36px">' + ib(mi('arrow_back'), cls='ib vic')
            + '<div class="title" style="padding-top:0">晚风 · 深夜电台</div>' + ib(rx('f235'), cls='ib vic') + ib(rx('ea42'), cls='ib vic') + '</div></div>'
            + sheet + SYN + GEST)
    return page(393, 852, 3, body, extra='.ph{background:#000}')


def tablet(inner):
    w, h = 1280, 800
    hdr = ('<div class="appbar"><div class="back">' + mi('arrow_back') + '</div><span class="av" style="background-image:url(.cache/img/65.jpg)"></span>'
           '<div class="tt"><div class="n">晚风</div><div class="s">哔哩哔哩 · 唱见电台</div></div>'
           '<div class="fol on">' + rx('eb7b') + '已关注</div><div class="recbtn"><span class="ring"><i></i></span></div>' + ib(rx('ea42')) + '<div style="width:4px"></div></div>')
    stage = ('<div style="flex:1;position:relative;background:#000;display:flex;align-items:center;overflow:hidden"><div style="width:100%;aspect-ratio:16/9;background:#000 url(.cache/img/158.jpg) center 55%/cover"></div>'
             '<div class="vtop"><div class="title">' + u2m.TITLE + '</div>' + ib(rx('f235'), cls='ib vic') + '</div></div>')
    right = (f'<div style="width:400px;border-left:1px solid var(--ov);position:relative;background:var(--surface)">'
             f'<div class="pnl" style="position:absolute;top:0;right:0;bottom:0;width:360px;box-shadow:-6px 0 20px rgba(0,0,0,.18)">{inner}</div></div>')
    body = STATUS + hdr + f'<div style="flex:1;display:flex;min-height:0">{stage}{right}</div>'
    return page(w, h, 1.5, body, frame='win', extra='.win{display:flex;flex-direction:column}')


# ---------------------------------------------------------------------
# 4.0.0 (the forms are 3.x's)
# ---------------------------------------------------------------------
def now_timer_landscape():
    chips = ''.join(f'<span style="height:32px;padding:0 10px;border-radius:8px;box-shadow:inset 0 0 0 1px var(--ov);font-size:13px;display:inline-flex;align-items:center">{p} 分钟</span>' for p in PRESETS)
    dlg = ('<div class="dg" style="left:186px;top:12px;width:480px;height:369px">'
           '<div class="t">当前直播间播放定时器</div>'
           '<div class="swr2" style="padding:0 24px;min-height:56px"><div class="x"><div class="a">启用当前直播间定时停止</div><div class="b">到时暂停当前直播并结束后台音频，不关闭应用</div></div><span class="swm off"></span></div>'
           f'<div style="display:flex;flex-wrap:wrap;gap:8px;padding:8px 24px">{chips}</div>'
           '<div style="padding:8px 24px 0"><div class="fd2" style="opacity:.5"><span class="lbl" style="background:var(--sch)">停止前播放时长</span>60<span class="sfx">分钟</span></div></div>'
           '<div class="ac"><span class="tb">取消</span><span class="fb">确认</span></div></div>')
    return page(852, 393, 2, SYN + u2m.v4_fs_bars() + '<div class="scr"></div>' + dlg, frame='fs', extra=FS_EXTRA)


def now_link_portrait():
    rows = ''.join(f'<div class="li"><span>{q}</span>' + (mr('check', 22, 'color:var(--primary)') if i == 0 else '') + '</div>' for i, q in enumerate(QUALITIES))
    dlg = ('<div class="dg" style="left:16px;right:16px;top:250px">'
           '<div class="t">获取直链</div><div style="padding:0 24px 8px;font-size:14px;font-weight:500">选择清晰度</div>' + rows
           + '<div class="ac"><span class="tb">取消</span></div></div>')
    return page(393, 852, 3, u2m.v4_room('<div class="scr"></div>' + dlg))


def now_fit_portrait():
    names = ['默认比例', '居中裁剪', '填充屏幕', '适应高度', '适应宽度', '等比缩小']
    rows = ''.join(f'<div class="li"><span>{q}</span>' + (mr('check', 22, 'color:var(--primary)') if i == 0 else '') + '</div>' for i, q in enumerate(names))
    dlg = ('<div class="dg" style="left:16px;right:16px;top:200px">'
           '<div class="t">画面比例</div>' + rows + '<div class="ac"><span class="tb">取消</span></div></div>')
    return page(393, 852, 3, u2m.v4_room('<div class="scr"></div>' + dlg))


# ---------------------------------------------------------------------
# the new design
# ---------------------------------------------------------------------
def v4_timer_portrait(n=True):
    return portrait(pnl('定时关闭', timer_body(n=n), n=n))


def v4_timer_landscape():
    return landscape(pnl('定时关闭', timer_body()))


def v4_volume_portrait(n=True):
    return portrait(pnl('房间音量', volume_body(n=n), n=n))


def v4_volume_landscape():
    return landscape(pnl('房间音量', volume_body()))


def v4_link_portrait_fullscreen():
    return portrait_fullscreen(pnl('获取直链', line_body(), back=True))


def v4_cast_tablet():
    return tablet(pnl('投屏', cast_body('cast'), back=True))


def v4_message_landscape():
    press = '<div class="dm" style="left:120px;top:150px;background:rgba(54,97,142,.55);border-radius:6px;padding:0 6px">可以点《晴天》吗，前排支持！</div>'
    return landscape(pnl('弹幕', message_body()), extra_body=press)


def v4_panels(n=True):
    """The pages of the stream and cast panels and the other states, 360 × 470 each."""
    w, h = 360, 470
    nn = (lambda k: k) if n else (lambda k: None)
    cells = [
        ('获取直链 · 清晰度', '当前清晰度主色加勾，写“正在播放”', pnl('获取直链', quality_body(n=n), n=False)),
        ('获取直链 · 线路', '左上 ← 回到清晰度；当前线路主色加勾；点一条复制并关闭', pnl('获取直链', line_body(n=n), back=True, n_back=nn(5))),
        ('投屏 · 设备', '← 回到线路；正在投的设备主色加勾；列表上方那行右边是刷新', pnl('投屏', cast_body('cast', n=n), back=True)),
        ('投屏 · 搜索中', '顶上一条进度；搜到一个列一个', pnl('投屏', cast_body('searching'), back=True)),
        ('投屏 · 正在投', '点了的设备转圈，投上后加勾', pnl('投屏', cast_body('casting'), back=True)),
        ('投屏 · 没找到', '原文案；点刷新再找一次', pnl('投屏', cast_body('empty'), back=True)),
        ('房间音量 · 静音后', '图标变成静音；再点回到静音前的音量（B-14）', pnl('房间音量', volume_body(muted=True))),
        ('定时关闭 · 关着', '点一个时长直接开始', pnl('定时关闭', timer_body(on=False))),
    ]
    o = ['<div style="display:flex;flex-wrap:wrap;gap:24px;padding:24px;background:var(--sch)">']
    for cap, sub, inner in cells:
        o.append(f'<div><div style="font-size:15px;font-weight:600;margin:0 0 2px 4px">{cap}</div><div style="font-size:12px;color:var(--onv);margin:0 0 8px 4px;width:{w}px">{sub}</div>'
                 f'<div style="width:{w}px;height:{h}px;border-radius:16px;overflow:hidden;box-shadow:0 2px 10px rgba(0,0,0,.12)">{inner}</div></div>')
    o.append('</div>')
    return page(1632, 1130, 1, ''.join(o), frame='win', extra='.win{height:auto}')


def menu_rows(n=False):
    nn = (lambda k: k) if n else (lambda k: None)
    groups = [
        [(mr('swap_horiz'), '切换直播间', None), (rx('f20f'), '定时关闭', '28 分钟后暂停'), (rx('f2a2'), '房间音量', None), (rx('ea80'), '画面比例', '默认比例')],
        [(rx('f235'), '投屏', None), (rx('eeaf'), '获取直链', None), (rx('f0fd'), '分享', None), (mr('open_in_new'), '在哔哩哔哩打开', None)],
        [(rx('f1b4'), '本地互动体验', None)],
    ]
    o = []
    for gi, g in enumerate(groups):
        if gi:
            o.append('<div class="msep"></div>')
        for icon, text, sub in g:
            mark = N(nn(1), 'tl', 'chg') if text == '定时关闭' else ''
            o.append(f'<div class="it{" two" if sub else ""}"{mark}>{icon}<span class="tx">{text}' + (f'<span class="d">{sub}</span>' if sub else '') + '</span></div>')
    return ''.join(o)


def v4_menu_portrait(n=True):
    menu = f'<div class="mn4" style="right:8px;top:90px;width:230px">{menu_rows(n)}</div>'
    return page(393, 852, 3, u2m.v4_room(menu))


FITS = ['默认比例', '居中裁剪', '填充屏幕', '适应高度', '适应宽度', '等比缩小']


def fit_menu(current=0, n=False):
    nn = (lambda k: k) if n else (lambda k: None)
    return ''.join(f'<div class="it{" on" if i == current else ""}"{N(nn(2), "tl", "chg") if i == 0 else ""}><span class="tx">{t}</span>'
                   + (mr('check', 18, 'color:var(--primary)') if i == current else '') + '</div>' for i, t in enumerate(FITS))


def v4_fit_portrait(n=True):
    btn = f'<div style="position:absolute;right:4px;top:36px;width:48px;height:56px;border-radius:24px;background:rgba(54,97,142,.12);z-index:22"{N(1 if n else None, "bl", "keep")}></div>'
    menu = f'<div class="mn4" style="right:8px;top:96px;width:168px">{fit_menu(n=n)}</div>'
    return page(393, 852, 3, u2m.v4_room(btn + menu))


ORIENT = [('自动识别', '按画面的实际尺寸判断是竖屏还是横屏直播'), ('强制竖屏', '当作竖屏直播：画面加高、下面是可拖的面板，能进竖屏全屏'),
          ('强制横屏', '当作普通横屏直播：16:9 画面，全屏时转成横屏')]


def orientation_menu(current=0, n=False):
    nn = (lambda k: k) if n else (lambda k: None)
    rows = ''.join(f'<div class="it two{" on" if i == current else ""}"{N(nn(2), "tl", "chg") if i == 1 else ""}><span class="tx">{a}<span class="d">{b}</span></span>'
                   + (mr('check', 18, 'color:var(--primary)') if i == current else '') + '</div>' for i, (a, b) in enumerate(ORIENT))
    return ('<div class="hd">本直播间画面方向</div>' + rows + '<div class="msep"></div>'
            f'<div class="swi"{N(nn(3), "tl", "keep")}><span class="x">记住单个直播间方向<small>下次进入同一直播间继续使用</small></span><span class="swm off"></span></div>')


def v4_orientation_landscape(n=True):
    menu = f'<div class="mn4" style="right:120px;bottom:60px;width:330px;white-space:normal">{orientation_menu(n=n)}</div>'
    btn = f'<div style="position:absolute;right:146px;bottom:4px;width:48px;height:48px;border-radius:24px;background:rgba(255,255,255,.2);z-index:22"{N(1 if n else None, "tc", "keep")}></div>'
    return page(852, 393, 2, SYN + u2m.v4_fs_bars() + btn + menu, frame='fs', extra=FS_EXTRA + '.mn4 .it{white-space:normal}')


def v4_unfollow_portrait(n=True):
    menu = ('<div class="mn4" style="right:96px;top:84px;width:200px">'
            '<div class="hd">晚风 · 哔哩哔哩</div>'
            f'<div class="it dng"{N(2 if n else None, "tl", "chg")}>' + mr('heart_broken') + '<span class="tx">取消关注</span></div></div>')
    btn = f'<div style="position:absolute;right:96px;top:46px;width:88px;height:36px;border-radius:18px;box-shadow:0 0 0 2px var(--primary);z-index:22"{N(1 if n else None, "tl", "keep")}></div>'
    return page(393, 852, 3, u2m.v4_room(btn + menu))


def v4_toast_fullscreen():
    toast = ('<div style="position:absolute;left:146px;width:560px;bottom:68px;z-index:30"><div class="toast2"><span class="x">已取消关注 晚风</span>'
             '<span class="ac">撤销</span></div></div>'
             '<div class="lbl2" style="left:720px;bottom:78px">下栏上方 16</div>')
    return page(852, 393, 2, SYN + u2m.v4_fs_bars() + toast, frame='fs', extra=FS_EXTRA)


def now_toast_fullscreen():
    toast = ('<div style="position:absolute;left:146px;width:560px;bottom:16px;z-index:30"><div class="toast2"><span class="x">已复制直链</span></div></div>'
             '<div class="lbl2" style="left:720px;bottom:26px">压在下栏上</div>')
    return page(852, 393, 2, SYN + u2m.v4_fs_bars() + toast, frame='fs', extra=FS_EXTRA)


def v4_keyword_portrait():
    dlg = ('<div class="dg" style="left:16px;right:16px;top:300px;padding-bottom:16px">'
           '<div class="t">屏蔽弹幕关键词</div>'
           '<div style="padding:4px 24px 0"><div class="fd2" style="box-shadow:inset 0 0 0 2px var(--primary)"><span class="lbl" style="background:var(--sch);color:var(--primary)">关键词</span>晴天</div>'
           '<div style="display:flex;justify-content:space-between;font-size:12px;color:var(--onv);padding:4px 14px 0"><span>含这个词的弹幕都不再显示</span><span>2/40</span></div></div>'
           '<div class="ac" style="padding-top:16px"><span class="tb">取消</span><span class="fb">屏蔽</span></div></div>')
    kb = '<div style="position:absolute;left:0;right:0;bottom:0;height:300px;background:#D3D6DD;z-index:22"></div>'
    return page(393, 852, 3, u2m.v4_room('<div class="scr"></div>' + dlg + kb))


OUT = {
    'now-timer-landscape': now_timer_landscape(),
    'now-link-portrait': now_link_portrait(),
    'now-fit-portrait': now_fit_portrait(),
    'now-toast-fullscreen': now_toast_fullscreen(),
    'v4-timer-portrait': v4_timer_portrait(),
    'v4-timer-landscape': v4_timer_landscape(),
    'v4-volume-portrait': v4_volume_portrait(),
    'v4-volume-landscape': v4_volume_landscape(),
    'v4-link-portrait-fullscreen': v4_link_portrait_fullscreen(),
    'v4-cast-tablet': v4_cast_tablet(),
    'v4-panels': v4_panels(),
    'v4-menu': v4_menu_portrait(),
    'v4-fit': v4_fit_portrait(),
    'v4-orientation': v4_orientation_landscape(),
    'v4-unfollow': v4_unfollow_portrait(),
    'v4-toast-fullscreen': v4_toast_fullscreen(),
    'v4-message-landscape': v4_message_landscape(),
    'v4-keyword': v4_keyword_portrait(),
}

if __name__ == '__main__':
    for name, html in OUT.items():
        with open(os.path.join(HERE, name + '.html'), 'w', encoding='utf-8') as f:
            f.write(html)
    print(len(OUT), 'pages')
