"""Renders mockup pages (HTML using kit/kit.css) to JPEG with headless Chromium.

A mockup declares its size in the head:
    <meta name="mock-size" content="393x852@3">        phone, 3x
    <meta name="mock-size" content="852x393@2">        landscape phone
    <meta name="mock-size" content="393x2400@2 crop">  long panel, cut at the content
and writes paths relative to tools/ui/mock/ (href="kit/kit.css",
src=".cache/img/158.jpg"): pages are served with <base href> there.

usage: python3 tools/ui/mock/render.py <file.html | dir> ... [--out DIR] [--annotate] [--dark]
  --out       where the JPEGs go (default: for .../<task>/src/x.html, .../<task>/)
  --annotate  also render x-n.jpg with the numbered callouts (kit/annotate.js),
              for pages that mark controls with data-n
  --dark      also render x-dark.jpg with the dark colour roles
Output width is twice the logical width, at most 1704 px. Needs
chrome-headless-shell (Playwright's) and ffmpeg; run fetch.sh once first.
"""
import argparse, glob, os, re, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SHELLS = sorted(glob.glob(os.path.expanduser('~/.cache/ms-playwright/chromium_headless_shell-*/chrome-headless-shell-linux64/chrome-headless-shell')))
SIZE = re.compile(r'<meta\s+name="mock-size"\s+content="(\d+)x(\d+)@([\d.]+)(\s+crop)?"', re.I)


def content_height(png):
    sys.path.insert(0, os.path.join(HERE, '..'))
    from export_compare import content_height as ch  # same trimming as the page export
    return ch(png)


def render(src, out_dir, variant):
    html = open(src, encoding='utf-8').read()
    m = SIZE.search(html)
    w, h, scale, crop = (int(m.group(1)), int(m.group(2)), float(m.group(3)), bool(m.group(4))) if m else (393, 852, 3.0, False)
    inject = f'<base href="file://{HERE}/">'
    if variant == 'n':
        inject += '<script>document.documentElement.classList.add("annotate")</script><script src="kit/annotate.js"></script>'
    if variant == 'dark':
        inject += '<script>document.documentElement.setAttribute("data-theme","dark")</script>'
    html = re.sub(r'<head>', '<head>' + inject, html, count=1, flags=re.I)
    name = os.path.splitext(os.path.basename(src))[0] + ('' if not variant else f'-{variant}')
    with tempfile.TemporaryDirectory() as tmp:
        page = os.path.join(tmp, 'page.html')
        open(page, 'w', encoding='utf-8').write(html)
        png = os.path.join(tmp, 'shot.png')
        subprocess.run([SHELLS[-1], '--headless', '--no-sandbox', '--hide-scrollbars', '--allow-file-access-from-files',
                        f'--force-device-scale-factor={scale}', f'--window-size={w},{h}', '--virtual-time-budget=4000',
                        f'--screenshot={png}', f'file://{page}'], check=True, capture_output=True)
        vf = []
        if crop:
            vf.append(f'crop=iw:{content_height(png)}:0:0')
        vf.append(f"scale='min({min(w * 2, 1704)},iw)':-1")
        out = os.path.join(out_dir, name + '.jpg')
        subprocess.run(['ffmpeg', '-loglevel', 'error', '-y', '-i', png, '-vf', ','.join(vf), '-q:v', '4', out], check=True)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('inputs', nargs='+')
    ap.add_argument('--out')
    ap.add_argument('--annotate', action='store_true')
    ap.add_argument('--dark', action='store_true')
    args = ap.parse_args()
    if not SHELLS:
        sys.exit('render: chrome-headless-shell not found (npx playwright install chromium-headless-shell)')
    files = []
    for i in args.inputs:
        files += sorted(glob.glob(os.path.join(i, '*.html'))) if os.path.isdir(i) else [i]
    for f in files:
        f = os.path.abspath(f)
        out_dir = args.out or (os.path.dirname(os.path.dirname(f)) if os.path.basename(os.path.dirname(f)) == 'src' else os.path.dirname(f))
        os.makedirs(out_dir, exist_ok=True)
        numbered = 'data-n=' in open(f, encoding='utf-8').read()
        variants = [''] + (['n'] if args.annotate and numbered else []) + (['dark'] if args.dark else [])
        for v in variants:
            print(os.path.relpath(render(f, out_dir, v)))


if __name__ == '__main__':
    main()
