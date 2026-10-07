# O02 画中画

系统画中画。

Android 系统画中画的原生一侧：能不能用、怎么进、窗口比例、离开应用时自动进、窗口里的暂停按钮、系统设置关了本应用画中画时怎么说明，以及进出时把状态告诉 Dart。

## 范围

- 包括：
  - `MainActivity.kt` 的 `pure_live/pip` 通道：`isSupported`、`status`、`enter`、`openSettings`、`setPlaying`、`setAutoEnter`（Dart → 原生），`changed`、`togglePlay`（原生 → Dart）；`onUserLeaveHint`、`onPictureInPictureModeChanged`；窗口按钮的广播 `com.mystyle.purelive.PIP_TOGGLE` 和它的接收器。
  - 清单 `android:supportsPictureInPicture="true"`、`resizeableActivity="true"`、`configChanges`（进出画中画不重建 Activity）；窗口按钮图标 `res/drawable/ic_pip_pause.xml`、`ic_pip_play.xml`。
  - 通道在 Dart 一侧的约定（方法名、参数、返回值），代码在 `features/live_play/logic/background_playback.dart` 的 `PictureInPicture`（和 C02 共用，改通道时两边一起改）。
- 不包括（归哪里）：
  - 直播间什么时候进画中画、画中画里画什么（只有画面、小窗弹幕和录制标记）、自动画中画的条件、从画中画回来后控制条怎样 → [C02](../../C-直播间/C02-小窗、画中画、后台播放/README.md)（`mini/room_mini_window.dart`、`logic/mini_window.dart`、`player/player_view.dart`）。
  - 画中画窗口按钮的样子和文字、“无法打开画中画”提示条的样子 → A14.1 c7、A07.8 c9、A07.11。
  - 应用内悬浮小窗（Flutter 自己画）和桌面小窗 → C02、A07.8、X01。
  - 小窗尺寸设置、拖角改尺寸、画中画弹幕随窗口缩放（新功能提议）→ V01.5。

## 现状：做到哪、怎么工作的

用户看得到的：

- 直播间画面上栏的小窗按钮（Android）：系统设置允许时直接进系统画中画，画面在别的应用上方继续播；系统设置关了本应用的画中画时不进，下栏上方出现提示条“无法打开画中画：…”，带“去设置”（打开系统的本应用画中画设置页，厂商没有这一页时打开应用详情页）和关闭。
- 设置 → 视频 → 小窗“离开应用时自动画中画”（`autoPipOnLeave`，默认关）开着、而且画面正在播（不是纯音频、暂停、未开播）时，按 Home 或切到别的应用自动进画中画。
- 画中画窗口里有系统画的一个按钮：在播时“暂停”、暂停时“播放”（中文，A14.1 c7）；点它暂停或继续。3.x 的窗口里没有这个按钮。
- 窗口比例跟画面：横屏 16:9 左右，竖屏主播按真实比例（或在“小窗跟随真实画面比例”关时 9:16，C02.1 c2），超出系统允许的 1:2.39～2.39:1 时取边界值。

内部怎么工作：

```text
Dart PictureInPicture.availability()  → 通道 status → pictureInPictureStatus()（MainActivity.kt:441）
     unsupported（没有画中画特性或低于 Android 8）/ disabled（AppOps 关了）/ allowed
Dart PictureInPicture.enter(宽, 高)   → 通道 enter → enterPictureInPicture（:447）
     比例 pictureInPictureRatio（:416，夹到 1/2.39～2.39，按千分之一取整）
     + 窗口按钮 pictureInPictureActions（:532）→ enterPictureInPictureMode
     → 回答 entered / disabled / failed（异常也算 failed）
系统进出画中画 → onPictureInPictureModeChanged（:585）→ 通道 changed(bool) → PictureInPicture.active
自动进入：Dart setAutoEnter(enabled, 宽, 高) → setAutoEnterPictureInPicture（:490）
     Android 12+：setPictureInPictureParams(setAutoEnterEnabled)，回桌面时系统自己平滑进入
     Android 8～11：记下比例，onUserLeaveHint（:509）里 enterPictureInPictureMode
窗口按钮：Dart bindPlayback → 通道 setPlaying {playing, play, pause}（:545）
     playing 为 null 时不显示按钮；第一次有房间时注册 PIP_TOGGLE 接收器（Android 13+ RECEIVER_NOT_EXPORTED）
     点按钮 → 广播 → pipReceiver → 通道 togglePlay → Dart 暂停或继续
```

- 完成度：清点第 2 节 F-AND-06（系统画中画）“完成”，K90 上看过从直播间进画中画（S02.3）。没看过：从画中画回来后控制条（S02.1 改过，复验 O02.1）、关掉画中画权限时的提示条（S02.5 的 1B-23）、自动画中画、窗口按钮暂停（S02.5 的 1D-04）。
- 3.x 用 floating 插件（本地打了 AGP 9 补丁），4.x 改成自己的通道，不再维护补丁副本；多了系统关了画中画时的说明、窗口按钮、Android 12+ 的自动进入。

## 代码地图

| 文件 | 职责 |
|---|---|
| `apps/pure_live/android/app/src/main/kotlin/com/mystyle/purelive/MainActivity.kt` | `PIP_CHANNEL`（:94）、`PIP_TOGGLE`（:96）；状态 `pipPlaying`、按钮文字（默认“播放”“暂停”，:116-118）、接收器（:120-124）、`autoEnterPip` 和 `autoEnterRatio`（:127-128）；通道分派（:267-297）；`pictureInPictureSupported`（:411，Android 8+ 且有 `FEATURE_PICTURE_IN_PICTURE`）、`pictureInPictureRatio`（:416）、`pictureInPictureAllowed`（:426，AppOps `OPSTR_PICTURE_IN_PICTURE`，查不到时当允许）、`pictureInPictureStatus`（:441）、`enterPictureInPicture`（:447）、`openPictureInPictureSettings`（:467，先 `android.settings.PICTURE_IN_PICTURE_SETTINGS` 再应用详情）、`setAutoEnterPictureInPicture`（:490）、`onUserLeaveHint`（:509）、`pictureInPictureActions`（:532）、`setPictureInPicturePlaying`（:545）、`onPictureInPictureModeChanged`（:585）；`onDestroy` 注销接收器（:729-736） |
| `apps/pure_live/android/app/src/main/AndroidManifest.xml` | `MainActivity` 的 `supportsPictureInPicture`、`resizeableActivity`（:67-68）、`configChanges`（:66，含 `screenSize|smallestScreenSize|screenLayout`，进出画中画不重建） |
| `apps/pure_live/android/app/src/main/res/drawable/ic_pip_pause.xml`、`ic_pip_play.xml` | 窗口按钮的图标（只从原生引用；`system_surfaces_test.dart` 检查 release 资源压缩后还在） |
| `apps/pure_live/lib/features/live_play/logic/background_playback.dart` | Dart 一侧 `PictureInPicture`（:42）：`active`（:47）、`bindPlayback`/`unbindPlayback`（:72、:88，按持有者，最后一个放开时按钮消失）、`supported`（:109）、`availability`（:121）、`enter`（:137）、`openSettings`（:153）、`setAutoEnter`（:165）；`RoomBackgroundPolicy._syncNotification`（:431）里随播放状态调 `bindPlayback` |
| `apps/pure_live/lib/features/live_play/mini/room_mini_window.dart` | 调用方（C02）：按钮进入 `_enterPip`（:132）、自动进入 `_AutoPip`（:256，`setAutoEnter` 在 :290）、`showPipDisabledToast`（:316） |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `apps/pure_live/test/features/live_play/live_play_mini_window_test.dart` | 用假的 `pure_live/pip` 通道（:821、:840）：系统关了画中画时说明并给“去设置”、画中画里只有画面（:868）；自动画中画只在画面播放时登记（:895）；自动画中画的条件（:333） |
| `apps/pure_live/test/platform/system_surfaces_test.dart` | 画中画窗口按钮（:177 起，A14.1 c7：播放时“暂停”、暂停时“播放”，点了切换）；按钮图标在 release 资源压缩后还在（:232） |
| `apps/pure_live/test/features/live_play/live_play_page_test.dart` | 从画中画回来控制条重新计时、能点（:203，M13.16） |

原生的进出、系统动画、AppOps 只能在真机看。

## 3.x 基线

- `git show v3.2.11:pubspec.yaml`：`floating`（:185-186，`plugins/built_in_kotlin/floating`，本地 AGP 9 补丁）。
- `lib/player/core/player_manager.dart`：`enablePip`（:2808）先 `isPipPreparing = true` 画紧凑布局（:2839）、等一帧再 `floating.enable(ImmediatePiP(aspectRatio, sourceRectHint))`（:2844-2853）；画中画中画面比例变了 `_updateActiveAndroidPip`（:1055，带 `sourceRectHint` :1073）更新窗口。
- 3.x 不检查系统设置是否关了画中画（关了就什么都不发生），窗口里没有按钮，没有离开应用时自动进入（4.x 的 `autoPipOnLeave` 是 A07.8 J1 定的）。
- 3.x 的 `MainActivity.kt`（378 行）没有画中画代码，都在插件里；清单同样 `supportsPictureInPicture="true"`（`android/app/src/main/AndroidManifest.xml:56`）。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 从画中画回来后控制条卡住（K90 第二轮出现过），S02.1 做了防御性修改（同一个播放器元素、回来时重新计时并强制出一帧），没复验 | `apps/pure_live/lib/features/live_play/player/player_view.dart:241-268` | 控制条不消失、按钮没反应，要退出直播间 | [O02.1](O02.1-画中画复验/README.md) |
| 自动进画中画（Android 12+ 由系统进入）时页面不会先变成“只有画面”，按钮进入时才有 `preparing` | `mini/room_mini_window.dart:256-300` 对比 `:132-170` | 系统动画的第一帧可能截到整个直播间页面，画中画里一瞬间是缩小的整页 | O02.1 一起看；确认后在 C02 开任务 |
| 画中画中画面比例变了（换清晰度、竖屏主播第一帧前后），只有开着“离开应用时自动画中画”时才通过 `setAutoEnter` 更新窗口比例；按钮进入的不更新 | `mini/room_mini_window.dart:286-290`；原生没有单独的“改比例”方法 | 窗口有黑边或画面被裁 | O02.1 复验时看；要改时通道加一个 `update`（`setPictureInPictureParams` 只改比例） |
| 没传 `sourceRectHint`（3.x 有）、没关 `setSeamlessResizeEnabled` | `MainActivity.kt:450-453`、`:495-500` | 进入动画从整个窗口缩，而不是从画面那一块；Android 12+ 改窗口大小时视频可能闪一下 | 小，暂不做；O02.1 发现明显问题再开任务 |
| 窗口按钮的接收器第一次绑定房间时注册，只在 `onDestroy` 注销 | `MainActivity.kt:549-557`、`:729-736` | 没有影响（只收本应用的广播）；记下来免得以为漏了 | 不做 |

## 相关决定和规范

- D-004（只做 Android）、D-012（暂停时控制层不自动隐藏，画中画回来也一样）、D-018（`autoPipOnLeave`、`portraitPipFollowSource` 键不变）、D-019（真机只点测试包）。
- A07.8 的设计（J1 自动画中画）、A07.8 c9 和 A07.11 B09 c8（关了画中画时的提示条）、A14.1 c7（窗口按钮）。

## 测试和验证

- 自动测试：`cd apps/pure_live && flutter test test/features/live_play/live_play_mini_window_test.dart test/platform/system_surfaces_test.dart test/features/live_play/live_play_page_test.dart`。只测到通道的调用和 Dart 一侧的状态。
- 真机：[CHECKLIST](../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 1 节第 11 条；S02.5 的 1B-23（关掉画中画权限）、1D-04（窗口按钮暂停）；临时关画中画权限用 `adb shell appops set com.mystyle.purelive.v4dev PICTURE_IN_PICTURE ignore`，测完 `allow`。看窗口参数用 `adb shell dumpsys activity activities | grep -i -A3 pip`。

## 路线

1. **O02.1 画中画复验**（第二档，小）：K90 上按钮进入和自动进入两种，回来后控制条、提示条、窗口按钮、比例；和 S02.5 第一阶段的 1B、1D 组同一次上机。
2. O02.1 确认上表第 2、3 条是真问题后，在 C02 开修复任务（Dart 一侧为主，比例更新要在这里加通道方法）。
3. 以后：V01.5（画中画弹幕随窗口缩放）确认后，可能要原生报窗口尺寸（`onPictureInPictureModeChanged` 带上 `newConfig` 的大小）。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [O Android系统集成](../README.md)。

- 代码：`android/.../MainActivity.kt`、`features/live_play/mini/`
- 进度：`░░░░░░░░░░░░░░░░░░░░` 0%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| O02.1 | 画中画复验：从画中画回来后控制条卡住的问题 | 验证 | 未开始 | — | — | [设计或说明](O02.1-画中画复验/README.md)、[任务书](O02.1-画中画复验/brief.md) |

## 还没完成的

- **O02.1 画中画复验：从画中画回来后控制条卡住的问题**（未开始，第二档，规模 小）

<!-- docs:生成结束 -->
