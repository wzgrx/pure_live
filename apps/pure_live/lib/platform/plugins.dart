import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:open_filex/open_filex.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/pages/backup/backup_page.dart';
import 'package:pure_live/pages/iptv/iptv_import.dart';
import 'package:pure_live/pages/record_settings/record_settings_dialogs.dart';
import 'package:pure_live/pages/settings/data_tools.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/shared/rooms/share_code.dart';
import 'package:share_plus/share_plus.dart';

/// Hands the plugins to the places that wait for them (M12.3); `main` calls
/// this once before the first frame.
///
/// - the room menu's share sheet ([SystemShare.sheet], share_plus);
/// - the disk part of the image cache ([ImageCacheTools.clearDisk],
///   flutter_cache_manager's default manager, which cached_network_image
///   and live_ui's images use);
/// - opening local files ([AppNavigator.openFile], open_filex on Android).
void installPluginHooks() {
  SystemShare.sheet = shareText;
  ImageCacheTools.clearDisk = () => DefaultCacheManager().emptyCache();
  AppNavigator.openFile = openLocalFile;
}

/// The page hooks that are providers (`ProviderScope.overrides` in `main`):
/// the system pickers of the IPTV import, the backups and the record folder.
List<Override> pluginOverrides() => [
  iptvFilePickerProvider.overrideWithValue(pickIptvFile),
  backupPickerProvider.overrideWithValue(pickBackupPath),
  recordDirectoryPickerProvider.overrideWithValue(pickRecordDirectory),
];

/// The system share sheet with [text] (share_plus); true once it was shown.
Future<bool> shareText(String text) async {
  await SharePlus.instance.share(ShareParams(text: text));
  return true;
}

/// Opens the local file at [path] with the app the system picks: open_filex
/// on Android (a content URI through its file provider; `url_launcher`
/// cannot hand out the app's private files), the shell elsewhere.
Future<bool> openLocalFile(String path) async {
  if (Platform.isAndroid) {
    final result = await OpenFilex.open(path);
    return result.type == ResultType.done;
  }
  return await AppNavigator.openExternal(Uri.file(path));
}

/// Desktop pickers filter by extension; Android's document picker filters by
/// MIME type, which most providers do not know for playlists and guides, so
/// it shows every file and the importer checks the content.
bool get _filterByExtension => !Platform.isAndroid;

/// The IPTV import's file (3.x `FilePicker.platform.pickFiles` with the
/// kind's extensions). On Android the picker copies the chosen document into
/// the app's cache, so no storage permission is needed.
Future<File?> pickIptvFile(BuildContext context, IptvImportKind kind) async {
  final file = await FilePicker.pickFile(
    dialogTitle: i18n(kind == IptvImportKind.playlist ? 'dialog_import_playlist_title' : 'dialog_import_epg_title'),
    type: _filterByExtension ? FileType.custom : FileType.any,
    allowedExtensions: _filterByExtension ? importExtensions(kind) : null,
  );
  final path = file?.path;
  return path == null ? null : File(path);
}

/// A backup file to restore, or the folder backups go to (the backup page's
/// [BackupPicker]). Android uses the system document picker for both: a
/// picked file is copied into the app's cache; a picked folder is checked
/// for writing by the page. No "all files" access is asked for.
Future<String?> pickBackupPath(BuildContext context, {required String initial, required bool pickFile}) async {
  final start = Directory(initial).existsSync() ? initial : null;
  if (!pickFile) {
    return await FilePicker.getDirectoryPath(dialogTitle: i18n('backup_directory'), initialDirectory: start);
  }
  final file = await FilePicker.pickFile(
    dialogTitle: i18n('recover_backup'),
    initialDirectory: start,
    type: _filterByExtension ? FileType.custom : FileType.any,
    allowedExtensions: _filterByExtension ? const ['txt', 'json'] : null,
  );
  return file?.path;
}

/// The record folder (3.x `FilePicker.platform.getDirectoryPath`).
Future<String?> pickRecordDirectory() => FilePicker.getDirectoryPath(dialogTitle: i18n('record_save_path'));
