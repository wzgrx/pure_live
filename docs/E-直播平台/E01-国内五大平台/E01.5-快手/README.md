# E01.5 快手

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：3.x 平台逐个重构（D-001）；之后的升级落地（2026-09-29，只按统一原则补）、国内平台完善（2026-10-01，H.265 档）和 E06.1 的详情标题（UPGRADES A-3）都记在 [record.md](record.md) 和 [E06.1 的记录 2](../../E06-平台层升级/E06.1-已批准升级的余项/record-2.md)
- 旧编号：M4.05、M4.U.5、T02a.5
- 相关：模型 [E05.1](../../E05-平台框架和模型/README.md)、[E05.2](../../E05-平台框架和模型/README.md)（`fillFromDetail` 取卡片标题）、[E05.3](../../E05-平台框架和模型/E05.3-房间详情补齐时连封面一起补/README.md)；链接 [E04.1](../../E04-链接解析和分享口令/README.md)；弹幕 D01.6；快手 App 跳转 C03.1；H.265 中转在 G 组；巡检 [E01.6](../E01.6-国内五大平台巡检和修复/README.md)；决定 D-001、D-017、D-018
- 代码：`packages/live_core/lib/src/sites/kuaishou/`（`kuaishou_api.dart` 862 行解析，`kuaishou_site.dart` 453 行请求编排和游客会话）；样本 `fixtures/kuaishou/`（25 组，含弹幕 `danmaku/S16-live`）

## 目标

把 3.x 的快手适配器（`lib/core/site/kuaishou/kuaishou_site.dart` 598 行，类名拼成 `KuaishowSite`）重构进 `live_core`：分类、分区（含非游戏分区的 `cursor` 翻页）、推荐、搜索、房间页详情、游客会话、清晰度和线路、恢复、链接都和 3.x 一样能用。修掉 3.x 的 18 个问题（未开播和不存在的主播进房显示“状态未知”、进房后人数是整个分区的数字、搜索被限流时显示“没有结果”、非游戏分区第 2 页和第 1 页一样、建会话不走代理等），去掉对 GetX 设置和播放器状态的依赖。

## 平台接口要点

| 功能 | 接口（`live.kuaishou.com` 除非另写） | 位置 |
|---|---|---|
| 游客会话 | 用户配了 Cookie 就只用它；否则以浏览器身份裸访问一次房间页，把 `Set-Cookie`（`did`、`clientid`、`client_key`、`kpn`、`kuaishou.live.bfb1s`）存成会话，再尽力上报 `did`（`log-sdk.ksapisrv.com/…/misc2`，只带浏览器请求头）；会话 30 分钟有效，并发合并成一次；被拒时换新会话重试一次 | `kuaishou_site.dart:24`、`:121` |
| 浏览器身份 | `live_net` 的 `BrowserUserAgent`：UA 和客户端提示成套，每个游客会话随机一个 | |
| 分类 | `/live_api/category/data?type=<大类>&page=<页>&size=30`，按 `hasMore` 逐页走完，任何一页失败整个目录失败（8 个大类约 800 个分区） | `:210`、`:219` |
| 分区房间 | `/live_api/<gameboard 或 non-gameboard>/list`，非游戏分区（7 位编号）第 2 页起带上一页的 `cursor`；跨页去重（排行在两次请求之间会变） | `:244`、`:260` |
| 推荐 | `/live_api/home/list`，只有一页，按主播去重 | `:291`、`:293` |
| 搜索 | `/live_api/search/author?keyword=…&page=…&lssid=`（主播搜索，`lssid` 为空）；直播搜索 `search/liveStream` 对游客回 `result: 10`，所以房间和主播搜索都走主播搜索；`result` 2 为 `RateLimited`、10 为 `RiskControl` | `:305`、`:312`、`:321` |
| 详情 | 房间页 `/u/<用户 id>`，按 JSON 结构截取页面状态（只替换字符串外的裸 `undefined`）；`isLiving` 决定在播；`errorType` 22 为 `NotFound`，其他为 `RiskControl`；房间页没有直播标题，`title` 留空（A-3），没有房间人数 | `:350-365`；`kuaishou_api.dart:220-232` |
| 画质和线路 | 房间页的 `playUrls`，进房时放进 `KuaishouRoomData`，取流直接用；H.264 档照 3.x，房间页 H.265 里 H.264 没有的档带“ · H.265”加在后面；线路带 Chrome 140 的 UA、Origin、Referer，只有用户 Cookie 才带；有效期读 `txTime`、`wsTime`、`hwTime`、`ty_Time`、`auth_key`，提前 10 分钟续期；恢复时重新取房间页 | `:373-395` |
| 优先 H.264 | `KuaishouSite(preferH264:)`，开（默认）时 H.265 档排在后面，关时按档位排 | `app/platforms.dart:150` 传入 |
| 链接 | `live.kuaishou.com/u/<id>`；不支持 `v.kuaishou.com` 短链和 `m.gifshow.com`（没有样本） | `:433` |

## 3.x 和现状

| 方面 | 3.x（`lib/core/site/kuaishou/kuaishou_site.dart`） | 现在 | 说明 |
|---|---|---|---|
| 分类 | `getCategores` `:53`（3.x 经 v4 桥接） | `kuaishou_site.dart:210` | 一致 |
| 分区 | `:136`，不读 `hasMore`、不回传 `cursor`，非游戏分区第 2 页和第 1 页一样；卡片缺字段整页失败 | `:244` | 按 `cursor` 翻页、跨页去重；缺字段的卡片跳过 |
| 推荐 | `:270`，封面是分区海报、标题是主播简介、同一主播出现两次，每一页都返回同一份 | `:291` | 用卡片自己的 `poster`、`caption`，去重，只有第 1 页 |
| 搜索 | `:530`、`:583`（`searchAnchors` 返回空）；限流或拦截时“没有结果” | `:305`、`:321` | 类型化错误；`searchAnchors` 返回主播搜索结果 |
| 详情 | `:389`；`:129-135`、`:465` 未开播页面 `liveStream` 没有 `poster` 时抛类型错误并吞成“状态未知”；`:466-467` 人数取分区的 `watchingCount`；`:469` 房间号换成 `author.id`；`:292`、`:469` 标题是主播简介 | `:350` | 未开播如实返回、不存在报 `NotFound`；不给人数（由卡片或弹幕补）；房间号保持请求时的写法；标题留空，进房时由 `fillFromDetail` 取卡片标题（E06.1） |
| 取流 | `getPlayQualites` `:173`、`getPlayUrls` `:260`；签名地址约 24 小时过期没有续期信息，请求头在播放层写死 | `:373-395` | 线路带请求头和有效期；恢复重新取房间页；补上 H.265 档 |
| 会话 | `:372-388` 另建 Dio 和 CookieJar，不走代理；`:520` 把会话 Cookie 发给日志上报 | 注入的 `LiveHttp` | 3.x 问题 11、13 |
| `link` | 有时是场次 id，有时是网页地址 | 一律是房间页，场次 id 在 `KuaishouRoomData.liveStreamId` | 给 App 跳转（C03.1）用 |
| 弹幕 | `getDanmaku()` `:50`（移动端 feed 轮询） | `live_danmaku/lib/src/sites/kuaishou.dart`（D01.6） | 房间人数由 feed 的 `currentWatchingCount` 补 |

## 结果

- 首次重构（2026-09-28，提交 `944c67f40`）：18 个 3.x 问题见 record.md“审查发现的 v3 问题”，14 条有意差异见“与 v3 的有意差异”。保留 3.x 的做法：标题带【回放】的轮播卡片仍是直播中（房间页说在播，也能播）、封面补 `.jpg`、建会话的顺序、`lssid` 为空、不支持短链。
- 升级落地（2026-09-29，`ab456b879`）：开播时间取列表卡片的 `statrtTime`（平台原文的拼写，毫秒）；在播却没有可播放画质的标 `unplayable`；实测用户 id 不分大小写（`kpl704668133` 打开 `KPL704668133`），快手加进 `SiteIds.caseInsensitiveRoomIds`；分区翻页跨页去重。
- 国内平台完善（2026-10-01，`c5ebffe2e`）：真实接口检查全部正常；带会话 Cookie 的房间页开始给 H.265，补上 H.264 没有的档（“4K · H.265”等）并加“优先 H.264”开关。
- 详情标题（2026-10-02，`4f1a8b4a8`，E06.1 c1）：`roomDetail` 不再把简介写进 `title`，进房保留卡片标题，60 秒刷新和关注刷新不再用简介盖掉标题。
- 测试：`packages/live_core/test/sites/kuaishou_api_test.dart` 42 个 `test(` 写法、`kuaishou_site_test.dart` 36 个（record.md 统计 90 个用例）；弹幕 `packages/live_danmaku/test/kuaishou_test.dart` 70 个。

## 验证

- 自动测试：样本逐键对照 3.x（`link`、推荐封面和标题、人数是有意差异）；游客会话的复用、并发、过期重建、被拒重试；浏览器身份成套；分区 `cursor` 和去重；H.265 档的名字、顺序和回落；大小写身份合并；A-3 标题（`kuaishou_api_test.dart:1025-1038`）。
- 真实接口：2026-09-28 实测快手不分大小写；2026-10-01 跑了推荐、分类（约 20 个请求）、两个分区两页、搜索、3 个在播和 1 个未开播房间、8 档线路和 H.265、两个房间各 2 分钟弹幕（record.md）。
- 真机：播放和弹幕 K90 看过（2026-10-01，[FEATURES.md](../../../inventory/FEATURES.md) 第 14 节）。A-3 待真机：从推荐或分区卡片进房，标题是卡片上的直播标题，停留超过 1 分钟标题不变，关注后回到关注页标题不被简介替换（E06.1 记录 2“要在 K90 上看的”第 1 条）。

## 留下的问题

- 房间页没有开播时间，进房、关注刷新拿不到（受阻：没找到按主播查开播时间的公开接口）。
- 私密直播（`liveStream.privateLive`）没有样本，没有读。
- 登录后的直播搜索（UPGRADES C-17、候选 K-4）没验证，暂缓。
- 礼物、醒目留言要桌面端 WebSocket（要浏览器签名），不做（候选 K-3）。
- 从链接进房（没有卡片）时标题为空：E06.1 选择 A，界面显示主播名。
- 快手 App 跳转（F-RT-05）归 C03.1；H.265 档的 FLV 中转归 G 组。
- 接口会变：定期巡检归 [E01.6](../E01.6-国内五大平台巡检和修复/README.md)。
