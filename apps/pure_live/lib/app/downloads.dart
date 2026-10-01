import 'dart:async';
import 'dart:io';

import 'package:live_net/live_net.dart';
import 'package:live_store/live_store.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Bytes received so far and the whole size when known.
typedef DownloadProgress = void Function(int received, int? total);

/// The folder update packages go to (3.x `CacheController.resolveDownloadDirectory`):
/// the folder chosen on the cache page ([Settings.downloadDirectoryPath]),
/// else the platform default ([defaultDownloadDirectory]).
Future<Directory> resolveDownloadDirectory(SettingsStore settings, {required Directory dataRoot}) async {
  final custom = settings.get(Settings.downloadDirectoryPath).trim();
  if (custom.isNotEmpty) return Directory(custom);
  return await defaultDownloadDirectory(dataRoot: dataRoot);
}

/// The default download folder: Android's app download folder
/// (`Android/data/<package>/files/Download/pure_live`, no permission needed,
/// as 3.x), elsewhere `downloads` in the data folder (3.x's `DOWNLOADS`).
Future<Directory> defaultDownloadDirectory({required Directory dataRoot}) async {
  if (Platform.isAndroid) {
    try {
      final downloads = await getDownloadsDirectory();
      if (downloads != null) return Directory(p.join(downloads.path, 'pure_live'));
    } on Object {
      // Falls back to the data folder.
    }
  }
  return Directory(p.join(dataRoot.path, 'downloads'));
}

/// Whether [directory] exists or can be made and takes a file (3.x
/// `isCustomDownloadDirectoryUsable`; Android may leave a picked folder
/// readable but not writable).
Future<bool> canWriteDirectory(Directory directory) async {
  try {
    await directory.create(recursive: true);
    final probe = File(p.join(directory.path, '.pure_live_write_probe'));
    await probe.writeAsString('ok', flush: true);
    await probe.delete();
    return true;
  } on Object {
    return false;
  }
}

/// A file name safe on every platform from [url] or [suggested] (3.x
/// `safeDownloadFileName`).
String safeDownloadFileName(String url, {String? suggested}) {
  var name = suggested?.trim() ?? '';
  if (name.isEmpty) {
    final segments = Uri.tryParse(url)?.pathSegments ?? const [];
    name = segments.where((segment) => segment.isNotEmpty).lastOrNull ?? '';
  }
  name = name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_').trim();
  if (name.isEmpty || name == '.' || name == '..') name = 'download';
  return name;
}

/// Why a download stopped.
enum DownloadFailure {
  /// Every source failed (network, server, bad answer).
  network,

  /// The file could not be written.
  disk,

  /// The user cancelled.
  cancelled,
}

/// A failed download.
final class DownloadException implements Exception {
  /// Creates the failure.
  const new(this.reason, [this.detail]);

  /// What went wrong.
  final DownloadFailure reason;

  /// Diagnostic detail.
  final String? detail;

  @override
  String toString() => 'DownloadException(${reason.name}${detail == null ? '' : ': $detail'})';
}

/// Downloads one file through the app's HTTP client (proxy, logging) with
/// progress and resume: bytes go to `<target>.part`, which a later run
/// continues with a `Range` request when the server allows it (3.x started
/// over every time); the finished file replaces the target only when complete.
///
/// Several sources (mirrors) are tried in order; a source that fails moves
/// on to the next with the bytes already received.
final class FileDownloader {
  /// Creates a downloader over [http].
  new(this.http, {this.site = 'app', this.gapTimeout = const Duration(seconds: 30)});

  /// Transport (the app's client, so the app proxy applies).
  final LiveHttp http;

  /// The request's site id (proxy route and throttle).
  final String site;

  /// Longest wait for the headers and between chunks.
  final Duration gapTimeout;

  /// The unfinished part of [target].
  static File partOf(File target) => File('${target.path}.part');

  /// Downloads into [target]; returns it when complete. Throws
  /// [DownloadException]; a cancel keeps the part for a later resume.
  Future<File> download(
    List<Uri> sources,
    File target, {
    DownloadProgress? onProgress,
    CancelToken? cancel,
    Map<String, String> headers = const {},
  }) async {
    if (sources.isEmpty) throw const DownloadException(DownloadFailure.network, 'no source');
    final part = partOf(target);
    try {
      await target.parent.create(recursive: true);
    } on FileSystemException catch (error) {
      throw DownloadException(DownloadFailure.disk, error.message);
    }
    Object? lastError;
    for (final source in sources) {
      if (cancel?.isCancelled ?? false) throw const DownloadException(DownloadFailure.cancelled);
      try {
        await _fetch(source, part, headers: headers, onProgress: onProgress, cancel: cancel);
        try {
          if (target.existsSync()) await target.delete();
          return await part.rename(target.path);
        } on FileSystemException catch (error) {
          throw DownloadException(DownloadFailure.disk, error.message);
        }
      } on DownloadException catch (error) {
        if (error.reason != DownloadFailure.network) rethrow;
        lastError = error;
      } on TransportFailure catch (error) {
        if (error.reason == TransportReason.cancelled || (cancel?.isCancelled ?? false)) {
          throw const DownloadException(DownloadFailure.cancelled);
        }
        lastError = error;
      }
    }
    throw DownloadException(DownloadFailure.network, '$lastError');
  }

  Future<void> _fetch(
    Uri source,
    File part, {
    required Map<String, String> headers,
    required DownloadProgress? onProgress,
    required CancelToken? cancel,
  }) async {
    final have = part.existsSync() ? part.lengthSync() : 0;
    final response = await http.open(
      LiveRequest(
        site: site,
        url: source,
        headers: {'cache-control': 'no-cache', if (have > 0) 'range': 'bytes=$have-', ...headers},
        timeout: gapTimeout,
        cancel: cancel,
      ),
    );
    var received = 0;
    int? total;
    FileMode mode;
    if (response.status == 206 && have > 0) {
      // Content-Range: bytes <start>-<end>/<size>; anything but our start
      // means the server answered another range.
      final range = RegExp(r'bytes (\d+)-\d+/(\d+|\*)').firstMatch(response.header('content-range') ?? '');
      if (range == null || int.parse(range.group(1)!) != have) {
        await response.discard();
        throw const DownloadException(DownloadFailure.network, 'unexpected range');
      }
      received = have;
      total = int.tryParse(range.group(2)!) ?? (response.contentLength == null ? null : have + response.contentLength!);
      mode = FileMode.append;
    } else if (response.status == 416 && have > 0) {
      // The part already holds the whole file.
      await response.discard();
      onProgress?.call(have, have);
      return;
    } else if (response.isSuccess) {
      total = response.contentLength;
      mode = FileMode.write;
    } else {
      await response.discard();
      throw DownloadException(DownloadFailure.network, 'HTTP ${response.status}');
    }
    onProgress?.call(received, total);
    IOSink sink;
    try {
      sink = part.openWrite(mode: mode);
    } on FileSystemException catch (error) {
      await response.discard();
      throw DownloadException(DownloadFailure.disk, error.message);
    }
    try {
      await for (final chunk in response.body) {
        if (cancel?.isCancelled ?? false) throw const DownloadException(DownloadFailure.cancelled);
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
    } finally {
      await sink.flush();
      await sink.close();
    }
    if (total != null && received < total) {
      throw DownloadException(DownloadFailure.network, 'short body $received/$total');
    }
  }
}
