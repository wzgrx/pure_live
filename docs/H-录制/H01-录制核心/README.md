# H01 录制核心

`packages/live_record` 里一次录制从选流到 MP4 的全部逻辑：选流、开输入、FFmpeg 写分段、断线重连、合成 MP4、录弹幕 XML。纯 Dart，不依赖 Flutter，FFmpeg、保活和存储权限由应用注入。

## 范围

- 包括：任务模型和 3.x 任务 JSON（`task.dart`）、选流和续签（`resolver.dart`）、开输入（`input.dart`）、FFmpeg 参数和失败分类（`ffmpeg.dart`）、一次录制的事件（`capture.dart`）、分段日志和命名（`segments.dart`、`naming.dart`）、合并和合并进度（`merge.dart`）、重试和租期的时间（`policy.dart`）、文件大小和码率（`metrics.dart`）、诊断脱敏（`diagnostics.dart`）、录制弹幕（`chat.dart`），以及 `recorder.dart` 里一次尝试、结束、重连、合并的部分。
- 不包括（归哪里）：录制设置的默认值和录制目录（`settings.dart`、`storage.dart`）在 H03；排队、开播检测、开播自动录、启动时恢复（`scheduler.dart`、`recorder.dart` 的 `_schedulePoll`、`monitorTask`、`restore`）在 H04；应用接线、FFmpegKit、前台服务在 H02；通知在 H05；中继和 HLS 窗口本身在 G01（`packages/live_media`）；平台的取流接口在 E。

## 现状：做到哪、怎么工作的

- 用户看得到的：点录制后卡片“准备中” → 收到第一批数据变“录制中”（计时、大小、码率、第几段）→ 停止后“正在整理文件 42%”→“已保存”。CDN 断开（EOF）时静默变“重连中 · 第 N 次”，2 秒后用新地址开新的尝试；每次尝试是一个单独的目录和 MP4（`<根>/<平台>/<主播>/<yyyy-MM-dd>/<HH-mm-ss>/<yyyyMMdd_HHmmss_SSS>.mp4`），开了“同时录制弹幕”旁边有同名 `.xml`。会切断连接的租期（斗鱼 FLV、CHZZK、PandaTV 的 HLS）在中继里续签，不新开尝试。
- 内部怎么走：

```text
Recorder.startTask → _start → RecordScheduler.enqueue → _run（recorder.dart:377）
  RecordStreamResolver.resolve：房间详情 → 清晰度排序 → 只解析这一档的线路
  → attemptDirectory 建目录（:418-428）→ SegmentReservation 占前缀
  → RecordInputOpener.open：HTTP(S) 的 FLV/HLS 走 LoopbackRelay（HLS 带预取窗口），配方走 RecipeOpener，RTMP 等直连
  → FfmpegCommand.record → RecordCapture.start：Acknowledged → Started → Progress… → Ended
  → _onCapture(CaptureEnded)（:607-642）→ _finalize → _queueCurrentAttempt 记为待合并
       ├ 失败、可重试、开了自动重连 → _scheduleReconnect（:896-933）：EOF/403/404 走快速档 2～15 秒，其他按设置
       └ 会话结束（停止、重试用完、失败）→ _mergePending → 每个尝试 RecordMerger.merge → MP4
```

- 完成度：照 3.x 的有 FFmpeg 参数逐条一致、失败分类的关键词和顺序、clock-v1 分段日志和 concat 清单、只合并本次尝试的文件、`.partial` 改名才算提交、损坏的尝试保留源文件、任务 JSON schema 9、CDN 断开快速重连、录满 10 秒清零重试次数。确认过的改动：续期在中继里做、不再新开 FFmpeg（H01.1 问题 1）；录制按平台实际返回的清晰度记、受限时提示一次（H01.3）；合并进度（H01.3）；弹幕 XML 每 2 秒重写结尾、随时是完整文件（H01.2）。还缺的：下播后的重试上限和空分段（H01.5）。

## 代码地图

| 文件 | 职责 |
|---|---|
| `packages/live_record/lib/live_record.dart` | 导出下面 16 个文件 |
| `lib/src/task.dart`（647 行） | `RecordStatus`（9 种，值顺序是 3.x 存的下标，`order` 是录制中心“全部”的排序）、`RecordTask`（3.x `LiveRecordTask`，可变；`beginNewRecording` 清会话、`beginNewAttempt` 只换尝试、`queuePendingAttempt`/`removePendingAttempt`、`markFailure`、`toJson` 不写签名地址）、`PendingRecordingAttempt`（目录 + 前缀 + 损坏标记）、`recordingPrefixOf` |
| `lib/src/resolver.dart`（431） | `RecordStreamResolver.resolve`：严格的房间详情 → 清晰度按平台排序、把最接近“默认清晰度”的一档放最前 → 只解析需要的那一档；续签同线路，失败换线路再换清晰度；`servedQuality` 按平台实际返回的编号命名（H01.3）；`RecordStreamException` 九种类型（`notLive`、`restricted`……）和是否可重试 |
| `lib/src/input.dart`（141） | `RecordInputOpener.open`：HTTP(S) 的 FLV、HLS 一律套 `live_media` 的 `LoopbackRelay`（HLS 打开 `HlsPrefetchOptions`），会切断连接的租期在中继里续签，配方（Bigo、FC2、niconico）每次录制各开各的授权，其他协议直连并带请求头和代理 |
| `lib/src/ffmpeg.dart`（370） | 注入接口 `FfmpegRunner`/`FfmpegExecution`/`FfmpegStatistics`；`FfmpegCommand.record`（`-f segment`、`-segment_list` CSV、`flush_packets=1:…:output_ts_offset=1.4`、只对网络错误和 5xx 重连）和 `merge`（`-xerror`、`+faststart`）；`classifyFfmpegFailure`（`FfmpegFailureKind` 13 种）；`FfmpegMediaIntegrity`；`normalizeLiveRecordedSeconds` |
| `lib/src/capture.dart`（331） | `RecordCapture`：一次 FFmpeg 会话的密封事件；返回 0 或 EOF 当作 CDN 断开（`unexpectedEof`，静默、可重试）；`refreshesSignedStream`（:103-106）把 `leaseRefresh`、`unexpectedEof`、`httpAccess` 都算“换新地址能好”；停止先关输入、5 秒没排空再取消；日志留最后 120 行并脱敏；HLS 漏段标“有缺口” |
| `lib/src/segments.dart`（184） | `SegmentClock`：clock-v1 日志校验（每段一行、名字按序、起点从 0 严格递增，任何不符都报错，:19-46）和 concat 清单；`legacyConcatManifest`（3.x 旧分段）；`selectAttemptSegments`（只选本次前缀）；`SegmentReservation`（同一前缀只允许一个写入者） |
| `lib/src/merge.dart`（228） | `RecordMerger.merge`：损坏的尝试直接拒绝；列出 `.ts`（0 字节的 clock-v1 分段特意留下，让日志校验失败，:88-90）；有 0 字节分段就报 `segmentClock`（:105-107）；写 `.partial`，FFmpeg 正常退出、日志无损坏、文件非空才改名并删分段和日志；`mergeProgress`、`mergeTimeout`（30 秒～1 小时） |
| `lib/src/policy.dart`（61） | `RecordPolicy`：开播检测间隔和退避、重连间隔（EOF 2 秒起、最多 15 秒）、`shouldEnterPollingAfterRetryLimit`（:37-41，EOF 永远不进等开播）、租期预取时间 |
| `lib/src/metrics.dart`（110） | `SegmentMeter`（读分段文件算大小，只看当前和下一段）、`hasSegments`（有非空分段才记为待合并）、`BitrateWindow`（5 秒窗口码率）、`reconcileFinalizedBytes` |
| `lib/src/naming.dart`（44） | `safePathComponent`、`safePinyinComponent`（拼音目录）、`attemptDirectory`（`<平台>/<主播>/<日期>/<时间>`） |
| `lib/src/diagnostics.dart`（38） | `sanitizeRecordDiagnostic`、`sanitizeFfmpegLog`：去掉媒体地址、Cookie、签名参数 |
| `lib/src/chat.dart`（646） | `RecordChatRecorder` 只看 `Recorder.changes`：录制中的任务保持一个弹幕连接，每次尝试写一个同名 B 站 XML（`RecordChatWriter`，每 2 秒写入并重写 `</i>`）；开了“录制弹幕时包含礼物”时同一个文件里也有录播姬格式的 `<gift>`（连击一条，规则是 `live_core` 的 `live_gift_combo.dart`）和 `<sc>`（H01.8）；连接器是接口 `RecordChatConnector`，应用用 `live_danmaku` 实现 |
| `lib/src/recorder.dart`（1362） | `Recorder`：任务、一次尝试（`_run` :377-537）、事件处理（`_onCapture` :562-644）、结束和重连（`_doFinalize` :713-769、`_scheduleReconnect` :896-933）、合并（`_mergePending` :821-839、`_mergeAttempts` :841-885）、租期预取（:935-979）、停止和删除、持久化（2 秒合并写一次）；`RecordNotice` 四种提示 |

测试（`packages/live_record/test/`，`dart test`，共 43 个）：

| 测试文件 | 覆盖什么 |
|---|---|
| `task_test.dart`（8） | 3.x JSON 读写、签名地址不落盘、待合并去重和损坏标记、会话和尝试、排序、设置规整、路径名 |
| `ffmpeg_test.dart`（8） | 录制参数、协议选项、失败分类、时间纠偏、分段日志、只合并本次尝试、前缀预留、重试和租期时间（:111-137） |
| `recorder_test.dart`（14） | 选流 5 个；FLV/HLS 走中继、RTMP 直连；录制→停止→合并；EOF 快速重连后两段都合并（:194-208）；未开播转等待；损坏保留源文件；恢复；直播间的清晰度只给这个任务；开播自动录；并发上限排队 |
| `applied_quality_test.dart`（6） | 清晰度标签和画质受限提示（H01.3） |
| `merge_progress_test.dart`（3） | 合并进度公式、单调、到 100%、不进 JSON |
| `chat_test.dart`（4） | XML 随时完整、一次尝试一个文件、重连间隙不写、关闭和重连 |
| `chat_gifts_test.dart`（10） | H01.8：开关关时和以前逐字一样；`<gift>`、`<sc>` 的格式、转义、连击、`COMBO_SEND`、时间顺序、30 秒分段、20 分钟忙直播间的性能 |
| `support/fakes.dart` | `FakeSite`、`FakeFfmpeg`（录制写一个 1000 字节分段和一行日志，合并写 `mp4`） |

## 3.x 基线

- 3.x 的录制在 `lib/recorder/`（约 14200 行），内核散在 `services/` 和 `pages/recorder/recorder_controller.dart`（1763 行）里。对应关系逐行列在 [H01.1 的记录](H01.1-录制内核/record.md)“对照”一节。
- 要保留的行为：`services/ffmpeg_service.dart:51` 起的单次会话（EOF 静默重连）；`services/recorder_continuation_policy.dart:76-83` 的重试上限（3.x 同样对 EOF 豁免，见 H01.5）；`pages/recorder/recorder_controller.dart:227-229` 录满 10 秒清零重试、`:270-290` EOF/403/404 进快速档、`:1202-1235` `_scheduleReconnect`；`services/recording_segment_clock.dart` 的 clock-v1；`services/video_processor_service.dart:139`（非 clock 的 0 字节分段跳过）、`:170`（clock 的 0 字节分段报错）、`:222-233` 合并进度事件（3.x 界面没接）。
- 3.x 的录制没有对应的操作习惯条目（[specs/UI.md](../../specs/UI.md) 附录 A 不涉及录制）。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 下播后 EOF、403、404 永远走快速重试，不计上限 | `policy.dart:37-41`；`capture.dart:103-106`；`recorder.dart:620-622`、`:901-905` | 录制中心一直“重连中”，每 2 秒新建一个尝试目录、敲一次 CDN | [H01.5](H01.5-主播下播后不再无限快速重试/README.md) 阶段 1 |
| 重试用完转“等待开播”时不合并已录的尝试 | `recorder.dart:906-914` | 下播后看不到 MP4，要等下一场结束或手动停止 | H01.5 阶段 1 |
| 平台说“未开播”时转“等待开播”也不合并；下一场由检测开始时不清待合并，几场的尝试要等用户停止才一起合成 | `recorder.dart:495-501`；3.x `recorder_controller.dart:962-967` 同 | 开着开播自动录的任务一直拿不到 MP4 | H01.5 c3b（2026-10-07 写任务书时发现） |
| `_doFinalize` 的同步前缀里调 `_endSession`（重试用完且下播就结束）时，`rt.finalizing` 先被它填上、又被 `??=` 覆盖、随即清空，合并期间录制器以为没在整理文件 | `recorder.dart:703-710`、`:726-732`、`:906-909` | 合并期间“开始录制”“停止”“检测”不会等合并结束 | H01.5 c3（统一由 `_doFinalize` 自己 `await` 合并） |
| 六间房的录制详情不带弹幕参数 | `packages/live_core/lib/src/sites/sixroom/sixroom_site.dart:416` | 不影响录制弹幕（`recordChatConnector` 用进房详情，`apps/pure_live/lib/app/recording.dart:51`）；影响多画面的六间房格子（N 组） | 本子分类不用改，见[组说明](../README.md)“风险和注意” |
| 一个 0 字节分段让这次尝试合并失败；失败的尝试留在 `pendingAttempts`，之后每一场结束都再失败一次 | `merge.dart:88-90`、`:105-107`；`recorder.dart:864-879`；`task.dart:418-426`（新会话不清待合并） | 那一段录像不出 MP4，任务一直标“文件合并”失败 | H01.5 阶段 2 |
| 合并失败的说明是英文 | `recorder.dart:887-894`（`'Joining the recording failed'`）、`features/recorder/recorder_texts.dart:72-90`（`merge` 阶段没有本地化说明） | 卡片写“最近失败（文件合并）：Joining the recording failed” | H01.5 阶段 2 |
| 每次失败的尝试都留下一个目录（目录在开输入之前就建了） | `recorder.dart:418-428` | 重试多时录制目录里一堆空文件夹 | H01.5 阶段 2 |
| 最后一段没写进日志（FFmpeg 被取消、进程被杀）时那次尝试合并失败 | `segments.dart:25` | 不出 MP4，原始分段保留 | 不做：有意 fail closed，宁可留分段也不猜时长（3.x 同） |
| 漏段只靠 FFmpeg 日志判定 | `capture.dart:109-113` | 换 FFmpeg 版本日志变了就认不出 | 不做（H01.2 取舍） |
| `recorder_test.dart` 用了 20 毫秒采样、50 毫秒录制的定时器 | `test/recorder_test.dart:156`、`:197`、`:289` | 和 D-017“测试定时器至少 1 秒”不符 | 下次改这个文件的任务顺手改成按条件等（H01.5 新加的测试照 D-017） |

## 相关决定和规范

- D-017：测试定时器至少 1 秒、不访问真实平台。D-018：3.x 的设置键名和含义不变（任务 JSON 同理不改结构）。D-019：只在测试包上操作。
- 依赖方向：`live_record` 只依赖 `live_core`、`live_media`、`live_net`（`tools/gate/check_deps.py`），不能依赖 `live_danmaku`，所以弹幕连接器是接口。
- [specs/ENGINEERING.md](../../specs/ENGINEERING.md) 第 4 节（分层）、第 7 节（代码规则）。

## 测试和验证

- 自动：`cd packages/live_record && dart test`（43 个，全部用 `FakeFfmpeg`，不跑真 FFmpeg、不联网）。缺的：EOF 重试上限、空分段、重试用完时合并（H01.5 补）；真 FFmpeg 的分段和合并只在真机上验证。
- 真机：[S02 的 CHECKLIST.md](../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 3 节 1～7 条；S02.3 走过第 1 条（5 分 39 秒两段合成，F-REC-03 算验证过）；第 2、3、6、7 条（F-REC-10、06、07、11）没做，归 H01.4。

## 路线

1. H01.5（第一档）：阶段 1 EOF 重试设上限后转等开播，用完时和平台说未开播时都先合并（c3、c3b）；阶段 2 合并跳过尾部空分段、全空的尝试不算失败、清空目录、合并失败说中文。
2. H01.4（第二档）：F-REC-06、07、10、11 四项真机验证，改功能清点；H01.3 留下的两条真机检查建议顺带看。
3. 新想法（例如录制历史页、按大小分段）写进 [V01](../../V-需求和反馈/V01-新功能提议/README.md)，不直接加任务。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [H 录制](../README.md)。

- 代码：`packages/live_record`
- 进度：`████████████████░░░░` 82%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| H01.1 | 录制内核 | 功能 | 完成 | 2026-10-01 | 833e570ce | [设计或说明](H01.1-录制内核/README.md)、[记录](H01.1-录制内核/record.md) |
| H01.2 | 录制补全 | 功能 | 完成 | 2026-10-01 | 8c043873d | [设计或说明](H01.2-录制补全/README.md)、[记录](H01.2-录制补全/record.md) |
| H01.3 | 合并进度：录制中心和录制面板显示合成 MP4 的进度 | 功能 | 完成 | 2026-10-02 | d145aa930 | [设计或说明](H01.3-合并进度/README.md)、[记录](H01.3-合并进度/record.md) |
| H01.4 | 录制的 4 项真机验证：划掉应用后继续录、所有文件访问权限、同时录弹幕 XML、HLS 预取 | 验证 | 未开始 | — | — | [设计或说明](H01.4-录制余项/README.md)、[任务书](H01.4-录制余项/brief.md) |
| H01.5 | 主播下播后不再无限快速重试；正常下播后合并已录分段（开播自动录拿不到 MP4）；合并时跳过 0 字节分段，有一段有效就能合并 | 功能 | 待真机 | 2026-10-08 | b2b62a1f7 | [设计或说明](H01.5-主播下播后不再无限快速重试/README.md)、[任务书](H01.5-主播下播后不再无限快速重试/brief.md)、[记录](H01.5-主播下播后不再无限快速重试/record.md) |
| H01.6 | YY 等 HLS 直播每两秒报一次音频“Packet corrupt”，录制被当成损坏、一直拿不到 MP4 | 功能 | 完成 | 2026-10-08 | — | [设计或说明](H01.6-HLS音频丢包被当成录制损坏/README.md)、[任务书](H01.6-HLS音频丢包被当成录制损坏/brief.md)、[记录](H01.6-HLS音频丢包被当成录制损坏/record.md) |
| H01.7 | 录映客默认录的是 HEVC 的“原画”，不看“优先 H.264” | 功能 | 完成 | 2026-10-08 | — | [设计或说明](H01.7-映客录制默认录HEVC/README.md)、[任务书](H01.7-映客录制默认录HEVC/brief.md)、[记录](H01.7-映客录制默认录HEVC/record.md) |
| H01.8 | 录制的弹幕 XML 带礼物（新开关，默认关） | 功能 | 待真机 | 2026-10-09 | — | [设计或说明](H01.8-弹幕XML带礼物/README.md)、[任务书](H01.8-弹幕XML带礼物/brief.md)、[记录](H01.8-弹幕XML带礼物/record.md)、[真机验证](H01.8-弹幕XML带礼物/verify.md) |

## 还没完成的

- **H01.4 录制的 4 项真机验证：划掉应用后继续录、所有文件访问权限、同时录弹幕 XML、HLS 预取**（未开始，第二档，规模 中）
  - 阶段：划掉应用后继续录和所有文件访问权限 → 弹幕 XML 和 HLS 预取
  - 说明：原来的 1 项缺失（合并进度 F-REC-13）已由 H01.3 做完；剩下 F-REC-06、F-REC-07、F-REC-10、F-REC-11（CHECKLIST 3 第 2、3、6、7 条），顺带看合并进度的显示（V03.3 核对）

<!-- docs:生成结束 -->
