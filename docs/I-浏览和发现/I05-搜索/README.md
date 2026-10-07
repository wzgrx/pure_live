# I05 搜索

搜索直播间和主播背后的逻辑：在哪些平台搜（“全部”和单个平台、全部里去掉的平台）、怎么并发、超时、翻页、去重、排序和筛选，各平台能搜到什么（能力表和说明），搜索历史，粘贴直播链接直接进房，以及网页搜索（应用内网页认出直播间后问是否进入）。

## 范围

- 包括：
  - `apps/pure_live/lib/features/search/search_model.dart`：`SearchModel`（平台选择、房间 / 主播两种模式、全平台并发、每个平台各自翻页、取消旧请求、筛选和排序）、`AnchorResult`。
  - `search_capability.dart`：各平台的搜索能力表 `SearchCapabilities`（能不能搜到未开播、能不能翻页、有没有主播搜索、网页搜索）、`webSearchUrl`、说明文字。
  - `search_ranking.dart`：四种排序和“包含未开播”。
  - `search_history.dart`：搜索历史（meta `search.history`，20 条）。
  - `search_scope.dart` 的数据部分：`SearchScopeStore`（“全部”里去掉的平台，meta `search.allExcluded`）、`overseasPlatforms`（海外 15 个平台）。
  - `search_view.dart`、`web_search_view.dart` 里和逻辑有关的部分：链接识别（`LinkParser`）、网页搜索的参数校验（`WebSearchRequest.parse`）、网页里认出直播间（`_pageShown`）。
  - `search_page.dart`：路由 `/search`、`/web_search` 分给两个视图，参数是字符串时作为初始关键词。
- 不包括（归哪里）：
  - 搜索页、网页搜索页**长什么样**（搜索框、平台条、筛选栏、搜索范围面板、骨架、空状态、直播间提示条）→ [A09.7 搜索](../../A-界面设计/A09-浏览界面/A09.7-搜索/README.md)、[A09.8 网页搜索](../../A-界面设计/A09-浏览界面/A09.8-网页搜索/README.md)；`search_widgets.dart` 和 `search_scope.dart` 的面板是界面，归 A09。
  - 各平台的 `searchRooms`、`searchAnchors`、`LiveSearchPaginationPolicy`、`LiveCancellableSearch` → [E 直播平台](../../E-直播平台/README.md)；链接解析 `LinkParser` → [E04](../../E-直播平台/E04-链接解析和分享口令/README.md)。
  - 应用内网页 `shared/in_app_web.dart`（flutter_inappwebview、Windows 的 WebView2 检查）→ O03.1；卡片和卡片对话框 → A09.1；Picarto 卡片显示简介 → [A09.11](../../A-界面设计/A09-浏览界面/A09.11-Picarto搜索卡片简介/README.md)。
  - 分享、剪贴板口令自动识别 → O03（搜索页只在点“粘贴”时读剪贴板）。

## 现状：做到哪、怎么工作的

- 用户看得到的：
  - 平台条：“全部”+ 平台显示里的平台（页面打开时取一次快照，3.x 同）。“全部”可以在搜索范围面板里去掉一些平台（例如没有代理时去掉海外平台），记住在 meta 里；至少留一个。海外平台失败时横幅建议开代理（M13.16）。
  - 两种模式：直播间（所有能搜的平台）、主播（哔哩哔哩、斗鱼、虎牙、快手、网易 CC、YY、AcFun 7 个有主播搜索的平台；结果是头像、名字、平台、直播状态，点了进房）。选了不支持的平台时说明。
  - 搜索：同时最多 12 个平台，每个平台每页 12 秒超时，先回来的先显示，“还有 N 个平台在搜索…”；跨平台按房间身份去重；滑到底（距底 480）自动加载下一页，平台不能翻页、本页失败、本页为空就停，连续 2 页没有新结果也停，按关键词决定能不能翻页（YouTube 等）。换平台、换模式、换范围时取消旧请求并重搜输入框里的词。
  - 筛选和排序：“包含未开播”（关掉时能播的回放保留）；综合（直播 > 回放 > 其余）、平台优先、观众（按“优先实时在线”设置）、粉丝。设置变了重排。
  - 部分平台失败：横幅写平台名，可重试、去网页搜索、关掉；全部失败是错误样式加“重试”。
  - 粘贴链接：识别到支持的直播链接（含短链、中文标点结尾）时提示“识别到直播链接 / 进入”，回车或“进入”直接打开直播间，不发搜索；认不出按文字搜。
  - 搜索历史：没搜索时显示最近 20 条，新的在前、不分大小写去重、单条删除和清空；链接进房不记；太长的词截到 200 字。
  - 网页搜索：有网页搜索的平台带关键词打开应用内网页（没有 WebView 的平台和系统直接用系统浏览器；Windows 没有 WebView2 时先问），网页里每打开一页用 `LinkParser` 认一次，认出直播间时底部提示条“进入 / 关闭”（关了的同一房间不再提示），进房后返回回到网页；网页加载失败给“重试”和“用浏览器打开”。地址只留搜索参数（去掉跟踪参数）。
- 内部怎么工作：

```text
SearchView（search_view.dart:41）
  建 SearchModel(sites: availableIds(hotAreasList) 的快照) ；SearchHistory(meta)；SearchScopeStore(meta).load → setExcluded
  提交：先 LinkParser.parse（链接 → toLiveRoomDetail）→ 认不出 → model.search(word) + history.add
SearchModel（search_model.dart:61）
  search（:269）→ _start（:286，新代号 + CancelToken）→ _searchPage（:335）
     _searchBounded（:398）：最多 12 个并发，每个 _searchSite（:448）12 秒超时
     每批回来：_rawRooms[_roomKey] = room（去重）→ _canLoadAnother（:426）→ _apply（:488，排序筛选）→ 通知
  loadMore（:298）：只请求还能翻页的平台
  TwitCasting 关键词超过 100 字先截（_queryFor :480）
WebSearchView（web_search_view.dart:65）
  WebSearchRequest.parse（:32，3.x 的 {url, platform} 参数，只认 http(s)、不带用户信息）
  InAppWeb 每显示一页 → _pageShown（:111）→ LinkParser → WebSearchRoomBar → _enter（进房，返回回到网页）
```

- 完成度（和 3.x 对照）：
  - 一致的：“全部”和单个平台、12 个并发和 12 秒、先回来先显示、各自翻页和停止条件、480 像素、`LiveSearchPaginationPolicy`、跨平台去重、“包含未开播”、四种排序、观众口径跟设置、部分失败横幅、空关键词提示、回车和按钮同一帧只搜一次、网页搜索认出直播间后问是否进入（3.x 也是应用内 WebView）。
  - 确认过的改动：能力表按平台层核对（YY、TwitCasting 只搜直播中，升级 A-5；YouTube 可翻页，23-2；I05.1 问题 1、2）；说明文字重写（问题 3）；回放不算未开播（问题 4）；TwitCasting 超长关键词（问题 5）；粘贴链接进房（问题 6）；网页搜索地址去跟踪参数（问题 8）；主播搜索、搜索历史、粘贴按钮、骨架、平台标志（I05.1 界面改进）；“全部”的搜索范围和海外平台建议（M13.16，A09.7 X3）；网页搜索的提示条（A09.8）。
  - 和 I05.1 当时不同的：I05.1 时没有 WebView 插件，网页搜索走系统浏览器；O03.1 加了 `flutter_inappwebview` 后接回应用内网页（3.x 的做法），A09.8 定了提示条的样子。
  - 还缺：卡片上显示 Picarto 简介（升级 11-5，A09.11 未开始）。

## 代码地图

| 文件 | 职责 |
|---|---|
| `apps/pure_live/lib/features/search/search_model.dart`（531 行） | `SearchMode`（`:11`）、`AnchorResult`（`:21`，`toRoom`）、`searchRequestTimeout` 12 秒（`:48`）、`maxStagnantSearchPages` 2（`:52`）、`maxConcurrentSearchSites` 12（`:55`）；`SearchModel`（`:61`：`supports` `:167`、`setExcluded` `:198`、`select` `:213`、`setMode` `:222`、`setIncludeOffline` `:244`、`setSort` `:252`、`reorder` `:260`、`search` `:269`、`loadMore` `:298`、`_searchPage` `:335`、`_searchBounded` `:398`、`_canLoadAnother` `:426`、`_searchSite` `:448`、`_queryFor` `:480`、`_roomKey` `:483`、`_apply` `:488`） |
| `features/search/search_capability.dart`（205） | `SearchCoverage`（`:5`，能搜到未开播 / 只搜直播中 / 在推荐里筛选 / 只能精确查找 / 本机频道）、`SearchCapability`（`:33`）、`SearchCapabilities.of`（`:148`）、`webSearchUrl`（`:153`）、`searchCoverageText`（`:176`）、`searchCoverageShortText`（`:193`） |
| `features/search/search_ranking.dart`（78） | `SearchSortMode`（`:4`）、`SearchRanking.apply`（`:24`）、`compare`（`:39`）、`_stateRank`（`:68`，直播 2、回放 1、其余 0）、`followerCount`（`:72`） |
| `features/search/search_history.dart`（86） | `SearchHistory`（`:11`：`key` `search.history`、`limit` 20、`maxLength` 200、`load`、`add`、`remove`、`clear`） |
| `features/search/search_scope.dart`（263） | `overseasPlatforms`（`:14`，15 个）、`SearchScopeStore`（`:34`，`search.allExcluded`）；`showSearchScopePanel`、`SearchScopePanel`（`:71`、`:92`，界面） |
| `features/search/search_view.dart`（767） | `SearchView`（`:41`）：模型、历史、范围、`LinkParser`（`:118-125`）、范围面板的结果（`:233-238`）；其余是界面（A09.7） |
| `features/search/web_search_view.dart`（452） | `WebSearchRequest`（`:15`，`parse` `:32`）、`WebSearchView`（`:65`：没有 WebView 时直接开系统浏览器 `:97-109`、`_pageShown` `:111`、`_enter` `:124`、`_dismiss` `:131`、`_openExternal` `:136`）；`WebSearchRoomBar`、`WebSearchFailure`（界面，A09.8） |
| `features/search/search_page.dart`（29）、`search_widgets.dart`（641） | 路由分发；平台条、筛选栏、历史、骨架、主播行（界面） |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `apps/pure_live/test/features/search/search_test.dart`（27 个用例，含按尺寸展开的） | 能力表（A-5）、排序和筛选、卡片；全平台合并排序、失败记名、翻页停止；超时算失败、换平台搜草稿；去掉的平台（M13.16）；主播模式；历史；每个平台一行范围说明；页面：卡片、失败横幅、历史、点卡进房（带结果列表）；海外失败建议代理、范围面板记住；右键开卡片对话框（附录 A 第 14 条）；粘贴链接直接进房；主播模式页面；搜索框、平台条、筛选栏的布局和各宽度；向下滚动收起平台条；排序菜单；范围面板；骨架和四种空状态；网页搜索路由；没有 WebView2 时先问；滚轮横向滚平台条；Esc 返回 |
| `test/features/search/web_search_test.dart`（4） | 3.x 参数和非法参数；没有 WebView 时直接开系统浏览器并说明；直播间提示条在各宽度的位置；网页加载失败的重试和用浏览器打开 |
| `test/shared/room_lists_test.dart` 的 `c4` | 搜索页共用平台快照（升级 19-1） |

## 3.x 基线

- `~/ref/v3ref/lib/modules/search/`（`git show v3.2.11:lib/modules/search/...`，10 个文件 2331 行）：`search_controller.dart`（654：Windows 每次打开查 WebView2 `:146-175`、`:616-630`；网页搜索地址带跟踪参数 `:100-142`；不认链接 `:176-198`；说明文字拼成一大段 `:440-498`；每次比较读设置 `:500-508`）、`search_page.dart`（370）、`search_capability.dart`（164：YY、TwitCasting 标错 `:129-135`，YouTube 只能精确查 `:64-68`）、`search_platform_strip.dart`（105）、`search_ranking.dart`（69：只认 `isLiveNow` `:18`、`:52`）、`web_search_controller.dart`（550）、`web_search_page.dart`（215）、`web_search_room_parser.dart`（186）。
- 3.x 搜索页不存任何数据（没有历史、没有范围），没有要迁移的。
- 必须保留的操作习惯（[specs/UI.md](../../specs/UI.md) 附录 A）：第 14 条（结果卡片长按或右键 = 操作菜单）；第 7 条的 Esc 返回（`search_test.dart:908`）。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 搜索历史和“全部”的搜索范围存在 meta 里，不进备份 | `search_history.dart:18`、`search_scope.dart:41` | 换手机恢复备份后历史和范围没了 | 没有任务；要进备份需要 J03 的备份带上这两个键（新想法进 V01） |
| TwitCasting 超过 100 字的关键词在页面里截断，平台层没有自己截 | `search_model.dart:480-481` | 平台层改了以后这里是多余的 | 等 E03.4 改；不单独开任务 |
| Picarto 卡片上不显示简介（升级 11-5 只做了一半：标题是频道名、对话框里有简介） | `packages/live_ui` 的 `RoomCardData` 没有简介字段 | 搜 Picarto 时卡片第二行没有频道简介 | [A09.11](../../A-界面设计/A09-浏览界面/A09.11-Picarto搜索卡片简介/README.md)（未开始，先改卡片设计） |
| I05.1 记录里的 `search_cards.dart`、`search_room_sheet.dart` 已没有（卡片和对话框共用 `shared/rooms/`）；记录说网页搜索用系统浏览器，现在是应用内网页；测试数（12）已变成 27 + 4 | [I05.1 记录](I05.1-搜索/record.md) | 只是记录过时 | I05.1 README 已注明 |
| 网页搜索（F-SRC-04）没有真机结果；I05.1 登记“完成”，记录写“本次没装机”，S02.3 看过关键词搜索 | 功能清点 F-SRC-04 | 应用内网页认出直播间、返回回到网页没有在 K90 上走过 | [S02.6](../../S-质量和验证/S02-真机验证/S02.6-K90补验/README.md) 第 3 阶段（已列） |

## 相关决定和规范

- D-017（测试用假平台）、D-018（`hotAreasList`、`preferRealOnlineCounts` 照 3.x）、D-026（搜索历史、主播搜索这类 3.x 没有的功能当时由用户授权的统一原则覆盖；以后新功能先进 V01）。
- [specs/UPGRADES.md](../../specs/UPGRADES.md)：A-5、A-4（搜索页）、23-2、12-5、11-5（部分）、19-1、统一原则“受限直播搜索照常显示”“说明文字”。
- 界面决定：A09.7（X1 滚动收起、X3 搜索范围面板）、A09.8（网页搜索提示条）。

## 测试和验证

- 自动：`cd apps/pure_live && flutter test test/features/search`（31 个）。缺的：没有真的 WebView（`InAppWeb` 在测试里是假的）；`LinkParser` 的短链在 E04 的测试里。
- 真机：[S02 真机清单](../../S-质量和验证/S02-真机验证/CHECKLIST.md)第 4 节第 3 条（网页搜索，归 S02.6）；关键词搜索在 S02.3 走过。

## 路线

本子分类没有未完成的任务。

1. S02.6 第 3 阶段验证网页搜索（F-SRC-04）。
2. A09.11 改卡片设计后显示 Picarto 简介。
3. 新想法（搜索历史进备份、按分区搜索）写进 [V01](../../V-需求和反馈/V01-新功能提议/README.md)。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [I 浏览和发现](../README.md)。

- 代码：`features/search/`
- 进度：`████████████████████` 100%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| I05.1 | 搜索 | 功能 | 完成 | 2026-10-01 | b8b1ec18f | [设计或说明](I05.1-搜索/README.md)、[记录](I05.1-搜索/record.md) |

<!-- docs:生成结束 -->
