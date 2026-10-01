import 'package:flutter/material.dart';
import 'package:live_player/live_player.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/live_play/logic/mini_window.dart';
import 'package:pure_live/features/live_play/logic/room_orientation.dart';
import 'package:pure_live/i18n/i18n.dart';

/// "显示识别状态" on the picture (3.x `PortraitStreamDiagnosticsBadge`,
/// F.1d): the picture's size and ratio, its orientation, the room's
/// orientation choice and, on the second line, where the size came from
/// (the decoder, or before the first frame the platform's declaration,
/// F.1b). v4 keeps no confidence, sample count or time, so those are not
/// shown.
class PortraitDiagnosticsBadge extends StatelessWidget {
  /// Creates the badge for [session] and the room's [orientation] choice.
  const new({required this.session, required this.orientation, super.key});

  /// The room's player.
  final PlaybackSession session;

  /// The room's orientation choice.
  final RoomOrientationChoice orientation;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ListenableBuilder(
      listenable: orientation,
      builder: (context, _) => StreamBuilder<PlaybackState>(
        stream: session.states,
        initialData: session.state,
        builder: (context, snapshot) => DecoratedBox(
          key: const ValueKey('portrait-stream-diagnostics'),
          decoration: BoxDecoration(color: OnVideoColors.scrim, borderRadius: BorderRadius.circular(8)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            child: Text(
              portraitDiagnosticsText(snapshot.data ?? session.state, orientation.value),
              style: const TextStyle(color: OnVideoColors.foreground, fontSize: 11, decoration: TextDecoration.none),
            ),
          ),
        ),
      ),
    ),
  );
}

/// The badge's two lines for [state] and the room's [choice].
@visibleForTesting
String portraitDiagnosticsText(PlaybackState state, RoomOrientation choice) {
  final picture = expectedPictureSize(state);
  final ratio = state.expectedAspectRatio;
  final shape = switch (ratio) {
    null => 'portrait_orientation_unknown',
    final value when (value - 1).abs() < 0.05 => 'portrait_orientation_square',
    final value when value < 1 => 'portrait_orientation_portrait',
    _ => 'portrait_orientation_landscape',
  };
  final override = switch (choice) {
    RoomOrientation.automatic => 'portrait_override_auto',
    RoomOrientation.portrait => 'portrait_override_portrait',
    RoomOrientation.landscape => 'portrait_override_landscape',
  };
  final evidence = state.aspectRatio != null
      ? i18n('portrait_evidence_decoder')
      : state.declaredAspectRatio != null
      ? i18n('portrait_evidence_platform')
      : '--';
  return '${picture.width ?? '--'}×${picture.height ?? '--'}  ${ratio?.toStringAsFixed(3) ?? '--'}  '
      '${i18n(shape)}  ${i18n(override)}\n$evidence';
}
