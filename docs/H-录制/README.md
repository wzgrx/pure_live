# H 录制

录制的逻辑：从直播间或录制中心发起一次录制，到 FFmpeg 写分段、断线重连、合成 MP4、录弹幕、开播自动录、前台服务和通知。排在 G 播放之后：录制靠平台取流（E）和播放的本地中继（G01），天天录的人比天天看的人少；但它出错会丢录像，所以其中会丢数据的问题（H01.5）排第一档。

## 范围

- 管什么：
  - 录制内核 `packages/live_record`：任务模型和 3.x 的任务 JSON（schema 9）、选流（清晰度、线路、续签）、开输入（复用 `live_media` 的中继和 HLS 窗口）、FFmpeg 参数和事件、分段（clock-v1 日志）和命名、合成 MP4 和合并进度、重试和开播检测、租期预取、排队、持久化和恢复、录制弹幕 XML。
  - 应用里的接线：`apps/pure_live/lib/app/recording.dart`（`AppRecording`、`RecordSettingsStore`、默认目录、3.x 录像搬家、弹幕连接器）、`lib/platform/recording_platform.dart`（FFmpegKit、Android 前台服务和存储权限、CA 证书包）、`android/app/src/main/kotlin/com/mystyle/purelive/RecorderForegroundService.kt`、`RecorderPlugin.kt`。
  - 录制中心和录制设置页背后的逻辑：`features/recorder/`（筛选、排序、打开时定位任务、失败说明）、`features/record_settings/`（设置读写、目录校验）、`shared/record/` 里由任务算出状态和动作的部分（`record_state.dart`、`record_actions.dart`）。
  - 录制通知的文字和“录制已停止”提醒：`app/recording_notice.dart`。
- 不管什么：
  - 看得见的样子：录制中心卡片、录制设置页的布局、录制按钮和七种状态图形在 [A10 录制界面](../A-界面设计/A10-录制界面/README.md)（A10.1 录制中心、A10.2 录制设置、A10.3 录制按钮和状态图标），直播间的录制面板在 A07.6，通知的排法和类别在 A14.1；这里只管它们背后的状态和动作。分工的规矩：改“长什么样、怎么点、各状态怎么说”在 A10 开任务；改“什么时候变成这个状态、文件怎么写、通知什么时候发”在 H 开任务；两边都要动的（例如 H05.1 是 A10.3 X4 的后半）各开一个、互相写“相关”。共用的 `shared/record/` 里，`record_state.dart`、`record_actions.dart` 的规则归 H，`record_status_card.dart`、`record_look.dart` 归 A10。
  - 中继和 HLS 窗口本身（`packages/live_media`）在 G01；平台取流、清晰度列表在 E；设置注册表和备份（`live_store` 的 `Settings.recorder`）在 J01、J03。
  - Android 共性的通知权限、前台服务类型、返回手势在 O01、O04、O06。
  - 录制历史页：3.x 只有路由 `kRecordHistory`、没有页面，不做（H02.1 记录“留给后续”）。

## 子分类怎么分

| 子分类 | 管什么 | 和其他子分类、其他组的关系 |
|---|---|---|
| [H01 录制核心](H01-录制核心/README.md) | `live_record` 包：一次录制从选流到 MP4 的全部逻辑、重试、合并、弹幕文件 | H02～H05 都用它的 `Recorder`；中继来自 G01，取流来自 E |
| [H02 录制中心](H02-录制中心/README.md) | 应用里的录制接入（`AppRecording`、provider、FFmpegKit、前台服务）和录制中心页的逻辑 | 界面在 A10.1；直播间录制面板（A07.6）用同一个 `AppRecording` |
| [H03 录制设置和存储](H03-录制设置和存储/README.md) | 19 项录制设置、录制目录（`PureLiveRecords`、所有文件访问权限、缓存上限、打开文件夹、3.x 录像搬家） | 设置注册表和备份在 J01、J03；界面在 A10.2 |
| [H04 自动录制和排队](H04-自动录制和排队/README.md) | 开播检测（挂机轮询）、开播自动录、名额和排队、启动时恢复 | 代码在 `live_record` 的 `Recorder` 和 `RecordScheduler`；H01.5 会改下播后的去向 |
| [H05 录制通知](H05-录制通知/README.md) | 前台录制通知的文字和按钮、“录制已停止”提醒、点通知去哪 | 小图标和类别在 A14.1、A10.3；前台服务的保活在 H02 |

## 现状（2026-10-07）

- 做到哪：
  - 完成：H01.1 录制内核、H01.2 录制补全（弹幕 XML、HLS 预取、设置进 `live_store`、打开文件夹、划掉应用后继续录）、H01.3 合并进度和清晰度标签、H02.1 录制中心与录制接入。K90 上录过一场：5 分 39 秒、两段合成一个 MP4（[S02.3 记录](../S-质量和验证/S02-真机验证/S02.3-K90验证主流程/record.md)）。
  - 待真机：H05.1（通知按状态写标题、“录制已停止”换图标）。
  - 没做：H01.5（第一档：下播后无限快速重试、空分段让合并失败；v2 任务书补了“平台说未开播时也不合并”的 c3b）、H01.4（F-REC-06、07、10、11 四项真机验证）、H05.2（点前台通知定位任务）、H05.3（整理文件时通知显示进度，V03.3 核对时新开）。
  - H03、H04 没有登记任务：设置和存储、开播检测和排队的逻辑都做完了，剩下的真机检查（所有文件访问、后台长时间等开播）并在 H01.4。
  - 功能清点（[inventory/FEATURES.md](../inventory/FEATURES.md) 第 11 节）：13 项里 9 项完成、4 项没验证（F-REC-06 划掉后继续录、F-REC-07 所有文件访问、F-REC-10 弹幕 XML、F-REC-11 HLS 预取），这四项都归 H01.4。
  - 和 3.x 比多了：合并进度、清晰度按平台实际返回的记、画质受限提示一次、续期不再新开 FFmpeg（一场一个 MP4）、录制中心五个筛选带数量、开播自动录、通知按状态写字和“录制已停止”提醒、弹幕 XML 随时是完整文件。少了：无。
- 主要的代码：
  - `packages/live_record/lib/src/`：17 个文件约 4800 行，`recorder.dart`（1362 行）是 3.x `RecorderController` 去掉界面的部分；测试 43 个。
  - `apps/pure_live/lib/app/recording.dart`（574 行）、`app/recording_notice.dart`（174）、`platform/recording_platform.dart`（404）；页面逻辑在 `features/recorder/`、`features/record_settings/`、`shared/record/`；原生在 `android/.../RecorderForegroundService.kt`、`RecorderPlugin.kt`。
  - 应用测试：`test/features/recorder/`（31 个）、`test/features/record_settings/`（12 个）、`test/platform/system_surfaces_test.dart` 里录制通知的部分。

## 当前重点和顺序

1. 第一档 [H01.5](H01-录制核心/H01.5-主播下播后不再无限快速重试/README.md)：主播下播后 EOF 重试设上限、合并跳过空分段。上游 pure_live `2b9ffc7a3` 修了同一个问题；现在下播后录制中心一直“重连中”、每 2 秒新建一个空的尝试目录，一个空分段就让整段合并失败，失败的尝试还挂在任务上，之后每一场都会再失败一次。
2. 待真机 H05.1：随 S02.5 在 K90 上逐条看（[H05.1](H05-录制通知/H05.1-录制通知按状态写标题/README.md)）。
3. 第二档 [H01.4](H01-录制核心/H01.4-录制余项/README.md)：F-REC-06、07、10、11 四项真机验证，改功能清点；发现的问题另开任务。H01.3 留下的两条真机检查（清晰度标签、合并进度）还没有归属，建议顺带看（见 H01.4 任务书最后）。
4. 第三档 H05.2：只录一个直播间时点前台通知定位到那条任务（定位的接口 A08.5 已做好）；H05.3：整理文件时通知显示百分比、去掉计时。两个都改 `RecorderForegroundService.kt` 的 `RecordWords` 和 `buildNotification`，建议连着做。

## 风险和注意

- 平台：签名地址过期、租期切断连接、下播后接口仍说“直播中”或给出 404 的地址——H01.5 的上限就是为最后这种；平台改接口由 E07.1 巡检发现。
- Android：HyperOS 等系统划掉应用即杀进程，前台服务也挡不住（下次启动时合并被杀时的分段）；Android 15 起 dataSync 前台服务有时限，到点 `onTimeout` → `Recorder.keepAliveInterrupted('timeout')`，任务失败并发“录制已停止”；默认目录在 `Android/data/<包名>/` 下，Android 11 起系统文件管理进不去，只能复制路径。
- FFmpegKit 原生包：根 `pubspec.yaml` 指向本地 `.ffmpeg_kit/`，每个新工作区先跑 `bash tools/ffmpeg_kit/fetch.sh`，否则构建和应用测试报 “Local override not found”。
- 3.x 兼容：任务 JSON（`recorder_tasks`，schema 9）、`RecordStatus` 的下标顺序、19 个设置的 Hive 键名和含义都不改（D-018）；不碰用户的 3.x 安装和数据（D-019）。
- 已知的跨组问题：
  - 六间房的录制详情不带弹幕参数（`packages/live_core/lib/src/sites/sixroom/sixroom_site.dart:416`，`getRoomDetailForRecording` 调 `_detail(roomId, media: true)`，没有 `danmaku: true`；进房详情 `:407` 带）。D 组（[D01.28](../D-弹幕/D01-平台弹幕协议/D01.28-六间房弹幕/README.md)）记的影响是“六间房录制没有弹幕 XML”，但读代码看**录制的弹幕不受影响**：录制弹幕的连接器 `recordChatConnector` 自己调 `site.getRoomDetail`（`apps/pure_live/lib/app/recording.dart:51`），拿的是带弹幕参数的进房详情；录制详情只给 `RecordStreamResolver` 选流（`packages/live_record/lib/src/resolver.dart:166`）。真正受影响的是多画面：`features/multiview/logic/multiview_controller.dart:488` 用录制详情建格子，`:865` 因 `danmakuData` 为空不连弹幕，六间房的格子没有弹幕（N 组）。没有任务；H 这边不用改，建议 D01.28 的说明改成指向多画面，修法照旧（录制详情也带 `SixRoomDanmakuArgs`）。
  - 主播下播、平台说“未开播”时，开着开播自动录的任务不合并（`packages/live_record/lib/src/recorder.dart:495-501`，3.x 同），并入 H01.5 c3b，见 [H04](H04-自动录制和排队/README.md)。
- 改这一组的代码时：合并失败一律保留原始分段（`merge.dart` fail closed）；签名地址不落盘（`RecordTask.toJson`）；诊断先脱敏（`diagnostics.dart`）；测试定时器至少 1 秒、不访问真实平台（D-017）；用户看得到的文字中文、中英文翻译一起加（D-005）。

## 相关

- 规范：[specs/ENGINEERING.md](../specs/ENGINEERING.md)；界面部分 [specs/UI.md](../specs/UI.md)。决定：D-005、D-017、D-018、D-019。
- 其他组：[A10 录制界面](../A-界面设计/A10-录制界面/README.md)、[A07.6 直播间弹窗（录制面板）](../A-界面设计/A07-直播间界面/A07.6-直播间弹窗/README.md)、[A14.1 系统界面](../A-界面设计/A14-系统界面/A14.1-系统界面/README.md)、[G01 引擎](../G-播放/G01-引擎/README.md)（中继）、[O01 通知和前台服务](../O-Android系统集成/O01-通知和前台服务/README.md)、[S02 真机清单](../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 3 节、[W01.1 上游对照](../W-上游借鉴/W01-定期对照/W01.1-2026-10-03上游对照/README.md)。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 进度和子分类

`█████████████░░░░░░░` 65%

| 子分类 | 范围 | 进度 | 完成 / 全部 |
|---|---|---|---:|
| [H01 录制核心](H01-录制核心/README.md) | FFmpeg 录制、分段、合并、弹幕文件、重试。 | `█████████████░░░░░░░` 67% | 3 / 5 |
| [H02 录制中心](H02-录制中心/README.md) | 录制任务的管理和接入。 | `████████████████████` 100% | 1 / 1 |
| [H03 录制设置和存储](H03-录制设置和存储/README.md) | 录制设置、存储目录、权限。 | — | 0 / 0 |
| [H04 自动录制和排队](H04-自动录制和排队/README.md) | 开播自动录、名额和排队。 | — | 0 / 0 |
| [H05 录制通知](H05-录制通知/README.md) | 前台录制通知、“录制已停止”提醒。 | `█████████░░░░░░░░░░░` 45% | 0 / 3 |

## 还没完成的（5）

| 任务 | 状态 | 档位 | 阶段 |
|---|---|---|---|
| [H01.5](H01-录制核心/H01.5-主播下播后不再无限快速重试/README.md) 主播下播后不再无限快速重试；合并时跳过 0 字节分段，有一段有效就能合并 | 未开始 | 第一档 | 0/2：下一阶段“EOF 重试设上限后转入等开播” |
| [H01.4](H01-录制核心/H01.4-录制余项/README.md) 录制的 4 项真机验证：划掉应用后继续录、所有文件访问权限、同时录弹幕 XML、HLS 预取 | 未开始 | 第二档 | 0/2：下一阶段“划掉应用后继续录和所有文件访问权限” |
| [H05.2](H05-录制通知/H05.2-只录一个直播间时点前台录制/README.md) 只录一个直播间时，点前台录制通知也定位到那条任务 | 未开始 | 第三档 | — |
| [H05.3](H05-录制通知/H05.3-录制通知显示合并进度/README.md) 录制通知在合并时显示进度（H01.3 记录“没做的”第 2 条） | 未开始 | 第三档 | — |
| [H05.1](H05-录制通知/H05.1-录制通知按状态写标题/README.md) 录制通知按状态写标题，“录制已停止”提醒换新图标 | 待真机 | — | — |

决定见 [DECISIONS.md](../DECISIONS.md)，做法见 [PROCESS.md](../PROCESS.md)。

<!-- docs:生成结束 -->
