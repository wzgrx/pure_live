# A08.8 长按弹幕面板加回 3.x 的等级 Lv.N：记录

- 日期：2026-10-08
- 执行者：Claude
- 分支和提交：本机工作区（从 master `d24c6757b` 开始）
- 设计或说明：[README.md](README.md)；任务书 [brief.md](brief.md)

## 根因

- `apps/pure_live/lib/features/live_play/danmaku/message_panel.dart:131-151`（改前，`_actions` 的卡片）只放了一个 `Text.rich`（“用户名：内容”），重写面板时没有带上 3.x `danmaku_message_actions.dart:17-20` 的 `subtitle: Text('Lv.${message.userLevel}')`。平台层（`LiveMessage.userLevel`）一直有值，只是界面没读。

## 做了什么

- c1：`userLevel`（去掉首尾空白）不为空时，卡片里“用户名：内容”下面加一行“Lv.N”：`bodySmall`、`onSurfaceVariant` 色、上边距 4（键 `live-play-message-level`）；为空时卡片里还是原来那一个 `Text.rich`，高度不变。
- c2：“Lv.” 不翻译；读屏读“等级 N”：`Semantics(label:, excludeSemantics: true)`，新键 `danmaku_user_level`（zh“等级 {level}”、en“Level {level}”，按键名排序）。
- c3：本地弹幕、系统消息不变（没有等级就没有这一行）；弹幕列表、飞行弹幕、面板其他行和第二页都没动。

## 测试

- `room_popups_test.dart` 新组 `A08.8: the message panel shows the sender's level`，竖屏（下方面板）和横屏全屏（右侧面板）各两个：
  - `message panel shows the sender level`：`userLevel: '12'` → 卡片里有“Lv.12”，字号等于 `bodySmall`，颜色 `onSurfaceVariant`，读屏标签“等级 12”。
  - `message panel without a level has no level line`：卡片里没有“Lv.”，“路人：前排”照旧。
- 改之前：两个“shows the sender level”失败（找不到“Lv.12”）；改后 `apps/pure_live` 全部通过。

## 真机

待 K90（任务书“真机验证”）：

1. SHOWROOM 或克拉克拉直播间长按弹幕列表里一条弹幕：卡片内容下面有“Lv.N”。
2. 哔哩哔哩直播间长按一条弹幕：没有等级这一行，卡片和以前一样。
3. 横屏全屏点按画面上的弹幕（设置开着时）：右侧面板同样显示等级。

## K90 复查（2026-10-08，master ce7640a5b）

- 虎牙聊天长按一条（虎牙不报等级）：卡片只有“二狗：内容”，没有 Lv 行，和原来一样 ✓。带等级的平台（SHOWROOM、克拉克拉）这次房间里没人发言，没看到。
