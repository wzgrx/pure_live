# A08.10 弹幕列表里用户名和内容分开显示；加“显示用户名”开关：任务书

## 背景

- 来源：用户 2026-10-09：弹幕列表里发送者的名字和内容要用明显不同的方式显示，名字在所有平台一个样子、内容一个样子；横屏也要考虑；加一个开关，可以只显示内容、不显示用户名。按已确认处理，设计里要选的由维护者按 D-003 定（[README.md](README.md)“需要选的和选择”G1～G12）。
- 现象：紧凑行的名字和内容字号、字重都一样（`bodyLarge` 400），白色弹幕时只靠 `onSurfaceVariant` 和 `onSurface` 一点颜色差，深色主题下几乎分不开；彩色弹幕的名字是彩色的，同一个平台的名字一会儿灰一会儿彩；卡片的名字是 600、`onSurface`，和紧凑行不一样；本地弹幕、长按卡片又各是一套。
- 为什么现在做：用户日常用的界面（第一档）。
- 已经做过的：A08.1（两种样式）、D04.1（名字 4.5:1）、E06.2 c2、c3（17LIVE 名字颜色和徽章、“对方”）、A08.6（“弹幕列表”一组三处共用）。

## 目标和验收

1. 两种样式里名字 = `bodyLarge` 600 + 名字颜色，内容 = `bodyLarge` 400 + `onSurface`；本地弹幕、礼物一行、醒目留言一行、长按卡片用同一套。
2. 名字颜色一条规则：平台名字颜色 → 弹幕颜色 → `onSurfaceVariant`，都过 `chatNameColor` 的 4.5:1；浅色、深色、纯黑三套主题都查。
3. 名字前的顺序：“对方” → 徽章图 → 粉丝牌 → 名字 → 内容；粉丝牌是 `ChatChip`。
4. “弹幕列表”一组加“显示用户名”（`showChatNames`，默认开）；关掉后列表里没有名字、徽章、粉丝牌、头像，“本地”“对方”留着；长按卡片照旧有名字。
5. 手机横着拿 869×400、宽屏 1280×800 同一个列表跟着开关；280 宽、1.3 倍和 2 倍字不溢出、名字不截断。

## 现状（读代码得出，写文件:行）

- `apps/pure_live/lib/features/live_play/danmaku/chat_list.dart`：`ChatLineView._compact`（名字 `body?.copyWith(color: nameColor)`，400）、`_card`（名字 `body?.emphasis`，颜色 `named ?? (avatar.isEmpty ? onSurface : colour)`，“: ”）、`_fans`（`TextSpan` + `backgroundColor`）、礼物和醒目留言分支；`ChatList._view` 的行缓存只看样式和表情表。
- `apps/pure_live/lib/features/live_play/local_interaction/local_chat_line.dart`：名字 400 `onSurfaceVariant`。
- `apps/pure_live/lib/features/live_play/danmaku/message_panel.dart` `_actions`：名字只用 `message.color`。
- `apps/pure_live/lib/shared/danmaku/chat_list_settings.dart` `ChatListSettings`：列表样式、礼物两行。

## 3.x 基线

- `git show v3.2.11:lib/modules/live_play/widgets/danmaku/danmaku_list_view.dart:446-531`：`DanmakuItem` 名字 14 号 700、内容 14 号 500，同一个颜色；左边 8 像素弹幕颜色圆点；双击复制“用户名: 内容”。没有“显示用户名”设置。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`。
2. `docs/specs/UI.md` 第 3 节第 7 条、第 8.1、8.2 节。
3. 本文件夹的 `README.md`；A08.1、A08.6、A08.8、D04.1、E06.2 的 README。

## 范围

- 可以改：`apps/pure_live/lib/features/live_play/danmaku/`、`local_interaction/local_chat_line.dart`、`shared/danmaku/chat_list_settings.dart`、`features/settings/settings_catalog.dart`、`packages/live_store/lib/src/settings/settings.dart`、翻译文件、对应测试、设置登记（`settings_defaults_test`、`tools/docs/settings_audit_notes.py`、`docs/inventory/OWNERS.toml`）。
- 不能改：飞行弹幕层和小窗弹幕；醒目留言标签的卡片；礼物一行的结构和配色（V03.5 之后另做）；复制的文字；已有设置的键名和默认值。

## 方案和阶段

| 阶段 | 做什么 | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | 名字和内容两个角色、一条颜色规则、标签顺序（c1～c3） | `chat_text.dart`（新）、`chat_list.dart`、`local_chat_line.dart`、`message_panel.dart` | 两种样式、三套主题的字重、颜色、对比度、顺序测试通过 |
| 2 | “显示用户名”开关（c4、c5） | `settings.dart`、`chat_list_settings.dart`、`settings_catalog.dart`、翻译、登记 | 开关在三处、搜索能找到、关掉后各行按 G6 显示 |
| 3 | 横屏、宽屏、大字号 | 测试 | 869×400、1280×800 跟着开关；280 宽 2 倍字不溢出 |

## 测试

- `apps/pure_live/test/features/live_play/chat_line_roles_test.dart`（新）：G1、G2、G3、G5、G6、大字号、直播间竖屏 / 横屏 / 宽屏、设置组。
- 改：`chat_line_marks_test.dart`（卡片的冒号）、`chat_names_test.dart`（粉丝牌是小块）、`settings_danmaku_test.dart`（开关和搜索）、`packages/live_store/test/danmaku_new_settings_test.dart`（默认值、备份）。

## 真机验证（维护者在 K90 上做）

见 [verify.md](verify.md)。

## 风险和注意

- `settings.dart`、`settings_defaults_test.dart`、`settings_audit_notes.py`、`OWNERS.toml`、翻译文件、`tasks.toml` 和生成的文档容易和同时合并的设置任务冲突：两边的行都保留，再运行 `python3 tools/docs/docs.py`。

## 环境和提交

- `source ~/tools/purelive-env.sh`；根目录 `bash tools/ffmpeg_kit/fetch.sh android`、`bash tools/ffmpeg_kit/fetch.sh linux`。
- 分支是本机工作区；提交信息以 `[A08.10]` 开头（英文）；不推 master。
- 提交前 `bash tools/gate/gate.sh --all`，日志里有 `gate: passed`。

## 报告（中文，简洁）

每条做到没有；测试数量；改了哪些文件；新设置和翻译键；要在真机上看的；可能冲突的文件。
