"""U.3d global dialogs: new version, download directory, update download,
share-command import. v3 restored and the new design.

v3 (tag v3.2.11):
  lib/modules/about/widgets/version_dialog.dart:26-86     NewVersionDialog
  lib/common/widgets/download_directory_dialog.dart:17-64  directory prompt
  lib/common/widgets/download_apk_dialog.dart:489-702      download dialog
  lib/plugins/update.dart:61-146                           the flow and toasts
  lib/common/widgets/share_command_import_dialog.dart      share import
The v3 new-version and share dialogs, the home pages and the rails come from
U.3c, U.3a and U.3b (same pieces everywhere).
    python3 docs/ui/compare/U.3d/src/gen.py && python3 tools/ui/mock/render.py docs/ui/compare/U.3d/src/ --annotate"""
import importlib.util
import os
import sys

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))


def _load(name, task):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, '..', '..', task, 'src', 'gen.py'))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


A = _load('u3a', 'U.3a')
B = _load('u3b', 'U.3b')
C = _load('u3c', 'U.3c')
mr, mi, rx, attrs = A.mr, A.mi, A.rx, A.attrs

CSS = '''
.d4{background:var(--sch);border-radius:24px;padding:24px 24px 0;color:var(--on);display:flex;flex-direction:column;max-height:100%}
.d4 .t{font-size:20px;font-weight:600;line-height:28px}
.d4 .sub{font-size:14px;color:var(--onv);margin-top:6px;line-height:20px;display:flex;flex-wrap:wrap;gap:4px 12px;align-items:center}
.d4 .lk{color:var(--primary);display:inline-flex;align-items:center;gap:2px}
.d4 .msg{font-size:14px;line-height:1.5;margin-top:16px}
.d4 .acts{display:flex;align-items:center;gap:8px;padding:20px 0 24px;flex:none}
.d4 .acts .gap{flex:1}
.tb4{height:40px;padding:0 12px;border-radius:20px;display:flex;align-items:center;font-size:14px;font-weight:500;color:var(--primary);white-space:nowrap}
.tb4.gr{color:var(--onv)}
.fb4{height:40px;padding:0 20px;border-radius:20px;display:flex;align-items:center;gap:6px;font-size:14px;font-weight:500;background:var(--primary);color:var(--onPrimary);white-space:nowrap}
.fb4.hv{box-shadow:0 0 0 3px rgba(54,97,142,.25);background:#2E5780}
.ob4{height:40px;padding:0 16px;border-radius:20px;display:flex;align-items:center;gap:6px;font-size:14px;font-weight:500;color:var(--primary);box-shadow:inset 0 0 0 1px var(--outline);white-space:nowrap}
.lg{font-size:13px;font-weight:600;color:var(--primary);margin:18px 0 6px}
.log{font-size:14px;line-height:21px;color:var(--on);overflow:hidden;position:relative}
.log li{list-style:none;position:relative;padding-left:16px;margin:0 0 6px}
.log li::before{content:'';position:absolute;left:4px;top:8px;width:5px;height:5px;border-radius:3px;background:var(--onv)}
.log.fade::after{content:'';position:absolute;left:0;right:0;bottom:0;height:36px;background:linear-gradient(transparent,var(--sch))}
.ck{display:flex;align-items:center;gap:10px;height:48px;font-size:14px;margin-top:8px;white-space:nowrap}
.ck .bx{width:18px;height:18px;border-radius:2px;box-shadow:inset 0 0 0 2px var(--onv);flex:none}
.path{font-size:14px;color:var(--onv);margin-top:12px;word-break:break-all;line-height:1.5}
/* download dialog */
.dl{background:var(--sch);border-radius:24px;padding:16px;color:var(--on)}
.dl .hd{display:flex;gap:16px;align-items:flex-start}
.dl .hd.col{flex-direction:column;gap:12px}
.ic{width:44px;height:44px;border-radius:22px;background:rgba(54,97,142,.1);display:grid;place-items:center;flex:none;color:var(--primary)}
.ic.err{color:var(--error);background:rgba(186,26,26,.1)}
.spin{width:22px;height:22px;border-radius:11px;border:2.5px solid var(--primary);border-right-color:transparent;border-bottom-color:transparent;transform:rotate(30deg)}
.spin.s18{width:18px;height:18px;border-width:2px}
.dl .dtt{font-size:15px;font-weight:700;line-height:21px}
.dl .dst{word-break:break-all;font-size:12px;font-weight:500;color:var(--primary);margin-top:4px;line-height:17px}
.dl .dst.err{color:var(--error)}
.dl.v4 .dtt{font-weight:600}.dl.v4 .dst{font-size:14px;line-height:20px;font-weight:400;color:var(--onv)}
.dl.v4 .dst.err{color:var(--error)}
.pg{margin-top:20px;padding:14px 16px;border-radius:16px;background:var(--scl);display:flex;align-items:center;gap:16px}
.pg.col{flex-direction:column;align-items:stretch;gap:8px}
.pg.col .bar{flex:none}
.bar{flex:1;height:8px;border-radius:8px;background:var(--schh);position:relative;overflow:hidden}
.bar i{position:absolute;left:0;top:0;bottom:0;border-radius:8px;background:var(--primary)}
.bar.ind i{left:22%;width:36%}
.bar.err i{background:var(--outline)}
.pc{width:48px;text-align:right;font-size:14px;font-weight:700;color:var(--primary);font-feature-settings:'tnum'}
.pg.col .pc{width:auto}
.dl .acts{display:flex;gap:8px;justify-content:flex-end;margin-top:16px}
.dl .acts.col{flex-direction:column;align-items:stretch}
.dl .acts.col>div{justify-content:center}
.dl .acts .gap{flex:1}
.fb3i.fb3d,.fb4.fb3d{background:rgba(25,28,32,.12);color:rgba(25,28,32,.38)}
.ob3{height:40px;padding:0 16px;border-radius:20px;display:flex;align-items:center;gap:8px;font-size:13px;font-weight:500;color:var(--primary);box-shadow:inset 0 0 0 1px var(--outline)}
.fb3i{height:40px;padding:0 16px;border-radius:20px;display:flex;align-items:center;gap:8px;font-size:13px;font-weight:500;background:var(--primary);color:var(--onPrimary)}
.snack{position:absolute;left:0;right:0;bottom:100px;z-index:30;background:#2E3135;color:#EFF0F7;font-size:13px;padding:14px 16px}
/* state sheet */
.sheetp{padding:16px 16px 24px;display:flex;flex-direction:column;gap:10px;background:var(--surface)}
.cap2{font-size:13px;font-weight:600;color:var(--onv);margin-top:10px}
.cap2 small{font-weight:400;margin-left:6px}
.room4{display:flex;gap:12px;align-items:flex-start;margin-top:16px}
.room4 .a{width:48px;height:48px;border-radius:24px;background:url(.cache/img/65.jpg) center/cover;flex:none}
.room4 .n{font-size:15px;font-weight:600;line-height:21px}
.room4 .m{font-size:14px;color:var(--onv);margin-top:4px;line-height:20px}
.kbd{display:inline-block;padding:0 5px;border-radius:4px;box-shadow:inset 0 0 0 1px var(--outline);font-size:12px;line-height:18px;color:var(--onv);margin-left:6px}
'''


def page(w, h, scale, body, frame='ph', syn=True):
    style = '' if frame == 'ph' else f' style="--w:{w}px;--h:{h}px"'
    s = '<div class="syn" style="z-index:46">示意图片</div>' if syn else ''
    return (f'<!doctype html><html><head><meta charset="utf-8"><meta name="mock-size" content="{w}x{h}@{scale}">'
            f'<link rel="stylesheet" href="kit/kit.css"><style>{A.CSS}{B.CSS}{C.CSS}{CSS}</style></head>'
            f'<body><div class="{frame}"{style}>{body}{s}</div></body></html>')


def btn(cls, text, n=None, tag=None, icon=''):
    return f'<div class="{cls}"{attrs(n, tag, "bc" if n else None)}>{icon}{text}</div>'


# ---------- backgrounds ----------
def home_v3():
    return C.home_v3()


def home_v4():
    return A.status_bar() + A.v4_bar_favorites(False) + '<div class="main">' + A.favorites_body() + '</div>' + A.nav_bar(0, 'shapes')


def wide_home(v4, w, h, cols):
    rail = B.v4_rail(0, n=False) if v4 else B.v3_rail(0)
    return rail + '<div class="body">' + B.fav_page(cols) + '</div>'


def fs_video():
    return '<div style="position:absolute;inset:0;background:#000 url(.cache/img/274.jpg) center 40%/cover"></div>'


# ---------- new version ----------
def v4_update(n=False, log_h=None, width=361, hover=False, keys=False):
    """Narrow (phone) dialog: the checkbox has its own row; from 480 wide it
    sits at the left of the button row, so a landscape phone shows the whole log."""
    N = (lambda k: k) if n else (lambda k: None)
    log_style = f' style="max-height:{log_h}px"' if log_h else ''
    fade = ' fade' if log_h else ''
    log = f'<ul class="log{fade}"{log_style}>' + ''.join(f'<li>{x}</li>' for x in C.UPDATE_LOG) + '</ul>'
    k = (lambda key: f'<span class="kbd">{key}</span>') if keys else (lambda key: '')
    wide = width >= 480
    check = ('<div class="ck"' + attrs(N(2), 'add' if n else None, 'tl' if n else None)
             + (' style="margin:0 8px 0 0"' if wide else '') + '><span class="bx"></span>不再提醒这个版本</div>')
    other = btn('tb4', '其他下载方式', N(3), 'add' if n else None)
    acts = ('<div class="acts">' + (check + '<div class="gap"></div>' + other if wide else other + '<div class="gap"></div>')
            + btn('tb4', '取消' + k('Esc'), N(4)) + btn('fb4' + (' hv' if hover else ''), '下载并安装' + k('Enter'), N(5), 'chg' if n else None)
            + '</div>')
    return (f'<div class="d4" style="width:{width}px"><div class="t">发现新版本 v3.2.11</div>'
            '<div class="sub"><span>当前 v3.2.10</span><span class="lk"' + attrs(N(1), 'chg' if n else None, 'tr' if n else None) + '>本软件开源免费'
            + mr('open_in_new', 16) + '</span></div><div class="lg">更新内容</div>' + log
            + ('' if wide else check) + acts + '</div>')


# ---------- download directory ----------
DIR_MSG = '当前还没有可用的下载目录。你可以自行选择目录，或使用默认下载目录来存放应用更新、下载文件与字体。'
DIR_PATH = '/storage/emulated/0/Android/data/com.mystyle.purelive/files/downloads/pure_live'


def v3_dir(width=361):
    """download_directory_dialog.dart:20-63: message bodyMedium, default path
    bodySmall in the hint colour, 使用默认目录 / 选择目录 (48 high), no cancel."""
    return (f'<div class="d3" style="width:{width}px"><div class="t">选择下载目录</div>'
            f'<div style="font-size:13px;line-height:1.5">{DIR_MSG}</div>'
            f'<div style="font-size:12px;color:rgba(0,0,0,.6);margin-top:12px;word-break:break-all;line-height:1.45">默认目录：{DIR_PATH}</div>'
            '<div class="acts"><div class="tb3" style="height:48px">使用默认目录</div><div class="fb3" style="height:48px">选择目录</div></div></div>')


def v4_dir(n=False, width=361):
    N = (lambda k: k) if n else (lambda k: None)
    return (f'<div class="d4" style="width:{width}px"><div class="t">选择下载目录</div>'
            f'<div class="msg">{DIR_MSG}</div><div class="path">默认目录：{DIR_PATH}</div>'
            '<div class="acts">' + btn('tb4 gr', '取消', N(6), 'add' if n else None) + '<div class="gap"></div>'
            + btn('tb4', '使用默认目录', N(7)) + btn('fb4', '选择目录', N(8)) + '</div></div>')


# ---------- update download ----------
V3_TITLE = '正在下载 v3.2.11...'


def v3_download(state, compact=True, width=361):
    """download_apk_dialog.dart:489-702. compact = screen narrower than 420."""
    spin = '<div class="spin"></div>'
    icon = {'done': mr('check_circle', 24), 'openfail': mr('error_outline', 24), 'nofolder': mr('error_outline', 24)}.get(state, spin)
    err = state in ('openfail', 'nofolder')
    status = {'prep': '准备中...', 'run': '18.6 MB / 62.4 MB', 'unknown': '已下载: 18 MB', 'done': '下载完成',
              'opening': '下载完成，正在打开文件...', 'openfail': '文件已下载，但打开失败。',
              'nofolder': '系统里没有可以打开该文件夹的应用，文件位置：' + DIR_PATH}[state]
    pct = {'prep': '…', 'unknown': '…', 'run': '30%'}.get(state, '100%')
    fill = {'prep': None, 'unknown': None, 'run': 30}.get(state, 100)
    bar = ('<div class="bar ind"><i></i></div>' if fill is None else f'<div class="bar"><i style="width:{fill}%"></i></div>')
    head = (f'<div class="hd{" col" if compact else ""}"><div class="ic{" err" if err else ""}">{icon}</div><div>'
            f'<div class="dtt">{V3_TITLE}</div><div class="dst{" err" if err else ""}">{status}</div></div></div>')
    prog = f'<div class="pg{" col" if compact else ""}">{bar}<div class="pc">{pct}</div></div>'
    install = '<div class="fb3i">' + mr('install_mobile', 18) + '立即安装</div>'
    folder = '<div class="ob3">' + mr('folder_open', 18) + '打开文件夹</div>'
    if state in ('prep', 'run', 'unknown'):
        acts = '<div class="acts"><div class="tb3">取消</div></div>'
    elif state == 'opening':
        acts = ('<div class="acts col"><div class="fb3i fb3d"><span class="spin s18" style="border-color:rgba(25,28,32,.38);'
                'border-right-color:transparent;border-bottom-color:transparent"></span>下载完成，正在打开文件...</div></div>')
    elif state in ('openfail', 'nofolder'):
        again = '<div class="fb3i">' + mr('install_mobile', 18) + '重新打开</div>'
        close = '<div class="ob3">关闭</div>'
        acts = f'<div class="acts col">{again}{close}</div>' if compact else f'<div class="acts">{close}{again}</div>'
    else:
        acts = f'<div class="acts col">{install}{folder}</div>' if compact else f'<div class="acts">{folder}{install}</div>'
    return f'<div class="dl" style="width:{width}px">{head}{prog}{acts}</div>'


def v4_download(state, n=False, width=361, hover=False):
    N = (lambda k: k) if n else (lambda k: None)
    spin = '<div class="spin"></div>'
    icon = {'done': mr('check_circle', 24), 'nofolder': mr('check_circle', 24), 'openfail': mr('error_outline', 24),
            'fail': mr('error_outline', 24)}.get(state, spin)
    err = state in ('openfail', 'fail')
    title = {'fail': '下载没有完成', 'done': 'v3.2.11 已下载', 'opening': 'v3.2.11 已下载', 'openfail': 'v3.2.11 已下载',
             'nofolder': 'v3.2.11 已下载'}.get(state, '正在下载 v3.2.11')
    status = {'prep': '准备中...', 'run': '18.6 MB / 62.4 MB', 'unknown': '已下载: 18 MB', 'done': '下载完成',
              'opening': '下载完成，正在打开文件...', 'openfail': '文件已下载，但打开失败。',
              'fail': '下载中断，已下载的部分会保留，重试时接着下载',
              'nofolder': '系统里没有可以打开该文件夹的应用，文件位置：' + DIR_PATH}[state]
    pct = {'prep': '…', 'unknown': '…', 'run': '30%', 'fail': '30%'}.get(state, '100%')
    fill = {'prep': None, 'unknown': None, 'run': 30, 'fail': 30}.get(state, 100)
    bar = ('<div class="bar ind"><i></i></div>' if fill is None
           else f'<div class="bar{" err" if state == "fail" else ""}"><i style="width:{fill}%"></i></div>')
    head = (f'<div class="hd"><div class="ic{" err" if err else ""}">{icon}</div><div style="min-width:0">'
            f'<div class="dtt">{title}</div><div class="dst{" err" if err else ""}">{status}</div></div></div>')
    prog = f'<div class="pg">{bar}<div class="pc"' + (' style="color:var(--onv)"' if state == 'fail' else '') + f'>{pct}</div></div>'
    close = btn('tb4 gr', '关闭', N(10) if state == 'done' else None, 'add' if (n and state == 'done') else None)
    if state in ('prep', 'run', 'unknown'):
        acts = btn('tb4', '取消', N(9) if state == 'run' else None)
    elif state == 'opening':
        acts = ('<div class="fb4 fb3d"><span class="spin s18" style="border-color:rgba(25,28,32,.38);border-right-color:transparent;'
                'border-bottom-color:transparent"></span>正在打开</div>')
    elif state == 'openfail':
        acts = close + '<div class="gap"></div>' + btn('fb4', '重新打开', N(15), icon=mr('install_mobile', 18))
    elif state == 'fail':
        acts = (btn('tb4 gr', '关闭') + '<div class="gap"></div>' + btn('tb4', '在浏览器中下载', N(13), 'add' if n else None)
                + btn('fb4', '重试', N(14), 'add' if n else None, mr('refresh', 18)))
    else:
        acts = (close + '<div class="gap"></div>' + btn('tb4', '打开文件夹', N(11) if state == 'done' else None)
                + btn('fb4' + (' hv' if hover else ''), '立即安装', N(12) if state == 'done' else None, None, mr('install_mobile', 18)))
    return f'<div class="dl v4" style="width:{width}px">{head}{prog}<div class="acts">{acts}</div></div>'


def states_sheet(v4):
    items = [('prep', '准备中'), ('run', '下载中'), ('unknown', '大小未知'), ('done', '下载完成'), ('opening', '正在打开安装包'),
             ('openfail', '打开失败'), ('nofolder', '打开文件夹失败（没有能打开文件夹的应用）')]
    if v4:
        items.insert(5, ('fail', '下载失败'))
    out = ''
    for state, cap in items:
        if v4:
            out += f'<div class="cap2">{cap}</div>' + v4_download(state, n=True)
        else:
            out += f'<div class="cap2">{cap}</div>' + v3_download(state)
            if state == 'openfail':
                out += ('<div class="cap2">下载失败<small>对话框直接关掉，只在页面底部弹一行提示条</small></div>'
                        '<div style="background:#2E3135;color:#EFF0F7;font-size:13px;padding:14px 16px">下载失败，请稍后重试</div>')
    return page(393, 2600, 2, f'<div class="sheetp" style="width:393px">{out}</div>', 'win', syn=False).replace('393x2600@2', '393x2600@2 crop')


# ---------- share-command import ----------
def v4_share(n=False, width=353):
    N = (lambda k: k) if n else (lambda k: None)
    title, nick, _, rid = C.ROOM
    return (f'<div class="d4" style="width:{width}px"><div class="t">打开分享的直播间</div>'
            '<div class="sub">从剪贴板识别到分享口令</div>'
            f'<div class="room4"><span class="a"></span><div style="min-width:0"><div class="n">{title}</div>'
            f'<div class="m">{nick} · 哔哩哔哩 · 房间号 {rid}</div></div></div>'
            '<div class="acts"><div class="gap"></div>' + btn('tb4', '取消', N(16)) + btn('fb4', '进入房间', N(17)) + '</div></div>')


def ov(inner, pad='0 16px'):
    return C.overlay(inner, pad)


def build():
    out = {}
    P = (393, 852, 3)
    # new version
    out['v3-update'] = page(*P, home_v3() + ov(C.v3_update_dialog()))
    out['v4-update'] = page(*P, home_v4() + ov(v4_update(n=True)))
    out['v3-update-land'] = page(852, 393, 2, wide_home(False, 852, 393, 3) + ov(C.v3_update_dialog(560), '12px 16px'), 'win')
    out['v4-update-land'] = page(852, 393, 2, wide_home(True, 852, 393, 3) + ov(v4_update(width=560), '12px 16px'), 'win')
    out['v3-update-wide'] = page(1280, 800, 1.5, wide_home(False, 1280, 800, 4) + ov(C.v3_update_dialog(560)), 'win')
    out['v4-update-wide'] = page(1280, 800, 1.5, wide_home(True, 1280, 800, 4) + ov(v4_update(width=560, hover=True)), 'win')
    # download directory
    out['v3-dir'] = page(*P, home_v3() + ov(v3_dir()))
    out['v4-dir'] = page(*P, home_v4() + ov(v4_dir(n=True)))
    # download
    out['v3-download'] = page(*P, home_v3() + ov(v3_download('run')) + '<div class="toast" style="bottom:120px">正在下载 纯粹直播v3.2.11...</div>')
    out['v4-download'] = page(*P, home_v4() + ov(v4_download('run')))
    out['v3-download-states'] = states_sheet(False)
    out['v4-download-states'] = states_sheet(True)
    out['v3-download-wide'] = page(1280, 800, 1.5, wide_home(False, 1280, 800, 4) + ov(v3_download('done', compact=False, width=440)), 'win')
    out['v4-download-wide'] = page(1280, 800, 1.5, wide_home(True, 1280, 800, 4) + ov(v4_download('done', width=440, hover=True)), 'win')
    # share-command import
    out['v3-share'] = page(*P, home_v3() + ov(C.v3_share_dialog(), '0 20px'))
    out['v4-share'] = page(*P, home_v4() + ov(v4_share(n=True), '0 20px'))
    out['v3-share-land'] = page(852, 393, 2, fs_video() + ov(C.v3_share_dialog(360), '24px 20px'), 'fs')
    out['v4-share-land'] = page(852, 393, 2, fs_video() + ov(v4_share(width=400), '24px 20px'), 'fs')
    return out


if __name__ == '__main__':
    pages = build()
    for name, html in pages.items():
        open(os.path.join(HERE, name + '.html'), 'w', encoding='utf-8').write(html)
    print(len(pages), 'pages')
