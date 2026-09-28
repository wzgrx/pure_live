import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:live_ui/src/icons/live_icon.dart';
import 'package:live_ui/src/icons/live_icons.dart';
import 'package:live_ui/src/illustration.dart';
import 'package:live_ui/src/metrics.dart';
import 'package:live_ui/src/room_card_view.dart';
import 'package:live_ui/src/ui_text.dart';

/// Centered progress for a page or panel that has nothing to show yet and
/// no list shape to stand in for (resolving a link, signing in). Lists use
/// [SkeletonGrid] and [SkeletonList] instead (principles §2.5, §7.8).
class LoadingView extends StatelessWidget {
  /// Creates the view.
  const new({this.label, super.key});

  /// Optional text under the indicator.
  final String? label;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        if (label != null) ...[
          const SizedBox(height: Space.s4),
          Text(label!, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ],
    ),
  );
}

/// The colour of skeleton blocks: the cover placeholder's (principles §3.4).
Color _block(BuildContext context) => Theme.of(context).colorScheme.surfaceContainerHighest;

/// One bar standing for a line of [style] text: as tall as the line, the
/// bar itself a little shorter than the glyphs, [fraction] of the width.
class _LineBar extends StatelessWidget {
  const new({required this.style, required this.fraction});

  final TextStyle style;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final size = scaler.scale(style.fontSize!);
    final line = size * (style.height ?? 1.4);
    return SizedBox(
      height: line,
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: FractionallySizedBox(
          widthFactor: fraction,
          child: DecoratedBox(
            decoration: BoxDecoration(color: _block(context), borderRadius: BorderRadius.circular(Radii.r1)),
            child: SizedBox(height: size * 0.75),
          ),
        ),
      ),
    );
  }
}

/// A static stand-in for a grid of room cards while the first page loads
/// (principles §2.5, §7.8): the same columns, gaps, padding and card height
/// as the grid that replaces it, cover blocks and text bars in the cover
/// placeholder colour. No spinner, no shimmer, nothing moves; the cards take
/// the blocks' places when they arrive, so the page does not jump.
///
/// Pass the geometry of the real grid (the app's `CardGridGeometry`), so
/// both come from one formula (principles §5.2).
class SkeletonGrid extends StatelessWidget {
  /// Creates the grid.
  const new({
    required this.columns,
    required this.gap,
    required this.padding,
    required this.cellHeight,
    this.density = CardDensity.standard,
    super.key,
  });

  /// Cards per row.
  final int columns;

  /// Gap between cards.
  final double gap;

  /// Padding around the grid.
  final EdgeInsets padding;

  /// Height of a card.
  final double cellHeight;

  /// Text lines under each cover: two for standard, one for compact.
  final CardDensity density;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      label: LiveUiText.current.loading,
      liveRegion: true,
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final height = constraints.hasBoundedHeight ? constraints.maxHeight : cellHeight * 3;
            final rows = math.max(1, ((height - padding.vertical + gap) / (cellHeight + gap)).ceil());
            return CustomScrollView(
              physics: const NeverScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: padding,
                  sliver: SliverGrid.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisSpacing: gap,
                      crossAxisSpacing: gap,
                      mainAxisExtent: cellHeight,
                    ),
                    itemCount: rows * columns,
                    itemBuilder: (context, index) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AspectRatio(
                          aspectRatio: 16 / 9,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: _block(context),
                              borderRadius: BorderRadius.circular(Radii.r2),
                            ),
                          ),
                        ),
                        // The card's text padding (RoomCardView).
                        Padding(
                          padding: const EdgeInsets.fromLTRB(Space.s1, Space.s2, Space.s1, Space.s1),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _LineBar(style: text.titleSmall!, fraction: 0.45),
                              if (density == CardDensity.standard) _LineBar(style: text.bodySmall!, fraction: 0.8),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// A static stand-in for a list of two-line rows (history, recordings,
/// offline follows) while it loads: a round [leading] block where the
/// avatar goes and two text bars, as many rows as fit (principles §2.5).
class SkeletonList extends StatelessWidget {
  /// Creates the list.
  const new({this.leading = true, this.padding = EdgeInsets.zero, super.key});

  /// Whether rows start with an avatar.
  final bool leading;

  /// Padding around the rows.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final scaler = MediaQuery.textScalerOf(context);
    double line(TextStyle style) => scaler.scale(style.fontSize!) * (style.height ?? 1.4);
    // A two-line ListTile: 8 dp above and below, never under 72 dp (M3).
    final rowHeight = math.max(72, line(text.bodyLarge!) + line(text.bodyMedium!) + 2 * Space.s2).toDouble();
    return Semantics(
      label: LiveUiText.current.loading,
      liveRegion: true,
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final height = constraints.hasBoundedHeight ? constraints.maxHeight : rowHeight * 4;
            final rows = math.max(1, ((height - padding.vertical) / rowHeight).ceil());
            return ListView.builder(
              physics: const NeverScrollableScrollPhysics(),
              padding: padding,
              itemCount: rows,
              itemExtent: rowHeight,
              itemBuilder: (context, index) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.s4),
                child: Row(
                  children: [
                    if (leading) ...[
                      DecoratedBox(
                        decoration: BoxDecoration(color: _block(context), shape: BoxShape.circle),
                        child: const SizedBox.square(dimension: 40),
                      ),
                      const SizedBox(width: Space.s4),
                    ],
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _LineBar(style: text.bodyLarge!, fraction: 0.4),
                          _LineBar(style: text.bodyMedium!, fraction: 0.7),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// A button of a [MessageView].
@immutable
final class MessageAction {
  /// Creates the action.
  const new(this.label, this.onPressed);

  /// Button text.
  final String label;

  /// What it does.
  final VoidCallback onPressed;
}

/// An empty or error state: what happened and the next step, in place
/// (principles rule 3, §3.3): an [illustration] (or a small [icon] where
/// there is no room for one), a title, a message and up to three buttons,
/// the first filled and the others outlined.
class MessageView extends StatelessWidget {
  /// Creates the view.
  const new({
    required this.title,
    this.message,
    this.illustration,
    this.icon = LiveIcons.inbox,
    this.actionLabel,
    this.onAction,
    this.secondaryLabel,
    this.onSecondary,
    this.actions = const [],
    super.key,
  }) : _error = false;

  /// An error state with a retry button ("重试" unless [actionLabel] says
  /// otherwise).
  const new error({
    required this.title,
    this.message,
    this.illustration,
    this.onAction,
    this.actionLabel,
    this.secondaryLabel,
    this.onSecondary,
    this.actions = const [],
    super.key,
  }) : icon = LiveIcons.error,
       _error = true;

  /// Headline.
  final String title;

  /// Explanation.
  final String? message;

  /// The picture above the title (principles §3.3); [icon] when null.
  final Illustration? illustration;

  /// A 48 dp icon for places too small for an [illustration] (sheets,
  /// panels).
  final LiveIcons icon;

  /// Primary action label.
  final String? actionLabel;

  /// Primary action.
  final VoidCallback? onAction;

  /// Secondary action label.
  final String? secondaryLabel;

  /// Secondary action.
  final VoidCallback? onSecondary;

  /// Further buttons after the primary and secondary ones; three buttons at
  /// most in all.
  final List<MessageAction> actions;

  final bool _error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final words = LiveUiText.current;
    final buttons = [
      if (onAction case final action?) MessageAction(actionLabel ?? (_error ? words.retry : words.ok), action),
      if (onSecondary case final action?) MessageAction(secondaryLabel ?? words.cancel, action),
      ...actions,
    ];
    assert(buttons.length <= 3, 'a message view has at most three buttons');
    final illustration = this.illustration;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Space.s6),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (illustration != null)
                IllustrationView(illustration)
              else
                LiveIcon(icon, size: Sizes.iconXxl, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(height: Space.s4),
              Text(
                title,
                style: illustration != null ? theme.textTheme.titleLarge : theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              if (message != null) ...[
                const SizedBox(height: Space.s2),
                Text(
                  message!,
                  style: theme.textTheme.bodyMedium!.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ],
              if (buttons.isNotEmpty) ...[
                const SizedBox(height: Space.s6),
                Wrap(
                  spacing: Space.s2,
                  runSpacing: Space.s2,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final (index, button) in buttons.indexed)
                      if (index == 0)
                        FilledButton(onPressed: button.onPressed, child: Text(button.label))
                      else
                        OutlinedButton(onPressed: button.onPressed, child: Text(button.label)),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
