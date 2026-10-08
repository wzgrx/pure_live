# H01.7 映客录制默认录 HEVC：任务书

## 背景

- 来源：G01.3 记录“录制选档”。录制偏好默认“原画”，映客“原画”只有 HEVC（FLV 里 codec 12），录下来的文件别的播放器打不开。
- 为什么是第二档：只影响映客等少数有 HEVC 档的平台，能手动换清晰度绕开。

## 目标和验收

1. 开着“优先 H.264”、任务没指定清晰度：映客录 FLV（H.264）。
2. 关着：照旧录“原画”。
3. 面板手动选了“原画”：录 HEVC。
4. 房间只有 HEVC 档：照录。
5. 录制面板“这次录制”默认显示的档和实际录的一致。

## 现状

- `packages/live_record/lib/src/resolver.dart:296-324`（`orderQualities`）、`recorder.dart` 三处 `resolver.resolve`、`settings.dart`（`RecordSettings`）。
- `apps/pure_live/lib/app/recording.dart:261`（`RecordSettings.of`）、`lib/shared/record/record_state.dart:94`、`lib/features/live_play/record/record_panel.dart:359`。

## 范围

- 可以改：上面列的文件和测试。
- 不能改：播放选档（G01.3 已做）；平台适配器的编码提示。

## 方案和阶段

| 阶段 | 做什么 | 怎么算做完 |
|---|---|---|
| 1 | 先写失败的测试，再改排序和录制器 | `dart test` 通过 |
| 2 | 面板默认档 | `flutter test` 通过 |
