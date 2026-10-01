"""Exports a comparison page (kept outside the repository; published as a
claude.ai page) as one JPEG per
section, so the review reads on GitHub without the page. Needs headless
Chromium (Playwright's chrome-headless-shell) and ffmpeg.

usage: python3 tools/ui/export_compare.py <compare.html> <out dir>
"""
import glob, os, re, subprocess, sys, tempfile

SHELL = sorted(glob.glob(os.path.expanduser('~/.cache/ms-playwright/chromium_headless_shell-*/chrome-headless-shell-linux64/chrome-headless-shell')))[-1]
WIDTH, SCALE, TALL = 1100, 1.5, 9000


def content_height(png):
    """Height in pixels down to the last row that differs from the page background."""
    w = int(subprocess.check_output(['ffprobe', '-v', 'error', '-select_streams', 'v', '-show_entries', 'stream=width', '-of', 'csv=p=0', png]).strip())
    raw = subprocess.check_output(['ffmpeg', '-loglevel', 'error', '-i', png, '-f', 'rawvideo', '-pix_fmt', 'gray', '-'])
    rows = len(raw) // w
    bg = raw[(rows - 1) * w:(rows) * w]  # the bottom row is page background
    for y in range(rows - 1, -1, -1):
        row = raw[y * w:(y + 1) * w]
        if row != bg and max(abs(a - b) for a, b in zip(row[::4], bg[::4])) > 6:
            return min(rows, y + 1 + int(24 * SCALE))
    return rows


def main(src, out):
    os.makedirs(out, exist_ok=True)
    page = open(src, encoding='utf-8').read()
    head_end = page.index('<div class="wrap">')
    head, body = page[:head_end], page[head_end + len('<div class="wrap">'):]
    body = body[:body.rindex('</div>')]
    parts = re.split(r'(?=<h2>)', body)
    with tempfile.TemporaryDirectory() as tmp:
        for i, part in enumerate(parts, 1):
            title = re.search(r'<h2>(.*?)</h2>', part)
            name = re.sub(r'[^\w一-鿿]+', '-', title.group(1) if title else '对比').strip('-')
            html = os.path.join(tmp, f'{i}.html')
            with open(html, 'w', encoding='utf-8') as f:
                f.write('<!doctype html><html><head><meta charset="utf-8"></head><body style="margin:0">' + head + '<div class="wrap">' + part + '</div></body></html>')
            png = os.path.join(tmp, f'{i}.png')
            subprocess.run([SHELL, '--headless', '--no-sandbox', '--hide-scrollbars', f'--force-device-scale-factor={SCALE}', f'--window-size={WIDTH},{TALL}', '--virtual-time-budget=4000', f'--screenshot={png}', 'file://' + html], check=True, capture_output=True)
            h = content_height(png)
            jpg = os.path.join(out, f'{i:02d}-{name}.jpg')
            subprocess.run(['ffmpeg', '-loglevel', 'error', '-y', '-i', png, '-vf', f'crop=iw:{h}:0:0', '-q:v', '6', jpg], check=True)
            print(jpg)


if __name__ == '__main__':
    main(*sys.argv[1:3])
