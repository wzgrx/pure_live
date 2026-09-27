import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

/// The figure a card shows (F-DSC-05): the platform's heat first (3.x's
/// default), or concurrent viewers first when the user prefers them; the
/// other figures fill in when the first is missing.
int? shownAudience(Audience audience, {required bool preferOnline}) => preferOnline
    ? audience.online ?? audience.popularity ?? audience.cumulative
    : audience.popularity ?? audience.online ?? audience.cumulative;

/// 真实在线人数优先 (F-DSC-05; off: platform heat first).
final preferRealOnlineSetting = NotifierProvider<SettingNotifier<bool>, bool>(
  () => SettingNotifier(Settings.preferRealOnlineCounts),
);

/// What each platform's figures mean (F-DSC-05), from 3.x's measured notes,
/// in the interface language.
Map<String, String> get audienceNotes => t.audience.notes;
