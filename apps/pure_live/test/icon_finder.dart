import 'package:flutter_test/flutter_test.dart';
import 'package:live_ui/live_ui.dart';

export 'package:live_ui/live_ui.dart' show LiveIcons;

/// The [LiveIcon]s showing [icon]; with [filled], only those in that fill
/// state (principles §2.6: a toggle shows its state by fill alone).
Finder findIcon(LiveIcons icon, {bool? filled}) => find.byWidgetPredicate(
  (widget) => widget is LiveIcon && widget.icon == icon && (filled == null || (widget.filled ?? false) == filled),
  description: 'LiveIcon(${icon.name}${filled == null ? '' : ', filled: $filled'})',
);
