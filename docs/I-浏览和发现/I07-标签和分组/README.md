# I07 标签和分组

关注的分组（4.x 叫“标签”，3.x 叫“自定义标签”）背后的逻辑：标签的增删改、名字校验、置顶和排序、给直播间设标签（未关注先关注）、关注页按标签筛选用到的计数；以及设置里“弹幕屏蔽”页的入口和参数（屏蔽本身的数据和规则在 D02、界面在 A08.3）。

## 范围

- 包括：
  - 标签管理页的逻辑：`apps/pure_live/lib/features/tags/tags_page.dart`（`tagListProvider`、`tagFollowsProvider`、同一时间一个改动、一个对话框、拖动后先按新顺序显示）、`tag_tile.dart` 的 `followedTagCounts`（只数仍在关注里的房间）、`tag_editor_dialog.dart` 的校验（名字 15 字、说明 40 字、空名和同名、编辑期间被别处改了不覆盖）。
  - 给直播间设标签：`apps/pure_live/lib/shared/rooms/room_menu.dart` 的 `editRoomTags`（`:261`，未关注先问“关注并设置标签”）、`shared/rooms/room_tags_dialog.dart` 的 `RoomTagPicker`（多选、就地新建、保存 `setTagsOf`）。
  - 存储的用法：`live_store` 的 `TagStore`（`packages/live_store/lib/src/tags.dart:57`：`validateName`、`add`、`update`、`delete`、`reorder`、`pinToTop`、`tagsOf`、`setTagsOf`、`watchAll`、`watchAssignments`）。
  - 设置里的弹幕屏蔽页的路由和参数：`features/shield/shield_page.dart`（`RoutePath.kSettingsDanmuShield`，参数 `BlockKind.user` 时滚到“已屏蔽用户”）。
- 不包括（归哪里）：
  - 标签管理页、设标签对话框**长什么样** → [A09.10 标签管理](../../A-界面设计/A09-浏览界面/A09.10-标签管理/README.md)、[A09.1 房间卡片](../../A-界面设计/A09-浏览界面/A09.1-房间卡片/README.md)（卡片对话框里的“设置标签”）。
  - 弹幕屏蔽页的界面（`DanmakuBlockManager` 四组）→ [A08.3](../../A-界面设计/A08-弹幕界面/A08.3-弹幕屏蔽页/README.md)；屏蔽词和屏蔽用户的存储（`BlockListStore`，`packages/live_store/lib/src/block_lists.dart:15`）和匹配规则（包含即屏蔽、名字完全相同即屏蔽、打码昵称）→ [D02 过滤和屏蔽](../../D-弹幕/D02-过滤和屏蔽/README.md)。
  - 关注页按标签筛选、标签顺序参与排序 → [I04](../I04-关注/README.md)（`favorite_rules.dart` 的 `tagsOf`、`FollowOrder._tagRank`）。
  - 标签的 3.x 导入（`user_custom_tags_v5`、`room_to_tags_mapping_v1`）和备份 → J06、J03。

## 现状：做到哪、怎么工作的

- 用户看得到的：
  - 标签管理（设置 → 标签管理，或设标签对话框右上角）：一列标签（最宽 720），每行拖动把手、名字、说明（没有时“暂无描述”）、“N 个直播间”、置顶 / 编辑 / 删除；第一个的置顶是实心图钉、不能点。把手拖动或长按整行拖动排序，拖完先按新顺序显示、保存完才换回存储的数据，不会跳回去。点一行看详情（名字、说明、房间数、“编辑标签”）。删除先确认，说明有几个关注的直播间会去掉这个标签。添加、保存、删除成功都有提示，失败“标签更改未保存，请重试”。
  - 编辑框：名字最多 15 字、说明最多 40 字，显示字数；空名、同名（不分大小写）在框下报错；编辑期间这个标签被别处改了或删了，不覆盖，提示“编辑期间此标签已发生变化”。
  - 设标签（卡片对话框的“设置标签”）：没关注的先问“关注并设置标签”，关注后打开多选框；框里可就地新建（同样的校验），建好自动选中；保存写 `setTagsOf`。
  - 弹幕屏蔽（设置 → 视频 → 弹幕屏蔽，或直播间屏蔽管理的同一个组件）：从带 `BlockKind.user` 参数的入口打开时滚到“已屏蔽用户”。
- 内部怎么工作：

```text
TagsPage（tags_page.dart:39）
  tagListProvider（:18，tags.watchAll）、tagFollowsProvider（:27，follows.watchAll）+ assignments
  _roomsOf（:66）→ followedTagCounts（tag_tile.dart:10，只数仍在关注里的房间）
  _run（:74）：同一时间一个改动，失败提示 tag_changes_save_failed
  _edit / _open / _delete（:98、:104、:111）→ showTagEditor（tag_editor_dialog.dart:18）
      _submit（:60）：validateName → add / update（按 id）；原标签已变 → _markStale（:118）
  _reorder（:139）：_pendingOrder 先显示 → tags.reorder(ids) → _onTags（:162）收到同样顺序才放下
卡片对话框“设置标签” → editRoomTags（room_menu.dart:261）
  未关注 → 确认 → followRoom → tags.all() + tagsOf(room) → RoomTagPicker（room_tags_dialog.dart:32）
      _addTag（:99）：validateName → add → 选中；_save（:141）→ setTagsOf(room, ids)
TagStore（live_store tags.dart:57）：名字不分大小写唯一；删标签时从所有房间去掉；pinToTop = reorder([id])
```

- 完成度（和 3.x 对照）：
  - 一致的：名字 15 字、说明 40 字、空名和同名报错、编辑期间被改则拒绝保存、删除先确认、第一个不能置顶、操作进行中不能再点、失败提示、设标签前未关注先问（3.x `tags_need_follow_tip`）。
  - 确认过的改动：按 id 操作（I07.1 问题 4：3.x 按下标，列表被替换时删不掉也不提示）；`ReorderableListView` 加拖动把手、读屏能排序（问题 5）；网格改一列列表、房间数、详情转编辑、成功提示、显示字数（I07.1 界面改进，A09.10 定稿）。弹幕屏蔽：I07.1 做的两页（关键词、用户）后来由 A08.3 换成直播间同一个 `DanmakuBlockManager`（四组），“清空”和“手动加屏蔽用户”随设计去掉。
  - 还缺：无。

## 代码地图

| 文件 | 职责 |
|---|---|
| `apps/pure_live/lib/features/tags/tags_page.dart`（298 行） | `tagListProvider`（`:18`）、`tagFollowsProvider`（`:27`）、`TagsPage`（`:39`：`_roomsOf` `:66`、`_run` `:74`、对话框只开一个 `_dialog` `:87-95`、`_edit` `:98`、`_open` `:104`、`_delete` `:111`、`_reorder` `:139`、`_onTags` `:162`）；列表和提示是界面（A09.10） |
| `features/tags/tag_tile.dart`（235） | `followedTagCounts`（`:10`）；`TagTile`（`:25`，界面）；`TagDetailsAction`、`showTagDetails`（`:181`、`:189`） |
| `features/tags/tag_editor_dialog.dart`（249） | `tagNameMaxLength` 15（`:10`）、`tagDescriptionMaxLength` 40（`:13`）、`showTagEditor`（`:18`，设标签对话框也可用）、`TagEditorDialog`（`:27`：`_submit` `:60`、`_refuse` `:110`、`_markStale` `:118`） |
| `apps/pure_live/lib/shared/rooms/room_menu.dart`（290） | `editRoomTags`（`:261`，未关注先问） |
| `shared/rooms/room_tags_dialog.dart`（488） | `roomTagNameMaxLength` 15、`roomTagNoteMaxLength` 40（`:13`、`:16`）、`RoomTagPicker`（`:32`：`_addTag` `:99`、`_save` `:141`）；其余是界面（A09.1） |
| `features/shield/shield_page.dart`（47） | `ShieldPage`（`:21`）：`DanmakuBlockManager(showUsers: route.arguments == BlockKind.user)`（`:38-42`），最宽 720；界面归 A08.3 |
| `packages/live_store/lib/src/tags.dart` | `TagStore`（`:57`：`validateName` `:81`、`add` `:90`、`update` `:103`、`delete` `:110`、`reorder` `:117`、`pinToTop` `:129`、`tagsOf` `:132`、`setTagsOf` `:152`）（J02） |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `apps/pure_live/test/features/tags/tags_page_test.dart`（7） | 空状态添加、空名和同名报错；房间数只数关注里的、详情转编辑、第一个不能置顶、置顶、删除先确认并说明房间数、删除后从所有房间去掉；拖动把手排序；竖屏一行一个、按钮顺序（A09.10 c2、c3）；详情和编辑框（c6、c7）；横屏和宽屏最宽 720；编辑期间被别处改名拒绝保存 |
| `test/shared/shared_test.dart` 的卡片对话框用例 | 未关注先关注、在设标签框里新建标签并选中 |
| `test/features/shield/shield_page_test.dart`（7） | 弹幕屏蔽页（归 A08.3）：带 `BlockKind.user` 滚到用户 |

## 3.x 基线

- `~/ref/v3ref/lib/modules/tags/`（`git show v3.2.11:lib/modules/tags/...`）：`tag_management_page.dart`（736 行：按下标删 `:455`，长按卡片拖动 `:166`，`flutter_reorderable_grid_view`）、`tag_management_controller.dart`（443：`indexWhere` 得 -1 时什么也不做 `:225`，`togglePinStatus` 没有调用者 `:211`）、`live_tag.dart`；存储部分 J02.1 做成 `TagStore`。
- 设标签：`lib/common/widgets/room_card.dart` 的 `_showTagSelectionGridModal`（多选、未关注先提示 `tags_need_follow_tip`、框里新建、失败 `tag_assignment_save_failed`）。
- 弹幕屏蔽：`lib/modules/shield/danmu_shield_page.dart`（132 行，只有关键词，点小块就删 `:86`）、`danmu_shield_controller.dart`（29 行，重复时不提示还清空输入 `:13-14`）。
- 必须保留的操作习惯（[specs/UI.md](../../specs/UI.md) 附录 A）：第 14 条（卡片长按或右键 = 操作菜单，“设置标签”在里面）。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 标签名和说明的长度上限写了两份（标签管理的编辑框和设标签框里的新建） | `features/tags/tag_editor_dialog.dart:10`、`:13`；`shared/rooms/room_tags_dialog.dart:13`、`:16` | 改一处忘了另一处会不一致 | [I03.2](../I03-分区/I03.2-浏览列表的小问题合集/README.md) 第 2 阶段（2026-10-07 登记：上限放进一处）；2026-10-08 已改，待 K90 |
| I07.1 记录和代码不符：`shield/block_list_tab.dart` 已被 A08.3（`5ba728803`）换成 `shared/danmaku/block_manager.dart` 的 `DanmakuBlockManager`，`shield_page.dart` 只剩 47 行；“清空”“手动加屏蔽用户”随 A08.3 设计去掉；I07.1 加的 `shield_tab_*`、`shield_clear*`、`shield_duplicate` 等翻译键现在已不在翻译文件里（只剩 `shield_title`、`shield_removed`） | [I07.1 记录](I07.1-分组与屏蔽/record.md) | 只是记录过时；另外 A08 子分类说明写这些键“还留着”，和实际不符 | I07.1 README 已注明；A08 的说法写进本单元报告 |
| I07.1 登记“完成”，记录没有 K90 结果；标签管理的拖动排序、设标签在 S02.3 冒烟里没有单独记录 | — | 没有真机证据 | 建议并入 S02.6 第 3 阶段（写进本单元报告） |

## 相关决定和规范

- D-018（3.x 的标签数据由 J02.1 原样导入，键不变）、D-024（翻译键这次不清理；本子分类相关的 `shield_*` 键已在 A08.3 时删掉，见上表）、D-003（A09.10 的待选按建议 A）。
- [specs/UI.md](../../specs/UI.md) 第 3 节第 7 条（卡片和设置里的屏蔽用同一个组件）。

## 测试和验证

- 自动：`cd apps/pure_live && flutter test test/features/tags test/shared/shared_test.dart`；`TagStore` 在 `packages/live_store` 的测试里。缺的：设标签框的保存失败（`tag_assignment_save_failed`）没有用例。
- 真机：[S02 真机清单](../../S-质量和验证/S02-真机验证/CHECKLIST.md)第 4 节没有标签专门的一条。

## 路线

本子分类没有未完成的任务（标签长度上限写两份的那条并进了 [I03.2](../I03-分区/I03.2-浏览列表的小问题合集/README.md)）。界面由 A09.10、A09.1、A08.3 管；屏蔽的规则由 D02 管。新想法（例如标签颜色、按标签批量操作）写进 [V01](../../V-需求和反馈/V01-新功能提议/README.md)。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [I 浏览和发现](../README.md)。

- 代码：`features/tags/`、`shield/`
- 进度：`████████████████████` 100%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| I07.1 | 分组与屏蔽 | 功能 | 完成 | 2026-10-01 | caebee14d | [设计或说明](I07.1-分组与屏蔽/README.md)、[记录](I07.1-分组与屏蔽/record.md) |

<!-- docs:生成结束 -->
