import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/shared/danmaku/danmaku_overlay.dart';

// The danmaku look, shared by the live room and the multi-view page (M12.2);
// the settings themselves are in danmaku_settings_content.dart (U.2f, U.8).

/// The danmaku look from the settings.
DanmakuLook danmakuLookOf(WidgetRef ref) {
  final font = watchSetting(ref, Settings.danmakuFontFamilyName);
  return DanmakuLook(
    fontSize: watchSetting(ref, Settings.danmakuFontSize),
    fontWeight: watchSetting(ref, Settings.danmakuFontWeight),
    speed: watchSetting(ref, Settings.danmakuSpeed),
    opacity: watchSetting(ref, Settings.danmakuOpacity),
    area: watchSetting(ref, Settings.danmakuArea),
    // Pixels kept free above and below (3.x `danmakuTopArea`/`BottomArea`).
    topMargin: watchSetting(ref, Settings.danmakuTopArea),
    bottomMargin: watchSetting(ref, Settings.danmakuBottomArea),
    stroke: watchSetting(ref, Settings.enableDanmakuStroke),
    strokeWidth: watchSetting(ref, Settings.danmakuFontBorder),
    // F.2a: the danmaku font ("Default" is the system's) and text-only mode.
    fontFamily: font.isEmpty || font == Settings.danmakuFontFamilyName.defaultValue ? null : font,
    textOnly: watchSetting(ref, Settings.noEmojiMode),
  );
}

/// The choices of "暂停时的弹幕" ([Settings.danmakuPausedBehavior], B02 c3).
abstract final class DanmakuPausedBehavior {
  /// The platform's danmaku stand with the paused video (the default).
  static const String pause = 'pause';

  /// They fly on, and new ones come in, while the video is paused.
  static const String fly = 'continue';
}

/// Whether the platform's flying danmaku move with the video in [status]
/// ([DanmakuOverlay.running]) as "暂停时的弹幕" ([behavior]) says: while it
/// plays; while it is paused only with [DanmakuPausedBehavior.fly]; never
/// while it opens, buffers, failed or stopped. The main picture, the mini
/// windows (in-app and picture-in-picture) and the multi-view all ask this.
bool danmakuRunning(PlaybackStatus status, String behavior) => switch (status) {
  PlaybackStatus.playing => true,
  PlaybackStatus.paused => behavior == DanmakuPausedBehavior.fly,
  PlaybackStatus.idle ||
  PlaybackStatus.opening ||
  PlaybackStatus.buffering ||
  PlaybackStatus.completed ||
  PlaybackStatus.error ||
  PlaybackStatus.stopped => false,
};
