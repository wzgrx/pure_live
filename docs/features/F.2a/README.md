# F.2a 弹幕设置生效：帧率、字体、纯文字模式

- 状态：未开始
- 档位：必须；规模：中
- 功能点：F-DM-04、F-DM-05、F-DM-06（见 [INVENTORY.md](../INVENTORY.md)）
- 涉及代码：`apps/pure_live/lib/shared/danmaku/`（`danmaku_overlay.dart`、`danmaku_settings.dart`）
- 依赖：U.2h（飞行弹幕渲染选型）之后；U.2h 如果换掉弹幕层，这三项在新弹幕层里一起做
- 来源：M13.14“留给后续”第 5 项、M12.4（弹幕字体）、M13.17 任务说明第 3、9 项
- 评审页：按授权直接开发（只把 v3 的行为补回来）
- 记录：[records/F.2a.md](../records/F.2a.md)（开发后）

## 要做的

| 功能点 | v3 | v4 现在 | 要做到 |
|---|---|---|---|
| F-DM-04 | 弹幕帧率：跟随屏幕（省电和均衡最高 60）或固定（`modules/live_play/widgets/video_player/video_controller.dart:90`） | 设置面板有；主画面的弹幕层不读 `danmakuFps`、`danmakuAutoFps`（只有小窗弹幕读帧率） | 主画面和多画面的弹幕层按设置限帧 |
| F-DM-05 | 弹幕字体（`video_controller.dart:91`） | 字体能下载、注册（M12.4，注册名就是设置里的 id）；弹幕层不读 `danmakuFontFamilyName` | 弹幕用选中的字体；字体没下载时用系统字体并在设置行提示（M12.4 已有） |
| F-DM-06 | 纯文字模式：飞行弹幕不显示表情（`video_controller.dart:76`） | 开关只进模板（`shared/danmaku/danmaku_templates.dart:36`），弹幕层不读 `noEmojiMode` | 打开时飞行弹幕去掉表情 |

## 改动清单

| 编号 | 类型 | 内容 | 对应 |
|---|---|---|---|
| c1 | 修复 | `DanmakuLook` 带上帧率（跟随时按刷新率档位算，同 v3 `resolvedDanmakuFps`）、字体、纯文字 | F-DM-04、F-DM-05、F-DM-06 |
| c2 | 修复 | `DanmakuOverlay` 按这三项画；多画面同样生效（它用同一个弹幕层） | 同上 |

## 测试和验证

- 组件测试：固定 30 帧时每秒重绘不超过 30 次；字体名传到文字样式；纯文字时表情码被去掉。
- K90：TASKS 第 5 节 5.2 第 3 条；profile 模式看一次帧时间（每秒 50 条弹幕）。

## 经过

| 日期 | 内容 |
|---|---|
| 2026-10-02 | 建立（第 1 版清点） |
