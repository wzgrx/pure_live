# A14 系统界面

系统画、但内容由应用决定的界面：Android 的播放通知和录制通知、画中画窗口里的系统按钮、启动图标和系统启动画面、分享接收的提示、长按图标的快捷方式、权限说明对话框；Windows、Linux 照 3.x 不加系统通知。

## 范围

- 包括（A14.1）：
  - 播放通知（媒体卡片）：小图标、类别名、按钮名称中文（c2、c6）。
  - 录制前台服务通知：标题和正文、系统计时、“停止录制 / 全部停止”“录制中心”两个按钮（c3、c4）；“录制已停止”提醒和它的类别“录制提醒”（c5）。
  - 画中画窗口的“暂停 / 播放”动作按钮（c7）。
  - 启动图标（自适应图标的内缩、单色层，c8）、Android 12 起的系统启动画面、11 及以下的启动底色（c9）。
  - 分享接收的提示文字（正在打开、没有能打开的链接、文件格式不对，c10、c11）、权限说明对话框（先说明再请求、永久拒绝时“去设置”，c12～c14）、长按图标的快捷方式（搜索直播、录制中心、最近看过的两个直播间，c15）。
  - 登记表的代码目录里还有 `features/live_play/mini/`：A14 只关心其中**进系统画中画**那一段（`room_mini_window.dart` 调 `PictureInPicture`）；小窗本身的样子归 A07.8。
- 不包括（归哪里）：
  - 这些功能本身：后台播放和媒体会话在 [C02](../../C-直播间/C02-小窗、画中画、后台播放/README.md) 和 [O01](../../O-Android系统集成/O01-通知和前台服务/README.md)，画中画在 [O02](../../O-Android系统集成/O02-画中画/README.md)，分享接收和快捷方式在 [O03](../../O-Android系统集成/O03-分享接收和快捷方式/README.md)，权限在 [O04](../../O-Android系统集成/O04-权限/README.md)，录制通知按状态写标题、合并进度在 [H05](../../H-录制/H05-录制通知/README.md)。
  - 应用自己画的启动页（A06.4）、口令导入对话框（A06.3）在 [A06](../A06-首页和全局/README.md)；应用内小窗和画中画里应用自己画的东西在 [A07.8](../A07-直播间界面/A07.8-小窗/README.md)；录制通知小图标的形状随 [A10.3](../A10-录制界面/A10.3-录制按钮和状态图标/README.md)；“录制已停止”点开定位到任务在 [A08.5](../A08-弹幕界面/A08.5-设置里的弹幕页/README.md)（c3）。
  - Windows、Linux 的窗口、托盘在 [A16](../A16-桌面界面/README.md)；电视的启动横幅在 A17.2；iOS、macOS 的系统差异在 [A18](../A18-苹果平台界面/README.md)。

## 现状：做到哪、怎么工作的

- **用户看得到的**（Android）：
  - 后台播放（或助眠）时状态栏是单色电视小图标（`drawable/ic_stat_playback.xml`）；通知类别“纯粹直播播放”（`audio_channel_name`），媒体卡片的按钮读作“播放 / 暂停 / 停止”。通知只在“后台播放”打开或助眠进行中才有（`enableBackgroundPlay`，`background_playback.dart:415`），在直播间里开始播放就出现、暂停时留着（C01.2 确认的改动）。
  - 录一个直播间：通知标题按状态写“准备录制 / 正在录制 / 正在重连 / 正在整理录像 · 主播名”（H05.1），正文“标题 · 清晰度”，顶上系统计时；录几个：“正在录制 N 个直播间”，正文是主播名，按钮“全部停止”。点通知或“录制中心”打开录制中心（停在顶部，单个直播间时也不定位，H05.2）。小图标是 A10.3 的实心圆挖方块（`ic_stat_recording.xml`）。
  - 任务失败时：Android 停掉服务（6 小时时限、被杀）一定发、其他失败只在应用不在前台时发“录制已停止 · 主播名”（类别“录制提醒”，单独的小图标 `ic_stat_record_stopped.xml`，开口圆环加“!”），点通知或“打开录制中心”定位到那条任务并描边约 2 秒（A08.5 c3）。
  - 画中画点一下有“暂停 / 播放”按钮，图标跟着房间的播放状态变；离开直播间时去掉。
  - 桌面图标里的电视约占可见圆的六成（前景内缩 2%，3.x 16%），Android 13 起打开主题图标时用单色层；长按图标有“搜索直播”“录制中心”和最近看过的两个直播间（动态快捷方式，打开过一次应用后才有，直播间用统一的电视图标）。
  - 冷启动：Android 12 起系统启动画面浅色 `#FAF8FF`、深色 `#121318` 底加 Logo（不带白圈，150 dp，和启动页 Logo 一样大）；13 起跟应用的“主题模式”（下次冷启动生效）；11 及以下整屏同底色。
  - 分享链接进来先提示“正在打开分享的直播间…”（3 秒提示条，没有转圈）；分享的内容里没有直播间链接时说“分享的内容里没有能打开的直播间链接”，只有文件格式不对才说“仅限 M3U 或 TXT”；平台已下线、解析失败照 3.x。
  - 打开“后台播放”“新直播间自动助眠”：先说明再弹系统通知权限框，再说明电池限制并跳系统电量页；永久拒绝时说明框换成“通知权限已关闭”和“去设置”，回到应用再查一次。第一次开始录制而通知关着时说明一次（可以不开）。
- **内部怎么工作**：
  - 播放通知：`RoomBackgroundPolicy`（`apps/pure_live/lib/features/live_play/logic/background_playback.dart:393`，`live_play_page.dart:292` 建）在 `_syncNotification`（`:431`）里调 `RoomMediaNotification.show / update / hide`（`:299`、`:326`、`:355`、`:373`）；audio_service 的配置在 `:311-316`（类别 id `com.mystyle.purelive.audio`、名称 `audio_channel_name`、小图标 `drawable/ic_stat_playback`），按钮 `mediaControls`（`:276`）。小图标只在 Dart 里按名字用，靠 `res/raw/keep.xml` 让发布版的资源压缩留住（连同 audio_service 的三个按钮图标，见“已知问题”第 1 条）。
  - 画中画按钮：同一个 `_syncNotification` 调 `PictureInPicture.bindPlayback`（`:434` → `:72`），变化才经通道 `pure_live/pip` 的 `setPlaying` 发给原生（`_setPlaying` `:96`）；原生 `MainActivity.kt` 的 `setPictureInPicturePlaying`（`:545`）和 `pictureInPictureActions`（`:532`，一个 `RemoteAction`）更新画中画参数，按钮的广播回到 Dart 调房间的暂停 / 继续；`dispose` 时 `unbindPlayback`（`:515`）。进画中画本身由 `mini/room_mini_window.dart` 的 `RoomMiniWindow`（`:31`，`PictureInPicture.enter` `:148`、自动画中画 `_AutoPip` `:256`）发起。
  - 录制通知：Dart 在任务变化时算文字（`recordNotificationContent`，`apps/pure_live/lib/app/recording_notice.dart:22`，单个直播间按状态取标题 `_oneTitleKey` `:59`），`AndroidRecordKeepAlive`（`apps/pure_live/lib/platform/recording_platform.dart:166`，`refresh` `:216`）有变化才经通道 `pure_live/recorder` 的 `update` 发给原生；`RecorderForegroundService.kt` 的 `buildNotification`（`:323`）建通知，两个按钮（`:335-336`），计时 `setUsesChronometer`（`:341`），不每秒刷新。`RecordingNotices`（`recording_notice.dart:94`）听任务变化，`changed`（`:147`）决定何时发“录制已停止”，经 `AndroidRecordKeepAlive.alert`（`recording_platform.dart:231`）到原生 `alert`（`RecorderForegroundService.kt:130`，每个任务一个请求码 `taskRequest` `:187`）。两个类别在 `channels`（`:152`）：`pure_live_recording`（`:97`，3.x 同一个 id，名字从 “Recording” 改成“录制”）、`pure_live_recording_alerts`（`:98`）。
  - 分享和快捷方式：原生 `ShareIntakePlugin.kt`（通道 `pure_live/share_intake` `:84`）收 `SEND`、`SEND_MULTIPLE`、`VIEW`（`AndroidManifest.xml:81-123`）、设动态快捷方式（`setShortcuts` `:139`，最多两个直播间 `:156`）；Dart 侧 `ShareChannel`（`apps/pure_live/lib/platform/share_channel.dart:75`，`setRecentRooms` `:123`）、`SystemIntake.start`（`apps/pure_live/lib/app/intake/system_intake.dart:32`：剪贴板、分享、`:57` 跟着观看记录更新快捷方式、`:58` 跟着主题模式设启动画面）、`ShareIntake`（`app/intake/share_intake.dart:52`，提示文字 `:155`、`:159`、`:183`、`:191`、`:202`）。
  - 启动画面：资源 `values-v31/styles.xml`（`LaunchTheme`、`SplashTheme.Light`、`SplashTheme.Dark`）、`values-night-v31/styles.xml`、`values/colors.xml`（`splash_light` / `splash_dark`）、`drawable/splash_icon.xml`（`splash_logo.png` 内缩 24%）；13 起 Dart 的 `setSplashTheme`（`system_intake.dart:96`）经 `pure_live/app` 通道调 `MainActivity.kt` 的 `setSplashTheme`（`:570`，`splashScreen.setSplashScreenTheme` `:579`）。
  - 权限：`showPermissionDialog`（`apps/pure_live/lib/shared/permission_prompts.dart:30`）是通用对话框；`BackgroundPermissions`（`:72`）问通知和电池、`RecordingPermissionPrompts`（`:146`，`notificationsOnce` `:168`、`explainStorage` `:207`）；回到应用后再查一次靠 `nextResume`（`:49`）；原生调用在 `SystemPermissions`（`apps/pure_live/lib/platform/system_permissions.dart:26`）→ `PermissionsPlugin.kt`（`notificationState` 等五个方法 `:68-72`）。
- **完成度**：A14.1 登记为完成（2026-10-02，和 O03.2 一起合并）。K90 上有结果的：后台播放通知的文字和中文按钮（c6）、录制通知的标题、正文和两个按钮（c3、c4）（S02.2）；打开后台播放的说明 → 系统通知权限 → 电池说明（c12 的一部分，S02.2）；画中画进入、分享链接直接进房（S02.3，没看画中画的暂停按钮）。**没有真机结果的**：c2 小图标形状、c5“录制已停止”、c7 画中画暂停按钮、c8 桌面图标和单色层、c9 系统启动画面、c10 / c11 分享提示文字、c13 永久拒绝、c14 第一次录制的说明、c15 长按快捷方式（见“已知问题”）。

## 代码地图

Dart（`apps/pure_live/lib/`）：

| 文件 | 职责 | 设计 |
|---|---|---|
| `features/live_play/logic/background_playback.dart`（517 行） | `PipAvailability`（`:16`）、`PipEntry`（`:29`）、`PictureInPicture`（`:42`，`bindPlayback` `:72`、`unbindPlayback` `:88`、`enter` `:137`、`setAutoEnter` `:165`）、`DeviceControls`（`:180`，音量、亮度）、`BackgroundKeepAlive`（`:233`）、`_RoomAudioHandler`（`:251`）、`mediaControls`（`:276`，中文按钮）、`RoomMediaNotification`（`:299`，配置 `:311-316`）、`RoomBackgroundPolicy`（`:393`，`_syncNotification` `:431`） | c2、c6、c7 |
| `app/recording_notice.dart`（174） | `recordNotificationContent`（`:22`，一个 / 几个、计时起点）、`_oneTitleKey`（`:59`，H05.1）、`formatRecordDuration`（`:67`）、`recordStoppedContent`（`:76`，原因和已保存时长）、`RecordingNotices`（`:94`，`changed` `:147` 决定发“录制已停止”，`stopAll` `:165`） | c3、c4、c5 |
| `platform/recording_platform.dart`（404） | `AndroidRecordKeepAlive`（`:166`，`refresh` `:216` 有变化才发、`alert` `:231`、原生回调 `stopAll` `:300`）、`androidStorageAccess`（`:322`）、`platformAppRecording`（`:348`，接上 `RecordingNotices`）；其余是 FFmpeg 执行和证书（H 组） | c3～c5、c14 |
| `platform/share_channel.dart`（148） | `SharedPayload`（`:15`）、`RecentRoomShortcut`（`:69`）、`ShareChannel`（`:75`，`listen` `:90`、`clipboardStamp` `:110`、`setRecentRooms` `:123`）、`releaseSharedFile`（`:140`） | c10、c11、c15 |
| `app/intake/system_intake.dart`（124） | `SystemIntake`（`:27`，`start` `:32` 接剪贴板、分享、快捷方式、启动画面主题）、`openOutsidePage`（`:77`，快捷方式和通知打开的页面）、`recentRoomShortcuts`（`:83`）、`setSplashTheme`（`:96`） | c9、c15 |
| `app/intake/share_intake.dart`（280） | `ShareIntake`（`:52`，`ingest` `:105`、链接 `_openLink` `:180`、文件导入 `_importAll` `:199`；提示文字 c10、c11） | c10、c11 |
| `app/intake/clipboard_rooms.dart`（117） | `readClipboardText`（`:13`）、`ClipboardRoomWatcher`（`:34`，剪贴板口令，O03.2；对话框在 A06.3） | c1（保留） |
| `shared/permission_prompts.dart`（217） | `PermissionAnswer`（`:16`）、`showPermissionDialog`（`:30`）、`nextResume`（`:49`）、`BackgroundPermissions`（`:72`）、`backgroundPermissionsProvider`（`:137`）、`RecordingPermissionPrompts`（`:146`） | c12～c14 |
| `platform/system_permissions.dart`（74） | `NotificationPermission`（`:8`，已允许 / 可以问 / 永久拒绝）、`SystemPermissions`（`:26`，通道 `pure_live/permissions`） | c13 |
| `features/live_play/mini/room_mini_window.dart`（328） | `RoomMiniWindow`（`:31`，进系统画中画 `enter` 用 `PictureInPicture` `:133-166`、桌面小窗）、`_AutoPip`（`:256`，离开应用自动画中画）、`RoomMiniScope`（`:303`）、`showPipDisabledToast`（`:316`） | A07.8；A14 只用它进画中画 |
| `features/live_play/mini/mini_player.dart`（616）、`floating_window.dart`（206）、`compact_danmaku.dart`（220） | 小窗和画中画里应用自己画的画面、按钮、浮动窗口、小窗弹幕 | A07.8、A08（不属 A14） |

Android（`apps/pure_live/android/app/src/main/`）：

| 文件 | 职责 | 设计 |
|---|---|---|
| `kotlin/com/mystyle/purelive/MainActivity.kt`（900） | 通道和插件注册（`configureFlutterEngine` `:190`）；画中画：`pure_live/pip`（`:267-296`，`setPlaying` `:277`）、`enterPictureInPicture`（`:447`）、`setAutoEnterPictureInPicture`（`:490`）、`pictureInPictureActions`（`:532`）、`setPictureInPicturePlaying`（`:545`）；`setSplashTheme`（`:570`） | c7、c9 |
| `kotlin/.../RecorderForegroundService.kt`（344） | `RecordWords`（`:27`，Dart 发来的文字）、`RecorderForegroundService`（`:86`）：类别 `:97-98`、`update`（`:113`）、`alert`（`:130`）、`channels`（`:152`）、`openRecordings`（`:171`，带任务 id 时定位）、`buildNotification`（`:323`） | c3～c5 |
| `kotlin/.../RecorderPlugin.kt`（242） | 通道 `pure_live/recorder`：`setActive`、`update`、`alert`（`:81-87`）、存储权限（`:101-102`）；`onStopRequested`（`:159`）把通知的“停止录制”转给 Dart | c4、c5、c14 |
| `kotlin/.../ShareIntakePlugin.kt`（385） | 分享和打开文件的接收（`receive` `:221`，最多 20 个文件、每个 256 MB `:87-88`）、`openRoute`（`:78`，快捷方式和通知打开的路由）、`setShortcuts`（`:139`）、`clipboardStamp`（`:185`） | c10、c11、c15 |
| `kotlin/.../PermissionsPlugin.kt`（205） | 通知权限状态、请求、电池无限制、打开本应用通知设置（`:68-72`） | c12、c13 |
| `kotlin/.../SystemAccessPlugin.kt`（143） | 安装未知应用、Android 17 本地网络权限、传感器横屏（`:79-83`；O04.1） | 不属 A14 |
| `kotlin/.../AppChannelsPlugin.kt`（281） | 文字编码、密钥加解密、原生 HTTP、组播锁 | 不属 A14 |
| `AndroidManifest.xml` | `POST_NOTIFICATIONS`（`:8`）、应用图标和电视横幅（`:56-62`）、`LaunchTheme`（`:64`）、`supportsPictureInPicture`（`:68`）、`VIEW`/`SEND`/`SEND_MULTIPLE`（`:81-123`）、分享目标（`:124`）、两个前台服务（`:128`、`:142`）；`src/debug/`、`src/profile/` 的清单只加网络权限 | c1、c7、c15 |
| `res/drawable/ic_stat_playback.xml`、`ic_stat_recording.xml`、`ic_stat_record_stopped.xml` | 播放、录制中、录制已停止的单色小图标（后两个随 A10.3、H05.1 改过形状） | c2、c5 |
| `res/drawable/ic_pip_play.xml`、`ic_pip_pause.xml` | 画中画按钮图标 | c7 |
| `res/drawable/ic_shortcut_search*.xml`、`ic_shortcut_record*.xml`、`ic_shortcut_room*.xml` | 快捷方式图标（自适应：底 `shortcut_background` `#D9E2FF`、前景 `#2D4578`） | c15 |
| `res/mipmap-anydpi-v26/ic_launcher.xml`、`res/drawable/ic_launcher_monochrome.xml`、`res/drawable-*dpi/ic_launcher_foreground.png`、`res/mipmap-*dpi/ic_launcher.png` | 自适应图标（前景内缩 2%、单色层）；位图照 3.x | c8 |
| `res/values-v31/styles.xml`、`res/values-night-v31/styles.xml`、`res/values/colors.xml`、`res/values-night/colors.xml`、`res/drawable/splash_icon.xml`、`res/drawable-nodpi/splash_logo.png`、`res/drawable/launch_background.xml`、`res/drawable-v21/launch_background.xml`、`res/values/styles.xml`、`res/values-night/styles.xml` | 12 起的系统启动画面主题和底色、13 起两个可选主题；11 及以下的启动底色；`NormalTheme` | c9 |
| `res/values/strings.xml`、`res/values-en/strings.xml` | 应用名、快捷方式“搜索直播”“录制中心”（英文 Search、Recordings） | c15 |
| `res/raw/keep.xml` | 让发布版留住只在 Dart 里按名字用的 `ic_stat_playback` 和 audio_service 的三个按钮图标 | c2 |
| `res/xml/share_targets.xml` | 分享目标（文本、M3U、XML、JSON、gzip） | c1 |
| `res/drawable/banner.png`、`res/drawable-xhdpi/banner.png` | 电视桌面横幅 | A17.2 |
| `res/xml/network_security_config.xml` | 明文流量配置 | 不属 A14 |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `apps/pure_live/test/platform/system_surfaces_test.dart`（12） | 录制通知文字（一个、几个、计时起点）、单个直播间按状态写标题（H05.1）；保活把文字发给 Android、没变不发、“停止录制”停全部；“录制已停止”的原因和已保存时长、何时发；媒体按钮中文（c6）；画中画按钮（c7：变化才发、点了暂停 / 继续、离开房间去掉）；资源：单色小图标、电视放大和单色层、发布版留住的资源（`c5bc87666` 后加）、插件请求码不重复（`132a5672b` 后加）、启动画面颜色和图标、快捷方式两种语言 |
| `apps/pure_live/test/intake_test.dart`（15） | 分享提示（c10、c11）、文件导入、剪贴板口令、快捷方式数据（c15）（O03.2） |
| `apps/pure_live/test/shared/permission_prompts_test.dart`（7） | 权限说明对话框、永久拒绝和“去设置”、回来再查、第一次录制的说明、所有文件访问的说明（c12～c14） |

## 3.x 基线

- 播放通知：`git show v3.2.11:lib/player/core/live_audio_service.dart`（只在移动端和 macOS 建 `:119`；`AudioServiceConfig` `:53-62`，类别 id 同 v4，`notificationColor: Colors.blue` `:61`；`buildMediaItem` `:157-170`：专辑是应用名、标题、主播、封面）、`lib/player/core/live_audio_handler.dart:193`（暂停 / 播放、停止两个按钮，名称是 audio_service 默认英文）；小图标是默认的 `mipmap/ic_launcher`（Android 8 起是自适应图标，状态栏上推测是白色圆块，设计“拿不准”第 1 条）。
- 录制通知：`android/app/src/main/kotlin/com/mystyle/pure_live/RecorderForegroundService.kt`（类别 `pure_live_recording` 名称 “Recording” `:33-34`，小图标 `ic_launcher_foreground` `:240`，没有按钮）、`lib/recorder/services/recorder_background_service.dart:117-121`（文字取 `recorder_background_notification_title/text`，“直播录制进行中”）；被系统停掉时不发通知，只在应用里把任务标为失败（`lib/recorder/pages/recorder/recorder_controller.dart:1037-1054` 的 `_onBackgroundInterrupted`）。
- 画中画：`plugins/built_in_kotlin/floating/android/src/main/kotlin/eu/wroblewscy/marcin/floating/floating/FloatingPlugin.kt:88-110`（`buildPictureInPictureParams` 只给比例和源区域，没有动作按钮）。
- 启动图标和启动画面：`android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml`（前景内缩 16%，没有单色层）；`res/drawable/launch_background.xml`（白底）、`values-night/styles.xml`（黑底）；没有 `values-v31`，Android 12 起是系统默认的白底加圆形图标。
- 分享和权限：3.x 有 `res/xml/share_targets.xml` 和分享接收（`lib/plugins/share_command_handler.dart:28`）、口令导入、权限说明文字（`permission_notification_title` 等键），A14.1 c1 保留；没有长按快捷方式。
- 必须保留：点播放通知回到直播间；定时关闭到点停止通知；录制用前台服务；3.x 的通知类别 id 不变（`com.mystyle.purelive.audio`、`pure_live_recording`，升级后名字跟着变）；[specs/UI.md](../../specs/UI.md) 附录 A 里和系统界面有关的没有单列的条目。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 已解决：发布版的资源压缩删掉了只在 Dart 里按名字用的 audio_service 按钮图标，Android 13 起播放通知和前台服务起不来 | `res/raw/keep.xml` | 发布版后台播放失效 | `c5bc87666`（2026-10-02）加进 `keep.xml`，`system_surfaces_test.dart` 有用例守着 |
| A14.1 登记为完成，但 c2、c5、c7、c8、c9、c10、c11、c13、c14、c15 没有 K90 结果（只有 c3、c4、c6 和 c12 的一部分在 S02.2 看过） | A14.1 [record.md](A14.1-系统界面/record.md)“要在 K90 上看的”1、3～7 条 | 不符合 PROCESS“完成要有真机结果” | 写进本单元报告；c5 随 S02.5 阶段 4（4B）看，其余建议并入 [S03.1](../../S-质量和验证/S03-统一验证/README.md) 或给 A14.1 补一份 verify.md |
| 系统启动画面在自选主题色、纯黑深色时仍是默认底色 | `res/values/colors.xml`、`values-v31/styles.xml` | 冷启动一闪的底色和应用不同 | 不改（系统启动画面拿不到应用的主题色，设计“拿不准”第 6 条） |
| 分享链接的“正在打开…”提示没有转圈、3 秒后自己消失 | `app/intake/share_intake.dart:183` | 慢的平台解析时提示可能先消失 | 提示条要先有关闭接口（A02.2 的 `AppToast`）；没有登记任务 |
| 最近直播间快捷方式用统一图标，没有主播头像；要先打开过一次应用才出现 | `ShareIntakePlugin.kt:139-179` | 两个直播间快捷方式看起来一样 | 以后有需要走 V01 提议 |
| 只录一个直播间时点前台录制通知不定位到任务（“录制已停止”提醒能定位） | `RecorderForegroundService.kt:334`（`openRecordings(this, 0)` 不带任务） | 少一步 | [H05.2](../../H-录制/H05-录制通知/H05.2-只录一个直播间时点前台录制/README.md) |
| 录制通知在合并时不显示进度 | `recording_notice.dart:22` | 停止后通知只写“正在整理录像” | [H05.3](../../H-录制/H05-录制通知/H05.3-录制通知显示合并进度/README.md) |
| HyperOS 是否读单色层、画中画菜单样子没记录 | 资源、`MainActivity.kt:532` | 主题图标可能不变色 | [S03.1](../../S-质量和验证/S03-统一验证/README.md) |
| 从画中画回来后控制条卡住（S02.1 防御性改过，没复验） | 直播间 | 回来要再点一次或退出直播间 | [O02.1](../../O-Android系统集成/O02-画中画/O02.1-画中画复验/README.md) |
| 代码注释里还用旧编号（`U.14 c8`、`F02 c2`、`M13.15` 等） | `ic_launcher.xml:2`、`values-v31/styles.xml:3`、`system_intake.dart:76` 等 | 按注释找文档要先查 [MAPPING.md](../../MAPPING.md) | Z 组一次性替换 |

## 相关决定和规范

- D-003（A14.1 的 X1～X4 由维护者按建议 A 定：录制通知两个按钮、“录制提醒”类别、三个快捷方式、单色层）。
- D-019（K90 随时可用，真机只点测试包 `com.mystyle.purelive.v4dev`，不碰 3.x）。
- 通知、快捷方式的系统文字放 `res/values/strings.xml` 和 `values-en/`，Dart 里的放翻译文件（所有给用户看的文字中文）。
- [specs/UI.md](../../specs/UI.md) 第 4 节（平台差异集中在 A16.1、A14.1、A18 这几处，其他任务不写平台分支）。

## 测试和验证

- 自动测试：`cd apps/pure_live && flutter test test/platform/system_surfaces_test.dart test/intake_test.dart test/shared/permission_prompts_test.dart`（共 34 个用例声明）。原生部分（通知真实的样子、`RemoteAction`、启动画面、快捷方式、主题图标）测试只能查资源文件和发给原生的数据；缺：没有在模拟器或真机上截图对照。
- 真机：[S02 的 CHECKLIST](../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 1 节第 10、11 条（后台播放通知、画中画）、第 3 节第 1 条（录制通知）、第 4 节第 11 条（分享、口令）。已有结果见“现状”的完成度；H05.1 的通知标题和 c5 提醒在 [S02.5](../../S-质量和验证/S02-真机验证/S02.5-4.0.0构建号5001/README.md) 的阶段 2、4 里（2B-02～07、4B-01～06）。

## 路线

1. S02.5（未开始）：H05.1 按状态写的通知标题、A10.3 的小图标、A08.5 的“录制已停止”定位在 K90 上看，顺带补 c5。
2. 补 A14.1 没看过的原生部分（c2 小图标、c7 画中画按钮、c8 桌面图标、c9 启动画面、c15 快捷方式、c10 / c11 分享提示、c13 永久拒绝）：并入 S03.1 或给 A14.1 写 verify.md，由维护者定。
3. [O02.1](../../O-Android系统集成/O02-画中画/O02.1-画中画复验/README.md)：画中画回来后的控制条；[H05.2](../../H-录制/H05-录制通知/H05.2-只录一个直播间时点前台录制/README.md)、[H05.3](../../H-录制/H05-录制通知/H05.3-录制通知显示合并进度/README.md)：录制通知的定位和合并进度。
4. Windows 开工（X01）时按 c16 确认不加系统通知、任务栏按钮；苹果平台的系统界面在 A18。新想法（快捷方式头像、提示条转圈）写进 V01 提议。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [A 界面设计](../README.md)。

- 代码：`apps/pure_live/android/` 的资源、`features/live_play/mini/`
- 进度：`████████████████████` 100%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| A14.1 | 系统界面：通知、画中画窗口、启动画面、分享接收 | 界面 | 完成 | 2026-10-02 | 8cf3c21b7 | [设计或说明](A14.1-系统界面/README.md)、[记录](A14.1-系统界面/record.md)、[评审页](A14.1-系统界面/page/01-说明.jpg) |

<!-- docs:生成结束 -->
