import 'package:flutter/material.dart';
import 'package:live_ui/src/theme/text_styles.dart';
import 'package:live_ui/src/widgets/scrolling.dart';
import 'package:live_ui/src/widgets/settings_tiles.dart';

// The frame of the settings-like pages outside the settings feature
// (recording settings, backup, WebDAV, device sync; docs/A-界面设计/A10-录制界面/A10.2-录制设置,
// U.11a–c): the same app bar and reading column as the settings pages.

/// The app bar of a settings-like page: the title at the platform's place
/// (3.x: the start on Android; [centerTitle] centres it), 20 px semi-bold, [subtitle] under it when given (the WebDAV server); a
/// compact height when the window is short (a phone held sideways, U.6a).
PreferredSizeWidget settingsPageAppBar(
  BuildContext context, {
  required String title,
  String? subtitle,
  List<Widget> actions = const [],
  PreferredSizeWidget? bottom,
  bool centerTitle = false,
}) {
  final short = MediaQuery.sizeOf(context).height < 480;
  final heading = Text(title, style: context.textStyles.t18.copyWith(fontSize: 20, fontWeight: FontWeight.w600));
  return AppBar(
    title: subtitle == null
        ? heading
        : Column(
            crossAxisAlignment: centerTitle ? CrossAxisAlignment.center : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              heading,
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.textStyles.t12.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
    centerTitle: centerTitle,
    toolbarHeight: short ? 48 : kToolbarHeight,
    scrolledUnderElevation: 0,
    bottom: bottom,
    actions: [...actions, if (actions.isNotEmpty) const SizedBox(width: 4)],
  );
}

/// The scrolling body of a settings-like page: [children] (groups) in one
/// column at most [readableContentMaxWidth] wide, centred (UI_PLAN §5.3).
class SettingsPageList extends StatelessWidget {
  /// Creates the body.
  const new({required this.children, this.controller, this.physics, super.key});

  /// The groups and notes.
  final List<Widget> children;

  /// The scroll position.
  final ScrollController? controller;

  /// The scroll physics (pull to refresh needs an always scrollable one).
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    controller: controller,
    physics: physics ?? const PureLiveScrollPhysics(),
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
    child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: readableContentMaxWidth),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      ),
    ),
  );
}
