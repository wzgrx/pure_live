/// A displayed audience figure like `1234`, `1,234`, `1.2万`, `3w+` or `1亿`
/// as a number; null when [text] has no digits.
int? audienceNumber(String text) {
  final match = RegExp(r'(\d+(?:\.\d+)?)\s*([万wW亿]?)').firstMatch(text.replaceAll(',', ''));
  if (match == null) return null;
  final number = double.parse(match.group(1)!);
  final unit = switch (match.group(2)) {
    '万' || 'w' || 'W' => 10000,
    '亿' => 100000000,
    _ => 1,
  };
  return (number * unit).round();
}
