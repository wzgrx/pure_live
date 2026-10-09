import 'package:flutter/material.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/live_play/danmaku/gift_count_pulse.dart';
import 'package:pure_live/features/live_play/local_interaction/local_interaction_scope.dart';
import 'package:pure_live/i18n/i18n.dart';

/// A small local gift's line (D08.5 c3): "🌶 Pure Live 送出 辣条 ×N" flying
/// from beyond the right edge of the gift layer to beyond its left edge,
/// near its top, in [duration] (the tier's time in the banner queue): fast
/// in, slowly through the middle where it is read, fast out.
///
/// A combo's new count (the same `serial`, keep it under
/// `ValueKey(serial)`) jumps the "×N" and gives the rest of the way the
/// whole [duration] again, as the queue starts the banner's time again: the
/// line slows down while the gift is tapped on.
///
/// Only the line's layer moves (a [Flow] repainting with the clock, the
/// line in its own [RepaintBoundary]): nothing is built or laid out per
/// frame. Its text grows with the system's at most 1.3 times, as the
/// controls' over the picture (UI.md §8.2), so it stays a strip.
class LocalGiftFlyer extends StatefulWidget {
  /// Creates the line of [show].
  const new({required this.show, required this.duration, super.key});

  /// The gift.
  final LocalGiftShow show;

  /// How long the flight takes.
  final Duration duration;

  /// How far below the layer's top the line flies.
  static const double top = 8;

  @override
  State<LocalGiftFlyer> createState() => _LocalGiftFlyerState();
}

class _LocalGiftFlyerState extends State<LocalGiftFlyer> with SingleTickerProviderStateMixin {
  late final AnimationController _flight = AnimationController(vsync: this, duration: widget.duration)..forward();

  @override
  void didUpdateWidget(LocalGiftFlyer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.show.revision != oldWidget.show.revision && !_flight.isCompleted) {
      // A combo: the rest of the way in a whole duration again.
      _flight.animateTo(1, duration: widget.duration);
    }
  }

  @override
  void dispose() {
    _flight.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Flow(
    key: const ValueKey('local-gift-flyer-lane'),
    delegate: _Flight(_flight),
    children: [
      RepaintBoundary(
        child: MediaQuery.withClampedTextScaling(maxScaleFactor: 1.3, child: LocalGiftFlyerLine(show: widget.show)),
      ),
    ],
  );
}

/// Where the line is at [progress] (0..1) of its flight, as a part of the
/// way: fast in, a third of the speed through the middle, fast out.
double localGiftFlyerPath(double progress) {
  final from = progress - 0.5;
  return 0.35 * progress + 0.65 * (0.5 + 4 * from * from * from);
}

class _Flight extends FlowDelegate {
  new(this.flight) : super(repaint: flight);

  final Animation<double> flight;

  @override
  BoxConstraints getConstraintsForChild(int i, BoxConstraints constraints) =>
      BoxConstraints(maxHeight: constraints.maxHeight);

  @override
  void paintChildren(FlowPaintingContext context) {
    final width = context.getChildSize(0)?.width ?? 0;
    final x = context.size.width - (context.size.width + width) * localGiftFlyerPath(flight.value);
    context.paintChild(0, transform: Matrix4.translationValues(x, LocalGiftFlyer.top, 0));
  }

  @override
  bool shouldRepaint(_Flight oldDelegate) => oldDelegate.flight != flight;
}

/// The flying line itself: the gift, "Pure Live 送出 辣条" and its "×N" in a
/// slim pill of the gift's colour (the banner's look, on one line).
class LocalGiftFlyerLine extends StatelessWidget {
  /// Creates the line of [show].
  const new({required this.show, super.key});

  /// The gift.
  final LocalGiftShow show;

  @override
  Widget build(BuildContext context) {
    final message = show.message;
    final gift = LocalGiftData.of(message);
    final profile = LocalProfile.of(message);
    if (gift == null || profile == null) return const SizedBox.shrink();
    final color = Color.fromARGB(255, gift.color.r, gift.color.g, gift.color.b);
    final theme = Theme.of(context);
    final text = theme.textTheme.titleMedium?.copyWith(
      fontSize: 15,
      fontWeight: FontWeight.w700,
      height: 1.3,
      color: OnVideoColors.foreground,
      shadows: OnVideoColors.shadows,
    );
    return Container(
      key: const ValueKey('local-gift-flyer'),
      padding: const EdgeInsets.fromLTRB(8, 4, 14, 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [color.withValues(alpha: 0.9), OnVideoColors.bannerEnd]),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: OnVideoColors.bannerOutline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(localEmojiText(gift.emoji), style: localEmojiStyle(const TextStyle(fontSize: 20, height: 1.2))),
          const SizedBox(width: 6),
          Text(
            '${profile.name} ${i18n('local_sent_gift')} ${gift.name}',
            key: const ValueKey('local-gift-flyer-title'),
            maxLines: 1,
            softWrap: false,
            style: text,
          ),
          const SizedBox(width: 8),
          GiftCountPulse(
            count: gift.count,
            jump: GiftCountJump.banner,
            child: Text(
              '×${gift.count}',
              key: const ValueKey('local-gift-flyer-count'),
              style: theme.textTheme.titleLarge?.tabular.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                height: 1.2,
                color: OnVideoColors.foreground,
                shadows: OnVideoColors.shadows,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
