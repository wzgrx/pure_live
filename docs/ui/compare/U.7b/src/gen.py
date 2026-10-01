"""U.7b recording settings: v3 restored and the new design.

v3 (tag v3.2.11):
  page      lib/recorder/pages/record_settings/record_settings_page.dart (groups :36-228,
            cache header :273-313, dialogs :329-471, integer dialog :482-622)
  rows      lib/common/widgets/widget_extensions.dart (group title :21-36, card :38-112,
            switch row :114-152, row :154-268, slider row :352-460; content max 960 :8)
  defaults  lib/recorder/consts/recorder_config.dart:12-71
  theme     lib/common/style/theme.dart (app bar centred 20/600, dialog surfaceContainerHigh r24)

    python3 docs/ui/compare/U.7b/src/gen.py && python3 tools/ui/mock/render.py docs/ui/compare/U.7b/src/ --annotate
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
CSS = '''
.col{display:flex;flex-direction:column}
.ab{height:56px;display:flex;align-items:center;position:relative;flex:none;background:var(--surface)}
.ab .ttl{position:absolute;left:0;right:0;text-align:center;font-size:20px;font-weight:600;pointer-events:none}
.ab .ib.lead{color:var(--on);margin-left:4px}
.body{flex:1;min-height:0;overflow:hidden;position:relative}
.lst{padding:0 16px 16px;margin:0 auto;min-width:0;width:100%}
/* ---------- v3 rows (widget_extensions.dart) ---------- */
.gt{padding:0 0 8px 8px;font-size:12px;font-weight:700;letter-spacing:.5px;color:rgba(54,97,142,.65)}
.gt.row2{display:flex;align-items:center;justify-content:space-between;padding-bottom:0}
.gt .act{display:flex;align-items:center;gap:6px;height:48px;padding-right:8px;font-size:14px;font-weight:600;letter-spacing:0;color:var(--primary)}
.cd{background:rgba(225,226,232,.15);border:.5px solid rgba(0,0,0,.05);border-radius:20px;overflow:hidden;margin-bottom:20px}
.tl{display:flex;align-items:flex-start;gap:12px;padding:8px 16px;min-height:56px}
.tl.sw2{padding:6px 8px 6px 16px;align-items:center}
.tl .ic{color:var(--primary);padding-top:2px;flex:none;width:22px}
.tl .x{flex:1;min-width:0;align-self:center}
.tl .a{font-size:15px;font-weight:600;line-height:1.35}
.tl .b{font-size:12px;color:rgba(0,0,0,.45);margin-top:2px;line-height:1.4;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.tl .b.long{white-space:normal}
.tl .ch{color:rgba(0,0,0,.24);padding-top:4px;flex:none}
.tl .sp2{width:20px;height:20px;border-radius:10px;border:2px solid rgba(54,97,142,.25);border-top-color:var(--primary);flex:none;margin-top:4px}
.sdr{display:flex;gap:12px;padding:10px 16px}
.sdr .ic{color:var(--primary);padding-top:2px;width:24px;flex:none}
.sdr .x{flex:1;min-width:0}
.sdr .h{display:flex;justify-content:space-between;align-items:flex-start;gap:12px}
.sdr .a{font-size:15px;font-weight:600}
.sdr .v{padding:2px 8px;border-radius:6px;background:rgba(54,97,142,.1);font-size:13px;font-weight:700;color:var(--primary);font-feature-settings:'tnum';white-space:nowrap}
.trk{height:4px;border-radius:2px;background:rgba(54,97,142,.15);position:relative;margin:20px 6px 12px 2px}
.trk i{position:absolute;left:0;top:0;bottom:0;border-radius:2px;background:var(--primary)}
.trk u{position:absolute;top:-8px;width:20px;height:20px;border-radius:10px;background:var(--primary);margin-left:-10px}
/* ---------- dialogs ---------- */
.sheetbg{background:var(--scc)}
.cap{padding:20px 16px 8px;font-size:13px;font-weight:600;color:var(--onv)}
.dl{margin:0 16px 8px;background:var(--sch);border-radius:24px;padding:24px 0 0;overflow:hidden}
.dl .h{padding:0 24px;font-size:20px;font-weight:700;line-height:1.35}
.dl .c{padding:16px 24px 0;font-size:13px;line-height:1.6;color:var(--onv)}
.dl .rl{padding:8px 12px 16px}
.rr{display:flex;align-items:center;gap:16px;padding:10px 16px;border-radius:16px;min-height:56px}
.rr .rd{width:20px;height:20px;border-radius:10px;border:2px solid var(--onv);flex:none;display:grid;place-items:center}
.rr.on{background:rgba(54,97,142,.05)}
.rr.on .rd{border-color:var(--primary)}.rr.on .rd::after{content:'';width:10px;height:10px;border-radius:5px;background:var(--primary)}
.rr .t{font-size:15px;font-weight:600}.rr .d{font-size:12px;margin-top:2px;color:var(--onv)}
.rr.on .t{color:var(--primary)}
.dl .acts{display:flex;justify-content:flex-end;gap:8px;padding:24px 24px 24px}
.dl .acts span{height:40px;padding:0 16px;border-radius:20px;display:flex;align-items:center;font-size:13px;font-weight:600;color:var(--primary)}
.dl .acts .f{background:var(--primary);color:var(--onPrimary)}
.dl .acts .e{background:var(--scl);color:var(--primary);border-radius:12px;padding:0 24px}
.dl .acts .r{background:var(--error);color:#fff}
.inp{margin:16px 24px 0;height:56px;border-radius:12px;border:1px solid var(--outline);background:var(--scl);position:relative;display:flex;align-items:center;padding:0 16px;font-size:20px}
.inp .lb{position:absolute;left:12px;top:-9px;padding:0 4px;background:var(--sch);font-size:12px;color:var(--onv)}
.qs{padding:16px 24px 0;font-size:14px;font-weight:600}
.qc{display:flex;flex-wrap:wrap;gap:8px;padding:8px 24px 0}
.qc span{height:32px;min-width:40px;padding:0 12px;border-radius:8px;border:1px solid var(--outline);display:grid;place-items:center;font-size:14px}
.qc span.on{background:rgba(54,97,142,.2);border-color:transparent}
/* ---------- new ---------- */
.ng{padding:16px 8px 8px;font-size:13px;font-weight:600;color:var(--primary)}
.ng:first-child{padding-top:8px}
.nc{background:var(--scl);border-radius:20px;overflow:hidden}
.nt{display:flex;align-items:center;gap:14px;padding:10px 12px 10px 16px;min-height:56px;position:relative}
.nt+.nt::before{content:'';position:absolute;left:52px;right:16px;top:0;height:1px;background:var(--ov);opacity:.5}
.nt .ic{color:var(--primary);flex:none;width:22px;align-self:flex-start;padding-top:3px}
.nt .x{flex:1;min-width:0}
.nt .a{font-size:15px;font-weight:600;line-height:1.4}
.nt .b{font-size:12px;color:var(--onv);margin-top:2px;line-height:1.45;overflow-wrap:anywhere}
.nt .v{font-size:14px;color:var(--onv);white-space:nowrap;font-feature-settings:'tnum'}
.nt .ch{color:var(--onv);margin-left:-8px}
.nt.dis .ic,.nt.dis .x,.nt.dis .v,.nt.dis .ch,.nt.dis .sw,.nt.dis .stp{opacity:.38}
.nt .ib2{width:40px;height:40px;border-radius:20px;display:grid;place-items:center;color:var(--primary);flex:none}
.stp{display:flex;align-items:center;gap:4px;flex:none}
.stp b{width:36px;height:36px;border-radius:18px;box-shadow:inset 0 0 0 1px var(--ov);display:grid;place-items:center;color:var(--primary);font-weight:400}
.stp em{font-style:normal;min-width:28px;text-align:center;font-size:16px;font-weight:600;font-feature-settings:'tnum'}
.ns{padding:10px 12px 12px 16px;position:relative}
.ns+.nt::before,.nt+.ns::before{content:'';position:absolute;left:52px;right:16px;top:0;height:1px;background:var(--ov);opacity:.5}
.ns .h{display:flex;align-items:center;gap:14px}
.ns .ic{color:var(--primary);width:22px;flex:none}
.ns .a{flex:1;font-size:15px;font-weight:600}
.ns .vv{font-size:14px;color:var(--primary);font-weight:600;font-feature-settings:'tnum'}
.ns .trk{margin:18px 6px 10px 38px}
.ns.dis .ic,.ns.dis .a,.ns.dis .vv,.ns.dis .trk{opacity:.38}
.ns .tk{display:flex;justify-content:space-between;margin:0 0 0 36px;font-size:11px;color:var(--onv)}
.nd .rr .rd{display:none}
.nd .rr{padding:10px 16px 10px 20px}
.nd .rr .ck{margin-left:auto;color:var(--primary)}
.nd .rr .t{font-size:16px;font-weight:500}.nd .rr.on .t{font-weight:600}
.nd .rr .d{font-size:14px;line-height:1.45}
.hl{box-shadow:inset 0 0 0 2px var(--primary);border-radius:12px;background:rgba(54,97,142,.06)}
.toast{bottom:40px}
'''
mr = lambda n, s=24: f'<span class="mr" style="font-size:{s}px">{n}</span>'
rx = lambda c, s=24: f'<span class="rx" style="font-size:{s}px">&#x{c};</span>'
STATUS_BAR = '<div class="status"><span>21:36</span><span class="r"><span class="mi">signal_cellular_alt</span><span class="mi">wifi</span><span class="mi">battery_full</span></span></div>'
STATUS_LAND = ('<div class="status" style="height:24px;font-size:12px;padding:0 24px"><span>21:36</span>'
               '<span class="r"><span class="mi">wifi</span><span class="mi">battery_full</span></span></div>')
PATH = '/storage/emulated/0/Download/PureLiveRecords'


def page(w, h, scale, body, root='ph', crop=False):
    syn = ''
    return (f'<!doctype html><html><head><meta charset="utf-8"><meta name="mock-size" content="{w}x{h}@{scale}{" crop" if crop else ""}">'
            f'<link rel="stylesheet" href="kit/kit.css"><style>{CSS}</style></head>'
            f'<body><div class="{root} col" style="--w:{w}px;--h:{h}px;width:{w}px;height:{"auto" if crop else f"{h}px"}">{body}{syn}'
            '</div></body></html>')


def n(k, tag=None):
    return (f' data-n="{k}"' if k else '') + (f' data-tag="{tag}"' if tag and k else '')


def appbar(nums=False):
    return (f'<div class="ab"><div class="ib lead"{n(1 if nums else None)}>{mr("arrow_back")}</div>'
            '<div class="ttl">录制设置</div></div>')


# ---------------------------------------------------------------- v3
def v3_tile(icon, title, sub=None, chevron=True, long=False, spinner=False):
    trail = '<span class="sp2"></span>' if spinner else (f'<span class="ch">{mr("chevron_right", 20)}</span>' if chevron else '')
    sub = f'<div class="b{" long" if long else ""}">{sub}</div>' if sub else ''
    return f'<div class="tl"><span class="ic">{rx(icon, 22)}</span><div class="x"><div class="a">{title}</div>{sub}</div>{trail}</div>'


def v3_switch(icon, title, sub, on, long=False):
    return (f'<div class="tl sw2"><span class="ic" style="align-self:flex-start;padding-top:4px">{rx(icon, 22)}</span><div class="x"><div class="a">{title}</div>'
            f'<div class="b{" long" if long else ""}">{sub}</div></div><span class="sw{" on" if on else ""}"></span></div>')


def v3_slider(icon, title, value, frac):
    return (f'<div class="sdr"><span class="ic">{rx(icon, 22)}</span><div class="x"><div class="h"><span class="a">{title}</span><span class="v">{value}</span></div>'
            f'<div class="trk"><i style="width:{frac * 100:.1f}%"></i><u style="left:{frac * 100:.1f}%"></u></div></div></div>')


def v3_groups(all_on=False, narrow=True):
    g1 = ('<div class="gt">基础配置</div><div class="cd">'
          + v3_tile('ee02', '默认录制清晰度', '原画')
          + v3_switch('f226', '使用拼音文件夹名', '开启后使用主播拼音命名录制文件夹，关闭则使用主播原名', False)
          + v3_switch('eb51', '同时录制弹幕', '在录像旁保存同名 .xml 弹幕文件（B 站格式，可用 DanmakuFactory、PotPlayer 等加载）；需要平台已接入远端弹幕', False)
          + '</div>')
    act = f'<span class="act">{rx("ed70", 18)}打开文件夹</span>'
    head = (f'<div class="gt" style="padding-bottom:0">缓存管理</div><div style="display:flex;justify-content:flex-end;margin-bottom:8px">{act}</div>' if narrow
            else f'<div class="gt row2"><span>缓存管理</span>{act}</div><div style="height:8px"></div>')
    g2 = (head + '<div class="cd">'
          + v3_tile('f3cc', 'Pure Live 录制文件目录', PATH)
          + v3_switch('eca5', '启用缓存限制', '超过限制后自动清理旧录制', all_on)
          + (v3_tile('ec16', '缓存限制', '1024 MB') if all_on else '')
          + v3_tile('f572', '当前缓存大小', '3584.25 MB', chevron=False)
          + v3_tile('ec22', '清空录制文件目录', '仅删除上方 Pure Live 专用目录内的录制文件')
          + '</div>')
    g3 = ('<div class="gt">录制性能与画质</div><div class="cd">'
          + v3_switch('f280', '优先录制原画轨道', '强制选择最高清晰度流 (0:v:0)', True)
          + v3_tile('f214', '录制读写超时', '15s')
          + v3_tile('f179', '输入缓冲队列', '2048')
          + v3_slider('ed21', '视频切片时长', '5m', (300 - 60) / (3600 - 60))
          + v3_tile('f1e8', '最大同时录制任务数', '3')
          + '</div>')
    g4 = ('<div class="gt">自动重连</div><div class="cd">'
          + v3_switch('f064', '自动断线重连', '录制异常时尝试恢复', True)
          + v3_slider('f33d', '最大重试次数', '5', (5 - 1) / (20 - 1))
          + v3_slider('f20f', '重连间隔时间', '30s', (30 - 5) / (120 - 5))
          + '</div>')
    g5 = ('<div class="gt">挂机轮询检测</div><div class="cd">'
          + v3_switch('f04c', '启用开播检测', '主播未开播时自动轮询', all_on)
          + ((v3_slider('f20f', '检测间隔时间', '30s', (30 - 10) / (300 - 10))
              + v3_switch('eeab', '启用指数退避', '失败次数越多，检测间隔越长', True)
              + v3_slider('f337', '最大检测间隔', '5m', 0)) if all_on else '')
          + v3_switch('f080', '应用启动时恢复待录任务', '恢复上次录制中、排队、重连或等待开播的任务；保留已停止、已完成和失败状态。关闭自动检测时，仅检查一次。', False, long=True)
          + '</div><div style="height:60px"></div>')
    return g1 + g2 + g3 + g4 + g5


def v3_phone():
    return page(393, 852, 3, STATUS_BAR + appbar() + f'<div class="body"><div class="lst">{v3_groups()}</div></div><div class="gesture"></div>')


def v3_full(all_on=False):
    return page(393, 3200, 2, appbar() + f'<div class="lst">{v3_groups(all_on)}</div>', crop=True)


def v3_land():
    return page(852, 393, 2, STATUS_LAND + appbar() + f'<div class="body"><div class="lst" style="max-width:960px">{v3_groups(narrow=False)}</div></div>', root='win')


def v3_wide():
    return page(1280, 800, 1.5, appbar() + f'<div class="body"><div class="lst" style="max-width:960px;padding-top:4px">{v3_groups(narrow=False)}</div></div>', root='win')


def radio(opts, sel, desc=None):
    out = ''
    for i, o in enumerate(opts):
        d = f'<div class="d">{desc[i]}</div>' if desc else ''
        out += f'<div class="rr{" on" if i == sel else ""}"><span class="rd"></span><div><div class="t">{o}</div>{d}</div></div>'
    return out


TIMEOUT = (['15s', '30s', '60s'], ['响应迅速 (推荐，适合稳定网络)', '平衡模式 (兼顾稳定与重连速度)', '保守模式 (适合极端弱网环境)'])
QUEUE = (['512', '1024', '2048', '4096', '8192'], ['省电模式', '标清/高清推荐', '原画推荐 (1080P)', '极致性能 (适用于 4K 录制/高负载环境)', '极致性能 (适用于 4K 录制/高负载环境)'])
QUALITIES = ['原画', '蓝光8M', '蓝光4M', '超清', '流畅']


def v3_dialogs():
    d = '<div class="cap">默认录制清晰度（选了就关）</div>'
    d += f'<div class="dl"><div class="h">默认录制清晰度</div><div class="rl">{radio(QUALITIES, 0)}</div></div>'
    d += '<div class="cap">录制读写超时</div>'
    d += f'<div class="dl"><div class="h">录制读写超时</div><div class="rl">{radio(TIMEOUT[0], 0, TIMEOUT[1])}</div></div>'
    d += '<div class="cap">输入缓冲队列</div>'
    d += f'<div class="dl"><div class="h">输入缓冲队列</div><div class="rl">{radio(QUEUE[0], 2, QUEUE[1])}</div></div>'
    d += '<div class="cap">最大同时录制任务数</div>'
    chips = ''.join(f'<span class="{"on" if v == 3 else ""}">{v}</span>' for v in range(1, 11))
    d += (f'<div class="dl"><div class="h">最大同时录制任务数</div><div class="inp"><span class="lb">手动输入</span>3</div>'
          f'<div class="qs">快速选择</div><div class="qc">{chips}</div><div class="acts"><span>取消</span><span class="f">确认</span></div></div>')
    d += '<div class="cap">缓存限制</div>'
    d += ('<div class="dl"><div class="h">设置最大缓存 (MB)</div><div class="inp"><span class="lb">手动输入</span>1024</div>'
          '<div class="acts"><span>取消</span><span class="f">确认</span></div></div>')
    d += '<div class="cap">清空录制文件目录</div>'
    d += ('<div class="dl"><div class="h">确认清空录制文件目录？</div><div class="c">仅删除当前显示的 Pure Live 专用录制目录内容；所选父目录中的其他文件不受影响。</div>'
          '<div class="acts"><span>取消</span><span class="e">清除</span></div></div><div style="height:16px"></div>')
    return page(393, 4000, 2, f'<div class="sheetbg">{d}</div>', crop=True)


# ---------------------------------------------------------------- new
def nt(icon, title, sub=None, value=None, chevron=False, switch=None, dis=False, extra='', num=None, tag=None, cls=''):
    sub = f'<div class="b">{sub}</div>' if sub else ''
    val = f'<span class="v">{value}</span>' if value else ''
    ch = f'<span class="ch">{mr("chevron_right", 22)}</span>' if chevron else ''
    sw = f'<span class="sw{" on" if switch else ""}"></span>' if switch is not None else ''
    return (f'<div class="nt{" dis" if dis else ""} {cls}"{n(num, tag)}><span class="ic">{rx(icon, 22)}</span><div class="x"><div class="a">{title}</div>{sub}</div>'
            f'{val}{ch}{sw}{extra}</div>')


def ns(icon, title, value, frac, dis=False, ticks=None, num=None, tag=None):
    tk = f'<div class="tk">{"".join(f"<span>{t}</span>" for t in ticks)}</div>' if ticks else ''
    return (f'<div class="ns{" dis" if dis else ""}"{n(num, tag)}><div class="h"><span class="ic">{rx(icon, 22)}</span><span class="a">{title}</span><span class="vv">{value}</span></div>'
            f'<div class="trk"><i style="width:{frac * 100:.1f}%"></i><u style="left:{frac * 100:.1f}%"></u></div>{tk}</div>')


def v4_groups(nums=False, highlight=False):
    k = (lambda x: x) if nums else (lambda x: None)
    g = '<div class="ng">基础配置</div><div class="nc">'
    g += nt('ee02', '默认录制清晰度', value='原画', chevron=True, num=k(2))
    g += nt('f226', '使用拼音文件夹名', '开启后使用主播拼音命名录制文件夹，关闭则使用主播原名', switch=False, num=k(3))
    g += nt('eb51', '同时录制弹幕', '在录像旁保存同名 .xml 弹幕文件（B 站格式，可用 DanmakuFactory、PotPlayer 等加载）；需要平台已接入远端弹幕', switch=False, num=k(4))
    g += '</div>'
    g += '<div class="ng">录制文件</div><div class="nc">'
    folder = f'<span class="ib2"{n(k(6), "chg")}>{rx("ed70", 22)}</span>'
    g += nt('f3cc', 'Pure Live 录制文件目录', PATH, extra=folder, num=k(5))
    g += nt('eca5', '限制录制文件总大小', '超过上限时自动删除最早的录像', switch=False, num=k(7))
    g += nt('ec16', '总大小上限', value='1024 MB', chevron=True, dis=True, num=k(8))
    g += nt('f572', '已占用', value='3.5 GB')
    g += nt('ec22', '清空录制文件目录', '仅删除上方 Pure Live 专用目录内的录制文件', chevron=True, num=k(9))
    g += '</div>'
    g += '<div class="ng">录制性能与画质</div><div class="nc">'
    g += nt('f280', '优先录制原画轨道', '强制选择最高清晰度流 (0:v:0)', switch=True, num=k(10))
    g += nt('f214', '录制读写超时', '响应迅速 (推荐，适合稳定网络)', value='15 秒', chevron=True, num=k(11))
    g += nt('f179', '输入缓冲队列', '原画推荐 (1080P)', value='2048', chevron=True, num=k(12))
    g += ns('ed21', '视频切片时长', '5 分钟', (5 - 1) / 59, num=k(13))
    stepper = f'<span class="stp"><b>{rx("f1af", 20)}</b><em>3</em><b>{rx("ea13", 20)}</b></span>'
    g += nt('f1e8', '最大同时录制任务数', '超过的任务排队，有空位自动开始（1～10）', extra=stepper, num=k(14), tag='chg',
            cls='hl' if highlight else '')
    g += '</div>'
    g += '<div class="ng">自动重连</div><div class="nc">'
    g += nt('f064', '自动断线重连', '录制异常时尝试恢复', switch=True, num=k(15))
    g += ns('f33d', '最大重试次数', '5 次', (5 - 1) / 19, num=k(16))
    g += ns('f20f', '重连间隔时间', '30 秒', (30 - 5) / 115, num=k(17))
    g += '</div>'
    g += '<div class="ng">开播检测</div><div class="nc">'
    g += nt('f04c', '启用开播检测', '主播未开播时自动轮询', switch=False, num=k(18))
    g += ns('f20f', '检测间隔时间', '30 秒', (30 - 10) / 290, dis=True, num=k(19))
    g += nt('eeab', '启用指数退避', '失败次数越多，检测间隔越长', switch=False, dis=True, num=k(20))
    g += ns('f337', '最大检测间隔', '5 分钟', 0, dis=True, num=k(21))
    g += nt('f080', '应用启动时恢复待录任务', '恢复上次录制中、排队、重连或等待开播的任务；保留已停止、已完成和失败状态。关闭自动检测时，仅检查一次。', switch=False, num=k(22))
    g += '</div><div style="height:40px"></div>'
    return g


def v4_phone(nums=False):
    return page(393, 852, 3, STATUS_BAR + appbar(nums) + f'<div class="body"><div class="lst">{v4_groups(nums)}</div></div><div class="gesture"></div>')


def v4_full():
    return page(393, 3400, 2, appbar(True) + f'<div class="lst">{v4_groups(True)}</div>', crop=True)


def v4_limit():
    """Opened from the record panel's 改上限: scrolled to the row, highlighted."""
    body = f'<div class="body"><div class="lst" style="margin-top:-700px">{v4_groups(highlight=True)}</div></div>'
    return page(393, 852, 3, STATUS_BAR + appbar() + body + '<div class="gesture"></div>')


def v4_land():
    return page(852, 393, 2, STATUS_LAND + appbar() + f'<div class="body"><div class="lst" style="max-width:752px">{v4_groups()}</div></div>', root='win')


def v4_wide():
    return page(1280, 800, 1.5, appbar() + f'<div class="body"><div class="lst" style="max-width:752px;padding-top:4px">{v4_groups()}</div></div>', root='win')


def nradio(opts, sel, desc=None):
    out = ''
    for i, o in enumerate(opts):
        d = f'<div class="d">{desc[i]}</div>' if desc else ''
        ck = f'<span class="ck">{mr("check", 22)}</span>' if i == sel else ''
        out += f'<div class="rr{" on" if i == sel else ""}"><div><div class="t">{o}</div>{d}</div>{ck}</div>'
    return out


def v4_dialogs():
    d = '<div class="cap">默认录制清晰度（选了就关，同 v3）</div>'
    d += f'<div class="dl nd"><div class="h">默认录制清晰度</div><div class="rl">{nradio(QUALITIES, 0)}</div></div>'
    d += '<div class="cap">录制读写超时</div>'
    d += f'<div class="dl nd"><div class="h">录制读写超时</div><div class="rl">{nradio(["15 秒", "30 秒", "60 秒"], 0, TIMEOUT[1])}</div></div>'
    d += '<div class="cap">输入缓冲队列</div>'
    d += f'<div class="dl nd"><div class="h">输入缓冲队列</div><div class="rl">{nradio(QUEUE[0], 2, QUEUE[1])}</div></div>'
    d += '<div class="cap">总大小上限（原“设置最大缓存 (MB)”）</div>'
    d += ('<div class="dl"><div class="h">录制文件总大小上限 (MB)</div><div class="inp"><span class="lb">手动输入</span>1024</div>'
          '<div class="c" style="padding-top:8px;font-size:14px">超过时自动删除最早的录像。正在录的文件不会被删。</div>'
          '<div class="acts"><span>取消</span><span class="f">确认</span></div></div>')
    d += '<div class="cap">清空录制文件目录</div>'
    d += ('<div class="dl"><div class="h">清空录制文件目录？</div><div class="c" style="font-size:14px">将删除 3.5 GB 录像，不能恢复。只删 Pure Live 专用录制目录里的内容；'
          '所选父目录中的其他文件和正在录的文件不受影响。</div>'
          '<div class="acts"><span>取消</span><span class="r">清空</span></div></div><div style="height:16px"></div>')
    return page(393, 4000, 2, f'<div class="sheetbg">{d}</div>', crop=True)


OUT = {
    'v3-phone': v3_phone(), 'v3-full': v3_full(), 'v3-full-on': v3_full(True), 'v3-dialogs': v3_dialogs(),
    'v3-landscape': v3_land(), 'v3-wide': v3_wide(),
    'v4-phone': v4_phone(), 'v4-full': v4_full(), 'v4-limit': v4_limit(), 'v4-dialogs': v4_dialogs(),
    'v4-landscape': v4_land(), 'v4-wide': v4_wide(),
}
for name, html in OUT.items():
    open(os.path.join(HERE, name + '.html'), 'w', encoding='utf-8').write(html)
print(len(OUT), 'pages')
