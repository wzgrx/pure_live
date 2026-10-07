# H01.2 录制补全

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能（模块重构的补全）
- 来源：H01.1 记录“留给后续”（录制弹幕、HLS 预取）、H02.1 记录“留给后续”（设置进 `live_store`、打开文件夹、构建时间、划掉应用后继续录）、`~/ref/notes/m13_notes.md` 的 “From H02.1 recording” 条目
- 旧编号：M8.1、T08a.2
- 相关：H01.1、H02.1；G01.1（`live_media` 的中继，本任务加了 `HlsMediaWindow`）；J02.1（3.x 设置导入，`legacy_values`）；O03.1（目录选择器）；C01.2（`AudioServiceActivity` 缓存引擎）；提交 `8c043873d`（记录）

## 目标

把 H01.1、H02.1 留下的六件事做完，让录制和 3.x 一样完整：录弹幕、HLS 不漏段、录制设置进备份、Android 能打开录制文件夹、构建不再每次下载 FFmpeg 原生包、划掉应用后录制不断。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11`） | 做之前 | 现在 |
|---|---|---|---|
| 录制弹幕 | `recorder/services/recording_danmaku_service.dart`（241 行）：每次尝试一个 B 站 XML，结束时才写 `</i>`，不看屏蔽词 | 没有，设置页“同时录制弹幕”不可开 | `packages/live_record/lib/src/chat.dart`：`RecordChatRecorder` + `RecordChatWriter`，每 2 秒写入并重写 `</i>`，用屏蔽词和屏蔽用户过滤；连接器 `apps/pure_live/lib/app/recording.dart:43` |
| HLS 预取和保留窗口 | `hls_prefetch_*`、`hls_retained_*`、`hls_low_latency.dart` 等约 2900 行 | 没有，FFmpeg 一次只取一段，慢 CDN 和短窗口会漏段 | `packages/live_media/lib/src/relay/hls_window.dart`（`HlsMediaWindow`，约 400 行），录制的中继默认打开 |
| 录制设置的存储 | Hive 19 个键，不进备份 | `meta['recorder.settings']` 一个 JSON | `live_store` 设置注册表 `Settings.recordXxx`（`packages/live_store/lib/src/settings/settings.dart:908` 起，键名沿用 3.x），进备份的 `recorder` 分区，录制目录不进备份 |
| 打开录制文件夹（Android） | android_intent 发文件夹意图，打不开时没反应（`recorder_controller.dart:1599-1601`） | 复制路径 | `android_intent_plus` 发 DocumentsUI 的文件夹意图；应用专属目录直接复制路径并说明（`features/recorder/recorder_page.dart:28-63`、`platform/plugins.dart:70` 起） |
| FFmpeg 原生包 | 构建钩子每次下载 | 同 3.x（Android 约 40 MB） | `tools/ffmpeg_kit/fetch.sh`、`fetch.ps1` 缓存并校验 SHA-256，根 `pubspec.yaml` 指向 `.ffmpeg_kit/` |
| 划掉应用后继续录 | 前台服务 `stopWithTask="false"` | 同，但后台播放结束时 audio_service 会销毁缓存的引擎，录制中断 | 录制前台服务运行期间绑定 audio_service 的媒体服务，录完才解绑（`RecorderForegroundService.kt`） |

## 结果

- 六件事都做了（详见 [record.md](record.md) 第 1～6 节）：
  1. 录制弹幕：时间以这次尝试进入“录制中”为 0（3.x 以创建时间，晚几秒）；文件任何时候都是完整 XML；只写聊天、按 `messageId` 去重；“折叠重复”“相似度过滤”只影响显示，不影响录制。
  2. HLS 预取：FFmpeg 再次加载某个媒体列表后才开始；每个列表最多 4 个并行、整段收完才交给 FFmpeg、单段超过 32 MiB 不缓存；保留窗口最多 48 段；未交付的最多 96 MiB；低延迟标签去掉、日期范围等跟着分段走；预取失败的段让 FFmpeg 自己取。只放内存。
  3. 设置：19 项进 `live_store`；一次性迁移：先采纳 H02.1 期间存在 `meta` 的 v4 值，再采纳 J02.1 停放在 `legacy_values` 的 3.x 值（`LegacyMigration.adoptLegacyValues`，`packages/live_store/lib/src/legacy/legacy_import.dart:192`）。
  4. 打开文件夹：公共目录发意图，打开前 `canResolveActivity`，打不开复制路径；应用专属目录（Android 11 起系统文件管理进不去）复制路径并提示“在录制设置里换到公共目录”，新键 `recorder_folder_private_copied`。
  5. 原生包缓存：克隆或新建工作区后先跑一次 `bash tools/ffmpeg_kit/fetch.sh`，之后离线也能构建和测试；门禁自动跑。
  6. 划掉应用：通知点击改为和桌面图标一样的启动意图。
- 测试：`live_store` 31（+1）、`live_record` 30（+3，`chat_test.dart`）、`live_media` 40（+2，`hls_window_test.dart`）、应用全部 206 个通过；`flutter build apk --debug` 成功。

## 验证

- 自动测试：`packages/live_record/test/chat_test.dart`（XML 随时完整、一次尝试一个文件、重连间隙不写、关闭和重连）；`packages/live_media/test/hls_window_test.dart`（CDN 删段后慢读者仍从中继拿到、不开预取时行为不变）；`packages/live_store` 的 `backup_test`（3.x 停放值只采纳一次、备份带 `recorder` 分区但不带目录）；应用 `test/features/recorder/`（设置迁移、Android 文件夹地址）。
- 真机：**没验证**（当时没装手机）：弹幕 XML、HLS 预取效果、打开文件夹、划掉应用后继续录、通知点回应用。这些对应功能清点 F-REC-06、10、11，归 [H01.4](../H01.4-录制余项/README.md)（F-REC-12 打开文件夹在清点里已算完成，H01.4 验证 F-REC-07 时顺便再看）。

## 留下的问题

- 部分国产系统（MIUI、HyperOS）划掉即杀进程，前台服务挡不住；下次启动时合并被杀时的分段。要不要引导用户打开自启动，等 H01.4 的真机结果再定。
- Windows：`fetch.ps1` 没在主机上跑过；录制、合并、打开文件夹的 Windows 检查归 X 组（D-004：当前只做 Android）。
- 漏段仍只靠 FFmpeg 日志判定，窗口本身不报（有意取舍）。
