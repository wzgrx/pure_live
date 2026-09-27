# 虎牙（huya）平台规格

第 1 阶段草案。只写行为和外部契约，不规定类名和函数拆分。

- 平台 id：`huya`（lib/core/sites.dart:45）。
- 证据写法：`文件:行号` 相对仓库根目录，基于当前 master 检出（c28c17fb）。旧实现文件：`lib/core/site/huya/huya_site.dart`、`huya_transport_policy.dart`、`huya_request_params.dart`、`huya_utils.dart`，`lib/core/danmaku/huya_danmaku.dart`，`lib/pkg/tars/net/base_tars_http.dart`，`lib/player/core/playback_header_resolver.dart`；下文只写文件名。测试写 `huya_play_url_test.dart` 等（都在 `test/`）。审计文档都在 `docs/`，简称：SESSION = HUYA_PLAYBACK_SESSION.md，NATIVE = HUYA_NATIVE_LEASE_FIX_2026_09_05.md，LINEID = HUYA_LINE_IDENTITY_AUDIT_2026_09_05.md，CONT = HUYA_CONTINUITY_AUDIT_2026_09_05.md，REAUDIT = HUYA_REAUDIT_2026_09_06.md。
- 能力：目录（分类、分区房间、推荐）、搜索（只有直播中的房间）、详情、取流（HTTP-FLV 和 HLS；原生签名 FLV 的凭据到期不断开已建立的连接，只预取）、弹幕（含头条留言，即醒目留言）、可选登录 Cookie、录制。
- 全部是纯 Dart：签名只用 md5，协议是 Tars/WUP。不需要 WebView、JS 或原生通道。
- 不提供：主播搜索、单独的开播状态查询。旧实现有，但没有调用方（huya_site.dart:922-956；docs/rewrite/diagnosis/01-sites.md ③-8）。

---

## 1. 房间身份与链接

**规范身份**：房间号 `roomId`，以字符串保存。

**一个房间涉及的各种标识**

| 标识 | 来源 | 用途 | 证据 |
|---|---|---|---|
| 房间号 | 链接路径第一段；列表 `profileRoom`；搜索 `room_id` | 房间身份、详情请求参数、网页链接 | huya_site.dart:221, 585, 728 |
| 主播 UID | 详情 `profileInfo.uid` | 弹幕分组 `live:{uid}`、`chat:{uid}` | huya_site.dart:723-727；huya_danmaku.dart:135-149 |
| 流的主播 UID | `baseSteamInfoList[].lPresenterUid`；缺失时依次用 `profileInfo.uid`、`lChannelId` | 原生 FLV 的签名 UID（第 6.2 节） | huya_site.dart:646-649, 394 |
| topSid / subSid | `baseSteamInfoList[].lChannelId` / `lSubChannelId` | topSid 是头条留言板的 `lPid`；subSid 用于 App 深链 | huya_site.dart:632-637, 1056-1057；room_external_opener.dart:160-169 |
| yyid | 搜索结果 `yyid` | 把搜索里的直播间和主播条目对上 | huya_site.dart:858-868, 901 |

- 旧实现直接用输入值作为详情里的房间号，不做规范化（huya_site.dart:711, 728）。
- 旧实现的 topSid/subSid 取自最后一条匹配上的线路（huya_site.dart:632-637, 665-670）。同一房间各 CDN 的值是否总是相同 [待确认]。

**可接受的输入**

| 形式 | 例 | 处理 | 证据 |
|---|---|---|---|
| 纯数字 | `660000` | 直接作为房间号 | — |
| 房间页 | `https://www.huya.com/660000`、`https://m.huya.com/660000` | 主机是 `huya.com` 或它的任意子域时，取第一个非空路径段 | web_search_room_parser.dart:137-138, 171 |
| 别名 | `https://www.huya.com/abc_1` | 接受 `[A-Za-z0-9_-]+` | web_search_room_parser.dart:138 |

- `huya.com.example` 这类主机不是虎牙（web_search_room_parser.dart:171；huya_transport_policy_test.dart:56-62 对媒体主机做了同样的限制）。
- 以下 [待确认]：别名能否直接请求详情，响应里哪个字段是规范的数字房间号；分享短链、`?roomid=` 查询参数形式、App 分享口令的真实格式。

**归一流程**：去掉空白；拿到详情后，把房间身份换成规范的数字房间号，避免同一房间在关注和历史里出现两份（依赖上面的 [待确认]）。

**外部打开**
- 网页：`https://www.huya.com/{roomId}`（huya_site.dart:728；room_external_opener.dart:163）。
- 网页搜索：`https://www.huya.com/search?hsk={关键词}`（search_controller.dart:121-122）。
- App：`yykiwi://homepage/index.html?banneraction=…channelid={subSid}&subid={subSid}&liveuid={subSid}…`，只在 subSid>0 时提供（room_external_opener.dart:160-169）。旧实现三个参数都填 subSid；channelid 和 liveuid 是否应分别是 topSid 和主播 UID [待确认]。

---

## 2. 目录

### 2.1 分类

- 一级分类固定四个：`1` 网游、`2` 单机、`8` 娱乐、`3` 手游（huya_site.dart:156-161）。
- 二级分区：`GET https://live.cdn.huya.com/liveconfig/game/bussLive?bussType={一级 id}`。`data[]` 里每一项：`gid` 是数字，转成字符串作为分区 id；`gameFullName` 是名称（huya_site.dart:173-194）。
- 分区图标：`https://huyaimg.msstatic.com/cdnimage/game/{gid}-MS.jpg`（huya_site.dart:187）。
- 没有分页，一次返回全部。旧实现串行请求四个一级分类，并忽略分页参数（huya_site.dart:155-168）。v4 可以并发请求；任何一个失败，整体返回相应的 SiteFailure，不返回缺了一块的分类树。
- `gid == 1663`（星秀）在旧实现里有标记（huya_site.dart:703），但全仓没有使用方。v4 不保留 [待确认是否有产品用途]。

### 2.2 分区房间与推荐

- 请求：`GET https://www.huya.com/cache.php?m=LiveList&do=getLiveListByPage&tagAll=0&page={n}`。分区房间另加 `gameId={gid}`（huya_site.dart:198-206, 521-523）。推荐就是不带 `gameId` 的全站列表；排序依据 [待确认]。
- 请求头：移动版 Chrome UA（huya_request_params.dart:5-6）；推荐另加 `Origin`、`Referer: https://www.huya.com/`（huya_site.dart:524-529）。旧实现还带了用户 Cookie。公开列表是否需要 Cookie [待确认]；v4 默认不带。
- 响应 `data.datas[]` 转为房间卡片：

| 卡片字段 | 来源 | 规则 | 证据 |
|---|---|---|---|
| 房间号 | `profileRoom` | | huya_site.dart:221 |
| 标题 | `introduction` | 为空时用 `roomName` | :216-219 |
| 封面 | `screenshot` | 不含 `?` 时追加 `?x-oss-process=style/w338_h190&`，取缩略图 | :212-215 |
| 主播 | `nick`、`avatar180` | | :224, 228 |
| 分区 | `gameFullName` | | :229 |
| 人数 | `totalCount` | 这是热度，不是在线人数（第 4.3 节） | :225-227 |
| 状态 | — | 列表里的都算直播中 | :230-231 |

### 2.3 分页与结束判断

- 页码从 1 开始。
- 旧界面假定服务端每页固定 120 条，在本地切片显示（area_rooms_binding.dart:33-35；popular_controller.dart:69-71）。实际每页条数，以及 `data` 里有没有总页数字段 [待确认]。
- v4 的游标是下一页页码。结束条件：到达服务端给出的总页数，或者 `datas` 为空。不按“条数少于某值”判断（01-sites.md ⑥）。
- 旧推荐把所有异常包成 `Exception(e.toString())`（huya_site.dart:560-562）。v4 按第 9 节分类。

---

## 3. 搜索

- 请求：`GET https://search.cdn.huya.com/?m=Search&do=getSearchContent&q={关键词}&uid=0&v=4&typ=-5&livestate=0&rows={n}&start={偏移}`，不需要特殊请求头（huya_site.dart:871-886）。
- `rows` 限制在 1–50（huya_site.dart:872；4047cfba）；`start = (页码 − 1) × rows`。
- 响应：`response["3"].docs` 是直播间，`response["1"].docs` 是主播（huya_site.dart:889-890）。
- 直播间字段：
  - 封面 `game_screenshot`，缩略图规则同 2.2；
  - 标题 `game_introduction`，为空时用 `game_roomName`；
  - 主播 `game_nick`、头像 `game_imgUrl`；
  - 分区 `gameName`；
  - 热度 `game_total_count`；
  - 另有 `uid`、`yyid`、`room_id`（huya_site.dart:891-918）。
- 房间号：先在主播条目里找 `uid` 和 `yyid` 都相同的一项，用它的 `room_id`；找不到才用直播间条目自己的 `room_id`（huya_site.dart:858-868, 901；6c85c874“修复虎牙搜索”）。两者什么时候不同 [待确认]。
- 只覆盖直播中的房间（search_capability.dart:123 `liveOnly`），结果都标为直播中（huya_site.dart:909-910）。
- 游标是下一个 `start`。结束条件取决于响应里的总数字段（例如 `numFound`）[待确认]。`docs` 为空表示无结果，不是失败。

---

## 4. 房间详情

### 4.1 请求

`GET https://mp.huya.com/cache.php?m=Live&do=profileRoom&roomid={roomId}&showSecret=1&_={毫秒时间戳}`（huya_site.dart:580-604）

- `showSecret=1`：响应里带 AntiCode。
- `_` 参数和 `Cache-Control: no-cache`、`Pragma: no-cache`：绕过接口约 30 秒的公共缓存。不加的话，主播下播后仍可能拿到旧的 `ON`（huya_site.dart:587-590；db7d0df3）。
- 其它请求头：移动版 Chrome UA、`Origin: https://www.huya.com`、`Referer: https://www.huya.com/`、`Sec-Fetch-*`，可选 Cookie（huya_site.dart:592-603）。

### 4.2 字段与直播状态

成功条件：顶层 `status == 200`，并且 `data` 是对象（huya_site.dart:606-607）。

| 详情字段 | 来源 |
|---|---|
| 标题、简介 | `data.liveData.introduction` |
| 封面 | `data.liveData.screenshot` |
| 分区 | `data.liveData.gameFullName`，分区 id 是 `liveData.gid` |
| 主播 | `data.profileInfo.nick`、`avatar180`、`uid` |
| 公告 | `data.welcomeText` |
| 热度 | 见 4.3 |
| 线路、画质 | `data.stream`、`data.liveData.bitRateInfo`（第 5 节） |
| 弹幕参数 | 主播 UID、topSid、subSid（第 1 节） |

证据：huya_site.dart:705-729, 761-786。

直播状态取 `data.liveStatus`，去掉空白后转大写比较（huya_site.dart:608, 751-759；huya_play_url_test.dart:26-40）：

| 值 | 房间状态 |
|---|---|
| `ON` | 直播中 |
| `REPLAY` | 回放（不算直播中） |
| `OFF`、`OFFLINE`、`CLOSED` | 已下播，权威结论 |
| 其它值或缺失 | 未知；不能当作下播 |

- 只有表中明确的下播值，才能让录制停止、让关注标为未开播（huya_site.dart:745-749；233d858d；RECORDING_AUDIT_3_0_13.md:44）。
- 下播时不解析线路，只返回元数据（huya_site.dart:609-611, 761-786）。
- `ON` 但没有 `data.stream`：旧实现在录制路径抛格式错误（huya_site.dart:731-733），在普通路径退回播放器里上一次的房间（:734-741；01-sites.md ② 要求去掉）。v4 返回 StreamUnavailable。这种情况实际是否出现，`REPLAY` 是否带 `stream`、能否播放 [待确认]。
- 请求失败、`status ≠ 200`、结构缺失都必须作为失败传出去，不能返回“状态未知的房间”（01-sites.md ③-1）。映射见第 9 节。

### 4.3 人数字段的含义

虎牙的公开接口不提供同时在线人数，下面这些**全部是热度**：

- 详情 `liveData.totalCount` 和 `userCount`：实测两者相同，都是几百万量级的热度值。取 `totalCount`，为空时退回 `userCount`；在线人数留空（huya_site.dart:142-152；huya_audience_metric_test.dart:6-18；879813f5、125e61d2）。
- 列表的 `totalCount`、搜索的 `game_total_count`（huya_site.dart:225-227, 912-914）。
- 弹幕 URI 8006 的 `iAttendeeCount`：实测和列表热度在同一量级，按热度处理（huya_danmaku.dart:207-220；huya_danmaku_protocol_test.dart:63-88）。

界面文案必须写“热度”，不能写“在线”或“观看人数”。

---

## 5. 画质与线路

### 5.1 画质

- 来源：`data.liveData.bitRateInfo`，可能是 JSON 字符串，也可能是数组。解析失败或缺失时用 `data.stream.flv.rateArray`（huya_site.dart:689-702）。
- 每一项有 `sDisplayName`（名称）和 `iBitRate`（kbps）。名称为空或码率为负的丢弃；同一码率只保留第一个（huya_site.dart:788-800）。
- 列表为空时只提供一个“原画”（码率 0），不自己编造其它档位（huya_site.dart:246-252；huya_play_url_test.dart:537-544；cafdf384）。
- 排序：码率 0（原画）在最前，其余按码率降序（huya_site.dart:268, 273）。
- 选择 id 就是码率，刷新前后保持稳定（huya_play_url_test.dart:517-535）。
- 所有画质共用同一组线路，画质只体现在查询参数 `ratio` 上：
  - 码率 > 0：写入 `ratio={码率}`，替换已有的值；
  - 原画：删除 `ratio`。
  - 证据：huya_site.dart:440-444；huya_play_url_test.dart:86-114。
- 画质确认：虎牙不回报实际画质，StreamLine 的画质一律记为“已请求、未确认”（LINEID 的验证记录明确写“请求码率，不冒充实际平均码率”）。
- `codec`：模板里没有就追加 `codec=264`，已有则保留（huya_site.dart:439；huya_play_url_test.dart:86-101）。实测所有画质都是 AVC（PLATFORM_PROBE_2026_09_25.md:87）。

### 5.2 线路

- 线路来自 `data.stream.flv.multiLine[]` 和 `data.stream.hls.multiLine[]` 中 `url` 非空的项。用 `multiLine[].cdnType` 对应 `baseSteamInfoList[].sCdnType`，取出：
  - 基址 `sFlvUrl` / `sHlsUrl`；
  - 流名 `sStreamName`；
  - `sFlvAntiCode`、`sHlsAntiCode`；
  - `lPresenterUid`、`lChannelId`、`lSubChannelId`。
  - 证据：huya_site.dart:620-688。
- 不在 `multiLine` 里的 `baseSteamInfoList` 项不列出，例如优先级为 −1 的 AL13（SESSION §11）。
- 顺序保留服务端给出的顺序。旧实现先列全部 FLV，再列全部 HLS（huya_site.dart:624-688）。不因平台不同就擅自改成 HLS 优先（SESSION §2 第 7 条）。
- 已观测到的 CDN：AL、TX、HS、TX15、HS24，每个都同时提供 FLV 和 HLS（SESSION §11）。
- 媒体地址：`{基址}/{sStreamName}.{flv 或 m3u8}?{签名后的 AntiCode}`（huya_site.dart:437-445）。
- 基址是 `http://` 并且主机属于 `huya.com` 时改成 `https://`；其它主机不改（huya_site.dart:510-516；huya_play_url_test.dart:81-84）。

### 5.3 线路身份与回退顺序

**线路身份 = CDN 主机（含端口）+ 格式（`.flv` / `.m3u8`）+ 凭据类型**，不是列表下标（huya_transport_policy.dart:5-50；4df2f98d；LINEID）。

凭据类型：
- **原生签名 FLV**：主机属于 `huya.com`，路径以 `.flv` 结尾，并且 `ctype=huya_pc_exe`、`t=100`（huya_transport_policy.dart:71-78）。
- **网页 FLV**：其余虎牙 `.flv`。
- **HLS**：`.m3u8`。

StreamLine 的 `cdnId` 取服务端的 `cdnType`（如 `AL`），同时保存主机。比较时用“主机 + 端口 + 格式 + 凭据类型”。路径（含流名）只用于第一轮精确匹配；主播重新开播会换流名，此时仍按 CDN 匹配（huya_transport_policy.dart:39-42）。

刷新后选线（huya_transport_policy.dart:5-50；huya_transport_policy_test.dart:8-75）：
1. 候选池依次是：原生 FLV（仅当原来就是原生 FLV）→ 同格式 → 全部。
2. 在池内先找“同 CDN、同凭据类型、同路径”，再找“同 CDN、同凭据类型”。
3. 不换线时返回匹配项；池里找不到就取池中第一项。
4. 换线（当前线路失败）时取匹配项的下一项，循环；池里只剩这一条时，退到下一个更宽的池。
5. 当前地址不是虎牙地址时，不做身份匹配。

回退顺序：原生 FLV（先同 CDN，再其它 CDN）→ 网页 FLV → HLS。用户选了 HLS 就保持 HLS；HLS 失败后可以换到原生 FLV（huya_transport_policy_test.dart:26-48）。

其它规则：
- 取流时各线路并行签名。一条失败只丢这一条，其它照常返回；结果去重（huya_site.dart:285-305；huya_play_url_test.dart:171-198）。
- 录制、按线路恢复时只签选中的那一条（huya_site.dart:338-359；huya_play_url_test.dart:546-573）。

---

## 6. 取流

### 6.1 总流程

每次“打开”都要走完整流程：首播、换画质、换线路、恢复、录制、续期都算一次打开。

1. 重新请求详情。恢复和续期也必须重新请求，不能复用缓存的地址（huya_site.dart:308-336；SESSION §5）。已下播则不返回线路。
2. 按格式为每条线路取凭据：
   - FLV：先取原生 WUP 凭据（6.2）；失败或者拿到时已过期，走网页后备（6.3）。
   - HLS：只用 `sHlsAntiCode`，**绝不**使用 FLV 凭据（huya_site.dart:377-381；huya_play_url_test.dart:69-79）。
3. 用各自的身份签名（6.4），拼出地址，附上请求头（6.5）和租期（6.6）。

### 6.2 原生 WUP 凭据（FLV 首选）

**传输**（base_tars_http.dart:46-107；huya_site.dart:1162-1184）
- `POST https://wup.huya.com`，`Content-Type: application/x-wup`。
- Tars TUP3 封包：requestId=0，servant `liveui`，函数 `getCdnTokenInfoEx`，参数键 `tReq`。
- 响应：键 `""` 是返回码，必须为 0；键 `tRsp` 是结果。
- HTTP 头：`Origin: https://www.huya.com`、`Referer: https://www.huya.com/`、`User-Agent: {HYSDK UA}`（huya_site.dart:1171-1175）。
- 超时：连接、发送、接收各 6 秒，整次 8 秒。每次请求用自己的连接，结束后关闭（huya_site.dart:1162-1184；huya_play_url_test.dart:11-24）。

**请求体 `GetCdnTokenExReq`**（tag：0 sFlvUrl、1 sStreamName、2 iLoopTime、3 tId、4 iAppId；lib/core/tars/get_cdn_token_ex_req.dart:8-31）

| 字段 | 值 |
|---|---|
| sFlvUrl | `""` |
| sStreamName | 线路流名 |
| iLoopTime | 0 |
| iAppId | 66 |
| tId | 见下 |

tId 是 `HuyaUserId`（tag：0 lUid、1 sGuid、2 sToken、3 sHuYaUA、4 sCookie、5 iTokenType、6 sDeviceInfo、7 sQIMEI；lib/core/tars/types.dart:6-37）。原生请求里 `lUid=0`、`sHuYaUA=pc_exe&7060000&official`，其余为空或 0。**不带 Cookie，不带观众 UID**（huya_site.dart:1157-1160；huya_play_url_test.dart:307-316）。

**响应 `GetCdnTokenExResp`**（lib/core/tars/get_cdn_token_ex_resp.dart）
- tag0 `sFlvToken`：AntiCode 模板，实测含 `wsTime`、`fm`、`ctype=huya_pc_exe`、`t=100`（NATIVE；huya_play_url_test.dart:331-339）。完整字段表 [待确认]。
- tag1 `iExpireTime`：实测为 300（NATIVE）。
- `sFlvToken` 为空，或没有合法的 `wsTime`，都算失败（huya_site.dart:1293-1298）。

**并发与缓存**：同一流名同一时刻只发一个请求，并发的打开共享结果；**不缓存**，每个使用者各自签名（huya_site.dart:1143-1155）。

**签名 UID**：用线路的主播 UID（见第 1 节的取值链）；只有它缺失时才用观众 UID（huya_site.dart:394）。NATIVE 说明，A/B 对照比较的是“原生取凭据 + 对应签名 UID”的整套契约，没有逐个字段隔离实验，所以“必须用主播 UID”这一点 [待确认]。

**与网页身份隔离**：原生契约的 UID、tId 不能和网页后备的观众身份、Cookie 混用（huya_site.dart:430-431；SESSION 开头的说明）。

### 6.3 网页后备（仅 FLV）

原生失败时按下面顺序处理（huya_site.dart:402-435）：

1. 房间的 `sFlvAntiCode` 不含 `fm=`：视为旧式静态令牌，原样使用。
2. 含 `fm=`：用观众身份（第 8 节）签名。
3. 签名失败（模板过期或结构不对）：用观众身份请求网页版 `getCdnTokenInfoEx`（huya_site.dart:1186-1247；huya_play_url_test.dart:255-285）：
   - `sFlvUrl` = 该线路的 https 基址，`sStreamName` = 流名，`iLoopTime=0`，`iAppId=66`；
   - tId：`lUid` = 观众 UID，`sGuid` = 本实例的 32 位随机十六进制串，`sToken=""`，`sHuYaUA=webh5&0.1.0&websocket`，`sCookie` = 用户 Cookie，`iTokenType=0`；
   - HTTP 头用移动版 Chrome UA，并带 Cookie；
   - 只合并“同一观众、同一线路、同一流名”的并发请求（huya_site.dart:1187）；
   - 返回的 `sFlvToken` 含 `fm` 时，再用观众身份签名。
4. 仍然拿不到令牌：这条线路失败（huya_site.dart:426-429）。

页面外层的 `hyPlayerConfig.vappid=10057` 不是 iAppId。iAppId 固定 66，iLoopTime 固定 0（SESSION §1）。

### 6.4 AntiCode 签名

输入：服务端 AntiCode 查询串、流名、签名 UID、当前时刻（huya_site.dart:1065-1141）。

1. 解析查询串。`fm` 为空时原样返回（已经签好的，或旧式令牌）。
2. `ctype` 缺省为 `huya_webh5`，`t` 缺省为 `100`；`t=103` 是 WAP 形式（huya_site.dart:1072-1074；huya_play_url_test.dart:209-218）。
3. `wsTime` 是十六进制秒。缺失或非法 → 失败；当前时刻 > wsTime + 300 秒 → 失败（凭据已过期）。**不在本地延长 wsTime**，输出时原样保留（huya_site.dart:1082-1090；huya_play_url_test.dart:116-135, 220-234）。
4. `seqid = UID + 当前毫秒`。同一进程内，每次签名用的毫秒值严格递增，保证同时打开的播放和录制拿到不同的 seqid 和 wsSecret（huya_site.dart:1076-1078, 1091；huya_play_url_test.dart:318-329；8a6fdce1）。
5. `hash = md5("{seqid}|{ctype}|{t}")`（huya_site.dart:1092）。
6. `u = rotl64(UID)`：只把低 32 位循环左移 8 位，高 32 位不变（huya_site.dart:1249-1261；huya_play_url_test.dart:200-207）。非 WAP 在模板里用 u，WAP 用原 UID。
7. `fm` 先做 URL 解码，再做 base64 解码，得到模板。模板必须同时含 `$0 $1 $2 $3`，否则失败。在**完整模板**上依次替换第一次出现的 `$0` = UID 或 u、`$1` = 流名、`$2` = hash、`$3` = 原样的 wsTime；不假设分隔符和字段顺序（huya_site.dart:1096-1110；huya_play_url_test.dart:137-169）。
8. `wsSecret = md5(替换后的模板)`。
9. 输出：保留原参数，删掉 `wsSecret seqid u uid uuid fm`，再写入 `wsSecret`、`wsTime`、`seqid`、`ctype`、`ver=1`、`fs`（原值，缺省 `bgct`）、`t`。非 WAP 写 `u`；WAP 写 `uid` 和随机 `uuid`（huya_site.dart:1113-1140）。最终地址里不能有 `fm`。
10. 最后按 5.1 处理 `codec` 和 `ratio`。

`launch.wsTimeSync` 返回的时间只用于统计延迟，不能当作签名时钟（SESSION §8）。

### 6.5 请求头与 HYSDK UA 的来源

**媒体请求头**（播放和录制相同；playback_header_resolver.dart:71-83）
- `User-Agent: HYSDK(Windows,30000002)_APP(pc_exe&7090000&official)_SDK(trans&2.35.0.5996)`（huya_request_params.dart:18）
- `Origin: https://www.huya.com`
- `Referer: https://www.huya.com/{roomId}`
- 旧实现还带用户 Cookie。CDN 是否需要 [待确认]；v4 默认不给 CDN 发 Cookie。
- 网页 FLV 和 HLS 是否应改用浏览器 UA [待确认]。旧实现对所有虎牙媒体都用 HYSDK UA；冷启动时曾因原生地址配了浏览器 UA 而修正（8a6fdce1；NATIVE“修复设计”第 6 条；playback_header_resolver_test.dart:14-26）。

**UA 的来源**
- 旧：启动时从上游仓库 `liuchuancong/pure_live` master 分支的 `assets/play_config.json` 读取 `huya.user_agent`，经 raw.githubusercontent 和十几个第三方 GitHub 代理竞速下载，写进进程级变量；失败或为空时用内置常量（huya_site.dart:361-372；lib/common/utils/githup_mirror.dart:1-60；startup_controller.dart:46-51）。
  - 远端值目前和内置常量相同（assets/play_config.json）。
  - 远端值只影响媒体请求头（playback_header_resolver.dart:75）；WUP 请求一直用常量（huya_site.dart:1174），两边可能不一致。
- v4：
  - 把 HYSDK UA、原生 tId 串 `pc_exe&7060000&official`、网页 tId 串 `webh5&0.1.0&websocket`、iAppId 66 作为一组“虎牙客户端身份”，随适配器一起发布。
  - 运行时覆盖只能来自本项目自有并签名的规则包（PLAN 05“规则热更新”）；不访问上游仓库，也不访问第三方镜像。
  - 同一次取流中，WUP 请求和媒体请求使用同一份值。
- HTTP UA 里是 `7090000`，tId 里是 `7060000`，两者是否需要一致 [待确认]。

### 6.6 租期

| 家族 | 识别 | issuedAt | refreshAt | invalidAt | cutsConnection |
|---|---|---|---|---|---|
| 原生签名 FLV | 5.3 的原生条件 | 签名时刻 | invalidAt − 30 s | min(wsTime + 300 s，iExpireTime 给出的上界) | **false** |
| 网页 FLV（含旧式静态令牌） | 虎牙主机、`.flv`、不是原生 | 从地址还原：`seqid − UID`（非 WAP 先把 `u` 反旋转，WAP 用 `uid`）；没有 seqid 时用构造地址的时刻 | min(issuedAt + 100 s，wsTime + 270 s，网页 WUP 的 refreshAt) | min(issuedAt + 125 s，wsTime + 300 s，网页 WUP 的 invalidAt) | true |
| HLS | 虎牙主机、`.m3u8` | 同上 | 同上 | 同上 | true |

证据：huya_site.dart:57-58, 60-99, 112-129, 446-452, 1293-1319；huya_transport_policy.dart:60-78；huya_play_url_test.dart:376-485。

**iExpireTime 的解释**：大于 10¹² 是毫秒时间戳，大于 10⁹ 是秒时间戳，否则是相对秒数。只有它早于 wsTime + 300 s 时才收紧 invalidAt（huya_site.dart:1300-1318；huya_play_url_test.dart:376-402）。

**网页家族为什么是 100/125 秒**
- 同一个匿名签名 FLV 约 121 秒 EOF；同一个签名 HLS 的播放列表约 130 秒后开始返回 403；三轮 FLV/HLS 都在签发后 129–132 秒结束，而这时 wsTime 还有将近一天（CONT“外部接口证据”；SESSION §7、§8）。
- 这是观测推断，不是虎牙公开的承诺。

**租期从签发时刻算，不从打开时刻算**
- 签发 90 秒后才打开的同一个地址，只活了 20 秒；同一地址并发打开两次，分别只有 80 秒和 40 秒（SESSION §12）。
- 所以网页地址不能用于第二条连接；issuedAt 也不能随“什么时候读取元数据”而漂移（huya_site.dart:107-129；huya_play_url_test.dart:450-461）。
- 没有 seqid 的旧式令牌，按构造地址的时刻计（huya_site.dart:446-451；huya_play_url_test.dart:463-485）。

**原生签名 FLV：凭据只限制新建连接**
- 同条件对照：原生地址在 AL、TX 两个 CDN 上都连续读到 420 秒（测试主动停止）；网页地址 120.8 秒 EOF（NATIVE 同条件探测表）。
- 到 refreshAt 时只预取下一份地址，不重开正在正常播放或录制的连接。
- 真正发生 EOF 或错误时：预取的地址还没过 invalidAt 就用它重连，否则重新取流。
- 证据：huya_transport_policy.dart:60-69；recorder_controller.dart:1075-1078, 1146-1155；player_manager.dart:4171-4185, 4568-4576；8a6fdce1、d6d4123c；HUYA_RECORDER_LEASE_AUDIT_2026_09_05.md §1。

**其它**
- 虎牙 FLV 不走斗鱼式的关键帧拼接（flv_splice_relay_test.dart:204）。网页家族到期后是“新建连接并接管”，播放层怎么做无缝接管由播放规格规定（旧 Windows 实现在网页家族上提前到 40 秒就开始预热：player_manager.dart:307, 4568-4576）。
- 录制：原生 FLV 不需要按租期切段；网页 FLV 和 HLS 需要按租期换连接。

### 6.7 其它规则

- 签名地址、Cookie、UID、令牌都不能写进日志，也不能持久化。诊断只记主机、协议、CDN 类型和码率（huya_site.dart:1366-1370；huya_play_url_test.dart:487-499；SESSION §8、§11）。
- HLS 对 Range 请求返回 206 是正常的分段响应，不算线路失败（SESSION §11）。
- 判断拿到了媒体，要看首字节：FLV 以 `FLV` 开头，HLS 以 `#EXTM3U` 开头。HTTP 200 或播放器 open 成功，都不等于能出画面（SESSION §6、§10）。

---

## 7. 弹幕

### 7.1 连接

- 地址：`wss://wsapi.huya.com`，二进制帧（huya_danmaku.dart:73）。旧地址 `cdnws.api.huya.com` 已废弃（125e61d2）。
- 探针握手带 `Origin: https://www.huya.com`（tool/huya_danmaku_probe.py:108-117），应用本身没带。是否必须 [待确认]。
- 需要的参数：主播 UID（`profileInfo.uid`）；另外用 topSid 拉头条留言。
- 主播 UID ≤ 0 时不建立连接 [待确认；旧实现会注册 `live:0`]。
- 每次连接就绪（包括重连之后）都重新注册分组，并立即发一次心跳（huya_danmaku.dart:105-112）。

### 7.2 编码

外层帧是一个 Tars 结构：tag0 int 命令号，tag1 bytes 负载（huya_danmaku.dart:77-83, 135-149, 171-186）。

| 方向 | 命令号 | 负载 |
|---|---|---|
| 客户端 → 服务端 | 16 注册分组 | Tars 结构：tag0 `list<string>` = [`live:{主播UID}`, `chat:{主播UID}`]，tag1 string = `""` |
| 客户端 → 服务端 | 20 心跳 | 空 bytes |
| 服务端 → 客户端 | 7 单条推送 | tag0 pushType、tag1 uri、tag2 bytes 消息体、tag3 protocolType |
| 服务端 → 客户端 | 22 分组推送 | tag0 string 分组 id；tag1 列表，每项：tag0 uri、tag1 bytes 消息体、tag2 long 消息 id |

其它命令忽略。

### 7.3 心跳

- 连接就绪时立即发一次，之后每 60 秒一次（huya_danmaku.dart:48-49, 110-115；huya_danmaku_protocol_test.dart:44-50）。
- 超过 max(3 × 心跳间隔, 90 秒) = 180 秒没有收到任何消息，视为断线并重连（lib/core/common/web_socket_util.dart:253-258）。
- 旧的 `OnUserHeartBeat` 长包已经不能维持订阅（125e61d2）。

### 7.4 消息类型

| uri | 含义 | 消息体 | 输出 |
|---|---|---|---|
| 1400 | 聊天 | tag0 发送者（tag0 uid、tag2 昵称、tag3 性别）；tag3 内容；tag6 格式（tag0 颜色、tag1 字号、tag2 速度、tag3 过渡方式） | 聊天事件；颜色 ≤ 0 时用白色（huya_danmaku.dart:193-206, 389-470） |
| 8006 | 热度 | tag0 `iAttendeeCount` | 热度更新，不是在线人数（:207-220） |
| 2001314 | 头条留言（醒目留言）通知 | 不需要解码 | 后台拉取留言板（7.5） |
| 其它 | — | — | 忽略。礼物、进场、贵宾席等是否需要 [待确认] |

- 分组推送里每条消息的 id 记为 `huya:{消息 id}`，用来去重（huya_danmaku.dart:184, 204, 218）。
- 旧实现读发送者时，把 `lMid` 也从 tag0 读（huya_danmaku.dart:398），这是错的，v4 不沿用。正确的 tag [待确认]。

### 7.5 头条留言

**请求**（huya_utils.dart:18-47；lib/core/tars/get_game_event_message_board_req.dart:16-20）
- WUP `POST https://wup.huya.com`，servant `wupui`，函数 `getHeadLineMessageBoard`。
- 请求体：tag0 `lPid` = topSid，tag1 sOffset，tag2 tId（`sHuYaUA` = HYSDK UA），tag3 `iMessageBoardScope=0`，tag4 `iPageSize=10`。
- HTTP 头：`Origin`、`Referer: https://www.huya.com`，HYSDK UA。
- 超时：连接、发送、接收各 2 秒，整次 3 秒；每次用自己的连接并关闭（huya_utils.dart:18-25, 44-52；huya_message_board_test.dart；4aefaa04）。

**响应**：面板的 tag1 是列表，每项 tag0 用户（tag1 昵称、tag2 头像）、tag1 内容、tag2 iCost、tag4 iTotalSec、tag5 iCountDown、tag9 lMessageId、tag12 iCostPay（lib/core/tars/game_event_message_board_info.dart:20-26）。

**解析规则**（huya_utils.dart:55-97）
- 内容为空，或剩余秒数 ≤ 0，丢弃。剩余秒数取 iCountDown，没有时取 iTotalSec。
- 价格 = iCost；iCost ≤ 0 时用 max(1, round(iCostPay / 100))。
- 结束时间 = 当前 + 剩余秒数；开始时间 = 结束时间 − 总时长。
- id = `huya:{lMessageId}`。

**拉取时机**
- 通知到达时留言板可能还没更新。在后台按 0、0.6、1.8、4 秒做有限次重试，不阻塞弹幕解码；已有基线后只要出现新条目就停止重试（huya_danmaku.dart:34-39, 221-295；huya_danmaku_protocol_test.dart:90-137）。
- 按消息 id 去重，最多记 512 条；内容相同但 id 不同的是两条（huya_danmaku.dart:43-44, 289-295；huya_danmaku_protocol_test.dart:139-176；398d182d、13d4d409）。
- 进房时拉一次全量（huya_site.dart:1051-1060；live_play_controller.dart:315-319, 721）。旧实现为此又请求了一次详情，v4 直接用已有详情里的 topSid。

### 7.6 丢弃跨房间消息

- 以连接会话为界：切房、停止或重新开始后，上一会话的帧、重连回调、还没返回的留言板结果全部丢弃（huya_danmaku.dart:86-127, 156-169, 253-260；huya_danmaku_protocol_test.dart:178-209）。
- 命令 22 带分组 id。v4 只接受分组 id 等于本连接注册的 `live:{UID}` 或 `chat:{UID}` 的条目，其余丢弃。旧实现读了分组 id 但没有校验（huya_danmaku.dart:341）。06-tests.md:57 说测试覆盖了“丢弃跨房间消息”，实际只覆盖了会话隔离。服务端实际的分组 id 取值 [待确认]；测试夹具用的是 `live:2272316519`（huya_danmaku_protocol_test.dart:28-29）。
- 命令 7 不带分组信息，只能靠会话隔离。

---

## 8. 登录与 Cookie

**登录方式**
- 用户从浏览器复制整段 Cookie 粘贴进来（huya_cookie_controller.dart:13-17；assets/translations/zh.json:327-328）。
- 旧实现只要 Cookie 非空就显示“已登录”，不检查是否有效（account_page.dart:48）。能用来校验登录状态的接口 [待确认]。

**yyuid**：只从 Cookie 中精确的 `yyuid=数字` 字段读取（`foo=yyuid=12` 不算），值 > 0 才有效（huya_site.dart:1029-1034；huya_play_url_test.dart:236-240）。

**观众身份**（只用于网页后备的签名和网页 WUP 的 tId）
1. Cookie 里有 yyuid → 账号身份。
2. 否则匿名登录：`POST https://udblgn.huya.com/web/anonymousLogin`，JSON `{"appId":5002,"byPass":3,"context":"","version":"2.4","data":{}}`，取 `data.uid`。请求头用移动版 Chrome UA、`Origin`/`Referer: https://www.huya.com/`、`Sec-Fetch-*`（huya_site.dart:958-974）。成功后在本实例内缓存；并发请求合并（huya_site.dart:981-1012）。
3. 匿名登录失败：本次使用本地临时 UID，取值为 1400000000000 加上 [0, 10¹¹) 内的均匀随机数。**临时 UID 不缓存**，下一次取流重新请求官方匿名身份（huya_site.dart:997-1006, 1042-1049；huya_play_url_test.dart:242-253）。
4. GUID：每个适配器实例一个 32 位随机十六进制串（huya_site.dart:1036-1040）。

**其它规则**
- `lPresenterUid` 是主播，不能当作观众身份（huya_site.dart:976-980；SESSION §2 第 1 条）。
- 原生 FLV 不使用观众身份，也不使用 Cookie（6.2）。
- 登录不能免除签名续期、短连接或换线；账号和匿名的签名、线路、连接生命周期完全相同（SESSION §8、§12）。
- 旧实现把 Cookie 发给详情、列表、网页 WUP 和媒体请求（huya_site.dart:207, 526, 600, 821, 1203-1209；playback_header_resolver.dart:76-82）。v4：Cookie 由 CredentialStore 加密保存；网页 WUP 必须带；其它请求是否需要 [待确认]，确认前不带。

---

## 9. 错误与风控

| 场景 | 旧行为 | v4 |
|---|---|---|
| 连接、DNS、TLS 失败或超时（HTTP、WUP、WebSocket） | 各处抛通用异常 | Network |
| 用户取消 | 没有统一的取消 | Cancelled；取消只关闭自己的请求 |
| 详情 `status ≠ 200` 或 `data` 缺失 | 录制路径抛 FormatException；普通路径退回旧房间（huya_site.dart:731-741, 828-830） | 房间不存在 → NotFound（响应特征 [待确认]）；其余 → ApiChanged |
| `liveStatus` 是 OFF/OFFLINE/CLOSED | 返回下播房间 | 房间状态“下播”，不是失败 |
| `liveStatus` 是 REPLAY | 标为回放 | 房间状态“回放”，不是失败 |
| `liveStatus` 是其它值 | 状态未知 | 房间状态“未知”；既不是失败，也不是下播 |
| `ON` 但没有 `stream`，或者一条可用线路都没有 | 抛错或返回空列表（huya_site.dart:731-733, 301-305） | StreamUnavailable |
| 单条线路签名失败：模板缺占位符、没有 wsTime、`sFlvToken` 为空、Tars 解码失败、WUP 返回码 ≠ 0 | 丢弃这条线路（huya_site.dart:291-300） | 只丢这一条。全部失败时：原因属于结构问题 → ApiChanged；否则 → StreamUnavailable |
| AntiCode 已过期 | 抛 StateError，走后备（huya_site.dart:1087-1089） | 重新取详情再签；仍然过期 → ApiChanged。是否可能是本机时钟偏差 [待确认] |
| 原生 WUP 失败 | 回退网页（huya_site.dart:398-400） | 不上报，回退网页，记一次诊断计数 |
| 匿名登录失败 | 用临时 UID | 不上报，标记为降级 |
| CDN 对新签名地址返回 403 | 播放器重新签名或换线 | 同一线路重新取流签名一次，再按 5.3 换线；全部失败 → StreamUnavailable。能否区分出风控或 IP 限制（RiskControl）[待确认] |
| CDN 返回 404 | 播放器恢复 | 重新取详情：已下播 → 房间状态；否则 → StreamUnavailable |
| 连续请求多个房间详情时失败（#846） | 关注刷新限制为 4 路并发（ISSUE_AUDIT_2026_09_05.md:15） | 限流信号 [待确认]，确认后映射为 RateLimited |
| 需要登录、地区限制、年龄或付费 | 没有见到 | 暂不产生 NeedLogin、RegionRestricted、AgeOrPaid。密码房、付费房是否存在 [待确认] |
| 列表或搜索的结构缺失 | 抛异常，或 `Exception(e.toString())` | ApiChanged；结果为空时返回空页，不算失败 |
| 弹幕连接失败或断开 | 回调里传中文句子（huya_danmaku.dart:119, 124） | 通过连接状态流报告，不返回文案 |
| 头条留言拉取失败 | 最后一次重试时记日志（huya_danmaku.dart:281-285） | 静默；不影响弹幕连接 |

---

## 10. 踩过的坑

| 编号 | 现象 | 根因 | 正确做法 | 证据 |
|---|---|---|---|---|
| REG-HUYA-001 | FLV 播放约 2 分钟 EOF，Windows 黑屏或短暂停顿；换 HLS 也一样 | 网页模板签出的地址受 CDN 短会话限制（签发后约 2 分钟），和 wsTime 无关 | FLV 首选原生 WUP 凭据；网页后备按 100/125 s 租期、cutsConnection=true 主动接管 | 8a6fdce1；NATIVE 同条件探测表；CONT；SESSION §7-§8；huya_play_url_test.dart:331-362 |
| REG-HUYA-002 | 正常播放的原生 FLV 被定时重开（Windows 每 40 秒换播放器，录制到 refreshAt 就取消输入），带来卡顿和交接开销 | 把“新建连接的凭据期限”当成了“已建立连接的截止时间”；对所有虎牙地址套用短租约 | 原生 FLV cutsConnection=false，到期只预取；只有网页 FLV 和 HLS 保留主动接管 | 8a6fdce1、d6d4123c；huya_transport_policy.dart:60-78；huya_transport_policy_test.dart:102-118；HUYA_RECORDER_LEASE_AUDIT_2026_09_05.md §1；REAUDIT |
| REG-HUYA-003 | 房间 AntiCode 为空或已签好时，没走原生路径，直接失败或落回短连接 | 只有网页模板含 `fm` 时才去取原生凭据；而原生请求只需要流名 | 所有 FLV 线路都先尝试原生，失败才回退网页 | d6d4123c；REAUDIT；huya_play_url_test.dart:331-362 |
| REG-HUYA-004 | 签名失效，CDN 拒绝 | 在本地延长 wsTime（上游曾延长一天） | wsTime 原样保留；过期就重新取详情和凭据 | huya_site.dart:1062-1090；SESSION §1、§2；huya_play_url_test.dart:116-135, 220-234 |
| REG-HUYA-005 | 模板一变就签出错误的 wsSecret（表现为 403） | 假设 `fm` 是 `prefix_$0_$1_$2_$3`，按下划线拆开再拼 | 在完整模板上替换四个占位符；缺占位符在打开 CDN 之前就判失败；最终地址去掉 `fm` | db7d0df3；SESSION §10；huya_site.dart:1096-1124；huya_play_url_test.dart:137-169 |
| REG-HUYA-006 | 部分房间的 HLS 或 FLV 签名失效 | 原生接口只返回 `sFlvToken`，上游把它同时用于 HLS；旧本地代码从 HLS AntiCode 起步，FLV 的 WUP 失败时误用了它。服务端可以按 CDN 和协议分别滚动令牌，两者相同只是巧合 | FLV 用 `sFlvAntiCode` 或原生 `sFlvToken`；HLS 只用 `sHlsAntiCode` | huya_site.dart:377-381；SESSION §7（上游审查第 3 条）、§10；huya_play_url_test.dart:59-79 |
| REG-HUYA-007 | 同一地址晚打开或并发打开时，连接明显更短；同一毫秒签名的播放和录制拿到相同地址 | CDN 会话从签发起算，并和 seqid 绑定 | 每次打开生成新 seqid（进程内毫秒严格递增）；网页地址不用于第二条连接 | 8a6fdce1；SESSION §12；huya_site.dart:1076-1078；huya_play_url_test.dart:318-329 |
| REG-HUYA-008 | FLV 首次连接 403，Windows 延迟回退到 HLS，表现为先黑屏 | rotl64 只返回旋转后的低 32 位；匿名 UID 超过 2³²，`u` 和 WUP 身份对不上 | 只旋转低 32 位，保留高 32 位 | db7d0df3；SESSION §1；huya_site.dart:1249-1261；huya_play_url_test.dart:200-207 |
| REG-HUYA-009 | 网页签名的身份和官方不一致 | 把 `lPresenterUid`（上游实际填的是 topSid）当观众身份用于网页签名 | 网页路径只用 yyuid 或匿名 UID；原生路径有自己的契约，两者不能混用 | SESSION §1、§2、§7；huya_site.dart:430-431, 976-980 |
| REG-HUYA-010 | 刷新或恢复后跳到别的线路（如 TX FLV 变成 TX HLS），或跳过健康的 FLV | 新列表会重排、过滤掉失败项，旧下标失去意义 | 按 CDN 主机、格式、凭据类型匹配（5.3） | 4df2f98d；LINEID“新错误的第一发生点”；huya_transport_policy.dart:5-50；huya_transport_policy_test.dart |
| REG-HUYA-011 | 起播和换画质慢得像卡住；一个 CDN 模板异常导致整个房间没有源 | 逐条串行取令牌；异常没有按线路隔离 | 并行签名、按线路隔离失败、保留服务端顺序 | db7d0df3；huya_site.dart:285-305；huya_play_url_test.dart:171-198 |
| REG-HUYA-012 | 换画质后还是旧画质；选原画拿到的却是转码 | 沿用了页面抓取时带的 `ratio` | 码率 > 0 替换 `ratio`，原画删除 `ratio` | cafdf384；huya_site.dart:440-444；huya_play_url_test.dart:86-114 |
| REG-HUYA-013 | 出现并不存在的“高清 2000”，切过去画面不变 | 没有画质列表时自造了 2000 kbps 一档 | 只列服务端给出的码率；为空时只给原画 | cafdf384；huya_site.dart:246-252；huya_play_url_test.dart:537-544 |
| REG-HUYA-014 | 显示几百万“在线” | `userCount`、`totalCount`、8006 的 `iAttendeeCount` 都是热度 | 统一标为热度，在线人数留空 | 879813f5、125e61d2；huya_site.dart:142-152；huya_danmaku.dart:207-220；huya_audience_metric_test.dart；huya_danmaku_protocol_test.dart:63-88 |
| REG-HUYA-015 | 详情请求失败时录制被停止，关注被误标为未开播 | 请求失败返回了“未开播”房间，或被当成下播 | 只有 OFF/OFFLINE/CLOSED 是下播；未知状态和请求失败都不是 | 233d858d；huya_site.dart:745-759；huya_play_url_test.dart:26-40；RECORDING_AUDIT_3_0_13.md:44 |
| REG-HUYA-016 | 主播下播后，进房或刷新仍显示直播中 | `profileRoom` 有约 30 秒公共缓存 | 带毫秒时间戳参数 `_` 和 no-cache 请求头 | db7d0df3；huya_site.dart:587-590 |
| REG-HUYA-017 | 一次网络抖动之后一直 403，重启应用才好；匿名登录失败时还会崩溃 | 本地临时 UID 被当作官方身份缓存到进程结束；生成临时 UID 时请求的随机范围超过 2³² 上限，抛 RangeError | 临时 UID 不缓存，下次取流重试官方接口；随机数用两段合法区间组合 | db7d0df3；SESSION §10；huya_site.dart:997-1006, 1042-1049；huya_play_url_test.dart:242-253 |
| REG-HUYA-018 | 诊断和线路身份里的 CDN 名称为空 | `multiLine` 的字段叫 `cdnType`，旧代码读的是 `sCdnType` | 用 `multiLine` 的 `cdnType`，再按 `baseSteamInfoList` 的 `sCdnType` 对应 | SESSION §11；huya_site.dart:627-629, 645 |
| REG-HUYA-019 | 没有 seqid 的地址要等到 wsTime + 5 分钟才处理，期间先 EOF 黑屏 | 只会从 seqid 推算签发时间 | 没有 seqid 时，用本地构造地址的时刻作为 issuedAt | SESSION §11；huya_site.dart:446-451；huya_play_url_test.dart:463-485 |
| REG-HUYA-020 | 握手成功但收不到弹幕，订阅掉线 | 旧网关地址和旧的 `OnUserHeartBeat`、加入包已不能维持订阅 | 连 `wsapi.huya.com`；命令 16 注册 `live:`、`chat:` 分组；命令 20 心跳；解析命令 7 和 22 | 125e61d2；huya_danmaku.dart:73-83, 135-149；huya_danmaku_protocol_test.dart:44-61 |
| REG-HUYA-021 | 醒目留言要手动刷新才出现；拉取期间弹幕停顿；内容相同的两条付费留言被合并；切房后旧房间的结果被显示 | 通知比留言板更新早；在解码流程里等待 HTTP；按内容去重；没有会话隔离 | 后台有限重试、按事件 id 去重、按会话丢弃旧结果 | 398d182d、13d4d409；huya_danmaku.dart:221-295；huya_danmaku_protocol_test.dart:90-209 |
| REG-HUYA-022 | 弱网下请求越积越多 | Tars 客户端的默认超时 60000 被当成秒；`Future.timeout` 只是不再等待，不关闭连接；每次新建的客户端都没关闭 | 连接、发送、接收分别限时，另有整次时限；每个请求结束都关闭自己的连接 | 4aefaa04；HUYA_MESSAGE_BOARD_HTTP_AUDIT_2026_09_05.md；base_tars_http.dart:19-39；huya_message_board_test.dart；huya_play_url_test.dart:11-24 |
| REG-HUYA-023 | 异常日志里出现 wsSecret、fm、流名和完整地址 | 线路对象的文本输出包含了全部字段 | 日志只记主机、协议、CDN 类型、码率 | SESSION §11；huya_site.dart:1366-1370；huya_play_url_test.dart:487-499 |
| REG-HUYA-024 | 冷启动时（远程 UA 还没加载）原生地址配上了浏览器 UA | 进程级 UA 的缺省值是浏览器 UA | 媒体请求默认用 HYSDK UA，与原生凭据一致；UA 随适配器发布（6.5） | 8a6fdce1（playback_header_resolver.dart:75 缺省值）；NATIVE“修复设计”第 6 条；playback_header_resolver_test.dart:14-26 |
| REG-HUYA-025 | 最小化恢复后画面永久黑屏 | 签名刷新返回同一个地址时，被当成“刷新成功”，没有重开已经死掉的连接 | 由源错误触发的恢复一律重开连接（播放层规则）；站点层保证每次恢复都重新取详情和签名 | SESSION §5；huya_site.dart:308-336 |
| REG-HUYA-026 | 把页面上的 `vappid=10057` 或 `wsTimeSync` 的服务器时间用进签名的想法 | 页面配置号不是 token 请求的应用号；`wsTimeSync` 只用于延迟统计 | iAppId 固定 66；签名只用本地时钟和服务端 wsTime | SESSION §1、§8 |

---

## 11. 样本清单

**存放与记录**
- 样本放在 `fixtures/huya/`。
- 每个样本记录：URL、抓取时间、直连还是经 Clash、原始内容的 SHA-256、做过脱敏的字段（06-tests.md ⑥-1）。
- 媒体数据本身不入库，只保存首字节和统计值（06-tests.md:108）。

**要录制的样本**

| 编号 | 内容 | 请求 | 份数 | 用途 |
|---|---|---|---|---|
| S01 | 分区 | `bussLive`，bussType = 1、2、8、3 | 4 | 分类树 |
| S02 | 推荐 | `getLiveListByPage` 第 1、2 页和末页 | 3 | 卡片字段；每页条数；有无总页数字段 |
| S03 | 分区房间 | 同上加 `gameId`，一个热门分区、一个冷门分区 | 各 2 页 | 同上 |
| S04 | 搜索 | `getSearchContent v=4`：有结果、无结果、第 2 页；尽量包含 `room_id` 与主播条目不一致的例子 | 3–4 | 房间号映射；结束条件 |
| S05 | 详情（直播中） | `profileRoom`：多 CDN 房间（如 660000）；`bitRateInfo` 为字符串、为数组、缺失（走 `rateArray`）各一 | 3 | 线路、画质、状态、热度 |
| S06 | 详情（非直播） | OFF、REPLAY、不存在的房间、字母别名房间 | 4 | 状态；NotFound；规范房间号 |
| S07 | 匿名登录 | `anonymousLogin` 成功的响应 | 1 | 观众身份 |
| S08 | 原生 WUP | `getCdnTokenInfoEx` 的请求字节和响应字节：至少两个不同流名；另录一个返回码 ≠ 0 的 | ≥3 | Tars 编解码；租期 |
| S09 | 网页 WUP | `getCdnTokenInfoEx`：匿名、账号各一 | 2 | 网页后备 |
| S10 | 头条留言板 | `getHeadLineMessageBoard`：空的、有条目的 | 2 | 醒目留言解析 |
| S11 | 弹幕 | 高密度房间 60 秒原始帧：客户端的 16、20；服务端的 7 和 22（uri 1400、8006、2001314 以及未知 uri） | ≥1 | 解码；分组 id 的实际取值 |
| S12 | 各线路地址 | 每个 CDN 分别取原生 FLV、网页 FLV、HLS：最终地址（查询串脱敏）、HTTP 状态、Content-Type、前 16 字节；HLS 的 Range 响应 | 每房间 3 × CDN 数 | 线路身份；格式识别 |
| S13 | 连接寿命 | 同一房间：网页 FLV 和 HLS 单连接读到结束；原生 FLV 读 ≥ 420 秒；签发 90 秒后才打开的网页地址 | 各 1 次，只存时长、字节数、状态码 | 租期参数 |
| S14 | 房间页（可选） | `https://www.huya.com/{room}` 里的 `stream:` 数据块 | 1 | 探针用的备用来源（tool/probes/huya_native_transport_probe_test.dart:28-48） |

**脱敏**
- 删除：Cookie（请求头里的和 tId.sCookie 里的）、yyuid、匿名 UID、sGuid、wsSecret、seqid、u、uid、uuid。
- 替换：
  - `fm` 换成人工模板，保留 base64 编码、分隔符和 `$0`–`$3` 的位置。解码后的真实模板里有没有敏感内容 [待确认]；
  - `sFlvToken` 和各 AntiCode 按同样方式重建；
  - wsTime 平移到样本的固定时钟，保留十六进制格式和它与 iExpireTime 的相对关系。
- 保留（公开数据）：CDN 类型和主机、流名、主播 UID、lChannelId、lSubChannelId、房间号、热度、分区。
- 弹幕：发送者 uid 和昵称换成稳定的假名；保留消息 id 的顺序。

**生成期望值的旧入口**

旧文件都依赖 Flutter，要在旧应用里用 `flutter test` 运行。

| 入口 | 位置 | 说明 |
|---|---|---|
| `HuyaSite.parseBitRates` | huya_site.dart:788-800 | 画质列表 |
| `HuyaSite.parsePlayQualities` | :249-275 | 画质排序、选择 id |
| `HuyaSite.isExplicitOfflineState`、`parseHuyaLiveStatus` | :745-759 | 直播状态 |
| `HuyaSite.parseRoomAudience` | :148-152 | 热度 |
| `HuyaSite().buildAntiCode(流名, uid, antiCode, now: 固定时刻)` | :1065-1141 | 签名。非 WAP 时结果完全确定；WAP 的 uuid 含随机数 |
| `HuyaSite.rotateViewerUid32`、`unrotateViewerUid32` | :1249-1269 | u 的计算 |
| `HuyaSite.replaceQueryParameter`、`secureHuyaCdnBase` | :491-516 | ratio 处理、https 改写 |
| `HuyaSite.getSignedSequenceIssuedAt` | :112-129 | 从地址还原签发时刻 |
| `HuyaCdnTokenLease.fromResponse(resp, now:)` | :1293-1319 | 原生和网页 WUP 的租期 |
| `HuyaSite.buildNativePlaybackTokenRequest`、`buildPlaybackTokenRequest`、`buildPlaybackTokenUserId` | :1157-1247 | WUP 请求体；配合 base_tars_http.dart:87-107 的封包和解包得到字节级期望 |
| `HuyaSite.parseViewerUidFromCookie` | :1029-1034 | yyuid |
| `HuyaTransportPolicy.selectRefreshedLine`、`hasShortTransportLease`、`hasNativeFlvCredential` | huya_transport_policy.dart:5-78 | 线路身份、租期家族；表驱动测试可以直接转成 YAML（06-tests.md:162） |
| `HuyaDanmaku().getJoinData(uid)`、`heartbeatData`、`decodeMessage(帧)` 加 onMessage 收集 | huya_danmaku.dart:77-83, 135-149, 171-228 | 弹幕编解码 |
| `getHuyaSuperChatMessageList(lPid:, first:, clientFactory:)` | huya_utils.dart:31-97 | 注入客户端即可回放 S10 |

分类、列表、搜索、详情的解析写在联网方法内部，没有静态入口（huya_site.dart:173-237, 519-743, 870-920）。要用旧代码生成期望值，需要替换全局 HTTP 客户端的 Dio 适配器来回放样本（做法见 test/cc_catalog_test.dart:58-75），并注册设置服务提供空 Cookie。成本是否值得 [待确认]；不值得的话按本规格手写期望值。

---

## 12. 待确认

| # | 问题 | 怎么查 |
|---|---|---|
| 1 | 字母别名能否直接请求详情，响应里哪个字段是规范的数字房间号；分享短链、`?roomid=` 形式、App 分享口令 | S06，并收集真实分享文本 |
| 2 | 列表每页的实际条数；有无总页数字段；推荐的排序依据 | S02、S03 |
| 3 | 搜索的总数字段；`livestate`、`typ`、`v` 的含义；直播间条目的 `room_id` 何时和主播条目不同 | S04 |
| 4 | 房间不存在时 `profileRoom` 的响应；`ON` 却没有 `stream` 是否真实出现；`REPLAY` 是否带 `stream`、能否播放 | S05、S06 |
| 5 | 同一房间各 CDN 的 `lChannelId`、`lSubChannelId` 是否总相同；头条留言的 `lPid` 用 topSid 是否正确 | S05、S10 |
| 6 | App 深链里 channelid、liveuid 是否应分别是 topSid 和主播 UID（旧实现都填 subSid） | 用真实 App 测试 |
| 7 | 原生签名必须用主播 UID 吗；用观众 UID 或 0 会怎样 | S12、S13 的对照变体 |
| 8 | 原生 `sFlvToken` 的完整字段；`iExpireTime` 在不同房间和 CDN 下的取值 | S08 |
| 9 | WUP 返回码表，以及各码对应的 SiteFailure | S08、S09 |
| 10 | HTTP UA 的 `7090000` 和 tId 的 `7060000` 是否需要一致；网页 FLV 和 HLS 是否要用浏览器 UA | S12，换 UA 对照 |
| 11 | CDN 是否需要 Referer 和 Cookie；列表、详情接口是否需要 Cookie。不需要的话 v4 不再发送账号 Cookie | S02、S05、S12，带与不带对照 |
| 12 | 100/125 秒在其它房间、其它 CDN、登录状态下是否成立；原生 FLV 的连接最长能维持多久 | S13，多房间、多 CDN |
| 13 | 本机时钟偏差超过 5 分钟时会误判“已过期”，是否需要用服务器时间校准 | 人为调整时钟做实验 |
| 14 | CDN 403 能否区分为签名错误、风控或 IP 限制；有没有限流信号（#846 的连续失败） | S12 故障变体；批量刷新关注时抓包 |
| 15 | 有没有密码房、付费房、地区限制房，以及它们的响应（对应 NeedLogin、AgeOrPaid、RegionRestricted） | 找真实房间 |
| 16 | 弹幕：命令 22 的分组 id 实际取值；握手是否必须带 `Origin`；主播 UID 缺失时怎么办；聊天发送者结构里 `lMid` 的正确 tag；礼物、进场等 uri 是否需要 | S11 |
| 17 | 有没有接口可以校验 Cookie 是否仍然有效 | 用维护者账号抓包 |
| 18 | 解码后的真实 `fm` 模板有没有敏感内容，决定脱敏方式 | S05、S08 |
| 19 | 星秀（gid 1663）的标记有没有产品用途 | 产品确认 |
| 20 | 是否需要“包含未开播主播”的搜索（旧的 `v=1` 接口，字段 `gameLiveOn`） | 产品确认 |
