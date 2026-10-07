# O02.1 画中画复验：任务书

## 背景

- 来源：K90 第二轮真机测试（2026-10-01）：“从画中画回到应用后，控制条一直显示，按钮（包括全屏）点了没反应，直到退出直播间；新进直播间正常。”S02.1 第 a 条（`docs/S-质量和验证/S02-真机验证/S02.1-真机问题修复/record.md` 第 127 行起）做了防御性修改，提交 `6e0be540b`，当时“真机没能复现（手机在用）”，留给下一轮真机。
- 现象怎么出现：直播间（竖屏普通布局）→ 上栏小窗按钮进系统画中画 → 点画中画窗口回到应用 → 控制条一直显示、点哪里都没反应。
- 为什么现在做：第二档、小；画中画是常用功能，这个问题出现时只能退出直播间。S02.3 只看了进入（CHECKLIST 第 1 节第 11 条“部分”）。
- 已经做过的：S02.1（播放器在三种布局之间保持同一个元素；回来时控制条重新计时、解锁、强制出一帧）；A14.1 c7（窗口按钮）；A07.8 J1（离开应用自动画中画）；A07.8 c9、A07.11 B09 c8（关了画中画时的提示条）。

## 目标和验收

1. 按钮进入 → 点窗口回到应用：控制条显示，4 秒后自己隐藏；点画面再出来；全屏、清晰度、弹幕开关都有反应；画面不黑、不重新起播。
2. 从最近任务（多任务界面）回来：同第 1 条。
3. 暂停着进画中画再回来：控制条一直显示（D-012），中间 ▶ 点了继续播放。
4. 横屏全屏时进画中画再回来：回到横屏全屏，锁已解除，返回键先退出全屏。
5. 开着“离开应用时自动画中画”按 Home：进画中画；回来同第 1 条；记下画中画第一帧是不是整个直播间页面（截图或录屏）。
6. 画中画窗口里系统画的按钮：在播时“暂停”，点了暂停、文字变“播放”；再点继续。
7. 关掉本应用画中画权限后点小窗按钮：不进画中画，下栏上方提示条“无法打开画中画：系统设置里关掉了“纯粹直播”的画中画”，带“去设置”和 ✕；“去设置”打开系统页。测完恢复权限。
8. 结果逐条写进 `verify.md`；第 1、2 条通过时，登记表改“完成”，并告诉维护者更新 CHECKLIST 第 1 节第 11 条和清点 F-AND-06 的备注（本任务不改 S 组和清点）。
9. 任何一条不通过：现象、日志、根因线索写进 `verify.md`，报告里建议开的修复任务（编号由维护者定）。

## 现状（读代码得出，写文件:行）

`apps/pure_live/lib/` 下：

- 页面：`features/live_play/live_play_page.dart`：`_pip`（:140）由 `_onMini`（:424-427）按 `RoomMiniWindow.compact` 设；`_pip` 为真时只画播放器（:757）；播放器用同一个 `_playerKey`（:771，传给 `RoomPlayer` :784-789），三种布局之间不重建。
- 播放器：`features/live_play/player/player_view.dart`：`didUpdateWidget`（:241-268）进画中画时停掉隐藏计时，回来时 `_controls = true`、`_locked = false`、`_scheduleHide()`、`SchedulerBinding.instance.scheduleForcedFrame()`；`_scheduleHide`（:312-319）4 秒，暂停时不计时；画中画时画 `MiniPlayerSurface`（:560-576）。
- 小窗：`features/live_play/mini/room_mini_window.dart`：`compact`（:75）= 画中画中、或 Android 上准备中、或桌面小窗；`enter`（:123）→ `_enterPip`（:132-170：`availability`，被系统关了就 `showPipDisabledToast`，否则 `preparing = true`、等一帧、`PictureInPicture.enter`）；`_AutoPip`（:256-300）跟着设置、路由、播放状态调 `setAutoEnter`（:290）。
- 通道：`features/live_play/logic/background_playback.dart` 的 `PictureInPicture`（:42），`active`（:47）由原生 `changed` 设；原生 `apps/pure_live/android/app/src/main/kotlin/com/mystyle/purelive/MainActivity.kt`：`enterPictureInPicture`（:447）、`setAutoEnterPictureInPicture`（:490）、`onPictureInPictureModeChanged`（:585）、窗口按钮（:532-567）。
- 根因线索（S02.1）：修改前每次进出画中画都会丢掉播放器整棵子树（控制条状态、手势层、视频纹理都重建）；现象像是“界面帧没再更新、只有视频纹理在刷新”。如果还卡：重点看回来时 Flutter 有没有收到 `resumed`（`AppLifecycleState`）、有没有出新帧。

## 3.x 基线

- `git show v3.2.11:lib/player/core/player_manager.dart`：`enablePip`（:2808）先画紧凑布局（`isPipPreparing`，:2839），等一帧再 `floating.enable(ImmediatePiP(aspectRatio, sourceRectHint))`（:2844-2853）；回来时照常（3.x 没有这个问题的记录）。
- 3.x 没有窗口按钮、没有关了画中画的说明、没有离开应用自动画中画；这三项是 4.x 确认过的改动，不要当成和 3.x 不一致。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 10 节真机验证、第 14 节规则）。
2. `docs/S-质量和验证/S02-真机验证/README.md`（上机的做法：构建、安装、带前台检查的输入、截图）和 `CHECKLIST.md` 第 1 节第 11 条。
3. 本文件夹的 `README.md`；`docs/S-质量和验证/S02-真机验证/S02.1-真机问题修复/record.md` 第 a 条；`docs/O-Android系统集成/O02-画中画/README.md`；`docs/C-直播间/C02-小窗、画中画、后台播放/README.md` 的已知问题。

## 范围

- 可以改：本文件夹（`verify.md`、`verify/` 截图）。
- 不能改：任何代码（`apps/`、`packages/`）；登记表以外的其他组文档（CHECKLIST、FEATURES 的更新写进报告由维护者做）；用户的正式包 `com.mystyle.purelive` 和 3.x 数据；版本号、`assets/version.json`、`assets/releases.json`；签名配置。

## 方案和阶段

| 阶段 | 做什么（对应 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | c1～c5：按下面的真机步骤逐条做，结果和截图写进 `verify.md`；卡住时抓日志 | `verify.md`、`verify/*.jpg` | 9 步都有结果；通过时登记表改“完成”（`date` 写验证日期）；不通过时写清现象和日志位置 |

规模小，一个阶段。

## 测试

- 不改代码，不加测试。上机前在本机跑一遍相关的自动测试，确认构建的提交是好的：`cd apps/pure_live && flutter test test/features/live_play/live_play_page_test.dart test/features/live_play/live_play_mini_window_test.dart test/platform/system_surfaces_test.dart`。

## 真机验证（维护者在 K90 上做）

准备：构建合并后的 master（profile 或 debug，测试包 `com.mystyle.purelive.v4dev`）装到 K90；关注里有一个正常的横屏直播间（例如哔哩哔哩）和一个竖屏主播（抖音）；每次点按前确认前台是测试包；截图缩到宽 540。

| 步骤 | 期望 |
|---|---|
| 1. 进横屏画面的直播间（竖屏普通布局），点上栏小窗按钮 | 进系统画中画，只有画面和小窗弹幕，没有应用自己的按钮 |
| 2. 点画中画窗口放大回到应用 | 回到直播间，控制条显示；不碰屏幕 4 秒后控制条隐藏；点画面控制条出来；点全屏进横屏全屏；返回退出全屏 |
| 3. 再进画中画，然后从最近任务（多任务界面）点纯粹直播回来 | 同第 2 步 |
| 4. 暂停后进画中画，再回来 | 控制条一直显示（不自动隐藏），中间 ▶ 点了继续播放 |
| 5. 双击进横屏全屏，点右侧锁，然后点上栏小窗进画中画，再回来 | 回到横屏全屏、锁已解除（手势可用）；返回先退出全屏 |
| 6. 设置 → 视频 → 小窗 → 打开“离开应用时自动画中画”；进直播间播放中按 Home | 自动进画中画（录屏看第一帧是不是整个直播间页面缩小，记下来）；点窗口回来同第 2 步 |
| 7. 画中画里点系统画的按钮 | 在播时是“暂停”，点了暂停、按钮变“播放”；再点继续播放 |
| 8. 进抖音竖屏主播，点小窗按钮；在画中画里等 10 秒 | 窗口是竖的（按真实比例）；记下有没有黑边 |
| 9. `adb shell appops set com.mystyle.purelive.v4dev PICTURE_IN_PICTURE ignore`，回直播间点小窗按钮；点“去设置”；回来后 `adb shell appops set com.mystyle.purelive.v4dev PICTURE_IN_PICTURE allow` | 不进画中画；下栏上方提示条“无法打开画中画：系统设置里关掉了“纯粹直播”的画中画”，带“去设置”和 ✕，不自动消失；“去设置”打开系统的画中画设置页（或应用详情页）；恢复权限后小窗按钮正常 |

卡住时抓什么（第 2～6 步任何一步控制条不消失、点了没反应）：

- `adb logcat -c` 后重做一遍，再 `adb logcat -d -v time | grep -iE 'purelive|flutter|ActivityTaskManager|PictureInPicture' > verify/logcat.txt`；看回来时 Activity 的 `onResume`、Flutter 的 `AppLifecycleState.resumed` 有没有到。
- profile 构建时用 DevTools 的 Performance 看回来后有没有新帧；或者 `adb shell dumpsys gfxinfo com.mystyle.purelive.v4dev` 回来前后各一次，看帧数有没有增加。
- `adb shell dumpsys activity activities | grep -i -A5 purelive` 看 Activity 是否还停在画中画模式。

## 风险和注意

- 每次点按前确认前台是测试包（`adb shell dumpsys activity activities | grep mResumedActivity`）；不点正式包和 3.x（D-019）。
- 第 9 步改了画中画权限，**测完必须恢复** `allow`；第 6 步打开的设置测完关掉（默认关）。
- HyperOS 的画中画窗口可能有系统自己的手势（拖到边上隐藏），回来时用点窗口放大，不要拖。
- 和 S02.5 第一阶段的 1B-23、1D-04 是同样的操作，同一次上机时结果分别写进两边的 `verify.md`，不用重复做。

## 环境和提交

- 构建：`source ~/tools/purelive-env.sh`；根目录 `bash tools/ffmpeg_kit/fetch.sh`、`flutter pub get`；`cd apps/pure_live && flutter build apk --profile`（或 `--debug`），`adb -s 192.168.1.2:5555 install -r build/app/outputs/flutter-apk/app-profile.apk`。
- 提交只有文档：`verify.md` 和截图，提交信息以 `[O02.1]` 开头（英文）；登记表改状态后运行 `python3 tools/docs/docs.py`、`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：已经做完的步骤写进 `verify.md` 并提交，在 `verify.md` 末尾写“停在第几步”；登记表写 `next`（从第几步接着做）。

## 报告（中文，简洁）

9 步各自的结果；卡住时的现象、日志位置和根因线索；第 6 步自动进入时第一帧的样子、第 8 步有没有黑边（决定 C02 要不要开修复任务）；建议更新的 CHECKLIST 和 FEATURES 条目；权限和设置都已恢复。
