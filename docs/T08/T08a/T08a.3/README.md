# T08a.3 录制合并进度（附：录制清晰度标签）

- 状态：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 档位：可以以后；规模：小
- 功能点：F-REC-13（见 [inventory/FEATURES.md](../../../inventory/FEATURES.md)）；附带 T15b.2 发现的问题第 1 条（录制的清晰度标签）
- 涉及代码：`packages/live_record`（`resolver.dart`、`recorder.dart`、`merge.dart`、`task.dart`）、`shared/record/`、`features/recorder/`
- 依赖：T08c.1（录制设置）合并后
- 来源：T08a.1“留给后续”（`mergeProgress`）；[T15b.2 记录](../../../T15/T15b/T15b.2/record.md)“发现的问题”第 1 条
- 评审页：按授权直接开发（界面照 T05g.1 录制面板“整理文件”、T08b.2 的状态卡）
- 记录：[records/F.3a.md](record.md)（开发后）

## 一、录制清晰度标签

### v3 的行为（`~/ref/v3ref/lib`，v3.2.11）

| 行为 | 位置 |
|---|---|
| 录制解析器用 `resolveAppliedPlayQuality` 算实际画质，和播放同一个函数 | `recorder/services/stream_resolver_service.dart:372-376` |
| 任务的清晰度写 `playbackLabel`：平台没确认时是“未确认 · 原画” | `recorder/pages/recorder/recorder_controller.dart:905`；`common/utils/play_quality_label.dart:6-8` |
| 播放时画质受限弹“平台实际返回 超清，已按真实画质播放”；录制不提示 | `modules/live_play/controllers/player_controller.dart:741`、`:817` |

### v4 现在

- 先写了测试（`packages/live_record/test/applied_quality_test.dart` 第 1 条）：哔哩哔哩游客样本（`fixtures/bilibili/S07-guest-qn0`、`S07-guest-qn10000`，请求 10000 返回 `current_qn=250`）走录制解析器，`applied` 是 **超清（250）、已确认**；整个录制器跑一遍，任务的清晰度也是“超清”。这条路是对的，改之前就通过。
- 录制解析器和直播间用的清晰度列表是同一个来源：都是 `discoverPlayQualities` → `BilibiliSite.getPlayQualities`（`qn=0` 的回答里各编码 `accept_qn` 和 `current_qn` 的并集，`packages/live_core/lib/src/sites/bilibili/bilibili_api.dart:369-389`）；录制面板的选项就是直播间的列表（`live_play_page.dart:577-581`）。两边只会因为平台两次回答不同而不同。
- `resolveAppliedPlayQuality`（`packages/live_core/lib/src/live_site.dart:183-195`）：平台确认的编号**不在列表里**时退回请求的那一项、标“未确认”。录制写 `stream.quality.quality`（`packages/live_record/lib/src/recorder.dart:438`），把“未确认”丢了。
- 录制不提示画质受限（播放有，`features/live_play/logic/room_controller.dart:427-432`）。

### 差别和根因

| 编号 | 差别 | 根因 |
|---|---|---|
| P1 | K90 上录哔哩哔哩，面板、通知、录制中心写“原画”，文件是 720p | （按 T15b.2 的现象推断，没抓到当时的回答）T15b.2 里录制面板的清晰度只列出“原画”一个，即这个直播间 `qn=0` 的回答只有 10000；请求 10000 时平台给 250（720p），250 不在列表里，`resolveAppliedPlayQuality` 退回“原画”并标未确认；录制写标签时丢了“未确认”（`recorder.dart:438`，v3 写 `playbackLabel`）。测试样本里 250 在列表中，所以看不出来。代码里没有别的路会把平台确认的 250 写成“原画” |
| P2 | 画质受限时录制不说 | 录制器没有这个提示（v3 也没有） |

### 要做的改动

| 编号 | 类型 | 内容 | 对应 |
|---|---|---|---|
| c1 | 修复 | 录制按平台实际返回的清晰度记：确认的编号在列表里 → 那一项；**不在列表里 → 用平台的编号命名**（`LiveQualityLabel`，哔哩哔哩 250 = 超清），算确认；平台没确认 → 请求的名字加“?”（v4 播放菜单的写法，v3 是“未确认 · ”） | P1 |
| c2 | 增强 | 画质受限（平台确认的和请求的不同）时提示一次：新提示种类 `qualityLimited`，直播间（录制按钮已在听录制提示）和录制中心（在当前页时）弹“平台实际返回 超清，已按真实画质录制”；同一次录制只提示一次，重连、续期不再提示 | P2 |

### 需要选的

| 处 | A（建议，按 A 做） | B |
|---|---|---|
| 确认的编号不在列表里 | 用平台的编号命名，算确认（哔哩哔哩是“超清”） | 照 v3 写“原画?”（未确认）：真实画质还是看不到 |
| 提示的次数 | 每次录制（用户开始或开播自动开始）一次 | 每次连接都提示：重连时会反复弹 |

## 二、T08a.3 合并进度

### v3 的行为

| 行为 | 位置 |
|---|---|
| 合成 MP4 时按 FFmpeg 统计发进度事件：输出字节 / 输入字节，没有时用媒体时间 / 录制时长；0～99%，只增不减，写完文件才 100% | `recorder/services/video_processor_service.dart:26-29`、`:222-233`、`:389-405` |
| 界面没有接这个事件（`VideoProcessorService` 只在 `recorder_controller.dart:564`、`:607`、`:844`、`:848` 用到，没人听 `stream`）：卡片只显示“处理中” | 同上 |

### v4 现在

- `RecordMerger.merge` 只读日志和退出码（`packages/live_record/lib/src/merge.dart:131-148`），不读 `FfmpegExecution.statistics`（`ffmpeg.dart:22`）。
- 录制器合并时只把任务改成 `processing`（`recorder.dart:720`、`:769`、`:962`、`:1248`），任务没有进度。
- 状态卡“正在整理文件”只有转圈和说明（`apps/pure_live/lib/shared/record/record_status_card.dart:401-416`），录制面板和录制中心共用这张卡。

### 差别和根因

| 编号 | 差别 | 根因 |
|---|---|---|
| P3 | 合并时看不到进度，长录制停止后不知道还要等多久 | T08a.1 搬合并时没搬进度（`merge.dart` 不读统计），留给后续 |

INVENTORY 里 F-REC-13 写 v3“界面显示百分比”，实际 v3 只发事件、界面没显示，已改正。

### 要做的改动

| 编号 | 类型 | 内容 | 对应 |
|---|---|---|---|
| c3 | 补上 | `merge.dart` 读 FFmpeg 统计算进度（v3 的算法），`merge(onProgress:)` 回调：只增不减，最多 99%，文件改名成功后 100% | P3 |
| c4 | 补上 | 录制器把几次尝试的进度按源文件字节合成整体进度，写到任务的 `mergeProgress`（只在内存，不存盘）；整数百分比变了才通知界面；合并结束清掉 | P3 |
| c5 | 补上 | 状态卡“正在整理文件”：标题右边显示百分比，说明下面一条进度条；FFmpeg 还没报进度时进度条来回走、不显示百分比。录制面板（T05g.1）和录制中心（T08b.2）同一张卡 | P3 |

### 需要选的

无。

## 测试和验证

- `live_record`：哔哩哔哩游客样本走录制解析器是“超清”；列表只有“原画”、平台给 250 时记“超清”并算受限（改之前失败）；平台没确认时是“原画?”；整个录制器跑一遍只提示一次；合并进度从假 FFmpeg 的统计算出，单调、到 100%；录制器把进度写到任务、结束后清掉。
- `apps/pure_live`：状态卡在合并时显示百分比和进度条；提示文字。
- K90：TASKS 第 5 节 5.3 第 1 条（停止后看“正在整理文件”的百分比）；另加：游客录哔哩哔哩，面板、通知、录制中心写平台实际给的清晰度，开始后弹一次“平台实际返回 …”。

## 风险和性能

- 不加常驻任务和定时器；进度只在合并时按 FFmpeg 统计更新，每次合并最多 100 次界面通知，不存盘。
- 任务 JSON 不变（`mergeProgress` 不存）；`selectedQuality` 仍是显示用的名字，只是平台没确认时多一个“?”。
- 只改录制；播放遇到同样情况仍显示“原画?”（`room_controller.dart` 不在本任务的目录，记在记录里）。

## 经过

| 日期 | 内容 |
|---|---|
| 2026-10-02 | 建立（第 1 版清点） |
| 2026-10-02 | 写功能对比；并入 T15b.2 发现的录制清晰度标签问题；INVENTORY 的 F-REC-13 改正（v3 界面没显示进度） |
| 2026-10-02 | 开发完成（录制记平台实际给的清晰度、受限时提示一次；合并进度在状态卡上），待 K90 验证 |
