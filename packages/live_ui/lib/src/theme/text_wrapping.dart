/// U+2060 WORD JOINER: no line break on either side of it, and nothing drawn.
const String wordJoiner = '⁠';

const int _wordJoinerRune = 0x2060;
const int _noBreakSpaceRune = 0x00A0;

/// Han, kana and Hangul: each one a word for line breaking.
bool _isCjk(int rune) =>
    (rune >= 0x3040 && rune <= 0x30FF) ||
    (rune >= 0x3400 && rune <= 0x4DBF) ||
    (rune >= 0x4E00 && rune <= 0x9FFF) ||
    (rune >= 0xAC00 && rune <= 0xD7AF) ||
    (rune >= 0xF900 && rune <= 0xFAFF) ||
    (rune >= 0x20000 && rune <= 0x2FA1F);

/// Punctuation and spaces at the end of a text, which the line breaker keeps
/// with the word before them anyway.
bool _isTrailing(int rune) =>
    rune <= 0x20 ||
    (rune >= 0x21 && rune <= 0x2F) ||
    (rune >= 0x3A && rune <= 0x40) ||
    (rune >= 0x5B && rune <= 0x60) ||
    (rune >= 0x7B && rune <= 0x7E) ||
    (rune >= 0x2010 && rune <= 0x2027) ||
    (rune >= 0x3000 && rune <= 0x303F) ||
    (rune >= 0xFF01 && rune <= 0xFF0F) ||
    (rune >= 0xFF1A && rune <= 0xFF20) ||
    (rune >= 0xFF3B && rune <= 0xFF40) ||
    (rune >= 0xFF5B && rune <= 0xFF65);

/// [text] that never ends a paragraph with a line of one character
/// (docs/A-界面设计/A01-设计系统/A01.4-全局细节打磨 c1; Flutter has no `text-wrap:
/// pretty`): the last two Chinese characters of each paragraph are joined
/// with [wordJoiner], so a line break before the last one takes the one
/// before it along; in other text the last space becomes a no-break space.
/// Punctuation at the end stays with the word before it.
///
/// For explanations (setting rows, panels, status pages, banners), not
/// titles.
String withoutOrphan(String text) {
  if (text.isEmpty) return text;
  if (text.contains('\n')) return text.split('\n').map(withoutOrphan).join('\n');
  final runes = text.runes.toList();
  var end = runes.length;
  while (end > 0 && _isTrailing(runes[end - 1])) {
    end--;
  }
  if (end < 2) return text;
  final last = runes[end - 1];
  if (_isCjk(last)) {
    if (!_isCjk(runes[end - 2])) return text;
    return String.fromCharCodes([...runes.take(end - 1), _wordJoinerRune, ...runes.skip(end - 1)]);
  }
  // A word of other letters: join it to the word before.
  var space = end - 1;
  while (space > 0 && runes[space] != 0x20 && !_isCjk(runes[space])) {
    space--;
  }
  if (space <= 0 || runes[space] != 0x20 || runes[space - 1] == 0x20) return text;
  return String.fromCharCodes([...runes.take(space), _noBreakSpaceRune, ...runes.skip(space + 1)]);
}
