# A14 系统界面

通知、画中画窗口、启动画面、分享接收的外观。

一句话：系统画、但内容由应用决定的界面：Android 的播放通知和录制通知、画中画窗口里的按钮、启动图标和系统启动画面、分享接收的提示、桌面快捷方式、权限说明对话框；Windows、Linux 照 3.x 不加系统通知。

## 范围

- 包括（A14.1）：
  - 播放通知（媒体卡片）：小图标、类别名、按钮名称中文。
  - 录制前台服务通知：标题和正文、系统计时、“停止录制 / 全部停止”“录制中心”两个按钮；“录制已停止”提醒和它的类别。
  - 画中画窗口的“暂停 / 播放”动作按钮。
  - 启动图标（自适应图标的内缩、单色层）、Android 12 起的系统启动画面、11 及以下的启动底色。
  - 分享接收的提示文字（正在打开、没有能打开的链接、文件格式不对）、长按图标的快捷方式（搜索直播、录制中心、最近看过的两个直播间）、权限说明对话框（先说明再请求、永久拒绝时“去设置”）。
- 不包括（归哪里）：
  - 这些功能本身：后台播放和媒体会话在 [C02](../../C-直播间/C02-小窗、画中画、后台播放/README.md) 和 [O01](../../O-Android系统集成/O01-通知和前台服务/README.md)，画中画在 [O02](../../O-Android系统集成/O02-画中画/README.md)，分享接收和快捷方式在 [O03](../../O-Android系统集成/O03-分享接收和快捷方式/README.md)，权限在 [O04](../../O-Android系统集成/O04-权限/README.md)，录制通知的文字和按状态写标题在 [H05](../../H-录制/H05-录制通知/README.md)。
  - 应用自己画的启动页（A06.4）、口令导入对话框（A06.3）在 [A06](../A06-首页和全局/README.md)；应用内小窗和画中画里应用自己画的按钮在 [A07.8](../A07-直播间界面/A07.8-小窗/README.md)；录制通知的小图标形状随 [A10.3](../A10-录制界面/A10.3-录制按钮和状态图标/README.md)。
  - Windows、Linux 的窗口、托盘在 [A16.1](../A16-桌面界面/A16.1-桌面窗口/README.md)；iOS、macOS 的系统差异在 [A18](../A18-苹果平台界面/README.md)。

## 现状：做到哪、怎么工作的

- **用户看得到的**（Android）：
  - 后台播放时状态栏是单色电视小图标；媒体卡片的按钮读作“播放 / 暂停 / 停止”。
  - 录一个直播间：通知“正在录制 · 主播名”（准备中、重连中、合成中分别写“准备录制 / 正在重连 / 正在整理录像 · 主播名”，H05.1），正文“标题 · 清晰度”，顶上系统计时；录几个：“正在录制 N 个直播间”，正文是主播名，按钮“全部停止”。点通知或“录制中心”打开录制中心。被系统停掉或失败时另发“录制已停止”（单独的小图标，点开定位到那条任务）。
  - 画中画点一下有“暂停 / 播放”按钮，图标跟着状态变。
  - 桌面图标里的电视约占可见圆的六成，Android 13 起打开主题图标时用单色层；长按图标有“搜索直播”“录制中心”和最近看过的两个直播间。
  - 冷启动：系统启动画面浅色 `#FAF8FF`、深色 `#121318` 底加 Logo（不带白圈，和启动页一样大），13 起跟应用的“主题模式”。
  - 分享链接进来先提示“正在打开分享的直播间…”；分享的内容里没有直播间链接时说明原因。
- **内部怎么工作**：
  - 播放通知：`RoomMediaNotification`（`apps/pure_live/lib/features/live_play/logic/background_playback.dart:299`）用 audio_service，小图标 `drawable/ic_stat_playback`，按钮名称 `mediaControls`（:276）；画中画按钮 `PictureInPicture.bindPlayback`（:42 起）把房间的播放状态发给原生，原生用 `RemoteAction` 画按钮，点了回到 Dart 调暂停 / 继续。
  - 录制通知：Dart 在任务变化时算文字（`recordNotificationContent`，`apps/pure_live/lib/app/recording_notice.dart:22`），有变化才经 `AndroidRecordKeepAlive`（`lib/platform/recording_platform.dart:166`）发给原生前台服务 `RecorderForegroundService.kt`；不每秒刷新，计时用系统的 `setUsesChronometer`。
  - 分享和快捷方式：原生 `ShareIntakePlugin.kt` 收分享和打开文件、设动态快捷方式（`setShortcuts`）；Dart 侧 `ShareChannel`（`lib/platform/share_channel.dart:75`）和 `SystemIntake`（`lib/app/intake/system_intake.dart:27`，跟着观看记录更新快捷方式 :57）、`ShareIntake`（`lib/app/intake/share_intake.dart:52`）。
  - 权限：`showPermissionDialog`（`lib/shared/permission_prompts.dart:30`）先说明，`SystemPermissions`（`lib/platform/system_permissions.dart:26`）问通知和电池，回到应用后再查一次（`nextResume` :49）。
- **完成度**：A14.1 完成（2026-10-02，和 O03.2 一起合并），K90 冒烟看过后台播放通知的文字和按钮、录制通知的标题和按钮（S02.2）、画中画（S02.3）、分享链接直接进房（S02.3）。和设计不同的四处见 A14.1 的“实现和验证”。

## 代码地图

| 文件 | 职责 |
|---|---|
| `apps/pure_live/lib/features/live_play/logic/background_playback.dart` | 画中画可用性和进入方式（:16、:29）、`PictureInPicture`（:42，暂停 / 播放按钮）、设备控制（:180）、后台保活（:233）、媒体按钮中文 `mediaControls`（:276）、播放通知 `RoomMediaNotification`（:299）、后台策略（:393） |
| `apps/pure_live/lib/app/recording_notice.dart` | 录制通知的标题、正文、按钮文字和计时起点（:22，单个直播间按状态写标题 :59）、“录制已停止”的文字（`RecordingNotices` :94） |
| `apps/pure_live/lib/platform/recording_platform.dart` | `AndroidRecordKeepAlive`（:166）：有变化才把通知内容发给原生、“停止录制”回调 |
| `apps/pure_live/lib/platform/share_channel.dart` | 分享内容 `SharedPayload`（:15）、最近直播间快捷方式的数据（:69）、和原生的通道（:75，`setRecentRooms` :123） |
| `apps/pure_live/lib/app/intake/system_intake.dart`、`share_intake.dart`、`clipboard_rooms.dart` | 系统传进来的东西怎么处理：分享、打开文件、`purelive://`、剪贴板口令；提示文字（c10、c11） |
| `apps/pure_live/lib/shared/permission_prompts.dart`、`apps/pure_live/lib/platform/system_permissions.dart` | 权限说明对话框、后台播放和录制的权限流程；通知和电池的原生调用 |
| `apps/pure_live/android/app/src/main/kotlin/com/mystyle/purelive/MainActivity.kt` | 插件注册、画中画动作和接收器、`setSplashTheme`（13 起跟应用深浅色） |
| `apps/pure_live/android/app/src/main/kotlin/com/mystyle/purelive/RecorderForegroundService.kt`、`RecorderPlugin.kt` | 录制前台服务和通知（两个按钮、计时、“录制已停止”提醒类别）；`update`、`alert`、`stopAll` |
| `apps/pure_live/android/app/src/main/kotlin/com/mystyle/purelive/ShareIntakePlugin.kt`、`PermissionsPlugin.kt`、`SystemAccessPlugin.kt` | 分享接收和动态快捷方式；通知和电池权限；安装和本地网络权限 |
| `apps/pure_live/android/app/src/main/res/drawable/` | 小图标 `ic_stat_playback.xml`、`ic_stat_recording.xml`、`ic_stat_record_stopped.xml`；画中画 `ic_pip_play.xml`、`ic_pip_pause.xml`；快捷方式 `ic_shortcut_*.xml`；单色层 `ic_launcher_monochrome.xml`；启动画面 `splash_icon.xml`、`launch_background.xml`；电视横幅 `banner.png` |
| `apps/pure_live/android/app/src/main/res/mipmap-anydpi-v26/`、`values-v31/`、`values-night-v31/`、`values-night/` | 自适应图标（前景内缩 2%、单色层）；12 起的系统启动画面主题和底色 |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `apps/pure_live/test/platform/system_surfaces_test.dart` | 录制通知文字（一个、几个、按状态的标题、计时起点）、保活没变不发、“停止录制”、“录制已停止”何时发、媒体按钮中文、画中画按钮、资源文件（小图标、图标内缩和单色层、启动画面颜色和图标、快捷方式文字） |
| `apps/pure_live/test/intake_test.dart`、`test/shared/permission_prompts_test.dart` | 分享提示（c10、c11）、快捷方式；权限对话框和永久拒绝、第一次录制时的说明（O03.2） |

## 3.x 基线

- 播放通知：`git show v3.2.11:lib/player/core/live_audio_service.dart`（只在 Android 和 macOS 建，`:51-63` 类别和颜色，`:157-170` 标题、副标题、封面）、`live_audio_handler.dart:193-196`（暂停 / 播放、停止两个按钮，名称是 audio_service 默认英文），小图标是默认的 `mipmap/ic_launcher`。
- 录制通知：`android/app/src/main/kotlin/com/mystyle/pure_live/RecorderForegroundService.kt`（类别 `pure_live_recording` 名称“Recording” `:33-35`，小图标 `ic_launcher_foreground` `:240`，没有按钮）、`lib/recorder/services/recorder_background_service.dart:117-121`（“直播录制进行中”）；被系统停掉时不通知（`lib/recorder/pages/recorder/recorder_controller.dart:1036-1054`）。
- 画中画：`plugins/built_in_kotlin/floating/android/src/main/kotlin/eu/wroblewscy/marcin/floating/floating/FloatingPlugin.kt:88-110`（只给比例和源区域，没有动作按钮）。
- 分享和权限：3.x 的分享接收、口令导入、权限说明文字是基线（A14.1 c1 保留）。
- 必须保留：点通知回到直播间；定时关闭到点停止通知；录制用前台服务；3.x 的通知类别 id 不变（`pure_live_recording`，升级后名字跟着变）。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 系统启动画面在自选主题色、纯黑深色时仍是默认底色 | `values-v31/` | 冷启动一闪的底色和应用不同 | 不改（系统启动画面拿不到应用的主题色，设计“拿不准”第 6 条） |
| 分享链接的“正在打开…”提示没有转圈、3 秒后自己消失 | `share_intake.dart` | 慢的平台解析时提示可能先消失 | 提示条加关闭接口后再改（没有登记任务） |
| 最近直播间快捷方式用统一图标，没有主播头像；要先打开过一次应用才出现 | `ShareIntakePlugin.kt` | 两个直播间快捷方式看起来一样 | 以后有需要走 V01 提议 |
| HyperOS 是否读单色层、画中画菜单样子没逐项记录 | 资源 | 主题图标可能不变色 | [S03.1](../../S-质量和验证/S03-统一验证/README.md) |
| 从画中画回来后控制条卡住 | 直播间 | 回来要再点一次 | [O02.1](../../O-Android系统集成/O02-画中画/README.md) |
| 只录一个直播间时点前台录制通知不定位到任务 | 录制通知 | 少一步 | [H05.2](../../H-录制/H05-录制通知/README.md) |

## 相关决定和规范

- D-003（A14.1 的 X1～X4 按建议 A：录制通知两个按钮、“录制提醒”类别、三个快捷方式、单色层）、D-019（真机只点测试包）、D-005（通知、快捷方式、权限说明的文字中文，`res/values/strings.xml` 和 `values-en/`）。
- [specs/UI.md](../../specs/UI.md) 第 4 节（平台差异只在 A16.1、A14.1、A18 这几处，其他任务不写平台分支）。

## 测试和验证

- 自动测试：`cd apps/pure_live && flutter test test/platform/system_surfaces_test.dart test/intake_test.dart test/shared/permission_prompts_test.dart`。原生部分（通知的真实样子、`RemoteAction`、启动画面、快捷方式）测试只能查资源文件和发给原生的数据。
- 真机：[S02 的 CHECKLIST](../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 1 节第 10、11 条（后台播放通知、画中画）、第 3 节第 1 条（录制通知）、第 4 节第 11 条（分享、口令）。S02.2、S02.3 里通过的见上面“完成度”。

## 路线

1. [H05.1](../../H-录制/H05-录制通知/README.md)（待真机）和 [A10.3](../A10-录制界面/A10.3-录制按钮和状态图标/verify.md)：录制通知按状态的标题、两个小图标一起在 K90 上看。
2. [O02.1](../../O-Android系统集成/O02-画中画/README.md)：画中画回来后的控制条问题。
3. Windows 开工（X01）时按 c16 确认不加系统通知、任务栏按钮；苹果平台的系统界面在 A18。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [A 界面设计](../README.md)。

- 代码：`apps/pure_live/android/` 的资源、`features/live_play/mini/`
- 进度：`████████████████████` 100%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| A14.1 | 系统界面：通知、画中画窗口、启动画面、分享接收 | 界面 | 完成 | 2026-10-02 | 8cf3c21b7 | [设计或说明](A14.1-系统界面/README.md)、[记录](A14.1-系统界面/record.md)、[评审页](A14.1-系统界面/page/01-说明.jpg) |

<!-- docs:生成结束 -->
