# A07.15 画面上下滑避开系统底部手势区：任务书

## 背景

- 来源：上游对照 `docs/W-上游借鉴/W01-定期对照/W01.1-2026-10-03上游对照/README.md`“4.x 也有的问题”：上游 pure_live `1cdcb7b2a` 修了“从屏幕底边上滑回桌面时，先触发了画面的亮度或音量调节”（上游写死底部 48）；4.x 有同样的问题。登记表说明：用系统给的手势区高度。
- 现象：Android 全面屏手势，横屏全屏看直播，从屏幕底边上滑回桌面：回来后音量（右半）或亮度（左半）变了。复现：横屏全屏 → 在画面右半从屏幕最底边快速上滑回桌面 → 回到应用看音量。
- 为什么做：第二档；回桌面是高频动作，误调要用户手动调回。
- 已经做过的：画面手势（`player/player_gestures.dart`，3.x `BrightnessVolumnDargArea` 的移植）；竖屏全屏底部上滑回到面板和三栏换台（A07.2、A07.3）。

## 目标和验收

1. 从系统手势区（屏幕底边 `systemGestureInsets.bottom` 以内；X1 选 A 时还有顶边 `systemGestureInsets.top`）开始的竖向拖动：不调音量、不调亮度、不换台，也不出现音量或亮度条。
2. 从画面其他地方开始的拖动和现在完全一样（左半亮度、右半音量，竖屏全屏中间一栏换台）。
3. 竖屏全屏底部 96 上滑回到面板不受影响（它先判断）。
4. 系统报告手势区为 0（电脑、iOS 等）时行为不变；不加固定的保底高度。
5. 改之前会失败的测试先写；全部测试和门禁通过。

X1、X2 见 README“待选和决定”；按 D-003，没有回复时按建议 A。

## 现状（读代码得出，写文件:行）

`apps/pure_live/lib/features/live_play/` 省略前缀：

- `player/player_gestures.dart:143-169` 的 `_onDragStart`：
  - `:148-151`：有 `onSwipeUp`（竖屏全屏）且起点在底部 `portraitRestoreZone`（96，`logic/room_layout.dart:174`）里 → 记为回到面板，返回；
  - `:153`：`pictureDragAt`（`logic/room_layout.dart:197`）按横坐标分亮度、换台、音量；
  - `:154-158`：换台；`:159`：不是 Android（`DeviceControls.available`，`logic/background_playback.dart:184`）就不调；
  - `:160-168`：开始调，先读当前值。**没有看系统手势区。**
- `:185-200` 的 `_onDragUpdate` 每次移动都调 `_apply`（`:121-135`），立即写系统音量或窗口亮度；系统接管手势时只来 `onVerticalDragCancel`（`:212-217`），已写的不会退回。
- `:204-220`：只在 Android 或有回到面板、换台时挂竖向拖动；`player/player_view.dart:641-645` 锁定时 `enabled: false`。
- 全屏是 `SystemUiMode.immersiveSticky`（`live_play_page.dart:550`、`:571`）；离开直播间时 `live_play_page.dart:466` 把亮度还给系统。

## 3.x 基线

- `git show v3.2.11:lib/modules/live_play/widgets/video_player/video_controller_panel.dart:817-1006`（`BrightnessVolumnDargArea`）：`:851-902` 的 `_onVerticalDragUpdate` 只看锁定和左右半屏（Windows 左半不调）；`:904-910` 的 `_onVerticalDragStart` 只判断竖屏全屏底部回到面板的区域。3.x 也没有避开系统手势区。
- 要保留的：附录 A 第 4 条（左侧上下滑调亮度、右侧调音量；锁定锁住所有手势）、第 5 条（竖屏全屏时在底部上滑退出）。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5、8、14 节）。
2. `docs/specs/ENGINEERING.md`；`docs/specs/UI.md` 附录 A 第 4、5 条。
3. 本文件夹的 `README.md`；`docs/A-界面设计/A07-直播间界面/A07.3-竖屏全屏上下滑换台/README.md`（三栏）；`docs/A-界面设计/A07-直播间界面/README.md`（直播间结构）。

## 范围

- 可以改：`apps/pure_live/lib/features/live_play/player/player_gestures.dart`（`_onDragStart`）；`apps/pure_live/lib/features/live_play/logic/room_layout.dart`（加一个纯函数，放在 `pictureDragAt` 旁边）；`apps/pure_live/test/features/live_play/room_swipe_test.dart`、`room_popups_test.dart`（或新建 `player_gestures_test.dart`）；本文件夹。
- 不能改：`portraitRestoreZone` 的值和回到面板的规则；左右分区和三栏的规则（`pictureDragAt`）；调节的灵敏度；A07.14 要改的 `player/player_view.dart` 的单击和双击；原生代码（`MainActivity.kt`）；版本号、`assets/version.json`、`assets/releases.json`；签名配置；3.x 的设置键名和含义。

## 方案和阶段

| 阶段 | 做什么（对应 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | c1：在 `logic/room_layout.dart` 加纯函数（例如 `inSystemGestureArea({required double globalY, required double screenHeight, required EdgeInsets insets})`，X1 选 A 时同时看顶边）；`_onDragStart` 在 `:148-151` 之后、`:152` 之前用 `MediaQuery.systemGestureInsetsOf(context)`、`MediaQuery.sizeOf(context)` 和 `details.globalPosition.dy` 判断，在区里直接返回（`_dragging`、`_switching` 保持空）。c2：回到面板仍然最先判断。c3：系统报告 0 时不加保底 | `player/player_gestures.dart`、`logic/room_layout.dart`、测试 | 验收 1～5；门禁通过 |

注意用全局坐标：手势层在竖屏普通布局里只是屏幕上方的一块，用局部坐标会把画面底边当成屏幕底边。

## 测试

- 纯函数（`room_swipe_test.dart`，`pictureDragAt` 的用例在 `:237-241`）：底边区内为真、区外为假、手势区 0 时总为假；X1 选 A 时顶边同样。
- 组件（先写，改之前跑一次确认失败）：横屏全屏、`DeviceControls.debugAvailable = true`（`tearDown` 里还原为 `null`）、假的 `pure_live/device_controls` 通道记录 `setVolume`（同 `room_popups_test.dart:250` 那条的做法）；用 `MediaQuery`（`MediaQueryData.systemGestureInsets` 底部 32）包住，或设 `tester.view` 的手势区：
  - 右半从底边 10 以内往上拖 → 没有 `gesture-level-volume`，通道没收到 `setVolume`；
  - 右半从画面中间往上拖 → 照旧调音量；
  - 竖屏全屏从底边往上拖 → 仍回到面板（`swipeRestoresPanel`）。
- 测试里不访问真实平台；等待用 `tester.pump`。
- 跑 `apps/pure_live` 的 `flutter analyze`、全部 `flutter test`、`dart format --output=none --set-exit-if-changed .`；`python3 tools/gate/check_ui_structure.py`。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 全面屏手势，横屏全屏，在画面右半从屏幕最底边上滑回桌面，再回来 | 音量没变，回来时没有音量条 |
| 2. 同上，在左半 | 亮度没变 |
| 3. 横屏全屏，在画面中间上下滑 | 照常调亮度、音量 |
| 4. 竖屏全屏，从底部上滑 | 回到面板（底边上滑回桌面时不回到面板） |
| 5. （X1 选 A）横屏全屏从顶边下拉出状态栏 | 亮度没变 |
| 6. 换成三键导航重复 1 | 记下结果（系统可能报告 0，这时和改之前一样） |

把 K90 报告的手势区高度写进 `record.md`（可以临时打日志看 `MediaQuery.systemGestureInsetsOf`）。

## 风险和注意

- 和 A07.14 改的是相邻的代码（同在 `player/` 下的手势），依次做。
- 沉浸模式下系统怎么分配这次拖动（先显示系统栏还是直接回桌面）各家系统不同；判断只看起点，不依赖系统是否取消。
- 只点测试包；不碰 3.x（D-019）。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 分支 `ai/A07.15` 或本机工作区；提交信息以 `[A07.15]` 开头（英文）；不推 master。
- 提交前：`dart format --output=none --set-exit-if-changed .`、`flutter analyze`、全部 `flutter test`（`apps/pure_live`）；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”、更新登记表的 `next`、`branch`。

## 报告（中文，简洁）

X1、X2 按哪个做的；每条验收做到没有；改了哪些文件（文件:行）；测试数量（改之前失败的那几条）；要在真机上看的；可能冲突的文件（`player/player_gestures.dart`、`logic/room_layout.dart`）。
