# E04 链接解析和分享口令

用户粘贴或分享过来的直播间链接、短链、分享文字，认出是哪个平台的哪个房间：公共的提取和短链跟随（`links.dart`）、平台编号和“已下线”的判断（`sites.dart`），以及 34 个平台各自的链接规则（`LiveSiteLinks` 的四个方法，写在各平台适配器里）。

## 范围

- 包括：
  - `packages/live_core/lib/src/links.dart`：`RoomLink`、`LinkResolution`（`LinkRoom`、`LinkRedirect`）、`LiveSiteLinks` 混入、`ShortLinkSession`、`LinkParser`、`RoomPaths`。
  - `packages/live_core/lib/src/sites.dart` 里和链接有关的：`SiteIds.retired`、`retiredHosts`、`isRetiredLink`（已下线平台的链接答“已下线”而不是“认不出”）。
  - 各平台适配器里的 `roomIdFromUrl`、`needsResolving`、`resolveUrl`、`roomIdsInShareText`（下面的代码地图）：规则的内容随平台任务（E01～E03）改，这里管它们的约定和公共部分。
- 不包括（归哪里）：
  - 3.x 格式的分享口令（`apps/pure_live/lib/shared/rooms/share_code.dart` 的 `encodeRoomShareCode` `:19`、`decodeRoomShareCode` `:69`）、剪贴板识别（`app/intake/clipboard_rooms.dart:34` 的 `ClipboardRoomWatcher`）、系统分享接收（`app/intake/share_intake.dart:52` 的 `ShareIntake`）→ O03（O03.2）；它们拿到文字后调这里的 `LinkParser`。
  - 搜索框粘贴链接、网页搜索进房的界面 → I 组（I05）和 A 组；工具箱“获取直链”的界面 → C03。
  - 平台注册表 `SiteRegistry`、平台编号的含义 → [E05](../E05-平台框架和模型/README.md)。

## 现状：做到哪、怎么工作的

- 用户看得到的：
  - 搜索框里粘贴一段带链接的文字，提交时直接进房（`features/search/search_view.dart:213-215`）；是已下线平台的链接时提示“该平台已下线”（`:216-218`，`platform_retired`）。
  - 应用内网页搜索：打开的页面是某个直播间时，底部出现“进入直播间”条（`features/search/web_search_view.dart:110-121`）。
  - 从别的应用分享文字或链接到本应用：认得出就直接进房，认不出提示“解析失败”，已下线平台提示已下线（`app/intake/share_intake.dart:152`、`:180-197`）。
  - 工具箱里粘贴链接取直链或投屏（`features/toolbox/toolbox_actions.dart:23-24`、`:201`）。
- 内部怎么工作：
  1. `LinkParser.parse(text)`（`links.dart:273`）开一个 `ShortLinkSession`（最多 8 个不同地址、不自动跟随跳转、默认只读响应头），整体 12 秒超时，调用方可取消；
  2. 先问每个平台 `roomIdsInShareText`（应用深链：小红书 `xhsdiscover://`、SOOP）；
  3. 再用 `sharedHttpUrls`（`:227`）从文字里取 http(s) 链接：第一个中文标点处截断，去掉结尾标点（小红书、微博保留 `/.`、`/..`），跳过带用户信息、其他协议、转义解不开的；
  4. 对每个链接按平台显示顺序先试 `roomIdFromUrl`（不发请求），再试 `needsResolving` 为真的平台的 `resolveUrl`；结果是 `LinkRoom`（找到）或 `LinkRedirect`（跳到别的地址，整段再解析一遍，可能落到另一个平台）；
  5. 返回 `RoomLink(platform, roomId)`，调用方打开直播间。
- 完成度（和 3.x 对照）：
  - 一致的：3.x 的链接提取、8 个地址的短链预算、12 秒超时、先深链后网页、先直链后短链、平台顺序；3.x 认得出的链接都认得出（各平台任务把 3.x `live_url_tool.dart` 的用例逐条移植）。
  - 确认过的改动：中文后缀对所有平台截断（E04.1 问题 3）；新认得的链接：niconico `nico.ms` 和旧手机站（17-2）、微博 `t.cn`（18-9）、Steam 自定义地址（27-4）、酷狗任意路径上的 `roomId`（29-4）、YouTube `@handle`（23 系列）、Kick（X-1）。
  - 还缺：SOOP 分享文本带 App 深链（UPGRADES 7-9 后半，未排）；酷狗 `fanxing2.kugou.com`（29-4 后半，受阻：没录到用它的分享链接）。

## 代码地图

公共部分：

| 文件 | 职责 |
|---|---|
| `packages/live_core/lib/src/links.dart`（359 行） | `RoomLink`（`:10`）、`LinkResolution`（`:32`）、`LinkRoom`（`:37`）、`LinkRedirect`（`:46`）、`LiveSiteLinks`（`:56`，四个方法的默认都是“认不出”）、`ShortLinkSession`（`:77`：`maxRequests` `:82`、`redirectStatuses` `:85`、`get` `:113`、`send` `:147`、`redirectTarget` `:175`、`close` `:188`）、`LinkParser`（`:197`：`_proseHosts` `:210`、`sharedHttpUrls` `:227`、`containsSupportedLink` `:264`、`parse` `:273`、`_parse` `:285`）、`RoomPaths`（`:318`，18 个保留路径段、`hostIs`、`firstSegment`） |
| `packages/live_core/lib/src/sites.dart`（303） | `retired`（`:157`，11 个）、`retiredHosts`（`:173`，15 个域名）、`isRetiredLink`（`:249`） |

各平台的链接方法（`packages/live_core/lib/src/sites/<平台>/<平台>_site.dart` 的行号）：

| 平台 | `roomIdFromUrl` | 要请求的链接（`needsResolving` / `resolveUrl`） | 深链 |
|---|---|---|---|
| 哔哩哔哩 | `:600` | `b23.tv` 短链（`:620` / `:625`） | — |
| 斗鱼 | `:527` | 字母别名页 `www.douyu.com/lpl`（`:540` / `:555`） | — |
| 虎牙 | `:813` | 字母别名页 `www.huya.com/lpl`（`:820` / `:829`） | — |
| 抖音 | `:761` | `v.douyin.com` 分享链接、`webcast.amemv.com/…/reflow/{room_id}`（`:782` / `:804`） | — |
| 快手 | `:433` | — | — |
| 网易 CC、YY、AcFun、猫耳、映客、京东、酷狗、百度、六间房、LOOK、17LIVE | `cc :394`、`yy :511`、`acfun :621`、`missevan :292`、`inke :439`、`jdlive :426`、`kugoulive :371`、`baidulive :391`、`sixroom :496`、`looklive :376`、`seventeenlive :308` | — | — |
| 克拉克拉 | `:394` | 直播页、加密分享链接（`:403` / `:410`） | — |
| 小红书 | `:237` | `xhslink.com`（`:241` / `:246`） | `xhsdiscover://`（`:255`） |
| 微博 | `:327` | `t.cn`（`:332` / `:339`） | — |
| SOOP | `:367` | — | App 链接（`:383`） |
| Twitch、Picarto、TwitCasting、CHZZK、BIGO、PandaTV、FC2、Kick | `twitch :602`、`picarto :321`、`twitcasting :331`、`chzzk :391`、`bigo :599`、`pandalive :400`、`fc2live :497`、`kick :277` | — | — |
| niconico | `:474` | 节目链接 `lv…`、`nico.ms`、旧手机站，要读观看页换成主播（`:480` / `:487`） | — |
| SHOWROOM | `:401` | 纯数字房间键 `/r/7779344804`（`:411` / `:419`） | — |
| LiveMe | `:369` | 主播页 `/u/<uid>`、分享页 `/v/<vid>`（`:377` / `:387`） | — |
| TikTok | `:316` | `share/live/<房间号>`、分享短链（`:324` / `:332`） | — |
| YouTube | `:682` | `@handle`、`c/…`、`user/…`（`:691` / `:701`） | — |
| Steam 直播 | `:502` | 自定义地址 `steamcommunity.com/id/<名字>`（`:506` / `:511`） | — |

应用里的调用：`features/search/search_view.dart:125`、`features/search/web_search_view.dart:116`、`features/toolbox/toolbox_actions.dart:23`、`app/intake/system_intake.dart:48`。

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `packages/live_core/test/sites_links_test.dart`（23 个 `test(`） | 平台编号和顺序、已下线平台和链接、注册表；链接提取、短链会话的全部规则、超时和取消 |
| `packages/live_core/test/sites/<平台>_site_test.dart` | 每个平台的链接用例（3.x `live_url_tool` 测试逐条移植） |
| `apps/pure_live/test/intake_test.dart` | 分享接收和剪贴板口令（O03.2）调用 `LinkParser` 的流程 |

## 3.x 基线

- `git show v3.2.11:lib/common/utils/live_url_tool.dart`（463 行）：`LiveUrlTool`（`:33`）、小红书深链（`:34`）、`sharedHttpUrls`（`:47`，中文标点只对小红书、微博截断）、`containsSupportedLink`（`:100`）、`parseLiveUrl`（`:155`）和 `_parseLiveUrl`（`:194`，一个函数里调约 20 个平台的规则）、抖音房间号（`_getRealDouyinRoomId` `:335`）、`getPlayUrlByRoomId`（`:388`）、`castPlayUrlByRoomId`（`:405`）。
- `lib/common/utils/live_short_link_session.dart`（73 行）：`maxRequests = 8`（`:16`），每次新建 dio。
- `lib/modules/search/web_search_room_parser.dart`：网页搜索的房间路径规则。
- 必须保留：3.x 能认的链接都能认；签名链接原样不重新编码；短链失败不影响后面的直链；超时 12 秒。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| SOOP 分享文本不带 App 深链 | 分享在 `shared/rooms/share_code.dart:19`（3.x 格式的分享码） | 别人点分享链接不能直接拉起 SOOP App | UPGRADES 7-9 后半，未排（要先定分享格式） |
| 酷狗 `fanxing2.kugou.com` 的分享链接没处理 | `kugoulive_site.dart:371` | 这类链接认不出 | UPGRADES 29-4 后半，受阻：没录到样本 |
| E04.1 记录说 Kick“仍按已下线”，已过时 | [E04.1 记录](E04.1-平台框架与链接解析/record.md)“上游核对” | 读记录的人会误解 | E04.1 README 已注明；记录是当时写的，不改 |
| 短链会话只按 3.x 的 8 个地址；一次解析整体 12 秒 | `links.dart:82`、`:273` | 弱网下长链路的短链可能超时 | 没有实测问题，不做 |
| 平台改版后新的短链域名认不出 | 各平台 `needsResolving` | 分享进不了房 | 巡检（E01.6、E07.1）时用最新的分享链接试一次 |

## 相关决定和规范

- D-001（照 3.x 的行为）、D-017（链接测试用假 `LiveHttp`，不访问真实平台）。
- [specs/UPGRADES.md](../../specs/UPGRADES.md)：7-9、17-2、18-9、23 系列、27-4、29-4、X-1。

## 测试和验证

- 自动测试：`cd packages/live_core && dart test test/sites_links_test.dart test/sites/`；`cd apps/pure_live && flutter test test/intake_test.dart`。覆盖公共规则和每个平台的链接；缺的：真实的分享文字样本只在各平台测试里零散有。
- 真机：[S02 的 CHECKLIST.md](../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 4 节第 2 条（粘贴哔哩哔哩直播链接直接进房，没看）、第 3 条（网页搜索进房）、第 11 条（从别的应用分享，2026-10-02 S02.3 通过）。

## 路线

1. 没有登记的任务：E04.1 已完成；新问题随平台巡检（[E01.6](../E01-国内五大平台/E01.6-国内五大平台巡检和修复/README.md)、[E07.1](../E07-平台巡检/E07.1-平台巡检工具/README.md)）发现后在这里登记。
2. 以后：SOOP 分享深链（7-9）等分享格式定了再开任务；新想法写进 V01 提议，不直接加任务。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [E 直播平台](../README.md)。

- 代码：`packages/live_core/lib/src/links.dart`
- 进度：`████████████████████` 100%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| E04.1 | 平台框架与链接解析：站点注册、链接工具和短链 | 平台 | 完成 | 2026-09-28 | e49c4bdd3 | [设计或说明](E04.1-平台框架与链接解析/README.md)、[记录](E04.1-平台框架与链接解析/record.md) |
| E04.2 | 小红书分享短链认 xhslink.com/o/ 前缀：整段分享文案粘贴后能打开直播间 | 平台 | 完成 | 2026-10-08 | — | [设计或说明](E04.2-小红书o前缀短链/README.md)、[记录](E04.2-小红书o前缀短链/record.md) |

<!-- docs:生成结束 -->
