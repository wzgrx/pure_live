# H01.7 映客录制默认录 HEVC：记录

- 日期：2026-10-08
- 执行者：Claude
- 分支和提交：本机工作区 `ai/H01.7`（从 master `fbc6e6385` 开始）
- 任务书：[brief.md](brief.md)；设计或说明：[README.md](README.md)

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| 验收 1～4 | 做了 | `orderQualities(preferH264:)` + `_avoidHevc`；`RecordSettings.preferH264` 默认开（同 `Settings.preferH264`）；录制器三处 `resolve` 传 `task.qualityOverride == null && settings().preferH264` |
| 验收 5 | 做了 | `recordDefaultQuality(…, preferH264:)`，面板的 `_View` 带上设置值 |

## 根因

见 README“3.x 和现状”：录制排序不看编码，名字一匹配就把 HEVC 的“原画”放第一。

## 测试

- `recorder_test.dart` 新增 2 个：“优先 H.264 passes over an HEVC quality…”（映客两档、按位置落在 HEVC、只有 HEVC）、“the recorder honours 优先 H.264…”（开着选网宿 H.264 线路，关着选即构）。改之前编译失败（没有 `preferH264` 参数）。
- `live_play_popups_test.dart` 加了面板默认档的断言。
- `dart test`（live_record）、`flutter test test/features/live_play/live_play_popups_test.dart test/features/recorder` 全过；analyze 无问题。

## 真机

待 K90：见 README“验证”。

## K90 复查（2026-10-08，master 820129343）

- 映客“可可”（有原画）：录制面板“这次录制”默认选中 FLV ✓；录 35 秒停止，MP4 是 H.264 720×1280 + AAC ✓。
