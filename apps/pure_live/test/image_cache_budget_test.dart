// P05 (research 2026-10-02 D2): the decoded-image cache sized by the
// device's memory.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/app/bootstrap.dart';

void main() {
  const mebibyte = 1024 * 1024;
  const gibibyte = 1024 * mebibyte;

  test("phones with 4 GiB or less (or unknown) keep 3.x's budget; more memory gets 128 MiB", () {
    expect(decodedImageBudget(desktop: false), (count: 160, bytes: 48 * mebibyte));
    // A "4 GB" phone reads about 3.6 GiB.
    expect(decodedImageBudget(desktop: false, totalMemoryBytes: 3700 * mebibyte), (count: 160, bytes: 48 * mebibyte));
    expect(decodedImageBudget(desktop: false, totalMemoryBytes: 4 * gibibyte), (count: 160, bytes: 48 * mebibyte));
    expect(decodedImageBudget(desktop: false, totalMemoryBytes: 5600 * mebibyte), (count: 320, bytes: 128 * mebibyte));
    expect(decodedImageBudget(desktop: false, totalMemoryBytes: 16 * gibibyte), (count: 320, bytes: 128 * mebibyte));
    // Desktops: 3.x's.
    expect(decodedImageBudget(desktop: true, totalMemoryBytes: 32 * gibibyte), (count: 240, bytes: 72 * mebibyte));
  });

  test("the memory comes from /proc/meminfo's MemTotal; unreadable is unknown", () {
    final folder = Directory.systemTemp.createTempSync('meminfo');
    addTearDown(() => folder.deleteSync(recursive: true));
    final file = File('${folder.path}/meminfo')
      ..writeAsStringSync('MemTotal:       11712340 kB\nMemFree:          823456 kB\nMemAvailable:    5123456 kB\n');
    expect(readTotalMemoryBytes(path: file.path), 11712340 * 1024);
    file.writeAsStringSync('MemFree: 1 kB\n');
    expect(readTotalMemoryBytes(path: file.path), isNull);
    expect(readTotalMemoryBytes(path: '${folder.path}/missing'), isNull);
  });

  testWidgets('the cache takes the budget', (tester) async {
    final cache = PaintingBinding.instance.imageCache;
    final count = cache.maximumSize;
    final bytes = cache.maximumSizeBytes;
    addTearDown(() {
      cache
        ..maximumSize = count
        ..maximumSizeBytes = bytes;
    });
    configureDecodedImageCache(desktop: false, totalMemoryBytes: 12 * gibibyte);
    expect(cache.maximumSize, 320);
    expect(cache.maximumSizeBytes, 128 * mebibyte);
    configureDecodedImageCache(desktop: false);
    expect(cache.maximumSizeBytes, 48 * mebibyte);
  });
}
