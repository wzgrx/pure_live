# H01.1 录制内核

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能（模块重构）
- 来源：模块重构计划（D-001：在 3.x 的代码上逐块重构）；3.x 的 `lib/recorder/` 里不属于页面的部分，加上放在页面目录、实际是内核的 `pages/recorder/recorder_controller.dart`（1763 行）
- 旧编号：M8、T08a.1
- 相关：G01.1（中继和配方，录制复用）；I01.1（FFmpeg 实现、前台服务、provider 的位置）；J02.1（设置和任务的 3.x 迁移）；后续 H01.2（补全）、H02.1（录制中心和接入）、H01.3（合并进度）；提交 `833e570ce`

## 目标

把 3.x 的录制内核搬成纯 Dart 包 `packages/live_record`：不依赖 Flutter、GetX 和全局单例，能单测；FFmpeg、保活、存储权限都由应用注入；行为（参数、重试、分段、合并、任务 JSON）照 3.x，只修审查出的问题。做完以后应用（I01.1、M13 页面）只需要一个 `Recorder` 实例。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11`） | 现在 | 结果 |
|---|---|---|---|
| 结构 | `lib/recorder/services/` 30 多个文件 + `pages/recorder/recorder_controller.dart`，`Get.find`、`.to` 单例（`ffmpeg_service.dart:9-10,314`） | `packages/live_record/lib/src/` 16 个文件，`Recorder`（`recorder.dart`）注入 `sites`、`ffmpeg`、`storage`、`settings`、`persist`、`keepAlive`、`storageAccess`、`caFile` | 纯 Dart，43 个测试（H01.1 时 27 个） |
| 签名地址续期 | 到点结束这次 FFmpeg 再开一次（`recorder_controller.dart:1059-1086`），每次续期多一个 MP4、有缺口 | 会切断连接的租期在中继里续签（`input.dart`），不切断的只预取、断线时快速重连（`recorder.dart:935-979`） | 一场一个 MP4 |
| 录制中继 | 自写 FLV、HLS 两套（约 1900 行，`ffmpeg_flv_input_relay.dart`、`ffmpeg_hls_input_relay.dart`） | 复用 `live_media` 的 `LoopbackRelay`（`input.dart:26`） | 停止时关输入、FFmpeg 排空后退出 |
| FFmpeg 调用 | 直接用 FFmpegKit 插件，事件是字符串键的 Map（`ffmpeg_event.dart`） | 注入接口 `FfmpegRunner`（`ffmpeg.dart:11`），密封事件（`capture.dart:14-107`） | 应用用 FFmpegKit 实现（H02.1） |
| 并发上限 | 从 `Get.find<RecordSettingsController>` 读，没注册时退回 1（`ffmpeg_scheduler.dart:24-31`） | 构造时注入的函数每次读设置（`recorder.dart:144`） | 后台启动也对 |
| 付费、私密房间 | 按普通失败重试到上限（`stream_resolver_service.dart:120-131`） | 报 `restricted`、不重试（`resolver.dart`） | 升级 22-1 内核部分 |
| 提示文字 | 内核里直接 Toast、拼中文（`recorder_controller.dart:291-293,960`） | 内核只给类型 `RecordNotice`、`FfmpegFailureKind`、`RecordStreamErrorType` | 文字由页面给 |
| 任务 JSON | schema 9，`recorder_tasks` | `RecordTask.fromJson`/`toJson`（`task.dart`）照读照写 | 3.x 存的任务原样读入 |

## 结果

- 做了什么（详见 [record.md](record.md)“做法”）：任务和设置（`task.dart`、`settings.dart`）、选流（`resolver.dart`，游标规则照 3.x，线路按 scheme/host/path 去重）、开输入（`input.dart`）、FFmpeg 参数和失败分类（`ffmpeg.dart`，选项逐条照 3.x）、一次录制（`capture.dart`）、分段和命名（`segments.dart`、`naming.dart`、`storage.dart`）、合并（`merge.dart`）、调度（`scheduler.dart`）、内核（`recorder.dart`：添加、开始、停止、删除、检测、恢复、持久化 2 秒合并写一次、每分钟检查缓存上限）。
- 修了审查出的 3.x 问题 9 条（record.md“审查发现的 v3 问题”）：续期缺口、两套自写中继、依赖 GetX 不能单测、后台并发退回 1、受限房间重试到底、内核弹提示、Map 事件、卡住判定读系统时间、只有虎牙原生 FLV 预取。
- 有意差异 7 条：FFmpeg 由应用注入；所有 HTTP(S) 的 FLV、HLS 都套中继；续期不新开 FFmpeg；录制专用的 HLS 预取当时没搬（后由 H01.2 补做）；错误文字由界面给；代理按平台用 `ProxyPolicy`；断线预取通用化。
- 留给后续的：录制弹幕、HLS 预取窗口（H01.2 完成）；合并进度（H01.3 完成）；FFmpeg 实现、前台服务、存储权限、默认目录、provider（H02.1 完成）；设置读写和 3.x 迁移（J02.1、H01.2 完成）。
- 提交 `833e570ce`（2026-10-01）；新增第三方包 `pinyindart` 0.0.1（3.x 同款）。
- 测试 27 个：`task_test.dart` 7、`ffmpeg_test.dart` 8、`recorder_test.dart` 12。

## 验证

- 自动测试：`cd packages/live_record && dart test`（现在 43 个，H01.2、H01.3 加了 16 个）：3.x JSON 读写和脱敏、录制参数、失败分类、分段日志、只合并本次尝试、选流、FLV/HLS 走中继而 RTMP 直连、录制→停止→合并、EOF 快速重连、未开播转等待、损坏保留源文件、恢复、并发排队。
- 真机：录制主流程在 K90 上走过：S02.2 录 75 秒（[记录](../../../S-质量和验证/S02-真机验证/S02.2-K90冒烟/record.md)）、S02.3 录 5 分 39 秒两段合成一个 MP4（[记录](../../../S-质量和验证/S02-真机验证/S02.3-K90验证主流程/record.md)）。

## 留下的问题

- 照 3.x 搬来的“EOF 不计重试上限”和“0 字节分段让合并失败”两条规则有问题（上游 `2b9ffc7a3` 已修）：[H01.5](../H01.5-主播下播后不再无限快速重试/README.md)。
- 划掉应用后继续录、所有文件访问、弹幕 XML、HLS 漏段在真机上没验证：[H01.4](../H01.4-录制余项/README.md)。
- `recorder_test.dart` 里有 20、50 毫秒的定时器（`:156`、`:197`、`:289`），和 D-017 不符，下次改这个文件时改成按条件等。
