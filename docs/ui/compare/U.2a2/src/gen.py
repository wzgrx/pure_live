"""U.2a2 record button and recording states, redesigned (cloud task B04, audit A-02).

The user (problem 02): "录制的按钮图标需要重新优化设计一下，现在这个看起来像在录制……让人从图标就可以明显看出来".

v3 (tag v3.2.11): lib/modules/live_play/widgets/button/record_action_button.dart:40-104 and
  record_action_content.dart: idle Remix.record_circle_line (onSurfaceVariant on surfaceContainerHighest,
  a 48 square with radius 12), a task "已监控" checkbox_circle_fill (primary), running, reconnecting and
  preparing record_circle_fill (redAccent on red 12 %).
Now (4.0.0): packages/live_ui/lib/src/widgets/record_glyph.dart (idle: grey ring around a RED dot;
  recording: red disc, blinking white dot, halo), apps/pure_live/lib/features/live_play/buttons/
  record_button.dart and player/recording_badge.dart switch on RecordStatus.isActive, so preparing and
  joining (processing) look like recording ("● 录制中").
New design: one glyph in seven states (idle, waiting, preparing, recording, reconnecting, processing,
  failed), drawn here as inline SVG with the geometry RecordGlyph paints in the app (a 24 box).

    python3 docs/ui/compare/U.2a2/src/gen.py && python3 tools/ui/mock/render.py docs/ui/compare/U.2a2/src/ --annotate
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
RED = '#D92D20'
CSS = '''
:root{--amber:#915600;--onError:#FFFFFF;--warnbg2:#FFF4E5}
[data-theme=dark]{--amber:#FFB95C;--onError:#690005}
.gl{display:block;flex:none;overflow:visible}
.col{display:flex;flex-direction:column}
.vbox{position:relative;width:100%;aspect-ratio:16/9;background:#000;overflow:hidden;flex:none}
.pic{position:absolute;inset:0;background:#000 center 55%/cover}
.dm{font-size:16px}
.vtop .rb{margin-top:0}
/* v3 */
.v3tt{margin-left:8px;flex:1;min-width:0;font-size:11px;line-height:16px;font-weight:400;white-space:nowrap;overflow:hidden}
.v3tt div{overflow:hidden;text-overflow:ellipsis}
.v3heart{width:40px;height:40px;border-radius:20px;background:var(--sc);color:var(--osc);display:grid;place-items:center;margin:0 5px 0 2px;flex:none}
.v3rec{width:48px;height:48px;border-radius:12px;background:var(--schh);color:var(--onv);display:grid;place-items:center;flex:none}
.v3rec.mon{background:rgba(54,97,142,.10);color:var(--primary)}
.v3rec.run{background:rgba(255,82,82,.12);color:#FF5252}
/* the room bar */
.recbtn{width:48px}
.pillrec{height:36px;border-radius:18px;display:flex;align-items:center;gap:8px;padding:0 14px;background:var(--sc);color:var(--osc);font-size:14px;font-weight:600;flex:none;margin:0 4px}
.tonal{width:40px;height:40px;border-radius:20px;background:var(--sc);display:grid;place-items:center;margin:0 4px;flex:none}
/* on the picture */
.mk{display:inline-flex;align-items:center;gap:5px;height:24px;padding:0 9px 0 7px;border-radius:12px;font:600 12px 'Noto Sans SC';font-feature-settings:'tnum';color:#fff;white-space:nowrap;flex:none}
.mk.rec{background:#D92D20}.mk.rec i{width:7px;height:7px;border-radius:4px;background:#fff}
.mk.dim{background:rgba(0,0,0,.6);padding-left:5px}
.mkpos{position:absolute;left:12px;z-index:6}
.rt{color:#fff;font:600 14px 'Geist','Noto Sans SC';font-feature-settings:'tnum';text-shadow:0 1px 3px rgba(0,0,0,.6)}
.rbt{height:48px;display:flex;align-items:center;gap:6px;padding:0 10px 0 12px;flex:none}
.vfol{height:32px;border-radius:16px;display:flex;align-items:center;gap:3px;padding:0 12px 0 9px;font-size:13px;font-weight:500;background:rgba(255,255,255,.18);color:#fff;margin:0 4px 8px;flex:none}.vfol .rx{font-size:16px}
.comp{flex:1;max-width:420px;height:40px;border-radius:20px;background:rgba(0,0,0,.54);border:1px solid rgba(255,255,255,.24);display:flex;align-items:center;color:rgba(255,255,255,.6);font-size:13px;white-space:nowrap;overflow:hidden;min-width:0}
.comp .a{width:40px;display:grid;place-items:center;color:#FFD166;flex:none}.comp .s{margin-left:auto;width:40px;display:grid;place-items:center;color:#fff;flex:none}
.fs .vtop .time{margin:14px 6px 0 2px}.fs .vtop .bat{margin:16px 8px 0 0}
.lock{position:absolute;right:20px;top:50%;transform:translateY(-50%);width:50px;height:50px;border-radius:25px;background:rgba(0,0,0,.38);display:grid;place-items:center;color:#fff;z-index:6}
/* sheets */
.xs{background:var(--surface);padding:14px 16px 18px}
.h2{font-size:15px;font-weight:600;margin:4px 2px 10px}
.h2 small{font-weight:400;color:var(--onv);margin-left:6px;font-size:12px}
.lab{font-size:13px;color:var(--onv);padding:12px 18px 6px}
.lab b{color:var(--on);font-weight:600}
.lab .bad{color:var(--error);font-weight:600}
.lab .ok{color:var(--ok);font-weight:600}
.bar{border-top:1px solid var(--ov);border-bottom:1px solid var(--ov)}
.strip{position:relative;height:64px;background:#000 center 30%/cover;overflow:hidden}
.strip::before{content:'';position:absolute;inset:0;background:linear-gradient(180deg,rgba(0,0,0,.6),rgba(0,0,0,.25))}
.strip>*{position:relative}
/* glyph sheet */
table.gs{border-collapse:collapse;width:100%}
.gs th{font-size:12px;font-weight:600;color:var(--onv);text-align:left;padding:6px 8px;border-bottom:1px solid var(--ov);white-space:nowrap}
.gs td{padding:8px;border-bottom:1px solid var(--ov);vertical-align:middle;font-size:12.5px;line-height:1.5}
.gs td.nm{font-size:14px;font-weight:600;white-space:nowrap}
.gs td.nm small{display:block;font-size:11px;font-weight:400;color:var(--onv);font-family:'Geist',monospace}
.cell{display:grid;place-items:center;width:56px;height:56px;border-radius:10px;background:var(--surface);box-shadow:inset 0 0 0 1px var(--ov)}
.cell.dk{background:#1b1f26;box-shadow:none}
.cell.big{width:112px;height:112px}
.cell.big.grid{background-image:linear-gradient(rgba(127,127,127,.12) 1px,transparent 1px),linear-gradient(90deg,rgba(127,127,127,.12) 1px,transparent 1px);background-size:4px 4px}
.redq{display:inline-block;min-width:22px;padding:1px 6px;border-radius:6px;font-size:11px;font-weight:600;text-align:center}
.redq.no{background:var(--sch);color:var(--onv)}.redq.yes{background:#D92D20;color:#fff}
.frames{display:flex;gap:10px;align-items:center}
.frames span{font-size:11px;color:var(--onv);text-align:center}
/* matrix */
table.mx{border-collapse:separate;border-spacing:0;width:100%}
.mx th{font-size:13px;font-weight:600;text-align:left;padding:8px 10px;color:var(--on);background:var(--scc);white-space:nowrap}
.mx th small{display:block;font-weight:400;font-size:11px;color:var(--onv)}
.mx td{padding:10px;border-bottom:1px solid var(--ov);vertical-align:middle}
.mx td.nm{font-size:15px;font-weight:600;white-space:nowrap}
.mx td.nm small{display:block;font-size:11px;font-weight:400;color:var(--onv);font-family:'Geist',monospace}
.mbar{display:flex;align-items:center;height:56px;background:var(--surface);border-radius:10px;box-shadow:inset 0 0 0 1px var(--ov);padding:0 4px 0 8px;width:250px}
.mbar .ib,.appbar .ib{color:var(--onv)}
.mbar .sp{flex:1}
.mbar.narrow{width:150px}
.mvid{position:relative;height:56px;border-radius:10px;overflow:hidden;background:#000 center 40%/cover;width:300px;display:flex;align-items:center;gap:10px;padding:0 10px}
.mvid::before{content:'';position:absolute;inset:0;background:rgba(0,0,0,.45)}
.mvid>*{position:relative}
.mvid .cap{font-size:11px;color:rgba(255,255,255,.75)}
.mfs{position:relative;height:56px;border-radius:10px;overflow:hidden;background:#000 center 40%/cover;width:236px;display:flex;align-items:center;justify-content:flex-end;padding:0 4px}
.mfs::before{content:'';position:absolute;inset:0;background:linear-gradient(180deg,rgba(0,0,0,.6),rgba(0,0,0,.35))}
.mfs>*{position:relative}
.none{font-size:12px;color:var(--onv)}
.mcard{display:flex;align-items:center;gap:8px;height:44px;border-radius:10px;padding:0 12px;width:236px;font-size:14px;font-weight:600}
.mcard .me{margin-left:auto;font-size:11px;font-weight:400;color:var(--onv);font-feature-settings:'tnum'}
.mcard.neutral{background:var(--sch)}
.mcard.red{background:var(--recbg);box-shadow:inset 0 0 0 1px rgba(217,45,32,.3);color:#B3261E}
.mcard.yellow{background:var(--warnbg);box-shadow:inset 0 0 0 1px rgba(145,86,0,.3);color:var(--amber)}
.mcard.error{background:#FBEBEA;box-shadow:inset 0 0 0 1px rgba(186,26,26,.3);color:var(--error)}
[data-theme=dark] .mcard.error{background:#3A1F1E}
[data-theme=dark] .mcard.red{color:#FFB4AB}
.mnot{display:flex;align-items:center;gap:8px;height:44px;border-radius:10px;background:#1b1f26;color:#fff;padding:0 12px;width:210px;font-size:12px}
.mnot .tx{white-space:nowrap;overflow:hidden;text-overflow:ellipsis;color:rgba(255,255,255,.85)}
/* status cards (U.2f, full size) */
.sb{border-radius:16px;padding:14px 16px 16px;margin-bottom:12px}
.sb.neutral{background:var(--sch)}
.sb.red{background:var(--recbg);box-shadow:inset 0 0 0 1px rgba(217,45,32,.3)}
.sb.yellow{background:var(--warnbg);box-shadow:inset 0 0 0 1px rgba(145,86,0,.3)}
.sb.green{background:var(--okbg);box-shadow:inset 0 0 0 1px rgba(27,114,54,.3)}
.sb.error{background:#FBEBEA;box-shadow:inset 0 0 0 1px rgba(186,26,26,.3)}
[data-theme=dark] .sb.error{background:#3A1F1E}
.sh{display:flex;align-items:center;gap:8px;min-height:22px}
.sh .ic{width:22px;height:22px;display:grid;place-items:center;flex:none}
.sh .tt{display:block;font-size:16px;font-weight:600;flex:1;min-width:0;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.sh .me{font-size:12px;color:var(--onv);font-feature-settings:'tnum';flex:none}
.red .sh .tt{color:#B3261E}.yellow .sh .tt{color:var(--amber)}.green .sh .tt,.green .sh .ic{color:#1B7236}.error .sh .tt{color:var(--error)}
[data-theme=dark] .red .sh .tt{color:#FFB4AB}[data-theme=dark] .green .sh .tt,[data-theme=dark] .green .sh .ic{color:#6FDD8B}
.sd{margin-top:8px;font-size:14px;line-height:1.5;color:var(--onv);font-feature-settings:'tnum'}
.clock{font:600 36px/1.2 'Geist','Noto Sans SC';font-feature-settings:'tnum';margin-top:8px}
.chips{display:flex;flex-wrap:wrap;gap:8px;margin-top:8px}
.chips span{height:28px;padding:0 10px;border-radius:8px;background:var(--surface);font-size:14px;display:flex;align-items:center;font-feature-settings:'tnum'}
.lin{height:4px;border-radius:2px;background:rgba(127,127,127,.25);margin-top:10px;position:relative}.lin i{position:absolute;left:0;top:0;bottom:0;border-radius:2px;background:var(--primary)}
.bt{display:flex;gap:12px;margin-top:12px}
.bt>div{flex:1;height:48px;border-radius:24px;display:flex;align-items:center;justify-content:center;gap:8px;font-size:15px;font-weight:600;white-space:nowrap}
.bt .go{background:#D92D20;color:#fff}.bt .go i{width:8px;height:8px;border-radius:4px;background:#fff}
.bt .stop{background:var(--surface);color:#B3261E;box-shadow:inset 0 0 0 1.5px #D92D20}.bt .stop i{width:10px;height:10px;border-radius:2px;background:#B3261E}
.bt .pl{background:var(--surface);color:var(--primary);box-shadow:inset 0 0 0 1px var(--ov)}
.bt .er{background:#D92D20;color:#fff}
.cap2{font-size:13px;font-weight:600;color:var(--onv);margin:2px 2px 6px}
/* recording centre (U.7a, compact card) */
.ab{height:56px;display:flex;align-items:center;position:relative;flex:none;background:var(--surface)}
.ab .ttl{position:absolute;left:0;right:0;text-align:center;font-size:20px;font-weight:600;pointer-events:none}
.ab .sp{flex:1}.ab .ib{color:var(--onv)}.ab .ib.lead{color:var(--on);margin-left:4px}
.fl{padding:6px 10px;background:var(--surface);display:flex}
.fl .c{flex:1;padding:3px;min-width:0}
.fl .c b{display:flex;height:44px;border-radius:11px;align-items:center;justify-content:center;gap:4px;font-size:13px;font-weight:500;color:var(--onv);background:rgba(225,226,232,.46);white-space:nowrap;overflow:hidden}
[data-theme=dark] .fl .c b{background:rgba(50,53,58,.6)}
.fl .c b small{font-size:12px;font-weight:500;font-feature-settings:'tnum';opacity:.8}
.fl .c b.on{background:var(--pc);color:var(--opc);font-weight:600}
.clist{padding:12px 16px 24px;flex:1;overflow:hidden}
.card{background:var(--scl);border-radius:16px;padding:12px;margin-bottom:12px}
.hd{display:flex;gap:10px;align-items:flex-start;position:relative}
.cov{width:96px;height:54px;border-radius:8px;background:center/cover;flex:none}
.hd .tx{flex:1;min-width:0;padding-right:4px}
.hd .n{display:flex;align-items:center;gap:6px;font-size:15px;font-weight:600;line-height:20px}
.hd .t{font-size:13px;color:var(--onv);line-height:18px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;margin-top:1px}
.hd .m{font-size:12px;color:var(--onv);line-height:17px;margin-top:1px}
.hd .more{width:40px;height:40px;margin:-6px -6px 0 0;display:grid;place-items:center;color:var(--onv);flex:none}
.ar{height:22px;border-radius:11px;display:inline-flex;align-items:center;gap:3px;padding:0 8px 0 6px;background:var(--pc);color:var(--opc);font-size:12px;font-weight:600;flex:none}
.card .sb{margin:10px 0 0;border-radius:12px;padding:12px}
.card .sh .tt{font-size:15px}
.card .sd{font-size:13px;margin-top:6px}
.card .clock{font-size:24px;margin-top:6px}
.card .chips{gap:6px;margin-top:6px}.card .chips span{height:26px;font-size:13px}
.card .bt{gap:8px;margin-top:10px}.card .bt>div{height:40px;font-size:14px}
.nav{height:80px;flex:none;background:var(--scc);display:flex}
.nav>div{flex:1;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:4px;font-size:12px;font-weight:500;color:var(--onv)}
.nav i{width:64px;height:32px;border-radius:16px;display:grid;place-items:center;font-style:normal}
.nav .on{color:var(--on)}.nav .on i{background:var(--sc);color:var(--osc)}
/* notifications */
.sbar{height:36px;display:flex;align-items:center;gap:6px;padding:0 20px 0 24px;font:600 14px 'Geist','Noto Sans SC';background:#0d0f12;color:#fff}
.sbar .r{margin-left:auto;display:flex;gap:5px}.sbar .mi{font-size:16px}
.shade{background:#1b1f26;padding:14px 12px;display:flex;flex-direction:column;gap:10px}
.ntf{background:#2a2f37;border-radius:20px;padding:14px 16px;color:#e8eaf0}
.ntf .h{display:flex;align-items:center;gap:6px;font-size:12px;color:rgba(232,234,240,.75)}
.ntf .t{font-size:15px;font-weight:600;margin-top:6px}.ntf .s{font-size:13px;color:rgba(232,234,240,.75);margin-top:2px}
.ntf .a{display:flex;gap:18px;margin-top:10px;font-size:14px;font-weight:600;color:#A0CAFD}
.ntag{display:inline-block;font-size:11px;font-weight:600;padding:1px 6px;border-radius:6px;margin-left:6px}
.ntag.old{background:#5c2420;color:#ffdad6}.ntag.new{background:#1f3b26;color:#b8f0c6}.ntag.prop{background:#3b3320;color:#ffe2a8}
.bigicons{display:flex;gap:18px;align-items:flex-end;padding:6px 4px 2px}
.bigicons div{display:flex;flex-direction:column;align-items:center;gap:6px;font-size:11px;color:rgba(232,234,240,.75)}
'''

mr = lambda n, s=24: f'<span class="mr" style="font-size:{s}px">{n}</span>'
mi = lambda n, s=24: f'<span class="mi" style="font-size:{s}px">{n}</span>'
rx = lambda c, s=24: f'<span class="rx" style="font-size:{s}px">&#x{c};</span>'
ci = lambda c, s=24: f'<span class="ci" style="font-size:{s}px">&#x{c};</span>'
IMG_ROOM = '.cache/img/158.jpg'
IMG_AV = '.cache/img/65.jpg'
IMG_FS = '.cache/img/274.jpg'
TITLE = '深夜电台 · 点歌接龙到天亮'


def attrs(n=None, tag=None, at=None):
    return (f' data-n="{n}"' if n else '') + (f' data-tag="{tag}"' if tag and n else '') + (f' data-at="{at}"' if at and n else '')


def ib(inner, n=None, cls='ib', tag=None, at=None):
    return f'<div class="{cls}"{attrs(n, tag, at)}>{inner}</div>'


# ---------------------------------------------------------------- the glyph
# Geometry in a 24 box (RecordGlyph scales it): ring radius 9, stroke 2 (outer 20, like a
# Material icon's live area); centre dot radius 3.5; recording disc radius 10 with a 7.5 white
# square (corner 1.8) and a halo ring from 10 to 12; badges (clock, "!") centred at 18.8, 18.8
# with a radius-6 cut-out of the ring.
L = 56.549  # 2 * pi * 9
BX = 18.8
_ids = [0]

STATES = ['idle', 'waiting', 'preparing', 'recording', 'reconnecting', 'processing', 'failed']
NAME = {'idle': '未录', 'waiting': '等待开播', 'preparing': '准备中', 'recording': '录制中', 'reconnecting': '重连中',
        'processing': '合成中', 'failed': '失败'}
STATUS = {'idle': 'null · stopped · completed', 'waiting': 'waitingLive · queued（满）', 'preparing': 'preparing · queued（有空位）',
          'recording': 'running', 'reconnecting': 'reconnecting', 'processing': 'processing', 'failed': 'failed'}


def glyph(state, size=24, ink='var(--onv)', video=False, pct=0.45, halo=0.3, sw=2.0):
    _ids[0] += 1
    mid = f'gm{_ids[0]}'
    amber = '#FFB95C' if video else 'var(--amber)'
    err = '#FFB4AB' if video else 'var(--error)'
    onerr = '#690005' if video else 'var(--onError)'

    def ring(c, extra=''):
        return f'<circle cx="12" cy="12" r="9" fill="none" stroke="{c}" stroke-width="{sw}"{extra}/>'

    def dot(c):
        return f'<circle cx="12" cy="12" r="3.5" fill="{c}"/>'

    cut = (f'<defs><mask id="{mid}"><rect width="24" height="24" fill="#fff"/>'
           f'<circle cx="{BX}" cy="{BX}" r="6" fill="#000"/></mask></defs>')
    if state == 'idle':
        body = ring(ink) + dot(ink)
    elif state == 'waiting':
        body = (cut + f'<g mask="url(#{mid})">{ring(ink)}{dot(ink)}</g>'
                f'<circle cx="{BX}" cy="{BX}" r="4.3" fill="none" stroke="{ink}" stroke-width="1.5"/>'
                f'<path d="M{BX} 16.6v2.3l1.5 1" fill="none" stroke="{ink}" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/>')
    elif state == 'failed':
        body = (cut + f'<g mask="url(#{mid})">{ring(ink)}{dot(ink)}</g>'
                f'<circle cx="{BX}" cy="{BX}" r="5" fill="{err}"/>'
                f'<rect x="{BX - 0.75}" y="15.9" width="1.5" height="3.5" rx=".75" fill="{onerr}"/>'
                f'<circle cx="{BX}" cy="21.0" r=".9" fill="{onerr}"/>')
    elif state in ('preparing', 'processing'):
        frac = 0.25 if state == 'preparing' else pct
        body = (ring(ink, ' stroke-opacity=".28"')
                + f'<circle cx="12" cy="12" r="9" fill="none" stroke="{ink}" stroke-width="{sw}" stroke-linecap="round" '
                f'stroke-dasharray="{L * frac:.2f} {L:.2f}" transform="rotate({-90 if state == "processing" else 20} 12 12)"/>'
                + dot(ink))
    elif state == 'reconnecting':
        body = (f'<circle cx="12" cy="12" r="9" fill="none" stroke="{amber}" stroke-width="{sw}" stroke-dasharray="4.3 2.769" '
                'transform="rotate(-90 12 12)"/>' + dot(amber))
    elif state == 'recording':
        body = (f'<circle cx="12" cy="12" r="11" fill="none" stroke="{RED}" stroke-opacity="{halo}" stroke-width="2"/>'
                f'<circle cx="12" cy="12" r="10" fill="{RED}"/>'
                '<rect x="8.25" y="8.25" width="7.5" height="7.5" rx="1.8" fill="#fff"/>')
    else:
        raise ValueError(state)
    return f'<svg class="gl" width="{size}" height="{size}" viewBox="0 0 24 24">{body}</svg>'


def old_idle(size=24, ink='var(--onv)'):
    """4.0.0: a grey ring around a red dot (the problem)."""
    return (f'<svg class="gl" width="{size}" height="{size}" viewBox="0 0 24 24"><circle cx="12" cy="12" r="11" fill="none" stroke="{ink}" stroke-width="2"/>'
            f'<circle cx="12" cy="12" r="5" fill="{RED}"/></svg>')


def old_rec(size=26):
    """4.0.0: a white dot on a red disc with a halo."""
    return (f'<svg class="gl" width="{size}" height="{size}" viewBox="0 0 26 26" style="overflow:visible"><circle cx="13" cy="13" r="14.6" fill="rgba(217,45,32,.25)"/>'
            f'<circle cx="13" cy="13" r="13" fill="{RED}"/><circle cx="13" cy="13" r="4.7" fill="#fff"/></svg>')


def notif_icon(kind='new', size=24, color='#fff'):
    """The Android status bar icon (one colour)."""
    if kind == 'old':  # ic_stat_recording before: a ring around a dot
        d = 'M12,22C6.477,22 2,17.523 2,12S6.477,2 12,2s10,4.477 10,10 -4.477,10 -10,10zM12,20a8,8 0,1 0,0 -16,8 8,0 0,0 0,16zM12,15a3,3 0,1 1,0 -6,3 3,0 0,1 0,6z'
        return f'<svg class="gl" width="{size}" height="{size}" viewBox="0 0 24 24"><path fill="{color}" fill-rule="evenodd" d="{d}"/></svg>'
    if kind == 'new':  # the recording disc with the square knocked out
        d = ('M12,2a10,10 0,1 1,0 20a10,10 0,1 1,0 -20z'
             'M10.05,8.25h3.9a1.8,1.8 0,0 1,1.8 1.8v3.9a1.8,1.8 0,0 1,-1.8 1.8h-3.9a1.8,1.8 0,0 1,-1.8 -1.8v-3.9a1.8,1.8 0,0 1,1.8 -1.8z')
        return f'<svg class="gl" width="{size}" height="{size}" viewBox="0 0 24 24"><path fill="{color}" fill-rule="evenodd" d="{d}"/></svg>'
    # proposal for "录制已停止": the idle ring and dot with "!" (needs one Kotlin line, not done)
    _ids[0] += 1
    mid = f'gm{_ids[0]}'
    return (f'<svg class="gl" width="{size}" height="{size}" viewBox="0 0 24 24"><defs><mask id="{mid}"><rect width="24" height="24" fill="#fff"/>'
            f'<circle cx="{BX}" cy="{BX}" r="6" fill="#000"/></mask></defs><g mask="url(#{mid})"><circle cx="12" cy="12" r="9" fill="none" stroke="{color}" stroke-width="2"/>'
            f'<circle cx="12" cy="12" r="3.5" fill="{color}"/></g><circle cx="{BX}" cy="{BX}" r="5" fill="{color}"/>'
            f'<rect x="{BX - 0.75}" y="15.9" width="1.5" height="3.5" rx=".75" fill="#1b1f26"/><circle cx="{BX}" cy="21.0" r=".9" fill="#1b1f26"/></svg>')


def mark(state, compact=False):
    """The mark on the picture (RecordingBadge): recording red, reconnecting and joining on a dark pill."""
    if state == 'recording':
        return f'<span class="mk rec"><i></i>{"12:34" if compact else "录制中 12:34"}</span>'
    if state == 'reconnecting':
        return f'<span class="mk dim">{glyph("reconnecting", 14, "#fff", video=True, sw=2.6)}{"12:34" if compact else "重连中 12:34"}</span>'
    if state == 'processing':
        return f'<span class="mk dim">{glyph("processing", 14, "#fff", video=True, sw=2.6)}{"45%" if compact else "合成中 45%"}</span>'
    return ''


# ---------------------------------------------------------------- page frame
def doc(w, h, scale, body, crop=False, root=''):
    return (f'<!doctype html><html><head><meta charset="utf-8"><meta name="mock-size" content="{w}x{h}@{scale}{" crop" if crop else ""}">'
            f'<link rel="stylesheet" href="kit/kit.css"><style>{CSS}</style></head><body>{body}</body></html>')


def status_bar():
    return ('<div class="status"><span>21:36</span><span class="r"><span class="mi">signal_cellular_alt</span>'
            '<span class="mi">wifi</span><span class="mi">battery_full</span></span></div>')


def phone(inner):
    return (f'<div class="ph"><div style="display:flex;flex-direction:column;height:852px">{status_bar()}{inner}</div>'
            '<div class="syn">示意图片</div><div class="gesture"></div></div>')


# ---------------------------------------------------------------- room bars
def v3_bar(kind):
    icon = {'idle': rx('f05a', 18), 'mon': rx('eb80', 18), 'run': rx('f059', 18)}[kind]
    cls = {'idle': '', 'mon': ' mon', 'run': ' run'}[kind]
    return (f'<div class="appbar"><div class="back">{mi("arrow_back")}</div><span class="av" style="background-image:url({IMG_AV})"></span>'
            f'<div class="v3tt"><div>晚风&nbsp;</div><div>哔哩哔哩 / 唱见电台</div></div><div class="v3heart">{rx("ee0b", 24)}</div>'
            f'<div class="v3rec{cls}">{icon}</div>{ib(rx("ea42"))}<div style="width:4px"></div></div>')


def rec_button(state, n=None, tag=None):
    """The room bar's record button (light page)."""
    if state == 'waiting':
        return f'<div class="pillrec"{attrs(n, tag)}>{glyph("waiting", 18, "var(--osc)")}自动录</div>'
    return f'<div class="recbtn ib"{attrs(n, tag)}>{glyph(state)}</div>'


def bar(rec, follow=True, n_follow=None, n_menu=None):
    fol = f'<div class="fol on"{attrs(n_follow)}>' + rx('eb7b') + '已关注</div>' if follow else ''
    return (f'<div class="appbar"><div class="back">{mi("arrow_back")}</div><span class="av" style="background-image:url({IMG_AV})"></span>'
            f'<div class="tt"><div class="n">晚风</div><div class="s">哔哩哔哩 · 唱见电台</div></div>{fol}{rec}'
            f'<div class="ib" style="width:44px"{attrs(n_menu)}>' + rx('ea42') + '</div><div style="width:2px"></div></div>')


def now_bar(kind):
    """4.0.0's room bar."""
    if kind == 'idle':
        rec = f'<div class="recbtn ib">{old_idle(22)}</div>'
    elif kind == 'auto':
        rec = '<div class="autorec" style="height:36px;border-radius:18px;padding:0 14px;margin:0 4px">' + rx('f215', 18) + '自动录</div>'
    else:
        rec = f'<div class="recbtn ib">{old_rec()}</div>'
    return bar(rec)


def strip(content, img=IMG_ROOM):
    return f'<div class="strip" style="background-image:url({img})"><div style="display:flex;align-items:center;height:100%;padding:0 12px;gap:10px">{content}</div></div>'


def v3_appbar():
    rows = [('未录', 'idle', '“录制”：中性色空心圈'), ('有任务（已监控）', 'mon', '“已监控”：主色勾'), ('录制中、重连中、准备中', 'run', '“录制中”：红色实心圈')]
    body = ''.join(f'<div class="lab"><b>{a}</b> · {c}</div><div class="bar">{v3_bar(k)}</div>' for a, k, c in rows)
    return doc(393, 900, 2, f'<div class="xs" style="padding:4px 0 14px">{body}</div>', crop=True)


def v4_current():
    """4.0.0 (U.2a change 13) and what goes wrong."""
    old_mark = '<span class="mk rec"><i></i>录制中 12:34</span>'
    rows = [
        ('未录', '<span class="bad">灰圈里是红点，看着像在录</span>', now_bar('idle'), ''),
        ('等待开播（开播自动录）', '“自动录”', now_bar('auto'), ''),
        ('录制中', '红底白点闪烁，画面角上“● 录制中”', now_bar('rec'), old_mark),
        ('准备中', '<span class="bad">还没开始写文件，已经显示红色“录制中”</span>', now_bar('rec'), old_mark),
        ('重连中', '<span class="bad">断开了也显示红色“录制中”</span>', now_bar('rec'), old_mark),
        ('合成中（停止以后）', '<span class="bad">已经停了，还显示红色“录制中”</span>', now_bar('rec'), old_mark),
        ('失败', '和未录一样，看不出失败', now_bar('idle'), ''),
    ]
    body = ''
    for a, c, b, m in rows:
        body += f'<div class="lab"><b>{a}</b> · {c}</div><div class="bar">{b}</div>'
        if m:
            body += strip(m)
    return doc(393, 1600, 2, f'<div class="xs" style="padding:4px 0 14px">{body}</div>', crop=True)


def v4_appbar():
    rows = [
        ('idle', '单色圆环 + 中心小圆点，和旁边的图标同色；<b>没有红色</b>'),
        ('waiting', '“自动录”：圆环右下角小钟（窄顶栏只有图标）'),
        ('preparing', '中性色环形进度（转圈）'),
        ('recording', '<b>红色实心圆 + 白色圆角方块</b>，外圈慢慢呼吸'),
        ('reconnecting', '琥珀色虚线圆环'),
        ('processing', '中性色环形进度（按合成进度走）'),
        ('failed', '圆环右下角“!”'),
    ]
    body = ''
    for state, c in rows:
        body += f'<div class="lab"><b>{NAME[state]}</b> · {c}</div><div class="bar">{bar(rec_button(state))}</div>'
    narrow = ('<div class="lab"><b>窄顶栏</b>（名字放不下时）· “自动录”只剩图标，其余同上</div>'
              '<div class="bar">' + bar(f'<div class="tonal">{glyph("waiting", 20, "var(--osc)")}</div>') + '</div>')
    return doc(393, 1400, 2, f'<div class="xs" style="padding:4px 0 14px">{body}{narrow}</div>', crop=True)


# ---------------------------------------------------------------- the glyph sheet
def v4_glyphs():
    desc = {
        'idle': ('环 2dp + 中心圆点 7dp；颜色 = 旁边图标的颜色（亮：onSurfaceVariant，画面上：白）', '静止'),
        'waiting': ('未录的圆环，右下角挖空放小钟（线 1.5dp）', '静止'),
        'preparing': ('淡环（28%）上 1/4 段转圈 + 中心圆点；中性色', '转圈 1.2 秒一圈；减少动态效果时停住'),
        'recording': ('红色实心圆 20dp + 白色圆角方块 7.5dp；外圈 2dp 红色光晕', '光晕 2.4 秒一呼一吸（透明度 15%↔45%）；减少动态效果时常亮 30%'),
        'reconnecting': ('琥珀色虚线圆环（8 段）+ 琥珀色圆点', '静止'),
        'processing': ('淡环上画合成进度（从 12 点顺时针）+ 中心圆点；没有进度时同准备中', '跟着进度走'),
        'failed': ('未录的圆环，右下角挖空放错误色“!”徽标', '静止'),
    }
    rows = ''
    for s in STATES:
        red = '<span class="redq yes">红</span>' if s == 'recording' else '<span class="redq no">无</span>'
        extra = ''
        if s == 'recording':
            extra = ('<div class="frames" style="margin-top:6px">' + ''.join(
                f'<span>{glyph("recording", 32, halo=a)}<br>{t}</span>' for a, t in [(.15, '吸 15%'), (.3, '30%'), (.45, '呼 45%')]) + '</div>')
        rows += (f'<tr><td class="nm">{NAME[s]}<small>{STATUS[s]}</small></td>'
                 f'<td><div class="cell">{glyph(s)}</div></td>'
                 f'<td><div class="cell dk">{glyph(s, ink="#fff", video=True)}</div></td>'
                 f'<td><div class="cell big grid">{glyph(s, 96)}</div></td>'
                 f'<td>{red}</td><td>{desc[s][0]}{extra}</td><td>{desc[s][1]}</td></tr>')
    marks = ''.join(f'<div style="display:flex;flex-direction:column;gap:6px;align-items:flex-start"><span style="font-size:12px;color:var(--onv)">{NAME[s]}</span>'
                    f'<div style="display:flex;gap:8px;padding:8px;border-radius:10px;background:#000 center/cover url({IMG_ROOM})">{mark(s)}{mark(s, True)}</div></div>'
                    for s in ('recording', 'reconnecting', 'processing'))
    body = (f'<div class="xs"><div class="h2">一个图标、七种状态<small>24dp；亮背景 / 画面上 / 放大 4 倍（格子 1dp）</small></div>'
            '<table class="gs"><tr><th>状态</th><th>亮背景</th><th>画面上</th><th>放大</th><th>红色</th><th>画法</th><th>动效</th></tr>'
            f'{rows}</table>'
            '<div class="h2" style="margin-top:18px">画面上的角标<small>只在录制中、重连中、合成中出现；左：控制栏显示时，右：控制栏隐藏和小窗</small></div>'
            f'<div style="display:flex;gap:24px">{marks}</div></div>')
    return doc(1100, 1400, 1.5, body, crop=True)


# ---------------------------------------------------------------- where each state shows
def v4_matrix():
    cards = {
        'idle': ('neutral', '没在录制', ''), 'waiting': ('neutral', '等待开播', ''), 'preparing': ('neutral', '准备中', ''),
        'recording': ('red', '录制中', '第 3 段'), 'reconnecting': ('yellow', '连接断开，正在重连', '第 2 次'),
        'processing': ('neutral', '正在整理文件', '45%'), 'failed': ('error', '录制失败', ''),
    }
    notif = {
        'idle': None, 'waiting': None, 'preparing': '正在录制 · 晚风', 'recording': '正在录制 · 晚风  12:34',
        'reconnecting': '正在录制 · 晚风', 'processing': '正在录制 · 晚风', 'failed': '录制已停止 · 晚风',
    }
    rows = ''
    for s in STATES:
        # 1. the room bar (light page)
        rec = rec_button(s)
        top = (f'<div class="mbar"><span class="sp"></span><div class="fol on">{rx("eb7b")}已关注</div>{rec}'
               f'<div class="ib" style="width:40px">{rx("ea42")}</div></div>')
        # 2. on the picture: the mark (controls shown / hidden)
        if mark(s):
            pic = f'<div class="mvid" style="background-image:url({IMG_ROOM})">{mark(s)}<span class="cap">隐藏时</span>{mark(s, True)}</div>'
        else:
            pic = '<span class="none">画面上不显示角标</span>'
        # 3. fullscreen top bar (landscape: the time beside it while recording)
        fs_rec = glyph(s, 24, '#fff', video=True)
        if s == 'waiting':
            fs_btn = ib(fs_rec)
        elif s == 'recording':
            fs_btn = f'<div class="rbt">{fs_rec}<span class="rt">12:34</span></div>'
        else:
            fs_btn = ib(fs_rec)
        fs = (f'<div class="mfs" style="background-image:url({IMG_FS})">{ib(rx("f235"), cls="ib vic")}{fs_btn}'
              f'{ib(rx("ea42"), cls="ib vic")}</div>')
        # 4. status card / recording centre header
        tone, title, meta = cards[s]
        ink = {'neutral': 'var(--onv)', 'red': 'var(--onv)', 'yellow': 'var(--amber)', 'error': 'var(--onv)'}[tone]
        card = (f'<div class="mcard {tone}">{glyph(s, 20, ink)}<span>{title}</span>'
                + (f'<span class="me">{meta}</span>' if meta else '') + '</div>')
        # 5. Android notification
        nt = notif[s]
        if nt is None:
            note = '<span class="none">没有通知</span>'
        elif s == 'failed':
            note = (f'<div class="mnot">{notif_icon("new", 18)}<span class="tx">{nt}</span></div>'
                    '<div class="none" style="margin-top:4px">建议换成“!”图形（要改一行原生代码，见待定）</div>')
        else:
            note = f'<div class="mnot">{notif_icon("new", 18)}<span class="tx">{nt}</span></div>'
            if s != 'recording':
                note += '<div class="none" style="margin-top:4px">同一个前台通知，小图标不随状态变</div>'
        rows += (f'<tr><td class="nm">{NAME[s]}<small>{STATUS[s]}</small></td><td>{top}</td><td>{pic}</td><td>{fs}</td>'
                 f'<td>{card}</td><td>{note}</td></tr>')
    body = ('<div class="xs"><div class="h2">七种状态在各处的样子<small>同一组图形；红色只在“录制中”</small></div>'
            '<table class="mx"><tr><th>状态</th><th>直播间顶栏<small>亮背景页</small></th><th>画面上<small>暗：角标</small></th>'
            '<th>全屏顶栏<small>横屏有空间时加 mm:ss</small></th><th>状态卡 · 录制中心<small>卡片头</small></th><th>通知<small>状态栏小图标（单色）</small></th></tr>'
            f'{rows}</table></div>')
    return doc(1560, 1200, 1.1, body, crop=True)


# ---------------------------------------------------------------- the room (phone)
DMS = [(0.35, 0.30, '前排支持！'), (0.08, 0.48, '这首好好听'), (0.55, 0.62, '晚风今天状态好好')]
CHAT = [('#C2410C', 'Aki', '打卡第 52 天，晚安前来听歌'), ('#000', '路过的风', '主播声音太温柔了'), ('#1971C2', '夜猫子', '可以点《晴天》吗'),
        ('#000', '一只小熊', '这首歌好好听'), ('#C2255C', '星河长明', '前排支持！'), ('#2F9E44', '清欢', '下一首想听《晚风》'),
        ('#000', '风吹麦浪', '来了来了'), ('#000', '小林同学', '今天也是被治愈的一天'), ('#000', '橘子汽水', '晚风晚上好～'),
        ('#000', '不吃香菜', '上一首是什么歌？'), ('#000', '月亮邮差', '这个混响调得真舒服')]


def pic(w=393, h=221):
    d = ''.join(f'<div class="dm" style="left:{x * w:.0f}px;top:{y * h:.0f}px">{t}</div>' for x, y, t in DMS)
    return f'<div class="pic" style="background-image:url({IMG_ROOM})"></div>{d}'


def inline_bars(mk='', n_mark=None):
    lead = f'<div style="margin:12px 0 0 4px"{attrs(n_mark, "chg")}>{mk}</div>' if mk else ''
    top = (f'<div class="vtop">{lead}<div class="title">{TITLE}</div>' + ib(rx('ee05', 21), None, 'ib vic') + ib(rx('f235'), None, 'ib vic')
           + ib(ci('e806'), None, 'ib vic') + '</div>')
    bot = ('<div class="vbot">' + ib(mr('pause', 28), None, 'ib vic') + ib(mr('refresh'), None, 'ib vic') + ib('<span class="dmk open"></span>', None, 'ib vic')
           + ib('<span class="dmk set"></span>', None, 'ib vic') + '<div style="flex:1"></div>' + ib(mr('screen_rotation_alt', 21), None, 'ib vic')
           + ib(mr('fullscreen', 26), None, 'ib vic') + '</div>')
    return top + bot


def info():
    figs = ('<div class="figs"><span class="fg"><span class="mr">people_alt</span><b>1.2万</b></span><span class="fg"><span class="mr">whatshot</span><b>84.7万</b></span>'
            '<span class="fg"><span class="mr">schedule</span><b>2:18</b></span></div>')
    chips = '<div class="chip">原画' + rx('ea4e', 18) + '</div><div class="chip">线路1' + rx('ea4e', 18) + '</div>'
    return (f'<div class="info"><div class="l1"><span class="t">{TITLE}</span><span class="more">详情' + rx('ea4e', 18) + '</span></div>'
            f'<div class="l2">{figs}{chips}</div></div><hr>')


def chat():
    rows = ''.join(f'<div class="row"><span class="u" style="{"" if c == "#000" else "color:" + c}">{u}：</span>{t}</div>' for c, u, t in CHAT)
    return ('<div class="tabs"><div class="on">弹幕列表</div><div>醒目留言<span class="badge">2</span></div><div>弹幕设置</div><div>屏蔽管理</div></div>'
            f'<div style="flex:1;overflow:hidden;display:flex;flex-direction:column;justify-content:flex-end;padding:4px 0 14px"><div class="sys">弹幕服务器连接正常</div>{rows}</div>')


def room(state, numbered=False):
    n = (lambda k: k) if numbered else (lambda k: None)
    head = bar(rec_button(state, n(1), 'chg'), n_follow=None, n_menu=None)
    mk = mark(state)
    video = f'<div class="vbox">{pic()}{inline_bars(mk, n(2) if mk else None)}</div>'
    return doc(393, 852, 3, phone(f'{head}{video}{info()}<div style="flex:1;min-height:0;display:flex;flex-direction:column;overflow:hidden">{chat()}</div>'))


# ---------------------------------------------------------------- fullscreen (landscape)
FDMS = [(0.35, 0.30, '前排支持！'), (0.10, 0.42, '这条街好热闹'), (0.55, 0.52, '主播带我们去时代广场'), (0.22, 0.21, '晚上好～')]


def land(state, numbered=False):
    n = (lambda k: k) if numbered else (lambda k: None)
    w, h = 852, 393
    d = ''.join(f'<div class="dm" style="left:{x * w:.0f}px;top:{y * h:.0f}px;font-size:18px">{t}</div>' for x, y, t in FDMS)
    g = glyph(state, 24, '#fff', video=True)
    if state == 'recording':
        rec = f'<div class="rbt"{attrs(n(1), "chg")}>{g}<span class="rt">12:34</span></div>'
    else:
        rec = f'<div class="ib"{attrs(n(1), "chg")}>{g}</div>'
    lead = ib(mi('arrow_back'), None, 'ib vic') + '<div class="time">21:36</div><div class="bat">76</div>'
    trail = (ib(mr('swap_horiz'), None, 'ib vic') + ib(rx('ee05', 21), None, 'ib vic') + ib(rx('f235'), None, 'ib vic')
             + ib(ci('e806'), None, 'ib vic') + rec + ib(rx('ea42'), None, 'ib vic'))
    top = f'<div class="vtop">{lead}<div class="title">纽约时代广场，夜游直播</div>{trail}</div>'
    comp = '<div class="comp"><span class="a">' + mr('auto_awesome', 18) + '</span>发送一条本地字幕<span class="s">' + mr('send', 18) + '</span></div>'
    bot = ('<div class="vbot" style="padding:0 12px 4px">' + ib(mr('pause', 28), None, 'ib vic') + ib(mr('refresh'), None, 'ib vic')
           + '<div class="vfol">' + rx('eb7b') + '已关注</div>' + ib('<span class="dmk open"></span>', None, 'ib vic') + ib('<span class="dmk set"></span>', None, 'ib vic')
           + f'<div style="flex:1;display:flex;justify-content:center;padding:0 8px;height:48px;align-items:center">{comp}</div>'
           + '<div class="vchip" style="margin:0 3px">原画' + rx('ea4e', 18) + '</div><div class="vchip" style="margin:0 3px">线路1' + rx('ea4e', 18) + '</div>'
           + ib(mr('screen_rotation_alt', 21), None, 'ib vic') + ib(rx('ea80', 22), None, 'ib vic') + ib(mr('fullscreen_exit', 26), None, 'ib vic') + '</div>')
    # The mark under the bars: not for recording (the bar carries the time), still for reconnecting and joining.
    mk = '' if state == 'recording' else (f'<div class="mkpos" style="top:62px;left:16px"{attrs(n(2), "chg")}>{mark(state)}</div>' if mark(state) else '')
    return doc(w, h, 2, f'<div class="fs" style="--w:{w}px;--h:{h}px;background-image:url({IMG_FS});background-position:center 40%">{d}{top}{bot}{mk}'
                        f'<div class="lock">{mr("lock_open", 28)}</div><div class="syn">示意图片</div></div>')


def land_hidden():
    """Controls hidden: the compact mark alone in the corner."""
    w, h = 852, 393
    d = ''.join(f'<div class="dm" style="left:{x * w:.0f}px;top:{y * h:.0f}px;font-size:18px">{t}</div>' for x, y, t in FDMS)
    return doc(w, h, 2, f'<div class="fs" style="--w:{w}px;--h:{h}px;background-image:url({IMG_FS});background-position:center 40%">{d}'
                        f'<div class="mkpos" style="top:12px;left:40px">{mark("recording", True)}</div><div class="syn">示意图片</div></div>')


# ---------------------------------------------------------------- the record panel's status cards (U.2f)
def sb(state, full=True):
    tone = {'recording': 'red', 'queued': 'yellow', 'reconnecting': 'yellow', 'saved': 'green', 'failed': 'error'}.get(state, 'neutral')
    ink = {'yellow': 'var(--amber)'}.get(tone, 'var(--onv)')
    icon = {
        'idle': glyph('idle', 20, ink), 'waiting': glyph('waiting', 20, ink), 'preparing': glyph('preparing', 20, ink),
        'queued': glyph('waiting', 20, ink), 'recording': glyph('recording', 20), 'reconnecting': glyph('reconnecting', 20),
        'processing': glyph('processing', 20, ink), 'saved': mr('check_circle', 20), 'failed': glyph('failed', 20, ink),
    }[state]
    title = {'idle': '没在录制', 'waiting': '等待开播', 'preparing': '准备中', 'queued': '排队中', 'recording': '录制中',
             'reconnecting': '连接断开，正在重连', 'processing': '正在整理文件', 'saved': '已保存', 'failed': '录制失败'}[state]
    meta, body, buttons = '', '', ''
    if state == 'idle':
        body = '<div class="sd">点开始录制，录这个直播间；也可以打开下面的“开播自动录”。</div>' if full else ''
        buttons = '<div class="go"><i></i>开始录制</div>'
    elif state == 'waiting':
        body = '<div class="sd">主播开播后自动开始录制。</div>' if full else '<div class="sd">每 30 秒检查一次是否开播 · 上次检查 21:35</div>'
        buttons = '<div class="go"><i></i>现在就录</div>'
    elif state == 'preparing':
        body = '<div class="sd">正在获取直播流（原画）…</div>'
        buttons = '<div class="pl">取消</div>'
    elif state == 'queued':
        body = '<div class="sd">同时最多录 3 个，现在正在录 3 个；有空位就自动开始。</div>'
        buttons = '<div class="pl">取消</div><div class="pl">改上限</div>'
    elif state == 'recording':
        meta = '第 3 段 · 每 5 分钟一段'
        body = '<div class="clock">00:12:34</div><div class="chips"><span>已录 356 MB</span><span>3.2 Mbps</span><span>原画</span><span>弹幕 1,284 条</span></div>'
        buttons = '<div class="stop"><i></i>停止录制</div>'
    elif state == 'reconnecting':
        meta = '第 2 次，共 5 次'
        body = '<div class="sd">28 秒后重试。已录的 00:12:34 · 356 MB 不会丢。</div>'
        buttons = '<div class="stop"><i></i>停止录制</div>'
    elif state == 'processing':
        meta = '45%'
        body = '<div class="sd">把 3 段合成一个 MP4，完成后就能播放。可以关掉这里，不影响整理。</div><div class="lin"><i style="width:45%"></i></div>'
    elif state == 'saved':
        meta = '今天 21:30'
        body = '<div class="sd">时长 00:35:12 · 1.2 GB · 原画 · 弹幕 3,410 条</div>'
        buttons = '<div class="pl">播放</div><div class="pl">在录制中心查看</div>'
    elif state == 'failed':
        body = '<div class="sd">获取直播流时超时（第 5 次，已不再重试）。可以换个清晰度再试。</div>'
        buttons = '<div class="pl">查看原因</div><div class="er">重试</div>'
    head = (f'<div class="sh"><span class="ic">{icon}</span><span class="tt">{title}</span>' + (f'<span class="me">{meta}</span>' if meta else '') + '</div>')
    return f'<div class="sb {tone}">{head}{body}' + (f'<div class="bt">{buttons}</div>' if buttons else '') + '</div>'


def v4_cards():
    order = ['idle', 'waiting', 'preparing', 'queued', 'recording', 'reconnecting', 'processing', 'saved', 'failed']
    names = {'idle': '未录', 'waiting': '等待开播', 'preparing': '准备中', 'queued': '排队中（和等待开播同一个图形）', 'recording': '录制中',
             'reconnecting': '重连中', 'processing': '合成中', 'saved': '已保存（不变：绿色勾）', 'failed': '失败'}
    body = ''.join(f'<div class="cap2">{names[s]}</div>{sb(s)}' for s in order)
    return doc(393, 2600, 2, f'<div class="xs">{body}</div>', crop=True)


# ---------------------------------------------------------------- the recording centre (U.7a)
ROOMS = {
    'wf': ('158', '晚风', '深夜电台 · 点歌接龙到天亮', 'bilibili', '哔哩哔哩', '热度 84.7万'),
    'lw': ('304', '录音棚老王', '调音台教学 第 12 课', 'bilibili', '哔哩哔哩', '热度 3.1万'),
    'cj': ('111', '车库阿杰', '周末老爷车巡游现场', 'douyu', '斗鱼', '热度 12.6万'),
    'ch': ('169', '柴柴日记', '小狗满草地跑一下午', 'bilibili', '哔哩哔哩', '热度 6.4万'),
}


def ccard(key, state, auto=False):
    cover, nick, title, pid, pname, aud = ROOMS[key]
    pill = f'<span class="ar">{rx("f215", 13)}自动录</span>' if auto else ''
    hd = (f'<div class="hd"><div class="cov" style="background-image:url(.cache/img/{cover}.jpg)"></div>'
          f'<div class="tx"><div class="n"><span>{nick}</span>{pill}</div><div class="t">{title}</div>'
          f'<div class="m">{pname} · {aud}</div></div><div class="more">{mr("more_vert", 22)}</div></div>')
    return f'<div class="card">{hd}{sb(state, full=False)}</div>'


def v4_centre():
    ab = (f'<div class="ab"><div class="ib lead">{mr("menu")}</div><div class="ttl">录制中心</div><div class="sp"></div>'
          f'<div class="ib">{rx("f3cc", 22)}</div><div class="ib">{rx("f0ea", 22)}</div><div style="width:8px"></div></div>')
    fl = ''.join(f'<div class="c"><b class="{"on" if i == 0 else ""}">{t}<small>{c}</small></b></div>'
                 for i, (t, c) in enumerate([('全部', 4), ('进行中', 2), ('等待开播', 1), ('已保存', 0), ('失败', 1)]))
    lst = ccard('wf', 'recording', True) + ccard('lw', 'processing') + ccard('cj', 'waiting', True) + ccard('ch', 'failed')
    inner = f'{ab}<div class="fl">{fl}</div><hr><div class="clist">{lst}</div>'
    # A long page (the four cards whole); the bottom navigation is left out.
    return doc(393, 2000, 2, f'<div class="ph" style="height:auto">{status_bar()}{inner}<div class="syn">示意图片</div></div>', crop=True)


# ---------------------------------------------------------------- notifications
def v4_notify():
    big = ''.join(f'<div>{notif_icon(k, 48)}<span>{t}</span></div>' for k, t in [('old', '现在：圆环圆点'), ('new', '新：录制中'), ('stop', '建议：录制已停止')])
    body = (f'<div style="width:393px;background:#1b1f26">'
            f'<div class="sbar"><span>21:36</span>{notif_icon("old", 16)}<span class="ntag old">现在</span>'
            f'<span class="r"><span class="mi">wifi</span><span class="mi">battery_full</span></span></div>'
            f'<div class="sbar"><span>21:36</span>{notif_icon("new", 16)}<span class="ntag new">新</span>'
            f'<span class="r"><span class="mi">wifi</span><span class="mi">battery_full</span></span></div>'
            '<div class="shade">'
            f'<div class="ntf"><div class="h">{notif_icon("new", 16, "#e8eaf0")}纯粹直播 · 12:34</div><div class="t">正在录制 · 晚风</div>'
            '<div class="s">深夜电台 · 点歌接龙到天亮 · 原画</div><div class="a"><span>全部停止</span><span>录制中心</span></div></div>'
            f'<div class="ntf"><div class="h">{notif_icon("new", 16, "#e8eaf0")}纯粹直播<span class="ntag prop">建议换成右下图形</span></div><div class="t">录制已停止 · 晚风</div>'
            '<div class="s">后台被系统结束。已保存 12:34 的录像。</div><div class="a"><span>打开录制中心</span></div></div>'
            f'<div class="bigicons">{big}</div>'
            '</div></div>')
    return doc(393, 900, 3, body, crop=True)


OUT = {
    'v3-appbar': v3_appbar(),
    'v4-current': v4_current(),
    'v4-glyphs': v4_glyphs(),
    'v4-appbar': v4_appbar(),
    'v4-matrix': v4_matrix(),
    'v4-room-idle': room('idle'),
    'v4-room-recording': room('recording', numbered=True),
    'v4-room-processing': room('processing'),
    'v4-land-recording': land('recording', numbered=True),
    'v4-land-reconnecting': land('reconnecting', numbered=True),
    'v4-land-hidden': land_hidden(),
    'v4-cards': v4_cards(),
    'v4-centre': v4_centre(),
    'v4-notify': v4_notify(),
}
for name, html in OUT.items():
    open(os.path.join(HERE, name + '.html'), 'w', encoding='utf-8').write(html)
print(len(OUT), 'pages')
