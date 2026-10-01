"""U.2i refresh rate and frame-rate matching (Android): the settings rows and a
diagram of which rate is used when.
v3 (tag v3.2.11): general_settings_page.dart:24-39 (row), :173-209 (texts);
common/widgets/adaptive_refresh_rate_scope.dart (policy);
android/app/src/main/kotlin/com/mystyle/pure_live/MainActivity.kt:304-377.
The refresh-rate row and dialog are U.6d's confirmed design (d3, d4); this
task adds one switch and the playback policy.
    python3 docs/ui/compare/U.2i/src/gen.py && python3 tools/ui/mock/render.py docs/ui/compare/U.2i/src/ --annotate"""
import os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from smock import *  # noqa: E402,F401,F403

EXTRA = '''
.board .scr.lt{background:var(--surface);padding:8px 0 16px;display:block}
.pol{padding:28px 32px 32px;background:var(--surface);width:1290px}
.pol h3{font-size:20px;font-weight:600;margin-bottom:4px}
.pol .sub{font-size:14px;color:var(--onv);margin-bottom:18px}
.tl{display:flex;gap:6px;align-items:stretch;margin-bottom:8px}
.tl .st{flex:1;border-radius:12px;padding:10px 12px;background:var(--scl);box-shadow:inset 0 0 0 1px var(--ov);min-width:0}
.tl .st .w{font-size:13px;color:var(--onv);line-height:1.45}
.tl .st .hz{font:600 22px/1.3 'Geist','Noto Sans SC';font-feature-settings:'tnum';margin-top:6px}
.tl .st .why{font-size:12px;color:var(--onv);line-height:1.45;margin-top:2px}
.tl .st.x-hi{background:var(--pc);box-shadow:none}.tl .st.x-hi .hz{color:var(--opc)}
.tl .st.x-sys{background:var(--sch)}
.tl .ar{display:grid;place-items:center;color:var(--outline);flex:none;width:14px}
.tbl{width:100%;border-collapse:separate;border-spacing:0;margin-top:22px;font-size:14px}
.tbl th{text-align:left;font-weight:600;padding:10px 12px;background:var(--sch);border-bottom:1px solid var(--ov)}
.tbl th:first-child{border-radius:12px 0 0 0}.tbl th:last-child{border-radius:0 12px 0 0}
.tbl td{padding:10px 12px;border-bottom:1px solid var(--ov);vertical-align:top;line-height:1.5;background:var(--scl)}
.tbl td:first-child{font-weight:600;width:210px}
.tbl .hz{font:600 15px 'Geist','Noto Sans SC';font-feature-settings:'tnum'}
.tbl .new{display:inline-block;font-size:11px;font-weight:600;padding:1px 6px;border-radius:6px;background:var(--okbg);color:var(--ok);margin-left:6px;vertical-align:1px}
.foot{font-size:13px;color:var(--onv);margin-top:14px;line-height:1.6}
'''


def P(w, h, s, body, **k):
    return page(w, h, s, body, extra_css=EXTRA, **k)


RR = {
    'ps': '省电（默认）', 'ps_d': '界面由系统动态调度；主画面弹幕上限 60 FPS，小窗弹幕上限 30 FPS，适合长时间观看。',
}
MATCH = '播放时匹配视频帧率'
MATCH_D = '看直播时让屏幕刷新率是视频帧率的整数倍（30、60 帧用 60 或 120 Hz），画面更匀；只在不闪屏时切换'


def settings():
    v3 = v3gt('通用') + v3card([v3tile(rx('f371', 22), '界面刷新率', f'{RR["ps"]} · {RR["ps_d"]} · 60 / 120 Hz', 'chev24', long=True)])
    new = sec('显示') + grp([link('界面刷新率', '当前 60 Hz，最高 120 Hz', '省电', 1, 'keep'),
                            sw(MATCH, MATCH_D, True, 2, 'add')])
    single = sec('显示') + grp([link('界面刷新率', '当前 60 Hz，最高 60 Hz', '省电', None),
                               sw(MATCH, MATCH_D, False, dis=True, why='这台设备只有 60 Hz，用不上')])
    cells = [('v3：设置 → 通用（Android）', f'<div class="v3body" style="padding:8px 16px 0">{v3}</div>'),
             ('新设计：设置 → 通用 → 显示（行的样子照 U.6d）', new),
             ('新设计：只有一个刷新率的设备', single)]
    inner = ''.join(f'<div class="cell"><div class="cap">{c}</div><div class="scr lt">{h}</div></div>' for c, h in cells)
    return P(1290, 1200, 1.5, f'<div class="board" style="width:1290px">{inner}</div>', crop=True, frame='none')


def step(what, hz, why, cls=''):
    return f'<div class="st {cls}"><div class="w">{what}</div><div class="hz">{hz}</div><div class="why">{why}</div></div>'


AR = '<div class="ar">' + mr('chevron_right', 20) + '</div>'


def policy():
    tl = AR.join([
        step('首页、列表', '系统决定', '均衡档：按住、滚动时 120，停 1.5 秒交还系统（照 v3）', 'x-sys'),
        step('进直播间，开始播放（视频 60 帧）', '60 Hz', '声明内容帧率 60，系统选 60 或 120', 'x-hi'),
        step('拖面板、滚弹幕列表', '120 Hz', '60 的整数倍里最高；停 1.5 秒回 60', 'x-hi'),
        step('暂停', '系统决定', '清除声明；继续播放再声明', 'x-sys'),
        step('画中画', '60 Hz', '画面还在播，保持声明', 'x-hi'),
        step('退出直播间、进后台', '系统决定', '清除声明，释放高刷', 'x-sys'),
    ])
    rows = [
        ('首页、列表、设置（不在直播间）', '系统决定', '按住、滚动时最高；停 1.5 秒交还系统', '一直最高', '照 v3'),
        ('直播间播放中，30 或 60 帧', '声明 60<span class="new">新</span>', '60；拖面板、滚列表时 120', '120<span class="new">新</span>', '不用 90、144：60 帧在上面停留时间不均'),
        ('直播间播放中，25 或 50 帧', '声明 50<span class="new">新</span>', '有 50 或 100 Hz 才用，否则同 30/60 帧', '100（没有就用最高）', '只在不闪屏时切换'),
        ('直播间播放中，24 帧', '声明 24<span class="new">新</span>', '有 48、72 或 120 Hz 才用', '整数倍里最高', '大多是回放、点播'),
        ('帧率还没读到（刚开播、音频）', '系统决定', '同列表', '最高', '不声明'),
        ('暂停、退出直播间、进后台', '清除声明', '清除声明', '清除声明（回到一直最高）；后台释放', '照 v3：进后台释放'),
        ('画中画', '保持声明', '保持', '保持', '照 v3：画中画不释放'),
    ]
    body = ''.join(f'<tr><td>{a}</td><td>{b}</td><td>{c}</td><td>{d}</td><td>{e}</td></tr>' for a, b, c, d, e in rows)
    html = (f'<div class="pol"><h3>什么时候用哪个刷新率（Android，以 60 / 120 Hz 的手机为例）</h3>'
            '<div class="sub">上面一条是“均衡”档看一次直播的过程；下面是三档在各种情况下的做法。“播放时匹配视频帧率”关掉时，直播间里和列表一样（照 v3）。</div>'
            f'<div class="tl">{tl}</div>'
            '<table class="tbl"><tr><th>情况</th><th>省电（默认）</th><th>均衡</th><th>最高（设备上限）</th><th>说明</th></tr>'
            f'{body}</table>'
            '<div class="foot">“声明”指告诉系统画面里是固定帧率的视频（Android 11 起），系统在不闪屏的前提下选它的整数倍；Android 6～10 只能改“希望的刷新率”，改成整数倍里最高的那一档。'
            '弹幕每个刷新周期都动（U.2h），刷新率变了速度不变。</div></div>')
    return P(1290, 1400, 1.5, html, crop=True, frame='none')


OUT = {'v4-settings': settings(), 'v4-policy': policy()}
if __name__ == '__main__':
    for name, html in OUT.items():
        open(os.path.join(HERE, name + '.html'), 'w', encoding='utf-8').write(html)
    print(len(OUT), 'pages')
