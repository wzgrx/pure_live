# D01.27 弹幕（新增）：百度直播

- 日期：2026-09-30
- 目标：`packages/live_danmaku/lib/src/sites/baidulive.dart`
  - `BaiduLiveDanmakuConnection`：连接（HTTP 轮询，直接继承 `DanmakuConnectionBase`，同快手 D01.6、YouTube D01.20）；
  - `BaiduLiveDanmakuProtocol`：请求头、时序常量、播放列表和分片的解析，不做 I/O；
  - `BaiduLivePlaylist`（一次列表回答）、`BaiduLiveSegment`（一个分片的消息）、`BaiduLiveGift`（礼物消息的 `data`）。
- 参数：`live_core` 新增的 `BaiduLiveDanmakuArgs`（只加，不改已有行为，见“参数”）。
- 升级条目：30-3“百度弹幕（轮询消息列表）”。v3、归档 v4 和 pure_live_TV 都没有百度弹幕（`EmptyDanmaku`），这是新增功能，没有旧行为可对照。
- 样本（`fixtures/baidulive/`）：
  - `S02-room-chat`：本模块补录的房间命令（2026-09-30 12:23 UTC，教育频道当时人最多的直播 11548522172“奇门国学文化大讲堂”），下面 S03 的三个列表地址就来自它；签名的时间和有效期保留，用来测过期；
  - `danmaku/S03-live-chat`、`S04-live-online`、`S05-live-gift`：本模块补录（2026-09-30 12:23～12:30 UTC，直连、匿名、只读），教育、新闻、财经三个频道当时人最多的直播各 7 分钟，每 2 s 拉一次聊天、reliable、host 三个列表和每个新分片；
  - `danmaku/S06-ended`：本模块补录，两个已结束直播的列表（S02-room-ended 那场的聊天列表；另一场的 reliable 列表，分片签名已过期，回答 403）；
  - `danmaku/S07-synthetic`：合成数据（`cases.json`，由 `synthetic_cases.py` 生成）：43 个分片、8 个播放列表；
  - 五个目录的 `expected.json` 都由 `danmaku/web_expected.py` 生成（见“期望值的来源”）。
- 参考：
  - 归档规格 `spec/sites/baidulive.md` 第 7 节（协议已查明，当时以“聊天量太小”暂不实现）、第 12 节“待确认 1”；归档没有百度弹幕的代码和样本；
  - pure_live_TV `e1cca224`：`lib/platforms/baidulive/baidu_live_site.dart:45` 是 `EmptyDanmaku`，没有可参考的实现；
  - 百度直播 PC 房间页的前端脚本 `https://mbdp02.bdstatic.com/static/live/media/pclive/scripts/chunks/pchome.live.fcb2dc0e.js`（2026-09-30 取）：类 `Se`（消息列表轮询：`loadM3u8File`、`parseM3u8Text`、`loadTsFile`、`parseTsFileText`）、类 `Te`（聊天：`start`、`initIM`、`initM3u8Message`、`handleMessage`、`addChatItem`）、常量表 `t.g`（`messageRefreshTime: 2e3`）、地址工具 `o`（把 `http`/`https` 换成页面的协议），以及房间数据里 `msgHlsUrl` 的取法（`video.msg_hls_url || chat_msg_hls_url`）；
  - `live_core` 的 `BaiduLiveApi`（E02.11、E02.11）：`userAgent`、`webOrigin`、`roomUrl`、房间命令的解析；
  - 实测：见“实测”。

## 做法

- **HTTP 轮询消息列表，不用 WebSocket**：网页在支持 WebSocket 的浏览器里用百度 IM（`pim.baidu.com`，闭源的 LCP SDK，要 `BAIDUID` Cookie 和它的 appId 登入聊天室，`Te.initIM`）；不支持时退回轮询房间命令给的消息列表（`Te.initM3u8Message`）。IM 要跑平台的 SDK，按规则不硬做；消息列表是公开的签名地址，匿名只读就能读，也是归档规格 §7 查明的方式。所以和快手、YouTube 一样直接继承 `DanmakuConnectionBase`：间隔用 `run.delay`，取消挂在 `run.ended` 上。框架没有改。
- **参数由进房详情给出，不多发请求**：房间命令 371 本来就有 `chat_msg_hls_url`、`reliable_msg_hls_url`、`host_msg_hls_url` 和 `msg_hls_pull_internal_in_second`，进房时放进 `LiveRoom.danmakuData`。
- **加入**：第一次拿到聊天列表就算加入，报 `DanmakuReady`。列表里已有的分片是历史，不取（列表总留着最后三个分片，不管多旧：录到 reliable 列表的分片是 35 小时前的，已结束直播的聊天列表停在 3 天前）。
- **之后**：每隔 `pullInterval`（5 s）依次拉聊天、reliable、host 三个列表，没见过的分片按顺序各取一次，报出里面的聊天、在线人数和礼物。reliable、host 列表的第一次回答同样是历史。
- **上报**：聊天（白色聊天行）、在线人数（`LiveAudienceUpdate(onlineViewers)`，每条 101 都报）、礼物（`LiveMessageType.gift`，界面暂不显示，和其他平台一致）。平台没有醒目留言、付费留言。
- **直播结束**：本房间的 102（网页的 `stopLive`）以 `connectionFailed`、说明 `Broadcast ended` 结束连接，不重连；`mix_room_close` 不是本房间的结束信号（见“协议”），不处理。

## 参数（`live_core`）

`packages/live_core/lib/src/sites/baidulive/baidulive_api.dart` 只做了添加：

| 新增 | 内容 |
|---|---|
| `BaiduLiveDanmakuArgs` | `roomId`、`chatList`、`reliableList`、`hostList`、`pullInterval`、`expiresAt`，`isExpiredAt(now)`；`toString` 只写房间号（地址带签名） |
| `BaiduLiveRoom.danmaku` | 在播房间命令的参数；卡片、预告、未开播、回放为 null。`enrich` 带上这次回答自己的参数 |
| `BaiduLiveApi.danmakuArgs(command, roomId)` | 聊天列表 `chat_msg_hls_url`（没有时用 `video.msg_hls_url`，同一个列表），reliable、host 列表；间隔 `msg_hls_pull_internal_in_second`（没有时用 `video` 里的），正整数限制在 1～10 s，其他为 5 s；没有合规的聊天列表就没有参数 |
| `BaiduLiveApi.messageList(value)` | 只收 `liveshowstatic.baidu.com` 上路径以 `.m3u8` 结尾的 http/https 地址（没有用户信息和片段）；**http 换成 https**：网页的地址工具把它换成页面的协议（https），实测 https 的列表 18 次、分片 45 次都是 200；查询串原样保留，签名不重编码 |
| `BaiduLiveApi.signatureExpiry(uri)` | `authorization=bce-auth-v1/<密钥 id>/<UTC 时间>/<秒数>/<签名头>/<签名>` 的时间加秒数；`/`、`:` 写成 `%2F`、`%3A` 的也认；时间不合法（13 月、45 日会被 `DateTime` 滚动）、秒数为 0 或超过 10 位、前缀不对时为 null |
| `BaiduLiveApi.messageListHost`、`defaultPullInterval` | `liveshowstatic.baidu.com`、5 s |
| `BaiduLiveApi.liveRoom(..., withData: true)` | 同时把 `room.danmaku` 放进 `danmakuData`：进房、录制带参数；关注刷新、搜索、列表卡片不带（`mergeFrom` 保留已有的） |

签名实测：列表地址在取房间命令的那一刻签，有效 15768000 s（182.5 天）；分片地址签 604800 s（7 天）。过期后 BOS 回 403 `RequestExpired`（S06 的分片）。所以：

- 连接开始时参数已过期（按注入的 `now`），直接以 `credentialsUnavailable`（`Chat list signature expired at …`）结束，不发请求；运行中聊天列表回 403 且已过期，同样结束；
- **由 M13 重新取房间详情**（一次房间命令，拿到新签名），再 `connect`。进房取到的参数半年后才过期，实际上只在直播间长时间不刷新时才会遇到。
- 旧样本（S02-room-live 等）的 `authorization` 当时整串换成了同形随机值，解不出时间，`expiresAt` 为 null，不做过期检查。

## 协议

**三个列表**（房间命令给出，`mcast_id` 各不相同）：

| 列表 | 录到的内容 | 本实现 |
|---|---|---|
| `chat_msg_hls_url`（`live_<chat_mcast_id>.m3u8`，= `video.msg_hls_url`） | 聊天、在线人数 101、各种 107 通知 | 读；它的回答决定加入、失败和重连 |
| `reliable_msg_hls_url` | 107/10024 免费礼物“拍拍”、107/10013 数字人字幕板、开播通知 `preview_trans_2_living` | 读（礼物） |
| `host_msg_hls_url` | 三场直播 7 分钟里一直 404（`NoSuchKey`），归档规格时也一直 404 | 读，404 容忍（见“连接和时序”） |

**播放列表**：`#EXTM3U`、`#EXT-X-VERSION:3`、`#EXT-X-TARGETDURATION:15`、`#EXT-X-MEDIA-SEQUENCE:0`，然后每个分片一行 `#EXT-X-PROGRAM-DATE-TIME`、一行 `#EXTINF` 和一行以 `/` 开头的相对地址 `/v1/liveshowstatic/<mcast_id>_<纳秒时间>.ts?authorization=…`。聊天列表录到的每次都是 3 个分片（reliable 1～3 个），`Content-Type: application/octet-stream`，`Cache-Control: max-age=10`，不压缩。

- 分片地址按列表地址解析，只收同一主机和协议的；
- 录到的 591 个成功回答（聊天和 reliable 列表）的 `EXT-X-MEDIA-SEQUENCE` 全是 0，**不能用媒体序号去重**，改按分片路径（`<mcast_id>_<纳秒时间>.ts`，唯一且递增）去重；也没有录到列表倒退（新的回答比旧的少了新分片）；
- 不是 `#EXTM3U` 开头（错误页、JSON 错误）是一次失败。

**分片**：gzip 压缩的 JSON。录到的全部带 `Content-Encoding: gzip`（传输层 `IoLiveHttp` 自动解压）；归档规格记录过不带这个头的，所以解码前看魔数 `1f 8b` 再解一次（最多两层）。结构：

```
{version, time, duration, list: [{appid, mcast_id, messages: [
  {type: 0, msgid, create_time, from_user, content: "{\"text\":\"<再编码的 JSON>\"}", …}
]}]}
```

外层消息只读 `type` 为 0 的（网页 `handleMessage`：`0 == +e.type`），`content` 是 JSON 文本（或对象），其中 `text` 又是 JSON 文本（或对象），这就是载荷：

| 载荷 `type` | 含义（依据） | 本实现 | 网页 |
|---|---|---|---|
| 0 | 聊天（网页 `addChatItem`） | 聊天行，见下表 | 聊天列表 |
| 101 | 在线人数 `data.onlineusercnt`（与房间命令的 `online_users` 同一个数，录到 3～60 s 一条），另有在线用户列表、`real_onlineusercnt_str`、`hot_rank_score_str` 等 | `onlineViewers`（整数，0 或更大） | 不显示 |
| 102 | 直播停止（网页 `stopLive`，回放时不管） | 本房间的（`room_id` 没有或相同）：报完这个分片，以 `connectionFailed`（`Broadcast ended`）结束 | 停止播放，列表照拉 |
| 103、104、108 | 104 换流（网页 `liveChangeFlow`），其他网页不处理 | 不报 | — |
| 107 + `service_type` 10024 | 礼物（归档规格 §7；录到的都是免费的“拍拍”） | 礼物消息，见下 | 不处理 |
| 107 + 其他 | `mix_room_close`（`room_ids` 是推荐位里**别的**已下播房间，录到的 27 条和已结束直播最后的 3 条都不含本房间）、`clue_top_floating_screen`、`growth_user_level_up`、`growth_user_enter`、`mark_update`、`mix_zan`（点赞）、`digital_bg_board`、`preview_trans_2_living`、服务 740（商品卡片）；网页处理置顶评论、302/303 禁言、1082 清晰度、1090 应急 | 不报 | 各自的界面 |

**聊天行**（网页 `addChatItem`，加上面的房间检查）：

| `LiveMessage` | 取值 |
|---|---|
| 文本 | 按 `message_type`：`"0"` 取 `content`，为空取 `message_body.txt.word`；`"3"` 取 `message_body.link.title`；`"1"`、`"2"`、`"4"`（图片、卡片）没有文字，`"5"`（语音，网页显示“[语音] 不支持消息类型”）不报；其他（含没有）取 `content`。回复（有 `at_name`、`at_message_type` 为 0 且有被回复的话）取自己的话 `message_body.txt.word`。去首尾空白，空的不报 |
| 用户名 | `name`，去首尾空白（没有时为空） |
| 用户 id | `uid`（文字或整数） |
| 消息 id | 外层 `msgid`（16 位整数），不加前缀（同 D01.11 以后的新平台） |
| 时间 | 外层 `create_time`（Unix 秒），正数且在 `DateTime` 范围内；本地时区 |
| 房间 | 载荷的 `room_id` 与本房间不同就丢，没有时照收 |
| 颜色、等级、粉丝牌 | 白色、空（`vip`、`character_name` 不读） |

**礼物**（107/10024 的 `service_info`）：发送人 `user_name`、`user_id`；`content` 是 JSON 文本（或对象）：`gift_name`（没有就不报）、`gift_count`（正整数，否则按 1）、`gift_id`、`is_free`（1 为免费）、`gift_url`（只收 https）。文本是 `<礼物名> ×<数量>`，`data` 是 `BaiduLiveGift`；消息 id、时间同聊天；`service_info.room_id` 不同就丢。

录到的聊天里，教育直播间约一半是主播自己的欢迎机器人（`src: live-digital`），财经直播间的是 AI 机器人（`src: airobot_cron_bot`），网页照样显示，本实现也照报。

## 连接和时序

| 项目 | 本实现 | 网页（后备的列表轮询） | 归档规格 §7 | 依据 |
|---|---|---|---|---|
| 请求头 | 桌面 Chrome UA、`Accept: application/json, text/plain, */*`、`Origin: https://live.baidu.com`、`Referer` 房间页 | 浏览器的，跨域（列表 `Access-Control-Allow-Origin: *`） | — | 实测不带请求头也是 200；和适配器的 UA 一致 |
| 协议 | https（房间命令给的 http 换成 https） | 页面的协议（https） | 平台给的 http | 网页地址工具 `o`；实测 |
| 请求时限 | 10 s | axios 默认（不限） | — | 列表不到 1 KB、分片几 KB |
| 开始前的请求 | 无（参数来自进房详情） | 房间命令 | — | — |
| 签名过期 | 开始时已过期：`credentialsUnavailable`，不发请求；运行中 403 且已过期：同样结束 | 不检查 | 未提 | 时间炸弹规则；见“参数” |
| 加入 | 第一次聊天列表回答（200 且是播放列表，或 404）即加入，报 `DanmakuReady`；列出的分片是历史，不取 | 第一次就取列表里全部分片（本想跳过 10 s 以前的，但它从 `#EXTINF` 行读日期，读不到，判断从不生效） | 未提 | 录到的列表留着很旧的分片（差异 2） |
| 加入失败 | 合计 3 次（间隔 2 s），第 3 次以 `connectionFailed` 结束，说明是最后一次的错误；开始阶段不报重连 | 失败当作空列表，2 s 后再拉 | — | 同 YouTube（D01.20） |
| 轮询间隔 | 上一轮结束后等 `msg_hls_pull_internal_in_second`（录到都是 5 s），限制在 1～10 s | 固定 2 s（`messageRefreshTime`，`forceTime`） | 5 s | 录到分片间隔最短 1.78 s、中位 10～29 s；列表留 3 个，5 s 内没出现过超过 3 个新分片，不会漏（差异 1） |
| 每轮的请求 | 聊天列表 → 它的新分片 → reliable 列表 → 它的新分片 → host 列表（在跳过期内不问） | 只有聊天列表 | 三个列表 | 礼物只在 reliable 列表里 |
| 分片去重 | 按路径，每个列表记最近 256 个 | 按完整地址（含签名） | — | 媒体序号恒为 0（见“协议”） |
| 断点续拉 | 失败恢复后，列表里还没取过的分片照常补取；列表只留 3 个，中断期间出现过 3 个以上新分片时，更早的就拿不到了 | 同（`dataObj`） | — | — |
| 聊天列表失败 | 没有回答、状态不是 2xx 或 404、不是播放列表：连续第 1 次报 `DanmakuReconnecting(disconnected)`（带错误说明），分别等 1、2、4、8、8… s 重试，第 9 次失败以 `reconnectsExhausted` 结束；失败后成功再报 `DanmakuReady`；这期间不问另外两个列表 | 当作空列表，2 s 后再拉，永不放弃 | — | 同快手（D01.1 的 HTTP 轮询约定） |
| 聊天列表 404 | 列表还不存在（还没有消息）：不算失败，照常间隔；以后列出的分片都是新的 | 同（当作空列表） | — | 网页做法 |
| reliable、host 列表失败 | 不报事件；连续第 k 次失败（含 404、403）后跳过 1、2、4、8、12、12… 轮（回放 7 分钟的录制，host 列表问了 9～10 次）；第一次成功的回答是历史；先 404 的列表以后列出的都是新的 | 不读 | host 一直 404 | “404 要容忍”，又不能每 5 s 白问一次 |
| 分片失败 | 4xx（如过期的 403）：跳过；没有回答或 5xx：下一轮还在列表里时再取，共 3 次；不是 JSON 对象：跳过；都不报事件 | 失败不管 | — | S06 的 403；录制里 2 个分片超时 |
| 直播结束 | 本房间的 102：报完该分片，`connectionFailed`（`Broadcast ended`），不再请求 | 停止播放，继续拉列表 | 把 `mix_room_close` 记作 107/10013 | 录制里没出现 102（网页脚本为据，合成帧测试）；`mix_room_close` 说的是别的房间 |
| 心跳 | 没有（`heartbeatInterval` 为 0，`heartbeat()` 什么也不做） | — | — | 轮询本身就是连通检查 |
| 关闭、换房间 | 进行中的请求被取消，等待立即结束，晚到的回答丢掉 | — | — | D01.1 |
| 代理 | 按平台 `baidulive` 取路线（`LiveHttp` 里） | — | — | 与房间接口同一出口 |

同一时间只有一个请求：一轮里的列表和分片依次请求，上一轮结束后才开始等下一轮。7 分钟的回放里每轮 2～3 个列表请求，加上新分片，平均约 0.5 个请求每秒。

## 登记方式

应用（I01.1）建平台表时：

```dart
DanmakuRegistry({
  SiteIds.baiduLive: () => BaiduLiveDanmakuConnection(http: liveHttp),
  // …
});
```

| 参数 | 必需 | 说明 |
|---|---|---|
| `http` | 是 | `live_net` 的 `LiveHttp`，用应用交给 `BaiduLiveSite` 的那一个：请求按平台 id `baidulive` 取代理路线和限流 |
| `now` | 否 | 与签名过期时间比较的时钟，默认 `DateTime.now`（测试里固定成录制时间） |

不需要 Cookie、账号或设置：全程匿名。参数来自在播房间的进房详情；不在播（预告、未开播、回放）没有参数，按 D01.1 不连接。

## 期望值的来源

v3、归档 v4、上游都没有百度弹幕的解码，所以期望值由 `fixtures/baidulive/danmaku/web_expected.py` 生成：它按网页脚本（类 `Se` 的列表解析、类 `Te` 的 `handleMessage` 和 `addChatItem`）和归档规格 §7（101 的人数、107/10024 的礼物）用 Python 独立重写，不看 Dart 代码。网页靠 JavaScript 隐式转换接受的怪值（`+"" == 0`、`+null == 0`）这里从严（只认整数、整数文字和整数值的小数），两边一致。每个 `expected.json` 的 `generator` 写明了来源。运行：仓库根目录 `python3 fixtures/baidulive/danmaku/synthetic_cases.py && python3 fixtures/baidulive/danmaku/web_expected.py`。

| 对照 | 结果 |
|---|---|
| S03 的 16 个（内容不同的）播放列表回答、32 个分片 | 一致：17 条聊天、6 次在线人数 |
| S04 的 18 个播放列表、38 个分片 | 一致：105 次在线人数，没有聊天 |
| S05 的 14 个播放列表、19 个分片 | 一致：3 条聊天、7 次在线人数、3 个礼物 |
| S06 的 2 个播放列表、3 个分片 | 一致：3 条 `mix_room_close`，不报 |
| S07 的 43 个分片、8 个播放列表 | 一致（含 6 个抛 `FormatException` 的坏分片和 4 个坏列表） |
| 每个录下的分片再按“不带 `Content-Encoding`”（仍是 gzip）交给解码 | 与带头时相同 |

会话（连接的时序）没有旧实现可对照，用录下的列表在虚拟时钟上回放（见“测试”）：每次拉列表回答当时最后一次录到的那一次，分片回答录到的内容；检查加入、历史不取、每个新分片只取一次、报出的消息逐条等于 `expected.json` 里这些分片的解码、等待的时长、host 列表的询问次数、每个请求的请求头和时限。

## 与归档 v4 和上游的差异

归档 v4 和 pure_live_TV 都没有实现，只有归档规格 §7 的协议说明。与它的不同：

| # | 差异 | 原因 |
|---|---|---|
| 1 | 列表改用 https | 网页如此；实测可用；不需要明文 http |
| 2 | 102 才是结束信号，`mix_room_close` 不是 | 规格把 107/10013 `mix_room_close` 和聊天放在一起列出，没说含义；实测它的 `room_ids` 是别的房间，本房间从未出现，已结束直播最后的几条也不含自己 |
| 3 | host 列表 404 时按轮跳过，不是每次都问 | 规格记录一直 404；每 5 s 白问一次没有意义 |
| 4 | 在线人数取 101 的 `onlineusercnt`、礼物取 10024 | 照规格的建议；规格没写字段细节，按录到的数据 |

## 与网页的差异

| # | 差异 | 原因 |
|---|---|---|
| 1 | 间隔用房间命令的 5 s，不是网页的 2 s | 平台在房间命令里给的就是 5 s（`msg_hls_pull_internal_in_second`），归档规格也是 5 s；实测 5 s 不漏分片，请求少一半多 |
| 2 | 加入时不取列表里已有的分片 | 列表总留最后三个分片，安静的列表里可能是几十小时前的（reliable 列表 35 小时、已结束直播 3 天）；网页想跳过 10 s 以前的却没生效，会把旧消息当新的显示 |
| 3 | 另读 reliable、host 列表 | 礼物在 reliable 列表里（升级条目 30-3 要礼物） |
| 4 | 聊天列表连续失败时退避、最终放弃 | D01.1 的统一约定（界面能提示“断开”）；网页每 2 s 一直拉 |
| 5 | 按分片路径去重 | 路径唯一；网页按完整地址（签名不变时等价） |
| 6 | 语音消息不报 | 弹幕里飞“[语音] 不支持消息类型”没有意义 |
| 7 | 102 后结束连接 | 一个房间号就是一场直播，结束后的回放没有新聊天（只有点赞之类的通知）；网页继续拉，界面上只显示已结束 |
| 8 | 报在线人数和礼物 | 网页的聊天列表不显示它们；在线人数按 `audience.dart` 的约定上报，礼物按升级条目 |
| 9 | 不接 IM（WebSocket） | 要运行平台闭源的 IM SDK（LCP 协议、`BAIDUID`），按规则不做；列表轮询匿名可读 |
| 10 | 不取进房时的历史评论（网页 `initHistoryComments`） | 弹幕只飞新的（同其他平台） |

## 实测

2026-09-30 12:17～13:16 UTC，直连、匿名、只读（不登录、不发言），请求头同适配器。用 Python 小脚本和本实现（`IoLiveHttp`）。

- **频道推荐**：7 个频道第 1 页，按人数挑了教育 11548522172（14.7 万）、财经 11542685348（10.1 万）、新闻 11588562681（9.8 万）；另看了 2 人在线的购物直播 11588173517（也有 101 和商品卡片的 107/740）。
- **录制**：见“样本”。三场各 7 分钟，每 2 s 一轮：聊天列表成功 294 次、超时 8 次；reliable 列表成功 295 次、超时 7 次；host 列表 293 次都是 404、超时 9 次；分片 91 个（2 个超时）。聊天 20 条（7 分钟里；多是机器人），在线人数 118 次，礼物只在财经直播 reliable 列表的旧分片里有 3 个（35 小时前的“拍拍”）。
- **签名**：列表签 182.5 天，分片 7 天；不带签名回 403 `AccessDenied`，分片过期回 403 `RequestExpired`；https 与 http 一样可用。
- **已结束的直播**：S02-room-ended 那场（09-27 结束）的聊天列表停在它最后的三条 `mix_room_close`；另一场（11562145409，09-16 开播）的聊天列表 09-30 还出现过点赞（`mix_zan`），它的 reliable 列表的分片（09-16 签）回 403。录制里没有见到 102。
- **本实现，在播**（13:13～13:16 UTC）：教育直播 1.2 s 加入，90 s 内 4 条聊天、1 次在线人数；新闻直播 0.9 s 加入，90 s 内 28 次在线人数；没有重复的消息 id，关闭后状态为 `idle`。

## 样本

- **S02-room-chat**：房间命令。`online_user_list` 里 10 位观众的 uid、头像、名字换成同形合成值（与分片里同一人的替换值相同）；四个列表地址的 `authorization` 只换密钥 id 和签名（同长度十六进制），签名时间和有效期保留；响应头 `x-bfe-svbbrers` 回显的出口地址换成 `203.0.113.7`。`meta.json` 的 `raw` 是录制脚本保存的解码后回答（紧凑 JSON）的摘要。
- **S03～S05**：`frames.jsonl` 每行一次请求：`t`（毫秒，从第一次请求算）、`list`、`kind`（playlist/segment）、`url`、`status` 或 `error`（超时）；列表回答写 `text`，与这个列表上一次成功回答相同时写 `same: true`；分片写 `b64`（gzip 的正文）和 `encoding: gzip`（送来时带 `Content-Encoding: gzip`，录到的都带）。脱敏：
  - 所有地址（列表、分片、列表正文里的分片行）的签名同上；
  - 分片解压后逐层解开（外层、`content`、`text`），观众的 `uid`、`user_id`、`from_user`、`lastestuid`、`to_user`、`enable_user_list`、`search_enable_user_list` 换成同位数的合成数字，`name`、`nick_name`、`user_name`、`lastestuser` 换成同形合成名字，`bd_uk`、`uk` 换成同形值，`portrait`、`avatar` 换掉头像路径的可变部分，`clueLiveContent` 里打码名字的首字换掉；同一人在各帧、各样本、房间命令里用同一组值；聊天文字里出现的观众名字（包括主播欢迎机器人念出的 4 个进场观众名）一并替换；
  - 保留：主播（房间命令的 host，以及它自己发的聊天：名字、uk、uid、发送者、头像，都是公开的）和系统发送者“百度网友”（852517826）；消息 id、时间、房间号、徽章和礼物图片不是个人信息；
  - 写入后把所有原值（名字、编号、uk、头像路径、密钥 id、签名、出口地址）在全部字符串里再查一遍（分片解压、嵌套 JSON 解开后），找到就不写。录制和脱敏用的 Python 小脚本没有放进仓库，`meta.json` 的 `tool`、`scrubbed` 写明了做法；`raw` 是原始录制文件的摘要。
- **S06-ended**：只有签名要换；`mix_room_close` 的发送者是系统账号。
- **S07-synthetic**：名字、编号、时间都是编造的，分片按原样字节（base64）保存，Dart 测试和生成脚本读同一份字节。
- 门禁的 `fixture privacy` 通过。

## 回归条目的覆盖

归档规格没有 REG-BAIDULIVE 条目；§10“踩过的坑”三条都属于平台层（E02.11）。§12“待确认 1”（弹幕实现及三种列表的区别）由本模块回答，见“协议”。

## 受阻

没有。没能验证的：

- **102（直播停止）**：7 分钟 × 3 场和两场已结束直播的列表里都没有出现，按网页脚本实现，只用合成帧测过；如果平台其实不发，结束后的直播只是不再有新分片，连接照常每 5 s 拉一次（不打转、不报错），界面按房间状态处理。
- **不带 `Content-Encoding` 的 gzip 分片**：录到的都带；按归档规格的记录做了，合成数据和本地服务器测过。
- **回复（`at_name`）、图片、链接、语音消息**：录制里只有文字聊天；按网页脚本实现，合成数据覆盖。
- **长时间运行**：实测最长 7 分钟（约 900 个请求），没有遇到 429 或风控。

## 后续升级候选（由用户决定）

| # | 内容 | 现状 | 依据 |
|---|---|---|---|
| 1 | 接百度 IM（WebSocket），延迟更低、消息更全 | 列表轮询，延迟最多一个间隔（5 s）加分片生成的时间 | 要运行平台的 IM SDK（`pim.baidu.com`、LCP），需要先决定是否接受 |
| 2 | 显示礼物 | 以 `gift` 类型上报，界面不显示 | 与其他平台的礼物一起由 M13 决定；字段在 `BaiduLiveGift` |
| 3 | 显示进场、点赞、升级等通知 | 不报 | 107/10013 的 `growth_user_enter`、`mix_zan`、`growth_user_level_up` 等 |
| 4 | 在线人数改报 `real_onlineusercnt_str`（录到 1～48，远小于显示的十几万） | 报 `onlineusercnt`，与房间页、卡片显示的一致 | 口径要与平台层（E02.11 的 `online_users`）一起改 |

## 放到其他模块的部分

| 内容 | 去向 |
|---|---|
| 登记到 `DanmakuRegistry` | I01.1（见“登记方式”） |
| 关闭、重连原因的界面文字；`connectionFailed` 的说明（`Broadcast ended`、加入失败的错误）和 `credentialsUnavailable`（`Chat list signature expired at …`） | M13（D01.1 的原因表） |
| 签名过期（`credentialsUnavailable`）后重新取房间详情再连；`Broadcast ended` 后刷新房间（它变成回放） | M13 |
| 房间公告 `baidulive_chat_notice` | 已在平台层改好：`BaiduLiveApi.chatNotice` 去掉“这里暂时看不到百度直播间的聊天。”，只说明人数（“人数是正在观看的人数，主播的粉丝数另外显示。”）；3.x 原文留作 `legacyChatNotice` 给对照测试和 J02.1 迁移；平台层的对照测试把公告列为有意差异（30-10、D01.27）。翻译在 M13 |
| 进房详情的人数和弹幕报的人数不同时显示哪个 | M13（其他平台也是后到的覆盖先到的） |
| 应用允许的网络：列表已是 https，不需要为弹幕放开明文 http（媒体线路另有要求，见 E02.11） | I01.1 |
| 上面的候选 | M13 |
| `live_core` 的 `LiveDanmaku`、`BaiduLiveSite.getDanmaku()` | D01 各平台完成后删除 |

## 在线人数

`audience.dart` 里百度仍是 `roomList`（卡片的 `audience_count` 就是在线人数），能力没有变，只在注释里补上了这个来源：聊天列表的 101 带着同一个数（`onlineusercnt`，与房间命令的 `online_users` 相同），弹幕连接每收到一条就报一次 `LiveAudienceUpdate(onlineViewers)`。

## 新增的通用能力、依赖

没有。框架文件没有改，没有新依赖（gzip 用 `dart:io`，同抖音、AcFun）；只在 `live_danmaku.dart` 里按字母顺序加了一行导出。`live_core` 只改了本平台目录（见“参数”）和 `audience.dart` 里百度那一项的注释。

## 测试

`live_danmaku/test/sites/baidulive_test.dart` 86 个用例，`live_danmaku` 共 1049 个；`live_core` 的百度测试加了 9 个（`baidulive_api_test.dart` 7 个、`baidulive_site_test.dart` 2 个），共 3550 个。都连续跑 3 次全部通过；三个测试文件直接运行（`tools/timeshift/run.sh` 的做法）在时钟 +30 天、+1 年、+5 年下也通过并正常退出（签名过期只和注入的 `now` 比较，固定成录制时间）。

| 分组 | 用例 | 内容 |
|---|---|---|
| 协议 | 5 | 时限、加入重试、退避、跳过轮数、分片重试、记住的分片数、结束说明；请求头；分片键和恒为 0 的媒体序号；在线人数消息和 `BaiduLiveGift`；一条聊天行的全部字段（S03）和礼物（S05） |
| 录制对照网页脚本 | 5 | S03～S06 的每个播放列表和分片（各自的消息计数；不带 `Content-Encoding` 时结果相同）；S06 过期分片的 403 和已结束直播的 `mix_room_close` |
| 合成对照网页脚本 | 53 | 43 个分片、8 个列表各一个用例，一个检查每个都有期望值，一个检查 gzip 的有无和两层 |
| 录制回放（虚拟时钟） | 3 | S03、S04、S05 整段：加入、历史不取、每个新分片只取一次、报出的消息等于 `expected.json`、等待、host 列表约每分钟一次、请求头和时限 |
| 连接 | 20 | 没有心跳、平台表登记、参数类型；加入不取历史并按轮报新分片；聊天列表 404 也加入；加入 3 次失败；不是播放列表；已过期的参数不发请求；录下的参数半年后过期；过期后 403 结束、之前的 403 重连；失败的通知、退避、第 9 次结束、恢复后再就绪；reliable、host 列表的跳过轮数和历史；礼物；分片的 403、超时、5xx、坏分片；不带头的 gzip；102 结束、`mix_room_close` 不结束；间隔；超过 256 个分片时忘掉最旧的；加入时 `close`；等待中 `close`；换房间丢掉晚到的回答；本地 HTTP 服务器端到端（线上的请求和请求头、带头和不带头的 gzip、404 的 host 列表） |
