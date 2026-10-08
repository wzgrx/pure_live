# I06 观看历史

观看记录背后的逻辑：记录怎么来（进房成功后记一条）、保留多少（上限、截断）、按日期怎么分组和筛选、刷新怎么做（并发、超时、失败标状态未知、离开页面也保存）、删除和清空删哪些。观看记录也是直播间“看其他”、多画面选房、桌面图标长按的“最近直播间”的来源。

## 范围

- 包括：
  - `apps/pure_live/lib/features/history/history_sections.dart`：按观看日期分组（`HistorySection`）、筛选（`filterHistory`）、观看时间文字。
  - `features/history/history_refresh.dart`：刷新（`siteHistoryLoader`、`refreshHistoryRooms`、`HistoryRefreshResult`）。
  - `features/history/history_limit_dialog.dart` 的规则：预设、自定义、0 = 不限、没点“应用”直接确认也采用输入的数字、改小时提醒会删几条。
  - `features/history/history_page.dart` 里调存储的地方：`historyRoomsProvider`（`watchAll`）、`_runRefresh`（`:83`）、`_remove`、`_clear`（只删当时显示的）、`_editLimit`；页面内的 provider `historyLoaderProvider`、`historyClockProvider`（测试替换）。
  - 存储语义（`live_store` 的 `HistoryStore`，`packages/live_store/lib/src/rooms.dart:152`）在这里怎么用：新的在前、重看移到最前、按 `historyLimit` 截断、刷新合并不改顺序。
- 不包括（归哪里）：
  - 观看记录页**长什么样**（标题“观看记录”和第二行“18 / 50 条”、按钮顺序、分组标题、网格、卡片的删除按钮、三个对话框）→ [A09.9 观看历史](../../A-界面设计/A09-浏览界面/A09.9-观看历史/README.md)；卡片和卡片对话框 → A09.1。
  - 记录一条历史：直播间进房成功后 `store.history.record`（`features/live_play/logic/room_controller.dart:440`）→ [C01](../../C-直播间/C01-进房和房间逻辑/README.md)；“看其他”面板的历史来源（`room_switch_panel.dart:153`）→ A07.13；多画面选房（`multiview/widgets/room_picker.dart:154`）→ N01；桌面图标长按的最近直播间（`app/intake/system_intake.dart:57`）→ O03；电视的观看记录（`tv/pages/tv_history_pane.dart`）→ X03。
  - `HistoryStore` 本身、3.x 历史的导入、备份里的历史 → J02、J06、J03。

## 现状：做到哪、怎么工作的

- 用户看得到的：
  - 设置“历史记录上限”默认 50（0 = 不限）；新的在前，重看的移到最前，超过上限删最早的。
  - 页面：按今天、昨天、近 7 天、更早分组（按日历日，没有观看时间的旧记录归“更早”），每组带条数；标题第二行“18 / 50 条”。
  - 筛选：按标题、主播、房间号、平台名（含中文名）；筛选时“清空”只删匹配的，刷新也只刷匹配的。
  - 刷新（下拉或顶栏“刷新”）：同时最多“并发刷新数”个（默认 4），每个 12 秒；有轻量刷新接口的平台用它；失败的、或平台回了另一个房间的，标“状态未知”（不再显示几天前的“直播中”和人数）；同一时间只跑一次，再拉一次并到正在跑的那次；离开页面后不再发新请求，已取到的照样存；结束提示“已刷新 N 个直播间”或“N 个中有 M 个刷新失败，已标为状态未知”。
  - 删除一条、清空：先确认；只删页面当时显示的那些，之后又看过的（观看时间变了）保留。
  - 保留数量：预设 20、50、100、200、500、不限，加自定义数字；输入了数字没点“应用”直接点“确认”也采用（3.x 会悄悄丢掉）；改小时红字“保存后将删除最早的 N 条记录”。
- 内部怎么工作：

```text
进房成功：room_controller.dart:440 → store.history.record(room, now)（新的在前、去重、按 historyLimit 截断）
HistoryPage（history_page.dart:44）
  historyRoomsProvider（:22，watchAll，autoDispose）→ _shown = filterHistory(rooms, 筛选词)
  → HistorySection.of(watchedAt, now) 分组（history_sections.dart:26）
  _refresh（:81，同一时间一次）→ _runRefresh（:83）
      refreshHistoryRooms（history_refresh.dart:47）：min(并发, 条数) 个 worker，每个 12 s
          siteHistoryLoader（:13）：getRoomDetailForRefresh 或 getRoomDetail；没有适配器抛错
          成功且同一身份 → 新详情；否则 → pendingAfterError()
      → store.history.update(结果)（合并，不改顺序，页面关了也存）→ 提示
  _remove / _clear（:144、:158）→ HistoryStore.clear(当时显示的)
  _editLimit（:176）→ HistoryLimitDialog → settings.set(historyLimit) + 截断
```

- 完成度（和 3.x 对照）：
  - 一致的：上限设置和默认值、新的在前、并发设置和 12 秒、同一时间一次刷新、删除和清空先确认、长按菜单、点卡片进房、保留数量的预设和自定义、整宽“应用”按钮（A09.9 c1 恢复 3.x 的）。
  - 确认过的改动：没点“应用”的数字也采用（I06.1 问题 1）；失败标状态未知（问题 2）；顶栏刷新按钮（问题 3，鼠标拉不出下拉刷新）；离开页面也保存（问题 4）；轻量刷新接口（问题 5）；按日期分组、筛选、刷新结果提示、改小时提醒、空状态说明（A09.9 c2～c8）；平台回了另一个房间时算失败、不替换这一条（3.x 会替换）。
  - 还缺：无功能缺口。

## 代码地图

| 文件 | 职责 |
|---|---|
| `apps/pure_live/lib/features/history/history_sections.dart`（93 行） | `HistorySection`（`:6`：今天、昨天、近 7 天、更早；`of` `:26`，按日历日）、`filterHistory`（`:59`，标题、主播、房间号、平台名）、`historySectionTitle`（`:76`）、`historyWatchedLabel`（`:81`，“今天 21:05 / 09-30 21:05 观看”） |
| `features/history/history_refresh.dart`（86） | `HistoryRoomLoader`（`:7`）、`siteHistoryLoader`（`:13`，没有适配器时抛错）、`HistoryRefreshResult`（`:23`，`succeeded`）、`refreshHistoryRooms`（`:47`：worker `:61`、身份不同算失败 `:73-74`） |
| `features/history/history_limit_dialog.dart`（194） | `unlimitedHistoryLimit` 0（`:11`）、`historyLimitLabel`（`:14`）、`showHistoryLimitDialog`（`:20`）、`HistoryLimitDialog`（`:32`：`_applyCustom` `:69`、`_save` `:80`，没点“应用”的数字先校验再采用 `:82-86`） |
| `features/history/history_page.dart`（434） | `historyRoomsProvider`（`:22`）、`historyLoaderProvider`（`:27`）、`historyClockProvider`（`:32`）；`HistoryPage`（`:44`：`_refresh` `:81`、`_runRefresh` `:83`、`_remove` `:144`、`_clear` `:158`、`_editLimit` `:176`、筛选 `_toggleFilter` `:183`、返回先关筛选 `_back` `:192`、卡片对话框加“从历史删除” `_openMenu` `:200`）；其余是界面（A09.9） |
| `packages/live_store/lib/src/rooms.dart:152` | `HistoryStore`：`record`、`watchAll`、`all`、`update`（合并）、`clear(rooms)`、`setLimit`（J02） |
| `packages/live_store/lib/src/settings/settings.dart:137` | `historyLimit`（默认 50，最小 0） |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `apps/pure_live/test/features/history/history_page_test.dart`（17 个用例，含按尺寸展开的） | 空状态；按日分组、条数和上限；删除和清空先确认；筛选和只清空匹配的；顶栏刷新拉出 3.x 的刷新头（P02）；刷新更新、保留观看时间、失败标未知；轮播和封禁的标记（1-1）；保留数量提醒和截断；长按菜单关注、取消关注先确认、删除；标题和按钮顺序（U.5c）；各尺寸列数；Esc 和返回先关筛选；右键开对话框（附录 A 第 14 条）；空页没有清空按钮；保留数量框的整宽“应用”；卡片数据；刷新并发上限和取消 |

## 3.x 基线

- `~/ref/v3ref/lib/modules/history/history_page.dart`（`git show v3.2.11:lib/modules/history/history_page.dart`，407 行）：刷新 `onRefresh`（`:26`，同一时间一次）、`_refreshHistory`（`:28`，并发设置 `:33`、12 秒 `:49`，失败返回原房间 `:51-54`，离开页面不保存 `:58`）；保留数量框 `draftLimit`（`:256`、`:265`、`:276`），`_save` 只存 `draftLimit`（`:295-299`）。
- `lib/common/services/settings/history_controller.dart`（236 行，存储部分已在 J02.1 变成 `HistoryStore`）；进房时记录 `lib/modules/live_play/controllers/live_play_controller.dart:752`、`:809-811`（`addRoomToHistoryDurably`）。
- 必须保留的操作习惯（[specs/UI.md](../../specs/UI.md) 附录 A）：第 14 条（卡片长按或右键 = 操作菜单）；第 7 条的返回链（筛选打开时返回先关筛选，`history_page.dart:192`）。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 已下线平台（没有适配器）的记录每次刷新都算失败，提示里的“刷新失败”数包括它们；关注页是直接跳过不请求 | `history_refresh.dart:15`（`site == null` 抛错）；对照 `features/favorite/follow_refresher.dart:64` | 历史里有已下线平台的记录时，每次刷新都提示“有 M 个刷新失败” | [I03.2](../I03-分区/I03.2-浏览列表的小问题合集/README.md) 第 2 阶段（2026-10-07 登记：跳过，和关注一致）；2026-10-08 已改，待 K90 |
| 平台回了另一个身份的房间（改名、换场）时算失败、不替换（3.x 会替换这一条） | `history_refresh.dart:73-74` | 改了房间号的主播在历史里一直是“状态未知” | 有意（I06.1 记录）：避免把别人的房间写进历史；不做 |
| I06.1 记录里的 `history_cards.dart`、`history_room_menu.dart` 已不在（卡片用 A09.1 的 `LiveRoomCard`，菜单用共用的卡片对话框加“从历史删除”）；记录里的测试路径 `test/pages/history/` 现在是 `test/features/history/`，9 个变 17 个 | [I06.1 记录](I06.1-观看历史/record.md) | 只是记录过时 | I06.1 README 已注明 |
| I06.1 登记“完成”，记录没有 K90 结果；S02.3 看过观看记录的列表和点进房 | [S02.3 记录](../../S-质量和验证/S02-真机验证/S02.3-K90验证主流程/record.md) | 刷新、筛选、保留数量没有真机记录 | 建议并入 S02.6 第 3 阶段（写进本单元报告） |

## 相关决定和规范

- D-009（下拉刷新回弹）、D-017（测试用内存库 `LiveStore.memory()` 和假时钟）、D-018（`historyLimit` 照 3.x 的键和默认值）。
- [specs/UPGRADES.md](../../specs/UPGRADES.md)：统一原则“卡片标出受限类型”“占位信息不覆盖存下的值”、28-2（历史卡片部分）、1-1（轮播和封禁标记）。

## 测试和验证

- 自动：`cd apps/pure_live && flutter test test/features/history`（17 个）；`HistoryStore` 的截断和合并在 `packages/live_store` 的测试里。缺的：已下线平台的记录刷新时的处理。
- 真机：[S02 真机清单](../../S-质量和验证/S02-真机验证/CHECKLIST.md)第 4 节（历史）；S02.3 走过。

## 路线

本子分类没有未完成的任务。页面的样子由 A09.9 管（已完成）。“已知问题”第 1 条并进了 [I03.2](../I03-分区/I03.2-浏览列表的小问题合集/README.md)（2026-10-07）。新想法（例如按平台筛选、导出历史）写进 [V01](../../V-需求和反馈/V01-新功能提议/README.md)。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [I 浏览和发现](../README.md)。

- 代码：`features/history/`
- 进度：`████████████████████` 100%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| I06.1 | 观看历史 | 功能 | 完成 | 2026-10-01 | 070024e43 | [设计或说明](I06.1-观看历史/README.md)、[记录](I06.1-观看历史/record.md) |

<!-- docs:生成结束 -->
