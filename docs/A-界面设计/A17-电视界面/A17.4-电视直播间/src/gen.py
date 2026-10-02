"""U.15d TV live room: pure_live_TV restored (v3-*) and the new design (v4-*),
960x540 logical (1920x1080). Pieces in tvkit.py.

pure_live_TV (~/ref/pure_live_TV, lib/modules/live/playback/):
  pages/live_play_page.dart          side-panel frame (400 design px, 24 from the edge)
  widgets/player_key_scope.dart      keys: OK controls, Up/Down channel, Left double-press follow, Right playlist
  widgets/video_player/tv_video_surface.dart   room card (_RoomInfoBar), channel toast, loading
  widgets/video_player/video_controller_panel_parts.dart   bottom bar (12 pills) and option lists
  widgets/panels/{playlist_panel,player_index_panel,player_room_row,danmaku_settings_panel,shield_panel}.dart
  dialogs/room_switch_dialog_parts.dart   centred switch dialog (3 tabs)
  widgets/placeholder/not_living_video_widget.dart, video_player/{playback_failure_overlay,audio_only_surface}.dart
New design: docs/ui/compare/U.15d/README.md; same components as U.2a/U.2c/U.2e/U.2f/U.2g.

    python3 docs/ui/compare/U.15d/src/gen.py
    python3 tools/ui/mock/render.py docs/ui/compare/U.15d/src/ --annotate
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from tvkit import *  # noqa: E402,F403

ROOMS = [
    ('深夜电台 · 点歌接龙到天亮', '晚风', '哔哩哔哩', 'BILIBILI', '1.2万', IMG_AV, '唱见电台'),
    ('周末一起看海', '小鱼', '虎牙', 'HUYA', '3.4万', COVERS[0], '户外'),
    ('英雄联盟 钻石局冲分', '阿杰', '斗鱼', 'DOUYU', '56.1万', COVERS[1], '英雄联盟'),
    ('夜游西湖 · 断桥边', '行者老王', '抖音', 'DOUYIN', '8902', COVERS[2], '户外'),
    ('古典吉他练习 · 第 200 天', '琴房小周', '哔哩哔哩', 'BILIBILI', '2315', COVERS[3], '乐器'),
    ('猫咖日常 · 新来的橘猫', '猫掌柜', '快手', 'KUAISHOU', '1.8万', COVERS[4], '萌宠'),
    ('深夜食堂 · 煮一碗面', '老陈', '虎牙', 'HUYA', '6021', COVERS[5], '美食'),
    ('星空延时摄影', '观星者', '哔哩哔哩', 'BILIBILI', '4410', COVERS[6], '科技'),
]
OUT = {}

# =====================================================================
# pure_live_TV
# =====================================================================
def p_info(room=0, banner=None):
    t, nick, plat, pid, aud, av, area = ROOMS[room]
    card = (f'<div class="p p-info"><div class="card"><div class="p-av" style="width:30px;height:30px;background-image:url({av})"></div>'
            f'<div class="tx"><div class="t">{t}</div><div class="m"><span class="p-pill f">{pid}</span><span class="nk">{nick}</span>'
            f'<span class="p-pill">{mr("whatshot", 8, "color:rgba(255,255,255,.7)")}{aud}</span></div></div><div class="dv"></div>'
            f'<div class="clk">{rx("f20f", 12, "color:rgba(255,255,255,.7)")}21:36</div></div></div>')
    if banner:
        card += f'<div class="p p-toast" style="top:62px">{banner}</div>'
    return card


P_BAR = [('mi', 'favorite', '已关注'), ('mr', 'pause', '暂停'), ('mr', 'refresh', '重试'), ('dmk', 'open', '弹幕开'),
         ('dmk', 'set', '弹幕设置'), ('mr', 'dynamic_feed', '弹幕关键词过滤'), ('mr', 'high_quality', '原画'),
         ('mr', 'density_small', '线路 1'), ('mo', 'video_settings', '默认比例'), ('rx', 'f235', '视频模式'),
         ('mr', 'swap_horiz', '切换直播间'), ('mr', 'memory', 'Mpv播放器')]


def p_icon(kind, name, s=12):
    if kind == 'dmk':
        return dmk(name, s)
    if kind == 'rx':
        return rx(name, s)
    return {'mi': mi, 'mr': mr, 'mo': mo}[kind](name, s)


def p_bar(sel=0, opts=None):
    pills = ''.join(f'<div class="p-pl{" s" if i == sel else ""}">{p_icon(k, n)}<span>{l}</span></div>' for i, (k, n, l) in enumerate(P_BAR))
    o = ''
    if opts:
        title, items, cur, at = opts
        rows = ''.join(f'<div class="r"><div class="p-pl{" s" if i == at else ""}" style="justify-content:center"><span>{x}</span>'
                       + (mr('check', 11) if i == cur else '') + '</div></div>' for i, x in enumerate(items))
        o = f'<div class="p-opts"><div class="h">{title}</div>{rows}</div>'
    return f'<div class="p p-ctl">{o}<div class="p-bar">{pills}</div></div>'


def p_side(title, body, hint1, header=''):
    return (f'<div class="p p-side"><div class="h">{title}</div>{header}<div class="ls">{body}</div>'
            f'<div class="p-hint">{hint1}</div><div class="p-hint2">↑↓ 选择 · OK 确认 · ← 关闭</div></div>')


def p_room(i, sel=False, act=False, fol=None):
    t, nick, plat, pid, aud, av, area = ROOMS[i]
    fl = f'<span class="p-fl{" on" if fol else ""}">{"已关注" if fol else "关注"}</span>' if fol is not None else ''
    cls = ' s' if sel else (' a' if act else '')
    return (f'<div class="p-room{cls}"><div class="p-av" style="width:30px;height:30px;background-image:url({av})"></div>'
            f'<div class="tx"><div class="t"><span>{t}</span>{fl}</div><div class="n">{nick}</div></div>'
            f'<div class="r">{pid}<b>{aud}</b></div></div>')


P_DM = [('mr', 'subtitles', '弹幕开关', '弹幕开'), ('mr', 'format_size', '弹幕字号', '16'), ('mr', 'speed', '弹幕速度', '120 px/s'),
        ('mr', 'opacity', '弹幕透明度', '100%'), ('mo', 'border_color', '弹幕描边', '开'), ('mr', 'line_weight', '描边宽度', '4 px'),
        ('mr', 'format_bold', '弹幕字重', '500'), ('mr', 'motion_photos_on', '弹幕帧率', '60 fps'), ('mr', 'auto_mode', '自动帧率', '关'),
        ('mr', 'vertical_align_top', '显示区域', '100%'), ('mr', 'vertical_align_center', '顶部安全距离', '0 px'),
        ('mr', 'vertical_align_bottom', '底部占用高度', '0 px'), ('mo', 'emoji_emotions', '表情显示', '开'),
        ('mr', 'swap_horiz', '面板位置', '右'), ('mr', 'settings_overscan', '左右距离', '24'), ('mr', 'format_size', '面板字号', '100%')]


def p_rows(rows, sel=0):
    return ''.join(f'<div class="p-row{" s" if i == sel else ""}">{p_icon(k, n)}<span class="l">{l}</span><span class="v">{v}</span></div>'
                   for i, (k, n, l, v) in enumerate(rows))


# ---- v3-entry: entering after a channel switch (card for 5 s, channel toast 2 s)
OUT['v3-entry'] = tv(danmaku(10) + p_info(0, banner='晚风'), cls='p')

# ---- v3-controls: OK -> card + bar (index remembered, 0 = follow)
OUT['v3-controls'] = tv(danmaku(10) + p_info(0) + p_bar(sel=0), cls='p')

# ---- v3-quality: the bar's quality list (centred, stays open)
OUT['v3-quality'] = tv(danmaku(10) + p_info(0) + p_bar(sel=-1, opts=('清晰度', ['原画', '蓝光', '超清', '高清', '流畅'], 0, 1)), cls='p')

# ---- v3-playlist: Right -> playlist panel on the right
pl = ''.join(p_room(i, sel=(i == 1), act=(i == 0), fol=(i in (0, 1))) for i in range(8))
OUT['v3-playlist'] = tv(danmaku(10) + p_side('播放列表', pl, '↑↓ 选择 · ←→ 调整 · OK 确认'), cls='p')

# ---- v3-danmaku: danmaku settings panel (first screen; the list scrolls)
OUT['v3-danmaku'] = tv(danmaku(10) + p_side('弹幕设置', p_rows(P_DM, 0), '↑↓ 选择 · ←→ 调整 · OK 确认'), cls='p')
OUT['v3-danmaku-full'] = page(960, 640, 2, frame(danmaku(10) + p_side('弹幕设置', p_rows(P_DM, 9), '↑↓ 选择 · ←→ 调整 · OK 确认'),
                                                   cls='p', extra_style='--h:640px'))

# ---- v3-shield: keyword filter with the phone QR on top
qr_head = ('<div style="padding:2px 6px 4px;text-align:center;flex:none"><div style="font:500 7px \'Noto Sans SC\'">弹幕关键词屏蔽</div>'
           f'<div class="p-qr" style="margin:2px auto 0;width:max-content">{qr(56)}<div style="font:600 7px \'Noto Sans SC\';margin-top:4px;max-width:96px;white-space:nowrap;overflow:hidden">http://192.168.1.5:8080/#/danmaku</div></div>'
           '<div style="font:500 7px \'Noto Sans SC\';margin-top:3px">手机扫码编辑屏蔽词</div></div>')
sh = ''.join(f'<div class="p-row{" s" if i == 0 else ""}">{mr("block", 12)}<span class="l">{w}</span><span class="v">删除</span></div>'
             for i, w in enumerate(['剧透', '刷屏', '广告位招租']))
OUT['v3-shield'] = tv(danmaku(10) + p_side('弹幕关键词过滤 · 3', sh, '↑↓ 选择 · OK 确认 · ← 关闭', header=qr_head), cls='p')

# ---- v3-switch: centred room switch dialog
tabs = ('<div style="display:flex;justify-content:center;gap:5px;margin:2px 0 7px"><span class="p-tab s">已开播 (8)</span>'
        '<span class="p-tab">录播 (1)</span><span class="p-tab">观看记录 (30)</span></div>')
rows = ''.join(p_room(i, sel=(i == 2)) for i in (1, 2, 3, 4, 5, 6, 7))
dlg = (f'<div class="p-scrim"></div><div class="p p-dlg" style="left:174px;top:38px;width:612px;height:464px">'
       f'<div class="h">切换直播间</div>{tabs}<div style="height:340px;border-radius:9px;border:.5px solid rgba(255,255,255,.08);'
       f'background:rgba(0,0,0,.1);padding:5px 6px;overflow:hidden">{rows}</div></div>')
OUT['v3-switch'] = tv(danmaku(10) + p_info(0) + dlg, cls='p')


# ---- v3-states: loading, failure, offline, audio only
def p_state_loading():
    return frame('<div class="p p-cen" style="z-index:3"><div class="p-spin" style="width:18px;height:18px"></div>'
                 '<div style="font:500 8px \'Noto Sans SC\';margin-top:6px">正在加载房间信息...</div></div>' + p_info(0), img=None, cls='p')


def p_btn(icon, label, bg, sel):
    return f'<div class="p-btn{" s" if sel else ""}" style="background:{bg}">{mr(icon, 10)}{label}</div>'


def p_state_failed():
    return frame('<div class="p p-cen" style="background:rgba(0,0,0,.72)">' + mr('error_outline', 24, 'color:#fff') +
                 '<div style="font:500 9px \'Noto Sans SC\';margin-top:6px">播放失败</div>'
                 '<div style="font:500 7px \'Noto Sans SC\';margin-top:5px">↑↓ 选择 · ←→ 调整 · OK 确认</div>'
                 '<div style="display:flex;gap:8px;margin-top:10px">' + p_btn('refresh', '重试播放', '#00A1FF', True)
                 + p_btn('travel_explore', '刷新房间', 'rgba(255,255,255,.12)', False) + '</div></div>' + p_info(0), cls='p')


def p_state_offline():
    av = (f'<div style="position:relative;width:36px;height:36px"><div class="p-av" style="width:36px;height:36px;background-image:url({IMG_AV})"></div>'
          f'<div style="position:absolute;right:-1px;bottom:-1px;width:12px;height:12px;border-radius:50%;background:#3A3A3F;border:1px solid #121212;display:grid;place-items:center">{mr("videocam_off", 8, "color:rgba(255,255,255,.7)")}</div></div>')
    return frame('<div class="p p-cen" style="background:rgba(0,0,0,.86)">' + av +
                 '<div style="font:500 9px \'Noto Sans SC\';margin-top:6px">深夜电台 · 点歌接龙到天亮</div>'
                 '<div style="font:600 12px \'Noto Sans SC\';margin-top:9px">该房间未开播或已下播</div>'
                 '<div style="font:300 9px \'Noto Sans SC\';margin-top:4px">请切换其他直播间进行观看吧</div>'
                 '<div style="font:500 7px \'Noto Sans SC\';margin-top:5px">↑↓ 选择 · ←→ 调整 · OK 确认</div>'
                 '<div style="display:flex;gap:8px;margin-top:10px">' + p_btn('swap_horiz', '切换直播间', '#00A1FF', True)
                 + p_btn('refresh', '刷新房间', 'rgba(255,255,255,.12)', False) + '</div></div>', cls='p')


def p_state_audio():
    return frame(f'<div style="position:absolute;inset:0;background:#121212"></div><div style="position:absolute;inset:0;background:url({IMG_AV}) center/cover;opacity:.2"></div>'
                 '<div style="position:absolute;inset:0;background:linear-gradient(180deg,rgba(18,18,18,.86),rgba(18,18,18,.62),rgba(18,18,18,.92))"></div>'
                 f'<div class="p p-cen"><div style="padding:3px;border-radius:50%;border:1px solid rgba(0,161,255,.55)"><div class="p-av" style="width:76px;height:76px;background-image:url({IMG_AV})"></div></div>'
                 '<div style="font:600 14px \'Noto Sans SC\';margin-top:16px">深夜电台 · 点歌接龙到天亮</div><div style="font:500 9px \'Noto Sans SC\';margin-top:5px">晚风</div>'
                 f'<div style="margin-top:13px;display:flex;align-items:center;gap:5px;padding:6px 10px;border-radius:99px;background:rgba(31,31,31,.72);border:.5px solid rgba(0,161,255,.45);font:500 9px \'Noto Sans SC\'">{rx("ee05", 12, "color:#00A1FF")}仅播放音频</div></div>', img=None, cls='p')


OUT['v3-states'] = sheet('pure_live_TV：直播间的四种状态（按代码还原）', [
    ('加载中', '房间信息还没回来；房间卡片照常显示', p_state_loading()),
    ('播放失败', '整片 72% 黑，两个按钮，左右键选', p_state_failed()),
    ('未开播', '整片 86% 黑，两个按钮', p_state_offline()),
    ('仅播放音频', '控制栏“视频模式”切换；房间卡片 + 徽标', p_state_audio()),
])

# =====================================================================
# new design
# =====================================================================
def t_info(room=0, pos=None, rec=False, extra=''):
    t, nick, plat, pid, aud, av, area = ROOMS[room]
    figs = (f'<span class="t-fg">{mr("people_alt")}<b>{aud}</b></span><span class="t-fg">{mr("whatshot")}<b>84.7万</b></span>'
            f'<span class="t-fg">{mr("schedule")}<b>2:18</b></span>') if room == 0 else (
            f'<span class="t-fg">{mr("people_alt")}<b>{aud}</b></span><span class="t-fg">{mr("schedule")}<b>0:46</b></span>')
    rt = '<div class="t-clk">21:36</div>'
    if rec:
        rt += '<span class="t-tag rec"><i></i>录制中 12:34</span>'
    if pos:
        rt += f'<span class="t-tag pos">{pos}</span>'
    return ('<div class="t-gt"></div>'
            f'<div class="t-info"><div class="t-av" style="width:56px;height:56px;background-image:url({av})"></div>'
            f'<div class="tx"><div class="l1"><span class="nm">{nick}</span><span class="pf">{plat} · {area}</span></div>'
            f'<div class="ti">{t}</div><div class="l3">{figs}{extra}</div></div><div class="rt">{rt}</div></div>')


def ib(inner, n=None, focus=False, tip=None, cls='', tag=None):
    t = f'<div class="t-tip">{tip}</div>' if focus and tip else ''
    return f'<div class="t-ib{" fo" if focus else ""}{(" " + cls) if cls else ""}"{attrs(n, tag)}>{inner}{t}</div>'


BAR_TIPS = {1: '暂停', 2: '刷新', 4: '弹幕开关', 5: '弹幕设置', 8: '画面比例', 9: '切换直播间', 10: '纯音频', 11: '录制', 12: '播放设置'}


def t_bar(focus=None, menu_open=False, rec=False):
    f = lambda k: focus == k
    left = (ib(mr('pause', 32), 1, f(1), BAR_TIPS[1]) + ib(mr('refresh', 28), 2, f(2), BAR_TIPS[2])
            + f'<div class="t-fol{" fo" if f(3) else ""}"{attrs(3)}>{rx("eb7b", 18)}已关注</div>'
            + ib(dmk('open', 28), 4, f(4), BAR_TIPS[4]) + ib(dmk('set', 28), 5, f(5), BAR_TIPS[5]))
    arrow = 'ea78' if menu_open else 'ea4e'
    right = (f'<div class="t-chip{" fo" if f(6) else ""}"{attrs(6)}>原画{rx(arrow)}</div>'
             f'<div class="t-chip{" fo" if f(7) else ""}"{attrs(7)}>线路1{rx("ea4e")}</div>'
             + ib(rx('ea80', 26), 8, f(8), BAR_TIPS[8]) + '<div class="t-sep"></div>'
             + ib(mr('swap_horiz', 30), 9, f(9), BAR_TIPS[9], tag='keep') + ib(rx('ee05', 26), 10, f(10), BAR_TIPS[10], tag='keep')
             + ib('<span class="t-recon"><i></i></span>' if rec else '<span class="t-ring"><i></i></span>', 11, f(11), BAR_TIPS[11], tag='add')
             + ib(rx('ea42', 26), 12, f(12), BAR_TIPS[12], tag='add'))
    return f'<div class="t-gb"></div><div class="t-bar"><div class="g">{left}</div><div class="g">{right}</div></div>'


DM = danmaku(20)

# ---- v4-info: OK -> info bar + control bar (focus on 刷新)
OUT['v4-info'] = tv(DM + t_info(0) + t_bar(focus=2))

# ---- v4-quality: the same small menu as the phone, above the button
menu = ('<div class="t-menu" style="left:524px;bottom:88px;width:176px">'
        + ''.join(f'<div class="it{" on" if i == 0 else ""}{" fo" if i == 2 else ""}"><span>{x}</span>{rx("eb7b") if i == 0 else ""}</div>'
                  for i, x in enumerate(['原画', '蓝光', '超清', '高清', '流畅'])) + '</div>')
OUT['v4-quality'] = tv(DM + t_info(0) + t_bar(focus=None, menu_open=True) + menu)

# ---- v4-switch: just pressed Down: the next room loads, the info bar names it and its place in the list
sw = ('<div class="t-st" style="z-index:4"><div class="t-spin" style="width:36px;height:36px"></div>'
      '<div class="stt" style="font-weight:400;font-size:16px">正在进入直播间…</div></div>')
OUT['v4-switch'] = tv(t_info(1, pos='播放列表 2 / 24') + sw, img=None)

# ---- left: room list panel (one component: the list Up/Down walks + the phone's 切换直播间 tabs)
def t_room(i, focus=False, cur=False, n=None):
    t, nick, plat, pid, aud, av, area = ROOMS[i]
    right = '<span class="t-now">' + mr('equalizer', 15) + '正在播放</span>' if cur else f'{mr("people_alt", 16, "vertical-align:-3px")} {aud}'
    return (f'<div class="t-room{" fo" if focus else ""}{" cur" if cur else ""}"{attrs(n)}>'
            f'<div class="t-av" style="width:42px;height:42px;background-image:url({av});box-shadow:none"></div>'
            f'<div class="x"><div class="a">{t}</div><div class="b">{nick} · {plat}</div></div><div class="r">{right}</div></div>')


def t_tabs(on=0, focus=None, counts=(24, 8, 1, 30), n=None):
    names = ['播放列表', '已开播', '录播', '观看记录']
    return '<div class="t-tabs">' + ''.join(
        f'<div class="t-tab{" on" if i == on else ""}{" fo" if i == focus else ""}"{attrs(n if i == 0 else None)}>{x}<span class="c">{c}</span></div>'
        for i, (x, c) in enumerate(zip(names, counts))) + '</div>'


def left_panel(tabs, rows, hint):
    return (f'<div class="t-side l"><div class="t-ph"><span class="t1">切换直播间</span><span class="lk">刷新</span></div>{tabs}'
            f'<div class="t-body">{rows}</div><div class="t-hint">{hint}</div></div>')


rows = t_room(0, cur=True) + t_room(1) + t_room(2, focus=True, n=2) + ''.join(t_room(i) for i in (3, 4, 5))
OUT['v4-list'] = tv(DM + left_panel(t_tabs(0, n=1), rows, '↑↓ 选择 · OK 换到这里 · 菜单键 关注 · → 关闭'))
rows = ''.join(t_room(i) for i in (1, 2, 3, 4, 5, 6))
OUT['v4-list-live'] = tv(DM + left_panel(t_tabs(1, focus=1), rows, '←→ 换标签 · ↓ 进入列表 · → 关闭'))


# ---- right: 播放设置
def row(icon, label, value=None, n=None, focus=False, sw=None, chev=True, desc=None, tag=None, dis=False):
    v = ''
    if sw is not None:
        v = f'<div class="t-sw{" on" if sw else ""}"></div>'
    elif value is not None:
        v = f'<span class="v">{value}{rx("ea6e") if chev else ""}</span>'
    d = f'<div class="b">{desc}</div>' if desc else ''
    return (f'<div class="t-row{" fo" if focus else ""}{" dis" if dis else ""}"{attrs(n, tag)}><span class="ic">{icon}</span>'
            f'<div class="x"><div class="a">{label}</div>{d}</div>{v}</div>')


def right_panel(title, body, hint, back=False, link=''):
    bk = f'<span class="bk">{rx("ea64", 22)}</span>' if back else ''
    return (f'<div class="t-side"><div class="t-ph">{bk}<span class="t1">{title}</span>{link}</div>'
            f'<div class="t-body">{body}</div><div class="t-hint">{hint}</div></div>')


SET_ROWS = [
    ('sec', '画面'),
    (mr('high_quality', 24), '清晰度', '原画', 1, None),
    (mr('alt_route', 24), '线路', '线路1', 2, None),
    (rx('ea80', 22), '画面比例', '默认比例', 3, None),
    (rx('ee05', 22), '纯音频', None, 4, False),
    ('sec', '弹幕'),
    (dmk('open', 22), '显示弹幕', None, 5, True),
    (dmk('set', 22), '弹幕设置', '', 6, None),
    (mr('filter_alt_off', 22), '屏蔽管理', '3 个关键词', 7, None),
    ('sec', '直播间'),
    ('<span class="t-ring" style="width:20px;height:20px;border-color:var(--onv)"><i style="width:8px;height:8px"></i></span>', '录制', '没在录', 8, None),
    (mr('swap_horiz', 24), '切换直播间', '', 9, None),
    (mr('schedule', 22), '定时关闭', '关', 10, None),
    (mr('volume_up', 22), '房间音量', '100%', 11, None),
    (rx('f0fd', 22), '分享', '', 12, None),
    (rx('eeb2', 22), '获取直链', '', 13, None),
    ('sec', '面板'),
    (mr('format_size', 22), '面板字号', '100%', 14, None),
    (mr('settings_overscan', 22), '左右距离', '0', 15, None),
]


def settings_body(focus=1, upto=None):
    out = []
    for r in SET_ROWS[:upto]:
        if r[0] == 'sec':
            out.append(f'<div class="t-sec">{r[1]}</div>')
            continue
        icon, label, value, n, sw = r
        tag = 'add' if n == 8 else None
        out.append(row(icon, label, value, n, focus == n, sw=sw, tag=tag))
    return ''.join(out)


OUT['v4-settings'] = tv(DM + right_panel('播放设置', settings_body(1), '↑↓ 选择 · OK 打开 · ← 关闭'))
OUT['v4-settings-full'] = page(400, 1200, 2, f'<div class="win t" style="--w:400px;--h:1200px;height:auto;background:var(--surface);padding:28px 24px 24px">'
                               f'<div class="t-ph"><span class="t1">播放设置</span></div>{settings_body(0)}</div>', crop=True)
qmenu = ('<div class="t-menu" style="right:404px;top:98px;width:176px">'
         + ''.join(f'<div class="it{" on" if i == 0 else ""}{" fo" if i == 2 else ""}"><span>{x}</span>{rx("eb7b") if i == 0 else ""}</div>'
                   for i, x in enumerate(['原画', '蓝光', '超清', '高清', '流畅'])) + '</div>')
OUT['v4-settings-quality'] = tv(DM + right_panel('播放设置', settings_body(None), '↑↓ 选择 · OK 选定 · 返回 收起') + qmenu)


# ---- 弹幕设置: U.2f component, TV size; Left/Right adjust the focused value
def slider(label, val, pct, focus=False, n=None, dis=False):
    lr = f'<span class="t-lr" style="margin-left:8px">{rx("ea64", 18)}{rx("ea6e", 18)}</span>' if focus else ''
    return (f'<div class="t-row{" fo" if focus else ""}{" dis" if dis else ""}" style="display:block;padding:10px 12px 4px"{attrs(n)}>'
            f'<div style="display:flex;align-items:center;justify-content:space-between"><span class="a" style="font:400 17px \'Noto Sans SC\'">{label}</span>'
            f'<span style="display:flex;align-items:center"><span class="t-vp">{val}</span>{lr}</span></div>'
            f'<div class="t-tr"><i style="width:{pct}%"></i><u style="left:calc({pct}% - 10px)"></u></div></div>')


def stepper(label, val, focus=False, n=None, dis=False):
    return (f'<div class="t-row{" fo" if focus else ""}{" dis" if dis else ""}"{attrs(n)}><div class="x"><div class="a">{label}</div></div>'
            f'<span class="t-lr">{rx("ea64", 20)}<b style="color:var(--on);font:600 16px \'Noto Sans SC\';min-width:24px;text-align:center">{val}</b>{rx("ea6e", 20)}</span></div>')


def swrow(label, on, desc=None, focus=False, n=None):
    d = f'<div class="b">{desc}</div>' if desc else ''
    return (f'<div class="t-row{" fo" if focus else ""}"{attrs(n)}><div class="x"><div class="a" style="white-space:normal">{label}</div>{d}</div>'
            f'<div class="t-sw{" on" if on else ""}"></div></div>')


TPL = ('<div class="t-sec">观看模板</div><div style="display:flex;flex-wrap:wrap;gap:8px;padding:2px 4px"{n1}>'
       '<span class="t-tg2 on">{chk}顶部 20% · 均衡</span><span class="t-tg2">顶部 35% · 舒适</span><span class="t-tg2">顶部 55% · 高密度</span><span class="t-tg2">重置</span></div>'
       '<div style="font:400 14px/1.45 \'Noto Sans SC\';color:var(--onv);padding:8px 4px 4px">弹幕只占画面顶部约 20%，速度与密度适中，避免遮挡主体内容。</div>'
       '<div style="display:flex;flex-wrap:wrap;gap:4px 16px;padding:4px 4px 2px;font:400 15px \'Noto Sans SC\';color:var(--primary)"{n2}>'
       '<span style="display:flex;align-items:center;gap:4px;height:40px">{save}把当前设置存为我的模板</span><span style="display:flex;align-items:center;gap:4px;height:40px">{rest}用我的模板</span></div>')


def tpl(n=True):
    return TPL.format(n1=attrs(1) if n else '', n2=attrs(2) if n else '', chk=rx('eb7b', 18), save=mr('save', 20), rest=mr('history', 20))


def danmaku_body(focus=3, full=False):
    b = tpl(not full)
    b += ('<div class="t-sec">显示范围</div><div class="t-grp">' + slider('画面顶部占用高度', '20%', 20, focus == 3, None if full else 3)
          + stepper('顶部留白（像素）', '0', focus == 4, None if full else 4) + stepper('区域底部留白（像素）', '0', focus == 5) + '</div>')
    if full:
        b += ('<div class="t-sec">样式</div><div class="t-grp">' + slider('透明度', '92%', 92) + slider('滚动速度（像素/秒）', '118 px/s', 26)
              + slider('字体大小', '16.0 px', 30) + slider('字体粗细', '稍粗', 45) + swrow('弹幕描边', True) + slider('描边宽度', '1.5 px', 37)
              + swrow('纯文字模式（隐藏表情）', False) + '</div>'
              + '<div class="t-sec">重复弹幕</div><div class="t-grp">'
              + swrow('合并短时间内的相同弹幕', False, '不同用户发送相同内容时只保留第一条；本地弹幕和系统消息不受影响。')
              + stepper('相同内容合并时间（秒）', '5', dis=True) + '</div>'
              + '<div class="t-sec">流畅度</div><div class="t-grp">'
              + swrow('弹幕帧率跟随界面刷新率', True, '跟随“通用”里的省电、均衡或最高档位；关闭后可以手动设帧率。')
              + slider('弹幕帧率', '120 FPS', 40, dis=True) + '</div>'
              + '<div style="font:400 14px/1.5 \'Noto Sans SC\';color:var(--onv);padding:14px 4px 0">“画面弹幕交互”（点击、长按画面上的弹幕）要用手指或鼠标，电视上不显示这一组。</div>')
    return b


chg = '<span class="lk">改动立即生效</span>'
OUT['v4-danmaku'] = tv(DM + right_panel('弹幕设置', danmaku_body(3), '↑↓ 选择 · ←→ 调整 · 返回 回到播放设置', back=True, link=chg))
OUT['v4-danmaku-full'] = page(400, 1900, 2, f'<div class="win t" style="--w:400px;--h:1900px;height:auto;background:var(--surface);padding:28px 24px 24px">'
                              f'<div class="t-ph"><span class="bk">{rx("ea64", 22)}</span><span class="t1">弹幕设置</span>{chg}</div>{danmaku_body(None, True)}</div>', crop=True)


# ---- 屏蔽管理: U.2e component, TV size; keywords typed with the remote's keyboard or on the phone
def chip(word, focus=False, n=None, icon=None):
    ic = mr(icon, 18, 'color:var(--primary)') if icon else ''
    return f'<span class="t-tg2{" fo" if focus else ""}"{attrs(n)}>{ic}{word}{rx("eb99", 18, "color:var(--onv);margin-left:2px")}</span>'


def shield_body(full=False, removed=False):
    b = ('<div class="t-sec">弹幕关键词屏蔽</div><div class="t-grp" style="padding:12px">'
         f'<div class="t-in"{attrs(1)}>{rx("ea13", 20, "margin-right:6px;color:var(--primary)")}添加关键词（遥控器输入）</div>'
         f'<div style="display:flex;align-items:center;gap:12px;margin-top:10px"><div style="flex:none">{qr(56)}</div>'
         '<div style="font:400 14px/1.45 \'Noto Sans SC\';color:var(--onv)">也可以用手机扫码，在手机上添加和删除<br><span style="color:var(--on)">192.168.1.5:8080</span></div></div>'
         f'<div style="font:400 14px \'Noto Sans SC\';color:var(--onv);margin:12px 2px 8px">已添加{2 if removed else 3}个关键词</div>'
         '<div style="display:flex;flex-wrap:wrap;gap:8px">' + ('' if removed else chip('剧透', True, 2)) + chip('刷屏', removed) + chip('广告位招租') + '</div></div>'
         '<div class="t-sec">已屏蔽用户（2）</div><div class="t-grp" style="padding:12px;display:flex;flex-wrap:wrap;gap:8px">'
         + chip('路人甲', n=3, icon='person_off') + chip('某某广告', icon='person_off') + '</div>'
         '<div class="t-sec">平台弹幕过滤</div><div class="t-grp">'
         + swrow('过滤斗鱼疑似自动弹幕', False, '开启后按启发式标记隐藏疑似自动或活动弹幕，也可能隐藏普通聊天', n=4) + '</div>')
    if full:
        b += ('<div class="t-sec">相似弹幕过滤</div><div class="t-grp">' + swrow('启用相似弹幕过滤', True)
              + slider('相似度阈值', '85%', 70) + slider('缓存时间', '3 秒', 4) + slider('最大缓存数量', '100', 8) + '</div>')
    return b


OUT['v4-shield'] = tv(DM + right_panel('屏蔽管理', shield_body(), '←→↑↓ 选择 · OK 删除 · 返回 回到播放设置', back=True))
OUT['v4-shield-full'] = page(400, 1400, 2, f'<div class="win t" style="--w:400px;--h:1400px;height:auto;background:var(--surface);padding:28px 24px 24px">'
                             f'<div class="t-ph"><span class="bk">{rx("ea64", 22)}</span><span class="t1">屏蔽管理</span></div>{shield_body(True)}</div>', crop=True)
toast = '<div class="t-toast" style="left:280px">已移除“剧透” · 按<b>菜单键</b>撤销</div>'
OUT['v4-shield-undo'] = tv(DM + right_panel('屏蔽管理', shield_body(removed=True), '←→↑↓ 选择 · OK 删除 · 返回 回到播放设置', back=True) + toast)

# ---- 录制: U.2f record panel, TV size
rec = ('<div class="t-grp" style="padding:16px;background:var(--scc)">'
       '<div style="display:flex;align-items:center;gap:10px"><span class="t-ring" style="border-color:var(--onv)"><i></i></span><span style="font:600 18px \'Noto Sans SC\'">没在录制</span></div>'
       '<div style="font:400 14px/1.45 \'Noto Sans SC\';color:var(--onv);margin:8px 0 14px">开始后一直录到主播下播，或你点“停止录制”。</div>'
       f'<div class="t-btn go fo"{attrs(1)}><i></i>开始录制</div></div>'
       '<div class="t-sec">这次录制</div>'
       '<div style="display:flex;justify-content:space-between;align-items:baseline;padding:2px 4px 8px"><span style="font:400 17px \'Noto Sans SC\'">录制清晰度</span><span style="font:400 14px \'Noto Sans SC\';color:var(--onv)">默认值在录制设置里改</span></div>'
       f'<div style="display:flex;flex-wrap:wrap;gap:8px;padding:0 4px"{attrs(2)}><span class="t-tg2 on">{rx("eb7b", 18)}原画</span><span class="t-tg2">蓝光</span><span class="t-tg2">超清</span><span class="t-tg2">高清</span><span class="t-tg2">流畅</span></div>'
       + swrow('同时录弹幕', False, '在录像旁保存同名 .xml 弹幕文件，PotPlayer 等可以加载', n=3)
       + '<div class="t-sec">自动录</div>' + swrow('开播自动录', False, '主播开播时自动开始录，下播后自动停止', n=4)
       + '<div style="display:flex;justify-content:space-between;font:400 14px \'Noto Sans SC\';color:var(--onv);padding:12px 4px 0"><span>保存到 下载/PureLiveRecords</span></div>')
OUT['v4-record'] = tv(DM + right_panel('录制', rec, '↑↓ 选择 · OK 确认 · 返回 回到播放设置', back=True))


# ---- states: the U.2g state component, TV size (default focus on the first button)
def vb(label, icon, primary=True, focus=False):
    return f'<div class="t-vb {"p" if primary else "o"}{" fo" if focus else ""}">{icon}{label}</div>'


KH = '<div class="kh">↑↓ 换一个直播间 · ←→ 选择按钮 · OK 确认</div>'


def st(title, sub='', icon='', acts='', bg=None, dim='', info=False, kh=True):
    inner = ''
    if bg == 'cover':
        inner += f'<div class="t-cov" style="background-image:url({IMG_ROOM});background-position:center 55%"></div>'
    if dim:
        inner += f'<div class="t-dim {dim}"></div>'
    inner += (f'<div class="t-st">{icon}<div class="stt">{title}</div>' + (f'<div class="ss">{sub}</div>' if sub else '')
              + (f'<div class="acts">{acts}</div>' if acts else '') + (KH if kh else '') + '</div>')
    if info:
        inner += t_info(0)
    return frame(inner, img=IMG_ROOM if bg == 'pic' else None, syn=False)


SW = mr('swap_horiz', 20)
RF = mr('refresh', 20)
STATES = [
    ('进房中', '名字、标题先显示（E2）；8 秒还没画面时同 U.2g 的“加载较慢”',
     st('正在进入直播间…', icon='<div class="t-spin" style="width:36px;height:36px"></div>', info=True, kh=False)),
    ('未开播', '每 60 秒查一次，开播自动播放（U.2g Z2）',
     st('当前主播未开播或已下播', '开播后会自动开始播放', f'<div class="t-av" style="width:72px;height:72px;background-image:url({IMG_AV})"></div>',
        vb('切换直播间', SW, True, True) + vb('刷新', RF, False), bg='cover')),
    ('播放已中断', '原因写在画面上；控制栏照常',
     st('播放已中断', '网络连接失败', mr('error_outline', 44), vb('重试', RF, True, True) + vb('换线路', mr('alt_route', 20), False), bg='pic', dim='x')),
    ('正在重连', 'U.2a E3；有多条线路才有“换线路”',
     st('正在重连（第 2 次）', '', '<div class="t-spin" style="width:36px;height:36px"></div>', vb('换线路', mr('alt_route', 20), False, True), bg='pic', dim='l')),
    ('受限 · 需要登录', '去登录打开电视的账号登录（扫码）',
     st('该直播需要登录平台账号才能观看', '', mr('lock', 44), vb('去登录', mr('login', 20), True, True) + vb('重试', RF, False), bg='pic', dim='x')),
    ('获取直播间信息失败', '按原因写（网络、风控、接口变化）',
     st('网络连接失败，请检查网络或代理后重试', '', mr('error_outline', 44), vb('重试', RF, True, True) + vb('切换直播间', SW, False))),
    ('纯音频播放中', 'U.2a E5；播放设置里的“纯音频”关掉恢复画面',
     st('纯音频播放中', '', rx('ee05', 48), bg='cover', kh=False)),
    ('回放已播完', '录播、回看放完',
     st('回放已播完', '', mr('replay', 44), vb('从头播放', mr('replay', 20), True, True) + vb('切换直播间', SW, False), bg='pic', dim='x')),
]
OUT['v4-states'] = sheet('新设计：直播间的状态（U.2g 的同一个组件，电视字号；白圈是默认焦点）', STATES)

for name, html in OUT.items():
    if html is None:
        continue
    open(os.path.join(HERE, name + '.html'), 'w', encoding='utf-8').write(html)
print(len([h for h in OUT.values() if h]), 'pages')
