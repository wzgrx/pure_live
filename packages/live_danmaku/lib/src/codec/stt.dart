/// Douyu's STT text serialisation (spec/sites/douyu.md §7.3): `key@=value/`
/// pairs; inside a value `@` is `@A` and `/` is `@S`.
///
/// Decoding is shallow on purpose: chat text may legitimately contain `@=`
/// or `//` (a pasted link), so only fields known to be nested are decoded a
/// second time, through [map] and [list].
abstract final class Stt {
  /// Escapes a value.
  static String escape(String value) => value.replaceAll('@', '@A').replaceAll('/', '@S');

  /// Reverses [escape].
  static String unescape(String value) => value.replaceAll('@S', '/').replaceAll('@A', '@');

  /// The pairs of [text], values unescaped once. Later duplicates win.
  static Map<String, String> map(String text) {
    final result = <String, String>{};
    for (final part in text.split('/')) {
      final separator = part.indexOf('@=');
      if (separator <= 0) continue;
      result[unescape(part.substring(0, separator))] = unescape(part.substring(separator + 2));
    }
    return result;
  }

  /// The items of a list value (as returned by [map]), each unescaped once;
  /// an item that is itself a structure goes through [map] again.
  static List<String> list(String value) => [
    for (final item in value.split('/'))
      if (item.isNotEmpty) unescape(item),
  ];

  /// Serialises [pairs] in order.
  static String encode(Map<String, String> pairs) =>
      pairs.entries.map((entry) => '${escape(entry.key)}@=${escape(entry.value)}/').join();
}
