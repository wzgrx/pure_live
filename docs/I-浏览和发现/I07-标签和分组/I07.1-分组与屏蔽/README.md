# I07.1 分组与屏蔽

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能（页面重构）
- 来源：模块重构计划的页面部分（D-001）；3.x 的 `lib/modules/tags/`（`tag_management_page.dart` 736 行、`tag_management_controller.dart` 443 行）、`lib/modules/shield/`（`danmu_shield_page.dart` 132 行、`danmu_shield_controller.dart` 29 行）、直播间 `keyword_block_page.dart` 里屏蔽用户列表
- 旧编号：M13.9、T07h.1
- 相关：J02.1（`TagStore`、`BlockListStore`）；D01.1（`DanmakuBlockList` 匹配规则）；I01.2（设标签对话框进共用卡片菜单）；之后的 A09.10（标签管理界面）、A08.3（弹幕屏蔽页换成直播间的屏蔽管理组件）；提交 `caebee14d`；记录 [record.md](record.md)

## 目标

在 4.x 里做出 3.x 的标签管理页（添加、编辑、删除、置顶、拖动排序）和设置里的弹幕屏蔽页，并修掉 3.x 的问题：按下标操作标签、读屏不能排序、屏蔽词重复时不提示还清空输入、点一下就删且不能撤销、屏蔽用户只能进直播间看。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11`） | 当时做成 | 现在（文件:行） |
|---|---|---|---|
| 标签按什么操作 | 下标（`tag_management_page.dart:455`、`tag_management_controller.dart:225`），列表被替换时删不掉也不提示 | 按 id（`TagStore`），编辑期间被改则提示 | 同（`features/tags/tag_editor_dialog.dart:60-118`） |
| 排序 | 长按卡片（`:166`，`flutter_reorderable_grid_view`），读屏不能用 | `ReorderableListView` + 拖动把手 | 同（`tags_page.dart:139`） |
| 标签列表 | 两列网格 | 一列列表、房间数、详情转编辑 | 同，A09.10 定稿（最宽 720、按钮顺序） |
| 设标签 | `room_card.dart` 的选择框 | 不在本页（留给共用卡片菜单） | `shared/rooms/room_menu.dart:261` `editRoomTags`、`room_tags_dialog.dart:32`（I01.2、A09.1） |
| 弹幕屏蔽页 | 只有关键词，点小块就删（`danmu_shield_page.dart:86`），重复时清空输入不提示（`danmu_shield_controller.dart:13-14`） | 两页“关键词”“用户”、撤销、清空、就地报错 | A08.3（`5ba728803`）换成直播间同一个 `DanmakuBlockManager`（四组：关键词、已屏蔽用户、平台过滤、相似过滤），`features/shield/shield_page.dart` 47 行；“清空”和手动加屏蔽用户随设计去掉，撤销和重复提示保留 |
| 屏蔽用户 | 只能在直播间的屏蔽面板里看、删 | 设置页“用户”标签页 | 设置页“已屏蔽用户”一组（同一组件） |

## 结果

- 做了什么（详见 [record.md](record.md)“做法”）：标签管理（`tags_page.dart`、`tag_tile.dart`、`tag_editor_dialog.dart`：按 id 写入 `TagStore`、同一时间一个改动、一个对话框、拖动后先按新顺序显示、名字 15 字说明 40 字、同名不分大小写）；弹幕屏蔽（当时的 `shield_page.dart` + `block_list_tab.dart`：两页、新的在前、点小块或 × 移除可撤销、清空可撤销、就地报错）。
- 修了 3.x 问题 6 条（record.md“v3 问题及处理”；第 6 条 `togglePinStatus` 没有调用者，不搬）。
- 界面改进 13 条：标签部分由 A09.10 定稿；屏蔽部分由 A08.3 整体换掉。
- 翻译键中英文各 25 个（`shield_*` 16 个、`tags_*` 9 个）；`shield_*` 里除 `shield_title`、`shield_removed` 外已随 A08.3 删掉。
- 提交 `caebee14d`（2026-10-01）。
- 测试：当时 7 个（`tags_page_test.dart` 4、`shield_page_test.dart` 3）。

## 验证

- 自动测试：现在 `apps/pure_live/test/features/tags/tags_page_test.dart` 7 个（A09.10 加了布局和对话框的用例）；`test/features/shield/shield_page_test.dart` 7 个已是 A08.3 的测试（一页四组、空说明、撤销、带 `BlockKind.user` 滚到用户）。
- 真机：record.md 没有 K90 结果；标签管理和设标签没有真机记录（见[子分类说明](../README.md)“已知问题”）。弹幕屏蔽页的真机步骤归 A08.3。

## 留下的问题

- record.md“留给后续”现在的去向：设标签的选择框 → I01.2、A09.1（完成，`editRoomTags`、`RoomTagPicker`）；关注页按标签筛选 → I04.1（完成）；设置页入口 → J01.1、A11（完成）；多画面的弹幕过滤读 `store.blockLists` → N01（完成）。
- 标签名和说明的上限写了两份（`tag_editor_dialog.dart:10-13`、`room_tags_dialog.dart:13-16`）：见子分类“已知问题”，没有任务。
