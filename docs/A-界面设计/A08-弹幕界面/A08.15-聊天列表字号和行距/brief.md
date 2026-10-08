# A08.15 聊天列表字号和行距（接 A08.10）：任务书

## 背景

- 来源：V03.6（`docs/V-需求和反馈/V03-审查和调研/V03.6-弹幕系统和本地互动体验/README.md`）第 3.2 节、第 4 节 E4（甲档）、第 5.2 节做法 A；用户 2026-10-09（D-040）。
- 现象：聊天列表的字号只跟系统字体走，弹幕密时一屏的行数改不了。
- 为什么现在做：第二档；常见客户端的标配、改动小。
- 已经做过的：A08.10（名字和内容两个角色 `ChatText`、“显示用户名”）——**必须先合并**，本任务只给它加参数；A08.6（“弹幕列表”一组三处共用）。

## 目标和验收

1. 两个新设置：`danmakuListFontSize`（默认 0 = 现在的样子，12～22，超出读成 0）、`danmakuListLineSpacing`（默认 `standard` = 现在的行距；`compact`、`loose`）；跟备份和设备同步。
2. 默认值下列表和改之前像素一致（布局测试对比）。
3. 改了以后紧凑、卡片、本地弹幕、礼物行、醒目留言行一起变；粉丝牌、徽章、头像、礼物图按比例；系统字体缩放照样生效。
4. 手机横屏 280 宽、宽屏右栏、字号 22 + 系统 2 倍时不溢出。
5. 设置行在“弹幕列表”一组“弹幕列表样式”下面，三处同一个组件；设置搜索“字号”“行距”能找到；文字走翻译。

## 现状（读代码得出）

- A08.10 合并后：`apps/pure_live/lib/features/live_play/danmaku/chat_text.dart`（`ChatText.name`、`ChatText.content`，`bodyLarge`）；`chat_list.dart` 的 `ChatLineView`、`ChatList`（读 `showChatNames`）；本地行 `features/live_play/local_interaction/local_chat_line.dart`。
- 设置组件 `apps/pure_live/lib/shared/danmaku/chat_list_settings.dart`（“弹幕列表样式”分段按钮 `:58-65`）；搜索 `features/settings/settings_catalog.dart`。

## 3.x 基线

- 3.x 卡片 14 号写死；没有这两个设置。要保留：默认样子不变（D-018、D-040）。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`。
2. `docs/specs/UI.md` 第 8.2 节（主次分明）、第 3 节第 6 条。
3. 本文件夹 `README.md`；A08.10、A08.6 的 README。

## 范围

- 可以改：`chat_text.dart`、`chat_list.dart`、`local_chat_line.dart`（只加字号和行距参数）；`chat_list_settings.dart`、`settings_catalog.dart`；`packages/live_store/lib/src/settings/settings.dart`（登记 `Settings.all`、`settings_defaults_test.dart`、`tools/docs/settings_audit_notes.py`）；`docs/inventory/OWNERS.toml`；翻译文件；对应测试。
- 不能改：A08.10 定的字重、颜色、顺序；飞行弹幕；3.x 的设置键；版本号。

## 方案和阶段

规模小，不分阶段：c1 设置 → c2、c3 列表跟它 → 设置行和搜索 → 测试。

## 测试

- `packages/live_store/test/`：默认值、范围、超出读成 0、备份往返。
- `apps/pure_live/test/features/live_play/`：默认时文字样式和改之前一样；字号 12、22 时名字和内容同字号；行距三档的行高；280 宽 + 22 + 2 倍不溢出；卡片、本地行、礼物行都跟。
- `live_play_tabs_test.dart`、`settings_danmaku_test.dart`：设置行的位置和搜索。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 默认设置 | 列表和之前一样 |
| 2. 字号调到 12、行距紧凑 | 一屏多很多行，仍看得清 |
| 3. 字号 22，手机横着拿 | 不截断、不溢出 |

## 风险和注意

- 和 A08.11 改同一个文件：先后做。
- 列表行的缓存（A08.10 c5 按样式、开关、表情表判断）要加上字号和行距，否则改了不生效。

## 环境和提交

- `source ~/tools/purelive-env.sh`；`apps/pure_live` 全部 `flutter test`；推送前 `bash tools/gate/gate.sh --all`。
- 分支 `ai/A08.15`；提交信息以 `[A08.15]` 开头（英文）；不推 master。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节。

## 报告（中文，简洁）

每条做到没有；新设置和翻译键；测试数量；改了哪些文件；真机上要看的。
