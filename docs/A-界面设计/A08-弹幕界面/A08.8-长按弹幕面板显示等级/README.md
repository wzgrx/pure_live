# A08.8 长按弹幕面板加回 3.x 的等级 Lv.N

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：界面
- 来源：D 组写文档时发现（[D01 已知问题](../../../D-弹幕/D01-平台弹幕协议/README.md)）；决定 D-033（2026-10-07，用户授权维护者定）
- 相关：D-001（功能不少）、D-033；[A08.4](../A08.4-画面弹幕点按和长按/README.md)（长按面板的入口）、A07.11 c8（屏蔽关键词第二页）、D01（各平台解出的等级）

## 界面清点

| 编号 | 界面 | 怎么打开 | 布局 |
|---|---|---|---|
| A08.8-01 | 长按弹幕面板的第一块（“用户名：内容”卡片） | 弹幕列表长按或右键；画面上的弹幕点按或长按（设置开着时） | 竖屏在画面下方、横屏和宽屏在右侧 |

## 3.x 的样子和问题

- 3.x：`git show v3.2.11:lib/modules/live_play/widgets/danmaku/danmaku_message_actions.dart:17-20`：底部面板第一行 `ListTile`，标题“用户名: 内容”，`message.userLevel` 不为空时副标题 “Lv.N”。
- 4.x 现在：`apps/pure_live/lib/features/live_play/danmaku/message_panel.dart:112-150`（`_actions`）只有一张“用户名：内容”卡片，没有等级。`LiveMessage.userLevel`（`packages/live_core/lib/src/live_message.dart:323`，字符串，默认空）在 8 个平台的弹幕里有值：BIGO、SHOWROOM、Kick、克拉克拉、酷狗、猫耳、LOOK、17LIVE（`packages/live_danmaku/lib/src/sites/`）。

## 设计

- c1：卡片里“用户名：内容”下面加一行“Lv.N”（`bodySmall`，`onSurfaceVariant` 色，上边距 4）；`userLevel` 为空时不显示这一行，卡片高度和现在一样。
- c2：等级文字不翻译（“Lv.” 是 3.x 的写法，平台给的等级原样显示）；读屏时读作“等级 N”（`Semantics(label:)`，翻译键 `danmaku_user_level`，zh“等级 {level}”、en “Level {level}”）。
- c3：本地弹幕和系统消息照旧（本地弹幕没有等级）。

按 D-003 由维护者定，不另出评审页（改动只有一行文字，位置照 3.x）。

## 实现和验证

- 未开始。测试：`apps/pure_live/test/features/live_play/room_popups_test.dart` 加两个用例（有等级显示“Lv.12”、没有等级不显示）。
- 真机：在 SHOWROOM 或克拉克拉的直播间长按一条带等级的弹幕，看到“Lv.N”；哔哩哔哩（不解等级）没有这一行。
