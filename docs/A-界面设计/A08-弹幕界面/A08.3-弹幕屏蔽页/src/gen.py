"""U.12d danmaku block page (设置里的弹幕关键词屏蔽) mockups: v3 restored and
the new design.

v3 (tag v3.2.11): lib/modules/shield/danmu_shield_page.dart, danmu_shield_controller.dart;
entry: modules/settings/pages/video_settings_page.dart:288-293.
New design: the block component of the live room's 屏蔽管理 tab, copied from
docs/ui/compare/U.2e/src/gen.py (v4_block and its CSS) so both stay the same
component (U.2e choice E4). Keywords and user names are examples.
    python3 docs/ui/compare/U.12d/src/gen.py && python3 tools/ui/mock/render.py docs/ui/compare/U.12d/src/ --annotate"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from skit import *  # noqa: E402,F401,F403
from skit import composite as _composite  # noqa: E402

CSS2 = '''
/* v3 */
.f3k{height:56px;border-radius:14px;background:var(--scl);display:flex;align-items:center;padding:0 6px 0 16px;font-size:15px}
.f3k .x{flex:1;color:rgba(67,71,78,.6)}.f3k .x.v{color:var(--on)}
.f3k.foc{box-shadow:inset 0 0 0 1.5px var(--primary)}
.f3k .tb{font-weight:600;padding:0 10px;border-radius:10px}
.cnt3{font-size:12px;color:var(--onv);text-align:right;padding:4px 12px 0}
.kt{padding:24px 4px 12px;font-size:14px;font-weight:700;color:var(--primary)}
.chips3{display:flex;flex-wrap:wrap;gap:10px}
.chip3{min-height:48px;display:flex;align-items:center}
.chip3>span{padding:8px 12px;border-radius:10px;background:rgba(54,97,142,.06);box-shadow:inset 0 0 0 1px rgba(54,97,142,.15);font-size:13px;font-weight:500;display:flex;align-items:center;gap:6px}
/* new: copied from U.2e (block tab) */
.ns{padding:18px 20px 8px;font-size:13px;font-weight:600;color:var(--primary);display:flex;align-items:center}
.ncd{margin:0 12px;background:var(--scl);border-radius:16px}
.n .sl .t,.n .swr .t,.n .ct .t{font-weight:400}.n .swr .s{color:var(--onv)}
.sl{padding:12px 16px}.sl .h{display:flex;justify-content:space-between;align-items:center;gap:8px}.sl .t{font-size:15px}
.vpill{padding:4px 10px;border-radius:20px;background:color-mix(in srgb,var(--primary) 10%,transparent);font-size:12px;font-weight:700;color:var(--primary);font-feature-settings:'tnum';white-space:nowrap}
.tr{height:4px;border-radius:2px;background:color-mix(in srgb,var(--primary) 15%,transparent);margin:18px 8px 10px 0;position:relative}.tr i{position:absolute;left:0;top:0;bottom:0;border-radius:2px;background:var(--primary)}.tr u{position:absolute;top:-8px;width:20px;height:20px;border-radius:10px;background:var(--primary)}
.swr{display:flex;align-items:center;gap:12px;padding:10px 16px;min-height:56px}.swr .x{flex:1;min-width:0}.swr .t{font-size:15px}.swr .s{font-size:12px;margin-top:2px;line-height:1.4}
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
.toast2{position:absolute;left:12px;right:12px;bottom:20px;z-index:30;background:#2E3135;color:#EFF0F7;font-size:14px;padding:0 4px 0 16px;height:48px;border-radius:4px;display:flex;align-items:center;box-shadow:0 3px 8px rgba(0,0,0,.25)}
.toast2 span{flex:1}.toast2 b{color:#A0CAFD;font-weight:600;padding:0 12px;height:48px;display:flex;align-items:center}
'''


def composite(phones, **kw):
    return _composite(phones, css=CSS2, **kw)


def p(html):
    return page('393x852@3', html, css=CSS2)


KEYS = ['剧透', '刷屏', '广告位招租', '哈哈哈哈哈哈', '代练']
USERS = ['路人甲', '某某广告']


# ---------------------------------------------------------------- v3
def v3_body(keys=KEYS, text='', focus=False):
    fld = (f'<div class="f3k{" foc" if focus else ""}"><span class="x{" v" if text else ""}">{text or "请输入关键字"}</span>'
           f'<span class="tb">{rx("ea13", 18)}添加</span></div><div class="cnt3">{len(text)}/40</div>')
    title = f'<div class="kt">已添加 {len(keys)} 个关键词（点击可移除）</div>'
    if keys:
        lst = '<div class="chips3">' + ''.join(f'<div class="chip3"><span>{k}{rx("eb99", 14, "rgba(54,97,142,.6)")}</span></div>' for k in keys) + '</div>'
    else:
        lst = (f'<div style="padding-top:40px"><div class="sv" style="height:auto"><div class="svc">{rx("ec3a")}</div><h4>暂无屏蔽关键词</h4>'
               '<p>添加关键词后，包含该内容的弹幕将被自动过滤</p></div></div>')
    return f'<div style="padding:16px"><div style="max-width:100%">{fld}{title}{lst}</div></div>'


V3BAR = bar('弹幕关键词屏蔽')


# ---------------------------------------------------------------- new (U.2e component)
def sl(t, v, pct, dis=False):
    return (f'<div class="sl{" dis" if dis else ""}"><div class="h"><span class="t">{t}</span><span class="vpill">{v}</span></div>'
            f'<div class="tr"><i style="width:{pct}%"></i><u style="left:calc({pct}% - 10px)"></u></div></div>')


def swr(t, on, s=None, n=None, tag=None, dis=False):
    sub = f'<div class="s">{s}</div>' if s else ''
    return f'<div class="swr{" dis" if dis else ""}"><div class="x"><div class="t">{t}</div>{sub}</div><span class="sw{" on" if on else ""}"{dn(n, tag, "tl")}></span></div>'


def kchips(items, user=False, n=None, tag=None):
    out = ''
    for i, k in enumerate(items):
        lead = mr('person_off', 16) if user else ''
        x = f'<span class="x"{dn(n, tag, "tr") if i == 0 else ""}>{rx("eb99", 18)}</span>'
        out += f'<span class="kchip">{lead}{k}{x}</span>'
    return f'<div class="kchips">{out}</div>'


def v4_block(n=False, sim_on=False, keys=KEYS, users=USERS, field='', err=None, n_filters=False):
    N = (lambda k: k) if n else (lambda k: None)
    F = (lambda k: k) if n_filters else (lambda k: None)
    fcls = 'f err' if err else ('f foc' if field else 'f')
    ftext = field or '请输入关键词'
    help_ = (f'<div class="nhelp{" err" if err else ""}"><span>{err or ""}</span><span>{len(field)}/40</span></div>')
    kw = ('<div class="ns" style="padding-top:12px">弹幕关键词屏蔽</div><div class="ncd">'
          f'<div class="nfld"><div class="{fcls}"{dn(N(2), "chg", "tl")}>{ftext}</div><div class="add"{dn(N(3), "chg", "tr")}>' + rx('ea13', 18) + '添加</div></div>' + help_
          + (f'<div class="nsub">已添加{len(keys)}个关键词</div>' + kchips(keys, n=N(4), tag='chg') if keys else
             '<div class="nsub">暂无屏蔽关键词</div><div class="kempty" style="padding-top:0">添加关键词后，包含该内容的弹幕将被自动过滤</div>') + '</div>')
    us = (f'<div class="ns">已屏蔽用户（{len(users)}）</div><div class="ncd" style="padding-top:12px">' + kchips(users, True, n=N(5), tag='add') + '</div>' if users else
          '<div class="ns">已屏蔽用户（0）</div><div class="ncd"><div class="kempty" style="padding-top:14px">还没有屏蔽的用户；长按弹幕可屏蔽发送者</div></div>')
    sim = (swr('启用相似弹幕过滤', sim_on, n=F(7), tag='add') + sl('相似度阈值', '85%', 70, dis=not sim_on) + sl('缓存时间', '3 秒', 3, dis=not sim_on)
           + sl('最大缓存数量', '100', 8, dis=not sim_on))
    flt = ('<div class="ns">平台弹幕过滤</div><div class="ncd">' + swr('过滤斗鱼疑似自动弹幕', False, '开启后按启发式标记隐藏疑似自动或活动弹幕，也可能隐藏普通聊天', n=F(6), tag='add') + '</div>'
           + '<div class="ns">相似弹幕过滤</div><div class="ncd">' + sim + '</div>')
    return f'<div class="n">{kw}{us}{flt}<div style="height:24px"></div></div>'


def v4_page(inner):
    return ln(inner)


V4BAR = bar('弹幕屏蔽')


OUT = {}
OUT['v3-shield'] = p(phone(v3_body(), V3BAR))
OUT['v3-shield-states'] = composite([
    (phone(v3_body([]), V3BAR), '还没有关键词'),
    (phone(v3_body(text='剧透', focus=True), V3BAR), '输入已有的“剧透”点添加：'),
    (phone(v3_body(), V3BAR), '……框被清空，列表不变，什么也不说'),
    (phone(v3_body(), V3BAR, '<div class="stoast" style="bottom:90px">请输入关键字</div>'), '空着点添加：提示'),
])
OUT['v3-shield-land'] = page('852x393@2', land(v3_body(), V3BAR), 'win', '--w:852px;--h:393px', css=CSS2)
OUT['v3-shield-wide'] = page('1280x800@1.5', wide(v3_body(), V3BAR), 'win', '--w:1280px;--h:800px', css=CSS2)

OUT['v4-shield'] = p(phone(v4_page(v4_block(n=True)), bar('弹幕屏蔽', n_back=1)))
OUT['v4-shield-full'] = page('393x1700@2 crop', bar('弹幕屏蔽') + v4_page(v4_block(sim_on=True, n_filters=True)), 'long', css=CSS2)
OUT['v4-shield-states'] = composite([
    (phone(v4_page(v4_block(keys=[], users=[])), V4BAR), '什么都还没屏蔽：两组都有说明'),
    (phone(v4_page(v4_block(field='剧透', err='“剧透”已经在屏蔽列表里')), V4BAR), '关键词已在列表里：直接说，不清空'),
    (phone(v4_page(v4_block(keys=KEYS[1:])), V4BAR, '<div class="toast2"><span>已移除“剧透”</span><b>撤销</b></div>'), '点 × 删除以后：可以撤销'),
])
OUT['v4-shield-land'] = page('852x393@2', land(v4_page(v4_block()), V4BAR), 'win', '--w:852px;--h:393px', css=CSS2)
OUT['v4-shield-wide'] = page('1280x800@1.5', wide(v4_page(v4_block(sim_on=True)), V4BAR), 'win', '--w:1280px;--h:800px', css=CSS2)

write(HERE, OUT)
