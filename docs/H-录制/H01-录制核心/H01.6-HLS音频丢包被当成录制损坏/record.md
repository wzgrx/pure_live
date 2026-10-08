# H01.6 HLS 直播的音频丢包被当成录制损坏，一直拿不到 MP4：记录

- 日期：2026-10-08
- 执行者：Claude
- 分支和提交：本机工作区 `ai/H01.6`（从 master `8277d272e` 开始）
- 任务书：[brief.md](brief.md)；设计或说明：[README.md](README.md)

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| c1 有损坏也照常合并、保留原始分段 | 做了 | `merge.dart`：去掉 `damaged` 时直接拒绝；`damaged` 时合并成功也不删 `.ts`。任务新字段 `inputDamagedKept`（只在为真时写进 JSON，3.x 照常读），录制中心卡片的提醒行加一句“录制时有少量数据包损坏，MP4 已照常合成；原始分段也留在录制文件夹里，可对照检查。”（新键 `recorder_input_damaged_kept`）。`MergeFailure.inputIntegrity` 不再用到，删了。合并本身失败照旧报“ffmpeg.inputIntegrity / Recorded input is damaged” |
| c2 音频偶发丢包不算损坏 | 做了，有偏差 | 不按流编号（stream 0/1）猜，而是读 FFmpeg 开头的输入描述（`Stream #0:1[0x101]: Audio: …`，FFmpeg Kit 分几次回调送来，`capture.dart` 先拼起来）记下哪些是音频流；`Packet corrupt (stream = N` 的 N 是音频流就不算损坏。没做“持续大量音频丢包也算损坏”：丢的包已被 `discardcorrupt` 扔掉，写进文件的都是好包，最多是一段没声音，标成损坏只会多留一份分段；也没写计数（目前没有地方显示） |
| 先写失败的测试 | 做了 | 见下 |

## 根因

见 [README.md](README.md)“3.x 和现状”：YY 的 HLS 每个分片边界有一个音频包被 FFmpeg 报 `Packet corrupt … dropping it`，录制中见到就置损坏，合并直接拒绝。

## 测试

- `packages/live_record/test/recorder_test.dart`：
  - “a damaged attempt is joined and keeps its source (H01.6)”（原“…fails the join”）：视频 `Packet corrupt (stream = 0…)` → 停止后有 MP4、任务已停止、`inputDamagedKept`、`.ts` 还在。
  - “HLS audio drops at segment boundaries are not damage”：分段送来的输入描述（视频 #0:0、音频 #0:1，再到 `Output #0`）后 5 行 `[mpegts] Packet corrupt (stream = 1, …), dropping it.` → MP4、无错误、`.ts` 已删。
  - `dart test`：59 条全过；`dart analyze` 无问题。
- `apps/pure_live/test/features/recorder/recorder_centre_test.dart`：已保存卡片显示新提醒；`flutter test test/features/recorder test/shared` 85 条全过。

## 真机

待 K90：YY 直播间录 1 分钟停止，得到 MP4；哔哩哔哩录制照旧。
