# F.2b 画面弹幕点按和长按

- 日期：2026-10-02
- 任务：[F.2b/README.md](../F.2b/README.md)；和 U.2h 的 c9 一起做（[U.2h 记录](../../ui/records/U.2h.md)）
- 改动：`shared/danmaku/danmaku_overlay.dart`（`messageAt`、`held`）、`features/live_play/player/player_view.dart`、`features/live_play/danmaku/chat_list.dart`

## 逐条对照

| 编号 | 做到 | 说明 |
|---|---|---|
| c1 弹幕层给出“这个点上是哪条” | ✅ | `DanmakuOverlayState.messageAt`：按这一帧的位置，上下左右放宽 4 像素，叠着时取后进来的 |
| c2 画面的点按、长按先问弹幕层 | ✅ | 开关开着才问；控制条显示时上下控制条范围不问（3.x `shouldHandleVideoSurfaceTap`，按三种排布各自的条高）；锁定时不问；没命中照原来（显示 / 隐藏控制层、双击全屏）。点按在按下的那一刻就问（双击要等 0.3 秒，弹幕已经走开），比 3.x 准。长按手势只在长按开关开着时挂上 |
| c3 面板用 U.2f 的“长按弹幕” | ✅ | `chat_list.dart` 新的顶层 `showRoomMessageActions`：列表长按和画面弹幕共用（复制、屏蔽此用户、屏蔽关键词） |
| c4 面板打开时弹幕停住 | ✅ | 弹幕层 `held`：整层停住，新弹幕不进，面板关了继续 |

没做的：面板没有挪到 `shared/danmaku/`（README 原来的打算）：多画面不在本批目录，直播间里放在 `chat_list.dart` 就够；多画面要用时再挪。3.x 的“长按后 1 秒内的点按不算”不需要：手势竞争里长按赢了就不会再有点按。

## 根因

M12.2 换成自己的画法时弹幕层整层 `IgnorePointer`、不记位置，画面手势层也不知道有弹幕可点；设置面板的两个开关（U.2f）没人读。

## v3 → v4

`video_controller.dart:132-149`、`:217-220`、`:258-263`、`:984-995`，`video_controller_panel.dart:69-84`、`:196-245` → `player_view.dart` 的 `_danmakuAt`、`_openMessage`、`danmakuTapAllowed`；`DanmakuMessageActions` → `showRoomMessageActions` / `showChatMessageActions`。

## 设置

没有新设置；`enableDanmakuTapInteraction`、`enableDanmakuLongPressInteraction` 默认开，同 3.x。

## 测试

直播间 2 个（`live_play_page_test.dart`）：点一条飞着的弹幕出面板三项、弹幕停住、关了继续，长按出同一个面板；点按开关关时只切换控制层，另测控制条范围不命中。弹幕层的命中和停住在 U.2h 的测试里。

## 没验证的

K90：TASKS 第 5 节 5.2 第 6 条（真机上点小字弹幕好不好点中）。
