"""U.1d popups: catalogue boards (v3 restored / new) for the small menu, the
dialog, the panel and the toast, and the screens they open on. Writes the
HTML next to this file; then
    python3 tools/ui/mock/render.py docs/ui/compare/U.1d/src/ --annotate

Shared pieces come from ../../U.1c/src (parts.py, and the settings page of
U.1c's gen.py).

v3 (tag v3.2.11, ~/ref/v3ref/lib):
  plugins/utils.dart                         showAlertDialog / showMessageDialog / showEditTextDialog /
                                             showOptionDialog / showRightDialog (:110-226, :395-652)
  common/style/theme.dart                    dialogTheme, bottomSheetTheme (:171-183)
  common/utils/toast_util.dart, common/global/initialized.dart:170-175   SmartDialog toast, 3 s
  flutter_smart_dialog 5.3.0 toast_widget.dart / view_utils.dart        black, radius 20, bottom 50
  common/widgets/menu_button.dart, common_appbar_actions.dart          the two home menus
  modules/live_play/widgets/resolution_selector/resolution_selector.dart   quality menu
  modules/live_play/widgets/danmaku/danmaku_message_actions.dart       bottom sheet, keyword dialog
  modules/settings/pages/video_settings_page.dart                      option / input / reset dialogs
"""
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
U1C = os.path.join(HERE, '..', '..', 'U.1c', 'src')
sys.path.insert(0, U1C)
from parts import (mr, mi, rx, r, dn, IMG, STATUS, GESTURE, page, board, cap, group, box, cell)  # noqa: E402

_spec = importlib.util.spec_from_file_location('u1c_gen', os.path.join(U1C, 'gen.py'))
c1 = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(c1)

CSS = r'''
.scrim2{background:color-mix(in srgb,#000 54%,var(--surface))}
.scr{position:absolute;inset:0;background:rgba(0,0,0,.54);z-index:20}
/* v3 AlertDialog (dialogTheme: surfaceContainerHigh, radius 24, title 20/600, content 13) */
.dg3{background:var(--sch);border-radius:24px;padding:24px;color:var(--on)}
.dg3 .t{font-size:20px;font-weight:600;line-height:1.35}
.dg3 .t.b16{font-size:16px;font-weight:700}
.dg3 .c{font-size:13px;line-height:1.5;margin-top:16px;color:var(--onv)}
.dg3 .ac{display:flex;justify-content:flex-end;gap:8px;margin-top:24px;align-items:center}
.mut3{height:48px;padding:0 12px;display:flex;align-items:center;font-size:14px;color:var(--hint)}
.fb3r{height:48px;padding:0 24px;border-radius:24px;display:flex;align-items:center;background:var(--error);color:var(--onerr);font-size:13px;font-weight:500}
.fb3p{height:48px;padding:0 24px;border-radius:24px;display:flex;align-items:center;background:var(--primary);color:var(--onPrimary);font-size:13px;font-weight:500}
.rd3{display:flex;align-items:center;padding:0 24px 0 12px;height:48px;font-size:13px}
.rd3 i{width:20px;height:20px;border-radius:10px;border:2px solid var(--onv);margin:0 18px 0 2px;flex:none;position:relative}
.rd3 i.on{border-color:var(--primary)}.rd3 i.on::after{content:'';position:absolute;inset:3px;border-radius:50%;background:var(--primary)}
.fd3{border-radius:12px;box-shadow:inset 0 0 0 1px var(--outline);background:var(--scl);padding:0 16px;height:52px;display:flex;align-items:center;font-size:14px}
.fd3.foc{box-shadow:inset 0 0 0 1.5px var(--primary)}
.fd3e{border-radius:14px;background:color-mix(in srgb,var(--schh) 40%,transparent);padding:16px;font:13px/1.5 'Geist Mono',ui-monospace,monospace;height:116px;color:var(--onv)}
/* new dialog */
.dg4{background:var(--sch);border-radius:24px;padding:24px 24px 20px;color:var(--on)}
.dg4 .t{font-size:20px;font-weight:600;line-height:1.35}
.dg4 .c{font-size:14px;line-height:1.55;margin-top:12px;color:var(--onv)}
.dg4 .ac{display:flex;justify-content:flex-end;gap:8px;margin-top:20px;align-items:center}
.dg4 .ac .l{margin-right:auto}
.op4{display:flex;align-items:center;height:48px;padding:0 24px;font-size:15px;position:relative}
.op4>span:first-child{flex:1}.op4.on{color:var(--primary);font-weight:600}
.fd{position:relative;height:48px;border-radius:12px;box-shadow:inset 0 0 0 1px var(--outline);display:flex;align-items:center;padding:0 14px;font-size:14px;background:transparent;margin-top:16px}
.fd.foc{box-shadow:inset 0 0 0 2px var(--primary)}.fd.err{box-shadow:inset 0 0 0 2px var(--error)}
.fd .lbl{position:absolute;left:10px;top:-9px;padding:0 4px;background:var(--sch);font-size:12px;color:var(--onv)}
.fd.foc .lbl{color:var(--primary)}.fd.err .lbl{color:var(--error)}
.fd .sfx{margin-left:auto;color:var(--onv)}
.fd .phd{color:var(--onv)}
.caret{display:inline-block;width:1.5px;height:20px;background:var(--primary);margin-left:1px;vertical-align:middle}
.fh{display:flex;justify-content:space-between;font-size:12px;color:var(--onv);padding:4px 14px 0;line-height:1.4}
.fh.e span:first-child{color:var(--error)}
.cb{display:flex;align-items:center;gap:10px;font-size:14px;color:var(--on)}
.cb i{width:18px;height:18px;border-radius:2px;border:2px solid var(--onv);flex:none}
.cb i.on{background:var(--primary);border-color:var(--primary);position:relative}.cb i.on::after{content:'';position:absolute;left:4px;top:0;width:5px;height:10px;border:solid var(--onPrimary);border-width:0 2px 2px 0;transform:rotate(45deg)}
/* menus */
.m3{background:var(--scc);border-radius:8px;padding:8px 0;box-shadow:0 2px 6px rgba(0,0,0,.18),0 1px 2px rgba(0,0,0,.12);display:inline-block;min-width:112px;color:var(--on)}
.m3 .it{position:relative;height:48px;display:flex;align-items:center;gap:12px;padding:0 12px;white-space:nowrap}
.mn4{background:var(--schh);border-radius:8px;padding:8px 0;box-shadow:0 4px 14px rgba(0,0,0,.2);display:inline-block;min-width:128px;color:var(--on)}
.mn4 .it{position:relative;min-height:48px;display:flex;align-items:center;gap:12px;padding:0 14px 0 16px;font-size:14px;white-space:nowrap}
.mn4 .it>.mr,.mn4 .it>.rx,.mn4 .it>.mi{color:var(--onv)}
.mn4 .it .tx{flex:1}
.mn4 .it.on{color:var(--primary);font-weight:600}.mn4 .it.on>.mr{color:var(--primary)}
.mn4 .it.dg,.mn4 .it.dg>.rx{color:var(--error)}
.mn4 .it .d{display:block;font-size:12px;color:var(--onv);font-weight:400;margin-top:1px}
.mn4 .it.two{padding-top:6px;padding-bottom:6px}
.mn4 .hd{padding:6px 16px 8px;font-size:13px;color:var(--onv);white-space:nowrap}
.mn4 .sp{height:1px;background:var(--ov);margin:6px 0}
.anc{display:inline-flex;align-items:center;gap:2px;height:36px;padding:0 8px 0 12px;border-radius:8px;box-shadow:inset 0 0 0 1px var(--ov);font-size:13px;background:var(--scl)}
/* panels */
.pn4{background:var(--surface);color:var(--on);overflow:hidden;position:relative}
.pn4 .hdl{width:32px;height:4px;border-radius:2px;background:color-mix(in srgb,var(--onv) 40%,transparent);margin:10px auto 0}
.pn4 .ph2{height:52px;display:flex;align-items:center;padding:0 4px 0 20px}
.pn4 .ph2 .t{font-size:17px;font-weight:600;flex:1}
.pn4 .ph2 .lk{font-size:14px;color:var(--primary);display:flex;align-items:center;padding:0 4px}
.pn4 .ph2 .x{position:relative;width:48px;height:48px;border-radius:24px;display:grid;place-items:center;color:var(--onv)}
.mf{position:relative;width:118px;height:236px;border-radius:14px;border:2px solid var(--outline);overflow:hidden;background:var(--surface);flex:none}
.mf.l{width:236px;height:118px}
.mf .vd{position:absolute;background:#000 url(.cache/img/158.jpg) center/cover}
.mf .pp{position:absolute;background:var(--sc);color:var(--osc);font-size:11px;font-weight:600;display:grid;place-items:center;box-shadow:0 -2px 8px rgba(0,0,0,.18)}
.mf .pg2{position:absolute;inset:0;background:repeating-linear-gradient(0deg,var(--surface) 0 14px,var(--scl) 14px 26px)}
.mf .sc2{position:absolute;inset:0;background:rgba(0,0,0,.4)}
.mf .ct{position:absolute;background:var(--sch);border-radius:10px;font-size:10px;display:grid;place-items:center;color:var(--on)}
.bs3{background:var(--scc);border-radius:24px 24px 0 0;color:var(--on)}
.bs3 .hdl{width:32px;height:4px;border-radius:2px;background:color-mix(in srgb,var(--onv) 40%,transparent);margin:0 auto}
.rp3{width:320px;background:var(--cardc);border-radius:4px 0 0 4px;color:var(--on)}
/* toasts */
.tbar{position:relative;height:150px;border-radius:12px;overflow:hidden;border:1px dashed var(--ov);background:var(--surface)}
.nav3{position:absolute;left:0;right:0;bottom:0;height:80px;background:var(--scc);display:flex}
.nav3 div{flex:1;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:4px;font-size:12px;color:var(--onv)}
.nav3 div.on{color:var(--on);font-weight:600}.nav3 div.on span:first-child{background:var(--sc);border-radius:16px;width:64px;height:32px;display:grid;place-items:center}
'''

DLG_W = 361  # phone: screen 393 minus 16 on each side


def scrbox(inner, h=None, pad='24px 16px'):
    hs = f'height:{h}px;' if h else ''
    return f'<div class="x-box scrim2" style="{hs}padding:{pad};display:flex;align-items:center;justify-content:center">{inner}</div>'


def xb(kind, t, ic='', cls='', n=None, tag=None):
    return f'<span class="xb {kind}{" nb" if not ic else ""} {cls}"{dn(n, tag)}>{ic}{t}</span>'


# =====================================================================
# menus
# =====================================================================


def v3_menu():
    c = group('三套菜单样子')
    c += cap('首页左上菜单（MenuButton）', '表面容器色、圆角 8；图标 24 次要色，字 12 号（menu_button.dart:14-84）')
    rows = [('settings_5_line', '设置'), ('information_line', '关于'), ('history_line', '历史记录'), ('cloud_line', '备份与恢复')]
    c += box('<div style="padding:14px 16px"><div class="m3">' + ''.join(f'<div class="it">{r(i, 24, "color:var(--onv)")}<span style="font-size:12px">{t}</span></div>' for i, t in rows) + '</div></div>')
    c += cap('首页右上菜单（CommonAppBarActions）', '圆角 14；图标 20 主色，字 14 号（common_appbar_actions.dart:13-68）')
    rows = [('search_line', '搜索直播'), ('link', '链接访问'), ('layout_grid_line', '多画面')]
    c += box('<div style="padding:14px 16px"><div class="m3" style="border-radius:14px">' + ''.join(f'<div class="it" style="padding:0 14px">{r(i, 20, "color:var(--primary)")}<span style="font-size:14px">{t}</span></div>' for i, t in rows) + '</div></div>')
    c += cap('清晰度菜单', '表面容器最高色、圆角 8；字 11 号，当前项只变主色（resolution_selector.dart:24-80，U.2f 已改）')
    q = ['原画', '蓝光', '超清', '高清', '流畅']
    c += box('<div style="padding:14px 16px"><div class="m3" style="background:var(--schh)">' + ''.join(f'<div class="it" style="font-size:11px;{"color:var(--primary)" if i == 0 else ""}">{t}</div>' for i, t in enumerate(q)) + '</div></div>')
    c += cap('默认菜单（搜索排序、每页条数）', '圆角 4，字 13 号；当前项靠 initialValue（search_page.dart:261-280、desktop_components.dart:238-262）')
    s = ['综合：直播→观众→粉丝', '平台优先：按主页顺序', '观众优先', '粉丝优先']
    c += box('<div style="padding:14px 16px"><div class="m3" style="border-radius:4px">' + ''.join(f'<div class="it" style="font-size:13px;font-weight:500;padding:0 12px">{t}</div>' for t in s) + '</div></div>')
    c += group('状态')
    c += cap('悬停 / 键盘焦点 / 按下', 'Flutter 默认叠层；焦点没有框；没有禁用项、没有说明行、没有分组线')
    c += box('<div style="padding:14px 16px"><div class="m3">' + ''.join(f'<div class="it {k}" style="font-size:12px">{r("settings_5_line", 24, "color:var(--onv)")}{t}</div>' for k, t in (('st-h', '悬停'), ('ov3', '键盘焦点'), ('st-p', '按下'))) + '</div></div>')
    c += cap('位置', '按钮下方（PopupMenuPosition.under），左上菜单右移 12、右上菜单下移 10、清晰度下移 5；放不下时由 Flutter 往上挪')
    return board('v3 · 小菜单', 'PopupMenuButton，各处自己设样子', c, extra_css=CSS)


def mn4(items, w=None, cls=''):
    out = f'<div class="mn4 {cls}" style="{f"width:{w}px" if w else ""}">'
    for it in items:
        kind = it[0]
        if kind == 'sep':
            out += '<div class="sp"></div>'
        elif kind == 'hd':
            out += f'<div class="hd">{it[1]}</div>'
        else:
            _, ic, t, st, *rest = it + ('',) * (4 - len(it)) if len(it) < 4 else it
            desc = rest[0] if rest else ''
            on = 'on' in st
            two = ' two' if desc else ''
            tx = f'<span class="tx">{t}' + (f'<span class="d">{desc}</span>' if desc else '') + '</span>'
            out += f'<div class="it {st}{two}">{ic}{tx}{mr("check", 20) if on else ""}</div>'
    return out + '</div>'


def v4_menu():
    c = group('一个小菜单（U.2f 已确认的样子）')
    c += cap('默认', '表面容器最高色、圆角 8、浮层阴影；每行 48，字 14，图标 24 次要色；宽度跟内容（128–280）')
    c += box('<div style="padding:14px 16px">' + mn4([('it', r('settings_5_line'), '设置', ''), ('it', r('information_line'), '关于', ''), ('it', r('cloud_line'), '备份与恢复', '')]) + '</div>')
    c += cap('当前项', '主色、600、右边勾（清晰度、线路、画面比例、排序、每页条数）')
    c += box('<div style="padding:14px 16px">' + mn4([('it', '', '原画', 'on'), ('it', '', '蓝光', ''), ('it', '', '超清', ''), ('it', '', '高清', ''), ('it', '', '流畅', '')], w=150) + '</div>')
    c += cap('带说明、标题行、分组线、危险项', '说明 12 号次要色（U.2b 画面模式）；第一行写是哪个东西、不能点（U.4d 分区卡片）；危险动作错误色')
    c += box('<div style="padding:14px 16px;display:flex;gap:12px;align-items:flex-start;flex-wrap:wrap">'
             + mn4([('it', mr('blur_on'), '沉浸背景', 'on', '两边用模糊的封面填满'), ('it', mr('crop_free'), '完整画面', '', '两边黑边'), ('sep',), ('it', mr('crop'), '铺满裁剪', '', '裁掉上下')], w=220)
             + mn4([('hd', '守望先锋 · 哔哩哔哩 · 网游'), ('it', rx('ee0b'), '关注分区', ''), ('sep',), ('it', r('delete_bin_line'), '取消关注', 'dg')], w=200) + '</div>')
    c += group('状态')
    c += cap('悬停 / 键盘焦点 / 按下 / 禁用', '整行叠层 8%、12%；键盘焦点主色框（只在用键盘时）；用不了的项变灰、不能点')
    c += box('<div style="padding:14px 16px">' + mn4([('it', r('settings_5_line'), '悬停', 'st-h'), ('it', r('settings_5_line'), '键盘焦点', 'st-fi'),
                                                       ('it', r('settings_5_line'), '按下', 'st-p'), ('it', r('layout_grid_line'), '禁用', 'dis')]) + '</div>')
    c += group('位置')
    c += cap('贴着按钮，放得下的一边', '默认在按钮下方、和按钮左边（或右边）对齐，间隔 4；下面放不下就放在上方；画面不变暗。选完就关；点外面、返回键、Esc 关闭；上下键移动、回车选')
    c += box('<div style="display:grid;grid-template-columns:1fr 1fr;gap:10px;padding:14px">'
             + '<div><span class="anc">原画' + mr('expand_less', 18) + '</span><div style="margin-top:4px">' + mn4([('it', '', '原画', 'on'), ('it', '', '蓝光', ''), ('it', '', '超清', '')], w=130) + '</div><div class="x-lb" style="text-align:left">下方</div></div>'
             + '<div style="display:flex;flex-direction:column;justify-content:flex-end"><div style="margin-bottom:4px">' + mn4([('it', '', '线路1', 'on'), ('it', '', '线路2', '')], w=130) + '</div><span class="anc" style="align-self:flex-start">线路1' + mr('expand_less', 18) + '</span><div class="x-lb" style="text-align:left">放不下时在上方</div></div></div>')
    return board('新设计 · 小菜单', '一个组件，用在清晰度、线路、画面比例、右上角菜单、首页菜单、排序、分区卡片长按', c, extra_css=CSS)


# =====================================================================
# dialogs
# =====================================================================


def v3_dialog():
    c = group('通用对话框（plugins/utils.dart）')
    c += cap('确认 showAlertDialog', '标题 20/600，正文 13 号，“取消”“确认”两个文字按钮 13 号（:110-131、:395-445）；宽度跟内容，最窄 280。用在退出登录、网页搜索认出房间号')
    c += scrbox(f'<div class="dg3" style="width:300px"><div class="t">退出登录</div><div class="c">确定要退出哔哩哔哩账号吗？</div>'
                f'<div class="ac"><span class="tb3 ni" style="height:48px">取消</span><span class="tb3 ni" style="height:48px">确认</span></div></div>')
    c += cap('消息 showMessageDialog', '只有“确认”；代码里没有用到（:137-147）')
    c += cap('输入 showEditTextDialog', '固定 4–5 行的等宽字体大框；屏幕窄于 420（所有手机）按钮竖排占满；只有 GitHub 登录用到，v4 已去掉（:212-222、:507-652）')
    c += scrbox('<div class="dg3" style="width:345px;padding:0;overflow:hidden"><div style="padding:24px 24px 20px"><div class="t" style="font-size:18px">GitHub 登录</div>'
                '<div class="fd3e" style="margin-top:16px">请粘贴授权链接</div></div><div style="height:1px;background:var(--ov)"></div>'
                '<div style="padding:10px 16px 12px;display:flex;flex-direction:column;gap:8px"><span class="tb3" style="justify-content:center;border-radius:10px">取消</span>'
                '<span class="fb3" style="justify-content:center;border-radius:10px">确认</span></div></div>')
    c += cap('选项 showOptionDialog', '单选圈 + 文字，点一项就选中关闭，没有按钮（:224-226、:447-505）；用在“请选择登陆方式”')
    c += group('各页自己写的（同类对话框，40 个文件）')
    c += cap('输入：屏蔽弹幕关键词', '标题 20/600，输入框带字数，“取消”文字按钮 + “确认”实心按钮（danmaku_message_actions.dart:107-124）')
    c += scrbox('<div class="dg3" style="width:300px"><div class="t">屏蔽弹幕关键词</div><div class="fd3 foc" style="margin-top:16px">前排支持！</div>'
                '<div style="text-align:right;font-size:12px;color:var(--onv);padding:4px 12px 0">5/40</div>'
                '<div class="ac"><span class="tb3 ni">取消</span><span class="fb3">确认</span></div></div>')
    c += cap('选项：首选清晰度', '标题 16 号粗体；单选圈，13 号；只有“取消”（灰色 14 号）（video_settings_page.dart:444-492）')
    opts = ['原画', '蓝光8M', '蓝光4M', '超清', '流畅']
    c += scrbox('<div class="dg3" style="width:280px;padding:24px 0 24px"><div class="t b16" style="padding:0 24px">首选清晰度</div><div style="margin-top:12px">'
                + ''.join(f'<div class="rd3"><i class="{"on" if i == 0 else ""}"></i>{t}</div>' for i, t in enumerate(opts))
                + '</div><div class="ac" style="padding:0 24px;margin-top:12px"><span class="mut3">取消</span></div></div>')
    c += cap('危险确认：重置小窗位置和大小', '标题 16 号粗体，正文 14 号，红色实心“重置”（video_settings_page.dart:526-556）；“清空历史”“删除”也是红色，但取消关注是“确认”文字按钮（favorite_floating_button.dart）')
    c += scrbox('<div class="dg3" style="width:345px"><div class="t b16">重置小窗位置和大小</div><div class="c" style="font-size:14px;color:var(--on)">确定要清除已保存的小窗位置和大小吗？</div>'
                '<div class="ac"><span class="mut3">取消</span><span class="fb3r">重置</span></div></div>')
    c += group('按钮的状态')
    c += cap('文字按钮 / 实心按钮', '悬停、焦点、按下是叠层（焦点没有框）；保存中实心按钮换成转圈、两个按钮都不能点，返回键也不关（video_settings_page.dart:649-711）')
    c += ('<div class="x-row" style="gap:8px">' + cell('<span class="tb3 ni">确认</span>', '默认') + cell('<span class="tb3 ni st-h">确认</span>', '悬停')
          + cell('<span class="tb3 ni ov3">确认</span>', '焦点') + cell('<span class="tb3 ni st-p">确认</span>', '按下')
          + cell('<span class="fb3"><span class="spin" style="width:18px;height:18px;color:var(--onPrimary)"></span></span>', '保存中') + '</div>')
    return board('v3 · 对话框', 'dialogTheme：表面容器高色、圆角 24、标题 20/600、正文 13（theme.dart:177-183）；按钮各写各的', c, extra_css=CSS, h=5000)


def v4_dialog():
    c = group('一个对话框，四种内容')
    c += cap('确认', '标题 20/600，正文 14，“取消”文字按钮 + 写明动作的实心按钮；宽 = 屏宽减 32，最宽 400（长内容 560）')
    c += scrbox(f'<div class="dg4" style="width:{DLG_W}px"><div class="t">退出登录</div><div class="c">确定要退出哔哩哔哩账号吗？</div>'
                f'<div class="ac">{xb("txt", "取消")}{xb("fill", "退出登录")}</div></div>')
    c += cap('危险确认', '删除、清空、重置、取消关注：红色实心按钮（U.4a c12、U.5c）')
    c += scrbox(f'<div class="dg4" style="width:{DLG_W}px"><div class="t">重置小窗位置和大小</div><div class="c">确定要清除已保存的小窗位置和大小吗？</div>'
                f'<div class="ac">{xb("txt", "取消")}{xb("err", "重置")}</div></div>')
    c += cap('消息', '一个“知道了”；有去处时多一个按钮（例：U.2j 无法打开画中画的“去设置”，正文是示意）')
    c += scrbox(f'<div class="dg4" style="width:{DLG_W}px"><div class="t">无法打开画中画</div><div class="c">系统设置里关掉了纯粹直播的画中画权限。</div>'
                f'<div class="ac">{xb("txt", "知道了")}{xb("fill", "去设置")}</div></div>')
    c += cap('输入', '默认单行；正文字体；框下是说明或错误、字数；主要按钮写明动作；键盘弹出时整个对话框留在键盘上方')
    c += scrbox(f'<div class="dg4" style="width:{DLG_W}px"><div class="t">屏蔽弹幕关键词</div>'
                '<div class="fd foc"><span class="lbl">关键词</span>前排支持！<i class="caret"></i></div><div class="fh"><span>含这个词的弹幕都不再显示</span><span>5/40</span></div>'
                f'<div class="ac">{xb("txt", "取消")}{xb("fill", "屏蔽")}</div></div>')
    c += cap('输入出错', '错误写在框下（错误色），不弹提示条；保存中主要按钮转圈，两个按钮和返回键都不可用（照 v3，见下面“进行中”）')
    c += scrbox(f'<div class="dg4" style="width:{DLG_W}px"><div class="t">屏蔽弹幕关键词</div>'
                '<div class="fd err"><span class="lbl">关键词</span><span class="phd">请输入关键词</span></div><div class="fh e"><span>请输入关键词</span><span>0/40</span></div>'
                f'<div class="ac">{xb("txt", "取消")}{xb("fill", "屏蔽")}</div></div>')
    c += cap('选项', '点一项就选中关闭；当前项主色加勾（计划书第 7 节）；只有“取消”')
    opts = ['原画', '蓝光8M', '蓝光4M', '超清', '流畅']
    c += scrbox(f'<div class="dg4" style="width:{DLG_W}px;padding:24px 0 16px"><div class="t" style="padding:0 24px">首选清晰度</div><div style="margin-top:12px">'
                + ''.join(f'<div class="op4{" on" if i == 0 else ""}"><span>{t}</span>{mr("check", 20) if i == 0 else ""}</div>' for i, t in enumerate(opts))
                + f'</div><div class="ac" style="padding:0 16px;margin-top:8px">{xb("txt", "取消")}</div></div>')
    c += cap('带勾选', '“不再提醒这个版本”“不再询问”放在按钮行左边（U.3d c4）；窄时放在正文下面')
    c += scrbox(f'<div class="dg4" style="width:{DLG_W}px"><div class="t">发现新版本 v3.2.12</div><div class="c">当前 v3.2.11</div>'
                '<div class="cb" style="margin-top:14px"><i class="on"></i>不再提醒这个版本</div>'
                f'<div class="ac">{xb("txt", "取消")}{xb("fill", "下载并安装")}</div></div>')
    c += group('按钮的状态（对话框里所有按钮一样）')
    c += cap('文字按钮', '高 40，点击区域 48；键盘焦点主色框，只在用键盘时显示；回车 = 主要按钮，Esc = 取消')
    c += c1.btn_states4('txt', '', '取消')
    c += cap('实心按钮', '')
    c += c1.btn_states4('fill', '', '保存')
    c += cap('危险按钮', '')
    c += c1.btn_states4('err', '', '重置')
    c += cap('按钮排法', '一行靠右，取消在左；只有字体放大 1.5 倍以上才竖排（U.3d c10）')
    return board('新设计 · 对话框', '表面容器高色、圆角 24、标题 20/600、正文和按钮 14；居中；点外面、返回键、Esc 等于取消', c, extra_css=CSS, h=5600)


# =====================================================================
# panels
# =====================================================================


def mframe(kind):
    """Tiny schematic of where a panel sits."""
    if kind == 'v3-sheet':
        return ('<div class="mf"><div class="pg2"></div><div class="sc2"></div><div class="pp" style="left:0;right:0;bottom:0;height:110px;border-radius:12px 12px 0 0;background:var(--scc);color:var(--on)">底部面板</div></div>')
    if kind == 'v3-center':
        return ('<div class="mf"><div class="vd" style="left:0;right:0;top:22px;height:66px"></div><div class="pg2" style="top:88px"></div><div class="sc2"></div>'
                '<div class="ct" style="left:8px;right:8px;top:60px;height:130px">居中对话框</div></div>')
    if kind == 'v3-fsright':
        return ('<div class="mf l"><div class="vd" style="inset:0"></div><div class="sc2"></div><div class="pp" style="right:0;top:0;bottom:0;width:118px;border-radius:8px 0 0 8px;background:var(--scc);color:var(--on)">右半边</div></div>')
    if kind == 'below':
        return ('<div class="mf"><div class="vd" style="left:0;right:0;top:22px;height:66px"></div><div class="pp" style="left:0;right:0;top:88px;bottom:0;border-radius:10px 10px 0 0">画面下方</div></div>')
    if kind == 'right':
        return ('<div class="mf l"><div class="vd" style="inset:0"></div><div class="pp" style="right:0;top:0;bottom:0;width:86px;border-radius:10px 0 0 10px">右侧 360</div></div>')
    if kind == 'bottom':
        return ('<div class="mf"><div class="pg2"></div><div class="sc2"></div><div class="pp" style="left:0;right:0;bottom:0;height:150px;border-radius:10px 10px 0 0">底部</div></div>')
    if kind == 'wright':
        return ('<div class="mf l"><div class="pg2"></div><div class="sc2"></div><div class="pp" style="right:0;top:0;bottom:0;width:72px;border-radius:10px 0 0 10px">右侧</div></div>')


def v3_panel():
    c = group('位置：同类功能三种弹法')
    c += cap('', '竖屏录制、弹幕设置是居中对话框；全屏的弹幕设置、清晰度是右半边；长按弹幕、多画面是底部面板（U.2f 已改成一个面板）')
    c += ('<div class="x-row" style="gap:12px;align-items:flex-end">' + cell(mframe('v3-sheet'), '底部面板') + cell(mframe('v3-center'), '居中对话框')
          + '</div><div style="margin-top:10px">' + cell(mframe('v3-fsright'), '全屏：右半边') + '</div>')
    c += group('底部面板（bottomSheetTheme，theme.dart:171-176）')
    c += cap('长按弹幕', '表面容器色、顶角 24、把手；没有标题和关闭按钮；行是 ListTile（danmaku_message_actions.dart:10-56）')
    lt = c1.lt3
    c += box('<div class="bs3" style="margin-top:20px;padding-top:22px"><div class="hdl"></div><div style="height:18px"></div>'
             + lt('', '星河长明: 前排支持！') + lt(mr('copy_all'), '复制') + lt(mr('person_off'), '屏蔽该用户的弹幕', '星河长明') + lt(mr('filter_alt'), '屏蔽弹幕关键词', '前排支持！')
             + '<div style="height:16px"></div></div>', style='background:color-mix(in srgb,#000 54%,var(--surface));border-style:solid')
    c += group('右侧面板 showRightDialog（utils.dart:149-205）')
    c += cap('', '宽 320、cardColor、左边圆角 4，返回箭头加标题；代码里没有用到')
    c += box('<div style="display:flex;justify-content:flex-end;height:200px;background:color-mix(in srgb,#000 30%,var(--surface))"><div class="rp3">'
             '<div style="display:flex;align-items:center;height:48px">' + f'<div class="ib">{mi("arrow_back")}</div>' + '<span style="font-size:15px;font-weight:500">标题</span></div>'
             '<div style="height:1px;background:rgba(127,127,127,.1)"></div></div></div>')
    c += group('状态')
    c += cap('', '没有关闭按钮，靠下拉、点外面、返回键；内容加载、空各自画')
    return board('v3 · 面板', 'showModalBottomSheet、showRightDialog、直播间里各自写的右侧面板', c, extra_css=CSS)


def pnl(title, link='', body='', handle=False, x_cls='', radius='16px 16px 0 0', shadow='0 -4px 16px rgba(0,0,0,.12)', w=None, divider=False):
    lk = f'<span class="lk">{link}{mr("chevron_right", 18)}</span>' if link else ''
    return (f'<div class="pn4" style="border-radius:{radius};box-shadow:{shadow};{f"width:{w}px;" if w else ""}">' + ('<div class="hdl"></div>' if handle else '')
            + f'<div class="ph2"><span class="t">{title}</span>{lk}<span class="x {x_cls}">{mr("close")}</span></div>'
            + ('<div style="height:1px;background:var(--ov)"></div>' if divider else '') + body + '</div>')


def v4_panel():
    lr = c1.lr
    sw = c1.sw
    c = group('一个面板，三个位置（U.2f 已确认）')
    c += cap('', '有画面：竖屏在画面下方，横屏和宽屏在右侧（宽 360），画面照常播、不变暗；没有画面的页面：竖屏从底部升起（带把手），宽屏在右侧')
    c += ('<div class="x-row" style="gap:12px;align-items:flex-end">' + cell(mframe('below'), '有画面 · 竖屏') + cell(mframe('bottom'), '没有画面 · 竖屏')
          + '</div><div class="x-row" style="gap:12px;margin-top:10px">' + cell(mframe('right'), '有画面 · 横屏、宽屏') + '</div>'
          + '<div class="x-row" style="gap:12px;margin-top:10px">' + cell(mframe('wright'), '没有画面 · 宽屏') + '</div>')
    c += group('样子')
    c += cap('标题栏', '标题 17/600；右边可以有一个文字链接（例“录制中心 ›”）和 ✕（48）；顶角 16；表面色；浮层阴影')
    body = ('<div style="padding:0 12px 12px"><div class="ncd">' + lr('', '同时录弹幕', '在录像旁保存同名 .xml 弹幕文件', sw()) + lr('', '开播自动录', '主播开播时自动开始录，下播后自动停止', sw(True)) + '</div></div>')
    c += box('<div style="padding:16px 0 0;background:var(--scl)">' + pnl('录制', '录制中心', body) + '</div>')
    c += cap('没有画面的页面（底部）', '多一个把手，能往下拖关（U.4b 全部平台）')
    c += box('<div style="padding:16px 0 0;background:color-mix(in srgb,#000 40%,var(--surface))">' + pnl('全部平台', '平台显示', '<div style="height:70px"></div>', handle=True) + '</div>')
    c += cap('内容滚动后', '标题栏下面出现一条分隔线；标题栏不动')
    c += box('<div style="padding:16px 0 0;background:var(--scl)">' + pnl('弹幕设置', '', '<div style="padding:8px 12px 12px"><div class="ncd">' + lr('', '点击画面弹幕查看操作', None, sw(True)) + '</div></div>', divider=True) + '</div>')
    c += cap('加载中 / 空', '用 U.1c 的骨架和区块状态')
    c += box('<div style="padding:16px 0 0;background:var(--scl)">' + pnl('节目单', '', '<div style="padding:0 12px 12px">' + c1.skel_row() + c1.skel_row() + '</div>') + '</div>')
    c += group('关闭')
    c += cap('✕ 的状态', '悬停、键盘焦点、按下；也能用返回键、Esc；竖屏在画面下方时往下拖标题栏关（U.2f）；同一时间只开一个面板')
    c += ('<div class="x-row" style="gap:18px">' + ''.join(cell(f'<span class="pn4" style="display:inline-block;border-radius:24px"><span class="ph2" style="padding:0;height:48px;display:block"><span class="x {k}">{mr("close")}</span></span></span>', t)
                                                      for k, t in (('', '默认'), ('st-h', '悬停'), ('st-fi', '键盘焦点'), ('st-p', '按下'))) + '</div>')
    return board('新设计 · 面板', '画面下方 / 右侧 / 底部同一个组件，只换位置', c, extra_css=CSS)


# =====================================================================
# toasts and tooltips
# =====================================================================


def v3_toast():
    c = group('提示条（两套）')
    c += cap('ToastUtil（SmartDialog，225 处）', '黑底胶囊、圆角 20、14 号白字，离屏幕底 50，3 秒（initialized.dart:171-174、toast_widget.dart:13-21）；深色主题是灰底 #606060')
    c += ('<div class="tbar"><div class="nav3"><div class="on"><span>' + rx('ee0a') + '</span><span>关注</span></div><div><span>' + rx('ed33') + '</span><span>热门</span></div>'
          '<div><span>' + rx('ea42') + '</span><span>分区</span></div><div><span>' + rx('ec54') + '</span><span>录制中心</span></div></div>'
          '<div style="position:absolute;left:0;right:0;bottom:50px;text-align:center;z-index:2"><span class="ts3">已复制到剪贴板</span></div></div>')
    c += '<div class="x-hs" style="margin-top:6px">离底 50：竖屏压在底部导航栏上</div>'
    c += cap('SnackBar（11 个文件 21 处）', '主题默认：贴底整条、反色底、13 号（web_dav_help.dart:295、version_page.dart:470、download_apk_dialog.dart:486 等）')
    c += '<div class="tbar" style="height:80px"><div style="position:absolute;left:0;right:0;bottom:0"><div class="sb3">已复制到剪贴板</div></div></div>'
    c += cap('SnackBar 浮起', 'Cookie 编辑器：浮起、圆角 4（account_cookie_editor.dart:108-109）')
    c += '<div class="tbar" style="height:80px"><div style="position:absolute;left:15px;right:15px;bottom:10px"><div class="sb3" style="border-radius:4px">Cookie 已保存在本机</div></div></div>'
    c += cap('带操作', 'ToastUtil 不能带按钮：删除没有撤销（U.2e K5）')
    c += cap('同一句 3 秒内不重复', 'toast_util.dart:13-18')
    c += group('按钮名称提示（Tooltip，Flutter 默认）')
    c += cap('电脑 / 手机', '电脑 12 号、深灰 90%、圆角 4；手机长按出现，14 号；悬停或长按 0.5 秒左右出现')
    c += '<div class="x-row" style="gap:16px">' + cell('<span class="tp3">小窗播放</span>', '电脑') + cell('<span class="tp3 m">小窗播放</span>', '手机') + '</div>'
    return board('v3 · 提示条和按钮名称提示', 'ToastUtil、SnackBar、Tooltip', c, extra_css=CSS)


def ts4(text, act='', close=False, cls='', st=''):
    return (f'<div class="ts4 {cls}" style="{st}"><span class="x">{text}</span>' + (f'<span class="ac">{act}</span>' if act else '')
            + (f'<span class="cl">{mr("close", 20)}</span>' if close else '') + '</div>')


def v4_toast():
    c = group('一种提示条')
    c += cap('一句话', '反色底（浅色主题深底、深色主题浅底）、圆角 8、14 号；最多两行；3 秒（照 v3）；同一句 3 秒内不重复（照 v3）')
    c += ('<div class="tbar"><div class="nav3"><div class="on"><span>' + rx('ee0a') + '</span><span>关注</span></div><div><span>' + rx('ed33') + '</span><span>热门</span></div>'
          '<div><span>' + rx('ea42') + '</span><span>分区</span></div><div><span>' + rx('ec54') + '</span><span>录制中心</span></div></div>'
          '<div style="position:absolute;left:12px;right:12px;bottom:96px;z-index:2">' + ts4('已复制到剪贴板') + '</div></div>')
    c += '<div class="x-hs" style="margin-top:6px">在底部导航栏上方 16；没有导航栏时离底 16 加安全区</div>'
    c += cap('带一个操作', '撤销、重试、查看：操作是反色主色；带操作时 4 秒（U.2e c15）')
    c += ts4('已移除“前排”', '撤销')
    c += cap('要用户选的', '带 ✕，不自动消失，直到点了操作或 ✕（U.5b 认出直播间）')
    c += ts4('这是一个直播间 · 哔哩哔哩 21452505', '进入', True)
    c += cap('两行', '超过两行的内容不用提示条，改用对话框或页内横幅')
    c += ts4('“前排支持！”已加入屏蔽关键词，列表里含这个词的弹幕已去掉', '撤销')
    c += cap('操作按钮的状态', '悬停、键盘焦点、按下（叠层同其他按钮）')
    c += ('<div class="x-row" style="gap:10px">' + ''.join(cell(f'<div class="ts4" style="padding:4px"><span class="ac {k}">撤销</span></div>', t)
                                                      for k, t in (('', '默认'), ('st-h', '悬停'), ('st-f', '键盘焦点'), ('st-p', '按下'))) + '</div>')
    c += cap('位置', '竖屏底部；全屏时在画面中下部、底栏上方；宽屏底部居中，最宽 560；同一时间一条，新的替换旧的')
    c += group('按钮名称提示')
    c += cap('电脑 / 手机', '照 v3（Flutter 默认）：电脑悬停、手机长按；文字和按钮用法表一致')
    c += '<div class="x-row" style="gap:16px">' + cell('<span class="tp3">小窗播放</span>', '电脑') + cell('<span class="tp3 m">小窗播放</span>', '手机') + '</div>'
    return board('新设计 · 提示条', '一种提示条，可带一个操作和关闭；按钮名称提示照 v3', c, extra_css=CSS)


OUT = {
    'v3-menu': v3_menu(), 'v4-menu': v4_menu(),
    'v3-dialog': v3_dialog(), 'v4-dialog': v4_dialog(),
    'v3-panel': v3_panel(), 'v4-panel': v4_panel(),
    'v3-toast': v3_toast(), 'v4-toast': v4_toast(),
}

# =====================================================================
# screens
# =====================================================================
OPTS = ['原画', '蓝光8M', '蓝光4M', '超清', '流畅']


def opt3(top):
    return (f'<div class="scr"></div><div class="dg3" style="position:absolute;z-index:21;left:56px;width:280px;top:{top}px;padding:24px 0">'
            '<div class="t b16" style="padding:0 24px">首选清晰度</div><div style="margin-top:12px">'
            + ''.join(f'<div class="rd3"><i class="{"on" if i == 0 else ""}"></i>{t}</div>' for i, t in enumerate(OPTS))
            + '</div><div class="ac" style="padding:0 24px;margin-top:12px"><span class="mut3">取消</span></div></div>')


def opt4(left, top, w, n=False):
    return (f'<div class="scr"></div><div class="dg4" style="position:absolute;z-index:21;left:{left}px;width:{w}px;top:{top}px;padding:24px 0 16px">'
            '<div class="t" style="padding:0 24px">首选清晰度</div><div style="margin-top:12px">'
            + ''.join(f'<div class="op4{" on" if i == 0 else ""}"{dn(1 if (n and i == 0) else (2 if (n and i == 1) else None), "chg")}><span>{t}</span>{mr("check", 20) if i == 0 else ""}</div>' for i, t in enumerate(OPTS))
            + f'</div><div class="ac" style="padding:0 16px;margin-top:8px">{xb("txt", "取消", n=3 if n else None, tag="keep")}</div></div>')


ph3 = lambda extra: page(393, 852, 3, STATUS + c1.APPBAR3 + c1.settings3() + GESTURE + extra, frame='ph', extra_css=CSS)
ph4 = lambda extra: page(393, 852, 3, STATUS + c1.appbar4() + c1.settings4() + GESTURE + extra, frame='ph', extra_css=CSS)
OUT['v3-option-phone'] = ph3(opt3(250))
OUT['v4-option-phone'] = ph4(opt4(16, 236, DLG_W, n=True))


def land3(extra):
    return page(852, 393, 2, '<div style="height:24px"></div>' + c1.APPBAR3 + c1.settings3(820) + extra, frame='fs', style='background:var(--surface)', extra_css=CSS)


def land4(extra):
    return page(852, 393, 2, '<div style="height:24px"></div>' + c1.appbar4() + c1.settings4(720) + extra, frame='fs', style='background:var(--surface)', extra_css=CSS)


# v3: AlertDialog(scrollable) — title and options scroll together, 取消 stays; dialog height = 393 - 40
OUT['v3-option-land'] = land3('<div class="scr"></div><div class="dg3" style="position:absolute;z-index:21;left:286px;width:280px;top:20px;height:353px;padding:0;display:flex;flex-direction:column;overflow:hidden">'
                              '<div style="flex:1;overflow:hidden;padding-top:0"><div>'
                              '<div class="t b16" style="padding:24px 24px 0">首选清晰度</div><div style="margin-top:12px">'
                              + ''.join(f'<div class="rd3"><i class="{"on" if i == 0 else ""}"></i>{t}</div>' for i, t in enumerate(OPTS))
                              + '</div></div></div><div class="ac" style="padding:0 24px 16px;margin-top:0"><span class="mut3">取消</span></div></div>')
OUT['v4-option-land'] = land4('<div class="scr"></div><div class="dg4" style="position:absolute;z-index:21;left:226px;width:400px;top:16px;height:361px;padding:20px 0 12px;display:flex;flex-direction:column">'
                              '<div class="t" style="padding:0 24px 10px">首选清晰度</div>'
                              '<div style="flex:1;overflow:hidden">' + ''.join(f'<div class="op4{" on" if i == 0 else ""}"><span>{t}</span>{mr("check", 20) if i == 0 else ""}</div>' for i, t in enumerate(OPTS))
                              + '</div>'
                              f'<div class="ac" style="padding:0 16px;margin-top:8px">{xb("txt", "取消")}</div></div>')

# input with the keyboard up (Android): 自动助眠播放时长 (video_settings_page.dart:577-714)
KEY = '<span style="flex:1;max-width:120px;border-radius:6px;background:#fff;box-shadow:0 1px 0 rgba(0,0,0,.25);display:grid;place-items:center;font:500 22px Geist;color:#222">{}</span>'
KB = ('<div style="position:absolute;left:0;right:0;bottom:0;height:300px;z-index:22;background:#D3D6DD;padding:10px 6px 30px;display:flex;flex-direction:column;gap:8px">'
      + ''.join('<div style="display:flex;gap:8px;justify-content:center;flex:1">' + ''.join(KEY.format(k) for k in row) + '</div>'
                for row in (('1', '2', '3'), ('4', '5', '6'), ('7', '8', '9'), ('.', '0', mi('backspace', 22, 'color:#222'))))
      + '<div style="position:absolute;left:8px;top:-22px;font-size:11px;color:#fff;background:rgba(0,0,0,.5);padding:1px 6px;border-radius:4px">数字键盘（示意）</div></div>')
CH3 = ['15 分钟', '30 分钟', '45 分钟', '1 小时', '90 分钟', '2 小时', '4 小时', '8 小时', '12 小时', '1 天']


def input3():
    chips = ''.join(f'<span style="height:32px;padding:0 10px;border-radius:8px;box-shadow:inset 0 0 0 1px var(--ov);display:inline-flex;align-items:center;font-size:13px;font-weight:500">{t}</span>' for t in CH3)
    return ('<div class="scr"></div><div class="dg3" style="position:absolute;z-index:21;left:16px;right:16px;top:118px;padding:24px 24px 16px">'
            '<div class="t b16">自动助眠播放时长</div><div style="font-size:12px;color:var(--onv);margin-top:16px;line-height:1.5">自动助眠启动时按此时长重新计时，到时停止播放。可选快捷时长，也可直接输入分钟数。</div>'
            f'<div style="display:flex;flex-wrap:wrap;gap:8px;margin-top:12px">{chips}</div>'
            '<div style="position:relative;margin-top:20px;height:52px;border-radius:4px;box-shadow:inset 0 0 0 2px var(--primary);display:flex;align-items:center;padding:0 12px;font-size:14px">45<i class="caret"></i>'
            '<span style="margin-left:auto;color:var(--onv)">分钟</span><span style="position:absolute;left:8px;top:-9px;background:var(--sch);padding:0 4px;font-size:12px;color:var(--primary)">自定义播放时长</span></div>'
            '<div style="font-size:12px;color:var(--onv);padding:4px 12px 0">请输入 1 分钟至 365 天之间的分钟数</div>'
            '<div class="ac" style="margin-top:12px"><span class="mut3">取消</span><span class="fb3p">保存</span></div></div>')


def input4(n=False):
    chips = ''.join(f'<span class="x-ch{" on" if t == "45 分钟" else ""}" style="height:36px;padding:0 12px">{mr("check", 18) if t == "45 分钟" else ""}{t}</span>' for t in CH3)
    return ('<div class="scr"></div><div class="dg4" style="position:absolute;z-index:21;left:16px;right:16px;top:74px;padding:22px 24px 14px">'
            '<div class="t">自动助眠播放时长</div><div class="c" style="margin-top:8px">自动助眠启动时按此时长重新计时，到时停止播放。可选快捷时长，也可直接输入分钟数。</div>'
            f'<div style="display:flex;flex-wrap:wrap;gap:8px;margin-top:12px"{dn(1 if n else None, "chg")}>{chips}</div>'
            f'<div class="fd foc" style="margin-top:20px"{dn(2 if n else None, "chg")}><span class="lbl">自定义播放时长</span>45<i class="caret"></i><span class="sfx">分钟</span></div>'
            '<div class="fh"><span>请输入 1 分钟至 365 天之间的分钟数</span></div>'
            f'<div class="ac" style="margin-top:12px">{xb("txt", "取消", n=3 if n else None, tag="keep")}{xb("fill", "保存", n=4 if n else None, tag="keep")}</div></div>')


OUT['v3-input-phone'] = ph3(input3() + KB)
OUT['v4-input-phone'] = ph4(input4(True) + KB)

# confirm on a Windows window: 重置小窗位置和大小 (video_settings_page.dart:526-556)
win3 = lambda extra: page(1280, 800, 1.5, c1.WIN_BAR + c1.APPBAR3 + c1.settings3(960) + extra, frame='win', extra_css=CSS)
win4 = lambda extra: page(1280, 800, 1.5, c1.WIN_BAR + c1.appbar4() + c1.settings4(720) + extra, frame='win', extra_css=CSS)
OUT['v3-confirm-wide'] = win3('<div class="scr"></div><div class="dg3" style="position:absolute;z-index:21;left:469px;width:342px;top:310px">'
                              '<div class="t b16">重置小窗位置和大小</div><div class="c" style="font-size:14px;color:var(--on)">确定要清除已保存的小窗位置和大小吗？</div>'
                              '<div class="ac"><span class="mut3">取消</span><span class="fb3r">重置</span></div></div>')
OUT['v4-confirm-wide'] = win4('<div class="scr"></div><div class="dg4" style="position:absolute;z-index:21;left:440px;width:400px;top:310px">'
                              '<div class="t">重置小窗位置和大小</div><div class="c">确定要清除已保存的小窗位置和大小吗？</div>'
                              f'<div class="ac">{xb("txt", "取消", n=1, tag="keep")}{xb("err", "重置", cls="st-h", n=2, tag="chg")}</div></div>'
                              '<div style="position:absolute;z-index:22;left:803px;top:396px">' + mi('near_me', 22, 'color:#111;transform:rotate(-80deg);filter:drop-shadow(0 0 1px #fff)') + '</div>')

# toast on the phone home (bottom navigation) and in fullscreen
CARDS = [(1, '深夜电台 · 点歌接龙到天亮', '晚风'), (111, '【原神】深渊满星挑战', '一只小熊'), (133, '手绘板绘练习｜今天画一只橘猫', '清欢画画'),
         (169, '周末露营直播，带你看山里的星空', '山野'), (183, '英语口语陪练，零基础也能开口', 'Aki老师'), (206, '复古游戏通关：魂斗罗', '像素老王')]


def home(toast):
    cards = ''.join(f'<div style="background:var(--scl);border-radius:20px;overflow:hidden"><div style="aspect-ratio:16/9;border-radius:20px;background:url({IMG}{i}.jpg) center/cover"></div>'
                    f'<div style="padding:8px 10px 10px"><div style="font-size:13px;font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">{t}</div>'
                    f'<div style="font-size:12px;color:var(--onv);margin-top:2px">{n}</div></div></div>' for i, t, n in CARDS)
    bar = (f'<div class="appbar" style="padding:0 4px"><div class="ib">{mr("menu")}</div><div style="flex:1;display:flex;justify-content:center">'
           + c1.tb(['哔哩哔哩', '斗鱼', '虎牙'], 0) + f'</div><div class="ib">{r("menu_search_line")}</div></div>')
    nav = ('<div class="nav3" style="height:80px;bottom:24px"><div><span>' + rx('ee0b') + '</span><span>关注</span></div><div class="on"><span>' + rx('ed32') + '</span><span>热门</span></div>'
           '<div><span>' + rx('ea42') + '</span><span>分区</span></div><div><span>' + rx('ec54') + '</span><span>录制中心</span></div></div>'
           '<div style="position:absolute;left:0;right:0;bottom:0;height:24px;background:var(--scc)"></div>')
    return page(393, 852, 3, STATUS + bar + f'<div style="display:grid;grid-template-columns:1fr 1fr;gap:6px;padding:6px">{cards}</div>' + nav + GESTURE
                + '<div class="syn">示意图片</div>' + toast, frame='ph', extra_css=CSS)


OUT['v3-toast-phone'] = home('<div style="position:absolute;left:0;right:0;bottom:50px;text-align:center;z-index:30"><span class="ts3">已复制到剪贴板</span></div>')
OUT['v4-toast-phone'] = home('<div style="position:absolute;left:12px;right:12px;bottom:120px;z-index:30">' + ts4('已移除“前排”', '<span' + dn(1, 'add') + '>撤销</span>') + '</div>')


def fs(toast):
    ic = lambda n, s=24: f'<div class="ib vic">{mr(n, s)}</div>'
    top = (f'<div class="vtop">{ic("arrow_back")}<div class="time" style="margin:14px 6px 0 2px">21:36</div><div class="title">纽约时代广场，夜游直播</div>'
           f'{ic("swap_horiz")}<div class="ib vic">{rx("ee05", 21)}</div><div class="ib vic"><span class="ci" style="font-size:24px">&#xe806;</span></div></div>')
    bot = (f'<div class="vbot" style="padding:0 12px 4px">{ic("pause", 28)}{ic("refresh")}<div class="ib vic"><span class="dmk open"></span></div>'
           f'<div class="ib vic"><span class="dmk set"></span></div><div style="flex:1"></div><div class="vchip" style="margin:0 3px">原画{rx("ea4e", 18)}</div>{ic("fullscreen_exit", 26)}</div>')
    return page(852, 393, 2, '<div class="syn">示意图片</div>' + top + bot + toast, frame='fs', style='background-image:url(.cache/img/274.jpg);background-position:center 40%', extra_css=CSS)


OUT['v3-toast-fs'] = fs('<div style="position:absolute;left:0;right:0;bottom:50px;text-align:center;z-index:30"><span class="ts3">发送成功，将在 2 秒后同步显示</span></div>')
OUT['v4-toast-fs'] = fs('<div style="position:absolute;left:0;right:0;bottom:96px;display:flex;justify-content:center;z-index:30">' + ts4('发送成功，将在 2 秒后同步显示', st='max-width:480px') + '</div>')

for name, html in OUT.items():
    open(os.path.join(HERE, name + '.html'), 'w', encoding='utf-8').write(html)
print(len(OUT), 'pages')
