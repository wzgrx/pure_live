# H01.5 主播下播后不再无限快速重试；合并时跳过 0 字节分段

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能
- 来源：上游 pure_live 提交 `2b9ffc7a3`（2026-10-01，“fix(recorder): 主播下播后不再无限重试, 合并容忍空分段”）；[W01.1 上游对照](../../../W-上游借鉴/W01-定期对照/W01.1-2026-10-03上游对照/README.md)（2026-10-03）确认 4.x 有同样的问题
- 旧编号：T08a.5
- 相关：H01.1（内核，照 3.x 搬了这条规则）；H04（重试用完后“等待开播”）；A10.1 录制中心（失败说明的显示）；H05（“录制已停止”提醒只在任务变“失败”时发）；任务书 [brief.md](brief.md)

## 目标

主播下播后，录制在半分钟内停止重连：先把这一场录到的尝试合成 MP4，再转“等待开播”（开了“开播自动录”或 3.x 留下的任务）或“已保存”（关了“开播自动录”）；不再一直“重连中”、每 2 秒新建一个空文件夹、敲平台的 CDN。合并时一次尝试最后几段是空文件，其余照常合成；全是空文件的尝试直接丢掉，不再让整场录像“文件合并失败”；合并失败时卡片写中文原因。

为什么要做：每天录播的人每场下播都会遇到；前台服务一直开着耗电；一个空分段让那段录像不出 MP4，失败的尝试还一直挂在任务上，之后每一场结束都再报一次失败。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11`） | 现在（4.x） | 要做到 |
|---|---|---|---|
| EOF 是否计入重试上限 | 不计：`recorder/services/recorder_continuation_policy.dart:76-83`（`if (unexpectedEof) return false`） | 同 3.x：`packages/live_record/lib/src/policy.dart:37-41` | EOF 快速重试上限是“最大重试次数”的 2 倍（默认 5 → 10 次），同上游 `2b9ffc7a3` |
| 哪些失败走快速档 | `pages/recorder/recorder_controller.dart:270-290`：`leaseRefresh`、`unexpectedEof`、`httpAccess`；进了快速档，这一场之后的失败都算快速，直到某次录满 10 秒（`:227-229`） | 同：`capture.dart:103-106`、`recorder.dart:617-620`、`:598-601` | 不变；只是取流时网络不通（`RecordStreamErrorType.networkError`）不触发上限检查 |
| 重试用完以后 | `recorder_controller.dart:1205-1213`：转“等待开播”并排检测，**不合并** | `recorder.dart:906-914` 同；关了“开播自动录”时 `_endSession(failed: true)`，下播也算失败 | 先合并再等开播；关了“开播自动录”时快速档用完算“已保存” |
| 开播检测关着（默认） | 停在“等待开播”，不检测 | 同（`recorder.dart:1073`，`settings.dart:24` 默认关） | 不变；录制中心已有“开播检测关着”的提示和“打开”（`features/recorder/recorder_page.dart:526`） |
| 0 字节的 clock-v1 分段 | `services/video_processor_service.dart:139` 特意留下、`:170` 报错 | `merge.dart:88-90` 留下、`:105-107` 报 `segmentClock` | 尾部的空段跳过，日志里对应的尾行一起去掉；中间的空段仍报错、保留源文件 |
| 全是空分段的尝试 | 合并报 `segmentClock`（上游改成报“没有可合并的有效分段”） | 不会记为待合并（`metrics.dart:62-75` 要有非空分段），但目录和空文件留在盘上 | 丢掉、不算失败；删掉空文件和空目录 |
| 合并失败的尝试 | 一直在待合并里，下次再合 | 同：`recorder.dart:864-879` 不移出，`task.dart:418-426` 新会话也不清 | 不变（真的失败要保留源文件）；空分段不再造成失败 |
| 合并失败的说明 | 3.x `_friendlyError` 的通用文字 | 英文：`recorder.dart:891` 的 `'Joining the recording failed'` 原样显示（`features/recorder/recorder_texts.dart:72-90` 对 `merge` 阶段没有说明） | 中文“分段没能合成 MP4，原始分段保留在录制文件夹里” |

## 方案

- **c1 EOF 上限**（`policy.dart:37-41`）：`retryCount >= (unexpectedEof ? limit * 2 : limit)`，`limit = maximumRetries.clamp(1, 100)`；快速档的间隔不变（2 秒起，开了退避最多 15 秒）。
- **c2 断网不触发上限**（`recorder.dart:486-508`）：取流抛 `RecordStreamException` 且类型是 `networkError`（请求本身失败，`resolver.dart:175`、`:185`、`:227`）时，照旧按快速档重连、次数照旧加一，但不检查上限；平台回答了却没有可用的流（`cdnFailed`、`noQuality`）、流一开就断（EOF、403、404）、开输入失败都计入。这样录制中关 Wi-Fi 30 秒（真机清单第 3 节第 4 条）不会把录制结束掉。上游把这些一律计入，这里有意不同。
- **c3 用完时先合并**（`recorder.dart:694-807`、`:896-933`）：`_scheduleReconnect` 只负责排重试，返回是否排上；用完时由调用方收尾：合并这一场的待合并尝试，然后按 `_endsAfterBroadcast`（`:773-774`）结束为“已保存”（快速档用完）/“失败”（普通失败用完），或转“等待开播”并在合并结束后排检测；同时清掉 `rapidRecovery`、预取的地址和租期定时器，下一场从头开始。
- **c4 尾部空段**（`merge.dart:84-116`、`segments.dart:19-46`、`:84-91`）：排序后去掉末尾连续的 0 字节（或已消失的）分段；剩下的里面还有 0 字节就照旧 `segmentClock`；日志比剩下的分段多出的行，只有在它们正好是被去掉的那几段、按顺序排在最后时才一起忽略。合并成功后被去掉的空段和日志一起删掉。
- **c5 全空的尝试**：`merge` 返回新的 `MergeFailure.empty`；`_mergeAttempts`（`recorder.dart:841-885`）遇到它把尝试移出待合并、删掉它的空文件，不算失败。
- **c6 没写出东西的尝试不留目录**：`_queueCurrentAttempt`（`recorder.dart:809-816`）发现这次没有非空分段时，删掉这次前缀的 0 字节分段、空日志，目录空了就删目录（目录里有别的文件就留着）。
- **c7 合并失败说中文**：`recordFailureText`（`features/recorder/recorder_texts.dart:72-90`）给 `merge` 阶段加说明键 `recorder_merge_failed`，英文诊断放到下面的小字。

| 阶段 | 内容 | 对应登记表 |
|---|---|---|
| 1 | c1、c2、c3 | “EOF 重试设上限后转入等开播” |
| 2 | c4、c5、c6、c7 | “合并跳过空分段” |

和上游 `2b9ffc7a3` 的差别：上游用完次数后不合并（这里先合并，下播后马上有 MP4）；上游全空时报错并加键 `recorder_no_valid_segments`（这里当“没东西”丢掉，4.x 本来就不把全空的尝试记为待合并）；上游过滤所有空段，但日志校验对中间空段、日志里有空段那一行仍会失败（这里明确只容忍尾部空段并去掉对应的日志尾行）；上游断网也计入上限（这里不计，见 c2）。

## 验证

- 自动测试（详见 [brief.md](brief.md)“测试”）：`packages/live_record/test/ffmpeg_test.dart` 的重试规则；`test/recorder_test.dart` 新增下播后用完次数先合并再等开播、关了开播自动录结束为已保存、断网不用掉上限、开了开播检测合并后会再检测；新文件 `test/merge_empty_test.dart`：尾部空段跳过、日志尾行一起去掉、中间空段仍失败、全空尝试不算失败、没写出东西的尝试不留目录；应用 `test/features/recorder/` 的合并失败说明。
- 真机：待开发，步骤在任务书“真机验证”。

## 留下的问题

- 开播检测默认关：次数用完转“等待开播”后不会自己检测，要用户点“立即检测”或打开开播检测（3.x 同）。要不要在下播后临时检测一次，属于 H04 的新行为，需要时在 V01 提议。
- 日志缺最后一行的非空分段（FFmpeg 被取消、进程被杀）仍然 fail closed，那次尝试不出 MP4、分段保留：不在本任务。
- 真正合并失败的尝试一直挂在任务上、每场结束再试一次：保留源文件是有意的；要不要给“丢弃这次尝试”的操作，放到 A10.1 以后再议。
- 登记表写的规模是“小”，按上面的 c1～c7 实际是“中”（两个阶段各约 2 小时），开工前请维护者确认。
