import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_media/live_media.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/core/store.dart';

/// Creates playback engines: mpv on devices (ADR 0006), a fake in tests.
/// Hardware decoding follows the setting at creation time.
final Provider<EngineFactory> engineFactoryProvider = Provider<EngineFactory>((ref) {
  final settings = ref.watch(storeProvider).settings;
  return () => mpvEngineFactory(MpvEngineConfig(hardwareDecoding: settings.get(Settings.hardwareDecoding)))();
});
