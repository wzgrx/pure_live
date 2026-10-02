"""U.12b about, version update and version history mockups: v3 restored and
the new design.

v3 (tag v3.2.11): lib/modules/about/about_page.dart, about/version_history.dart
(mobile list :226-305, detail dialog :307-363, desktop :129-224 and :477-525,
download confirm :391-438), about/widgets/version_dialog.dart (new version
prompt), modules/version/version_page.dart (packages and sources :204-341,
source dialog :343-438), plugins/update.dart (18 mirrors + origin).
Version numbers, dates, sizes, change logs and download addresses are examples;
the project address and mirror hosts are replaced by placeholders.
    python3 docs/ui/compare/U.12b/src/gen.py && python3 tools/ui/mock/render.py docs/ui/compare/U.12b/src/ --annotate"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from skit import *  # noqa: E402,F401,F403
from skit import composite as _composite  # noqa: E402

ICON = '../../../apps/pure_live/assets/icons/icon.png'
CSS2 = '''
.logo{width:80px;height:80px;border-radius:24px;box-shadow:0 6px 16px rgba(54,97,142,.06),inset 0 0 0 1px rgba(54,97,142,.08);padding:16px;margin:0 auto}
.logo img{width:100%;height:100%;object-fit:contain}
.app{text-align:center;font-size:20px;font-weight:700;letter-spacing:.5px;margin-top:18px}
.vpill3{display:inline-block;margin-top:6px;padding:2px 8px;border-radius:12px;background:var(--scl);box-shadow:inset 0 0 0 .5px rgba(0,0,0,.05);font-size:11px;font-weight:500;color:var(--onv)}
.vpill3b{padding:4px 10px;border-radius:20px;background:rgba(209,228,255,.5);font-size:11px;font-weight:600;color:var(--primary)}
.newtag{padding:4px 10px;border-radius:12px;background:var(--primary);color:var(--onPrimary);font-size:12px;font-weight:600;white-space:nowrap}
.vbadge2{padding:6px 10px;border-radius:10px;background:rgba(54,97,142,.08);font-size:15px;font-weight:700;color:var(--primary);font-feature-settings:'tnum';white-space:nowrap}
.hcard{display:flex;align-items:center;gap:16px;padding:16px;border-radius:16px;background:var(--scl);box-shadow:inset 0 0 0 1px rgba(195,199,207,.3);margin-bottom:10px}
.hcard .x{flex:1}.hcard .d{font-size:13px;font-weight:500}.hcard .s{font-size:12px;color:rgba(67,71,78,.6);margin-top:3px}
.hrow{display:flex;align-items:center;gap:12px;padding:12px 8px 12px 16px;min-height:64px}
.hrow .x{flex:1;min-width:0}.hrow .t{font-size:15px;font-weight:600;font-feature-settings:'tnum';display:flex;align-items:center;gap:8px}.hrow .s{font-size:12px;color:var(--onv);margin-top:2px}
.ctag{font-size:11px;font-weight:600;padding:1px 6px;border-radius:6px;background:var(--sc);color:var(--osc)}
.ptag{font-size:11px;font-weight:600;padding:1px 6px;border-radius:6px;background:#FFDAD6;color:#410002}
.md{font-size:13px;line-height:1.6;color:var(--onv)}
.md h4{font-size:14px;color:var(--on);margin:10px 0 4px}
.md li{margin-left:18px}
.fcard{display:flex;align-items:center;gap:12px;padding:12px;border-radius:14px;background:var(--scc);box-shadow:inset 0 0 0 1px rgba(195,199,207,.15);margin-bottom:8px}
.fcard .bx{width:36px;height:36px;border-radius:10px;background:rgba(54,97,142,.08);display:grid;place-items:center;color:var(--primary);flex:none}
.fcard .x{flex:1;min-width:0}.fcard .n{font-size:13px;font-weight:600;word-break:break-all}.fcard .s{font-size:12px;color:rgba(67,71,78,.7);margin-top:2px}
.fcard .ab{width:40px;height:40px;border-radius:20px;background:rgba(54,97,142,.08);color:var(--primary);display:grid;place-items:center;flex:none}
.bigdlg{position:absolute;z-index:21;left:16px;right:16px;top:60px;bottom:40px;background:var(--sch);border-radius:28px;padding:15px;overflow:hidden;display:flex;flex-direction:column}
.hdr{display:flex;align-items:center;gap:12px}
.av36{width:36px;height:36px;border-radius:18px;background:var(--schh);display:grid;place-items:center;color:var(--onv);flex:none}
.hdr .x{flex:1}.hdr .v{font-size:15px;font-weight:700}.hdr .d{font-size:12px;color:var(--onv)}
.lnkbtn{width:40px;height:40px;border-radius:20px;background:rgba(225,226,232,.4);display:grid;place-items:center;flex:none}
.side2{width:320px;flex:none;border-right:1px solid rgba(195,199,207,.4);padding:12px 16px;overflow:hidden}
.ditem{display:flex;align-items:center;gap:14px;padding:14px;border-radius:16px;margin-bottom:8px;box-shadow:inset 0 0 0 1.5px transparent}
.ditem.on{background:rgba(209,228,255,.25);box-shadow:inset 0 0 0 1.5px var(--primary)}
.ditem i{width:8px;height:8px;border-radius:4px;background:var(--ov);flex:none}.ditem.on i{background:var(--primary)}
.ditem .x{flex:1}.ditem .v{font-size:15px;font-weight:700}.ditem.on .v{color:var(--primary)}.ditem .d{font-size:12px;color:rgba(67,71,78,.6)}
.split{display:flex;height:100%}
.pane{flex:1;padding:24px;display:flex;flex-direction:column;min-width:0}
.pane .card{flex:1;margin-top:16px;border-radius:20px;background:var(--scl);box-shadow:inset 0 0 0 1px rgba(195,199,207,.3);padding:20px;overflow:hidden}
.plat{display:flex;align-items:center;gap:14px}
.plat .ib3{padding:8px;border-radius:12px;background:rgba(54,97,142,.1);color:var(--primary);display:grid;place-items:center}
.plat .t{font-size:15px;font-weight:700}.plat .s{font-size:12px;color:rgba(0,0,0,.48);margin-top:2px}
.secT{font-size:13px;font-weight:600;color:rgba(25,28,32,.8);margin:20px 0 10px}
.srcs{display:grid;grid-template-columns:1fr 1fr;gap:8px}
.src{height:48px;border-radius:10px;background:var(--scl);box-shadow:inset 0 0 0 1px rgba(195,199,207,.25);display:flex;align-items:center;justify-content:center;gap:4px;font-size:12px;font-weight:600;color:var(--onv)}
.stat4{display:flex;align-items:center;gap:14px;padding:18px;border-radius:16px;background:rgba(54,97,142,.08);box-shadow:inset 0 0 0 1px rgba(54,97,142,.25);margin:12px 12px 0}
.stat4 .t{font-size:16px;font-weight:700}.stat4 .s{font-size:12px;color:var(--onv);margin-top:4px;display:flex;gap:12px;flex-wrap:wrap}
.pk{padding:12px 16px}
.pk .h{display:flex;align-items:center;gap:8px}.pk .h .x{flex:1;font-size:14px;font-weight:600}
.pk .h .x small{font-size:12px;font-weight:400;color:var(--onv)}
.ttag{font-size:11px;font-weight:600;padding:2px 6px;border-radius:6px;background:var(--pc);color:var(--opc)}
.more{display:flex;align-items:center;gap:4px;font-size:13px;color:var(--primary);font-weight:600;margin-top:8px}
.urlbox{padding:12px;border-radius:12px;background:var(--scl);font-size:11px;color:var(--onv);word-break:break-all;margin:4px 0}
'''


def composite(phones, **kw):
    return _composite(phones, css=CSS2, **kw)


def p(html):
    return page('393x852@3', html, css=CSS2)


RX = dict(cloud='ec56', hist='ee17', lic='f10c', code='ebad', warn='eca1', refresh='f064', arrow='ea6e', link='eeb2', user='f264',
          box='f2f5', copyf='ecd2', dl='ec54', android='ea36', win='f2c8', mac='eee8', linkm='eeaf', clip='eb91', info='ee59')
PROJECT = 'https://github.com/示例/pure_live'
LEGAL3 = ('© 2026 PureLive 开源项目。本程序为纯本地客户端应用，直接请求媒体平台官方公开接口，项目本身不存储、不制作、不分发任何音视频资源。本程序登录及云同步功能由第三方基础设施服务商 Firebase 提供。'
          '开发者郑重承诺，本程序本身不收集、不处理且不留存任何用户个人隐私信息。所有运行、配置及同步数据均由用户自行留存与控制，数据所有权及隐私权益完全归属于用户。用户需自行承担使用本测试工具所产生的相关法律责任。')
LEGAL4 = ('© 2026 PureLive 开源项目。本程序是纯本地客户端，直接请求各直播平台公开的接口，项目本身不存储、不制作、不分发任何音视频内容。开发者不收集、不处理、不保存任何用户个人信息；'
          '所有设置和数据都保存在你自己的设备上，由你自己控制。使用本程序产生的法律责任由使用者自行承担。')
CUR = '3.2.10'
NEW = '3.2.11'
RELEASES = [('3.2.11', '2026-09-28', '38.6 MB'), ('3.2.10', '2026-09-12', '38.4 MB'), ('3.2.9', '2026-08-30', '38.1 MB'),
            ('3.2.8', '2026-08-15', '37.9 MB'), ('3.2.7', '2026-07-31', '37.9 MB'), ('3.2.6', '2026-07-18', '37.6 MB'), ('3.2.5', '2026-07-02', '37.5 MB')]
LOG = ('<h4>新功能</h4><ul><li>直播间支持定时关闭</li><li>录制中心显示每段文件的大小</li></ul>'
       '<h4>修复</h4><ul><li>修复部分平台弹幕断开后不重连</li><li>修复横屏时清晰度菜单被遮挡</li></ul>')
FILES = [('pure_live-3.2.11-android-arm64-v8a.apk', '38.6 MB', '1,204'), ('pure_live-3.2.11-android-armeabi-v7a.apk', '35.2 MB', '312'),
         ('pure_live-3.2.11-windows-x64-setup.exe', '52.8 MB', '806')]


# ---------------------------------------------------------------- about
def about_head(v3=True, version=CUR):
    return (f'<div style="padding:12px 0 28px;text-align:center"><div class="logo"><img src="{ICON}"></div>'
            f'<div class="app">纯粹直播</div><span class="vpill3">v{version}</span></div>')


def v3_about():
    rows1 = cd3(t3(rx(RX['cloud'], 22), '在线更新', None, f'<span class="vpill3b">v{CUR}</span>'),
                t3(rx(RX['hist'], 22), '历史记录', '历史版本更新记录'),
                t3(rx(RX['lic'], 22), '开源许可证'))
    rows2 = cd3(t3(rx(RX['code'], 22), '项目主页', PROJECT),
                t3(rx(RX['warn'], 22), '项目声明', LEGAL3, trailing='', icon_color='var(--error)'))
    return '<div class="l3"><div class="w">' + about_head() + g3('关于') + '<div style="height:8px"></div>' + rows1 + '<div style="height:4px"></div>' + g3('项目') + '<div style="height:8px"></div>' + rows2 + '</div></div>'


def v4_about(n=False, newer=True):
    N = (lambda k, t: (k, t)) if n else (lambda k, t: (None, None))
    tag = f'<span class="newtag">新版本 v{NEW}</span>' if newer else ''
    rows1 = ncd(nr(rx(RX['cloud'], 22), '在线更新', '检查新版本并下载安装包', f'{tag}<span class="ch">{mr("chevron_right")}</span>', *N(1, 'chg')),
                nr(rx(RX['hist'], 22), '版本历史', '历史版本更新记录', 'chev', *N(2, 'chg')),
                nr(rx(RX['lic'], 22), '开源许可证', None, 'chev', *N(3, 'keep')))
    rows2 = ncd(nr(rx(RX['code'], 22), '项目主页', PROJECT, mr('open_in_new', 20, 'var(--onv)'), *N(4, 'keep')),
                nr(rx(RX['info'], 22), '项目声明', LEGAL4, '', icon_mute=True))
    return ln(about_head(False) + ns('关于') + rows1 + ns('项目') + rows2)


# ---------------------------------------------------------------- version page
def v3_version():
    def section(title, n_src=19):
        btns = ''.join(f'<span class="src">{rx(RX["linkm"], 14)}下载源 {i + 1}</span>' for i in range(n_src))
        return f'<div class="secT">{title}</div><div class="srcs">{btns}</div>'
    card = ('<div class="cd3" style="padding:16px"><div class="plat"><span class="ib3">' + rx(RX['android'], 24) + '</span><div><div class="t">Android</div>'
            '<div class="s">适用于 Android 移动端系统</div></div></div><div style="height:4px"></div>'
            + section('ARM64 (64位)') + section('ARM32 (通用)') + section('x86_64 (Arch)') + '</div>')
    log = cd3(f'<div class="md" style="padding:4px 16px 12px">{LOG}</div>')
    return '<div class="l3"><div class="w">' + card + g3('更新日志') + '<div style="height:8px"></div>' + log + '</div></div>'


def v4_version(n=False, newer=True, expanded=False):
    N = (lambda k, t: (k, t)) if n else (lambda k, t: (None, None))
    stat = (f'<div class="stat4">{mr("system_update" if newer else "verified", 36, "var(--primary)")}<div><div class="t">'
            + (f'发现新版本: v{NEW}' if newer else '已在使用最新版本') + f'</div><div class="s"><span>当前 v{CUR if newer else NEW}</span><span>最新 v{NEW}</span></div></div></div>')

    def pkg(title, size, mine=False, k=None):
        kd, td = N(k, 'chg') if k else (None, None)
        km, tm = N(k + 1, 'chg') if k else (None, None)
        srcs = ''
        if expanded and mine:
            srcs = ('<div class="srcs" style="margin-top:10px">' + ''.join(f'<span class="src">{mr("link", 14)}下载源 {i + 1}</span>' for i in range(5))
                    + f'<span class="src">{mr("link", 14)}…</span></div>')
        return (f'<div class="pk"><div class="h"><span class="x">{title} <small>· {size}</small>' + (' <span class="ttag">本机</span>' if mine else '') + '</span>'
                f'<span class="tonal" style="height:36px"{dn(kd, td)}>{mr("download", 18)}下载并安装</span></div>'
                f'<div class="more"{dn(km, tm, "tl")}>{mr("expand_less" if expanded and mine else "expand_more", 18)}选择下载源（19 个）</div>{srcs}</div>')
    files = ncd(pkg('ARM64 (64位)', '38.6 MB', True, 5), '<div class="nsep" style="height:1px;background:var(--ov);margin:0 16px;opacity:.6"></div>',
                pkg('ARM32 (通用)', '35.2 MB'), '<div style="height:1px;background:var(--ov);margin:0 16px;opacity:.6"></div>', pkg('x86_64 (Arch)', '39.9 MB'))
    log = ncd(f'<div class="md" style="padding:8px 16px 12px">{LOG}</div>')
    return ln(stat + ns('下载文件 · Android') + files + ns('更新日志') + log)


# ---------------------------------------------------------------- history
def v3_hist_list():
    cards = ''.join(f'<div class="hcard"><span class="vbadge2">v{v}</span><div class="x"><div class="d">{d}</div><div class="s">文件大小: {s}</div></div>'
                    f'{rx(RX["arrow"], 18, "var(--outline)")}</div>' for v, d, s in RELEASES)
    return f'<div style="padding:8px 16px 24px">{cards}</div>'


def detail_body(v4=False, n=False):
    N = (lambda k, t: (k, t)) if n else (lambda k, t: (None, None))
    k1, t1 = N(8, 'keep')
    k2, t2 = N(9, 'keep')
    k3, t3_ = N(10, 'keep')
    hdr = (f'<div class="hdr"><span class="av36">{rx(RX["user"], 18)}</span><div class="x"><div class="v">v{NEW}</div><div class="d">发布于 2026-09-28</div></div>'
           f'<span class="lnkbtn"{dn(k1, t1)}>{rx(RX["link"], 16)}</span></div>')
    files = ''.join(f'<div class="fcard"><span class="bx">{rx(RX["box"], 18)}</span><div class="x"><div class="n">{nm}</div><div class="s">{sz} · 已被下载 {c} 次</div></div>'
                    f'<span class="ab"{dn(k2 if i == 0 else None, t2)}>{rx(RX["copyf"], 16)}</span><span class="ab"{dn(k3 if i == 0 else None, t3_)}>{rx(RX["dl"], 16)}</span></div>'
                    for i, (nm, sz, c) in enumerate(FILES))
    return hdr, f'<div class="md" style="margin-top:8px">{LOG}</div><div style="font-size:14px;font-weight:700;margin:24px 0 10px">下载文件</div>{files}'


def v3_detail_dialog():
    hdr, body = detail_body()
    return (f'<div class="dim"></div><div class="bigdlg">{hdr}{body}<div style="flex:1"></div>'
            '<div style="text-align:right"><span class="tb" style="font-weight:700">关闭</span></div></div>')


def v4_detail_dialog(n=False):
    hdr, body = detail_body(True, n)
    return (f'<div class="dim"></div><div class="bigdlg" style="padding:0">'
            f'<div style="display:flex;align-items:center;padding:8px 4px 0 16px"><div style="flex:1">{hdr}</div>'
            f'<span style="width:48px;height:48px;display:grid;place-items:center;color:var(--onv);flex:none"{dn(11 if n else None, "chg")}>{mi("close", 24)}</span></div>'
            f'<div style="padding:0 15px;overflow:hidden;flex:1">{body}</div></div>')


def v4_hist_list(n=False):
    N = (lambda k, t: (k, t)) if n else (lambda k, t: (None, None))
    rows = ''
    for i, (v, d, s) in enumerate(RELEASES):
        tags = (' <span class="ctag">当前</span>' if v == CUR else '') + (' <span class="ttag">最新</span>' if i == 0 else '')
        k, t = N(7, 'chg') if i == 0 else (None, None)
        rows += (f'<div class="hrow{" sep" if i else ""}" style="{"border-top:1px solid color-mix(in srgb,var(--ov) 60%,transparent)" if i else ""}"{dn(k, t, "tl")}>'
                 f'<div class="x"><div class="t">v{v}{tags}</div><div class="s">发布于 {d}</div></div>{mr("chevron_right", 20, "var(--onv)")}</div>')
    return ln('<div style="height:8px"></div>' + ncd(rows))


def v3_hist_desktop(w=1280, h=800):
    items = ''.join(f'<div class="ditem{" on" if i == 0 else ""}"><i></i><div class="x"><div class="v">v{v}</div><div class="d">{d}</div></div>'
                    f'{rx(RX["arrow"], 16, "var(--primary)" if i == 0 else "var(--outline)")}</div>' for i, (v, d, s) in enumerate(RELEASES))
    hdr, body = detail_body()
    return f'<div class="split"><div class="side2">{items}</div><div class="pane">{hdr}<div class="card">{body}</div></div></div>'


def v4_hist_desktop(n=False):
    N = (lambda k, t: (k, t)) if n else (lambda k, t: (None, None))
    items = ''
    for i, (v, d, s) in enumerate(RELEASES):
        tags = (' <span class="ctag">当前</span>' if v == CUR else '') + (' <span class="ttag">最新</span>' if i == 0 else '')
        items += (f'<div class="ditem{" on" if i == 0 else ""}"><div class="x"><div class="v" style="display:flex;gap:6px;align-items:center">v{v}{tags}</div>'
                  f'<div class="d">发布于 {d}</div></div></div>')
    hdr, body = detail_body(True, n)
    return f'<div class="split"><div class="side2" style="width:300px">{items}</div><div class="pane" style="max-width:760px">{hdr}<div class="card" style="background:var(--scl);box-shadow:none;border-radius:16px">{body}</div></div></div>'


V3HIST = bar('历史版本更新记录', act(rx(RX['refresh'], 20)))


def v4_hist_bar(n=False):
    return bar('版本历史', act(mr('refresh'), 12 if n else None, 'keep'), n_back=None)


def new_version_dialog(v4=False, top=150):
    if not v4:
        return ('<div class="dim"></div><div class="dlg2" style="top:' + str(top) + 'px"><h3>检查更新</h3><div class="c" style="margin-top:12px">'
                f'<span class="tb" style="padding-left:0;font-size:15px;font-weight:500">{mi("open_in_new", 18)}本软件开源免费</span>'
                f'<div class="md" style="color:rgba(0,0,0,.87)">{LOG}</div></div>'
                '<div class="acts"><span>取消</span><span class="fb2">更新</span></div></div>')
    return ('<div class="dim"></div><div class="dlg2" style="top:' + str(top) + 'px"><h3>发现新版本: v' + NEW + '</h3>'
            f'<div style="font-size:12px;color:var(--onv);margin-top:4px">当前 v{CUR} · 发布于 2026-09-28</div>'
            f'<div class="md" style="margin-top:8px">{LOG}</div>'
            '<div class="acts"><span style="margin-right:auto;padding-left:0">项目主页</span><span>以后再说</span><span class="fb2">去更新</span></div></div>')


def dl_confirm(v4=False, top=320):
    if not v4:
        return ('<div class="dim"></div><div class="dlg2" style="top:' + str(top) + 'px"><h3>点击下载</h3><div class="c">是否下载“pure_live-3.2.11-android-arm64-v8a.apk”？</div>'
                '<div class="acts"><span class="big">取消</span><span class="fb2 big">点击下载</span></div></div>')
    return ('<div class="dim"></div><div class="dlg2" style="top:' + str(top) + 'px"><h3>下载安装包</h3><div class="c v4">是否下载“pure_live-3.2.11-android-arm64-v8a.apk”（38.6 MB）？下载完成后会打开安装。</div>'
            '<div class="acts"><span>取消</span><span class="fb2">下载</span></div></div>')


def src_dialog(v4=False, top=230):
    url = 'https://mirror3.example.com/https://github.com/示例/pure_live/releases/download/v3.2.11/pure_live-3.2.11-android-arm64-v8a.apk'
    if not v4:
        return ('<div class="dim"></div><div class="dlg2" style="top:' + str(top) + 'px;padding:20px 12px 16px">'
                f'<div style="display:flex;align-items:center;gap:12px;padding:0 8px 12px"><span style="width:36px;height:36px;border-radius:18px;background:rgba(54,97,142,.1);display:grid;place-items:center;color:var(--primary)">{rx(RX["cloud"], 20)}</span>'
                '<div><div style="font-size:15px;font-weight:700">ARM64 (64位)</div><div style="font-size:11px;color:rgba(0,0,0,.6)">下载源 3</div></div></div>'
                f'<div class="urlbox" style="margin:4px 8px">{url}</div><div style="height:8px"></div>'
                f'<div class="fb" style="display:flex;margin:0 8px">{rx(RX["dl"], 20)}点击下载</div><div style="height:8px"></div>'
                f'<div class="ob" style="display:flex;margin:0 8px">{rx(RX["clip"], 20)}复制链接</div>'
                '<div class="acts" style="padding-right:8px"><span>取消</span></div></div>')
    return ('<div class="dim"></div><div class="dlg2" style="top:' + str(top) + 'px"><h3 style="font-size:18px">ARM64 (64位) · 下载源 3</h3>'
            f'<div style="font-size:13px;font-weight:600;margin-top:12px">pure_live-3.2.11-android-arm64-v8a.apk</div><div class="urlbox" style="margin-top:8px">{url}</div>'
            f'<div style="display:flex;flex-direction:column;gap:8px;margin-top:12px"><span class="fb big">{mr("download", 20)}在应用内下载</span>'
            f'<span class="ob big">{mr("open_in_browser", 20)}在浏览器中下载</span><span class="ob big">{mr("content_copy", 20)}复制链接</span></div>'
            '<div class="acts"><span>取消</span></div></div>')


OUT = {}
# ---- v3
V3ABOUT = bar('')
OUT['v3-about'] = p(phone(v3_about(), V3ABOUT))
OUT['v3-about-wide'] = page('1280x800@1.5', wide(v3_about(), V3ABOUT), 'win', '--w:1280px;--h:800px', css=CSS2)
OUT['v3-about-land'] = page('852x393@2', land(v3_about(), V3ABOUT), 'win', '--w:852px;--h:393px', css=CSS2)
V3VER = bar('版本更新')
OUT['v3-version'] = p(phone(v3_version(), V3VER))
OUT['v3-version-full'] = page('393x2200@2 crop', V3VER + v3_version(), 'long', css=CSS2)
OUT['v3-version-dialogs'] = composite([
    (phone(v3_version(), V3VER, src_dialog(False, 220)), '点任一个“下载源 N”'),
    (phone('<div class="sv">' + mr('cloud_off', 48, 'var(--primary)') + '<h4>更新信息获取失败</h4><p>请检查网络和更新源后重试。</p><div class="acts"><span class="fb">' + rx(RX['refresh'], 18) + '重试</span></div></div>', V3VER), '获取失败'),
    (phone(v3_about(), V3ABOUT, new_version_dialog(False, 170)), '启动时发现新版本（首页弹出）'),
])
OUT['v3-history'] = p(phone(v3_hist_list(), V3HIST))
OUT['v3-history-detail'] = composite([
    (phone(v3_hist_list(), V3HIST, v3_detail_dialog()), '点一个版本：大对话框，“关闭”在内容最下面'),
    (phone(v3_hist_list(), V3HIST, dl_confirm(False)), '点下载：标题和按钮都是“点击下载”'),
])
OUT['v3-history-wide'] = page('1280x800@1.5', wide(v3_hist_desktop(), V3HIST), 'win', '--w:1280px;--h:800px', css=CSS2)
OUT['v3-history-land'] = page('852x393@2', land(v3_hist_desktop(), V3HIST), 'win', '--w:852px;--h:393px', css=CSS2)

# ---- new
OUT['v4-about'] = p(phone(v4_about(n=True), bar('')))
OUT['v4-about-wide'] = page('1280x800@1.5', wide(v4_about(), bar('')), 'win', '--w:1280px;--h:800px', css=CSS2)
OUT['v4-about-land'] = page('852x393@2', land(v4_about(), bar('')), 'win', '--w:852px;--h:393px', css=CSS2)
V4VER = bar('版本更新', act(mr('refresh')))
OUT['v4-version'] = p(phone(v4_version(n=True), bar('版本更新', act(mr('refresh')))))
OUT['v4-version-full'] = page('393x1500@2 crop', V4VER + v4_version(expanded=True), 'long', css=CSS2)
OUT['v4-version-dialogs'] = composite([
    (phone(v4_version(expanded=True), V4VER, src_dialog(True, 200)), '点一个下载源：应用内、浏览器、复制'),
    (phone(v4_version(newer=False), V4VER), '已是最新：状态写清'),
    (phone('<div class="sv">' + mr('cloud_off', 48, 'var(--primary)') + '<h4>更新信息获取失败</h4><p>请检查网络和更新源后重试。</p><div class="acts"><span class="fb">' + mr('refresh', 18) + '重试</span></div></div>', V4VER), '获取失败（照 v3）'),
    (phone(v4_about(), bar(''), new_version_dialog(True, 200)), '启动时发现新版本：写版本号'),
])
OUT['v4-history'] = p(phone(v4_hist_list(n=True), v4_hist_bar(n=True)))
OUT['v4-history-detail'] = composite([
    (phone(v4_hist_list(), v4_hist_bar(), v4_detail_dialog(n=True)), '点一个版本：关闭在右上角，内容自己滚动'),
    (phone(v4_hist_list(), v4_hist_bar(), dl_confirm(True)), '点下载：写清下载什么、之后做什么'),
])
OUT['v4-history-wide'] = page('1280x800@1.5', wide(v4_hist_desktop(), v4_hist_bar()), 'win', '--w:1280px;--h:800px', css=CSS2)
OUT['v4-history-land'] = page('852x393@2', land(v4_hist_desktop(), v4_hist_bar()), 'win', '--w:852px;--h:393px', css=CSS2)

write(HERE, OUT)
