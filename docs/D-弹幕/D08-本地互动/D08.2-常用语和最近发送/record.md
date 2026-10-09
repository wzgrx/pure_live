# D08.2 常用语和最近发送：记录

- 日期：2026-10-09
- 执行者：Claude（本机工作区，没有推送、没有合并）
- 分支和提交：工作区分支 `worktree-agent-a4c68d33d49a63222`，提交 `[D08.2] …`（在 `[A08.14]` 之后，同一个长按面板先后做）；起点 master `1748290b9`（含 D08.1）
- 任务书：[brief.md](brief.md)；设计和每条选择的理由：[README.md](README.md)“设计”c1～c5、“定稿的选择”s1～s11（维护者按 D-003 定）；来源：V03.6 第 4 节 E6、第 5.3 节最后一段

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| 1 新设置 `localInteraction.phrases`（默认空、最多 20 条），跟备份和设备同步 | 做了 | 每条最多 **40** 字，不是 100（s2：常用语就是一条本地弹幕，A08.13 定的上限是 40）；放在设置里不另开表（s1） |
| 2 获得焦点时上方一排：最近 5 条（不重复，取自 D08.1）+ 常用语；都没有时不出现 | 做了 | 已经是常用语的那句不算进“最近”（s4）；全屏下栏里这一排浮在输入框上方（s5） |
| 3 点标签直接发；长按放进输入框 | 做了 | 点了以后输入框里打了一半的字不动（s7） |
| 4 本地弹幕的长按面板“存为常用语”（存过的“已在常用语里”） | 做了 | 满 20 条时点不了并写明（s9） |
| 5 设置 → 本地用户与互动“常用语”一组：加、删（4 秒撤销）、排序 | 做了 | 另外点文字可以修改；删除用按钮，没做左滑（s10） |
| 6 三处输入框一样；文字走翻译 | 做了 | 竖屏和宽屏列表下面、互动面板、全屏下栏（含窄于 180 点开的输入行）都是 `LocalComposerChips` |

## 根因

- 新功能，3.x 没有常用语。本地弹幕在 D08.1 以前不进记录，所以“最近发过”要等 D08.1 的 `local_events`（已合并）。
- 顺手修的 D08.1 小毛病：`apps/pure_live/lib/features/live_play/local_interaction/logic/local_interaction.dart` 的 `_keep` 用 `write(store).catchError((Object _) {})`；`LocalEventStore.add` 返回的是 `Future<int>`，写入失败时 `catchError` 的处理函数必须返回 `int`，于是又抛出 `ArgumentError`（逻辑测试在数据库关了以后写入时看到的）。改成 `then((_) {}, onError: …)`。正常使用时只有退出那一刻会碰到。

## 存储

- `localInteraction.phrases`：`StringListSetting`（`packages/live_store/lib/src/settings/setting.dart` 新加两个可选参数：`tidy` 去首尾空白、空的和重复的，`maxItems` 只留前 N 条；别的列表设置不传，行为不变），`localInteraction` 一节、`SettingScope.synced`：完整备份里在 `localInteraction` 一节，设备同步属于“设置”一类；3.x 读备份时不认识这个键，忽略。
- 每条 40 字由应用管（`LocalCatalog.clipDanmaku`：去首尾空白、按字取前 40 个），读的时候截（备份里写长了也只显示和发出 40 字），存的时候也截。
- 最近发过：不存，现算（`LocalInteraction.recentChats`，读内存里的 `events`，D08.1 已经加载）。

## 改了哪些文件

- `packages/live_store/lib/src/settings/setting.dart`（`StringListSetting.tidy`、`maxItems`、`normalize`）、`settings.dart`（`localInteractionPhrases`、`localPhraseLimit`，加进 `Settings.all`）。
- `apps/pure_live/lib/features/live_play/local_interaction/logic/local_catalog.dart`（`clipDanmaku`、`recentCount`）、`logic/local_interaction.dart`（常用语的读写、`phraseProblem`、`recentChats`、`LocalPhraseProblem`；`_keep` 的写入失败）。
- `apps/pure_live/lib/features/live_play/local_interaction/local_composer.dart`（`LocalComposerChips`；列表下面和面板里放在输入行上面，画面上用 `OverlayPortal` 浮在输入框上方）。
- `apps/pure_live/lib/features/live_play/danmaku/message_panel.dart`（`_SavePhraseRow`；`localSendAgainText` 改用 `LocalCatalog.clipDanmaku`，行为不变）。
- `apps/pure_live/lib/features/live_play/local_interaction/local_interaction_settings_page.dart`（`LocalPhrasesEditor`、`_PhraseRow`）。
- `packages/live_ui/lib/src/icons/app_icons.dart`（4 个图标）；`zh.json`、`en.json`（15 个键）。
- 测试：新文件 `packages/live_store/test/local_phrases_test.dart`、`apps/pure_live/test/features/live_play/local_phrases_test.dart`；`packages/live_store/test/settings_defaults_test.dart`（`newInV4`）；`apps/pure_live/test/shared/sync_parts_test.dart`（一个）；`packages/live_ui/test/design_system_test.dart`（对照表）。
- 文档：本文件夹（README 的定稿选择、record）；D08 子分类 README（代码地图、已知问题、测试）；A08.2 README“实现和验证”补一条；`tools/docs/settings_audit_notes.py`（新设置的说明）和生成的 J01.2 `settings.md`；`docs/tasks.toml`（D08.2）。
- 没改：`chat_list.dart`、发送的规则（`LocalRoomSession.sendChat`）、3.x 的键、版本号。

## 新设置、图标、翻译键

- 新设置：`localInteraction.phrases`，默认 `[]`（D-040：老用户看不到变化），最多 20 条，每条 40 字。
- 新图标：`AppIcons.localRecent`（`history_rounded`，“最近”标签）、`localPhraseSave`（`playlist_add_rounded`，存为常用语）、`localPhraseSaved`（`playlist_add_check_rounded`，已在常用语里）、`localPhrases`（`format_list_bulleted_rounded`，设置页这一组的说明）。
- 新翻译键（zh、en，按键名排序）：`local_chip_recent`、`local_phrase_add`、`local_phrase_added`、`local_phrase_deleted`、`local_phrase_edit`、`local_phrase_empty`、`local_phrase_exists`、`local_phrase_hint`、`local_phrase_save`、`local_phrase_save_desc`、`local_phrase_saved`、`local_phrases`、`local_phrases_desc`、`local_phrases_empty`、`local_phrases_full`。

## 测试

- `packages/live_store/test/local_phrases_test.dart`（5 个）：键、默认空、`localInteraction` 一节、进备份；读的时候去空白、去空、去重、只留 20 条（重复的不占名额）、不是列表读成空；别的列表设置照旧（不去重）；存进去读出来是整理过的、完整备份带上、恢复后顺序一样、覆盖另一台的；D08.2 以前的备份（和 3.x 的）恢复后是空的，坏的被修好。`settings_defaults_test.dart`：`newInV4` 里加了这个键（默认空）。
- `apps/pure_live/test/features/live_play/local_phrases_test.dart`（21 个）：
  - 逻辑 4 个：最近 5 条不重复、新的在前、常用语不算、礼物和加币不算；加在最后、去空白、截 40 字（emoji 算一个）、不重复、满 20 条；修改、移动、删掉再放回（放回原位、不重复放）、存进设置；备份里写长了读出来截成 40 字、截完一样的只算一条。
  - 输入框 14 个：竖屏没有焦点、没有内容时不出现，有了以后最近 5 条（带“最近”图标）在前、常用语在后，在输入栏里、在输入框上面，失去焦点就收起；点标签发出（进记录）、打了一半的字和焦点都还在、发过的常用语只出现一次，长按放进输入框（光标在最后）、不发出；互动面板的输入框同样；横屏全屏、竖屏、窄全屏下栏（<180，点开的输入行）各在 1、1.3、2 倍字号下：标签在输入框上面、都在屏幕里、不溢出；全屏的标签和输入框一样宽、长的常用语以“…”结尾、字最多放大 1.3 倍、点了飞过画面、仍在全屏；窄下栏点了以后输入行关上。
  - “存为常用语”2 个：自己的本地弹幕在“再发一次”下面有，点了关面板、提示“已存为常用语”、存进设置；再长按是“已在常用语里”、点不了；平台弹幕没有；满 20 条时点不了并写明。
  - 设置页 3 个：在“画面上”后面、空的说明、“0 / 20”；添加（输入框 40 字）、重复的在框下说“已经有这条常用语了”不关、修改；删除马上没了、提示条 4 秒、点“撤销”回到原位；拖动把手排序、存进设置；满 20 条“添加常用语”变灰并写明。
- `apps/pure_live/test/shared/sync_parts_test.dart` 新增 1 个：常用语跟“设置”一类走，不勾设置时这台的不变，勾了换成来的。
- 跑过：`local_phrases_test.dart`、`local_plus_one_test.dart`、`local_interaction_test.dart`、`local_history_test.dart`、`sync_parts_test.dart`，`packages/live_store` 的设置、备份、常用语测试。

## 门禁

- 和 A08.14 一起跑，结果写在下面一次提交里。

## 真机上要看的

K90（`com.mystyle.purelive.v4dev`，每次点按前确认前台是测试包）：

1. 竖屏直播间发几条本地弹幕（有一两句重复），点输入框：键盘弹起后，输入框上方一排标签，最近发过的 5 条（不重复、新的在左、带小钟图标）；输入框和标签都在键盘上面，没有被顶出屏幕；标签能横着滑。
2. 点一个标签：直接发出（列表多一条、画面上飞过），键盘不收；长按一个标签：它进了输入框，光标在最后，没有发出。
3. 长按自己的一条本地弹幕：“再发一次”下面有“存为常用语”；点了面板关、提示“已存为常用语”；再点输入框，标签最后多了它（最近里不再重复出现）；再长按同一条：“已在常用语里”，灰的。
4. 全屏横屏（控制层显示时）点下栏中间的输入框：标签浮在输入框上方、和输入框一样宽、深色底白字；点一个发出后飞过画面，仍在全屏；横屏键盘（可能是全屏输入法）弹起时看标签和输入框的位置。
5. 把下栏中间弄到窄于 180（分屏或窄横屏）：点圆按钮打开的输入行上方同样有标签；点标签发出后输入行关上。
6. 右上角菜单 → 本地互动体验：面板里的输入框同样有标签。
7. 设置 → 本地用户与互动：“画面上”下面有“常用语”一组；添加一条、点文字修改、按住左边把手拖动排序、点右边删除（提示条 4 秒“撤销”，点了回到原位）；加到 20 条时“添加常用语”变灰。回直播间看标签的顺序和设置页一样。
8. 系统字体调到最大，重复步骤 1、4：标签和输入框不溢出、不截断成一半；全屏下栏的标签字比竖屏的小一些（最多 1.3 倍）。
9. 设备同步（J05）只勾“设置”从另一台发过来：常用语跟着过来；不勾“设置”时这台的常用语不变。
10. 关掉本地互动：设置页只剩第一组，直播间没有输入框，长按本地弹幕没有这两行。
