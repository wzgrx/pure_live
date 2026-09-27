# 平台规格：LOOK 直播（looklive）

第 7 阶段第三批。只写行为和外部契约，不规定类名和函数拆分。

- 平台 id：`looklive`，显示名“LOOK 直播”（网易云音乐旗下）。
- 证据写法：`文件:行号` 相对 `legacy/lib/core/site/looklive/`（A = look_live_api.dart，S = look_live_site.dart，L = look_live_link.dart）。样本编号见 §11。
- 状态：**保留**。2026-09-27 本机默认出口实测（2026-09-28 查明本机默认出口经系统层隧道在境外，不是中国大陆直连）：`weapi` 加密的推荐接口、房间接口和网易云信的 FLV/HLS 媒体都能匿名访问。不满足 ADR 0003 的任何下线条件。
- 能力：目录（视频直播、声音直播两个分区）、推荐（视频直播）、详情、取流（FLV + HLS；视频 AVC，声音直播只有音频）、链接解析。
- 不提供：搜索（没有匿名接口）；弹幕（网易云信 IM，见 §7）；登录。

---

## 1. 房间身份与链接

**规范身份**：直播间号 `liveRoomNo`（2–18 位数字，L:2）。主播的 `userId`、场次 `liveId`/`roomInfo.id` 不作身份。

| 输入 | 例 | 处理 | 证据 |
|---|---|---|---|
| 纯房间号 | `21623631` | 直接使用 | L:14-15 |
| 房间页 | `https://look.163.com/live?id=<房间号>` | 路径只能是 `/live`，取 `id` | L:16-33 |
| 分享文本 | 链接前后有文字 | 抽出第一个 URL | — |

- 外部打开：`https://look.163.com/live?id=<房间号>`（L:4）。

## 2. 目录

### 2.1 分区

固定两个（旧版同样按类型分，A:219-222）：`video`“视频直播”、`audio`“声音直播”，挂在一级分类 `look`“分类”下。推荐 = 视频直播列表。

### 2.2 列表

- 视频：`POST https://api.look.163.com/weapi/livestream/homepage/recommend`；声音：`POST …/weapi/livestream/listen/homepage/recommend/list`。明文载荷 `{"offset":<(页-1)×20>,"limit":20}`，按 §6.1 加密（A:216-240）。
- 响应 `{code: 200, data: {itemList: [...], hasMore}}`；只取 `type == "1"` 且有 `liveData` 的项（S01-video-p1、S02-audio-p1）。
- 翻页：`hasMore == true` 且本页非空时还有下一页。视频列表录到 3 条、`hasMore` 为 false；声音列表每页 20 条。
- 声音列表里夹有视频直播卡片（`liveType == 1`，S02-audio-p1），旧版按分区跳过（A:236-238）；v4 同样只保留本分区的卡片。
- 卡片：房间号 `userInfo.liveRoomNo`；昵称 `userInfo.nickname`；标题 `liveTitle`；封面 `liveCoverUrl`；头像 `userInfo.avatarUrl`；在线人数 `onlineNumber`；热度 `popularity`。图片是 `http` 地址，网易云音乐图床同样支持 `https`，v4 改用 `https`。列表只有直播中。

## 3. 搜索

不提供。

## 4. 房间详情

- `POST https://api.look.163.com/weapi/livestream/room/get/v3`，载荷 `{"liveRoomNo":"<房间号>"}`（A:242-270）。
- 响应 `data.anchor`（`liveRoomNo`、`nickName`、`avatarUrl`）、`data.roomInfo`（`title`、`liveCoverUrl`、`liveType` 1 视频/2 声音、`liveStreamType`、`liveUrl{httpPullUrl, hlsPullUrl, rtmpPullUrl}`、`startTime`）、`data.liveStatus`（S03-room-video、S03-room-audio）。
- `anchor.liveRoomNo` 必须等于请求的房间号，否则 ApiChanged。
- 状态 `liveStatus`：1 → 直播；0、-1 → 未开播；-10 → 未开播（旧版“受限”，A:256）；其它 → ApiChanged。
- 不存在：`{code: 404, message: "直播间不存在"}`（S03-room-notfound）→ NotFound。
- `code` 424、520、522、555 → RiskControl（旧版的“无权访问”，A:192-194）；其它非 200 → ApiChanged。
- 分区按 `liveType`：2 → 声音直播，其它 → 视频直播。
- 人数：房间接口没有，三个口径为空。

## 5. 画质与线路

- 一档 `source`“原画”；线路：`httpPullUrl`（FLV）、`hlsPullUrl`（HLS），线路 id 为格式名。
- 编码：视频直播 AVC（FLV 头 codec id 7）；声音直播 FLV 只有音频（FLV 头 flags 为 4，只有 AAC 标签），`codec` 为空，播放层按纯音频处理。
- 地址是 `http`（`pull*.live.126.net`，网易云信），没有签名和过期参数，`lease` 为空。
- `liveStreamType == 50` 且没有 `liveUrl` 的房间只能在 App 里看（旧版 A:78）→ StreamUnavailable。

## 6. 取流

### 6.1 weapi 加密

网易网页版通用的请求信封（A:153-172）：

1. 明文 = 紧凑 JSON（无空格）。
2. `params` = base64(AES-128-CBC(base64(AES-128-CBC(明文, 键 `0CoJUm6Qyw8W8jud`)), 键 `0123456789abcdef`))，IV 都是 `0102030405060708`，PKCS#7 填充。
3. `encSecKey` = 倒序的 `0123456789abcdef` 按十六进制读成整数，`^65537 mod` 网页公钥模数，十六进制补足 256 位。第二把键固定，所以 `encSecKey` 是常量。
4. 表单 `params`、`encSecKey` 以 `application/x-www-form-urlencoded` 提交。

v4 在 live_core 里自带 AES 加密实现（packages/live_core/lib/src/crypto/aes.dart），用 FIPS-197 向量和 OpenSSL 输出核对，不引入 pointycastle（旧版依赖它，A:7-11）。

### 6.2 流程

取流时重新请求房间接口（§4）；不在播 → StreamUnavailable；按 §5 组线路。请求头：UA、`Origin`/`Referer: https://look.163.com/`，实测不带也能拉。

## 7. 弹幕

不做。直播间聊天走网易云信 IM（需要云信的 appKey 和匿名登录流程），匿名接入 [待确认]。

## 8. 登录与 Cookie

不支持。响应会下发匿名 Cookie `NMTID`，接口不依赖它。

## 9. 错误与风控

| 情况 | 识别 | v4 |
|---|---|---|
| 传输失败、超时、HTTP 5xx | 传输层 / 状态码 | NetworkFailure |
| HTTP 401/403 | 状态码 | RiskControl |
| HTTP 429 | 状态码 | RateLimited |
| `code == 404` | JSON | NotFound |
| `code` 424/520/522/555 | JSON | RiskControl |
| 其它 `code != 200`、房间号不符、未知状态 | JSON | ApiChanged |
| 未开播 | `liveStatus` 非 1 | 房间 offline；取流 StreamUnavailable |

## 10. 踩过的坑

| 现象 | 根因 | 正确做法 | 证据 |
|---|---|---|---|
| 声音分区出现视频直播 | 推荐流里插入视频卡片 | 按 `liveType` 过滤 | A:236-238；S02-audio-p1 |
| 声音直播黑屏 | 流里只有音频 | `codec` 为空，交给播放层的纯音频处理 | S03-room-audio |

## 11. 样本清单

2026-09-27 本机默认出口录制（规则 tools/live_cli/lib/src/fixture/rules/looklive.dart）。没有旧版期望值（ADR 0016），测试 packages/live_core/test/sites/looklive_test.dart 直接对照正文；请求表单由 Python + OpenSSL 生成，Dart 的加密实现必须逐字节复现才能匹配回放。

| # | 样本 | 覆盖 |
|---|---|---|
| S01 | `S01-video-p1` | 视频推荐（3 条，`hasMore` false） |
| S02 | `S02-audio-p1`、`-p2` | 声音推荐，含插入的视频卡片 |
| S03 | `S03-room-video`、`-audio`、`-notfound` | 房间接口三种情况 |

**需要脱敏的字段**：没有。接口只返回主播公开信息；表单是公开常量加密的公开载荷；匿名 Cookie 由工具统一替换。

**缺**：未开播房间的样本（录制时找不到下播的已知房间号，房间号很稀疏）。

## 12. 待确认

1. 未开播、`liveStatus -10` 的房间样本。
2. `liveStreamType` 各值的含义（录到 1 视频、6 声音）。
3. 云信 IM 的匿名接入。
