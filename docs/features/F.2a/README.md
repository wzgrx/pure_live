# F.2a 弹幕设置生效：帧率、字体、纯文字模式

- 状态：开发中（2026-10-02，和 U.2h、U.2i 合在一起做）
- 档位：必须；规模：中
- 功能点：F-DM-04、F-DM-05、F-DM-06（见 [INVENTORY.md](../INVENTORY.md)）
- 涉及代码：`apps/pure_live/lib/shared/danmaku/`（`danmaku_overlay.dart`、`danmaku_settings.dart`）、`features/live_play/player/player_view.dart`
- 依赖：U.2h（飞行弹幕渲染，已确认：方案 A 改进自己的画法），这三项在新弹幕层里一起做
- 来源：M13.14“留给后续”第 5 项、M12.4（弹幕字体）、M13.17 任务说明第 3、9 项
- 评审页：按授权直接开发（只把 v3 的行为补回来；界面照已确认的 [U.2h](../../ui/compare/U.2h/README.md)、[U.2i](../../ui/compare/U.2i/README.md)）
- 记录：[records/F.2a.md](../records/F.2a.md)（开发后）

## v3 的行为（`~/ref/v3ref`，v3.2.11）

| 功能点 | 行为 | 位置 |
|---|---|---|
| F-DM-04 | 弹幕层的 `fps`：跟随时按“界面刷新率”档位算（省电 = min(设备最高, 60)，均衡 = 60，最高 = 设备最高），手动 30～240；改设置、刷新率变化时立即重配 | `modules/live_play/widgets/video_player/video_controller_panel.dart:798-800`；`common/services/settings/danmaku_settings_controller.dart:135-162`；`video_controller.dart:121-129` |
| F-DM-05 | 弹幕层的 `fontFamily` = 设置里的字体 id（`Default` 是系统字体） | `video_controller_panel.dart:804`；`video_controller.dart:91` |
| F-DM-06 | 纯文字模式：表情图不画（直接跳过，不显示代码） | `video_controller_panel.dart:797`；`plugins/flame_barrage/lib/src/layout/mixed_layout.dart:175`、`:201` |

## v4 现在

- 主画面弹幕层不传 `fps`，每个刷新周期都画；设置面板只改显示的数字（`features/live_play/player/player_view.dart:269-273`；`shared/danmaku/danmaku_settings_content.dart:214-246`）。
- `DanmakuLook` 没有字体、纯文字（`shared/danmaku/danmaku_settings.dart:10-21`），弹幕层的文字样式不带字体（`danmaku_overlay.dart:201-206`）。
- 弹幕层不认识表情代码，`[笑哭]` 原样显示成文字（`danmaku_overlay.dart:207-211`）；`noEmojiMode` 只进模板（`danmaku_templates.dart:36`）。

## 差别和根因

| 编号 | 差别 | 根因 |
|---|---|---|
| P1 | 弹幕帧率设置不生效 | M13.14 搬弹幕层时只给小窗加了 `fps` 参数，主画面没传（`player_view.dart:271`） |
| P2 | 弹幕字体不生效 | `DanmakuLook` 没有字体字段，`danmakuLookOf` 不读 `danmakuFontFamilyName`（`danmaku_settings.dart:10-21`） |
| P3 | 纯文字模式对飞行弹幕无效 | 弹幕层只画纯文字，没有表情图，也就没有“去掉表情”这一步（`danmaku_overlay.dart:207`） |

## 要做的改动

| 编号 | 类型 | 内容 | 对应 |
|---|---|---|---|
| c1 | 修复 | 帧率：照 U.2h 的 c3（跟随时按 v3 档位算上限，再取当前刷新率的整数分之一；手动值生效），直播间主画面和全屏都传；刷新率变化时立即重算 | P1 |
| c2 | 修复 | 字体：照 U.2h 的 c8，`DanmakuLook.fontFamily`，`Default` 用系统字体 | P2 |
| c3 | 修复 | 纯文字：照 U.2h 的 c8，表情图照 U.2h 的 c1（字号 × 1.3）；纯文字模式跳过表情（照 v3，不显示代码），去掉后为空的不飞 | P3 |

多画面（`features/multiview/`）、电视用同一个弹幕层和 `danmakuLookOf`，字体和纯文字自动生效；帧率要它们自己传（不在本任务的目录，见记录）。

## 需要选的

无（照 v3，U.2h、U.2i 已确认）。

## 测试和验证

- 组件测试：手动 30 帧时 60 赫兹下每秒重绘约 30 次；跟随时 120 赫兹、上限 60 → 隔一帧画一次；字体名传到弹幕文字；纯文字时表情不画、只剩表情的弹幕不飞。
- K90：TASKS 第 5 节 5.2 第 3 条；profile 模式看一次帧时间。

## 风险和性能

- 没有新常驻任务；帧率封顶后光栅次数减少。
- 3.x 的键 `danmakuFps`、`danmakuAutoFps`、`danmakuFontFamilyName`、`noEmojiMode` 名字和含义不变。

## 经过

| 日期 | 内容 |
|---|---|
| 2026-10-02 | 建立（第 1 版清点） |
| 2026-10-02 | 写功能对比（v3、v4、根因、改动），和 U.2h、U.2i 一起开发 |
