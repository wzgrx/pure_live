# O05.1 屏幕常亮跟随设置

- 状态：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 档位：必须；规模：小
- 功能点：F-ROOM-13（见 [inventory/FEATURES.md](../../../inventory/FEATURES.md)）
- 涉及代码：`features/live_play/`（直播间、应用内小窗）、`packages/live_player`（`lib/src/video_view.dart`）
- 依赖：—
- 来源：C01.1“留给后续”、M13.17 任务说明第 8 项
- 评审页：按授权直接开发（只把 v3 的行为补回来）
- 记录：[records/F.1a.md](record.md)（开发后）

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
