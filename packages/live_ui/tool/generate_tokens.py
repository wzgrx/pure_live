"""Generates lib/src/color_tokens.dart from spec/design/tokens.json.

Run from the repository root: python3 packages/live_ui/tool/generate_tokens.py
test/color_tokens_test.dart fails when the generated file is out of date.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
TOKENS = ROOT / 'spec/design/tokens.json'
OUTPUT = ROOT / 'packages/live_ui/lib/src/color_tokens.dart'


def camel(name):
    parts = name.split('-')
    return parts[0] + ''.join(part.capitalize() for part in parts[1:])


def argb(value):
    value = value.strip()
    if value.startswith('#'):
        return '0xFF' + value[1:].upper()
    red, green, blue, alpha = re.match(r'rgba\((\d+),\s*(\d+),\s*(\d+),\s*([\d.]+)\)', value).groups()
    return '0x%02X%02X%02X%02X' % (round(float(alpha) * 255), int(red), int(green), int(blue))


def render(tokens):
    themes = {'light': [], 'dark': [], 'black': []}
    fixed = []
    for token in tokens['color']['tokens']:
        value, name = token['value'], camel(token['name'])
        if isinstance(value, dict):
            themes['light'].append((name, argb(value['light'])))
            themes['dark'].append((name, argb(value['dark'])))
            themes['black'].append((name, argb(value.get('black', value['dark']))))
        else:
            fixed.append((name, argb(value)))
    names = [name for name, _ in themes['light']]
    out = [
        '// GENERATED from spec/design/tokens.json by packages/live_ui/tool/generate_tokens.py.',
        '// Do not edit by hand; change the tokens and regenerate.',
        '',
        "import 'dart:ui';",
        '',
        '/// Colour tokens of one theme (spec/design/tokens.json).',
        'final class ColorTokens {',
        '  /// Creates a token set.',
        '  const new({',
    ]
    out += [f'    required this.{name},' for name in names]
    out += ['  });', '']
    for name in names:
        out += [f'  /// Token `{name}`.', f'  final Color {name};', '']
    for theme in ('light', 'dark', 'black'):
        out += [f'  /// The {theme} theme.', f'  static const {theme} = ColorTokens(']
        out += [f'    {name}: Color({value}),' for name, value in themes[theme]]
        out += ['  );', '']
    out.pop()
    out += ['}', '', '/// Tokens that are the same in every theme.', 'abstract final class FixedColors {']
    for name, value in fixed:
        out += [f'  /// Token `{name}`.', f'  static const {name} = Color({value});', '']
    out.pop()
    out += ['}', '']
    return '\n'.join(out)


if __name__ == '__main__':
    text = render(json.loads(TOKENS.read_text(encoding='utf-8')))
    if '--check' in sys.argv:
        sys.exit(0 if OUTPUT.read_text(encoding='utf-8') == text else 1)
    OUTPUT.write_text(text, encoding='utf-8')
