# T06d.2 哔哩哔哩：访客昵称说明和登录引导、粉丝牌和头像

- 规模：中；分组：弹幕；依赖：T06b.2 之后；能否和别的任务同时做：可以和 T05f.1、T01d.2、T08b.3 同时；和 T02f.2 都会改聊天行，建议错开
- 出设计：不用（照已确认的设计和本任务单）
- 先读：审查报告 A-04
- 可以改：`packages/live_danmaku`（哔哩哔哩解析）、`features/live_play/danmaku/`、`features/live_play/logic/`（只在需要时）；其他目录不改。

## 要做的

- c1 访客连接哔哩哔哩弹幕时，聊天列表顶部常驻一条提示“访客模式下哔哩哔哩会隐藏昵称 · 去登录”（替换现在每次连接插入的系统消息），点“去登录”打开哔哩哔哩登录（`AppNavigator.toBiliBiliLogin()`），登录回来自动重连弹幕；Cookie 失效时提示“登录已失效 · 重新登录”。
- c2 解析粉丝牌（`user.medal{name, level}` 或 `info[3]`）填进 `LiveMessage.fansName`、`fansLevel`（`features/live_play/danmaku/chat_list.dart` 的 `_fans` 已经会画）；卡片样式的聊天行加头像（`user.base.face`）。
- c3 登录后昵称完整：确认解析顺序在登录态下取到全名（写测试用的合成样本，字段照 `fixtures/bilibili/danmaku/` 里的结构）。

## 验收

- 未登录时提示清楚并能一键去登录；有粉丝牌的观众显示粉丝牌；登录后昵称完整。
- 测试：提示的显示和隐藏；粉丝牌和头像解析；登录态样本取全名。

## 真机上看的（写进记录，维护者在 K90 上看）

- 未登录进哔哩哔哩直播间：聊天列表顶部有提示；点去登录 → 扫码登录 → 回来后昵称完整。

