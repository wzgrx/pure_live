# A07.15 画面上下滑避开系统底部手势区：记录

- 日期：2026-10-08
- 执行者：Claude
- 分支和提交：本机工作区，提交 `[A07.15]`
- 任务书：[brief.md](brief.md)；设计或说明：[README.md](README.md)

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| c1 | 做了 | 起点在系统手势区（底边 `systemGestureInsets.bottom`，X1 选 A 也看顶边 `top`）的竖向拖动不调亮度、音量，不换台，不出现亮度或音量条 |
| c2 | 做了 | 竖屏全屏底部 96 的“回到面板”仍然最先判断 |
| c3 | 做了 | 系统报告 0 时不变，没有保底高度 |
| X1 | 选 A | 顶边一起避开（按 D-003 没有回复时用建议 A） |
| X2 | 选 A | 左右两侧的返回手势区不管 |

## 根因

- `apps/pure_live/lib/features/live_play/player/player_gestures.dart` `_onDragStart`（改前 `:143-169`）只看竖屏全屏底部 96 和左右分区，不看系统手势区；之后每次移动都直接写系统音量或窗口亮度，系统接管手势时只来取消，已写的不退回。
- 还有一点：竖向拖动的 `DragStartDetails` 默认是“越过拖动阈值时”的位置（`DragStartBehavior.start`），从底边 8 起手、越过阈值时已经在手势区外了，所以要用按下时的位置（`onVerticalDragDown`）判断，不能用 `onVerticalDragStart` 给的位置。没改成 `DragStartBehavior.down`，那样第一次移动会带上阈值那一段，灵敏度会变。

## 改了哪些文件

- `apps/pure_live/lib/features/live_play/logic/room_layout.dart:213-225`：纯函数 `inSystemGestureArea`（全局纵坐标、屏幕高度、上下手势区；0 时总为假）。
- `apps/pure_live/lib/features/live_play/player/player_gestures.dart`：`_downY`（`:92-95`，按下时的全局纵坐标，`onVerticalDragDown` 记下，`:224`）；`_onDragStart` 在回到面板之后、`pictureDragAt` 之前判断，在区里直接返回（`:156-166`）。
- 没动：`portraitRestoreZone`、`pictureDragAt`、灵敏度、`player_view.dart`、原生代码。

## 新设置、翻译键、门禁基线

- 无。

## 测试

- 新增 3 个：
  - `room_swipe_test.dart`：纯函数——底边区内为真、区外为假、顶边同样、手势区 0 时总为假。
  - `room_popups_test.dart`（A07.15 组）：横屏全屏、手势区上 24 下 32、控件隐藏后，右半从底边 8 上拖不调音量、没有音量条；左半从顶边 6 下拉不调亮度、没有亮度条；右半中间上拖照旧调音量。**改之前失败**（`setVolume` 被调用 3 次）。
  - `live_play_layouts_test.dart`：竖屏全屏、底部手势区 32，从底边 10 上滑仍回到面板。
- 全部通过：`apps/pure_live` 全量 902 个。

## 真机上要看的

| 步骤 | 期望 |
|---|---|
| 1. 全面屏手势，横屏全屏，在画面右半从屏幕最底边上滑回桌面，再回来 | 音量没变，回来时没有音量条 |
| 2. 同上，在左半 | 亮度没变 |
| 3. 横屏全屏，在画面中间上下滑 | 照常调亮度、音量 |
| 4. 竖屏全屏，从底部上滑 | 回到面板（底边上滑回桌面时不回到面板） |
| 5. 横屏全屏从顶边下拉出状态栏 | 亮度没变 |
| 6. 换成三键导航重复 1 | 记下结果（系统可能报告 0，这时和改之前一样） |

- K90 报告的手势区高度：没有真机，待维护者记下（可以临时打日志看 `MediaQuery.systemGestureInsetsOf`）。
