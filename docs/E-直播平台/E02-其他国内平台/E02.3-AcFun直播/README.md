# E02.3 AcFun 直播

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：3.x 平台逐个重构（D-001）；之后的升级落地（2026-09-29，UPGRADES 10-1～10-5）记在 [record.md](record.md)；弹幕由 D01.10 接上；卡片上的开播时间由 E06.1 第 3 条接到界面
- 旧编号：M4.10、M4.U.10、T02b.3
- 相关：模型 [E05.1](../../E05-平台框架和模型/E05.1-基础模型与接口/README.md)、[E05.2](../../E05-平台框架和模型/E05.2-模型扩展/README.md)；链接 [E04.1](../../E04-链接解析和分享口令/E04.1-平台框架与链接解析/README.md)；弹幕 [D01.10](../../../D-弹幕/D01-平台弹幕协议/D01.10-AcFun弹幕/README.md)（用这里的 `AcfunDanmakuArgs`）；卡片开播时间 [E06.1](../../E06-平台层升级/E06.1-已批准升级的余项/README.md) 第 3 条；游标翻页由推荐页 I02.1、分区页 I03.1 接上；决定 D-001、D-017、D-018
- 代码：`packages/live_core/lib/src/sites/acfun/`（`acfun_api.dart` 660 行解析，`acfun_site.dart` 675 行请求编排、访客会话和游标）；通用 HTML 片段读取器 `packages/live_core/lib/src/html.dart`（`HtmlElement.parseFragment`，`:42`）；样本 `fixtures/acfun/`（ls 共 14 项：13 组接口录制，另有弹幕样本目录 `danmaku/`；归档没有冻结输出，用 3.x 代码原样复制到临时包里补出各组的 `expected.json`）；应用在 `apps/pure_live/lib/app/platforms.dart:161` 建 `AcfunSite(http)`

## 目标

把 3.x 的 AcFun 适配器（`lib/core/site/acfun/` 四个文件共 793 行）重构进 `live_core`：分类、推荐、分区、作者搜索、详情、访客登录和 `startPlay` 取流、恢复、链接都和 3.x 一样（全部匿名）。修掉 3.x 的 12 个问题（取流偶发失败要再点一次、翻页报“分页过期”、一张坏卡片整页失败、不存在的主播报“格式错误”等），会话、游标、搜索序列从全局静态对象改为适配器实例上的状态。

## 平台接口要点

| 功能 | 接口（`live.acfun.cn` 除非另写；全部匿名） | 位置 |
|---|---|---|
| 分类 | `/api/channel/list?count=1`（只取分区表，不动任何游标）；一个分类“AcFun 直播”，4 个分区（虚拟偶像、游戏、娱乐、其他）；“全部”（filterId 0）从 10-2 起去掉，存下的“全部”按推荐读 | `acfun_site.dart:109`、`:125`；`acfun_api.dart:214` |
| 推荐、分区 | `/api/channel/list`，不透明游标 `pcursor`，每页 30；按页码提供时每个“页大小 + 分区”一条游标链（最多 12 条链、64 个游标），丢了游标就重读前面的页；跨页去重；另有 `getDirectoryPageAtCursor` 直接按游标取（10-5） | `acfun_site.dart:142`、`:147`、`:159`、`:186`、`:267`；`acfun_api.dart:251` |
| 搜索 | `www.acfun.cn/search`（HTML，用 `HtmlElement.parseFragment` 读卡片），必须带 UA 和 `Referer: https://www.acfun.cn/search`（否则 403，`RiskControl`）；服务端每页 30 条切成应用的页，页号 × 30 达到总数才结束；一页最多 8 秒、4 个服务端页；结果是作者，含未开播 | `acfun_site.dart:308`、`:349`、`:412`；`acfun_api.dart:524`、`:565` |
| 详情 | `/api/live/info`；在播只看 `liveId`；关注刷新、开播状态只请求它；进房、录制再加访客会话和 `startPlay`（共 3 个请求） | `acfun_site.dart:434`、`:446`、`:461-474`；`acfun_api.dart:268` |
| 访客会话 | `id.app.acfun.cn/rest/app/visitor/login`（Cookie `_did=web_<16 位>`），内存复用 5 分钟，并发共用一次；`acSecurity` 可以没有 | `acfun_site.dart:480`；`acfun_api.dart:341` |
| 取流 | `api.kuaishouzt.com/rest/zt/live/web/startPlay`（`pullStreamType=FLV`）：`videoPlayRes` 是 JSON 字符串，画质按 3.x 的排序值（有 `level` 的 `1000000 + level`，否则码率，两种刻度不混排）；被拒时当次换会话重试一次；129004 是关播（`StreamUnavailable`），380205 是付费直播未购票（`paid`，不换会话）；恢复只请求 `startPlay` | `acfun_site.dart:509`、`:551-570`、`:575`、`:589`；`acfun_api.dart:360`、`:397`、`:460` |
| 线路 | 带 UA、`Referer`、`Origin: https://live.acfun.cn`，路径 `.flv` / `.m3u8` 定格式，CDN 主机作线路编号，`auth_key` 算租期 | `acfun_api.dart:477`、`:502` |
| 弹幕参数 | `AcfunDanmakuArgs`：作者 id、`liveId`、访客会话、`availableTickets`、`enterRoomAttach`，`refresh` 取新会话和新 `startPlay`；付费直播不给 | `acfun_site.dart:594`、`:606` |
| 链接 | `live.acfun.cn/live/<id>`、手机页 `m.acfun.cn/live/detail/<id>`、个人主页 `www.acfun.cn/u/<id>`（也认 `acfun.cn/u/`、`.aspx`）、手机主页 `m.acfun.cn/upPage/<id>`；`m.acfun.cn/u/<id>` 是手机站首页，不认 | `acfun_site.dart:621` |

弹幕协议（快手中台长连接、AES-128-CBC、protobuf 帧、礼物表 `gift/list`）归 [D01.10](../../../D-弹幕/D01-平台弹幕协议/D01.10-AcFun弹幕/README.md)。

## 3.x 和现状

| 方面 | 3.x（`~/ref/v3ref/lib/core/site/acfun/`） | 现在（`packages/live_core/lib/src/sites/acfun/`） | 说明 |
|---|---|---|---|
| 分类 | `acfun_site.dart:61`，含“全部” | `acfun_site.dart:125`，去掉“全部” | 10-2；探测时“全部”和推荐的 23 个房间逐个相同 |
| 列表翻页 | `acfun_directory.dart:22-39` 页码和游标存在共享序列里，被挤出就报“分页过期” | 游标链跟适配器走，丢了就重读；跨页去重；另可按游标取页 | 3.x 问题 2（REG-ACFUN-004）、10-5 |
| 搜索 | `acfun_search.dart`（`package:html` 选择器），坏卡片整页失败 | `HtmlElement.parseFragment`，坏卡片跳过 | 3.x 问题 3 |
| 详情 | `acfun_api.dart:226-229` 要求 `liveId` 和 `streamName` 同时有，否则报格式错误；没有简介 | `acfun_site.dart:434`、`:461` | 只看 `liveId`；简介取主播签名 |
| 取流 | `acfun_api.dart:279-283` 被拒只作废会话，本次照样失败；`acfun_site.dart:145-146` 未开播返回空列表；`:166-173` 恢复把整个房间重读一遍 | `acfun_site.dart:551-570` | 当次换会话重试；未开播报 `StreamUnavailable`；恢复只请求 `startPlay` |
| 付费直播 | 380205 当成会话被拒，换会话重试后 `RiskControl`，进房失败（5 个请求） | 直播中 + `paid`，取流报 `restricted room (paid)`（3 个请求；已标付费的卡片不发请求） | 统一原则（依据网页脚本） |
| 开播时间 | 不显示 | `createTime`，进房时补 `startPlay` 的 `liveStartTime` | 10-3 |
| 主页链接 | 不认 | 认 | 10-1 |
| 弹幕 | `acfun_site.dart:34` `getDanmaku()` 是 `EmptyDanmaku` | `packages/live_danmaku/lib/src/sites/acfun.dart`（D01.10） | 新增（10-4） |

## 结果

- 首次重构（2026-09-28，提交 `fc70af736`）：12 个 3.x 问题、13 条有意差异见 record.md；没有采用归档 v4 的两处有风险的做法（`level ?? bitrate` 混排、缺 `acSecurity` 就报错）。新增通用的 `HtmlElement.parseFragment`（`html.dart`）和 `&ensp;` 等实体的解码（`json.dart` 的 `decodeHtmlEntities`）。
- 升级落地（2026-09-29，`bd9760d7e`）：10-1 认个人主页；10-2 去掉“全部”；10-3 开播时间；10-4 核对弹幕参数（弹幕在 D01.10）；10-5 按游标取页；付费直播按网页脚本识别；列表跨页去重。付费房进房请求从 5 个（失败）降到 3 个。画质 id、身份、分区都不变，J02.1 不用迁移。
- 界面接上：卡片主播名后“已播 N”（E06.1 第 3 条 c1）；推荐页按游标翻页（I02.1）、分区页游标逐页传递（I03.1）。
- 测试：`packages/live_core/test/sites/acfun_api_test.dart` 40 个 `test(` 写法、`acfun_site_test.dart` 51 个（record.md 按实际用例统计 94 个：43 + 51）、`packages/live_core/test/html_test.dart` 3 个；弹幕 `packages/live_danmaku/test/sites/acfun_test.dart` 38 个。

## 验证

- 自动测试：样本逐键对照 3.x 冻结输出（新键 `startedAt`、`restriction` 单独断言，新增的键只有这两个）；画质混排的顺序（REG-ACFUN-005）、会话被拒重试一次（REG-ACFUN-003）、搜索短页不提前结束（REG-ACFUN-002）、搜索带 UA 和 `Referer`（REG-ACFUN-006）、翻页重读和跨页去重（REG-ACFUN-004）；付费直播用合成答复。
- 真实接口：2026-09-29 直连、匿名只读探测（主页链接 301、“全部”与推荐逐个相同、访客登录和 `startPlay` 仍给 `acSecurity` 和 4 张票据、推荐 26 个和 23 个房间都只有 `paidShowUserBuyStatus: false`），结果没有存成样本。不用代理。
- 真机：没有在 K90 上专门看过（[FEATURES.md](../../../inventory/FEATURES.md) 第 14 节 AcFun 一行“播放：完成”“弹幕：新增”，指样本和探针测过）；E06.1 记录“要在 K90 上看的”第 1 条是推荐页 AcFun 卡片上的“已播 N 分钟”。

## 留下的问题

- 付费直播没有在播样本，`paidShowUuid` 和 380205 的判断来自网页脚本，用合成答复测试；遇到在播的付费直播时补录核对：没有任务管。
- 10-1～10-5（UPGRADES）都已完成，本平台没有“未排”或“受阻”的升级项。
- 搜索结果都是作者（含未开播），搜索页的说明在界面层（I05.1 的搜索能力表）。
- 录制遇到付费直播：详情是直播中、取流报 `StreamUnavailable`，按录制的规则处理（H01.1）。
