"""U.15g TV music mockups: pure_live_TV restored (v3-*) and the new design
(v4-*). Shared TV pieces come from ../../U.15f/src/tvkit.py.
    python3 docs/ui/compare/U.15g/src/gen.py && python3 tools/ui/mock/render.py docs/ui/compare/U.15g/src/ --annotate
pure_live_TV sources (~/ref/pure_live_TV/lib/modules/music):
  music_section.dart, music_section_view.dart, widgets/music_mini_bar.dart, widgets/music_song_row.dart,
  widgets/music_song_menu.dart, widgets/music_playlist_cards.dart, widgets/music_video_card.dart
  pages/playback/music_player_page.dart, music_now_playing_queue_widgets.dart,
      widgets/player_control_bar_parts.dart, player_now_playing_view.dart, player_queue_panel.dart
  pages/playlist/music_fav_folders_page.dart, music_user_playlist_detail_page.dart, music_playlist_dialogs.dart
  pages/discover/music_daily_page.dart
"""
import os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', 'U.15f', 'src'))
from tvkit import *  # noqa: E402,F401,F403

CSS = '''
.row3{display:flex;align-items:center;gap:0;padding:10px 14px;border-radius:14px;background:rgba(31,31,31,.45);border:2px solid transparent;margin-bottom:4px}
.row3.cur{background:rgba(0,161,255,.14)}.row3.foc{background:#1F1F1F;border-color:#00A1FF}
.row3 .ix{width:44px;font-size:16px;font-weight:500;text-align:center}
.row3 .th{width:132px;height:120px;border-radius:12px;background:#333 center/cover;flex:none;margin:0 16px 0 8px}
.row3 .tt3{font-size:18px;font-weight:600}.row3 .ln{display:flex;align-items:center;gap:4px;font-size:16px;font-weight:500;margin-top:4px}
.mini3{position:absolute;left:12px;right:12px;bottom:12px;box-shadow:0 0 0 12px #121212,0 40px 0 12px #121212;padding:10px 16px;border-radius:20px;background:#1F1F1F;border:1px solid rgba(0,161,255,.35)}
.ib3{display:inline-grid;place-items:center;border-radius:50%;background:rgba(31,31,31,.45);flex:none}
.lrc3{font-size:20px;font-weight:500;color:rgba(255,255,255,.6);line-height:1.6;margin-bottom:18px}
.lrc3.on{font-size:26px;font-weight:700;color:#fff}
.lrc4{font-size:17px;color:rgba(255,255,255,.55);line-height:26px;margin-bottom:12px}
.lrc4.on{font-size:22px;font-weight:600;color:#fff;line-height:30px}
.qrow{display:flex;align-items:center;gap:12px;min-height:52px;padding:6px 12px;border-radius:12px;background:#101A26;margin-bottom:6px}
.qrow .ix{width:24px;text-align:center;font-size:14px;color:rgba(243,245,247,.6);flex:none}
.qrow .th{width:72px;height:40px;border-radius:6px;background:#16243A center/cover;flex:none}
.qrow .x{flex:1;min-width:0}.qrow .a{font-size:15px;font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.qrow .b{font-size:13px;color:rgba(243,245,247,.72);white-space:nowrap;overflow:hidden;text-overflow:ellipsis;margin-top:1px}
.qrow .du{font-size:14px;color:rgba(243,245,247,.72);font-feature-settings:'tnum'}
.qrow.cur .a{color:#7DB6FF}.qrow.fr{background:#1E3148}
.pl{display:flex;flex-direction:column;gap:6px}
.pl .cv{position:relative;aspect-ratio:3/2;border-radius:12px;background:#16243A center/cover;overflow:hidden}
.pl .nm{font-size:14px;font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;display:flex;align-items:center;gap:4px}
.pl.pf .cv{box-shadow:0 0 0 3px #F2F5FA}.pl.pf{transform:scale(1.05)}
.minib{position:absolute;left:0;right:0;bottom:28px;height:60px;border-radius:16px;background:#101A26;display:flex;align-items:center;gap:12px;padding:0 12px;overflow:hidden;z-index:8}
'''
ARCH = '古筝弹唱合集 2026'
UP = '弦月'
QUEUE = [('晚风', '04:48'), ('春日来信', '03:44'), ('月光下的港口', '04:05'), ('雨后', '03:30'), ('归途', '04:12'), ('茉莉花', '03:58'),
         ('渔舟唱晚', '05:20'), ('高山流水', '06:02'), ('彩云追月', '04:31'), ('平湖秋月', '04:44'), ('梁祝', '07:15'), ('送别', '03:12')]
COV = 219
LYRICS = ['晚风吹过旧街口', '路灯一盏一盏亮起来', '你说要去很远的地方', '我把心事折成纸船', '放进夜色里的河流', '等一个回声']


# ======================================================================
#  v3
# ======================================================================
def row3(i, title, dur, cur=False, focus=False):
    cls = 'row3' + (' cur' if cur else '') + (' foc' if focus else '')
    ix = mr('graphic_eq', 30, '#00A1FF') if cur else f'{i + 1}'
    c = 'color:#00A1FF' if cur else ''
    return (f'<div class="{cls}"><div class="ix">{ix}</div><div class="th" style="background-image:url({IMG(COV)})"></div><div style="flex:1;min-width:0">'
            f'<div class="tt3" style="{c}">{title}</div>'
            f'<div class="ln">{mr("album", 18)}{ARCH}<span style="width:10px"></span>{mr("person_outline", 18)}{UP}</div>'
            f'<div class="ln" style="margin-top:2px">{mr("playlist_play", 18)}P{i + 1}/12<span style="width:10px"></span>{mr("schedule", 18)}{dur}</div></div></div>')


def mini3():
    return (f'<div class="mini3"><div style="display:flex;align-items:center"><div style="flex:1;display:flex;align-items:center;padding:6px 10px;border-radius:12px">'
            f'<span style="width:40px;height:40px;border-radius:20px;background:url({AV}) center/cover"></span>'
            f'<div style="flex:1;margin-left:14px"><div style="font-size:18px;font-weight:700">晚风</div><div style="font-size:14px;font-weight:500;margin-top:2px;padding-left:10px">{UP}</div></div>'
            '<span style="font-size:14px;font-weight:500" class="t">01:12 / 04:48</span></div>'
            + ''.join(f'<span class="ib3" style="width:52px;height:52px;margin-left:6px">{mr(n, 22)}</span>' for n in ['favorite_border', 'playlist_add', 'skip_previous'])
            + f'<span class="ib3" style="width:64px;height:64px;margin-left:6px;background:rgba(31,31,31,.75)">{mr("pause", 28)}</span>'
            + f'<span class="ib3" style="width:52px;height:52px;margin-left:6px">{mr("skip_next", 22)}</span></div>'
            '<div style="height:6px;border-radius:3px;background:rgba(255,255,255,.25);margin-top:6px;position:relative"><i style="position:absolute;left:0;top:0;bottom:0;width:25%;border-radius:3px;background:#00A1FF"></i></div></div>')


def v3_now(menu=False):
    src = (f'<div style="margin:0 20px 6px;padding:16px;border-radius:16px;background:#1F1F1F;display:flex;align-items:center;gap:16px">'
           f'<span style="width:80px;height:80px;border-radius:40px;background:url({AV}) center/cover;flex:none"></span>'
           f'<div style="flex:1"><div style="font-size:20px;font-weight:700">{ARCH}</div><div style="display:flex;align-items:center;gap:4px;margin-top:4px;font-size:16px">'
           f'{mr("person_outline", 18)}{UP}<span style="margin-left:10px;font-size:14px;font-weight:600;color:#00A1FF">已关注</span></div></div>'
           f'<span style="width:132px;height:84px;border-radius:12px;background:url({IMG(COV)}) center/cover"></span></div>')
    rows = ''.join(row3(i, t, d, cur=(i == 0), focus=(i == (1 if menu else 0))) for i, (t, d) in enumerate(QUEUE[:6]))
    body = (rail3('music', 0) + '<div class="pane">' + '<div style="padding:16px 20px 10px;font-size:24px;font-weight:700">正在播放（12）</div>'
            + src + f'<div style="padding:6px 20px 0">{rows}</div>' + mini3() + '</div>')
    if menu:
        opts = [('low_priority', '下一首播放', '#00A1FF', True), ('favorite_border', '喜欢这首歌', '#00A1FF', False), ('playlist_add', '加入歌单', '#00A1FF', False),
                ('delete_outline', '已从队列移除', '#FF5252', False)]
        rows = ''.join(f'<div class="opt3{" foc" if f else ""}">{mr(i, 26, c)}<span>{t}</span></div>' for i, t, c, f in opts)
        body += ('<div class="scrim3"></div><div class="dlg3" style="width:560px;left:680px;top:300px"><div class="h">春日来信</div>' + rows
                 + '<div style="display:flex;justify-content:flex-end;margin-top:32px">' + b3('取消', cls='sec') + '</div></div>')
    return page(body, CSS, restore=True)


def v3_player_bg():
    lyr = ''.join(f'<div class="lrc3{" on" if i == 2 else ""}">{l}</div>' for i, l in enumerate(LYRICS))
    return ('<div style="position:absolute;inset:0;background:#000;display:flex;padding:96px 64px">'
            f'<div style="flex:5;display:flex;flex-direction:column;align-items:center;justify-content:center"><div style="width:300px;height:300px;border-radius:24px;background:url({IMG(COV)}) center/cover"></div>'
            f'<div style="font-size:26px;font-weight:700;margin-top:28px">晚风</div><div style="font-size:18px;font-weight:500;color:rgba(255,255,255,.7);margin-top:10px">{UP}</div></div>'
            f'<div style="width:48px"></div><div style="flex:6;display:flex;flex-direction:column;justify-content:center">{lyr}</div></div>')


def v3_player(panel=None):
    top = (f'<div style="position:absolute;top:24px;left:48px;right:48px;display:flex;align-items:center;gap:12px;z-index:5">{mr("music_note", 28, "#00A1FF")}'
           '<span style="flex:1;font-size:22px;font-weight:700">晚风</span><span style="font-size:18px;color:rgba(255,255,255,.7)">P1/12</span>'
           f'<span style="font-size:18px;color:rgba(255,255,255,.7)">1080P</span><span style="font-size:18px;color:rgba(255,255,255,.7)">{UP}</span></div>')
    acts = [('skip_previous', '上一首'), ('pause', '暂停'), ('skip_next', '下一首'), ('high_quality', '1080P'), ('videocam', '显示画面'),
            ('queue_music', '正在播放'), ('lyrics', '选择歌词'), ('memory', 'Mpv播放器'), ('settings', '设置')]
    sel = 3 if panel == 'quality' else (5 if panel == 'queue' else 1)
    pills = ''.join(b3(l, n, 'mo' if n in ('lyrics', 'settings', 'videocam') else 'mr', cls=('sel' if i == sel and panel != 'queue' else 'sec'), size=22)
                    for i, (n, l) in enumerate(acts))
    opts = ''
    if panel == 'quality':
        items = [('1080P+', False), ('1080P', True), ('720P', False), ('480P', False)]
        opts = ('<div style="background:rgba(0,0,0,.92);border-radius:16px;margin-bottom:12px;padding-bottom:12px"><div style="padding:14px 24px 6px;font-size:20px;font-weight:600">音质</div>'
                + ''.join(f'<div style="margin:4px 16px;padding:10px 20px;border-radius:12px;display:inline-flex;align-items:center;gap:8px;font-size:16px;font-weight:500;'
                          f'background:{"rgba(0,161,255,.22)" if a else "rgba(255,255,255,.08)"};border:2px solid {"#00A1FF" if a else "transparent"};color:{"#fff" if a else "rgba(255,255,255,.7)"}">'
                          f'{l}{mr("check", 20, "#00A1FF") if a else ""}</div><br>' for l, a in items) + '</div>')
    bar = ('<div style="position:absolute;left:48px;right:48px;bottom:32px;padding:18px 24px;border-radius:24px;background:rgba(0,0,0,.72);border:1px solid rgba(0,161,255,.35);z-index:5">'
           + opts + '<div style="display:flex;align-items:center;gap:16px"><span class="t" style="font-size:18px;color:rgba(255,255,255,.7)">01:12</span>'
           '<div style="flex:1;height:16px;border-radius:11px;border:1px solid rgba(255,255,255,.24);margin:10px 0;position:relative"><i style="position:absolute;left:3px;top:3px;bottom:3px;width:25%;border-radius:8px;background:#00A1FF"></i></div>'
           f'<span class="t" style="font-size:18px;color:rgba(255,255,255,.7)">04:48</span></div><div style="display:flex;flex-wrap:wrap;justify-content:center;gap:10px 12px;margin-top:16px">{pills}</div></div>')
    line = ('<div style="position:absolute;left:0;right:0;bottom:0;height:5px;background:rgba(255,255,255,.16);z-index:6">'
            '<i style="position:absolute;left:0;top:0;bottom:0;width:25%;background:#00A1FF"></i></div>')
    body = v3_player_bg() + top + bar + line
    if panel == 'queue':
        def qrow(i, t, d, cur, sel):
            bg = '#00A1FF' if sel else ('rgba(0,161,255,.22)' if cur else 'rgba(255,255,255,.06)')
            ix = mr('play_arrow', 32, '#fff' if sel else '#00A1FF') if cur else f'<span style="font-size:16px;color:rgba(255,255,255,.54)">{i + 1}</span>'
            return (f'<div style="height:88px;margin:4px 0;padding:0 14px;border-radius:14px;background:{bg};display:flex;align-items:center">'
                    f'<span style="width:34px;text-align:center">{ix}</span><span style="width:104px;height:64px;border-radius:10px;background:url({IMG(COV)}) center/cover;margin:0 14px 0 12px"></span>'
                    f'<div style="flex:1;min-width:0"><div style="font-size:18px;font-weight:600;color:{"#00A1FF" if cur and not sel else "#fff"}">{t}</div>'
                    f'<div style="display:flex;align-items:center;gap:4px;font-size:16px;color:{"rgba(255,255,255,.7)" if sel else "rgba(255,255,255,.54)"};margin-top:4px">{mr("album", 18)}{ARCH}</div></div>'
                    f'<span style="padding:2px 8px;border-radius:6px;background:rgba(255,255,255,.08);font-size:14px;font-weight:600;color:rgba(255,255,255,.54)">P{i + 1}/12</span></div>')
        rows = ''.join(qrow(i, t, d, i == 0, i == 0) for i, (t, d) in enumerate(QUEUE[:7]))
        body += ('<div style="position:absolute;top:100px;bottom:100px;right:48px;width:520px;background:rgba(0,0,0,.88);border-radius:24px;border:1px solid rgba(0,161,255,.5);z-index:10;overflow:hidden;display:flex;flex-direction:column">'
                 '<div style="display:flex;align-items:center;padding:14px 12px 10px 26px;gap:6px"><span style="flex:1;font-size:20px;font-weight:600">正在播放（12）</span>'
                 + ''.join(f'<span class="ib3" style="width:58px;height:58px">{mr(n, 22)}</span>' for n in ['playlist_remove', 'playlist_play', 'close'])
                 + f'</div><div style="flex:1;overflow:hidden;padding:0 16px">{rows}</div>'
                 '<div style="padding:8px 26px 14px;font-size:14px;color:rgba(255,255,255,.38)">↑↓ 选择 · OK 确认 · ← 关闭</div></div>')
    return page(body, CSS, restore=True)


def plcard3(name, n, cover, pinned=False, liked=False, focus=False):
    st = 'border-color:#00A1FF;box-shadow:0 0 18px 1.5px rgba(0,161,255,.4)' if focus else ''
    bg = f'background:url({IMG(cover)}) center/cover' if cover else 'background:rgba(0,161,255,.15)'
    inner = '' if cover else f'<div style="position:absolute;inset:0;display:grid;place-items:center">{mr("library_music", 64, "#00A1FF")}</div>'
    pin = f'<span class="cvt">{chip3("", "push_pin")}</span>' if pinned else ''
    return (f'<div style="display:flex;flex-direction:column"><div style="flex:1;border-radius:24px;border:2px solid transparent;position:relative;overflow:hidden;{bg};{st}">{inner}{pin}'
            f'<span style="position:absolute;right:12px;bottom:12px">{chip3(str(n))}</span></div>'
            f'<div style="display:flex;align-items:center;gap:6px;padding-top:4px;font-size:16px;font-weight:600">{mr("favorite", 22, "#00A1FF") if liked else ""}{name}</div></div>')


PLAYLISTS = [('喜欢的歌曲', 32, None, True, True), ('周末歌单', 18, 342, True, False), ('通勤路上', 40, 225, False, False), ('古风', 12, 219, False, False)]
FOLDERS = [('默认收藏夹', 128, 1, '同步于 9/30'), ('练琴参考', 46, 133, '尚未同步'), ('睡前听', 21, 292, '同步于 9/28')]


def v3_playlists():
    shelf = ('<div style="display:grid;grid-template-columns:repeat(6,minmax(0,1fr));grid-auto-rows:186px;gap:16px">'
             + ''.join(plcard3(*p, focus=(i == 0)) for i, p in enumerate(PLAYLISTS)) + '</div>')
    def folder(name, n, cover, synced):
        return (f'<div style="border-radius:16px;background:#1F1F1F;overflow:hidden;display:flex;flex-direction:column">'
                f'<div style="flex:1;background:url({IMG(cover)}) center/cover;position:relative"><span style="position:absolute;right:12px;bottom:12px">{chip3(str(n))}</span></div>'
                f'<div style="padding:10px 14px"><div style="font-size:16px;font-weight:600">{name}</div><div style="font-size:14px;margin-top:4px">{synced}</div></div></div>')
    folders = ('<div style="display:grid;grid-template-columns:repeat(4,minmax(0,1fr));grid-auto-rows:322px;gap:6px">' + ''.join(folder(*f) for f in FOLDERS) + '</div>')
    head = ('<div style="display:flex;align-items:center;gap:12px;padding:16px 24px 8px"><span class="acc" style="font-size:22px;font-weight:700;flex:1">歌单（7）</span>'
            + b3('导入歌单', 'download', size=24) + b3('新建歌单', 'playlist_add', size=24) + b3('全部同步', 'sync', cls='sec', size=24) + '</div>')
    body = (rail3('music', 2) + '<div class="pane">' + head + f'<div style="padding:8px 24px">{shelf}'
            '<div style="font-size:18px;font-weight:600;margin:16px 0 12px">同步歌单（3）</div>' + folders + '</div>' + mini3() + '</div>')
    return page(body, CSS, restore=True)


def v3_playlist():
    rows = ''.join(row3(i, t, d, cur=False) for i, (t, d) in enumerate(QUEUE[:6]))
    head = ('<div style="display:flex;align-items:center;gap:12px;padding:16px 20px 10px"><span style="font-size:22px;font-weight:700;flex:1">（18）</span>'
            + b3('多选', 'checklist', cls='sec', size=24) + b3('正在播放', 'music_note', cls='sec', size=24) + b3('播放全部', 'play_circle_fill', size=28) + '</div>')
    body = hdr3('周末歌单', focus_back=True) + head + f'<div style="padding:16px 20px">{rows}</div>'
    return page(body, CSS, restore=True)


def mvcard3(v, focus=False):
    title, up, cover, plays, dms, dur, region, date = v
    st = 'background:#1E3948;border-color:#00A1FF;transform:scale(1.01)' if focus else ''
    return (f'<div style="border-radius:18px;background:#1F1F1F;border:2px solid transparent;display:flex;flex-direction:column;{st}">'
            f'<div style="flex:1;border-radius:18px;position:relative;overflow:hidden;background:url({IMG(cover)}) center/cover">'
            f'<span style="position:absolute;left:12px;bottom:12px;display:flex;gap:6px">{chip3(plays, "play_arrow")}{chip3(dms, "comment", "mo")}</span>'
            f'<span style="position:absolute;right:12px;bottom:12px">{chip3(dur)}</span></div>'
            f'<div style="display:flex;align-items:center;gap:12px;padding:8px 12px 8px 10px"><span style="width:40px;height:40px;border-radius:20px;background:url({AV}) center/cover;flex:none"></span>'
            f'<div style="min-width:0"><div style="font-size:16px;font-weight:700;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">{title}</div>'
            f'<div style="font-size:14px;font-weight:500;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">{up} · {date}</div></div></div></div>')


MV = [('古筝弹唱《晚风》完整版', '弦月', 219, '15.5万', '2763', '04:48', '音乐', '2026-09-30'),
      ('街头弹唱合集，听歌的进来', '阿远', 342, '18.9万', '4210', '33:18', '音乐', '2026-09-21'),
      ('钢琴即兴：夜航星', '六弦琴', 250, '3.2万', '412', '05:12', '音乐', '2026-09-18'),
      ('小城夏天 · 吉他弹唱', '阿远', 287, '8.8万', '967', '03:56', '音乐', '2026-09-15'),
      ('海边的信（原创）', '月亮邮差', 292, '1.2万', '188', '04:20', '音乐', '2026-09-12'),
      ('雨夜白噪音 · 三小时', '早起的鸟', 360, '46.1万', '1.3万', '3:00:00', '音乐', '2026-09-10'),
      ('民谣现场：归途', '风吹麦浪', 304, '2.6万', '233', '04:12', '音乐', '2026-09-08'),
      ('城市夜跑歌单', '风吹麦浪', 225, '9812', '120', '42:30', '音乐', '2026-09-05')]


def v3_daily():
    grid = ('<div style="display:grid;grid-template-columns:repeat(4,minmax(0,1fr));grid-auto-rows:323px;gap:6px;padding:24px">'
            + ''.join(mvcard3(v, focus=(i == 0)) for i, v in enumerate(MV)) + '</div>')
    head = ('<div style="display:flex;align-items:center;padding:16px 24px 8px">' + b3('默认收藏夹', 'folder', 'mo', cls='sec', size=24)
            + '<span style="flex:1"></span>' + b3('重新生成', 'refresh', cls='sec', size=24) + '</div>')
    body = (rail3('music', 3) + '<div class="pane"><div style="padding:12px 24px 0">' + tabs3(['每日', '动态', '排行'], 0).replace('margin-top:24px', 'margin-top:0')
            + '</div>' + head + grid + mini3() + '</div>')
    return page(body, CSS, restore=True)


def v3_add():
    body_bg = v3_now().split('<div class="d">', 1)[1].rsplit('</div><div class="syn">', 1)[0]

    def item(icon, name, n, focus=False):
        st = 'background:#1F1F1F;border-color:#00A1FF' if focus else ''
        return (f'<div style="display:flex;align-items:center;gap:12px;padding:12px 16px;border-radius:12px;border:2px solid transparent;{st}">'
                f'{mr(icon, 26, "#00A1FF")}<span style="flex:1;font-size:18px;font-weight:500">{name}</span><span style="font-size:14px;font-weight:500">{n}</span></div>')
    rows = (item('favorite', '喜欢的歌曲', 32, True) + item('queue_music', '周末歌单', 18) + item('queue_music', '通勤路上', 40) + item('queue_music', '古风', 12)
            + '<div style="height:8px"></div>' + item('playlist_add', '新建歌单', ''))
    dlg = ('<div class="scrim3"></div><div class="dlg3" style="width:640px;left:640px;top:220px"><div class="h">加入歌单</div>' + rows
           + '<div style="display:flex;justify-content:flex-end;margin-top:32px">' + b3('取消', cls='sec') + '</div></div>')
    return page(body_bg + dlg, CSS, restore=True)


# ======================================================================
#  new design
# ======================================================================
def qrow4(i, title, dur, cur=False, focus=False, n=None, tag='chg', thumb=True):
    cls = 'qrow' + (' cur' if cur else '') + (' fr' if focus else '')
    ix = mr('graphic_eq', 20, '#7DB6FF') if cur else f'{i + 1}'
    th = f'<span class="th" style="background-image:url({IMG(COV)})"></span>' if thumb else ''
    return (f'<div class="{cls}"{at(n, tag)}><span class="ix">{ix}</span>{th}<div class="x"><div class="a">{title}</div>'
            f'<div class="b">P{i + 1}/12 · {ARCH} · {UP}</div></div><span class="du">{dur}</span></div>')


def minibar4(n=None):
    N = (lambda k: k) if n else (lambda k: None)
    return (f'<div class="minib"><div class="nrow" style="flex:1;min-height:44px;padding:4px 10px;gap:10px;background:transparent"{at(N(10), "keep")}>'
            f'<span style="width:40px;height:40px;border-radius:20px;background:url({AV}) center/cover;flex:none"></span>'
            f'<div class="x"><div class="a">晚风</div><div class="b">{UP}</div></div><span class="v tnum">01:12 / 04:48</span></div>'
            + nb('', 'favorite_border', 'ic', n=N(11), tag='keep') + nb('', 'playlist_add', 'ic', n=N(12), tag='keep') + nb('', 'skip_previous', 'ic', n=N(13), tag='keep')
            + nb('', 'pause', 'ic pri', n=N(14), tag='keep') + nb('', 'skip_next', 'ic', n=N(15), tag='keep')
            + '<div style="position:absolute;left:0;right:0;bottom:0;height:3px;background:rgba(255,255,255,.12)"><i style="position:absolute;left:0;top:0;bottom:0;width:25%;background:#4D9BFF"></i></div></div>')


def v4_now(n=True, menu=False):
    N = (lambda k: k) if n else (lambda k: None)
    NB = (lambda k: None) if menu else N
    head = (f'<div style="position:absolute;left:0;right:0;top:28px;display:flex;align-items:center;gap:12px"><span style="font-size:20px;font-weight:600">正在播放</span>'
            f'<span class="sub" style="font-size:14px">12 首</span><span style="flex:1"></span>'
            f'<span class="nb sm"{at(NB(8), "add")}>{mr("repeat", 18)}列表循环{mr("arrow_drop_down", 20)}</span>{nb("清空", "playlist_remove", "sm", n=NB(9), tag="keep")}</div>')
    src = (f'<div class="sub" style="position:absolute;left:0;right:0;top:70px;font-size:14px;display:flex;align-items:center;gap:6px">'
           f'{mr("album", 16)}来自 {ARCH} · {UP}<span class="acc" style="font-weight:600">已关注</span></div>')
    rows = ''.join(qrow4(i, t, d, cur=(i == 0), focus=(i == (1 if menu else 0)), n=NB(7) if i == 0 else None) for i, (t, d) in enumerate(QUEUE[:5]))
    body = (rail4('music', 0, n=(1, 2) if (n and not menu) else None) + '<div class="ncontent">' + head + src
            + f'<div style="position:absolute;left:0;right:0;top:100px">{rows}</div>' + minibar4(n and not menu) + '</div>')
    if menu:
        body += ('<div class="nscrim"></div><div class="ndlg" style="width:420px"><div class="h">春日来信</div><div class="sub" style="font-size:13px">P2/12 · '
                 + ARCH + '</div><div style="margin-top:12px">'
                 + opt4('下一首播放', 'low_priority', focus=True, n=N(1), tag='keep') + opt4('喜欢这首歌', 'favorite_border', n=N(2), tag='keep')
                 + opt4('加入歌单', 'playlist_add', n=N(3), tag='keep') + opt4('从队列移除', 'remove_circle_outline', red=True, fam='mo', n=N(4), tag='chg')
                 + f'</div><div class="btns">{nb("取消", n=N(5), tag="keep")}</div></div>')
    return page(body, CSS)


def v4_player_bg():
    lyr = ''.join(f'<div class="lrc4{" on" if i == 2 else ""}">{l}</div>' for i, l in enumerate(LYRICS))
    return ('<div class="pic" style="background:#000"></div>'
            f'<div style="position:absolute;left:96px;top:96px;width:280px;display:flex;flex-direction:column;align-items:center">'
            f'<div style="width:200px;height:200px;border-radius:16px;background:url({IMG(COV)}) center/cover"></div>'
            f'<div style="font-size:20px;font-weight:600;margin-top:16px">晚风</div><div style="font-size:15px;color:rgba(255,255,255,.72);margin-top:4px">{UP}</div></div>'
            f'<div style="position:absolute;left:440px;right:96px;top:110px">{lyr}</div>')


def v4_player(menu=None, n=True):
    N = (lambda k: k) if n else (lambda k: None)
    F = lambda k: ' f' if (menu is None and k == 'play') else ''
    top = ('<div class="vtopg"></div><div class="vtitle"><span class="t">晚风</span>'
           f'<span class="m">P1/12 · 1080P · {UP}</span></div>')
    sk = (f'<div class="vseek"{at(N(1), "keep")}><span>01:12</span><div class="bar"><i style="width:25%"></i></div><span>04:48</span></div>')
    qopen = ' style="background:rgba(255,255,255,.34)"' if menu == 'quality' else ''
    pills = (f'<span class="vp ic"{at(N(2), "keep")}>{mr("skip_previous")}</span>'
             f'<span class="vp big{F("play")}"{at(N(3), "chg")}>{mr("pause")}</span>'
             f'<span class="vp ic"{at(N(4), "keep")}>{mr("skip_next")}</span><span style="width:8px"></span>'
             f'<span class="vp"{at(N(5), "add")}>{mr("repeat")}列表循环</span>'
             f'<span class="vp"{at(N(6), "chg")}{qopen}>{mo("high_quality")}1080P</span>'
             f'<span class="vp"{at(N(7), "keep")}>{mo("videocam")}显示画面</span>'
             f'<span class="vp"{at(N(8), "keep")}>{mr("queue_music")}正在播放</span>'
             f'<span class="vp"{at(N(9), "keep")}>{mo("lyrics")}选择歌词</span>'
             f'<span class="vp"{at(N(10), "chg")}>{mr("memory")}Mpv</span>'
             f'<span class="vp ic"{at(N(11), "keep")}>{mo("settings")}</span>')
    line = ('<div style="position:absolute;left:0;right:0;bottom:0;height:3px;background:rgba(255,255,255,.16);z-index:6">'
            '<i style="position:absolute;left:0;top:0;bottom:0;width:25%;background:#4D9BFF"></i></div>')
    body = v4_player_bg() + top + '<div class="vbotg"></div>' + sk + f'<div class="vpills" style="gap:6px">{pills}</div>' + line
    if menu == 'quality':
        body += ('<div class="nmenu" style="left:296px;bottom:76px;width:150px"><div class="mh">音质</div>'
                 + opt4('1080P+') + opt4('1080P', cur=True, focus=True) + opt4('720P') + opt4('480P') + '</div>')
    if menu == 'queue':
        rows = ''.join(qrow4(i, t, d, cur=(i == 0), focus=(i == 0), thumb=False) for i, (t, d) in enumerate(QUEUE[:8]))
        body += (f'<div class="npanel"><div class="phd"><span class="t">正在播放<span class="sub" style="font-size:14px;font-weight:400;margin-left:6px">12 首</span></span>'
                 f'<span class="nb sm">{mr("repeat", 18)}列表循环{mr("arrow_drop_down", 20)}</span>'
                 f'<span class="nb ic sm">{mr("playlist_remove", 20)}</span><span class="nb ic sm">{mr("close", 20)}</span></div>'
                 f'<div style="flex:1;overflow:hidden;padding:4px 4px 0">{rows}</div><div class="nhint">返回键关闭 · 长按确认或菜单键：更多操作</div></div>')
    return page(body, CSS)


def plcard4(name, cnt, cover, pinned=False, liked=False, focus=False, n=None, tag='keep'):
    bg = f'background-image:url({IMG(cover)})' if cover else 'background:rgba(16,121,249,.18)'
    inner = '' if cover else f'<div style="position:absolute;inset:0;display:grid;place-items:center">{mr("favorite", 40, "#7DB6FF")}</div>'
    pin = f'<span class="nchip" style="left:6px;top:6px">{mr("push_pin", 13)}置顶</span>' if pinned and not liked else ''
    return (f'<div class="pl{" pf" if focus else ""}"{at(n, tag)}><div class="cv" style="{bg}">{inner}{pin}<span class="nchip" style="right:6px;bottom:6px">{cnt} 首</span></div>'
            f'<div class="nm">{name}</div></div>')


def v4_playlists(n=True):
    N = (lambda k: k) if n else (lambda k: None)
    head = (f'<div style="position:absolute;left:0;right:0;top:28px;display:flex;align-items:center;gap:10px"><span style="font-size:20px;font-weight:600">歌单</span>'
            f'<span class="sub" style="font-size:14px">4 个</span><span style="flex:1"></span>'
            + nb('导入歌单', 'download', 'sm', n=N(8), tag='keep') + nb('新建歌单', 'playlist_add', 'sm', n=N(9), tag='keep') + nb('全部同步', 'sync', 'sm', n=N(10), tag='keep') + '</div>')
    shelf = ('<div style="position:absolute;left:0;right:0;top:80px;display:grid;grid-template-columns:repeat(6,minmax(0,1fr));gap:14px">'
             + ''.join(plcard4(*p, focus=(i == 0), n=N(11) if i == 0 else None) for i, p in enumerate(PLAYLISTS)) + '</div>')
    def folder(name, cnt, cover, synced, nn=None):
        return (f'<div class="nc"{at(nn, "keep")}><div class="cv" style="background-image:url({IMG(cover)})"><span class="nchip" style="right:6px;bottom:6px">{cnt} 首</span></div>'
                f'<div class="ninfo" style="padding:8px 10px 10px"><div class="x"><div class="ct">{name}</div><div class="st">{synced}</div></div></div></div>')
    folders = ('<div class="nsec" style="position:absolute;left:0;top:222px;margin:0">哔哩哔哩收藏夹 3 个</div>'
               '<div class="ngrid" style="top:250px">' + ''.join(folder(*f, nn=N(12) if i == 0 else None) for i, f in enumerate(FOLDERS)) + '</div>')
    body = rail4('music', 2, n=(1, 2) if n else None) + '<div class="ncontent">' + head + shelf + folders + minibar4() + '</div>'
    return page(body, CSS)


def v4_playlist(n=True):
    N = (lambda k: k) if n else (lambda k: None)
    acts = (f'<span class="sub" style="font-size:14px">18 首</span>' + nb('多选', 'checklist', 'sm', n=N(2), tag='keep')
            + nb('正在播放', 'music_note', 'sm', n=N(3), tag='keep') + nb('播放全部', 'play_arrow', 'sm pri f', n=N(4), tag='chg'))
    rows = ''.join(qrow4(i, t, d, n=N(5) if i == 0 else None, tag='chg') for i, (t, d) in enumerate(QUEUE[:6]))
    body = ('<div class="ncontent" style="left:48px">' + hdr4('周末歌单', n=N(1), actions=acts)
            + f'<div style="position:absolute;left:0;right:0;top:80px">{rows}</div>' + '</div>')
    return page(body, CSS)


def v4_daily(n=True):
    N = (lambda k: k) if n else (lambda k: None)
    extra = ('<span style="flex:1"></span>' + nb('默认收藏夹', 'folder', 'sm', fam='mo', n=N(9), tag='keep') + nb('重新生成', 'refresh', 'sm', n=N(10), tag='keep'))
    cards = [vcard4(v, focus=(i == 0), badge='', n=N(11) if i == 0 else None, tag='chg') for i, v in enumerate(MV)]
    body = (rail4('music', 3, n=(1, 2) if n else None) + '<div class="ncontent">' + tabs4(['每日', '动态', '排行'], 0, n=N(8), extra=extra)
            + '<div class="ngrid" style="top:76px">' + ''.join(cards) + '</div>' + minibar4() + '</div>')
    return page(body, CSS)


def v4_add(n=True):
    N = (lambda k: k) if n else (lambda k: None)
    bg = v4_now(n=False).split('<div class="tv">', 1)[1].rsplit('</div><div class="syn">', 1)[0]
    dlg = ('<div class="nscrim"></div><div class="ndlg" style="width:420px"><div class="h">加入歌单</div><div class="sub" style="font-size:13px">晚风 · ' + ARCH + '</div>'
           '<div style="margin-top:12px">'
           + opt4('喜欢的歌曲', 'favorite', right='<span class="sub" style="font-size:13px">已在 · 32 首</span>', icolor='#7DB6FF', n=N(1), tag='chg')
           + opt4('周末歌单', 'queue_music', right='<span class="sub" style="font-size:13px">18 首</span>', focus=True, n=N(2), tag='keep')
           + opt4('通勤路上', 'queue_music', right='<span class="sub" style="font-size:13px">已在 · 40 首</span>')
           + opt4('古风', 'queue_music', right='<span class="sub" style="font-size:13px">12 首</span>')
           + opt4('新建歌单并加入', 'add', n=N(3), tag='chg') + '</div>'
           f'<div class="btns">{nb("取消", n=N(4), tag="keep")}</div></div>')
    return page(bg + dlg, CSS)


OUT = {
    'v3-now': v3_now(), 'v4-now': v4_now(),
    'v3-song-menu': v3_now(menu=True), 'v4-song-menu': v4_now(menu=True),
    'v3-player': v3_player(), 'v4-player': v4_player(),
    'v3-player-quality': v3_player('quality'), 'v4-player-quality': v4_player('quality', n=False),
    'v3-player-queue': v3_player('queue'), 'v4-player-queue': v4_player('queue', n=False),
    'v3-playlists': v3_playlists(), 'v4-playlists': v4_playlists(),
    'v3-playlist': v3_playlist(), 'v4-playlist': v4_playlist(),
    'v3-daily': v3_daily(), 'v4-daily': v4_daily(),
    'v3-add': v3_add(), 'v4-add': v4_add(),
}
if __name__ == '__main__':
    write(HERE, OUT)
