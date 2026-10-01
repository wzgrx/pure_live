"""U.12c tag management mockups: v3 restored and the new design.

v3 (tag v3.2.11): lib/modules/tags/tag_management_page.dart (tip :345-371,
cards :67-157, grid :159-210, details :277-343, delete :386-430, editor
:442-736). Tag names, descriptions and room counts are examples.
    python3 docs/ui/compare/U.12c/src/gen.py && python3 tools/ui/mock/render.py docs/ui/compare/U.12c/src/ --annotate"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from skit import *  # noqa: E402,F401,F403
from skit import composite as _composite  # noqa: E402

CSS2 = '''
.tip3{display:flex;gap:12px;padding:12px 16px;border-radius:16px;background:rgba(54,97,142,.05);font-size:13px;line-height:1.4;color:rgba(67,71,78,.8)}
.tip3 .rx{color:rgba(54,97,142,.8);font-size:18px}
.tg3{border-radius:16px;background:rgba(83,95,112,.08);box-shadow:inset 0 0 0 1px rgba(83,95,112,.3);padding:12px 12px 4px;display:flex;flex-direction:column}
.tg3 .n{min-height:48px;display:flex;align-items:center;font-size:14px;font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.tg3 .d{font-size:11px;color:rgba(0,0,0,.38);line-height:1.3;margin-top:4px;min-height:28px;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden}
.tg3 .d.e{color:rgba(0,0,0,.15);font-style:italic}
.tg3 .bar3{margin:6px 0 8px;padding:0 8px;border-radius:10px;background:rgba(236,238,244,.5);display:flex;align-items:center;height:48px}
.tg3 .bar3 span{flex:1;display:grid;place-items:center}
.tg3 .bar3 i{width:1px;height:14px;background:rgba(0,0,0,.06)}
.grid3{display:grid;gap:12px}
.empty3{text-align:center;padding-top:32px;color:rgba(0,0,0,.38);font-size:14px;line-height:1.5;white-space:pre-line}
.lab12{font-size:12px;font-weight:700;color:var(--primary)}
.lab12g{font-size:12px;color:rgba(67,71,78,.6)}
.tf4{height:52px;border-radius:12px;box-shadow:inset 0 0 0 1px var(--outline);background:var(--scl);display:flex;align-items:center;padding:0 4px 0 12px;font-size:15px;margin-top:6px}
.tf4 .x{flex:1}.tf4 .ph2{color:rgba(67,71,78,.6)}
.tf4.foc{box-shadow:inset 0 0 0 2px var(--primary)}.tf4.bad{box-shadow:inset 0 0 0 2px var(--error)}
.tf4 .c{width:44px;height:44px;display:grid;place-items:center;color:var(--onv)}
/* new list */
.trow{display:flex;align-items:center;padding:6px 4px 6px 0;min-height:76px}
.trow .h{width:44px;height:48px;display:grid;place-items:center;color:var(--onv);flex:none}
.trow .x{flex:1;min-width:0}
.trow .t{font-size:15px;font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.trow .s{font-size:12px;color:var(--onv);line-height:1.4;margin-top:2px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.trow .s.e{font-style:italic;opacity:.7}
.trow .c{font-size:12px;color:var(--primary);margin-top:2px;display:flex;align-items:center;gap:4px}
.trow .b{width:44px;height:48px;display:grid;place-items:center;flex:none}
.trow .b.dis{opacity:.38}
.tcard{background:var(--scl);border-radius:16px;margin:0 12px 8px}
.tcard.lift{box-shadow:0 8px 20px rgba(0,0,0,.18);background:var(--surface);transform:translateY(-4px) scale(1.02)}
.gap{height:76px;margin:0 12px 8px;border-radius:16px;box-shadow:inset 0 0 0 2px dashed var(--ov);border:2px dashed var(--ov)}
'''


def composite(phones, **kw):
    return _composite(phones, css=CSS2, **kw)


def p(html):
    return page('393x852@3', html, css=CSS2)


TAGS = [('常看', '每天都会看的直播间', 12), ('音乐', '唱歌、电台、点歌', 8), ('游戏', '', 15), ('户外', '旅行、徒步、钓鱼', 4), ('学习', '读书、自习室', 3)]


# ---------------------------------------------------------------- v3
def v3_card(i, name, desc, _):
    pin = rx('f038' if i == 0 else 'f039', 16, 'var(--primary)')
    d = f'<div class="d">{desc}</div>' if desc else '<div class="d e">暂无描述</div>'
    return (f'<div class="tg3"><div class="n">{name}</div>{d}<div class="bar3"><span>{pin}</span><i></i><span>{rx("ec86", 16, "var(--onv)")}</span><i></i>'
            f'<span>{rx("ec2a", 16, "rgba(186,26,26,.7)")}</span></div></div>')


def v3_body(tags=TAGS, cols=1):
    tip = f'<div class="tip3">{rx("ee59")}<span>长按任意标签卡片，即可自由拖拽以动态调整它们的排列展示顺序。</span></div><div style="height:12px"></div>'
    if not tags:
        grid = '<div class="empty3">' + rx('f023', 48, 'rgba(0,0,0,.15)') + '<div style="height:16px"></div>暂无自定义标签。\n点击右上角 “+” 按钮即可创建。</div>'
    else:
        tmpl = f'repeat({cols},minmax(0,1fr))'
        grid = f'<div class="grid3" style="grid-template-columns:{tmpl}">' + ''.join(v3_card(i, *t) for i, t in enumerate(tags)) + '</div>'
    return l3(tip + g3('标签管理') + grid)


V3BAR = bar('标签管理', act(rx('ea13')) + '<div style="width:4px"></div>')


def v3_details():
    return ('<div class="dim"></div><div class="dlg2" style="top:250px;border-radius:20px"><h3 style="font-size:16px;font-weight:700">标签详情</h3>'
            '<div style="margin-top:16px"><div class="lab12">标签名称</div><div style="font-size:16px;font-weight:600;margin-top:6px">常看</div>'
            '<div class="lab12g" style="margin-top:18px">备注描述</div><div style="margin-top:6px;padding:12px;border-radius:12px;background:rgba(225,226,232,.2);font-size:14px;color:var(--onv)">每天都会看的直播间</div></div>'
            '<div class="acts"><span class="sq" style="border-radius:10px;font-weight:700">确认</span></div></div>')


def v3_editor(edit=False, err=None):
    nm = '常看' if edit else ''
    return ('<div class="dim"></div><div class="dlg2" style="top:200px"><h3>' + ('编辑标签' if edit else '添加标签') + '</h3><div style="margin-top:20px">'
            '<div class="lab12">标签名称</div>'
            f'<div class="tf4{" bad" if err else " foc"}"><span class="x{"" if nm else " ph2"}">{nm or "请输入标签名称..."}</span>' + (f'<span class="c">{mi("clear", 18)}</span>' if nm else '') + '</div>'
            + (f'<div class="fh err" style="padding-left:12px">{err}</div>' if err else '')
            + '<div class="lab12g" style="margin-top:16px">备注描述</div>'
            '<div class="tf4"><span class="x ph2">请输入备注/描述（可选）...</span></div></div>'
            '<div class="acts"><span style="color:var(--onv)">取消</span><span class="sq">确认</span></div></div>')


def v3_delete():
    return ('<div class="dim"></div><div class="dlg2" style="top:300px"><h3>删除标签</h3><div class="c">确定要永久删除标签“游戏”吗？</div>'
            '<div class="acts"><span class="big">取消</span><span class="err big">删除</span></div></div>')


# ---------------------------------------------------------------- new
def v4_row(i, name, desc, rooms, n=False, lift=False, dis=False):
    N = (lambda k, t: (k, t)) if n and i == 0 else (lambda k, t: (None, None))
    k1, t1 = N(2, 'chg')
    k2, t2 = N(3, 'chg')
    k3, t3_ = N(4, 'keep')
    k4, t4 = N(5, 'keep')
    k5, t5 = N(6, 'keep')
    d = f'<div class="s">{desc}</div>' if desc else '<div class="s e">暂无描述</div>'
    pin = f'<span class="b"{dn(k3, t3_)}>{rx("f038" if i == 0 else "f039", 20, "var(--primary)")}</span>'
    return (f'<div class="tcard{" lift" if lift else ""}"><div class="trow"{dn(k2, t2, "tl")}><span class="h"{dn(k1, t1, "bl")}>{mr("drag_indicator")}</span>'
            f'<div class="x"><div class="t">{name}</div>{d}<div class="c">{mr("live_tv", 13)}{rooms} 个直播间</div></div>'
            f'{pin}<span class="b"{dn(k4, t4)}>{rx("ec86", 20, "var(--onv)")}</span><span class="b"{dn(k5, t5)}>{rx("ec2a", 20, "var(--error)")}</span></div></div>')


def v4_body(tags=TAGS, n=False, drag=None):
    tip = '<div class="hint" style="padding:8px 20px 12px">拖动左侧把手调整顺序（手机上也可以长按卡片拖动），关注页的标签栏按这个顺序显示。点卡片查看详情。</div>'
    if not tags:
        body = (f'<div class="sv" style="height:600px"><div class="svc">{rx("f023")}</div><h4>暂无自定义标签。</h4>'
                '<p>标签用来给关注的直播间分组：在直播间卡片的菜单里给直播间加标签，关注页可以按标签筛选。</p>'
                f'<div class="acts"><span class="fb">{mr("add", 18)}添加标签</span></div></div>')
        return ln(body)
    rows = ''
    for i, t in enumerate(tags):
        if drag is not None and i == drag:
            rows += '<div class="gap"></div>'
            continue
        rows += v4_row(i, *t, n=n)
    if drag is not None:
        lifted = v4_row(drag, *tags[drag], lift=True)
        rows = rows.replace('<div class="gap"></div>', '<div style="position:relative"><div class="gap"></div><div style="position:absolute;left:0;right:0;top:-46px;z-index:5">' + lifted + '</div></div>')
    return ln(tip + rows)


def v4_bar(n=False):
    return bar('标签管理', act(mr('add'), 1 if n else None, 'keep') + '<div style="width:4px"></div>', n_back=None)


def v4_details():
    return ('<div class="dim"></div><div class="dlg2" style="top:230px"><h3>标签详情</h3>'
            '<div style="margin-top:16px"><div class="lab12">标签名称</div><div style="font-size:16px;font-weight:600;margin-top:6px">常看</div>'
            '<div class="lab12" style="margin-top:16px">备注描述</div><div style="margin-top:6px;padding:12px;border-radius:12px;background:var(--scl);font-size:14px">每天都会看的直播间</div>'
            '<div class="lab12" style="margin-top:16px">关注中带此标签的直播间</div><div style="font-size:14px;margin-top:6px">12 个直播间</div></div>'
            '<div class="acts"><span>编辑标签</span><span class="fb2">关闭</span></div></div>')


def v4_editor(edit=False, err=None, top=200):
    nm = '音乐' if err else ('常看' if edit else '')
    return ('<div class="dim"></div><div class="dlg2" style="top:' + str(top) + 'px"><h3>' + ('编辑标签' if edit else '添加标签') + '</h3><div style="margin-top:16px">'
            f'<div class="fld{" bad" if err else " foc"}" style="background:var(--sch)"><span class="lab">标签名称</span><span class="x{"" if nm else " ph2"}">{nm or "请输入标签名称..."}</span>'
            + (mi('clear', 20) if nm else '') + '</div>'
            + (f'<div class="fh err">{err}</div>' if err else f'<div class="fh" style="text-align:right">{len(nm)}/15</div>')
            + '<div class="fld" style="background:var(--sch);margin-top:12px"><span class="lab">备注描述</span><span class="x ph2">请输入备注/描述（可选）...</span></div>'
            '<div class="fh" style="text-align:right">0/40</div></div>'
            '<div class="acts"><span>取消</span><span class="fb2">确认</span></div></div>')


def v4_delete():
    return ('<div class="dim"></div><div class="dlg2" style="top:290px"><h3>删除标签</h3><div class="c v4">确定要永久删除标签“游戏”吗？<br>15 个关注的直播间会移除这个标签，关注本身不受影响。</div>'
            '<div class="acts"><span>取消</span><span class="err">删除</span></div></div>')


OUT = {}
OUT['v3-tags'] = p(phone(v3_body(), V3BAR))
OUT['v3-tags-states'] = composite([
    (phone(v3_body([]), V3BAR), '没有标签'),
    (phone(v3_body(), V3BAR, v3_details()), '点名字：标签详情'),
    (phone(v3_body(), V3BAR, v3_editor()), '右上角 +：添加标签'),
    (phone(v3_body(), V3BAR, v3_delete()), '删除：不说影响几个直播间'),
])
OUT['v3-tags-land'] = page('852x393@2', land(v3_body(cols=5), V3BAR), 'win', '--w:852px;--h:393px', css=CSS2)
OUT['v3-tags-wide'] = page('1280x800@1.5', wide(v3_body(cols=6), V3BAR), 'win', '--w:1280px;--h:800px', css=CSS2)

V4BAR = v4_bar()
OUT['v4-tags'] = p(phone(v4_body(n=True), v4_bar(True)))
OUT['v4-tags-states'] = composite([
    (phone(v4_body([]), V4BAR), '没有标签：说标签是干什么的'),
    (phone(v4_body(drag=1), V4BAR), '拖动排序：把手或长按'),
    (phone(v4_body(), V4BAR, v4_details()), '点卡片：详情，可直接编辑'),
    (phone(v4_body(), V4BAR, v4_editor(err='已存在同名标签')), '添加：名字重复'),
    (phone(v4_body(), V4BAR, v4_delete()), '删除：说影响几个直播间'),
])
OUT['v4-tags-land'] = page('852x393@2', land(v4_body(), V4BAR), 'win', '--w:852px;--h:393px', css=CSS2)
OUT['v4-tags-wide'] = page('1280x800@1.5', wide(v4_body(), V4BAR, '<div class="tip" style="left:300px;top:150px">拖动排序</div>'),
                           'win', '--w:1280px;--h:800px', css=CSS2)

write(HERE, OUT)
