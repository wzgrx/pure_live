import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('foreground Android activity always routes hardware volume to media', () {
    final source = File('android/app/src/main/kotlin/com/mystyle/pure_live/MainActivity.kt').readAsStringSync();

    expect(source, contains('import android.media.AudioManager'));
    expect(
      source,
      contains('setVolumeControlStream(AudioManager.STREAM_MUSIC)'),
      reason: 'the visible media activity must bind hardware volume keys to the music stream',
    );

    final onResume = RegExp(r'override fun onResume\(\)\s*\{(?<body>[\s\S]*?)\n\s*\}').firstMatch(source);
    expect(onResume, isNotNull);
    expect(
      onResume!.namedGroup('body'),
      contains('setVolumeControlStream(AudioManager.STREAM_MUSIC)'),
      reason: 'the binding must be restored whenever the activity becomes visible',
    );
  });
}
