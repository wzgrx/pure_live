# A07.15 画面上下滑避开系统底部手势区：上滑回桌面时不再误调亮度或音量

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能（画面手势的判定；不改样子，没有设计稿）
- 来源：上游对照 [W01.1](../../../W-上游借鉴/W01-定期对照/W01.1-2026-10-03上游对照/README.md)“4.x 也有的问题”第 3 行：上游 pure_live `1cdcb7b2a` 修了“从屏幕底边上滑回桌面时，先触发了画面的亮度或音量调节”（上游写死 48 高），4.x 的 `_onDragStart` 同样没有避开系统手势区；登记表说明“用系统给的手势区高度”
- 旧编号：T05f.4
- 相关：画面手势 [specs/UI.md](../../../specs/UI.md) 附录 A 第 4 条（左半亮度、右半音量）、第 5 条（竖屏全屏底部上滑回到面板）；竖屏全屏上下滑换台 [A07.3](../A07.3-竖屏全屏上下滑换台/README.md)（画面分三栏）；相邻任务 [A07.14](../A07.14-双击飞行弹幕面板一闪/README.md)（同在 `player/` 下的手势，依次做）；D-003

## 目标

全屏看直播时，用全面屏手势从屏幕底边上滑回桌面（或在沉浸模式下从底边划出系统栏），不再顺手把亮度或音量调掉；在画面中间正常上下滑，亮度和音量照旧。系统没有手势区的地方（电脑、平板键鼠、三键导航报告 0 的系统）行为不变。

为什么做：第二档。Android 全面屏手势是现在手机的默认，横屏全屏和竖屏全屏的画面一直铺到屏幕底边，回桌面是每次离开都要做的动作；误调的音量和亮度要用户再调回来（亮度是窗口亮度，离开直播间才恢复）。

## 3.x 和现状

| 方面 | 3.x（文件:行） | 现在（文件:行） | 要做到 |
|---|---|---|---|
| 拖动从哪里开始算亮度或音量 | `git show v3.2.11:lib/modules/live_play/widgets/video_player/video_controller_panel.dart:851-902`（`_onVerticalDragUpdate`：只看锁定、左右半屏，Windows 左半不调亮度），`:904-910`（`_onVerticalDragStart` 只判断竖屏全屏底部回到面板的区域）——同样没有避开系统手势区 | `apps/pure_live/lib/features/live_play/player/player_gestures.dart:143-169` 的 `_onDragStart`：先看竖屏全屏底部 `portraitRestoreZone`（96，`logic/room_layout.dart:174`），再按横坐标分 `pictureDragAt`（`logic/room_layout.dart:197`），然后读当前音量或亮度开始调；不看系统手势区 | 从系统手势区（屏幕底边，见 X1 是否加上顶边）开始的竖向拖动不调亮度、音量，也不换台 |
| 调节什么时候生效 | 每次移动都写（`:894-900`） | `_onDragUpdate`（`:185-200`）每次移动都调 `_apply`（`:121-135`）写系统音量或窗口亮度；系统接管手势时只来 `onVerticalDragCancel`（`:212-217`），已经写进去的不会退回 | 不变；只是不再开始 |
| 竖屏全屏底部上滑回到面板 | `:904-910`、`:920-930`：松手时才判断 | `:148-151`（底部 96 记为 `_restoring`），`:177-182` 松手时 `swipeRestoresPanel`（`logic/room_layout.dart:178`）；被系统取消的拖动不回到面板 | 不变（只在松手时生效，系统接管时没有松手） |
| 谁有这些手势 | 手机 | `build`（`:204-220`）：只在 `DeviceControls.available`（Android，`logic/background_playback.dart:184`）或有回到面板、换台时挂竖向拖动；锁定时 `enabled` 为假（`player/player_view.dart:641-645`） | 不变 |
| 全屏的系统栏 | — | 横屏全屏、竖屏全屏都是 `SystemUiMode.immersiveSticky`（`live_play_page.dart:550`、`:571`）：系统栏隐藏，从边上划先显示系统栏或回桌面 | 不变 |

哪些布局受影响：画面贴着屏幕底边的横屏全屏、竖屏全屏（竖屏全屏底部 96 已经归“回到面板”，所以主要是横屏全屏，以及 X1 的顶边）。竖屏普通布局的画面在屏幕上方，底边不在系统手势区；宽屏、电脑没有这类手势。

## 方案

- c1：`_onDragStart` 在判断竖屏全屏回到面板之后、`pictureDragAt` 之前，先看起点是不是在系统手势区：用 `MediaQuery.systemGestureInsetsOf(context)` 和 `MediaQuery.sizeOf(context)`，拿**全局**坐标 `details.globalPosition.dy` 比较（手势层不一定从屏幕顶上开始，用局部坐标会错）；在区里就把 `_dragging`、`_switching` 都留空直接返回，这次拖动什么都不调。判断写成纯函数放在 `logic/room_layout.dart`（`pictureDragAt` 旁边），便于单元测试。
- c2：顺序：竖屏全屏底部 96 的“回到面板”仍然最先（它只在松手时生效，系统接管时只有取消，不会误触发；而且它比手势区高，换成先判断手势区会让底边上滑回到面板失效）。
- c3：不加固定的保底高度：系统报告 0 时（电脑、iOS、三键导航在部分系统上）行为和现在一样（照登记表说明，不照上游写死 48）。
- 待选和决定：
  - X1：顶边要不要一起避开（沉浸模式下从顶边下拉出状态栏、通知栏时，左半会先调暗亮度）。**A**（建议）一起避开，用 `systemGestureInsets.top`，系统报告 0 时不变；B 只管底边（登记表标题只写了底边）。理由：同一个原因、同一行判断，代价是顶边那一条不能开始调节。
  - X2：左右两侧的返回手势区（`systemGestureInsets.left/right`）。**A**（建议）不管：返回手势是横向的，竖向拖动识别器只在竖向移动占优时才赢；B 也避开（横屏时左右边缘几十 dp 不能调）。
  - 按 D-003，没有回复时用 A。

## 验证

- 自动测试（做的时候写，先写改之前会失败的）：
  - 纯函数：给定屏幕大小、手势区和全局坐标，底边区内为真、区外为假、手势区为 0 时总是假（`apps/pure_live/test/features/live_play/room_swipe_test.dart`，`pictureDragAt` 的用例在 `:237-241`）。
  - 组件：横屏全屏、`DeviceControls.debugAvailable = true`、假的 `pure_live/device_controls` 通道（同 `room_popups_test.dart:250` 那条的做法），`MediaQueryData.systemGestureInsets` 底部 32：从底边 10 以内往上拖，没有 `gesture-level-volume`、通道没收到 `setVolume`；从画面中间往上拖，照旧调音量。竖屏全屏从底边上拖仍按 `swipeRestoresPanel` 回到面板。X1 选 A 时加顶边一条。
- 真机：待真机（K90，全面屏手势）：横屏全屏从底边上滑回桌面后回来，音量和亮度没变；竖屏全屏同样；画面中间上下滑照常；三键导航下各看一次。记下 K90 报告的手势区高度。

## 留下的问题

- 系统接管以前已经写进去的那几次移动现在不会退回；c1 之后从手势区开始的拖动根本不调，所以不需要退回。
- 3.x 也有同样的问题，修了以后和 3.x 的差别只在手势区那一条，不影响附录 A 第 4 条的用法。
