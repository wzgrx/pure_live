import 'package:flutter/material.dart';
import 'package:live_ui/src/icons/app_icons.dart';
import 'package:live_ui/src/theme/live_colors.dart';

/// One visible line of a [JsonTreeSliver].
@immutable
final class JsonTreeLine {
  /// Creates a line.
  const new({required this.path, required this.name, required this.value, required this.depth});

  /// Where the value sits ("app/realOnlinePlatforms"); a branch's identity.
  final String path;

  /// The key, or the index of a list item.
  final String name;

  /// The value (a map or list is a branch).
  final Object? value;

  /// How deep it is (0 for the top level).
  final int depth;

  /// Whether it opens.
  bool get branch => value is Map || value is List;
}

/// The lines of [data] shown with the branches in [open] open (3.x
/// flutter_json's tree, flattened so the page builds only the lines on
/// screen).
List<JsonTreeLine> jsonTreeLines(Map<String, Object?> data, Set<String> open) {
  final lines = <JsonTreeLine>[];
  void walk(Object? value, String path, int depth) {
    final children = switch (value) {
      final Map<Object?, Object?> map => map.entries.map((entry) => MapEntry('${entry.key}', entry.value)),
      final List<Object?> list => [for (final (index, item) in list.indexed) MapEntry('$index', item)],
      _ => const <MapEntry<String, Object?>>[],
    };
    for (final MapEntry(:key, value: child) in children) {
      final childPath = path.isEmpty ? key : '$path/$key';
      final line = JsonTreeLine(path: childPath, name: key, value: child, depth: depth);
      lines.add(line);
      if (line.branch && open.contains(childPath)) walk(child, childPath, depth + 1);
    }
  }

  walk(data, '', 0);
  return lines;
}

/// The paths of the branches in the first [levels] levels of [data]; one
/// open level shows two levels of lines (3.x: the sections open, their
/// lists and maps closed).
Set<String> jsonTreeOpenLevels(Map<String, Object?> data, {int levels = 1}) {
  final open = <String>{};
  void walk(Object? value, String path, int depth) {
    if (depth >= levels) return;
    final children = switch (value) {
      final Map<Object?, Object?> map => map.entries.map((entry) => MapEntry('${entry.key}', entry.value)),
      final List<Object?> list => [for (final (index, item) in list.indexed) MapEntry('$index', item)],
      _ => const <MapEntry<String, Object?>>[],
    };
    for (final MapEntry(:key, value: child) in children) {
      if (child is! Map && child is! List) continue;
      final childPath = path.isEmpty ? key : '$path/$key';
      open.add(childPath);
      walk(child, childPath, depth + 1);
    }
  }

  walk(data, '', 0);
  return open;
}

/// A JSON tree as a sliver: one line per key, branches open and close with a
/// tap on the key; colours from the theme (U.6e e11: keys primary 600,
/// numbers green, strings tertiary, booleans dark yellow, branches
/// secondary text), so both themes pass contrast. Scrolls with the page
/// (e9).
class JsonTreeSliver extends StatefulWidget {
  /// Creates the tree of [data] with the first [openLevels] levels open.
  const new({
    required this.data,
    this.openLevels = 1,
    this.objectLabel = 'Object',
    this.arrayLabel = 'Array',
    super.key,
  });

  /// The content.
  final Map<String, Object?> data;

  /// Levels open at first.
  final int openLevels;

  /// How a map reads ("Object").
  final String objectLabel;

  /// How a list reads (`Array<String>[8]`).
  final String arrayLabel;

  @override
  State<JsonTreeSliver> createState() => _JsonTreeSliverState();
}

class _JsonTreeSliverState extends State<JsonTreeSliver> {
  late Set<String> _open = jsonTreeOpenLevels(widget.data, levels: widget.openLevels);
  late List<JsonTreeLine> _lines = jsonTreeLines(widget.data, _open);

  @override
  void didUpdateWidget(JsonTreeSliver oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.data, widget.data)) {
      _open = jsonTreeOpenLevels(widget.data, levels: widget.openLevels);
      _lines = jsonTreeLines(widget.data, _open);
    }
  }

  void _toggle(JsonTreeLine line) => setState(() {
    if (!_open.remove(line.path)) _open.add(line.path);
    _lines = jsonTreeLines(widget.data, _open);
  });

  String _describe(Object? value) => switch (value) {
    final Map<Object?, Object?> _ => widget.objectLabel,
    final List<Object?> list => '${widget.arrayLabel}<${_itemType(list)}>[${list.length}]',
    final String text => '"$text"',
    null => 'null',
    _ => '$value',
  };

  static String _itemType(List<Object?> list) {
    final types = {for (final item in list) _typeName(item)};
    return types.length == 1 ? types.first : 'dynamic';
  }

  static String _typeName(Object? value) => switch (value) {
    String() => 'String',
    int() => 'int',
    double() => 'double',
    bool() => 'bool',
    Map() => 'Object',
    List() => 'Array',
    _ => 'dynamic',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final base = (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
      fontSize: theme.textTheme.bodyLarge?.fontSize,
      height: 1.4,
    );
    Color valueColor(Object? value) => switch (value) {
      num() => dark ? LiveSemanticColors.successDark : LiveSemanticColors.successLight,
      String() => colors.tertiary,
      bool() => dark ? LiveSemanticColors.warningDark : LiveSemanticColors.warningLight,
      _ => colors.onSurfaceVariant,
    };
    return SliverList.builder(
      itemCount: _lines.length,
      itemBuilder: (context, index) {
        final line = _lines[index];
        final open = _open.contains(line.path);
        final row = Padding(
          padding: EdgeInsetsDirectional.only(start: 12.0 + line.depth * 20, end: 12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 36),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: line.branch
                      ? Icon(
                          open ? AppIcons.treeExpanded : AppIcons.treeCollapsed,
                          size: 20,
                          color: colors.onSurfaceVariant,
                        )
                      : null,
                ),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: line.name,
                          style: TextStyle(fontWeight: FontWeight.w600, color: colors.primary),
                        ),
                        TextSpan(
                          text: ': ',
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                        TextSpan(
                          text: _describe(line.value),
                          style: TextStyle(color: valueColor(line.value)),
                        ),
                      ],
                    ),
                    style: base,
                  ),
                ),
              ],
            ),
          ),
        );
        return line.branch
            ? InkWell(key: ValueKey('json-tree-${line.path}'), onTap: () => _toggle(line), child: row)
            : KeyedSubtree(key: ValueKey('json-tree-${line.path}'), child: row);
      },
    );
  }
}
