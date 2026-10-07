# E03.2 Twitch

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：3.x 平台逐个重构（D-001）；之后的升级落地（2026-09-29，UPGRADES 8-1～8-10）、WebView 传输（2026-10-01，UPGRADES X-1）记在 [record.md](record.md)；Cookie 被拒的出口和按引擎能力请求编码在 [E06.1](../../E06-平台层升级/E06.1-已批准升级的余项/README.md)（B-7、8-8）
- 旧编号：M4.08、M4.U.8、T02c.2
- 相关：模型 [E05.1](../../E05-平台框架和模型/README.md)、[E05.2](../../E05-平台框架和模型/README.md)（登录名不分大小写，重播标回放）；链接 [E04.1](../../E04-链接解析和分享口令/README.md)；弹幕 D01.9；Cookie 提示和编码接到应用 [E06.2](../../E06-平台层升级/E06.2-平台层新数据接到界面/brief.md) 第 4 阶段；原生 TLS 通道在 Q 组；决定 D-001、D-017、D-018
- 代码：`packages/live_core/lib/src/sites/twitch/`（`twitch_api.dart` 949 行解析，`twitch_site.dart` 620 行请求编排和 GraphQL 传输）；应用侧 `apps/pure_live/lib/platform/twitch_webview_http.dart`（无界面 WebView 发 GraphQL）；样本 `fixtures/twitch/`（26 组）

## 目标

把 3.x 的 Twitch 适配器（`lib/core/site/twitch/twitch_site.dart` 1029 行，直接依赖 GetX、MethodChannel、WebView）重构进纯 Dart 的 `live_core`：分类、分区、推荐、搜索、详情、播放令牌和 usher 取流、恢复、链接都和 3.x 一样。Android 上 3.x 遇到过代理在 CONNECT 后断开 `dart:io` 的 TLS、或被要求完整性令牌，做法是改走系统 TLS 和 WebView；这里把它们变成注入的“备用传输”。修掉 3.x 的 16 个问题（请求头是共享的可变 Map、过期的登录令牌让目录和搜索全部失败、搜索第 2 页和第 1 页一样、分类要 71 次请求等）。

## 平台接口要点

| 功能 | 接口 | 位置 |
|---|---|---|
| GraphQL | `POST https://gql.twitch.tv/gql`，3.x 的持久化查询哈希、Chrome 137 UA、`Client-ID`、每个适配器一个 `Device-Id`、`Accept-Language: zh-CN`（8-2）；先交给 `http`，传输失败、5xx 或完整性质询时依次交给 `gqlFallbacks`（Android 的系统 TLS、无界面 WebView） | `twitch_api.dart:76`；`app/platforms.dart:152-158` |
| 分类 | 批量请求合并各标签（3.x 桌面端 71 次）；中文下没有名字的标签多一次 en-US 请求补英文名 | `twitch_site.dart:274` |
| 分区、推荐 | 分区一次向平台要 100 个放进快照本地分页（8-10），推荐 30 个；后续页被质询时列表到此结束（注入浏览器传输后能续）；推荐和分区的游标分开、有上限；语言筛选设置 `twitchLanguages`（默认所有语言） | `:352`、`:368` |
| 搜索 | 第 2 页起把上一页的频道游标放进 `options.targets`（8-1） | `:432` |
| 详情 | 一个原始 `user` 查询（3.x 是 `ChannelShell` + `StreamMetadata`）；在播时封面用直播截图（8-5）、简介取 `description`（8-4）；`stream.type == 'rerun'` 标回放（8-9）；`stream.restriction` 填受限类型 | `:465-477` |
| 取流 | 先 `PlaybackAccessToken`（只有这个请求带用户 Cookie 和 `Authorization: OAuth`），再 usher `usher.ttvnw.net/api/channel/hls/<login>.m3u8`，`supported_codecs` 按“优先 H.264”和 `codecs:`（引擎能解的编码）给；线路带 3.x 播放层的请求头（不带用户 Cookie，8-7）；恢复重新取令牌和主播放列表 | `:485-523`；`twitch_api.dart:363-376` |
| Cookie 被拒 | 播放令牌拒绝存下的 Cookie（401 或完整性质询）时改匿名，同一份 Cookie 不再发送；`cookieRefusals` 流每份 Cookie 报一次（E06.1 c3） | `:187`、`:196`、`:576-591` |
| 弹幕参数 | `TwitchDanmakuArgs`：频道登录名（小写）和同一份 Cookie 里的聊天登录 | |
| 链接 | `twitch.tv`、`www.`、`m.`、`go.` 的频道页和 pop-out 聊天、嵌入播放器；Twitch 自己的页面（`drops`、`clips` 等）不算 | `:602` |

## 3.x 和现状

| 方面 | 3.x（`lib/core/site/twitch/twitch_site.dart`） | 现在 | 说明 |
|---|---|---|---|
| 依赖 | `:58`、`:178`、`:219`、`:223`、`:269`、`:288`、`:578` 读全局设置、MethodChannel、WebView | 纯 Dart；系统 TLS 和 WebView 作为备用传输注入 | 3.x 问题 1 |
| 请求头 | `:40-71`、`:554` 实例上的可变 Map，并发互相影响，usher 也带 Cookie | 每个请求自己的请求头；会话只随播放令牌 | 3.x 问题 2、3 |
| 失效 Cookie | `:58-66`、`:142-171` 过期令牌让所有请求失败，开关一打开整个实例不再用登录 | 被拒的那份 Cookie 不再发，换了再试；`cookieRefusals` 让界面提示一次 | E06.1 B-7（界面在 E06.2） |
| 分类 | `:433-473` 41 个标签各请求一次再递归翻页 | 批量 | 3.x 问题 12 |
| 搜索 | `:895` 游标放在顶层变量，第 2 页和第 1 页一样 | 真正翻页 | 8-1（REG-TWITCH-002） |
| 分区语言 | 只看中文和韩语 | 默认所有语言，设置可选 | 8-3 |
| 图片 | 经 `i2.wp.com` 第三方代理 | Twitch CDN 直连 | 8-7 |
| 编码 | usher 不带 `supported_codecs`，只有 H.264 | 按“优先 H.264”和引擎能力请求 HEVC、AV1 | 8-8 |
| 重播 | 卡片算直播、详情算未开播，点进去报错 | 回放，能播 | 8-9 |
| 开播状态 | `:526-533` 吞掉所有错误返回 false | 用详情结果，出错抛出 | 3.x 问题 5 |
| 画质 id | `:616` 含平均码率，重新取流时找不到原来那一档 | 同一档按名称匹配 | 3.x 问题 16 |
| 弹幕 | IRC 连接用分区卡片的数字 id 拼 `JOIN #<…>`（`twitch_danmaku.dart:87`） | 登录名 | 3.x 问题 8；D01.9 |

## 结果

- 首次重构（2026-09-28，提交 `a312c7267`）：16 个 3.x 问题、16 条有意差异见 record.md；3.x 离开 Flutter 跑不起来，冻结输出用 `fixtures/twitch/legacy_expected.py` 生成。定了 GraphQL 备用传输的接口约定（record.md“GraphQL 传输的接口约定”）。
- 升级落地（2026-09-29，`5d9911bdd`）：8-1～8-10 完成；新设置 `twitchLanguages`（默认空）和共用的 `preferH264`；开播时间取 `stream.createdAt`；受限类型读 `stream.restriction`（`SUB_ONLY` 等）。
- WebView 传输（2026-10-01，提交 `43688c03b`）：`TwitchWebViewHttp` 在 `www.twitch.tv/twitch` 空白页里发 GraphQL，只放行 `POST gql.twitch.tv/gql`，缓存 `/integrity` 令牌，账号 Cookie 不进页面，代理用 `ProxyController` 覆盖。
- 平台层余项（2026-10-02，`4f1a8b4a8`，E06.1）：`LiveSiteCookieRefusals.cookieRefusals`、`TwitchSite(codecs:)`。
- 测试：`packages/live_core/test/sites/twitch_api_test.dart` 54 个 `test(` 写法、`twitch_site_test.dart` 54 个；`apps/pure_live/test/platform/twitch_webview_http_test.dart` 7 个；弹幕 `packages/live_danmaku/test/twitch_test.dart`。

## 验证

- 自动测试：样本逐键对照 3.x 冻结输出；备用传输收到完全相同的请求；分类批量；快照分页（30/30/27/空，只请求 2 次）；重播、受限、编码参数；Cookie 被拒每份报一次。
- 真实接口：样本 2026-09-27/28 经代理录制；2026-09-29 补录 6 个样本（中文名、推荐、搜索第 2 页等）。
- 真机：没验证（[FEATURES.md](../../../inventory/FEATURES.md) 第 14 节“原生 TLS + 浏览器令牌，没验证”）；要用户开着代理，见 [S02 的 CHECKLIST.md](../../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 5 节第 7 条（进 Twitch、Kick 直播间能播）。真机上 KPSDK 能否就绪、`/integrity` 令牌是否被 GraphQL 接受都还没看。

## 留下的问题

- Cookie 失效提示和按引擎能力传 `codecs`：平台层已有，应用还没接（[E06.2](../../E06-平台层升级/E06.2-平台层新数据接到界面/brief.md) 第 4 阶段）。
- 关掉“优先 H.264”时的 HEVC、AV1 没有真实样本（G 组按硬解能力选档）。
- WebView 覆盖代理是进程级的；Windows 不注入备用传输（X 组以后再看）。
- 走到 WebView 时播放令牌是匿名的（账号不进无界面浏览器，同 3.x）。
