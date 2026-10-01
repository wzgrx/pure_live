"""U.5b web search mockups: v3 restored and the new design.

v3 (tag v3.2.11): lib/modules/search/web_search_page.dart (AppBar :33-49,
WebView :60-94, progress :95-105, failure :106-114 and :158-195, Linux
system browser page :119-156), web_search_controller.dart (desktop
User-Agent :141-144, room prompt :514-521, opening the room replaces the
page :523-525, back goes back in the page first :418-434),
plugins/utils.dart (_SharedAlertDialog :395-445).
The web pages are placeholders, not any platform's site.
    python3 docs/ui/compare/U.5b/src/gen.py && python3 tools/ui/mock/render.py docs/ui/compare/U.5b/src/ --annotate"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
IMG = '.cache/img/'

CSS = '''
.ph .status{background:var(--surface)}
.sb24{height:24px;display:flex;align-items:center;justify-content:space-between;padding:0 16px;font:600 12px 'Geist','Noto Sans SC';background:var(--surface)}
.sb24 .mi{font-size:13px}
.bar{height:56px;display:flex;align-items:center;background:var(--surface);position:relative;flex:none;z-index:3}
.bar .b{width:56px;height:56px;display:grid;place-items:center;flex:none}
.bar .b .mi,.bar .b .mr{font-size:24px}
.bar .ct{position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);font-size:20px;font-weight:600;white-space:nowrap}
.bar .tt{flex:1;min-width:0;padding-left:4px}
.bar .tt .n{font-size:17px;font-weight:600;line-height:22px}
.bar .tt .s{font-size:12px;color:var(--onv);line-height:16px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.bar .ib2{width:48px;height:48px;display:grid;place-items:center;flex:none;color:var(--on)}
.prog{height:4px;background:rgba(54,97,142,.18);position:relative;z-index:4}.prog i{position:absolute;left:0;top:0;bottom:0;background:var(--primary)}
.view{position:relative;flex:1;overflow:hidden;background:#fff}
.col2{display:flex;flex-direction:column;height:100%}
/* placeholder web page, laid out at desktop width and scaled */
.wp{position:absolute;left:0;top:0;width:1280px;transform-origin:0 0;background:#fff;color:#222;font-family:'Noto Sans SC'}
.wp .hd{height:64px;display:flex;align-items:center;gap:24px;padding:0 40px;border-bottom:1px solid #e5e5e5}
.wp .lg{width:120px;height:32px;border-radius:6px;background:#9AA3AF}
.wp .sbx{width:520px;height:40px;border:2px solid #9AA3AF;border-radius:8px;display:flex;align-items:center;padding:0 14px;font-size:16px}
.wp .nav{display:flex;gap:28px;padding:16px 40px;font-size:16px;color:#555;border-bottom:1px solid #eee}.wp .nav b{color:#222}
.wp .gr{display:grid;grid-template-columns:repeat(4,1fr);gap:20px;padding:20px 40px}
.wp .it .im{aspect-ratio:16/9;border-radius:8px;background:#ddd center/cover}
.wp .it .t{font-size:15px;margin-top:8px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.wp .it .u{font-size:13px;color:#888;margin-top:4px}
.wp .room{display:flex;gap:16px;padding:20px 40px}.wp .room .v{flex:1;aspect-ratio:16/9;background:#000 url(.cache/img/158.jpg) center/cover;border-radius:6px}
.wp .room .c{width:300px;border:1px solid #eee;border-radius:6px;padding:12px;font-size:14px;color:#555;line-height:2}
.wp .rt{padding:20px 40px 0;font-size:22px;font-weight:600}.wp .ru{padding:6px 40px 0;font-size:14px;color:#888}
.wtag{position:absolute;right:8px;top:8px;z-index:5;font:500 10px 'Noto Sans SC';padding:2px 6px;border-radius:4px;background:rgba(0,0,0,.55);color:#fff}
/* states */
.fail{position:absolute;inset:0;background:var(--surface);display:flex;flex-direction:column;align-items:center;justify-content:center;padding:24px;text-align:center;z-index:6}
.fail .big{font-size:48px}
.fail h4{margin-top:20px;font-size:15px;font-weight:600}
.fail p{margin-top:8px;font-size:13px;line-height:1.4;color:var(--onv);max-width:560px}
.fbtn{margin-top:20px;height:40px;border-radius:20px;background:var(--primary);color:var(--onPrimary);display:flex;align-items:center;gap:8px;padding:0 24px 0 16px;font-size:13px;font-weight:500}
.fbtn .mr{font-size:18px}
.tbtn2{margin-top:8px;height:40px;display:flex;align-items:center;gap:8px;padding:0 12px;color:var(--primary);font-size:13px;font-weight:500}.tbtn2 .mr{font-size:18px}
.dim{position:absolute;inset:0;background:rgba(0,0,0,.4);z-index:20}
.dlg2{position:absolute;z-index:21;background:var(--sch);border-radius:24px;padding:24px 24px 16px}
.dlg2 h3{font-size:20px;font-weight:600;line-height:1.3}
.dlg2 .c{margin-top:16px;padding:12px 0;font-size:13px;line-height:1.45}
.dlg2 .acts{display:flex;justify-content:flex-end;gap:8px;margin-top:12px}
.dlg2 .acts span{height:48px;display:flex;align-items:center;padding:0 12px;font-size:13px;font-weight:500;color:var(--primary)}
.rbar{position:absolute;left:12px;right:12px;bottom:16px;z-index:8;border-radius:16px;background:var(--sch);box-shadow:0 4px 14px rgba(0,0,0,.22);display:flex;align-items:center;gap:12px;padding:10px 8px 10px 14px}
.rbar img{width:28px;height:28px;border-radius:7px;flex:none}
.rbar .x{flex:1;min-width:0}.rbar b{display:block;font-size:14px;font-weight:600}.rbar small{display:block;font-size:12px;color:var(--onv);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.rbar .go{height:40px;padding:0 18px;border-radius:20px;background:var(--primary);color:var(--onPrimary);font-size:13px;font-weight:600;display:flex;align-items:center;flex:none}
.rbar .cl{width:40px;height:40px;display:grid;place-items:center;color:var(--onv);flex:none}
.toast{bottom:40px}
'''

mr = lambda n, s=None: f'<span class="mr"{f" style=\"font-size:{s}px\"" if s else ""}>{n}</span>'
mi = lambda n, s=None: f'<span class="mi"{f" style=\"font-size:{s}px\"" if s else ""}>{n}</span>'
LOGO = '../../../packages/live_ui/assets/platforms/'


def dn(n, tag=None, at=None):
    if n is None:
        return ''
    return f' data-n="{n}"' + (f' data-tag="{tag}"' if tag else '') + (f' data-at="{at}"' if at else '')


STATUS = ('<div class="status"><span>21:36</span><span class="r"><span class="mi">signal_cellular_alt</span>'
          '<span class="mi">wifi</span><span class="mi">battery_full</span></span></div>')
SB24 = ('<div class="sb24"><span>21:36</span><span style="display:flex;gap:4px"><span class="mi">wifi</span>'
        '<span class="mi">battery_full</span></span></div>')


def page(size, body, cls='ph', style=''):
    return (f'<!doctype html><html><head><meta charset="utf-8"><meta name="mock-size" content="{size}">'
            f'<link rel="stylesheet" href="kit/kit.css"><style>{CSS}</style></head><body>'
            f'<div class="{cls}" style="{style}">{body}</div></body></html>')


COVERS = ['1', '111', '133', '169', '183', '206', '219', '237', '250', '287', '292', '304']
TITLES = ['晚风电台｜深夜点歌', '晚风吹过的夏天', '【晚风】原创歌曲首发', '晚风与夜空 户外慢直播', '晚风 KTV 等你来点歌', '听晚风讲故事',
          '晚风｜周末合唱', '海边的晚风', '晚风读书会', '晚风里的城市骑行', '晚风钢琴', '晚风小厨房']


def web_results(scale):
    items = ''.join(f'<div class="it"><div class="im" style="background-image:url({IMG}{c}.jpg)"></div><div class="t">{t}</div>'
                    f'<div class="u">主播 · 在线 {i + 2}.{i}万</div></div>' for i, (c, t) in enumerate(zip(COVERS, TITLES)))
    return (f'<div class="wp" style="transform:scale({scale})"><div class="hd"><div class="lg"></div><div class="sbx">晚风</div></div>'
            f'<div class="nav"><b>直播</b><span>主播</span><span>视频</span><span>专栏</span></div><div class="gr">{items}</div></div>')


def web_room(scale):
    chat = '<br>'.join(['来了来了', '主播晚上好', '这首歌好听', '前排支持', '晚风好温柔'])
    return (f'<div class="wp" style="transform:scale({scale})"><div class="hd"><div class="lg"></div><div class="sbx">晚风</div></div>'
            f'<div class="rt">晚风电台｜深夜点歌</div><div class="ru">晚风 · 唱见电台</div>'
            f'<div class="room"><div class="v"></div><div class="c">{chat}</div></div></div>')


def view(inner, extra=''):
    return f'<div class="view">{inner}<span class="wtag">示意网页</span>{extra}</div>'


# ---------- v3 ----------
def v3_bar():
    return (f'<div class="bar"><div class="b">{mi("arrow_back")}</div><div class="ct">网页搜索</div>'
            f'<div style="flex:1"></div><div class="b">{mi("close")}</div></div>')


def v3_fail(retry=True):
    return (f'<div class="fail"><span class="mr big" style="color:var(--error)">wifi_off</span><h4>网页搜索暂不可用</h4>'
            f'<p>{"网页加载失败，请检查网络或代理后重试。" if retry else "网页搜索地址无效，请返回搜索页后重试。"}</p>'
            f'<div class="fbtn">{mr("refresh" if retry else "close")}{"重试" if retry else "关闭"}</div></div>')


V3_ROOM_DLG = ('<div class="dim"></div><div class="dlg2" style="left:16px;right:16px;top:330px">'
               '<h3>提示</h3><div class="c">检测到房间号，是否打开直播间？</div>'
               '<div class="acts"><span>取消</span><span>确认</span></div></div>')

# ---------- new ----------
def v4_bar(n=True, sub='哔哩哔哩 · 晚风'):
    return (f'<div class="bar"><div class="b"{dn(1 if n else None, "keep")}>{mi("arrow_back")}</div>'
            f'<div class="tt"{dn(2 if n else None, "chg", "tl")}><div class="n">网页搜索</div><div class="s">{sub}</div></div>'
            f'<div class="ib2"{dn(3 if n else None, "add")}>{mr("open_in_new")}</div>'
            f'<div class="ib2" style="margin-right:4px"{dn(4 if n else None, "keep")}>{mi("close")}</div></div>')


def v4_room_bar(n=True):
    return (f'<div class="rbar"><img src="{LOGO}bilibili.png"><div class="x"><b>这是一个直播间</b><small>哔哩哔哩 · 房间号 21452505</small></div>'
            f'<span class="go"{dn(5 if n else None, "chg")}>进入</span><span class="cl"{dn(6 if n else None, "add")}>{mr("close", 20)}</span></div>')


def v4_fail():
    return (f'<div class="fail"><span class="mr big" style="color:var(--error)">wifi_off</span><h4>网页搜索暂不可用</h4>'
            f'<p>网页加载失败，请检查网络或代理后重试。</p><div class="fbtn">{mr("refresh")}重试</div>'
            f'<div class="tbtn2">{mr("open_in_new")}使用系统浏览器打开</div></div>')


def external_page(v4=False):
    if v4:
        body = (f'<span class="mr big" style="color:var(--primary)">open_in_browser</span>'
                f'<p style="color:var(--on);font-size:14px;margin-top:16px">网页搜索在系统浏览器中打开。找到想看的直播间后复制它的链接，回到搜索框粘贴即可直接进入。</p>'
                f'<p>search.bilibili.com</p><div class="fbtn">{mr("open_in_new")}使用系统浏览器打开</div>')
    else:
        body = (f'<span class="mr big" style="color:var(--primary)">open_in_browser</span>'
                f'<p style="color:var(--on);font-size:14px;margin-top:16px">Linux 版使用系统浏览器继续网页搜索；应用内原生搜索、直播详情和播放功能保持可用。</p>'
                f'<div class="fbtn">{mr("open_in_new")}使用系统浏览器打开</div>')
    return f'<div class="fail" style="position:relative;flex:1">{body}</div>'


PH = 393 / 1280
LAND = 852 / 1280
OUT = {}
# v3
OUT['v3-web-phone'] = page('393x852@3', STATUS + '<div class="col2" style="height:816px">' + v3_bar() +
                           '<div class="prog"><i style="width:45%"></i></div>' + view(web_results(PH)) + '</div>')
OUT['v3-web-room'] = page('393x852@3', STATUS + '<div class="col2" style="height:816px">' + v3_bar() + view(web_room(PH)) + '</div>' + V3_ROOM_DLG)
OUT['v3-web-failed'] = page('393x852@3', STATUS + '<div class="col2" style="height:816px">' + v3_bar() + view('', v3_fail()) + '</div>')
OUT['v3-web-land'] = page('852x393@2', SB24 + '<div class="col2" style="height:369px">' + v3_bar() + view(web_results(LAND)) + '</div>',
                          'win', '--w:852px;--h:393px')
OUT['v3-web-wide'] = page('1280x800@1.5', '<div class="col2" style="height:800px">' + v3_bar() + view(web_results(1)) + '</div>',
                          'win', '--w:1280px;--h:800px')
OUT['v3-web-linux'] = page('1280x800@1.5', '<div class="col2" style="height:800px">' + v3_bar() + external_page() + '</div>',
                           'win', '--w:1280px;--h:800px')
# new
OUT['v4-web-phone'] = page('393x852@3', STATUS + '<div class="col2" style="height:816px">' + v4_bar(False) +
                           '<div class="prog"><i style="width:45%"></i></div>' + view(web_results(PH)) + '</div>')
OUT['v4-web-room'] = page('393x852@3', STATUS + '<div class="col2" style="height:816px">' + v4_bar() + view(web_room(PH), v4_room_bar()) + '</div>')
OUT['v4-web-failed'] = page('393x852@3', STATUS + '<div class="col2" style="height:816px">' + v4_bar(False) + view('', v4_fail()) + '</div>')
OUT['v4-web-land'] = page('852x393@2', SB24 + '<div class="col2" style="height:369px">' + v4_bar(False) +
                          view(web_room(LAND), v4_room_bar(False).replace('class="rbar"', 'class="rbar" style="left:auto;width:420px"')) + '</div>',
                          'win', '--w:852px;--h:393px')
OUT['v4-web-wide'] = page('1280x800@1.5', '<div class="col2" style="height:800px">' + v4_bar(False) +
                          view(web_room(1), v4_room_bar(False).replace('class="rbar"', 'class="rbar" style="left:auto;right:24px;bottom:24px;width:440px"')) + '</div>'
                          + '<div class="tip" style="right:52px;top:52px">使用系统浏览器打开</div>',
                          'win', '--w:1280px;--h:800px')
OUT['v4-web-linux'] = page('1280x800@1.5', '<div class="col2" style="height:800px">' + v4_bar(False, '哔哩哔哩 · 晚风').replace(
    f'<div class="ib2">{mr("open_in_new")}</div>', '') + external_page(True) + '</div>', 'win', '--w:1280px;--h:800px')

for name, html in OUT.items():
    open(os.path.join(HERE, name + '.html'), 'w', encoding='utf-8').write(html)
print(len(OUT), 'pages')
