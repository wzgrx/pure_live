# H01.4 录制余项：功能清点里录制部分的 1 项缺失、5 项没验证

（标题是登记时的数，现在实际是 0 项缺失、4 项没验证加两条长录制和 H01.3 的检查，见下面“3.x 和现状”。）

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能（以真机验证为主，发现的问题另开任务修）
- 来源：清点：[inventory/FEATURES.md](../../../inventory/FEATURES.md) 第 11 节“录制（REC）”的统计行（登记时是“1 项缺失、5 项没验证”）；H01.3 记录“要在 K90 上看的”两条
- 旧编号：T08a.4
- 相关：H01.2（弹幕 XML、HLS 预取、划掉应用后继续录）、H02.1（前台服务、存储权限）、H01.3（合并进度、清晰度标签）、S02.3（K90 上录过一场）；[S02 真机清单](../../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 3 节；任务书 [brief.md](brief.md)

## 目标

把功能清点第 11 节里还没在真机上看过的录制功能逐项在 K90 上看完，结果写进 `verify.md`，功能清点改成“完成”或开出修复任务。做完以后录制这一节没有“缺失”和“没验证”。

## 3.x 和现状

登记的标题“1 项缺失、5 项没验证”是 H01.3 之前的数：缺失的 F-REC-13（合并进度）已由 H01.3 做完，F-REC-03 已在 S02.3 上录过一场。现在第 11 节的表里还剩下面这些（统计行没跟着改，仍写 7 / 1 / 5）：

| 功能点 | 3.x（文件:行） | 现在（文件:行） | 没验证的原因 | 要做到 |
|---|---|---|---|---|
| F-REC-06 前台服务、通知、唤醒锁；划掉应用后继续录 | `android/.../RecorderForegroundService.kt:20`、`RecorderBackgroundPlugin.kt:21` | `apps/pure_live/android/app/src/main/kotlin/com/mystyle/purelive/RecorderForegroundService.kt:86` 起（`stopWithTask="false"`、唤醒锁、Wi-Fi 锁、绑定 audio_service 的媒体服务）；`MainActivity.kt:88`（`AudioServiceActivity`，引擎缓存） | S02.3 在 HyperOS 最近任务里上滑没删掉卡片（把列表滚动了），没真正划掉 | 划掉后录制不断；回到应用录制中心是当前状态；HyperOS 杀进程时记下现象，并验证下次启动合并被杀时的分段 |
| F-REC-07 存储权限（Android 11 起“所有文件访问”） | `recorder/pages/recorder/recorder_controller.dart:665` | `RecorderPlugin.kt`（`requestStorage`）、`lib/platform/recording_platform.dart` 的 `androidStorageAccess` | 没在真机上从录制设置换到公共目录 | 换到 `Download/` 时弹系统“所有文件访问”页，允许后能写，拒绝时说明 |
| F-REC-10 同时录制弹幕（XML） | `recorder/services/recording_danmaku_service.dart:11` | `packages/live_record/lib/src/chat.dart`（`RecordChatRecorder`、`RecordChatWriter`）、`lib/app/recording.dart:43` 的 `recordChatConnector` | 连接各平台弹幕和写文件只在单元测试里看过 | MP4 旁有同名 XML，打开是完整文档，时间和画面对得上 |
| F-REC-11 HLS 预取和保留窗口 | `recorder/services/hls_relay_prefetch.dart:182` | `packages/live_media/lib/src/relay/hls_window.dart`（`HlsMediaWindow`），录制默认打开（`packages/live_record/lib/src/input.dart`） | 效果没在真机量 | 走代理录海外 HLS 平台 30 分钟，录制中心不报“有缺口”或比关掉预取时少 |
| F-REC-03 FFmpeg 录制、分段、合并（备注“没在真机录完一场”） | `recorder/services/ffmpeg_service.dart:51`、`video_processor_service.dart:14` | `capture.dart`、`merge.dart` | S02.3 录了 5 分 39 秒两段，没录过长的 | 录 30 分钟以上（6 段以上）停止后合成一个 MP4，时长对得上、分段和日志清掉 |
| H01.3 c1、c2 清晰度标签和受限提示 | 3.x 写“未确认 · 原画”、不提示 | `packages/live_record/lib/src/resolver.dart` 的 `servedQuality`、`recorder.dart:480-483` | H01.3 记录“要在 K90 上看的”第 1 条没做 | 游客录哔哩哔哩：面板、通知、录制中心写平台实际给的清晰度，开始后提示一次 |
| H01.3 c3～c5 合并进度 | 3.x 只发事件、界面没接 | `merge.dart` 的 `onProgress`、`shared/record/record_status_card.dart` | 同上第 2 条 | 长录制停止后“正在整理文件”显示百分比、进度条走到底变“已保存” |

## 方案

- c1 真机逐项验证（上表 7 行），结果写进本文件夹的 `verify.md`（照 [templates/verify.md](../../../templates/verify.md)），截图放 `verify/`。
- c2 修正功能清点：第 11 节各行的“v4 现状”和统计行（通过的改“完成（日期，H01.4，记录链接）”）。
- c3 不通过的：每个问题写现象和根因线索，在 H01 或对应组开新任务（登记表加任务、`to` 写进来），本任务不改代码。
- 分两个阶段：阶段 1 是不需要代理的 F-REC-03、06、07、10 和 H01.3 两条；阶段 2 是要代理的 F-REC-11（海外平台）。

## 验证

- 自动测试：无（本任务不改代码）；相关的已有测试是 `packages/live_record/test/chat_test.dart`、`packages/live_media/test/hls_window_test.dart`、`apps/pure_live/test/features/recorder/recording_wiring_test.dart`、`test/platform/system_surfaces_test.dart`。
- 真机：见 [brief.md](brief.md)“真机验证”，结果写 `verify.md`。

## 留下的问题

- 登记表的标题还写“1 项缺失、5 项没验证”，和现在不符（见上）；功能清点第 11 节的统计行也是旧的。都由本任务的 c2 改，标题请维护者在登记表里改。
- H01.3 在登记表里是“完成”，但它的真机检查没做（并入本任务），按 [PROCESS.md](../../../PROCESS.md) 第 3.2 节应是“待真机”。
