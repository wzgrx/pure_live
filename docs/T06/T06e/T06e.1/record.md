# T06e.1 弹幕设置生效：帧率、字体、纯文字模式

- 日期：2026-10-02
- 任务：[T06e.1/README.md](README.md)；和 T06c.1 一起做（[T06c.1 记录](../../T06c/T06c.1/record.md)）
- 改动：`shared/danmaku/danmaku_overlay.dart`、`danmaku_settings.dart`、`features/live_play/player/player_view.dart`

## 逐条对照

| 编号 | 做到 | 说明 |
|---|---|---|
| c1 帧率 | ✅ | 直播间把 `resolvedDanmakuFps`（跟随时按 v3 档位，手动 30～240）传给弹幕层，弹幕层取当前刷新率的整数分之一（T06c.1 c3）；全屏、竖屏全屏是同一个弹幕层 |
| c2 字体 | ✅ | `danmakuLookOf` 读 `danmakuFontFamilyName`，`Default` 用系统字体；字体由 T07a.3 注册，注册名就是 id |
| c3 纯文字 | ✅ | `noEmojiMode` 开时表情跳过（照 v3 不显示代码），只剩表情的不飞；关时表情是图（1.3 × 字号） |

## 根因

T05a.2 把弹幕层换成自己的画法时只搬了样式数值：主画面没传 `fps`（`player_view.dart`），`DanmakuLook` 没有字体和纯文字两个字段，弹幕层也没有表情图，所以三个设置只有设置面板和模板在读。

## v3 → v4

`modules/live_play/widgets/video_player/video_controller_panel.dart:786-811`（`BarrageConfig`）→ `features/live_play/player/player_view.dart` 的 `_danmaku`；`danmaku_settings_controller.dart:135-162` → `shared/danmaku/danmaku_templates.dart` 的 `resolvedDanmakuFps`（已有）+ `danmaku_overlay.dart` 的 `danmakuFrameDivisor`。

## 设置

没有新设置；`danmakuFps`、`danmakuAutoFps`、`danmakuFontFamilyName`、`noEmojiMode` 的键名和含义不变。

## 测试

弹幕层 3 个（T06c.1 记录里的帧率、字体和纯文字两条，加整数分之一的表）；直播间 1 个（`live_play_page_test.dart`：设置改成手动 30、选字体、纯文字后弹幕层拿到 30、字体名、纯文字；暂停后不再进新弹幕）。

## 没验证的

K90：TASKS 第 5 节 5.2 第 3 条（固定 30 帧看起来是否均匀、下载的字体是否用上、表情是否消失）。

## 合并时注意

多画面不在本批目录：它的弹幕层自动有字体和纯文字，帧率仍然每个刷新周期都画（要传 `fps` 时在 `multiview_page.dart` 照直播间写）。
