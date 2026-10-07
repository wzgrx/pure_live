# O01 通知和前台服务

媒体通知、前台服务。

让应用在后台还能播、还能录的原生机制：前台服务、通知渠道、唤醒锁和 Wi-Fi 锁，以及点通知回到哪里。

## 范围

- 包括：
  - 直播间的系统媒体通知所依赖的原生部分：`MainActivity` 继承 audio_service 的 `AudioServiceActivity`（引擎缓存），清单里的 `AudioService`（`mediaPlayback` 前台服务）和 `MediaButtonReceiver`。
  - 后台播放时的唤醒锁和 Wi-Fi 锁（`pure_live/background_playback`）。
  - 录制的前台服务 `RecorderForegroundService`（`dataSync`）和它的通道 `pure_live/recorder`：启动要等真正进入前台、15 秒超时；被系统停掉（Android 15 的 6 小时上限、服务被杀）时告诉 Dart；录制时绑住媒体服务，避免划掉界面后引擎被 audio_service 销毁。
  - 两个通知渠道（“录制”、“录制提醒”）、通知小图标资源、点通知和按钮打开录制中心的 `PendingIntent`。
- 不包括（归哪里）：
  - 通知上的文字、标题怎么写、哪些状态发提醒 → H05（`app/recording_notice.dart`）、A14.1 c2～c6。
  - 直播间什么时候显示媒体通知、按钮做什么 → C02（`RoomBackgroundPolicy`、`RoomMediaNotification`）。
  - 录制什么时候开始、停止 → H02；通知权限的申请 → O04。

## 现状：做到哪、怎么工作的

用户看得到的：

- **媒体通知**：直播间开着“后台播放”或助眠时，进房播放就在通知栏出现（标题是直播间标题、正文是主播名、封面、“暂停”“停止”中文按钮，小图标是单色电视）；按 Home 后继续播放。没开时不显示（C01.2 的确认改动：Android 不允许应用进入后台后再启动前台服务）。
- **录制通知**：开始录制后常驻通知“正在录制 · 主播名”，正文“标题 · 清晰度”，系统计时从第一段开始；按钮“停止录制”“录制中心”；点通知打开录制中心。录制被系统停掉或在后台失败时发“录制已停止”提醒，点它打开录制中心并定位到那条任务（A08.5 的 F02 c2）。

内部怎么工作：

```text
媒体通知：Dart RoomMediaNotification.show（features/live_play/logic/background_playback.dart:299）
  → audio_service AudioService.init（渠道 com.mystyle.purelive.audio，小图标 drawable/ic_stat_playback）
  → 清单里的 com.ryanheise.audioservice.AudioService（mediaPlayback 前台服务）
后台锁：BackgroundKeepAlive.set（:233）→ pure_live/background_playback setKeepAlive
  → MainActivity.setPlaybackKeepAlive（MainActivity.kt:680-707）：PARTIAL_WAKE_LOCK + Wi-Fi 锁（Android 10+ 低延迟）
录制：AndroidRecordKeepAlive（platform/recording_platform.dart:166）第一个持有者 → pure_live/recorder setActive
  → RecorderPlugin.setActive（RecorderPlugin.kt:107）→ RecorderForegroundService.start → startForeground(dataSync)
  → onReady 回答 Dart（15 秒没进前台就失败，:48、:122）
  → 服务持有唤醒锁、Wi-Fi 锁，bindService(flags 0) 绑住 audio_service 的媒体服务（RecorderForegroundService.kt:292-304）
  系统停服务：onTimeout（Android 15，:257）或 onDestroy 非请求 → interrupted {timeout | service_stopped} → Dart 把任务标失败、发提醒
```

- 完成度：清点第 2 节 F-AND-07（媒体通知）完成并在 K90 看过（S02.2）；录制通知和按钮在 K90 看过（S02.2）；“划掉应用后继续录”没验证成（S02.3：HyperOS 的最近任务里上滑没删掉卡片）。

## 代码地图

| 文件 | 职责 |
|---|---|
| `apps/pure_live/android/app/src/main/kotlin/com/mystyle/purelive/MainActivity.kt` | 父类 `AudioServiceActivity`（:88，引擎缓存，媒体通知和录制在 Activity 销毁后继续）；`pure_live/background_playback` 通道（:231-243）和 `setPlaybackKeepAlive`（:680-707，`PARTIAL_WAKE_LOCK`、`WIFI_MODE_FULL_LOW_LATENCY`/`HIGH_PERF`，不计数） |
| `.../RecorderForegroundService.kt`（344 行） | `RecordWords`（:27，通知文字，缺的用 3.x 的默认）；服务（:86）：`start`、`update`、`alert`（每个任务一条提醒，请求码按任务 id 区分 :187）、`stop`；两个渠道 `pure_live_recording`（低重要性）、`pure_live_recording_alerts`（默认，:152-165）；`startForeground(dataSync)`（:236-240）；`onTimeout`（:257，Android 15 的上限）；锁（:274-290）；绑住媒体服务（:292-304）；通知（:323-343：计时器、“停止录制”、“录制中心”） |
| `.../RecorderPlugin.kt`（242 行） | 通道 `pure_live/recorder`：`setActive`（:107，等服务进前台再回答，15 秒超时）、`update`、`alert`、`storageGranted`/`requestStorage`（见 O04）；向 Dart 发 `interrupted`、`stopAll`（通知上的“停止录制”）；引擎分离时停服务（:67-77） |
| `apps/pure_live/android/app/src/main/AndroidManifest.xml` | 权限 `FOREGROUND_SERVICE`、`FOREGROUND_SERVICE_MEDIA_PLAYBACK`、`FOREGROUND_SERVICE_DATA_SYNC`、`POST_NOTIFICATIONS`、`WAKE_LOCK`（:4-28，照 3.x，`FOREGROUND_SERVICE_REMOTE_MESSAGING` 也是照抄 3.x 的声明，4.x 没有这种服务）；`AudioService`（:128-134）、`MediaButtonReceiver`（:135-140）、`RecorderForegroundService`（:142-145，`dataSync`，`stopWithTask="false"`） |
| `.../res/drawable/ic_stat_playback.xml`、`ic_stat_recording.xml`、`ic_stat_record_stopped.xml` | 通知小图标（单色，A14.1 c2、H05.1） |
| `apps/pure_live/lib/features/live_play/logic/background_playback.dart` | Dart 一侧：`BackgroundKeepAlive`（:233）、`RoomMediaNotification`（:299）、`mediaControls`（:276）——行为归 C02 |
| `apps/pure_live/lib/platform/recording_platform.dart`（404 行） | `AndroidRecordKeepAlive`（:166，第一个持有者启动、最后一个释放时停止，被系统停掉后拒绝自动重试直到用户手动开始）、`androidStorageAccess`（:322）、`platformAppRecording`（:348） |
| `apps/pure_live/lib/app/recording_notice.dart` | 录制通知的文字（H05） |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `apps/pure_live/test/platform/system_surfaces_test.dart`（12 个） | 录制通知文字（一个房间、几个房间、计时起点）；保活只在文字变化时发；“停止录制”停全部；“录制已停止”提醒；媒体按钮中文；小图标是单色、release 资源压缩后还在；请求码唯一 |
| `apps/pure_live/test/features/live_play/live_play_more_test.dart` | 离开应用的规则（后台播放时持锁、不暂停） |

## 3.x 基线

- `android/app/src/main/kotlin/com/mystyle/pure_live/RecorderForegroundService.kt`（249 行）和 `RecorderBackgroundPlugin.kt`（557 行，通道 `pure_live/recorder_background`，`Coordinator` 状态机 :83-85）：4.x 的录制前台服务照它改写，去掉了 Dart 侧另起引擎的部分（4.x 录制在主引擎里，靠 `AudioServiceActivity` 缓存引擎）。
- `android/app/src/main/kotlin/com/mystyle/pure_live/MainActivity.kt`（378 行）：也是 `AudioServiceActivity`；`pure_live/background_playback` 通道（:142）。
- `lib/player/core/live_audio_service.dart`（262 行）、`live_audio_handler.dart`（310 行）：手机上一播放就显示媒体通知；`background_playback_service.dart`（锁）。
- 3.x 的录制渠道叫英文 “Recording”，4.x 建渠道时改成中文（`RecorderForegroundService.channels` 的注释）。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 划掉应用后录制是否继续没验证成：HyperOS 最近任务里上滑没删掉卡片 | `RecorderForegroundService.kt:76-84`（绑住媒体服务的理由）、清单 `stopWithTask="false"` | 用户划掉应用后录制可能断 | S02.3 记了“真正划掉后再试”；没有单独登记任务，建议在 S02.5 第二阶段（弹幕和录制）做 |
| Android 15 起 `dataSync` 服务每天累计 6 小时，到时系统停掉录制（3.x 也是） | `RecorderForegroundService.kt:255-263` | 一天录超过 6 小时会断，第二天恢复 | 发布说明已写；改成 `mediaProcessing` 等别的类型要重新评估，未登记 |
| 媒体通知只在后台播放或助眠时显示 | `features/live_play/logic/background_playback.dart:431-438` | 和 3.x 不同（确认过的改动） | 不做 |

## 相关决定和规范

- D-004（只做 Android）、D-018（`enableBackgroundPlay`、`enableAsmrSleepMode` 键不变）、D-019（真机只点测试包）。
- A14.1 的 c2～c6（通知小图标、录制通知、按钮、提醒、媒体按钮中文）；H05.1（录制通知按状态写标题）。

## 测试和验证

- 自动测试：`cd apps/pure_live && flutter test test/platform/system_surfaces_test.dart`；服务真正进前台、系统停服务、锁只能在真机看。
- 真机：[CHECKLIST](../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 1 节第 10 条（后台播放和媒体通知）、第 3 节第 1、3 条（录制通知、划掉应用后继续录）；看前台服务用 `adb shell dumpsys activity services com.mystyle.purelive.v4dev`，看锁用 `adb shell dumpsys power | grep -i purelive`。

## 路线

- 这个子分类没有登记的任务。要做的真机项（划掉应用后继续录）建议放进 S02.5 第二阶段；H05.2（单个录制点通知定位到任务）在 H05。新的通知需求（例如开播提醒）先走 V01 提议。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [O Android系统集成](../README.md)。

- 代码：`apps/pure_live/android/`
- 进度：还没有任务


还没有任务。

<!-- docs:生成结束 -->
