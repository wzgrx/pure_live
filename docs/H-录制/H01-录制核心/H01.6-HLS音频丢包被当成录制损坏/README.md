# H01.6 HLS 直播的音频丢包被当成录制损坏，一直拿不到 MP4

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能
- 来源：2026-10-08 K90 复测 H01.5（S02.5 记录）
- 相关：[H01.5](../H01.5-主播下播后不再无限快速重试/README.md)（停止时尾部丢包不再算损坏）

## 目标

YY（以及其他用 HLS 录制的平台）录完能正常合成 MP4；真正损坏的录制仍然保留原始分段。

## 3.x 和现状

| 方面 | 现在 | 要做到 |
|---|---|---|
| K90 实测 | YY “小颖儿”（`mobile-hls:4000`，`sslproxy.yy.com:4443/livesystem/…m3u8`）录 45～70 秒后停止：任务“录制失败 · Recorded input is damaged”，只有 `.ts` 和 `.csv`，没有 MP4；`.ts` 本身完好（ffprobe、ffmpeg 解码无错）。删掉任务重新录一样 | 合成 MP4 |
| 根因 | 电脑上用 ffmpeg 直接读同一个 m3u8 40 秒：每个 HLS 分片边界都有一行 `[mpegts] Packet corrupt (stream = 1, dts = …), dropping it.`（stream 1 是音频，约每 2 秒一次）。`packages/live_record/lib/src/ffmpeg.dart:335-345` 的 `hasPacketError` 把它算成损坏；`capture.dart:228-237` 在录制中（不是停止后）见到就置 `_packetError`；`merge.dart:91` 有损坏就直接拒绝合并（`MergeFailure.inputIntegrity`）；`recorder.dart:886-893` 显示“Recorded input is damaged” | 分片边界上偶尔丢掉的音频包不算损坏 |
| 3.x | 3.x 也有同样的“输入损坏”标记（`recorder_controller.dart:306`、`:522`），但 3.x 用自己的中继读流 | — |

## 方案（按 D-003 由维护者定）

- c1：合并不再因为录制中有丢包就拒绝：`damaged` 时照常合并，但**保留原始分段**（不删 `.ts`），任务显示“录制时丢弃了少量损坏的数据包，原始分段保留在文件夹里”（新翻译键）。合并本身失败时照旧报失败。
- c2：`hasPacketError` 区分“偶尔的音频丢包”（不影响画面）和视频损坏：只有视频流（stream 0）或持续大量的音频丢包才置损坏标记；音频偶发的只计数，写进诊断。
- 先写失败的测试：假 FFmpeg 在录制中每秒输出一行 `Packet corrupt (stream = 1, …)`，停止后应得到 MP4、任务“已停止”。

## 验证

- 自动测试：`packages/live_record/test/recorder_test.dart`（“a damaged attempt keeps its source and fails the join”这一条要按新规则改：视频损坏仍保留分段，但能合并时照样合并）。
- 真机：K90 YY 直播间录 1 分钟停止，得到 MP4；哔哩哔哩录制照旧。
