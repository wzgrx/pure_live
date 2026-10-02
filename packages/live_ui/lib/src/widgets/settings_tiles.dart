import 'package:flutter/material.dart';

// 3.x's settings builders (`AppLayoutFactory`: `buildGroupTitle`,
// `buildModernCard`, `buildSwitchTile`, `buildTile`, `buildSliderTile`,
// `SectionTitle`, `MenuListTile`) are gone: every page uses the one settings
// row ([SettingsGroup], [SettingsLinkRow], [SettingsSwitchRow] …,
// docs/A-界面设计/A02-组件/A02.1-通用组件 c16), and reading columns are at most 720 wide
// instead of 3.x's 960 (U.1c c18).

/// The widest a reading column gets on large screens (settings-like pages,
/// details; docs/specs/UI.md §5.3): one column, centred.
const double readableContentMaxWidth = 720;

/// [child] in a centred column at most [readableContentMaxWidth] wide (the
/// whole width on narrower screens).
class ReadableContent extends StatelessWidget {
  /// Wraps [child].
  const new({required this.child, super.key});

  /// The column.
  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: readableContentMaxWidth),
      child: child,
    ),
  );
}
