/// The danmaku frame rate in use (3.x `resolvedDanmakuFps`): the manual
/// [configured] rate, or with [automatic] the display's highest rate capped
/// by the refresh rate [mode] (`powerSaving` 60, `balanced` 60,
/// `performance` the display's).
int resolvedDanmakuFps({
  required bool automatic,
  required int configured,
  required String mode,
  double? maxRefreshRate,
  double? currentRefreshRate,
  bool pip = false,
}) {
  // The picture-in-picture danmaku goes down to 15 and saves power at 30
  // (3.x `resolveAdaptiveDanmakuFps(pip: true)`).
  final floor = pip ? 15 : 30;
  if (!automatic) return configured.clamp(floor, 240);
  final maximum = maxRefreshRate ?? 0;
  final current = currentRefreshRate ?? 0;
  final detected = maximum > 0 ? maximum : (current > 0 ? current : 60.0);
  final device = detected.round().clamp(floor, 240);
  return switch (mode) {
    'performance' => device,
    'balanced' => device.clamp(floor, 60),
    _ => device.clamp(floor, pip ? 30 : 60),
  };
}
