# Q01 请求和编码

所有 HTTP 请求共用的那一层：`LiveHttp` 接口和它在 `dart:io` 上的实现、请求和响应的形状、超时和取消、请求头和 User-Agent 的规则、失败诊断、按平台限速、错误类型，以及纯 Dart 的 Brotli 解码器。

## 范围

- 包括：
  - `packages/live_net/lib/src/` 里除代理（Q02）和 WebSocket（Q03）以外的部分：`live_http.dart`、`io_http.dart`、`request.dart`、`response.dart`、`streamed_response.dart`、`calls.dart`、`headers.dart`、`user_agent.dart`、`diagnostics.dart`、`throttled_http.dart`、`transport_failure.dart`、`cookies.dart`（`CookieVault` 接口）、`codec/`（Brotli）、`testing/replay_http.dart`（样本回放）。
  - 应用里把它接起来的地方：`apps/pure_live/lib/app/bootstrap.dart:150-160`（`LoggingHttp(IoLiveHttp(proxy:))`，失败写进应用日志）。
- 不包括（归哪里）：
  - 代理选路、地址纠错、镜像和竞速 → [Q02](../Q02-代理和镜像/README.md)（`proxy.dart`、`race.dart`）；WebSocket 和原生通道 → [Q03](../Q03-原生HTTP和WebSocket/README.md)。
  - 各平台的请求头、签名、Cookie 怎么拼 → E 组；平台用的 `BrowserUserAgent.clientHints`（快手）由平台调用。
  - Cookie 的存储和加密（`StoreCookieVault`、`SecretStore`）→ J、K 组；网络错误在界面上怎么说 → A02.1 和各页面（`failureText`）。
  - 弹幕帧里的 Brotli 和 zlib 怎么拆帧 → D01（D01.2 哔哩哔哩、猫耳）。

## 现状：做到哪、怎么工作的

- 用户看得到的：几乎没有直接的界面；表现为各平台列表、搜索、进房、更新检查能正常请求，失败时界面按状态码和失败类型给中文提示，日志页里能看到失败请求的结构摘要（不含地址参数值、Cookie、请求体）。
- 内部怎么工作：
  1. 平台、更新、字体等都拿到同一个 `LiveHttp`（`bootstrap.dart:155`：`LoggingHttp(IoLiveHttp(proxy: SettingsProxyPolicy), onFailure: AppLog.warning)`）；需要限速的平台再包一层 `ThrottledHttp`。
  2. `LiveRequest`（`request.dart:29`）带平台 `site`（选代理路线、限速、日志用）、方法、地址、请求头、请求体、超时（默认 20 秒，`:25`）、`CancelToken`（`:7`）；`LiveRequest.withQuery`（`:128`）把参数接在原查询串后面，原有部分逐字节保留（签名参数不被重新编码）。
  3. `IoLiveHttp`（`io_http.dart:17`）每条代理路线一个 `HttpClient`（`:29-39`：连接超时 20 秒、空闲 30 秒、`autoUncompress` 处理 gzip 和 deflate、`findProxy` 固定为这条路线）；`send`（`:42`）读完整响应，`open`（`:62`）流式读（块之间也有超时）；取消时直接断开连接；`failureOf`（`:144`）把 `dart:io` 的异常归成 `TransportFailure`（连接、超时、取消、协议……）。没有设 User-Agent 的请求保留 `dart:io` 的默认值（虎牙搜索没有 UA 会 403）。
  4. `calls.dart` 的扩展 `LiveHttpCalls`（`:13`）：`getText`、`getJson`（不管 Content-Type 都按 JSON 解析）、`postJson`（三种请求体）、`head`（任何状态码都返回）、`download`（先写 `.part`，200/206 读完才改名，失败删掉 `.part`）。非 2xx 抛 `HttpStatusFailure`（`transport_failure.dart:45`，带状态码、256 字符内容预览、响应头）。
  5. `HttpHeaderPolicy`（`headers.dart:9`）：别名（`http-user-agent`、`referrer`、`cookies`、前导 `!`）、去控制字符、按名字排序，`encode`/`decode` 给需要存请求头的地方（录制任务）。
  6. `BrowserUserAgent`（`user_agent.dart:14`）：Chrome 153～155、Edge 153～154、Safari 26.6/27.0，按 UA 精简写法（`<主版本>.0.0.0`），`clientHints` 和所选浏览器一致。
  7. `LoggingHttp`（`diagnostics.dart:15`）：失败（含非 2xx）时调 `onFailure`，只记来源、方法、状态码、路径段数、查询参数名、请求头名、请求体和响应体大小，不像字段名的键写 `(redacted-key)`；取消不算失败。
  8. `brotliDecode(data, maxOutput:)`（`codec/brotli.dart:25`）：一次性解一个完整 Brotli 流，坏数据抛 `FormatException`，`maxOutput` 在读到元块长度时就拒绝“解压炸弹”。哔哩哔哩弹幕 protover 3（`packages/live_danmaku/lib/src/sites/bilibili.dart:327`、`:452`，16 MiB 上限）和猫耳弹幕（`missevan.dart:255`，帧头给出解压长度）在用。
- 完成度（和 3.x 对照）：
  - 一致：20 秒超时的语义（整个请求、等响应头、块之间）；查询串保留；请求头规范化；`getText` 等五种用法；失败日志只记结构（移植 3.x 的 4 个用例）；`raceJson`、`fastestUrl` 的行为（Q02）。
  - 确认过的改动：dio 单例换成注入的 `LiveHttp`；网络层不依赖设置和界面（错误不再调 `i18n`）；`request_scope.dart` 的取消补丁删除（`dart:io` 取消即断开）；UA 表更新到当前版本；`fetchText`（GBK 回退，没有调用方）不保留，GBK 由 L01.1 处理。
  - 多了：Brotli（3.x 没有，哔哩哔哩只能用 protover 2）；`ThrottledHttp`；`ReplayHttp`（测试回放录下的样本）。

## 代码地图

`packages/live_net/lib/src/`：

| 文件 | 职责 |
|---|---|
| `live_http.dart`（20 行） | `LiveHttp` 接口（`:8`）：`send`、`open`、`close` |
| `io_http.dart`（223） | `IoLiveHttp`（`:17`，每条路线一个客户端 `:29-39`、`send` `:42`、`open` `:62`）、`failureOf`（`:144`）、`_Exchange`（`:156`，超时和取消的竞速） |
| `request.dart`（139） | `CancelToken`（`:7`）、`defaultRequestTimeout` 20 秒（`:25`）、`LiveRequest`（`:29`，`get` `:46`、`form` `:57`、`json` `:80`、`withQuery` `:128`） |
| `response.dart`（40）、`streamed_response.dart`（43） | `LiveResponse`（`:7`，`header` 不分大小写、`isSuccess`）；`LiveStreamedResponse`（`collect` `:34`、`discard` `:40`） |
| `calls.dart`（146） | `LiveHttpCalls`（`:13`）：`getText` `:15`、`getJson` `:28`、`postJson` `:41`、`head` `:83`、`download`（`.part` 和改名，`:118-140`） |
| `headers.dart`（61） | `HttpHeaderPolicy`（`:9`）：`normalize` `:15`、`canonicalName` `:32`、`encode` `:45`、`decode` `:51` |
| `user_agent.dart`（105） | `BrowserUserAgent`（`:14`，`random` `:20`，版本表 `:65-71`，`clientHints`） |
| `diagnostics.dart`（141） | `LoggingHttp`（`:15`）和结构摘要 |
| `throttled_http.dart`（60） | `ThrottledHttp`（`:10`）：按平台的最小间隔 |
| `transport_failure.dart`（82） | `TransportReason`（`:5`）、`TransportFailure`（`:24`）、`HttpStatusFailure`（`:45`，`of` `:55`） |
| `cookies.dart`（38） | `CookieVault`（`:6`）、`MemoryCookieVault`（`:15`，测试用） |
| `codec/brotli.dart`（759）、`brotli_tables.dart`（303）、`brotli_dictionary.dart`（1474，生成） | `brotliDecode`（`:25`）；RFC 7932 的表；静态字典（`tools/brotli/gen_dictionary.py` 生成） |
| `testing/replay_http.dart` | `ReplayHttp`（`:83`）：测试里按录下的样本回答 |

应用：`apps/pure_live/lib/app/bootstrap.dart:150-160`（建客户端、失败进日志 `AppLog.instance.warning('http', …)`）；`app/services.dart`（`AppServices.http` 交给各处）。

测试（`cd packages/live_net && dart test`，按 `test(` 计 84 个）：

| 测试文件 | 覆盖什么 |
|---|---|
| `io_http_test.dart`（13） | 文本和重复响应头、表单、重定向、4xx 也是响应、gzip、超时、取消、连接被拒、按平台走代理；流式读、块间超时、读取中取消、等响应头超时 |
| `request_test.dart`（7）、`calls_test.dart`（7） | 查询串原样保留、默认 20 秒、表单和 JSON；`getText`/`getJson`/`postJson`、`HttpStatusFailure` 预览、`head`、下载的改名和进度、206、失败删 `.part` |
| `diagnostics_test.dart`（5） | 不泄露签名地址、载荷、凭证；日志函数出错不影响原失败；大响应体只记大小；取消不记 |
| `headers_user_agent_test.dart`（5） | 请求头规范化和编解码；UA 五种组合、格式、客户端提示一致 |
| `throttle_replay_test.dart`（4） | 按平台限速、样本回放 |
| `brotli_test.dart`（16 个 `test`，含按向量组循环的用例） | 表的 CRC 和 SHA-256；与参考解码器逐个一致（官方、参考编码器、自造流 531 个，变异 2447 个）；`maxOutput` 和解压炸弹；截断、随机字节；猫耳真实帧 |
| `proxy_test.dart`（8）、`race_test.dart`（6）、`socket_test.dart`（13） | 见 Q02、Q03 |

## 3.x 基线

文件都在 `git show v3.2.11:lib/` 下（逐个对照见 [Q01.1 记录](Q01.1-网络/record.md)“对照”表）：

- `core/common/http_client.dart`（228 行）：dio 单例，`getText`、`getJson`、`postJson`、`head`、`download`；代理经 GetX 读设置（`:35-53`），改设置要重建 dio；下载失败留 `.part`（`:160-200`）；为 `json;charset=utf-8` 专门写转换器（`:217-228`）。
- `core/common/custom_interceptor.dart`（74）：失败诊断；`core/common/http_header_policy.dart`（53）：请求头规范化（4.x 行为不变）；`core/common/request_scope.dart`（20）：dio 取消补丁；`core/common/core_error.dart`（47）：`HttpError` 直接调 `i18n()`（`:22-46`）。
- `plugins/fake_useragent.dart`（153）：macOS 版本号被 `replaceAll(RegExp(r'.'), '-')` 变成横线（`:13`、`:15`）、Safari 用了 Chrome 的版本号（`:88`）、版本停在 2021～2023 年。
- `plugins/race_http.dart`（129）：竞速不提前结束、赢家出来后不取消其余（`:100-129`）。
- 3.x 没有 Brotli 解码（pub 的 `brotli` 0.6.0 要求 SDK <3.0.0），哔哩哔哩弹幕用 protover 2（zlib）。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| HTTP 响应的 `content-encoding: br` 不会自动解：`IoLiveHttp` 只开了 `dart:io` 的 `autoUncompress`（gzip、deflate），Brotli 解码器只用在弹幕帧上；现在没有平台的请求头里带 `accept-encoding: br`（全仓库搜不到） | `io_http.dart:34`；`codec/brotli.dart` | 以后有平台请求头写了 `br`、服务器真的回 Brotli 时，响应体是乱码 | 不做；平台加 `accept-encoding` 时注意（E 组的规则，写进平台任务的审查清单） |
| 各平台写死的浏览器 UA 版本不一（Chrome 140 有 20 处、128、138、137、134、114 各几处），`BrowserUserAgent` 是 153～155，更新检查用 151 | `packages/live_core/lib/src/sites/` 各平台；`apps/pure_live/lib/features/version/update_feed.dart:335-338` | 外观不统一；平台按实测的 UA 工作，改了可能被风控 | 不统一改；某个平台因为 UA 被拦时在 E 组开任务 |
| Brotli 只有一次性接口，整个输出放在内存里；不支持大窗口和共享字典 | `codec/brotli.dart:25` | 弹幕帧只有几百字节到几 KB，没有影响 | 不做（Q01.2 记录“限制”） |
| Q01.1 的记录写 64 个用例，之后加了 Brotli 和若干用例，现在包里按 `test(` 计 84 个；Q01.2 记录写 18 个 Brotli 用例（按用例展开计），按 `test(` 计 16 个 | 两个任务的记录 | 数字口径不同，不影响 | 本说明以现在的代码为准 |
| 代码注释里的旧编号（M1、M4.D、M7） | `io_http.dart:36` 等 | 找文档先查 MAPPING | Z 组统一替换 |

## 相关决定和规范

- D-017：网络测试在本机回环上起真实服务，不访问真实平台；定时器至少 1 秒。
- D-018：网络设置（代理、镜像）的 3.x 键名不变（见 Q02）。
- [specs/ENGINEERING.md](../../specs/ENGINEERING.md) 第 4 节：`live_net` 只依赖 `meta` 和 `dart:io`（`tools/gate/check_deps.py`）；样本隐私（`fixtures/README.md` 的脱敏规则，门禁查）。
- [specs/UPGRADES.md](../../specs/UPGRADES.md) 附录 B-3（哔哩哔哩 protover 3，用 Q01.2 的解码器，完成）。

## 测试和验证

- 自动测试：`cd packages/live_net && dart test`（84 个；Brotli 单独约 7 秒，坏数据各在独立 isolate 里跑、带 2 分钟总超时）。重新生成 Brotli 向量见 [Q01.2 记录](Q01.2-Brotli解码/record.md)“测试”。
- 真机：没有单独的清单条目；网络层随 [CHECKLIST](../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 1、4 节的各平台请求一起验证（S02.2、S02.3 看过国内平台）；哔哩哔哩弹幕 protover 3 随第 2 节第 1 条。

## 路线

1. 没有排着的任务；Q01 的代码稳定。
2. 维护时：UA 表每半年按当前浏览器版本更新一次（`user_agent.dart:65-71`，Z 组的定期维护）；平台加 `accept-encoding` 时检查是否会回 Brotli。
3. 以后：Windows 的 WinHTTP 通道（X01.2，Kick 在 Windows 上要它）走 `LiveHttp` 接口接入，不改本子分类。新想法写进 V01 提议。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [Q 网络和代理](../README.md)。

- 代码：`packages/live_net`
- 进度：`████████████████████` 100%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| Q01.1 | 网络：HTTP 客户端、拦截器、请求头策略、代理路由、WebSocket | 功能 | 完成 | 2026-09-28 | 9b70c640d | [设计或说明](Q01.1-网络/README.md)、[记录](Q01.1-网络/record.md) |
| Q01.2 | Brotli 解码（猫耳弹幕、哔哩哔哩 protover 3） | 功能 | 完成 | 2026-09-29 | a2b5c0610 | [设计或说明](Q01.2-Brotli解码/README.md)、[记录](Q01.2-Brotli解码/record.md) |

<!-- docs:生成结束 -->
