# H02.1 录制中心与录制设置（含录制接入）

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能（页面重构 + 原生接入）
- 来源：模块重构计划的页面部分（D-001）；I01.1、H01.1 记录“留给其他模块”的录制接入（FFmpeg 实现、前台服务、存储权限、CA 包、provider）
- 旧编号：M13.15、T08b.1
- 相关：H01.1（`Recorder`）、J02.1（`legacy_values`）、A01.1（设置卡片、状态页）、I01.1（provider、`AppNavigator`）；之后的 H01.2（设置进 `live_store`、打开文件夹、划掉后继续录）、A10.1、A10.2（录制中心和录制设置的界面重做）；提交 `de14b3c8e`

## 目标

用户能在 4.x 里像 3.x 一样录制：录制中心看任务、开始、停止、删除、看失败原因；录制设置改 19 项设置；直播间的“录制”按钮有接口可用。为此把录制内核接进应用：Android、Windows、Linux 用 FFmpegKit 录，Android 有前台服务和存储权限。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11`） | 现在 | 结果 |
|---|---|---|---|
| FFmpeg | `lib/recorder/services/ffmpeg_service.dart` 直接用 `ffmpeg_kit_extended_flutter` | `lib/platform/recording_platform.dart:23` `FfmpegKitRunner`（同一插件 0.6.2、同一个 FFmpeg 9.0.2 原生包），实现 `live_record` 的 `FfmpegRunner` | 一致 |
| 前台服务 | `RecorderForegroundService.kt`（249 行）+ `RecorderBackgroundPlugin.kt`（557 行） | `RecorderForegroundService.kt` + `RecorderPlugin.kt`（通道 `pure_live/recorder`），Dart 侧 `AndroidRecordKeepAlive`（`recording_platform.dart:166`） | 同样 dataSync、唤醒锁、Wi-Fi 锁、Android 15 时限回调 |
| 存储权限 | `recorder_controller.dart:665`，用 permission_handler、device_info_plus | `androidStorageAccess`（`recording_platform.dart:322`）+ `RecorderPlugin.requestStorage`，自己的原生通道 | 只在用户操作时申请，自动恢复时不弹（同 3.x） |
| 录制中心 | `pages/recorder/recorder_page.dart`（842 行），九个状态筛选，失败原样显示英文（:682） | `features/recorder/`：H02.1 时九个筛选加数量；A10.1 之后改成五个筛选、卡片用状态卡 | 失败说明本地化 |
| “立即检测” | 实际是强制开始一次新录制（`recorder_page.dart:423,440`），检测不到会把任务标失败 | 调 `refreshTaskStatus`，只检测、开播才开始 | 修了 3.x 问题 3 |
| 打开文件夹 | 发文件夹意图，`Android/data` 下打不开且没反应（`recorder_controller.dart:1599-1601`） | H02.1 时复制路径；H01.2 起公共目录发意图、应用专属目录复制并说明 | 修了 3.x 问题 4 |
| 录制设置的存储 | Hive 19 个键；第一次进设置就把当时的默认目录写死（`record_settings_controller.dart:339-347`） | H02.1 时 `meta['recorder.settings']`；H01.2 起 `live_store` 设置注册表；空目录 = 默认目录 | 修了 3.x 问题 5 |

## 结果

- 做了什么（详见 [record.md](record.md)）：
  - 录制接入：`FfmpegKitRunner`；原生包配置写在根 `pubspec.yaml`（pub workspace 下钩子读根 pubspec），`dependency_overrides` 加 `code_assets: 2.1.0`；`RecordCaBundle`（Android、Linux 把 3.x 的 Mozilla CA 包写到 `<数据目录>/certificates/`）；前台服务和 `AndroidRecordKeepAlive`；`androidStorageAccess`；`AppRecording`（`lib/app/recording.dart:369`）和 `recordingProvider`；`AppBootstrap.wire` 用 `platformAppRecording`，后台 `start()`。
  - 页面：录制中心（状态格、按状态的任务卡片、进行中提示、输入缺失警告、本地化的最近失败和原始诊断、按状态的按钮和进行中状态、删除确认、点卡片进直播间）；录制设置（基础、缓存管理、性能与画质、自动重连、挂机轮询检测五组）。
  - 给直播间录制按钮的接口：`recording.available`、`taskFor(room)`、`addTask(room, startImmediately:)`、`startTask`、`recorder.stopTask`、`recorder.removeTask`、`recorder.notices` + `recordNoticeText`。
  - 已批准的升级：22-1（受限房间的提示和卡片说明）、26-2（FC2、Bigo、niconico 的配方打开器随录制器注册）。
- 修了 3.x 问题 6 条（失败原因看不懂、受限房间只说网络错误、“立即检测”强制开始、打开文件夹没反应、默认目录写死、滑块每动一下写一次）；第 7 条“录制设置不进备份”后由 H01.2 修。
- 后续变化：界面在 A10.1（录制中心，五个筛选、状态卡）、A10.2（录制设置）重做；设置存储、打开文件夹、划掉后继续录、原生包缓存由 H01.2 完成。
- 测试：6 个（`recorder_page_test.dart` 4、`recording_wiring_test.dart` 2）；`flutter build apk --debug` 成功，APK 含三个 ABI 的 `libffmpegkit.so` 和 CA 包。

## 验证

- 自动测试：现在 `apps/pure_live/test/features/recorder/` 共 31 个（之后 A10.1、H01.3 加的），`test/features/record_settings/` 12 个。
- 真机：S02.2（录 75 秒：面板、通知、录制中心“已保存”卡片，[记录](../../../S-质量和验证/S02-真机验证/S02.2-K90冒烟/record.md)）、S02.3（录 5 分 39 秒两段合成，[记录](../../../S-质量和验证/S02-真机验证/S02.3-K90验证主流程/record.md)）。所有文件访问权限页的返回、Android 15 时限回调没在真机上看过，归 [H01.4](../../H01-录制核心/H01.4-录制余项/README.md)。

## 留下的问题

- Windows 主机上的构建、录制、合并、打开文件夹没检查过；3.x 导入的 `recordSavePath` 可能指向 3.x 安装目录：X 组以后做（D-004）。
- 录制历史（3.x `record_history`、路由 `kRecordHistory`）：3.x 没有页面，不做。
- 合并失败的说明仍是英文：[H01.5](../../H01-录制核心/H01.5-主播下播后不再无限快速重试/README.md) 阶段 2。
