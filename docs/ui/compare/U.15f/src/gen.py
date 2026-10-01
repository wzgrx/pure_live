"""U.15f TV video (VOD) mockups: pure_live_TV restored (v3-*) and the new
design (v4-*). Shared pieces live in tvkit.py (also used by U.15g, U.15h).
    python3 docs/ui/compare/U.15f/src/gen.py && python3 tools/ui/mock/render.py docs/ui/compare/U.15f/src/ --annotate
pure_live_TV sources (~/ref/pure_live_TV/lib):
  features/home/home_page.dart            mode button, video rail (:162-185)
  modules/video/pages/home/video_home_page.dart, widgets/video_card.dart
  modules/video/pages/archive/video_detail_page.dart
  modules/video/pages/discover/video_season_page.dart, video_region_page.dart, video_search_results.dart
  modules/video/pages/playback/video_player_widgets.dart, widgets/video_control_bar.dart,
      video_quality_menu.dart, video_comments_panel.dart, video_parts_panel.dart
  modules/video/pages/personal/*.dart, modules/vod/pages/*.dart, modules/vod/widgets/bilibili_login_gate.dart
"""
import os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from tvkit import *  # noqa: E402,F401,F403

V = VIDEOS
CSS = '''
.dm3{position:absolute;white-space:nowrap;color:#fff;font:600 30px 'Noto Sans SC';text-shadow:0 0 2px #000,0 0 2px #000,0 0 3px #000}
.dm4{position:absolute;white-space:nowrap;color:#fff;font:600 17px 'Noto Sans SC';text-shadow:0 0 1px #000,0 0 1px #000,0 0 2px #000;z-index:2}
.pill3{height:52px;padding:0 18px;border-radius:17px;background:rgba(255,255,255,.08);display:inline-flex;align-items:center;gap:8px;font-size:20px;color:#fff;white-space:nowrap;flex:none}
.pill3 .mr,.pill3 .mo{font-size:24px;color:rgba(255,255,255,.7)}
.pill3.sel{background:#00A1FF;font-weight:600}.pill3.sel .mr{color:#fff}
.dmk.s{width:20px;height:20px}
'''
DM3 = [(820, 210, '这个机位太绝了'), (300, 300, '前排支持！'), (1180, 380, '延时摄影yyds'), (560, 470, '第二个镜头是哪里')]
DM4 = [(410, 105, '这个机位太绝了'), (150, 150, '前排支持！'), (590, 190, '延时摄影yyds'), (280, 235, '第二个镜头是哪里')]


# ======================================================================
#  v3 (pure_live_TV)
# ======================================================================
def grid3(cards, cols=4, top=0, row_h=323):
    return (f'<div class="grid3" style="grid-template-columns:repeat({cols},minmax(0,1fr));grid-auto-rows:{row_h}px;padding-top:{24 + top}px">'
            + ''.join(cards) + '</div>')


def v3_home():
    cards = [vcard3(v, focus=(i == 0)) for i, v in enumerate(V)]
    return page(rail3('video', 2) + '<div class="pane">' + tabs3(['动态', '推荐', '热门'], 1) + grid3(cards) + '</div>', CSS, restore=True)


def chip_action3(icon, label, fam='mo', active=False):
    c = '#00A1FF' if active else '#fff'
    bg = 'rgba(0,161,255,.2)' if active else '#1F1F1F'
    return (f'<span style="display:inline-flex;align-items:center;gap:8px;padding:10px 16px;border-radius:24px;background:{bg};'
            f'font-size:14px;font-weight:600;color:{c}">{(mr if fam == "mr" else mo)(icon, 22, c)}{label}</span>')


def part3(i, title, dur, focus=False):
    st = 'background:#1E3948;border-color:#00A1FF' if focus else ''
    return (f'<div style="height:76px;display:flex;align-items:center;padding:0 16px;border-radius:18px;background:#1F1F1F;border:2px solid transparent;margin-bottom:8px;{st}">'
            f'<span style="width:40px;font-size:18px;font-weight:500">{i}</span><span style="flex:1;font-size:18px;font-weight:500">{title}</span>'
            f'<span style="font-size:16px;font-weight:500">{dur}</span></div>')


def v3_detail():
    v = V[0]
    head = (f'<div style="display:flex;gap:32px;align-items:flex-start">'
            f'<div style="width:400px;height:225px;border-radius:24px;background:url({IMG(v[2])}) center/cover;position:relative;flex:none">'
            f'<span class="b3" style="position:absolute;left:14px;top:14px;background:#1F1F1F">生活</span>'
            f'<span class="b3" style="position:absolute;right:14px;bottom:12px;background:#1F1F1F">12:34</span></div>'
            f'<div style="flex:1;min-width:0"><div style="font-size:24px;font-weight:700;line-height:1.35">{v[0]}</div>'
            f'<div style="font-size:14px;font-weight:500;margin-top:10px">播放 12.3万 · 2048 条弹幕 · 2026-09-28 18:30</div>'
            f'<div style="display:inline-flex;align-items:center;gap:12px;padding:12px;border-radius:20px;background:#1F1F1F;margin-top:16px">'
            f'<span class="av3" style="background-image:url({AV})"></span><span style="font-size:16px;font-weight:700">山野影像</span>{mr("chevron_right", 24)}</div>'
            '<div style="display:flex;flex-wrap:wrap;gap:10px;margin-top:16px">'
            + chip_action3('thumb_up_alt', '点赞') + chip_action3('toll', '投币', 'mr') + chip_action3('star_outline', '收藏', 'mr')
            + chip_action3('recommend', '一键三连', 'mr') + chip_action3('watch_later', '稍后再看') + chip_action3('comment', '评论')
            + '</div></div></div>')
    desc = ('<div class="card3" style="margin-top:20px;padding:18px;font-size:14px;font-weight:500;line-height:1.55">'
            '这次带着两台相机在城市里跑了一整夜，从傍晚的天桥到凌晨的港口，一共十二个机位。拍摄参数和后期流程放在评论区置顶，有问题可以留言。</div>')
    parts = ('<div style="display:flex;align-items:center;gap:16px;padding:0 0 12px 8px;margin-top:24px">'
             '<span class="acc" style="font-size:20px;font-weight:600">播放列表（3）</span>' + b3('播放全部', 'play_circle_fill', size=28) + '</div>'
             + part3(1, '天桥与车流', '04:12') + part3(2, '港口的凌晨', '05:01') + part3(3, '拍摄参数和后期', '03:21'))
    rel = ('<div class="acc" style="font-size:20px;font-weight:600;margin:16px 0 10px 8px">相关视频</div><div style="display:flex;gap:12px">'
           + ''.join(f'<div style="width:300px;height:277px;flex:none">{vcard3(x, style="height:100%")}</div>' for x in V[3:9]) + '</div>')
    body = hdr3('视频详情', focus_back=True) + f'<div style="padding:24px">{head}{desc}{parts}{rel}</div>'
    return page(body, CSS, restore=True)


def ep3(title, badge='', focus=False):
    st = 'border-color:#00A1FF' if focus else ''
    b = f'<div style="font-size:14px;font-weight:500;color:#00A1FF;margin-top:6px">{badge}</div>' if badge else ''
    return (f'<div style="background:#1F1F1F;border-radius:12px;border:2px solid transparent;padding:0 14px;display:flex;flex-direction:column;justify-content:center;{st}">'
            f'<div style="font-size:16px;font-weight:500;line-height:1.3">{title}</div>{b}</div>')


EPS = ['启程', '北方的城', '旧友', '雪原', '灯塔守夜人', '海上的信', '第二个约定', '回声', '暖冬', '归途', '星图', '远行',
       '潮汐', '风暴前夜', '失物', '雾港', '回信', '石阶', '夜航', '星落', '旧照片', '火种', '守望', '黎明', '长桥', '归岸', '约定', '终章']


def v3_season():
    left = (f'<div style="width:340px;flex:none;display:flex;flex-direction:column">'
            f'<div style="width:340px;height:453px;border-radius:16px;background:url({IMG(304)}) center/cover"></div>'
            f'<div style="display:flex;align-items:center;margin-top:16px">{mr("star", 24, "#FFC107")}<span style="font-size:20px;font-weight:700;color:#FFC107;margin:0 16px 0 6px">9.6</span>'
            '<span style="font-size:16px;font-weight:500">28 话</span></div>'
            '<div style="display:flex;gap:8px;margin-top:10px">' + ''.join(
                f'<span style="padding:4px 12px;border-radius:14px;background:#1F1F1F;font-size:14px;font-weight:500">{s}</span>' for s in ['奇幻', '冒险', '治愈'])
            + '</div><div style="font-size:14px;line-height:1.55;margin-top:12px">少女带着一张旧星图出发，沿着北方的海岸线寻找父亲留下的十二座灯塔。每一座灯塔里，都藏着一段被时间遗忘的约定……</div></div>')
    tiles = ''.join(ep3(t, '会员' if i > 9 else '') for i, t in enumerate(EPS))
    right = ('<div style="flex:1;min-width:0;display:flex;flex-direction:column"><div style="display:flex;align-items:center;padding:0 0 12px 8px">'
             '<span class="acc" style="font-size:20px;font-weight:600">选集（28）</span><span style="flex:1"></span>' + b3('播放全部', 'play_circle_fill', size=28)
             + f'</div><div style="display:grid;grid-template-columns:repeat(4,minmax(0,1fr));grid-auto-rows:141px;gap:12px">{tiles}</div></div>')
    body = hdr3('星海旅人 第二季', focus_back=True) + f'<div style="padding:24px;display:flex;gap:32px">{left}{right}</div>'
    return page(body, CSS, restore=True)


def v3_player_chrome(sel=1):
    top = (f'<div style="position:absolute;top:24px;left:48px;right:48px;display:flex;align-items:center;z-index:5">{mo("movie", 28, "#00A1FF")}'
           f'<span style="flex:1;margin-left:10px;font-size:22px;font-weight:700">天桥与车流</span>'
           '<span style="font-size:18px;font-weight:500;color:rgba(255,255,255,.7);margin-left:12px">P1/3</span>'
           '<span style="font-size:18px;font-weight:500;color:rgba(255,255,255,.7);margin-left:12px">1080P 高清</span>'
           f'<span style="margin-left:12px;display:flex;align-items:center;gap:4px;font-size:18px;color:rgba(255,255,255,.7)">{mo("visibility", 20, "rgba(255,255,255,.7)")}1.2万</span>'
           '<span style="font-size:18px;font-weight:500;color:rgba(255,255,255,.7);margin-left:12px">山野影像</span></div>')
    pills = [('skip_previous', '上一集', 'mr'), ('pause', '播放', 'mr'), ('skip_next', '下一集', 'mr'), ('replay_10', '快退10秒', 'mr'),
             ('forward_10', '快进10秒', 'mr'), ('speed', '1.0x', 'mr'), ('high_quality', '1080P 高清', 'mo'), ('playlist_play', '选集', 'mr'),
             ('subtitles', '弹幕开', 'mo'), ('comment', '评论', 'mo'), ('tune', '弹幕设置', 'mr'), ('closed_caption', '字幕关', 'mo'), ('aspect_ratio', '适应', 'mr')]
    row = ''.join(f'<span class="pill3{" sel" if i == sel else ""}">{(mr if f == "mr" else mo)(n)}{l}</span>' for i, (n, l, f) in enumerate(pills))
    bar = ('<div style="position:absolute;left:48px;right:48px;bottom:32px;padding:18px 24px;border-radius:24px;background:rgba(0,0,0,.72);border:1px solid rgba(0,161,255,.35);z-index:5">'
           '<div style="display:flex;align-items:center;gap:16px"><span style="font-size:18px;font-weight:500;color:rgba(255,255,255,.7)" class="t">01:46</span>'
           '<div style="flex:1;height:10px;border-radius:9px;border:1px solid rgba(255,255,255,.24);margin:8px 0;position:relative"><i style="position:absolute;left:2px;top:2px;bottom:2px;width:42%;border-radius:7px;background:#00A1FF"></i></div>'
           '<span style="font-size:18px;font-weight:500;color:rgba(255,255,255,.7)" class="t">04:12</span></div>'
           f'<div style="display:flex;gap:12px;margin-top:16px;overflow:hidden">{row}</div></div>')
    return top + bar


def v3_player(menu=None):
    dm = ''.join(f'<div class="dm3" style="left:{x}px;top:{y}px">{t}</div>' for x, y, t in DM3)
    line = ('<div style="position:absolute;left:0;right:0;bottom:0;height:5px;background:rgba(255,255,255,.16);z-index:6">'
            '<i style="position:absolute;left:0;top:0;bottom:0;width:42%;background:#00A1FF"></i></div>')
    body = f'<div class="pic" style="background-image:url({IMG(274)})"></div>{dm}' + v3_player_chrome(sel=None if menu else 1) + line
    if menu == 'quality':
        opts = [('1080P 高清', True), ('720P 高清', False), ('480P 清晰', False), ('360P 流畅', False)]
        rows = ''.join(
            f'<div style="height:56px;margin:0 12px 8px;padding:0 14px;border-radius:12px;display:flex;align-items:center;font-size:16px;font-weight:500;'
            f'background:{"rgba(0,161,255,.22)" if c else "rgba(255,255,255,.06)"};color:{"#00A1FF" if c else "#fff"};border:2px solid {"#00A1FF" if c else "transparent"}">'
            f'<span style="flex:1">{l}</span>{mr("check", 22, "#00A1FF") if c else ""}</div>' for l, c in opts)
        body += (f'<div style="position:absolute;top:100px;right:48px;width:320px;background:rgba(0,0,0,.86);border-radius:20px;border:1px solid rgba(0,161,255,.5);padding-bottom:8px;z-index:10">'
                 f'<div style="display:flex;align-items:center;padding:16px;gap:10px">{mo("high_quality", 26, "#00A1FF")}<span style="flex:1;font-size:18px;font-weight:600">画质</span>'
                 f'<span style="width:40px;height:40px;border-radius:20px;background:rgba(31,31,31,.45);display:grid;place-items:center">{mr("close", 22)}</span></div>{rows}</div>')
    if menu == 'comments':
        def tile(name, like, text, rep=0, focus=False):
            likest = 'border:1.5px solid #00A1FF;background:rgba(255,255,255,.12)' if focus else 'border:1.5px solid transparent'
            r = f'<div style="font-size:14px;font-weight:500;color:rgba(255,255,255,.54);margin-top:6px">共 {rep} 条回复，按 OK 展开</div>' if rep else ''
            return (f'<div style="margin-bottom:8px;padding:12px;border-radius:12px;background:rgba(255,255,255,.06)"><div style="display:flex;align-items:center">'
                    f'<span style="flex:1;font-size:14px;font-weight:600;color:#00A1FF">{name}</span>'
                    f'<span style="display:inline-flex;align-items:center;gap:4px;padding:4px 10px;border-radius:10px;{likest};font-size:14px;color:rgba(255,255,255,.54)">{mo("thumb_up_alt", 16, "rgba(255,255,255,.54)")}{like}</span></div>'
                    f'<div style="font-size:14px;font-weight:500;line-height:1.4;margin-top:6px">{text}</div>{r}</div>')
        tiles = (tile('风吹麦浪', '1,024', '第二个机位是在哪里拍的？港口那段的光线太好看了，求一个具体位置。', 23, True)
                 + tile('小林同学', '356', '延时摄影一晚上要换几块电池啊', 8) + tile('清欢', '88', '收藏了，周末就去试试') + tile('Aki', '61', '这个配乐叫什么名字？', 3)
                 + tile('早起的鸟', '40', '城市的夜晚原来这么安静'))
        body += (f'<div style="position:absolute;top:100px;bottom:100px;right:48px;width:620px;background:rgba(0,0,0,.88);border-radius:24px;border:1px solid rgba(0,161,255,.5);z-index:10;overflow:hidden">'
                 f'<div style="display:flex;align-items:center;padding:20px;gap:10px">{mo("comment", 28, "#00A1FF")}<span style="flex:1;font-size:20px;font-weight:600">评论</span>'
                 f'<span style="width:40px;height:40px;border-radius:20px;background:rgba(31,31,31,.45);display:grid;place-items:center">{mr("close", 22)}</span></div>'
                 f'<div style="padding:0 16px">{tiles}</div></div>')
    return page(body, CSS, restore=True)


def space_card3(v, focus=False):
    st = 'border-color:#00A1FF' if focus else ''
    return (f'<div style="background:#1F1F1F;border-radius:14px;border:2px solid transparent;display:flex;flex-direction:column;overflow:hidden;{st}">'
            f'<div style="flex:1;background:url({IMG(v[2])}) center/cover"></div><div style="padding:10px;font-size:14px;font-weight:500;line-height:1.4;height:59px;overflow:hidden">{v[0]}</div></div>')


def v3_space():
    stat = lambda v, l: f'<div><div style="font-size:18px;font-weight:700">{v}</div><div style="font-size:14px">{l}</div></div>'
    head = (f'<div style="margin:0 24px;padding:20px;border-radius:20px;background:#1F1F1F;display:flex;align-items:center;gap:20px">'
            f'<span style="width:96px;height:96px;border-radius:48px;background:url({AV}) center/cover;flex:none"></span>'
            '<div style="flex:1"><div style="font-size:24px;font-weight:700">山野影像</div><div style="font-size:14px;font-weight:500;margin-top:6px">用镜头记录城市的夜晚和山里的星空。商务合作请私信。</div>'
            f'<div style="display:flex;gap:24px;margin-top:8px">{stat("12.6万", "粉丝")}{stat("218", "关注")}{stat("356", "投稿")}</div></div>'
            + b3('取消关注', 'done', cls='sec', size=24) + '</div>')
    sec = ('<div style="display:flex;align-items:center;padding:0 24px;margin-top:12px"><span class="acc" style="font-size:20px;font-weight:600">投稿（356）</span>'
           '<span style="flex:1"></span>' + b3('最新发布', 'schedule', cls='sec', size=22) + '</div>')
    grid = ('<div style="display:grid;grid-template-columns:repeat(4,minmax(0,1fr));grid-auto-rows:345px;gap:6px;padding:12px 24px 0">'
            + ''.join(space_card3(v) for v in V[:8]) + '</div>')
    return page(hdr3('山野影像', focus_back=True) + head + sec + grid, CSS, restore=True)


def ptabs3(sel, focus=None):
    labels = ['UP主', '稍后再看', '收藏夹', '历史记录', '我的追番']
    out = '<div style="display:flex;justify-content:center;gap:14px;padding:16px 0 8px">'
    for i, l in enumerate(labels):
        bg = 'rgba(0,161,255,.18)' if i == sel else '#1F1F1F'
        c = '#00A1FF' if i == sel else '#fff'
        out += f'<span style="padding:12px 34px;border-radius:34px;background:{bg};color:{c};font-size:18px;font-weight:600;border:2px solid transparent">{l}</span>'
    return out + '</div>'


HIST = [(V[0], 2, '今天 20:31', '看到 01:46 / 04:12', 42), (V[1], 1, '今天 19:05', '已看完', 100), (V[5], 1, '昨天 23:12', '看到 18:40 / 41:07', 45),
        (V[6], 1, '09-28 21:40', '看到 02:10 / 04:48', 45), (V[9], 1, '09-27 10:02', '看到 05:30 / 1:12:45', 8)]


def v3_history():
    rows = ''
    for i, (v, p, t, prog, pc) in enumerate(HIST):
        st = 'border-color:#00A1FF' if i == 0 else ''
        pchip = f'<span style="padding:2px 8px;border-radius:6px;background:rgba(0,161,255,.14);color:#00A1FF;font-size:15px;font-weight:600;margin-right:10px">P{p}</span>' if p > 1 else ''
        done = prog == '已看完'
        rows += (f'<div style="margin-bottom:10px;padding:10px;border-radius:16px;background:#1F1F1F;border:2px solid transparent;display:flex;gap:16px;align-items:center;{st}">'
                 f'<div style="width:210px;height:122px;border-radius:10px;background:url({IMG(v[2])}) center/cover;position:relative;overflow:hidden;flex:none">'
                 f'<i style="position:absolute;left:0;right:0;bottom:0;height:4px;background:rgba(255,255,255,.24)"></i><i style="position:absolute;left:0;bottom:0;height:4px;width:{pc}%;background:#00A1FF"></i></div>'
                 f'<div style="flex:1;min-width:0"><div style="font-size:20px;font-weight:700">{v[0]}</div>'
                 f'<div style="display:flex;align-items:center;margin-top:6px">{pchip}<span style="font-size:16px;font-weight:500">{v[1]}</span></div>'
                 f'<div style="display:flex;align-items:center;gap:4px;margin-top:6px;font-size:16px">{mr("schedule", 20)}{t}<span style="width:10px"></span>{mr("play_circle_outline", 20)}'
                 f'<span style="{"color:#00A1FF;font-weight:500" if done else ""}">{prog}</span></div></div></div>')
    return page(rail3('video', 1) + '<div class="pane">' + ptabs3(3) + f'<div style="padding:24px">{rows}</div></div>', CSS, restore=True)


def v3_card_menu():
    cards = [vcard3(v) for v in V[:8]]
    over = (f'<div style="position:absolute;inset:0;background:rgba(0,0,0,.82);display:flex;align-items:center;justify-content:space-evenly;z-index:4">'
            f'{mo("watch_later", 30)}{mr("person_outline", 30)}</div>')
    c0 = cards[0].replace('<div class="vc"', '<div class="vc foc"', 1).replace('<div class="cvb">', over + '<div class="cvb">', 1)
    cards[0] = c0
    return page(rail3('video', 1) + '<div class="pane">' + ptabs3(1) + grid3(cards, top=-24) + '</div>', CSS, restore=True)


def v3_login():
    gate = ('<div class="st-wrap"><div style="padding:36px 48px;border-radius:24px;background:#1F1F1F;border:2.5px solid #00A1FF;box-shadow:0 0 20px rgba(0,161,255,.4);display:flex;flex-direction:column;align-items:center">'
            + mo('lock', 72, '#00A1FF') + '<div style="font-size:22px;font-weight:700;margin-top:18px">请先登录B站账号</div>'
            '<div style="font-size:16px;font-weight:500;margin-top:8px">登录后即可使用音乐和视频模式</div>'
            f'<div style="margin-top:20px;padding:12px 32px;border-radius:28px;background:#00A1FF;display:flex;align-items:center;gap:10px;font-size:18px;font-weight:600">{mr("qr_code_scanner", 26)}扫码登录</div></div></div>')
    return page(rail3('video', 2) + f'<div class="pane">{gate}</div>', CSS, restore=True)


REGIONS = ['动画', '游戏', '音乐', '知识', '生活', '鬼畜', '时尚', '娱乐', '影视', '纪录片']


def v3_error():
    dot = '<span style="width:20px;height:20px;border-radius:5px;background:#5A5A5A;flex:none"></span>'
    body = (rail3('video', 3) + '<div class="pane">' + tabs3(REGIONS, 3, icons=[dot] * 10)
            + state3('wifi_off', '数据加载失败', 'DioException [connection timeout]: The request connection took longer than 0:00:15.000000 and it was aborted.', top=114)
            + '</div>')
    return page(body, CSS, restore=True)


def v3_search():
    words = ['城市夜景延时', '量子纠缠', '露营装备', '魂斗罗', '古筝弹唱', '八段锦', '橘猫', '手绘板', '英语口语', '夜跑', '编程入门', '读书会']
    chips = ''.join(
        f'<span style="display:inline-flex;align-items:center;gap:8px;padding:10px 20px;border-radius:24px;background:#1F1F1F;border:2px solid {"#00A1FF" if i == 0 else "transparent"};font-size:16px">'
        f'<b style="font-weight:700;color:{"#FF5252" if i < 3 else "#fff"}">{i + 1}</b><span style="font-weight:500">{w}</span></span>' for i, w in enumerate(words))
    top = ('<div style="display:flex;align-items:center;gap:16px;padding:16px 24px 8px">'
           '<div style="width:560px;height:64px;border-radius:16px;background:#1F1F1F;display:flex;align-items:center;padding:0 20px;font-size:18px;color:rgba(255,255,255,.6)">搜索全站视频</div>'
           + b3('搜索直播', 'search', size=28) + '</div>')
    board = (f'<div style="padding:24px"><div style="display:flex;align-items:center;gap:8px">{mr("local_fire_department", 26, "#00A1FF")}'
             f'<span class="acc" style="font-size:20px;font-weight:600">热搜榜</span></div><div style="display:flex;flex-wrap:wrap;gap:12px;margin-top:16px">{chips}</div></div>')
    return page(rail3('video', 0) + f'<div class="pane">{top}{board}</div>', CSS, restore=True)


# ======================================================================
#  new design
# ======================================================================
def grid4(cards, top=76):
    return f'<div class="ngrid" style="top:{top}px">' + ''.join(cards) + '</div>'


def v4_home(n=True):
    N = (lambda k: k) if n else (lambda k: None)
    cards = [vcard4(v, focus=(i == 0), n=N(9) if i == 0 else None, tag='keep') for i, v in enumerate(V)]
    body = (rail4('video', 2, n=(1, 2) if n else None) + '<div class="ncontent">' + tabs4(['动态', '推荐', '热门'], 1, n=N(8)) + grid4(cards) + '</div>')
    return page(body, CSS)


def v4_home_rail():
    cards = [vcard4(v) for v in V]
    body = (rail4('video', 2, focus=2, expanded=True) + '<div class="ncontent">' + tabs4(['动态', '推荐', '热门'], 1) + grid4(cards) + '</div>'
            + '<div class="dim"></div>')
    return page(body, CSS)


def chip4(icon, label, fam='mo', on=False, n=None, tag=None, focus=False):
    cls = 'nb sm' + (' on' if on else '') + (' f' if focus else '')
    return f'<span class="{cls}"{at(n, tag)}>{(mr if fam == "mr" else mo)(icon, 18)}{label}</span>'


def prow4(i, title, dur, cur=False, focus=False, n=None, prog=None):
    cls = 'nrow' + (' fr' if focus else '')
    lead = mr('play_arrow', 20, '#7DB6FF') if cur else f'<span class="sub" style="font-size:14px">{i}</span>'
    p = f'<span class="sub" style="font-size:13px">{prog}</span>' if prog else ''
    return (f'<div class="{cls}" style="min-height:40px;padding:6px 14px;margin-bottom:8px"{at(n, "keep")}><span style="width:22px;display:grid;place-items:center">{lead}</span>'
            f'<div class="x"><div class="a" style="font-size:14px">{title}</div></div>{p}<span class="v tnum">{dur}</span></div>')


def v4_detail(n=True):
    N = (lambda k: k) if n else (lambda k: None)
    v = V[0]
    cover = (f'<div style="position:absolute;left:0;top:76px;width:320px;height:180px;border-radius:16px;background:url({IMG(v[2])}) center/cover">'
             f'<span class="nchip" style="left:8px;top:8px">生活</span><span class="nchip" style="right:8px;bottom:8px">12:34</span></div>')
    info = ('<div style="position:absolute;left:336px;right:0;top:76px">'
            f'<div style="font-size:18px;font-weight:600;line-height:26px">{v[0]}</div>'
            '<div class="sub" style="font-size:14px;margin-top:6px">播放 12.3万 · 2048 条弹幕 · 2026-09-28 18:30</div>'
            f'<div class="nrow" style="display:inline-flex;min-height:44px;padding:6px 12px 6px 6px;margin-top:12px;border-radius:22px;gap:10px"{at(N(3), "keep")}>'
            f'<span class="nav" style="width:32px;height:32px;border-radius:16px;background-image:url({AV})"></span><span class="a" style="font-size:15px">山野影像</span>'
            f'{mr("chevron_right", 20, "rgba(243,245,247,.72)")}</div>'
            '<div class="sub" style="font-size:14px;line-height:22px;margin-top:12px;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden">'
            '这次带着两台相机在城市里跑了一整夜，从傍晚的天桥到凌晨的港口，一共十二个机位。拍摄参数和后期流程放在评论区置顶，有问题可以留言。</div></div>')
    acts = ('<div style="position:absolute;left:0;right:0;top:272px;display:flex;gap:10px;align-items:center">'
            + f'<span class="nb pri f"{at(N(4), "add")}>{mr("play_arrow", 22)}继续 P1 · 01:46</span>'
            + chip4('thumb_up_alt', '点赞', n=N(5), tag='keep') + chip4('toll', '投币', 'mr', n=N(6), tag='keep') + chip4('star', '已收藏', 'mr', on=True, n=N(7), tag='chg')
            + chip4('recommend', '一键三连', 'mr', n=N(8), tag='keep') + chip4('watch_later', '稍后再看', n=N(9), tag='keep') + chip4('comment', '评论', n=N(10), tag='keep')
            + '</div>')
    parts = ('<div style="position:absolute;left:0;right:0;top:326px"><div class="nsec">播放列表（3）</div>'
             + prow4(1, '天桥与车流', '04:12', cur=True, n=N(11), prog='看到 01:46') + prow4(2, '港口的凌晨', '05:01') + prow4(3, '拍摄参数和后期', '03:21')
             + '<div class="nsec" style="margin-top:14px">相关视频</div></div>')
    body = '<div class="ncontent" style="left:48px">' + hdr4('视频详情', n=N(1)) + cover + info + acts + parts + '</div>'
    return page(body, CSS)


def ep4(no, title, badge='', focus=False, cur=False, n=None):
    cls = 'nrow' + (' fr' if focus else '')
    b = f'<span class="nchip" style="position:static;background:rgba(16,121,249,.25);color:#9CC6FF;height:18px;font-size:12px">{badge}</span>' if badge else ''
    return (f'<div class="{cls}" style="min-height:52px;padding:6px 12px;flex-direction:column;align-items:flex-start;gap:0;justify-content:center"{at(n, "chg")}>'
            f'<div style="display:flex;gap:6px;align-items:center;width:100%"><span style="font-size:14px;font-weight:600;{"color:#7DB6FF" if cur else ""}">第 {no} 话</span>{b}</div>'
            f'<div class="sub" style="font-size:13px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;width:100%">{title}</div></div>')


def v4_season(n=True):
    N = (lambda k: k) if n else (lambda k: None)
    left = (f'<div style="position:absolute;left:0;top:76px;width:180px">'
            f'<div style="width:180px;height:240px;border-radius:16px;background:url({IMG(304)}) center/cover"></div>'
            f'<div style="display:flex;align-items:center;gap:4px;margin-top:10px">{mr("star", 18, "#FFC107")}<b style="font-size:16px;color:#FFC107">9.6</b>'
            '<span class="sub" style="font-size:14px;margin-left:8px">28 话</span></div><div class="sub" style="font-size:14px;margin-top:2px">奇幻 · 冒险 · 治愈</div>'
            '<div class="sub" style="font-size:14px;line-height:22px;margin-top:6px;display:-webkit-box;-webkit-line-clamp:4;-webkit-box-orient:vertical;overflow:hidden">'
            '少女带着一张旧星图出发，沿着北方的海岸线寻找父亲留下的十二座灯塔。每一座灯塔里，都藏着一段被时间遗忘的约定……</div></div>')
    tiles = ''.join(ep4(i + 1, t, '会员' if i > 9 else '', focus=(i == 0), n=N(4) if i == 0 else None) for i, t in enumerate(EPS))
    right = ('<div style="position:absolute;left:204px;right:0;top:76px"><div style="display:flex;align-items:center;gap:10px;margin-bottom:12px">'
             '<span class="nsec" style="margin:0">选集（28）</span><span style="flex:1"></span>'
             + nb('播放全部', 'play_circle', 'sm', n=N(3), tag='keep')
             + f'</div><div style="display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:10px">{tiles}</div></div>')
    body = '<div class="ncontent" style="left:48px">' + hdr4('星海旅人 第二季', n=N(1)) + left + right + '</div>'
    return page(body, CSS)


def v4_player_chrome(focus='play', n=True, seek=False, open_=None):
    N = (lambda k: k) if n else (lambda k: None)
    F = lambda k: ' f' if focus == k else ''
    top = ('<div class="vtopg"></div><div class="vtitle"><span class="t">天桥与车流</span>'
           '<span class="m">P1/3 · 1080P 高清 · 1.2万人在看 · 山野影像</span></div>')
    seek_cls = 'vseek f2' if seek else 'vseek'
    sk = (f'<div class="{seek_cls}"{at(N(1), "keep")}><span>01:46</span><div class="bar"><i style="width:42%"></i>' + ('<u style="left:42%"></u>' if seek else '')
          + '</div><span>04:12</span></div>')
    pills = (f'<span class="vp ic{F("prev")}"{at(N(2), "keep")}>{mr("skip_previous")}</span>'
             f'<span class="vp big{F("play")}"{at(N(3), "chg")}>{mr("pause")}</span>'
             f'<span class="vp ic{F("next")}"{at(N(4), "keep")}>{mr("skip_next")}</span><span style="width:10px"></span>'
             f'<span class="vp{F("parts")}"{at(N(5), "keep")}>{mr("playlist_play")}选集 P1/3</span>'
             f'<span class="vp{F("q")}"{at(N(6), "chg")}' + (' style="background:rgba(255,255,255,.34)"' if open_ == 'q' else '') + f'>{mo("high_quality")}1080P 高清</span>'
             f'<span class="vp{F("speed")}"{at(N(7), "keep")}>{mr("speed")}1.0x</span>'
             f'<span class="vp ic on{F("dm")}"{at(N(8), "chg")}><span class="dmk open s"></span></span>'
             f'<span class="vp ic{F("dms")}"{at(N(9), "chg")}><span class="dmk set s"></span></span>'
             f'<span class="vp dis{F("sub")}"{at(N(10), "chg")}>{mo("closed_caption")}无字幕</span>'
             f'<span class="vp{F("cmt")}"{at(N(11), "keep")}>{mo("comment")}评论</span>'
             f'<span class="vp{F("fit")}"{at(N(12), "keep")}>{mr("aspect_ratio")}适应</span>')
    line = ('<div style="position:absolute;left:0;right:0;bottom:0;height:3px;background:rgba(255,255,255,.16);z-index:6">'
            '<i style="position:absolute;left:0;top:0;bottom:0;width:42%;background:#4D9BFF"></i></div>')
    return top + '<div class="vbotg"></div>' + sk + f'<div class="vpills">{pills}</div>' + line


def v4_player(menu=None, n=True):
    dm = ''.join(f'<div class="dm4" style="left:{x}px;top:{y}px">{t}</div>' for x, y, t in DM4)
    focus = {'quality': None, 'comments': None}.get(menu, 'play')
    body = f'<div class="pic" style="background-image:url({IMG(274)})"></div>{dm}' + v4_player_chrome(focus, n and not menu, open_='q' if menu == 'quality' else None)
    if menu == 'quality':
        body += ('<div class="nmenu" style="left:330px;bottom:76px;width:170px">'
                 + opt4('1080P 高清', cur=True, focus=True) + opt4('720P 高清') + opt4('480P 清晰') + opt4('360P 流畅') + '</div>')
    if menu == 'comments':
        body += comments_panel4()
    return page(body, CSS)


COMMENTS = [('风吹麦浪', '2 小时前', '第二个机位是在哪里拍的？港口那段的光线太好看了，求一个具体位置。', '1,024', 23, True),
            ('小林同学', '3 小时前', '延时摄影一晚上要换几块电池啊', '356', 8, False),
            ('清欢', '昨天', '收藏了，周末就去试试', '88', 0, False),
            ('Aki', '昨天', '这个配乐叫什么名字？', '61', 3, False)]


def comment4(name, t, text, like, rep, top=False, focus=None, n=None):
    """One comment, same component in the player panel and the comments page."""
    pin = '<span class="nchip" style="position:static;background:rgba(16,121,249,.25);color:#9CC6FF;height:18px;font-size:12px">置顶</span>' if top else ''
    fl = ' f' if focus == 'like' else ''
    fr_ = ' f' if focus == 'rep' else ''
    reps = f'<span class="nb sm{fr_}" style="height:28px;font-size:13px;background:transparent;padding:0 8px"{at(n and n + 1, "chg")}>{mo("forum", 16)}{rep} 条回复</span>' if rep else ''
    return (f'<div style="padding:10px 12px;border-radius:12px;background:#152234;margin-bottom:8px">'
            f'<div style="display:flex;align-items:center;gap:8px"><span class="nav" style="width:28px;height:28px;border-radius:14px;background-image:url({AV})"></span>'
            f'<span style="font-size:14px;font-weight:600">{name}</span>{pin}<span class="sub" style="font-size:13px">{t}</span></div>'
            f'<div style="font-size:14px;line-height:22px;margin:6px 0 4px">{text}</div>'
            f'<div style="display:flex;gap:6px"><span class="nb sm{fl}" style="height:28px;font-size:13px;background:transparent;padding:0 8px"{at(n, "keep")}>{mo("thumb_up_alt", 16)}{like}</span>{reps}</div></div>')


def comments_panel4(n=None):
    rows = ''.join(comment4(*c, focus='like' if i == 0 else None, n=(n + 3) if (n and i == 0) else None) for i, c in enumerate(COMMENTS))
    return (f'<div class="npanel"><div class="phd"><span class="t">评论</span>'
            + tabs4(['热门', '最新'], 0, n=n and n + 1, top=0, extra='').replace('class="ntabs"', 'class="ntabs" style="position:static;width:auto"').replace(' style="top:0px"', '')
            + f'<span class="nb ic sm"{at(n and n + 2, "keep")}>{mr("close", 20)}</span></div>'
            f'<div style="flex:1;overflow:hidden">{rows}</div><div class="nhint">返回键关闭</div></div>')


def v4_space(n=True):
    N = (lambda k: k) if n else (lambda k: None)
    stat = lambda v, l: f'<span><b style="font-size:15px">{v}</b><span class="sub" style="font-size:13px;margin-left:4px">{l}</span></span>'
    head = (f'<div style="position:absolute;left:0;right:0;top:76px;display:flex;align-items:center;gap:16px">'
            f'<span style="width:64px;height:64px;border-radius:32px;background:url({AV}) center/cover;flex:none"></span>'
            '<div style="flex:1;min-width:0"><div style="font-size:18px;font-weight:600">山野影像</div>'
            '<div class="sub" style="font-size:14px;margin-top:2px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">用镜头记录城市的夜晚和山里的星空。商务合作请私信。</div>'
            f'<div style="display:flex;gap:16px;margin-top:4px">{stat("12.6万", "粉丝")}{stat("218", "关注")}{stat("356", "投稿")}</div></div>'
            + nb('已关注', 'check', n=N(3), tag='chg') + '</div>')
    sec = ('<div style="position:absolute;left:0;right:0;top:156px;display:flex;align-items:center"><span class="nsec" style="margin:0">投稿（356）</span><span style="flex:1"></span>'
           + f'<span class="nb sm"{at(N(4), "chg")}>{mr("schedule", 18)}最新发布{mr("arrow_drop_down", 20)}</span></div>')
    cards = [vcard4(v, focus=(i == 0), n=N(5) if i == 0 else None, tag='chg') for i, v in enumerate(V[:8])]
    body = '<div class="ncontent" style="left:48px">' + hdr4('山野影像', n=N(1)) + head + sec + grid4(cards, top=196) + '</div>'
    return page(body, CSS)


def ptabs4(sel, n=None):
    return tabs4(['UP主', '稍后再看', '收藏夹', '历史记录', '我的追番'], sel, n=n)


def hrow4(v, p, t, prog, pc, focus=False, n=None):
    cls = 'nrow' + (' fr' if focus else '')
    done = prog == '已看完'
    meta = (f'P{p} · ' if p > 1 else '') + f'{v[1]} · {t}'
    return (f'<div class="{cls}" style="padding:8px;gap:14px;margin-bottom:10px"{at(n, "keep")}>'
            f'<div style="width:128px;height:72px;border-radius:8px;background:url({IMG(v[2])}) center/cover;position:relative;overflow:hidden;flex:none">'
            f'<div class="nprog"><i style="width:{pc}%"></i></div></div><div class="x"><div class="a">{v[0]}</div><div class="b">{meta}</div>'
            f'<div class="b" style="{"color:#7DB6FF" if done else ""}">{prog}</div></div></div>')


def v4_history(n=True):
    N = (lambda k: k) if n else (lambda k: None)
    rows = ''.join(hrow4(*h, focus=(i == 0), n=N(9) if i == 0 else None) for i, h in enumerate(HIST))
    body = (rail4('video', 1, n=(1, 2) if n else None) + '<div class="ncontent">' + ptabs4(3, n=N(8))
            + f'<div style="position:absolute;left:0;right:0;top:76px">{rows}</div></div>')
    return page(body, CSS)


def v4_card_menu(n=True):
    N = (lambda k: k) if n else (lambda k: None)
    cards = [vcard4(v, focus=(i == 0)) for i, v in enumerate(V[:8])]
    v = V[0]
    dlg = ('<div class="nscrim"></div><div class="ndlg" style="width:440px">'
           f'<div style="display:flex;gap:12px;align-items:center"><span style="width:96px;height:54px;border-radius:8px;background:url({IMG(v[2])}) center/cover;flex:none"></span>'
           f'<div style="min-width:0"><div class="h" style="font-size:16px;line-height:22px">{v[0]}</div><div class="sub" style="font-size:13px">{v[1]} · 12:34</div></div></div>'
           '<div style="margin-top:14px">'
           + opt4('从稍后再看移除', 'remove_circle_outline', focus=True, n=N(1), tag='chg', fam='mo')
           + opt4('UP 主主页', 'person_outline', n=N(2), tag='keep') + '</div>'
           f'<div class="btns">{nb("取消", n=N(3), tag="keep")}</div></div>')
    body = (rail4('video', 1) + '<div class="ncontent">' + ptabs4(1) + grid4(cards) + '</div>' + dlg)
    return page(body, CSS)


def v4_login(n=True):
    N = (lambda k: k) if n else (lambda k: None)
    st = state4('lock', '请先登录B站账号', '登录后即可使用音乐和视频模式：推荐、关注的 UP 主、收藏、历史都从你的账号读取',
                nb('扫码登录', 'qr_code_scanner', 'pri f', n=N(1), tag='keep'))
    return page(rail4('video', 2) + f'<div class="ncontent">{st}</div>', CSS)


def v4_error(n=True):
    N = (lambda k: k) if n else (lambda k: None)
    st = state4('cloud_off', '分区加载失败', '网络连接超时（15 秒）。检查网络后重试，或者换一个分区。',
                nb('重试', 'refresh', 'pri f', n=N(2), tag='add'), style='top:64px')
    body = rail4('video', 3) + '<div class="ncontent">' + tabs4(REGIONS, 3, n=N(1)) + st + '</div>'
    return page(body, CSS)


def v4_search(n=True):
    N = (lambda k: k) if n else (lambda k: None)
    words = ['城市夜景延时', '量子纠缠', '露营装备', '魂斗罗', '古筝弹唱', '八段锦', '橘猫', '手绘板', '英语口语', '夜跑', '编程入门', '读书会']
    chips = ''.join(
        f'<span class="nb{" f" if i == 0 else ""}"{at(N(3) if i == 0 else None, "keep")}><b style="color:{"#FF8A80" if i < 3 else "rgba(243,245,247,.6)"};font-weight:600">{i + 1}</b>{w}</span>'
        for i, w in enumerate(words))
    field = (f'<div style="position:absolute;left:0;top:28px;display:flex;gap:12px;align-items:center">'
             f'<div class="nrow" style="width:440px;min-height:44px;border-radius:22px;padding:0 16px"{at(N(1), "keep")}>{mr("search", 22, "rgba(243,245,247,.72)")}'
             '<span class="sub" style="font-size:15px">搜索全站视频</span></div>' + nb('搜索', 'search', 'pri', n=N(2), tag='chg') + '</div>')
    board = (f'<div style="position:absolute;left:0;right:0;top:96px"><div class="nsec">{mr("local_fire_department", 18, "#7DB6FF")} 热搜榜</div>'
             f'<div style="display:flex;flex-wrap:wrap;gap:10px">{chips}</div></div>')
    return page(rail4('video', 0) + f'<div class="ncontent">{field}{board}</div>', CSS)


OUT = {
    'v3-home': v3_home(), 'v4-home': v4_home(), 'v4-home-rail': v4_home_rail(),
    'v3-detail': v3_detail(), 'v4-detail': v4_detail(),
    'v3-season': v3_season(), 'v4-season': v4_season(),
    'v3-player': v3_player(), 'v4-player': v4_player(),
    'v3-player-quality': v3_player('quality'), 'v4-player-quality': v4_player('quality', n=False),
    'v3-player-comments': v3_player('comments'), 'v4-player-comments': v4_player('comments', n=False),
    'v3-space': v3_space(), 'v4-space': v4_space(),
    'v3-history': v3_history(), 'v4-history': v4_history(),
    'v3-card-menu': v3_card_menu(), 'v4-card-menu': v4_card_menu(),
    'v3-login': v3_login(), 'v4-login': v4_login(),
    'v3-error': v3_error(), 'v4-error': v4_error(),
    'v3-search': v3_search(), 'v4-search': v4_search(),
}
if __name__ == '__main__':
    write(HERE, OUT)
