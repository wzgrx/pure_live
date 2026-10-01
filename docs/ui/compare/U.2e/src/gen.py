"""U.2e mockups: the four tabs under the live room video (弹幕列表、醒目留言、
弹幕设置、屏蔽管理), v3 restored and the new design.

v3 (tag v3.2.11):
  widgets/danmaku/danmaku_tab.dart          tabs, loading, "display off" hint
  widgets/danmaku/danmaku_list_view.dart    card rows, resume button, local composer
  pages/super_chat_page.dart                empty state, list
  widgets/layout/super_chat_card.dart       the card
  pages/danmaku_settings_page.dart          settings tab (not embedded) + PiP section
  settings/pages/pip_danmaku_settings_page.dart  PipDanmakuSettingsSection
  pages/keyword_block_page.dart             屏蔽管理
New design: rows and system chips from U.2a, the settings component from U.2f.

    python3 docs/ui/compare/U.2e/src/gen.py
    python3 tools/ui/mock/render.py docs/ui/compare/U.2e/src/ --annotate
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))

CSS = '''
body{position:relative}
.ph{display:flex;flex-direction:column}
.ph>.status,.ph>.appbar,.ph>.video,.ph>.info,.ph>hr,.ph>.tabs,.ph>.res{flex:none}
.area{flex:1;min-height:0;position:relative;overflow:hidden;display:flex;flex-direction:column;background:var(--surface)}
.list{flex:1;min-height:0;overflow:hidden;display:flex;flex-direction:column;justify-content:flex-end;padding:6px 0 10px}
.scroll{flex:1;min-height:0;overflow:hidden}
.u{white-space:nowrap}
/* ---------- v3 pieces ---------- */
.v3h .tt{margin-left:8px;gap:1px}.v3h .tt div{font-size:11px;line-height:15px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.tonal{width:40px;height:40px;border-radius:20px;background:var(--sc);display:grid;place-items:center;color:var(--osc);margin:0 5px 0 2px;flex:none}
.v3rec{width:48px;height:48px;border-radius:12px;background:var(--schh);color:var(--onv);display:grid;place-items:center}
.v3top{position:absolute;left:0;right:0;top:0;height:56px;display:flex;align-items:center;padding:0 8px;background:linear-gradient(0deg,transparent,rgba(0,0,0,.45));z-index:5;color:#fff}
.v3top .title{flex:1;min-width:0;padding:0 12px;font:700 16px 'Noto Sans SC';white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.v3bot{position:absolute;left:0;right:0;bottom:0;height:56px;display:flex;align-items:center;padding:0 8px;background:linear-gradient(180deg,transparent,rgba(0,0,0,.45));color:#fff;z-index:5}
.v3bot .sc3{flex:none;width:313px;overflow:hidden;display:flex;align-items:center}
.v3bot .sp3{flex:1}
.pill{display:flex;align-items:center;gap:2px;padding:0 6px;height:48px;font-size:14px;flex:none}
.fit{flex:none;padding:0 6px;font-size:15px;white-space:nowrap}
.res{height:56px;display:flex;align-items:center;padding:4px}
.res .aud{flex:3;padding:0 8px;display:flex;align-items:center;gap:4px;font-size:12px}
.res .sel{flex:2;text-align:right;font-size:11px;color:var(--primary);padding-right:12px}
.res .line{flex:1;text-align:right;font-size:11px;color:var(--primary);padding-right:12px}
.tabs.v3t div{color:rgba(67,71,78,.8)}.tabs.v3t .on{color:var(--primary)}
[data-theme=dark] .tabs.v3t div{color:rgba(195,199,207,.8)}[data-theme=dark] .tabs.v3t .on{color:var(--primary)}
.it{margin:4px 8px;background:rgba(255,255,255,.72);border:.5px solid rgba(0,0,0,.08);border-radius:10px;padding:8px 12px;display:flex;align-items:flex-start}
.it i{width:8px;height:8px;border-radius:4px;margin:6px 10px 0 0;flex:none}.it p{font-size:14px;line-height:1.45;font-weight:400;color:rgba(0,0,0,.87)}.it b{font-weight:700}
[data-theme=dark] .it{background:rgba(29,32,36,.65);border-color:rgba(255,255,255,.08)}[data-theme=dark] .it p{color:rgba(255,255,255,.7)}
[data-theme=dark] .it i.k{background:#fff!important}
.resume{position:absolute;right:12px;bottom:12px;z-index:4;display:flex;align-items:center;gap:8px;height:40px;padding:0 14px;border-radius:14px;font-size:14px;font-weight:600;white-space:nowrap}
.resume.v3{background:color-mix(in srgb,var(--primary) 92%,transparent);color:#fff}
.resume.v4{background:var(--primary);color:var(--onPrimary)}
.comp{background:var(--scl);padding:8px 8px 8px 10px;display:flex;align-items:center;gap:6px;flex:none}
.comp .f{flex:1;min-width:0;height:48px;border-radius:22px;border:1px solid var(--outline);display:flex;align-items:center;color:var(--onv);font-size:14px;white-space:nowrap;overflow:hidden}
.comp .a{width:44px;height:46px;display:grid;place-items:center;color:var(--primary);flex:none}
.comp .s{width:40px;height:40px;border-radius:20px;background:var(--primary);color:var(--onPrimary);display:grid;place-items:center;flex:none}
.hint3{flex:1;display:flex;align-items:center;justify-content:center;padding:24px;text-align:center;font-size:13px;line-height:1.5}
/* super chat card (v3 structure) */
.sc{margin:6px 10px;border-radius:12px;overflow:hidden;border:.8px solid rgba(0,0,0,.08)}
.sc.sh{box-shadow:0 3px 10px rgba(0,0,0,.10)}
.sc .hd{display:flex;align-items:center;padding:9px 12px;gap:10px}
.sc .av2{width:44px;height:44px;border-radius:22px;padding:1.8px;flex:none}.sc .av2 span{display:block;width:100%;height:100%;border-radius:50%;background:center/cover}
.sc .x{flex:1;min-width:0}.sc .nm{font-size:14px;font-weight:600;line-height:1.2;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.sc .pr{display:flex;align-items:center;gap:3px;margin-top:5px;font:700 15px 'Geist','Noto Sans SC';font-feature-settings:'tnum'}
.sc .inf{display:flex;flex-direction:column;align-items:flex-end;gap:6px;flex:none}
.sc .tg{padding:3px 7px;border-radius:6px;font:700 12px/1 'Geist','Noto Sans SC';letter-spacing:.5px;display:flex;align-items:center;gap:3px}
.sc .tm{display:flex;align-items:center;gap:3px;font:500 12px/1 'Geist','Noto Sans SC';font-feature-settings:'tnum'}
.sc .bd{padding:10px 14px 13px;font-size:14px;line-height:1.5}
.empty{padding:48px 24px;text-align:center;display:flex;flex-direction:column;align-items:center}
.empty .t{font-size:18px;font-weight:700;margin-top:16px}.empty .s{font-size:13px;color:var(--onv);margin-top:8px;line-height:1.5}
/* v3 settings tab (DanmakuSettingsContent, not embedded) and keyword page */
.pad3{padding:12px 16px}
.g3{padding:0 0 8px 8px;font-size:12px;font-weight:700;color:color-mix(in srgb,var(--primary) 65%,transparent);letter-spacing:.5px}
.g3.sp{margin-bottom:8px}
.cd3{background:color-mix(in srgb,var(--schh) 15%,var(--surface));border-radius:20px;border:.5px solid rgba(0,0,0,.05);margin-bottom:20px}
.chips3{display:flex;flex-wrap:wrap;gap:8px}
.chip3{height:32px;margin:8px 0;padding:0 12px 0 8px;border-radius:8px;box-shadow:inset 0 0 0 1px rgba(115,119,127,.35);background:var(--schh);font-size:13px;font-weight:600;display:flex;align-items:center;gap:6px;white-space:nowrap}
.chip3.on{background:var(--primary);color:var(--onPrimary);box-shadow:none}.chip3 .mr{font-size:18px;width:18px}
.ob3{height:48px;padding:0 12px;border-radius:24px;box-shadow:inset 0 0 0 1px color-mix(in srgb,var(--primary) 45%,transparent);color:var(--primary);font-size:13px;font-weight:500;display:flex;align-items:center;gap:8px;white-space:nowrap}
.desc3{font-size:12px;line-height:1.45;color:var(--onv);margin-top:10px}
.fld3{margin:4px;height:52px;border-radius:12px;background:var(--scl);box-shadow:inset 0 0 0 1px var(--outline);display:flex;align-items:center;padding-left:16px;font-size:14px;color:var(--onv)}
.fld3 span:first-child{flex:1}.fld3 .rx{width:48px;text-align:center;color:var(--onv)}
.cnt{font-size:12px;color:var(--onv);text-align:right;padding:4px 16px 6px}
.kt3{padding:8px 32px 6px;font-size:15px;font-weight:600;color:var(--onv)}
.kr3{margin:3px 20px;height:48px;border-radius:12px;background:var(--scl);display:flex;align-items:center;padding-left:16px;font-size:14px}
.kr3 .mr{color:var(--primary);font-size:19px;margin-right:16px}.kr3 span.t{flex:1}.kr3 .x{width:48px;height:48px;display:grid;place-items:center;color:var(--onv)}
/* rows shared by both (values from U.2f) */
.sl{padding:12px 16px}.sl .h{display:flex;justify-content:space-between;align-items:center;gap:8px}.sl .t{font-size:15px;font-weight:600}
.vpill{padding:4px 10px;border-radius:20px;background:color-mix(in srgb,var(--primary) 10%,transparent);font-size:12px;font-weight:700;color:var(--primary);font-feature-settings:'tnum';white-space:nowrap}
.tr{height:4px;border-radius:2px;background:color-mix(in srgb,var(--primary) 15%,transparent);margin:18px 8px 10px 0;position:relative}.tr i{position:absolute;left:0;top:0;bottom:0;border-radius:2px;background:var(--primary)}.tr u{position:absolute;top:-8px;width:20px;height:20px;border-radius:10px;background:var(--primary)}
.swr{display:flex;align-items:center;gap:12px;padding:10px 16px;min-height:56px}.swr .x{flex:1;min-width:0}.swr .t{font-size:15px;font-weight:600}.swr .s{font-size:12px;margin-top:2px;line-height:1.4}
.ct{display:flex;align-items:center;justify-content:space-between;padding:12px 16px;gap:8px}.ct .t{font-size:15px;font-weight:600}
.cb{display:flex;align-items:center;border-radius:12px;box-shadow:inset 0 0 0 1px var(--ov);height:36px;flex:none}.cb span{width:34px;text-align:center;color:var(--onv);font-size:18px}.cb b{min-width:36px;text-align:center;color:var(--primary);font-size:14px;font-feature-settings:'tnum'}
/* ---------- new design (U.2f component) ---------- */
.ns{padding:18px 20px 8px;font-size:13px;font-weight:600;color:var(--primary);display:flex;align-items:center}
.ns .r{margin-left:auto;font-size:13px;font-weight:400;color:var(--onv)}
.ncd{margin:0 12px;background:var(--scl);border-radius:16px}
.n .sl .t,.n .swr .t,.n .ct .t{font-weight:400}.n .swr .s{color:var(--onv)}
.nchips{display:flex;flex-wrap:wrap;gap:8px;padding:2px 16px 0}.nchip{height:36px;padding:0 12px;border-radius:18px;box-shadow:inset 0 0 0 1px var(--ov);font-size:13px;display:flex;align-items:center;gap:4px;white-space:nowrap;flex:none}
.nchip.on{background:var(--sc);box-shadow:none;color:var(--osc);font-weight:600}.nchip .mr{font-size:16px}
.ndesc{padding:8px 20px 0;font-size:12px;color:var(--onv);line-height:1.5}
.nact{display:flex;gap:16px;padding:6px 20px 0;font-size:13px;color:var(--primary);font-weight:400}.nact span{display:flex;align-items:center;gap:4px;height:40px}
.seg{display:flex;margin:0 16px 12px;height:40px;border-radius:20px;box-shadow:inset 0 0 0 1px var(--outline);overflow:hidden}
.seg div{flex:1;display:flex;align-items:center;justify-content:center;gap:4px;font-size:14px}.seg div+div{border-left:1px solid var(--outline)}
.seg .on{background:var(--sc);color:var(--osc);font-weight:600}.seg .mr{font-size:18px}
.colr{display:flex;align-items:center;gap:8px}.colr i{width:28px;height:28px;border-radius:14px;background:#fff;box-shadow:inset 0 0 0 1px var(--ov)}.colr b{font-size:12px;color:var(--primary);font-feature-settings:'tnum'}
/* new: block tab */
.nfld{display:flex;align-items:center;gap:8px;padding:12px 12px 0}
.nfld .f{flex:1;min-width:0;height:48px;border-radius:12px;box-shadow:inset 0 0 0 1px var(--outline);background:var(--surface);display:flex;align-items:center;padding:0 14px;font-size:14px;color:var(--onv)}
.nfld .f.foc{box-shadow:inset 0 0 0 2px var(--primary);color:var(--on)}.nfld .f.err{box-shadow:inset 0 0 0 2px var(--error);color:var(--on)}
.nfld .add{height:48px;padding:0 18px 0 14px;border-radius:24px;background:var(--primary);color:var(--onPrimary);display:flex;align-items:center;gap:4px;font-size:14px;font-weight:600;flex:none}
.nfld .add .rx{font-size:18px}
.nhelp{display:flex;justify-content:space-between;padding:4px 16px 0 24px;font-size:12px;color:var(--onv)}.nhelp.err span:first-child{color:var(--error)}
.nsub{padding:14px 16px 8px;font-size:13px;color:var(--onv)}
.kchips{display:flex;flex-wrap:wrap;gap:8px;padding:0 12px 14px}
.kchip{height:36px;border-radius:8px;box-shadow:inset 0 0 0 1px var(--ov);background:var(--surface);display:flex;align-items:center;padding-left:12px;font-size:14px;white-space:nowrap}
.kchip .mr{font-size:16px;color:var(--primary);margin-right:4px}.kchip .x{width:34px;height:36px;display:grid;place-items:center;color:var(--onv)}
.kempty{padding:4px 16px 16px;font-size:13px;color:var(--onv);line-height:1.5}
/* new: empty / status in the list */
.stat{flex:1;display:flex;flex-direction:column;align-items:center;justify-content:center;padding:16px 32px;text-align:center}
.stat .ic{color:var(--onv)}.stat .t{font-size:15px;font-weight:600;margin-top:10px}.stat .s{font-size:13px;color:var(--onv);margin-top:6px;line-height:1.5}
.tbtn{margin-top:14px;height:40px;padding:0 18px;border-radius:20px;background:var(--sc);color:var(--osc);font-size:14px;font-weight:600;display:flex;align-items:center;gap:6px}
.spin{width:22px;height:22px;border-radius:11px;border:3px solid var(--sc);border-top-color:var(--primary);transform:rotate(45deg)}
.toast2{position:absolute;left:12px;right:12px;bottom:14px;z-index:30;background:#2E3135;color:#EFF0F7;font-size:14px;padding:0 4px 0 16px;height:48px;border-radius:4px;display:flex;align-items:center;box-shadow:0 3px 8px rgba(0,0,0,.25)}
.toast2 span{flex:1}.toast2 b{color:#A0CAFD;font-weight:600;padding:0 12px;height:48px;display:flex;align-items:center}
.rowc{margin:4px 8px;background:var(--scl);border:.5px solid color-mix(in srgb,var(--ov) 60%,transparent);border-radius:10px;padding:8px 12px;display:flex;align-items:flex-start}
.rowc i{width:8px;height:8px;border-radius:4px;margin:6px 10px 0 0;flex:none}.rowc p{font-size:14px;line-height:1.45}.rowc b{font-weight:600}
/* long sheets */
.long{position:relative;width:393px;background:var(--surface)}
.cap{padding:18px 16px 8px;font-size:13px;font-weight:600;color:var(--onv);background:var(--scc)}
.cap b{color:var(--on)}
.blk{position:relative;display:flex;flex-direction:column;overflow:hidden;border-bottom:1px solid var(--ov)}
/* wide / landscape */
.win{display:flex;flex-direction:column}
.body{flex:1;display:flex;min-height:0;position:relative}
.stage{position:relative;flex:1;background:#000;display:flex;align-items:center;justify-content:center;overflow:hidden}
.stage .pic{width:100%;aspect-ratio:16/9;background:#000 url(.cache/img/158.jpg) center 55%/cover}
.colm{flex:none;display:flex;flex-direction:column;background:var(--surface);border-left:1px solid var(--ov);position:relative;overflow:hidden}
.v3fol{height:40px;padding:0 14px;border-radius:6px;background:rgba(54,97,142,.49);color:#fff;font-size:12px;display:flex;align-items:center;margin:0 5px 0 2px;flex:none}
.v3recw{height:48px;padding:0 8px;border-radius:12px;background:var(--schh);color:var(--onv);display:flex;align-items:center;gap:4px;font-size:11px;font-weight:600;flex:none}
.tabs .cb2{position:relative}.tabs .corner{position:absolute;top:-7px;right:-13px;min-width:15px;height:15px;border-radius:8px;background:var(--primary);color:var(--onPrimary);font:600 10px/15px 'Geist';text-align:center;padding:0 4px}
.vvol{display:flex;align-items:center;gap:6px;color:#fff;margin:0 4px}.vvol .t{width:80px;height:4px;border-radius:2px;background:rgba(255,255,255,.35);position:relative}.vvol .t i{position:absolute;left:0;top:0;bottom:0;width:70%;background:#fff;border-radius:2px}.vvol .t u{position:absolute;left:calc(70% - 7px);top:-5px;width:14px;height:14px;border-radius:7px;background:#fff}
'''

mr = lambda n, s=24: f'<span class="mr" style="font-size:{s}px">{n}</span>'
mi = lambda n, s=24: f'<span class="mi" style="font-size:{s}px">{n}</span>'
rx = lambda c, s=24: f'<span class="rx" style="font-size:{s}px">&#x{c};</span>'
ci = lambda c, s=24: f'<span class="ci" style="font-size:{s}px">&#x{c};</span>'


def ib(inner, n=None, cls='ib', tag=None, at=None):
    a = (f' data-n="{n}"' if n else '') + (f' data-tag="{tag}"' if tag else '') + (f' data-at="{at}"' if at else '')
    return f'<div class="{cls}"{a}>{inner}</div>'


def dn(n, tag=None, at=None):
    return (f' data-n="{n}"' if n else '') + (f' data-tag="{tag}"' if tag and n else '') + (f' data-at="{at}"' if at and n else '')


STATUS = ('<div class="status"><span>21:36</span><span class="r"><span class="mi">signal_cellular_alt</span>'
          '<span class="mi">wifi</span><span class="mi">battery_full</span></span></div>')
TITLE = '深夜电台 · 点歌接龙到天亮'
CHAT = [('#C2410C', 'Aki', '打卡第 52 天，晚安前来听歌'), (None, '路过的风', '主播声音太温柔了'), ('#1971C2', '夜猫子', '可以点《晴天》吗'),
        (None, '一只小熊', '这首歌好好听'), ('#C2255C', '星河长明', '前排支持！'), ('#2F9E44', '清欢', '下一首想听《晚风》'),
        (None, '风吹麦浪', '来了来了'), (None, '小林同学', '今天也是被治愈的一天'), (None, '橘子汽水', '晚风晚上好～'),
        (None, '不吃香菜', '上一首是什么歌？'), (None, '月亮邮差', '这个混响调得真舒服'), (None, '南风知我意', '晚风唱歌真的绝了')]
# v3 SuperChatCard data: bilibili tiers (header colour, body colour); arrival order, oldest first
SCS = [('清欢', '.cache/img/111.jpg', '50', '#DBFFFD', '#427D9E', '00:31', '第一次来，主播的声音好治愈'),
       ('星河长明', '.cache/img/133.jpg', '30', '#EDF5FF', '#2A60B2', '00:42', '晚风今天状态真好，祝直播越来越好！'),
       ('夜猫子', '.cache/img/169.jpg', '100', '#FFF1C5', '#E2B52B', '04:36', '可以点一首《晴天》吗？明天要考试了，想听这首放松一下')]


def lum(hex_):
    c = [int(hex_[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    c = [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c]
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]


def ink_v3(bg):  # super_chat_card.dart:79-85
    return ('#18181A', 'rgba(24,24,26,.54)') if lum(bg) > 0.55 else ('#FFFFFF', 'rgba(255,255,255,.70)')


def ink_v4(bg):  # pick the colour with the higher contrast
    l = lum(bg)
    dark = (l + 0.05) / (lum('#18181A') + 0.05)
    light = 1.05 / (l + 0.05)
    return ('#18181A', 'rgba(24,24,26,.62)') if dark >= light else ('#FFFFFF', 'rgba(255,255,255,.80)')


def page(w, h, scale, body, crop=False, frame='ph', style=''):
    size = f'{w}x{h}@{scale}' + (' crop' if crop else '')
    return (f'<!doctype html><html><head><meta charset="utf-8"><meta name="mock-size" content="{size}">'
            f'<link rel="stylesheet" href="kit/kit.css"><style>{CSS}</style></head>'
            f'<body><div class="{frame}" style="{style}">{body}</div></body></html>')


def phone(top, area, extra=''):
    return page(393, 852, 3, top + f'<div class="area">{area}</div>{extra}<div class="syn" style="top:6px">示意图片</div><div class="gesture"></div>')


def long_page(inner, h=3200):
    return page(393, h, 2, inner, crop=True, frame='long')


# ---------------------------------------------------------------- tops
def flying():
    return ('<div class="dm" style="left:150px;top:62px">前排支持！</div><div class="dm" style="left:24px;top:88px">这首好好听</div>'
            '<div class="dm" style="left:226px;top:114px">晚风今天状态好好</div>')


def v3_tabs(on=0, cls='tabs v3t'):
    names = ['弹幕列表', '醒目留言', '弹幕设置', '屏蔽管理']
    return f'<div class="{cls}">' + ''.join(f'<div{" class=\"on\"" if i == on else ""}>{t}</div>' for i, t in enumerate(names)) + '</div>'


def v3_top(on=0):
    head = ('<div class="appbar v3h"><div class="back">' + mi('arrow_back') + '</div><span class="av" style="background-image:url(.cache/img/65.jpg)"></span>'
            '<div class="tt"><div>晚风</div><div>哔哩哔哩 / 唱见电台</div></div>'
            '<div class="tonal">' + rx('ee0b', 19) + '</div><div class="ib"><span class="v3rec">' + rx('f05a', 18) + '</span></div>'
            + ib(rx('ea42')) + '<div style="width:4px"></div></div>')
    top = '<div class="v3top"><div class="title">' + TITLE + '</div>' + ib(rx('ee05', 21)) + ib(rx('f235')) + ib(ci('e806')) + '</div>'
    bot = ('<div class="v3bot"><div class="sc3">' + ib(mr('pause', 28)) + ib(mr('refresh')) + '<div class="pill">' + mr('check', 15) + '已关注</div>'
           + ib('<span class="dmk open"></span>') + ib('<span class="dmk set"></span>') + ib(mr('screen_rotation_alt', 21)) + '<div class="fit">默认比例</div></div>'
           + '<div class="sp3"></div>' + ib(mr('fullscreen', 26)) + '</div>')
    video = '<div class="video" style="background-image:url(.cache/img/158.jpg)">' + flying() + top + bot + '</div>'
    res = '<div class="res"><div class="aud">' + mr('people_alt', 14) + '在线 1.2万</div><div class="sel">原画</div><div class="line">线路1</div></div><hr>'
    return STATUS + head + video + res + v3_tabs(on)


def v4_tabs(on=0, sc=3, n=None, corner=False):
    def lab(i, t):
        if i == 1 and sc:
            return f'<span class="cb2">{t}<span class="corner">{sc}</span></span>' if corner else f'{t}<span class="badge">{sc}</span>'
        return t
    names = ['弹幕列表', '醒目留言', '弹幕设置', '屏蔽管理']
    return (f'<div class="tabs"{dn(n, at="tl")}>' + ''.join(f'<div{" class=\"on\"" if i == on else ""}>{lab(i, t)}</div>' for i, t in enumerate(names)) + '</div>')


def v4_info(heat=True):
    return ('<div class="info"><div class="l1"><span class="t">' + TITLE + '</span><span class="more">详情' + rx('ea4e', 18) + '</span></div>'
            '<div class="l2"><div class="figs"><span class="fg"><span class="mr">people_alt</span><b>1.2万</b></span>' + ('<span class="fg"><span class="mr">whatshot</span><b>84.7万</b></span>' if heat else '') +
            '<span class="fg"><span class="mr">schedule</span><b>2:18</b></span></div>'
            '<div class="chip">原画' + rx('ea4e', 18) + '</div><div class="chip">线路 1' + rx('ea4e', 18) + '</div></div></div><hr>')


def v4_top(on=0, sc=3, n=None):
    head = ('<div class="appbar"><div class="back">' + mi('arrow_back') + '</div><span class="av" style="background-image:url(.cache/img/65.jpg)"></span>'
            '<div class="tt"><div class="n">晚风</div><div class="s">哔哩哔哩 · 唱见电台</div></div>'
            '<div class="fol on">' + rx('eb7b', 16) + '已关注</div><div class="recbtn"><span class="ring"><i></i></span></div>' + ib(rx('ea42')) + '<div style="width:4px"></div></div>')
    top = '<div class="vtop"><div class="title">' + TITLE + '</div>' + ib(rx('ee05', 21), cls='ib vic') + ib(rx('f235'), cls='ib vic') + ib(ci('e806'), cls='ib vic') + '</div>'
    bot = ('<div class="vbot">' + ib(mr('pause', 28), cls='ib vic') + ib(mr('refresh'), cls='ib vic') + ib('<span class="dmk open"></span>', cls='ib vic')
           + ib('<span class="dmk set"></span>', cls='ib vic') + '<div style="flex:1"></div>' + ib(mr('screen_rotation_alt', 21), cls='ib vic') + ib(mr('fullscreen', 26), cls='ib vic') + '</div>')
    video = '<div class="video" style="background-image:url(.cache/img/158.jpg)">' + flying() + top + bot + '</div>'
    return STATUS + head + video + v4_info() + v4_tabs(on, sc, n)


# ---------------------------------------------------------------- 弹幕列表
def v3_cards(rows, sys_=('开始连接弹幕服务器', '弹幕服务器连接正常')):
    items = [('#000', '系统消息', t) for t in sys_] + [(c or '#000', u, t) for c, u, t in rows]
    return ''.join(f'<div class="it"><i{" class=\"k\"" if c == "#000" else ""} style="background:{c}"></i><p><b>{u}: </b>{t}</p></div>' for c, u, t in items)


def v4_rows(rows, n_row=None):
    out = []
    for i, (c, u, t) in enumerate(rows):
        attr = dn(n_row, at='tl') if i == len(rows) - 3 else ''
        out.append(f'<div class="row"{attr}><span class="u" style="{"color:" + c if c else ""}">{u}：</span>{t}</div>')
    return ''.join(out)


def v3_composer():
    return ('<div class="comp"><div class="f"><span class="a">' + mr('auto_awesome', 19) + '</span>发送一条本地字幕</div>'
            '<div class="s">' + mr('send', 22) + '</div></div>')


def v4_composer(n=True):
    return ('<div class="comp"><div class="f"' + dn(5 if n else None, at='tr') + '><span class="a"' + dn(4 if n else None, at='tl') + '>' + mr('auto_awesome', 19)
            + '</span>发送一条本地字幕</div><div class="s"' + dn(6 if n else None, at='tr') + '>' + mr('send', 22) + '</div></div>')


def v3_list_area(composer=True, resume=True):
    return (f'<div class="list" style="position:relative">{v3_cards(CHAT[:9], ())}</div>'
            + ('<div class="resume v3" style="bottom:74px">' + mr('arrow_downward', 18) + '12 条新弹幕，点击回到底部</div>' if resume else '')
            + (v3_composer() if composer else ''))


def v4_list_area(composer=True, resume=True, n=True):
    return (f'<div class="list">{v4_rows(CHAT[2:], 2 if n else None)}</div>'
            + ('<div class="resume v4" style="bottom:76px"' + dn(3 if n else None, at='tl') + '>' + mr('arrow_downward', 18) + '12 条新弹幕，点击回到底部</div>' if resume else '')
            + (v4_composer(n) if composer else ''))


# ---------------------------------------------------------------- 醒目留言
def sc_card(sc, v4=False, narrow=False):
    name, av, price, top, bottom, left, text = sc
    ink = ink_v4 if v4 else ink_v3
    hp, hs = ink(top)
    bp, _ = ink(bottom)
    ring = hp
    tag = f'<span class="tg" style="background:{"rgba(24,24,26,.10)" if hp != "#FFFFFF" else "rgba(255,255,255,.10)"};color:{hs}">' + rx('f28f', 11).replace('style="', 'style="color:#FFC107;') + 'SC</span>'
    tm = f'<span class="tm" style="color:{hp}">' + rx('f20f', 13).replace('style="', f'style="color:{hs};') + f'{left}</span>'
    price_row = f'<div class="pr" style="color:{hp}">' + rx('ef60', 16).replace('style="', 'style="color:#FFC107;') + f'￥{price}</div>'
    if narrow:
        hd = (f'<div class="hd" style="background:{top};flex-direction:column;align-items:stretch;gap:10px"><div style="display:flex;align-items:center;gap:10px">'
              f'<span class="av2" style="background:{ring}"><span style="background-image:url({av})"></span></span><div class="nm" style="color:{hp};white-space:normal">{name}</div></div>'
              f'{price_row}<div class="inf" style="align-items:flex-start">{tag}{tm}</div></div>')
    else:
        hd = (f'<div class="hd" style="background:{top}"><span class="av2" style="background:{ring}"><span style="background-image:url({av})"></span></span>'
              f'<div class="x"><div class="nm" style="color:{hp}">{name}</div>{price_row}</div><div class="inf">{tag}{tm}</div></div>')
    return f'<div class="sc{"" if v4 else " sh"}">{hd}<div class="bd" style="background:{bottom};color:{bp}">{text}</div></div>'


def sc_area(v4=False, n=False):
    cards = list(reversed(SCS)) if v4 else SCS
    html = ''
    for i, sc in enumerate(cards):
        c = sc_card(sc, v4)
        if n and i == 0:
            c = c.replace('<div class="bd"', '<div class="bd"' + dn(9, at='tl'), 1)
        html += f'<div style="padding-bottom:8px">{c}</div>'
    return f'<div class="scroll" style="padding:8px 0">{html}</div>'


def sc_empty(sub='当前直播间的付费留言会显示在这里。'):
    return ('<div class="empty">' + rx('eb71', 42).replace('style="', 'style="color:var(--primary);') + '<div class="t">暂无醒目留言</div>'
            f'<div class="s">{sub}</div></div>')


# ---------------------------------------------------------------- settings rows
def sl(t, v, pct, dis=False):
    return (f'<div class="sl{" dis" if dis else ""}"><div class="h"><span class="t">{t}</span><span class="vpill">{v}</span></div>'
            f'<div class="tr"><i style="width:{pct}%"></i><u style="left:calc({pct}% - 10px)"></u></div></div>')


def swr(t, on, s=None, n=None, tag=None, dis=False, s_on=False):
    sub = f'<div class="s"{" style=\"color:var(--on)\"" if s_on else ""}>{s}</div>' if s else ''
    return f'<div class="swr{" dis" if dis else ""}"><div class="x"><div class="t">{t}</div>{sub}</div><span class="sw{" on" if on else ""}"{dn(n, tag, "tl")}></span></div>'


def ct(t, v, dis=False):
    return f'<div class="ct{" dis" if dis else ""}"><span class="t">{t}</span><span class="cb"><span>－</span><b>{v}</b><span>＋</span></span></div>'


# v3 settings tab: DanmakuSettingsContent(embedded: false) + PipDanmakuSettingsSection
def v3_settings(pip=True):
    chips = ''
    for t, on, ic in [('顶部 20% · 均衡', True, ''), ('顶部 35% · 舒适', False, ''), ('顶部 55% · 高密度', False, ''), ('重置', False, '')]:
        icon = mr('check', 18) if on else '<span style="width:18px"></span>'
        chips += f'<span class="chip3{" on" if on else ""}">{icon}{t}</span>'
    chips += '<span class="ob3">' + mi('save', 18) + '保存当前模板</span><span class="ob3">' + mr('restore', 18) + '恢复已保存模板</span>'
    tpl = ('<div class="cd3" style="padding:12px"><div class="chips3">' + chips + '</div><div class="desc3">最佳观看：弹幕只占画面顶部约 20%，速度与密度适中，避免遮挡主体内容。<br>'
           '本页调整会立即作用于上方直播画面；保存当前模板只用于以后快速恢复。</div></div>')
    g = lambda t: f'<div class="g3 sp">{t}</div>'
    body = (g('弹幕观看模板') + tpl
            + g('画面顶部占用高度') + '<div class="cd3">' + swr('纯文字模式（隐藏表情）', False) + sl('画面顶部占用高度', '20%', 20) + '</div>'
            + g('位置') + '<div class="cd3">' + ct('顶部留白（像素）', 0) + ct('区域底部留白（像素）', 0) + '</div>'
            + g('样式') + '<div class="cd3">' + sl('透明度', '92%', 92) + sl('滚动速度（像素/秒）', '118 px/s', 26) + sl('字体大小', '16.0 px', 30) + sl('字体粗细', '稍粗', 50)
            + swr('弹幕描边', True) + sl('描边宽度', '1.5 px', 37)
            + swr('弹幕帧率 · 跟随界面刷新率策略', True, '开启：跟随通用里的省电、均衡或最高档位并立即生效；关闭：仅使用这里的手动帧率。', s_on=True)
            + '<div style="padding:0 16px 12px;color:var(--primary);font-weight:600;font-size:14px">120 FPS</div></div>'
            + g('重复弹幕过滤') + '<div class="cd3">' + swr('合并短时间内的相同弹幕', False, '不同用户发送相同内容时只保留第一条；本地弹幕和系统消息不受影响。', s_on=True) + '</div>'
            + g('屏幕弹幕交互') + '<div class="cd3">' + swr('点击画面弹幕查看操作', True) + swr('长按画面弹幕打开屏蔽操作', True) + '</div>')
    if pip:
        body += ('<div class="g3">小窗弹幕</div><div style="height:8px"></div><div class="cd3">' + swr('小窗显示弹幕', True) + swr('纯文字模式（隐藏表情）', False)
                 + swr('根据小窗尺寸自动缩放', True) + swr('保留平台弹幕颜色', True) + sl('字体大小', '12.0', 25) + sl('字体粗细', '稍粗', 50)
                 + sl('滚动速度（像素/秒）', '90', 18) + sl('透明度', '90%', 89) + sl('画面顶部占用高度', '50%', 44) + ct('最大同时显示数量', 6)
                 + sl('发送间隔', '0.35s', 15) + swr('弹幕帧率 · 跟随界面刷新率策略', True, '开启：小窗弹幕跟随同一全局档位；关闭：小窗使用独立手动帧率，不影响主画面。')
                 + '<div style="padding:0 16px 12px;color:var(--primary);font-weight:600;font-size:14px">120 FPS</div></div>')
    return f'<div class="pad3">{body}</div>'


# new: the U.2f component (same items, same order) + 弹幕列表 and 小窗弹幕 at the end
def v4_settings(tail=True, n=True):
    N = (lambda k: k) if n else (lambda k: None)
    chips = '<div class="nchips">' + ''.join(
        f'<span class="nchip{" on" if on else ""}">' + (mr('check', 16) if on else '') + f'{t}</span>'
        for t, on in [('顶部 20% · 均衡', True), ('顶部 35% · 舒适', False), ('顶部 55% · 高密度', False), ('重置', False)]) + '</div>'
    body = ('<div class="ns" style="padding-top:12px">观看模板<span class="r">改动立即生效</span></div>' + chips
            + '<div class="ndesc">弹幕只占画面顶部约 20%，速度与密度适中，避免遮挡主体内容。</div>'
            + '<div class="nact"><span>' + mr('save', 18) + '把当前设置存为我的模板</span><span>' + mr('restore', 18) + '用我的模板</span></div>'
            + '<div class="ns">显示范围</div><div class="ncd">' + sl('画面顶部占用高度', '20%', 20) + ct('顶部留白（像素）', 0) + ct('区域底部留白（像素）', 0) + '</div>'
            + '<div class="ns">样式</div><div class="ncd">' + sl('透明度', '92%', 92) + sl('滚动速度（像素/秒）', '118 px/s', 26) + sl('字体大小', '16.0 px', 30)
            + sl('字体粗细', '稍粗', 50) + swr('弹幕描边', True) + sl('描边宽度', '1.5 px', 37) + swr('纯文字模式（隐藏表情）', False) + '</div>'
            + '<div class="ns">重复弹幕</div><div class="ncd">' + swr('合并短时间内的相同弹幕', False, '不同用户发送相同内容时只保留第一条；本地弹幕和系统消息不受影响。')
            + ct('相同内容合并时间（秒）', 5, dis=True) + '</div>'
            + '<div class="ns">画面弹幕交互</div><div class="ncd">' + swr('点击画面弹幕查看操作', True) + swr('长按画面弹幕打开屏蔽操作', True) + '</div>'
            + '<div class="ns">流畅度</div><div class="ncd">' + swr('弹幕帧率跟随界面刷新率', True, '跟随“通用”里的省电、均衡或最高档位；关闭后可以手动设帧率。')
            + sl('弹幕帧率', '120 FPS', 47, dis=True) + '</div>')
    if tail:
        body += ('<div class="ns">弹幕列表</div><div class="ncd"><div class="swr" style="padding-bottom:6px"><div class="x"><div class="t">弹幕列表样式</div>'
                 '<div class="s">紧凑：一行一条，用户名用浅色；卡片：3.x 的每条一张卡片</div></div></div>'
                 f'<div class="seg"{dn(N(10), "add", "tl")}><div class="on">' + mr('check', 18) + '紧凑</div><div>卡片</div></div>'
                 + swr('在聊天列表显示礼物', False, '平台上报的礼物显示为聊天里的一行，不在画面上飞过', n=N(11), tag='add') + '</div>'
                 + '<div class="ns">小窗弹幕</div><div class="ncd">'
                 + swr('小窗显示弹幕', True, '配置 Android 系统画中画、Windows 小窗和应用内悬浮窗的弹幕样式', n=N(12), tag='keep')
                 + swr('纯文字模式（隐藏表情）', False) + swr('根据小窗尺寸自动缩放', True) + swr('保留平台弹幕颜色', True)
                 + '<div class="ct dis"><span class="t">统一弹幕颜色</span><span class="colr"><i></i><b>#FFFFFFFF</b></span></div>'
                 + sl('字体大小', '12.0 px', 25) + sl('字体粗细', '稍粗', 50) + sl('滚动速度（像素/秒）', '90 px/s', 18) + sl('透明度', '90%', 89)
                 + sl('画面顶部占用高度', '50%', 44) + ct('最大同时显示数量', 6) + sl('发送间隔', '0.35 秒', 15)
                 + swr('弹幕帧率跟随界面刷新率', True, '跟随同一全局档位；关闭后小窗用单独的手动帧率，不影响主画面。')
                 + sl('弹幕帧率', '120 FPS', 47, dis=True) + '</div>')
    return f'<div class="n">{body}<div style="height:24px"></div></div>'


# ---------------------------------------------------------------- 屏蔽管理
KEYS = ['剧透', '刷屏', '广告位招租']
USERS = ['路人甲', '某某广告']


def v3_block(sim_on=False, lists=True):
    g = lambda t: f'<div class="g3">{t}</div>'
    sim = swr('启用相似弹幕过滤', sim_on)
    if sim_on:
        sim += sl('相似度阈值', '85%', 70) + sl('缓存时间', '3 秒', 3) + sl('最大缓存数量', '100', 8)
    body = (g('平台弹幕过滤') + '<div class="cd3">' + swr('过滤斗鱼疑似自动弹幕', False, '开启后按启发式标记隐藏疑似自动或活动弹幕，也可能隐藏普通聊天') + '</div>'
            + g('相似弹幕过滤') + '<div class="cd3">' + sim + '</div>'
            + g('弹幕关键词屏蔽') + '<div class="cd3" style="padding-bottom:2px"><div class="fld3"><span>请输入关键词</span>' + rx('ea11', 24) + '</div><div class="cnt">0/40</div></div>')
    rows = ''
    if lists:
        rows += f'<div class="kt3">已添加{len(KEYS)}个关键词</div>' + ''.join(
            f'<div class="kr3">{mr("filter_alt_off", 19)}<span class="t">{k}</span><span class="x">{rx("eb99", 18)}</span></div>' for k in KEYS)
        rows += f'<div style="height:20px"></div><div class="kt3">已屏蔽用户（{len(USERS)}）</div>' + ''.join(
            f'<div class="kr3">{mr("person_off", 19)}<span class="t">{u}</span><span class="x">{rx("eb99", 18)}</span></div>' for u in USERS)
    return f'<div class="pad3" style="padding-bottom:0">{body}</div>{rows}<div style="height:24px"></div>'


def kchips(items, user=False, n=None, tag=None):
    out = ''
    for i, k in enumerate(items):
        lead = mr('person_off', 16) if user else ''
        x = f'<span class="x"{dn(n, tag, "tr") if i == 0 else ""}>{rx("eb99", 18)}</span>'
        out += f'<span class="kchip">{lead}{k}{x}</span>'
    return f'<div class="kchips">{out}</div>'


def v4_block(n=True, sim_on=False, keys=KEYS, users=USERS, field='', err=None, n_filters=False):
    N = (lambda k: k) if n else (lambda k: None)
    F = (lambda k: k) if n_filters else (lambda k: None)
    fcls = 'f err' if err else ('f foc' if field else 'f')
    ftext = field or '请输入关键词'
    help_ = (f'<div class="nhelp{" err" if err else ""}"><span>{err or ""}</span><span>{len(field)}/40</span></div>')
    kw = ('<div class="ns" style="padding-top:12px">弹幕关键词屏蔽</div><div class="ncd">'
          f'<div class="nfld"><div class="{fcls}"{dn(N(13), at="tl")}>{ftext}</div><div class="add"{dn(N(14), at="tr")}>' + rx('ea13', 18) + '添加</div></div>' + help_
          + (f'<div class="nsub">已添加{len(keys)}个关键词</div>' + kchips(keys, n=N(15)) if keys else
             '<div class="nsub">暂无屏蔽关键词</div><div class="kempty" style="padding-top:0">添加关键词后，包含该内容的弹幕将被自动过滤</div>') + '</div>')
    us = (f'<div class="ns">已屏蔽用户（{len(users)}）</div><div class="ncd" style="padding-top:12px">' + kchips(users, True, n=N(16)) + '</div>' if users else
          '<div class="ns">已屏蔽用户（0）</div><div class="ncd"><div class="kempty" style="padding-top:14px">还没有屏蔽的用户；长按弹幕可屏蔽发送者</div></div>')
    sim = (swr('启用相似弹幕过滤', sim_on, n=F(18)) + sl('相似度阈值', '85%', 70, dis=not sim_on) + sl('缓存时间', '3 秒', 3, dis=not sim_on)
           + sl('最大缓存数量', '100', 8, dis=not sim_on))
    flt = ('<div class="ns">平台弹幕过滤</div><div class="ncd">' + swr('过滤斗鱼疑似自动弹幕', False, '开启后按启发式标记隐藏疑似自动或活动弹幕，也可能隐藏普通聊天', n=F(17)) + '</div>'
           + '<div class="ns">相似弹幕过滤</div><div class="ncd">' + sim + '</div>')
    return f'<div class="n">{kw}{us}{flt}<div style="height:24px"></div></div>'


# ---------------------------------------------------------------- state sheets
def blk(caption, inner, h, tabs):
    return f'<div class="cap">{caption}</div><div class="blk" style="height:{h}px">{tabs}<div class="area">{inner}</div></div>'


def stat(icon, title, sub=None, btn=None, n=None):
    return ('<div class="stat">' + icon + f'<div class="t">{title}</div>' + (f'<div class="s">{sub}</div>' if sub else '')
            + (f'<div class="tbtn"{dn(n, "add", "tr")}>{btn}</div>' if btn else '') + '</div>')


def v3_list_states():
    t = v3_tabs(0)
    s = blk('<b>连接中 / 刚连上还没人说话</b>：只有两张“系统消息”卡片，上面一片空白', f'<div class="list">{v3_cards([])}</div>', 300, t)
    s += blk('<b>平台不提供弹幕</b>（网易 CC）：整片空白，没有任何说明', '<div class="list"></div>', 300, t)
    s += blk('<b>连接失败</b>：一张系统消息卡片，没有下一步', f'<div class="list">{v3_cards([], ("开始连接弹幕服务器", "弹幕服务器连接超时，已自动释放并可重新连接"))}</div>', 300, t)
    s += blk('<b>“设置 → 视频 → 显示弹幕”关闭时</b>：列表换成一句话，没有入口', '<div class="hint3">全局弹幕显示已关闭；仍可切换到“弹幕设置”调整主播放器和小窗弹幕。</div>', 300, t)
    return long_page(s)


def v4_list_states():
    t = v4_tabs(0)
    s = blk('<b>连接中</b>：还没有弹幕时，最新的系统消息放在中间当状态', stat('<span class="spin"></span>', '开始连接弹幕服务器'), 300, t)
    s += blk('<b>连上了，还没人说话</b>', stat(rx('eb71', 32).replace('style="', 'style="color:var(--onv);'), '还没有弹幕', '弹幕服务器连接正常，新弹幕会显示在这里'), 300, t)
    s += blk('<b>连接失败</b>：给出下一步', stat(rx('f2c2', 32).replace('style="', 'style="color:var(--onv);'), '弹幕服务器连接超时',
                                               '已自动释放，可以重新连接', mr('refresh', 18) + '重新连接', 8), 320, t)
    s += blk('<b>平台不提供弹幕</b>（网易 CC）', stat(rx('eb65', 32).replace('style="', 'style="color:var(--onv);'), '网易 CC 的直播间没有弹幕', '醒目留言、弹幕设置、屏蔽管理照常可用'), 300, t)
    s += blk('<b>“显示弹幕”关闭时</b>：加一个按钮直接打开', stat(rx('eb65', 32).replace('style="', 'style="color:var(--onv);'), '全局弹幕显示已关闭',
                                                    '仍可切换到“弹幕设置”调整主播放器和小窗弹幕。', '开启弹幕显示', 7), 320, t)
    s += blk('<b>有了第一条弹幕以后</b>：照 U.2a，系统消息是居中的小标签', '<div class="list"><div class="sys">弹幕服务器连接正常</div>' + v4_rows(CHAT[:3]) + '</div>', 260, t)
    cards = ''.join(f'<div class="rowc"><i style="background:{c or "var(--on)"}"></i><p><b>{u}: </b>{x}</p></div>' for c, u, x in CHAT[:5])
    s += blk('<b>弹幕列表样式选“卡片”</b>（U.2a 已定，设置在“弹幕设置 → 弹幕列表”）', f'<div class="list">{cards}</div>', 300, t)
    return long_page(s, 3600)


def v4_sc_states():
    t1 = v4_tabs(1, 0)
    s = blk('<b>没有醒目留言</b>（哔哩哔哩、虎牙、斗鱼）：照 v3', sc_empty(), 330, t1)
    s += blk('<b>平台不提供醒目留言</b>（抖音、快手、网易 CC 等）：说清楚，不让人一直等', sc_empty('抖音的直播间没有醒目留言。'), 330, t1)
    narrow = sc_card(SCS[2], v4=True, narrow=True)
    s += blk('<b>窄栏或系统字体放大时</b>：卡片头部竖排（照 v3，宽度 &lt;280 或字体放大）', f'<div style="width:270px;margin:8px auto">{narrow}</div>', 420, v4_tabs(1, 1))
    return long_page(s)


def v4_block_states():
    t = v4_tabs(3)
    s = blk('<b>什么都还没屏蔽</b>：两组都显示空的说明', v4_block(n=False, keys=[], users=[]), 470, t)
    s += blk('<b>关键词已经在列表里</b>：输入框下面直接说，不清空', v4_block(n=False, field='剧透', err='“剧透”已经在屏蔽列表里'), 302, t)
    s += blk('<b>点 × 删除以后</b>：提示条可以撤销（4 秒）', v4_block(n=False, keys=KEYS[1:]) +
             f'<div class="toast2"><span>已移除“剧透”</span><b{dn(19, "add", "tr")}>撤销</b></div>', 302, t)
    return long_page(s)


# ---------------------------------------------------------------- wide (U.2d layout) and landscape
def col_width(w):
    return max(300, min(400, round(w * 0.34)))


def v3_wide(w, h, scale, area, on, windows=True):
    head = ('<div class="appbar v3h"><div class="back">' + mi('arrow_back') + '</div><span class="av" style="background-image:url(.cache/img/65.jpg)"></span>'
            '<div class="tt"><div>晚风</div><div>哔哩哔哩 / 唱见电台</div></div>'
            '<div class="v3fol">已关注</div><div class="v3recw">' + rx('f05a', 14) + '录制</div>' + ib(rx('ea42')) + '<div style="width:4px"></div></div>')
    top = ('<div class="v3top"><div class="title">' + TITLE + '</div>' + ib(rx('ee05', 21)) + ('' if windows else ib(rx('f235'))) + ib(ci('e806')) + '</div>')
    left = ib(mr('pause', 28)) + ib(mr('refresh')) + '<div class="pill">' + mr('check', 15) + '已关注</div>' + ib('<span class="dmk open"></span>') + ib('<span class="dmk set"></span>')
    right = (('' if windows else ib(mr('screen_rotation_alt', 21))) + '<div class="fit">默认比例</div>'
             + (ib(mr('volume_up', 22)) + ib(mr('unfold_more', 26)) if windows else '') + ib(mr('fullscreen', 26)))
    bot = f'<div class="v3bot"><div style="display:flex;align-items:center">{left}</div><div style="flex:1"></div><div style="display:flex;align-items:center">{right}</div></div>'
    stage = f'<div class="stage"><div class="pic"></div>{top}{bot}</div>'
    cw = col_width(w)
    col = (f'<div class="colm" style="width:{cw}px"><div class="res"><div class="aud">' + mr('people_alt', 14) + '在线 1.2万</div><div class="sel">原画</div><div class="line">线路1</div></div><hr>'
           + v3_tabs(on) + f'<div class="area">{area}</div></div>')
    return page(w, h, scale, head + f'<div class="body">{stage}{col}</div><div class="syn" style="top:6px">示意图片</div>', frame='win', style=f'--w:{w}px;--h:{h}px')


def v4_wide(w, h, scale, area, on, windows=True):
    head = ('<div class="appbar"><div class="back">' + mi('arrow_back') + '</div><span class="av" style="background-image:url(.cache/img/65.jpg)"></span>'
            '<div class="tt"><div class="n">晚风</div><div class="s">哔哩哔哩 · 唱见电台</div></div>'
            '<div class="fol on">' + rx('eb7b', 16) + '已关注</div><div class="recbtn"><span class="ring"><i></i></span></div>' + ib(rx('ea42')) + '<div style="width:4px"></div></div>')
    top = ('<div class="vtop"><div class="title">' + TITLE + '</div>' + ib(rx('ee05', 21), cls='ib vic') + ('' if windows else ib(rx('f235'), cls='ib vic')) + ib(ci('e806'), cls='ib vic') + '</div>')
    left = ib(mr('pause', 28), cls='ib vic') + ib(mr('refresh'), cls='ib vic') + ib('<span class="dmk open"></span>', cls='ib vic') + ib('<span class="dmk set"></span>', cls='ib vic')
    right = (('<div class="vvol">' + mr('volume_up', 22) + '<div class="t"><i></i><u></u></div></div>' if windows else ib(mr('screen_rotation_alt', 21), cls='ib vic'))
             + ib(mr('vertical_split', 24), cls='ib vic') + (ib(mr('unfold_more', 26), cls='ib vic') if windows else '') + ib(mr('fullscreen', 26), cls='ib vic'))
    bot = f'<div class="vbot"><div style="display:flex;align-items:center">{left}</div><div style="flex:1"></div><div style="display:flex;align-items:center">{right}</div></div>'
    stage = f'<div class="stage"><div class="pic"></div>{top}{bot}</div>'
    cw = col_width(w)
    col = f'<div class="colm" style="width:{cw}px">' + v4_info(cw >= 340) + v4_tabs(on, 3, corner=cw < 340) + f'<div class="area">{area}</div></div>'
    return page(w, h, scale, head + f'<div class="body">{stage}{col}</div><div class="syn" style="top:6px">示意图片</div>', frame='win', style=f'--w:{w}px;--h:{h}px')


# ---------------------------------------------------------------- output
OUT = {
    # portrait, v3
    'v3-list': phone(v3_top(0), v3_list_area()),
    'v3-sc': phone(v3_top(1), sc_area()),
    'v3-settings': phone(v3_top(2), '<div class="scroll">' + v3_settings() + '</div>'),
    'v3-block': phone(v3_top(3), '<div class="scroll">' + v3_block() + '</div>'),
    'v3-settings-full': long_page(v3_settings(), 4000),
    'v3-block-full': long_page(v3_block(sim_on=True)),
    'v3-list-states': v3_list_states(),
    'v3-sc-empty': phone(v3_top(1), sc_empty()),
    # portrait, new
    'v4-list': phone(v4_top(0, n=1), v4_list_area()),  # rows: CHAT[1:] so no half row under the tabs
    'v4-sc': phone(v4_top(1), sc_area(v4=True, n=True)),
    'v4-settings': phone(v4_top(2), '<div class="scroll">' + v4_settings(n=False) + '</div>'),
    'v4-block': phone(v4_top(3), '<div class="scroll">' + v4_block() + '</div>'),
    'v4-settings-full': long_page(v4_settings(), 4400),
    'v4-block-full': long_page(v4_block(n=False, sim_on=True, n_filters=True)),
    'v4-list-states': v4_list_states(),
    'v4-sc-states': v4_sc_states(),
    'v4-block-states': v4_block_states(),
    # wide 1280x800 (U.2d layout) and landscape phone 852x393
    'v3-wide': v3_wide(1280, 800, 1.5, sc_area(), 1),
    'v4-wide': v4_wide(1280, 800, 1.5, sc_area(v4=True), 1),
    'v4-wide-block': v4_wide(1280, 800, 1.5, '<div class="scroll">' + v4_block(n=False) + '</div>', 3),
    'v3-land': v3_wide(852, 393, 2, f'<div class="list">{v3_cards(CHAT[:6], ())}</div>', 0, windows=False),
    'v4-land': v4_wide(852, 393, 2, f'<div class="list">{v4_rows(CHAT)}</div>', 0, windows=False),
}
for name, html in OUT.items():
    open(os.path.join(HERE, name + '.html'), 'w', encoding='utf-8').write(html)
print(len(OUT), 'pages')
