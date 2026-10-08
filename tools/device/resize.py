#!/usr/bin/env python3
"""Shrink device screenshots and put them side by side (Z04.1).

  resize.py shrink IN.png OUT.jpg WIDTH     scale to WIDTH, save as JPEG, delete IN
  resize.py row OUT.jpg WIDTH IMG...        each image scaled to WIDTH, side by side,
                                            shorter ones padded at the bottom

Uses Pillow when it is installed, otherwise ffmpeg (and ffprobe for rows). With
neither, `shrink` keeps the PNG and says so; `row` fails. Standard library only
apart from those optional tools.
"""

import shutil
import subprocess
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:  # Pillow is optional
    Image = None


def scaled_height(width, height, target):
    """Height after scaling (width, height) to `target` wide, rounded to even."""
    value = round(height * target / width)
    return max(2, value + (value % 2))


def shrink(src, dst, width):
    src, dst = Path(src), Path(dst)
    if Image is not None:
        with Image.open(src) as image:
            size = (width, scaled_height(image.width, image.height, width))
            image.convert('RGB').resize(size, Image.LANCZOS).save(dst, 'JPEG', quality=80)
    elif shutil.which('ffmpeg'):
        subprocess.run(['ffmpeg', '-loglevel', 'error', '-y', '-i', str(src),
                        '-vf', f'scale={width}:-2', '-q:v', '4', str(dst)], check=True)
    else:
        print(f'NOTE: neither Pillow nor ffmpeg is installed; kept {src} unscaled')
        return src
    src.unlink()
    print(dst)
    return dst


def _probe(path):
    out = subprocess.run(['ffprobe', '-v', 'error', '-select_streams', 'v:0',
                          '-show_entries', 'stream=width,height', '-of', 'csv=p=0', str(path)],
                         check=True, capture_output=True, text=True).stdout
    width, height = out.strip().split(',')[:2]
    return int(width), int(height)


def row(dst, width, images):
    if not images:
        raise SystemExit('row: no images')
    if Image is not None:
        tiles = []
        for path in images:
            with Image.open(path) as image:
                size = (width, scaled_height(image.width, image.height, width))
                tiles.append(image.convert('RGB').resize(size, Image.LANCZOS))
        canvas = Image.new('RGB', (width * len(tiles), max(t.height for t in tiles)), 'black')
        for index, tile in enumerate(tiles):
            canvas.paste(tile, (index * width, 0))
        canvas.save(dst, 'JPEG', quality=80)
    elif shutil.which('ffmpeg') and shutil.which('ffprobe'):
        heights = [scaled_height(*_probe(p), width) for p in images]
        top = max(heights)
        args, chains = [], []
        for index, path in enumerate(images):
            args += ['-i', str(path)]
            chains.append(f'[{index}]scale={width}:{heights[index]},pad={width}:{top}[v{index}]')
        if len(images) == 1:
            graph = chains[0].replace('[v0]', '')
        else:
            inputs = ''.join(f'[v{i}]' for i in range(len(images)))
            graph = ';'.join(chains) + f';{inputs}hstack={len(images)}'
        subprocess.run(['ffmpeg', '-loglevel', 'error', '-y', *args, '-filter_complex', graph,
                        '-q:v', '4', str(dst)], check=True)
    else:
        raise SystemExit('row: needs Pillow, or ffmpeg and ffprobe')
    print(dst)
    return Path(dst)


def main(argv):
    if len(argv) == 4 and argv[0] == 'shrink':
        shrink(argv[1], argv[2], int(argv[3]))
        return 0
    if len(argv) >= 4 and argv[0] == 'row':
        row(argv[1], int(argv[2]), argv[3:])
        return 0
    print(__doc__.strip(), file=sys.stderr)
    return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
