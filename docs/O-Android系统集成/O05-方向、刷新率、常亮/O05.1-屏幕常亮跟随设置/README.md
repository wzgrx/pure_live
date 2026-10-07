# O05.1 屏幕常亮跟随设置

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)（下面“档位：必须”是当时旧任务表的写法）
- 类型：功能
- 旧编号：F.1a、T13e.1
- 相关：决定 D-018（`enableScreenKeepOn` 键不变）；C01.1（当时把常亮交给了 media_kit）；真机归 [S02.6](../../../S-质量和验证/S02-真机验证/S02.6-K90补验/README.md) 第 1 阶段（原来归 C01.3，按 D-029 转过去）
- 档位：必须；规模：小
- 功能点：F-ROOM-13（见 [inventory/FEATURES.md](../../../inventory/FEATURES.md)）
- 涉及代码：`features/live_play/`（直播间、应用内小窗）、`packages/live_player`（`lib/src/video_view.dart`）
- 依赖：—
- 来源：C01.1“留给后续”、M13.17 任务说明第 8 项
- 评审页：按授权直接开发（只把 v3 的行为补回来）
- 记录：[record.md](record.md)

## v3 的行为（`~/ref/v3ref`，v3.2.11）

| 行为 | 位置 |
|---|---|
| 进直播间按“屏幕常亮”开或关常亮，设置改动立即生效 | `modules/live_play/controllers/live_play_controller.dart:177-179`、`:252-260` |
| 播放器建立时设置开着就常亮，播放器销毁时关掉 | `modules/live_play/controllers/player_controller.dart:441`、`:530`；`widgets/video_player/video_controller.dart:494`、`:1527` |

## v4 现在

- `Settings.enableScreenKeepOn`（`packages/live_store/lib/src/settings/settings.dart:33`，默认开）没人读。
- `LiveVideoView` 用 media_kit `Video` 默认的 `wakelock: true`（`packages/live_player/lib/src/video_view.dart:99-105`；`third_party/media_kit_video/lib/src/video/video_texture.dart:128`、`:327-341`）：播放时一直常亮，设置关了也一样。

## 差别和根因

| 编号 | 差别 | 根因 |
|---|---|---|
| P1 | 关掉“屏幕常亮”后看直播仍不灭屏 | 常亮交给了 media_kit 的默认值，搬直播间（C01.1）时没接设置 |
| P2 | 设置改了也不会立即生效 | media_kit 的 `Video` 只在建立时读 `wakelock`（`video_texture.dart:233-268` 不处理它） |

## 要做的改动

| 编号 | 类型 | 内容 | 对应 |
|---|---|---|---|
| c1 | 修复 | `LiveVideoView` 自己管常亮（加参数 `keepScreenOn`，默认开 = 现在的行为：播放时常亮），不再用 media_kit 自带的；全应用一个计数，几个画面不会互相关掉 | P1、P2 |
| c2 | 修复 | 直播间、应用内小窗按 `enableScreenKeepOn` 传，设置改动立即生效，离开（画面销毁）时释放 | P1、P2 |

多画面（`features/multiview/`）、电视不在本任务的目录，保持默认（播放时常亮），见记录。

## 需要选的

无。和 v3 的一处小差别：v3 在直播间里一直常亮（暂停也亮）；这里照 media_kit 现在的做法，只在播放时常亮，暂停后按系统超时灭屏（TASKS 第 5 节 5.1 第 7 条的预期不受影响）。

## 测试和验证

- 组件测试（`packages/live_player`）：设置关时不请求常亮；开时播放才请求、暂停和销毁时释放；参数改动立即生效；两个画面共用一个计数。
- 组件测试（直播间）：设置关 → 直播间的画面不常亮。
- K90：TASKS 第 5 节 5.1 第 7 条。

## 风险和性能

- 没有新常驻任务；常亮由同一个插件（wakelock_plus）完成。
- 3.x 的键 `enableScreenKeepOn` 不变。

## 经过

| 日期 | 内容 |
|---|---|
| 2026-10-02 | 建立（第 1 版清点） |
| 2026-10-02 | 写功能对比 |
| 2026-10-02 | 开发完成（LiveVideoView 自己管常亮，直播间和应用内小窗按设置），待 K90 验证 |

## 结果

- 提交：合并 `b8462638a`（2026-10-02）；逐条见 [record.md](record.md)。c1、c2 都做到，没有偏差。
- 现在的位置：`packages/live_player/lib/src/screen_wake.dart`（新，`ScreenWake` 全应用计数，`WakelockPlus.toggle`）；`packages/live_player/lib/src/video_view.dart`（`keepScreenOn` :28、`_syncWake` :77：播放或缓冲时才请求，media_kit `Video` 自带的常亮关掉）；`packages/live_player/pubspec.yaml` 加 `wakelock_plus`；直播间 `apps/pure_live/lib/features/live_play/player/player_view.dart:503-516`、应用内小窗 `mini/floating_window.dart:187` 传 `enableScreenKeepOn`。
- 没有新设置、没有新翻译键。
- 测试：`packages/live_player/test/frame_rate_test.dart` 2 个（:102 关时不请求、开时立即请求、销毁释放；:118 两个画面一个计数、暂停释放）；`apps/pure_live/test/features/live_play/live_play_page_test.dart` 1 个（:439，设置关了不请求，再开立即请求，离开释放）。

## 验证

- 自动测试：上面 3 个。
- 真机：**没有结果**。登记表是“完成”，但记录写明 K90 没看（CHECKLIST 第 1 节第 7 条：开时播放 3 分钟不灭屏，关时按系统超时灭屏）；V03.3 把清点 F-ROOM-13 改成“没验证”，归 S02.6 第 1 阶段（原来归 C01.3，C01.3 按 D-029 改“不做”）。看的时候可以用 `adb shell dumpsys power | grep -i -A2 wake` 确认应用持有的唤醒锁，系统超时先临时改成 30 秒（`adb shell settings put system screen_off_timeout 30000`，测完改回原值）。

## 留下的问题

- 真机没看：S02.6 第 1 阶段。
- 多画面（`features/multiview/widgets/cell_view.dart`）、电视（`tv/room/tv_live_play_page.dart`）没传 `keepScreenOn`，播放时总是常亮、不看设置：没有任务，要跟设置时各加一个参数。
- 和 3.x 的差别（确认过）：暂停后不常亮。

