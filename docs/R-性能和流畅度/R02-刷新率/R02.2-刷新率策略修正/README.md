# R02.2 刷新率策略修正：播放中只用帧率声明、没有整数倍取最高、系统限速提示

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：性能
- 来源：[V03.2 流畅度、刷新率、分辨率调研](../../../V-需求和反馈/V03-审查和调研/V03.2-流畅度、刷新率、分辨率调研/README.md)（2026-10-02）第 1 节的 R1～R4、R6（含 K90 只读实测）；结论定为 D-010
- 旧编号：P01、T14b.2
- 相关：决定 D-010、D-016；前一个任务 [R02.1](../R02.1-刷新率和帧率匹配/README.md)（新旧对比写在它的“4.0.x 修订”一节）；弹幕帧率 D03.1；耗电 [R05.1](../../R05-耗电/R05.1-耗电/README.md)；任务单 [brief.md](brief.md)（旧格式，开发时用的）、记录 [record.md](record.md)、真机步骤 [verify.md](verify.md)

## 目标

- 播放中我们自己的刷新率请求真的起作用：均衡档看 30/60 帧直播时，拖聊天、面板能由应用升到 120，而不是只靠系统 1.5 秒的触摸加速。
- K90 这类只有 60/90/120 Hz 的屏上，24/25/50 帧的视频不再交给系统（多半 60，25 帧 2、3 交替），而是取最高刷新率，帧节奏更匀。
- 系统（HyperOS 这类）把应用压在 60 Hz 时，用户知道去哪调。
- 只投具体数值、不投类别，清单不声明游戏，防止以后被回退。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11`） | R02.1 之后 | 现在（R02.2，文件:行） |
|---|---|---|---|
| 播放中的请求 | 没有帧率匹配，照三档改窗口提示 | Flutter 画面声明视频帧率（`FIXED_SOURCE`）+ 均衡操作时窗口提示“整数倍里最高”——后者对已声明的画面无效 | 只在 Flutter 画面上声明（Android 12+），窗口提示清零；均衡操作中声明整数倍里最高、松手 1.5 秒回空闲值（`apps/pure_live/lib/platform/display_mode.dart:279-299`；`MainActivity.kt:784-840`） |
| 没有整数倍时（K90 上 25/50 帧） | — | 返回 null，交给系统 | 取设备最高（`display_mode.dart:146`）；24 帧唯一的整数倍 120，空闲也取它 |
| 不播放、要高刷 | 窗口提示最高 | 同 3.x | Android 16+ 画面声明 `AT_LEAST` 最高、窗口提示清零；8～15 照旧 |
| 被系统压在 60 Hz | 用户不知道 | 同 3.x | `DisplayMode.limited`（`:171` 起，`limitDelay` 3 秒 `:179`）；设置“界面刷新率”下面黄色提示（`features/settings/settings_editors.dart:901` 的 `RefreshRateTile`），省电档不显示 |
| 投票方式 | 数值 | 数值 | 不变，加了防回退的测试（清单没有 `appCategory`/`isGame`，Kotlin 没有帧率类别） |
| 档位说明文字 | 3.x 原文 | 被 `00f5edf18` 当作没用的键删掉，对话框显示键名 | 恢复 3.x 原文，代码里写完整键名 |

## 结果

- 改动（提交 `584da6662`，2026-10-02，“feat(display): one frame-rate declaration while playing; tell when held at 60 Hz (P01)”）：
  - c1 R1：`MainActivity.kt` 的 `applyPreferredDisplayMode` + `applyVideoFrameRate` 合成 `applyRefreshRate` + `applySurfaceFrameRate`，通道 `setHighRefreshRate {enabled, frameRate?, refreshRate?}`，去掉 `setVideoFrameRate`；`display_mode.dart` 的 `_applyRate` 一次调用。
  - c2 R2：`playbackRefreshRate` 不再返回 null，没有整数倍取最高；均衡空闲没有 ≤60 的整数倍时取最低的整数倍；换显示器时重新选。
  - c3 R3：`DisplayMode.limited`（全局指针事件、3 秒计时、再读一次确认）和设置里的提示（`settings_refresh_rate_limited`，带 `{rate}`）。
  - c4 R4、R6：防回退的测试。
  - c5：R02.1 README 加“4.0.x 修订”一节。
- 偏差（详见记录）：限制检测只在用户操作时计时（画面静止时系统空闲降频不算限制）；省电档不显示提示；Android 8～11 播放中保留窗口提示；顺带修了档位说明被误删的回归。
- 新设置：无；新翻译键 `settings_refresh_rate_limited`；恢复 `refresh_rate_power_saving_desc`、`refresh_rate_balanced_desc`、`refresh_rate_performance_desc`。
- 测试：新增和改动 20 个（新增 14 个）：`room_refresh_rate_test.dart`（帧率 × 设备模式的表、通道参数）、`platform/display_mode_test.dart`（限制提示、防回退）、`features/settings/refresh_rate_limited_test.dart`（提示的出现和消失、对话框说明文字）；`flutter build apk --debug --target-platform android-arm64` 编译通过。

## 性能任务：测量

| 指标 | 改之前 | 目标或结果 | 怎么测 |
|---|---|---|---|
| 均衡档播 60 帧、拖面板时的刷新率 | 靠系统触摸加速（K90 1.5 秒） | 100 毫秒内到 120，松手约 1.5 秒回 60 | 开发者选项“显示刷新率”；`dumpsys SurfaceFlinger` 里 Flutter 那一层的投票（待真机） |
| 均衡档播 25/50 帧、不操作 | 系统选（多半 60） | 120 | 同上（待真机） |
| 限制提示 | 没有 | 系统刷新率“标准”时出现，“高”时消失 | 设置页（待真机） |
| 耗电 | — | 省电档不高于 3.x；均衡档看 24/25/50 帧会更耗电（已知代价） | R05.1 |

## 验证

- 自动测试：`cd apps/pure_live && flutter test test/features/live_play/room_refresh_rate_test.dart test/platform/display_mode_test.dart test/features/settings/refresh_rate_limited_test.dart`。Kotlin 没有单元测试。
- 真机：**待真机**，步骤见 [verify.md](verify.md)（均衡档 60 帧拖面板、24/25/50 帧、不播放的页面、限制提示、对话框文字、HyperOS 的场景限制）。

## 留下的问题

- 记录“需要维护者决定的”：144/165 Hz 屏上 25/50 帧空闲时一直用 144/165（更耗电），要不要改成“空闲时没有整数倍取不超过 120 的最高”（K90 不受影响）；限制检测只在操作时计时；恢复的三条说明用 3.x 原文。
- 记录的真机步骤提到“面板‘统计信息’里能看到帧率”，4.x 没有这个面板；verify.md 改用 `dumpsys SurfaceFlinger` 看视频帧率。
- specs/UI.md 第 9.1 节的写法（“Android 11 起”“25/50 帧选 50 或 100 赫兹”）和 D-010、实现不一致，需要维护者改规范。
