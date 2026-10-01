"""U.2g live room states: v3 restored and the new design, in portrait (U.2a
layout), landscape fullscreen (U.2c) and wide (U.2d), plus an overview sheet
of every state of the picture area and the IPTV programme guide.

v3 (tag v3.2.11):
  widgets/layout/live_play_video.dart:36-41,69-73,79-110 (placeholder choice,
    VideoLoading / RoomLoadFailedWidget / NotLivingVideoWidget)
  widgets/video_player/video_loading.dart, common/widgets/app_status_view.dart
    (24 px ring, the "default" loading style)
  widgets/placeholder/not_living_video_widget.dart (header, three lines)
  widgets/video_player/playback_failure_overlay.dart (dim + dark card)
  player/core/player_manager.dart:3292-3477 (audio-only picture)
  widgets/video_player/iptv_schedule_dialog.dart, video_controller_panel.dart
    :340-458 (IPTV title, "正在播放", guide button, AlertDialog)
  widgets/resolution_selector/resolutions_row.dart:18-20 and
    widgets/layout/live_play_content.dart:60-66,593-595 (blank info row and
    chat while the room is not playing; IPTV shows the video only)
New design: docs/ui/compare/U.2g/README.md.

    python3 docs/ui/compare/U.2g/src/gen.py
    python3 tools/ui/mock/render.py docs/ui/compare/U.2g/src/ --annotate
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))

CSS = '''
.syn{top:6px}
/* ---- picture box and covers ---- */
.vbox{position:relative;width:100%;aspect-ratio:16/9;background:#000;overflow:hidden;flex:none}
.pic{position:absolute;inset:0;background:#000 center 55%/cover}
.cov{position:absolute;inset:0;background:#000 center/cover}
.cov::after{content:'';position:absolute;inset:0;background:rgba(0,0,0,.72)}
.dimn{position:absolute;inset:0;background:rgba(0,0,0,.6)}.dimn.l{background:rgba(0,0,0,.45)}
.frz{position:absolute;inset:0;background:#000 center 55%/cover;filter:saturate(.85)}
.dimv{position:absolute;inset:0;background:rgba(0,0,0,.33)}
/* ---- v3 pieces ---- */
.v3spin{width:24px;height:24px;border-radius:50%;background:conic-gradient(from 0deg,#fff,rgba(255,255,255,.1) 85%,#fff);-webkit-mask:radial-gradient(circle,transparent 8.4px,#000 8.6px);mask:radial-gradient(circle,transparent 8.4px,#000 8.6px)}
.v3spin.pri{background:conic-gradient(from 0deg,var(--primary),rgba(54,97,142,.1) 85%,var(--primary))}
.v3c{position:absolute;inset:0;display:grid;place-items:center;z-index:2}
.v3tt{margin-left:8px;flex:1;min-width:0;font-size:11px;line-height:16px;font-weight:400;white-space:nowrap;overflow:hidden}
.cpi.w{background:conic-gradient(#fff 0 72%,transparent 72%)}
.cpi{--sw:4px;display:inline-block;border-radius:50%;background:conic-gradient(var(--primary) 0 72%,transparent 72%);-webkit-mask:radial-gradient(circle closest-side,transparent calc(100% - var(--sw) - .5px),#000 calc(100% - var(--sw)));mask:radial-gradient(circle closest-side,transparent calc(100% - var(--sw) - .5px),#000 calc(100% - var(--sw)));transform:rotate(40deg)}
.v3tt div{overflow:hidden;text-overflow:ellipsis}
.v3heart{width:40px;height:40px;border-radius:20px;background:var(--sc);color:var(--osc);display:grid;place-items:center;margin:0 5px 0 2px;flex:none}
.v3recsq{width:48px;height:48px;border-radius:12px;background:var(--schh);color:var(--onv);display:grid;place-items:center;flex:none}
.v3fspin{width:47px;display:grid;place-items:center;flex:none}
.v3fol{height:40px;padding:0 14px;border-radius:6px;background:rgba(54,97,142,.49);color:#fff;font-size:12px;display:flex;align-items:center;margin:0 5px 0 2px;flex:none}
.v3recw{height:48px;padding:0 8px;border-radius:12px;background:var(--schh);color:var(--onv);display:flex;align-items:center;gap:4px;font-size:11px;font-weight:600;flex:none}
.v3top{position:absolute;left:0;right:0;top:0;height:56px;display:flex;align-items:center;padding:0 8px;background:linear-gradient(0deg,transparent,rgba(0,0,0,.45));z-index:5;color:#fff}
.v3top .title{flex:1;min-width:0;padding:0 12px;white-space:nowrap;overflow:hidden}
.v3top .title b{display:block;font:700 16px/22px 'Noto Sans SC';overflow:hidden;text-overflow:ellipsis}
.v3top .title small{display:block;font-size:14px;line-height:19px;color:rgba(255,255,255,.85);overflow:hidden;text-overflow:ellipsis}
.v3bot{position:absolute;left:0;right:0;bottom:0;height:56px;display:flex;align-items:center;padding:0 8px;background:linear-gradient(180deg,transparent,rgba(0,0,0,.45));color:#fff;z-index:5}
.v3pill{display:flex;align-items:center;gap:2px;padding:0 6px;height:48px;font-size:14px;flex:none;color:#fff}
.v3sel{display:flex;align-items:center;gap:6px;height:36px;padding:0 10px;border-radius:18px;background:rgba(255,255,255,.13);color:#fff;font-size:13px;font-weight:600;flex:none}
.v3fit{flex:none;padding:0 6px;color:#fff;font-size:15px;white-space:nowrap}
.v3swap{width:40px;height:40px;border-radius:20px;background:rgba(0,0,0,.26);display:grid;place-items:center;color:#fff;margin:0 4px;flex:none}
.v3comp{flex:1;max-width:420px;height:40px;border-radius:20px;background:rgba(0,0,0,.54);border:1px solid rgba(255,255,255,.24);display:flex;align-items:center;color:rgba(255,255,255,.6);font-size:13px;white-space:nowrap;overflow:hidden;min-width:0;margin:0 8px}
.v3comp .a{width:40px;display:grid;place-items:center;color:#FFD166;flex:none}.v3comp .s{margin-left:auto;width:40px;display:grid;place-items:center;color:#fff;flex:none}
/* not living (NotLivingVideoWidget) */
.v3nl{position:absolute;inset:0;display:flex;flex-direction:column;z-index:2}
.v3nl .hd{height:55px;display:flex;align-items:center;padding:0 8px;background:linear-gradient(0deg,transparent,rgba(0,0,0,.45));color:#fff;flex:none}
.v3nl .hd .t{flex:1;min-width:0;padding:0 12px;font-size:14px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.v3nl .bd{flex:1;display:flex;flex-direction:column;align-items:center;justify-content:center;color:#fff;text-align:center;padding:8px 0}
.v3nl .bd .a{font-size:16px;padding:8px}.v3nl .bd p{font-size:14px;line-height:1.45}
/* RoomLoadFailedWidget */
.v3lf{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;color:#fff;text-align:center;padding:16px;z-index:2}
.v3lf>.mr{color:rgba(255,255,255,.7)}.v3lf p{font-size:14px;margin:8px 0 12px}
.v3tonal{height:40px;padding:0 24px 0 16px;border-radius:20px;background:var(--sc);color:var(--osc);display:flex;align-items:center;gap:8px;font-size:14px;font-weight:500}
/* PlaybackFailureOverlay */
.v3pf{position:absolute;inset:0;display:grid;place-items:center;z-index:6}
.v3pf .card{max-width:336px;background:rgba(32,33,36,.933);border-radius:12px;padding:12px;text-align:center;color:#fff}
.v3pf .card b{display:block;font-size:16px;font-weight:400}.v3pf .card p{font-size:13px;color:rgba(255,255,255,.7);margin:8px 0}
.v3fill{height:40px;padding:0 24px 0 16px;border-radius:20px;background:var(--primary);color:#fff;display:inline-flex;align-items:center;gap:8px;font-size:14px;font-weight:500}
.v3fill.off{background:rgba(25,28,32,.12);color:rgba(25,28,32,.38)}
/* audio only (buildAudioOnlyUI) */
.v3au{position:absolute;inset:0;z-index:1;overflow:hidden}
.v3au .bg{position:absolute;inset:0;background:center/cover;opacity:.22;filter:brightness(.25) sepia(.3) hue-rotate(190deg)}
.v3au .gr{position:absolute;inset:0;background:linear-gradient(135deg,rgba(18,24,39,.91),rgba(11,14,22,.95),rgba(21,16,32,.94))}
.v3au .in{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;text-align:center;color:#fff;padding:4px 16px}
.v3au .avc{border-radius:50%;background:center/cover;border:1.5px solid rgba(255,255,255,.15);box-shadow:0 0 10px 4px rgba(255,255,255,.04)}
.v3au .ti{font-weight:700;letter-spacing:.3px;line-height:1.25;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:100%}
.v3au .nk{border-radius:20px;background:rgba(255,255,255,.06);border:1px solid rgba(255,255,255,.08);color:rgba(255,255,255,.75);font-weight:500}
.v3au .bdg{border-radius:30px;background:rgba(255,255,255,.08);border:1px solid rgba(255,255,255,.1);display:flex;align-items:center;font-weight:600;letter-spacing:.2px}
.v3au .bdg.rs{background:rgba(91,103,241,.28);border-color:rgba(139,148,255,.62)}
.v3toast{position:absolute;left:50%;transform:translateX(-50%);z-index:40;background:#000;color:#fff;font-size:14px;padding:10px 25px;border-radius:20px;white-space:nowrap}
/* v3 cards list (wide) */
.it{margin:4px 8px;background:rgba(255,255,255,.72);border:.5px solid rgba(0,0,0,.08);border-radius:10px;padding:8px 12px;display:flex;align-items:flex-start}
.it i{width:8px;height:8px;border-radius:4px;margin:6px 10px 0 0;flex:none}.it p{font-size:14px;line-height:1.45;font-weight:400}.it b{font-weight:700}
.res{height:56px;display:flex;align-items:center;padding:4px;flex:none}
.res .aud{flex:3;padding:0 8px;display:flex;align-items:center;gap:4px;font-size:12px}
.res .sel{flex:2;text-align:right;font-size:11px;color:var(--primary);padding-right:12px}
.res .line{flex:1;text-align:right;font-size:11px;color:var(--primary);padding-right:12px}
/* v3 IPTV dialog */
.scrim{z-index:20}
.v3dlg{position:absolute;z-index:21;background:var(--sch);border-radius:16px;overflow:hidden;display:flex;flex-direction:column;box-shadow:0 8px 24px rgba(0,0,0,.25);color:var(--on)}
.v3dh{display:flex;align-items:flex-start;padding:12px 8px 8px 20px;flex:none}
.v3dh .ic{padding-top:8px;color:var(--primary)}.v3dh .t{flex:1;padding:7px 0 7px 10px;font-size:15px;font-weight:700;line-height:20px}
.v3dh .x{width:40px;height:40px;display:grid;place-items:center;color:rgba(25,28,32,.6)}
.v3dd{height:.5px;background:var(--ov);flex:none}
.v3ret{margin:12px 16px 0;height:40px;border-radius:20px;background:var(--primary);color:#fff;display:flex;align-items:center;justify-content:center;gap:8px;font-size:14px;font-weight:500;flex:none}
.v3gl{flex:1;overflow:hidden;padding:0 16px;position:relative}
.v3pt{padding:4px 0;box-sizing:border-box}
.v3pt .m{height:100%;border-radius:12px;padding:10px 16px;border:1px solid transparent;display:flex;align-items:center;gap:12px}
.v3pt.st .m{flex-direction:column;align-items:flex-start;justify-content:flex-start;gap:8px}
.v3pt.st .tt{flex:none}
.v3pt.cur .m{background:rgba(54,97,142,.06);border-color:rgba(54,97,142,.15)}
.v3pt .tc{padding:4px 8px;border-radius:6px;background:rgba(242,243,250,.5);font-size:13px;font-weight:500;color:rgba(67,71,78,.65);font-feature-settings:'tnum';flex:none}
.v3pt.cur .tc{background:rgba(54,97,142,.1);color:var(--primary);font-weight:700}
.v3pt .tt{flex:1;font-size:14px;color:rgba(25,28,32,.85);line-height:1.4}
.v3pt.cur .tt{color:var(--primary);font-weight:700}
.v3pt .w{display:flex;align-items:center;gap:8px}
.v3live{display:inline-flex;align-items:center;gap:4px;padding:3px 8px;border-radius:6px;background:var(--primary);color:#fff;font-size:10px;font-weight:700}
.v3hist{color:rgba(67,71,78,.6)}.v3hist.off{color:rgba(25,28,32,.3)}
.v3st{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;padding:24px;text-align:center}
.v3st p{font-size:13px;color:rgba(67,71,78,.75);margin-top:12px}
/* ---- new: state layer (one component everywhere) ---- */
.stl{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;text-align:center;color:#fff;z-index:4;padding:12px 16px}
.stl .ic{color:rgba(255,255,255,.78);line-height:1}
.stl .t{font:600 15px/1.4 'Noto Sans SC';margin-top:8px;text-shadow:0 1px 3px rgba(0,0,0,.6);max-width:360px}
.stl .s{font-size:13px;line-height:1.45;color:rgba(255,255,255,.75);margin-top:2px;max-width:340px;text-shadow:0 1px 3px rgba(0,0,0,.6)}
.stl .acts{display:flex;gap:10px;margin-top:12px}
.stl .av2{border-radius:50%;background:center/cover;box-shadow:0 0 0 2px rgba(255,255,255,.28)}
.vb{height:40px;padding:0 16px;border-radius:20px;display:flex;align-items:center;gap:6px;font-size:14px;font-weight:600;white-space:nowrap;flex:none}
.vb .rx,.vb .mr{font-size:18px}
.vb.p{background:#fff;color:#191C20}
.vb.o{background:rgba(0,0,0,.35);color:#fff;box-shadow:inset 0 0 0 1px rgba(255,255,255,.45)}
.spin{width:24px;height:24px;border-radius:50%;background:conic-gradient(from 0deg,#fff,rgba(255,255,255,.1) 85%,#fff);-webkit-mask:radial-gradient(circle,transparent 8.4px,#000 8.6px);mask:radial-gradient(circle,transparent 8.4px,#000 8.6px)}
.spin.l{width:32px;height:32px;-webkit-mask:radial-gradient(circle,transparent 11.6px,#000 11.8px);mask:radial-gradient(circle,transparent 11.6px,#000 11.8px)}
.spin.s{width:16px;height:16px;-webkit-mask:radial-gradient(circle,transparent 5.6px,#000 5.8px);mask:radial-gradient(circle,transparent 5.6px,#000 5.8px)}
.sk{display:inline-block;border-radius:8px;background:var(--schh);flex:none}
.skc{height:32px;border-radius:8px;background:var(--scl);border:1px solid var(--ov);flex:none}
.tag3{flex:none;font-size:12px;line-height:16px;padding:1px 4px;border-radius:4px;border:1px solid var(--onv);color:var(--onv);margin-right:6px}
.tag3.rd{border-color:var(--error);color:var(--error)}
.yel{color:#FFD166 !important}
.cbadge{position:absolute;left:10px;top:52px;z-index:6;display:flex;align-items:center;gap:5px;height:26px;padding:0 4px 0 8px;border-radius:13px;background:rgba(0,0,0,.6);color:#fff;font:600 12px 'Noto Sans SC';font-feature-settings:'tnum'}
.cbadge .rx{font-size:14px}.cbadge .go{margin-left:4px;height:20px;padding:0 8px;border-radius:10px;background:#fff;color:#191C20;display:flex;align-items:center;font-size:12px}
.vtop .title small{display:block;font:400 13px/18px 'Noto Sans SC';color:rgba(255,255,255,.85);overflow:hidden;text-overflow:ellipsis}
.vring{width:22px;height:22px;border-radius:11px;border:2px solid #fff;display:grid;place-items:center}.vring i{width:9px;height:9px;border-radius:5px;background:#FF5449}
.vfol{height:32px;border-radius:16px;display:flex;align-items:center;gap:3px;padding:0 12px 0 9px;font-size:13px;font-weight:500;background:rgba(255,255,255,.18);color:#fff;margin:0 4px 8px;flex:none}
.vbot .vchip{margin-bottom:6px !important}.vfol .rx{font-size:16px}
.comp{flex:1;max-width:420px;height:40px;border-radius:20px;background:rgba(0,0,0,.54);border:1px solid rgba(255,255,255,.24);display:flex;align-items:center;color:rgba(255,255,255,.6);font-size:13px;white-space:nowrap;overflow:hidden;min-width:0}
.comp .a{width:40px;display:grid;place-items:center;color:#FFD166;flex:none}.comp .s{margin-left:auto;width:40px;display:grid;place-items:center;color:#fff;flex:none}
.fs .vtop .time{margin:14px 6px 0 2px}.fs .vtop .bat{margin:16px 8px 0 0}
.lock{position:absolute;right:20px;top:50%;transform:translateY(-50%);width:50px;height:50px;border-radius:25px;background:rgba(0,0,0,.38);display:grid;place-items:center;color:#fff;z-index:6}
.dm{font-size:16px}
/* chat area when not playing */
.emp{flex:1;display:flex;flex-direction:column;padding:12px 16px;gap:14px;min-height:0}
.note{background:var(--scl);border-radius:12px;padding:12px 14px}
.note .h{font-size:13px;color:var(--onv);margin-bottom:4px}.note p{font-size:14px;line-height:1.5}
.note .more{color:var(--primary);font-size:13px;display:inline-block;margin-top:4px;padding:2px 0}
.hint{align-self:center;font-size:13px;color:var(--onv);padding:3px 12px;border-radius:12px;background:var(--scc)}
/* guide (one component: below the picture, right panel, right column) */
.gd{display:flex;flex-direction:column;min-height:0;flex:1;background:var(--surface);color:var(--on)}
.gd-h{height:52px;display:flex;align-items:center;gap:8px;padding:0 4px 0 16px;flex:none}
.gd-h .t{font-size:16px;font-weight:600}.gd-h .w{font-size:12px;color:var(--onv);margin-left:2px}
.gd-h .sp{flex:1}.gd-h .x{width:48px;height:48px;display:grid;place-items:center;color:var(--onv)}
.gd-cu{margin:0 12px 6px;border-radius:12px;background:var(--pc);color:var(--opc);display:flex;align-items:center;gap:8px;padding:8px 8px 8px 14px;flex:none}
.gd-cu .x{flex:1;min-width:0}.gd-cu .a{font-size:12px}.gd-cu .b{font-size:14px;font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.gd-cu .go{height:36px;padding:0 14px 0 10px;border-radius:18px;background:var(--primary);color:var(--onPrimary);display:flex;align-items:center;gap:4px;font-size:14px;font-weight:600;flex:none}
.gd-l{flex:1;overflow:hidden;min-height:0}
.gd-d{height:32px;display:flex;align-items:center;padding:0 16px;font-size:13px;font-weight:600;color:var(--onv);background:var(--scl)}
.gd-r{min-height:52px;display:flex;align-items:center;gap:12px;padding:6px 12px 6px 16px}
.gd-r .tm{width:44px;font-size:14px;color:var(--onv);font-feature-settings:'tnum';flex:none}
.gd-r .tt{flex:1;min-width:0;font-size:15px;line-height:1.4}
.gd-r .rt{flex:none;display:flex;align-items:center;gap:3px;font-size:13px;color:var(--primary)}
.gd-r .rt .rx{font-size:16px}
.gd-r.past .tt{color:var(--on)}.gd-r.gone .tt,.gd-r.gone .tm{color:rgba(67,71,78,.6)}
.gd-r.cur{background:rgba(54,97,142,.07);box-shadow:inset 3px 0 0 var(--primary)}
.gd-r.cur .tt{font-weight:600}
.gd-r.cu{background:rgba(54,97,142,.07);box-shadow:inset 3px 0 0 var(--primary)}
.livet{flex:none;height:22px;padding:0 7px;border-radius:6px;background:var(--live);color:#fff;font-size:12px;font-weight:600;display:flex;align-items:center;gap:3px}
.livet .rx{font-size:13px}
.gd-st{flex:1;display:flex;flex-direction:column;align-items:center;justify-content:center;text-align:center;padding:24px;color:var(--onv);gap:6px}
.gd-st .t{font-size:15px;color:var(--on);font-weight:600}.gd-st p{font-size:13px;line-height:1.5}
.gd-st .bt{margin-top:8px;height:40px;padding:0 18px;border-radius:20px;background:var(--primary);color:var(--onPrimary);display:flex;align-items:center;gap:6px;font-size:14px;font-weight:600}
/* wide */
.win{display:flex;flex-direction:column}
.body{flex:1;display:flex;min-height:0;position:relative}
.stage{position:relative;flex:1;background:#000;display:flex;align-items:center;justify-content:center;overflow:hidden}
.stage .pic2{width:100%;aspect-ratio:16/9;background:#000 center 55%/cover;position:relative}
.col{flex:none;display:flex;flex-direction:column;background:var(--surface);border-left:1px solid var(--ov);position:relative;overflow:hidden}
.list{flex:1;overflow:hidden;display:flex;flex-direction:column;justify-content:flex-end;padding:6px 0 10px}
.collapse{position:absolute;top:50%;width:22px;height:56px;border-radius:8px 0 0 8px;background:var(--schh);color:var(--onv);display:grid;place-items:center;z-index:8;transform:translateY(-50%)}
.vvol{display:flex;align-items:center;gap:6px;color:#fff;margin:0 4px}.vvol .t{width:80px;height:4px;border-radius:2px;background:rgba(255,255,255,.35);position:relative}.vvol .t i{position:absolute;left:0;top:0;bottom:0;width:70%;background:#fff;border-radius:2px}.vvol .t u{position:absolute;left:calc(70% - 7px);top:-5px;width:14px;height:14px;border-radius:7px;background:#fff}
/* sheets */
.sheet2{width:820px;padding:12px 11px 16px;display:grid;grid-template-columns:393px 393px;gap:14px 12px;background:var(--surface)}
.cell .cap{font-size:13px;font-weight:600;margin:0 0 6px 2px;color:var(--on)}.cell .cap small{font-weight:400;color:var(--onv);margin-left:6px}
.cell .vbox{border-radius:0}
.sheet2 .hd2{grid-column:1/3;font-size:15px;font-weight:600;padding:4px 2px 0}
'''

mr = lambda n, s=24: f'<span class="mr" style="font-size:{s}px">{n}</span>'
mi = lambda n, s=24: f'<span class="mi" style="font-size:{s}px">{n}</span>'
rx = lambda c, s=24: f'<span class="rx" style="font-size:{s}px">&#x{c};</span>'
ci = lambda c, s=24: f'<span class="ci" style="font-size:{s}px">&#x{c};</span>'


def attrs(n=None, tag=None, at=None):
    return (f' data-n="{n}"' if n else '') + (f' data-tag="{tag}"' if tag else '') + (f' data-at="{at}"' if at else '')


def ib(inner, n=None, cls='ib', tag=None, at=None):
    return f'<div class="{cls}"{attrs(n, tag, at)}>{inner}</div>'


IMG_ROOM = '.cache/img/158.jpg'      # 晚风's room (U.2a, U.2d)
IMG_AV = '.cache/img/65.jpg'
IMG_TV = '.cache/img/287.jpg'        # an IPTV channel picture
IMG_TVAV = '.cache/img/219.jpg'      # the IPTV room's default avatar (示意)
TITLE = '深夜电台 · 点歌接龙到天亮'
NOTICE = '每晚七点开播，点歌发弹幕“点歌+歌名”，醒目留言优先。周末加播到凌晨两点，节假日另行通知……'
CHAT = [('#C2410C', 'Aki', '打卡第 52 天，晚安前来听歌'), ('#000', '路过的风', '主播声音太温柔了'), ('#1971C2', '夜猫子', '可以点《晴天》吗'),
        ('#000', '一只小熊', '这首歌好好听'), ('#C2255C', '星河长明', '前排支持！'), ('#2F9E44', '清欢', '下一首想听《晚风》'),
        ('#000', '风吹麦浪', '来了来了'), ('#000', '小林同学', '今天也是被治愈的一天'), ('#000', '橘子汽水', '晚风晚上好～'),
        ('#000', '不吃香菜', '上一首是什么歌？'), ('#000', '月亮邮差', '这个混响调得真舒服'), ('#000', '一只小熊', '主播加油')]
DMS = [(0.35, 0.30, '前排支持！'), (0.08, 0.48, '这首好好听'), (0.55, 0.62, '晚风今天状态好好')]

# IPTV programmes (today is 10-01, 21:36; the live programme is 21:30)
CH = '纪实频道'
GROUP = '纪录片'
YDAY = [('19:30', '候鸟迁徙（第 1 集）'), ('20:30', '海岸线（第 1 集）'), ('21:25', '山野之间'), ('22:20', '森林的秘密（第 1 集）'), ('23:15', '极地之旅（第 1 集）')]
TODAY = [('00:10', '高原上的四季'), ('18:30', '城市的夜晚'), ('19:30', '候鸟迁徙（第 2 集）'), ('20:30', '海岸线（第 2 集）'),
         ('21:30', '江河万里（第 3 集）'), ('22:20', '森林的秘密（第 2 集）'), ('23:15', '极地之旅（第 2 集）')]
TMRW = [('00:10', '高原上的四季（重播）'), ('01:05', '城市的夜晚（重播）'), ('02:00', '山野之间（重播）')]
LIVE_PROG = '江河万里（第 3 集）'
CU_PROG = '候鸟迁徙（第 2 集）'


def doc(w, h, scale, body, crop=False):
    return (f'<!doctype html><html><head><meta charset="utf-8"><meta name="mock-size" content="{w}x{h}@{scale}{" crop" if crop else ""}">'
            f'<link rel="stylesheet" href="kit/kit.css"><style>{CSS}</style></head><body>{body}</body></html>')


def status_bar():
    return ('<div class="status"><span>21:36</span><span class="r"><span class="mi">signal_cellular_alt</span>'
            '<span class="mi">wifi</span><span class="mi">battery_full</span></span></div>')


def phone(inner, toast=None):
    t = f'<div class="v3toast" style="bottom:56px">{toast}</div>' if toast else ''
    return (f'<div class="ph"><div style="display:flex;flex-direction:column;height:852px">{status_bar()}{inner}</div>'
            f'<div class="syn">示意图片</div>{t}<div class="gesture"></div></div>')


# ======================================================================
# v3
# ======================================================================
def v3_header(nick='晚风', area='哔哩哔哩 / 唱见电台', av=IMG_AV, follow='heart', wide=False):
    avs = f'background-image:url({av})' if av else 'background:var(--schh)'
    if wide:
        fol = '<div class="v3fol">已关注</div>' if follow != 'spin' else '<div class="v3fspin"><span class="cpi" style="width:18px;height:18px;--sw:2px"></span></div>'
        rec = '<div class="v3recw">' + rx('f05a', 14) + '录制</div>'
    else:
        fol = ('<div class="v3heart">' + rx('ee0b', 24) + '</div>') if follow != 'spin' else '<div class="v3fspin"><span class="cpi" style="width:18px;height:18px;--sw:2px"></span></div>'
        rec = '<div class="v3recsq">' + rx('f05a', 24) + '</div>'
    return (f'<div class="appbar"><div class="back">{mi("arrow_back")}</div><span class="av" style="{avs}"></span>'
            f'<div class="v3tt"><div>{nick}&nbsp;</div><div>{area}</div></div>{fol}{rec}{ib(rx("ea42"))}<div style="width:4px"></div></div>')


def v3_bars_portrait(title=TITLE, programme=None, iptv=False, audio=False):
    t = f'<b>{title}</b>' + (f'<small>正在播放: {programme}</small>' if programme else '')
    top = (f'<div class="v3top"><div class="title">{t}</div>' + (ib(mi('assignment')) if iptv else '')
           + V3AUD(audio) + ib(rx('f235')) + ib(ci('e806')) + '</div>')
    bot = ('<div class="v3bot">' + ib(mr('pause', 28)) + ib(mr('refresh')) + '<div class="v3pill">' + mr('check', 15) + '已关注</div>'
           + ib('<span class="dmk open"></span>') + ib('<span class="dmk set"></span>') + ib(mr('screen_rotation_alt', 21))
           + '<div style="flex:1"></div>' + ib(mr('fullscreen', 26)) + '</div>')
    return top + bot


def v3_bars_land(title='深夜电台 · 点歌接龙到天亮', programme=None, iptv=False, audio=False):
    t = f'<b>{title}</b>' + (f'<small>正在播放: {programme}</small>' if programme else '')
    top = ('<div class="v3top">' + ib(mi('arrow_back')) + '<div class="time" style="padding:0 4px">21:36</div><div class="bat" style="margin:0 8px">76</div>'
           f'<div class="title">{t}</div>' + (ib(mi('assignment')) if iptv else '') + '<div class="v3swap">' + mr('swap_horiz') + '</div>'
           + V3AUD(audio) + ib(rx('f235')) + ib(ci('e806')) + '</div>')
    comp = '<div class="v3comp"><span class="a">' + mr('auto_awesome', 18) + '</span>发送一条本地字幕<span class="s">' + mr('send', 18) + '</span></div>'
    bot = ('<div class="v3bot" style="padding:0 16px">' + ib(mr('pause', 28)) + ib(mr('refresh')) + '<div class="v3pill">' + mr('check', 15) + '已关注</div>'
           + ib('<span class="dmk open"></span>') + ib('<span class="dmk set"></span>') + '<div style="flex:1;display:flex;justify-content:center">' + comp + '</div>'
           + '<div class="v3sel">' + mr('tune', 17) + '原画 · 线路1</div>' + ib(mr('screen_rotation_alt', 21)) + '<div class="v3fit">默认比例</div>'
           + ib(mr('fullscreen_exit', 26)) + '</div>')
    return top + bot + '<div class="lock">' + mr('lock_open', 28) + '</div>'


def v3_bars_wide(title=TITLE, programme=None, iptv=False, audio=False):
    t = f'<b>{title}</b>' + (f'<small>正在播放: {programme}</small>' if programme else '')
    top = f'<div class="v3top"><div class="title">{t}</div>' + (ib(mi('assignment')) if iptv else '') + V3AUD(audio) + ib(ci('e806')) + '</div>'
    bot = ('<div class="v3bot">' + ib(mr('pause', 28)) + ib(mr('refresh')) + '<div class="v3pill">' + mr('check', 15) + '已关注</div>'
           + ib('<span class="dmk open"></span>') + ib('<span class="dmk set"></span>') + '<div style="flex:1"></div>'
           + '<div class="v3fit">默认比例</div>' + ib(mr('volume_up', 22)) + ib(mr('unfold_more', 26)) + ib(mr('fullscreen', 26)) + '</div>')
    return top + bot


def V3AUD(audio):
    return ('<div class="ib" style="color:#FFD166">' + rx('ee04', 21) + '</div>') if audio else ib(rx('ee05', 21))


def v3_spinner():
    return '<div class="v3c"><span class="v3spin"></span></div>'


def v3_notliving(title=TITLE, full=False):
    hd = (ib(mr('arrow_back')) if full else '') + f'<div class="t">{title}</div>'
    if full:
        hd += ib(mi('swap_horiz')) + '<div class="time" style="padding:0 8px">21:36</div>'
    return (f'<div class="v3nl"><div class="hd">{hd}</div><div class="bd"><div class="a">无法播放直播</div>'
            '<p>该房间未开播或已下播</p><p>请切换其他直播间进行观看吧</p></div></div>')


def v3_loadfail():
    return ('<div class="v3lf">' + mr('error_outline', 36) + '<p>获取直播间信息失败,请重新获取</p>'
            '<div class="v3tonal">' + mr('refresh', 18) + '重试</div></div>')


def v3_failure(retrying=False):
    btn = '<div class="v3fill' + (' off' if retrying else '') + '">' + mr('refresh', 18) + '重试</div>'
    return ('<div class="dimv" style="z-index:6"></div><div class="v3pf"><div class="card"><b>播放已中断</b>'
            '<p>重新加载直播间以获取最新播放源。</p>' + btn + '</div></div>')


def v3_audio(h, restoring=False, av=IMG_AV, title=TITLE, nick='晚风'):
    compact = h < 500
    a = max(50, min(76, h * 0.22)) if compact else 100
    ts, ns, bs = (14, 11, 11) if compact else (22, 13, 13)
    gl, gm, gs = (10, 8, 4) if compact else (24, 16, 8)
    pad_n = '2px 8px' if compact else '5px 14px'
    pad_b = '5px 10px' if compact else '8px 16px'
    ic = (f'<span class="cpi w" style="width:{12 if compact else 15}px;height:{12 if compact else 15}px;--sw:1.8px"></span>') if restoring else f'<span class="rx" style="font-size:{12 if compact else 16}px;color:rgba(255,255,255,.85)">&#xee05;</span>'
    word = '正在恢复实时画面' if restoring else '纯音频模式'
    return (f'<div class="v3au"><div class="bg" style="background-image:url({av})"></div><div class="gr"></div><div class="in">'
            f'<div class="avc" style="width:{a:.0f}px;height:{a:.0f}px;background-image:url({av})"></div>'
            f'<div class="ti" style="font-size:{ts}px;margin-top:{gl}px">{title}</div>'
            f'<div class="nk" style="font-size:{ns}px;padding:{pad_n};margin-top:{gs}px">{nick}</div>'
            f'<div class="bdg{" rs" if restoring else ""}" style="font-size:{bs}px;padding:{pad_b};margin-top:{gm}px;gap:{4 if compact else 8}px">{ic}{word}</div>'
            '</div></div>')


def v3_res_row(blank=False, iptv=False):
    if blank:
        return '<div style="height:56px;flex:none"></div>'
    aud = '' if iptv else '<div class="aud">' + mr('people_alt', 14) + '在线 1.2万</div>'
    return f'<div class="res">{aud}<div class="sel">原画</div><div class="line">线路1</div></div>'


def v3_cards(n=7):
    return ''.join(f'<div class="it"><i style="background:{c}"></i><p><b>{u}: </b>{t}</p></div>' for c, u, t in CHAT[:n])


def v3_portrait(video, blank=True, toast=None, header=None, chat_cards=None):
    head = header or v3_header()
    below = ('<div style="height:56px"></div><hr>' if blank else
             v3_res_row() + '<hr><div class="tabs"><div class="on">弹幕列表</div><div>醒目留言</div><div>弹幕设置</div><div>屏蔽管理</div></div>'
             + '<div style="flex:1;min-height:0;display:flex;flex-direction:column;justify-content:flex-end;overflow:hidden;padding-bottom:12px">' + (chat_cards or v3_cards(7)) + '</div>')
    return phone(f'{head}<div class="vbox">{video}</div>{below}', toast)


def v3_land(video, toast=None):
    t = f'<div class="v3toast" style="bottom:50px">{toast}</div>' if toast else ''
    return f'<div class="fs" style="--w:852px;--h:393px">{video}<div class="syn">示意图片</div>{t}</div>'


def v3_wide(stage, blank=True, toast=None, header=None, chat=None):
    head = header or v3_header(area='哔哩哔哩 / 唱见电台', wide=True)
    if chat is None:
        chat = (v3_res_row(True) + '<hr>') if blank else (v3_res_row() + '<hr><div class="tabs"><div class="on">弹幕列表</div><div>醒目留言</div><div>弹幕设置</div><div>屏蔽管理</div></div>'
                                                       + '<div class="list" style="justify-content:flex-start">' + v3_cards(7) + '</div>')
    t = f'<div class="v3toast" style="bottom:50px">{toast}</div>' if toast else ''
    return (f'<div class="win" style="--w:1280px;--h:800px">{head}<div class="body"><div class="stage">{stage}</div>'
            f'<div class="col" style="width:400px">{chat}</div></div><div class="syn">示意图片</div>{t}</div>')


def pic(img=IMG_ROOM, dm=True, w=393, h=221, pos='center 55%'):
    d = ''.join(f'<div class="dm" style="left:{x * w:.0f}px;top:{y * h:.0f}px">{t}</div>' for x, y, t in DMS) if dm else ''
    return f'<div class="pic" style="background-image:url({img});background-position:{pos}"></div>{d}'


# ======================================================================
# new design
# ======================================================================
def vb(label, icon=None, primary=True, n=None, tag=None):
    return f'<div class="vb {"p" if primary else "o"}"{attrs(n, tag)}>{icon or ""}{label}</div>'


def stl(title='', sub='', icon=None, spin=False, avatar=None, acts=(), dim=False, cover=None, size='m', big=False):
    """The state layer: [cover] [dim] icon/spinner/avatar, title, reason, at most two buttons."""
    isz = {'s': 0, 'm': 36, 'l': 44}[size]
    head = ''
    if spin:
        head = f'<span class="spin{" l" if big else ""}"></span>'
    elif avatar:
        a = {'s': 40, 'm': 48, 'l': 64}[size]
        head = f'<div class="av2" style="width:{a}px;height:{a}px;background-image:url({avatar})"></div>'
    elif icon and isz:
        head = f'<div class="ic">{mr(icon, isz)}</div>'
    if spin and title:
        body = head + f'<div class="s" style="font-size:14px;margin-top:10px;color:rgba(255,255,255,.88)">{title}</div>' + (f'<div class="s">{sub}</div>' if sub else '')
    else:
        body = head + (f'<div class="t">{title}</div>' if title else '') + (f'<div class="s">{sub}</div>' if sub else '')
    if acts:
        body += '<div class="acts">' + ''.join(acts) + '</div>'
    under = (f'<div class="cov" style="background-image:url({cover})"></div>' if cover else '') + (('<div class="dimn l"></div>' if dim == 'l' else '<div class="dimn"></div>') if dim else '')
    return f'{under}<div class="stl">{body}</div>'


def v4_header(nick='晚风', area='哔哩哔哩 · 唱见电台', av=IMG_AV, skeleton=False, follow=True, recording=False, n=None):
    if skeleton:
        return ('<div class="appbar"><div class="back">' + mi('arrow_back') + '</div><span class="av" style="background:var(--schh)"></span>'
                '<div class="tt"><span class="sk" style="width:72px;height:14px;margin:3px 0 5px"></span><span class="sk" style="width:112px;height:10px"></span></div>'
                '<span class="sk" style="width:76px;height:32px;border-radius:16px;margin-right:4px"></span><div class="recbtn dis"><span class="ring"><i></i></span></div>'
                + ib(rx('ea42')) + '<div style="width:4px"></div></div>')
    rec = '<span class="recon"><i></i></span>' if recording else '<span class="ring"><i></i></span>'
    fol = '<div class="fol on">' + rx('eb7b') + '已关注</div>' if follow else ''
    return (f'<div class="appbar"><div class="back">{mi("arrow_back")}</div><span class="av" style="background-image:url({av})"></span>'
            f'<div class="tt"><div class="n">{nick}</div><div class="s">{area}</div></div>{fol}<div class="recbtn">{rec}</div>'
            + '<div class="ib" style="width:44px">' + rx('ea42') + '</div><div style="width:2px"></div></div>')


def v4_info(state='live', title=TITLE, n=None):
    """U.2a's two-line info row; one line when nothing plays."""
    more = '<span class="more">详情' + rx('ea4e', 18) + '</span>'
    if state == 'loading':
        return ('<div class="info"><div class="l1"><span class="t"><span class="sk" style="width:168px;height:16px"></span></span><span class="more dis">详情' + rx('ea4e', 18) + '</span></div>'
                '<div class="l2"><div class="figs"><span class="sk" style="width:52px;height:12px"></span><span class="sk" style="width:52px;height:12px"></span></div>'
                '<div class="skc" style="width:72px"></div><div class="skc" style="width:78px"></div></div></div><hr>')
    tag = {'offline': '<span class="tag3">未开播</span>', 'banned': '<span class="tag3">已封禁</span>',
           'restricted': '<span class="tag3 rd">付费</span>'}.get(state, '')
    l1 = f'<div class="l1">{tag}<span class="t">{title}</span>{more}</div>'
    if state in ('offline', 'banned', 'failed-info'):
        return f'<div class="info">{l1}</div><hr>'
    figs = ('<div class="figs"><span class="fg"><span class="mr">people_alt</span><b>1.2万</b></span><span class="fg"><span class="mr">whatshot</span><b>84.7万</b></span>'
            '<span class="fg"><span class="mr">schedule</span><b>2:18</b></span></div>')
    chips = '' if state == 'restricted' else '<div class="chip">原画' + rx('ea4e', 18) + '</div><div class="chip">线路1' + rx('ea4e', 18) + '</div>'
    return f'<div class="info">{l1}<div class="l2">{figs}{chips}</div></div><hr>'


TABS = '<div class="tabs"><div class="on">弹幕列表</div><div>醒目留言<span class="badge">2</span></div><div>弹幕设置</div><div>屏蔽管理</div></div>'
TABS0 = '<div class="tabs"><div class="on">弹幕列表</div><div>醒目留言</div><div>弹幕设置</div><div>屏蔽管理</div></div>'


def rows(k=11):
    return ''.join(f'<div class="row"><span class="u" style="{"" if c == "#000" else "color:" + c}">{u}：</span>{t}</div>' for c, u, t in CHAT[:k])


def chat_live(k=11, sys='弹幕服务器连接正常'):
    return TABS + f'<div class="list" style="flex:1;overflow:hidden;display:flex;flex-direction:column;justify-content:flex-end;padding:4px 0 14px"><div class="sys">{sys}</div>{rows(k)}</div>'


def chat_offline(n=None):
    return (TABS0 + '<div class="emp"><div class="note"><div class="h">公告</div><p>' + NOTICE + '</p><span class="more"' + attrs(n, 'add' if n else None, 'tr' if n else None) + '>展开</span></div>'
            '<div class="hint">开播后这里显示弹幕</div></div>')


def chat_empty():
    return TABS0 + '<div class="emp"></div>'


def v4_bars_portrait(audio=False, title=TITLE, programme=None, guide_n=None, catchup=False):
    sub = ''
    if programme:
        sub = f'<small>{"正在回看" if catchup else "正在播放"}: {programme}</small>'
    head = (ib(rx('ee04' if audio else 'ee05', 21), None, 'ib vic' + (' yel' if audio else '')) + ib(rx('f235'), None, 'ib vic') + ib(ci('e806'), None, 'ib vic'))
    g = ib(mi('assignment'), guide_n, 'ib vic', 'keep' if guide_n else None) if programme else ''
    top = f'<div class="vtop"><div class="title">{title}{sub}</div>{g}{head}</div>'
    bot = ('<div class="vbot">' + ib(mr('pause', 28), None, 'ib vic') + ib(mr('refresh'), None, 'ib vic') + ib('<span class="dmk open"></span>', None, 'ib vic')
           + ib('<span class="dmk set"></span>', None, 'ib vic') + '<div style="flex:1"></div>' + ib(mr('screen_rotation_alt', 21), None, 'ib vic') + ib(mr('fullscreen', 26), None, 'ib vic') + '</div>')
    return top + bot


def v4_portrait(video, info, chat, header=None, extra=''):
    head = header or v4_header()
    return phone(f'{head}<div class="vbox">{video}</div>{info}<div style="flex:1;min-height:0;display:flex;flex-direction:column;overflow:hidden">{chat}</div>{extra}')


def v4_top_land(title='深夜电台 · 点歌接龙到天亮', playing=True, audio=False, programme=None, catchup=False, n0=None, guide_n=None):
    """U.2c's fullscreen top bar; without a stream only back, time, title, switch room, record and menu stay."""
    N = (lambda k: None) if n0 is None else (lambda k: n0 + k)
    sub = f'<small>{"正在回看" if catchup else "正在播放"}: {programme}</small>' if programme else ''
    T = None if n0 is None else 'keep'
    lead = ib(mi('arrow_back'), N(0), 'ib vic', T) + '<div class="time">21:36</div><div class="bat">76</div>'
    trail = (ib(mi('assignment'), guide_n, 'ib vic', 'keep' if guide_n else None) if programme else '') + ib(mr('swap_horiz'), N(1), 'ib vic', T)
    if playing:
        trail += ib(rx('ee04' if audio else 'ee05', 21), None, 'ib vic' + (' yel' if audio else '')) + ib(rx('f235'), None, 'ib vic') + ib(ci('e806'), None, 'ib vic')
    trail += '<div class="ib"' + attrs(N(2), T) + '><span class="vring"><i></i></span></div>' + ib(rx('ea42'), N(3), 'ib vic', T)
    return f'<div class="vtop">{lead}<div class="title">{title}{sub}</div>{trail}</div>'


def v4_bot_land():
    comp = '<div class="comp"><span class="a">' + mr('auto_awesome', 18) + '</span>发送一条本地字幕<span class="s">' + mr('send', 18) + '</span></div>'
    return ('<div class="vbot" style="padding:0 12px 4px">' + ib(mr('pause', 28), None, 'ib vic') + ib(mr('refresh'), None, 'ib vic') + '<div class="vfol">' + rx('eb7b') + '已关注</div>'
            + ib('<span class="dmk open"></span>', None, 'ib vic') + ib('<span class="dmk set"></span>', None, 'ib vic')
            + f'<div style="flex:1;display:flex;justify-content:center;padding:0 8px;height:48px;align-items:center">{comp}</div>'
            + '<div class="vchip" style="margin:0 3px">原画' + rx('ea4e', 18) + '</div><div class="vchip" style="margin:0 3px">线路1' + rx('ea4e', 18) + '</div>'
            + ib(mr('screen_rotation_alt', 21), None, 'ib vic') + ib(rx('ea80', 22), None, 'ib vic') + ib(mr('fullscreen_exit', 26), None, 'ib vic') + '</div>')


def v4_land(inner, toast=None):
    t = f'<div class="toast" style="bottom:96px">{toast}</div>' if toast else ''
    return f'<div class="fs" style="--w:852px;--h:393px">{inner}<div class="syn">示意图片</div>{t}</div>'


def v4_wide_stage_bars(audio=False, title=TITLE, programme=None, catchup=False, guide_n=None):
    sub = f'<small>{"正在回看" if catchup else "正在播放"}: {programme}</small>' if programme else ''
    g = ib(mi('assignment'), guide_n, 'ib vic') if programme else ''
    top = (f'<div class="vtop"><div class="title">{title}{sub}</div>{g}' + ib(rx('ee04' if audio else 'ee05', 21), None, 'ib vic' + (' yel' if audio else ''))
           + ib(ci('e806'), None, 'ib vic') + '</div>')
    bot = ('<div class="vbot"><div style="display:flex;align-items:center">' + ib(mr('pause', 28), None, 'ib vic') + ib(mr('refresh'), None, 'ib vic')
           + ib('<span class="dmk open"></span>', None, 'ib vic') + ib('<span class="dmk set"></span>', None, 'ib vic') + '</div><div style="flex:1"></div>'
           '<div style="display:flex;align-items:center"><div class="vvol">' + mr('volume_up', 22) + '<div class="t"><i></i><u></u></div></div>'
           + ib(mr('vertical_split', 24), None, 'ib vic') + ib(mr('unfold_more', 26), None, 'ib vic') + ib(mr('fullscreen', 26), None, 'ib vic') + '</div></div>')
    return top + bot


def v4_wide(stage, col, header=None, handle=True, toast=None):
    head = header or v4_header()
    hd = '<div class="collapse" style="right:400px">' + mr('chevron_right', 20) + '</div>' if handle else ''
    t = f'<div class="toast" style="bottom:40px;left:440px">{toast}</div>' if toast else ''
    return (f'<div class="win" style="--w:1280px;--h:800px">{head}<div class="body"><div class="stage">{stage}</div>'
            f'<div class="col" style="width:400px">{col}</div>{hd}</div><div class="syn">示意图片</div>{t}</div>')


def wcol(info, chat):
    return info + f'<div style="flex:1;display:flex;flex-direction:column;min-height:0">{chat}</div>'


# ---------------- the guide (new) ----------------
def gd_rows(mode='live', compact=False, n=None):
    """mode: live | catchup. Rows around the playing programme, grouped by day."""
    out = []

    def row(t, title, kind, label=None, nn=None):
        right = ''
        if kind == 'past':
            right = '<span class="rt">' + rx('ee17') + '回看</span>'
        elif kind == 'live':
            right = '<span class="livet">' + rx('eec0') + '正在直播</span>'
        elif kind == 'cu':
            right = '<span class="rt" style="font-weight:600">回看中</span>'
        cls = {'past': 'past', 'live': 'cur' if mode == 'live' else '', 'cu': 'cu', 'gone': 'gone', 'next': ''}[kind]
        if kind == 'live' and mode == 'catchup':
            cls = ''
        out.append(f'<div class="gd-r {cls}"{attrs(nn, 'chg' if nn else None)}><span class="tm">{t}</span><span class="tt">{title}</span>{right}</div>')

    if mode == 'live':
        out.append('<div class="gd-d">今天 · 10月1日 周四</div>')
        for i, (t, title) in enumerate(TODAY[2:]):
            kind = 'past' if t < '21:30' else ('live' if t == '21:30' else 'next')
            row(t, title, kind, nn=(n if (n and i == 0) else None))
        out.append('<div class="gd-d">明天 · 10月2日 周五</div>')
        for t, title in TMRW:
            row(t, title, 'next')
    else:
        out.append('<div class="gd-d">今天 · 10月1日 周四</div>')
        for i, (t, title) in enumerate(TODAY[1:]):
            kind = 'cu' if t == '19:30' else ('past' if t < '21:30' else ('live' if t == '21:30' else 'next'))
            row(t, title, kind)
        out.append('<div class="gd-d">明天 · 10月2日 周五</div>')
        for t, title in TMRW[:2]:
            row(t, title, 'next')
    return ''.join(out)


def guide(mode='live', panel=False, n=None, close_n=None, ret_n=None, row_n=None):
    x = f'<div class="x"{attrs(close_n, 'keep' if close_n else None)}>' + mr('close', 22) + '</div>' if panel else '<div style="width:12px"></div>'
    head = ('<div class="gd-h">' + f'<span style="color:var(--primary)">{rx("eb29", 20)}</span><span class="t">节目单</span><span class="w">可回看 2 天</span><span class="sp"></span>' + x + '</div>')
    cu = ''
    if mode == 'catchup':
        cu = (f'<div class="gd-cu"><div class="x"><div class="a">正在回看 · 今天 19:30</div><div class="b">{CU_PROG}</div></div>'
              f'<div class="go"{attrs(ret_n, 'chg' if ret_n else None)}>' + rx('eec0', 18) + '返回直播</div></div>')
    return f'<div class="gd">{head}{cu}<div class="gd-l">{gd_rows(mode, n=row_n)}</div></div>'


def guide_state(kind):
    if kind == 'loading':
        return '<div class="gd-st"><span class="cpi" style="width:28px;height:28px;--sw:3px"></span><p>正在读取节目单…</p></div>'
    if kind == 'failed':
        return ('<div class="gd-st">' + rx('eca1', 36) + '<div class="t">节目单读取失败</div><p>数据加载失败</p><div class="bt" data-n="3" data-tag="keep">' + mr('refresh', 18) + '重试</div></div>')
    if kind == 'none':
        return ('<div class="gd-st">' + rx('eb29', 36) + '<div class="t">还没有节目单</div><p>节目单用来在直播间显示正在播放和接下来的节目，并支持回看。</p>'
                '<div class="bt" data-n="19" data-tag="add">' + rx('ea13', 18) + '去导入节目单</div></div>')
    return ('<div class="gd-st">' + rx('ee4f', 36) + '<div class="t">暂无后续节目排班信息</div><p>这个频道在节目单里没有节目</p></div>')


# ---------------- v3 IPTV dialog ----------------
def v3_prog_tile(t, title, status, cur, stacked, ext):
    st = {'live': '<span class="v3live">' + rx('eec0', 11) + '正在直播</span>', 'hist': '<span class="v3hist">' + rx('ee17', 16) + '</span>',
          'gone': '<span class="v3hist off">' + rx('ee17', 16) + '</span>', 'none': ''}[status]
    tc = f'<span class="tc">{t}</span>'
    inner = (f'<div class="w">{tc}{st}</div><span class="tt">{title}</span>' if stacked else f'{tc}<span class="tt">{title}</span>{st}')
    return f'<div class="v3pt{" cur" if cur else ""}{" st" if stacked else ""}" style="height:{ext}px"><div class="m">{inner}</div></div>'


def v3_dialog(left, top, w, h, mode='live', state=None):
    stacked = w - 32 < 340
    ext = 120 if stacked else 84
    head = ('<div class="v3dh"><span class="ic">' + rx('eb29', 22) + '</span><span class="t">电视节目表预告</span><span class="x">' + rx('eb99', 20) + '</span></div><div class="v3dd"></div>')
    ret = ('<div class="v3ret">' + rx('eec0', 18) + '返回直播</div>') if mode == 'catchup' else ''
    if state == 'loading':
        body = '<div class="v3gl"><div class="v3st"><span class="cpi" style="width:36px;height:36px"></span></div></div>'
    elif state == 'failed':
        body = ('<div class="v3gl"><div class="v3st"><span style="color:var(--error)">' + rx('eca1', 40) + '</span><p>数据加载失败</p>'
                '<div class="v3fill" style="margin-top:16px">' + rx('f064', 18) + '重试</div></div></div>')
    elif state == 'empty':
        body = ('<div class="v3gl"><div class="v3st"><span style="color:rgba(25,28,32,.24)">' + rx('ee4f', 40) + '</span><p>暂无后续节目排班信息</p></div></div>')
    else:
        if mode == 'live':
            items = [(t, ti, 'live' if t == '21:30' else 'none', t == '21:30') for t, ti in TODAY[4:]] + [(t, ti, 'none', False) for t, ti in TMRW]
        else:
            items = [(t, ti, 'hist', t == '19:30') for t, ti in TODAY[2:4]] + [(TODAY[4][0], TODAY[4][1], 'live', False)] + [(t, ti, 'none', False) for t, ti in TODAY[5:]]
        tiles = ''.join(v3_prog_tile(t, ti, s, c, stacked, ext) for t, ti, s, c in items)
        body = f'<div class="v3gl">{tiles}</div>'
    return (f'<div class="scrim"></div><div class="v3dlg" style="left:{left}px;top:{top}px;width:{w}px;height:{h}px">{head}{ret}{body}</div>')


# ======================================================================
# pages
# ======================================================================
OUT = {}

# ---------- overview sheets (picture area only, portrait size) ----------
def cell(cap, inner, sub=''):
    return f'<div class="cell"><div class="cap">{cap}<small>{sub}</small></div><div class="vbox">{inner}</div></div>'


V3_CELLS = [
    ('加载中', '进房、刷新、换清晰度和线路时', v3_spinner()),
    ('未开播', '同时弹提示条“当前主播未开播或已下播”', v3_notliving()),
    ('已封禁', '和未开播一样；提示条却是“服务器错误,请稍后获取”', v3_notliving()),
    ('获取直播间信息失败', '同时弹同一句提示条', v3_loadfail()),
    ('播放已中断', '原因在 3 秒的提示条里，例如“网络连接失败”', pic(dm=False) + v3_failure()),
    ('播放已中断 · 重试中', '按钮变灰', pic(dm=False) + v3_failure(True)),
    ('断流、自动重连', '画面停在最后一帧，没有任何提示', pic(dm=False)),
    ('在播但放不了（登录、付费、地区）', '一直转圈；提示条“读取视频信息失败”', v3_spinner()),
    ('纯音频模式', '', v3_audio(221)),
    ('正在恢复实时画面', '从纯音频切回画面时', v3_audio(221, restoring=True)),
]


def v3_sheet():
    cells = ''.join(cell(c, inner, s) for c, s, inner in V3_CELLS)
    return doc(820, 3200, 2, f'<div class="sheet2"><div class="hd2">v3：画面区域的各种状态（竖屏尺寸，控制栏省略）</div>{cells}</div>', crop=True)


def v4_cells(n=True):
    N = (lambda k: k) if n else (lambda k: None)
    sw = lambda: vb('切换直播间', mr('swap_horiz', 18), True, N(1), 'chg')
    rf = lambda p=False: vb('刷新', mr('refresh', 18), p, N(2), 'add')
    rt = lambda p=True: vb('重试', mr('refresh', 18), p, N(3), 'keep')
    ln = lambda p=False: vb('换线路', mr('alt_route', 18), p, N(4), 'add')
    return [
        ('进房中', '名字、信息行先显示占位（E2）', stl('正在进入直播间…', spin=True)),
        ('连接直播流', '直播间信息已拿到，正在打开画面', stl('正在连接直播流…', spin=True)),
        ('加载较慢', '超过 8 秒仍没有画面', stl('正在连接直播流…', '比平时慢，可以换一条线路试试', spin=True, acts=(ln(True), rt(False)))),
        ('未开播', '每 60 秒查一次，开播自动开始播放', stl('当前主播未开播或已下播', '开播后会自动开始播放', avatar=IMG_AV, cover=IMG_ROOM, acts=(sw(), rf()))),
        ('已封禁', '', stl('该直播间已被平台封禁或关闭', icon='block', cover=IMG_ROOM, acts=(sw(), rf()))),
        ('轮播', '平台在放往期视频', stl('主播未开播，正在轮播往期视频', '开播后会自动开始播放', avatar=IMG_AV, cover=IMG_ROOM, acts=(sw(), rf()))),
        ('获取直播间信息失败', '按原因写（网络、风控、接口变化）', stl('网络连接失败，请检查网络或代理后重试', icon='error_outline', acts=(rt(), sw()))),
        ('直播间不存在', '', stl('直播间不存在或已被删除', icon='error_outline', acts=(sw(),))),
        ('暂时无法确认直播状态', '平台没说在不在播', stl('暂时无法确认直播状态', icon='help_outline', acts=(rf(True), sw()))),
        ('播放已中断', '原因写在这里，不再另弹提示条；控制栏照常', pic(dm=False) + stl('播放已中断', '网络连接失败', icon='error_outline', dim=True, acts=(rt(), ln()))),
        ('正在重连', 'U.2a E3；换线路只在有多条线路时出现', pic(dm=False) + stl('正在重连（第 2 次）', spin=True, dim='l', acts=(ln(),))),
        ('受限 · 付费', '原因 + 下一步', stl('这是付费直播，需要在平台购买后观看', icon='lock_outline', cover=IMG_ROOM, acts=(vb('在哔哩哔哩打开', mr('open_in_new', 18), True, N(6), 'add'), vb('切换直播间', mr('swap_horiz', 18), False, N(1), 'chg')))),
        ('受限 · 需要登录', '', stl('该直播需要登录平台账号才能观看', icon='lock_outline', cover=IMG_ROOM, acts=(vb('去登录', mr('login', 18), True, N(5), 'add'), rt(False)))),
        ('受限 · 地区', '换了代理可以重试', stl('该直播在你所在的地区不可观看', icon='lock_outline', cover=IMG_ROOM, acts=(rt(), sw() .replace('vb p', 'vb o')))),
        ('不可播放', '平台显示在播，但没有给出地址', stl('平台显示在播，但没有给出可播放的地址', icon='videocam_off', cover=IMG_ROOM, acts=(rt(), sw().replace('vb p', 'vb o')))),
        ('纯音频播放中', 'U.2a E5；耳机图标变黄', '<div class="cov" style="background-image:url(' + IMG_ROOM + ')"></div><div class="stl"><div class="ic">' + rx('ee04', 40) + '</div><div class="s" style="font-size:14px;margin-top:8px">纯音频播放中</div></div>'),
        ('正在恢复实时画面', '从纯音频切回画面', '<div class="cov" style="background-image:url(' + IMG_ROOM + ')"></div><div class="stl"><span class="spin"></span><div class="s" style="font-size:14px;margin-top:10px">正在恢复实时画面</div></div>'),
        ('回放已播完', '录播、回看的视频放完', pic(dm=False) + stl('回放已播完', icon='replay', dim=True, acts=(vb('从头播放', mr('replay', 18), True, N(7), 'add'), vb('切换直播间', mr('swap_horiz', 18), False, N(1), 'chg')))),
    ]


def v4_sheet(n=True):
    cells = ''.join(cell(c, inner, s) for c, s, inner in v4_cells(n))
    return doc(820, 3800, 2, f'<div class="sheet2"><div class="hd2">新设计：画面区域的各种状态，一个组件（竖屏尺寸，控制栏省略）</div>{cells}</div>', crop=True)


OUT['v3-states'] = v3_sheet()
OUT['v4-states'] = v4_sheet()

# ---------- portrait ----------
OUT['v3-p-loading'] = doc(393, 852, 3, v3_portrait(v3_spinner(), header=v3_header(nick='', area='哔哩哔哩', av=None, follow='spin')))
OUT['v4-p-loading'] = doc(393, 852, 3, v4_portrait(stl('正在进入直播间…', spin=True), v4_info('loading'), chat_empty(), header=v4_header(skeleton=True)))

OUT['v3-p-offline'] = doc(393, 852, 3, v3_portrait(v3_notliving(), toast='当前主播未开播或已下播'))
OUT['v4-p-offline'] = doc(393, 852, 3, v4_portrait(
    stl('当前主播未开播或已下播', '开播后会自动开始播放', avatar=IMG_AV, cover=IMG_ROOM, size='s',
        acts=(vb('切换直播间', mr('swap_horiz', 18), True, 1, 'chg'), vb('刷新', mr('refresh', 18), False, 2, 'add'))),
    v4_info('offline'), chat_offline(n=17)))

OUT['v3-p-failed'] = doc(393, 852, 3, v3_portrait(pic(dm=False) + v3_failure(), blank=False, toast='网络连接失败'))
OUT['v4-p-failed'] = doc(393, 852, 3, v4_portrait(pic(dm=False) + stl('播放已中断', '网络连接失败', dim=True, acts=(vb('重试', mr('refresh', 18)), vb('换线路', mr('alt_route', 18), False))),
                                                 v4_info('live'), chat_live()))

OUT['v3-p-reconnect'] = doc(393, 852, 3, v3_portrait(pic(), blank=False))
OUT['v4-p-reconnect'] = doc(393, 852, 3, v4_portrait(pic(dm=False) + stl('正在重连（第 2 次）', spin=True, dim='l', acts=(vb('换线路', mr('alt_route', 18), False),)),
                                                    v4_info('live'), chat_live()))

OUT['v3-p-restricted'] = doc(393, 852, 3, v3_portrait(v3_spinner(), toast='读取视频信息失败'))
OUT['v4-p-restricted'] = doc(393, 852, 3, v4_portrait(
    stl('这是付费直播，需要在平台购买后观看', icon='lock_outline', cover=IMG_ROOM, size='m',
        acts=(vb('在哔哩哔哩打开', mr('open_in_new', 18)), vb('切换直播间', mr('swap_horiz', 18), False))),
    v4_info('restricted'), chat_live()))

OUT['v3-p-audio'] = doc(393, 852, 3, v3_portrait(v3_audio(221) + v3_bars_portrait(audio=True), blank=False))
OUT['v4-p-audio'] = doc(393, 852, 3, v4_portrait(
    '<div class="cov" style="background-image:url(' + IMG_ROOM + ')"></div><div class="stl"><div class="ic">' + rx('ee04', 40) + '</div><div class="s" style="font-size:14px;margin-top:8px">纯音频播放中</div></div>'
    + v4_bars_portrait(audio=True), v4_info('live'), chat_live()))

# ---------- landscape (fullscreen) ----------
OUT['v3-l-loading'] = doc(852, 393, 2, v3_land(v3_spinner()))
OUT['v4-l-loading'] = doc(852, 393, 2, v4_land(stl('正在进入直播间…', spin=True) + v4_top_land(playing=False)))

OUT['v3-l-offline'] = doc(852, 393, 2, v3_land(v3_notliving(title='深夜电台 · 点歌接龙到天亮', full=True)))
OUT['v4-l-offline'] = doc(852, 393, 2, v4_land(
    stl('当前主播未开播或已下播', '开播后会自动开始播放', avatar=IMG_AV, cover=IMG_ROOM, size='m',
        acts=(vb('切换直播间', mr('swap_horiz', 18), True, 1, 'chg'), vb('刷新', mr('refresh', 18), False, 2, 'add')))
    + v4_top_land(playing=False, n0=13)))

LAND_PIC = '<div class="pic" style="background-image:url(.cache/img/274.jpg);background-position:center 40%"></div>'
OUT['v3-l-failed'] = doc(852, 393, 2, v3_land(LAND_PIC + v3_bars_land(title='纽约时代广场，夜游直播') + v3_failure(), toast='网络连接失败'))
OUT['v4-l-failed'] = doc(852, 393, 2, v4_land(LAND_PIC + stl('播放已中断', '网络连接失败', icon='error_outline', dim=True, acts=(vb('重试', mr('refresh', 18)), vb('换线路', mr('alt_route', 18), False)))
                                              + v4_top_land('纽约时代广场，夜游直播') + v4_bot_land() + '<div class="lock">' + mr('lock_open', 28) + '</div>'))

OUT['v3-l-reconnect'] = doc(852, 393, 2, v3_land(LAND_PIC + v3_bars_land(title='纽约时代广场，夜游直播')))
OUT['v4-l-reconnect'] = doc(852, 393, 2, v4_land(LAND_PIC + stl('正在重连（第 2 次）', spin=True, dim='l', acts=(vb('换线路', mr('alt_route', 18), False),))
                                                 + v4_top_land('纽约时代广场，夜游直播') + v4_bot_land() + '<div class="lock">' + mr('lock_open', 28) + '</div>'))

OUT['v3-l-restricted'] = doc(852, 393, 2, v3_land(v3_spinner(), toast='读取视频信息失败'))
OUT['v4-l-restricted'] = doc(852, 393, 2, v4_land(
    stl('这是付费直播，需要在平台购买后观看', icon='lock_outline', cover=IMG_ROOM, size='l',
        acts=(vb('在哔哩哔哩打开', mr('open_in_new', 18)), vb('切换直播间', mr('swap_horiz', 18), False)))
    + v4_top_land(playing=False)))

OUT['v3-l-audio'] = doc(852, 393, 2, v3_land(v3_audio(393) + v3_bars_land(audio=True)))
OUT['v4-l-audio'] = doc(852, 393, 2, v4_land(
    '<div class="cov" style="background-image:url(' + IMG_ROOM + ')"></div><div class="stl"><div class="ic">' + rx('ee04', 44) + '</div><div class="s" style="font-size:14px;margin-top:8px">纯音频播放中</div></div>'
    + v4_top_land(audio=True) + v4_bot_land() + '<div class="lock">' + mr('lock_open', 28) + '</div>'))

# ---------- wide ----------
WPIC = '<div class="pic2" style="background-image:url(' + IMG_ROOM + ')"></div>'
OUT['v3-w-loading'] = doc(1280, 800, 1.5, v3_wide(v3_spinner()))
OUT['v4-w-loading'] = doc(1280, 800, 1.5, v4_wide(stl('正在进入直播间…', spin=True, big=True), wcol(v4_info('loading'), chat_empty())))

OUT['v3-w-offline'] = doc(1280, 800, 1.5, v3_wide(v3_notliving(), toast='当前主播未开播或已下播'))
OUT['v4-w-offline'] = doc(1280, 800, 1.5, v4_wide(
    stl('当前主播未开播或已下播', '开播后会自动开始播放', avatar=IMG_AV, cover=IMG_ROOM, size='l',
        acts=(vb('切换直播间', mr('swap_horiz', 18)), vb('刷新', mr('refresh', 18), False))),
    wcol(v4_info('offline'), chat_offline())))

OUT['v3-w-failed'] = doc(1280, 800, 1.5, v3_wide(WPIC + v3_bars_wide() + v3_failure(), blank=False, toast='网络连接失败'))
OUT['v4-w-failed'] = doc(1280, 800, 1.5, v4_wide(WPIC + stl('播放已中断', '网络连接失败', icon='error_outline', size='l', dim=True,
                                                            acts=(vb('重试', mr('refresh', 18)), vb('换线路', mr('alt_route', 18), False))) + v4_wide_stage_bars(),
                                                  wcol(v4_info('live'), chat_live(12))))

OUT['v3-w-reconnect'] = doc(1280, 800, 1.5, v3_wide(WPIC + v3_bars_wide(), blank=False))
OUT['v4-w-reconnect'] = doc(1280, 800, 1.5, v4_wide(WPIC + stl('正在重连（第 2 次）', spin=True, big=True, dim='l', acts=(vb('换线路', mr('alt_route', 18), False),)) + v4_wide_stage_bars(),
                                                     wcol(v4_info('live'), chat_live(12))))

OUT['v3-w-restricted'] = doc(1280, 800, 1.5, v3_wide(v3_spinner(), toast='读取视频信息失败'))
OUT['v4-w-restricted'] = doc(1280, 800, 1.5, v4_wide(
    stl('这是付费直播，需要在平台购买后观看', icon='lock_outline', cover=IMG_ROOM, size='l',
        acts=(vb('在哔哩哔哩打开', mr('open_in_new', 18)), vb('切换直播间', mr('swap_horiz', 18), False))),
    wcol(v4_info('restricted'), chat_live(12))))

OUT['v3-w-audio'] = doc(1280, 800, 1.5, v3_wide(v3_audio(495) + v3_bars_wide(audio=True), blank=False))
OUT['v4-w-audio'] = doc(1280, 800, 1.5, v4_wide(
    '<div class="cov" style="background-image:url(' + IMG_ROOM + ')"></div><div class="stl"><div class="ic">' + rx('ee04', 44) + '</div><div class="s" style="font-size:15px;margin-top:8px">纯音频播放中</div></div>'
    + v4_wide_stage_bars(audio=True), wcol(v4_info('live'), chat_live(12))))

# ---------- IPTV: guide and catch-up ----------
TV_PIC = f'<div class="pic" style="background-image:url({IMG_TV});background-position:center 45%"></div>'
TV_HEAD_V3 = v3_header(nick=CH, area='网络 / ' + GROUP, av=IMG_TVAV)
TV_HEAD_V4 = v4_header(nick=CH, area='网络 · ' + GROUP, av=IMG_TVAV)


def v3_iptv_portrait(dialog=False):
    video = TV_PIC + v3_bars_portrait(title=CH, programme=LIVE_PROG, iptv=True)
    dlg = v3_dialog(40, 151, 313, 550) if dialog else ''
    return doc(393, 852, 3, phone(f'{TV_HEAD_V3}<div class="vbox">{video}</div>{dlg}'))


OUT['v3-p-iptv'] = v3_iptv_portrait()
OUT['v3-p-iptv-guide'] = v3_iptv_portrait(True)
OUT['v4-p-iptv'] = doc(393, 852, 3, phone(f'{TV_HEAD_V4}<div class="vbox">{TV_PIC}{v4_bars_portrait(title=CH, programme=LIVE_PROG, guide_n=8)}</div>'
                                          f'<div style="flex:1;min-height:0;display:flex;flex-direction:column">{guide("live", row_n=9)}</div>'))
OUT['v4-p-iptv-catchup'] = doc(393, 852, 3, phone(
    f'{TV_HEAD_V4}<div class="vbox">{TV_PIC}{v4_bars_portrait(title=CH, programme=CU_PROG, catchup=True)}'
    '<div class="cbadge" style="top:68px"' + attrs(11, 'add') + '>' + rx('ee17') + '回看 19:30<span class="go">返回直播</span></div></div>'
    f'<div style="flex:1;min-height:0;display:flex;flex-direction:column">{guide("catchup", ret_n=10)}</div>'))

TV_LAND = f'<div class="pic" style="background-image:url({IMG_TV});background-position:center 45%"></div>'
OUT['v3-l-iptv-guide'] = doc(852, 393, 2, v3_land(TV_LAND + v3_bars_land(title=CH, programme=LIVE_PROG, iptv=True) + v3_dialog(196, 24, 460, 345, mode='catchup')))
OUT['v4-l-iptv-guide'] = doc(852, 393, 2, v4_land(
    TV_LAND + v4_top_land(CH, programme=CU_PROG, catchup=True)
    + '<div class="cbadge" style="top:70px;left:16px"' + attrs(11, 'add') + '>' + rx('ee17') + '回看 19:30<span class="go">返回直播</span></div>'
    + '<div class="side" style="width:360px">' + guide('catchup', panel=True, close_n=18, ret_n=10) + '</div>'))

WTV = f'<div class="pic2" style="background-image:url({IMG_TV});background-position:center 45%"></div>'
OUT['v3-w-iptv-guide'] = doc(1280, 800, 1.5,
    '<div class="win" style="--w:1280px;--h:800px">' + v3_header(nick=CH, area='网络 / ' + GROUP, av=IMG_TVAV, wide=True)
    + f'<div style="position:relative;width:1280px;aspect-ratio:16/9;background:#000;overflow:hidden"><div class="pic" style="background-image:url({IMG_TV});background-position:center 45%"></div>'
    + v3_bars_wide(title=CH, programme=LIVE_PROG, iptv=True) + '</div>'
    + v3_dialog(410, 140, 460, 520) + '<div class="syn">示意图片</div></div>')
OUT['v4-w-iptv'] = doc(1280, 800, 1.5, v4_wide(WTV + v4_wide_stage_bars(title=CH, programme=LIVE_PROG), guide('live'),
                                                header=v4_header(nick=CH, area='网络 · ' + GROUP, av=IMG_TVAV)).replace('class="collapse"', 'class="collapse" data-n="12" data-tag="add" data-at="tl"'))

# guide states: v3 dialog (loading, failed, empty) and the new component (loading, failed, no guide, empty)
def guide_sheet_v3():
    cells = ''
    for cap, st in (('加载中', 'loading'), ('加载失败', 'failed'), ('没有节目（含没配置节目单来源）', 'empty')):
        d = v3_dialog(0, 0, 250, 300, state=st).replace('<div class="scrim"></div>', '')
        cells += f'<div><div class="cap" style="font-size:13px;font-weight:600;margin:0 0 6px 2px">{cap}</div><div style="position:relative;width:250px;height:300px">{d}</div></div>'
    return doc(820, 360, 2, f'<div style="display:flex;gap:16px;padding:12px 11px;background:var(--surface)">{cells}</div>', crop=True)


def guide_sheet_v4():
    cells = ''
    for cap, st in (('加载中', 'loading'), ('加载失败', 'failed'), ('没配置节目单来源', 'none'), ('频道没有节目', 'empty')):
        body = ('<div class="gd"><div class="gd-h"><span style="color:var(--primary)">' + rx('eb29', 20) + '</span><span class="t">节目单</span></div>' + guide_state(st) + '</div>')
        cells += (f'<div><div class="cap" style="font-size:13px;font-weight:600;margin:0 0 6px 2px">{cap}</div>'
                  f'<div style="width:393px;height:250px;display:flex;flex-direction:column;border:1px solid var(--ov);border-radius:12px;overflow:hidden">{body}</div></div>')
    return doc(820, 700, 2, f'<div style="display:grid;grid-template-columns:393px 393px;gap:14px 12px;padding:12px 11px;background:var(--surface)">{cells}</div>', crop=True)


OUT['v3-guide-states'] = guide_sheet_v3()
OUT['v4-guide-states'] = guide_sheet_v4()

for name, html in OUT.items():
    open(os.path.join(HERE, name + '.html'), 'w', encoding='utf-8').write(html)
print(len(OUT), 'pages')
