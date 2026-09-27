# 平台规格：17live（17LIVE）

第 7 阶段第三批。只写行为和外部契约，不规定类名和函数拆分。

- 平台 id：`17live`（legacy/lib/core/sites.dart:74），显示名 `17LIVE`（legacy/assets/translations/zh.json `site_17live`）。代码目录 `seventeenlive`（Dart 标识符不能以数字开头），样本目录 `fixtures/17live/`。
- 证据写法：`文件:行号` 相对 `legacy/lib/core/site/seventeenlive/`（A = seventeenlive_api.dart，L = seventeenlive_link.dart，S = seventeenlive_site.dart），其它旧代码写全路径（相对 `legacy/`）。样本编号见 §11。
- 状态：**保留**。2026-09-28 实测：接口、拉流、弹幕都能匿名使用（直连，出口在美国）；有公开目录（日本区约 35 个在播，台湾区约 20 个）。不满足 ADR 0003 的下线条件。
- 能力：目录（日本、台湾、香港三个地区的推荐区块，游标分页）、搜索（当前直播；房间号和链接精确查找）、详情、取流（HTTP-FLV：原画、增强高清、高清、H.264，每档两个 CDN）、弹幕（Ably 实时消息，匿名令牌）。
- 不提供：登录；回放（`ArchiveVideo`、`Vod`）；连麦房（`GroupCall`）的多路画面。
- **HEVC**：主播用手机端开播时，除 H.264 档以外的档位是 FLV codec id 12（旧式 HEVC），见 §6.4。

---

## 1. 房间身份与链接

**规范身份**：房间号 `liveStreamID`，等于主播的 `userInfo.roomID`，每个主播固定一个（L:33-36）。主播的 `userID` 是 UUID，不作为房间号。

| 输入 | 例 | 处理 | 证据 |
|---|---|---|---|
| 直播页 | `https://17.live/<语言>/live/<号>`、`https://17.live/live/<号>` | 房间号 | L:13-18 |
| 主播页 | `https://17.live/<语言>/profile/r/<号>`、`/profile/r/<号>` | 房间号 | L:19-27 |
| 房间号 | `27484154` | 搜索里直接查 | S:199 |
| 分享文本 | 链接前后夹有文字 | 抽出第一个 URL | — |

- 主机：`17.live`；`www.17.live` 301 跳到 `17.live`（2026-09-28 实测），v4 两个都认。语言段：两个字母，可带 `-` 后缀（`ja`、`zh-Hant`；L:44）。
- 房间号 `^[1-9][0-9]{0,11}$`（L:35）。
- 链接解析不发请求。外部打开：`https://17.live/ja/live/<号>`。

---

## 2. 目录

### 2.1 分类

- v4：一个 `Category`（id `region`，名称 `17LIVE`），三个 `Area`：`JP`（日本）、`TW`（台湾）、`HK`（香港，内容混有日本和台湾）。`US` 的内容只是日本和香港的混合，不单列。旧版只有日本区（A:183-184）。
- 推荐 = 日本区。

### 2.2 区块列表

- GET `https://api-dsa.17app.co/api/v1/sections?count=20&typeTab=2&region=<地区>&cursor=<游标>`（A:179-218；S01、S02）。网页首页也是这个请求（`typeTab=2`、`count=20`）。
- 返回 `sections[]`（每个区块 `id`、`name`（多语言键）、`labelID`、`grids[]`）和下一页 `cursor`。
- 区块 `id`：`TopBanner`（横幅）、`Label`（标签，如 `jp_V-LIVER`、`jp_game`）、`Latest`（新主播）、`PK`、`NewUserWelcome`、`ArchiveVideo`/`ArchiveClip`/`Vod`（回放）、`GroupCall`（连麦）等。跳过 `TopBanner`、`ArchiveVideo`、`ArchiveClip`、`Vod`（A:193，v4 另加 `ArchiveClip`）。
- 其它区块的 `grids[].stream` 是直播对象（§2.3）；只收 `status == 2`（直播中）的，标签区块里混有未开播的主播（S01：65 条里 33 个在播）。同一房间在多个区块出现只保留第一次（A:201）。
- 分页：下一页用返回的 `cursor`；为空或与本页游标相同时结束（A:208-214）。游标形如 `<时间>:<偏移>:<数量>:<序号>-<签名>`，原样传回。第二页通常只剩回放和连麦（S01-sections-jp-p2）。
- 单个标签区块没有独立的分页接口（`sections/Label` 返回 `no such section`）。

### 2.3 直播对象

| 字段 | 含义 | v4 |
|---|---|---|
| `liveStreamID` | 房间号 | 房间号 |
| `status` | 2 直播中，0 未开播（A:289-294） | 状态；其它值在详情里是 ApiChanged |
| `caption` | 标题 | 标题（空则主播名） |
| `userInfo.displayName`、`openID` | 主播名 | 主播名 |
| `userInfo.picture` | 头像文件名 | 头像 `https://cdn.17app.co/<文件名>` |
| `coverPhoto`、`thumbnail` | 截图（`http://cdn.17app.co/snapshot/…`）、主播图 | 封面（升级为 https） |
| `liveViewerCount` | 当前观众 | `online`（只在直播中） |
| `viewerCount` | 本场观看人数（详情才有） | `cumulative` |
| `beginTime` | 开播时间（秒，详情才有） | 开播时间 |
| `audioOnly` | 1 = 音频直播 | 分区显示“音频直播”（legacy/assets/translations/zh.json `seventeen_audio_room`） |

- 图片只接受 `cdn.17app.co`、`assets-17app.akamaized.net`，或者裸文件名（拼到 `cdn.17app.co`；A:367-383）。

---

## 3. 搜索

- GET `api/v1/liveStreams/search?query=<关键词>`（A:222-245；S03）：返回数组，只有当前在播的房间（形同 §2.3），没有分页；v4 只收 `status == 2`。没有结果时返回 `[]`（S03-search-none）。
- 输入是房间号或 17LIVE 链接：直接查详情（未开播也返回；S:199-207）。链接查不到返回空。
- 关键词超过 100 字截断（A:224）。

---

## 4. 房间详情

- GET `api/v1/lives/<房间号>`（A:166-175；S04）：§2.3 的全部字段，另有 `userInfo`（`roomID`、`bio`、`followerCount` 等）、`pullURLsInfo`、`guardianUserID`/`guardianPicture`（守护者，是观众）、`eventList` 等。
- 校验：`liveStreamID` 等于请求的房间号，`userInfo.roomID`（有时）也相等，否则 ApiChanged（A:279-286）。`status` 只能是 0 或 2。
- 未开播：`status 0`，`pullURLsInfo.rtmpURLs` 为空，`liveViewerCount`/`viewerCount` 是上一场的（S04-live-offline），v4 不显示。
- 不存在：**HTTP 520**，`{"errorCode":0,"errorMessage":"stream not found"}`（S04-live-notfound）→ NotFound。
- 简介 `userInfo.bio`。
- 弹幕参数（直播中）：`roomId`。

---

## 5. 画质与线路

- 每次取流重新请求 `lives/<号>`（§6.1）。`pullURLsInfo.rtmpURLs[]`（没有时用 `rtmpUrls`，A:316-319）每项是一个 CDN（`provider` 17 = 腾讯 `tencent-global-pull-rtmp.17app.co`，5 = 网宿 `wansu-global-pull-rtmp-latency.17app.co`），字段：

| v4 画质 | 字段（按序取第一个非空） | 腾讯 / 网宿的文件名 | 说明 |
|---|---|---|---|
| `source` 原画 | `urlHighQuality`、`urlLowQuality`、`webUrlLowQuality` | `<userID>.flv` | 主播推上来的流 |
| `enhanced` 增强高清 | `urlQualityEnhancedHD` | `_enhance002.flv` / `_QEHDSA.flv` | 转码 |
| `hd` 高清 | `urlLowBitrateHD`、`webUrl`、`url` | `_enhance003.flv` / `_LBHDSA.flv` | 转码 |
| `h264` H.264 | `url264` | `_h264.flv` | **H.264 转码，总是 AVC** |

- 旧版把 `urlLowQuality` 等叫“标准”并排在最后（A:334-341、S:230-244）；实测它们就是原始流（无后缀、与 `urlHighQuality` 相同），v4 叫“原画”并排在最前。2026-09-28 实测四档都是 604×1080、30 fps，码率 1.5～2.5 Mbit/s，差别不大。
- 地址必须是 `*pull-rtmp*.17app.co` 上的 `.flv`（A:351-365）；`http://` 升级为 `https://`（腾讯两种都能用）。
- 每个画质按 CDN 在列表里的顺序各一条线路（身份 `tencent` / `wansu`）。确认画质 = 请求。
- **默认画质是 H.264**（请求不指定画质时）：其它档位跟随主播的编码，可能是 FLV codec 12（§6.4）；播放器能识别（FFmpeg ≥ 8），但高通硬解是否丢帧未验证（REG-PLAY-022），所以不作默认。H.264 线路标 `codec: avc`，其它档位不标（未知）。

---

## 6. 取流

### 6.1 流程

- 每次取流重新请求 `lives/<号>`：`status` 必须是 2，否则 StreamUnavailable。

### 6.2 租期与 CDN

- 地址不带签名和时间，没有租期。
- **同一时刻只有列表里第一个 CDN 在服务**，另一个返回 404（2026-09-28 抽查 12 个直播间：9 个腾讯在前且可用，3 个网宿在前且可用，后一个一律 404）。播放器按线路顺序尝试。

### 6.3 请求头

- API：UA、`Accept: application/json, text/plain, */*`、`Origin: https://17.live`、`Referer: https://17.live/`（A:93-107）。
- 拉流：**必须带 `Referer: https://17.live/`**，没有时腾讯返回 403（只带 Origin 也是 403）；v4 线路请求头：UA、Referer。

### 6.4 媒体实况（2026-09-28）

- HTTP-FLV，AAC 音频（`audiocodecid 10`）。
- 视频编码（`flvinfo`，12 个在播房间，每个读第一个视频标签）：
  - 10 个房间四档都是 AVC（codec id 7）；
  - 2 个房间（29759207、29061512，开播设备是 iPhone）的原画、增强高清、高清是 **FLV codec id 12（旧式 HEVC）**，只有 H.264 档是 AVC；
  - 接口里没有能事先判断编码的字段（对比 HEVC 与 AVC 房间的详情，只有 `device` 不同：`iPhone 13 mini` 对 `OBS`，不可靠）。
- 结论：所有平台的 libmpv 都是 FFmpeg ≥ 8，能直接播放 codec 12，**不需要中转改写**（spec/modules/playback.md）；录制写入时改写成 enhanced FLV（ADR 0005）。高通硬解是否静默丢帧还没有真机验证（REG-PLAY-022），在那之前 v4 仍默认 H.264 档，其它档位可以手动选。
- `live_cli probe 17live https://17.live/ja/live/27484154`：解析 → 详情（直播中，在线 124）→ 取流（原画、增强高清、高清、H.264，选 H.264，线路 tencent、wansu）→ 读到 FLV，通过（2026-09-28）。

---

## 7. 弹幕

旧版没有 17LIVE 弹幕（S:83）。以下来自网页脚本（ably-js 2.21.0）和 2026-09-28 实测。

### 7.1 连接

- 令牌：POST `https://api-dsa.17app.co/api/v1/messenger/auth`，JSON 体 `{}`，匿名 → `{"provider":1,"token":"<Ably 令牌>","permissions":["*"]}`。`provider` 1 = Ably，2 = PubNub（网页的枚举）；不是 1 时不连接。网页的 Ably 客户端就用这个接口做 `authCallback`。
  - `messenger/token?type=1&roomID=<号>` 返回房间所用的推送服务（目前也是 Ably），v4 不调用。
  - 网页脚本里还有几把 Ably API Key（客户端签名用），v4 不用，也不写进仓库。
- 地址：`wss://17media.realtime.ably.net/?access_token=<令牌>&format=json&heartbeats=true&v=3`（ably-js 的 `environment: "17media"` → `17media.realtime.ably.net`；备用主机 `17-media-{a,b,c}-fallback.ably-realtime.com`，v4 不用）。握手请求头 `Origin: https://17.live`、UA。
- Ably JSON 协议（`action` 编号）：连上后服务端发 `CONNECTED`（4，含 `connectionId`、`connectionKey`、`maxIdleInterval: 15000`）；客户端发 `{"action":10,"channel":"<房间号>"}`（ATTACH），回 `ATTACHED`（11）即加入成功。频道名就是房间号（网页 `subscribeChatRoom(roomID)`）。
- `ERROR`（9）、带 `error` 的 `DISCONNECTED`（6）或 `DETACHED`（13）→ 拒绝，重新取令牌再连（令牌过期的错误码 40142）。

### 7.2 心跳

- `heartbeats=true`：服务端每 15 s 发 `{"action":0}`，客户端不发。静默看门狗 90 s（共用 SocketConnector：max(3 × 15 s, 90 s)）。

### 7.3 消息

- `MESSAGE`（15）：`channel`、`messages[]`（`id`、`data`）。`data` 是 **gzip 后 base64** 的 JSON（`H4sI` 开头；网页按 `gzip_base64` 解码）；v4 也接受直接的 JSON。消息 id 用 `17live:<id>`。
- JSON 的 `type`（网页枚举，节选）：

| type | 名称 | 内容 | 处理 |
|---|---|---|---|
| 3 | COMMENT | `commentMsg.comment.text`（或 `content`）、`sendTime`（毫秒）、`displayUser.userID`、`displayName` | 聊天 |
| 13 | NEW_GIFT | `giftMsg.giftID`（如 `2609_jp_cp_akanya`）、`displayUser`、`giftMetas[].combo.count`（连击序号） | 礼物：名称用 `giftID`（礼物表另有接口，v4 不查），每条计 1 个 |
| 38 | LIVE | `liveinfo.liveViewerCount` | 在线人数 |
| 5 | LIVE_STREAM_END | 下播 | 忽略 |
| 6、28、56、74、79、80 等 | 直播信息变化、入场反应、军团、排行、任务提醒 | 带观众信息 | 忽略 |

---

## 8. 登录与 Cookie

- 不支持登录。17LIVE 要求观众年满 18 岁（legacy/assets/translations/zh.json `seventeen_age_notice`），匿名接口不检查。

---

## 9. 错误与风控

| 情况 | 证据 | 映射 |
|---|---|---|
| 网络错误、超时 | A:247-258 | NetworkFailure |
| HTTP 520 `stream not found` | S04-live-notfound | NotFound |
| 其它 HTTP 5xx | A:265 | NetworkFailure |
| HTTP 420 `errorCode 7`（参数错误，如 `invalid channel type`、`no such section`） | 2026-09-28 实测 | ApiChanged（旧版当作限流，A:264） |
| HTTP 429 / 401、403 | A:262-264 | RateLimited / RiskControl |
| `status` 不是 0、2；答非所问的房间 | A:279-294 | ApiChanged |
| 未开播；没有拉流地址 | S04-live-offline；S:223-226 | StreamUnavailable |

---

## 10. 踩过的坑

| 编号 | 现象 | 根因 | 正确做法 | 证据 |
|---|---|---|---|---|
| REG-17LIVE-001 | 部分房间只有声音或黑屏 | 手机开播的原始流和增强档是 FLV codec 12 | 默认 H.264 档；高通真机验证（REG-PLAY-022）后再把默认改回最高档 | §6.4 |
| REG-17LIVE-002 | 一半线路 404 | 同一时刻只有列表第一个 CDN 在服务 | 按列表顺序给线路 | §6.2 |
| REG-17LIVE-003 | 拉流 403 | 拉流主机检查 Referer | 线路带 `Referer: https://17.live/` | §6.3 |
| REG-17LIVE-004 | 不存在的房间报“服务故障” | 17LIVE 用 HTTP 520 表示房间不存在 | 520 + `stream not found` → NotFound | §9 |

---

## 11. 样本清单

2026-09-28 直连录制（规则 tools/live_cli/lib/src/fixture/rules/seventeenlive.dart）。旧应用不能再运行（ADR 0016），没有 `expected.json`；v4 测试 packages/live_core/test/sites/seventeenlive_test.dart 直接对照样本。拉流是持续的 FLV，不录制；编码实况见 §6.4。

| 编号 | 接口或场景 | 已录制 |
|---|---|---|
| S01 | `sections` 日本区 | `S01-sections-jp`（第一页）、`S01-sections-jp-p2`（用第一页的游标：只剩回放和连麦，游标为空） |
| S02 | `sections` 台湾区 | `S02-sections-tw` |
| S03 | `liveStreams/search` | `S03-search`（花音）、`S03-search-none`（`[]`） |
| S04 | `lives/<号>` | `S04-live-live`、`S04-live-offline`（`status 0`）、`S04-live-notfound`（520） |
| S05 | 弹幕帧 | `fixtures/17live/danmaku/S05-live`（`live_cli danmaku 17live https://17.live/ja/live/29046769 --seconds 150 --record`：37 帧：令牌、ATTACH、ATTACHED、8 条评论、心跳） |

**缺**：礼物和在线人数消息的帧（录制时有过在线人数，这一段没有；单元测试按实测结构构造）；音频直播；连麦房。

**需要脱敏的字段**
- `lives/<号>`、搜索：`guardianUserID`（守护者，观众）、`guardianPicture`。
- 令牌：`messenger/auth` 的 `token`（只在弹幕录制里出现）。
- 弹幕帧：令牌（auth 响应、握手地址的 `access_token`）；`CONNECTED` 的 `connectionId`、`connectionKey`、`serverId`；消息负载解压后精简再压缩：评论只留文本和时间，礼物只留 `giftID`，在线人数只留人数，发送者的 `userID`、`displayName` 替换；其它类型只留 `type`。
- 主播、房间、活动、礼物、军团名称是公开信息，保留；拉流地址没有签名。

---

## 12. 待确认

| # | 问题 | 怎么查 |
|---|---|---|
| 1 | HEVC 房间的比例和规律（设备、地区） | 长期抽样 |
| 2 | 礼物 id → 名称、价值的接口 | 看网页礼物面板请求 |
| 3 | Ably 令牌的有效期和到期时的断开方式 | 连满一小时 |
| 4 | `messenger/token` 返回 PubNub 的房间 | 抽样 |
