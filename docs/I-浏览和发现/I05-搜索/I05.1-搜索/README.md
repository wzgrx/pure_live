# I05.1 搜索

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能（页面重构）
- 来源：模块重构计划的页面部分（D-001）；3.x 的 `lib/modules/search/`（10 个文件 2331 行）
- 旧编号：M13.4、T07f.1
- 相关：E04.1（`LinkParser`）；E 组各平台的 `searchRooms`、`searchAnchors`、翻页策略；J02.1（设置、关注、`MetaStore`）；I01.2（卡片和菜单挪到 `shared/rooms/`）；O03.1（`flutter_inappwebview`，网页搜索接回应用内）；之后的 A09.7（搜索界面）、A09.8（网页搜索界面）、M13.16（“全部”的搜索范围）；提交 `b8b1ec18f`；记录 [record.md](record.md)

## 目标

在 4.x 里做出 3.x 的搜索页：“全部”和单个平台、全平台并发、各自翻页、去重、筛选和排序、部分失败横幅、网页搜索；修掉能力表标错（YY、TwitCasting、YouTube）、说明文字是开发说明、回放被当成未开播、粘贴链接白搜一遍这些问题；按用户授权加上主播搜索、搜索历史、粘贴链接直接进房。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11`） | 当时做成 | 现在（文件:行） |
|---|---|---|---|
| 并发、超时、翻页 | `search_controller.dart`：12 个并发、12 秒、各自翻页、两页没新结果停 | 同 | `features/search/search_model.dart:48-55`、`:426` |
| 能力表 | `search_capability.dart:129-135` YY、TwitCasting 标“能搜到未开播”；`:64-68` YouTube 只能精确查 | 按平台层核对（A-5、23-2） | `search_capability.dart:148` |
| 说明文字 | `search_controller.dart:440-498` 开发说明拼成一大段 | 一行摘要 + 搜索范围面板 | 同；面板在 A09.7 改成“搜索范围”（选平台 + 说明，X3） |
| 未开播筛选 | `search_ranking.dart:18`、`:52` 只认 `isLiveNow`，回放也被藏 | 看 `isPlayableNow`；直播 > 回放 > 其余 | `search_ranking.dart:68` |
| 粘贴链接 | 不认（`search_controller.dart:176-198`），进房要去工具箱 | `LinkParser` 认出就直接进房 | `search_view.dart:125` |
| TwitCasting 长关键词 | 适配器抛错，当成失败 | 页面先截 100 字 | `search_model.dart:480` |
| 主播搜索、历史 | 没有 | 加上（7 个平台；meta `search.history` 20 条） | 同 |
| “全部”里去掉平台 | 没有 | 没有 | M13.16 加：`SearchScopeStore`（meta `search.allExcluded`）、海外平台建议代理（`search_scope.dart:14-58`） |
| 网页搜索 | 应用内 WebView，认出房间链接后确认进房；Windows 每次查 WebView2 | 系统浏览器（当时没有 WebView 插件），进房靠把链接粘贴回来 | O03.1 接回应用内网页：`web_search_view.dart:111` 每页用 `LinkParser` 认，提示条“进入 / 关闭”；没有 WebView 时直接开系统浏览器（`:97-109`） |
| 卡片和长按 | `RoomCard` 菜单 | 自己的 `search_cards.dart`、`search_room_sheet.dart`（底部面板） | 都没了：卡片和卡片对话框共用 `shared/rooms/`（I01.2、A09.1） |

## 结果

- 做了什么（详见 [record.md](record.md)“做法”）：`search_model.dart`、`search_capability.dart`、`search_ranking.dart`、`search_history.dart`、`search_view.dart`、`web_search_view.dart`、`search_page.dart`、`search_widgets.dart` 等；页面打开时取一次平台快照（3.x 同）。
- 3.x 功能逐项对照（record.md 15 行）：网页搜索当时改成系统浏览器，其余都有；后来网页搜索按 3.x 接回应用内（O03.1、A09.8）。
- 修了 3.x 问题 9 条（record.md“审查发现的 v3 问题”）；界面改进 11 条（之后由 A09.7、A09.8 定稿）。
- 已批准的升级：A-5、统一原则“说明文字”完成；A-4 搜索页完成；23-2、12-5、11-5（标题是频道名、对话框有简介；卡片简介由 A09.11 做）、统一原则“受限直播搜索照常显示”搜索部分完成。
- 翻译键中英文各 56 个；3.x 的 `search_coverage_*` 由 I01.2 删掉（只留 `search_coverage_acfun`）。
- 提交 `b8b1ec18f`（2026-10-01）。现在 `features/search/` 9 个文件 3052 行（多了 `search_scope.dart` 263 行，`web_search_view.dart` 从系统浏览器的小页变成应用内网页 452 行）。
- 测试：当时 12 个（`search_test.dart`）。

## 验证

- 自动测试：现在 `apps/pure_live/test/features/search/search_test.dart` 27 个、`web_search_test.dart` 4 个（之后 A09.7、A09.8、M13.16、A07.2 加的）。
- 真机：record.md 写“本次没装机”。S02.3（[记录](../../../S-质量和验证/S02-真机验证/S02.3-K90验证主流程/record.md)）走过关键词搜索；网页搜索（功能清点 F-SRC-04）没有真机结果，归 [S02.6](../../../S-质量和验证/S02-真机验证/S02.6-K90补验/README.md) 第 3 阶段。

## 留下的问题

- record.md“留给后续”现在的去向：应用内网页搜索 → O03.1、A09.8（完成，待 S02.6 真机）；卡片转换共用 → I01.2（完成）；卡片对话框的标签和分享 → I01.2、A09.1（完成）；卡片上显示简介（11-5）→ A09.11（未开始）；TwitCasting 截断挪到平台层 → 等 E03.4，没有任务；搜索历史进备份 → 没有任务（见[子分类说明](../README.md)“已知问题”）；分享和剪贴板自动识别 → O03（完成）。
