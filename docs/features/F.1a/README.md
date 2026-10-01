# F.1a 屏幕常亮跟随设置

- 状态：未开始
- 档位：必须；规模：小
- 功能点：F-ROOM-13（见 [INVENTORY.md](../INVENTORY.md)）
- 涉及代码：`features/live_play/`、`features/multiview/`、`packages/live_player`（`lib/src/video_view.dart`）
- 依赖：—
- 来源：M13.3“留给后续”、M13.17 任务说明第 8 项
- 评审页：按授权直接开发（只把 v3 的行为补回来）
- 记录：[records/F.1a.md](../records/F.1a.md)（开发后）

## 要做的

| 功能点 | v3 | v4 现在 | 要做到 |
|---|---|---|---|
| F-ROOM-13 | 进直播间按设置开或关常亮，设置改动立即生效，离开时关掉（`modules/live_play/controllers/live_play_controller.dart:177`、`:252`；`video_controller.dart:494`、`:1527`） | `Settings.enableScreenKeepOn` 没人读；`LiveVideoView` 用 media_kit `Video` 默认的 `wakelock: true`，所以总是常亮 | 关掉设置时不常亮；开着时只在直播间、多画面、应用内小窗播放期间常亮，离开后恢复 |

## 改动清单

| 编号 | 类型 | 内容 | 对应 |
|---|---|---|---|
| c1 | 修复 | `LiveVideoView` 不再用 media_kit 自带的常亮（加参数，默认保持现在的行为，免得别处变化） | F-ROOM-13 |
| c2 | 修复 | 直播间、多画面按 `enableScreenKeepOn` 开关常亮，设置改动立即生效，离开时关 | F-ROOM-13 |

## 测试和验证

- 组件测试：设置关时不请求常亮；开时进房请求、离开时释放；改设置立即生效（常亮用可替换的接口）。
- K90：TASKS 第 5 节 5.1 第 7 条。

## 经过

| 日期 | 内容 |
|---|---|
| 2026-10-02 | 建立（第 1 版清点） |
