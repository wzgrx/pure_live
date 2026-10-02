"""U.3c splash page and start-up prompts: v3 restored and the new design.

v3 (tag v3.2.11):
  lib/modules/splash/splash_screen.dart   logo fade 0->1 (easeIn) and scale
                                          0.8->1 (easeOutBack) over 2 s (:50-58),
                                          text, 30, progress bar, 30 (:86-111)
  lib/routes/app_pages.dart:188-235       gradient (light #E0F7FA..#80DEEA,
                                          dark #0D1B2A..#141E27), icon 150,
                                          "欢迎使用" t20 bold black54/white70,
                                          progressBar loader, leaves after 1 s
                                          (+ up to 350 ms follow check)
  lib/common/global/platform/desktop_manager.dart:595-650  share-command check
  lib/modules/home/home_page.dart:99-104, :198-216           update check at 2 s
At 1.0 s easeIn(0.5) = 0.315 and easeOutBack(0.5) = 1.068, so the page leaves
with the logo at about a third of its opacity (0.52 at 1.35 s).

U.3d imports this file for the v3 dialogs (new version, share command).
    python3 docs/ui/compare/U.3c/src/gen.py && python3 tools/ui/mock/render.py docs/ui/compare/U.3c/src/ --annotate
    python3 tools/ui/mock/render.py docs/ui/compare/U.3c/src/{v3,v4}-splash.html --dark"""
import importlib.util
import os
import sys

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location('u3a', os.path.join(HERE, '..', '..', 'U.3a', 'src', 'gen.py'))
A = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(A)
mr, mi, rx = A.mr, A.mi, A.rx

ICON = '../../../apps/pure_live/assets/icons/icon.png'   # same file as v3 assets/icons/icon.png

CSS = '''
.sp{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center}
.sp .logo{width:150px;height:150px;background:url(%s) center/contain no-repeat}
.v3sp{background:linear-gradient(135deg,#E0F7FA,#B2EBF2 50%%,#80DEEA)}
[data-theme=dark] .v3sp{background:linear-gradient(135deg,#0D1B2A,#1B263B 50%%,#141E27)}
.v3sp .w{font-size:20px;font-weight:700;color:rgba(0,0,0,.54);line-height:28px}
[data-theme=dark] .v3sp .w{color:rgba(255,255,255,.7)}
.v3bar{width:200px;height:4px;background:rgba(255,255,255,.3);position:relative;overflow:hidden}
.v3bar i{position:absolute;left:30%%;width:38%%;top:0;bottom:0;background:#fff}
.v4sp{background:linear-gradient(160deg,var(--surface) 0%%,var(--surface) 45%%,rgba(209,228,255,.7) 100%%)}
[data-theme=dark] .v4sp{background:linear-gradient(160deg,var(--surface) 0%%,var(--surface) 45%%,rgba(25,73,117,.45) 100%%)}
.v4sp .w{font-size:20px;font-weight:600;color:var(--on);line-height:28px;margin-top:16px}
.v4bar{width:200px;height:4px;border-radius:2px;background:rgba(54,97,142,.15);position:relative;overflow:hidden;margin-top:32px}
[data-theme=dark] .v4bar{background:rgba(160,202,253,.18)}
.v4bar i{position:absolute;left:30%%;width:38%%;top:0;bottom:0;border-radius:2px;background:var(--primary)}
.status.on-sp{position:absolute;left:0;right:0;top:0;z-index:5}
.cap{position:absolute;left:12px;right:12px;bottom:28px;z-index:6;text-align:center;font-size:12px;color:var(--onv)}
/* v3 dialogs (AlertDialog: surfaceContainerHigh, radius 24, padding 24) */
.ov{position:absolute;inset:0;z-index:20;display:flex;align-items:center;justify-content:center;background:rgba(0,0,0,.54)}
.d3{background:var(--sch);border-radius:24px;padding:24px 24px 0;color:var(--on)}
.d3 .t{font-size:20px;font-weight:600;line-height:28px;margin-bottom:16px}
.d3 .acts{display:flex;justify-content:flex-end;align-items:center;gap:8px;padding:24px 0 24px}
.tb3{height:40px;padding:0 12px;border-radius:8px;display:flex;align-items:center;font-size:13px;font-weight:500;color:var(--primary)}
.fb3{height:40px;padding:0 24px;border-radius:20px;display:flex;align-items:center;font-size:13px;font-weight:500;background:var(--primary);color:var(--onPrimary)}
.md{font-size:16px;line-height:24px;color:var(--on)}
.md li{list-style:none;position:relative;padding-left:22px;margin:0 0 6px}
.md li::before{content:'';position:absolute;left:6px;top:10px;width:5px;height:5px;border-radius:3px;background:var(--on)}
.lnk3{display:inline-flex;align-items:center;gap:8px;height:40px;padding:0 16px 0 12px;font-size:15px;color:var(--primary)}
.idb{background:var(--scl);border:1px solid rgba(195,199,207,.35);border-radius:12px;padding:12px;font-size:13px;margin-top:16px}
.idb .r{display:flex;gap:8px}.idb .r+.r{margin-top:10px}.idb .k{color:var(--onv)}.idb .v{font-weight:600}
/* start-up order diagram */
.flow{padding:28px 32px;display:flex;flex-direction:column;gap:18px}
.flow h3{font-size:17px;font-weight:600}
.lane{display:flex;align-items:stretch;gap:10px}
.step{flex:1;border-radius:12px;padding:12px 14px;background:var(--scl);box-shadow:inset 0 0 0 1px var(--ov);font-size:14px;line-height:1.5}
.step b{display:block;font-size:15px;margin-bottom:2px}.step small{color:var(--onv);font-size:13px}
.step.bad{box-shadow:inset 0 0 0 2px #D92D20;background:#FCEEEE}
.arr{display:grid;place-items:center;color:var(--onv);flex:none}
''' % ICON


def page(w, h, scale, body, frame='ph'):
    style = '' if frame == 'ph' else f' style="--w:{w}px;--h:{h}px"'
    return (f'<!doctype html><html><head><meta charset="utf-8"><meta name="mock-size" content="{w}x{h}@{scale}">'
            f'<link rel="stylesheet" href="kit/kit.css"><style>{A.CSS}{CSS}</style></head>'
            f'<body><div class="{frame}"{style}>{body}</div></body></html>')


# ---------- splash ----------
def v3_splash(opacity=0.315, scale=1.014, phone=True):
    o = f'opacity:{opacity};transform:scale({scale})'
    return ((A.status_bar().replace('class="status"', 'class="status on-sp"') if phone else '')
            + f'<div class="sp v3sp"><div class="logo" style="{o}"></div><div class="w" style="{o}">欢迎使用</div>'
            '<div style="height:30px"></div><div class="v3bar"><i></i></div><div style="height:30px"></div></div>')


def v4_splash(phone=True, n=True):
    return ((A.status_bar().replace('class="status"', 'class="status on-sp"') if phone else '')
            + '<div class="sp v4sp"' + (A.attrs(1, 'add', 'c') if n else '') + '><div class="logo"></div><div class="w">欢迎使用</div>'
            '<div class="v4bar"><i></i></div><div style="height:30px"></div></div>')


# ---------- v3 dialogs (also used by U.3d) ----------
UPDATE_LOG = ['斗鱼原画不再每 5 分钟断流：到期前在后台换链接并按关键帧无缝接上，没有卡顿。',
              'Android armv7 与 x86_64 改用自编 FFmpeg 9 播放库。',
              '下线 Kick（Cloudflare 拦截），现支持 33 个平台 + IPTV。']    # assets/version.json, 3.2.11


def v3_update_dialog(width=361):
    """version_dialog.dart:26-86: title 检查更新, open-source link (t15),
    the update log as Markdown, 取消 / 更新."""
    log = '<ul class="md">' + ''.join(f'<li>{x}</li>' for x in UPDATE_LOG) + '</ul>'
    return (f'<div class="d3" style="width:{width}px"><div class="t">检查更新</div>'
            '<div class="lnk3">' + mr('open_in_new', 18) + '本软件开源免费</div>' + log + '<div style="height:10px"></div>'
            '<div class="acts" style="padding-top:14px"><div class="tb3">取消</div><div class="fb3">更新</div></div></div>')


ROOM = ('深夜电台 · 点歌接龙到天亮', '晚风', 'bilibili', '21452505')


def v3_share_dialog(width=353):
    """share_command_import_dialog.dart:17-71: radius 16, title 分享, avatar
    24, title titleMedium w700, nick, a box with the platform id and room id."""
    title, nick, plat, rid = ROOM
    return (f'<div class="d3" style="width:{width}px;border-radius:16px"><div class="t">分享</div>'
            '<div style="display:flex;gap:12px;align-items:flex-start"><span class="av" style="width:48px;height:48px;border-radius:24px;'
            'background-image:url(.cache/img/65.jpg)"></span><div style="min-width:0"><div style="font-size:15px;font-weight:700;line-height:21px">'
            f'{title}</div><div style="font-size:13px;color:var(--onv);margin-top:4px">{nick}</div></div></div>'
            f'<div class="idb"><div class="r"><span class="k">平台</span><span class="v">{plat}</span></div>'
            f'<div class="r"><span class="k">房间号</span><span class="v">{rid}</span></div></div>'
            '<div class="acts"><div class="tb3" style="height:48px">取消</div><div class="fb3" style="height:48px">进入房间</div></div></div>')


def overlay(inner, pad='0 16px'):
    return f'<div class="ov" style="padding:{pad}">{inner}</div>'


def home_v3():
    return A.status_bar() + A.v3_bar_favorites() + '<div class="main">' + A.favorites_body() + '</div>' + A.nav_bar(0)


def flow():
    arr = '<div class="arr">' + mr('arrow_forward', 20) + '</div>'
    v3 = ('<h3>v3</h3><div class="lane"><div class="step"><b>启动页</b><small>1 秒 + 最多 0.35 秒</small></div>' + arr
          + '<div class="step"><b>首页</b><small>剪贴板有分享口令：马上弹“分享”</small></div>' + arr
          + '<div class="step bad"><b>2 秒后“检查更新”</b><small>不管在哪个页面、前面有没有对话框，都直接盖上去</small></div></div>')
    v4 = ('<h3>新设计</h3><div class="lane"><div class="step"><b>启动页</b><small>动画 0.4 秒做完，停 1 秒；点一下直接进首页</small></div>' + arr
          + '<div class="step"><b>首页</b><small>有分享口令：先弹“打开分享的直播间”</small></div>' + arr
          + '<div class="step"><b>新版本提示</b><small>前一个对话框关了、并且在首页时才弹；进了直播间就等回到首页</small></div></div>')
    return f'<div class="flow">{v3}{v4}</div>'


def build():
    out = {}
    out['v3-splash'] = page(393, 852, 3, v3_splash())
    out['v3-splash-full'] = page(393, 852, 3, v3_splash(1, 1))
    out['v4-splash'] = page(393, 852, 3, v4_splash())
    out['v3-splash-wide'] = page(1280, 800, 1.5, v3_splash(phone=False), 'win')
    out['v4-splash-wide'] = page(1280, 800, 1.5, v4_splash(phone=False, n=False), 'win')
    out['v3-startup-share'] = page(393, 852, 3, home_v3() + overlay(v3_share_dialog(), '0 20px')
                                   + '<div class="syn" style="z-index:46">示意图片</div>')
    out['v3-startup-stack'] = page(393, 852, 3, home_v3() + overlay(v3_share_dialog(), '0 20px') + overlay(v3_update_dialog())
                                   + '<div class="syn" style="z-index:46">示意图片</div>')
    out['startup-order'] = page(860, 330, 2, flow(), 'win')
    return out


if __name__ == '__main__':
    pages = build()
    for name, html in pages.items():
        open(os.path.join(HERE, name + '.html'), 'w', encoding='utf-8').write(html)
    print(len(pages), 'pages')
