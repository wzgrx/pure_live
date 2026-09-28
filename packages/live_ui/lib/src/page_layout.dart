import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:live_ui/src/metrics.dart';
import 'package:live_ui/src/tv/tv_scope.dart';
import 'package:live_ui/src/window_class.dart';

/// The horizontal lines a page is built on (spec/design/principles.md
/// §2.4): the header's title, tabs and actions sit on the same margins as the
/// content under them.
abstract final class PageMargin {
  /// The page margin at [context]: the window class's margin (16, 24 or
  /// 32); on TV the few dp a focused card grows into, since the rail and the
  /// overscan safe area already hold the rest (§5.3).
  static double of(BuildContext context) =>
      TvScope.of(context).enabled ? Space.s2 : WindowLayout(MediaQuery.sizeOf(context)).margin;

  /// The start and end padding of list rows on a page with [margin]: rows
  /// start on the margin, and never closer to the edge than Material's own
  /// 16 and 24 (TV rows keep them: their focus fill needs the room).
  static EdgeInsetsDirectional tilePadding(double margin) =>
      EdgeInsetsDirectional.only(start: math.max(Space.s4, margin), end: math.max(Space.s6, margin));

  /// The list row padding in force at [context] (the ambient
  /// [ListTileTheme], else Material's default), for headings and chips that
  /// line up with the rows.
  static EdgeInsets rowInsets(BuildContext context) =>
      ListTileTheme.of(context).contentPadding?.resolve(Directionality.of(context)) ??
      const EdgeInsets.only(left: Space.s4, right: Space.s6);

  /// Where content starts in a page [width] wide with [margin]: the margin,
  /// or with [maxContentWidth] the start of the rows in a centered column
  /// that wide (see [PageBody]).
  static double contentStart(double width, double margin, {double? maxContentWidth}) {
    if (maxContentWidth == null) return margin;
    return (width - math.min(width, maxContentWidth)) / 2 + tilePadding(margin).start;
  }
}

/// A page's body on the page's margins (principles §2.4): list rows start on
/// the margin, and with [maxContentWidth] the content is a centered column
/// that wide, the readable width of text pages (§4.4).
class PageBody extends StatelessWidget {
  /// Creates the body.
  const new({required this.child, this.maxContentWidth, super.key});

  /// The content.
  final Widget child;

  /// Width of the centered content column; null fills the page.
  final double? maxContentWidth;

  @override
  Widget build(BuildContext context) {
    final rows = ListTileTheme.merge(contentPadding: PageMargin.tilePadding(PageMargin.of(context)), child: child);
    final max = maxContentWidth;
    if (max == null) return rows;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: max),
        child: rows,
      ),
    );
  }
}

/// The top app bar of a page (principles §2.4): the title starts where the
/// content starts, the glyph of the last action ends on the page margin, and
/// a back button sits on the margin with the title after it. With
/// [maxContentWidth] (pages whose content is a centered [PageBody]) the title
/// and actions line up with that column instead.
class PageAppBar extends StatelessWidget implements PreferredSizeWidget {
  /// Creates the bar.
  const new({
    this.title,
    this.actions,
    this.bottom,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.maxContentWidth,
    this.toolbarHeight,
    super.key,
  });

  /// The title.
  final Widget? title;

  /// Buttons at the end.
  final List<Widget>? actions;

  /// A tab bar under the toolbar ([PageTabBar] lines its labels up).
  final PreferredSizeWidget? bottom;

  /// A widget before the title in place of the back button.
  final Widget? leading;

  /// Whether a back button shows on pages that can go back.
  final bool automaticallyImplyLeading;

  /// Width of the page's centered content column, if it has one.
  final double? maxContentWidth;

  /// Height of the toolbar; [kToolbarHeight] by default.
  final double? toolbarHeight;

  @override
  Size get preferredSize => Size.fromHeight((toolbarHeight ?? kToolbarHeight) + (bottom?.preferredSize.height ?? 0));

  /// Size of the icons in an app bar: Material draws them at 24 dp even
  /// where other buttons are larger (TV).
  static double iconSize(ThemeData theme) =>
      theme.appBarTheme.actionsIconTheme?.size ?? theme.appBarTheme.iconTheme?.size ?? Sizes.iconMd;

  /// The width an icon button takes in an app bar: Material centres the
  /// icon in a button at least 40 dp wide, padded to 48 dp where touch
  /// targets are padded.
  static double buttonWidth(ThemeData theme) {
    final visual = math.max(40, iconSize(theme) + 16).toDouble();
    return theme.materialTapTargetSize == MaterialTapTargetSize.padded ? math.max(Sizes.targetTouch, visual) : visual;
  }

  /// The offset of an app bar button's glyph from the button's edge.
  static double glyphInset(ThemeData theme) => (buttonWidth(theme) - iconSize(theme)) / 2;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final theme = Theme.of(context);
      final margin = PageMargin.of(context);
      final width = constraints.maxWidth;
      final start = PageMargin.contentStart(width, margin, maxContentWidth: maxContentWidth);
      final end = maxContentWidth == null ? margin : start;
      final inset = glyphInset(theme);
      final icon = iconSize(theme);
      var leading = this.leading;
      if (leading == null && automaticallyImplyLeading) {
        final route = ModalRoute.of(context);
        if (route?.impliesAppBarDismissal ?? false) leading = const BackButton();
      }
      double? leadingWidth;
      var titleStart = start;
      if (leading != null) {
        // The back glyph on the margin, the title one glyph and 32 dp later;
        // on a centered column the glyph hangs before the column's start.
        titleStart = math.max(start, margin + icon + Space.s8);
        final glyph = titleStart - icon - Space.s8;
        final pad = math.max(0, glyph - inset).toDouble();
        leadingWidth = pad + buttonWidth(theme);
        leading = Padding(
          padding: EdgeInsetsDirectional.only(start: pad),
          child: Align(alignment: AlignmentDirectional.centerStart, child: leading),
        );
      }
      return AppBar(
        title: title,
        actions: actions,
        bottom: bottom,
        leading: leading,
        leadingWidth: leadingWidth,
        automaticallyImplyLeading: false,
        toolbarHeight: toolbarHeight,
        titleSpacing: titleStart - (leadingWidth ?? 0),
        actionsPadding: EdgeInsetsDirectional.only(end: math.max(0, end - inset)),
      );
    },
  );
}

/// A scrollable row of tabs whose first label starts on the page's content
/// line (principles §2.4), for [PageAppBar.bottom] or above a page's content.
class PageTabBar extends StatelessWidget implements PreferredSizeWidget {
  /// Creates the tab bar.
  const new({required this.tabs, this.controller, this.maxContentWidth, this.dividerHeight, this.onTap, super.key});

  /// The tabs.
  final List<Widget> tabs;

  /// The controller; the ambient [DefaultTabController] when null.
  final TabController? controller;

  /// Width of the page's centered content column, if it has one.
  final double? maxContentWidth;

  /// Height of the divider under the tabs; the theme's when null.
  final double? dividerHeight;

  /// Called with the tapped tab.
  final ValueChanged<int>? onTap;

  @override
  Size get preferredSize => TabBar(tabs: tabs).preferredSize;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final margin = PageMargin.of(context);
      final start = PageMargin.contentStart(constraints.maxWidth, margin, maxContentWidth: maxContentWidth);
      // Labels carry 16 dp on each side; a narrower line (TV) narrows them.
      final label = math.min(Space.s4, start);
      return TabBar(
        controller: controller,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        dividerHeight: dividerHeight,
        onTap: onTap,
        labelPadding: EdgeInsets.symmetric(horizontal: label),
        padding: EdgeInsetsDirectional.only(start: start - label, end: math.max(0, margin - label)),
        tabs: tabs,
      );
    },
  );
}
