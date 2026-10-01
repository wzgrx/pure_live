# F.3a 录制合并进度（附：录制清晰度标签）

- 日期：2026-10-02
- 任务：[F.3a/README.md](../F.3a/README.md)
- 改动：`packages/live_record`（`resolver.dart`、`recorder.dart`、`merge.dart`、`task.dart`；测试 `applied_quality_test.dart`、`merge_progress_test.dart` 新，`support/fakes.dart`）、`apps/pure_live/lib/shared/record/`（`record_status_card.dart`、`record_state.dart`）、`features/recorder/recorder_texts.dart`、翻译（zh、en 各加 1 个键）
- `packages/live_core` 没有改。

## 一、录制清晰度标签（F.0b 发现的问题第 1 条）

### 排查

1. 先写测试：哔哩哔哩游客样本（`fixtures/bilibili/S07-guest-qn0`、`S07-guest-qn10000`：列表 原画 10000 / 蓝光 400 / 超清 250，请求 10000 回答 `current_qn=250`）走 `RecordStreamResolver`，`applied` = **超清（250），已确认**；整个 `Recorder` 跑一遍（假 FFmpeg），`task.selectedQuality` = “超清”。改之前就通过：平台确认的编号在列表里时，录制是对的。
2. 对照清晰度列表：录制解析器（`discovery.discover` → `discoverPlayQualities`）和直播间（`room_controller.dart:359`，录制面板的选项也是它，`live_play_page.dart:577-581`）用同一个函数、同一个请求（`getRoomPlayInfo qn=0`，各编码 `accept_qn` 和 `current_qn` 的并集，`bilibili_api.dart:369-389`），也没有包装层（`SiteRegistry.maybeOf` 直接给适配器）。两边只会因为平台两次回答不同而不同。
3. 代码里把平台给的 250 写成“原画”的只有一条路：确认的编号**不在发现时的列表里** → `resolveAppliedPlayQuality`（`live_core/lib/src/live_site.dart:183-195`）退回请求的“原画”并标未确认 → 录制写 `stream.quality.quality`（`recorder.dart:438`）把“未确认”丢了。v3 写 `playbackLabel`（“未确认 · 原画”，`recorder_controller.dart:905`）。
4. F.0b 记下“录制面板的清晰度只列出‘原画’一个”，即那个直播间 `qn=0` 的回答只有 10000——正好是第 3 条的情形。用改过的样本（`qn=0` 只列 10000，请求 10000 给 250）写测试，改之前得到“原画”（失败），改之后“超清”。

### 根因

确认的编号不在列表里时退回请求的名字，录制又丢了“未确认”标记（`recorder.dart:438`）。属于推断：F.0b 时没有抓平台的回答；K90 上再看一次（见下）。

### 逐条对照

| 编号 | 做到 | 说明 |
|---|---|---|
| c1 录制记平台实际返回的清晰度 | ✅ | `RecordStreamResolver.servedQuality`：确认的编号在列表里 → 那一项（不变）；不在列表里 → 用 `LiveQualityLabel` 按平台的编号命名（哔哩哔哩 250 = 超清），算确认；平台没确认（`qualityUnconfirmed`）→ 请求的名字加“?”（v4 播放菜单的写法）。任务写 `ResolvedRecordStream.qualityLabel`；面板、通知、录制中心都读 `selectedQuality`，不用改。重试的游标仍是请求的编号（`qualityCursorId`） |
| c2 画质受限时提示一次 | ✅ | 新提示 `RecordNoticeKind.qualityLimited`（带 `quality`）：平台确认的编号和请求的不同时，在 FFmpeg 开始写之后发；每次录制（用户开始、开播自动开始）只发一次，重连、续期不再发。文字“平台实际返回 超清，已按真实画质录制”（`record_quality_limited_to`）；直播间的录制按钮和录制中心本来就在听录制提示，直接弹 |

和 v3 的差别：v3 遇到列表外的编号写“未确认 · 原画”，这里写平台给的“超清”（README“需要选的”A）；v3 录制不提示画质受限，这里提示一次。

## 二、F.3a 合并进度

### 逐条对照

| 编号 | 做到 | 说明 |
|---|---|---|
| c3 `merge.dart` 进度 | ✅ | `merge(onProgress:)` 听 `FfmpegExecution.statistics`，`RecordMerger.mergeProgress` 照 v3：输出字节 / 输入字节（不超过 2 倍才算），否则媒体时间 / 录制时长（不超过时长 + 15 秒才算）；0～0.99，只增不减；改名成功后报 1 |
| c4 任务的进度 | ✅ | `RecordTask.mergeProgress`（0～1，只在内存，不进 JSON）：几次尝试按源文件字节加权合成整体进度；第一次和每过一个整数百分比通知界面一次（`persist: false`，不写盘）；合并结束清成 null |
| c5 状态卡 | ✅ | “正在整理文件”标题右边显示“42%”（重连卡显示“第 2 次”的位置），说明下面一条 4 高的进度条；FFmpeg 还没报进度时进度条来回走、不显示百分比。百分比和进度条各自按 `changes` 刷新，面板其他部分不重建。录制面板（U.2f）和录制中心（U.7a）同一张卡 |

INVENTORY 的 F-REC-13 改正：v3 只发进度事件（`video_processor_service.dart:222-233`），没有界面在听，卡片只显示“处理中”。

## v3 → v4

- `recorder/pages/recorder/recorder_controller.dart:905`（`playbackLabel`）→ `packages/live_record/lib/src/resolver.dart`（`servedQuality`、`qualityLabel`）、`recorder.dart`（标签、`qualityLimited` 提示）
- `recorder/services/video_processor_service.dart:222-233`、`:389-405` → `packages/live_record/lib/src/merge.dart`（`onProgress`、`mergeProgress`）、`recorder.dart`（`_mergePending`）、`apps/pure_live/lib/shared/record/record_status_card.dart`

## 设置

没有新设置。任务 JSON 不变（`mergeProgress` 不存）；`selectedQuality` 仍是显示用的名字，平台没确认时多一个“?”（v4 自己的任务键，3.x 不读）。

## 测试

- `live_record` 新增 9 个（共 43 个，全过）：`applied_quality_test.dart` 6 个（游客样本走解析器是超清且算受限；列表只有原画、平台给 250 时记超清——改之前失败；按请求给的不算受限；没确认是“原画?”；整个录制器跑一遍，任务是超清、提示一次；重连不再提示、重新开始再提示一次），`merge_progress_test.dart` 3 个（进度公式；合并按统计报 0.25、0.5、0.75、0.99、1，低的样本不报；任务合并时有进度、单调、到 1，结束清掉、不进 JSON）。
- `apps/pure_live`：新增 1 个（提示文字），改 3 个（录制面板“整理文件”：没进度时进度条来回走，有进度显示“37%”和进度条；录制中心九种状态里的“整理文件”卡显示“42%”；`record state` 里加百分比取整）。`flutter analyze` 无问题，全部 `flutter test` 692 个通过。
- 原有测试没有和改动冲突的：只是在三个原有测试里加了断言、给录制中心测试的“整理文件”任务加了进度。

## 要在 K90 上看的

1. 游客录哔哩哔哩（最好找一个录制面板只列出“原画”的直播间）：面板、通知、录制中心写平台实际给的清晰度（720p 应是“超清”）；开始后弹一次“平台实际返回 超清，已按真实画质录制”；断网重连后不再弹。若仍写“原画”且没有提示，说明平台当时确认的就是 10000（原画本身是 720p），标签是对的。
2. TASKS 第 5 节 5.3 第 1 条：录 10 分钟后停止，“正在整理文件”显示百分比、进度条走到底后变“已保存”；录制中心同一张卡也一样。

## 没做的

- 直播间播放遇到“确认的编号不在列表里”仍显示“原画?”（`resolveAppliedPlayQuality` 不变，`room_controller.dart` 不在本任务目录）。要一致时在 `_openQuality` 里改用 `RecordStreamResolver.servedQuality` 的同样规则。
- 录制通知在合并时不显示进度（`app/recording_notice.dart` 不在本任务目录）。

## 合并时注意

- `packages/live_record/lib/src/recorder.dart`：`RecordNoticeKind` 加了一项；别的分支若对它写穷尽的 `switch`（现在只有 `recorder_texts.dart` 一处）要补上。
- `test/support/fakes.dart` 的 `FakeFfmpeg` 加了 `joinStatistics`（默认空，原来的行为不变）。
- `record_status_card.dart` 的“整理文件”分支改了；U.7a / U.2f 相关分支改同一段时注意。
