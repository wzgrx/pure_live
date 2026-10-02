"""U.9 IPTV management mockups: v3 restored and the new design.
v3: lib/modules/iptv/iptv_page.dart ("IPTV 设置", dialogs) and
lib/modules/iptv/iptv_manage.dart ("订阅源管理"); the settings rows are
common/widgets/widget_extensions.dart (buildGroupTitle :21, buildModernCard :38,
buildSwitchTile :114, buildTile :154). Sample names and addresses are made up.
    python3 docs/ui/compare/U.9/src/gen.py && python3 tools/ui/mock/render.py docs/ui/compare/U.9/src/ --annotate"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))

# ---------------------------------------------------------------- shared look
CSS = '''
:root{--hint:rgba(0,0,0,.45);--gt:rgba(54,97,142,.65);--mcbg:#F1F2F8;--gc:#FFDDB8;--ogc:#4A2800;--tag:#E1E2E8}
[data-theme=dark]{--hint:rgba(255,255,255,.38);--gt:rgba(160,202,253,.65);--mcbg:#1C1F23;--gc:#5C3A12;--ogc:#FFDDB8;--tag:#32353A}
.pg{width:393px;background:var(--surface)}
.sbar{height:56px;display:flex;align-items:center;position:relative;background:var(--surface);flex:none}
.sbar .back{width:56px;height:56px;display:grid;place-items:center;flex:none}
.sbar .ttl{position:absolute;left:96px;right:96px;text-align:center;font-size:20px;font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;pointer-events:none}
.sbar .act{margin-left:auto;display:flex;align-items:center;padding-right:4px}
.bd{padding:12px 16px 28px}
.col{max-width:720px;margin:0 auto}
.gt{padding:0 0 8px 8px;font-size:12px;font-weight:700;color:var(--gt);letter-spacing:.5px}
.gt2{padding:4px 0 8px 4px;font-size:13px;font-weight:600;color:var(--primary);display:flex;align-items:center;gap:6px}
.gap{height:20px}
.mc{background:var(--mcbg);border-radius:20px;box-shadow:inset 0 0 0 .5px rgba(0,0,0,.05);overflow:hidden}
.mc2{background:var(--scl);border-radius:16px;overflow:hidden}
.tile{display:flex;align-items:center;gap:12px;padding:8px 16px;min-height:72px}
.tile.one{min-height:56px}
.tile .ic{color:var(--primary);font-size:22px;flex:none;width:22px;text-align:center}
.tile .tx{flex:1;min-width:0}
.tile .t{font-size:15px;font-weight:600;line-height:1.35}
.tile .s{font-size:12px;color:var(--hint);margin-top:2px;line-height:1.35;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.tile .s.wrap{white-space:normal}
.tile .s.on{color:var(--primary);font-weight:500}.tile .s.warn{color:#FF9800}.tile .s.err{color:var(--error)}
.tile .chev{color:rgba(0,0,0,.24);font-size:20px;flex:none}
[data-theme=dark] .tile .chev{color:rgba(255,255,255,.3)}
.n .tile .s{color:var(--onv);white-space:normal}.n .tile .chev{color:var(--outline)}
.dv{height:.5px;margin:0 16px;background:rgba(0,0,0,.08)}
[data-theme=dark] .dv{background:rgba(255,255,255,.08)}
.scrimw{position:relative}
.dlg2{background:var(--sch);border-radius:24px;padding:24px 24px 16px;margin:0 auto;box-shadow:0 8px 28px rgba(0,0,0,.28)}
.dlg2 .dt{font-size:20px;font-weight:600;line-height:1.3;display:flex;align-items:center;gap:12px}
.dlg2 .dc{font-size:13px;line-height:1.5;margin-top:14px;color:var(--on)}
.n .dlg2 .dc{font-size:14px}
.dlg2 .acts{display:flex;justify-content:flex-end;gap:8px;margin-top:20px;align-items:center}
.tb{height:40px;padding:0 12px;border-radius:8px;display:inline-flex;align-items:center;gap:6px;color:var(--primary);font-size:13px;font-weight:500;white-space:nowrap}
.n .tb{font-size:14px}
.tb.err{color:var(--error)}.tb.dim{opacity:.38}
.fb{height:40px;padding:0 20px;border-radius:12px;display:inline-flex;align-items:center;gap:6px;background:var(--primary);color:var(--onPrimary);font-size:14px;font-weight:600;white-space:nowrap}
.fb.err{background:var(--error);color:#fff}.fb.tonal{background:var(--sc);color:var(--osc)}
.ob{height:40px;padding:0 16px;border-radius:20px;display:inline-flex;align-items:center;gap:6px;box-shadow:inset 0 0 0 1px var(--outline);color:var(--primary);font-size:14px;font-weight:500;white-space:nowrap}
.inp{border-radius:12px;box-shadow:inset 0 0 0 1px var(--outline);padding:12px;font-size:14px;color:var(--on);background:transparent;line-height:1.4}
.inp.hint{color:var(--hint)}
.inp.foc{box-shadow:inset 0 0 0 2px var(--primary)}
.lab{font-size:12px;color:var(--primary);margin:0 0 -8px 10px;padding:0 4px;background:var(--sch);display:inline-block;position:relative;z-index:1}
.help{font-size:12px;color:var(--onv);margin:6px 4px 0;line-height:1.45}
.help.err{color:var(--error)}
.prog{height:4px;border-radius:2px;background:rgba(54,97,142,.18);position:relative;overflow:hidden}.prog i{position:absolute;left:0;top:0;bottom:0;width:38%;background:var(--primary);border-radius:2px}
.spin{width:20px;height:20px;border-radius:50%;border:2.5px solid rgba(54,97,142,.2);border-top-color:var(--primary);flex:none;display:inline-block}
.sheetbg{background:#D5D8DE;padding:20px 16px 8px}
[data-theme=dark] .sheetbg{background:#050607}
.cap{font-size:13px;font-weight:600;color:#3B3F46;margin:0 0 10px 4px}
[data-theme=dark] .cap{color:#C3C7CF}
.blk{margin-bottom:22px}
.toast2{background:#2E3135;color:#EFF0F7;font-size:14px;padding:12px 16px;border-radius:8px;box-shadow:0 3px 8px rgba(0,0,0,.25);display:inline-block;max-width:100%;line-height:1.4}
.pm{background:var(--schh);border-radius:8px;box-shadow:0 4px 14px rgba(0,0,0,.2);padding:8px 0;width:220px}
.pm .it{height:48px;display:flex;align-items:center;gap:12px;padding:0 16px;font-size:14px}
.pm .it .rx,.pm .it .mr{font-size:20px;color:var(--onv)}
.radio{width:20px;height:20px;border-radius:10px;border:2px solid var(--onv);flex:none;display:grid;place-items:center}
.radio.on{border-color:var(--primary)}.radio.on::after{content:'';width:10px;height:10px;border-radius:5px;background:var(--primary)}
'''

_col = lambda c: f'color:{c};' if c else ''
mr = lambda n, s=24, c=None: f'<span class="mr" style="{_col(c)}font-size:{s}px">{n}</span>'
mi = lambda n, s=24, c=None: f'<span class="mi" style="{_col(c)}font-size:{s}px">{n}</span>'
rx = lambda code, s=24, c=None: f'<span class="rx" style="{_col(c)}font-size:{s}px">&#x{code};</span>'
RX = dict(cloud='eb9d', refresh='f064', time='f20f', tv='f237', dl2='ec54', fileadd='ecc9', tv2='f235', pladd='f00f', folderopen='ed70',
          globe='edcf', draft='ec5c', cloudwindy='eba1', closec='eb97', warn='eca1', pl2='f00d', folder2='ed52', dlcloud2='ec56',
          del6='ec26', repeat='f074', chkfill='eb80', blankc='eb7d', info='ee59', more='ef77', copy='ecd5', ext='ecaf', check='eb7b',
          clip='eb91', arrowr='ea6e')


def A(n=None, tag=None, at=None):
    return (f' data-n="{n}"' if n else '') + (f' data-tag="{tag}"' if tag else '') + (f' data-at="{at}"' if at else '')


def doc(w, h, scale, body, crop=False, root_cls='ph', root_style=''):
    board = 'body{background:#D5D8DE}[data-theme=dark] body{background:#050607}' if 'sheetbg' in body else ''
    return (f'<!doctype html><html><head><meta charset="utf-8"><meta name="mock-size" content="{w}x{h}@{scale}{" crop" if crop else ""}">'
            f'<link rel="stylesheet" href="kit/kit.css"><style>{CSS}{board}</style></head>'
            f'<body><div class="{root_cls}" style="{root_style}">{body}</div></body></html>')


STATUS = '<div class="status"><span>21:36</span><span class="r"><span class="mi">wifi</span><span class="mi">battery_full</span></span></div>'


def sbar(title, actions='', n_back=None):
    return (f'<div class="sbar"><div class="back"{A(n_back)}>' + mi('arrow_back') + f'</div><div class="ttl">{title}</div>'
            f'<div class="act">{actions}</div></div>')


def gt(text):
    return f'<div class="gt">{text}</div>'


def tile(icon, title, sub=None, trail='chev', sub_cls='', n=None, tag=None, one=False, icon_color=None):
    ic = f'<span class="ic"' + (f' style="color:{icon_color}"' if icon_color else '') + f'>{icon}</span>' if icon else ''
    s = f'<div class="s {sub_cls}">{sub}</div>' if sub else ''
    if trail == 'chev':
        tr = mr('chevron_right', 20).replace('class="mr"', 'class="mr chev"')
    elif trail == 'on':
        tr = '<span class="sw on"></span>'
    elif trail == 'off':
        tr = '<span class="sw"></span>'
    else:
        tr = trail or ''
    return f'<div class="tile{" one" if one or not sub else ""}"{A(n, tag)}>{ic}<div class="tx"><div class="t">{title}</div>{s}</div>{tr}</div>'


def card(*tiles):
    return '<div class="mc">' + '<div class="dv"></div>'.join(tiles) + '</div>'


def dialog(title, content, actions, width=345, icon=None, extra_style=''):
    ic = icon or ''
    acts = f'<div class="acts">{actions}</div>' if actions else '<div style="height:8px"></div>'
    return (f'<div class="dlg2" style="width:{width}px;{extra_style}"><div class="dt">{ic}<span style="flex:1">{title}</span></div>'
            f'{content}{acts}</div>')


SHEET_W = 425


def sheet(blocks):
    """Several pieces on a grey board, each with a caption; phone-wide pieces stay 393."""
    inner = ''.join(f'<div class="blk"><div class="cap">{cap}</div>{html}</div>' for cap, html in blocks)
    return f'<div class="sheetbg" style="width:{SHEET_W}px">{inner}</div>'


def toasts(items):
    """Toasts with an optional note beside them (the note is not part of the toast)."""
    out = ''
    for it in items:
        text, note = (it, '') if isinstance(it, str) else it
        out += (f'<div style="margin-bottom:8px"><span class="toast2">{text}</span>'
                + (f'<div class="cap" style="font-weight:400;margin:4px 0 0 4px">{note}</div>' if note else '') + '</div>')
    return out


def write(name, html):
    open(os.path.join(HERE, name + '.html'), 'w', encoding='utf-8').write(html)


# ---------------------------------------------------------------- task CSS
CSS += '''
/* v3 subscription cards (iptv_manage.dart:448-831) */
.v3stats{border-radius:24px;padding:20px;background:linear-gradient(90deg,rgba(54,97,142,.12),#fff);display:flex;justify-content:space-around}
.v3stats .it{flex:1;display:flex;flex-direction:column;align-items:center}
.v3stats .ib2{width:46px;height:46px;border-radius:14px;background:rgba(54,97,142,.1);display:grid;place-items:center;color:var(--primary)}
.v3stats .v{font-size:12px;font-weight:700;margin-top:10px}.v3stats .l{font-size:12px;color:var(--hint);margin-top:4px}
.v3sec{display:flex;align-items:center;gap:8px;font-size:12px;font-weight:700;padding:24px 0 12px}
.v3sec .rx{color:var(--primary);font-size:18px}
.v3card{background:#fff;border-radius:22px;box-shadow:0 0 0 1px rgba(0,0,0,.06),0 4px 12px rgba(0,0,0,.03);padding:16px;margin-bottom:14px}
.v3card .idr{display:flex;align-items:flex-start;gap:14px}
.lead{position:relative;width:52px;height:52px;border-radius:16px;display:grid;place-items:center;flex:none}
.lead .bdg{position:absolute;right:-4px;bottom:-4px;min-height:18px;padding:1.5px 5px;border-radius:6px;border:2px solid #fff;color:#fff;font:900 11px/14px 'Geist','Noto Sans SC';letter-spacing:.2px;box-shadow:0 2px 4px rgba(0,0,0,.1)}
.v3card .nm{font-size:15px;font-weight:700;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.v3card .url{font-size:14px;color:var(--hint);margin-top:6px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.v3tag{padding:5px 10px;border-radius:999px;font-size:14px;font-weight:700;flex:none;align-self:center}
.abtn{min-height:48px;border-radius:14px;display:flex;align-items:center;justify-content:center;gap:6px;font-weight:600;font-size:14px;color:var(--primary);background:rgba(54,97,142,.08);flex:1}
.abtn.err{color:var(--error);background:rgba(186,26,26,.08)}
.abtn.dim{opacity:.38}
.swb{min-height:48px;border-radius:14px;background:rgba(54,97,142,.08);display:flex;align-items:center;gap:6px;padding:4px 12px;color:var(--primary);font-size:12px;font-weight:600}
.statecard{background:var(--scl);border-radius:16px;padding:20px}
/* new cards */
.st{background:var(--scl);border-radius:16px;padding:16px 8px;display:flex}
.st .it{flex:1;display:flex;flex-direction:column;align-items:center;gap:2px}
.st .v{font:600 20px/1.3 'Geist','Noto Sans SC';font-feature-settings:'tnum'}.st .l{font-size:12px;color:var(--onv)}
.sc{background:var(--scl);border-radius:16px;padding:14px 4px 12px 16px;margin-bottom:12px}
.sc.use{box-shadow:inset 0 0 0 1.5px var(--primary)}
.sc .idr{display:flex;align-items:flex-start;gap:14px}
.sc .nm{font-size:15px;font-weight:600;line-height:1.35;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.sc .meta{display:flex;flex-wrap:wrap;gap:6px;align-items:center;margin-top:4px;font-size:12px;color:var(--onv)}
.sc .url{font-size:12px;color:var(--onv);margin-top:4px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.tg{height:22px;padding:0 8px;border-radius:6px;background:var(--tag);color:var(--onv);font-size:12px;font-weight:500;display:inline-flex;align-items:center;gap:3px}
.tg .rx{font-size:13px}.tg.use{background:var(--primary);color:var(--onPrimary)}
.lead2{position:relative;width:48px;height:48px;border-radius:14px;display:grid;place-items:center;flex:none;background:var(--pc);color:var(--opc)}
.lead2.g{background:var(--gc);color:var(--ogc)}
.lead2 .bdg{position:absolute;right:-6px;bottom:-6px;padding:1px 5px;border-radius:6px;border:2px solid var(--scl);background:var(--opc);color:var(--pc);font:700 11px/14px 'Geist','Noto Sans SC'}
.lead2.g .bdg{background:var(--ogc);color:var(--gc)}
.morebtn{width:44px;height:44px;display:grid;place-items:center;color:var(--onv);flex:none;margin-top:-6px}
.acts2{display:flex;gap:8px;margin:12px 12px 0 0;align-items:center}
.swl{display:flex;align-items:center;gap:8px;margin:8px 12px 0 0;padding:4px 4px 4px 12px;min-height:48px;border-radius:12px;background:rgba(54,97,142,.06);font-size:14px;color:var(--on)}
.swl .x{flex:1}
.sk{background:var(--sch);border-radius:8px}
'''

# ---------------------------------------------------------------- sample data
PLAY_NET = dict(name='示例频道', url='https://example.com/iptv/channels.m3u', fmt='M3U', net=True)
EPG_NET = dict(name='hot', url='https://epg.zsdc.eu.org/t.xml.gz', fmt='XML.GZ', net=True, epg=True)
PLAY_LOCAL = dict(name='本地频道', url='/storage/emulated/0/Download/本地频道.txt', fmt='TXT', net=False)
BADGE = {'M3U': 'var(--primary)', 'TXT': '#FF9800', 'XML.GZ': '#546E7A', 'XML': 'var(--primary)', 'JSON': '#9C27B0'}


# ================================================================ v3
def v3_settings_body(init_error=False, epg_unset=False, auto_on=True):
    err = ('<div class="statecard" style="margin-bottom:12px"><div style="font-size:13px">读取 IPTV 配置失败。原有设置已保留，请重试。</div>'
           '<div class="tb" style="padding:0;margin-top:4px">重试</div></div>' if init_error else '')
    sync_tiles = [tile(rx(RX['refresh'], 22), '启动时全自动同步', '应用冷启动时自动在后台静默检查并更新网络资源', 'on' if auto_on else 'off')]
    if auto_on:
        sync_tiles.append(tile(rx(RX['time'], 22), '自动同步检查间隔', '当前每隔 24 小时进行一次同步'))
    sync_tiles.append(tile(rx(RX['tv'], 22), '自定义直播源请求头', None))
    epg_sub = ('点击选择一个节目单源', 'warn') if epg_unset else ('hot', '')
    return ('<div class="bd">' + err + gt('IPTV管理') + card(tile(rx(RX['cloud'], 22), '播放列表管理', '从服务器同步并覆盖最新的节目排班'))
            + '<div class="gap"></div>' + gt('自动化周期同步设置') + card(*sync_tiles)
            + '<div class="gap"></div>' + gt('播放源设置') + card(tile(rx(RX['dl2'], 22), '导入播放源', 'M3U / TXT'))
            + '<div class="gap"></div>' + gt('EPG 电视节目单设置')
            + card(tile(rx(RX['fileadd'], 22), '导入节目单源', 'XML / GZ / JSON'), tile(rx(RX['tv2'], 22), '当前启用的 EPG 数据源', epg_sub[0], sub_cls=epg_sub[1]))
            + '</div>')


def v3_card(it, wide=False, busy=False):
    epg = it.get('epg')
    lead_bg, lead_fg, icon = ('rgba(255,152,0,.12)', '#FF9800', RX['tv2']) if epg else ('rgba(54,97,142,.1)', 'var(--primary)', RX['pl2'])
    tag = ('<span class="v3tag" style="background:rgba(76,175,80,.12);color:#4CAF50">网络</span>' if it['net']
           else '<span class="v3tag" style="background:rgba(255,152,0,.12);color:#FF9800">本地</span>')
    idr = (f'<div class="idr"><div class="lead" style="background:{lead_bg};color:{lead_fg}">{rx(icon)}'
           f'<span class="bdg" style="background:{BADGE[it["fmt"]]}">{it["fmt"]}</span></div>'
           f'<div style="flex:1;min-width:0"><div class="nm">{it["name"]}</div><div class="url">{it["url"]}</div></div>{tag}</div>')
    sync = '<div class="abtn">' + rx(RX['dlcloud2'], 16) + '同步</div>'
    dele = '<div class="abtn err">' + rx(RX['del6'], 16) + '删除</div>'
    sw = '<div class="swb">' + rx(RX['repeat'], 16) + '<span style="flex:1">自动同步</span><span class="sw on"></span></div>'
    if not it['net']:
        acts = f'<div style="display:flex;margin-top:16px">{dele}</div>'
    elif wide:
        acts = f'<div style="display:flex;gap:10px;margin-top:16px">{sync}<div style="flex:1">{sw}</div>{dele}</div>'
    else:
        acts = f'<div style="display:flex;gap:10px;margin-top:16px">{sync}{dele}</div><div style="margin-top:10px">{sw}</div>'
    return f'<div class="v3card">{idr}{acts}</div>'


def v3_manage_body(wide=False):
    stats = ('<div class="v3stats">' + ''.join(
        f'<div class="it"><div class="ib2">{rx(ic)}</div><div class="v">{v}</div><div class="l">{l}</div></div>'
        for ic, v, l in ((RX['pl2'], '2', 'IPTV'), (RX['tv2'], '1', 'EPG'), (RX['globe'], '2', '网络'))) + '</div>')
    return ('<div style="padding:12px 16px 40px">' + stats
            + '<div class="v3sec">' + rx(RX['globe']) + '网络资源</div>' + v3_card(PLAY_NET, wide) + v3_card(EPG_NET, wide)
            + '<div class="v3sec">' + rx(RX['folder2']) + '本地资源</div>' + v3_card(PLAY_LOCAL, wide) + '</div>')


V3_MANAGE_BAR = lambda: sbar('订阅源管理', '<div class="ib">' + rx(RX['refresh']) + '</div>')


def v3_dialogs():
    hint = 'color:var(--hint)'
    imp = lambda title, icon, a, b: dialog(
        title, '<div style="margin:12px -12px 0">'
        + f'<div class="tile one" style="padding:0 16px;gap:16px">{rx(a, 24, "var(--primary)")}<div class="tx"><div class="t" style="font-weight:500;font-size:14px">本地导入</div></div></div>'
        + f'<div class="tile one" style="padding:0 16px;gap:16px">{rx(b, 24, "var(--primary)")}<div class="tx"><div class="t" style="font-weight:500;font-size:14px">网络导入</div></div></div></div>',
        '', icon=rx(icon).replace('style="', 'style="color:var(--primary);', 1))
    interval = dialog('选择自动同步时间间隔', '<div style="margin:8px -12px 0">' + ''.join(
        f'<div class="tile one" style="padding:0 16px;gap:16px;border-radius:14px;{"background:rgba(54,97,142,.08)" if h == 24 else ""}">'
        + (rx(RX['chkfill'], 22).replace('style="', 'style="color:var(--primary);', 1) if h == 24 else rx(RX['blankc'], 22).replace('style="', 'style="color:rgba(0,0,0,.3);', 1))
        + f'<div class="tx"><div class="t" style="font-size:14px;{"color:var(--primary)" if h == 24 else "font-weight:500"}">{h} 小时</div></div></div>'
        for h in (2, 6, 12, 24, 48, 72)) + '</div>', '', icon=rx(RX['time']).replace('style="', 'style="color:var(--primary);', 1))
    ua = dialog('修改请求头 (User-Agent)',
                '<div style="font-size:12px;color:var(--hint);margin-top:12px;line-height:1.45">设置自定义UA以解决部分直播源返回444或403拒绝访问的问题</div>'
                '<div style="margin-top:16px;height:144px;border-radius:14px;background:var(--scl);display:flex;flex-direction:column">'
                '<div style="flex:1;padding:14px 14px 4px;font:13px monospace;color:var(--hint);display:flex;justify-content:space-between">Mozilla/5.0...'
                + rx(RX['closec'], 18) + '</div>'
                '<div style="height:48px;display:flex;align-items:center;border-radius:0 0 14px 14px;background:rgba(0,0,0,.03)">'
                '<div class="ib">' + mr('remove') + '</div><div style="flex:1;display:flex;justify-content:center;align-items:center;gap:6px;font-size:11px;color:var(--hint)">'
                + mr('drag_indicator', 20) + '144 px</div><div class="ib">' + mr('add') + '</div></div></div>',
                '<span class="tb">取消</span><span class="fb">确认</span>', icon=rx(RX['tv']).replace('style="', 'style="color:var(--primary);', 1))
    net = dialog('请输入下载地址',
                 '<div style="margin-top:16px;display:flex;flex-direction:column;gap:12px">'
                 '<div class="inp" style="border-radius:4px;background:var(--scl)">https://example.com/iptv/channels.m3u</div>'
                 '<div class="inp hint" style="border-radius:4px;background:var(--scl)">文件名</div>'
                 '<div style="font-size:13px;color:var(--error)">请输入文件名</div></div>',
                 '<span class="tb">取消</span><span class="tb">确认</span>')
    net_run = dialog('请输入下载地址',
                     '<div style="margin-top:16px;display:flex;flex-direction:column;gap:12px">'
                     '<div class="inp" style="border-radius:4px;background:var(--scl)">https://example.com/iptv/channels.m3u</div>'
                     '<div class="inp" style="border-radius:4px;background:var(--scl)">示例频道</div>'
                     '<div class="prog" style="border-radius:0;height:4px"><i></i></div>'
                     '<div style="font-size:13px;line-height:1.5">导入正在进行。关闭窗口后导入仍会继续；完成前请勿重复导入。</div></div>',
                     '<span class="tb">关闭</span><span class="tb dim">确认</span>')
    epg = dialog('<span style="font-size:12px;font-weight:700">选择 EPG 数据源</span>',
                 '<div style="margin:8px -12px 0">'
                 '<div style="border-radius:12px;background:rgba(209,228,255,.25);padding:12px 16px;display:flex;gap:12px;align-items:center">'
                 + mi('radio_button_checked', 22).replace('style="', 'style="color:var(--primary);', 1)
                 + '<div style="flex:1;min-width:0"><div style="font-size:14px;font-weight:600">hot</div><div style="font-size:14px;color:var(--hint);margin-top:4px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">https://epg.zsdc.eu.org/t.xml.gz</div></div></div>'
                 '<div style="border-radius:12px;padding:12px 16px;display:flex;gap:12px;align-items:center;margin-top:4px">'
                 + mi('radio_button_unchecked', 22).replace('style="', 'style="color:var(--hint);', 1)
                 + '<div style="flex:1;min-width:0"><div style="font-size:14px;font-weight:500">示例节目单</div><div style="font-size:14px;color:var(--hint);margin-top:4px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">/storage/emulated/0/Download/示例节目单.xml</div></div></div></div>',
                 '<span class="tb">取消</span>', icon='', extra_style='border-radius:20px;padding-top:16px')
    epg = epg.replace('<span style="flex:1"><span style="font-size:12px;font-weight:700">选择 EPG 数据源</span></span>',
                      '<span style="flex:1;font-size:12px;font-weight:700">选择 EPG 数据源</span><span class="ib" style="width:40px;height:40px">' + mi('close', 22) + '</span>')
    dele = dialog('确认删除', '<div class="dc">你确定要删除这个订阅源吗？这将连带清空其下的所有频道和节目数据，且无法撤销。</div>',
                  '<span class="tb">取消</span><span class="tb err">确认</span>', extra_style='border-radius:18px')
    same = dialog('该订阅名称已存在', '<div class="dc">"示例频道"<br><br>是否确认删除旧的 M3U 数据并替换为当前文件？</div>',
                  '<span class="tb">取消</span><span class="tb">确认</span>', extra_style='border-radius:16px')
    tst = toasts(['正在批量抓取网络流数据...', ('请设置需要同步的资源', '点“同步”时，打开了自动同步的网络来源一个都没有'),
                  '远端服务器连接或解析失败', ('同步配置已保存', '保存请求头后也是这一句'),
                  ('同步失败: DioException [bad response]: …', '带异常原文（iptv_import_manager.dart:299）'), '订阅源已成功卸载并清除'])
    return sheet([('导入播放源（iptv_page.dart:310）', imp('导入播放列表 (M3U / TXT)', RX['pladd'], RX['folderopen'], RX['globe'])),
                  ('导入节目单源（:375）', imp('导入电视节目单 (XML / GZ / JSON)', RX['fileadd'], RX['draft'], RX['cloudwindy'])),
                  ('网络导入：校验出错（:759）', net), ('网络导入：进行中（:791）', net_run),
                  ('自动同步检查间隔（:241）', interval), ('修改请求头（:501）', ua),
                  ('当前启用的 EPG 数据源（:808）', epg), ('删除（iptv_manage.dart:833）', dele),
                  ('导入同名（iptv_import_manager.dart:261）', same), ('提示条（节选）', tst)])


def v3_states():
    load = ('<div class="pg">' + V3_MANAGE_BAR() + '<div class="prog" style="border-radius:0;height:2px"><i></i></div><div style="height:40px"></div></div>')
    empty = ('<div class="pg" style="padding:16px"><div class="statecard">' + rx(RX['pladd']).replace('style="', 'style="color:var(--primary);', 1)
             + '<div style="font-size:15px;font-weight:700;margin-top:12px">暂无订阅源</div><div style="font-size:13px;color:var(--hint);margin-top:8px">请返回 IPTV 设置导入播放列表或电子节目单。</div></div></div>')
    err = ('<div class="pg" style="padding:16px"><div class="statecard">' + rx(RX['warn']).replace('style="', 'style="color:var(--primary);', 1)
           + '<div style="font-size:15px;font-weight:700;margin-top:12px">订阅源加载失败</div><div style="font-size:13px;color:var(--hint);margin-top:8px">已有订阅数据已保留，请重试。</div>'
           '<div class="tb" style="padding:0;margin-top:12px">' + rx(RX['refresh'], 20) + '重试</div></div></div>')
    syncing = '<div class="pg">' + sbar('订阅源管理', '<div class="ib"><span class="spin"></span></div>') + '</div>'
    unset = '<div class="pg"><div class="bd" style="padding-bottom:12px">' + card(tile(rx(RX['tv2'], 22), '当前启用的 EPG 数据源', '点击选择一个节目单源', sub_cls='warn')) + '</div></div>'
    return sheet([('订阅源管理：加载中（顶上 2 像素进度条）', load), ('订阅源管理：空', empty), ('订阅源管理：出错', err),
                  ('订阅源管理：批量同步中（右上角转圈）', syncing), ('IPTV 设置：没选节目单（橙色字）', unset)])


# ================================================================ new design
def new_stats():
    return ('<div class="st">' + ''.join(f'<div class="it"><span class="v">{v}</span><span class="l">{l}</span></div>'
                                         for v, l in (('2', '播放列表'), ('1,286', '频道'), ('1', '节目单'))) + '</div>')


def new_card(it, meta, wide=False, n=False, use=False, busy=False, blocked=False):
    epg = it.get('epg')
    N = (lambda k: k) if n else (lambda k: None)
    tags = (f'<span class="tg">{rx(RX["globe"], 13)}网络</span>' if it['net'] else f'<span class="tg">{rx(RX["folder2"], 13)}本地</span>') \
        + ('<span class="tg use">使用中</span>' if use else '')
    idr = (f'<div class="idr"><div class="lead2{" g" if epg else ""}">{rx(RX["tv2"] if epg else RX["pl2"])}<span class="bdg">{it["fmt"]}</span></div>'
           f'<div style="flex:1;min-width:0"><div class="nm">{it["name"]}</div><div class="meta">{tags}<span>{meta}</span></div>'
           f'<div class="url">{it["url"]}</div></div><div class="morebtn"{A(N(4), "add")}>{mr("more_vert")}</div></div>')
    dim = ' dim' if blocked else ''
    sync = (f'<div class="abtn{dim}"{A(N(5))}>' + ('<span class="spin" style="width:16px;height:16px;border-width:2px"></span>' if busy else rx(RX['dlcloud2'], 16)) + '同步</div>')
    dele = f'<div class="abtn err{dim}"{A(N(6))}>' + rx(RX['del6'], 16) + '删除</div>'
    sw = f'<div class="swl"{A(N(7))}>' + rx(RX['repeat'], 18).replace('style="', 'style="color:var(--primary);', 1) + '<span class="x">自动同步</span><span class="sw on"></span></div>'
    if not it['net']:
        acts = f'<div class="acts2">{dele}</div>'
    elif wide:
        acts = f'<div class="acts2">{sync}<div style="flex:1.3">{sw.replace(chr(34) + ">", chr(34) + " style=" + chr(34) + "margin:0" + chr(34) + ">", 1)}</div>{dele}</div>'
    else:
        acts = f'<div class="acts2">{sync}{dele}</div>{sw}'
    return f'<div class="sc{" use" if use else ""}">{idr}{acts}</div>'


def new_body(n=False, wide=False):
    N = (lambda k: k) if n else (lambda k: None)
    play = (gt('播放列表') + card(tile(rx(RX['dl2'], 22), '导入播放列表', 'M3U / TXT 文件、订阅地址，或粘贴文本', n=N(3)))
            + '<div style="height:12px"></div>'
            + new_card(PLAY_NET, '1,024 个频道 · 今天 08:00 更新', wide, n)
            + new_card(PLAY_LOCAL, '262 个频道 · 09-28 21:40 导入', wide))
    guide = (gt('节目单') + card(tile(rx(RX['fileadd'], 22), '导入节目单', 'XML / GZ / JSON 文件或订阅地址', n=N(8)),
                                 tile(rx(RX['tv2'], 22), '当前使用的节目单', '默认节目单', n=N(9)))
             + '<div style="height:12px"></div>'
             + new_card(dict(EPG_NET, name='默认节目单'), '980 个频道 · 今天 08:00 更新', wide, use=True))
    sync = (gt('同步和播放') + card(tile(rx(RX['refresh'], 22), '启动时全自动同步', '打开应用 3 秒后，在后台同步超过间隔、且打开了“自动同步”的网络来源', 'on', n=N(10)),
                                   tile(rx(RX['time'], 22), '自动同步检查间隔', '当前每隔 24 小时进行一次同步', n=N(11)),
                                   tile(rx(RX['tv'], 22), '自定义直播源请求头', '未设置（使用默认请求头）', n=N(12))))
    return f'<div class="bd n"><div class="col">{new_stats()}<div class="gap"></div>{play}<div style="height:8px"></div>{guide}<div style="height:8px"></div>{sync}</div></div>'


def new_bar(n=False, busy=False):
    act = (f'<div class="ib"{A(2 if n else None)}>' + ('<span class="spin"></span>' if busy else rx(RX['refresh'])) + '</div>')
    return sbar('IPTV 设置', act, 1 if n else None)


def new_states():
    sk = lambda w, h, r=8: f'<div class="sk" style="width:{w};height:{h}px;border-radius:{r}px"></div>'
    loading = ('<div class="pg n">' + new_bar() + '<div class="bd" style="padding-bottom:16px"><div class="col">'
               + '<div class="st" style="height:74px;background:var(--sch)"></div><div class="gap"></div>'
               + sk('70px', 12) + '<div style="height:10px"></div>' + sk('100%', 72, 20) + '<div style="height:12px"></div>'
               + '<div class="sc"><div class="idr">' + sk('48px', 48, 14) + '<div style="flex:1;display:flex;flex-direction:column;gap:8px">' + sk('50%', 14) + sk('80%', 12) + sk('90%', 12) + '</div></div></div>'
               + '</div></div></div>')
    error = ('<div class="pg n"><div class="bd" style="padding-bottom:16px"><div class="statecard" style="display:flex;gap:12px">'
             + rx(RX['warn']).replace('style="', 'style="color:var(--error);', 1)
             + '<div style="flex:1"><div style="font-size:15px;font-weight:600">读取失败</div><div style="font-size:13px;color:var(--onv);margin-top:4px;line-height:1.5">读取 IPTV 配置失败。原有设置已保留，请重试。</div>'
             '<div class="tb" style="padding:0;margin-top:6px">' + rx(RX['refresh'], 18) + '重试</div></div></div></div></div>')
    empty = ('<div class="pg n"><div class="bd" style="padding-bottom:16px">' + gt('播放列表')
             + '<div class="statecard" style="text-align:center;padding:24px 20px">' + rx(RX['pladd'], 32, 'var(--onv)')
             + '<div style="font-size:15px;font-weight:600;margin-top:8px">还没有播放列表</div><div style="font-size:13px;color:var(--onv);margin-top:6px;line-height:1.5">导入 M3U 或 TXT 播放列表后，频道会出现在分区页的“网络”里，可以像直播间一样关注和观看。</div>'
             '<div class="fb tonal" style="margin-top:14px">导入播放列表</div></div>'
             '<div class="gap"></div>' + gt('节目单')
             + '<div class="statecard" style="text-align:center;padding:24px 20px">' + rx(RX['tv2'], 32, 'var(--onv)')
             + '<div style="font-size:15px;font-weight:600;margin-top:8px">还没有节目单</div><div style="font-size:13px;color:var(--onv);margin-top:6px;line-height:1.5">节目单用来在直播间显示正在播放和接下来的节目，并支持回看。</div>'
             '<div style="display:flex;gap:8px;justify-content:center;margin-top:14px"><div class="ob">默认节目单</div><div class="fb tonal">导入节目单</div></div></div></div></div>')
    off = ('<div class="pg n"><div class="bd" style="padding-bottom:16px"><div style="background:var(--warnbg);border-radius:16px;padding:14px 16px;display:flex;gap:12px">'
           + rx(RX['info'], 20).replace('style="', 'style="color:var(--warn);', 1)
           + '<div style="flex:1"><div style="font-size:14px;font-weight:600">IPTV 没有启用</div><div style="font-size:13px;color:var(--onv);margin-top:4px;line-height:1.5">平台设置里没有勾选“网络”：频道不会出现在分区页，启动时也不会自动同步。</div>'
           '<div class="tb" style="padding:0;margin-top:4px">启用</div></div></div></div></div>')
    syncall = ('<div class="pg n">' + new_bar(busy=True) + '<div class="bd" style="padding-bottom:16px"><div class="col">'
               '<div class="st" style="flex-direction:column;align-items:stretch;padding:14px 16px;gap:8px"><div style="display:flex;justify-content:space-between;font-size:14px"><span>正在同步网络来源</span><span class="tnum" style="color:var(--onv)">1 / 3</span></div>'
               '<div class="prog"><i style="width:33%"></i></div></div><div style="height:12px"></div>'
               + new_card(PLAY_NET, '1,024 个频道 · 今天 08:00 更新', busy=True, blocked=True) + '</div></div></div>')
    default = ('<div class="pg n"><div class="bd" style="padding-bottom:16px">' + gt('节目单')
               + '<div class="statecard" style="display:flex;gap:12px;align-items:flex-start"><span class="spin" style="margin-top:2px"></span><div style="flex:1">'
               '<div style="font-size:14px;font-weight:600">正在导入默认节目单…</div><div style="font-size:13px;color:var(--onv);margin-top:4px;line-height:1.5">节目单较大，可能需要一两分钟；可以离开本页，导入会继续。</div></div></div></div></div>')
    tst = toasts(['已导入播放列表“示例频道”，跳过了 3 处无法识别的内容', '“示例频道”同步失败：下载失败，请检查地址和网络后重试',
                  '已同步 3 个网络来源', '已保存请求头', '已删除“本地频道”'])
    return sheet([('加载中：骨架', loading), ('读取失败', error), ('两组都空：各自给出下一步', empty),
                  ('IPTV 没有在平台列表里启用（新）', off), ('全部同步中：进度和条数，卡片按钮暂不可用', syncall),
                  ('第一次进入，正在导入默认节目单', default), ('提示条（说清是哪一个、为什么）', tst)])


def new_dialogs():
    opt = lambda icon, t, s, n=None, tag=None: (f'<div class="tile" style="padding:6px 16px;gap:16px;min-height:64px"{A(n, tag)}>'
                                                + icon.replace('style="', 'style="color:var(--primary);', 1)
                                                + f'<div class="tx"><div class="t" style="font-weight:500;font-size:15px">{t}</div><div class="s" style="font-size:13px;white-space:normal">{s}</div></div></div>')
    imp_play = dialog('导入播放列表 (M3U / TXT)', '<div style="margin:10px -24px 0">'
                      + opt(rx(RX['folderopen']), '本地导入', '选择 M3U / M3U8 / TXT 文件', 13)
                      + opt(rx(RX['globe']), '网络导入', '填订阅地址，以后可以同步', 14)
                      + opt(rx(RX['clip']), '粘贴文本', '粘贴 M3U 或 TXT 列表的内容', 15, 'add') + '</div>',
                      '', icon=rx(RX['pladd'], 24, 'var(--primary)'))
    imp_epg = dialog('导入电视节目单 (XML / GZ / JSON)', '<div style="margin:10px -24px 0">'
                     + opt(rx(RX['draft']), '本地导入', '选择 XML / GZ / JSON 文件')
                     + opt(rx(RX['cloudwindy']), '网络导入', 'XMLTV（可为 .gz 压缩）或 JSON 地址')
                     + opt(rx(RX['tv2']), '默认节目单', '导入应用内置的节目单地址', 16, 'add') + '</div>',
                     '', icon=rx(RX['fileadd'], 24, 'var(--primary)'))
    net = dialog('从网络导入播放列表',
                 '<div style="margin-top:18px"><span class="lab">订阅地址</span><div class="inp foc"' + A(17) + '>https://example.com/iptv/channels.m3u</div></div>'
                 '<div style="margin-top:14px"><span class="lab" style="color:var(--onv)">名称（可选）</span><div class="inp hint"' + A(18) + '>channels</div></div>'
                 '<div class="help">留空时用地址里的文件名；已有同名的列表会先问你是否替换</div>',
                 '<span class="tb"' + A(20) + '>取消</span><span class="fb"' + A(19) + '>导入</span>')
    net_run = dialog('从网络导入播放列表',
                     '<div style="margin-top:18px"><span class="lab" style="color:var(--onv)">订阅地址</span><div class="inp">https://example.com/iptv/channels.m3u</div></div>'
                     '<div style="margin-top:16px" class="prog"><i></i></div>'
                     '<div class="help" style="font-size:13px;color:var(--on)">正在下载和导入。关闭窗口不会中止导入，完成后会提示结果。</div>',
                     '<span class="tb">关闭</span><span class="fb" style="opacity:.38">导入</span>')
    net_err = dialog('从网络导入播放列表',
                     '<div style="margin-top:18px"><span class="lab" style="color:var(--error)">订阅地址</span><div class="inp" style="box-shadow:inset 0 0 0 2px var(--error)">https://example.com/iptv/channels.m3u</div></div>'
                     '<div class="help err" style="font-size:13px">下载失败，请检查地址和网络后重试</div>',
                     '<span class="tb">取消</span><span class="fb">重试</span>')
    menu = ('<div style="display:flex;justify-content:flex-end;padding-right:8px"><div class="pm">'
            f'<div class="it"{A(21)}>' + rx(RX['ext'], 20) + '在浏览器中打开</div>'
            f'<div class="it"{A(22, "add")}>' + rx(RX['copy'], 20) + '复制地址</div></div></div>')
    interval = dialog('自动同步间隔', '<div style="margin:8px -12px 0">' + ''.join(
        f'<div class="tile one" style="padding:0 16px;gap:16px;border-radius:14px;{"background:rgba(54,97,142,.08)" if h == 24 else ""}">'
        + (rx(RX['chkfill'], 22).replace('style="', 'style="color:var(--primary);', 1) if h == 24 else rx(RX['blankc'], 22).replace('style="', 'style="color:var(--outline);', 1))
        + f'<div class="tx"><div class="t" style="font-size:15px;{"color:var(--primary)" if h == 24 else "font-weight:500"}">{h} 小时</div></div></div>'
        for h in (2, 6, 12, 24, 48, 72)) + '</div>', '', icon=rx(RX['time']).replace('style="', 'style="color:var(--primary);', 1))
    ua = dialog('修改请求头 (User-Agent)',
                '<div class="dc" style="color:var(--onv)">部分直播源返回 403 或 444 拒绝访问时，可以换一个请求头试试。</div>'
                '<div style="margin-top:14px;position:relative"><div class="inp foc" style="font:13px/1.5 monospace;min-height:84px;padding-right:44px"' + A(24) + '>Mozilla/5.0 (Linux; Android 15) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0 Mobile Safari/537.36</div>'
                '<span class="ib" style="position:absolute;right:0;top:0;color:var(--onv)"' + A(23) + '>' + rx(RX['closec'], 20) + '</span></div>'
                '<div class="help">留空使用默认请求头；输入框随内容变高（最多 500 字）</div>',
                '<span class="tb">取消</span><span class="fb"' + A(25) + '>确认</span>', icon=rx(RX['tv']).replace('style="', 'style="color:var(--primary);', 1))
    epg = dialog('选择节目单', '<div style="margin:12px -12px 0">'
                 f'<div style="border-radius:12px;background:rgba(54,97,142,.08);padding:10px 12px;display:flex;gap:14px;align-items:center"{A(26)}><span class="radio on"></span>'
                 '<div style="flex:1;min-width:0"><div style="font-size:15px;font-weight:600;color:var(--primary)">默认节目单</div><div style="font-size:13px;color:var(--onv);margin-top:2px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">https://epg.zsdc.eu.org/t.xml.gz</div></div></div>'
                 '<div style="border-radius:12px;padding:10px 12px;display:flex;gap:14px;align-items:center;margin-top:4px"><span class="radio"></span>'
                 '<div style="flex:1;min-width:0"><div style="font-size:15px;font-weight:500">示例节目单</div><div style="font-size:13px;color:var(--onv);margin-top:2px">/storage/emulated/0/Download/示例节目单.xml</div></div></div></div>',
                 '<span class="tb">取消</span>')
    dele = dialog('删除播放列表？', '<div class="dc">将删除“示例频道”及其 1,024 个频道，关注和历史里的这些频道将无法播放，此操作不可撤销。</div>',
                  '<span class="tb">取消</span><span class="fb err">删除</span>')
    dele_g = dialog('删除节目单？', '<div class="dc">将删除“默认节目单”及其 980 个频道的节目数据，此操作不可撤销。<br>这是当前使用的节目单，删除后将改用下一个节目单。</div>',
                    '<span class="tb">取消</span><span class="fb err">删除</span>')
    same = dialog('已有同名播放列表', '<div class="dc">已有名为“示例频道”的播放列表。替换后会用新内容更新它的频道，已关注的频道尽量保留。</div>',
                  '<span class="tb">取消</span><span class="fb">替换</span>')
    return sheet([('导入播放列表（多了“粘贴文本”）', imp_play), ('导入节目单（多了“默认节目单”）', imp_epg),
                  ('网络导入', net), ('网络导入：进行中', net_run), ('网络导入：失败说原因，可直接重试', net_err),
                  ('卡片右上角“更多”（代替点卡片打开）', menu), ('自动同步间隔（同 v3）', interval), ('修改请求头', ua),
                  ('选择节目单（点“当前使用的节目单”）', epg), ('删除播放列表', dele), ('删除正在使用的节目单', dele_g), ('导入同名', same)])


OUT = {
    # v3
    'v3-settings': doc(393, 852, 3, STATUS + sbar('IPTV 设置') + v3_settings_body() + '<div class="gesture"></div>'),
    'v3-manage': doc(393, 2400, 2, STATUS + V3_MANAGE_BAR() + v3_manage_body(), crop=True, root_cls='pg'),
    'v3-dialogs': doc(425, 4000, 2, v3_dialogs(), crop=True, root_cls=''),
    'v3-states': doc(425, 2000, 2, v3_states(), crop=True, root_cls=''),
    'v3-wide': doc(1280, 800, 1.5, V3_MANAGE_BAR() + '<div style="max-width:960px;margin:0 auto">' + v3_manage_body(wide=True) + '</div>',
                   root_cls='win'),
    'v3-land': doc(852, 393, 2, V3_MANAGE_BAR() + v3_manage_body(wide=True), root_cls='win', root_style='--w:852px;--h:393px'),
    # new
    'v4-page': doc(393, 2600, 2, STATUS + new_bar(n=True) + new_body(n=True), crop=True, root_cls='pg'),
    'v4-phone': doc(393, 852, 3, STATUS + new_bar() + new_body() + '<div class="gesture"></div>'),
    'v4-states': doc(425, 4000, 2, new_states(), crop=True, root_cls=''),
    'v4-dialogs': doc(425, 5000, 2, '<div class="n">' + new_dialogs() + '</div>', crop=True, root_cls=''),
    'v4-wide': doc(1280, 800, 1.5, new_bar() + new_body(wide=True), root_cls='win'),
    'v4-land': doc(852, 393, 2, new_bar() + new_body(wide=True), root_cls='win', root_style='--w:852px;--h:393px'),
}
for name, html in OUT.items():
    write(name, html)
print(len(OUT), 'pages')
