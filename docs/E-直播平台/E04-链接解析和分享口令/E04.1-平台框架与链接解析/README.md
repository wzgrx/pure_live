# E04.1 平台框架与链接解析：站点注册、链接工具和短链

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：3.x 逐块重构（D-001），在 E05.1 模型之后、各平台之前做：平台编号、注册表、链接解析的公共部分要先有，平台重构时才能把各自的链接规则放进来
- 旧编号：M3、T02d.1
- 相关：模型 [E05.1](../../E05-平台框架和模型/E05.1-基础模型与接口/README.md)；各平台的链接规则随平台任务（[E01](../../E01-国内五大平台/README.md)、[E02](../../E02-其他国内平台/README.md)、[E03](../../E03-海外平台/README.md)）；Kick 恢复 [E03.16](../../E03-海外平台/E03.16-Kick/README.md)；分享口令和剪贴板 O03.2；搜索框粘贴链接 I 组（F-SRC-02）；决定 D-001、D-017
- 代码：`packages/live_core/lib/src/sites.dart`（303 行）、`packages/live_core/lib/src/links.dart`（359 行）；测试 `packages/live_core/test/sites_links_test.dart`

## 目标

用户在搜索框粘贴、从别的应用分享、在应用内网页搜索里点开一个直播间链接（或带链接的分享文字）时，能认出是哪个平台的哪个房间并直接进房；短链（`b23.tv`、`v.douyin.com`、`xhslink.com`、`t.cn`……）要发请求跟随跳转，但有预算、超时和统一取消，不会卡住或下载落地页。同时把 3.x 的平台注册表改成“每个平台一个实例、一直复用”，平台自己的会话缓存（快手的会话 Cookie 等）不再每查一次就丢。

## 3.x 和现状

| 方面 | 3.x（`~/ref/v3ref/lib/`） | 现在（文件:行） | 说明 |
|---|---|---|---|
| 平台编号和顺序 | `core/sites.dart:39` `class Sites`（457 行） | `sites.dart:4` `SiteIds`，`supported`（`:114`，34 个加网络电视，3.x 的顺序） | 编号、顺序不变 |
| 注册表 | `supportSites` 是 getter（`core/sites.dart:217`），每读一次新建全部适配器；`Sites.of` 每次新建 | `SiteRegistry`（`sites.dart:263`）：第一次用到时建、之后复用；`ids`、`sites`、`of`、`maybeOf`、`availableIds(saved)` | 记录问题 1、2；`availableIds` 由调用方传入“热门平台”设置（问题 4） |
| 已下线平台 | 12 个平台、16 个域名 | `retired`（`sites.dart:157`，11 个）、`retiredHosts`（`:173`，15 个）、`isRetiredLink`（`:249`） | Kick 已在 E03.16 恢复（UPGRADES X-1），从已下线里去掉 |
| 平台显示名 | 注册表里调 `i18n()` | 适配器只给默认名 `LiveSite.name`，界面文字由界面层给 | 问题 5 |
| 链接提取 | `common/utils/live_url_tool.dart:47` `sharedHttpUrls`：中文标点只对小红书、微博截断 | `links.dart:227` `LinkParser.sharedHttpUrls`：所有域名在第一个中文标点处截断；小红书、微博保留结尾 `/.`、`/..`（`:210` `_proseHosts`） | 问题 3：`…/123。快来` 以前只有两个平台认得出 |
| 解析顺序 | `parseLiveUrl`（`live_url_tool.dart:155`、`_parseLiveUrl` `:194`），一个函数里直接调用约 20 个平台的规则 | `LinkParser.parse`（`links.dart:273`）→ `_parse`（`:285`）：先问各平台的应用深链 `roomIdsInShareText`，再对每个链接先试不发请求的 `roomIdFromUrl`，再试要请求的 `needsResolving` / `resolveUrl`；`LinkRedirect` 再解析一遍 | 规则随平台走：`LiveSiteLinks` 混入（`links.dart:56`） |
| 短链会话 | `live_short_link_session.dart:5`（73 行），每次新建 dio、最多 8 个地址（`:16`） | `ShortLinkSession`（`links.dart:77`）：共用 `LiveHttp`，`maxRequests` 8（`:82`），只认 301/302/303/307/308（`:85`），不自动跟随、默认只读响应头（`get` `:113`，`readBody` 才读正文）、`send`（`:147`，签名的表单请求）、`redirectTarget`（`:175`）、一个取消令牌（`close` `:188`） | 问题 6 |
| 超时和取消 | 12 秒 | `parse(..., timeout: 12 秒)`（`:273`）；超时或调用方取消时所有请求一起取消 | 同 3.x |
| 返回值 | `[房间号, 平台]` 字符串列表 | `RoomLink(platform, roomId)`（`links.dart:10`）、`LinkRoom`（`:37`）、`LinkRedirect`（`:46`） | 带类型 |
| 通用路径规则 | `modules/search/web_search_room_parser.dart` | `RoomPaths`（`links.dart:318`）：保留路径段 18 个、`hostIs`、`firstSegment` | 网页搜索和多个平台共用 |
| 界面流程 | `getPlayUrlByRoomId`（`live_url_tool.dart:388`）、`castPlayUrlByRoomId`（`:405`）带弹窗 | 移到工具箱 `apps/pure_live/lib/features/toolbox/toolbox_actions.dart:23` | 平台层不带界面 |

应用里调用 `LinkParser` 的地方：搜索框粘贴（`features/search/search_view.dart:125`）、网页搜索进房（`features/search/web_search_view.dart:116`）、工具箱（`features/toolbox/toolbox_actions.dart:23-24`）、系统分享接收（`app/intake/system_intake.dart:48`，`ShareIntake` 在 `share_intake.dart:52`）。

## 结果

- 2026-09-28 合并（提交 `e49c4bdd3`）：`sites.dart`、`links.dart` 两个文件；6 个 3.x 问题、保留的 3.x 行为（平台、链接提取、短链、超时、顺序）见 [record.md](record.md)。
- 各平台的链接规则随后在 E01～E03 各平台任务里写成 `LiveSiteLinks` 的四个方法；现在 34 个适配器都混入了它，13 个有要请求的短链或别名（哔哩哔哩 `b23.tv`、斗鱼和虎牙的字母别名、抖音 `v.douyin.com` 和 reflow、克拉克拉、LiveMe、niconico、SHOWROOM 纯数字房间键、Steam 自定义地址、TikTok、微博 `t.cn`、小红书 `xhslink.com`、YouTube `@handle`），2 个有应用深链（小红书 `xhsdiscover://`、SOOP）。逐个平台的位置见[子分类说明](../README.md)的代码地图。
- 测试：记录当时新增 34 个用例；现在 `sites_links_test.dart` 有 23 个 `test(` 写法（部分用例在循环里生成）。平台相关的链接用例（抖音短链、reflow、`b23.tv` 等）在各平台的 `_site_test.dart` 里。

## 验证

- 自动测试：`sites_links_test.dart`：平台编号和顺序、已下线平台和链接、注册表只建一次、`availableIds` 去重；链接提取（结尾标点、中文后缀、签名拼写不重新编码、其他协议、用户信息、不能解码的转义）；短链（五种跳转码、相对 `Location`、自跳转、片段、预算、失败不影响后面的直链、超时和取消、`containsSupportedLink` 不发请求）。全部用假的 `LiveHttp`，不访问真实平台（D-017）。
- 真机：从别的应用分享“快来看直播 https://live.bilibili.com/6”直接进房，K90 通过（2026-10-02，S02.3，[FEATURES.md](../../../inventory/FEATURES.md) F-AND-02）；搜索框粘贴链接（[S02 的 CHECKLIST.md](../../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 4 节第 2 条后半）没看。

## 留下的问题

- 记录“上游核对”一节说“Kick 仍按 v3 列为已下线”，已经过时：Kick 在 2026-10-01 恢复（E03.16），`retired` 里没有它了（`sites.dart:152-156` 的注释说明了恢复）。
- 短链会话的 8 个地址预算是 3.x 的数字，没有平台实测需要更多；抖音分享链接经 `v.douyin.com` → `www.iesdouyin.com` → reflow 一般 3 跳。
- 各平台链接规则在平台改版后会失效（例如新的短链域名）：随平台巡检核对（[E01.6](../../E01-国内五大平台/E01.6-国内五大平台巡检和修复/README.md)、[E07.1](../../E07-平台巡检/E07.1-平台巡检工具/README.md)）。
- 记录里的旧编号（M3、M13）对照 [MAPPING.md](../../../MAPPING.md)。
