# 第 0 阶段诊断：平台适配器（master@49ceccb0，只读）

口径：“60天”列用指定命令统计。各站目录是 2026-08-21 在 a3a744fa 中从平铺结构迁进来的，所以目录计数基本就是目录的全部历史；老 9 站在斜杠后另给主文件 `--follow` 的 60 天计数。测试数指 test/ 下引用该目录、适配器类或其弹幕文件的文件数。

## ① 规模与结构

- 共 34 个适配器（33 站 + IPTV）。`lib/core/site` 29,061 行；弹幕 12,099 行，其中抖音 protobuf 生成代码 8,809 行；Tars 2,919 行；utils 5,076 行；接口和注册表 976 行，60 天内改了 69 次，说明接口本身就不稳定。
- 两代代码并存：
  - **老 9 站**：B站、斗鱼、虎牙、抖音、快手、CC、Twitch、SOOP、YY，从上游移植。每站一个大文件，直接依赖 GetX、Settings 和 UI。
  - **新 24 站**：2026-09 自研，已拆成 `*_api/*_link/*_site`，自带 `XxxFailure` 枚举和 CancelToken，只剩 i18n 一处依赖。v4 应以新一代为模板。
- 维护热点是首批 5 站、CC 和 Twitch（主文件 60 天 15–29 次）；另有 15 个站只有 1–2 次提交。

| 平台 id | 目录行数 | 60天提交 | WebView/JS/原生 | 登录/Cookie | 弹幕实现 | 测试 |
|---|---|---|---|---|---|---|
| bilibili | 884 | 12/21 | 无 | 可选 Cookie+uid；匿名 buvid3/4 | danmaku/bilibili_danmaku.dart(544) | 3 |
| douyu | 1348 | 21/24 | 无（flutter_js 在 7410eb9f 移除） | 可选 Cookie＋LTP0/dy_did 续期 | douyu_danmaku.dart(320) | 7 |
| huya | 1576 | 20/29 | 无；UA 从上游 GitHub 远程拉取 | 可选 Cookie(yyuid)；匿名身份 | huya_danmaku.dart(474)+Tars | 7 |
| douyin | 1561 | 13/15 | 无 | 可选 Cookie；匿名 ttwid | douyin_danmaku.dart(335)+proto+xbogus | 7 |
| kuaishou | 598 | 9/15 | 无 | 可选 Cookie；匿名设备会话 | kuaishou_danmaku.dart(304，HTTP 轮询) | 3 |
| cc | 542 | 13/19 | 无 | 无 | 无 | 7 |
| twitch | 1029(+utils 658) | 10/15 | **无头 WebView(Kasada)＋Android 原生 TLS 通道** | 可选 Cookie(auth-token) | twitch_danmaku.dart(176，IRC) | 3 |
| soop | 698 | 9/13 | 无 | 可选 Cookie | soop_danmaku.dart(194) | 3 |
| yy | 792(+utils 1161) | 9 | 无 | 可选 Cookie | yy_danmaku.dart(214)+utils/yy | 1 |
| acfun | 793 | 2 | 无 | 匿名游客 token | 无 | 3 |
| niconico | 1241 | 9 | 自有输入（本地中继在 player/recorder） | 会话 Cookie | 无 | 21 |
| fc2live | 1016 | 1 | 自有输入＋控制 WebSocket | 付费/登录房受限 | 无 | 2 |
| bigo | 927 | 4 | 自有输入（HLS 保护） | 探针显示 needLogin | 无 | 4 |
| chzzk | 779 | 2 | 无 | 无（有地区/成人限制） | 无 | 1 |
| missevan | 534 | 7 | 无 | 无 | 无 | 3 |
| kilakila | 913 | 8 | 无 | 无 | 无 | 7 |
| inke | 518 | 5 | 无 | 无 | 无 | 4 |
| xiaohongshu | 642 | 4 | 无 | 无（仅链接） | 无 | 4 |
| weibo | 631 | 5 | 无 | 无 | 无 | 7 |
| picarto | 578 | 4 | 无 | 无 | 无 | 2 |
| twitcasting | 508 | 4 | 无 | 需回放 HLS 会话 Cookie | 无 | 3 |
| showroom | 797 | 2 | 无 | 无 | 无 | 1 |
| pandalive | 1078 | 2 | 无 | 无 | 无 | 2 |
| 17live(目录 seventeenlive) | 721 | 2 | 无 | 无 | 无 | 1 |
| liveme | 1068 | 2 | 无 | 无 | 无 | 1 |
| tiktok | 803 | 1 | 无 | 无（仅链接） | 无 | **0** |
| youtube | 1020 | 1 | 无 | SOCS 同意 Cookie | 无 | **0** |
| steambroadcast | 799 | 1 | 无 | 无 | 无 | 1 |
| jdlive / kugoulive / baidulive / sixroom / looklive | 727/913/995/910/730 | 各 1 | 无 | 无 | 无 | 各 1 |
| iptv | 392(+core/iptv 13,842) | 6/8 | 数据库(drift)＋文件 | 无 | 无 | 2 |

### 签名与反爬

| 平台 | 算法/手段 | 位置 | 纯 Dart |
|---|---|---|---|
| B站 | WBI：w_rid=md5(query+mixinKey)，加 wts | bilibili_site.dart:433-571 | 是 |
| B站 | buvid3/4、w_webid | :32-58, :833-869 | 是 |
| B站 | 弹幕认证 support_ack/queue_uuid，op24 回 ACK | bilibili_danmaku.dart:183-195 | 是 |
| 斗鱼 | getEncryption 描述符，enc_time 轮 md5 生成 auth，与 DID 绑定 | douyu_utils.dart:38,164-185,600-647 | 是 |
| 斗鱼 | passport safeAuth 用 LTP0 续期 | douyu_utils.dart:80 | 是 |
| 虎牙 | WUP/Tars getCdnTokenInfoEx（huya_pc_exe，t=100） | huya_site.dart:384-396；core/tars；pkg/tars | 是 |
| 虎牙 | AntiCode：wsSecret=md5(fm 模板)，seqid/ctype | huya_site.dart:1065-1130 | 是 |
| 虎牙 | HYSDK UA 取自上游仓库 play_config.json | huya_site.dart:361-372 | 是，但依赖上游仓库 |
| 抖音 | a_bogus（SM3+RC4，用 dart_sm） | utils/douyin/abogus.dart(732) | 是 |
| 抖音 | msToken、ttwid、__ac_nonce | douyin_utils.dart:34-99；douyin_site.dart:68-83,587-600 | 是 |
| 抖音 | 弹幕 signature（X-Bogus 式） | douyin_danmaku.dart:306-330；xbogus.dart | 是 |
| 快手 | 匿名设备 did＋CookieJar，随机 UA；弹幕绕开签名 WS，改走移动端 feed | kuaishou_site.dart:317-387,505-527；kuaishou_danmaku.dart:38-44 | 是 |
| Twitch | Client-Integrity＋Kasada KPSDK | twitch_site.dart:29-37,177-300；twitch_web_integrity.dart:24-26 | **否** |
| SOOP | AID 令牌 | soop_site.dart:299,525-539 | 是 |
| Bigo / LOOK / 克拉克拉 | AES（pointycastle），克拉克拉另有 md5 链接签名 | bigo_token.dart；look_live_api.dart:113-143；kilakila_link.dart:18-23,108 | 是 |
| LiveMe / 百度 | md5＋写死的密钥 | liveme_signer.dart:20-47；baidu_live_api.dart:320-323 | 是 |
| AcFun / YouTube / Steam | 游客 token / INNERTUBE key / viewertoken | acfun_api.dart:66-87；youtube_api.dart:200,216；steam_broadcast_api.dart:211 | 是 |
| CC / YY | 未发现签名 [待确认] | — | 是 |

目前没有任何 JS 执行，但 `plugins/built_in_kotlin/flutter_js`（2.3 MB）还留在仓库里，已不在 pubspec 中 [待确认可删]。唯一依赖 WebView/原生通道的是 Twitch。

## ② 依赖与耦合

| 依赖 | 位置（文件:行） | 解耦方式 |
|---|---|---|
| 失败时用 GetX 取 PlayerController 当前房间兜底 | douyu_site.dart:488-489；huya_site.dart:734-735；bilibili_site.dart:663-664；kuaishou_site.dart:410-411；soop_site.dart:353,362,436；cc_site.dart:266；yy_site.dart:640 | 适配器只抛 SiteFailure；“保留上次元数据”交给仓库层 |
| 从 SettingsService 读 Cookie | bilibili_site.dart:23-24；huya_site.dart:207,526,600,821,982,1203；douyu_utils.dart:327,335,577,586；douyin_site.dart:49-50；douyin_search.dart:29；kuaishou_site.dart:501,506；twitch_site.dart:58；soop_site.dart:193；yy_site.dart:34 | 注入只读的 `CredentialStore` |
| 续期后写回 Cookie | douyu_utils.dart:499-502 | 走 `CredentialStore.save`，由 live_store 加密落盘 |
| 代理设置 | twitch_site.dart:178,223,269；http_client.dart:36 | live_net 注入 NetworkPolicy |
| 弹幕过滤开关 | douyu_site.dart:71 | 过滤移到 live_danmaku 管线 |
| 首页平台顺序 | sites.dart:420 | 移到界面层 |
| IPTV 用 Get.find<DbService> 和 Settings | iptv_site.dart:30,67,73,114,136,148,366 | 把 IPTV 移出 live_core |
| 通过 `common/index.dart` 间接引入 flutter/material、GetX、控制器、路由 | 12 个站点文件，如 bilibili_site.dart:5、huya_site.dart:6、sites.dart:32；kuaishou/soop/twitch/yy 的弹幕文件第 4–6 行 | 禁止导入这个汇总文件，用 lint 强制 |
| flutter/foundation | bigo_api.dart:6（kIsWeb）；bilibili_danmaku.dart:8；huya_danmaku.dart:4 | 改用 package:meta |
| i18n：19 个文件共 110 处 | 如 chzzk_site.dart:242-246；sites.dart:218-266；core_error.dart:30-44 | 只返回枚举或键，由界面本地化 |
| CoreLog 依赖 GetX＋LogController | core_log.dart:4-10（16 个文件在用） | 注入 Logger |
| HttpClient 全局单例 | http_client.dart:26-40 | 每站注入客户端 |
| 原生通道 | android_native_http.dart:5,16，调用处 twitch_site.dart:126,156,224 | live_net 提供 PlatformTlsTransport 接口，由应用实现 |
| WebView | twitch_web_integrity.dart:6,189；webview_proxy_scope.dart:4 | 可选的 `BrowserAttestor` 接口，由应用注入 |
| 反向依赖录制层/播放层 | niconico_quality_catalog.dart:7 引用 recorder；live_room.dart:1 引用 player 的音量管理 | HLS 读取下沉到包内；音量移出模型 |
| 外部代码直接读适配器内部 | playback_header_resolver.dart:52-140（读静态 buvid3、playUserAgent、DouyinSite.cookie）；player_manager.dart:42、recorder_controller.dart:17（HuyaTransportPolicy）；account_controller.dart:7 | 请求头、租期、线路身份写进 StreamLine |

另外，lib/ 其他 30 个文件里有 326 处 `Sites.xxxSite` 分支（local_interaction_controller 51 处、search_capability 34 处、room_external_opener 33 处）；探针只能用 `flutter test` 跑（all_sites_playback_probe_test.dart:6）。

## ③ 技术债（按风险×收益排序）

| # | 问题 | 证据 |
|---|---|---|
| 1 | 错误被吞掉或只剩字符串 | 详情请求失败时返回“状态未知”的房间（7 个站，live_room.dart:874），因此不得不另造严格接口（live_site.dart:314-331）；`throw Exception(e.toString())` 共 8 处（如 bilibili_site.dart:91,127,149）；B站 -352 靠 `toString().contains` 判定（bilibili_site.dart:104 → area_rooms_controller.dart:25,60,87）；HttpError 继承 Error 且 toString 会本地化（core_error.dart:3,20）；弹幕错误回调传的是中文句子（douyu_danmaku.dart:81,86） |
| 2 | 平台层依赖 UI 和全局状态 | 见② |
| 3 | 取流结果不自描述 | 请求头由播放层按平台分支拼（playback_header_resolver.dart:52-140）；租期是以 URL 为键的旁路接口（live_site.dart:184-193），外加静态表（douyu_site.dart:33） |
| 4 | 可选能力靠 13 个标记接口加 `is` 检查 | live_site.dart:144-331；live_directory.dart:17-41；消费方约 25 处，如 stream_resolver_service.dart:133,190,358,377；player_controller.dart:368,716 |
| 5 | 基类默认返回空，“不支持”和“无结果”分不开 | live_site.dart:195-259；`LiveSite()` 被当成“全部”的占位（sites.dart:433）；详情有 3 个变体（:223/:311/:331） |
| 6 | 用 dynamic 传递平台数据 | live_room.dart:285-287；live_play_quality.dart:8；`start(dynamic)` 后再 `as` 转换（bilibili_danmaku.dart:98-101）；detail.data 共 44 处 |
| 7 | 状态归属混乱 | 静态缓存（bilibili_site.dart:32-34,433-436；douyin_site.dart:35；huya_site.dart:56）和实例缓存并存，而 Sites.of 每次都新建实例（sites.dart:269-275） |
| 8 | 无用 API 和职责混杂 | getLiveStatus、searchAnchors 在 lib 中没有任何调用；getSuperChatMessage 放在 LiveSite（live_site.dart:256）；`getCategores(1,1000)`（areas_list_controller.dart:29）；站点 id 与目录名不一致：`17live` 对 seventeenlive（sites.dart:74） |

## ④ 处置建议

| 处置 | 平台 | 依据 |
|---|---|---|
| 首批重写 | bilibili、douyu、huya、douyin、kuaishou | 维护热点；签名都已是纯 Dart；探针都能取到媒体（PLATFORM_PROBE_2026_09_25） |
| 第二批 | cc、yy、soop、acfun、twitch | 主流平台，或有弹幕、或维护活跃；Twitch 要等 live_net 提供平台 TLS 和 BrowserAttestor 接口 |
| 第三批（低成本，可作规则包候选） | chzzk、missevan、kilakila、inke、picarto、twitcasting、showroom、pandalive、17live、liveme、steambroadcast、sixroom、kugoulive、jdlive、baidulive、looklive、weibo | 已是新一代结构、纯 Dart、公开接口；多数只有 1–2 次提交，缺少用户量证据 [待确认] |
| 等 live_media 就绪后迁移 | niconico | 需要 WebSocket 座位加本地中继；测试最全（21 个） |
| 建议下线 | tiktok、youtube | 0 测试；没有公开目录，只能靠链接导入；只有 1 次提交 |
| 建议下线 | bigo | 探针显示需要登录（needLogin），而应用没有登录实现；还需要自有输入 |
| 建议下线 | fc2live | 分片签名绑定出口 IP（代理轮换就 403）；付费/登录房受限；需要自有输入 |
| 评估 | xiaohongshu | 只能通过分享链接进入，建议降级为“仅链接”或下线 |
| 不再算作站点 | iptv | 是本地数据源，移出 live_core |

## ⑤ 必须继承的行为与坑

| 现象 | 根因 | 正确做法 | 提交/测试 |
|---|---|---|---|
| 斗鱼原画每 5 分钟断一次 | 匿名 URL 带 expire=300，CDN 从签发起算 300 秒断开 | 租期 = 签发时刻 + expire；到期前 45 秒续签同线路同画质，在关键帧处拼接 | 31982153；flv_splice_relay_test；tool/probes/douyu_splice_probe_test |
| 斗鱼 403，响应只有 4 字节 | 加密描述符、签名、Cookie 用了不同的 DID；LTP0 混进了播放 Cookie | 三处统一 DID，描述符按 DID 失效；LTP0 只发给 passport | 2c378d76；platform_signing_utils_test |
| 斗鱼画质顺序颠倒、线路画质混杂 | rate 是不透明的请求码（原画是 0） | 保留接口给出的顺序；按服务端确认的 rate 给线路分组 | douyu_site.dart:172,255；03234c7d；douyu_quality_ack_test |
| 斗鱼报“输入流地址格式错误” | 把 CDN 基址当成媒体地址，或给已是绝对地址的 rtmp_live 又拼了前缀 | rtmp_live 是绝对地址时优先用；基址不能作为输入 | douyu_site.dart:400-426；douyu_playback_parser_test |
| 斗鱼 Cookie 已失效仍显示登录 | 网页版 dy_auth 不透明，H5 版是 JWT | 按令牌类型判断；网页版按保存时间 + 7 天；失败先续期再重试 | ce49cea3、44c2a940、5b48694d；douyu_cookie_session_test |
| 虎牙 FLV 约 2 分钟 EOF | 用了网页模板的短连接；把凭据到期当成连接截止 | 优先用 WUP 原生凭据；已建立的连接可以越过凭据期继续播，到期只预取、不重开 | 8a6fdce1；huya_transport_policy_test |
| 虎牙签名失效 | 本地延长 wsTime；假设 fm 模板结构；HLS 套用了 FLV 令牌 | 不延长 wsTime；整体替换服务端 fm 模板；HLS 和 FLV 令牌分开；每次打开都生成新 seqid | huya_site.dart:1063-1130；huya_play_url_test |
| 虎牙刷新后跳到别的线路 | 按列表下标选线 | 按 CDN 主机、格式和凭据类型识别线路 | huya_transport_policy.dart:3-48；4df2f98d |
| B站选了高画质但没生效 | 游客请求被服务端降档 | 以 current_qn 为实际画质；选项取自该编码的 accept_qn | bilibili_site.dart:173-213；bilibili_play_quality_test |
| B站登录后没有弹幕 | 认证包缺新字段、没回 ACK；uid 和 Cookie 不一致 | 发送 support_ack/queue_uuid/scene，回 op24 ACK；uid 取同一份 Cookie 里的 DedeUserID | 52db99fb、9b4eb33b；bilibili_danmaku_protocol_test |
| 抖音多画面黑屏 | 纯音频档 ao 被当成最低画质 | 过滤 only_audio/ao | 56cd4d97；douyin_playback_parser_test |
| 抖音弹幕连不上 | 签名里的 `+`、`/` 没编码；只连一个节点 | 签名做 URL 编码；多个 webcast100 节点故障切换 | douyin_danmaku.dart:65-72,170-177；f491afd7 |
| 快手搜索没有房间 | 匿名直播搜索返回“服务器繁忙” | 改用公开的主播搜索 | 2753a910；kuaishou_author_search_test |
| 快手弹幕 | 桌面端 WebSocket 需要签名 | 改用移动端 feed 串行轮询 | kuaishou_danmaku.dart:38-44；kuaishou_danmaku_test |
| 录制被误停 | 详情请求失败被当成“已下播” | 严格详情：传播错误，只有平台明确说下播才算下播 | live_site.dart:314-331；douyu_site.dart:510-512；233d858d |
| 恢复时重开了过期地址 | 恢复逻辑复用了缓存 URL | 恢复必须重新获取身份和令牌 | live_site.dart:164-169；douyu_playback_parser_test |
| 录制启动慢 | 给所有 CDN 都签了名 | 录制只签当前使用的线路 | live_site.dart:148-155；huya_play_url_test |
| CHZZK 受限直播导致整页失败 | v2 接口对这类直播直接返回 500/9004 | 改用 v3.1 接口，按 krOnlyViewing 标为地区限制 | 5a33808b |
| FC2 报格式错误 | 播放列表没有 .m3u8 后缀 | 按内容识别 HLS | dffc351d |
| Twitch 在 Android 上连接被重置 | dart:io 的 TLS 在代理 CONNECT 之后被重置 | 先用原生 TLS 重试，再退到 Chromium 完整性校验 | twitch_site.dart:122-126；aeb8651b |
| 取消一个请求影响了别的请求 | 取消时关闭了共享客户端 | 取消只作用于自己的请求 | live_quality_discovery.dart:9-11；a482e576 |

## ⑥ 对 v4 live_core 接口的建议

| 建议 | 依据 |
|---|---|
| 可选能力用 getter 返回 null 表示不支持：`CatalogSource? catalog`、`SearchSource? search`、`DanmakuSource? danmaku`、`AccountSource? account`，另有必有的 `RoomSource room`、`StreamSource streams`、`LinkResolver links`；平台元信息放进 SiteDescriptor；不再用 `is` 检查 | ③-4、③-5 |
| 统一的 sealed `SiteFailure`：Network、RateLimited、RiskControl、NeedLogin、RegionRestricted、AgeOrPaid、NotFound、ApiChanged、StreamUnavailable、Cancelled。可直接由新站 23 个 XxxFailure 枚举合并得到；下播/封禁/回放属于房间状态，不算失败 | ③-1 |
| 详情只有一个 `detail(ref, depth)`，永不吞错 | live_site.dart:314-331 |
| `StreamLine` 包含 uri、format、headers、cdnId、画质确认（请求/实际/是否确认）和租期；`Lease` 包含 issuedAt、refreshAt、invalidAt、cutsConnection。斗鱼 cutsConnection=true（拼接），虎牙原生 FLV 为 false（只预取） | ③-3 |
| `StreamSource` 提供 `streams(lines: all/only(i))`、`renew(line)`、`recover(ref)` | live_site.dart:148-175 |
| 会话型流用 `StreamLine.session(opener)`，由 live_media 中继 | niconico、FC2、Bigo |
| 注入 `SiteContext`：网络传输（含平台 TLS）、CredentialStore、Clock、Random、Logger、可选 BrowserAttestor；每个方法都必须带取消令牌 | ② |
| 弹幕输出 `Stream<DanmakuEvent>`（sealed）加连接状态流；参数用强类型；SC 拉取归入 DanmakuSource | ③-6、③-8 |
| 分页返回不透明游标，不按条数判断是否结束；只返回枚举或键，不返回文案；站点 id 与目录名一致 | live_directory.dart:5-6；sites.dart:74 |
| 每站保存脱敏响应样本做离线测试；探针用 `dart run live_cli` | all_sites_playback_probe_test.dart:6 |
