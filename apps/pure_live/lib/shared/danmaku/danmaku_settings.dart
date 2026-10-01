import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/shared/danmaku/danmaku_overlay.dart';

// The danmaku look, shared by the live room and the multi-view page (M12.2);
// the settings themselves are in danmaku_settings_content.dart (U.2f, U.8).

/// The danmaku look from the settings.
DanmakuLook danmakuLookOf(WidgetRef ref) => DanmakuLook(
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
);
