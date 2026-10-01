# F.3a 录制合并进度

- 状态：未开始
- 档位：可以以后；规模：小
- 功能点：F-REC-13（见 [INVENTORY.md](../INVENTORY.md)）
- 涉及代码：`packages/live_record`（`merge.dart` 加进度事件）、`features/recorder/`、`features/live_play/record/record_panel.dart`
- 依赖：U.7b（录制设置）合并后
- 来源：M8“留给后续”（`mergeProgress`）
- 评审页：按授权直接开发（界面照 U.2f 录制面板“整理文件”、U.7a）
- 记录：[records/F.3a.md](../records/F.3a.md)（开发后）

## 要做的

| 功能点 | v3 | v4 现在 | 要做到 |
|---|---|---|---|
| F-REC-13 | 合成 MP4 时发进度事件，界面显示百分比（`recorder/services/video_processor_service.dart:26`） | 合并时只显示“处理中” | 按 FFmpeg 的统计时间 / 总时长给出进度，录制中心和录制面板显示 |

## 测试和验证

- `live_record` 测试：假 FFmpeg 统计推出进度，单调、到 100%。
- K90：TASKS 第 5 节 5.3 第 1 条停止后看进度。

## 经过

| 日期 | 内容 |
|---|---|
| 2026-10-02 | 建立（第 1 版清点） |
