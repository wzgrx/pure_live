"""U.2h flying danmaku: v3 restored, v4 as it is now, and the new design.
Only the danmaku layer is the subject; the room around it follows U.2a/U.2c.

v3 look (tag v3.2.11): defaults danmaku_settings_controller.dart:7-16 (16 px,
weight 500, stroke 1.5, 120 px/s, opacity 1, area 1, top 0, bottom 0.5);
room config video_controller_panel.dart:781-813 (track height
fontSize x 1.55 clamped 24-64, emoji fontSize x 1.3); flame_barrage lane
height max(trackHeight, fontSize + 10) (scheduler/track_manager.dart:14), text
box height 1.15 (layout/mixed_layout.dart:280), text centred in the lane
(core/barrage_engine.dart:471-474); stroke drawn under the fill.
v4 now: apps/pure_live/lib/shared/danmaku/danmaku_overlay.dart (lane
1.4 x fontSize, line height 1.2, no emoticon pictures).
    python3 docs/ui/compare/U.2h/src/gen.py && python3 tools/ui/mock/render.py docs/ui/compare/U.2h/src/ --annotate"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
EMO = '../../../apps/pure_live/assets/emo/images/bilibili/{}.png'
CSS = '''
.x-layer{position:absolute;inset:0;overflow:hidden;z-index:3}
.x-dm{position:absolute;white-space:nowrap;font:500 16px/18.4px 'Noto Sans SC';display:flex;align-items:center}
.x-dm .t{position:relative;display:inline-block}
.x-dm .t b{font-weight:500}
.x-dm .t .s{position:absolute;left:0;top:0;color:transparent;-webkit-text-stroke:1.5px #000}
.x-dm .t .f{position:relative}
.x-dm img{width:20.8px;height:20.8px;vertical-align:middle}
.x-now .x-dm{line-height:19.2px}
.x-guide{position:absolute;left:0;right:0;border-top:1px dashed rgba(255,214,0,.55);z-index:2}
.x-lab{position:absolute;right:6px;z-index:4;font:600 10px 'Geist','Noto Sans SC';color:#FFE066;text-shadow:0 0 2px #000}
.v3h .nick{font-size:13px;line-height:18px}.v3h .area{font-size:12px;line-height:17px}
.x-fav{width:44px;height:44px;border-radius:22px;background:var(--pc);display:grid;place-items:center;color:var(--opc);margin-right:6px}
.x-rec{width:48px;height:48px;border-radius:12px;background:var(--schh);display:grid;place-items:center;color:var(--onv);margin-right:2px}
'''
mr = lambda n, s=24: f'<span class="mr" style="font-size:{s}px">{n}</span>'
mi = lambda n, s=24: f'<span class="mi" style="font-size:{s}px">{n}</span>'
rx = lambda c, s=24: f'<span class="rx" style="font-size:{s}px">&#x{c};</span>'

W = '#FFFFFF'
# (lane, x, text, colour); "[笑哭]" is a bilibili emoticon code (assets/emo/json/bilibili.json)
PORTRAIT = [(0, 196, '前排支持！', W), (1, 20, '这首歌好好听[笑哭]', W), (1, 268, '来了来了', W), (2, 128, '主播声音太温柔了', W),
            (3, -34, '晚风晚上好～', W), (3, 214, '可以点《晴天》吗', '#FFD100'), (4, 74, '打卡第 52 天，晚安前来听歌', W),
            (5, 8, '下一首想听《晚风》', W), (5, 300, '666', W), (6, 160, '这个混响调得真舒服', '#7FDBFF'), (7, 292, '晚上好', W)]
LAND = [(0, 360, '前排支持！', W), (1, 96, '这首歌好好听[笑哭]', W), (1, 560, '来了来了', W), (2, 250, '主播声音太温柔了', W),
        (3, -40, '晚风晚上好～', W), (3, 470, '可以点《晴天》吗', '#FFD100'), (4, 620, '666', W), (5, 140, '打卡第 52 天，晚安前来听歌', W),
        (6, 420, '这个混响调得真舒服', '#7FDBFF'), (7, 24, '下一首想听《晚风》', W), (7, 600, '今天也是被治愈的一天', W),
        (8, 300, '晚上好', W), (9, 700, '[笑哭][笑哭]', W), (10, 180, '上一首是什么歌？', W), (12, 520, '主播晚安', W)]


def dm(lane, x, text, colour, pitch, text_h, centred, emoticons, n=None):
    """One flying danmaku: the stroke copy under the fill (flame_barrage draws
    the stroke paragraph first)."""
    has_emo = '[笑哭]' in text and emoticons
    h = 20.8 if has_emo else text_h
    top = lane * pitch + ((pitch - h) / 2 if centred else 0)

    def run(s):
        if not emoticons:
            return f'<span class="t"><b class="s">{s}</b><b class="f" style="color:{colour}">{s}</b></span>'
        out, parts = '', s.split('[笑哭]')
        for i, p in enumerate(parts):
            if p:
                out += f'<span class="t"><b class="s">{p}</b><b class="f" style="color:{colour}">{p}</b></span>'
            if i < len(parts) - 1:
                out += f'<img src="{EMO.format("笑哭")}">'
        return out
    attr = f' data-n="{n}" data-tag="chg" data-at="tl"' if n else ''
    return f'<div class="x-dm" style="left:{x}px;top:{top:.1f}px;height:{h}px"{attr}>{run(text)}</div>'


def layer(items, pitch, text_h, centred, emoticons, guides=0, label=None, n_first=False):
    g = ''.join(f'<div class="x-guide" style="top:{i * pitch:.1f}px"></div>' for i in range(1, guides + 1))
    lab = f'<div class="x-lab" style="top:{pitch * 0.25:.0f}px">{label}</div>' if label else ''
    body = ''.join(dm(*it, pitch, text_h, centred, emoticons, n=(1 if n_first and i == 1 else None)) for i, it in enumerate(items))
    return f'<div class="x-layer">{g}{body}{lab}</div>'


def head(size):
    return (f'<!doctype html><html><head><meta charset="utf-8"><meta name="mock-size" content="{size}">'
            f'<link rel="stylesheet" href="kit/kit.css"><style>{CSS}</style></head><body>')


STATUS = '<div class="status"><span>21:36</span><span class="r"><span class="mi">signal_cellular_alt</span><span class="mi">wifi</span><span class="mi">battery_full</span></span></div>'


def v3_bar():
    return ('<div class="appbar v3h"><div class="back">' + mi('arrow_back') + '</div><span class="av" style="background-image:url(.cache/img/65.jpg)"></span>'
            '<div class="tt" style="margin-left:8px"><div class="nick">晚风</div><div class="area">哔哩哔哩 / 唱见电台</div></div>'
            '<div class="x-fav">' + mr('favorite_border', 22) + '</div><div class="x-rec">' + mr('radio_button_checked', 22) + '</div>'
            + '<div class="ib">' + rx('ea42') + '</div></div>')


def new_bar():
    return ('<div class="appbar"><div class="back">' + mi('arrow_back') + '</div><span class="av" style="background-image:url(.cache/img/65.jpg)"></span>'
            '<div class="tt"><div class="n">晚风</div><div class="s">哔哩哔哩 · 唱见电台</div></div>'
            '<div class="fol on">' + rx('eb7b') + '已关注</div><div class="recbtn"><span class="ring"><i></i></span></div>'
            + '<div class="ib" style="width:44px">' + rx('ea42') + '</div></div>')


def portrait(kind):
    """Status bar, app bar and the 16:9 picture (393 x 221) with the
    controls hidden, which is how danmaku are watched."""
    if kind == 'now':
        lay = layer(PORTRAIT, 22.4, 19.2, False, False, guides=9, label='轨道 22.4')
        lay = lay.replace('class="x-layer"', 'class="x-layer x-now"', 1)
    else:
        lay = layer(PORTRAIT, 26, 18.4, True, True, guides=8 if kind == 'v3' else 0, label='轨道 26' if kind == 'v3' else None,
                    n_first=kind == 'v4')
    bar = v3_bar() if kind == 'v3' else new_bar()
    return (head('393x313@3') + f'<div class="ph" style="height:313px">{STATUS}{bar}'
            f'<div class="video" style="background-image:url(.cache/img/158.jpg)">{lay}</div>'
            '<div class="syn" style="top:292px;left:auto;right:6px;transform:none">示意图片</div></div></body></html>')


def land(kind):
    lay = layer(LAND, 26, 18.4, True, True, guides=15 if kind == 'v3' else 0, label='轨道 26 · 共 15 条' if kind == 'v3' else None,
                n_first=kind == 'v4')
    return (head('852x393@2') + f'<div class="fs" style="--w:852px;--h:393px;background-image:url(.cache/img/158.jpg);background-position:center 55%">'
            f'<div class="syn" style="top:auto;bottom:8px;left:auto;right:8px;transform:none">示意图片</div>{lay}</div></body></html>')


OUT = {
    'v3-portrait': portrait('v3'), 'now-portrait': portrait('now'), 'v4-portrait': portrait('v4'),
    'v3-land': land('v3'), 'v4-land': land('v4'),
}
if __name__ == '__main__':
    for name, html in OUT.items():
        open(os.path.join(HERE, name + '.html'), 'w', encoding='utf-8').write(html)
    print(len(OUT), 'pages')
