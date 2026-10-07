# H01.5 主播下播后不再无限快速重试；正常下播后合并已录分段；合并时跳过 0 字节分段：记录

- 日期：2026-10-08
- 执行者：Claude
- 分支和提交：本机工作区（从 master `1ac3515f8` 开始）；`2037cd0e7`（阶段 1）、`319e6532c`（阶段 2）、`37510f4d4`（阶段 3）、`b2b62a1f7`（追加：手动停止也拿不到 MP4）
- 任务书：[brief.md](brief.md)；设计或说明：[README.md](README.md)

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| c1 EOF 上限 | 做了 | 同任务书：`retryCount >= (unexpectedEof ? limit * 2 : limit)` |
| c2 断网不触发上限 | 做了 | `_scheduleReconnect(counted:)`；只有取流报 `networkError` 不计入 |
| c3 用完时先合并 | 做了 | 收尾函数叫 `_closeSession(broadcastEnded:)`；检测用 `_pollAfterRun` 在本次运行和收尾都结束后再排（见根因 3） |
| c3b 平台说未开播时也先合并 | 做了 | `notLive` 两个分支合成一个，都走 `_closeSession` |
| c4 尾部空段 | 做了 | |
| c5 全空的尝试 | 做了 | `MergeFailure.empty`，放在枚举最后 |
| c6 没写出东西的尝试不留目录 | 做了 | `discardEmptyAttempt`（`segments.dart`）；录制器只在录制根目录下面调用它 |
| c7 合并失败说中文 | 做了 | 新键 `recorder_merge_failed` |
| 追加：手动停止拿不到 MP4（K90，YY） | 做了 | 维护者 2026-10-08 在 K90 上发现，要求一起做；改了 `capture.dart` 的损坏判定时机（任务书原本不让动 `capture.dart` 的失败分类，失败分类本身没改） |

验收：1～12 都有自动测试覆盖（见“测试”）；真机部分待维护者在 K90 上看。

## 根因

- 无限快速重试：`policy.dart:37-41`（master `1ac3515f8`）对 `unexpectedEof` 直接返回 false，快速档永远不到上限；而 `recorder.dart:617-620` 一碰到 EOF/403/404 就 `rapidRecovery = true`，之后这一场的失败都算快速档。主播下播后平台还给能解析的地址，每次都 EOF 或 404，于是每 2 秒一次、永远重连。
- 开播自动录拿不到 MP4：`recorder.dart:495-501` 平台说“未开播”时直接 `waitingLive`，不合并；检测到开播后走 `_start`（不清待合并），所以分段要等用户手动停止才合成。重试用完的路（`:906-914`）同样不合并。
- 开播检测排不上（读代码时发现，和上面同一处）：`_canPoll`（`recorder.dart:1057-1069`）要求本任务不在调度器里运行（`!scheduler.isRunning`，`:1067`）、`finalizing` 为空。`_run` 里的“未开播”分支（`:501`）和重试用完的分支（`:913`）都是在本次运行里面调 `_schedulePoll`，永远被挡掉——开着开播检测，主播下播后检测也不会再排上，任务一直“等待开播”不动。现在由 `_pollAfterRun` 等本次运行（`scheduler.waitFor`）和收尾都结束后再排。
- `rt.finalizing` 时序：`rt.finalizing ??= _doFinalize(…)`（`recorder.dart:703`）先同步执行 `_doFinalize` 到第一个 `await` 才赋值；在这个同步前缀里起的 `_endSession`（`:906-909`）会被覆盖、被提前清空。现在 `_finalizing` 先把 future 存进 `rt.finalizing` 再执行，收尾只在 `_doFinalize` 里 `await _closeSession`，不再嵌套起第二个 `finalizing`。
- 空分段让整次尝试合并失败：`merge.dart:88-90` 特意留下 0 字节的 clock-v1 分段，`:105-107` 有一个就抛 `FormatException` → `segmentClock`；失败的尝试不移出待合并（`recorder.dart:864-879`），每场结束都再失败一次。全是空分段的尝试在 `_queueCurrentAttempt`（`:809-816`）里不记为待合并，但目录和空文件留在盘上。
- 手动停止拿不到 MP4（K90，YY“小颖儿”，停止后“录制失败 · 最近失败（录制内核）：Recorded input is damaged”）：停止时 `capture.dart` 的 `_stop`（`:193-207`）关掉输入，FFmpeg 读到的最后一个 FLV tag 是半截的，FFmpeg 报 `Packet corrupt (stream = 0, dts = …), dropping it.`（`-fflags +discardcorrupt` 把它丢掉，输出没问题）。`capture.dart:222`、`:292` 把它算成输入损坏（`inputIntegrityError`），`merge.dart:81` 对损坏的尝试直接拒绝合并，`_markMergeFailure`（`recorder.dart:887-894`）写“Recorded input is damaged”。本机用维护者拷来的那段（46 s，h264+aac）转成 FLV 后在 tag 中间截断、按录制参数抓一遍，每次都出这一行；正好截在 tag 边界上则什么都不报。3.x 的 FLV 中继停止时在 tag 边界结束（`hasPendingAccessUnit`），所以没有这个问题。现在停止或租期结束之后才出现的这类报错算“尾部丢弃”（`inputTailDiscarded`，卡片已有“停止时部分输入未完整接收，已跳过；录像可能缺少相应内容。”），录制中出现的仍算损坏、保留源文件。

## 改了哪些文件

- `packages/live_record/lib/src/policy.dart`：c1。
- `packages/live_record/lib/src/recorder.dart`：c2、c3、c3b（`_closeSession`、`_finalizing`、`_pollAfterRun`；`_scheduleReconnect` 返回是否排上；删掉 `_endSession`）；c5（`_mergeAttempts` 处理 `MergeFailure.empty`）；c6（`_queueCurrentAttempt` 改成异步、没写出东西时调 `_discardEmptyAttempt`，只在 `storage.recordDirectory()` 下面删）；`CaptureEnded.inputTailDiscarded` 写进任务。
- `packages/live_record/lib/src/merge.dart`：c4、c5。
- `packages/live_record/lib/src/segments.dart`：`SegmentClock.parse`/`read` 的 `ignoredTail`；`discardEmptyAttempt`。
- `packages/live_record/lib/src/capture.dart`：停止或租期结束之后的 packet 报错记为 `inputTailDiscarded`，不再记为损坏；`CaptureEnded` 加 `inputTailDiscarded`。
- `apps/pure_live/lib/features/recorder/recorder_texts.dart`：c7。
- `apps/pure_live/assets/translations/zh.json`、`en.json`：`recorder_merge_failed`。
- 测试：`packages/live_record/test/ffmpeg_test.dart`、`recorder_test.dart`、`merge_empty_test.dart`（新）、`support/fakes.dart`（加可选的 `captureBytes`、`joinManifests`、`stopLog`，默认行为不变）；`apps/pure_live/test/features/recorder/recording_wiring_test.dart`。

## 新设置、翻译键、门禁基线

- 新翻译键：`recorder_merge_failed`（中文“分段没能合成 MP4，原始分段保留在录制文件夹里”）。
- 没有新设置；`RecordSettings` 默认值、`RecordTask` JSON、`RecordStatus` 顺序都没动。门禁基线没动。

## 保留的行为和有意差异

- 保留：录满 10 秒清零重试次数；直播中 CDN 断开 2 秒快速重连；合并失败保留源文件；只合并本次尝试的文件；中间空段、行序、时间顺序仍 fail closed。
- 和上游 `2b9ffc7a3` 的差别：用完次数后先合并再等开播（上游不合并）；全空的尝试丢掉、不算失败（上游报 `recorder_no_valid_segments`）；只容忍尾部空段并去掉对应的日志尾行（上游过滤所有空段，但日志校验对中间空段和日志里有空段那一行仍失败）；取流时断网不计入上限（上游计入）。
- 和任务书的一处出入：任务书说“没录到任何东西的任务（一直 404）关了开播自动录时快速档用完 → completed”。实际按 `_endsAfterBroadcast`（要录到过东西）走，和现在 `notLive` 的处理一致：什么都没录到的任务转“等待开播”，不是“已保存”。
- 开播检测排不上的修复让“等待开播”在开着开播检测时真的会按间隔检测（以前从一次运行里转入等待时不会）。

## 测试

- `live_record`：原 43 个 → 58 个，全部通过。新增：
  - `ffmpeg_test.dart`：重试规则加 3 条断言（EOF 第 10 次到上限、普通第 5 次到、第 4 次不到），改之前失败。
  - `recorder_test.dart`（`after the broadcast ends` 组）：快速重试到两倍上限后合并、等开播、3 秒内没有第 3 次录制；关了开播自动录结束为“已保存”；断网不用掉上限（次数超过 2 次仍“重连中”，网络回来后接着录）；开着开播检测时合并后约 10 秒再检测并开始新的一场。前三个以外的“断网”用例改之前也能过（它守 c2）。
  - `recorder_test.dart`：平台说未开播时先“正在整理文件”再“等待开播”、待合并为空、有 MP4；开着开播检测、开始时发现未开播的任务会再检测（两个都改之前失败）；停止时被截断的 packet 不算损坏、合并成功、`inputTailDiscarded` 为真（改之前任务“录制失败”，同 K90）。
  - `merge_empty_test.dart`（新，8 个）：尾部空段跳过、日志尾行一起去掉、中间空段仍失败、日志多出的行不是那几个空段时仍失败、全空是 `empty`、`discardEmptyAttempt` 只删本次前缀的空文件、恢复时丢掉全空的待合并尝试（任务“已停止”不是“失败”）、没写出东西的尝试不留目录。改之前 6 个失败（另 2 个守 fail closed）。
- 应用：893 个全部通过（新增 1 个：合并失败的卡片写中文，英文诊断在小字里）。
- `dart analyze --fatal-infos`、`flutter analyze --fatal-infos`、格式、`check_ui_structure.py`、`docs.py --check` 通过。

## 真机上要看的

前提：K90 装本分支的测试包（`com.mystyle.purelive.v4dev`），录制设置里“自动断线重连”开、最大重试次数 5、开播检测先关。

1. 手动停止（追加的问题）：进 YY“小颖儿”（或任一 YY 直播间）→ 录制 → 开始录制，等 45 秒 → 停止录制。期望：卡片“正在整理文件 N%”后“已停止”，不是“录制失败”；录制目录里是一个 MP4（系统播放器能放）；卡片可能多一行“停止时部分输入未完整接收，已跳过”。如果每次停止都出这一行、觉得吵，告诉我，另开 live_media 的任务让中继停止时在 tag 边界结束。
2. 模拟主播下播。注意关手机网络模拟不了（那是断网，次数不受限，见第 6 步）。办法：
   - 办法 A（推荐，可控）：用自己的哔哩哔哩账号在电脑上开播（直播姬或 OBS 推流），手机上录这个直播间 1 分钟，然后在电脑上**只停止推流、不点“下播”**：平台一段时间内仍说“直播中”，但流地址断开或 404，正是本任务的场景。之后再点“下播”可顺便看第 5b 步。
   - 办法 B：找一个快下播的主播，录到他下播。
   - 期望：卡片“重连中 · 第 N 次”，N 不超过 10（最大重试次数 5 的两倍）；半分钟内变“正在整理文件 N%”，再变“等待开播”，上面有“开播检测关着”的提示；前台通知消失。想快一点可以先把最大重试次数调成 1（上限 2 次）。
3. 看录制目录：用文件管理器打开 `Android/data/com.mystyle.purelive.v4dev/files/Records/<平台>/<主播>/<日期>/`：每个时间文件夹里一个 MP4；没有空文件夹、没有 0 字节的 `.ts`、没有 `.clock-v1.csv`。
4. 在直播间的录制面板关掉“开播自动录”，再录一场到下播：最后是“已保存”，不是“录制失败”；应用在后台时也没有“录制已停止”提醒。
5. 打开开播检测（间隔 30 秒），开着开播自动录，录到下播：合并后“等待开播”，之后每 30 秒检测一次（卡片上的“上次检测”时间会变）；主播再开播时自动开始新的一场。
5b. 开着开播自动录和开播检测，录一个下播后平台马上显示“未开播”的直播间（例如哔哩哔哩）到下播：卡片先“正在整理文件 N%”，再“等待开播”；目录里这一场已经有 MP4，不用手动停止。
6. 录制中关 Wi-Fi 和数据 30 秒再打开：期间“重连中”，次数可以超过 10；网络回来后接着录，最后停止时合成。

## 需要维护者决定的

- 某个平台下播后取流本身就报请求失败（`networkError`）的话，那个平台仍会一直重试（c2 的代价）。真机上遇到请记下平台，另开 E 组任务。
- 停止时最后半个 FLV tag 被丢掉：现在显示“部分输入未完整接收”；根治要改 `packages/live_media` 的中继（停止时在 tag 边界结束），不在本任务范围。

## 可能冲突的文件

- `packages/live_record/lib/src/recorder.dart`（大文件，A10.x、H04、H05 也可能改）；`apps/pure_live/lib/features/recorder/recorder_texts.dart`；两个翻译文件（按键名排序合并）。
