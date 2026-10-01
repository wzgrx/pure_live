# F.1d 冷门的播放设置

- 状态：未开始
- 档位：可以以后；规模：中
- 功能点：F-ROOM-21、F-PORT-05、F-PORT-06、F-MINI-04、F-APP-17、F-ROOM-25（见 [INVENTORY.md](../INVENTORY.md)）
- 涉及代码：`features/live_play/`（`logic/room_runtime.dart`、`mini/`）、`features/settings/`、`app/app.dart`
- 依赖：U.6c（播放设置页）合并后；X1 要用户选
- 来源：M12.4（`useHardStopOnExit`）、M13.7（小窗弹幕预览）、M13.14 第 4 项、M13.17 任务说明第 5、8、9 项
- 评审页：发评审页（X1）
- 记录：[records/F.1d.md](../records/F.1d.md)（开发后）

## 要做的

| 功能点 | v3 | v4 现在 | 要做到 |
|---|---|---|---|
| F-ROOM-21 | “退出时销毁播放器”关时，离开直播间保留播放器给下一个直播间复用（`common/services/settings/player_settings_controller.dart:52`） | 设置没人读；离开即释放或转小窗 | 见 X1 |
| F-PORT-05 | 小窗跟随竖屏源的比例（`modules/settings/pages/portrait_live_settings_page.dart`） | `portraitPipFollowSource` 没人读 | 应用内小窗、画中画按设置跟随竖屏比例 |
| F-PORT-06 | 竖屏诊断信息（`portrait_live_settings_page.dart:154`） | `showPortraitDiagnostics` 没人读 | 直播间显示 v3 的竖屏判断信息 |
| F-MINI-04 | 小窗弹幕设置的实时预览（`modules/settings/pages/pip_danmaku_settings_page.dart:31`） | 没有预览 | 设置页顶部有预览 |
| F-APP-17 | 系统内存紧张时清图片缓存（`common/global/platform/desktop_manager.dart:774`） | 没有 | 应用接 `didHaveMemoryPressure` |
| F-ROOM-25 | 键盘媒体键（`modules/live_play/widgets/keyboard/video_keyboard.dart:56`） | 空格、方向键、R、F、Esc 有，媒体键没有 | 外接键盘的播放 / 暂停键生效 |

## 需要用户选的

- X1 “退出时销毁播放器”：A（建议）保留开关，“关”时离开直播间把播放器留给下一个直播间（和应用内小窗共用 `RoomRuntime`，进下一个房间时少一次建播放器）；B 去掉这个开关（v4 离开即释放，设置页不再显示，3.x 的值不再起作用）。

## 测试和验证

- 组件测试各一个；K90：小窗和竖屏相关的看 TASKS 第 5 节 5.1 第 8、11、12 条。

## 经过

| 日期 | 内容 |
|---|---|
| 2026-10-02 | 建立（第 1 版清点） |
