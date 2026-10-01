import 'dart:async';

/// A frame rate mpv reported, or null when it is missing or not a video's
/// (below 10 or above 240 frames a second; a live FLV may report 1000).
double? parseFrameRate(String text) {
  final value = double.tryParse(text.trim());
  if (value == null || value.isNaN || value < 10 || value > 240) return null;
  return value;
}

/// The frame rate of what mpv plays (U.2i): `container-fps` once the stream
/// has opened ([settle] after the open), else `estimated-vf-fps` when two
/// readings [settle] apart agree within 1 %; null after [attempts] readings
/// or as soon as [current] says the open was replaced. A handful of reads per
/// open, nothing that keeps running.
Future<double?> probeFrameRate(
  Future<String> Function(String property) read, {
  bool Function()? current,
  Duration settle = const Duration(seconds: 2),
  int attempts = 4,
}) async {
  bool gone() => current != null && !current();
  await Future<void>.delayed(settle);
  if (gone()) return null;
  final container = parseFrameRate(await read('container-fps'));
  if (container != null) return container;
  double? previous;
  for (var i = 0; i < attempts; i++) {
    if (i > 0) await Future<void>.delayed(settle);
    if (gone()) return null;
    final estimate = parseFrameRate(await read('estimated-vf-fps'));
    if (estimate != null && previous != null && (estimate - previous).abs() <= previous * 0.01) return estimate;
    previous = estimate;
  }
  return null;
}
