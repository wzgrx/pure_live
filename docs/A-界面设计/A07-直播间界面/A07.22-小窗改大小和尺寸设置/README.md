# A07.22 应用内小窗拖角改大小、两指缩放，设置里加“小窗大小”（接 V01.5）

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：界面
- 来源：新功能提议 [V01.5](../../../V-需求和反馈/V01-新功能提议/V01.5-小窗拖角改尺寸/README.md)（D-036 同意做）；上游 pure_live `f9e03f446`（拖角改尺寸）、`e437b5bd8`、`a25facd94`（按直播流方向各记一套大小），media_core `7319d2d`（四边四角改大小、锁比例）
- 相关：决定 D-036、D-003（设计由维护者选，见 V01.5 README“评估结论和设计”S1～S13）、D-018（新设置只加不改）；小窗设计 [A07.8](../A07.8-小窗/README.md)（c2 按钮、c6 大小和位置、c10 不裁剪）；小窗弹幕随窗口缩放 [D03.3](../../../D-弹幕/D03-飞行弹幕引擎/D03.3-小窗和画中画的弹幕/README.md)；任务书 [brief.md](brief.md)、记录 [record.md](record.md)、真机步骤 [verify.md](verify.md)

## 目标

离开直播间后首页角落那个应用内小窗，手机上一直是 220 宽、不能改。现在：

1. 点一下小窗出按钮时，朝屏幕中间的那个下角多一个把手，按住往外（左右方向）拉变大、往里推变小；两指在画面上捏合、张开也能改大小（和 Android 系统画中画一样）。
2. 改过的大小记住，下次出来还是这么大；横屏画面、竖屏画面的小窗各记一份。
3. 设置 → 播放 →“小窗”一组加“小窗大小”：小、中、大三档，默认“中”= 原来的大小；拖过以后这一行显示“自定义”，选一档就回到那一档。
4. 小窗变大，里面的弹幕跟着变大（D03.3 已经按窗口宽度缩放，不用另做）；播放器不重建。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11:lib/`） | 改之前（`apps/pure_live/lib/`） | 要做到 |
|---|---|---|---|
| 大小 | `player/core/player_manager.dart:4737` `resolveAppFloatingSize`：220 宽（Windows 350），竖屏画面高 264 | `features/live_play/logic/mini_window.dart` 的 `inAppMiniSize`（A07.8 c6：短边 × 0.56，220～360） | 档位 × 拖过的倍数；默认和原来一样 |
| 改大小 | 不能 | 不能；拖动只改位置（`mini/mini_player.dart` 的 `onPan*`） | 把手、两指 |
| 设置 | 没有 | 没有 | “小窗大小”三档 |
| 记住 | 不记 | 不记 | 记住大小（不记位置，S7） |

## 结果

- c1 大小的规则（`apps/pure_live/lib/features/live_play/logic/mini_window.dart`）：`inAppMiniSize` 加 `factor`（档位的倍数，`inAppMiniSizes`：小 0.8、中 1、大 1.25）；`inAppMiniScale` 把拖过的倍数限在“长边 160～屏幕短边 × 0.9、竖屏画面宽不小于 120、不超出小窗能用的区域（`inAppMiniRoom`）”，档位本身的大小总是允许（所以倍数 1 永远不变）；`inAppMiniWindowSize` = 档位的大小 × 限过的倍数。
- c2 把手和方向：`inAppMiniGripCorner`：小窗中心在屏幕右半边时把手在左下角，否则在右下角；`inAppMiniGripExtent`：只看手指左右移动，往小窗外面那一侧是变大，换算成长边（画面比例不变）；上下不算，否则往左上方（屏幕中间）拉时竖直方向算成“往里推”，越拉越小；`inAppMiniResizedOffset`：把手对面的上角不动（两指是中心不动），之后照旧由 `inAppMiniOffset` 拉回屏幕里，所以在底部的小窗往上长。
- c3 手势（`apps/pure_live/lib/features/live_play/mini/mini_player.dart`）：`MiniPlayerSurface` 加 `resizeGrip`、`onResizeStart`、`onGripMove`、`onPinch`、`onResizeEnd`。给了 `onPinch` 时画面的手势从“拖动”换成“缩放”识别器：一根手指照旧拖动位置（换算成原来的 `onDragStart/Update/End`），两根手指是缩放；中途加一根或抬一根手指，识别器先报结束再按新的手指数重新开始。把手 `_ResizeGrip`（`mini-resize`）在按钮层里，和角上的按钮同一个样子（48、45% 黑圆底、白箭头 `AppIcons.miniResizeBottomLeft` / `miniResizeBottomRight`，读屏“拖动调整小窗大小”），按钮隐藏时它也隐藏、不接手势；拖着它时按钮不消失，松手后照旧 3 秒隐藏。桌面小窗和系统画中画不传这些参数，行为不变。
- c4 小窗（`apps/pure_live/lib/features/live_play/mini/floating_window.dart`）：读三个设置算大小；开始改大小时记下当时的矩形和倍数，拖动、捏合中只改 `_scale` 和左上角，`LiveVideoView` 和播放器不重建；结束时把倍数写进当前画面方向的那个设置（横屏画面 `floatWindowLandscapeScale`、竖屏画面 `floatWindowPortraitScale`），写进去之前先用自己记的值，避免松手的一帧跳回旧大小。
- c5 设置（`apps/pure_live/lib/features/settings/playback_tiles.dart` 的 `MiniWindowSizeTile`，`settings_catalog.dart` 的 `float_window_size`）：在“离开直播间时小窗播放”下面；那个开关关着时变灰并写“打开‘离开直播间时小窗播放’后生效”；显示当前档，拖过时显示“自定义”，弹窗里多一句“小窗现在是在画面上调过的大小；选一档会换回这一档的大小”；选任何一档（包括同一档）同时把两个倍数写回 1。设置搜索“小窗大小”“尺寸”能找到。
- c6 新设置（`packages/live_store/lib/src/settings/settings.dart`）：`floatWindowSize`（`player`，默认 `medium`，只认三档）、`floatWindowLandscapeScale`、`floatWindowPortraitScale`（`player`，默认 1，0.25～4）；都跟备份和设备同步（V01.5 S10）。
- 不做：记住位置（S7）；四边都能拖（S2）；系统画中画、桌面小窗、多画面；Windows 画中画的最小宽高（S12）。

## 验证

- 自动测试：见 [record.md](record.md)“测试”。
- 真机：[verify.md](verify.md)；待真机。

## 留下的问题

- 按钮显示的那 3 秒里，两指要按在按钮以外的画面上才能缩放（按钮在最上层）；平时按钮隐藏，不受影响。
- 小窗弹幕的放大上限保持 D03.3 的 2 倍（V01.5 S11），真机上看大窗口里的弹幕大小，觉得太大再按 W01.3 的建议跟上游钳回 1（改 `CompactDanmakuMetrics.maxScale` 一处）。
- 在设置里换档时，拖过位置的小窗保持左上角不动（不回到右下角）；觉得别扭再改。
