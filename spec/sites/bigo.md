# 平台规格：Bigo Live（bigo）

ADR 0003 的**候选下线**平台，第 7 阶段评估。只写行为和外部契约，不规定类名和函数拆分。

- 平台 id：`bigo`，显示名 `Bigo Live`。
- 证据写法：`文件:行号` 相对 `legacy/lib/core/site/bigo/`（A = bigo_api.dart，T = bigo_token.dart，P = bigo_hls_protection.dart，L = bigo_link.dart）；旧版录制输入 `legacy/lib/recorder/services/bigo_hls_input.dart`（R）。样本编号见 §11。

## 0. 去留评估（ADR 0003 下线标准）

2026-09-28 实测，本机两个出口各一次：默认出口（经系统层隧道，`203.0.113.8`）和 Clash 代理出口（`203.0.113.9`），都在境外。中国大陆真实直连没有测（[待确认] 旧诊断的 needLogin 是否也与地区有关，§4）。

| 标准 | 结论 | 证据 |
|---|---|---|
| 1. 取流成功率 < 50% | **接口层不满足**：匿名网页令牌（§6.1）→ `getInternalStudioInfo` 给出 `hls_src`，主列表、分片都 200；两个出口都成功。**播放层依赖中继**：分片被加扰（§6.3），ffmpeg 直接播放线上列表 11 次只成功 1 次；经本地中继解扰后 2/2 成功，不解扰 0/2（§5） | `live_cli probe bigo 414439909`（两个出口各一次）；S03-studio-live；S04-playlist |
| 2. 需要应用不支持的登录 | **不满足**：带网页令牌时 `needLogin=false`。旧版诊断看到的 `needLogin` 是不带令牌的表单请求（S03-studio-notoken），不是平台要求登录 | S03-studio-live 对 S03-studio-notoken |
| 3. 没有公开目录且链接不稳定 | **不满足**：`vedioList/72` 是公开推荐列表（S01-list，20 个房间）；`bigo.tv/<id>` 链接长期稳定 | S01-list |

**结论：有条件保留（待 14 天探针复核）**：实现推荐、详情、取流、链接，并提供 §6.3 的解扰函数。条件是 `live_media` 的 HLS 中继能在转发分片时调用解扰函数；中继不做，播放成功率接近 0，按标准 1 应下线。旧版诊断以“探针显示 needLogin、需要自有输入”建议下线（docs/rewrite/diagnosis/01-sites.md），前者是旧探针没带令牌，后者就是这个中继缺口，都不是平台本身不可用。

- 能力：推荐（一页 20 个）、详情、取流（HLS 一档，AVC）、链接解析。
- 不提供：分类（网页只有一个推荐列表）；搜索（网页搜索要登录后的接口，[待确认]）；弹幕（网页聊天走私有 WebSocket 二进制协议，本阶段未做，§7）；登录。

---

## 1. 房间身份与链接

- 房间 id = Bigo id（`bigo_id`/`siteId`），数字（`414439909`）或主播自选的字母数字（`qashia305`），形状 `^[A-Za-z0-9_][A-Za-z0-9_.-]{0,63}$`（A:330-332）。同一主播的数字 id 和自选 id 都能用于 §4 的请求（S03-studio-live 用数字 id 请求，回答里 `clientBigoId` 是自选 id）。

| 输入 | 处理 | 证据 |
|---|---|---|
| 纯数字 id | 直接使用 | L:36-44 |
| `https://www.bigo.tv/<id>`、`https://www.bigo.tv/<两字母语言>/<id>`（也收 `bigo.tv`、其它 `*.bigo.tv` 子域） | 取 id；`about`、`download`、`index`、`live`、`login`、`search`、`signup`、`show`、`user` 是页面不是房间 | L:18-27 |
| 分享文本 | 抽出第一个 URL | — |

- 外部打开：`https://www.bigo.tv/<id>`。

## 2. 目录

- 没有分类。推荐 = `GET https://ta.bigo.tv/official_website/OInterfaceWeb/vedioList/72?tabType=00&fetchNum=10&lang=en&countryCode=US`（A:231-236；`fetchNum=10` 实际返回 20 个），请求头 `Origin: https://www.bigo.tv`、`Referer: https://www.bigo.tv/`。
- 响应 `{"code":0,"data":{"resCode":"0","data":[…]}}`；`code != 0` 或 `resCode != "0"` → ApiChanged。
- 卡片：房间 id = `bigo_id`；标题 `room_topic`（空时用昵称）；主播 `nick_name`；封面 `cover_m`（缺时 `cover_l`）；在线人数 `user_count`；地区 `country_name`（常为空）。`is_locked == 1`（密码房）跳过。按 `bigo_id` 去重。
- 只有一页；续页返回空页。

## 3. 搜索

不提供（[待确认] 网页搜索接口是否匿名可用）。

## 4. 房间详情

`POST https://ta.bigo.tv/official_website/studio/getInternalStudioInfo?siteId=<id>&verify=&token=<网页令牌>`，空正文，`Content-Type: application/x-www-form-urlencoded`（A:252-260）。令牌每次详情/取流重新取（§6.1，两次 JSONP 请求）。

- `code != 0` → ApiChanged；`data.needLogin == true` → NeedsLogin（令牌缺失或失效时出现，S03-studio-notoken）。
- `alive`：`1` 直播，`0` 未开播，其它 → ApiChanged。
- 字段：主播 `nick_name`；标题 `roomTopic`（空时用昵称）；封面 `snapshot`；头像 `avatar`；分区 `gameTitle`；`uid`、`roomId` 放进 `danmakuKeys`。在线人数不给。
- `passRoom == true`（密码房）或 `isPaidShow == "1"`（付费秀）：状态照实，但不给 HLS（§6 报 StreamUnavailable）。

## 5. 画质与线路

- `data.hls_src`：HLS 媒体列表（`https://<十六进制>.cubetecn.com:1451/list_<a>_<sid>_0.m3u8`），只有一档，v4 叫 `hls`“自动”；线路 id = 主机名；编码 AVC（S04 分片 h264 + aac）。
- 地址里没有过期时间，没有租期；列表窗口只有 3 个约 1.9 秒的分片（`EXT-X-TARGETDURATION:2`）。
- 媒体请求头：`Origin: https://www.bigo.tv`、`Referer: https://www.bigo.tv/`、UA。
- **分片加扰（§6.3）**：列表带 `#EXT-X-BIGO-WEB-PROTECTION:VERSION=1,SEED=<n>`，每个分片前两个 TS 包的前 16 字节被异或（同步字节 `0x47` 变成别的值，PAT/PMT 不可读）。
  - 实测（2026-09-28，同一直播间）：把 3 个分片存成本地点播列表，ffmpeg 不解扰也能解码（它扫描 PES 猜流）；但 ffmpeg 直接打开线上直播列表，11 次只成功 1 次（代理出口 1/8、默认出口 0/3），失败都是 `could not find codec parameters`——窗口只有 3 个短分片，每个分片的 PAT/PMT 都被扰乱，探测期内拿不到节目表。经本地 HLS 中继转发（同一上游、同一代理）：解扰 2/2 成功，不解扰 0/2（超时）。
  - 结论：播放器（media_kit 底层是 ffmpeg）直接播放不可用，需要 `live_media` 的 HLS 中继在转发分片时调用解扰函数（§6.3）。**这是 `live_media` 的缺口**：现在的管线只有 splice/direct，不改写 HLS。旧版录制器用自有输入做同样的事（R:70-75）。

## 6. 取流

### 6.1 匿名网页令牌

1. `GET https://sec.bigo.sg/v1/webjs/t?callback=<名>` → JSONP `{"code":0,"time":"<秒>"}`（S02-time-live；这里的 time 是服务器给的固定值，不是当前时间，照原样用）。
2. `data` = Base64(`Salted__` + 8 字节随机盐 + AES-256-CBC(PKCS#7) 密文)，明文 `{"dr":"<32 位随机十六进制>","business":"bigolive-video","scene":"","at_time":"<time>","ver":"2.0"}`，密钥和 IV 由 OpenSSL 的 EVP_BytesToKey（md5，一轮）从口令 `undefinedval0x01` 和盐导出：`D_i = md5(D_{i-1} + 口令 + 盐)`，取前 32 字节为密钥、接着 16 字节为 IV（T:17-64）。等价于 `openssl enc -aes-256-cbc -md md5 -pass pass:undefinedval0x01`。
3. `GET https://sec.bigo.sg/v1/webjs/status?callback=<名>&data=<data>` → JSONP `{"code":0,"info":"success","token":"<54 位>"}`（S02-status-live）。

JSONP 解析不依赖回调名：取第一个 `(` 到最后一个 `)` 之间的 JSON。

### 6.2 取流

重新走 §6.1 + §4；未开播、密码房、付费秀、没有 `hls_src` 或不是 `.m3u8` → StreamUnavailable。

### 6.3 分片解扰（中继用）

- 种子：媒体列表 `#EXT-X-BIGO-WEB-PROTECTION:` 属性里的 `SEED=<十进制>`（0–2³²−1）。旧版正则要求 `:SEED=` 紧跟冒号（P:8-9），现在的标签是 `VERSION=1,SEED=…`，旧版已经匹配不到。没有这个标签 = 不加扰。
- 变换（加扰和解扰相同，做两次还原）：对包 `k = 0, 1`（每包 188 字节，不足一包就停）：`state = (seed XOR ((k+1) × 2654435769)) mod 2³²`，为 0 时取 `1831565813`；对该包前 16 字节逐个：`state ^= state << 13; state ^= state >> 17; state ^= state << 5`（都截到 32 位），`mask = state & 0xff`，为 0 时取 `165`，该字节异或 `mask`（P:24-40）。
- 实测：一个线上分片前 16 字节 `3853197a…2e58` 用种子 2020359253 解扰后是 `47 40 00 10 00 00 b0 0d …`（PAT）。

## 7. 弹幕

本阶段未做（缺口）。网页聊天走私有的二进制 WebSocket 协议，需要另行抓包。

## 8. 登录与 Cookie

不支持账号，不用 Cookie。

## 9. 错误与风控

| 情况 | 识别 | v4 |
|---|---|---|
| 传输失败、超时、HTTP 5xx | 传输层 / 状态码 | NetworkFailure |
| HTTP 401/403 | 状态码 | RiskControl |
| HTTP 429 | 状态码 | RateLimited |
| id 形状不对 | §1 | NotFound |
| 令牌缺失、失效 | `needLogin: true` | NeedsLogin |
| 未开播、密码、付费 | `alive`、`passRoom`、`isPaidShow` | 详情照实；取流 StreamUnavailable |
| 形状不符 | JSON / JSONP | ApiChanged |

[待确认] 不存在的 id 的回答（没有录到）。

## 10. 踩过的坑

| 现象 | 根因 | 正确做法 | 证据 |
|---|---|---|---|
| 探针说要登录 | 旧探针用表单请求，没带网页令牌 | 先走 §6.1 取令牌，放在查询参数里 | S03-studio-notoken |
| 解扰失效 | 标签加了 `VERSION=1,` 前缀 | 在属性列表里找 `SEED=` | S04-playlist |

## 11. 样本清单

2026-09-28 经代理录制（规则 tools/live_cli/lib/src/fixture/rules/bigo.dart）。没有旧版期望值（ADR 0016），测试 packages/live_core/test/sites/bigo_test.dart 直接对照正文；令牌请求用 OpenSSL 算出的向量校验，解扰用线上分片的前 16 字节校验。

| # | 样本 | 覆盖 |
|---|---|---|
| S01 | `S01-list` | 公开推荐列表（20 个） |
| S02 | `S02-time-live`、`S02-status-live` | 令牌的两步 JSONP |
| S03 | `S03-studio-live`、`S03-studio-notoken` | 带令牌的详情（直播）；不带令牌 → needLogin |
| S04 | `S04-playlist` | 媒体列表（带加扰标签） |

**需要脱敏的字段**：网页令牌 `token`（JSONP 正文和请求参数）、令牌请求 `data`、图片地址的 `auth-token`、`client_ip`。主播的公开信息保留。

## 12. 待确认

1. `live_media` 的 HLS 中继（改写列表、分片过解扰函数）；接入后复测播放成功率。
2. 网页搜索是否匿名可用。
3. 聊天协议。
4. 不存在的 id 的回答。
