"""U.15b TV shell: home rail, mode picker, exit confirm, update prompt,
agreement page, startup unlock. pure_live_TV restored (v3-*) and the new design (v4-*).

pure_live_TV sources (~/ref/pure_live_TV/lib):
  features/home/home_page.dart          rail :321-431, mode button :48-67, mode dialog :73-136, back :343-348
  features/home/home_provider.dart      destinations, names, icons :119-186; sidebarExpanded :202-212
  features/home/exit_confirm_dialog.dart, features/home/home_update_dialog.dart
  features/agreement/agreement_page.dart
  features/settings/pages/widgets/account_lock.dart   startup unlock :338-639
  core/widgets/tv_icon_button.dart (collapsed rail tile), tv_digital_clock.dart
Shared builders: ../../U.15a/src/tvkit.py.
    python3 docs/ui/compare/U.15b/src/gen.py && python3 tools/ui/mock/render.py docs/ui/compare/U.15b/src/ --annotate"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', 'U.15a', 'src'))
from tvkit import *  # noqa: E402,F401,F403

CSS = '''
.pw{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center}
.dots{display:flex;gap:14px;justify-content:center;align-items:center;height:40px}
.dots i{width:14px;height:14px;border-radius:7px;background:var(--on)}
.dots u{width:2px;height:28px;background:var(--primary);margin-left:2px}
.acc4{width:160px;border-radius:16px;background:var(--scc);padding:20px 12px 16px;display:flex;flex-direction:column;align-items:center;gap:10px}
.acc4 .av{width:72px;height:72px;border-radius:36px;background:center/cover}
.acc4 .nm{font:600 16px 'Noto Sans SC';white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:100%}
.acc4 .lk{font:400 14px 'Noto Sans SC';color:var(--onv);display:flex;align-items:center;gap:4px}
.acc3{width:74px;border-radius:8px;background:#1F1F1F;padding:8px;display:flex;flex-direction:column;align-items:center;border:1px solid transparent}
.acc3 .av{width:38px;height:38px;border-radius:19px;background:center/cover}
.acc3 .nm{font:500 8px 'Noto Sans SC';margin-top:5px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:100%}
.acc3.f{border-color:#00A1FF;box-shadow:0 0 12px .5px rgba(0,161,255,.4)}
.log4{margin-top:14px;border-radius:12px;background:var(--scl);padding:12px 16px;font:400 16px/1.6 'Noto Sans SC';color:var(--on)}
.lg4{font:600 14px 'Noto Sans SC';color:var(--onv);margin-top:16px}
.cb4{display:flex;align-items:center;gap:10px;font:400 16px 'Noto Sans SC';color:var(--onv);height:40px;padding:0 12px 0 8px;border-radius:12px}
.cb4 i{width:20px;height:20px;border-radius:4px;border:2px solid var(--outline)}
.prog4{height:8px;border-radius:4px;background:rgba(160,202,253,.2);margin-top:18px;position:relative}.prog4 i{position:absolute;left:0;top:0;bottom:0;border-radius:4px;background:var(--primary)}
'''


def t3(inner):
    return page(f'<div class="t3">{inner}</div>', CSS, dark=False, bg='#121212')


def t4(inner, syn=True):
    return page(f'<div class="t4">{inner}</div>', CSS, syn=syn)


# ---------------- home ----------------
def home3(expanded=False):
    if expanded:
        return t3(rail3('favorite', expanded=True) + f'<div class="pane" style="left:118px">{fav3(focus="i")}</div>')
    return t3(rail3('favorite', focus='favorite') + f'<div class="pane">{fav3()}</div>')


def home4(rail=False, n=False):
    if rail:
        return t4(rail4('favorite', focus='hot', expanded=True, n=n) + '<div class="dim"></div>'
                  + f'<div class="content">{fav4()}</div>')
    return t4(rail4('favorite') + f'<div class="content">{fav4(focus="i", n=n)}</div>')


# ---------------- mode picker ----------------
def mode3():
    rows = ''
    for i, (lab, ic) in enumerate([('直播', mr('live_tv', 13)), ('视频', mo('movie', 13)), ('音乐', mo('library_music', 13))]):
        f = i == 0
        st = 'background:#1F1F1F;border:1px solid #00A1FF' if f else 'border:1px solid transparent'
        rows += (f'<div class="{"fmk fl" if f else ""}" style="display:flex;align-items:center;gap:6px;padding:6px 8px;border-radius:6px;{st}">'
                 f'<span style="color:#00A1FF">{ic}</span><span style="flex:1;font:500 9px Noto Sans SC">{lab}</span>'
                 + (f'<span style="color:#00A1FF">{mr("check", 13)}</span>' if i == 0 else '') + '</div>')
    d = (f'<div class="scr3"></div><div class="d3" style="width:320px"><div class="h">选择模式</div>{rows}'
         f'<div class="ac">{btn3("取消", kind="sec")}</div></div>')
    return t3(rail3('favorite', mode_focus=False) + f'<div class="pane">{fav3()}</div>' + d)


def mode4(n=True):
    N = (lambda k: k + 20) if n else (lambda k: None)
    items = [('直播', mr('live_tv', 22), True), ('视频', mo('movie', 22), False), ('音乐', mo('library_music', 22), False)]
    rows = ''.join(f'<div class="o4{" cur f4 ns fmk fl" if cur else ""}"{at(N(1) if cur else (N(2) if i == 1 else None), "chg", "l")}>{ic}<span class="x">{lab}</span>'
                   + (mr('check', 22) if cur else '') + '</div>' for i, (lab, ic, cur) in enumerate(items))
    d = dialog4('选择模式', f'<div class="list4">{rows}</div>', btn4('取消', nn=N(3)), sub='切换后，正在播放的音乐会停止', width=440)
    return t4(rail4('favorite') + f'<div class="content">{fav4()}</div>' + d)


# ---------------- exit ----------------
def exit3():
    body = ('<div style="font:400 11px/1.5 Noto Sans SC;text-align:center">感谢使用纯粹直播 TV，期待下次再见。</div>'
            f'<div style="display:flex;justify-content:center;margin-top:12px"><div style="background:#fff;border-radius:8px;padding:6px">{qr(118)}</div></div>'
            f'<div style="display:flex;justify-content:center;align-items:center;gap:4px;margin-top:10px;font:700 11px Noto Sans SC"><span style="color:#00A1FF">{mr("favorite", 12)}</span>捐赠支持</div>'
            '<div style="font:400 10px/1.5 Noto Sans SC;text-align:center;margin-top:6px">项目全程开源免费，无任何付费门槛。若是本应用给您带来便利，欢迎微信扫码请开发者喝瓶牛奶，支持后续更新维护。</div>')
    return t3(rail3('favorite', focus=None) + f'<div class="pane">{fav3()}</div>' + dialog3('确定要退出吗？', body, btn3('取消', kind='sec') + btn3('确定', kind='f fmk')))


def exit4(n=True):
    N = (lambda k: k + 30) if n else (lambda k: None)
    body = ('<div style="display:flex;gap:24px;margin-top:14px;align-items:flex-start">'
            '<div style="flex:1"><div style="font:400 16px/1.6 Noto Sans SC;color:var(--onv)">感谢使用纯粹直播 TV，期待下次再见。</div>'
            f'<div style="display:flex;align-items:center;gap:6px;margin-top:16px;font:600 16px Noto Sans SC"><span style="color:#FF5C7A">{mr("favorite", 20)}</span>捐赠支持</div>'
            '<div style="font:400 14px/1.6 Noto Sans SC;color:var(--onv);margin-top:6px">项目全程开源免费，无任何付费门槛。若是本应用给您带来便利，欢迎微信扫码请开发者喝瓶牛奶，支持后续更新维护。</div></div>'
            f'<div style="background:#fff;border-radius:12px;padding:8px;flex:none">{qr(132)}</div></div>')
    return t4(rail4('favorite') + f'<div class="content">{fav4()}</div>'
              + dialog4('确定要退出吗？', body, btn4('取消', nn=N(1)) + btn4('退出', focused=True, nn=N(2), tag='chg'), width=600))


# ---------------- update ----------------
def update3():
    body = (f'<div style="display:flex;align-items:center;gap:6px"><span style="color:#00A1FF">{mr("system_update_alt", 14)}</span>'
            '<span style="font:600 12px Noto Sans SC">v3.0.6</span><span style="font:300 9px Noto Sans SC">&nbsp;&nbsp;→&nbsp;&nbsp;</span>'
            '<span style="font:600 12px Noto Sans SC;color:#00A1FF">v3.0.7</span></div>'
            '<div style="font:500 9px Noto Sans SC;margin-top:8px">更新内容</div>'
            '<div style="margin-top:4px;border-radius:6px;background:#121212;padding:8px;font:300 9px/1.5 Noto Sans SC;min-height:30px">-Feature:修复斗鱼播放视频卡顿,优化弹幕</div>')
    return t3(rail3('favorite') + f'<div class="pane">{fav3()}</div>' + dialog3('发现新版本', body, btn3('稍后', kind='sec') + btn3('下载', kind='f fmk')))


LOG = ['斗鱼原画不再每 5 分钟断流：到期前在后台换链接并按关键帧无缝接上，没有卡顿。', 'Android armv7 与 x86_64 改用自编 FFmpeg 9 播放库。',
       '下线 Kick（Cloudflare 拦截），现支持 33 个平台 + IPTV。']


def update4(n=True):
    N = (lambda k: k + 40) if n else (lambda k: None)
    log = ''.join(f'<div style="display:flex;gap:8px"><span>·</span><span>{x}</span></div>' for x in LOG)
    body = f'<div class="lg4">更新内容</div><div class="log4">{log}</div>'
    acts = (f'<span class="cb4 l"{at(N(1), "add")}><i></i>不再提醒这个版本</span>'
            + btn4('取消', nn=N(2)) + btn4('下载并安装', kind='pri', focused=True, nn=N(3)))
    d = ('<div class="scr4"></div><div class="d4" style="width:600px"><div class="h">发现新版本 v3.2.11</div>'
         '<div class="hs">当前 v3.2.10 · 本软件开源免费</div>' + body + f'<div class="ac">{acts}</div>'
         f'<div style="margin-top:10px;text-align:right"><span class="b4 sm" style="background:transparent;color:var(--primary)"{at(N(4), "add")}>其他下载方式</span></div></div>')
    return t4(rail4('favorite') + f'<div class="content">{fav4()}</div>' + d)


def update4_download(n=True):
    N = (lambda k: k + 45) if n else (lambda k: None)
    body = ('<div style="display:flex;align-items:center;gap:14px;margin-top:6px">'
            f'<span style="width:44px;height:44px;border-radius:22px;background:var(--pc);color:var(--opc);display:grid;place-items:center">{mr("download", 24)}</span>'
            '<div style="flex:1"><div class="h" style="font-size:20px">正在下载 v3.2.11</div><div class="hs" style="margin:2px 0 0">18.6 MB / 62.4 MB</div></div>'
            '<span class="tnum" style="font:600 18px Geist;color:var(--primary)">30%</span></div>'
            '<div class="prog4"><i style="width:30%"></i></div>'
            '')
    d = ('<div class="scr4"></div><div class="d4" style="width:520px">' + body
         + f'<div class="ac">{btn4("取消", focused=True, nn=N(1))}</div></div>')
    return t4(rail4('favorite') + f'<div class="content">{fav4()}</div>' + d)


# ---------------- agreement ----------------
AGREE = ['1. 本软件为开源软件，仅供个人学习、研究之用，严禁用于任何商业用途。',
         '2. 本软件不提供任何直播内容，所展示内容均来源于互联网。',
         '3. 您应自主决定是否使用本软件，并自行承担由此产生的一切后果与责任。',
         '4. 若本软件所含内容侵犯了您的合法权益，请及时与作者联系，作者将在核实后及时删除相关内容。']


def agree3():
    items = ''.join(f'<div style="font:400 16px/1.25 Noto Sans SC;margin-bottom:8px">{t}</div>' for t in AGREE)
    body = ('<div class="pw" style="padding:24px 48px"><div style="width:600px">'
            '<div style="font:700 20px Noto Sans SC;text-align:center">使用须知</div><div style="height:20px"></div>'
            '<div style="font:700 14px Noto Sans SC">欢迎使用纯粹直播 TV，请在使用前仔细阅读以下内容：</div><div style="height:12px"></div>'
            f'<div style="padding-left:14px;padding-right:4px">{items}</div><div style="height:8px"></div>'
            '<div style="font:700 14px Noto Sans SC">您继续使用本软件，即视为已阅读并同意上述全部内容。</div><div style="height:24px"></div>'
            f'<div style="display:flex;justify-content:center;gap:16px">{btn3("已阅读并同意", size="m", kind="f fmk fb")}{btn3("确定退出吗?", size="m", kind="sec")}</div>'
            '</div></div>')
    return page(f'<div class="t3">{body}</div>', CSS, dark=False, bg='#121212', syn=False)


def agree4(n=True):
    N = (lambda k: k + 50) if n else (lambda k: None)
    items = ''.join(f'<div style="display:flex;gap:10px;margin-top:10px"><span class="tnum" style="color:var(--primary);font-weight:600">{i + 1}</span><span>{t[3:]}</span></div>'
                    for i, t in enumerate(AGREE))
    body = ('<div class="pw" style="padding:28px 48px"><div style="width:720px">'
            '<div style="font:600 28px Noto Sans SC;text-align:center">使用须知</div>'
            '<div style="font:400 16px/1.6 Noto Sans SC;color:var(--onv);text-align:center;margin-top:8px">欢迎使用纯粹直播 TV，请在使用前仔细阅读以下内容：</div>'
            f'<div style="margin-top:14px;border-radius:16px;background:var(--scl);padding:14px 22px 18px;font:400 18px/1.6 Noto Sans SC">{items}</div>'
            '<div style="font:400 16px/1.6 Noto Sans SC;color:var(--onv);text-align:center;margin-top:14px">您继续使用本软件，即视为已阅读并同意上述全部内容。</div>'
            f'<div style="display:flex;justify-content:center;gap:16px;margin-top:22px">{btn4("已阅读并同意", kind="pri", focused=True, nn=N(1))}{btn4("退出", nn=N(2), tag="chg")}</div>'
            '</div></div>')
    return page(f'<div class="t4">{body}</div>', CSS, syn=False)


# ---------------- startup unlock ----------------
ACCS = [('晚风', '65', True), ('小林同学', '338', True), ('UID 3546512', None, False)]


def unlock3(pin=False):
    if not pin:
        cards = ''
        for i, (nm, img, locked) in enumerate(ACCS):
            av = f'background-image:url(.cache/img/{img}.jpg)' if img else 'background:#121212;display:grid;place-items:center;font:600 14px Noto Sans SC'
            inner = '' if img else nm[0]
            cards += (f'<div class="acc3{" f fmk" if i == 0 else ""}"><div class="av" style="{av}">{inner}</div><div class="nm">{nm}</div>'
                      f'<span style="margin-top:3px;color:{"#00A1FF" if locked else "#fff"}">{mr("lock_outline" if locked else "lock_open", 9)}</span></div>')
        mid = f'<div style="display:flex;gap:12px">{cards}</div>'
        title = '选择账号'
    else:
        mid = ('<div style="text-align:center"><div style="font:600 10px Noto Sans SC">小林同学</div>'
               '<div style="height:12px"></div><div style="font:700 14px Noto Sans SC;color:#00A1FF;letter-spacing:4px;height:26px;line-height:26px">****</div>'
               '<div style="height:6px"></div><div style="font:500 10px Noto Sans SC;color:#FF6B6B">密码错误</div></div>')
        title = '输入解锁密码'
    body = (f'<div class="ab" style="left:0;right:0;top:36px;text-align:center;font:700 14px Noto Sans SC">{title}</div>'
            f'<div class="pw" style="top:60px;bottom:28px">{mid}</div>')
    return page(f'<div class="t3">{body}</div>', CSS, dark=False, bg='#121212')


def unlock4(pin=False, n=True):
    N = (lambda k: k + 60) if n else (lambda k: None)
    if not pin:
        cards = ''
        for i, (nm, img, locked) in enumerate(ACCS):
            av = f'background-image:url(.cache/img/{img}.jpg)' if img else 'background:var(--sch);display:grid;place-items:center;font:600 28px Noto Sans SC'
            inner = '' if img else 'U'
            lk = (mr('lock', 16) + '有密码') if locked else (mr('lock_open', 16) + '没有密码')
            cards += (f'<div class="acc4{" f4 fmk" if i == 0 else ""}"{at(N(1) if i == 0 else None, "chg")}><div class="av" style="{av}">{inner}</div>'
                      f'<div class="nm">{nm}</div><div class="lk">{lk}</div></div>')
        mid = f'<div style="display:flex;gap:24px">{cards}</div>'
        title, hint = '选择账号', '左右键选择账号，OK 进入'
    else:
        mid = ('<div style="text-align:center"><div style="display:flex;align-items:center;gap:10px;justify-content:center">'
               '<span style="width:40px;height:40px;border-radius:20px;background:url(.cache/img/338.jpg) center/cover"></span><span style="font:600 18px Noto Sans SC">小林同学</span></div>'
               '<div class="dots" style="margin-top:24px"><i></i><i></i><i></i><i></i><u></u></div>'
               f'<div style="font:400 16px Noto Sans SC;color:var(--error);margin-top:14px;display:flex;align-items:center;gap:6px;justify-content:center">{mr("error_outline", 20)}密码错误，请重新输入</div></div>')
        title, hint = '输入解锁密码', '用方向键 ↑ ↓ ← → 输入密码，按 OK 确认；返回键删一位，删完回到选择账号'
    body = (f'<div class="ab" style="left:0;right:0;top:56px;text-align:center"><div class="ttl4" style="font-size:28px">{title}</div></div>'
            f'<div class="pw" style="top:60px;bottom:60px">{mid}</div>'
            f'<div class="ab" style="left:0;right:0;bottom:40px;text-align:center;font:400 16px Noto Sans SC;color:var(--onv)">{hint}</div>')
    return page(f'<div class="t4">{body}</div>', CSS)


OUT = {
    'v3-home': home3(), 'v3-home-expanded': home3(True),
    'v4-home': home4(n=True), 'v4-home-rail': home4(True, n=True),
    'v3-mode': mode3(), 'v4-mode': mode4(),
    'v3-exit': exit3(), 'v4-exit': exit4(),
    'v3-update': update3(), 'v4-update': update4(), 'v4-update-download': update4_download(),
    'v3-agreement': agree3(), 'v4-agreement': agree4(),
    'v3-unlock': unlock3(), 'v3-unlock-pin': unlock3(True), 'v4-unlock': unlock4(), 'v4-unlock-pin': unlock4(True),
}
write(OUT, HERE)
