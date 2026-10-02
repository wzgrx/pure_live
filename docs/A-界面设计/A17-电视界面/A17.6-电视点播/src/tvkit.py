"""Shared pieces for the TV mockups of U.15f (video), U.15g (music) and
U.15h (wallpaper). U.15g and U.15h import this file from ../../U.15f/src.

Canvas: 960x540 logical at 2x (a 1080p TV reports 960x540 at dpr 2).

* Restored pure_live_TV pages (``v3-*``) are written in pure_live_TV's own
  design pixels (a 1920x1080 draft, ``.sp`` = screen width / 1920) inside
  ``.d``, which is zoomed to one half; colours are its default ``dark``
  preset (core/theme/themes/dark_theme.dart: background #121212, card
  #1F1F1F, focus #00A1FF, text and secondary text white; the focused card
  is normalised to HSL(202, .42, .20) = #1E3948, tv_theme_data.dart:110).
* New-design pages (``v4-*``) are written in logical pixels: UI_PLAN 5.5
  (safe margins 48 / 28, collapsed rail that opens on focus, 4-column
  grids, focus = 1.05 scale + 3 px near-white ring, text one step above
  the phone, body >= 14, dark only) and the palette of v4's
  apps/pure_live/lib/tv/tv_theme.dart (TvPalette.of the dark scheme).
"""
import os

# ---------- icons ----------
def _ic(cls, n, s, c):
    return f'<span class="{cls}" style="font-size:{s}px{";color:" + c if c else ""}">{n}</span>'


mr = lambda n, s=24, c='': _ic('mr', n, s, c)   # Icons.*_rounded
mo = lambda n, s=24, c='': _ic('mo', n, s, c)   # Icons.*_outlined
mi = lambda n, s=24, c='': _ic('mi', n, s, c)   # Icons.* (filled)


def at(n=None, tag=None, pos=None):
    """data-n attributes for the numbered picture."""
    return ((f' data-n="{n}"' if n else '') + (f' data-tag="{tag}"' if tag and n else '')
            + (f' data-at="{pos}"' if pos and n else ''))


IMG = lambda i: f'.cache/img/{i}.jpg'
AV = IMG(65)

# ---------- sample data (fictional; pictures are picsum samples) ----------
# title, up, cover, plays, danmaku, duration, region, date
VIDEOS = [
    ('城市夜景延时摄影：一夜拍完十二个机位', '山野影像', 1, '12.3万', '2048', '12:34', '生活', '2026-09-28'),
    ('三分钟看懂量子纠缠，比你想的简单', '知识小站', 111, '86.1万', '1.2万', '03:21', '知识', '2026-09-30'),
    ('手绘板绘练习｜一只橘猫的十种画法', '清欢画画', 133, '4.6万', '873', '18:02', '生活', '2026-09-27'),
    ('周末露营：在山里看了一整夜星空', '山野', 169, '23.4万', '3511', '25:40', '生活', '2026-09-25'),
    ('英语口语：点餐时最常用的二十句', 'Aki老师', 183, '9.8万', '1022', '09:15', '知识', '2026-09-29'),
    ('复古游戏通关：魂斗罗一命通关', '像素老王', 206, '31.2万', '8840', '41:07', '游戏', '2026-09-26'),
    ('古筝弹唱《晚风》完整版', '弦月', 219, '15.5万', '2763', '04:48', '音乐', '2026-09-30'),
    ('城市夜跑 Vlog：十公里挑战', '风吹麦浪', 225, '2.1万', '305', '14:22', '生活', '2026-09-24'),
    ('读书会：《额尔古纳河右岸》第一章', '月亮邮差', 292, '6188', '96', '52:10', '知识', '2026-09-23'),
    ('编程实况：从零写一个小游戏', '小林同学', 338, '4.5万', '611', '1:12:45', '知识', '2026-09-22'),
    ('街头弹唱合集，听歌的进来', '阿远', 342, '18.9万', '4210', '33:18', '音乐', '2026-09-21'),
    ('晨练八段锦，跟着做二十分钟', '早起的鸟', 360, '7.7万', '512', '20:03', '生活', '2026-09-20'),
]

# ======================================================================
#  CSS
# ======================================================================
BASE_CSS = '''
html,body{background:#000}
.win{background:#000;color:#fff}
.syn{top:auto;bottom:6px;left:auto;right:8px;transform:none;z-index:90}
.tnum,.t{font-feature-settings:'tnum'}
'''

# --- restore: pure_live_TV design pixels (1920x1080), zoomed to one half ---
R_CSS = '''
.d{position:absolute;left:0;top:0;width:1920px;height:1080px;zoom:.5;background:#121212;color:#fff;overflow:hidden;font-family:'Noto Sans SC',sans-serif}
.d .rail{position:absolute;left:0;top:0;bottom:0;width:160px;background:rgba(18,18,18,.62);display:flex;flex-direction:column;align-items:center;padding:24px 0}
.d .clock{font:600 20px/1 'Geist','Noto Sans SC';letter-spacing:1.5px;margin:0 0 21px}
.d .rb{width:90px;height:90px;border-radius:20px;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:8px;background:rgba(31,31,31,.45);color:#fff;font-size:16px;font-weight:500;margin-bottom:20px;flex:none;line-height:1}
.d .rb .mr,.d .rb .mo{font-size:28px}
.d .rb.sel{background:#00A1FF}
.d .foc{box-shadow:0 0 0 2px #00A1FF,0 0 18px 2px rgba(0,161,255,.75)}
.d .rb.foc{background:rgba(0,161,255,.5);transform:scale(1.08)}
.d .pane{position:absolute;left:168px;top:8px;right:8px;bottom:8px}
.d .tabs3{height:90px;margin-top:24px;display:flex;align-items:flex-start;padding:12px 16px}
.d .tab3{height:36px;padding:0 28px;border-radius:18px;margin:0 6px;background:rgba(31,31,31,.75);display:flex;align-items:center;gap:10px;font-size:22px;font-weight:500;white-space:nowrap;flex:none}
.d .tab3.sel{background:#00A1FF}.d .tab3.foc{background:rgba(0,161,255,.5);transform:scale(1.08)}
.d .grid3{display:grid;gap:6px;padding:24px}
.d .vc{position:relative;border-radius:24px;background:#1F1F1F;display:flex;flex-direction:column;overflow:visible;border:2px solid transparent}
.d .vc.foc{background:#1E3948;border-color:#00A1FF;transform:scale(1.01)}
.d .vc .cv{position:relative;flex:1;border-radius:24px;background:#1F1F1F center/cover;overflow:hidden}
.d .vc .cv::after{content:'';position:absolute;left:0;right:0;bottom:0;height:64px;background:linear-gradient(transparent,rgba(0,0,0,.72))}
.d .chip3{display:inline-flex;align-items:center;gap:4px;padding:5px 14px;border-radius:20px;background:rgba(0,0,0,.98);color:#fff;font-size:14px;line-height:20px;white-space:nowrap}
.d .chip3 .mr,.d .chip3 .mo{font-size:13px}
.d .cvb{position:absolute;left:10px;right:10px;bottom:6px;display:flex;gap:6px;z-index:2}
.d .cvt{position:absolute;left:10px;top:10px;z-index:2}
.d .vi{display:flex;align-items:center;padding:16px 16px 8px 10px;gap:16px}
.d .av3{width:56px;height:56px;border-radius:28px;background:#333 center/cover;flex:none}
.d .vi .tt3{font-size:22px;font-weight:700;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;line-height:30px}
.d .vi .st3{font-size:18px;font-weight:500;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;line-height:25px;margin-top:4px}
.d .hdr3{height:66px;display:flex;align-items:center;padding:0 16px;gap:16px}
.d .hdr3 .t{font-size:24px;font-weight:700;flex:1;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.d .b3{display:inline-flex;align-items:center;gap:6px;padding:6px 14px;border-radius:999px;background:rgba(31,31,31,.75);color:#fff;font-size:14px;font-weight:500;line-height:20px;white-space:nowrap;flex:none}
.d .b3 .mr,.d .b3 .mo{font-size:20px}
.d .b3.sec{background:rgba(31,31,31,.45)}.d .b3.sel{background:#00A1FF}.d .b3.foc{background:rgba(0,161,255,.65);transform:scale(1.08)}
.d .acc{color:#00A1FF}
.d .card3{background:#1F1F1F;border-radius:16px}
.d .st-wrap{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center}
.d .st-ic{padding:22px;border-radius:50%;background:rgba(0,161,255,.10);border:1.5px solid rgba(0,161,255,.35);color:#00A1FF;display:grid;place-items:center}
.d .scrim3{position:absolute;inset:0;background:rgba(0,0,0,.54);z-index:40}
.d .dlg3{position:absolute;z-index:41;background:#1F1F1F;border-radius:24px;padding:32px;border:1px solid #00A1FF;box-shadow:0 0 12px 1px rgba(0,161,255,.75)}
.d .dlg3 .h{font-size:32px;font-weight:700;margin-bottom:24px}
.d .opt3{display:flex;align-items:center;gap:12px;padding:12px 16px;border-radius:12px;border:2px solid transparent;font-size:18px;font-weight:500;margin-bottom:10px}
.d .opt3.foc{background:#1F1F1F;border-color:#00A1FF;box-shadow:none}
'''

# --- new design: logical pixels on the 960x540 canvas ---
N_CSS = '''
.tv{position:absolute;inset:0;background:#080D14;color:#F3F5F7;overflow:hidden;font-family:'Noto Sans SC',sans-serif}
.sub{color:rgba(243,245,247,.72)}
.acc{color:#4D9BFF}
/* focus language: 1.05 scale + 3 px near-white ring (UI_PLAN 5.5) */
.f{transform:scale(1.05);box-shadow:0 0 0 3px #F2F5FA,0 6px 18px rgba(0,0,0,.5);position:relative;z-index:6}
.fr{transform:scale(1.02);box-shadow:0 0 0 3px #F2F5FA;position:relative;z-index:6}
/* rail (shell placeholder, U.15b) */
.nrail{position:absolute;left:0;top:0;bottom:0;width:112px;background:rgba(8,13,20,.86);border-right:1px solid rgba(255,255,255,.06);z-index:20}
.nrail .clk{position:absolute;left:48px;width:44px;top:28px;text-align:center;font:600 13px/16px 'Geist','Noto Sans SC';color:rgba(243,245,247,.72)}
.nrail .ri{position:absolute;left:48px;width:44px;height:44px;border-radius:14px;display:grid;place-items:center;color:rgba(243,245,247,.72)}
.nrail .ri .mr,.nrail .ri .mo{font-size:24px}
.nrail .ri.sel{background:#1079F9;color:#fff}
.nrail .ri.mode{background:#101A26;color:#F3F5F7}
.nrail .sep{position:absolute;left:52px;width:36px;height:1px;background:rgba(255,255,255,.12)}
.nrail.exp{width:232px;box-shadow:12px 0 32px rgba(0,0,0,.6);background:#0C1420}
.nrail.exp .ri{width:168px;display:flex;align-items:center;gap:12px;padding:0 12px;justify-content:flex-start;font-size:15px;font-weight:600}
.nrail.exp .clk{width:168px;text-align:left}
.ncontent{position:absolute;left:128px;right:48px;top:0;bottom:0}
.dim{position:absolute;inset:0;background:rgba(0,0,0,.45);z-index:15}
/* tabs */
.ntabs{position:absolute;left:0;right:0;top:28px;height:34px;display:flex;gap:10px;align-items:center;white-space:nowrap}
.ntab{height:32px;padding:0 16px;border-radius:16px;background:#101A26;color:rgba(243,245,247,.8);font-size:15px;font-weight:600;display:flex;align-items:center;gap:6px;flex:none}
.ntab.sel{background:#1079F9;color:#fff}
.ntab .mr,.ntab .mo{font-size:18px}
/* page header */
.nhdr{position:absolute;left:0;right:0;top:28px;height:36px;display:flex;align-items:center;gap:12px}
.nhdr .t{font-size:20px;font-weight:600;flex:1;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
/* buttons */
.nb{height:36px;padding:0 16px;border-radius:18px;background:#16243A;color:#F3F5F7;font-size:15px;font-weight:600;display:inline-flex;align-items:center;gap:6px;white-space:nowrap;flex:none}
.nb .mr,.nb .mo{font-size:20px}
.nb.pri{background:#1079F9;color:#fff}
.nb.on{background:rgba(16,121,249,.22);color:#7DB6FF}
.nb.sm{height:32px;padding:0 12px;font-size:14px}
.nb.ic{width:36px;padding:0;justify-content:center}
.nb.dis{opacity:.4}
/* cards */
.ngrid{position:absolute;left:0;right:0;display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:16px}
.nc{border-radius:16px;background:#101A26;overflow:visible;display:flex;flex-direction:column}
.nc .cv{position:relative;aspect-ratio:16/9;border-radius:16px 16px 0 0;background:#16243A center/cover;overflow:hidden}
.nc .cv.full{border-radius:16px}
.nc.f{background:#1E3148}
.nchip{position:absolute;display:inline-flex;align-items:center;gap:2px;height:20px;padding:0 5px;border-radius:6px;background:rgba(0,0,0,.6);color:#fff;font-size:12px;font-weight:600;white-space:nowrap;font-feature-settings:'tnum'}
.nchip .mr,.nchip .mo{font-size:14px}
.nprog{position:absolute;left:0;right:0;bottom:0;height:3px;background:rgba(255,255,255,.25)}.nprog i{position:absolute;left:0;top:0;bottom:0;background:#4D9BFF}
.ninfo{display:flex;gap:8px;padding:8px 10px 10px;align-items:flex-start}
.nav{width:24px;height:24px;border-radius:12px;background:#223 center/cover;flex:none;margin-top:1px}
.ninfo .x{flex:1;min-width:0}
.ninfo .ct{font-size:15px;font-weight:600;line-height:21px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.ninfo .st{font-size:13px;line-height:18px;color:rgba(243,245,247,.72);white-space:nowrap;overflow:hidden;text-overflow:ellipsis;margin-top:2px}
/* rows */
.nrow{display:flex;align-items:center;gap:14px;min-height:56px;padding:8px 16px;border-radius:12px;background:#101A26}
.nrow .x{flex:1;min-width:0}.nrow .a{font-size:15px;font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.nrow .b{font-size:13px;color:rgba(243,245,247,.72);margin-top:2px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.nrow .v{font-size:14px;color:rgba(243,245,247,.72);white-space:nowrap}
.nrow.fr{background:#1E3148}
.nsec{font-size:14px;font-weight:600;color:#7DB6FF;margin:0 0 8px 4px}
/* dialog, small menu, side panel (same components as the phone, TV sizes) */
.nscrim{position:absolute;inset:0;background:rgba(0,0,0,.6);z-index:40}
.ndlg{position:absolute;z-index:41;left:50%;top:50%;transform:translate(-50%,-50%);width:460px;background:#15202F;border-radius:24px;padding:24px;box-shadow:0 16px 48px rgba(0,0,0,.6)}
.ndlg .h{font-size:18px;font-weight:600;line-height:26px}
.ndlg .p{font-size:14px;line-height:22px;color:rgba(243,245,247,.72);margin-top:8px}
.ndlg .btns{display:flex;justify-content:flex-end;gap:12px;margin-top:20px}
.nopt{display:flex;align-items:center;gap:12px;height:48px;padding:0 14px;border-radius:12px;font-size:15px}
.nopt .x{flex:1;min-width:0;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.nopt.cur{color:#7DB6FF;font-weight:600}
.nopt.fr{background:#1E3148}
.nopt.red{color:#FF8A80}
.nmenu{position:absolute;z-index:41;background:#1B2738;border-radius:10px;padding:6px;box-shadow:0 8px 28px rgba(0,0,0,.55);min-width:150px}
.nmenu .nopt{height:42px}
.nmenu .mh{font-size:13px;color:rgba(243,245,247,.6);padding:6px 14px 4px}
.npanel{position:absolute;z-index:30;top:0;right:0;bottom:0;width:400px;background:#101A26;border-radius:16px 0 0 16px;box-shadow:-10px 0 30px rgba(0,0,0,.5);padding:28px 48px 28px 20px;display:flex;flex-direction:column}
.npanel .phd{display:flex;align-items:center;gap:8px;height:36px;margin-bottom:10px}
.npanel .phd .t{flex:1;font-size:18px;font-weight:600}
.nhint{font-size:13px;color:rgba(243,245,247,.6)}
/* status */
.nstate{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;text-align:center}
.nstate .ic{width:72px;height:72px;border-radius:36px;background:#101A26;display:grid;place-items:center;color:#7DB6FF}
.nstate .ic .mr,.nstate .ic .mo{font-size:36px}
.nstate .a{font-size:17px;font-weight:600;margin-top:16px}
.nstate .b{font-size:14px;color:rgba(243,245,247,.72);margin-top:6px;max-width:420px;line-height:22px}
.nstate .btns{display:flex;gap:12px;margin-top:18px}
.ntoast{position:absolute;left:50%;bottom:40px;transform:translateX(-50%);z-index:60;background:#2B3746;color:#F3F5F7;font-size:15px;padding:10px 18px;border-radius:8px;white-space:nowrap;box-shadow:0 6px 18px rgba(0,0,0,.4)}
/* video and its control layer (picture roles: white on a black gradient) */
.pic{position:absolute;inset:0;background:#000 center/cover}
.vtopg{position:absolute;left:0;right:0;top:0;height:110px;background:linear-gradient(rgba(0,0,0,.6),transparent);z-index:5}
.vbotg{position:absolute;left:0;right:0;bottom:0;height:190px;background:linear-gradient(transparent,rgba(0,0,0,.6) 45%,rgba(0,0,0,.72));z-index:5}
.vtitle{position:absolute;left:48px;right:48px;top:28px;display:flex;align-items:center;gap:12px;z-index:6;color:#fff}
.vtitle .t{flex:1;font-size:18px;font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;text-shadow:0 1px 3px rgba(0,0,0,.6)}
.vtitle .m{font-size:14px;color:rgba(255,255,255,.8);white-space:nowrap;font-feature-settings:'tnum'}
.vseek{position:absolute;left:48px;right:48px;bottom:84px;display:flex;align-items:center;gap:12px;z-index:6;color:#fff;font-size:14px;font-feature-settings:'tnum'}
.vseek .bar{flex:1;height:4px;border-radius:2px;background:rgba(255,255,255,.3);position:relative}
.vseek .bar i{position:absolute;left:0;top:0;bottom:0;border-radius:2px;background:#4D9BFF}
.vseek .bar b{position:absolute;top:-2px;bottom:-2px;width:0}
.vseek.f2 .bar{height:8px;border-radius:4px;box-shadow:0 0 0 3px #F2F5FA}
.vseek .bar u{position:absolute;top:50%;width:14px;height:14px;border-radius:7px;background:#fff;transform:translate(-50%,-50%)}
.vpills{position:absolute;left:48px;right:48px;bottom:32px;display:flex;gap:8px;z-index:6;align-items:center}
.vp{height:36px;padding:0 12px;border-radius:18px;background:rgba(255,255,255,.14);color:#fff;font-size:14px;font-weight:600;display:inline-flex;align-items:center;gap:5px;white-space:nowrap;flex:none}
.vp .mr,.vp .mo{font-size:20px}
.vp.ic{width:36px;padding:0;justify-content:center}
.vp.big{width:44px;height:44px;border-radius:22px;padding:0;justify-content:center;background:rgba(255,255,255,.22)}
.vp.big .mr{font-size:28px}
.vp.on .mr,.vp.on .mo{color:#7DB6FF}
.vp.dis{opacity:.4}
'''


def page(body, css='', restore=False, syn=True):
    """One 960x540 TV page; ``restore`` wraps the body in the zoomed .d."""
    inner = f'<div class="d">{body}</div>' if restore else f'<div class="tv">{body}</div>'
    tag = '<div class="syn">示意图片</div>' if syn else ''
    return ('<!doctype html><html><head><meta charset="utf-8"><meta name="mock-size" content="960x540@2">'
            f'<link rel="stylesheet" href="kit/kit.css"><style>{BASE_CSS}{R_CSS}{N_CSS}{css}</style></head>'
            f'<body><div class="win" style="--w:960px;--h:540px">{inner}{tag}</div></body></html>')


def write(here, pages):
    for name, html in pages.items():
        open(os.path.join(here, name + '.html'), 'w', encoding='utf-8').write(html)
    print(len(pages), 'pages')


# ======================================================================
#  Restore pieces (pure_live_TV, design px)
# ======================================================================
MODE = {'video': ('movie', '视频', 'mo'), 'music': ('library_music', '音乐', 'mo'), 'live': ('live_tv', '直播', 'mr')}
# features/home/home_page.dart _buildModeRailItems
RAIL3 = {
    'video': [('search', '搜索', 'mr'), ('person_outline', '我的', 'mr'), ('home', '首页', 'mo'),
              ('category', '分区', 'mo'), ('movie', '影视', 'mo')],
    'music': [('queue_music', '正在播放', 'mr'), ('search', '搜索', 'mr'), ('playlist_add_check', '歌单', 'mr'),
              ('explore', '推荐', 'mo'), ('person_outline', '我的', 'mr')],
}


def rail3(mode, sel, focus=None):
    """Collapsed sidebar (sidebarExpanded defaults to false): clock, the mode
    button, the mode's sections, settings at the bottom."""
    icon, label, fam = MODE[mode]
    ic = mr if fam == 'mr' else mo
    out = ['<div class="rail"><div class="clock t">21:36</div>',
           f'<div class="rb{" foc" if focus == "mode" else ""}">{ic(icon)}<span>{label}</span></div>']
    for i, (n, l, f) in enumerate(RAIL3[mode]):
        cls = 'rb' + (' sel' if i == sel else '') + (' foc' if focus == i else '')
        out.append(f'<div class="{cls}">{(mr if f == "mr" else mo)(n)}<span style="white-space:nowrap">{l}</span></div>')
    out.append('<div style="flex:1"></div><div class="rb' + (' foc' if focus == 'set' else '') + '">' + mo('settings') + '<span>设置</span></div></div>')
    return ''.join(out)


def tabs3(labels, sel=0, focus=None, icons=None):
    out = ['<div class="tabs3">']
    for i, l in enumerate(labels):
        cls = 'tab3' + (' sel' if i == sel else '') + (' foc' if i == focus else '')
        ic = icons[i] if icons else ''
        out.append(f'<div class="{cls}">{ic}{l}</div>')
    return ''.join(out) + '</div>'


def chip3(label, icon=None, fam='mr', color=''):
    ic = (mr if fam == 'mr' else mo)(icon, 13) if icon else ''
    st = f' style="color:{color}"' if color else ''
    return f'<span class="chip3"{st}>{ic}{label}</span>'


def vcard3(v, focus=False, badge=None, progress=None, style=''):
    """modules/video/widgets/video_card.dart (VideoCard)."""
    title, up, cover, plays, dms, dur, region, date = v
    b = badge if badge is not None else region
    prog = (f'<div style="position:absolute;left:0;right:0;bottom:0;height:4px;background:rgba(255,255,255,.25);z-index:3">'
            f'<i style="position:absolute;left:0;top:0;bottom:0;width:{progress}%;background:#00A1FF"></i></div>') if progress else ''
    return (f'<div class="vc{" foc" if focus else ""}" style="{style}"><div class="cv" style="background-image:url({IMG(cover)})">'
            + (f'<div class="cvt">{chip3(b)}</div>' if b else '')
            + f'<div class="cvb">{chip3(plays, "play_arrow")}{chip3(dms, "comment", "mo")}<span style="flex:1"></span>{chip3(dur)}</div>{prog}</div>'
            f'<div class="vi"><span class="av3" style="background-image:url({AV})"></span><div style="flex:1;min-width:0">'
            f'<div class="tt3">{title}</div><div class="st3">{up} · {date}</div></div></div></div>')


def hdr3(title, focus_back=False, actions=''):
    """core/widgets/tv_app_bar.dart: “返回” mini button + t24 title."""
    return (f'<div class="hdr3"><span class="b3{" foc" if focus_back else ""}">{mr("arrow_back_ios_new", 24)}返回</span>'
            f'<span class="t">{title}</span>{actions}</div>')


def b3(label, icon=None, fam='mr', cls='', size=20, style=''):
    ic = (mr if fam == 'mr' else mo)(icon, size) if icon else ''
    return f'<span class="b3 {cls}" style="{style}">{ic}{label}</span>'


def state3(icon, title, sub='', fam='mr', top=0):
    """core/widgets/app_status_view.dart (no button unless onTap is passed)."""
    return (f'<div class="st-wrap" style="top:{top}px"><div class="st-ic">{(mr if fam == "mr" else mo)(icon, 64, "#00A1FF")}</div>'
            f'<div style="height:40px"></div><div style="font-size:24px;font-weight:600">{title}</div>'
            + (f'<div style="font-size:24px;margin-top:6px">{sub}</div>' if sub else '') + '</div>')


def ring3(size=64, stroke=5):
    return (f'<div style="width:{size}px;height:{size}px;border-radius:50%;border:{stroke}px solid rgba(0,161,255,.25);'
            f'border-top-color:#00A1FF"></div>')


# ======================================================================
#  New-design pieces (logical px)
# ======================================================================
# Rail entries per mode, in pure_live_TV's order (kept: choice X1 in U.15f).
RAIL4 = {
    'video': [('search', '搜索', 'mr'), ('person_outline', '我的', 'mr'), ('home', '首页', 'mo'),
              ('category', '分区', 'mo'), ('theaters', '影视', 'mo')],
    'music': [('queue_music', '正在播放', 'mr'), ('search', '搜索', 'mr'), ('playlist_add_check', '歌单', 'mr'),
              ('explore', '推荐', 'mo'), ('person_outline', '我的', 'mr')],
}


def rail4(mode, sel, focus=None, expanded=False, n=None):
    """The shell's collapsed rail (U.15b); opens with labels when it holds
    the focus. Only the placement matters here."""
    icon, label, fam = MODE[mode]
    ic = mr if fam == 'mr' else mo
    lab = (lambda t: f'<span>{t}</span>') if expanded else (lambda t: '')
    y = 60
    out = [f'<div class="nrail{" exp" if expanded else ""}"><div class="clk t">21:36</div>',
           f'<div class="ri mode{" f" if focus == "mode" else ""}" style="top:{y}px"{at(n and n[0], "keep")}>{ic(icon)}{lab(label + " ▾" if expanded else "")}</div>',
           f'<div class="sep" style="top:{y + 54}px"></div>']
    y += 64
    for i, (nm, l, f) in enumerate(RAIL4[mode]):
        cls = 'ri' + (' sel' if i == sel else '') + (' f' if focus == i else '')
        out.append(f'<div class="{cls}" style="top:{y}px"{at(n and n[1] + i, "chg" if nm == "theaters" else "keep")}>{(mr if f == "mr" else mo)(nm)}{lab(l)}</div>')
        y += 52
    out.append(f'<div class="ri{" f" if focus == "set" else ""}" style="top:{540 - 28 - 44}px"{at(n and n[1] + len(RAIL4[mode]), "keep")}>{mo("settings")}{lab("设置")}</div></div>')
    return ''.join(out)


def tabs4(labels, sel=0, focus=None, n=None, top=28, icons=None, extra=''):
    out = [f'<div class="ntabs" style="top:{top}px">']
    for i, l in enumerate(labels):
        cls = 'ntab' + (' sel' if i == sel else '') + (' f' if i == focus else '')
        ic = icons[i] if icons else ''
        out.append(f'<div class="{cls}"{at(n if (n and i == 0) else None)}>{ic}{l}</div>')
    return ''.join(out) + extra + '</div>'


def vcard4(v, focus=False, badge=None, progress=None, n=None, tag=None, menu_hint=False):
    title, up, cover, plays, dms, dur, region, date = v
    b = badge if badge is not None else region
    prog = f'<div class="nprog"><i style="width:{progress}%"></i></div>' if progress else ''
    return (f'<div class="nc{" f" if focus else ""}"{at(n, tag)}><div class="cv" style="background-image:url({IMG(cover)})">'
            + (f'<span class="nchip" style="left:6px;top:6px">{b}</span>' if b else '')
            + f'<span class="nchip" style="left:6px;bottom:6px">{mr("play_arrow", 14)}{plays}<span style="width:6px"></span>{mo("subtitles", 13)}{dms}</span>'
            f'<span class="nchip" style="right:6px;bottom:6px">{dur}</span>{prog}</div>'
            f'<div class="ninfo"><span class="nav" style="background-image:url({AV})"></span><div class="x">'
            f'<div class="ct">{title}</div><div class="st">{up} · {date[5:]}</div></div></div></div>')


def hdr4(title, focus_back=False, n=None, actions=''):
    return (f'<div class="nhdr"><span class="nb sm{" f" if focus_back else ""}"{at(n, "keep")}>{mr("arrow_back", 20)}返回</span>'
            f'<span class="t">{title}</span>{actions}</div>')


def nb(label, icon=None, cls='', fam='mr', n=None, tag=None, size=20, style=''):
    ic = (mr if fam == 'mr' else mo)(icon, size) if icon else ''
    return f'<span class="nb {cls}"{at(n, tag)} style="{style}">{ic}{label}</span>'


def state4(icon, title, sub='', btns='', fam='mo', style=''):
    """The phone's status component (U.2g / U.4) in TV sizes: icon, one line,
    one reason, at most two buttons."""
    return (f'<div class="nstate" style="{style}"><div class="ic">{(mr if fam == "mr" else mo)(icon, 36)}</div><div class="a">{title}</div>'
            + (f'<div class="b">{sub}</div>' if sub else '') + (f'<div class="btns">{btns}</div>' if btns else '') + '</div>')


def spinner4(size=36):
    return (f'<div style="width:{size}px;height:{size}px;border-radius:50%;border:3px solid rgba(77,155,255,.25);'
            f'border-top-color:#4D9BFF"></div>')


def opt4(label, icon=None, cur=False, focus=False, red=False, right='', n=None, tag=None, fam='mr', icolor=''):
    cls = 'nopt' + (' cur' if cur else '') + (' fr' if focus else '') + (' red' if red else '')
    ic = (mr if fam == 'mr' else mo)(icon, 22, icolor) if icon else ''
    chk = mr('check', 20, '#7DB6FF') if cur else ''
    return f'<div class="{cls}"{at(n, tag)}>{ic}<span class="x">{label}</span>{right}{chk}</div>'
