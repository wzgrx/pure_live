# H02.1 页面：录制中心与录制设置（含录制接入）

- 日期：2026-10-01
- 目录：`apps/pure_live/lib/features/recorder/`（路由 `RoutePath.kRecordPage`，也是首页的“录制”Tab）、`apps/pure_live/lib/features/record_settings/`（路由 `RoutePath.kRecordSettings`），类名 `RecorderPage`、`RecordSettingsPage` 和构造参数不变
- 录制接入（I01.1、H01.1 留下的事）：`lib/app/recording.dart`、`lib/platform/recording_platform.dart`（新）、`lib/app/services.dart` 和 `lib/app/bootstrap.dart` 各几行、`apps/pure_live/pubspec.yaml`、根 `pubspec.yaml`、`android/`（新服务和插件、清单一条、`MainActivity` 注册一行）
- v3 来源：标签 `v3.2.11` 的 `lib/recorder/pages/recorder/`（`recorder_page.dart` 843 行、`recorder_controller.dart` 中页面部分）、`lib/recorder/pages/record_settings/`（页面 623 行、控制器 349 行）、`lib/recorder/widgets/recorder_bounded_scroll.dart`、`lib/recorder/consts/recorder_keys.dart`、`recorder_config.dart`、`lib/recorder/services/ffmpeg_service.dart`（FFmpegKit 用法）、`ffmpeg_tls_trust_store.dart`、`recorder_background_service.dart`，`android/.../RecorderForegroundService.kt`（252 行）、`RecorderBackgroundPlugin.kt`（558 行），`pubspec.yaml` 的 `ffmpeg_kit_extended_flutter` 和 `ffmpeg_kit_extended_config`
- 用到的模块：H01.1（`Recorder`、`RecordSettings`、`RecordStorage`、`FfmpegRunner`、`RecordKeepAlive`）、J02.1（`MetaStore`、`legacy_values`）、A01.1（设置卡片、`AppStatusView`、`CommonAvatar`、`LiveNetworkImage`、`PlatformLogo`）、I01.1（provider、`AppNavigator`、`i18n`）

## 做法

### 录制接入

| 部分 | 做法 |
|---|---|
| FFmpeg | `FfmpegKitRunner`（`recording_platform.dart`）实现 H01.1 的 `FfmpegRunner`：`FFmpegKitExtended.initialize()` 一次，`FFmpegKit.createSessionFromArguments`（参数列表原样传入），日志、统计、完成三个回调转成 `logs`、`statistics`、`exitCode`，`cancel` 调会话的 `cancel`；`executeAsync` 在完成前抛错时补一行日志并以 -1 结束。插件照 v3：`ffmpeg_kit_extended_flutter` 0.6.2（pub.dev 最新），原生包是 v3 的 FFmpeg 9.0.2 构建（发布 `native-ffmpeg-9.0.2-b1`），由插件的构建钩子在构建时下载到 `.dart_tool`，不进 Git |
| 原生包配置 | 钩子从 `.dart_tool/package_config.json` 旁边的 pubspec 读 `ffmpeg_kit_extended_config`，pub workspace 里那是**根** `pubspec.yaml`，所以配置写在根 pubspec（构建日志确认“Using app configuration from …/pubspec.yaml”和 v3 的 URL）。Android、Windows、Linux 三个地址照 v3 |
| 依赖覆盖 | 插件声明 `code_assets ^1.2.1`，而 media_kit 分支要 `^2.1.0`：根 pubspec 加 `code_assets: 2.1.0` 覆盖（v3 同样覆盖过；钩子只用 2.x 里没变的接口，`flutter build apk` 通过、APK 里有三个 ABI 的 `libffmpegkit.so`） |
| CA 证书包 | `RecordCaBundle`：Android 和 Linux 上把 v3 的 `assets/certificates/mozilla-ca-bundle.pem`（2026-08-13，SHA-256 与 v3 相同）写到 `<数据目录>/certificates/`，内容不同才重写；`Recorder.caFile` 返回这个路径（只用于直连的 HTTPS 输入，FLV/HLS 都走中继）。Windows 用 Schannel，不需要 |
| 前台服务 | Android：`RecorderForegroundService.kt`（dataSync 前台服务、通知、唤醒锁和 Wi-Fi 锁）+ `RecorderPlugin.kt`（通道 `pure_live/recorder`：`setActive` 等服务真正进入前台再回答，15 秒超时；Android 15 的时限 `onTimeout` 或服务被意外销毁时向 Dart 发 `interrupted`）。Dart 侧 `AndroidRecordKeepAlive` 实现 H01.1 的 `RecordKeepAlive`：第一个持有者启动服务、最后一个释放时停止；被系统停掉时调 `Recorder.keepAliveInterrupted(reason)`，之后自动重试一律拒绝，直到用户手动开始（`allowUserRetry`，同 v3） |
| 存储权限 | `androidStorageAccess`：管理目录可写就通过；否则只在用户操作时申请——API 30+ 打开“所有文件访问权限”设置页、返回后再检查，API 26～29 申请存储权限（`RecorderPlugin` 处理 Activity 结果）；自动恢复时不弹（同 v3 `requestIfMissing: false`） |
| 默认目录 | 沿用 I01.1 的 `defaultRecordDirectory`：Android 是应用外部存储目录下的 `Records`（不需要权限），其他平台是数据目录下的 `Records` |
| 录制设置的存储 | `RecordSettingsStore`：live_store 的设置注册表里没有录制设置（J02.1 把 3.x 的值留在 `legacy_values`），所以存成 `meta['recorder.settings']` 一个 JSON，键就是 3.x 的 Hive 键（`segmentTime`、`default_quality`、`recorder_rw_timeout`……19 个）；用户改动之前读 3.x 导入的值，第一次保存时连同导入值一起写入。读是同步的（录制器每次决定都读），写按顺序合并 |
| 应用里的录制 | `AppRecording`（`recording.dart`）：设置、管理目录（与录制器同一个 `RecordStorage`，在用的目录才受保护）、录制器、前台服务；`start()` 读设置后 `restore` 存下的任务（没有 v4 任务时读 3.x 的 `recorder_tasks`），设置变化转给 `settingsChanged()`；`addTask`/`startTask` 是用户操作（先 `allowUserRetry`）。`AppServices.recording` + `recordingProvider`；`recorderProvider` 现在返回真正的录制器（没有 FFmpeg 的平台和测试里是 null） |
| 启动 | `AppBootstrap.wire`：运行中的应用用 `platformAppRecording`（FFmpeg、前台服务、权限、CA），后台 `start()`；测试（`background: false`）只有设置和目录 |

### 页面

| 文件 | 内容 |
|---|---|
| `recorder/recorder_page.dart` | 录制中心：标题栏（打开文件夹、录制设置）、状态选择格（v3 的固定网格，带每个状态的任务数）、按状态的任务列表；订阅 `Recorder.changes` 刷新、`notices` 弹提示；`openRecordFolder` |
| `recorder/recorder_task_card.dart` | 任务卡片：封面和状态角标、标题、主播、平台、画质、线路、观众；录制时长、大小、速度、码率；进行中提示、输入缺失警告、最近失败（本地化说明 + 原始诊断）；按状态的操作按钮（带进行中状态）、删除确认 |
| `recorder/recorder_texts.dart` | 状态文字和颜色、失败阶段、FFmpeg 失败类型、取流失败类型、受限类型（22-1）的文字，提示文字，时长/大小/码率格式 |
| `record_settings/record_settings_page.dart` | 录制设置：基础配置、缓存管理（目录、上限、当前大小、清空）、录制性能与画质、自动重连、挂机轮询检测 |
| `record_settings/record_settings_dialogs.dart` | 单选框、整数输入框（快速选择）、目录输入框；`recordDirectoryPickerProvider`（系统目录选择器，应用加上 file_picker 后覆盖） |

### 给直播间“录制”按钮（M13.3b）的接口

`final recording = ref.read(recordingProvider);`
- `recording?.available`：这个版本能否录制；
- `recording.taskFor(room)`：这个房间的任务（没有则 null），状态变化听 `recording.recorder!.changes`；
- `recording.addTask(room, startImmediately: true/false)`：添加并开始，或等待开播（v3 `addTask`）；
- `recording.startTask(task)`（v3 `forceStartTask`）、`recording.recorder!.stopTask(task)`、`recording.recorder!.removeTask(task)`（v3 `unRecorder`）；
- 提示：`recording.recorder!.notices` 配合 `recorder_texts.dart` 的 `recordNoticeText`。

## 与 v3 的功能对照

| v3 | v4 | 说明 |
|---|---|---|
| 录制中心标题、返回/菜单按钮、打开文件夹、录制设置入口 | 有 | 首页 Tab 里手机宽度显示菜单按钮（同其他首页页面） |
| 9 个状态筛选（全部、录制中、等待开播、排队中、重连中、处理中、已完成、失败、已停止），固定网格，按宽度 3/5/9 列 | 有 | 加每个状态的任务数 |
| “全部”按状态分组、再按开始时间倒序（`RecorderTaskOrdering`） | 有 | H01.1 `RecordTask.forDisplay` |
| 空列表：图标、“暂无录制任务”、“添加直播间后将在这里显示” | 有 | 改了说明（见界面改进） |
| 卡片：封面 + 状态角标、标题、头像和主播名、平台标签、画质（默认“自动”）、线路、观众（热度/在线/累计/粉丝） | 有 | 平台标签用平台图标和名字 |
| 卡片：时长、大小、速度、码率 | 有 | |
| 卡片：重连中、准备中提示条 | 有 | 加处理中，重连显示第几次 |
| 卡片：输入缺失、尾部丢弃警告 | 有 | |
| 卡片：最近失败（阶段 + 错误） | 有 | 错误先显示本地化说明，原始诊断放在下面 |
| 卡片：开始时间 | 有 | |
| 按钮：录制中/重连/准备中 → 删除、停止；排队 → 删除、启动、取消；失败 → 重试；等待开播 → 立即检测；已完成 → 重新录制；已停止、处理中 → 启动 | 有 | 等待开播多一个“启动”，“立即检测”改为真的检测（见问题 3） |
| 删除前确认（显示名字，已录文件保留） | 有 | |
| 点卡片进直播间 | 有 | |
| 录制提示（FFmpeg 失败、取流失败、启动中） | 有 | 内核给类型，页面给文字 |
| 打开录制文件夹 | 有 | 桌面用 url_launcher 打开文件管理器；Android 复制路径（见问题 4） |
| 录制设置：默认录制清晰度（5 档） | 有 | |
| 使用拼音文件夹名 | 有 | |
| 同时录制弹幕 | 显示但不可开 | H01.1 没有录制弹幕（留给 H01.1 补做），开关和说明照实显示 |
| 录制文件目录（选择、验证可写后才保存、进行中转圈） | 有 | 应用还没有系统目录选择器：输入路径（可恢复默认）；有选择器后用 `recordDirectoryPickerProvider` 接上 |
| 启用缓存限制（打开时立即清理）、缓存上限（输入框）、当前大小、清空录制目录（确认、进行中） | 有 | 上限加快速选择，当前大小可刷新 |
| 缓存管理标题旁“打开文件夹” | 有 | |
| 优先录制原画轨道、读写超时（3 档）、输入缓冲队列（5 档）、切片时长（滑块）、最大同时任务数（输入框 + 1～10 快速选择） | 有 | 切片时长按 30 秒一档 |
| 自动断线重连、最大重试次数（开时显示）、重连间隔 | 有 | |
| 开播检测、检测间隔、指数退避、最大检测间隔（按开关显示）、启动时恢复待录任务 | 有 | 最大检测间隔按 1 分钟一档 |
| 设置保存失败提示 | 有 | |
| 后台录制保护（前台服务、通知、唤醒锁、Wi-Fi 锁、Android 15 时限） | 有 | 见“留给后续”：划掉应用后的引擎保活 |
| 存储权限申请（Android 11+ 所有文件访问，以下存储权限） | 有 | 自己的原生通道，不再用 permission_handler、device_info_plus |
| FFmpeg（FFmpegKit 0.6.2 + 自建 9.0.2 包）、CA 证书包 | 有 | |

## v3 问题及处理

| # | 问题 | 位置 | 处理 |
|---|---|---|---|
| 1 | 失败原因显示原始英文日志或 FFmpeg 末行，用户看不懂 | `recorder_page.dart:682`（`task.lastError` 原样） | 按失败阶段和类型显示本地化说明（存储已满、路径、连接、输入、解码、损坏、后台时限、受限），原始诊断放在下面的小字里 |
| 2 | 付费、私密、订阅直播取流失败只显示“网络/线路”错误 | 取流层（H01.1 问题 5） | 提示和卡片用直播间的受限说明（22-1） |
| 3 | 等待开播任务的“立即检测”实际是强制开始一次新录制（`forceStartTask`），检测不到时会把任务标成失败 | `recorder_page.dart:423,440` | “立即检测”调 `refreshTaskStatus`（只检测，开播就开始）；另给“启动” |
| 4 | Android 上“打开文件夹”用系统文件管理器的文件夹意图（`content://com.android.externalstorage.documents/...`），默认目录在 `Android/data` 下，Android 11 起系统文件管理器进不去；打不开时返回值被忽略，点了没有任何反应 | `recorder_controller.dart:1599-1601`、`file_utils.dart:165-200` | Android 复制路径并提示；桌面照旧打开，打不开时提示 |
| 5 | 第一次进入设置就把当时的默认目录写进 `recordSavePath`，之后默认目录变了（换包名、换安装位置、恢复到别的设备）也不跟着变 | `record_settings_controller.dart:339-347` | 不再写默认目录：空就是默认，页面显示实际目录 |
| 6 | 滑块每动一下就写一次 Hive | `record_settings_page.dart:143` 等 | 内存立即生效，写入按顺序合并 |
| 7 | 录制设置不进备份，换设备要重设 | v3 备份没有录制设置 | 未改（与 v3 相同），见“留给后续” |

## 界面改进

- 状态格显示每个状态的任务数，空的状态变淡，一眼看出哪里有任务。
- 空列表按筛选说明（“没有‘录制中’的任务”），“全部”为空时告诉用户怎么添加（直播间点“录制”，开播检测会自动开始）。
- 录制中的卡片：角标加闪烁的点、边框变绿、进度条是动态的；处理中（合并）也显示进度条和提示条；重连提示显示第几次。
- 按钮按下后显示转圈，完成前不能重复点（v3 只有删除有忙状态）。
- 失败说明本地化（见问题 1），受限房间说明原因（22-1）。
- 平台标签用平台图标和中文名（v3 是大写 id，如 `BILIBILI`）。
- 没有 FFmpeg 的版本显示“录制不可用”而不是空列表；设置页仍可改。
- 卡片在宽屏限制最大宽度 900，不再拉满。
- 设置页：切片时长按 30 秒、最大检测间隔按 1 分钟一档（v3 是任意秒数）；缓存上限加常用值；当前大小可手动刷新、计算中显示进度；目录框说明“PureLiveRecords 子文件夹”和 Android 权限；“同时录制弹幕”如实标明暂不可用。

## 已批准的升级

| 编号 | 处理 | 状态 |
|---|---|---|
| 22-1 TikTok 私密、订阅、付费 | 取流被拒的提示和卡片用直播间的受限说明（`live_play_restriction_*_hint`） | 完成（H02.1） |
| 26-2 FC2 三档画质 | 应用启动时建录制器，FC2、Bigo、niconico 的打开器随之注册（`recipeOpeners`） | 完成（H02.1） |

## 缺的共享服务或接口（已在本目录或 `lib/app` 里最小处理）

- **live_store 没有录制设置**：用 `meta['recorder.settings']` 存（3.x 键名）。建议协调者把这 19 个设置加进 `Settings` 注册表（键名照 3.x，J02.1 的导入会自动接管），再把 `RecordSettingsStore` 换成 `store.settings`，顺便进备份。——已做（H01.2）。
- **系统目录选择器**（file_picker，O03.1）：`recordDirectoryPickerProvider` 留了口子，在 `main` 里覆盖即可。
- **打开文件夹**（Android）：v3 用 android_intent 发文件夹意图（只对 `Android/data` 以外的目录有效）；应用没有这个插件，现在复制路径。——已做（H01.2，`android_intent_plus`，应用专属目录仍复制路径并说明）。

## 留给后续

- ~~**划掉应用后的录制**~~：完成（C01.2 的 `AudioServiceActivity` 缓存引擎 + H01.2 录制服务绑定 audio_service 的媒体服务，防止后台播放结束时引擎被销毁；见 `H01.2-record-more.md` 第 6 节）。
- ~~**录制弹幕**（H01.1 留下）~~：完成（H01.2），设置页开关已打开。
- **真机检查**（本次不装手机）：前台服务和通知、Android 15 时限回调、所有文件访问权限页的返回、CA 包、FFmpeg 在 Android/Windows 上实际录制和合并。
- **Windows**：在主机上构建（钩子下载 Windows 包），检查录制、合并和打开文件夹；3.x 导入的 `recordSavePath` 可能指向 3.x 安装目录（v4 会在其中建 `PureLiveRecords`），开发机上录制前先改目录。
- ~~**构建时间**~~：完成（H01.2）：配置改为本地路径 `.ffmpeg_kit/`，`tools/ffmpeg_kit/fetch.sh`（Windows 用 `fetch.ps1`）缺少时才下载到 `~/.cache/pure_live/ffmpeg_kit/` 并校验 SHA-256。
- **录制历史**（3.x `record_history`、路由 `kRecordHistory`）：v3 没有页面，不做。
- ~~录制设置进备份（问题 7）~~：完成（H01.2，19 项进 live_store 设置注册表，目录除外）。

## 依赖变化

- `apps/pure_live`：加 `ffmpeg_kit_extended_flutter: 0.6.2`（固定，同 v3）、资源 `assets/certificates/`。
- 根 `pubspec.yaml`：`ffmpeg_kit_extended_config`（v3 的三个原生包地址）、`dependency_overrides` 加 `code_assets: 2.1.0`。锁文件只多了 `ffmpeg_kit_extended_flutter`，`code_assets` 改为 direct overridden（版本不变）。
- `windows/flutter/generated_plugin_registrant.cc`、`generated_plugins.cmake`：pub get 自动加入插件。
- Android：`RecorderForegroundService.kt`、`RecorderPlugin.kt`（新），清单加 `<service android:name=".RecorderForegroundService" foregroundServiceType="dataSync" stopWithTask="false">`（权限 I01.1 已照 v3 声明），`MainActivity.configureFlutterEngine` 注册 `RecorderPlugin`。

## 构建

- WSL：`flutter analyze` 无问题；`flutter build apk --debug` 成功，APK 含 arm64-v8a、armeabi-v7a、x86_64 的 `libffmpegkit.so` 和 CA 包。没有往手机安装。

## 测试

6 个用例（`test/pages/recorder/`，加速流程，只测主要路径）：

| 测试文件 | 内容 |
|---|---|
| `recorder_page_test.dart`（4） | 录制设置读 3.x 的键（类型宽松、超出范围规整）、改动后 v4 的值优先并带上导入值；没有 FFmpeg 时显示“录制不可用”；录制中心按状态计数、筛选、失败的本地化说明和原始诊断、删除确认后任务消失；设置页显示导入的值，目录输入后验证并建 `PureLiveRecords`、最大任务数的范围校验和快速选择、读写超时单选、开播检测展开子项，都写进存储 |
| `recording_wiring_test.dart`（2） | 受限房间的提示（22-1）和 FFmpeg 失败类型的说明；Android 前台服务：多个任务只启动一次、系统停掉后通知录制器并仍发出停止、之后拒绝直到用户手动开始 |
