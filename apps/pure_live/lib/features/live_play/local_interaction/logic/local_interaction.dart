import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/features/live_play/local_interaction/logic/local_catalog.dart';
import 'package:pure_live/i18n/i18n.dart';

/// Who sent a local message: what the chat line, the gift banner and the
/// history show (decided when it is sent, as 3.x did).
@immutable
final class LocalProfile {
  /// Creates a profile.
  const new({required this.title, required this.name, required this.accent, this.badge, this.badgeName, this.level});

  /// [message]'s profile, or null when it is not a local message.
  static LocalProfile? of(LiveMessage message) {
    final data = message.data;
    if (!message.isLocal || data is! Map) return null;
    return LocalProfile(
      title: '${data['title'] ?? ''}',
      name: '${data['name'] ?? message.userName}',
      accent: data['accent'] is int ? data['accent'] as int : LocalCatalog.genericPack.accent,
      badge: data['badge'] as String?,
      badgeName: data['badgeName'] as String?,
      level: data['level'] as int?,
    );
  }

  /// The title ("听众").
  final String title;

  /// The nickname.
  final String name;

  /// The platform's colour, ARGB.
  final int accent;

  /// The platform's badge (an emoji or two letters); null while
  /// "显示平台身份徽章" is off.
  final String? badge;

  /// The badge's name ("舰队等级"); null with [badge].
  final String? badgeName;

  /// The level; null while "显示本地体验等级" is off.
  final int? level;

  /// The badge chip's words: "📺 舰队等级 Lv.1", or empty when both are off.
  String get badgeLabel => [if (badge != null) '$badge $badgeName', if (level != null) 'Lv.$level'].join(' ');

  /// "听众 · Pure Live".
  String get displayName => '$title · $name';

  /// 3.x's sender label (`profileLabel`): "📺 舰队等级 · 听众"; the title alone
  /// without the badge.
  String get legacyLabel => [if (badge != null) '$badge $badgeName', title].join(' · ');

  /// The message data that carries the profile.
  Map<String, Object?> toData() => {
    'local': true,
    'title': title,
    'name': name,
    'accent': accent,
    'badge': badge,
    'badgeName': badgeName,
    'level': level,
  };
}

/// A local gift as its message carries it.
@immutable
final class LocalGiftData {
  /// Creates the data.
  const new({required this.emoji, required this.name, required this.color, required this.big, required this.effect});

  /// [message]'s gift, or null when it is not a local gift.
  static LocalGiftData? of(LiveMessage message) {
    final data = message.data;
    if (!message.isLocal || message.type != LiveMessageType.gift || data is! Map) return null;
    return LocalGiftData(
      emoji: '${data['emoji'] ?? ''}',
      name: '${data['giftName'] ?? ''}',
      color: message.color,
      big: data['big'] == true,
      effect: data['effect'] != 'none',
    );
  }

  /// The picture.
  final String emoji;

  /// The gift's name.
  final String name;

  /// The banner's colour.
  final LiveMessageColor color;

  /// The bigger banner.
  final bool big;

  /// Whether the banner shows ("显示本地礼物特效" when it was sent).
  final bool effect;
}

/// The local interaction (3.x `LocalInteractionController`) over the
/// settings: the profile, the coins and experience, the history and the
/// local danmaku style, stored under 3.x's `localInteraction.*` keys.
///
/// Writes show at once (a slider drag does not wait for the database);
/// listeners hear every change, also those made elsewhere (the settings
/// page, a backup restore).
final class LocalInteraction extends ChangeNotifier {
  /// Creates the interaction over the settings store.
  new(this._settings) {
    _subscription = _settings.changes.listen((setting) {
      if (setting.section == _section) notifyListeners();
    });
  }

  static const _section = 'localInteraction';

  final SettingsStore _settings;
  late final StreamSubscription<Setting<Object>> _subscription;
  final Map<String, Object> _pending = {};
  final Map<String, int> _writes = {};
  bool _disposed = false;

  T _get<T extends Object>(Setting<T> setting) {
    final pending = _pending[setting.key];
    return pending is T ? pending : _settings.get(setting);
  }

  /// Stores [values] (repaired by their settings' rules) and shows them at
  /// once.
  void _setAll(Map<Setting<Object>, Object> values) {
    final tickets = <String, int>{};
    for (final MapEntry(key: setting, :value) in values.entries) {
      _pending[setting.key] = setting.read(value);
      tickets[setting.key] = _writes[setting.key] = (_writes[setting.key] ?? 0) + 1;
    }
    if (!_disposed) notifyListeners();
    unawaited(
      _settings.setAll(values).whenComplete(() {
        for (final MapEntry(:key, value: ticket) in tickets.entries) {
          if (_writes[key] == ticket) _pending.remove(key);
        }
      }),
    );
  }

  void _set<T extends Object>(Setting<T> setting, T value) => _setAll({setting: value});

  // ---- profile ----

  /// The local interaction is on (U.2k K2: on by default, as 3.x).
  bool get enabled => _get(Settings.localInteractionEnabled);

  /// Turns the local interaction on or off.
  set enabled(bool value) => _set(Settings.localInteractionEnabled, value);

  /// The nickname.
  String get userName => _get(Settings.localInteractionUserName);

  /// The title's id.
  String get title => _get(Settings.localInteractionTitle);

  /// Chooses the title [id].
  set title(String id) => _set(Settings.localInteractionTitle, id);

  /// The title's words.
  String get titleLabel => i18n('local_title_$title');

  /// Local danmaku fly over the picture.
  bool get showAsDanmaku => _get(Settings.localInteractionShowAsDanmaku);

  set showAsDanmaku(bool value) => _set(Settings.localInteractionShowAsDanmaku, value);

  /// The platform badge before the name.
  bool get showPlatformBadge => _get(Settings.localInteractionShowPlatformBadge);

  set showPlatformBadge(bool value) => _set(Settings.localInteractionShowPlatformBadge, value);

  /// The level in the badge.
  bool get showLevelBadge => _get(Settings.localInteractionShowLevelBadge);

  set showLevelBadge(bool value) => _set(Settings.localInteractionShowLevelBadge, value);

  /// The banner of a gift.
  bool get enableGiftEffects => _get(Settings.localInteractionEnableGiftEffects);

  set enableGiftEffects(bool value) => _set(Settings.localInteractionEnableGiftEffects, value);

  /// The pack previewed in the settings.
  String get previewPlatform => _get(Settings.localInteractionPreviewPlatform);

  set previewPlatform(String id) => _set(Settings.localInteractionPreviewPlatform, id);

  /// Coins.
  int get coins => _get(Settings.localInteractionCoins);

  /// Experience.
  int get experience => _get(Settings.localInteractionExperience);

  /// The level (one per 500 experience).
  int get level => LocalCatalog.levelFor(experience);

  /// Gifts and coins added, newest first.
  List<String> get history => _get(Settings.localInteractionHistory);

  /// Saves [value] as the nickname (trimmed, at most 20 characters); an
  /// empty one is not saved (3.x).
  void updateName(String value) {
    final name = LocalCatalog.normalizeName(value);
    if (name.isNotEmpty && name != userName) _set(Settings.localInteractionUserName, name);
  }

  /// Adds [amount] coins and a history line (3.x `recharge`).
  void recharge(int amount) {
    if (amount <= 0) return;
    _setAll({
      Settings.localInteractionCoins: coins + amount,
      Settings.localInteractionHistory: _withHistory('${i18n('local_recharge_record')} +$amount'),
    });
  }

  /// Empties the history (coins and level stay).
  void clearHistory() => _set(Settings.localInteractionHistory, const <String>[]);

  List<String> _withHistory(String line) => [line, ...history].take(LocalCatalog.historyLimit).toList();

  /// "用户等级 Lv.1 · 1000 电池" for [pack] (U.2k c12: one way everywhere).
  String statusLine(LocalPlatformPack pack) => '${i18n(pack.levelKey)} Lv.$level · $coins ${i18n(pack.currencyKey)}';

  /// The sender of a message in a room of [platform] now.
  LocalProfile profileFor(String platform) {
    final pack = LocalCatalog.packFor(platform);
    return LocalProfile(
      title: titleLabel,
      name: userName,
      accent: pack.accent,
      badge: showPlatformBadge ? pack.badge : null,
      badgeName: showPlatformBadge ? i18n(LocalCatalog.badgeKeyFor(platform)) : null,
      level: showLevelBadge ? level : null,
    );
  }

  /// A local danmaku saying [text] in a room of [platform] (3.x
  /// `createChat`).
  LiveMessage createChat(String text, {required String platform}) {
    final profile = profileFor(platform);
    return LiveMessage(
      type: LiveMessageType.chat,
      userName: '${profile.legacyLabel} · ${profile.name}',
      message: text.trim(),
      color: LiveMessageColor.numberToColor(color),
      userLevel: profile.level?.toString() ?? '',
      data: profile.toData(),
      isLocal: true,
      style: currentStyle,
    );
  }

  /// Sends [gift] in a room of [platform]: takes its price, adds as much
  /// experience and a history line (3.x `sendGift`). Null when the
  /// interaction is off or the coins do not cover it.
  LiveMessage? sendGift(LocalGift gift, {required String platform}) {
    if (!enabled || coins < gift.price) return null;
    final profile = profileFor(platform);
    final giftName = i18n(gift.nameKey);
    final sent = i18n('local_sent_gift');
    _setAll({
      Settings.localInteractionCoins: coins - gift.price,
      Settings.localInteractionExperience: experience + gift.price,
      Settings.localInteractionHistory: _withHistory(
        '${gift.emoji} ${profile.legacyLabel} · ${profile.name} $sent $giftName ×1',
      ),
    });
    return LiveMessage(
      type: LiveMessageType.gift,
      userName: profile.name,
      // U.2k c10: what flies over the picture, without the badge.
      message: '${profile.name} $sent $giftName ×1',
      color: gift.color,
      userLevel: profile.level?.toString() ?? '',
      fansName: profile.title,
      data: {
        ...profile.toData(),
        'giftId': gift.id,
        'giftName': giftName,
        'emoji': gift.emoji,
        'price': gift.price,
        'count': 1,
        'platform': platform,
        'big': gift.big,
        'effect': enableGiftEffects ? (gift.big ? 'full' : 'ticker') : 'none',
      },
      isLocal: true,
      style: currentStyle,
    );
  }

  // ---- local danmaku style ----

  /// The template's id, or `custom`.
  String get preset => _get(Settings.localDanmakuPreset);

  /// The template's words, or "自定义".
  String get presetLabel =>
      LocalCatalog.presetById(preset) == null ? i18n('local_danmaku_custom') : i18n('local_danmaku_preset_$preset');

  /// Colour, ARGB.
  int get color => _get(Settings.localDanmakuColor);

  /// Font size.
  double get fontSize => _get(Settings.localDanmakuFontSize);

  /// Speed, pixels per second.
  double get speed => _get(Settings.localDanmakuSpeed);

  /// Font weight.
  int get fontWeight => _get(Settings.localDanmakuFontWeight);

  /// Outline.
  bool get showStroke => _get(Settings.localDanmakuShowStroke);

  /// Outline width.
  double get strokeWidth => _get(Settings.localDanmakuStrokeWidth);

  /// `scroll`, `top` or `bottom`.
  String get placement => _get(Settings.localDanmakuPlacement);

  /// `system`, `rounded`, `serif` or `mono`.
  String get fontFamily => _get(Settings.localDanmakuFontFamily);

  /// Italic.
  bool get italic => _get(Settings.localDanmakuItalic);

  /// Opacity.
  double get opacity => _get(Settings.localDanmakuOpacity);

  /// Letter spacing.
  double get letterSpacing => _get(Settings.localDanmakuLetterSpacing);

  /// Outline colour, ARGB.
  int get strokeColor => _get(Settings.localDanmakuStrokeColor);

  /// Shadow or glow.
  bool get showShadow => _get(Settings.localDanmakuShowShadow);

  /// Shadow colour, ARGB.
  int get shadowColor => _get(Settings.localDanmakuShadowColor);

  /// Shadow blur.
  double get shadowBlur => _get(Settings.localDanmakuShadowBlur);

  /// Shadow offset.
  double get shadowOffset => _get(Settings.localDanmakuShadowOffset);

  /// How long a fixed message stays, milliseconds.
  int get fixedDurationMs => _get(Settings.localDanmakuFixedDurationMs);

  /// Changes one part of the style; the template becomes "自定义" (3.x
  /// `markDanmakuStyleCustom`).
  void setStyle<T extends Object>(Setting<T> setting, T value) =>
      _setAll({setting: value, Settings.localDanmakuPreset: 'custom'});

  /// Applies [preset] whole.
  void applyPreset(LocalDanmakuPreset preset) => _setAll({
    Settings.localDanmakuPreset: preset.id,
    Settings.localDanmakuColor: preset.color,
    Settings.localDanmakuFontSize: preset.fontSize,
    Settings.localDanmakuSpeed: preset.speed,
    Settings.localDanmakuFontWeight: preset.fontWeight,
    Settings.localDanmakuShowStroke: preset.showStroke,
    Settings.localDanmakuStrokeWidth: preset.strokeWidth,
    Settings.localDanmakuPlacement: preset.placement,
    Settings.localDanmakuFontFamily: preset.fontFamily,
    Settings.localDanmakuItalic: preset.italic,
    Settings.localDanmakuOpacity: preset.opacity,
    Settings.localDanmakuLetterSpacing: preset.letterSpacing,
    Settings.localDanmakuStrokeColor: preset.strokeColor,
    Settings.localDanmakuShowShadow: preset.showShadow,
    Settings.localDanmakuShadowColor: preset.shadowColor,
    Settings.localDanmakuShadowBlur: preset.shadowBlur,
    Settings.localDanmakuShadowOffset: preset.shadowOffset,
    Settings.localDanmakuFixedDurationMs: preset.fixedDurationMs,
  });

  /// "恢复默认": the "清爽" template (3.x `resetDanmakuStyle`).
  void resetStyle() => applyPreset(LocalCatalog.defaultPreset);

  /// The style local danmaku fly with (3.x `buildDanmakuStyle`, its clamps).
  LiveMessageStyle get currentStyle => LiveMessageStyle(
    fontSize: fontSize.clamp(14.0, 32.0),
    baseSpeed: speed.clamp(60.0, 260.0),
    fontWeight: fontWeight.clamp(400, 900),
    showStroke: showStroke,
    strokeWidth: showStroke ? strokeWidth.clamp(0.5, 4.0) : 0,
    placement: LocalCatalog.placementOf(placement),
    fontFamily: LocalCatalog.fontFamilyOf(fontFamily),
    italic: italic,
    opacity: opacity.clamp(0.35, 1.0),
    letterSpacing: letterSpacing.clamp(-0.5, 3.0),
    strokeColor: strokeColor,
    showShadow: showShadow,
    shadowColor: shadowColor,
    shadowBlur: showShadow ? shadowBlur.clamp(0.0, 6.0) : 0,
    shadowOffset: showShadow ? shadowOffset.clamp(0.0, 4.0) : 0,
    fixedDurationMs: fixedDurationMs.clamp(2000, 10000),
  );

  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
