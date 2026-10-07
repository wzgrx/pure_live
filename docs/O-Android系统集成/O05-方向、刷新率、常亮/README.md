# O05 方向、刷新率、常亮

屏幕方向、刷新率声明、屏幕常亮的原生部分。

播放时屏幕怎么摆、刷多快、灭不灭：横屏全屏时请求哪种方向（开着旋转锁也要能翻转）、把视频帧率或高刷新率告诉系统的原生做法、播放时让屏幕保持常亮。

## 范围

- 包括：
  - **方向**：`platform/screen_orientation.dart` 的 `ScreenOrientation.landscape()`（Flutter 的两个横向 + Android 的 `SENSOR_LANDSCAPE`）、原生 `SystemAccessPlugin.sensorLandscape`；直播间和多画面进、出全屏时请求的方向（`live_play_page.dart`、`multiview_page.dart` 里的调用）。
  - **刷新率的原生部分**：`MainActivity.kt` 的 `pure_live/display_mode` 通道和 `applyRefreshRate`（Android 12+ 在 Flutter 的 Surface 上声明帧率、8～11 用窗口的首选刷新率、16+ 不播放时声明最低刷新率）、显示器变化的监听；Dart 一侧 `platform/display_mode.dart` 的通道封装。
  - **屏幕常亮**：`packages/live_player/lib/src/screen_wake.dart`（全应用一个计数）和 `LiveVideoView.keepScreenOn`；直播间、应用内小窗按设置“屏幕常亮”（`enableScreenKeepOn`）传值。
- 不包括（归哪里）：
  - 选哪个刷新率（策略：帧率的整数倍、没有整数倍时取最高、系统限速提示、设置里的“界面刷新率”）→ R02（R02.1、R02.2，`logic/room_refresh_rate.dart` 和 `display_mode.dart` 里的计算函数）。
  - 什么时候进全屏、全屏方向的设置（“进入全屏时的方向” `portraitFullscreenPolicy`：跟随直播源 / 跟随系统 / 始终横屏）、竖屏全屏 → C01、A07.2、A07.4。
  - 平板和折叠屏上系统忽略方向请求 → [O06](../O06-返回手势、平板和折叠屏/README.md)。
  - 画中画窗口比例 → O02；电视（不转屏）→ X03。

## 现状：做到哪、怎么工作的

用户看得到的：

- **横屏全屏**（手机；双击、全屏按钮、F，或横屏直播间开着“默认全屏”，或竖屏直播间点“横屏全屏”胶囊）：画面横过来，**手机翻转 180° 画面跟着翻**，开着系统的旋转锁也翻（issue #36，D-023；3.x 开着旋转锁时不翻）。退出全屏（O05.3）：手机自动旋转关着时，不管怎么进的都先转回竖屏、3 秒后放开方向（HyperOS 在锁定时会把 `user_rotation` 改成横屏，直接放开会停在横屏）；自动旋转开着时直接放开、跟着手机方向；从“横屏全屏”胶囊进的不管开没开都先转回竖屏。设置“进入全屏时的方向”选“跟随系统”时，横屏直播进全屏不锁方向、跟系统的自动旋转走（开着旋转锁就不转）。多画面的全屏一样按传感器翻转。
- **刷新率**：直播间播放时按视频帧率声明（例如 30 帧的流在 120 Hz 屏上请求 120 Hz 的整数倍关系，具体策略见 R02）；不播放时设置“界面刷新率”选“性能”就请求最高刷新率；系统把应用限制在 60 Hz 时设置里提示（D-010）。
- **屏幕常亮**（设置 → 视频 →“屏幕常亮”，默认开，3.x 键 `enableScreenKeepOn`）：开着时直播间、应用内小窗**播放或缓冲时**不灭屏，暂停后按系统超时灭屏；关掉后看直播也按系统超时灭屏；改设置立即生效。多画面和电视不看这个设置，播放时总是常亮。

内部怎么工作：

```text
方向：方向请求都走 ScreenOrientation（screen_orientation.dart），新的请求先取消还没到的“放开”
LivePlayPage._enterFullscreen（live_play_page.dart:524）
  竖屏全屏 → ScreenOrientation.portrait() = [portraitUp]（:549）
  跟随系统且不是“横屏全屏”胶囊 → ScreenOrientation.free() = []（:551，UNSPECIFIED）
  其他 → ScreenOrientation.landscape()（:553）
        = setPreferredOrientations([landscapeLeft, landscapeRight])（Flutter → Android USER_LANDSCAPE，旋转锁开时不翻）
        + Android：通道 pure_live/system_access 的 sensorLandscape → requestedOrientation = SENSOR_LANDSCAPE（SystemAccessPlugin.kt:112）
  退出 _exitFullscreen（:572）→ _restoreSystemUi（:591）→ ScreenOrientation.restore(upright: 胶囊进的)（:70）
        Android 问通道 autoRotate（SystemAccessPlugin.kt:122，只读 ACCELEROMETER_ROTATION）
        关着、问不到或 upright → [portraitUp]，3 秒（settle）后 []；开着 → 直接 []；iOS 直接 []
  多画面同样：landscape()（multiview_page.dart:403），退出 restore()（:416）
  下一次 setPreferredOrientations 会覆盖 SENSOR_LANDSCAPE
刷新率：RoomRefreshRate（logic/room_refresh_rate.dart:13）→ DisplayMode.setPlayback（display_mode.dart:260）
  → 通道 pure_live/display_mode setHighRefreshRate {enabled, frameRate, refreshRate}（MainActivity.kt:217）
  → applyRefreshRate（:784）：播放中 Android 12+ Surface.setFrameRate(帧率, FIXED_SOURCE, 只在无缝时切换)；
     8～11 窗口 preferredRefreshRate；不播放且要高刷：16+ setFrameRate(最高, AT_LEAST)，8～15 窗口首选；否则都清掉
  显示器变化（onDisplayChanged）、回到前台 → 160 ms 后重新声明（新的 Surface 会忘掉声明）→ displayModeChanged 告诉 Dart
常亮：LiveVideoView._syncWake（packages/live_player/lib/src/video_view.dart:77）
  keepScreenOn && (playing || buffering) → ScreenWake.hold()；否则 release()；全应用计数到 0 才关（wakelock_plus）
```

- 完成度：O05.1 屏幕常亮“完成”（登记表），但清点 F-ROOM-13 是“没验证”（记录写明没在 K90 看），归 S02.6 第 1 阶段；O05.2 横屏翻转“待真机”（提交时只用 `dumpsys` 看了请求的方向值：横着时 `SENSOR_LANDSCAPE`、离开时 `PORTRAIT`、3 秒后 `UNSPECIFIED`，没手动翻转手机）；刷新率的原生部分随 R02.1、R02.2 做完，R02.2 待真机。

## 代码地图

| 文件 | 职责 |
|---|---|
| `apps/pure_live/lib/platform/screen_orientation.dart`（104 行） | `ScreenOrientation`：`landscape()`（:37，先 Flutter 的两个横向，再在 Android 上调 `sensorLandscape`；通道出错时只是不翻转）、`portrait()`（:54）、`free()`（:60）、`restore({upright})`（:70，O05.3）；全应用一个“放开”定时器（`settle` 3 秒），任何请求先取消它（`_claim` :88） |
| `apps/pure_live/android/app/src/main/kotlin/com/mystyle/purelive/SystemAccessPlugin.kt` | `sensorLandscape`（:116-120）：`requestedOrientation = SCREEN_ORIENTATION_SENSOR_LANDSCAPE`；没有 Activity 时回答 false。`autoRotate`（:122-125）：只读 `Settings.System.ACCELEROMETER_ROTATION` |
| `apps/pure_live/lib/features/live_play/live_play_page.dart` | `_enterFullscreen`（:524，方向 :548-554）、`_enterPortraitFullscreen`（:560）、`_exitFullscreen`（:572）、`_restoreSystemUi`（:591） |
| `apps/pure_live/lib/features/multiview/multiview_page.dart` | 全屏 `ScreenOrientation.landscape()`（:403）、退出 `ScreenOrientation.restore()`（:416） |
| `apps/pure_live/android/app/src/main/kotlin/com/mystyle/purelive/MainActivity.kt` | `pure_live/display_mode`（:211-230：`setHighRefreshRate`、`getDisplayModeInfo`）；`highRefreshRateEnabled`、`playbackFrameRate`、`playbackWindowRate`（:102-110）；显示器监听（:142-153、`registerDisplayListener` :742）；`applyRefreshRate`（:784-835，只用数值不用类别，注释 :781-782）；`applySurfaceFrameRate`（:842，`CHANGE_FRAME_RATE_ONLY_IF_SEAMLESS`）；`flutterSurfaceView`（:860）；`displayModeInfo`（:875） |
| `apps/pure_live/lib/platform/display_mode.dart`（376 行） | `DisplayModeInfo`（:12）、`PlaybackRefresh`（:92）、计算函数 `normalizeFrameRate`、`frameRateMultiples`、`playbackRefreshRate`（:111-170，归 R02）；`DisplayMode`（:171：`applyHighRefreshRate` :250、`setPlayback` :260、60 Hz 限速检测 `_checkLimit` :327） |
| `apps/pure_live/lib/features/live_play/logic/room_refresh_rate.dart`（77 行） | `RoomRefreshRate`（:13）：直播间播放时按会话的帧率调 `DisplayMode.setPlayback`（R02.1） |
| `packages/live_player/lib/src/screen_wake.dart`（45 行） | `ScreenWake`：`hold`、`release`、全应用计数，`apply` 默认 `WakelockPlus.toggle` |
| `packages/live_player/lib/src/video_view.dart` | `LiveVideoView.keepScreenOn`（:28，默认开）、`_syncWake`（:77）；media_kit `Video` 自带的常亮关掉 |
| `apps/pure_live/lib/features/live_play/player/player_view.dart`、`mini/floating_window.dart` | 直播间画面（:503-516）和应用内小窗（:187）传 `enableScreenKeepOn` |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `apps/pure_live/test/features/live_play/live_play_layouts_test.dart` | 假的 `pure_live/system_access`（:64-74，`autoRotate` 默认关）；O05.3 组（:337）：自动旋转关着时全屏按钮、双击进出都先竖屏再放开，开着时直接放开，全屏里关掉直播间也先竖屏；“横屏全屏”胶囊进入时先两个横向再 `sensorLandscape`、退出转回竖屏 |
| `apps/pure_live/test/platform/screen_orientation_test.dart`（6 个） | `ScreenOrientation.restore`：关着、开着、问不到、`upright`、3 秒内再进全屏不被放开、iOS |
| `apps/pure_live/test/features/live_play/live_play_page_test.dart` | 屏幕常亮：关时直播间不请求，再开立即请求，离开释放（:439，F.1a） |
| `packages/live_player/test/frame_rate_test.dart` | `ScreenWake`：关时不请求、开时立即请求、视图销毁释放（:102）；两个视图共用计数、暂停释放（:118） |
| `apps/pure_live/test/platform/display_mode_test.dart`（6 个）、`test/features/live_play/room_refresh_rate_test.dart`（10 个） | 刷新率的通道和策略（R02） |

多画面：`multiview_page_test.dart` 的 O05.3 一条测退出时先竖屏再放开；进全屏的翻转只在真机看（S02.5 的 1D-06）。

## 3.x 基线

- 方向：`git show v3.2.11:lib/player/utils/fullscreen.dart`：`landScape`（:260-278）只调 `setPreferredOrientations([landscapeLeft, landscapeRight])`（:267-270），开着旋转锁时不翻；`verticalScreen`（:281-284）；启动时 `lib/common/global/platform/mobile_manager.dart:55-60` 放开四个方向。3.x 的清单和原生没有方向代码。
- 刷新率：3.x `MainActivity.kt` 的 `applyPreferredDisplayMode`（:311-339）：只在“高刷新率”开时把窗口 `preferredRefreshRate` 设成最高、不锁 `preferredDisplayModeId`；没有按视频帧率声明（4.x 的 R02.1 增强）。
- 常亮：`lib/modules/live_play/controllers/live_play_controller.dart:177-179`、`:252-260`（进房按设置 `WakelockPlus.toggle`，改设置立即生效，暂停也亮）；播放器建立和销毁时（`player_controller.dart:441`、`:530`）。
- 必须保留：[specs/UI.md](../../specs/UI.md) 附录 A 第 11 条（强制横屏全屏退出后恢复竖屏）、第 12 条（“默认全屏”）；`enableScreenKeepOn`、`portraitFullscreenPolicy` 键和含义不变（D-018）。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 横屏全屏开着旋转锁翻转没在真机手动翻过 | `screen_orientation.dart:13`、`SystemAccessPlugin.kt:112` | issue #36 已回复“已修复”并关闭，但没有真机结果 | [O05.2](O05.2-横屏全屏随手机方向翻转/README.md)（待真机，S02.5 的 1B-21、1B-22、1D-06） |
| 屏幕常亮没在真机看（开时 3 分钟不灭、关时按系统超时灭） | `packages/live_player/lib/src/screen_wake.dart` | 清点 F-ROOM-13 “没验证” | S02.6 第 1 阶段（CHECKLIST 第 1 节第 7 条） |
| 暂停时不常亮（3.x 在直播间里一直常亮） | `video_view.dart:79` | 暂停看弹幕时会灭屏 | 确认过的差别（O05.1 README），不做 |
| 多画面、电视不看“屏幕常亮”设置，播放时总常亮 | `features/multiview/widgets/cell_view.dart`、`tv/room/tv_live_play_page.dart`（没传 `keepScreenOn`） | 设置关了，多画面里照样不灭屏 | 没有任务；要跟设置时各加一个参数（O05.1 记录“合并时注意”） |
| “进入全屏时的方向：跟随系统”时，横屏直播进全屏用 `[]`（跟系统旋转锁），开着锁不翻 | `live_play_page.dart:553-554` | 和 D-023 的“开着旋转锁也翻”不同，但这是用户选的“跟随系统” | 按设计，不做 |
| 大屏（最短边 ≥600dp）上 Android 16/17 忽略方向请求 | 系统行为 | 平板、折叠屏展开时进全屏不会转 | 见 O06；按当前方向排，不做 |

## 相关决定和规范

- D-010（刷新率：播放中只用帧率声明，没有整数倍时取最高，系统限速提示；只用数值不用类别）、D-018、D-023（横屏全屏按传感器翻转，开着旋转锁也翻）。
- [specs/UI.md](../../specs/UI.md) 第 5.3 节（大屏方向锁定被系统忽略）、第 9 节（刷新率）、附录 A 第 11、12 条。

## 测试和验证

- 自动测试：`cd apps/pure_live && flutter test test/features/live_play/live_play_layouts_test.dart test/features/live_play/live_play_page_test.dart test/platform/display_mode_test.dart test/features/live_play/room_refresh_rate_test.dart`；`cd packages/live_player && flutter test test/frame_rate_test.dart`。只测到通道的调用。
- 真机：方向 `adb shell dumpsys window | grep -i -E 'mRotation|mCurrentRotation|requestedOrientation'`、`adb shell dumpsys activity activities | grep -i requestedOrientation`；常亮 `adb shell dumpsys power | grep -i -A2 wake`；刷新率 `adb shell dumpsys SurfaceFlinger | grep -i 'refresh\|fps'`。清单：CHECKLIST 第 1 节第 5、7、18 条；S02.5 的 1B-21、1B-22、1D-06。

## 路线

1. **O05.2**（待真机）：照 [verify.md](O05.2-横屏全屏随手机方向翻转/verify.md) 在 K90 上看，和 S02.5 第一阶段同一次上机；通过就改“完成”。
2. S02.6 第 1 阶段：屏幕常亮的开和关。
3. R02.2（待真机）：刷新率策略的真机在 R02，原生改动也从那里提。
4. 以后：多画面、电视要不要跟“屏幕常亮”设置，等用户反馈；没有任务。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [O Android系统集成](../README.md)。

- 代码：`MainActivity.kt`、`platform/display_mode.dart`、`platform/screen_orientation.dart`
- 进度：`███████████████████░` 94%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| O05.1 | 屏幕常亮跟随设置 | 功能 | 完成 | 2026-10-02 | b8462638a | [设计或说明](O05.1-屏幕常亮跟随设置/README.md)、[记录](O05.1-屏幕常亮跟随设置/record.md) |
| O05.2 | 横屏全屏随手机方向翻转，开着旋转锁也翻（issue #36） | 功能 | 待真机 | 2026-10-02 | 3c1aa45ee | [设计或说明](O05.2-横屏全屏随手机方向翻转/README.md)、[任务书](O05.2-横屏全屏随手机方向翻转/brief.md)、[真机验证](O05.2-横屏全屏随手机方向翻转/verify.md) |
| O05.3 | 退出横屏全屏后回到竖屏，不改动系统的旋转锁定方向（自动旋转关着时 HyperOS 把 user_rotation 改成横屏） | 原生 | 待真机 | 2026-10-08 | — | [设计或说明](O05.3-退出横屏全屏后回到竖屏/README.md)、[任务书](O05.3-退出横屏全屏后回到竖屏/brief.md)、[记录](O05.3-退出横屏全屏后回到竖屏/record.md) |

<!-- docs:生成结束 -->
