"""Lists the translated strings a v3 (or pure_live_TV) file uses, in order,
with their Chinese text, so a restored mockup copies v3's words exactly.

usage: python3 tools/ui/strings.py <file under lib/> [--root ~/ref/v3ref]
  e.g. python3 tools/ui/strings.py modules/live_play/widgets/button/record_action_button.dart
"""
import argparse, json, os, re

I18N = re.compile(r"""\bi18n\(\s*['"]([a-zA-Z0-9_]+)['"]""")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('file')
    ap.add_argument('--root', default=os.path.expanduser('~/ref/v3ref'))
    args = ap.parse_args()
    zh = json.load(open(os.path.join(args.root, 'assets', 'translations', 'zh.json'), encoding='utf-8'))
    path = args.file if os.path.isabs(args.file) else os.path.join(args.root, 'lib', args.file)
    seen = set()
    for n, line in enumerate(open(path, encoding='utf-8'), 1):
        for key in I18N.findall(line):
            if key in seen:
                continue
            seen.add(key)
            print(f'{n:5d}  {key:40s} {zh.get(key, "（没有中文）")}')


if __name__ == '__main__':
    main()
