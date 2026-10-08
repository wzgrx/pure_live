"""Builds a comparison / review page from a task's spec (the task folder's page.json).

The page is one self-contained HTML file (pictures embedded) to publish as a
claude.ai page with the `db` capability. On that page every change has
"满意 / 不满意 / 再想想" buttons and a note, every choice has its options,
and there is a box for overall comments; they are saved in the page's
database (collection `review`, one document per item id:
{verdict | pick, note, ver, at}). Without the capability (a saved file, the
export) the controls stay hidden, so tools/ui/export_compare.py exports the
same file as clean section pictures.

usage: python3 tools/ui/mock/page.py docs/A-界面设计/A07-直播间界面/A07.4-横屏全屏/page.json [--out FILE]
  default out: ~/ref/design/compare/<id>.html

Spec (JSON; strings may contain HTML):
{
  "id": "U.2c", "title": "...", "version": 1, "date": "2026-10-01", "status": "待你确认",
  "intro": "<p>...</p>",
  "notes": [{"kind": "ok|warn|info", "html": "..."}],
  "sections": [
    {"h": "对比", "html": "...", "cols": 2,
     "figs": [{"img": "v3-phone.jpg", "cap": "v3", "sub": "手机横屏", "frame": "phone|land|long|plain"}]},
    {"h": "v3 的问题", "problems": [["F1", "问题", "位置"]]},
    {"h": "改了什么", "changes": [{"id": "c1", "type": "保留|修改|增强|去掉", "text": "..."}]},
    {"h": "每个按钮是干什么的、怎么用", "figs": [...], "usage": [["1", "控件", "怎么用"]]},
    {"h": "需要你选的", "choices": [{"id": "G1", "title": "...", "options": ["A，建议的做法", "B，另一种"]}]},
    {"h": "性能要点", "list": ["..."]},
    {"h": "...", "table": {"hdr": ["..."], "rows": [["..."]]}}
  ]
}
"""
import argparse, base64, html, json, mimetypes, os, re

HERE = os.path.dirname(os.path.abspath(__file__))
TAGS = {'保留': 'keep', '修改': 'chg', '增强': 'add', '去掉': 'prob'}


def esc(s):
    return html.escape(str(s), quote=True)


def data_uri(path):
    mime = mimetypes.guess_type(path)[0] or 'image/jpeg'
    return f'data:{mime};base64,' + base64.b64encode(open(path, 'rb').read()).decode()


def table(hdr, rows):
    head = ''.join(f'<th>{h}</th>' for h in hdr)
    body = ''.join('<tr>' + ''.join(f'<td>{c}</td>' for c in r) + '</tr>' for r in rows)
    return f'<div class="card tbl" style="margin-top:16px"><table><tr>{head}</tr>{body}</table></div>'


def rv_verdict(item):
    return (f'<div class="rv" data-id="{esc(item)}" data-kind="verdict">'
            '<button class="ok" data-v="ok" aria-pressed="false">满意</button>'
            '<button class="no" data-v="no" aria-pressed="false">不满意</button>'
            '<button class="hm" data-v="hm" aria-pressed="false">再想想</button>'
            '<input placeholder="想怎么改（可不填）"><span class="was"></span></div>')


def rv_pick(item, n):
    btns = ''.join(f'<button class="pick" data-v="{i}" aria-pressed="false">选 {chr(65 + i)}</button>' for i in range(n))
    return f'<div class="rv" data-id="{esc(item)}" data-kind="pick">{btns}<input placeholder="补充（可不填）"><span class="was"></span></div>'


def section(sec, base):
    out = [f'<h2>{sec["h"]}</h2>']
    if sec.get('html'):
        out.append(sec['html'])
    if sec.get('figs'):
        cols = sec.get('cols', min(len(sec['figs']), 2))
        figs = ''.join(
            f'<figure><figcaption>{f.get("cap", "")} <small>{f.get("sub", "")}</small></figcaption>'
            f'<img class="fimg {f.get("frame", "phone")}" alt="{esc(f.get("cap", ""))} {esc(f.get("sub", ""))}" src="{data_uri(os.path.join(base, f["img"]))}"></figure>'
            for f in sec['figs'])
        out.append(f'<div class="figs2 c{cols}">{figs}</div>')
    if sec.get('problems'):
        rows = [[f'<span class="tag prob">{esc(p[0])}</span>', p[1], p[2] if len(p) > 2 else '—'] for p in sec['problems']]
        out.append(table(['编号', '问题', '位置'], rows))
    if sec.get('changes'):
        rows = []
        for c in sec['changes']:
            t = c.get('type', '修改')
            text = c['text'] + (rv_verdict(c['id']) if c.get('id') else '')
            rows.append([f'<span class="tag {TAGS.get(t, "chg")}">{esc(t)}</span>' + (f'<br><small>{esc(c["id"])}</small>' if c.get('id') else ''), text])
        out.append(table(['类型', '内容'], rows))
    if sec.get('usage'):
        out.append(table(['编号', '控件', '怎么用'] if len(sec['usage'][0]) == 3 else ['控件', '怎么用'], sec['usage']))
    if sec.get('table'):
        out.append(table(sec['table']['hdr'], sec['table']['rows']))
    if sec.get('choices'):
        cards = ''
        for ch in sec['choices']:
            opts = ''.join(
                f'<div class="opt"><span class="tag {"add" if i == 0 else "keep"}">{chr(65 + i)}{" · 建议" if i == 0 else ""}</span><span>{o}</span></div>'
                for i, o in enumerate(ch['options']))
            cards += f'<div class="choice"><h3>{esc(ch["id"])}. {ch["title"]}</h3>{opts}{rv_pick(ch["id"], len(ch["options"]))}</div>'
        out.append(f'<div class="card choices">{cards}</div>')
    if sec.get('list'):
        out.append('<div class="card"><ul class="perf">' + ''.join(f'<li>{x}</li>' for x in sec['list']) + '</ul></div>')
    return '\n'.join(out)


SCRIPT = r'''<script>
(function(){
  var VER = __VER__;
  var LABEL = {ok:'满意', no:'不满意', hm:'再想想'};
  function start(db){
    if(!db) return;
    document.documentElement.classList.add('rv-on');
    var col = db.collection('review');
    var state = {};
    function paint(){
      var seen = 0, total = 0;
      document.querySelectorAll('.rv').forEach(function(box){
        total++;
        var d = state[box.dataset.id] || {};
        var cur = d.ver === VER;
        var val = box.dataset.kind === 'pick' ? String(d.pick) : d.verdict;
        box.querySelectorAll('button').forEach(function(b){ b.setAttribute('aria-pressed', String(cur && b.dataset.v === val)); });
        var input = box.querySelector('input');
        if (document.activeElement !== input) input.value = cur ? (d.note || '') : '';
        var was = box.querySelector('.was');
        was.textContent = (!cur && d.ver) ? ('第 ' + d.ver + ' 版：' + (box.dataset.kind === 'pick' ? ('选 ' + String.fromCharCode(65 + Number(d.pick))) : (LABEL[d.verdict] || '')) + (d.note ? ' · ' + d.note : '')) : '';
        if (cur && (val !== undefined && val !== 'undefined')) seen++;
      });
      var bar = document.querySelector('.rv-bar span');
      if (bar) bar.textContent = '已表态 ' + seen + ' / ' + total + ' 条';
      var ov = state.overall || {};
      var ta = document.querySelector('.overall textarea');
      if (ta && document.activeElement !== ta) ta.value = ov.ver === VER ? (ov.note || '') : '';
    }
    col.onSnapshot(function(snap){ state = {}; snap.docs.forEach(function(d){ state[d.id] = d.data(); }); paint(); },
                   function(){ document.querySelector('.rv-bar span').textContent = '保存暂时不可用，请刷新页面'; });
    function save(id, patch){
      var body = Object.assign({}, state[id] && state[id].ver === VER ? state[id] : {}, patch, {ver: VER, at: new Date().toISOString()});
      state[id] = body; paint();
      col.doc(id).set(body).catch(function(){ document.querySelector('.rv-bar span').textContent = '有一条没保存上，请再点一次'; });
    }
    document.querySelectorAll('.rv').forEach(function(box){
      box.querySelectorAll('button').forEach(function(b){
        b.addEventListener('click', function(){
          save(box.dataset.id, box.dataset.kind === 'pick' ? {pick: Number(b.dataset.v)} : {verdict: b.dataset.v});
        });
      });
      box.querySelector('input').addEventListener('change', function(e){ save(box.dataset.id, {note: e.target.value}); });
    });
    var ta = document.querySelector('.overall textarea');
    if (ta) ta.addEventListener('change', function(){ save('overall', {note: ta.value}); });
  }
  if (window.claude && window.claude.use) window.claude.use('db').then(start, function(){});
})();
</script>'''


def build(spec_path):
    spec = json.load(open(spec_path, encoding='utf-8'))
    base = os.path.dirname(os.path.abspath(spec_path))
    css = open(os.path.join(HERE, 'kit', 'page.css'), encoding='utf-8').read()
    head = (f'<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
            f'<title>{esc(spec["id"])} {esc(spec.get("short", "对比"))}</title><style>{css}</style>'
            + SCRIPT.replace('__VER__', str(int(spec.get('version', 1)))) + '</head><body>')
    parts = [f'<div class="wrap"><h1>{spec["title"]}</h1>',
             f'<p class="meta">{esc(spec["id"])} · 第 {spec.get("version", 1)} 版 · {esc(spec.get("date", ""))} · {esc(spec.get("status", "待你确认"))}</p>',
             '<div class="rv-bar">每一条下面可以点“满意 / 不满意 / 再想想”，写一句想怎么改；会自动保存，我这边能直接看到。<span></span></div>',
             spec.get('intro', '')]
    for n in spec.get('notes', []):
        parts.append(f'<div class="card note {n.get("kind", "info")}" style="margin-top:12px">{n["html"]}</div>')
    if spec.get('legend', True):
        parts.append('<div class="legend"><span class="tag prob">P v3 的问题</span><span class="tag keep">保留</span><span class="tag chg">修改</span><span class="tag add">增强</span></div>')
    for sec in spec.get('sections', []):
        parts.append(section(sec, base))
    parts.append('<div class="overall"><h3 style="font-size:19px;margin:40px 0 12px">整体意见</h3><div class="card"><textarea placeholder="整体满意吗？哪里还想改？（会自动保存）"></textarea></div></div>')
    parts.append('</div></body></html>')
    return head + '\n'.join(parts)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('spec')
    ap.add_argument('--out')
    args = ap.parse_args()
    spec_id = json.load(open(args.spec, encoding='utf-8'))['id']
    out = args.out or os.path.expanduser(f'~/ref/design/compare/{spec_id}.html')
    os.makedirs(os.path.dirname(out), exist_ok=True)
    open(out, 'w', encoding='utf-8').write(build(args.spec))
    print(out)


if __name__ == '__main__':
    main()
