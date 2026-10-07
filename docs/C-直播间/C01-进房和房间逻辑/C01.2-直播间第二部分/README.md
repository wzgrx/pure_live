# C01.2 直播间（第二部分）

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能（模块重构，含 Android 原生）
- 来源：C01.1 记录“留给后续”的菜单、工具、后台和画中画部分（模块重构计划 M13.14）
- 旧编号：M13.14、T05a.2
- 相关：依赖 C01.1、N02.1（`DlnaCastController`）、H02.1（录制接口）、I01.2（分享、弹幕设置面板）、L01.1（节目单和回看规则）、G02.1（后台规则、房间音量键、纯音频）；后续 C02.1、C03.1、A07.6、A07.8、A14.1；记录 [record.md](record.md)

## 目标

补齐 3.x 直播间除主要流程外的功能：右上角菜单（打开直播间、切换直播间、投屏、定时关闭、房间音量、获取直链、分享、新窗口）、录制按钮、纯音频和自动助眠、画中画、后台播放和系统媒体通知、音量和亮度手势、网络电视节目单和回看、弹幕模板和上下留白、礼物行。3.x 用三个插件做的画中画、音量、亮度改成 `MainActivity` 里的两个通道。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11`） | 现在 | 结果 |
|---|---|---|---|
| 菜单 | `modules/live_play/widgets/button/live_play_menu_button.dart`（217 行，:189-206 九项） | `buttons/room_menu_button.dart`（`RoomMenuEntry` :111、`roomMenuGroups` :158，A07.6 分成三组） | 一致；分组和小菜单是 A07.6、A07.12 的改动 |
| 打开直播间 | `services/room_external_opener.dart`（245 行，25 个平台分支写死网页地址） | `externalRoomTarget`（`room_menu_button.dart:30`）：网页用适配器的 `room.link`，只有 App 跳转按平台写 | 改（记录问题 2） |
| 投屏、获取直链 | `castPlayUrlByRoomId`、`getPlayUrlByRoomId` 重新取详情和清晰度（`common/utils/live_url_tool.dart:388`、`:405`） | `dialogs/stream_dialogs.dart` 的 `showStreamPanel`：用直播间已有的清晰度，只取所选档的地址 | 改（问题 1） |
| 定时关闭和自动助眠 | `TimerController`（`controllers/timer_controller.dart`）和 `LiveAudioService` 两个互不知道的计时器 | `LiveRoomController.setSleepTimer`（`logic/room_controller.dart:614`）一个计时器，助眠就是按 `asmrSleepMinutes` 开的定时 | 改（问题 4） |
| 房间音量 | `dialogs/room_volume_dialog.dart`、`player/core/live_room_volume_manager.dart`，键 `room_vol_<平台>_<房间>` | `dialogs/room_dialogs.dart` 的 `RoomVolumePanel`、`setVolume`/`saveVolume`，同一个键 | 一致（手机用系统音量） |
| 画中画、音量、亮度 | floating（要本地 AGP 9 补丁）、volume_controller、screen_brightness 三个插件 | `MainActivity.kt` 的 `pure_live/pip`、`pure_live/device_controls` 通道；Dart 一侧 `logic/background_playback.dart` 的 `PictureInPicture`、`DeviceControls` | 改（问题 3） |
| 后台播放 | `player/core/playback_lifecycle_coordinator.dart`（离开 1.5 秒暂停，:34）、`background_playback_service.dart` | `RoomBackgroundPolicy`（`background_playback.dart:393`），1.5 秒同 3.x | 一致 |
| 媒体通知 | `live_audio_service.dart`、`live_audio_handler.dart`，手机上一播放就显示 | `RoomMediaNotification`（`:299`），只在后台播放打开或助眠中显示 | 改（Android 不允许进后台后再启动前台服务） |
| 节目单和回看 | `widgets/video_player/iptv_schedule_dialog.dart`、`iptv_programme_policy.dart` | `dialogs/iptv_guide.dart`、`playCatchup`/`backToLive` | 一致 |
| 礼物 | 各平台上报但不显示 | 聊天列表里的礼物行，可关（`live_play.showGifts`） | 增强（问题 5，B-21） |

## 结果

- 提交：`13bc7fac1`（2026-10-01，`feat(app): live room part 2 - cast, record, share, gifts, background play, PiP, IPTV guide (M13.14)`），合并 `98f7d90f4`。
- 做了：当时新增 9 个文件、改 5 个（`features/live_play/` 共 15 个文件约 5100 行），另改 `shared/danmaku/danmaku_settings.dart`、`packages/live_player`（只加 `setPresentationVisible`）、`apps/pure_live/pubspec.yaml`（`audio_service`、`live_cast`）和 `android/`：`MainActivity` 父类改成 audio_service 的 `AudioServiceActivity`（同 3.x，引擎缓存，媒体通知和录制在 Activity 销毁后继续），清单加 `AudioService`（`mediaPlayback`）和 `MediaButtonReceiver`。逐项见 [record.md](record.md) 的“做法”和“与 v3 的功能对照”。
- 偏差：本地互动、应用内悬浮小窗、Windows 小窗、竖屏全屏的其余部分、弹幕其余设置、全屏顶栏的时间和电量、快手 App 跳转、预测返回当时没做（见下）。
- 测试：新增 12 个（`live_play_more_test.dart` 8 个、`live_play_more_page_test.dart` 3 个、`packages/live_player/test/session_test.dart` 1 个），`flutter analyze` 无问题；`flutter build apk --debug` 通过。
- 之后的变化：`room_menu_button.dart`、`record_button.dart` 搬到 `buttons/`，`stream_dialogs.dart`、`room_dialogs.dart`、`iptv_guide.dart` 搬到 `dialogs/`，`background_playback.dart` 搬到 `logic/`，`player_gestures.dart` 搬到 `player/`；`room_switcher.dart` 被 A07.13 的 `switch_room/room_switch_panel.dart` 取代；录制按钮的菜单变成 A07.6 的录制面板（`record/record_panel.dart`）。

## 验证

- 自动测试：`apps/pure_live/test/features/live_play/live_play_more_test.dart`（现在 8 个）、`live_play_more_page_test.dart`（现在 4 个，含 Y01.1 加的投屏先申请本地网络权限）。
- 真机：[S02.2](../../../S-质量和验证/S02-真机验证/S02.2-K90冒烟/record.md) 后台播放、媒体通知（中文按钮）、录制按钮和通知通过；[S02.3](../../../S-质量和验证/S02-真机验证/S02.3-K90验证主流程/record.md) 画中画进入、菜单各项（只看了菜单）通过。没看的：投屏到真电视（清点 F-RT-01，CHECKLIST 第 1 节第 13 条）和网络电视节目单回看（第 17 条）归 [S02.6](../../../S-质量和验证/S02-真机验证/S02.6-K90补验/README.md)；外部 App 跳转（第 14 条）没有专门的任务，按 D-029 判为完成（打开 App 的方式和哔哩哔哩、抖音一样走系统，关键部分不靠本应用的原生代码），日常回归时看。

## 留下的问题

- 记录“留给后续”各项的去向：真机检查 → S02.2、S02.3（投屏和外部跳转仍没看，见上）；应用内悬浮小窗和 Windows 小窗 → A07.8；本地互动 → A08.2；竖屏全屏显示模式、方向覆盖、诊断 → A07.2、C02.1；弹幕帧率、字体、纯文字 → D05.1；画面弹幕的点按和长按 → A08.4；全屏顶栏的时间和电量 → A07.4；快手 App 跳转、预测返回 → C03.1；移动数据清晰度 → O03.1。
- 缺的接口：消息模型的表情片段 → D03.2；`share_plus` 和 `window_manager` → O03.1；比页面活得久的播放持有者 → A07.8 的 `FloatingRoom`。
- 本任务没有剩下的问题。
