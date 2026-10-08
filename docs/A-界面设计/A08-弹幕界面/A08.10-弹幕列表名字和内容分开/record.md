# A08.10 弹幕列表里用户名和内容分开显示；加“显示用户名”开关：记录

- 日期：2026-10-09
- 执行者：Claude（本机工作区 `worktree-agent-a27c2eb0bda42cb93`，从 `87dd63729` 开始）
- 分支和提交：`worktree-agent-a27c2eb0bda42cb93`，提交见本文末尾“提交”
- 任务书：[brief.md](brief.md)；设计：[README.md](README.md)（G1～G12 按 D-003 由维护者定）；真机步骤：[verify.md](verify.md)

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| c1 名字和内容两个角色 | 做了：`ChatText.name`（`bodyLarge` 600，次要色或给的颜色）、`ChatText.content`（`bodyLarge` 400，`onSurface`）、`ChatText.nameEnd`（“：”）；紧凑行、卡片、本地弹幕和本地礼物、平台礼物、醒目留言一行、长按卡片都用它 | 没有 |
| c2 名字颜色一条规则 | 做了：`chatNameInk`（平台名字颜色 → 弹幕颜色 → 次要色，过 4.5:1）；卡片、长按卡片改成和紧凑行一样 | 卡片没有头像时名字原来是 `onSurface`，现在是次要色或彩色（G2、G3） |
| c3 标签顺序和粉丝牌 | 做了：“对方” → 徽章图 → 粉丝牌 → 名字 → 内容；粉丝牌改成 `ChatChip`（颜色不变） | 没有 |
| c4 “显示用户名”设置 | 做了：`showChatNames`（默认开），“弹幕列表”一组，搜索能找到 | 没有 |
| c5 关掉时的列表 | 做了：名字、徽章、粉丝牌、卡片头像不显示，“本地”“对方”留着；礼物、醒目留言一行、本地弹幕同样；长按卡片和复制不变 | 没有 |
| c6 “弹幕列表样式”的说明 | 做了：写明“用户名加粗、用浅色” | 没有 |
| 横屏、宽屏、大字号、三套主题 | 做了：同一个 `ChatList`；测试覆盖 869×400、1280×800、280 宽 1.3 倍和 2 倍字、浅色 / 深色 / 纯黑 | 没有改布局：现有的整段换行在 2 倍字下不溢出（G9） |

## 根因

- 名字和内容分不开：紧凑行的名字和内容同一个字号、同一个字重（`apps/pure_live/lib/features/live_play/danmaku/chat_list.dart` 改之前的 `_compact`：名字 `body?.copyWith(color: nameColor)`，`body` 是 `bodyLarge.regular`），只差 `onSurfaceVariant` 和 `onSurface` 的一点颜色，不符合 specs/UI.md 第 8.2 节“至少差一档字号或字重”。
- 各处不一样：卡片（`_card`）名字 600、`onSurface`、半角“: ”，有头像时才按弹幕颜色上色；本地弹幕（`local_chat_line.dart`）名字 400；长按卡片（`message_panel.dart` `_actions`）只看弹幕颜色、不看平台名字颜色——四处各写了一套样式，没有共用的角色。
- 粉丝牌是一段带 `backgroundColor` 的文字（`_fans`），和 E06.2 的 `ChatChip` 小块不是一个东西。

## 改了哪些文件

- 新：`apps/pure_live/lib/features/live_play/danmaku/chat_text.dart`（`ChatText`）。
- `apps/pure_live/lib/features/live_play/danmaku/chat_list.dart`：`chatNameInk`；`ChatList` 读 `showChatNames`、行缓存加这一项；`ChatLineView` 加 `showName`，`_lead`（顺序）、`_fans`（`ChatChip`）、`_name`、`_words`，紧凑行和卡片共用；礼物、醒目留言一行用名字角色。
- `apps/pure_live/lib/features/live_play/local_interaction/local_chat_line.dart`：`showName`；名字和内容用 `ChatText`。
- `apps/pure_live/lib/features/live_play/danmaku/message_panel.dart`：长按卡片用 `ChatText` 和 `chatNameInk`。
- `apps/pure_live/lib/shared/danmaku/chat_list_settings.dart`：“显示用户名”开关行。
- `apps/pure_live/lib/features/settings/settings_catalog.dart`：搜索条目 `danmaku_show_names`。
- `packages/live_store/lib/src/settings/settings.dart`：`Settings.showChatNames`，加进 `Settings.all`。
- 翻译：`apps/pure_live/assets/translations/zh.json`、`en.json`。
- 登记：`packages/live_store/test/settings_defaults_test.dart`（`newInV4`）、`tools/docs/settings_audit_notes.py`、`docs/inventory/OWNERS.toml`（`showChatNames` 归 A08）；生成的 `docs/inventory/OWNERS.md`、J01.2 `settings.md`、STATUS、TASKS、A 组和 A08 的 README。
- 文档：本文件夹的 README、brief、record、verify；A08 子分类 README 的“现状”和代码地图；`docs/tasks.toml` 登记 A08.10。

## 新设置、翻译键、门禁基线

- 新设置：`showChatNames`（`BoolSetting`，`section: 'danmaku'`，默认 `true`，跟备份和设备同步）；3.x 没有这个键，3.x 的备份导入后保持默认开（D-018）。
- 新翻译键：`danmaku_list_show_names`（“显示用户名”/“Show user names”）、`danmaku_list_show_names_desc`（“关掉后弹幕列表只显示内容；长按一条仍能看到是谁发的”）；改了文字：`danmaku_list_style_desc`。
- 门禁基线：没改。

## 测试

- 新增 `apps/pure_live/test/features/live_play/chat_line_roles_test.dart`（11 个）：
  - 两种样式 × 浅色 / 深色 / 纯黑：名字 600、次要色且 ≥4.5:1，内容 400、`onSurface`，同一个字号（改之前紧凑行名字是 400、卡片名字是 `onSurface`，这个用例会失败）；
  - 红、黄弹幕和平台名字颜色在三套主题、两种样式下都 ≥4.5:1，内容不跟着变色；
  - 顺序“对方 → 徽章 → 粉丝牌 → 名字 → 内容”两种样式一样，粉丝牌是 12 号 600 的小块（改之前粉丝牌不是小块，失败）；
  - 长按卡片的颜色规则（平台名字颜色优先）；
  - “显示用户名”关：紧凑和卡片只剩“对方”和内容、没有徽章 / 粉丝牌 / 头像；礼物、醒目留言一行、本地弹幕和本地礼物不显示名字，“本地”留着；
  - 280 宽（手机横着拿的列表）、1.3 倍和 2 倍字、三套主题、两种样式、所有标签加长名字：不溢出、整段换行、名字完整；本地弹幕 2 倍字不溢出；
  - 直播间竖屏：改设置后已显示的行和新来的行都不显示名字，长按卡片仍有名字；
  - 手机横着拿 869×400、宽屏 1280×800（卡片样式）：同一个列表跟着开关；
  - “弹幕列表”一组里开关在样式和礼物之间、默认开、点了改设置。
- 改了：`chat_line_marks_test.dart`（卡片的名字以“：”结尾）、`chat_names_test.dart`（粉丝牌是 `live-play-chat-fans` 小块）、`settings_danmaku_test.dart`（设置页的开关、搜索“用户名”在“弹幕 › 弹幕列表”）、`packages/live_store/test/danmaku_new_settings_test.dart`（默认开、`danmaku` 一节、备份带上）。
- `apps/pure_live` 的 `test/features/live_play`、`test/features/settings`、`test/shared` 542 个通过；`chat_benchmark_test.dart`（每秒 200 条 60 秒）单独跑：`ChatLineView` 602 次构建、每帧 45.2 个组件构建，和改之前一样（粉丝牌小块只在有粉丝牌的行上多一个组件）。
- 门禁：见文末。

## 真机上要看的

- 按 [verify.md](verify.md) 的 13 步。重点：
  - 深色和纯黑主题下，名字（加粗、浅灰）和内容（正常粗细、白）一眼分得开；彩色名字看得清。
  - 卡片样式没头像时名字从原来的白色变成浅灰或彩色，看是否舒服。
  - 粉丝牌小块和“本地”“对方”一样高，和文字居中对齐。
  - 关掉“显示用户名”后已经显示的行马上变；长按面板还有名字。
  - 手机横着拿的 280 宽列表、系统最大字号下整段换行、不出界。

## 提交

- 见报告；合并后在登记表补 `commit`。
