# A17.3 电视直播浏览：任务书

## 背景

- 来源：界面重做的电视部分（旧编号 U.15c、T18b.1）。设计第 1 版 2026-10-01 评审，用户同意全部电视设计（“后续全部通过”，确认记录 `422b69576`），待选 C1～C4 按建议 A（D-003）。设计正文在本文件夹 [README.md](README.md)（c1～c12、L1～L13 问题），评审页导出在 `page/`。
- 设计确认后又定了一条跨任务的规则（2026-10-01 旧界面任务表的“跨任务待同步”）：**分区卡片长按不用小菜单（README 的 c7），用 A17.1 c9 统一的卡片弹窗**，和手机 A09.4 的决定一样（手机现在是 `showAreaDialog`，`apps/pure_live/lib/features/areas/areas_common.dart:50`）。开发时以这条为准，在 record.md 写明偏差来源。另一条：不分分类、平铺显示的平台用同一份配置（pure_live_TV 是 20 个，手机只有抖音），开发时核对数据层。
- 现象（现在的电视浏览页，`apps/pure_live/lib/tv/pages/`，X03.1 做、A17.1 换了组件）：热门叫“推荐”；关注页状态叫“直播中 / 回放 / 未开播”、状态和平台分两行，未开播也是大封面卡片；分区和关注分区合在一页；分区卡片长按直接关注 / 取消关注，看不出将要做什么；历史是一个网格，不按日期分组，没有“保留数量”和“刷新”；搜索没有“直播间 / 主播”、包含未开播、排序；平台“全部”只有搜索有。
- 为什么现在做：第三档（D-004 电视排在 Android、Windows 之后）。电视阶段里排第二，在 A17.2（导航轨）之后：直播浏览是电视最常用的部分。
- 已经做过的：X03.1（各页和焦点规则）；A17.1（卡片、角标、卡片弹窗、标签、状态页、子页顶栏、危险确认框）；手机 A09.2～A09.9 全部完成（同一功能的内容、文字、空状态以手机为准）。
- 半成品：没有（旧分支 M14.2～M14.5 不含浏览页）。

## 目标和验收

1. （c2，C1 A）关注页顶部一行：状态“已开播 / 录播 / 未开播”和平台标签放一行、中间竖线分开，都带数量；分组标签（有标签时）一行，用小一号的胶囊。
2. （c3，C3 A）关注里的未开播用紧凑行、两列：头像、主播名、平台图标和上次的标题。
3. （c4）空状态文字照手机、操作说明换成遥控器的说法：关注“无关注直播 / … / 搜索直播”；关注分区“未发现分区 / 在分区页长按 OK（或按菜单键）关注分区，或打开分区后按顶上的“关注” / 去分区”；热门平台全关“没有要显示的平台 / … / 平台显示”；观看记录“暂无观看记录 / 看过的直播间会自动出现在这里 / 浏览热门”；按钮图标跟着意思。
4. （c5）热门平台标签右边固定一个“全部平台”，打开右侧面板（手机 A09.2 同一个平台面板的电视样式）：3 列平台，OK 直接切过去，右上“平台显示”。
5. （c6）分区的分类标签用次级样子：文字加下划线、下面一条分隔线；平台只有一个分类或不分分类时没有分类行。
6. （c7，按跨任务规则）分区卡片长按 OK 或菜单键打开统一的卡片弹窗（电视样式）：“分区 · 平台 · 分类”，关注分区 / 取消关注（取消先确认，焦点在“取消”）；已关注的分区右上角心形。
7. （c8）分区房间页：标题分区名，下面“平台 · 大类”，右边“＋ 关注 / ✓ 已关注”胶囊；默认焦点在第一张卡片。
8. （c9）关注分区单独一个入口（导航轨由 A17.2 放）：平台标签只列“全部”和有关注分区的平台、带数量；“全部”里卡片第二行是平台图标加分类。
9. （c10，C4 A）观看记录：顶上一行“观看记录 18 / 50 条”，右边“刷新”“保留数量 50”“清空”；平台标签只列有记录的平台、带数量；按今天、昨天、近 7 天、更早分组。
10. （c11，C2 A）搜索一页：搜索框、“直播间 / 主播”（默认直播间）、平台（含“全部”）、包含未开播、排序、说明行，结果在下面，上键回到搜索框和筛选；还没输入时显示最近搜索和“用手机输入”（二维码加一句说明，接收端没有时先不显示二维码，见“风险”）。
11. （c12）最近搜索“清空”先确认（焦点在“取消”）；历史标签只放大一次。
12. （c1）保留：4 列房间网格、6 列分区网格；在当前标签上再按 OK 刷新；卡片 OK 进直播间、当前列表就是换台列表；滑到底自动加载；回到页面焦点落在上次那张卡片；关注页的分组和排序；观看记录的清空、保留数量（20 / 50 / 100 / 200 / 不限 / 自定义）、重新核对是否在播；最近搜索长按删一条。
13. 手机界面一点不变；`flutter test` 全部通过；`tv` 直接写的颜色和图标保持 0。

## 现状（读代码得出，写文件:行）

- 关注：`apps/pure_live/lib/tv/pages/tv_favorites_pane.dart`（125 行），`favoriteControllerProvider`；状态标签 `_groups`（`:39-43`，键 `tv_follow_live`、`tv_follow_replay`、`tv_follow_offline`），状态一行（`:95`）、平台一行（`:110-112`，“全部平台”加有关注的平台）；未开播也用 `TvRoomGrid` 的大卡片；没有分组（标签）行。
- 热门：`tv/pages/tv_popular_pane.dart`：`TvFeedGrid`（`:26`，分页网格，搜索和分区房间也用）、`TvPopularPane`（`:91`），每页 24（`tvPageSize` `:19`），平台全关时只有一个状态页（`:137`）；没有“全部平台”面板。手机的平台面板 `PlatformPicker`（`apps/pure_live/lib/features/popular/popular_page.dart:225`）。
- 分区：`tv/pages/tv_areas_pane.dart`：第一个标签“关注的分区”（`:93`），然后每个平台、分类标签（`:157`，同一种胶囊）；`_AreaGrid`（`:184`）长按直接 `toggleAreaFollow`（`:218`，`features/areas/areas_common.dart:107`）。手机的分区弹窗 `showAreaDialog`（`areas_common.dart:50`）。
- 分区房间：`tv/pages/tv_area_rooms_page.dart`：`TvPageHeader` + 关注按钮（`:116`，也是直接切换）。
- 历史：`tv/pages/tv_history_pane.dart`：`tvHistoryProvider`（`:19`），清空先确认（`:48-50`），一条记录删除先确认（`:103-105`）；引用了 `features/history/history_sections.dart` 但只用了 `roomLabel`，没有分组（手机的分组 `historySections` 在那个文件 `:46`）。保留数量对话框手机有 `showHistoryLimitDialog`（`features/history/history_limit_dialog.dart:20`），重新核对在播 `refreshHistoryRooms`（`history_refresh.dart:47`）。
- 搜索：`tv/pages/tv_search_page.dart`：`SearchModel`（`features/search/search_model.dart:61`）只用了直播间模式；平台标签有“全部”（`:174-176`）；最近搜索（`:235`）、清空先确认（`:132-134`，A17.1 已加）、长按删一条（`:262`）。手机的范围面板 `SearchScopePanel`（`features/search/search_scope.dart:92`）有主播模式、包含未开播、排序。
- 卡片和网格：`tv/widgets/tv_room_grid.dart:25`（长按 `:136` 打开 `showTvRoomDialog`），`tv/widgets/tv_room_card.dart:25`，`tv/widgets/tv_area_card.dart:13`（已有心形）。没有紧凑行组件。
- 导航：入口名字和“关注分区”单独一项是 A17.2 的；这里假设 A17.2 已经给了“关注分区”入口（`TvPane`），没有的话先在分区页保留“关注的分区”标签。
- 测试：`apps/pure_live/test/tv/tv_test.dart` 的首页焦点、搜索用例会受影响。

## 3.x 基线

- 3.x 没有电视界面；基线是 pure_live_TV（`~/ref/pure_live_TV`，设计用 `b9d2f739`，本机现在 `37660afc`）的 `lib/modules/live/`：`hot/hot_page.dart`、`favorite/favorite_page.dart`（`:264-353`、`:380-388`、`:105-139`）、`areas/areas_page.dart`、`area_grid_view.dart`、`area_rooms_page.dart`、`favorite_areas/favorite_areas_page.dart`、`history/history_page.dart`（`:154-242`）、`search/tv_search_page.dart`、`tv_search_result_page.dart`；分页 `core/pagination/base_paged_tv_view.dart:68-79`；空状态 `core/widgets/empty_scene.dart:46-92`。开工前看 `git log b9d2f739..HEAD -- lib/modules/live/{hot,favorite,areas,favorite_areas,history,search}`。
- 内容和文字的基线是手机（已完成）：A09.2 热门（平台面板）、A09.3 关注（状态名、紧凑行）、A09.4 分区（分类次级样子、心形、长按弹窗）、A09.5 分区房间（顶栏关注胶囊）、A09.6 关注的分区、A09.7 搜索（范围、主播结果的卡片）、A09.9 观看历史（分组、保留数量）。
- 要保留的电视习惯：c1 那一行；从直播间回来焦点落在最后看的房间（X03.1）。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5、8、14 节）。
2. `docs/specs/ENGINEERING.md`（第 5 节 AGPL 来源）；`docs/specs/UI.md` 第 5.5 节、第 3 节第 6、7 条。
3. 本文件夹 `README.md` 和 `page/`；`docs/A-界面设计/A17-电视界面/A17.1-电视设计系统和通用组件/README.md`（卡片、角标、卡片弹窗）、`A17.2-电视外壳/README.md`（导航轨入口）。
4. 手机设计和记录：`docs/A-界面设计/A09-浏览界面/` 下 `A09.2-热门`、`A09.3-关注`、`A09.4-分区`、`A09.5-分区房间`、`A09.6-热门分区、关注的分区`、`A09.7-搜索`、`A09.9-观看历史` 的 README 和 record.md。
5. 代码：`apps/pure_live/lib/tv/pages/` 全部、`tv/widgets/tv_room_grid.dart`、`tv_room_card.dart`、`tv_area_card.dart`、`tv_room_dialog.dart`；手机 `features/popular/popular_page.dart`、`features/areas/areas_common.dart`、`features/area_rooms/follow_area_button.dart`、`features/history/`、`features/search/search_scope.dart`、`search_model.dart`。

## 范围

- 可以改：`apps/pure_live/lib/tv/pages/`、`tv/widgets/`（加紧凑行、次级标签、平台面板的电视样式）、`tv/home/tv_home_page.dart`（只为接入“关注分区”页，导航轨本身是 A17.2 的）；手机的组件需要拆出“内容”给电视用时，可以挪到 `apps/pure_live/lib/shared/`（手机样子不变）；翻译文件（只加键）；`test/tv/`；本文件夹。
- 不能改：手机各页的样子和行为；浏览逻辑（`favoriteControllerProvider`、`RoomFeed`、`AreaCatalog`、`SearchModel` 的规则）——要改逻辑另开 I 组任务；设置键名和含义（D-018）；版本号、`assets/version.json`、`assets/releases.json`；签名配置。

## 方案和阶段

| 阶段 | 做什么（对应 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | 关注页（c2、c3）和空状态（c4 关注部分）：一行状态 + 平台带数量、分组行、未开播紧凑行两列 | `tv/pages/tv_favorites_pane.dart`、新 `tv/widgets/tv_room_row.dart` | 新用例：状态和平台同一行、数量；未开播是行不是卡片、两列；空状态文字和按钮 |
| 2 | 热门（c5、c4 热门部分）和分区（c6、c7、c8）：“全部平台”面板、分类次级样子、分区长按统一弹窗、分区房间顶栏 | `tv_popular_pane.dart`、`tv_areas_pane.dart`、`tv_area_rooms_page.dart`、`tv/widgets/` | 新用例：“全部平台”面板 OK 切换；分区长按出弹窗（不是直接关注），取消关注先确认；分区房间顶栏“平台 · 大类”和关注胶囊、默认焦点第一张卡片 |
| 3 | 关注分区单独一页（c9）和观看记录（c10、c4 部分） | 新 `tv/pages/tv_followed_areas_pane.dart`、`tv_history_pane.dart` | 新用例：平台只列有关注的、带数量；“全部”卡片第二行；历史按日期分组、顶上计数、刷新、保留数量选择框和自定义输入 |
| 4 | 搜索（c11、c12）：一页、范围（直播间 / 主播、平台、包含未开播、排序）、结果在下、上键回筛选 | `tv_search_page.dart` | `tv_test.dart` 搜索用例照新布局改并通过；新用例：主播模式结果卡片不用头像当封面；清空先确认 |

每个阶段都要能单独合并。登记表现在是“设计 ✓ → 开发 → 真机”，开工时把“开发”按上表拆开写进 `stages`。

## 测试

- 改之前会失败：`test/tv/` 加“分区卡片长按打开弹窗而不是直接关注”（现在 `tv_areas_pane.dart:218` 直接切换）。
- 每个阶段的用例见上表；另外：
  - 从直播间返回，焦点落在最后看的房间（关注、热门、历史各一次）；
  - 在当前标签上再按 OK 刷新（热门、关注）；
  - 1080p@2x（960×540）和 720p（1280×720@1）各一个整页布局测试：标签行、两列紧凑行、历史分组标题不出屏、字不小于 14。
- 用 `test/fixtures/` 和现有测试里的假平台（`FakeSite` 之类，照 `tv_test.dart` 的写法），不访问真实平台；定时器至少 1 秒。

## 真机验证（维护者在电视或盒子上做）

| 步骤 | 期望 |
|---|---|
| 1. 关注页 | 顶上一行“已开播 12 · 录播 3 · 未开播 40 │ 全部 · 哔哩哔哩 8 …”；未开播是两列小行 |
| 2. 热门，平台标签走到最右的“全部平台”按 OK | 右侧面板 3 列平台，OK 直接切过去 |
| 3. 分区，长按一个分区（或按菜单键） | 弹窗写“分区 · 平台 · 分类”和“关注分区”；关注后卡片右上出现心形 |
| 4. 打开一个分区 | 顶上分区名、“平台 · 大类”、右边关注胶囊；焦点在第一张卡片 |
| 5. 观看记录 | 顶上“观看记录 N / 50 条”和三个按钮；按今天、昨天……分组；“保留数量”选择框焦点在当前值 |
| 6. 搜索输入一个主播名，切“主播”，打开“包含未开播” | 结果在下面，上键回到筛选；主播结果不是放大的头像 |
| 7. 从任一页进直播间换几个台再返回 | 焦点在最后看的那个房间 |

## 风险和注意

- 搜索的“用手机输入”二维码要有局域网接收端（pure_live_TV 的网页遥控；旧分支 M14.5 `37ef8cbf0` 的 `tv/remote/web_remote_server.dart` 有半成品，建在旧目录）。接收端不在本任务：没有时只显示遥控器输入，写进 record.md，留给 A17.5 / A17.9 的扫码到手机。
- 两列紧凑行和 4 列卡片混在一个可滚动区里，`TvGrid` 现在只管一种网格；要么分成两个 `TvGrid` 并处理上下衔接，要么扩展 `TvGrid`，别破坏按下标走和焦点记忆（X03.1 记录“焦点方案”）。
- 手机组件拆给电视用时，手机测试不改断言照样通过。
- 可能冲突的文件：`tv/home/tv_home_page.dart`（A17.2）、`tv/widgets/tv_room_grid.dart`、`tv_room_card.dart`（A17.4、A17.6 也会用）。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 分支 `ai/A17.3` 或本机工作区；提交信息以 `[A17.3]` 开头（英文）；不推 master。
- 提交前：`apps/pure_live` 跑 `dart format --output=none --set-exit-if-changed .`、`flutter analyze`、全部 `flutter test`；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”、更新登记表的 `done`、`next`、`branch`。

## 报告（中文，简洁）

每条验收做到没有；分区长按按跨任务规则做的说明；测试数量（改之前失败几个）；改了哪些文件；从手机挪到 `shared/` 的组件；新翻译键；要在电视上看的；可能冲突的文件。
