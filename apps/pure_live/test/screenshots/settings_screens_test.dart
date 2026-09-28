@Tags(['screenshots'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_record/live_record.dart';
import 'package:pure_live_app/features/iptv/iptv_page.dart';
import 'package:pure_live_app/features/settings/settings_page.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

import 'shot_harness.dart';

/// 我的, settings (principles §4.4: a list of groups up to medium width, two
/// panes from expanded), the recording center and the IPTV page.
void main() {
  screenshotSetUp();

  group('me', () {
    Future<void> me(ShotApp app) => app.go('/me');

    screenshot('me', ShotScreen.phone, me);
    screenshot('me', ShotScreen.large, me, theme: ShotTheme.dark);
  });

  group('settings', () {
    Future<void> settings(ShotApp app) => app.go('/me/settings');

    screenshot('settings', ShotScreen.phone, settings);
    screenshot('settings', ShotScreen.phone, settings, locale: AppLocale.zhHant);
    screenshot('settings', ShotScreen.phone, settings, locale: AppLocale.en);
    screenshot('settings', ShotScreen.phone, settings, theme: ShotTheme.dark);
    screenshot('settings', ShotScreen.expanded, settings);
    screenshot('settings', ShotScreen.large, settings, theme: ShotTheme.dark, locale: AppLocale.en);
    screenshot('settings-playback', ShotScreen.extraLarge, (app) async {
      await settings(app);
      await app.tester.tap(find.text(SettingsGroup.playback.label));
      await app.frames();
    });
  });

  group('settings group', () {
    Future<void> playback(ShotApp app) => app.go('/me/settings/playback');

    screenshot('settings-playback', ShotScreen.phone, playback);
    screenshot('settings-playback', ShotScreen.phone, playback, theme: ShotTheme.dark);
    screenshot('settings-playback', ShotScreen.phone, playback, locale: AppLocale.en);
    screenshot('settings-playback', ShotScreen.phone, playback, locale: AppLocale.zhHant, textScale: 2);
    screenshot('settings-general', ShotScreen.medium, (app) => app.go('/me/settings/general'), theme: ShotTheme.black);
  });

  group('recording', () {
    Future<void> recordings(ShotApp app) => app.go('/me/recordings');

    screenshot('recording', ShotScreen.phone, recordings, recorder: _recorder);
    screenshot('recording', ShotScreen.phone, recordings, recorder: _recorder, theme: ShotTheme.dark);
    screenshot('recording', ShotScreen.large, recordings, recorder: _recorder, locale: AppLocale.en);
    screenshot('recording-empty', ShotScreen.phone, recordings);
    // Before the stored tasks are read: a static skeleton (principles §2.5).
    screenshot('recording-loading', ShotScreen.phone, recordings, recorder: () async => ShotApp.unreadRecorder());
  });

  group('history', () {
    screenshot('history-empty', ShotScreen.phone, (app) => app.go('/me/history'));
  });

  group('iptv', () {
    ShotWorld withPlaylists() => ShotWorld(playlists: true);

    Future<void> iptv(ShotApp app) => app.push(iptvLocation);

    screenshot('iptv', ShotScreen.phone, iptv, world: withPlaylists);
    screenshot('iptv', ShotScreen.phone, iptv, world: withPlaylists, theme: ShotTheme.dark);
    screenshot('iptv', ShotScreen.large, iptv, world: withPlaylists);
  });
}

/// A recorder holding finished, failed and stopped tasks (running ones need
/// a live stream).
Future<RecordManager> _recorder() async {
  final start = DateTime(2026, 9, 27, 20);
  RecordTask task(
    ShotRoom room,
    RecordState state, {
    int bytes = 0,
    Duration media = Duration.zero,
    RecordFailure? failure,
  }) {
    final ref = RoomRef(room.platform, room.id);
    return RecordTask(
      room: ref,
      createdAt: start.add(Duration(minutes: shotRooms.indexOf(room))),
      state: state,
      snapshot: RecordRoomSnapshot(anchorName: room.anchor, title: room.title),
      failure: failure,
      stopCause: state == RecordState.stopped ? StopCause.user : null,
      session: bytes == 0
          ? null
          : RecordSessionInfo(
              layout: SessionLayout.at('/storage/emulated/0/Movies/PureLive', ref, room.anchor, start),
              bytes: bytes,
              media: media,
            ),
    );
  }

  final manager = RecordManager(
    rooms: SiteRecordRooms((_) => null),
    store: MemoryRecordTaskStore([
      task(shotRooms[0], RecordState.completed, bytes: 2400000000, media: const Duration(hours: 2, minutes: 41)),
      task(shotRooms[1], RecordState.completed, bytes: 812000000, media: const Duration(minutes: 57, seconds: 12)),
      task(
        shotRooms[2],
        RecordState.failed,
        bytes: 35000000,
        media: const Duration(minutes: 3),
        failure: RecordFailure(RecordErrorKind.allLinesFailed, RecordStage.stream),
      ),
      task(shotRooms[3], RecordState.stopped),
    ]),
    root: '/nonexistent',
    opener: httpRecordOpener(),
  );
  await manager.init();
  await manager.recovered;
  return manager;
}
