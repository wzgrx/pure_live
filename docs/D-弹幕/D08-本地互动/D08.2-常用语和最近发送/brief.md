# D08.2 常用语和最近发送：任务书

## 背景

- 来源：V03.6（`docs/V-需求和反馈/V03-审查和调研/V03.6-弹幕系统和本地互动体验/README.md`）第 4 节 E6（乙档）、第 5.3 节最后一段；用户 2026-10-09（D-040）。
- 现象：每次都要重打常说的话，手机上打字慢。
- 为什么现在做：第二档；接在 D08.1 后面。
- 已经做过的：D08.1（`local_events`，最近发过）——开工前确认已合并；A08.14 也改长按面板，先后做。

## 目标和验收

1. 新设置 `localInteraction.phrases`（字符串列表，最多 20 条、每条最多 100 字，默认空），跟备份和设备同步。
2. 输入框获得焦点时上方一排标签：最近发过的 5 条（不重复，取自 D08.1 的记录）+ 常用语；都没有时不出现。
3. 点标签直接发；长按放进输入框。
4. 本地弹幕的长按面板有“存为常用语”（存过的显示“已在常用语里”）。
5. 设置 → 本地用户与互动有“常用语”一组：加、删（4 秒撤销）、排序。
6. 三处输入框（竖屏和宽屏列表下面、全屏下栏、互动面板）一样；文字走翻译。

## 现状（读代码得出）

- `apps/pure_live/lib/features/live_play/local_interaction/local_composer.dart`：`LocalDanmakuComposer`（`:49`）、窄于 180 收成按钮（`:26`）、`LocalComposerChatStar`（`:488`）；`TextField`（`:280-300`）。
- `logic/local_room_session.dart` 的 `sendChat`；`features/live_play/danmaku/message_panel.dart`（本地弹幕的面板）。
- 设置页 `local_interaction/local_interaction_settings_page.dart`（五组，`:64-186`）。

## 3.x 基线

- 3.x 没有常用语。要保留：三处输入框的样子和发送（A08.2）。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`。
2. `docs/specs/UI.md` 第 3、7 节。
3. 本文件夹 `README.md`；D08.1 的 README；`docs/A-界面设计/A08-弹幕界面/A08.2-本地互动/README.md`。

## 范围

- 可以改：`local_composer.dart`、`message_panel.dart`（本地弹幕的一行）、`local_interaction_settings_page.dart`；`logic/local_interaction.dart`（常用语的读写）；`settings.dart`（新设置）、`settings_catalog.dart`；翻译文件；对应测试；A08.2 README 补一条。
- 不能改：发送的规则；3.x 键；版本号。

## 方案和阶段

| 阶段 | 做什么 | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | 设置、最近发过、输入框上方一排、点和长按 | 设置、logic、`local_composer.dart` | 测试通过 |
| 2 | 长按“存为常用语”、设置页管理 | `message_panel.dart`、设置页 | 测试通过 |

## 测试

- `packages/live_store/test/`：新设置默认空、20 条和 100 字上限、备份往返。
- `apps/pure_live/test/features/live_play/local_interaction_test.dart`：焦点时出现、没内容不出现；最近 5 条去重；点了发出、长按放进输入框；三处输入框；存为常用语；设置页加、删、撤销、排序。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 发几条本地弹幕，点输入框 | 上方有最近发过的 |
| 2. 长按自己的一条本地弹幕，存为常用语 | 输入框上方多了它 |
| 3. 全屏横屏的输入框 | 一样 |

## 风险和注意

- 标签一排不要把输入框顶出屏幕（键盘弹起时，竖屏和横屏都看）。

## 环境和提交

- `source ~/tools/purelive-env.sh`；`apps/pure_live` 全部 `flutter test`；推送前 `bash tools/gate/gate.sh --all`。
- 分支 `ai/D08.2`；提交信息以 `[D08.2]` 开头（英文）；不推 master。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节。

## 报告（中文，简洁）

每条做到没有；新设置和翻译键；测试数量；改了哪些文件；真机上要看的。
