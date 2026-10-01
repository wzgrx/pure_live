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
}) {
  if (!automatic) return configured.clamp(30, 240);
  final maximum = maxRefreshRate ?? 0;
  final current = currentRefreshRate ?? 0;
  final detected = maximum > 0 ? maximum : (current > 0 ? current : 60.0);
  final device = detected.round().clamp(30, 240);
  return mode == 'performance' ? device : device.clamp(30, 60);
}
