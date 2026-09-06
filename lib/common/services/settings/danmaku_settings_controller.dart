import 'package:pure_live/get/get.dart';
import 'package:pure_live/common/services/utils/hive_rx.dart';
import 'package:pure_live/common/models/app_refresh_rate_mode.dart';
import 'package:pure_live/common/services/display_mode_service.dart';

class DanmakuSettingsController extends GetxController {
  static const bool defaultEnablePipDanmaku = true;
  static const bool defaultPipDanmakuAutoScale = true;
  static const bool defaultPipDanmakuUseOriginalColor = true;
  static const int defaultPipDanmakuColor = 0xFFFFFFFF;
  static const double defaultPipDanmakuFontSize = 12.0;
  static const int defaultPipDanmakuFontWeight = 500;
  static const double defaultPipDanmakuSpeed = 90.0;
  static const double defaultPipDanmakuOpacity = 0.9;
  static const double defaultPipDanmakuArea = 0.5;
  static const int defaultPipDanmakuMaxVisibleCount = 6;
  static const double defaultPipDanmakuEmitInterval = 0.35;
  static const int defaultPipDanmakuFps = 30;
  static const bool defaultNoEmojiMode = false;
  static const bool defaultPipDanmakuNoEmojiMode = false;
  static const bool defaultFilterDouyuSuspectedAutomatedMessages = true;
  // Preserve the complete platform feed unless the user explicitly chooses
  // fuzzy suppression. Enabling this by default can hide a large share of
  // short messages in busy rooms even though the transport received them.
  static const bool defaultEnableDanmakuSimilarityFilter = false;

  static int normalizeFontWeight(Object? value, {int fallback = 500}) {
    final raw = value is num ? value.toInt() : fallback;
    return ((raw.clamp(100, 900) / 100).round() * 100).clamp(100, 900).toInt();
  }

  final RxBool hideDanmaku = hiveBool('hideDanmaku', false);
  final RxBool noEmojiMode = hiveBool('noEmojiMode', defaultNoEmojiMode);
  final RxDouble danmakuTopArea = hiveDouble('danmakuTopArea', 0.0);
  final RxDouble danmakuArea = hiveDouble('danmakuArea', 1.0);
  final RxDouble danmakuBottomArea = hiveDouble('danmakuBottomArea', 0.5);
  final RxDouble danmakuSpeed = hiveDouble('danmakuSpeed', 120.0);
  final RxDouble danmakuFontSize = hiveDouble('danmakuFontSize', 16.0);
  final RxInt danmakuFontWeight = hiveInt('danmakuFontWeight', 500);
  final RxDouble danmakuFontBorder = hiveDouble('danmakuFontBorder', 1.5);
  final RxDouble danmakuOpacity = hiveDouble('danmakuOpacity', 1.0);
  final RxBool enableDanmakuDisplay = hiveBool('enableDanmakuDisplay', true);
  final RxBool enableDanmakuStroke = hiveBool('enableDanmakuStroke', true);
  final RxInt danmakuFps = hiveInt('danmakuFps', 60);
  final RxBool danmakuAutoFps = hiveBool('danmakuAutoFps', true);
  final RxBool enableDanmakuTapInteraction = hiveBool('enableDanmakuTapInteraction', true);
  final RxBool enableDanmakuLongPressInteraction = hiveBool('enableDanmakuLongPressInteraction', true);
  final RxBool collapseRepeatedDanmaku = hiveBool('collapseRepeatedDanmaku', false);
  final RxInt repeatedDanmakuWindowSeconds = hiveInt('repeatedDanmakuWindowSeconds', 5);
  final RxInt danmakuInteractionMigration = hiveInt('danmakuInteractionMigration', 0);
  final RxString savedDanmakuTemplate = hiveString('savedDanmakuTemplate', '');
  final RxString danmakuFontFamilyName = hiveString('danmakuFontFamilyName', 'Default');
  final RxBool enablePipDanmaku = hiveBool('enablePipDanmaku', defaultEnablePipDanmaku);
  final RxBool pipDanmakuAutoScale = hiveBool('pipDanmakuAutoScale', defaultPipDanmakuAutoScale);
  // Keep the upstream storage key for existing users while exposing a
  // consistently-spelled Dart API and backup key.
  final RxBool pipDanmakuNoEmojiMode = hiveBool('pipDanmaNoEmojiMode', defaultPipDanmakuNoEmojiMode);
  final RxBool pipDanmakuUseOriginalColor = hiveBool('pipDanmakuUseOriginalColor', defaultPipDanmakuUseOriginalColor);
  final RxInt pipDanmakuColor = hiveInt('pipDanmakuColor', defaultPipDanmakuColor);
  final RxDouble pipDanmakuFontSize = hiveDouble('pipDanmakuFontSize', defaultPipDanmakuFontSize);
  final RxInt pipDanmakuFontWeight = hiveInt('pipDanmakuFontWeight', 500);
  final RxDouble pipDanmakuSpeed = hiveDouble('pipDanmakuSpeed', defaultPipDanmakuSpeed);
  final RxDouble pipDanmakuOpacity = hiveDouble('pipDanmakuOpacity', defaultPipDanmakuOpacity);
  final RxDouble pipDanmakuArea = hiveDouble('pipDanmakuArea', defaultPipDanmakuArea);
  final RxInt pipDanmakuMaxVisibleCount = hiveInt('pipDanmakuMaxVisibleCount', defaultPipDanmakuMaxVisibleCount);
  final RxDouble pipDanmakuEmitInterval = hiveDouble('pipDanmakuEmitInterval', defaultPipDanmakuEmitInterval);
  final RxInt pipDanmakuFps = hiveInt('pipDanmakuFps', defaultPipDanmakuFps);
  final RxBool pipDanmakuAutoFps = hiveBool('pipDanmakuAutoFps', true);

  // Douyu sometimes emits room-local chat packets without either of the
  // decoration/fan markers used by its web client. Keep the conservative
  // behavior by default, while allowing users who prefer the complete raw
  // room feed to opt in explicitly.
  final RxBool filterDouyuSuspectedAutomatedMessages = hiveBool(
    'filterDouyuSuspectedAutomatedMessages',
    defaultFilterDouyuSuspectedAutomatedMessages,
  );

  //   Enable danmaku Similarity Filter
  final RxBool enableDanmakuSimilarityFilter = hiveBool(
    'enableDanmakuSimilarityFilter',
    defaultEnableDanmakuSimilarityFilter,
  );
  final RxInt danmakuSimilarityThreshold = hiveInt('danmakuSimilarityThreshold', 85);
  final RxInt danmakuSimilarityCacheDuration = hiveInt('danmakuSimilarityCacheDuration', 3);
  final RxInt danmakuSimilarityMaxCacheSize = hiveInt('danmakuSimilarityMaxCacheSize', 100);
  @override
  void onInit() {
    super.onInit();
    danmakuFontWeight.v = normalizeFontWeight(danmakuFontWeight.v);
    pipDanmakuFontWeight.v = normalizeFontWeight(pipDanmakuFontWeight.v);
    danmakuSimilarityThreshold.v = danmakuSimilarityThreshold.v.clamp(50, 100).toInt();
    danmakuSimilarityCacheDuration.v = danmakuSimilarityCacheDuration.v.clamp(1, 60).toInt();
    danmakuSimilarityMaxCacheSize.v = danmakuSimilarityMaxCacheSize.v.clamp(20, 1000).toInt();
    if (danmakuInteractionMigration.v < 1) {
      enableDanmakuTapInteraction.v = true;
      enableDanmakuLongPressInteraction.v = true;
      danmakuInteractionMigration.v = 1;
    }
  }

  int resolvedDanmakuFps({bool pip = false, AppRefreshRateMode refreshRateMode = AppRefreshRateMode.powerSaving}) {
    final auto = pip ? pipDanmakuAutoFps.v : danmakuAutoFps.v;
    final configured = pip ? pipDanmakuFps.v : danmakuFps.v;
    if (!auto) return configured.clamp(pip ? 15 : 30, 240).toInt();
    return resolveAdaptiveDanmakuFps(DisplayModeService.info.value, pip: pip, refreshRateMode: refreshRateMode);
  }

  /// Resolves both room and PiP renderers from the single interface policy.
  ///
  /// Power saving keeps the existing 60/30 caps, balanced gives both surfaces
  /// a stable 60 FPS budget while touch-driven UI can temporarily use the
  /// display maximum, and Highest follows the detected device maximum for all
  /// UI/danmaku surfaces. A local manual value remains an explicit override.
  static int resolveAdaptiveDanmakuFps(
    DisplayModeInfo? display, {
    bool pip = false,
    AppRefreshRateMode refreshRateMode = AppRefreshRateMode.powerSaving,
  }) {
    final current = display?.currentRefreshRate ?? 0;
    final maximum = display?.maxRefreshRate ?? 0;
    final detected = maximum > 0 ? maximum : (current > 0 ? current : 60);
    final deviceMaximum = detected.round().clamp(pip ? 15 : 30, 240).toInt();
    return switch (refreshRateMode) {
      AppRefreshRateMode.powerSaving => deviceMaximum.clamp(pip ? 15 : 30, pip ? 30 : 60).toInt(),
      AppRefreshRateMode.balanced => deviceMaximum.clamp(pip ? 15 : 30, 60).toInt(),
      AppRefreshRateMode.performance => deviceMaximum,
    };
  }

  void resetPipDanmaku() {
    enablePipDanmaku.v = defaultEnablePipDanmaku;
    pipDanmakuAutoScale.v = defaultPipDanmakuAutoScale;
    pipDanmakuNoEmojiMode.v = defaultPipDanmakuNoEmojiMode;
    pipDanmakuUseOriginalColor.v = defaultPipDanmakuUseOriginalColor;
    pipDanmakuColor.v = defaultPipDanmakuColor;
    pipDanmakuFontSize.v = defaultPipDanmakuFontSize;
    pipDanmakuFontWeight.v = defaultPipDanmakuFontWeight;
    pipDanmakuSpeed.v = defaultPipDanmakuSpeed;
    pipDanmakuOpacity.v = defaultPipDanmakuOpacity;
    pipDanmakuArea.v = defaultPipDanmakuArea;
    pipDanmakuMaxVisibleCount.v = defaultPipDanmakuMaxVisibleCount;
    pipDanmakuEmitInterval.v = defaultPipDanmakuEmitInterval;
    pipDanmakuFps.v = defaultPipDanmakuFps;
    pipDanmakuAutoFps.v = true;
  }

  Map<String, dynamic> toJson() {
    return {
      'hideDanmaku': hideDanmaku.v,
      'noEmojiMode': noEmojiMode.v,
      'danmakuTopArea': danmakuTopArea.v,
      'danmakuArea': danmakuArea.v,
      'danmakuBottomArea': danmakuBottomArea.v,
      'danmakuSpeed': danmakuSpeed.v,
      'danmakuFontSize': danmakuFontSize.v,
      'danmakuFontWeight': danmakuFontWeight.v,
      'danmakuFontBorder': danmakuFontBorder.v,
      'danmakuOpacity': danmakuOpacity.v,
      'enableDanmakuDisplay': enableDanmakuDisplay.v,
      'danmakuFontFamilyName': danmakuFontFamilyName.v,
      'enableDanmakuStroke': enableDanmakuStroke.v,
      'danmakuFps': danmakuFps.v,
      'danmakuAutoFps': danmakuAutoFps.v,
      'enableDanmakuTapInteraction': enableDanmakuTapInteraction.v,
      'enableDanmakuLongPressInteraction': enableDanmakuLongPressInteraction.v,
      'collapseRepeatedDanmaku': collapseRepeatedDanmaku.v,
      'repeatedDanmakuWindowSeconds': repeatedDanmakuWindowSeconds.v,
      'savedDanmakuTemplate': savedDanmakuTemplate.v,
      'enablePipDanmaku': enablePipDanmaku.v,
      'pipDanmakuAutoScale': pipDanmakuAutoScale.v,
      'pipDanmakuNoEmojiMode': pipDanmakuNoEmojiMode.v,
      'pipDanmakuUseOriginalColor': pipDanmakuUseOriginalColor.v,
      'pipDanmakuColor': pipDanmakuColor.v,
      'pipDanmakuFontSize': pipDanmakuFontSize.v,
      'pipDanmakuFontWeight': pipDanmakuFontWeight.v,
      'pipDanmakuSpeed': pipDanmakuSpeed.v,
      'pipDanmakuOpacity': pipDanmakuOpacity.v,
      'pipDanmakuArea': pipDanmakuArea.v,
      'pipDanmakuMaxVisibleCount': pipDanmakuMaxVisibleCount.v,
      'pipDanmakuEmitInterval': pipDanmakuEmitInterval.v,
      'pipDanmakuFps': pipDanmakuFps.v,
      'pipDanmakuAutoFps': pipDanmakuAutoFps.v,
      'filterDouyuSuspectedAutomatedMessages': filterDouyuSuspectedAutomatedMessages.v,
      'enableDanmakuSimilarityFilter': enableDanmakuSimilarityFilter.v,
      'danmakuSimilarityThreshold': danmakuSimilarityThreshold.v,
      'danmakuSimilarityCacheDuration': danmakuSimilarityCacheDuration.v,
      'danmakuSimilarityMaxCacheSize': danmakuSimilarityMaxCacheSize.v,
    };
  }

  /// Parse the complete section without notifying observers or persisting values.
  static Map<String, dynamic> parseConfig(Map<String, dynamic> json) {
    T typed<T>(dynamic value) => value as T;
    return {
      'hideDanmaku': typed<bool>(json['hideDanmaku'] ?? false),
      'noEmojiMode': typed<bool>(json['noEmojiMode'] ?? defaultNoEmojiMode),
      'danmakuTopArea': typed<double>(json['danmakuTopArea']?.toDouble() ?? 0.0),
      'danmakuArea': typed<double>(json['danmakuArea']?.toDouble() ?? 1.0),
      'danmakuBottomArea': typed<double>(json['danmakuBottomArea']?.toDouble() ?? 0.5),
      'danmakuSpeed': typed<double>((json['danmakuSpeed'] ?? 120.0).toDouble().clamp(20.0, 400.0).toDouble()),
      'danmakuFontSize': typed<double>(json['danmakuFontSize']?.toDouble() ?? 16.0),
      'danmakuFontWeight': typed<int>(normalizeFontWeight(json['danmakuFontWeight'])),
      'danmakuFontBorder': typed<double>((json['danmakuFontBorder']?.toDouble() ?? 1.5).clamp(0.0, 4.0).toDouble()),
      'danmakuOpacity': typed<double>(json['danmakuOpacity']?.toDouble() ?? 1.0),
      'enableDanmakuDisplay': typed<bool>(json['enableDanmakuDisplay'] ?? true),
      'danmakuFontFamilyName': typed<String>(json['danmakuFontFamilyName'] ?? 'Default'),
      'enableDanmakuStroke': typed<bool>(json['enableDanmakuStroke'] ?? true),
      'danmakuFps': typed<int>(json['danmakuFps']?.toInt() ?? 60),
      'danmakuAutoFps': typed<bool>(json['danmakuAutoFps'] ?? true),
      'enableDanmakuTapInteraction': typed<bool>(json['enableDanmakuTapInteraction'] ?? true),
      'enableDanmakuLongPressInteraction': typed<bool>(json['enableDanmakuLongPressInteraction'] ?? true),
      'collapseRepeatedDanmaku': typed<bool>(json['collapseRepeatedDanmaku'] ?? false),
      'repeatedDanmakuWindowSeconds': typed<int>(
        (json['repeatedDanmakuWindowSeconds'] ?? 5).toInt().clamp(1, 30).toInt(),
      ),
      'savedDanmakuTemplate': typed<String>(json['savedDanmakuTemplate']?.toString() ?? ''),
      'enablePipDanmaku': typed<bool>(json['enablePipDanmaku'] ?? defaultEnablePipDanmaku),
      'pipDanmakuAutoScale': typed<bool>(json['pipDanmakuAutoScale'] ?? defaultPipDanmakuAutoScale),
      'pipDanmakuNoEmojiMode': typed<bool>(
        json['pipDanmakuNoEmojiMode'] ?? json['pipDanmaNoEmojiMode'] ?? defaultPipDanmakuNoEmojiMode,
      ),
      'pipDanmakuUseOriginalColor': typed<bool>(
        json['pipDanmakuUseOriginalColor'] ?? defaultPipDanmakuUseOriginalColor,
      ),
      'pipDanmakuColor': typed<int>(json['pipDanmakuColor']?.toInt() ?? defaultPipDanmakuColor),
      'pipDanmakuFontSize': typed<double>(
        (json['pipDanmakuFontSize'] ?? defaultPipDanmakuFontSize).toDouble().clamp(8.0, 24.0).toDouble(),
      ),
      'pipDanmakuFontWeight': typed<int>(normalizeFontWeight(json['pipDanmakuFontWeight'])),
      'pipDanmakuSpeed': typed<double>(
        (json['pipDanmakuSpeed'] ?? defaultPipDanmakuSpeed).toDouble().clamp(20.0, 400.0).toDouble(),
      ),
      'pipDanmakuOpacity': typed<double>(
        (json['pipDanmakuOpacity'] ?? defaultPipDanmakuOpacity).toDouble().clamp(0.1, 1.0).toDouble(),
      ),
      'pipDanmakuArea': typed<double>(
        (json['pipDanmakuArea'] ?? defaultPipDanmakuArea).toDouble().clamp(0.1, 1.0).toDouble(),
      ),
      'pipDanmakuMaxVisibleCount': typed<int>(
        (json['pipDanmakuMaxVisibleCount'] ?? defaultPipDanmakuMaxVisibleCount).toInt().clamp(1, 20).toInt(),
      ),
      'pipDanmakuEmitInterval': typed<double>(
        (json['pipDanmakuEmitInterval'] ?? defaultPipDanmakuEmitInterval).toDouble().clamp(0.05, 2.0).toDouble(),
      ),
      'pipDanmakuFps': typed<int>((json['pipDanmakuFps'] ?? defaultPipDanmakuFps).toInt().clamp(15, 240).toInt()),
      'pipDanmakuAutoFps': typed<bool>(json['pipDanmakuAutoFps'] ?? true),
      'filterDouyuSuspectedAutomatedMessages': typed<bool>(
        json['filterDouyuSuspectedAutomatedMessages'] ?? defaultFilterDouyuSuspectedAutomatedMessages,
      ),
      'enableDanmakuSimilarityFilter': typed<bool>(
        json['enableDanmakuSimilarityFilter'] ?? defaultEnableDanmakuSimilarityFilter,
      ),
      'danmakuSimilarityThreshold': typed<int>(
        (json['danmakuSimilarityThreshold'] ?? 85).toInt().clamp(50, 100).toInt(),
      ),
      'danmakuSimilarityCacheDuration': typed<int>(
        (json['danmakuSimilarityCacheDuration'] ?? 3).toInt().clamp(1, 60).toInt(),
      ),
      'danmakuSimilarityMaxCacheSize': typed<int>(
        (json['danmakuSimilarityMaxCacheSize'] ?? 100).toInt().clamp(20, 1000).toInt(),
      ),
    };
  }

  void fromJson(Map<String, dynamic> json) {
    final parsed = parseConfig(json);
    hideDanmaku.v = parsed['hideDanmaku'];
    noEmojiMode.v = parsed['noEmojiMode'];
    danmakuTopArea.v = parsed['danmakuTopArea'];
    danmakuArea.v = parsed['danmakuArea'];
    danmakuBottomArea.v = parsed['danmakuBottomArea'];
    danmakuSpeed.v = parsed['danmakuSpeed'];
    danmakuFontSize.v = parsed['danmakuFontSize'];
    danmakuFontWeight.v = parsed['danmakuFontWeight'];
    danmakuFontBorder.v = parsed['danmakuFontBorder'];
    danmakuOpacity.v = parsed['danmakuOpacity'];
    enableDanmakuDisplay.v = parsed['enableDanmakuDisplay'];
    danmakuFontFamilyName.v = parsed['danmakuFontFamilyName'];
    enableDanmakuStroke.v = parsed['enableDanmakuStroke'];
    danmakuFps.v = parsed['danmakuFps'];
    danmakuAutoFps.v = parsed['danmakuAutoFps'];
    enableDanmakuTapInteraction.v = parsed['enableDanmakuTapInteraction'];
    enableDanmakuLongPressInteraction.v = parsed['enableDanmakuLongPressInteraction'];
    collapseRepeatedDanmaku.v = parsed['collapseRepeatedDanmaku'];
    repeatedDanmakuWindowSeconds.v = parsed['repeatedDanmakuWindowSeconds'];
    savedDanmakuTemplate.v = parsed['savedDanmakuTemplate'];
    enablePipDanmaku.v = parsed['enablePipDanmaku'];
    pipDanmakuAutoScale.v = parsed['pipDanmakuAutoScale'];
    pipDanmakuNoEmojiMode.v = parsed['pipDanmakuNoEmojiMode'];
    pipDanmakuUseOriginalColor.v = parsed['pipDanmakuUseOriginalColor'];
    pipDanmakuColor.v = parsed['pipDanmakuColor'];
    pipDanmakuFontSize.v = parsed['pipDanmakuFontSize'];
    pipDanmakuFontWeight.v = parsed['pipDanmakuFontWeight'];
    pipDanmakuSpeed.v = parsed['pipDanmakuSpeed'];
    pipDanmakuOpacity.v = parsed['pipDanmakuOpacity'];
    pipDanmakuArea.v = parsed['pipDanmakuArea'];
    pipDanmakuMaxVisibleCount.v = parsed['pipDanmakuMaxVisibleCount'];
    pipDanmakuEmitInterval.v = parsed['pipDanmakuEmitInterval'];
    pipDanmakuFps.v = parsed['pipDanmakuFps'];
    pipDanmakuAutoFps.v = parsed['pipDanmakuAutoFps'];
    filterDouyuSuspectedAutomatedMessages.v = parsed['filterDouyuSuspectedAutomatedMessages'];
    enableDanmakuSimilarityFilter.v = parsed['enableDanmakuSimilarityFilter'];
    danmakuSimilarityThreshold.v = parsed['danmakuSimilarityThreshold'];
    danmakuSimilarityCacheDuration.v = parsed['danmakuSimilarityCacheDuration'];
    danmakuSimilarityMaxCacheSize.v = parsed['danmakuSimilarityMaxCacheSize'];
  }

  static Map<String, dynamic> extractConfig(Map<String, dynamic>? rootConfig) {
    final danmaku = rootConfig?['danmaku'] as Map<String, dynamic>? ?? {};
    return {
      'hideDanmaku': danmaku['hideDanmaku'] ?? false,
      'noEmojiMode': danmaku['noEmojiMode'] ?? defaultNoEmojiMode,
      'danmakuTopArea': (danmaku['danmakuTopArea'] ?? 0.0).toDouble(),
      'danmakuArea': (danmaku['danmakuArea'] ?? 1.0).toDouble(),
      'danmakuBottomArea': (danmaku['danmakuBottomArea'] ?? 0.5).toDouble(),
      'danmakuSpeed': (danmaku['danmakuSpeed'] ?? 120.0).toDouble().clamp(20.0, 400.0).toDouble(),
      'danmakuFontSize': (danmaku['danmakuFontSize'] ?? 16.0).toDouble(),
      'danmakuFontWeight': normalizeFontWeight(danmaku['danmakuFontWeight']),
      'danmakuFontBorder': (danmaku['danmakuFontBorder'] ?? 1.5).toDouble().clamp(0.0, 4.0).toDouble(),
      'danmakuOpacity': (danmaku['danmakuOpacity'] ?? 1.0).toDouble(),
      'enableDanmakuDisplay': danmaku['enableDanmakuDisplay'] ?? true,
      'danmakuFontFamilyName': danmaku['danmakuFontFamilyName'] ?? 'Default',
      'enableDanmakuStroke': danmaku['enableDanmakuStroke'] ?? true,
      'danmakuFps': (danmaku['danmakuFps'] ?? 60).toInt(),
      'danmakuAutoFps': danmaku['danmakuAutoFps'] ?? true,
      'enableDanmakuTapInteraction': danmaku['enableDanmakuTapInteraction'] ?? true,
      'enableDanmakuLongPressInteraction': danmaku['enableDanmakuLongPressInteraction'] ?? true,
      'collapseRepeatedDanmaku': danmaku['collapseRepeatedDanmaku'] ?? false,
      'repeatedDanmakuWindowSeconds': (danmaku['repeatedDanmakuWindowSeconds'] ?? 5).toInt().clamp(1, 30).toInt(),
      'savedDanmakuTemplate': danmaku['savedDanmakuTemplate']?.toString() ?? '',
      'enablePipDanmaku': danmaku['enablePipDanmaku'] ?? defaultEnablePipDanmaku,
      'pipDanmakuAutoScale': danmaku['pipDanmakuAutoScale'] ?? defaultPipDanmakuAutoScale,
      'pipDanmakuNoEmojiMode':
          danmaku['pipDanmakuNoEmojiMode'] ?? danmaku['pipDanmaNoEmojiMode'] ?? defaultPipDanmakuNoEmojiMode,
      'pipDanmakuUseOriginalColor': danmaku['pipDanmakuUseOriginalColor'] ?? defaultPipDanmakuUseOriginalColor,
      'pipDanmakuColor': (danmaku['pipDanmakuColor'] ?? defaultPipDanmakuColor).toInt(),
      'pipDanmakuFontSize': (danmaku['pipDanmakuFontSize'] ?? defaultPipDanmakuFontSize)
          .toDouble()
          .clamp(8.0, 24.0)
          .toDouble(),
      'pipDanmakuFontWeight': normalizeFontWeight(
        danmaku['pipDanmakuFontWeight'],
        fallback: defaultPipDanmakuFontWeight,
      ),
      'pipDanmakuSpeed': (danmaku['pipDanmakuSpeed'] ?? defaultPipDanmakuSpeed)
          .toDouble()
          .clamp(20.0, 400.0)
          .toDouble(),
      'pipDanmakuOpacity': (danmaku['pipDanmakuOpacity'] ?? defaultPipDanmakuOpacity)
          .toDouble()
          .clamp(0.1, 1.0)
          .toDouble(),
      'pipDanmakuArea': (danmaku['pipDanmakuArea'] ?? defaultPipDanmakuArea).toDouble().clamp(0.1, 1.0).toDouble(),
      'pipDanmakuMaxVisibleCount': (danmaku['pipDanmakuMaxVisibleCount'] ?? defaultPipDanmakuMaxVisibleCount)
          .toInt()
          .clamp(1, 20)
          .toInt(),
      'pipDanmakuEmitInterval': (danmaku['pipDanmakuEmitInterval'] ?? defaultPipDanmakuEmitInterval)
          .toDouble()
          .clamp(0.05, 2.0)
          .toDouble(),
      'pipDanmakuFps': (danmaku['pipDanmakuFps'] ?? defaultPipDanmakuFps).toInt().clamp(15, 240).toInt(),
      'pipDanmakuAutoFps': danmaku['pipDanmakuAutoFps'] ?? true,
      'filterDouyuSuspectedAutomatedMessages':
          danmaku['filterDouyuSuspectedAutomatedMessages'] ?? defaultFilterDouyuSuspectedAutomatedMessages,
      'enableDanmakuSimilarityFilter': danmaku['enableDanmakuSimilarityFilter'] ?? defaultEnableDanmakuSimilarityFilter,
      'danmakuSimilarityThreshold': (danmaku['danmakuSimilarityThreshold'] ?? 85).toInt().clamp(50, 100).toInt(),
      'danmakuSimilarityCacheDuration': (danmaku['danmakuSimilarityCacheDuration'] ?? 3).toInt().clamp(1, 60).toInt(),
      'danmakuSimilarityMaxCacheSize': (danmaku['danmakuSimilarityMaxCacheSize'] ?? 100)
          .toInt()
          .clamp(20, 1000)
          .toInt(),
    };
  }

  static Map<String, dynamic> mergeConfig(Map<String, dynamic> rootConfig, Map<String, dynamic> updateFields) {
    final danmaku = Map<String, dynamic>.from(rootConfig['danmaku'] ?? {});
    updateFields.forEach((k, v) => danmaku[k] = v);
    rootConfig['danmaku'] = danmaku;
    return rootConfig;
  }
}
