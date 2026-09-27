# 平台规格：酷狗直播（kugoulive）

第 7 阶段第三批。只写行为和外部契约，不规定类名和函数拆分。

- 平台 id：`kugoulive`，显示名“酷狗直播”（legacy/assets/translations/zh.json `site_kugoulive`）。
- 证据写法：`文件:行号` 相对 `legacy/lib/core/site/kugoulive/`（A = kugou_live_api.dart，S = kugou_live_site.dart，L = kugou_live_link.dart）。样本编号见 §11。
- 状态：**保留**。2026-09-27 直连（中国大陆）实测：首页分区、推荐和分区列表、搜索、房间信息、多线路 FLV 都能匿名访问。不满足 ADR 0003 的任何下线条件。
- 能力：目录（首页分区 → 分区房间，另有推荐）、搜索（主播，含未开播，一页）、详情、取流（两条线路的 HTTP-FLV，AVC）、链接解析。
- 不提供：弹幕（旧版未接入，zh.json `kugoulive_chat_notice`；聊天走繁星私有 WebSocket 协议，v4 本阶段不做，见 §7）；画质选择（接口只给主播推流的那一档）；登录。

---

## 1. 房间身份与链接

**规范身份**：房间号 `roomId`，3–11 位数字（L:2）。主播的 `kugouId`、`userId` 不作身份。

| 输入 | 例 | 处理 | 证据 |
|---|---|---|---|
| 纯房间号 | `3197156` | 直接使用 | L:14-16 |
| 房间页 | `https://fanxing.kugou.com/<房间号>` | 主机 `fanxing.kugou.com`、`mfanxing.kugou.com`（v4 另收 `fanxing2.kugou.com`），路径只有一段 | L:17-26 |
| 带查询参数 | `https://mfanxing.kugou.com/…?roomId=<房间号>` | 取 `roomId`。旧版只在路径为空时接受（L:27-28），v4 任何路径都接受（移动分享页路径会变） | L:27-28 |
| 分享文本 | 链接前后有文字 | 抽出第一个 URL | — |

- `pcindex/category/<id>` 等是分区页，不是房间。
- 外部打开：`https://fanxing.kugou.com/<房间号>`（L:4）。

## 2. 目录

### 2.1 分区

- 来源：首页 HTML `GET https://fanxing.kugou.com/`（A:226-229）。取所有 `href="/pcindex/category/<id>" … title="<名称>"`，按页面顺序、按 id 去重（A:311-329）。
- 排除：`3001` 关注、`3009` 我看过的、`3014` 我管理的、`3015` 我守护的（个人页，A:322）；`8000` 推荐（v4 走推荐接口）。
- 录到 13 个分区：一起玩、音乐、高清、舞蹈、颜值、新秀、酷次元、搞笑、国风、游戏女神、王者荣耀、和平精英、网游竞技（S01-home）。
- v4 只有一个一级分类（id `fanxing`，名称“分类”），分区挂在它下面。首页里一个分区链接都找不到 → ApiChanged（旧版退回写死的列表，A:133-148；v4 不用写死列表，失败就报错）。

### 2.2 推荐

- `GET https://fx1.service.kugou.com/mfanxing-home/h5/cdn/room/index/list?<列表参数>&page=<n>`，列表参数：`pid=0&kugouId=0&doubleLiveFirst=1&sysVersion=0&platform=7&device=PureLive-Web&channel=0&version=99999&longitude=0&latitude=0&appid=1010&liveTypeFilter=0&isNew=0&entranceType=0&uiMode=0`，请求头 `Origin`/`Referer: https://fanxing.kugou.com/`（A:231-262）。
- 响应 `{code: 0, data: {list: [...], hasNextPage: 1}}`；每页约 50 条（S02-recommend-p1、-p2）。
- 翻页：`hasNextPage == 1` 且本页非空时还有下一页。

### 2.3 分区房间

- 同 §2.2，路径换成 `/index/list_v4`，多一个 `cid=<分区 id>`（A:257）。
- 列表项是 `{uiType: "star", data: {...}}` 包装（S03-area-7024-p1），取 `data`。

### 2.4 卡片映射（推荐、分区、搜索共用）

| 目标 | 来源 |
|---|---|
| 房间 id | `roomId` |
| 标题 | `label`，缺时 `topicContent`、`performContent`，再缺用昵称 |
| 昵称 | `nickName` |
| 封面 | `imgPath`（缺时 `imagePath`）；以 `/` 开头的相对路径补 `https://p3.fx.kgimg.com` |
| 头像 | `userLogo`（缺时 `logo`），同上 |
| 在线人数 | `viewerNum`（缺时 `getViewerNum`），只对直播中且大于 0 的取值 |
| 热度 | `hot`（大于 0 时） |
| 状态 | `liveStatus`（缺时 `liveType`、`status`）：0、-1 → 未开播；1（摄像头直播）、6（手机/游戏直播，S02-recommend-p2 有 2 条）及其它正数 → 直播；取不到 → 跳过这一条 |

  状态 6 的房间：房间信息 `liveType = 2`、有 `liveSessionId`，取流正常（S04-room-mobile），所以是直播中。旧版把 1 以外的值都当“未知”（A:530-535），推荐第 2 页的这两个房间因此显示异常。

## 3. 搜索

- `GET https://fx1.service.kugou.com/pt_search/pcsearch/v1/type_all.jsonp?keywords=<kw>&nums=200,0,0,0&callback=<函数名>`（A:264-274）。
- 响应是 JSONP：`<函数名>({code: 0, data: {anchor: {list: [...]}}})`（S06-search，98 条）。取括号内的 JSON；`code != 0` → ApiChanged。
- `anchor.list` 字段同 §2.4（`liveStatus` 0/1、`logo`、`imgPath`、`viewerNum` 在搜索里是 0）。一次最多 200 条，只有一页。
- 无结果：`anchor.list` 为空（S06-search-empty）。

## 4. 房间详情

- `GET https://service2.fanxing.kugou.com/roomcen/room/web/cdn/getEnterRoomInfo?roomId=<房间号>`（A:276-280）。
- `data.normalRoomInfo`：`nickName`、`kugouId`、`userId`、`imgPath`（相对路径）、`userLogo`（相对路径）、`privateMesg`、`publicMesg`、`fansCount`、`limitType`（S04-room-live）。
- 不存在：`code == 0`，但 `kugouId == 0` 且 `nickName` 为空（S04-room-notfound，`roomId=999`）→ NotFound。
- 状态：`liveType == -1` → 未开播（S04-room-offline）；否则有 `liveSessionId` → 直播（S04-room-live 为 0，S04-room-mobile 为 2）；否则 → ApiChanged（旧版“未知”）。
- 标题取 `privateMesg`（与列表的 `label` 一致，如“给我一首歌的时间~”）；`publicMesg` 是直播时间之类的公告，放在公告里。旧版把 `publicMesg` 当标题（A:445）。
- 人数：房间信息没有，三个口径为空。
- `limitType > 0`：受限房间（旧版 A:432-437），状态照常，取流报 NeedsLogin [待确认含义，未录到样本]。

## 5. 画质与线路

- 每个房间只有一档：主播推流的那一档（`streamProfiles[].rate` 录到 3、4、5，同一房间的所有线路相同；2026-09-27 抽查 25 个推荐房间）。v4 只提供 `source`“原画”。
- 线路：`data.lines[]`，每条有 `sid`（录到 5 和 40，对应 `tx105`、`tx2` 两个腾讯云主机）。每条线路取 `httpsFlv` 的第一个地址（列表里同一地址出现两次）；有 `httpsHls` 时再加一条 HLS。线路 id = `sid<sid>-<格式>`。
- 编码：`codec` 1 → AVC（读取 FLV 头验证：codec id 7），2 → HEVC [待确认，未录到]。
- 服务端确认的画质：无。

## 6. 取流

- 取流前重新请求房间信息（§4）：不在播 → StreamUnavailable；受限 → NeedsLogin。
- `GET https://fx1.service.kugou.com/video/pc/live/pull/mutiline/streamaddr?std_rid=<房间号>&std_plat=7&std_kid=0&streamType=1-2-4-5-8&ua=fx-flash&targetLiveTypes=1-5-6&version=1000&supportEncryptMode=1&appid=1010&_=<毫秒>`（A:281-296）。
- `data.status == 1` 且 `data.roomId` 等于请求的房间号；`status == 0`、`lines` 为空 → StreamUnavailable（S05-stream-offline）。
- 地址带腾讯云签名 `txSecret`、十六进制过期时刻 `txTime`（签发后约 12 小时）和签名的 `token`（`0-<房间号>-…`）。旧版要求 `token` 以 `0-<房间号>-` 开头（A:506-507）；v4 不校验签名内容。
- 租期：`expiresAt = txTime`，提前 10 分钟刷新，`cutsConnection = false`（腾讯云只在建立连接时校验签名 [待确认]）。
- 媒体请求头：UA、`Origin`、`Referer: <房间页>`（A:150-154）；实测不带也能拉。

## 7. 弹幕

不做。繁星的聊天是私有二进制 WebSocket 协议，旧版没有实现可参考，匿名接入方式 [待确认]。

## 8. 登录与 Cookie

不支持。

## 9. 错误与风控

| 情况 | 识别 | v4 |
|---|---|---|
| 传输失败、超时、HTTP 5xx | 传输层 / 状态码 | NetworkFailure |
| HTTP 401/403 | 状态码 | RiskControl |
| HTTP 429 | 状态码 | RateLimited |
| `code != 0` | JSON | ApiChanged |
| 房间不存在 | `kugouId == 0` 且无昵称 | NotFound |
| 首页没有分区链接 | HTML | ApiChanged |
| 不在播 | `liveType == -1` / `status != 1` | 房间 offline；取流 StreamUnavailable |
| 受限 | `limitType > 0` | 取流 NeedsLogin |

## 10. 踩过的坑

| 现象 | 根因 | 正确做法 | 证据 |
|---|---|---|---|
| 手机开播的房间显示状态未知 | 列表 `liveStatus` 为 6 | 正数都视为直播 | S02-recommend-p2；S04-room-mobile |
| 房间标题是开播时间表 | 旧版用 `publicMesg` 做标题 | 标题 `privateMesg`，`publicMesg` 做公告 | A:445；S04-room-live |

## 11. 样本清单

2026-09-27 直连录制（规则 tools/live_cli/lib/src/fixture/rules/kugoulive.dart）。没有旧版期望值（ADR 0016），测试 packages/live_core/test/sites/kugoulive_test.dart 直接对照正文。

| # | 样本 | 覆盖 |
|---|---|---|
| S01 | `S01-home` | 首页分区链接 |
| S02 | `S02-recommend-p1`、`-p2` | 推荐列表、`hasNextPage`、`liveStatus` 6 |
| S03 | `S03-area-7024-p1` | 分区列表（舞蹈）、`star` 包装、末页 |
| S04 | `S04-room-live`、`-mobile`、`-offline`、`-notfound` | 房间信息四种情况 |
| S05 | `S05-stream-live`、`-offline` | 两条线路、`txTime`；`status 0` |
| S06 | `S06-search`、`-empty` | JSONP 搜索 |

**需要脱敏的字段**：媒体地址的 `txSecret` 和 `token`（签名），`txTime` 保留真实值供租期测试。主播公开信息保留。

## 12. 待确认

1. `limitType` 的含义和受限房间样本。
2. `codec` 2 是否为 HEVC，是否会出现旧式 codec 12 的 FLV。
3. 签名过期后已建立的连接是否断开。
4. 聊天协议。
5. 多档画质是否只在登录后出现。
