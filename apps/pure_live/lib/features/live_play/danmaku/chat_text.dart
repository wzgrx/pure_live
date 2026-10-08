import 'package:flutter/material.dart';
import 'package:live_ui/live_ui.dart';

/// The two text roles of a chat line (docs/A-界面设计/A08-弹幕界面/A08.10-弹幕列表名字和内容分开
/// G1, G2): the sender's name and what was said. Every line that names a
/// sender uses them (compact lines, cards, local lines, gifts, the super
/// chat line, the long-press card), so a name looks the same on every
/// platform and in both list styles.
///
/// Both take the body size, so they follow the font size settings and the
/// system text scale together and share one baseline with the emoticons;
/// they differ in weight (600 and 400, UI.md §8.2) and colour.
abstract final class ChatText {
  /// What follows a name before the content ("用户名：内容"), in the name's
  /// style.
  static const String nameEnd = '：';

  /// What was said: the body size, regular, the main ink.
  static TextStyle? content(ThemeData theme) =>
      theme.textTheme.bodyLarge?.regular.copyWith(color: theme.colorScheme.onSurface);

  /// The sender's name: the content's size, semibold, in [colour] (a
  /// platform's colour already made readable) or else the secondary ink.
  static TextStyle? name(ThemeData theme, [Color? colour]) =>
      theme.textTheme.bodyLarge?.emphasis.copyWith(color: colour ?? theme.colorScheme.onSurfaceVariant);
}
