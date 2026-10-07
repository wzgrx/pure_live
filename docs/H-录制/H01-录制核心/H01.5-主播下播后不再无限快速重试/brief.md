# H01.5 主播下播后不再无限快速重试；合并时跳过 0 字节分段：任务书

> 任务书模板（v2）。自包含：读完这一页和“先读”里的文件就能开工。

## 背景

- 来源：上游 pure_live（liuchuancong）提交 `2b9ffc7a3`，2026-10-01。提交说明原话：
  - “下播时流被服务端关闭产生 unexpectedEof，旧策略对它豁免重试上限，永远快速重试：每次都 resolve 到 404 的签名 URL，留下一堆 0 字节段”
  - “现在 EOF 快速重试也有上限(2x maxRetries)，用完转入离线轮询 —— 任务不丢，等主播开播即可，不再敲打 CDN”
  - “合并前过滤 0 字节/已消失的分段(重试风暴的残留)，有一个有效段就能合并出可播放的视频；全空才明确报错不再抛段时钟校验失败”
  
  本仓库能直接看：`git show 2b9ffc7a3`（上游的对象已在本机仓库里）。[W01.1 上游对照](../../../W-上游借鉴/W01-定期对照/W01.1-2026-10-03上游对照/README.md)逐条对照后确认 4.x 有同样的两个问题。
- 现象：
  1. 录一个直播间到主播下播：录制中心卡片一直“重连中 · 第 N 次”，N 一直涨；默认每 2 秒一次新的尝试（取流 → 平台还说“直播中”或给出已失效的签名地址 → 中继、FFmpeg 拿到 EOF 或 404 → 再来）；录制目录 `Records/<平台>/<主播>/<日期>/` 下每次多一个 `<HH-mm-ss>/` 文件夹；前台通知“正在重连 · 主播”一直在，直到用户手动停止。
  2. 停止后合并：只要某次尝试里有一个 0 字节的 `<前缀>_NNNNNN.clock-v1.ts`，这次尝试报 `segmentClock`，任务变“录制失败”，卡片写“最近失败（文件合并）：Joining the recording failed”，应用在后台时还会发“录制已停止 · 主播 / 录制出错停止了。”；那次尝试没有 MP4，分段留在盘上，并且一直留在任务的待合并列表里，下一场录完又合一次、又失败。
- 怎么复现：
  - 不用真机（推荐）：在 `packages/live_record/test/recorder_test.dart` 的 `recorder` 组里照现有用例（`:136-175` 的 `setUp`）写：`settings = RecordSettings(maxRetryCount: 1)`，`ffmpeg..captureExit = 0..captureSeconds = const Duration(seconds: 1)`，`site.status` 保持 `LiveStatus.live`（平台一直说直播中），`addTask(room())`。现在的代码里任务在 `reconnecting` 和 `running` 之间无限循环，`FakeFfmpeg` 的录制次数一直涨（每 2 秒一次），永远到不了 `waitingLive`——这就是“测试”第 1 条，改之前会超时失败。
  - 空分段：在临时目录放 `p_000000.clock-v1.ts`（1000 字节）、`p_000001.clock-v1.ts`（0 字节）和一行日志 `p_000000.clock-v1.ts,0.000000,4.000000`，调 `RecordMerger(FakeFfmpeg()).merge(directory, 'p')`，现在返回 `MergeFailure.segmentClock`（`merge.dart:105-107`）。
  - 真机：录一个哔哩哔哩以外、下播后签名地址还能解析的平台（上游的报告是这种情况；哪个平台会这样需要试，找不到就只靠上面的测试），等主播下播，看录制中心的“重连中 · 第 N 次”。
- 为什么现在做：第一档（[PLAN.md](../../../PLAN.md) 第一档列了它）：影响已发布的 4.0.0、天天录的人每场都会遇到、会丢录像。相关决定：D-017（测试定时器至少 1 秒、不访问真实平台）、D-005（中文、中英文翻译一起加）。
- 已经做过的：H01.1（`833e570ce`，内核，照 3.x 搬了“EOF 不计上限”和“空分段报错”这两条）、H01.2（`8c043873d`）、H01.3（`d145aa930`，合并进度）。没有别的任务改过 `policy.dart` 的这条规则和 `merge.dart` 的空分段处理。

## 目标和验收

1. 主播下播后（平台仍给出能解析的地址，但每次都 EOF、403 或 404），快速重试到 `2 × 最大重试次数` 次就停（默认 5 → 10 次）；默认设置下从第一次断开到停止不超过约 30 秒（10 × 2 秒加每次取流的时间）。
2. 停下时先把这一场所有待合并的尝试合成 MP4（卡片“正在整理文件 N%”），然后：任务的 `autoRecord` 不是 `false`（开了“开播自动录”或 3.x 留下的任务）→“等待开播”，开播检测开着就按间隔检测，开播后自动开始新的一场；`autoRecord == false` →“已保存”（`completed`，清掉最近失败），不是“录制失败”，也不发“录制已停止”提醒。
3. 主播下播后平台马上说“未开播”（取流报 `notLive`）时，同样先合并这一场再“等待开播”（开着开播自动录）——现在这条路不合并，分段要等用户停止才合成（c3b）。
4. 普通失败（不是 EOF、403、404）用完“最大重试次数”时同样先合并：之后“等待开播”，或关了“开播自动录”时“录制失败”（同现在）。
5. 取流时网络不通（`RecordStreamErrorType.networkError`）照旧快速重连、“第 N 次”照旧加一，但不会触发上限：录制中关 Wi-Fi 30 秒再打开，录制接着录（真机清单第 3 节第 4 条）。
6. 录满 10 秒清零重试次数的规则不变；直播中短暂断开（10 次以内）照旧快速重连，录像连续。
7. 一次尝试最后几段是 0 字节：跳过这些空段，其余照常合成 MP4；分段日志里如果有这些空段的行，也一起去掉；合并成功后空段和日志都删掉，目录里只剩 MP4（和弹幕 XML）。
8. 中间有 0 字节分段（后面还有非空分段）：仍报 `segmentClock`，源文件全部保留。
9. 一次尝试全是 0 字节分段：不算合并失败，移出待合并，删掉这些空文件和空日志，目录空了就删目录。
10. 一次尝试结束时没写出任何非空分段：同第 8 条清理，不再留下空目录；只删本次前缀的文件，目录里还有别的文件（别的前缀、弹幕 XML、用户的文件）就不删目录。
11. 合并失败（阶段 `merge`）时卡片写中文“分段没能合成 MP4，原始分段保留在录制文件夹里”，英文诊断在下面的小字。
12. 现有 43 个 `live_record` 测试和应用的全部测试照样通过；新加的测试在改之前失败。

## 现状（读代码得出，写文件:行）

- 快速档的来源：`packages/live_record/lib/src/capture.dart:303-317`：FFmpeg 返回 0 或 `ffmpegEndOfFile` 就是 `unexpectedEof`（静默、可重试）；`:103-106` `refreshesSignedStream` = `leaseRefresh || unexpectedEof || httpAccess`（403、404 在 `ffmpeg.dart:278-287` 归为 `httpAccess`）。`recorder.dart:617-620`：碰到一次就 `rt.rapidRecovery = true`，之后这一场的任何失败都算快速（`fast = refresh || rt.rapidRecovery`）；只有某次尝试录满 10 秒（`:598-601`）或用户重新开始（`_userStart`，`:317-321`）才清掉。`_run` 里取流失败、开输入失败也按 `fast: rt.rapidRecovery` 重连（`:507`、`:515`）。
- 上限：`_scheduleReconnect`（`recorder.dart:896-933`）先 `retryCount + 1`，再问 `RecordPolicy.shouldEnterPollingAfterRetryLimit`（`policy.dart:37-41`）：`!unexpectedEof && retryCount >= maximumRetries.clamp(1, 100)`，快速档永远是 false，于是永远 `reconnecting` + `Timer(delay)` → `_start`。
- 间隔：`policy.dart:22-33` 快速档基数 2 秒、上限 15 秒；`enableBackoff` 默认关（`settings.dart:26`），所以默认固定 2 秒；`maxRetryCount` 默认 5、范围 1～20（`settings.dart:22`、`:40`）；`retryDelay` 默认 30 秒（普通失败的间隔）。
- 用完以后（普通失败才会到这里）：`recorder.dart:906-914`：`_endsAfterBroadcast(task)`（`:773-774`：`autoRecord == false` 且录到过东西）→ `_endSession(task, failed: true)`；否则直接 `waitingLive` + `_schedulePoll(task)`，不合并。`_schedulePoll` 在开播检测关着时（`enablePolling` 默认 false，`settings.dart:24`）直接返回（`:1073`）。
- 平台说“未开播”：`_run` 的 `on RecordStreamException` 分支（`recorder.dart:486-509`）：`notLive` 且 `_endsAfterBroadcast` → `_endSession(failed: false)`（合并、“已保存”，`:489-494`）；`notLive` 其他情况 → `clearFailure`、`waitingLive`、`_schedulePoll`（`:495-501`），**不合并**。检测到开播后走 `_start`（`:327`），不是 `_userStart`，不调 `beginNewRecording`，待合并的尝试一场场累积，直到用户停止（`_userStop` `:995`）才一起合成。现有测试 `开播自动录: off finishes after the broadcast, on waits again…`（`test/recorder_test.dart:284`）只断言“on”的任务到了 `waitingLive`，没看待合并。3.x 同（`recorder_controller.dart:962-967`）。
- 坑：`_canPoll`（`recorder.dart:1057-1069`）要求 `rt.finalizing == null`。`_doFinalize`（`:713-769`）是在 `rt.finalizing` 里跑的，只要中间 `await` 过（合并），这时调 `_schedulePoll` 会直接返回、检测永远排不上。现有 `:749-753` 那个分支就是这样写的，只是直播录制走不到（直播的结束只有用户停止算“完成”）。另外 `_endSession`（`:778-807`）也用 `rt.finalizing ??=`，在 `_doFinalize` 里面调它会拿到自己的 future、等自己，死锁。还有一个更隐蔽的时序：`rt.finalizing ??= _doFinalize(…)`（`:703`）先读 `rt.finalizing`（空），再**同步**执行 `_doFinalize` 到第一个 `await`，最后才赋值。现在 `:726-732` 的 `_scheduleReconnect` → `unawaited(_endSession(…))`（`:906-909`，重试用完且下播就结束）就发生在这个同步前缀里：`_endSession` 把自己的 future 填进 `rt.finalizing`，紧接着被 `??=` 用 `_doFinalize` 的 future 覆盖；`_doFinalize` 随即结束，`whenComplete`（`:710`）把 `rt.finalizing` 清空，而 `_endSession` 的合并还在跑（它自己的 `whenComplete` 之后还会再清一次，可能清掉别人的）——合并期间 `_canPoll`、`startTask`、`stopTask` 都以为没有在整理文件。c3 的收尾要避免这种“在 `_doFinalize` 的同步前缀里起另一个 `finalizing`”的写法：统一让 `_doFinalize` 自己 `await` 合并。
- 合并：`merge.dart:84-98` 列 `.ts`，`:90` 跳过 0 字节的非 clock 文件，0 字节的 clock-v1 文件特意留下（注释 `:88-89`）；`:105-107` 有 0 字节分段就抛 `FormatException` → `MergeFailure.segmentClock`。`SegmentClock.parse`（`segments.dart:19-46`）要求日志行数等于分段数（`:25`）、第 i 行的名字等于第 i 个分段（`:31`）、`end > start`（`:36`）；`read`（`:84-91`）读文件后交给 `parse`。
- 失败之后：`_mergeAttempts`（`recorder.dart:841-885`）对失败的尝试只把 `ok` 设成 false，不移出 `pendingAttempts`；`_markMergeFailure`（`:887-894`）写英文 `'Joining the recording failed'`；`beginNewRecording`（`task.dart:418-426`）不清待合并，下一场结束时 `_mergePending`（`:821-839`）又合一次。
- 空目录：`_run` 在开输入之前就建了尝试目录（`recorder.dart:418-428`）；`_queueCurrentAttempt`（`:809-816`）在 `SegmentMeter.hasSegments`（`metrics.dart:62-75`，有非空分段才算）为假时直接返回，目录和 0 字节文件留下。
- 0 字节分段从哪来（根因线索）：上游在下播后的重试风暴里看到“一堆 0 字节段”。4.x 里能确定的两个来源：(1) FFmpeg 被取消（停止时 5 秒没排空就取消，`capture.dart:193-207`；或进程被杀后在 `restore` 里合并），分段封装器刚打开的下一段还没写进数据——“前面有数据、最后一段空”，正是合并失败的那种；(2) 一次尝试刚开始就断，分段文件已建、没有数据——整次都是空的，现在不记为待合并，只留空目录。日志里有没有空段那一行，取决于 FFmpeg 有没有写尾，所以 c4 两种都要处理。
- 用户看到的文字：`apps/pure_live/lib/features/recorder/recorder_texts.dart:72-90` `recordFailureText` 只对 `ffmpeg.*`、`background`、`room` 有本地化说明，`merge` 阶段直接显示 `lastError`；“录制已停止”提醒在任务变 `failed` 且应用不在前台时发（`app/recording_notice.dart:147-161`）。

## 3.x 基线

- `git show v3.2.11:lib/recorder/services/recorder_continuation_policy.dart`：`:76-83` 同样 `if (unexpectedEof) return false;`。
- `git show v3.2.11:lib/recorder/pages/recorder/recorder_controller.dart`：`:227-229` 录满 10 秒清零；`:270-290` 快速档；`:1202-1235` `_scheduleReconnect`（用完 → 等待开播 + 检测，不合并）。
- `git show v3.2.11:lib/recorder/services/video_processor_service.dart`：`:139` 非 clock 的空文件跳过；`:165-176` clock 模式下有空分段就报错。
- 3.x 有同样的问题；修复在 3.x 之后的上游 `2b9ffc7a3`：
  - `recorder_continuation_policy.dart`：`final budget = unexpectedEof ? maximumRetries.clamp(1, 100) * 2 : maximumRetries.clamp(1, 100); return retryCount >= budget;`
  - `video_processor_service.dart`：合并前把 0 字节和已消失的分段滤成 `validSegments`，全空时报新键 `recorder_no_valid_segments`，之后清单、字节数、日志校验都用 `validSegments`。
- 和上游的差别（有意，写进 record.md）：上游用完次数后不合并，这里先合并；上游全空时报错，这里丢掉不算失败；上游过滤所有空段（中间空段、日志里有空段那一行时照样校验失败），这里明确只容忍尾部空段并去掉对应的日志尾行；上游断网也计入上限，这里不计（c2）。
- 要保留的：录满 10 秒清零；CDN 断开 2 秒快速重连；合并失败保留源文件；只合并本次尝试的文件；任务 JSON 和状态值不变。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节分阶段、第 8 节合并审查、第 14 节规则）。
2. `docs/specs/ENGINEERING.md`（第 4 节分层、第 7 节代码规则）。
3. 本文件夹的 [README.md](README.md)；[H01 子分类说明](../README.md)；[H01.1 的记录](../H01.1-录制内核/record.md)（“保留的 v3 行为”“有意差异”）。
4. 代码：`packages/live_record/lib/src/policy.dart`；`recorder.dart` 的 `_run`（:377-537）、`_onCapture`（:562-644）、`_finalize`/`_doFinalize`（:694-769）、`_endsAfterBroadcast`/`_endSession`（:771-807）、`_queueCurrentAttempt`/`_mergePending`/`_mergeAttempts`/`_markMergeFailure`（:809-894）、`_scheduleReconnect`（:896-933）、`_canPoll`/`_schedulePoll`（:1057-1091）；`capture.dart`（:58-107、:253-330）；`merge.dart`；`segments.dart`；`metrics.dart`；`task.dart`（:418-470）。
5. 测试：`packages/live_record/test/support/fakes.dart`、`test/recorder_test.dart`（:136-208）、`test/ffmpeg_test.dart`（:111-137）；应用 `apps/pure_live/lib/features/recorder/recorder_texts.dart`、`test/features/recorder/recording_wiring_test.dart`。
6. `git show 2b9ffc7a3`。

## 范围

- 可以改：`packages/live_record/lib/src/policy.dart`、`recorder.dart`、`merge.dart`、`segments.dart`、`metrics.dart`；`packages/live_record/test/` 下的测试和 `support/fakes.dart`（只加可选参数，默认行为不变）；`apps/pure_live/lib/features/recorder/recorder_texts.dart`；`apps/pure_live/assets/translations/zh.json`、`en.json`（加 1 个键）；`apps/pure_live/test/features/recorder/` 里和失败说明有关的测试；本文件夹的 `record.md`。
- 不能改：其他组的界面和逻辑；版本号、`assets/version.json`、`assets/releases.json`；签名配置；3.x 的设置键名和含义（D-018）。本任务特有的禁区：`RecordTask.toJson`/`fromJson` 的结构和 `RecordStatus` 的值顺序（3.x 存的是下标）；`RecordSettings` 的默认值和范围（`maxRetryCount` 默认 5、1～20，`enablePolling` 默认关，`enableBackoff` 默认关）；`SegmentClock` 对中间空段、行序、时间顺序的 fail closed；`capture.dart` 和 `ffmpeg.dart` 的失败分类；录制面板、录制中心、通知的界面（A07.6、A10.1、A14.1）；`packages/live_media`。

## 方案和阶段

| 阶段 | 做什么（对应 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 EOF 重试设上限后转入等开播 | c1、c2、c3、c3b | `policy.dart`、`recorder.dart`、`test/ffmpeg_test.dart`、`test/recorder_test.dart` | 验收 1～6、12；阶段 1 的新测试改之前失败、改之后通过；门禁通过 |
| 2 合并跳过空分段 | c4、c5、c6、c7 | `merge.dart`、`segments.dart`、`recorder.dart`、`metrics.dart`、`recorder_texts.dart`、翻译、`test/merge_empty_test.dart`（新）、`support/fakes.dart`、应用的失败说明测试 | 验收 7～12；同上 |

每个阶段都要能单独合并（门禁通过、不留半截功能）。阶段 1 合并后，用完次数时会合并，遇到尾部空段仍会报合并失败——停止时现在也是这样，阶段 2 修掉。

### c1 EOF 上限（`policy.dart:35-41`）

```dart
/// Whether retries are used up and the task should wait for the room
/// again. A live EOF (or 403/404) is retried quickly, but a streamer who
/// ended the broadcast keeps causing them: they get twice the budget
/// (upstream pure_live 2b9ffc7a3) instead of none.
static bool shouldEnterPollingAfterRetryLimit({
  required int retryCount,
  required int maximumRetries,
  required bool unexpectedEof,
}) {
  final limit = maximumRetries.clamp(1, 100);
  return retryCount >= (unexpectedEof ? limit * 2 : limit);
}
```

名字和参数不变（调用方只有 `recorder.dart:901`）。

### c2 断网不触发上限（`recorder.dart:486-521`、`:896-905`）

- `_scheduleReconnect` 加参数 `bool counted = true`：`retryCount` 照旧加一（卡片的“第 N 次”），`counted` 为假时跳过上限检查。
- `_run` 的 `on RecordStreamException` 分支（`:502-508`）：`error.type == RecordStreamErrorType.networkError` 时传 `counted: false`；`cdnFailed`、`noQuality`、`unknown` 计入。`on Object` 分支（`:511-519`，开输入失败等）计入。
- 理由写进代码注释和 record.md：请求本身失败说明是网络问题，不是下播；平台回答了却没有流、或流一开就断，才是下播的样子。

### c3 用完时先合并，再等开播或结束（`recorder.dart:694-807`、`:896-933`）

- `_scheduleReconnect` 改成只排重试、返回 `bool`：排上了返回 true；用完返回 false，并且不改状态（删掉 `:906-914`）。
- 新的收尾（建议名 `_endAfterRetries`）：用完时 `rt.rapidRecovery = false`、`rt.prefetched = null`、`_cancelLease(rt)`；合并这一场的待合并尝试；合并失败 → `_markMergeFailure` + `failed`（同现在）；合并成功 →
  - `_endsAfterBroadcast(task)` 为真：快速档用完 → `completed`（`clearFailure()`，`retryCount = 0`）；普通失败用完 → `failed`（同现在）；
  - 否则 → `waitingLive`，**在合并的 future 结束、`rt.finalizing` 清掉之后**再 `_schedulePoll(task)`。
- 两个调用的地方：
  - `_doFinalize`（`:726-732`）：`_scheduleReconnect` 返回 false 时不要 `return`，接着走下面的合并（`:733-739`），合并后按上一条定状态。`_doFinalize` 改成返回“要不要排检测”，`_finalize`（`:694-711`）在 `whenComplete` 清掉 `rt.finalizing` 之后再调 `_schedulePoll`。不要在 `_doFinalize` 里面调 `_endSession`（死锁）或直接 `_schedulePoll`（被 `_canPoll` 挡掉）。顺手把 `:749-753` 的 `_schedulePoll` 也改成同样的方式。
  - `_run` 的两个 catch（`:507`、`:515`）：返回 false 时 `await` 收尾（`_endSession` 加参数 `waitAgain`，合并后按上一条定状态，检测在 future 结束后排），再 `_completeLifecycle(rt)`。要 `await`：`_run` 的 `finally`（`:535`）看到状态不是 `reconnecting` 就释放前台服务，不等的话合并期间前台通知就没了。
- c3b：`_run` 的 `notLive` 等待分支（`:495-501`）改成和用完时同一个收尾：有待合并的尝试就先合并（`processing`），合并后 `waitingLive`，检测在合并的 future 结束后排；没有待合并的照旧直接等。`_endsAfterBroadcast` 为真的分支（`:489-494`）不变。
- 注意 `_endsAfterBroadcast` 的条件是“录到过东西”，没录到任何东西的任务（一直 404）关了开播自动录时：快速档用完 → `completed`，没有文件；这和现在 `notLive` 的处理（`:489-494`）一致。

### c4 尾部空段（`merge.dart:84-124`、`segments.dart:19-46`、`:84-91`）

- `selectAttemptSegments` 排序后（`merge.dart:96-97`）：读每段的大小（读不到算 0），去掉末尾连续的 0 字节段，剩下的叫 `valid`、去掉的叫 `tail`。`valid` 为空 → `MergeFailure.empty`（c5）。
- clock 模式：`valid` 里还有 0 字节 → 照旧 `segmentClock`（`:105-107` 改成只查 `valid`）；`SegmentClock.read`/`parse` 加可选参数 `Iterable<String> ignoredTail = const []`（被去掉的文件名）：日志行数比分段多时，多出的必须正好是最后几行、名字按顺序等于 `ignoredTail` 的前几个，才去掉这些行再按原规则校验；其他情况照旧报错。空段的那一行可能 `end <= start`，去掉后不再参与 `:36` 的检查。
- 非 clock 的旧分段：`:90` 已经跳过 0 字节，不变。
- `inputBytes` 和清单只用 `valid`；成功后（`:168-179`）删掉 `valid` 和 `tail` 的文件，都删掉了才删日志。
- 更新 `RecordMerger` 和 `merge` 的文档注释（`:49-69`）。

### c5 全空的尝试（`merge.dart:9-28`、`recorder.dart:841-885`）

- `MergeFailure` 加 `empty`（“every segment of the attempt is empty”），放在最后，`noSegments` 的含义不变。
- `_mergeAttempts`：`result.failure == MergeFailure.empty` → `task.removePendingAttempt(attempt)`、删掉它的空文件（c6 的函数）、`onProgress(index, 1)`、`_update(task)`，不把 `ok` 设成 false。

### c6 没写出东西的尝试不留目录（`recorder.dart:809-816`、`metrics.dart` 或 `segments.dart`）

- 新函数（建议放在 `segments.dart`，名字如 `discardEmptyAttempt(String directory, String prefix)`）：删掉匹配 `^<prefix>_\d{6,}(\.clock-v1)?\.ts$` 且 0 字节的文件；日志 `<prefix>.clock-v1.csv` 是 0 字节、或每一行指向的分段都已删掉时删掉日志；然后目录里没有任何东西才删目录。任何删除失败都忽略（下次再说），不抛出。
- `_queueCurrentAttempt` 在 `hasSegments` 为假（`:813`）时调它；`allowLegacy` 的恢复路径（`:1293`）不调（3.x 的旧分段不碰）。
- 只动本次前缀的文件；目录里有弹幕 XML 或别的文件就留着目录。

### c7 合并失败说中文（`recorder_texts.dart:72-90`、翻译）

- `recordFailureText`：`stage == 'merge'` 时 `meaning = i18n('recorder_merge_failed')`，`lastError`（英文诊断）作为 `detail`。
- 新键 `recorder_merge_failed`：中文“分段没能合成 MP4，原始分段保留在录制文件夹里”，英文 “The segments could not be joined into an MP4; they are kept in the recording folder”。两个翻译文件按键名排序插入（`i18n_test.dart` 检查中英文键一致）。
- `_markMergeFailure` 的英文诊断不改（它是诊断，不是给用户看的文字）。

## 测试

- 先写改之前会失败的测试，再改代码。测试里的定时器至少 1 秒（D-017）；不访问真实平台（用 `FakeSite`、`FakeFfmpeg`）。`recorder_test.dart` 现有的 `until` 期限是 10 秒（`:166-172`），新测试要更长时给它加一个可选的期限参数。
- 阶段 1：
  - `test/ffmpeg_test.dart` 的 `reconnect, polling and lease timing follow 3.x`（:111-137）：保留 `retryCount: 9, maximumRetries: 5, unexpectedEof: true` 为假；加 `retryCount: 10` 为真（改之前失败）、`retryCount: 5, unexpectedEof: false` 为真、`retryCount: 4, unexpectedEof: false` 为假；用例名改成说明“EOF 有两倍的次数（上游 2b9ffc7a3）”。
  - `test/recorder_test.dart` 新增（`settings = RecordSettings(maxRetryCount: 1)`，上限 2 次；`ffmpeg..captureExit = 0..captureSeconds = const Duration(seconds: 1)`）：
    1. `after the broadcast ends the fast retries stop at twice the limit, the attempts are joined and the task waits for the room`：期望最终 `waitingLive`；录制的 FFmpeg 运行（参数里没有 `concat` 的）正好 2 次、合并 2 次；`pendingAttempts` 为空；`lastOutputPath` 存在；再等 3 秒没有第 3 次录制（开播检测默认关）。改之前一直 `reconnecting`，等到超时失败。
    2. `开播自动录 off: the fast retries running out end the session saved, not failed`：`addTask(room(), autoRecord: false)`，期望 `completed`、`lastError` 为空。
    3. `a network outage keeps reconnecting without using up the limit`：第一次录制 EOF 后把 `site.detailError` 设成普通异常（解析成 `networkError`），等 `retryCount` 超过 2 次后任务仍是 `reconnecting`；清掉 `detailError`、`captureExit = null`，下一次进入 `running`。
    4. `with the live check on, the task checks the room again after the join`：`RecordSettings(maxRetryCount: 1, enablePolling: true, liveCheckInterval: 10)`；到 `waitingLive` 后把 `captureExit` 设为 null，约 10 秒后自动开始第 3 次录制并进入 `running`（证明检测在合并之后排上了，没有被 `_canPoll` 挡掉）；`Timeout(Duration(seconds: 60))`。
    5. `when the room reports offline, the session is joined before it waits again`（c3b）：`addTask(room(), autoRecord: true)`、`captureExit = 0`；到 `reconnecting` 后 `site.status = LiveStatus.offline`；期望先 `processing` 再 `waitingLive`，`pendingAttempts` 为空、`lastOutputPath` 以 `.mp4` 结尾。改之前停在 `waitingLive` 但 `pendingAttempts` 有 1 个、没有 MP4。
  - 现有 `a live EOF reconnects quickly with a new attempt and joins both at the end`（:194-208）照样通过（一次断开在上限以内）。
- 阶段 2：新文件 `packages/live_record/test/merge_empty_test.dart`（用临时目录和 `FakeFfmpeg`；`support/fakes.dart` 的 `FakeFfmpeg` 加两样可选的东西，默认行为不变：合并时把 `-i` 后面清单文件的内容记进 `joinManifests`；录制时写多少字节 `captureBytes`，默认 1000，0 表示空分段且不写日志行）：
  1. `an empty last segment is skipped and the attempt joins`：`p_000000.clock-v1.ts`（1000 字节）、`p_000001.clock-v1.ts`（0 字节）、日志一行 `p_000000.clock-v1.ts,0.000000,4.000000` → 成功；清单只有 000000；之后目录里只剩 `p.mp4`。改之前是 `MergeFailure.segmentClock`。
  2. `a journal row of the empty tail goes with it`：日志两行（第二行 `p_000001.clock-v1.ts,4.000000,4.040000`）→ 成功。
  3. `an empty segment in the middle still fails closed`：000000（1000）、000001（0）、000002（1000），日志三行 → `segmentClock`，三个分段和日志都还在。
  4. `an attempt of only empty segments is empty, not a failure`：只有 000000（0 字节）→ `MergeFailure.empty`。
  5. `restore drops a pending attempt that holds only empty segments`（`Recorder.restore`，任务 JSON 状态 `running`、`pendingAttempts` 指向只有空分段的目录）→ 任务 `stopped`（不是 `failed`）、待合并为空、目录被删。
  6. `an attempt that wrote nothing leaves no folder`：`RecordSettings(autoReconnect: false)`、`captureBytes = 0`、`captureExit = 0` → 任务结束后 `Directory(task.outputDir!)` 不存在。
- 应用：`apps/pure_live/test/features/recorder/recording_wiring_test.dart`（或录制中心测试）加一个：`lastErrorStage: 'merge'` 的任务，卡片写“分段没能合成 MP4……”，英文诊断在小字里。
- 跑：`cd packages/live_record && dart format --output=none --set-exit-if-changed . && dart analyze && dart test`；`cd apps/pure_live && flutter analyze && flutter test`。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 录制设置：自动断线重连开、最大重试次数 5、开播检测关；在一个快下播的直播间点录制 → 立即录 | 卡片“录制中”，通知“正在录制 · 主播” |
| 2. 等主播下播 | 卡片“重连中 · 第 N 次”，N 不超过 10；半分钟内变“正在整理文件 N%”，再变“等待开播”，上方有“开播检测关着”的提示；前台通知消失 |
| 3. 看录制目录：`adb shell ls -lR /sdcard/Android/data/com.mystyle.purelive.v4dev/files/Records/<平台>/<主播>/<日期>/` | 每个时间文件夹里一个 MP4（系统播放器能放）；没有空文件夹、没有 0 字节的 `.ts`、没有 `.clock-v1.csv` |
| 4. 在直播间的录制面板关掉“开播自动录”，再录一场到下播 | 最后是“已保存”，不是“录制失败”；应用在后台时也没有“录制已停止”提醒 |
| 5. 打开开播检测（间隔 30 秒），录到下播 | 合并后“等待开播”，之后每 30 秒检测一次；主播再开播时自动开始新的一场 |
| 5b. 开着开播自动录和开播检测，录一个下播后平台马上显示“未开播”的直播间（例如哔哩哔哩）到下播 | 卡片先“正在整理文件 N%”，再“等待开播”；录制目录里这一场已经有 MP4，不用手动停止 |
| 6. 录制中关 Wi-Fi（手机数据也关）30 秒再打开（真机清单第 3 节第 4 条） | 期间“重连中”，次数可以超过 10；网络回来后继续录，最后合成 |

## 风险和注意

- 断网和下播靠 `networkError` 区分（c2）：某个平台下播后取流本身就报请求失败的话，那个平台仍会一直重试；遇到时在 record.md 记下平台，另开任务（E 组）。
- 合并在 `rt.finalizing` 里跑：不要在 `_doFinalize` 里调 `_endSession`（拿到自己的 future、等自己），也不要直接 `_schedulePoll`（`_canPoll` 要 `finalizing` 为空）。
- `_run` 的 `finally`（`:522-536`）按状态决定释放前台服务和保护目录，收尾要在它之前做完（`await`）。
- 删文件只删本次前缀的 0 字节分段和空日志；路径从任务里来，删之前确认在录制根目录下面（`RecordStorage.recordDirectory()`），不要因为 3.x 导入的奇怪路径删到别处。
- 冲突：`recorder.dart` 是录制的大文件，A10.x、H05.2 也可能改 `recorder_texts.dart`；翻译文件按键名排序合并。
- 规模：登记表写“小”，实际按两个阶段各约 2 小时；超出时停在阶段边界。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 分支 `ai/H01.5` 或本机工作区；提交信息以 `[H01.5]` 开头（英文），例如 `[H01.5] Cap fast reconnects after a live EOF at twice the retry limit`；不推 master。
- 提交前：`packages/live_record` 跑 `dart format --output=none --set-exit-if-changed .`、`dart analyze`、`dart test`；`apps/pure_live` 跑 `flutter analyze` 和全部 `flutter test`；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在本文件夹 `record.md` 写“停在哪”（做完了哪几个 c、哪些测试已经写好）、更新登记表的 `done`、`next`、`branch`。

## 报告（中文，简洁）

每条验收做到没有；根因（两个问题各一句）；和上游的差别；测试数量（`live_record` 原 43 个 → 现在多少，应用多少）；改了哪些文件；新翻译键 `recorder_merge_failed`；要在真机上看的（上表）；需要维护者决定的（例如某平台下播后报 `networkError`）；可能冲突的文件。
