import 'dart:convert';
import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_record/live_record.dart';
import 'package:live_store/live_store.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pure_live/app/services.dart';

/// Where the recording centre's tasks are kept (3.x `recorder_tasks`; the
/// import left 3.x's list in `legacy_values`).
const String recorderTasksKey = 'recorder.tasks';

/// The input openers of the recipe platforms (FC2, Bigo, niconico): without
/// them those rooms cannot be recorded (M8).
List<RecipeOpener> recipeOpeners(SiteRegistry sites) => [
  BigoRecipeOpener(sites.of(SiteIds.bigo) as BigoSite),
  Fc2RecipeOpener(sites.of(SiteIds.fc2Live) as Fc2LiveSite),
  NiconicoRecipeOpener(sites.of(SiteIds.niconico) as NiconicoSite),
];

/// The default recording folder: Android's app folder on external storage
/// (no permission needed), else `Records` in the data folder.
Future<String> defaultRecordDirectory(Directory dataRoot) async {
  if (Platform.isAndroid) {
    final external = await getExternalStorageDirectory();
    if (external != null) return p.join(external.path, 'Records');
  }
  return p.join(dataRoot.path, 'Records');
}

/// The recorder (M8) over the app's services.
///
/// The app still lacks three platform pieces (docs/modules/M12-app.md,
/// "留给其他模块"): the FFmpeg runner ([ffmpeg]; 3.x used FFmpegKit), the
/// Android foreground service ([keepAlive]) and the CA bundle FFmpeg's
/// OpenSSL needs on Android ([caFile]; 3.x shipped
/// `assets/certificates/mozilla-ca-bundle.pem`). Until the runner exists
/// the recorder is not created at start.
Recorder buildRecorder(
  AppServices services, {
  required FfmpegRunner ffmpeg,
  required RecordSettings Function() settings,
  RecordKeepAlive? keepAlive,
  Future<bool> Function({required bool interactive})? storageAccess,
  String? Function()? caFile,
}) {
  final store = services.store;
  return Recorder(
    sites: services.sites.maybeOf,
    ffmpeg: ffmpeg,
    storage: RecordStorage(
      defaultDirectory: () => defaultRecordDirectory(services.dataRoot),
      configuredPath: () => settings().savePath,
      isAndroid: Platform.isAndroid,
    ),
    settings: settings,
    inputs: RecordInputOpener(proxy: services.proxy, recipes: recipeOpeners(services.sites)),
    persist: (json) => store.meta.set(recorderTasksKey, json),
    keepAlive: keepAlive,
    storageAccess: storageAccess,
    caFile: caFile,
  );
}

/// The saved task list: v4's, else the one imported from 3.x.
Future<String?> savedRecorderTasks(LiveStore store) async {
  final saved = await store.meta.get(recorderTasksKey);
  if (saved != null) return saved;
  final legacy = await store.meta.legacyValue('recorder_tasks');
  return switch (legacy) {
    null => null,
    final String text => text,
    _ => jsonEncode(legacy),
  };
}
