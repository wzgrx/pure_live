# H01.6 HLS 直播的音频丢包被当成录制损坏：任务书

## 背景

- 来源：2026-10-08 K90 复测 H01.5：YY 直播间录完一直“录制失败 · Recorded input is damaged”，没有 MP4（删掉任务重录也一样）。根因和证据见本文件夹 README 的“3.x 和现状”。
- 为什么是第一档：YY（以及可能其他 HLS 录制的平台）录制完全拿不到 MP4。

## 目标和验收

1. 录制中出现音频（stream 1）的偶发 `Packet corrupt` 时，停止后合成 MP4，任务“已停止”。
2. 视频（stream 0）损坏或大量丢包时，仍然合并（能合并就合并），但保留原始分段，卡片写“录制时丢弃了少量损坏的数据包，原始分段保留在文件夹里”。
3. 合并本身失败时照旧失败、保留分段。
4. H01.5 的“停止后尾部丢包”规则不变。
5. 诊断（查看原因）里能看到丢包次数。

## 现状（读代码得出，写文件:行）

- `packages/live_record/lib/src/ffmpeg.dart:335-345`（`hasPacketError`）、`:348-` （`hasError`）。
- `packages/live_record/lib/src/capture.dart:225-245`（`_log`：录制中置 `_packetError`，停止后置 `_tailDiscarded`）、`:308-346`（结果里的 `inputIntegrityError`）。
- `packages/live_record/lib/src/merge.dart:85-91`（`damaged` 直接返回 `MergeFailure.inputIntegrity`）。
- `packages/live_record/lib/src/recorder.dart:850-893`（合并和 `_markMergeFailure`）。
- 界面文字：`apps/pure_live/lib/features/recorder/recorder_texts.dart`。

## 3.x 基线

- `git show v3.2.11:lib/recorder/pages/recorder/recorder_controller.dart`（`:306`、`:522` 的 `inputIntegrityError`），对照 3.x 遇到损坏时是否合并。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5、8、14 节）。
2. 本文件夹的 `README.md`；`docs/H-录制/H01-录制核心/H01.5-主播下播后不再无限快速重试/record.md`。

## 范围

- 可以改：`packages/live_record`（上面列的文件和测试）、`recorder_texts.dart`、翻译文件（zh、en）。
- 不能改：录制的取流和画质选择；文件命名和目录。

## 方案和阶段

| 阶段 | 做什么 | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | c1、c2 | `ffmpeg.dart`、`capture.dart`、`merge.dart`、`recorder.dart`、文字、测试 | 验收 1～5 |

## 测试

- 假 FFmpeg 在录制中输出 `[mpegts @ 0x1] Packet corrupt (stream = 1, dts = 1), dropping it.` 若干行 → 停止后 MP4、`lastError` 为空。
- 输出 `stream = 0` 的损坏 → 合并成功但分段保留、任务带“丢弃了损坏的数据包”的标记。
- 合并失败的路径不变。定时器至少 1 秒。

## 真机验证（K90）

| 步骤 | 期望 |
|---|---|
| 1. YY 直播间（HLS）录 1 分钟，停止 | “已停止”，文件夹里有 MP4 |
| 2. 哔哩哔哩直播间录 1 分钟，停止 | 照旧有 MP4 |

## 风险和注意

- 保留分段会多占一份空间，只在真有视频损坏时保留。

## 环境和提交

- `source ~/tools/purelive-env.sh`；分支 `ai/H01.6`；提交以 `[H01.6]` 开头；不推 master。

## 停下时

照 `docs/PROCESS.md` 第 5.2 节。

## 报告（中文，简洁）

每条验收；改了哪些文件；测试数量；要在真机上看的。
