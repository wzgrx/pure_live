# C02 小窗、画中画、后台播放

应用内小窗、系统画中画、后台播放的逻辑。

直播间离开屏幕中央以后怎么继续：缩成应用内悬浮小窗、进系统画中画、切到后台时暂停或继续播放，以及后台时的锁和媒体通知。

## 范围

- 包括：
  - **应用内悬浮小窗**：离开直播间时接过 `RoomRuntime`（`FloatingRoom`），再进同一个房间时交回；大小、位置、按钮、状态、小窗弹幕的规则（`logic/mini_window.dart`）和组件（`mini/`）。
  - **系统画中画的 Dart 一侧**：按钮进入、离开应用时自动进入（`autoPipOnLeave`）、系统关了本应用画中画时的提示、比例、画中画里只画画面和小窗弹幕、窗口里的暂停按钮（`PictureInPicture` 在 `logic/background_playback.dart`，`RoomMiniWindow` 在 `mini/room_mini_window.dart`）。
  - **桌面小窗**的直播间一侧（`RoomMiniWindow._enterDesktop`、`backToRoom`、`close`、`togglePin`）；窗口本身归桌面外壳（O03.1、X01）。
  - **后台**：离开应用 1.5 秒后暂停、回来继续（`RoomBackgroundPolicy`）；后台播放和助眠时持有唤醒锁和 Wi-Fi 锁（`BackgroundKeepAlive`）、显示媒体通知（`RoomMediaNotification`，audio_service）；手势用的媒体音量和窗口亮度（`DeviceControls`）。
  - 冷门播放设置里和离开、小窗有关的：播放器留给下一个房间、小窗跟随竖屏源（C02.1）。
- 不包括（归哪里）：
  - 小窗、画中画窗口、通知的样子 → A07.8、A14.1。
  - `MainActivity.kt` 的 `pure_live/pip`、`pure_live/background_playback`、`pure_live/device_controls` 原生实现 → O02、O01；画中画回来后控制条的复验 → O02.1。
  - 纯音频和音量的播放层 → G05；录制的前台服务 → O01、H。
  - 小窗拖角改尺寸、尺寸设置、画中画弹幕随窗口缩放（新功能提议）→ V01.5。

## 现状：做到哪、怎么工作的

用户看得到的：

- **应用内小窗**（设置 → 视频 → 小窗 →“离开直播间时小窗播放”，默认关，3.x 键 `floatPlay`）：正在播的直播间返回时缩到右下角（首页窄屏时在底栏上方，离边 16），宽 = 屏幕短边 × 0.56、限 220～360，竖屏画面高为 1.2 倍；可以拖，转屏后留在屏幕内；点一下显示按钮 3 秒（左上回直播间、右上关闭、中间播放/暂停，失败时是刷新），按钮显示时再点回直播间；有菜单和弹窗时隐藏、继续播；打开多画面或另一个直播间时关掉。
- **系统画中画**：画面上栏的小窗按钮进入；“离开应用时自动画中画”（同一组，默认关）开着且正在播画面（不是纯音频、暂停、未开播）时，回桌面或切应用自动进入（Android 12+ 由系统动画进入，8～11 在 `onUserLeaveHint` 进入）；画中画里只有画面、小窗弹幕和录制标记，系统画的暂停/播放按钮是中文（A14.1 c7）；系统设置关了本应用的画中画时，提示条带“去设置”（A07.8 c9、A07.11 B09 c8）。
- **后台**：离开应用 1.5 秒后暂停，回来继续；“后台播放”开着或自动助眠中不暂停，持有唤醒锁和 Wi-Fi 锁；媒体通知（标题、主播、封面、暂停/播放、停止）只在后台播放打开或助眠中显示，而且要在前台时就出现（Android 不允许应用在后台启动前台服务）。
- **画中画、小窗的比例**：画面的真实宽高；第一帧前用平台声明的尺寸（G04.1）；竖屏画面在“小窗跟随真实画面比例”关时固定 9:16（C02.1 c2）；系统限制在 1:2.39～2.39:1（`MainActivity.kt:416-419`）。

内部怎么工作：

```text
按小窗按钮 → RoomMiniWindow.enter（mini/room_mini_window.dart:123）
  └─ Android：PictureInPicture.availability → preparing=true（页面先只画播放器，等一帧）
       → PictureInPicture.enter(宽, 高) → 原生 enterPictureInPictureMode
       → 原生 onPictureInPictureModeChanged → 通道 changed → PictureInPicture.active
       → LivePlayPage._onMini → _pip=true → 只画播放器（同一个 GlobalKey，不重建）
离开应用 → RoomBackgroundPolicy.onHidden（logic/background_playback.dart:472）
  ├─ 后台播放开 / 助眠中：BackgroundKeepAlive.set(true)，照常播
  └─ 否则 1.5 秒后 pause()，记 _pausedByUs；onResumed（:493）时 resume()
  （画中画时 Flutter 报 inactive，不算离开）
返回离开直播间 → LivePlayPage.dispose → shouldFloatOnLeave → FloatingRoom.show(runtime)
```

- 完成度：清点 8.4（MINI）4 项和第 2 节 F-AND-06（画中画）、F-AND-07（媒体通知）都写完成。K90 上看过：后台播放和媒体通知（S02.2）、画中画进入（S02.3）。没看过：从画中画回来后的控制条和关掉画中画权限时的提示条（[O02.1](../../O-Android系统集成/O02-画中画/O02.1-画中画复验/README.md)）、自动画中画（O02.1 一起看）、C02.1 的小窗比例和播放器复用（按 D-029 判为完成，没有专门的真机任务，日常回归照 CHECKLIST 第 1 节第 11、12 条看）。

## 代码地图

`apps/pure_live/lib/features/live_play/` 下：

| 文件 | 职责 |
|---|---|
| `logic/mini_window.dart`（259 行） | 小窗的规则，不含组件：`MiniKind`、`MiniStatus` 和 `miniStatusOf`、`expectedPictureSize`、`miniPictureSize`（:83，竖屏不跟随时 9:16）、`inAppMiniSize` 和 `inAppMiniOffset`（大小、位置）、`shouldFloatOnLeave`（离开时转不转小窗）、`shouldAutoEnterPip`（自动画中画的条件）、`CompactDanmakuMetrics` 和 `compactDanmakuFps`（小窗弹幕字号、速度、帧率）、`withoutEmoteCodes`（纯文字） |
| `logic/background_playback.dart`（517 行） | `PictureInPicture`（:42，`pure_live/pip`：`supported`、`availability`、`enter`、`openSettings`、`setAutoEnter`、窗口按钮 `bindPlayback`、`active`）；`DeviceControls`（:180，`pure_live/device_controls`：媒体音量、窗口亮度）；`BackgroundKeepAlive`（:233，`pure_live/background_playback` 的唤醒锁和 Wi-Fi 锁）；`mediaControls`（:276）和 `RoomMediaNotification`（:299，audio_service 的通知）；`RoomBackgroundPolicy`（:393：`_syncNotification` :431、`onHidden` :472、`onResumed` :493） |
| `logic/room_runtime.dart` | `FloatingRoom`：应用内小窗持有的房间（见 [C01](../C01-进房和房间逻辑/README.md)） |
| `logic/player_standby.dart` | 离开时留播放器（见 C01） |
| `mini/room_mini_window.dart`（328 行） | `RoomMiniWindow`（:31）：小窗按钮做什么（`enter` :123、Android 画中画 `_enterPip` :132、桌面小窗）、`compact`（:75，页面只画播放器）、比例 `_pictureSize`（:106）；`_AutoPip`（:256）跟着设置、路由和播放状态登记自动画中画；`showPipDisabledToast`（:316）；`RoomMiniScope` |
| `mini/floating_window.dart`（206 行） | `FloatingRoomLayer`（:24）：应用最上层显示 `FloatingRoom.instance`，拖动、避开底栏、转屏后留在屏幕内、有弹层时隐藏；画面传 `keepScreenOn`（:187，O05.1） |
| `mini/mini_player.dart`（616 行） | `MiniPlayerSurface`（:47）：三种小窗共用的画面和按钮（回直播间、关闭、中间播放/暂停或刷新、桌面的置顶和滚轮音量）、状态层、纯音频封面 |
| `mini/compact_danmaku.dart`（220 行） | `CompactDanmakuLayer`（:24）：小窗弹幕（“小窗弹幕”页的设置），单独一层，不重画画面；暂停时照“暂停时的弹幕”设置停住或继续飞 |

测试（`apps/pure_live/test/`）：

| 测试文件 | 覆盖什么 |
|---|---|
| `features/live_play/live_play_mini_window_test.dart`（23 个） | 规则（大小、位置、弹幕、状态、转小窗条件、自动画中画条件、桌面小窗大小）；应用内小窗（同一个播放器、按钮、状态、有弹层时隐藏、多画面关掉、鼠标）；桌面小窗；Android 画中画（系统关了时的提示条、只有画面、自动画中画只在播放时登记） |
| `features/live_play/live_play_more_test.dart` | 后台规则：离开暂停、开后台播放不暂停、不可见时不判断卡住 |
| `features/live_play/room_extras_test.dart` | C02.1：留播放器、小窗比例 |
| `platform/system_surfaces_test.dart` | 媒体通知按钮的中文（A14.1 c6）、画中画窗口的暂停按钮（c7） |
| `features/live_play/live_play_page_test.dart` | 从画中画回来控制条重新计时（M13.16） |

## 3.x 基线

- `lib/player/core/player_manager.dart`（5028 行，`git show v3.2.11:lib/player/core/player_manager.dart`）：`enablePip`（:2808）先画紧凑布局、等一帧再进画中画（`isPipPreparing`），带 `sourceRectHint`（:2843）；`_updateActiveAndroidPip`（:1055）画中画里画面比例变了就更新窗口；`showAppFloating`（:2970）、`closeAppFloating`（:3158）应用内小窗（flutter_floating）。
- `lib/player/core/playback_lifecycle_coordinator.dart`：离开 1.5 秒（`hiddenPauseDelay` :34）；`background_playback_policy.dart`、`background_playback_service.dart`（锁）。
- `lib/player/core/live_audio_service.dart`（262 行）、`live_audio_handler.dart`（310 行）：媒体通知，手机上一播放就显示。
- 插件（`pubspec.yaml`）：floating（:185-186，本地 AGP 9 补丁）、flutter_floating（:188）、volume_controller（:123）、screen_brightness（:120-122），4.x 都换成了 `MainActivity` 的通道或 Flutter 自己画。
- 必须保留：[specs/UI.md](../../specs/UI.md) 附录 A 第 8 条（应用内小窗：有弹层时隐藏；手机上第一次点显示控件，再点回到直播间；只有有画面且没有加载错误时才转为小窗）。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 从画中画回来后控制条卡住（K90 第二轮出现过），S02.1 做了防御性修改（同一个播放器元素、回来时重新计时并强制出一帧），未复验 | `player/player_view.dart:241-268`、`live_play_page.dart:771`（`_playerKey`） | 控制条不消失、按钮没反应，要退出直播间 | O02.1 |
| 离开应用自动进画中画时，页面不会先变成“只有画面”（按钮进入时有 `preparing`） | `mini/room_mini_window.dart:256-300`（`_AutoPip` 只登记参数）对比 `:132-170` | 系统动画的第一帧可能截到整个直播间页面 | O02.1 一起看 |
| 画中画里画面比例变了（例如换了宽高比不同的清晰度），只有开着“离开应用时自动画中画”时才更新窗口比例；3.x 一直更新（`_updateActiveAndroidPip`） | `mini/room_mini_window.dart:286-290` | 窗口有黑边 | O02.1 复验时看，确认后开任务 |
| 没传 `sourceRectHint`（3.x 有） | `MainActivity.kt:447-461` | 进入动画从整个窗口缩，而不是从画面 | 小，暂不做 |
| 后台时未开播的房间开播会出声：`onHidden` 在离开 1.5 秒后只判断一次，会话那时没在播就不管，之后定时刷新开播的播放没人暂停；后台时也不补出媒体通知 | `logic/background_playback.dart:472-490`、`:431-440`；开播在 `logic/room_controller.dart:775-778` | 手机在口袋里突然出声，通知栏没有东西可以停 | **没有任务**（原归 C01.3，D-029 关掉后没有去处）；详见 [C01 的已知问题](../C01-进房和房间逻辑/README.md)，建议在 C01 开新任务，修在 `RoomBackgroundPolicy` 或控制器 |
| 小窗不能拖角改尺寸、没有尺寸设置 | — | 新功能 | V01.5（第三档） |

## 相关决定和规范

- D-012（暂停时控制层不自动隐藏，画中画回来也一样）、D-018（`floatPlay`、`autoPipOnLeave`、`portraitPipFollowSource`、`enableBackgroundPlay`、`enableAsmrSleepMode` 键不变）。
- [specs/UI.md](../../specs/UI.md) 附录 A 第 8 条；A07.8 的设计（[小窗](../../A-界面设计/A07-直播间界面/A07.8-小窗/README.md)，J1 自动画中画、J2 置顶、J3 桌面小窗关闭）；A14.1 c2（通知小图标）、c6（按钮中文）、c7（画中画暂停按钮）。

## 测试和验证

- 自动测试：`cd apps/pure_live && flutter test test/features/live_play/live_play_mini_window_test.dart test/features/live_play/live_play_more_test.dart test/platform/system_surfaces_test.dart`。原生进出画中画、通知、锁只能测到通道的调用。
- 真机：[CHECKLIST](../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 1 节第 10（后台播放和通知）、11（画中画）、12（应用内小窗）条。

## 路线

1. O02.1：在 K90 上复验画中画进出（按钮和自动两种），顺带看上表第 2、3 条。
2. 后台开播不出声：等维护者决定开任务（见 C01 的已知问题），修在 `RoomBackgroundPolicy`（离开以后才开始的播放立即暂停并记成“我们暂停的”）。
3. S02.5 第一阶段的 1D 组（小窗、画中画、多画面）会顺带看到应用内小窗和画中画的暂停按钮（A07.10、A07.11），结果写在各自任务的 `verify.md`。
4. 以后：V01.5（小窗尺寸）确认后，规则加在 `logic/mini_window.dart`，界面在 A07。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [C 直播间](../README.md)。

- 代码：`features/live_play/mini/`、`logic/background_playback.dart`
- 进度：`████████████████████` 100%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| C02.1 | 冷门的播放设置：退出时销毁播放器、小窗跟随竖屏源、竖屏诊断、小窗弹幕预览、内存紧张清缓存、键盘媒体键 | 功能 | 完成 | 2026-10-02 | 7b37e6f5f | [设计或说明](C02.1-冷门的播放设置/README.md)、[记录](C02.1-冷门的播放设置/record.md) |

<!-- docs:生成结束 -->
