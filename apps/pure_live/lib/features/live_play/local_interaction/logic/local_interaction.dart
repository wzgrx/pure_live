import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/features/live_play/local_interaction/logic/local_catalog.dart';
import 'package:pure_live/features/live_play/local_interaction/logic/local_gift_tier.dart';
import 'package:pure_live/features/live_play/local_interaction/logic/local_growth.dart';
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
  const new({
    required this.emoji,
    required this.name,
    required this.color,
    required this.big,
    required this.effect,
    this.id = '',
    this.count = 1,
    this.price = 0,
  });

  /// [message]'s gift, or null when it is not a local gift.
  static LocalGiftData? of(LiveMessage message) {
    final data = message.data;
    if (!message.isLocal || message.type != LiveMessageType.gift || data is! Map) return null;
    final count = data['count'];
    final price = data['price'];
    return LocalGiftData(
      emoji: '${data['emoji'] ?? ''}',
      name: '${data['giftName'] ?? ''}',
      color: message.color,
      big: data['big'] == true,
      effect: data['effect'] != 'none',
      id: '${data['giftId'] ?? ''}',
      count: count is int && count > 0 ? count : 1,
      price: price is int ? price : 0,
    );
  }

  /// The gift's id ([LocalGift.id]).
  final String id;

  /// How many (D08.4: the count chosen, and a combo's total so far).
  final int count;

  /// The price of one.
  final int price;

  /// The picture.
  final String emoji;

  /// The gift's name.
  final String name;

  /// The banner's colour.
  final LiveMessageColor color;

  /// The bigger banner.
  final bool big;

  /// Whether the banner shows ("显示本地礼物特效" when it was sent; D08.5:
  /// and the level let this gift's tier show).
  final bool effect;

  /// The effect's tier, by the price of one (D08.5 c1).
  LocalGiftTier get tier => LocalGiftTier.of(price: price, big: big);
}

/// A run of one gift (D08.4 c1): the sends of the same gift in a room, each
/// within [LocalCatalog.giftComboWindow] of the last. The room session keeps
/// it and hands it to [LocalInteraction.sendGift] with each send of the
/// run; the run is one history entry, one chat line and one banner whose
/// count goes up.
final class LocalGiftCombo {
  /// Starts a run of [gift] (empty until its first send).
  new(this.gift);

  /// The gift.
  final LocalGift gift;

  /// How many so far (every send's count added).
  int get count => _count;
  int _count = 0;

  /// The coins the run took so far.
  int get coins => _coins;
  int _coins = 0;

  /// The run's history entry as last shown, and its id once the store gave
  /// one.
  LocalEvent? _entry;
  Future<int>? _stored;

  /// The run's 3.x history line (`localInteraction.history`).
  String? _line;
}

/// Where a local message is sent (D08.1): the room's platform and id, and
/// its name then (the streamer, else the title).
typedef LocalPlace = ({String platform, String roomId, String roomName});

/// What [LocalInteraction.clearHistory] took, for
/// [LocalInteraction.restoreHistory] (A08.13: the clear can be undone):
/// 3.x's lines and the entries (D08.1).
typedef LocalHistoryCleared = ({List<String> lines, List<LocalEvent> events});

/// Why a text cannot be saved as a phrase (D08.2).
enum LocalPhraseProblem {
  /// Nothing but spaces.
  empty('local_phrase_empty'),

  /// The same phrase is there already.
  exists('local_phrase_exists'),

  /// [Settings.localPhraseLimit] are there already.
  full('local_phrases_full');

  new(this.messageKey);

  /// What to tell the user.
  final String messageKey;
}

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

  /// The banner of a gift (3.x's switch; D08.5: off is the level
  /// [LocalGiftEffectLevel.off]).
  bool get enableGiftEffects => _get(Settings.localInteractionEnableGiftEffects);

  set enableGiftEffects(bool value) => _set(Settings.localInteractionEnableGiftEffects, value);

  /// Which gifts show their effect (D08.5 c2). 3.x's switch decides first:
  /// off is [LocalGiftEffectLevel.off] whatever the new key says (a 3.x
  /// install over this one may have turned it off), on is the new key's
  /// [LocalGiftEffectLevel.all] or [LocalGiftEffectLevel.bigOnly] (its
  /// default, nothing stored, is all; an `off` stored there while 3.x
  /// turned the switch back on reads as all).
  LocalGiftEffectLevel get giftEffectLevel {
    if (!enableGiftEffects) return LocalGiftEffectLevel.off;
    final level = LocalGiftEffectLevel.parse(_get(Settings.localInteractionGiftEffectLevel));
    return level == LocalGiftEffectLevel.off ? LocalGiftEffectLevel.all : level;
  }

  /// Stores [level] and 3.x's switch with it (off is off, the others on),
  /// so 3.x reads the same choice.
  set giftEffectLevel(LocalGiftEffectLevel level) => _setAll({
    Settings.localInteractionGiftEffectLevel: level.id,
    Settings.localInteractionEnableGiftEffects: level != LocalGiftEffectLevel.off,
  });

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

  // ---- phrases and recent sends (D08.2) ----

  /// The user's phrases in their order (at most [Settings.localPhraseLimit]),
  /// each as a local danmaku may say it ([LocalCatalog.clipDanmaku]: a
  /// restored backup may hold longer ones).
  List<String> get phrases {
    final seen = <String>{};
    return List.unmodifiable([
      for (final phrase in _get(Settings.localInteractionPhrases))
        if (LocalCatalog.clipDanmaku(phrase) case final text when text.isNotEmpty && seen.add(text)) text,
    ]);
  }

  /// Whether [text] is one of the [phrases] (as it would be saved).
  bool hasPhrase(String text) => phrases.contains(LocalCatalog.clipDanmaku(text));

  /// Whether no more phrases can be added.
  bool get phrasesFull => phrases.length >= Settings.localPhraseLimit;

  /// Why [text] cannot be saved as a phrase (in place of the one at
  /// [replacing]): empty, there already, or the list full; null when it can.
  LocalPhraseProblem? phraseProblem(String text, {int? replacing}) {
    final words = LocalCatalog.clipDanmaku(text);
    if (words.isEmpty) return LocalPhraseProblem.empty;
    final list = phrases;
    final at = list.indexOf(words);
    if (at >= 0 && at != replacing) return LocalPhraseProblem.exists;
    if (replacing == null && list.length >= Settings.localPhraseLimit) return LocalPhraseProblem.full;
    return null;
  }

  /// Saves [text] as the last phrase; false (nothing saved) when
  /// [phraseProblem] says why not.
  bool addPhrase(String text) {
    if (phraseProblem(text) != null) return false;
    _set(Settings.localInteractionPhrases, [...phrases, LocalCatalog.clipDanmaku(text)]);
    return true;
  }

  /// Puts [text] in place of the phrase at [index]; false when
  /// [phraseProblem] says why not.
  bool editPhrase(int index, String text) {
    final list = [...phrases];
    if (index < 0 || index >= list.length || phraseProblem(text, replacing: index) != null) return false;
    list[index] = LocalCatalog.clipDanmaku(text);
    _set(Settings.localInteractionPhrases, list);
    return true;
  }

  /// Takes the phrase at [index] away and returns it (for [restorePhrase],
  /// the undo), or null when there is none.
  String? removePhrase(int index) {
    final list = [...phrases];
    if (index < 0 || index >= list.length) return null;
    final removed = list.removeAt(index);
    _set(Settings.localInteractionPhrases, list);
    return removed;
  }

  /// Puts [text] back at [index] (or the end), unless it is there already.
  void restorePhrase(int index, String text) {
    final list = [...phrases];
    final words = LocalCatalog.clipDanmaku(text);
    if (words.isEmpty || list.contains(words)) return;
    list.insert(index.clamp(0, list.length), words);
    _set(Settings.localInteractionPhrases, list);
  }

  /// Moves the phrase at [from] to [to] (the index it ends at).
  void movePhrase(int from, int to) {
    final list = [...phrases];
    if (from < 0 || from >= list.length) return;
    final moved = list.removeAt(from);
    list.insert(to.clamp(0, list.length), moved);
    _set(Settings.localInteractionPhrases, list);
  }

  /// The words of the local danmaku sent last, newest first: [count]
  /// different ones from the history (D08.1), leaving out the [phrases]
  /// (their chips follow anyway).
  List<String> recentChats({int count = LocalCatalog.recentCount}) {
    final skip = {...phrases};
    final recent = <String>[];
    for (final event in _entries) {
      if (recent.length >= count) break;
      if (event.kind != LocalEventKind.chat) continue;
      final words = LocalCatalog.clipDanmaku(event.text);
      if (words.isNotEmpty && skip.add(words)) recent.add(words);
    }
    return recent;
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
      // `then` with `onError`, not `catchError`: [write] may hand back a
      // Future<int> (an entry's id), whose catchError handler would have to
      // return an int, so a failed write threw again instead of being let go.
      write(store).then((_) {}, onError: (Object _) {}).whenComplete(() async {
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

  // ---- local growth (D08.3) ----

  /// Local growth is on: watching, the first room of the day and local
  /// danmaku earn experience and coins (on by default, D-040); off, only
  /// gifts earn experience, as in 3.x.
  bool get growthEnabled => _get(Settings.localInteractionGrowthEnabled);

  /// Turns local growth on or off; the time watched until now is kept.
  set growthEnabled(bool value) {
    if (!value) settleWatch();
    _set(Settings.localInteractionGrowthEnabled, value);
  }

  /// Whether anything grows now: the local interaction and local growth on.
  bool get growing => enabled && growthEnabled;

  /// The time now (the clock the interaction was given; a fake one in
  /// tests).
  DateTime now() => _now();

  /// The time watched that is not stored yet, and its day ([settleWatch]
  /// stores it: when a room stops counting, or with a step earned).
  Duration _unsaved = Duration.zero;
  String _unsavedDay = '';

  /// What growth gave today, the time watched not stored yet included.
  LocalGrowthDay get today => _dayState(LocalGrowthDay.dayOf(_now()));

  LocalGrowthDay _dayState(String day) {
    final stored = LocalGrowthDay.read(_get(Settings.localInteractionGrowthDay), day);
    return _unsavedDay == day ? stored.copyWith(watched: stored.watched + _unsaved) : stored;
  }

  /// Stores the time watched so far (the clock stopped counting: paused,
  /// in the background, the room left). Time of a day older than the one
  /// stored is let go (the clock was set back).
  void settleWatch() {
    final day = _unsavedDay;
    final unsaved = _unsaved;
    _unsaved = Duration.zero;
    _unsavedDay = '';
    if (_disposed || day.isEmpty || unsaved <= Duration.zero) return;
    final stored = LocalGrowthDay.parse(_get(Settings.localInteractionGrowthDay));
    if (stored != null && stored.day.compareTo(day) > 0) return;
    final state = stored != null && stored.day == day ? stored : LocalGrowthDay(day: day);
    _set(Settings.localInteractionGrowthDay, state.copyWith(watched: state.watched + unsaved).encode());
  }

  /// Settles the time watched on a day other than [day] before [day]'s
  /// counts are written.
  void _settleOther(String day) {
    if (_unsavedDay.isNotEmpty && _unsavedDay != day) settleWatch();
  }

  /// The first room of the day (D08.3 c3): [LocalCatalog.checkInExperience]
  /// and [LocalCatalog.checkInCoins], once a local day. False when given
  /// already or nothing grows.
  bool checkIn({LocalPlace? place}) {
    if (_disposed || !growing) return false;
    final day = LocalGrowthDay.dayOf(_now());
    _settleOther(day);
    final state = _dayState(day);
    if (state.checkedIn) return false;
    _grow(
      state.copyWith(checkedIn: true),
      experience: LocalCatalog.checkInExperience,
      coins: LocalCatalog.checkInCoins,
      place: place,
    );
    return true;
  }

  /// A room played from [from] to [to] (D08.3 c2): every
  /// [LocalCatalog.watchStep] of a day's playing earns
  /// [LocalCatalog.watchExperience] and [LocalCatalog.watchCoins], up to
  /// [LocalCatalog.watchExperienceDailyLimit] a day. Time over midnight
  /// counts for the day it fell in. The time is kept in memory and stored
  /// only when a step is earned or [settleWatch] runs, so watching writes
  /// once in ten minutes, not every minute.
  void watched(DateTime from, DateTime to, {LocalPlace? place}) {
    if (_disposed || !growing || !to.isAfter(from)) return;
    var start = from;
    while (start.isBefore(to)) {
      final midnight = LocalGrowthDay.endOfDay(start);
      final end = midnight.isBefore(to) ? midnight : to;
      _watchedOn(LocalGrowthDay.dayOf(start), end.difference(start), place);
      start = end;
    }
  }

  void _watchedOn(String day, Duration piece, LocalPlace? place) {
    _settleOther(day);
    final state = _dayState(day);
    final watched = state.watched + piece;
    const step = LocalCatalog.watchExperience;
    final earned = (watched.inMilliseconds ~/ LocalCatalog.watchStep.inMilliseconds).clamp(
      0,
      LocalCatalog.watchExperienceDailyLimit ~/ step,
    );
    final steps = earned - state.watchExperience ~/ step;
    if (steps <= 0) {
      _unsavedDay = day;
      _unsaved += piece;
      return;
    }
    _grow(
      state.copyWith(watched: watched, watchExperience: state.watchExperience + steps * step),
      experience: steps * step,
      coins: steps * LocalCatalog.watchCoins,
      place: place,
    );
  }

  /// A local danmaku was sent (D08.3 c4): [LocalCatalog.chatExperience], up
  /// to [LocalCatalog.chatExperienceDailyLimit] a day. False when nothing
  /// was given.
  bool rewardChat({LocalPlace? place}) {
    if (_disposed || !growing) return false;
    final day = LocalGrowthDay.dayOf(_now());
    _settleOther(day);
    final state = _dayState(day);
    if (state.chatExperience >= LocalCatalog.chatExperienceDailyLimit) return false;
    _grow(
      state.copyWith(chatExperience: state.chatExperience + LocalCatalog.chatExperience),
      experience: LocalCatalog.chatExperience,
      coins: 0,
      place: place,
    );
    return true;
  }

  /// Stores [state] (today's counts, the time not stored yet included) with
  /// [experience] and [coins] added, in one write; a level reached is
  /// recorded.
  void _grow(LocalGrowthDay state, {required int experience, required int coins, LocalPlace? place}) {
    final before = level;
    if (_unsavedDay == state.day) {
      _unsaved = Duration.zero;
      _unsavedDay = '';
    }
    _setAll({
      Settings.localInteractionGrowthDay: state.encode(),
      if (experience != 0) Settings.localInteractionExperience: this.experience + experience,
      if (coins != 0) Settings.localInteractionCoins: this.coins + coins,
    });
    _recordLevel(before, place);
  }

  /// Records the level reached when it is above [before] (D08.3: one
  /// `level` entry, "升到 Lv.N", however many levels one gain passed), while
  /// growth is on; off, sending is as before.
  void _recordLevel(int before, LocalPlace? place) {
    final reached = level;
    if (reached <= before || !growing) return;
    _record(
      LocalEvent(
        at: _now(),
        kind: LocalEventKind.level,
        platform: place?.platform ?? '',
        roomId: place?.roomId ?? '',
        roomName: place?.roomName ?? '',
        count: reached,
      ),
    );
  }

  /// "Lv.3 · 新人": the level now and its tier's name.
  String get levelLabel => 'Lv.$level · ${i18n(LocalCatalog.tierKeyFor(level))}';

  /// What growth gave today: "今天已签到 · 看直播 +30/300 · 弹幕 +5/50".
  String get growthTodayLine {
    final day = today;
    return [
      i18n(day.checkedIn ? 'local_growth_checked_in' : 'local_growth_not_checked_in'),
      i18n(
        'local_growth_watch',
        args: {'exp': '${day.watchExperience}', 'limit': '${LocalCatalog.watchExperienceDailyLimit}'},
      ),
      i18n(
        'local_growth_chat',
        args: {'exp': '${day.chatExperience}', 'limit': '${LocalCatalog.chatExperienceDailyLimit}'},
      ),
    ].join(' · ');
  }

  /// "还差 120 经验到 Lv.4".
  String get nextLevelLabel {
    final progress = LocalCatalog.progressFor(experience);
    return i18n('local_level_next', args: {'exp': '${progress.missing}', 'level': '${progress.level + 1}'});
  }

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

  /// Sends [count] of [gift] in a room of [platform]: takes their price,
  /// adds as much experience and a history line (3.x `sendGift`, one at a
  /// time). Null when the interaction is off or the coins do not cover them
  /// all.
  ///
  /// The entry (D08.1) names [place] when it was sent in a room. [combo]
  /// (D08.4 c1) is the run of this gift the send belongs to: an empty one
  /// starts with it, one with gifts in it grows, so the run is one history
  /// entry and one 3.x line whose count goes up, and the message says the
  /// run's count so far. Each send still takes its own coins and gives its
  /// own experience.
  LiveMessage? sendGift(
    LocalGift gift, {
    required String platform,
    LocalPlace? place,
    int count = 1,
    LocalGiftCombo? combo,
  }) {
    assert(combo == null || combo.gift.id == gift.id, 'a combo holds one gift');
    final cost = gift.price * count;
    if (!enabled || count < 1 || coins < cost) return null;
    final joining = combo != null && combo.count > 0;
    final total = joining ? combo.count + count : count;
    final profile = profileFor(platform);
    final giftName = i18n(gift.nameKey);
    final sent = i18n('local_sent_gift');
    final before = level;
    final line = '${gift.emoji} ${profile.legacyLabel} · ${profile.name} $sent $giftName ×$total';
    final lines = history;
    _setAll({
      Settings.localInteractionCoins: coins - cost,
      Settings.localInteractionExperience: experience + cost,
      // The run's line with its count raised while it is still the newest.
      Settings.localInteractionHistory: joining && lines.isNotEmpty && lines.first == combo._line
          ? [line, ...lines.skip(1)]
          : _withHistory(line),
    });
    if (!joining || !_growGift(combo, count, cost)) {
      _recordGift(
        LocalEvent(
          at: _now(),
          kind: LocalEventKind.gift,
          platform: place?.platform ?? platform,
          roomId: place?.roomId ?? '',
          roomName: place?.roomName ?? '',
          giftId: gift.id,
          count: count,
          coins: cost,
        ),
        combo,
      );
    }
    if (combo != null) {
      combo
        .._count = total
        .._coins += cost
        .._line = line;
    }
    _recordLevel(before, place);
    return LiveMessage(
      type: LiveMessageType.gift,
      userName: profile.name,
      // U.2k c10: what flies over the picture, without the badge.
      message: '${profile.name} $sent $giftName ×$total',
      color: gift.color,
      userLevel: profile.level?.toString() ?? '',
      fansName: profile.title,
      data: {
        ...profile.toData(),
        'giftId': gift.id,
        'giftName': giftName,
        'emoji': gift.emoji,
        'price': gift.price,
        'count': total,
        'platform': platform,
        'big': gift.big,
        // 3.x's values; D08.5: none also for a tier the level leaves out.
        'effect': switch (LocalGiftTier.ofGift(gift)) {
          final tier when !giftEffectLevel.shows(tier) => 'none',
          LocalGiftTier.big => 'full',
          _ => 'ticker',
        },
      },
      isLocal: true,
      style: currentStyle,
    );
  }

  /// Records [entry], a new gift entry, as [combo]'s (its id comes from the
  /// store).
  void _recordGift(LocalEvent entry, LocalGiftCombo? combo) {
    combo
      ?.._entry = entry
      .._stored = null;
    _keep([entry, ..._entries], (store) {
      final id = store.add(entry);
      combo?._stored = id;
      return id;
    });
  }

  /// Adds [count] gifts and [cost] coins to [combo]'s entry where it is
  /// (D08.4 c1); false when the entry is gone (the history was cleared
  /// meanwhile), so the send starts a new one.
  bool _growGift(LocalGiftCombo combo, int count, int cost) {
    final entry = combo._entry;
    if (entry == null) return false;
    final at = _entries.indexWhere((old) => _sameEntry(old, entry));
    if (at < 0) return false;
    final current = _entries[at];
    final grown = current.withCount(current.count + count, current.coins + cost);
    combo._entry = grown;
    final stored = combo._stored;
    _keep([..._entries]..[at] = grown, (store) async {
      final id = grown.id ?? await stored;
      if (id != null) await store.updateCount(id, count: grown.count, coins: grown.coins);
    });
    return true;
  }

  /// Whether [a] and [b] are the same entry: the same id, or before the
  /// store gave one, the same gift at the same time in the same room.
  static bool _sameEntry(LocalEvent a, LocalEvent b) {
    if (a.id != null && b.id != null) return a.id == b.id;
    return a.kind == b.kind &&
        a.giftId == b.giftId &&
        a.at.millisecondsSinceEpoch == b.at.millisecondsSinceEpoch &&
        a.platform == b.platform &&
        a.roomId == b.roomId;
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
