# T07h.1 页面：分组（标签）与弹幕屏蔽

- 日期：2026-10-01
- 目录：`apps/pure_live/lib/features/tags/`（路由 `RoutePath.kSettingsTags`）、`apps/pure_live/lib/features/shield/`（路由 `RoutePath.kSettingsDanmuShield`），类名和构造参数不变
- v3 来源：标签 `v3.2.11` 的 `lib/modules/tags/`（`tag_management_page.dart` 736 行、`tag_management_controller.dart` 443 行，存储部分已在 T09b.1 变成 `TagStore`）、`lib/modules/shield/`（`danmu_shield_page.dart` 132 行、`danmu_shield_controller.dart` 29 行）、`favorite_room_controller.dart` 的 `addShieldList`/`removeShieldList`/`addBlockedDanmakuUser`（T09b.1 变成 `BlockListStore`）、直播间 `keyword_block_page.dart` 里屏蔽用户列表的写法
- 用到的包：`live_store`（`store.tags`、`store.follows`、`store.blockLists`）、`live_core`（`LiveRoom.identityKey`）、`live_ui`（文字样式、`EmptyView`、`AppStatusView`、`PureLiveScrollPhysics`）

## 做法

| 文件 | 内容 |
|---|---|
| `tags/tags_page.dart` | 页面（`ConsumerStatefulWidget`）。标签来自 `store.tags.watchAll()`，房间数来自 `watchAssignments()` 和 `follows.watchAll()`（页面内的 3 个 `StreamProvider`）。写入都按 id 走 `TagStore`：`add`、`update`、`delete`、`pinToTop`、`reorder`。同一时间只做一个改动（3.x `_actionPending`），对话框同一时间只开一个（3.x `_dialogActive`）；拖动排序后先按新顺序显示，等存储回报后再换回存储的数据，列表不会跳回去 |
| `tags/tag_tile.dart` | 一行标签（拖动把手、名字、说明、房间数、置顶/编辑/删除）、详情对话框、`followedTagCounts`（只数仍在关注里的房间） |
| `tags/tag_editor_dialog.dart` | 添加/编辑对话框：名字 15 字、说明 40 字（同 v3）；保存时用 `validateName` 检查空名和同名（不分大小写）；编辑期间标签被别处改了或删了就不覆盖，提示 `tag_editor_stale_error`（同 v3） |
| `shield/shield_page.dart` | 页面：两个标签页“关键词（n）”“用户（n）”；路由参数为 `BlockKind.user` 时打开用户页 |
| `shield/block_list_tab.dart` | 一个屏蔽列表：输入框添加，条目按新到旧显示成小块，点一下移除（可撤销），“清空”确认后清空（可撤销）。数据来自 `store.blockLists.watch(kind)`，直播间的过滤（T05a.1 `room_controller.dart`）监听同一个流，改动立即生效 |

存储语义沿用 T09b.1：标签名不分大小写唯一，删标签时从所有房间去掉；屏蔽词和屏蔽用户去首尾空白、不分大小写去重、保留第一次的写法，设置页限 40 字（`BlockListStore.maxKeywordLength`）。过滤规则在 T06a.1（`DanmakuBlockList`）：弹幕文本转小写后包含任一屏蔽词即隐藏，发送者名字转小写后完全相同即隐藏。3.x 的 `user_custom_tags_v5`、`room_to_tags_mapping_v1`、`shieldList`、`blockedDanmakuUsers` 由 T09b.1 迁移，本页不另做迁移。

## 与 v3 的功能对照

### 标签管理

| v3 | v4 | 说明 |
|---|---|---|
| 标题“标签管理”，右上角“+”添加 | 有 | |
| 顶部提示：长按拖动排序 | 有 | 文字改为说明把手和长按两种拖法、顺序的用途 |
| 空状态：图标和“暂无自定义标签…” | 有 | 加用途说明和“添加标签”按钮 |
| 卡片：名字、说明（没有时斜体“暂无描述”）、置顶、编辑、删除，按钮有带名字的提示文字 | 有 | 网格改成列表，加房间数，见“界面改进”1、2 |
| 第一个标签的置顶按钮显示实心图钉、不可点 | 有 | |
| 拖动排序（长按） | 有 | 改用 Flutter 自带的 `ReorderableListView`：把手直接拖，整张卡片长按也能拖 |
| 点名字看详情（名字、说明） | 有 | 点整张卡片；详情加房间数和“编辑标签”按钮 |
| 添加/编辑对话框：名字 15 字、说明 40 字、清除按钮、空名和同名错误、保存中转圈且不能关闭、保存失败提示、编辑期间标签被改则拒绝保存 | 有 | 显示字数 |
| 删除先确认 | 有 | 确认框说明有几个关注的直播间会去掉这个标签 |
| 操作进行中不能再点，失败提示“标签更改未保存，请重试” | 有 | 进行中页面顶部有细进度条 |
| 给直播间设标签（卡片菜单里的标签选择框） | 不在本页 | 3.x 在 `room_card.dart`，见“留给后续” |

### 弹幕屏蔽

| v3 | v4 | 说明 |
|---|---|---|
| 标题“弹幕关键词屏蔽” | 改为“弹幕屏蔽” | 本页现在也管屏蔽用户 |
| 输入框（40 字）+“添加”按钮，回车也添加；空的提示“请输入关键字” | 有 | 空的和重复的在输入框下显示错误，见问题 1 |
| “已添加 n 个关键词（点击可移除）” | 有 | 旁边加“清空” |
| 关键词小块，点一下移除 | 有 | 加撤销；新加的排在前面 |
| 空状态“暂无屏蔽关键词” | 有 | |
| 屏蔽用户（v3 只在直播间的屏蔽面板里能看、能删） | 有 | 新的“用户”页：查看、手动添加、移除、清空 |

v3 其他读写这些数据的地方不在本页：直播间的屏蔽面板和长按弹幕屏蔽发送者（T05a.1 已接 `store.blockLists`）、多画面的弹幕过滤（M13 多画面）、关注页按标签筛选（M13 关注）、备份恢复（T09b.1 `BackupService`）。

## v3 问题及处理

| # | 问题 | 位置 | 处理 |
|---|---|---|---|
| 1 | 添加重复的屏蔽词时什么也不提示，输入框却被清空，用户以为加上了 | `danmu_shield_controller.dart:13-14`（不看 `addShieldList` 的返回值） | 输入框下显示“…已在列表中”，输入保留 |
| 2 | 点一下关键词就删掉，误触无法恢复 | `danmu_shield_page.dart:86` | 移除后提示带“撤销”，按原位置放回（期间新加的排在后面） |
| 3 | 设置里的屏蔽页只有关键词；屏蔽的用户只能进直播间才能看到和删除 | `danmu_shield_page.dart`、`keyword_block_page.dart:144` | 本页加“用户”标签页 |
| 4 | 标签按列表下标操作：对话框开着时列表被替换（恢复备份等），删除找不到原对象，`indexWhere` 得 -1，什么也不做也不提示 | `tag_management_page.dart:455`、`tag_management_controller.dart:225` | 按 id 操作（T09b.1 `TagStore`）；编辑时标签已不存在则提示“编辑期间此标签已发生变化” |
| 5 | 拖动排序只能长按卡片，读屏和键盘用户没法排序 | `tag_management_page.dart:166`（`flutter_reorderable_grid_view`） | `ReorderableListView` 自带“上移/下移”等读屏操作；另有拖动把手 |
| 6 | `togglePinStatus` 没有调用者 | `tag_management_controller.dart:211` | 不搬 |

## 界面改进

（2026-10-01 用户授权：界面、布局、操作和视觉反馈可以改进；数据仍在 `live_store`，3.x 数据由 T09b.1 原样导入。）

1. **标签列表**：两列网格改成一列卡片列表（桌面上居中、最宽 720）。标签名常常很短、说明在网格里只能显示两行，列表更好读，拖动排序也更稳。
2. **房间数**：每个标签显示“n 个直播间”（只数仍在关注里的，和关注页按标签筛选看到的一致）；详情和删除确认框里也有。
3. **拖动把手**：左侧把手按住就能拖（鼠标也行），手机上长按整张卡片也能拖；拖完先按新顺序显示，保存完成前列表不会跳回去。
4. **空状态**：说明标签的用途（给关注的直播间分组、关注页按标签筛选），并有“添加标签”按钮。
5. **详情对话框**：加房间数和“编辑标签”按钮，看完可以直接改。
6. **操作结果提示**：添加、保存、删除成功后提示（v3 只在失败时提示）；保存进行中页面顶部有细进度条。
7. **编辑框**：显示字数（v3 隐藏了计数）。
8. **屏蔽页分成“关键词”“用户”两页**，标签上带条数；每页写明匹配规则（包含即屏蔽 / 名字完全相同即屏蔽，不分大小写）。
9. **屏蔽项新加的排在前面**，添加后马上能看到；小块带“×”，点小块或“×”都能移除。
10. **撤销**：移除一项、清空列表后提示里有“撤销”。
11. **清空**：列表标题旁加“清空”，先确认（说明条数）。
12. **出错提示就地显示**：空输入、重复项在输入框下提示，不再弹 toast 或悄悄忽略。
13. 首次读取时显示加载动画，读取失败显示错误页和重试。

## 已批准的升级（docs/specs/UPGRADES.md）

UPGRADES 里没有属于本页的条目（标签、屏蔽相关的条目都在平台层或直播间）。统一原则“界面和操作”见上一节。

## 新增的翻译键

zh、en 各 25 个，按字母序插在各自前缀下：

- `shield_`：`shield_clear`、`shield_clear_keywords_confirm`、`shield_clear_users_confirm`、`shield_cleared`、`shield_duplicate`、`shield_keyword_rule`、`shield_removed`、`shield_save_failed`、`shield_tab_keywords`、`shield_tab_users`、`shield_title`、`shield_undo`、`shield_user_hint`、`shield_user_rule`、`shield_users_empty_subtitle`、`shield_users_empty_title`
- `tags_`：`tags_added`、`tags_delete_rooms_hint`、`tags_deleted`、`tags_drag_handle`、`tags_empty_hint`、`tags_room_count`、`tags_rooms_label`、`tags_saved`、`tags_sort_tip`

其余沿用 v3 的键（`tag_management`、`add_tag`、`tag_*`、`*_tag_named`、`no_tags_tip`、`shield_count_title`、`empty_shield_*`、`blocked_danmaku_users`、`please_input_keyword`、`click_to_remove` 等）。v3 的 `danmaku_keyword_block` 本页不再用（直播间的屏蔽面板还在用）。

## 留给后续

| 内容 | 去向 |
|---|---|
| 给直播间设标签的选择框（v3 `room_card.dart` 的 `_showTagSelectionGridModal`：多选、未关注先提示 `tags_need_follow_tip`、框里新建标签、保存失败提示 `tag_assignment_save_failed`）；接口用 `store.tags.setTagsOf`/`tagsOf`，新建标签可复用本目录的 `showTagEditor` | 共享卡片菜单（协调者）或关注页 |
| 关注页按标签筛选（v3 `favorite_controller.dart` 的标签栏，顺序就是本页的顺序） | M13 关注 |
| 设置页里进入这两页的入口（v3：平台设置 → 标签管理，视频设置 → 弹幕屏蔽） | M13 设置 |
| 多画面的弹幕过滤读 `store.blockLists`（v3 `multiview_danmaku_session.dart:199` 只看用户名单） | M13 多画面 |

没有缺少的共享服务或包接口：`TagStore`、`BlockListStore` 的现有方法够用（撤销用 `replaceAll`）。

## 测试

7 个（加速流程，只测主要路径；内存库 `LiveStore.memory()`，经 `testServices()`）：

| 测试文件 | 用例 |
|---|---|
| `test/pages/tags/tags_page_test.dart`（4） | 空状态添加、空名和同名（不分大小写）报错、添加提示和列表内容；房间数只数关注里的、详情转编辑并保存、第一个不能置顶、置顶、删除先确认并说明房间数、取消不删、删除后从所有房间去掉；拖动把手排序并保存；编辑期间被别处改名时拒绝保存 |
| `test/pages/shield/shield_page_test.dart`（3） | 空状态、空输入和重复项就地报错且输入保留、回车添加、标签页条数；点小块移除并撤销回原位；从参数打开用户页、添加用户、清空先确认、清空不影响关键词、撤销清空 |
