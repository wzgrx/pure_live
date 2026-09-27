# 平台规格：LiveMe（liveme）

第 7 阶段第三批。只写行为和外部契约，不规定类名和函数拆分。

- 平台 id：`liveme`，显示名 `LiveMe`（legacy/lib/core/site/liveme/liveme_site.dart:30-33）。
- 证据写法：`文件:行号` 相对 `legacy/lib/core/site/liveme/`（A = liveme_api.dart，S = liveme_site.dart，L = liveme_link.dart，G = liveme_signer.dart）。样本编号见 §11。
- 状态：**保留**。2026-09-27 直连（中国大陆）实测：精选目录、搜索、三个详情接口、签名的直播信息接口和 FLV/HLS 媒体都能匿名访问。不满足 ADR 0003 的任何下线条件。
- 能力：推荐（精选目录，分页）、搜索（主播，含未开播）、详情、取流（原画 FLV + HLS、360p FLV，AVC）、链接解析（短号、主页、分享页）。
- 不提供：分类；弹幕（旧版未接入，zh.json `liveme_chat_notice`；直播间 `chatSystem=3` 走私有 IM，匿名没有找到可用的通道，见 §7）；登录。

---

## 1. 房间身份与链接

**规范身份**：短号 `short_id`（`ushortid`），5–12 位数字，不以 0 开头（L:53-56）。

- 用户 id `uid`（13–24 位数字）和直播 id `vid`（每场一个）都不是房间身份，只用于请求。
- 旧版的卡片、收藏和链接都以短号为键（S:66-86），v4 相同。

| 输入 | 例 | 处理 | 证据 |
|---|---|---|---|
| 纯短号 | `209683072` | 直接使用 | L:44-49 |
| 直播页 | `https://www.liveme.com/[locale/]livehot/streaming/<短号>` | 主机 `liveme.com`/`www.liveme.com`；首段是 `us`、`zh-tw` 这类地区码时跳过 | L:9-24 |
| 用户页 | `…/u/<uid>` | `user/getinfo` 取 `short_id` | L:25-28；A:250-252 |
| 分享页 | `…/v/<vid>`、`…/m/v/<vid>/index.html?live=1` | 签名的 `queryinfosimple` 取 `ushortid`（直播信息的 `shareurl` 就是这种形式，S05-query-live） | L:29-39；A:252-253 |
| 分享文本 | 链接前后有文字 | 抽出第一个 URL | — |

- 外部打开：`https://www.liveme.com/livehot/streaming/<短号>`（L:62-66）。

## 2. 目录

### 2.1 分类

没有。`categories()` 返回空列表。

### 2.2 推荐（精选目录）

- `GET https://lvapi.liveme.com/live/featurelist?countryCode=GLOBAL&page_index=<n>&page_size=20&pid=3&posid=3002&h5=1`，请求头：UA、`Origin: https://www.liveme.com`、`Referer: https://www.liveme.com/livehot`（A:228-247）。
- 响应 `{status: "200", data: {video_info: [...], next_page: "1", ...}}`（S01-featurelist-p1、-p2）。`status` 和数字都是字符串。
- 翻页：`next_page == "1"` 且本页非空时还有下一页；游标是页码。
- 跳过：没有 `ushortid` 的卡片（联合直播间，A:252-257）；私密直播（`ispvt == 1`）、付费直播（`livebptype == 7` 或 `hot_label_v2.text == "Paid broadcast"`，A:377-383）——它们打不开，不进目录（旧版同样过滤，A:258）。
- 卡片映射（每项都是直播中）：

| 目标 | 来源 |
|---|---|
| 房间 id | `ushortid` |
| 标题 | `title`，空时用昵称 |
| 昵称、头像 | `uname`、`uface` |
| 封面 | `videocapture`（540），缺时 `smallcover` |
| 地区 | `countryCode` |
| 人数 | 在线 `playnumber`、热度 `heat`、累计 `watchnumber`（旧版同样分三种，S:78-81） |
| 开播时间 | `vtime`（秒） |

## 3. 搜索

- `GET https://live.liveme.com/search/searchKeyword?alias=liveme&tongdun_black_box=1&os=web&_time=<毫秒>&h5=1&thirdchannel=6&type=1&page=<n>&pageSize=30&keyword=<kw>&tuid=&uid=&token=&androidid=`（A:271-291）。
- 响应 `data.data_info[]`：`short_id`、`user_id`、`nickname`、`face`、`is_live`、`project`、`countryCode`、`fans_num`（S02-search-p1）。
- **一页固定 20 条，不管 `pageSize`**（S02-search-p1、-p2 都是 20 条，内容不重叠）。旧版“条数 ≥ pageSize 才有下一页”（A:318），所以永远只有第 1 页。v4：本页非空就给下一页游标，空页结束（S02-search-empty）。
- 状态：`is_live == 1` → 直播；其它 → 未开播。**不可靠**：`project` 为 `emolm`、`lmpro` 等联合项目的主播正在直播时也报 0（2026-09-27 实测 `174419840` 在播、搜索结果 `is_live=0`；旧版因此把这类行标成“未知”，A:305-313）。v4 没有“未知”状态，按未开播显示，进房以详情为准（§4）。
- 卡片：标题和昵称都用 `nickname`；头像 `face`；没有封面和人数。

## 4. 房间详情

三步，全部匿名：

### 4.1 短号 → 用户和当前直播

- `GET https://live.liveme.com/liveme_ent/v1/user/uid_vid_by_short_id?<访客参数>&short_id=<短号>`（A:329-341）。访客参数：`alias=liveme&tongdun_black_box=1&os=web&_time=<毫秒>&h5=1&thirdchannel=6`。
- 在播：`{data: {uid, vid}}`（S03-mapping-live）；未开播：`vid == ""`（S03-mapping-offline）；不存在：`{status: "400", msg: "params error"}`（S03-mapping-notfound）→ NotFound。

### 4.2 主播资料

- `GET https://live.liveme.com/user/getinfo?<访客参数>&userid=<uid>`（A:343-365）。
- `data.user.user_info`：`short_id`、`uid`、`nickname`/`uname`、`big_face`/`face`、`big_cover`/`cover`、`usign`（简介）、`countryCode`（S04-profile-live）。
- 不存在：`{status: "500", msg: "user not exist"}`（S04-profile-notfound）→ NotFound（旧版当服务错误）。
- 返回的 `short_id` 必须等于请求的短号，否则 ApiChanged。

### 4.3 直播信息（签名）

- `POST https://live.liveme.com/live/queryinfosimple?alias=liveme&tongdun_black_box=1&os=web`，表单 `_time`、`thirdchannel=6`、`videoid=<vid>`、`area=en`、`vali`，再加签名字段；请求头 `lm-s-sign`（A:367-399；签名见 §6.1）。
- `data.video_info` 的 `vid` 必须等于请求的 `vid`（S05-query-live）。
- 状态：`online == 1 && status == 0 && roomstate == 0` → 直播；`online == 0` 或 `status`/`roomstate` 非 0 → 未开播；其它 → ApiChanged（A:385-393，旧版的“未知”在 v4 是错误）。
- 私密、付费（§2.2 的条件）：状态照常，取流报 NeedsLogin（v4 不支持 LiveMe 登录）。
- 详情合成：在播时卡片字段取直播信息（映射同 §2.2），昵称、头像、封面缺失时用资料补；简介取 `usign`；未开播时标题用昵称，封面用资料封面，人数为空。

## 5. 画质与线路

| 画质 id | 名称 | 线路 |
|---|---|---|
| `source` | 原画 | FLV `videosource`（缺时 `videosourcemore`）、HLS `hlsvideosource` |
| `smooth` | 流畅 | FLV `smallsource`（`_360.flv`） |

- 顺序：原画在前。某档没有地址就不列出；一档都没有 → StreamUnavailable。
- 线路 id：格式名（`flv`、`hls`）。媒体主机随调度变化（`game.live11.linkv.fun`、`liveme.zglive.linkv.fun`），不能作为线路身份。
- 服务端确认的画质：无。
- 编码：AVC（2026-09-27 读取 FLV 头：video codec id 7，音频 AAC）。
- 旧版只接受 `linkv.fun`、`emolm.com`、`liveme.com` 主机，并把 `http` 改成 `https`（A:450-471）。实测 https 同样可用；v4 保留平台给的地址原样，不做主机白名单（平台换 CDN 时不至于全部失效）。

## 6. 取流

### 6.1 签名

`lm_s_ts` = 毫秒时间戳 + 一位计数；表单加上 `lm_s_id=LM6000101139961122666757`、`lm_s_ts`、`lm_s_str=md5(lm_s_ts)`、`lm_s_ver=1`、`h5=1`；把查询参数和表单合在一起按键名排序，依次拼接“键 + 值”，再拼接 `lm_s_id`、`lm_s_ts` 和网页密钥 `dd46dbb442b6e4ba817d6347d2ddf493`，取 md5 作为请求头 `lm-s-sign`（G:20-47）。`vali` 是 4 + `l` + 4 + `m` + 5 个取自网页字母表的随机字符（G:49-54）。常量来自官方网页脚本，与账号无关。2026-09-27 实测签名仍被接受。

### 6.2 流程

取流时重新执行 §4.1 和 §4.3（地址在直播信息里），不复用详情的结果。没有 `vid` 或不在播 → StreamUnavailable。

### 6.3 租期

- 地址带网宿签名 `wsSecret` 和十六进制的绝对过期时刻 `wsABStime`（S05-query-live 为签发后约 4.8 小时）。
- `Lease`：`expiresAt = wsABStime`，`refreshAt` 提前 10 分钟，`cutsConnection = false`：过期后已建立的连接是否被断开 [待确认]，在确认前只预取。

### 6.4 请求头

媒体请求带 UA、`Origin: https://www.liveme.com`、`Referer: <直播页>`（A:127-131）。实测不带也能拉流。

## 7. 弹幕

不做。直播信息里 `chatSystem = "3"`、`TCRoomId`，聊天走私有 IM SDK；`msgfile` 只是回放用的消息文件。匿名实时通道 [待确认]。

## 8. 登录与 Cookie

不支持。私密、付费直播报 NeedsLogin。

## 9. 错误与风控

| 情况 | 识别 | v4 |
|---|---|---|
| 传输失败、超时、HTTP 5xx | 传输层 / 状态码 | NetworkFailure |
| HTTP 401/403 | 状态码 | RiskControl |
| HTTP 420/429 | 状态码 | RateLimited |
| 业务 `status` 400/404 | JSON | NotFound（短号不存在返回 400） |
| 业务 `status` 500 且 `msg` 含 “not exist” | JSON | NotFound |
| 业务 `status` 401/403、420/429、其它 ≥ 500 | JSON | RiskControl、RateLimited、NetworkFailure |
| 其它 `status`、形状不符、id 不一致 | JSON | ApiChanged |
| 私密、付费直播 | §2.2 条件 | 取流 NeedsLogin |

## 10. 踩过的坑

| 现象 | 根因 | 正确做法 | 证据 |
|---|---|---|---|
| 搜索只有一页 | 服务端每页固定 20 条，旧版按“条数 ≥ 30”判断 | 空页才结束 | A:318；S02-search-p1/p2 |
| 在播主播搜索显示未开播 | 联合项目的 `is_live` 不可靠 | 进房以详情为准 | 实测；A:305-313 |
| 不存在的主播报服务错误 | 接口用业务 500 表示“user not exist” | 映射为 NotFound | S04-profile-notfound |

## 11. 样本清单

2026-09-27 直连录制（`live_cli fixture capture`，规则 tools/live_cli/lib/src/fixture/rules/liveme.dart）。没有旧版期望值（ADR 0016），v4 测试 packages/live_core/test/sites/liveme_test.dart 直接对照正文。

| # | 样本 | 请求 | 覆盖 |
|---|---|---|---|
| S01 | `S01-featurelist-p1`、`-p2` | 精选目录第 1、2 页 | 卡片、三种人数、`next_page` |
| S02 | `S02-search-p1`、`-p2`、`-empty` | 搜索 `andre` 第 1、2 页，无结果关键词 | 每页 20 条、空页结束 |
| S03 | `S03-mapping-live`、`-offline`、`-notfound` | 短号映射 | `vid` 有/无；业务 400 |
| S04 | `S04-profile-live`、`-offline`、`-notfound` | 主播资料 | 字段；“user not exist” |
| S05 | `S05-query-live` | 签名的直播信息 | 状态、FLV/HLS/360p、`wsABStime`、`shareurl` |

**需要脱敏的字段**：媒体地址的网宿签名 `wsSecret`（以及 HLS 子地址的 `wsIPSercert`、`wsSession`）替换为合成值，`wsABStime` 保留真实值供租期测试使用。签名字段 `lm-s-sign`、`lm_s_*`、`vali` 由公开常量和时间戳算出，不是凭据，原样保留。主播公开信息保留（ADR 0009 第 4 条）。

## 12. 待确认

1. `wsABStime` 过期后已建立的连接是否断开（`cutsConnection`）。
2. 匿名可用的实时聊天通道。
3. 联合项目主播的 `is_live` 何时可信。
4. `hot_label_v2` 付费标签的真实样本（录制时没有遇到付费直播）。
