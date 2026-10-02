# T02d.1 平台框架与链接解析

- 日期：2026-09-28
- 目标包：`packages/live_core`（`sites.dart`、`links.dart`）
- 参考仓库核对：pure_live_TV `9fb40418`

## 对照

| v3 文件 | 行数 | 重构后 |
|---|---|---|
| `core/sites.dart` | 457 | `sites.dart`：`SiteIds`（平台编号、已下线平台及其域名）、`SiteRegistry`（每个平台一个适配器实例） |
| `common/utils/live_url_tool.dart`（链接解析部分） | 473 | `links.dart`：`LinkParser`、`LiveSiteLinks`（平台的链接能力）、`RoomLink`、`LinkResolution` |
| `common/utils/live_short_link_session.dart` | 73 | `links.dart`：`ShortLinkSession`，改用 live_net |
| `modules/search/web_search_room_parser.dart`（通用部分） | 186 | `links.dart`：`RoomPaths`（保留路径段、域名判断、首段取房间号） |

## 拆分方式

v3 的链接解析集中在一个文件里，直接调用约 20 个平台各自的链接规则和接口（小红书、克拉克拉、LiveMe、TikTok、YouTube……），外加搜索页里主要平台的房间地址规则。重构后：

- **通用部分放在这里**：
  - 从分享文本里提取链接；
  - 短链会话：统一的请求预算、不自动跟随跳转、只读响应头、统一取消；
  - 按平台顺序询问每个平台的解析器；
  - 顺着跳转继续解析目标地址。
- **每个平台的规则**在 T02 随平台一起重构，形式是 `LiveSiteLinks` 混入：
  - `roomIdFromUrl`：房间地址，不需要请求；
  - `needsResolving` 和 `resolveUrl`：短链或分享码，需要请求。结果要么是找到房间，要么是跳转到另一个地址，由解析器再解析一遍；
  - `roomIdsInShareText`：应用深链，比如小红书的 `xhsdiscover://`。
- 返回值从 `[房间号, 平台]` 这样的字符串列表，改成带类型的 `RoomLink(platform, roomId)`。
- v3 的 `getPlayUrlByRoomId`、`castPlayUrlByRoomId` 是界面流程（弹窗、提示），移到 M13 工具箱。

## 审查发现的 v3 问题

| # | 问题 | 位置 | 根因 | 处理 |
|---|---|---|---|---|
| 1 | `Sites.supportSites` 是 getter，每读一次就新建全部 34 个适配器 | `core/sites.dart:217-267` | 注册表不持有实例 | `SiteRegistry` 在第一次用到时创建适配器，之后一直复用 |
| 2 | `Sites.of(id)` 每次调用都新建适配器，平台自己的会话缓存（比如快手的会话 Cookie）每查一次就丢一次 | `core/sites.dart:269-417` | 同上 | 同上。pure_live_TV 后来也改成了缓存（`platforms/sites.dart:343,400`），说明方向一致 |
| 3 | 分享文本里链接后面紧跟中文（如 `https://live.bilibili.com/123。快来`）时，只有小红书和微博会切掉后面的文字，其他平台带着“。快来”去匹配房间号，结果失败 | `common/utils/live_url_tool.dart:49-70` | 切中文标点的规则只对两个域名生效 | 所有域名都在第一个中文标点处截断；百分号编码的标点不受影响 |
| 4 | 注册表通过 GetX 读取“热门平台”设置 | `core/sites.dart:419-437` | 平台层依赖设置服务 | `availableIds(saved)` 由调用方传入已保存的列表 |
| 5 | 平台显示名在注册表里调用 `i18n()` | `core/sites.dart:217-267,439-457` | 平台层依赖界面翻译 | 适配器只提供默认名（`LiveSite.name`），界面文字由界面层给出 |
| 6 | 短链会话每次解析都新建一个 dio 客户端 | `common/utils/live_short_link_session.dart:6-10` | 靠关闭客户端来取消请求 | 共用注入的 `LiveHttp`，每次解析一个取消令牌 |

## 保留的 v3 行为

- **平台**：
  - 34 个平台（含 IPTV）的编号和显示顺序；
  - 12 个已下线的平台（花椒、OPENREC、TTING、PopkonTV、Shopee、VK、Nimo、Dailymotion、Rumble、GoodGame、淘宝、Kick）及其 16 个域名：保存过的关注、历史和链接仍可读，显示为“已下线”，不当作未知平台报错。
- **链接提取**：
  - 只取 http(s) 链接，保持原始拼写（签名参数不重新编码）；
  - 去掉结尾标点；
  - 小红书和微博保留结尾的 `/.` 和 `/..`（在这两个平台是路由结构）；
  - 跳过带用户信息、其他协议、百分号转义无法解码的链接。
- **短链**：
  - 一次解析最多请求 8 个不同地址；
  - 带片段的同一地址不重复请求，自跳转立刻停止；
  - 不自动跟随跳转；
  - 只认一个非空、协议为 http(s)、不带用户信息的 `Location`；
  - 非跳转状态码不看 `Location`；
  - 某个短链失败不影响后面的直链。
- **超时和取消**：默认 12 秒；超时或调用方取消时，所有进行中的请求一起取消，之后不再发新请求。
- **顺序**：先看应用深链，再看网页链接；每个链接先试不需要请求的规则，再试需要请求的；平台按显示顺序。

## 上游核对

- pure_live_TV 的注册表同样改为缓存适配器实例。
- pure_live_TV **重新加回了 Kick**（`platforms/kick`，约 960 行），v3 在 3.2.11 因 Cloudflare 拦截下线了它。这里仍按 v3 列为已下线；T02 最后评估电视版怎么绕过 Cloudflare，再决定是否恢复。

## 测试

新增 34 个用例（`sites_links_test.dart`），`live_core` 共 115 个，全部通过：

- 平台编号和顺序、已下线平台及其链接；
- 注册表只建一次适配器、按显示顺序列出、已保存列表的去重和过滤；
- 链接提取：结尾标点、中文后缀（问题 3）、签名拼写、其他协议、用户信息、无法解码的转义；
- 移植 v3 微博和小红书分享的提取用例（平台相关的判断留到 T02）；
- 移植 v3 短链测试中与平台无关的用例：
  - 五种跳转状态码；
  - 相对 `Location`、自跳转、片段、请求预算、失败后不影响后面的直链；
  - 直链和深链不发请求；
  - 无效或无关的 `Location`、重复的 `Location`、非跳转状态码；
  - 超时和调用方取消会取消请求；
  - 已取消的调用方不发请求；
  - `containsSupportedLink` 不发请求。
- 抖音短链、`webcast.amemv.com` 的 reflow 等平台相关用例，随 T02 抖音一起移植。
