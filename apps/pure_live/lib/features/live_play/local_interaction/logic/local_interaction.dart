import 'dart:async';
import 'dart:convert';

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

  /// Whether [message] is a local danmaku sent before the room was entered,
  /// shown again (D08.1 c6: "之前发的").
  static bool replayedIn(LiveMessage message) {
    final data = message.data;
    return message.isLocal && data is Map && data['replayed'] == true;
  }

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

/// Where a local message is sent (D08.1): the room's platform and id, and
/// its name then (the streamer, else the title).
typedef LocalPlace = ({String platform, String roomId, String roomName});

/// What [LocalInteraction.clearHistory] took, for
/// [LocalInteraction.restoreHistory] (A08.13: the clear can be undone):
/// 3.x's lines and the entries (D08.1).
typedef LocalHistoryCleared = ({List<String> lines, List<LocalEvent> events});

/// A part of the history (D08.1 c5: "全部 / 弹幕 / 礼物 / 币").
enum LocalHistoryFilter {
  /// Everything, the old lines and levels too.
  all('local_history_filter_all'),

  /// Local danmaku.
  chat('local_history_filter_chat'),

  /// Gifts.
  gift('local_history_filter_gift'),

  /// Coins added.
  coins('local_history_filter_coins');

  new(this.labelKey);

  /// The segment's words.
  final String labelKey;

  /// Whether [event] belongs here.
  bool accepts(LocalEvent event) => switch (this) {
    all => true,
    chat => event.kind == LocalEventKind.chat,
    gift => event.kind == LocalEventKind.gift,
    coins => event.kind == LocalEventKind.recharge,
  };
}

/// The local interaction (3.x `LocalInteractionController`) over the
/// settings: the profile, the coins and experience, the history and the
/// local danmaku style, stored under 3.x's `localInteraction.*` keys.
///
/// Writes show at once (a slider drag does not wait for the database);
/// listeners hear every change, also those made elsewhere (the settings
/// page, a backup restore).
final class LocalInteraction extends ChangeNotifier {
  /// Creates the interaction over the settings store; the history entries
  /// (D08.1) live in [events], or only in memory without it. [start] loads
  /// them.
  new(this._settings, {LocalEventStore? events, DateTime Function()? now})
    : _store = events,
      _now = now ?? DateTime.now {
    _subscription = _settings.changes.listen((setting) {
      if (setting.section == _section) notifyListeners();
    });
  }

  static const _section = 'localInteraction';

  final SettingsStore _settings;
  final LocalEventStore? _store;
  final DateTime Function() _now;
  late final StreamSubscription<Setting<Object>> _subscription;
  StreamSubscription<List<LocalEvent>>? _events;
  List<LocalEvent> _entries = const [];
  int _storing = 0;
  bool _stale = false;
  bool _started = false;
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

  /// Gifts and coins added, newest first: 3.x's sentences, still written
  /// (D-018: an install put back to 3.x reads them). The pages show
  /// [events].
  List<String> get history => _get(Settings.localInteractionHistory);

  /// The history (D08.1): local danmaku, gifts, coins and the lines from
  /// before, newest first, at most [LocalEventStore.limit].
  List<LocalEvent> get events => _entries;

  /// Saves [value] as the nickname (trimmed, at most 20 characters); an
  /// empty one is not saved (3.x).
  void updateName(String value) {
    final name = LocalCatalog.normalizeName(value);
    if (name.isNotEmpty && name != userName) _set(Settings.localInteractionUserName, name);
  }

  /// Entering a room puts the local danmaku sent there in the last day back
  /// at the top of its chat list (D08.1 c6).
  bool get replayOnEnter => _get(Settings.localInteractionReplayOnEnter);

  set replayOnEnter(bool value) => _set(Settings.localInteractionReplayOnEnter, value);

  /// Loads the history once: after [before] (taking over values a 3.x import
  /// parked), the old lines of `localInteraction.history` become entries the
  /// first time (D08.1 c3), then the stored entries are followed (a restore,
  /// another window).
  Future<void> start({Future<Object?> Function()? before}) async {
    if (_started) return;
    _started = true;
    try {
      await before?.call();
    } on Object {
      // Tried again on the next start.
    }
    final store = _store;
    if (store == null || _disposed) return;
    try {
      await store.adoptLegacyHistory(history, now: _now());
    } on Object {
      // The lines stay in the setting; tried again on the next start.
    }
    if (_disposed) return;
    _events = store.watch().listen(_stored, onError: (Object _) {});
  }

  void _stored(List<LocalEvent> entries) {
    if (_storing > 0) {
      // A write of this one is under way: the entries shown hold it already.
      _stale = true;
      return;
    }
    _entries = List.unmodifiable(entries);
    if (!_disposed) notifyListeners();
  }

  /// Shows [entries] at once and has [write] store them.
  void _keep(List<LocalEvent> entries, Future<void> Function(LocalEventStore store) write) {
    _entries = List.unmodifiable(entries.take(LocalEventStore.limit));
    if (!_disposed) notifyListeners();
    final store = _store;
    if (store == null) return;
    _storing++;
    unawaited(
      write(store).catchError((Object _) {}).whenComplete(() async {
        if (--_storing > 0 || !_stale || _disposed) return;
        _stale = false;
        try {
          _stored(await store.all());
        } on Object {
          // The next change brings them.
        }
      }),
    );
  }

  void _record(LocalEvent event) => _keep([event, ..._entries], (store) => store.add(event));

  /// The style local danmaku are sent with, as the stored settings
  /// (`localInteraction.danmaku*`), JSON.
  String get _styleJson => jsonEncode({
    for (final setting in Settings.localInteraction)
      if (setting.key.startsWith('localInteraction.danmaku')) setting.key: setting.encode(_get(setting)),
  });

  /// Adds [amount] coins and a history line (3.x `recharge`).
  void recharge(int amount) {
    if (amount <= 0) return;
    _setAll({
      Settings.localInteractionCoins: coins + amount,
      Settings.localInteractionHistory: _withHistory('${i18n('local_recharge_record')} +$amount'),
    });
    _record(LocalEvent(at: _now(), kind: LocalEventKind.recharge, coins: amount));
  }

  /// Records a local danmaku saying [text] sent in [place] (D08.1 c2; 3.x
  /// kept none).
  void recordChat(String text, LocalPlace place) {
    final words = text.trim();
    if (words.isEmpty) return;
    _record(
      LocalEvent(
        at: _now(),
        kind: LocalEventKind.chat,
        platform: place.platform,
        roomId: place.roomId,
        roomName: place.roomName,
        text: words,
        style: _styleJson,
      ),
    );
  }

  /// Empties the history (coins and level stay) and returns what it held,
  /// for [restoreHistory] (A08.13: the clear can be undone).
  LocalHistoryCleared clearHistory() {
    final cleared = (lines: history, events: _entries);
    _set(Settings.localInteractionHistory, const <String>[]);
    _keep(const [], (store) => store.clear());
    return cleared;
  }

  /// Puts [cleared] (what [clearHistory] returned) back under what was added
  /// since: the lines up to [LocalCatalog.historyLimit], the entries under
  /// their own ids.
  void restoreHistory(LocalHistoryCleared cleared) {
    if (cleared.lines.isNotEmpty) {
      _set(Settings.localInteractionHistory, [...history, ...cleared.lines].take(LocalCatalog.historyLimit).toList());
    }
    if (cleared.events.isEmpty) return;
    final merged = [..._entries, ...cleared.events]..sort((a, b) => b.at.compareTo(a.at));
    _keep(merged, (store) => store.addAll(cleared.events));
  }

  List<String> _withHistory(String line) => [line, ...history].take(LocalCatalog.historyLimit).toList();

  /// [event] in the interface language now (D08.1 c5): what a danmaku said,
  /// "🌶️ 送出 辣条 ×1", "增加本地体验币 +500", "升到 Lv.3", an old line as it
  /// was.
  String describe(LocalEvent event) {
    switch (event.kind) {
      case LocalEventKind.chat || LocalEventKind.legacy:
        return event.text;
      case LocalEventKind.gift:
        final gift = LocalCatalog.giftById(event.giftId);
        final name = gift == null ? event.giftId : i18n(gift.nameKey);
        final count = event.count < 1 ? 1 : event.count;
        return [if (gift != null) gift.emoji, i18n('local_sent_gift'), '$name ×$count'].join(' ');
      case LocalEventKind.recharge:
        return '${i18n('local_recharge_record')} +${event.coins}';
      case LocalEventKind.level:
        return i18n('local_history_level', args: {'level': '${event.count}'});
    }
  }

  /// The local danmaku [event] once more in a room of [platform], as the
  /// room shows one sent before it was entered (D08.1 c6): marked
  /// "之前发的" ([LocalProfile.replayedIn]), by the profile of now.
  LiveMessage replayed(LocalEvent event, {required String platform}) {
    final message = createChat(event.text, platform: platform);
    return LiveMessage(
      type: message.type,
      userName: message.userName,
      message: message.message,
      color: message.color,
      userLevel: message.userLevel,
      data: {...profileFor(platform).toData(), 'replayed': true, 'at': event.at.millisecondsSinceEpoch},
      isLocal: true,
      style: message.style,
    );
  }

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
  ///
  /// The entry (D08.1) names [place] when it was sent in a room.
  LiveMessage? sendGift(LocalGift gift, {required String platform, LocalPlace? place}) {
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
    _record(
      LocalEvent(
        at: _now(),
        kind: LocalEventKind.gift,
        platform: place?.platform ?? platform,
        roomId: place?.roomId ?? '',
        roomName: place?.roomName ?? '',
        giftId: gift.id,
        count: 1,
        coins: gift.price,
      ),
    );
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
    unawaited(_events?.cancel());
    super.dispose();
  }
}
