/// A small, tolerant reader of server-rendered HTML fragments, for the
/// parsers that 3.x wrote with `package:html` selectors (AcFun's search
/// page). It builds an element tree without adding a dependency; scripts
/// are kept as text and never run.
library;

import 'package:live_core/src/json.dart';

/// Elements that never have content or an end tag.
const _voidElements = {
  'area',
  'base',
  'br',
  'col',
  'embed',
  'hr',
  'img',
  'input',
  'link',
  'meta',
  'param',
  'source',
  'track',
  'wbr',
};

/// Elements whose content is raw text up to their own end tag.
const _rawTextElements = {'script', 'style', 'textarea', 'title'};

final RegExp _tagName = RegExp(r'[a-zA-Z][^\s/>]*');
final RegExp _attributeName = RegExp('[^\\s"\'>/=]+');
final RegExp _unquoted = RegExp(r'[^\s>]+');
final RegExp _spaces = RegExp(r'\s+');

/// One element of a parsed fragment.
final class HtmlElement {
  new _(this.tag, this.attributes, this.parent);

  /// Parses [html] into a fragment root. Unclosed elements end with the
  /// fragment, stray end tags are ignored, and an end tag closes the
  /// nearest open element of its name (and everything opened inside it).
  factory parseFragment(String html) {
    final root = HtmlElement._('#fragment', const {}, null);
    final open = <HtmlElement>[root];
    var index = 0;
    final text = StringBuffer();

    void flushText() {
      if (text.isEmpty) return;
      open.last._content.add(decodeHtmlEntities(text.toString()));
      text.clear();
    }

    while (index < html.length) {
      final lt = html.indexOf('<', index);
      if (lt < 0) {
        text.write(html.substring(index));
        break;
      }
      text.write(html.substring(index, lt));
      index = lt;
      if (html.startsWith('<!--', index)) {
        flushText();
        final end = html.indexOf('-->', index + 4);
        index = end < 0 ? html.length : end + 3;
        continue;
      }
      if (html.startsWith('</', index)) {
        final name = _tagName.matchAsPrefix(html, index + 2);
        if (name == null) {
          text.write('<');
          index++;
          continue;
        }
        flushText();
        final end = html.indexOf('>', name.end);
        index = end < 0 ? html.length : end + 1;
        final tag = name.group(0)!.toLowerCase();
        final at = open.lastIndexWhere((element) => element.tag == tag);
        if (at > 0) open.removeRange(at, open.length);
        continue;
      }
      if (html.startsWith('<!', index) || html.startsWith('<?', index)) {
        flushText();
        final end = html.indexOf('>', index);
        index = end < 0 ? html.length : end + 1;
        continue;
      }
      final name = _tagName.matchAsPrefix(html, index + 1);
      if (name == null) {
        text.write('<');
        index++;
        continue;
      }
      flushText();
      final tag = name.group(0)!.toLowerCase();
      final attributes = <String, String>{};
      var cursor = name.end;
      var selfClosing = false;
      while (cursor < html.length) {
        while (cursor < html.length && html[cursor].trim().isEmpty) {
          cursor++;
        }
        if (cursor >= html.length) break;
        if (html[cursor] == '>') {
          cursor++;
          break;
        }
        if (html.startsWith('/>', cursor)) {
          selfClosing = true;
          cursor += 2;
          break;
        }
        final attribute = _attributeName.matchAsPrefix(html, cursor);
        if (attribute == null) {
          cursor++;
          continue;
        }
        cursor = attribute.end;
        var value = '';
        var probe = cursor;
        while (probe < html.length && html[probe].trim().isEmpty) {
          probe++;
        }
        if (probe < html.length && html[probe] == '=') {
          probe++;
          while (probe < html.length && html[probe].trim().isEmpty) {
            probe++;
          }
          if (probe < html.length && (html[probe] == '"' || html[probe] == "'")) {
            final close = html.indexOf(html[probe], probe + 1);
            final end = close < 0 ? html.length : close;
            value = html.substring(probe + 1, end);
            cursor = close < 0 ? html.length : close + 1;
          } else {
            final bare = _unquoted.matchAsPrefix(html, probe);
            value = bare?.group(0) ?? '';
            cursor = bare?.end ?? probe;
          }
        }
        attributes.putIfAbsent(attribute.group(0)!.toLowerCase(), () => decodeHtmlEntities(value));
      }
      index = cursor;
      final element = HtmlElement._(tag, Map.unmodifiable(attributes), open.last);
      open.last._content.add(element);
      if (selfClosing || _voidElements.contains(tag)) continue;
      if (_rawTextElements.contains(tag)) {
        final close = RegExp('</$tag', caseSensitive: false).allMatches(html, index).firstOrNull?.start ?? -1;
        final end = close < 0 ? html.length : close;
        if (end > index) {
          final raw = html.substring(index, end);
          element._content.add(tag == 'script' || tag == 'style' ? raw : decodeHtmlEntities(raw));
        }
        final after = close < 0 ? -1 : html.indexOf('>', close);
        index = after < 0 ? html.length : after + 1;
        continue;
      }
      open.add(element);
    }
    flushText();
    return root;
  }

  /// Tag name in lower case; `#fragment` for the root of a fragment.
  final String tag;

  /// Attributes by lower-case name, values with character references
  /// decoded; the first of a repeated attribute wins, as in browsers.
  final Map<String, String> attributes;

  /// The enclosing element; null for the fragment root.
  final HtmlElement? parent;

  /// Content in document order: text ([String]) and child elements.
  final List<Object> _content = [];

  /// Child elements in document order.
  Iterable<HtmlElement> get children => _content.whereType<HtmlElement>();

  /// Every element inside this one, in document order.
  Iterable<HtmlElement> get descendants sync* {
    for (final child in children) {
      yield child;
      yield* child.descendants;
    }
  }

  /// The enclosing elements, nearest first.
  Iterable<HtmlElement> get ancestors sync* {
    for (var node = parent; node != null; node = node.parent) {
      yield node;
    }
  }

  /// The `class` attribute's names.
  Set<String> get classes => {
    for (final name in (attributes['class'] ?? '').split(_spaces))
      if (name.isNotEmpty) name,
  };

  /// Whether the `class` attribute lists [name].
  bool hasClass(String name) => classes.contains(name);

  /// The text of this element and its descendants, references decoded
  /// (the DOM's `textContent`).
  String get text {
    final buffer = StringBuffer();
    void collect(HtmlElement element) {
      for (final node in element._content) {
        if (node is String) {
          buffer.write(node);
        } else {
          collect(node as HtmlElement);
        }
      }
    }

    collect(this);
    return buffer.toString();
  }

  /// The first descendant, in document order, that passes [test].
  HtmlElement? query(bool Function(HtmlElement element) test) {
    for (final element in descendants) {
      if (test(element)) return element;
    }
    return null;
  }

  /// Every descendant, in document order, that passes [test].
  Iterable<HtmlElement> queryAll(bool Function(HtmlElement element) test) => descendants.where(test);

  @override
  String toString() => 'HtmlElement($tag${attributes.isEmpty ? '' : ' $attributes'})';
}
