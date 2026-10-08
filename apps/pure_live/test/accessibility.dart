// Flutter's accessibility guidelines over what is on screen, with each failure
// traced to the code that built it (docs/A-界面设计/A05-无障碍/A05.1-无障碍检查 c1).

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The guidelines every screen meets: 48×48 tap targets (Android), a label
/// on everything tappable, and WCAG AA text contrast (4.5:1; 3:1 for large
/// text).
const List<AccessibilityGuideline> appGuidelines = [
  androidTapTargetGuideline,
  labeledTapTargetGuideline,
  textContrastGuideline,
];

/// A failure that stays until the maintainer decides how its fix changes
/// the look (docs/A-界面设计/A05-无障碍/A05.1-无障碍检查/README.md, "待选和决定"):
/// the guideline, the file that built the node (`search/search_widgets.dart`)
/// and why.
typedef KnownAccessibilityFailure = ({Type guideline, String place, String why});

/// The failures of [appGuidelines] on the current frame, one line each with
/// the places in `lib/` that built the node; empty when all pass.
///
/// [known] failures are left out (matched on the place that built the node
/// itself), and so is selectable text, a read-only field the tap-target rule
/// counts as a button.
Future<List<String>> accessibilityFailures(
  WidgetTester tester, {
  List<KnownAccessibilityFailure> known = const [],
}) async {
  final handle = tester.ensureSemantics();
  try {
    await tester.pump();
    final failures = <String>[];
    for (final guideline in appGuidelines) {
      final evaluation = await guideline.evaluate(tester);
      if (evaluation.passed) continue;
      for (final reason in _split(evaluation.reason ?? '')) {
        final id = int.parse(RegExp(r'SemanticsNode#(\d+)').firstMatch(reason)!.group(1)!);
        if (guideline is MinimumTapTargetGuideline && _selectableText(tester, id)) continue;
        final places = _where(tester, id);
        final own = places.isEmpty ? '' : places.first;
        if (known.any((entry) => entry.guideline == guideline.runtimeType && own.contains(entry.place))) continue;
        failures.add('${guideline.runtimeType}: ${_summary(reason)}\n    at ${places.join(' < ')}');
      }
    }
    return failures;
  } finally {
    handle.dispose();
  }
}

/// Fails with every guideline failure on the current frame and where it was
/// built ([screen] names what is shown).
Future<void> expectAccessible(
  WidgetTester tester,
  String screen, {
  List<KnownAccessibilityFailure> known = const [],
}) async {
  final failures = await accessibilityFailures(tester, known: known);
  if (failures.isNotEmpty) fail('$screen:\n${failures.join('\n')}');
}

/// One reason per failing node (each starts with the node's description).
Iterable<String> _split(String reasons) sync* {
  final starts = RegExp(r'SemanticsNode#\d+').allMatches(reasons).map((match) => match.start).toList();
  for (var i = 0; i < starts.length; i++) {
    yield reasons.substring(starts[i], i + 1 < starts.length ? starts[i + 1] : reasons.length).trim();
  }
}

/// The node, its words, what was found and where it is on screen.
String _summary(String reason) {
  final node = RegExp(r'SemanticsNode#\d+').firstMatch(reason)!.group(0)!;
  final detail = switch (reason) {
    _ when reason.contains('tap target') => RegExp(r'found Size\([^)]*\)').firstMatch(reason)?.group(0) ?? '',
    _ when reason.contains('semantic label') => 'no label',
    _ =>
      '${RegExp(r'found [\d.]+ for a font size of [\w.]+').firstMatch(reason)?.group(0) ?? ''} '
          '(${RegExp(r'light - Color\([^)]*\), dark - Color\([^)]*\)').firstMatch(reason)?.group(0) ?? ''})',
  };
  final label = RegExp('label: "([^"]*)"').firstMatch(reason)?.group(1);
  final tooltip = RegExp('tooltip: "([^"]*)"').firstMatch(reason)?.group(1);
  final rect = RegExp(r'Rect\.fromLTRB\([^)]*\)').firstMatch(reason)?.group(0);
  final words = [if (label != null) 'label "$label"', if (tooltip != null) 'tooltip "$tooltip"'].join(' ');
  return '$node $words $detail $rect';
}

/// Whether node [id] is read-only text (`SelectableText`).
bool _selectableText(WidgetTester tester, int id) {
  SemanticsNode? found;
  bool visit(SemanticsNode node) {
    if (node.id == id) found = node;
    if (found == null) node.visitChildren(visit);
    return found == null;
  }

  for (final view in tester.binding.renderViews) {
    final root = view.owner?.semanticsOwner?.rootSemanticsNode;
    if (root != null) visit(root);
  }
  final flags = found?.getSemanticsData().flagsCollection;
  return flags != null && flags.isTextField && flags.isReadOnly;
}

/// The first places (`file:line`) in the app's and the workspace packages'
/// code that built node [id], the node's own first.
List<String> _where(WidgetTester tester, int id) {
  Element? owner;
  void visit(Element element) {
    if (owner != null) return;
    if (element is RenderObjectElement && element.renderObject.debugSemantics?.id == id) {
      owner = element;
      return;
    }
    element.visitChildren(visit);
  }

  tester.binding.rootElement!.visitChildren(visit);
  final found = owner;
  if (found == null) return const [];
  final places = <String>[];
  void add(Widget widget) {
    final place = _creation(widget);
    if (place != null && !places.contains(place)) places.add(place);
  }

  add(found.widget);
  found.visitAncestorElements((element) {
    add(element.widget);
    return places.length < 3;
  });
  return places;
}

/// `file:line` of where [widget] was created, for code under `lib/` of the
/// app or a workspace package.
String? _creation(Widget widget) {
  final json = widget.toDiagnosticsNode().toJsonMap(
    InspectorSerializationDelegate(service: WidgetInspectorService.instance),
  );
  final location = json['creationLocation'];
  if (location is! Map) return null;
  final match = RegExp(r'/(apps/pure_live/lib/.*|packages/live_[a-z_]+/lib/.*)$').firstMatch('${location['file']}');
  if (match == null) return null;
  return '${match.group(1)}:${location['line']}';
}
