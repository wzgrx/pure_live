"""Shared pieces for the TV mockups (U.15a, U.15b, U.15c import this file).

Canvas: 960x540 logical (an Android TV at 1080p reports 960x540 at 2x).
pure_live_TV (~/ref/pure_live_TV/lib, the TV baseline) drafts every size
against a 1920x1080 panel and scales it with flutter_screenutil
(`.sp`, `.w`, `.h`, `.ts` = x 0.5 on such a TV, core/theme/tv_text_scale.dart:23,
app/app.dart:45), so a drafted 18 becomes 9 logical px here. The *3 helpers
draw that baseline at those halved sizes; the *4 helpers draw the new design.

pure_live_TV sources:
  core/theme/themes/dark_theme.dart        default palette #121212 / #1F1F1F / #00A1FF / white
  core/theme/tv_theme_data.dart:120-125    focused card colour (normalized) -> #1E3948
  core/widgets/tv_focus_style.dart         ring 2.sp accent, glow 18 blur, scale 1.05
  core/widgets/tv_focusable.dart:77-89     scale Offset(1, 1.05) (height only), glow 24
  core/widgets/tv_button.dart              pill, sizes large/medium/small/mini, scale 1.08
  core/widgets/tv_icon_button.dart         collapsed rail tile (icon + short label)
  core/widgets/tv_tab_bar.dart             pills 36.h tall, t22 label, selected solid accent
  core/widgets/tv_room_card.dart           radius 24.sp, chips, info row avatar 56, t18 / t16
  core/widgets/tv_cover_chip.dart          black .98, t14
  core/widgets/tv_area_card.dart           6 columns, square art, t18 name
  core/widgets/tv_settings_row.dart        rows, switch, value label
  core/dialog/*.dart                       TvDialog 800.ts wide, title 32, buttons mini
  core/widgets/app_status_view.dart        status: circle icon 64, title/subtitle t24
New design colours are the phone's dark roles (tools/ui/mock/kit/kit.css
[data-theme=dark]); the page sets <html data-theme="dark">.
"""
import os
import sys

_KIT = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(_KIT, '..', '..', 'U.4a', 'src'))
from cards import R, SITE, LOGO, cover, avatar  # noqa: E402  (same sample rooms as the phone pages)

SITE = dict(SITE, all='全部', iptv='网络', twitch='Twitch', soop='Soop', yy='YY', acfun='AcFun 直播')

# ---------- icons ----------
mr = lambda n, s=24: f'<span class="mr" style="font-size:{s}px">{n}</span>'
mo = lambda n, s=24: f'<span class="mo" style="font-size:{s}px">{n}</span>'
rx = lambda c, s=24: f'<span class="rx" style="font-size:{s}px">&#x{c};</span>'
ci = lambda c, s=24: f'<span class="ci" style="font-size:{s}px">&#x{c};</span>'
RX = {'heart_3_line': 'ee0b', 'heart_3_fill': 'ee0a', 'fire_line': 'ed33', 'fire_fill': 'ed32', 'function_line': 'ed9e',
      'shapes_line': 'f3da', 'shapes_fill': 'f3d9', 'apps_2_line': 'ea42', 'heart_add_2_line': 'f4e6', 'history_line': 'ee17',
      'settings_5_line': 'f0ea', 'price_tag_3_line': 'f023', 'delete_bin_line': 'ec2a', 'login_box_fill': 'eed3',
      'error_warning_line': 'eca1', 'qr_code_line': 'f03d', 'arrow_down_s_line': 'ea4e', 'arrow_right_s_line': 'ea6e',
      'check_line': 'eb7b', 'add_line': 'ea13', 'search_line': 'f0d1', 'link': 'eeb2', 'movie_line': 'ef81',
      'refresh_line': 'f064', 'menu_2_fill': 'ef31', 'lock_line': 'eece', 'tv_2_line': 'f235'}
r = lambda name, s=24: rx(RX[name], s)
SEARCH_CI = lambda s=24: ci('e804', s)   # CustomIcons.search (phone U.3a c4)


def at(n=None, tag=None, pos=None):
    """data-n attributes for the numbered picture."""
    return ((f' data-n="{n}"' if n else '') + (f' data-tag="{tag}"' if tag and n else '')
            + (f' data-at="{pos}"' if pos and n else ''))


def page(body, css='', dark=True, bg=None, syn=True):
    """One 960x540 TV screen. dark=True gives the phone's dark roles to the kit variables."""
    theme = ' data-theme="dark"' if dark else ''
    style = f'--w:960px;--h:540px' + (f';background:{bg}' if bg else '')
    tag = '<div class="syn" style="top:4px">示意图片</div>' if syn else ''
    return (f'<!doctype html><html{theme}><head><meta charset="utf-8"><meta name="mock-size" content="960x540@2">'
            f'<link rel="stylesheet" href="kit/kit.css"><style>{CSS}{css}</style></head>'
            f'<body><div class="win tvw" style="{style}">{body}{tag}</div></body></html>')


def write(out, here):
    for name, html in out.items():
        open(os.path.join(here, name + '.html'), 'w', encoding='utf-8').write(html)
    print(len(out), 'pages')


CSS = '''
.tvw{font-family:'Noto Sans SC',sans-serif;color:#fff}
.tnum{font-family:'Geist','Noto Sans SC';font-feature-settings:'tnum'}
.ab{position:absolute}
.flexc{display:flex;align-items:center}
.fmk{position:relative}
.fmk::after{content:'焦点';position:absolute;left:50%;top:-17px;transform:translateX(-50%);z-index:30;font:600 9px/14px 'Noto Sans SC';
  color:#3A2600;background:#FFC53D;padding:0 5px;border-radius:7px;white-space:nowrap;letter-spacing:.5px}
.fmk.fb::after{top:auto;bottom:-17px}
.fmk.fl::after{left:-4px;transform:translateX(-100%);top:50%;margin-top:-7px}
.fmk.fr::after{left:auto;right:-4px;transform:translateX(100%);top:50%;margin-top:-7px}
/* ================= pure_live_TV (drafted size / 2) ================= */
.t3{background:#121212;color:#fff;position:absolute;inset:0;overflow:hidden}
.t3 .rail{position:absolute;left:0;top:0;bottom:0;width:80px;background:rgba(18,18,18,.62);display:flex;flex-direction:column;align-items:center;padding:12px 0}
.t3 .rail.x{width:114px;align-items:stretch}
.t3 .clk{font:600 10px/1 'Noto Sans SC';letter-spacing:1.5px;text-align:center;margin-bottom:3px}
.t3 .clkd{font:500 7px/1 'Noto Sans SC';text-align:center;color:#fff}
.t3 .rt{width:45px;height:45px;border-radius:10px;background:rgba(31,31,31,.45);display:flex;flex-direction:column;align-items:center;justify-content:center;gap:5px;flex:none;color:#fff}
.t3 .rt .mr,.t3 .rt .mo,.t3 .rt .rx{font-size:14px}
.t3 .rt b{font:500 8px/1 'Noto Sans SC';opacity:.78}
.t3 .rt.on{background:#00A1FF}.t3 .rt.on b{opacity:1}
.t3 .rt.f{background:rgba(0,161,255,.5);transform:scale(1.08);box-shadow:0 0 0 1px #00A1FF,0 0 9px 1px rgba(0,161,255,.75)}
.t3 .rt.on.f{background:#00A1FF}
.t3 .rb{height:27px;border-radius:14px;margin:0 8px;background:rgba(31,31,31,.45);display:flex;align-items:center;gap:5px;padding:0 12px;font:500 9px 'Noto Sans SC';flex:none}
.t3 .rb .mr,.t3 .rb .mo,.t3 .rb .rx{font-size:12px}
.t3 .rb.on{background:#00A1FF}
.t3 .rb.f{background:rgba(0,161,255,.5);box-shadow:0 0 0 1px #00A1FF,0 0 9px 1px rgba(0,161,255,.75)}
.t3 .pane{position:absolute;left:84px;top:4px;right:4px;bottom:4px}
.t3 .tb3{display:flex;align-items:center;gap:6px;height:45px;margin:12px 0 0;padding:6px 8px;white-space:nowrap;overflow:hidden}
.t3 .pl{height:33px;border-radius:17px;padding:0 14px;display:flex;align-items:center;gap:5px;font:500 11px 'Noto Sans SC';background:rgba(31,31,31,.75);flex:none;color:#fff}
.t3 .pl img{width:12px;height:12px;object-fit:contain}.t3 .pl .mr{font-size:12px}
.t3 .pl.on{background:#00A1FF}
.t3 .pl.f{background:rgba(0,161,255,.5);transform:scale(1.08);box-shadow:0 0 0 1px #00A1FF,0 0 9px 1px rgba(0,161,255,.75)}
.t3 .pl.on.f{background:#00A1FF}
.t3 .grid3{display:grid;grid-template-columns:repeat(4,1fr);gap:3px;padding:8px}
.t3 .c3{height:163px;border-radius:12px;background:#1F1F1F;display:flex;flex-direction:column;overflow:hidden;position:relative;border:1px solid transparent}
.t3 .c3.f{background:#1E3948;border-color:#00A1FF;box-shadow:0 0 9px .75px rgba(0,161,255,.75);transform:scale(1.01);overflow:visible;z-index:2}
.t3 .c3 .cv{flex:1;border-radius:12px;background:#1F1F1F center/cover;position:relative}
.t3 .ch3{position:absolute;height:13px;padding:0 7px;border-radius:10px;background:rgba(0,0,0,.98);color:#fff;font:400 7px/13px 'Noto Sans SC';display:flex;align-items:center;gap:2px;white-space:nowrap}
.t3 .ch3 .mr{font-size:6.5px}
.t3 .inf{height:34px;display:flex;align-items:center;padding:3px 0 3px 3px;flex:none}
.t3 .inf .a{width:28px;height:28px;border-radius:14px;background:center/cover;flex:none;margin:0}
.t3 .inf .t{flex:1;min-width:0;margin-left:4px}
.t3 .inf .t div{white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.t3 .inf .t .x{font:700 9px/1.2 'Noto Sans SC'}.t3 .inf .t .y{font:700 8px/1.2 'Noto Sans SC';margin-top:2px}
.t3 .a3{border-radius:9px;background:#121212;display:flex;flex-direction:column;align-items:center;padding:4.5px;border:1px solid transparent}
.t3 .a3 .im{flex:1;aspect-ratio:1;border-radius:6px;background:#fff center/contain no-repeat;min-height:0}
.t3 .a3 .n{font:600 9px/1.15 'Noto Sans SC';margin-top:4px;text-align:center;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:100%}
.t3 .a3.f{border-color:#00A1FF;box-shadow:0 0 6px .5px #00A1FF;transform:scale(1.04);z-index:2}
.t3 .a3.f .n{font-weight:700}
.b3{display:inline-flex;align-items:center;gap:3px;border-radius:999px;background:rgba(31,31,31,.75);color:#fff;font:500 7px 'Noto Sans SC';padding:3px 7px;white-space:nowrap}
.b3 .mr,.b3 .mo,.b3 .rx{font-size:10px}
.b3.s{font-size:8px;padding:4px 9px;gap:4px}.b3.s .mr,.b3.s .mo,.b3.s .rx{font-size:11px}
.b3.m{font-size:9px;padding:5px 12px;gap:5px}.b3.m .mr{font-size:12px}
.b3.l{font-size:10px;padding:7px 16px;gap:7px}
.b3.sec{background:rgba(31,31,31,.45)}
.b3.on{background:#00A1FF}
.b3.f{background:rgba(0,161,255,.65);transform:scale(1.08);box-shadow:0 0 0 1px #00A1FF,0 0 9px 1px rgba(0,161,255,.75)}
.scr3{position:absolute;inset:0;background:rgba(0,0,0,.59);z-index:20}
.d3{position:absolute;z-index:21;left:50%;top:50%;transform:translate(-50%,-50%);width:400px;padding:16px;border-radius:12px;background:#1F1F1F;
  border:.5px solid #00A1FF;box-shadow:0 0 6px .5px rgba(0,161,255,.75);color:#fff}
.d3 .h{font:700 16px/1.25 'Noto Sans SC';margin-bottom:12px}
.d3 .m{font:400 12px/1.4 'Noto Sans SC';color:#fff}
.d3 .ac{display:flex;justify-content:flex-end;gap:8px;margin-top:16px}
.o3{min-height:30px;border-radius:8px;padding:5px 10px;display:flex;align-items:center;gap:7px;background:rgba(255,255,255,.06);border:.5px solid rgba(255,255,255,.25);font:500 10px 'Noto Sans SC';color:#fff;margin-bottom:6px}
.o3 .mr,.o3 .mo{font-size:12px}
.o3 .x{flex:1;min-width:0}.o3 .x small{display:block;font-size:8px;color:rgba(255,255,255,.7)}
.o3.on,.o3.f{background:#00A1FF;border-color:#00A1FF}
/* ================= new design (phone dark roles, TV sizes) ================= */
.t4{background:var(--surface);color:var(--on);position:absolute;inset:0;overflow:hidden}
:root{--fc:#F1F3F9;--onfc:#111418}
.f4{box-shadow:0 0 0 3px var(--fc)!important;transform:scale(1.05);z-index:3;position:relative}
.f4.ns{transform:none}
/* rail */
.t4 .rail4{position:absolute;left:0;top:0;bottom:0;width:112px;background:var(--scl);border-right:1px solid var(--ov);padding:28px 0 28px 48px;display:flex;flex-direction:column;z-index:8}
.t4 .rail4.x{width:248px;box-shadow:8px 0 24px rgba(0,0,0,.45);padding-right:16px}
.t4 .clk4{width:48px;text-align:center;font:600 16px/1 'Geist','Noto Sans SC';font-feature-settings:'tnum';color:var(--on);height:20px}
.t4 .rail4.x .clk4{width:auto;text-align:left;font-size:22px;height:24px;padding-left:12px}
.t4 .clkd4{font:400 14px/1 'Geist';color:var(--onv);padding-left:12px;margin-top:4px}
.t4 .ri{height:44px;width:48px;border-radius:12px;display:flex;align-items:center;gap:14px;color:var(--onv);flex:none;margin-bottom:4px;position:relative}
.t4 .ri>span:first-child{width:48px;display:grid;place-items:center;flex:none}
.t4 .ri b{font:400 16px 'Noto Sans SC';white-space:nowrap;display:none}
.t4 .rail4.x .ri{width:auto}.t4 .rail4.x .ri b{display:block}
.t4 .ri.on{background:var(--pc);color:var(--opc)}.t4 .ri.on b{font-weight:600}
.t4 .ri .dd{margin-left:auto;margin-right:8px;color:var(--onv);display:none}.t4 .rail4.x .ri .dd{display:block}
.t4 .rsep{height:1px;background:var(--ov);margin:8px 6px 12px 0;flex:none}
.t4 .rail4.x .rsep{margin-right:0}
.t4 .content{position:absolute;left:128px;right:48px;top:28px;bottom:0}
.t4 .dim{position:absolute;inset:0;background:rgba(0,0,0,.45);z-index:7}
/* tab pills */
.tb4{display:flex;align-items:center;gap:8px;height:40px;white-space:nowrap;overflow:hidden;flex:none}
.pl4{height:36px;border-radius:18px;padding:0 16px;display:flex;align-items:center;gap:6px;font:400 16px 'Noto Sans SC';color:var(--onv);flex:none;background:var(--scc)}
.pl4 img{width:20px;height:20px;object-fit:contain;border-radius:4px}
.pl4 .mr,.pl4 .mo,.pl4 .rx{font-size:20px}
.pl4 .n{font:500 14px 'Geist';color:var(--onv);margin-left:2px}
.pl4.on{background:var(--pc);color:var(--opc);font-weight:600}.pl4.on .n{color:var(--opc)}
.pl4.fx{margin-left:auto}
.pl4.sm{height:32px;border-radius:16px;padding:0 14px;font-size:14px}
.vsep{width:1px;height:24px;background:var(--ov);flex:none;margin:0 4px}
.rline{height:3px;border-radius:2px;background:rgba(160,202,253,.22);position:relative;overflow:hidden}.rline i{position:absolute;left:12%;width:30%;top:0;bottom:0;background:var(--primary);border-radius:2px}
/* grid + room card */
.g4{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:16px;align-content:start}
.c4{border-radius:12px;background:var(--scc);display:flex;flex-direction:column;position:relative}
.c4 .cv{aspect-ratio:16/9;border-radius:12px 12px 0 0;background:var(--sch) center/cover;position:relative;overflow:hidden}
.c4 .dk{position:absolute;inset:0;background:rgba(0,0,0,.6)}
.ch4{position:absolute;height:22px;padding:0 8px;border-radius:11px;background:rgba(0,0,0,.6);color:#fff;font:600 14px/22px 'Noto Sans SC';display:flex;align-items:center;gap:4px;white-space:nowrap;z-index:2}
.ch4 img{width:14px;height:14px;object-fit:contain;border-radius:3px}.ch4 .mr{font-size:15px}
.ch4.tn{font-family:'Geist','Noto Sans SC';font-feature-settings:'tnum'}
.ch4.live{background:var(--live)}
.c4 .inf{display:flex;align-items:center;gap:8px;padding:10px 12px}
.c4 .inf .a{width:28px;height:28px;border-radius:14px;background:center/cover;flex:none}
.c4 .inf .nb{width:28px;text-align:center;font:700 18px 'Geist';flex:none}
.c4 .inf .t{flex:1;min-width:0}
.c4 .inf .t div{white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.c4 .inf .t .x{font:600 16px/22px 'Noto Sans SC';color:var(--on)}.c4 .inf .t .y{font:400 14px/20px 'Noto Sans SC';color:var(--onv)}
.c4.f4{background:var(--sch)}
.c4 .mq{display:flex;overflow:hidden;white-space:nowrap;-webkit-mask-image:linear-gradient(90deg,transparent,#000 14px,#000 calc(100% - 14px),transparent)}.c4 .mq span{flex:none;transform:translateX(-64px)}
.c4 .offlbl{position:absolute;inset:0;display:grid;place-items:center;font:600 16px 'Noto Sans SC';color:#fff;z-index:2}
/* compact row (offline follows, U.4c c5) */
.cr4{height:56px;border-radius:12px;background:var(--scc);display:flex;align-items:center;gap:12px;padding:0 14px}
.cr4 .a{width:32px;height:32px;border-radius:16px;background:center/cover;flex:none;filter:grayscale(.5)}
.cr4 .t{flex:1;min-width:0}.cr4 .t div{white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.cr4 .t .x{font:600 16px/22px 'Noto Sans SC'}.cr4 .t .y{font:400 14px/20px 'Noto Sans SC';color:var(--onv)}
.cr4 .st{font:400 14px 'Noto Sans SC';color:var(--onv);flex:none}
.cr4.f4{background:var(--sch)}
/* skeleton */
.sk4{border-radius:12px;background:var(--scc)}
.sk4 .cv{aspect-ratio:16/9;border-radius:12px 12px 0 0;background:var(--sch)}
.sk4 .ln{height:12px;border-radius:6px;background:var(--sch);margin:12px 12px 0 48px}.sk4 .ln.b{width:50%;margin:8px 0 14px 48px}
/* area card */
.ga4{display:grid;grid-template-columns:repeat(6,minmax(0,1fr));gap:16px;align-content:start}
.a4{border-radius:12px;background:var(--scc);display:flex;flex-direction:column;position:relative}
.a4 .im{aspect-ratio:1;border-radius:12px 12px 0 0;background:var(--sch) center/cover;position:relative}
.a4 .n{font:600 16px/22px 'Noto Sans SC';padding:8px 10px 2px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.a4 .s{font:400 14px/20px 'Noto Sans SC';color:var(--onv);padding:0 10px 8px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.a4.f4{background:var(--sch)}
.a4 .hrt{position:absolute;right:6px;top:6px;width:24px;height:24px;border-radius:12px;background:rgba(0,0,0,.6);display:grid;place-items:center;color:#FF5C7A}
/* buttons */
.b4{height:40px;border-radius:20px;padding:0 20px;display:inline-flex;align-items:center;justify-content:center;gap:8px;font:600 16px 'Noto Sans SC';
  background:var(--schh);color:var(--on);white-space:nowrap;flex:none}
.b4 .mr,.b4 .mo,.b4 .rx,.b4 .ci{font-size:20px}
.b4.pri{color:var(--primary)}.b4.err{color:var(--error)}
.b4.sm{height:36px;padding:0 16px;font-size:16px;font-weight:400}
/* dialogs */
.scr4{position:absolute;inset:0;background:rgba(0,0,0,.6);z-index:20}
.d4{position:absolute;z-index:21;left:50%;top:50%;transform:translate(-50%,-50%);width:520px;padding:28px 28px 24px;border-radius:24px;background:var(--sch);color:var(--on);box-shadow:0 12px 40px rgba(0,0,0,.5)}
.d4 .h{font:600 22px/1.3 'Noto Sans SC'}
.d4 .hs{font:400 14px/1.4 'Noto Sans SC';color:var(--onv);margin-top:4px}
.d4 .m{font:400 16px/1.6 'Noto Sans SC';color:var(--onv);margin-top:14px}
.d4 .ac{display:flex;justify-content:flex-end;gap:12px;margin-top:24px}
.d4 .ac .l{margin-right:auto}
.o4{height:48px;border-radius:12px;padding:0 16px;display:flex;align-items:center;gap:14px;font:400 16px 'Noto Sans SC';color:var(--on);margin-top:2px}
.o4 .mr,.o4 .mo,.o4 .rx{font-size:22px;color:var(--onv)}
.o4 .x{flex:1;min-width:0}.o4 .x small{display:block;font-size:14px;color:var(--onv);line-height:1.3}
.o4.cur{color:var(--primary);font-weight:600}.o4.cur .mr,.o4.cur .mo{color:var(--primary)}
.o4.f4{background:var(--schh)}
.o4 .ck{width:22px;height:22px;border-radius:11px;border:2px solid var(--outline);flex:none;display:grid;place-items:center}
.o4 .ck.on{background:var(--primary);border-color:var(--primary);color:var(--onPrimary)}.o4 .ck.on .mr{font-size:16px;color:var(--onPrimary)}
.list4{margin-top:12px}
/* settings rows */
.sg4{font:600 14px 'Noto Sans SC';color:var(--primary);padding:0 0 8px 16px}
.sc4{background:var(--scl);border-radius:16px;padding:4px;margin-bottom:20px}
.sr4{min-height:64px;border-radius:12px;display:flex;align-items:center;gap:16px;padding:10px 16px}
.sr4>.mr,.sr4>.mo,.sr4>.rx{font-size:24px;color:var(--onv);flex:none}
.sr4 .x{flex:1;min-width:0}.sr4 .x .a{font:400 17px/1.35 'Noto Sans SC'}.sr4 .x .b{font:400 14px/1.4 'Noto Sans SC';color:var(--onv);margin-top:2px}
.sr4 .v{font:400 16px 'Noto Sans SC';color:var(--onv);display:flex;align-items:center;gap:2px}.sr4 .v .mr{font-size:22px}
.sr4.f4{background:var(--schh)}
.sw4{width:48px;height:28px;border-radius:14px;border:2px solid var(--outline);background:var(--schh);position:relative;flex:none}
.sw4::after{content:'';position:absolute;left:5px;top:5px;width:14px;height:14px;border-radius:7px;background:var(--outline)}
.sw4.on{background:var(--primary);border-color:var(--primary)}.sw4.on::after{left:auto;right:3px;top:3px;width:18px;height:18px;border-radius:9px;background:var(--onPrimary)}
.sl4{height:6px;border-radius:3px;background:rgba(160,202,253,.2);margin-top:10px;position:relative}.sl4 i{position:absolute;left:0;top:0;bottom:0;border-radius:3px;background:var(--primary)}
.sl4 u{position:absolute;top:-5px;width:16px;height:16px;border-radius:8px;background:var(--primary);margin-left:-8px}
/* status */
.st4{display:flex;flex-direction:column;align-items:center;text-align:center}
.st4 .ic{width:88px;height:88px;border-radius:44px;background:rgba(160,202,253,.1);display:grid;place-items:center;color:var(--primary)}
.st4 .ic .mr,.st4 .ic .mo,.st4 .ic .rx{font-size:44px}
.st4 .h{font:600 22px/1.3 'Noto Sans SC';margin-top:20px}
.st4 .s{font:400 16px/1.6 'Noto Sans SC';color:var(--onv);margin-top:6px;max-width:420px}
.st4 .bs{display:flex;gap:12px;margin-top:22px}
.toast4{position:absolute;left:50%;bottom:48px;transform:translateX(-50%);z-index:30;background:#E1E2E8;color:#1D2024;font:400 16px 'Noto Sans SC';padding:12px 20px;border-radius:12px;white-space:nowrap;box-shadow:0 6px 18px rgba(0,0,0,.4)}
.hint4{position:absolute;right:48px;bottom:10px;font:400 14px 'Noto Sans SC';color:var(--onv);display:flex;gap:16px}
.hint4 kbd{font:600 12px 'Geist';border:1px solid var(--outline);border-radius:4px;padding:0 4px;margin-right:4px;color:var(--on)}
.qr{background:#fff;border-radius:6px;padding:6px;display:grid;grid-template-columns:repeat(21,1fr);gap:0}
.qr i{aspect-ratio:1;background:#101014}.qr i.o{background:transparent}
.ttl4{font:600 22px/1.3 'Noto Sans SC'}
.sub4{font:400 14px/1.4 'Noto Sans SC';color:var(--onv)}
'''

# ---------- a fake QR pattern (shown as "示意") ----------
def qr(size=120):
    import random
    rnd = random.Random(7)
    cells = []
    for y in range(21):
        for x in range(21):
            finder = any(x0 <= x < x0 + 7 and y0 <= y < y0 + 7 for x0, y0 in ((0, 0), (14, 0), (0, 14)))
            if finder:
                xx, yy = (x % 7 if x < 7 else (x - 14) % 7), (y % 7 if y < 7 else (y - 14) % 7)
                on = xx in (0, 6) or yy in (0, 6) or (2 <= xx <= 4 and 2 <= yy <= 4)
            else:
                on = rnd.random() < 0.48
            cells.append('<i></i>' if on else '<i class="o"></i>')
    return f'<div class="qr" style="width:{size}px">{"".join(cells)}</div>'


# ================= pure_live_TV pieces =================
RAIL3 = [('favorite', '关注', mr('favorite_border', 14)), ('hot', '热门', mo('local_fire_department', 14)),
         ('areas', '分类', r('function_line', 14)), ('favareas', '分区', mo('collections_bookmark', 14)),
         ('movie', '放映', mo('movie_creation', 14)), ('search', '搜索', mr('search', 14)), ('history', '记录', mr('history', 14))]
RAIL3_LONG = {'favorite': '直播关注', 'hot': '热门直播', 'areas': '分区类别', 'favareas': '关注分区', 'movie': '链接放映',
              'search': '搜索直播', 'history': '观看记录'}


def rail3(sel='favorite', focus=None, expanded=False, mode_focus=False, n=None):
    """home_page.dart:321-431: clock, mode button, destinations, settings at the bottom."""
    if expanded:
        items = ''.join(f'<div class="rb{" on" if k == sel else ""}{" f fmk fr" if k == focus else ""}" style="margin-bottom:10px">{ic}<span>{RAIL3_LONG[k]}</span></div>'
                        for k, _, ic in RAIL3)
        return ('<div class="rail x"><div class="clk">21:36:08</div><div class="clkd">2026/10/01</div><div style="height:7px"></div>'
                f'<div class="rb{" f fmk fr" if mode_focus else ""}" style="margin-bottom:10px">{mr("live_tv", 12)}<span>直播</span></div>{items}'
                f'<div style="flex:1"></div><div class="rb">{mo("settings", 12)}<span>设置</span></div></div>')
    items = ''.join(f'<div class="rt{" on" if k == sel else ""}{" f fmk fr" if k == focus else ""}" style="margin-bottom:10px">{ic}<b>{lab}</b></div>'
                    for k, lab, ic in RAIL3)
    return ('<div class="rail"><div class="clk">21:36</div><div style="height:7px"></div>'
            f'<div class="rt{" f fmk fr" if mode_focus else ""}" style="margin-bottom:10px">{mr("live_tv", 14)}<b>直播</b></div>{items}'
            f'<div style="flex:1"></div><div class="rt">{mo("settings", 14)}<b>设置</b></div></div>')


def tabs3(items, sel=0, focus=None, style=''):
    """tv_tab_bar.dart: items are (label, logo id or None or 'all')."""
    out = ''
    for i, (lab, logo) in enumerate(items):
        ic = mr('apps', 12) if logo == 'all' else (f'<img src="{LOGO(logo)}">' if logo else '')
        cls = 'pl' + (' on' if i == sel else '') + (' f fmk' if i == focus else '')
        out += f'<div class="{cls}">{ic}{lab}</div>'
    return f'<div class="tb3" style="{style}">{out}</div>'


def chip3(text, icon=None, color='#fff', pos=''):
    ic = f'<span class="mr" style="color:{color}">{icon}</span>' if icon else ''
    return f'<div class="ch3" style="{pos}">{ic}{text}</div>'


def card3(rid, focused=False, followed=False, replay=False, audience=True, state=None, chan=None):
    """tv_room_card.dart:91-325."""
    _, plat, title, nick, img, kind, fig = R[rid]
    bg = '' if state in ('loading', 'error') else f'background-image:url({cover(img)})'
    inner = ''
    if state == 'loading':
        inner = '<div style="position:absolute;inset:0;display:grid;place-items:center"><div style="width:16px;height:16px;border-radius:8px;border:1.3px solid #00A1FF;border-right-color:rgba(0,161,255,.1)"></div></div>'
    if state == 'error':
        inner = ('<div style="position:absolute;inset:0;display:grid;place-items:center"><div style="width:34px;height:34px;border-radius:17px;background:rgba(0,161,255,.1);'
                 'border:.75px solid rgba(0,161,255,.35);display:grid;place-items:center;color:#00A1FF">' + mr('wifi_off', 18) + '</div></div>')
    chips = chip3(plat.upper(), pos='left:6px;top:6px')
    if followed:
        chips = (f'<div style="position:absolute;left:6px;top:6px;display:flex;gap:4px"><div class="ch3" style="position:static">{plat.upper()}</div>'
                 f'<div class="ch3" style="position:static"><span class="mr" style="color:#FF5C7A">favorite</span>已关注</div></div>')
    if replay:
        chips += chip3('重播', 'videocam', pos='right:6px;top:6px')
    elif audience:
        chips += chip3(fig, 'whatshot', pos='right:6px;bottom:6px')
    lead = (f'<div class="a" style="background-image:url({avatar(rid)})"></div>' if chan is None else
            f'<div style="width:28px;text-align:center;font:800 14px Geist">{chan}</div>')
    return (f'<div class="c3{" f fmk" if focused else ""}"><div class="cv" style="{bg}">{inner}{chips}</div>'
            f'<div class="inf">{lead}<div class="t"><div class="x">{title}</div><div class="y">{nick}</div></div></div></div>')


def area3(name, img, focused=False, h=None):
    st = f'height:{h}px' if h else ''
    return (f'<div class="a3{" f fmk" if focused else ""}" style="{st}"><div class="im" style="background-image:url({cover(img)});background-size:cover"></div>'
            f'<div class="n">{name}</div></div>')


def btn3(text, icon=None, size='', kind='', extra=''):
    ic = icon or ''
    return f'<span class="b3 {size} {kind}"{extra}>{ic}{text}</span>'


def dialog3(title, body, buttons, width=400, top='50%'):
    return (f'<div class="scr3"></div><div class="d3" style="width:{width}px;top:{top}"><div class="h">{title}</div>{body}'
            f'<div class="ac">{buttons}</div></div>')


def status3(kind, title, sub, icon, buttons=''):
    """app_status_view.dart:349-425 (non-mini)."""
    return (f'<div style="display:flex;flex-direction:column;align-items:center;justify-content:center;height:100%;text-align:center">'
            f'<div style="padding:11px;border-radius:50%;background:rgba(0,161,255,.1);border:.75px solid rgba(0,161,255,.35);color:#00A1FF">{icon}</div>'
            f'<div style="height:20px"></div><div style="font:600 12px Noto Sans SC">{title}</div>'
            f'<div style="height:3px"></div><div style="font:400 12px Noto Sans SC">{sub}</div>'
            + (f'<div style="height:12px"></div><div style="display:flex;gap:8px">{buttons}</div>' if buttons else '') + '</div>')


# ================= new design pieces =================
RAIL4 = [('favorite', '关注', r('heart_3_line', 24), r('heart_3_fill', 24)),
         ('hot', '热门', r('fire_line', 24), r('fire_fill', 24)),
         ('areas', '分区', r('shapes_line', 24), r('shapes_fill', 24)),
         ('favareas', '关注分区', r('heart_add_2_line', 24), r('heart_add_2_line', 24)),
         ('movie', '链接放映', mo('movie_creation', 24), mr('movie_creation', 24)),
         ('search', '搜索', SEARCH_CI(24), SEARCH_CI(24)),
         ('history', '观看记录', r('history_line', 24), r('history_line', 24))]


def rail4(sel='favorite', focus=None, expanded=False, n=False, mode='直播'):
    """Collapsed: icons; focused: expands over the content with the names."""
    N = (lambda k: k) if n else (lambda k: None)
    x = ' x' if expanded else ''
    clock = ('<div class="clk4">21:36</div><div class="clkd4">10月1日 周三</div>' if expanded else '<div class="clk4">21:36</div>')
    mode_icon = {'直播': mr('live_tv', 24), '视频': mo('movie', 24), '音乐': mo('library_music', 24)}[mode]
    items = ''
    for i, (k, lab, ic, icf) in enumerate(RAIL4):
        cls = 'ri' + (' on' if k == sel else '') + (' f4 ns fmk fr' if k == focus else '')
        items += f'<div class="{cls}"{at(N(i + 2), "chg" if k in ("areas", "favareas", "search", "history") else "keep", "l")}><span>{icf if k == sel else ic}</span><b>{lab}</b></div>'
    modef = ' f4 ns fmk fr' if focus == 'mode' else ''
    return (f'<div class="rail4{x}">{clock}<div style="height:12px"></div>'
            f'<div class="ri{modef}"{at(N(1), "keep", "l")}><span>{mode_icon}</span><b>{mode}</b><span class="dd">{mr("unfold_more", 20)}</span></div>'
            f'<div class="rsep"></div>{items}<div style="flex:1"></div>'
            f'<div class="ri{" f4 ns fmk fr" if focus == "settings" else ""}"{at(N(9), "chg", "l")}><span>{r("settings_5_line", 24)}</span><b>设置</b></div></div>')


def tabs4(items, sel=0, focus=None, n=None, tag='keep', style=''):
    """items: (label, logo id / 'all' / None, count or None)."""
    out = ''
    for i, it in enumerate(items):
        lab, logo = it[0], it[1]
        cnt = it[2] if len(it) > 2 else None
        ic = mr('apps', 20) if logo == 'all' else (f'<img src="{LOGO(logo)}">' if logo else '')
        cls = 'pl4' + (' on' if i == sel else '') + (' f4 fmk' if i == focus else '')
        c = f'<span class="n">{cnt}</span>' if cnt is not None else ''
        out += f'<div class="{cls}"{at(n if i == 0 and n else None, tag, "tl")}>{ic}{lab}{c}</div>'
    return f'<div class="tb4" style="{style}">{out}</div>'


def chip4(inner, pos, cls=''):
    return f'<div class="ch4 {cls}" style="{pos}">{inner}</div>'


def card4(rid, focused=False, plat=False, followed=False, replay=False, offline=False, restricted=None,
          audience=True, state=None, chan=None, marquee=False, nn=None, title=None, nick=None):
    """Room card, TV style of U.4a: platform logo + name in mixed lists, live audience, replay, restricted."""
    _, p, t, nk, img, kind, fig = R[rid]
    t, nk = title or t, nick or nk
    if state == 'loading':
        cvs = 'background:var(--sch)'
        inner = f'<div style="position:absolute;inset:0;display:grid;place-items:center;color:var(--outline)">{mr("live_tv", 32)}</div>'
    else:
        cvs = f'background-image:url({cover(img)})'
        inner = ''
    chips = ''
    left = ''
    if plat:
        left += f'<div class="ch4" style="position:static"><img src="{LOGO(p)}">{SITE.get(p, p)}</div>'
    if followed:
        left += f'<div class="ch4" style="position:static;padding:0 5px"><span class="mr" style="color:#FF5C7A">favorite</span></div>'
    if left:
        chips += f'<div style="position:absolute;left:8px;top:8px;display:flex;gap:4px;z-index:2">{left}</div>'
    if replay:
        chips += chip4(mr('videocam', 15) + '录播', 'right:8px;top:8px')
    if restricted:
        chips += chip4(mr('lock', 15) + restricted, 'right:8px;top:8px')
    if audience and not offline and not replay:
        icon = {'whatshot': 'whatshot', 'people_alt': 'people_alt'}.get(kind, 'whatshot')
        chips += chip4(mr(icon, 15) + fig, 'right:8px;bottom:8px', 'tn')
    off = '<div class="dk"></div><div class="offlbl">未开播</div>' if offline else ''
    lead = (f'<div class="a" style="background-image:url({avatar(rid)})"></div>' if chan is None else f'<div class="nb">{chan}</div>')
    tt = f'<div class="x mq"><span>{t}</span></div>' if marquee else f'<div class="x">{t}</div>'
    return (f'<div class="c4{" f4 fmk" if focused else ""}"{at(nn, "chg", "tl")}><div class="cv" style="{cvs}">{inner}{off}{chips}</div>'
            f'<div class="inf">{lead}<div class="t">{tt}<div class="y">{nk}</div></div></div></div>')


def skel4():
    return '<div class="sk4"><div class="cv"></div><div class="ln"></div><div class="ln b"></div></div>'


def area4(name, img, focused=False, sub=None, followed=False, nn=None, noimg=False):
    im = f'background-image:url({cover(img)})' if not noimg else ''
    inner = '' if not noimg else f'<div style="position:absolute;inset:0;display:grid;place-items:center;color:var(--outline)">{mr("live_tv", 36)}</div>'
    h = f'<div class="hrt">{mr("favorite", 15)}</div>' if followed else ''
    s = f'<div class="s">{sub}</div>' if sub else '<div style="height:8px"></div>'
    return (f'<div class="a4{" f4 fmk" if focused else ""}"{at(nn, "chg", "tl")}><div class="im" style="{im}">{inner}{h}</div>'
            f'<div class="n">{name}</div>{s}</div>')


def btn4(text, icon=None, focused=False, kind='', nn=None, tag='keep', extra=''):
    ic = icon or ''
    cls = 'b4 ' + kind + (' f4 fmk' if focused else '')
    return f'<span class="{cls}"{at(nn, tag)}{extra}>{ic}{text}</span>'


def dialog4(title, body, buttons, sub=None, width=520, top='50%', scrim=True):
    s = f'<div class="hs">{sub}</div>' if sub else ''
    return ((('<div class="scr4"></div>') if scrim else '') +
            f'<div class="d4" style="width:{width}px;top:{top}"><div class="h">{title}</div>{s}{body}'
            f'<div class="ac">{buttons}</div></div>')


def status4(icon, title, sub, buttons=''):
    return (f'<div class="st4"><div class="ic">{icon}</div><div class="h">{title}</div><div class="s">{sub}</div>'
            + (f'<div class="bs">{buttons}</div>' if buttons else '') + '</div>')


# ================= page contents shared by U.15b (home) and U.15c (browse) =================
FAV_STATUS3 = [('正在直播', None), ('正在重播', None), ('未开播', None)]
FAV_PLATS3 = [('全部', 'all'), ('哔哩哔哩', 'bilibili'), ('斗鱼', 'douyu'), ('虎牙', 'huya'), ('抖音', 'douyin')]
FAV_TAGS = ['全部', '常看', '睡前听', '游戏', '学习']


def tagrow3(sel=0):
    """favorite_page.dart:313-353: mini TvButtons, 44.ts tall row."""
    b = ''.join(f'<span class="b3 {"on" if i == sel else "sec"}">{t}</span>' for i, t in enumerate(FAV_TAGS))
    return f'<div style="height:22px;display:flex;align-items:center;gap:6px;padding:0 4px">{b}</div>'


def fav3(focus=None, tags=True, status_focus=None):
    """pure_live_TV favorites pane (favorite_page.dart:264-391)."""
    cards = ''.join(card3(k, focused=(k == focus)) for k in 'aibcjdkemnop')
    return (tabs3(FAV_STATUS3, 0, status_focus) + '<div style="height:6px"></div>' + tabs3(FAV_PLATS3, 0)
            + '<div style="height:6px"></div>' + (tagrow3() if tags else '') + '<div style="height:8px"></div>'
            + f'<div class="grid3">{cards}</div>')


def tagrow4(sel=0, n=None):
    out = ''.join(f'<div class="pl4 sm{" on" if i == sel else ""}"{at(n if i == 0 and n else None, "keep", "tl")}>{t}</div>' for i, t in enumerate(FAV_TAGS))
    return f'<div class="tb4" style="height:32px;gap:8px">{out}</div>'


def fav4(focus=None, tags=True, n=False, rows='aibcjdkemnop', plat_focus=None):
    """New favorites pane (U.15c): status and platform tabs in one row (U.4c c3), counts (U.4c c4)."""
    N = (lambda k: k) if n else (lambda k: None)
    status = tabs4([('已开播', None, 12), ('录播', None, 1), ('未开播', None, 23)], 0, n=N(11), tag='chg')
    plats = tabs4([('全部', 'all', 13), ('哔哩哔哩', 'bilibili', 7), ('斗鱼', 'douyu', 3), ('虎牙', 'huya', 2)], 0, plat_focus, n=N(12), tag='chg')
    cards = ''.join(card4(k, focused=(k == focus), plat=True, marquee=(k == focus), nn=(N(14) if i == 0 else None))
                    for i, k in enumerate(rows))
    return (f'<div style="display:flex;align-items:center;gap:8px;height:40px">{status.replace("class=\"tb4\"", "class=\"tb4\" style=\"flex:none\"", 1)}'
            f'<span class="vsep"></span>{plats}</div>'
            + (f'<div style="height:12px"></div>{tagrow4(n=N(13))}' if tags else '')
            + f'<div class="g4" style="margin-top:16px">{cards}</div>')
