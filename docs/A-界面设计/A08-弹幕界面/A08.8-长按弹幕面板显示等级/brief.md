# A08.8 长按弹幕面板加回 3.x 的等级 Lv.N：任务书

## 背景

- 来源：D 组写文档时发现长按弹幕面板少了 3.x 的“Lv.N”（D01 子分类说明的已知问题）；2026-10-07 定为加回（D-033）。
- 现象：在 SHOWROOM、克拉克拉等平台的直播间长按一条弹幕，3.x 的面板第一行下面写“Lv.12”，4.x 没有。
- 为什么做：第三档；D-001（3.x 的功能一个不少）；平台层已经解出等级，只差显示。
- 已经做过的：A08.4（画面弹幕点按、长按打开同一个面板）、A07.11 c8（面板第二页输入屏蔽关键词）。

## 目标和验收

1. `LiveMessage.userLevel` 不为空时，面板卡片“用户名：内容”下面多一行“Lv.N”（`bodySmall`、`onSurfaceVariant`）。
2. 为空时卡片和现在完全一样。
3. 读屏读“等级 N”（新翻译键 `danmaku_user_level`，zh、en 都加，键名排序）。
4. 弹幕列表、飞行弹幕不变（只改面板）。

## 现状（读代码得出，写文件:行）

- `apps/pure_live/lib/features/live_play/danmaku/message_panel.dart:50` `RoomMessagePanel`；`:112-150` `_actions` 的卡片（`Text.rich`：名字用 `chatNameColor`、内容 `onSurface`，最多 6 行）。
- `packages/live_core/lib/src/live_message.dart:289`（构造参数 `userLevel = ''`）、`:323`（字段）。
- 有等级的平台：`packages/live_danmaku/lib/src/sites/` 的 `bigo.dart`、`showroom.dart`、`kick.dart`、`kilakila.dart`、`kugoulive.dart`、`missevan.dart`、`looklive.dart`、`seventeenlive.dart`。

## 3.x 基线

- `git show v3.2.11:lib/modules/live_play/widgets/danmaku/danmaku_message_actions.dart:17-20`：`subtitle: message.userLevel.isEmpty ? null : Text('Lv.${message.userLevel}')`。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节、第 8 节、第 14 节）。
2. `docs/specs/UI.md`（文字样式和颜色角色）。
3. 本文件夹的 `README.md`；`docs/A-界面设计/A08-弹幕界面/README.md`；`docs/A-界面设计/A08-弹幕界面/A08.4-画面弹幕点按和长按/README.md`。

## 范围

- 可以改：`message_panel.dart`；`apps/pure_live/assets/translations/zh.json`、`en.json`（加一个键）；`room_popups_test.dart`；本文件夹的文档。
- 不能改：`LiveMessage` 和各平台的解析（D 组）；弹幕列表和飞行弹幕；面板的其他行和第二页。

## 方案和阶段

| 阶段 | 做什么（README 的 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | c1～c3 | `message_panel.dart`、翻译文件、测试 | 验收 1～4；门禁 `--all` 通过 |

## 测试

- `apps/pure_live/test/features/live_play/room_popups_test.dart`：`message panel shows the sender level`（`userLevel: '12'` → 找到“Lv.12”）、`message panel without a level has no level line`（找不到“Lv.”）；竖屏（下方面板）和横屏（右侧面板）各跑一次。
- 测试里的定时器至少 1 秒；不访问真实平台。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 进一个 SHOWROOM 或克拉克拉的直播间，长按弹幕列表里一条弹幕 | 卡片里内容下面有“Lv.N” |
| 2. 进哔哩哔哩直播间长按一条弹幕 | 没有等级这一行，卡片和以前一样 |
| 3. 横屏全屏点按画面上的弹幕 | 右侧面板同样显示等级 |

## 风险和注意

- 翻译键排序（4 空格缩进，键名排序）；不要清理别的键（D-024）。
- 可能冲突的文件：`message_panel.dart`（A07.14 双击飞行弹幕面板一闪也会动这个文件附近）。

## 环境和提交

- `source ~/tools/purelive-env.sh`；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 分支 `ai/A08.8` 或本机工作区；提交信息以 `[A08.8]` 开头（英文）；不推 master。
- 提交前：`apps/pure_live` 跑 `dart format --output=none --set-exit-if-changed .`、`flutter analyze`、全部 `flutter test`；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”、更新登记表的 `done`、`next`、`branch`。

## 报告（中文，简洁）

做到没有；改了哪些文件；新翻译键；测试数量；要在真机上看的。
