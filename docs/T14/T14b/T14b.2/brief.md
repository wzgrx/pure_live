# T14b.2 刷新率：播放中统一用帧率声明、没有整数倍时取最高、厂商限制提示

- 规模：中；分组：刷新率；依赖：—；能否和别的任务同时做：可以和任何任务同时（只有它改 `MainActivity.kt` 的刷新率部分和 `platform/display_mode.dart`）
- 出设计：不用（照调研报告和本任务单；改变手感的地方在记录里写清前后对比）
- 先读：调研报告 `docs/T14/research-2026-10-02.md` 第 1 节（R1～R4、R6）；现有策略：`docs/T14/T14b/T14b.1/README.md`、`features/live_play/logic/room_refresh_rate.dart`
- 可以改：`apps/pure_live/android/app/src/main/kotlin/`（只改刷新率相关）、`platform/display_mode.dart`、`features/live_play/logic/room_refresh_rate.dart`、`features/settings/`（只改刷新率那一行）、`docs/T14/T14b/T14b.1/README.md`；其他目录不改。

## 要做的

- c1 R1：播放中只用 `Surface.setFrameRate` 声明（Android 文档：声明过帧率的 Surface 会忽略窗口的 `preferredRefreshRate`）。播放 + 均衡档操作中：声明视频帧率整数倍里最高的（K90 上 60 帧 → 120），`FIXED_SOURCE`；操作结束回到视频帧率。不播放时：均衡档操作中和最高档，Android 16+ 用 `setFrameRate(最高, AT_LEAST)`，11～15 保留窗口提示。改 `MainActivity.kt` 的 `applyVideoFrameRate`、`setHighRefreshRate` 和 `platform/display_mode.dart` 的 `_applyRate`。
- c2 R2：`playbackRefreshRate` 没有整数倍时取设备最高刷新率（25、50 帧在 K90 上取 120；24 帧取 120），不再返回 null 交给系统；同步改 `room_refresh_rate_test.dart` 和 `display_mode` 的测试。
- c3 R3：均衡档操作中或最高档时，请求 ≥90 但 `currentRefreshRate` 连续 3 秒是 60，在设置的“界面刷新率”那一行下面加一句提示：“系统把本应用限制在 60 Hz，可以在系统设置 → 显示 → 屏幕刷新率里调高”（中英文都加），恢复后提示消失。
- c4 R4、R6：投具体数值，不投类别（K90 的 HIGH 类别只给 90）；manifest 保持不声明 `appCategory=game`（Android 15 起游戏默认 60 Hz），加一个检查它的测试或门禁项。
- c5 在 `docs/T14/T14b/T14b.1/README.md` 末尾加“4.0.x 修订”一节，写清新旧策略对比（报告 1.4 节的表）。

## 验收

- 播放中刷新率按 c1、c2 走；被厂商限制时设置里有提示。
- 测试：`playbackRefreshRate` 对 24/25/30/50/60 帧 × 设备模式（60/90/120、60/120/144、60/90/120/144/165）的结果；提示的出现和消失；Kotlin 部分写清手动验证方法。

## 真机上看的（写进记录，维护者在 K90 上看）

- 开开发者选项“显示刷新率”。均衡档播 60 帧直播：不操作时 60，拖聊天或面板后 100 ms 内到 120，松手约 1.5 秒回 60；进出直播间不黑屏。
- `adb shell dumpsys SurfaceFlinger | grep -E "renderRate|activeMode="` 和 `dumpsys display` 的 mVotes 截一份写进记录。
- 系统刷新率改成“标准”，设置里出现限制提示；改回“高”提示消失。

