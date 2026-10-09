# D08.2 常用语和最近发送

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能
- 来源：[V03.6](../../../V-需求和反馈/V03-审查和调研/V03.6-弹幕系统和本地互动体验/README.md) 第 4 节 E6、第 5.3 节最后一段；用户 2026-10-09 点名“预设”（D-040）
- 相关：依赖 [D08.1](../D08.1-结构化的本地历史/README.md)（最近发过取自记录）；本地互动界面 [A08.2](../../../A-界面设计/A08-弹幕界面/A08.2-本地互动/README.md)（输入框 `local_composer.dart`）；“+1（本地）”A08.14；决定 D-018、D-040；任务书 [brief.md](brief.md)

## 目标

常说的话不用每次重打：本地弹幕输入框上方一排小标签——最近发过的 5 条 + 自己存的常用语（最多 20 条）；点一下直接发，长按放进输入框再改。长按自己的本地弹幕可以“存为常用语”；设置页能排序、删除。

## 3.x 和现状

| 方面 | 3.x | 现在 | 要做到 |
|---|---|---|---|
| 常用语 | 没有 | 没有 | 新设置 `localInteraction.phrases`（字符串列表，最多 20 条，每条最多 100 字，默认空） |
| 最近发过 | 没有 | 本地弹幕不记（D08.1 之前） | 从 D08.1 的记录取最近 5 条不重复的弹幕 |
| 输入框 | 输入框 + 发送 | 三处同一个组件 `LocalDanmakuComposer`（`features/live_play/local_interaction/local_composer.dart:49`） | 获得焦点时上方一排标签 |

## 设计（D-003，维护者定）

- c1 输入框获得焦点时，上方出一排可以横着滑的小标签（`ActionChip` 一类，`live_ui` 的组件）：先最近 5 条（带“最近”小图标），再常用语。没有内容时不出这一排。全屏下栏的窄输入框（窄于 180 收成按钮，`local_composer.dart:26`）展开后才有。
- c2 点一下 → 直接发（`LocalRoomSession.sendChat`）；长按 → 放进输入框，光标在最后。
- c3 本地弹幕的长按面板加“存为常用语”（和 A08.14 的“再发一次”在同一个面板里，先后做）；已经存过的写“已在常用语里”。
- c4 设置 → 本地用户与互动加一组“常用语”：列表、拖动排序、左滑或按钮删除（删除给 4 秒撤销，UI.md 第 7 节）、加一条。
- c5 常用语跟备份和设备同步（随设置一起走）。
- 默认空，老用户看不到变化（D-040）。

## 定稿的选择（D-003，维护者定，2026-10-09）

c1～c5 照上面的设计做；任务书没写死、开发时定下的：

| 编号 | 选择 | 理由 |
|---|---|---|
| s1 | **常用语存在设置里**：`localInteraction.phrases`（`StringListSetting`，`localInteraction` 一节），不另开表 | 最多 20 条、每条 40 字，整张表一起改（加、删、排序），从不按直播间查；设置的一节自动进完整备份和设备同步的“设置”一类（c5），不用再接 J03、J05；V03.6 第 5.3 节和任务书都写的是“一个列表设置”。D08.1 的记录要按直播间查、最多 2000 条，所以才放表——这里两条理由都不成立 |
| s2 | **每条最多 40 个字**，不是任务书写的 100 | 常用语就是一条本地弹幕，本地弹幕的上限是 40（A08.13 c3，`LocalCatalog.danmakuLimit`）；100 字的常用语点了也只能发出前 40 个字。按字数（emoji 算一个）截，和输入框一样 |
| s3 | 设置本身（`live_store`）管条数和整理：最多 20 条（`maxItems`），去掉首尾空白、空的和重复的（`tidy`）；40 字由应用管（`LocalCatalog.clipDanmaku`，读的时候截，写的时候也截） | 存储包是纯 Dart、不按“字”数（emoji 由几个码位组成），按码位截会把一个 emoji 截坏；条数和重复不涉及这个，放在设置里，备份导入的坏数据在读的时候就修好（和其他设置一样） |
| s4 | **最近发过取自 D08.1 的记录**（`local_events`，`LocalInteraction.events`，已经在内存里）：所有直播间的最近 5 条不重复的本地弹幕，新的在前；已经是常用语的不算（它有自己的标签），再往前补够 5 条 | 不另存；不按直播间分，换一个直播间也常说同一句；不重复显示同一句 |
| s5 | 标签的位置：竖屏和宽屏列表下面、互动面板里，标签是输入框的一部分（在输入行上面，列表让出位置）；全屏下栏是固定高度，标签浮在输入框上方（`OverlayPortal`，和输入框一样宽）；窄于 180 收成按钮时，点开的输入行上方同样浮着 | 下栏的一行不能长高；列表下面浮在列表上会挡住最后几行，让出位置更清楚 |
| s6 | 标签用 Material `ActionChip`（应用的芯片主题 `appChipTheme`，36 高、8 圆角）；最近的带 `AppIcons.localRecent`（`history_rounded`）；一个标签最宽 200，长的以“…”结尾；画面上的标签是输入框的深色底、白字，字跟系统放大最多 1.3 倍（UI.md 第 8.2 节）；列表下面的跟系统放大 | 和应用其他芯片一样；画面上的控件都这样 |
| s7 | 点一下：直接发（`LocalRoomSession.sendChat`，和输入框同一条路，进记录、按设置飞过），输入框里打了一半的字不动；窄屏点开的输入行发出后照旧关上。长按：用这条替换输入框里的字、光标在最后 | c2；不把打了一半的话吞掉 |
| s8 | 标签那一排算输入框的一部分（`TextFieldTapRegion`）：用鼠标点标签不会让输入框失去焦点 | 否则桌面上点下去那一刻标签就收起来了 |
| s9 | “存为常用语”只给自己的本地弹幕（平台弹幕先“+1（本地）”再存），在“再发一次”下面；存到最后一条；存过的写“已在常用语里”、点不了；满 20 条时点不了、说明写“常用语最多 20 条，先删掉一些”；点了关面板、提示“已存为常用语” | c3；和 A08.14 同一个面板，先后做 |
| s10 | 设置页：“画面上”下面一组“常用语”；一条一行：左边把手（按住拖动排序，和标签管理、热门平台的把手一样）、点文字弹出修改框、右边删除；删除马上生效、提示条“已删除常用语“…”· 撤销” 4 秒（UI.md 第 7 节）；“添加常用语”弹输入框（40 字计数、重复的在框下说“已经有这条常用语了”）；旁边“n / 20”，满了按钮变灰并写明；没有常用语时写“长按自己发的本地弹幕可以存为常用语” | c4；“左滑或按钮删除”选了按钮：一行里已经有拖动，左滑和拖动容易互相误触 |
| s11 | 默认空；本地互动关着时设置页只剩第一组（和以前一样），输入框和面板这两行也都没有 | D-040：老用户看不到变化 |

另外修了 D08.1 的一个小毛病：记录写进数据库失败时（例如退出时数据库已经关了），`LocalInteraction._keep` 的 `catchError` 处理函数返回不了 `int`，又抛出一个错误；改成 `then(onError:)`。

## 实现和验证

- 代码：`packages/live_store/lib/src/settings/setting.dart`（`StringListSetting` 的 `tidy`、`maxItems`）、`settings.dart`（`localInteractionPhrases`、`localPhraseLimit`）；`apps/pure_live/lib/features/live_play/local_interaction/logic/local_catalog.dart`（`clipDanmaku`、`recentCount`）、`logic/local_interaction.dart`（`phrases`、`addPhrase`、`editPhrase`、`removePhrase`、`restorePhrase`、`movePhrase`、`phraseProblem`、`recentChats`、`LocalPhraseProblem`）；`local_composer.dart`（`LocalComposerChips`、三处的位置）；`danmaku/message_panel.dart`（`_SavePhraseRow`）；`local_interaction_settings_page.dart`（`LocalPhrasesEditor`）；`AppIcons.localRecent`、`localPhraseSave`、`localPhraseSaved`、`localPhrases`；翻译 15 个键。
- 测试：`packages/live_store/test/local_phrases_test.dart`（5 个）、`settings_defaults_test.dart`（新设置默认空）；`apps/pure_live/test/features/live_play/local_phrases_test.dart`（21 个）。
- 记录和真机上要看的：[record.md](record.md)。
