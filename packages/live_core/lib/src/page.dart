import 'package:meta/meta.dart';

/// Opaque position of the next page; only the adapter that issued it reads it.
@immutable
final class PageCursor {
  /// Wraps an adapter-specific value (a page number, an offset, a token).
  const new(this.value);

  /// The adapter's value.
  final String value;

  @override
  bool operator ==(Object other) => other is PageCursor && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'PageCursor($value)';
}

/// One page of results (ADR 0010, rule 4).
///
/// The adapter decides whether more pages exist by the platform's own rule;
/// callers never infer the end from the item count.
@immutable
final class Page<T> {
  /// Creates a page; [next] is null on the last page.
  const new(this.items, {this.next});

  /// An empty last page.
  const new empty() : items = const [], next = null;

  /// Items in the order the platform spec defines (platform order unless the
  /// spec re-sorts).
  final List<T> items;

  /// Cursor for the following page, or null when this is the last one.
  final PageCursor? next;

  /// Whether no more pages follow.
  bool get isLast => next == null;
}
