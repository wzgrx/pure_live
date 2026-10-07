# Q01.1 网络：HTTP 客户端、拦截器、请求头策略、代理路由、WebSocket

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能（模块重构）
- 来源：4.x 逐块重构计划（D-001）的第一块：把 3.x `lib/core/common/` 的网络部分（dio 客户端、拦截器、请求头策略、代理路由、WebSocket 工具、错误类）和 `lib/plugins/` 的竞速请求、伪造 UA 搬进纯 Dart 包 `packages/live_net`
- 旧编号：M1、T03a.1
- 相关：决定 D-001、D-017；后续 [Q01.2](../Q01.2-Brotli解码/README.md)（Brotli）；用它的：E 组所有平台、D01 弹幕连接、G01 播放中继、Y02 更新、I01.3 字体；原生通道和本地网络权限当时“放到 I01.1”；记录 [record.md](record.md)

## 目标

- 网络层不再依赖 GetX 设置单例、界面翻译和 Flutter 插件：一个只依赖 `meta` 和 `dart:io` 的纯 Dart 包，能用 `dart test` 测、能给命令行工具用。
- 代理不再是全局可变状态：每个请求、每次握手按平台读一次 `ProxyPolicy`，改设置不用重建客户端。
- 行为照 3.x（超时、查询串、请求头规范化、代理纠错、WebSocket 重连、竞速），同时修掉审查发现的 13 个 3.x 问题。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11`，文件:行） | 现在（文件:行） | 结果 |
|---|---|---|---|
| HTTP 客户端 | `lib/core/common/http_client.dart`（228 行，dio 单例；代理经 GetX 读设置 `:35-53`） | `packages/live_net/lib/src/io_http.dart:17` `IoLiveHttp`（每条代理路线一个连接池）、`calls.dart:13` 的五种用法 | 注入，不读设置 |
| 失败诊断 | `custom_interceptor.dart`（74） | `diagnostics.dart:15` `LoggingHttp` | 只记结构；取消不记 |
| 请求头规范化 | `http_header_policy.dart`（53） | `headers.dart:9` | 不变 |
| 代理路由 | `proxy_routing.dart`（78；`:70` 局域网只看前两段） | `proxy.dart`（`proxyRouteFrom` `:108`、`isLocalNetworkProxyHost` `:121`） | 四段都校验；按平台选路 |
| 取消补丁 | `request_scope.dart`（20） | 删除 | `dart:io` 取消即断开 |
| WebSocket | `web_socket_util.dart`（354；代理是全局可变函数 `:17-60`） | `socket.dart:135` `LiveSocket`、`:74` `connectIoSocket` | 重连规则不变，代理注入 |
| 错误类 | `core_error.dart`（47；直接调 `i18n()` `:22-46`） | `transport_failure.dart`（`TransportFailure` `:24`、`HttpStatusFailure` `:45`） | 文字由界面层给 |
| 竞速请求 | `plugins/race_http.dart`（129；不提前结束 `:100-129`） | `race.dart`（`raceFirst` `:14`、`raceJson` `:54`、`fastestUrl` `:72`） | 全部结束即返回，赢家出来取消其余 |
| 伪造 UA | `plugins/fake_useragent.dart`（153；`:13`、`:15`、`:88` 的数据错误） | `user_agent.dart:14` `BrowserUserAgent` | 版本更新、格式按 UA 精简 |

## 结果

- 改动（提交 `9b70c640d`，2026-09-28，“feat(live_net): network layer refactored from v3 (M1)”）：
  - c1 `LiveHttp` 接口、`IoLiveHttp`、`LiveRequest`/`LiveResponse`/`LiveStreamedResponse`、`getText`/`getJson`/`postJson`/`head`/`download`（来自归档 v4 的传输核心，加上 3.x 的用法）。
  - c2 `HttpHeaderPolicy`、`BrowserUserAgent`（含和浏览器一致的客户端提示，快手用）。
  - c3 `ProxyPolicy`、`FixedProxyPolicy`、`proxyRouteFrom`、地址和端口纠错、局域网判断。
  - c4 `LiveSocket`（失败立即换地址、每轮多等一点最多 6 倍、连续 8 次放弃、有消息清零、半开检测 max(3 个心跳, 90 秒)、关闭握手最多 2 秒、每次握手读代理）。
  - c5 `raceFirst`、`raceJson`、`fastestUrl`、`GitHubMirror`。
  - c6 `LoggingHttp`、`ThrottledHttp`、`CookieVault`、`ReplayHttp`。
- 修掉的 3.x 问题 13 个（记录“审查发现的 v3 问题”表：macOS UA 版本号成横线、Safari 版本抄错、UA 版本过旧、快手客户端提示不一致、竞速不提前结束、`fetchText` 死代码、代理读全局单例、WebSocket 代理全局可变、网络层调翻译、下载失败留 `.part`、`192.168.1.999` 算局域网、取消记成错误、JSON 转换器补丁）。
- 有意差异：dio 换成 `dart:io`；取消补丁删除；`fetchText` 不保留（GBK 归 L01.1）。
- 放到别处的：原生 HTTP 通道（Twitch、Kick）和 Android 17 本地网络权限 → I01.1（现在的 `platform/native_http.dart`、`platform/system_access.dart`，见 Q03、Q04）；网页登录的代理 → K 组；应用日志 → I01.1；HLS 工具 → G 组。
- 测试：当时 64 个，连续跑 5 次全部通过；现在包里按 `test(` 计 84 个（加了 Q01.2 的 Brotli 和后来的用例）。

## 验证

- 自动测试：`cd packages/live_net && dart test`（`io_http_test`、`request_test`、`calls_test`、`diagnostics_test`、`proxy_test`、`headers_user_agent_test`、`race_test`、`socket_test`、`throttle_replay_test`）；WebSocket 用例里有本机回声服务器的真实收发。
- 真机：没有单独的 verify.md；网络层随 K90 冒烟（[S02.2](../../../S-质量和验证/S02-真机验证/S02.2-K90冒烟/record.md)）和主流程（[S02.3](../../../S-质量和验证/S02-真机验证/S02.3-K90验证主流程/record.md)）里各国内平台的列表、搜索、进房、弹幕一起工作。代理相关的真机项（F-NET-02 播放代理、F-AND-09 原生通道、F-NET-04 Twitch 令牌）在 S02.4，还没看。

## 留下的问题

- 封面和头像的磁盘缓存没有走本包的代理（flutter_cache_manager 的默认管理器直连）：不是本任务的范围，但 3.x 是跟随应用代理的，见 [Q02 已知问题](../../Q02-代理和镜像/README.md#已知问题和限制)，需要开任务。
- 弹幕握手 UA 的 `Dart/` 前缀：本任务按 3.x 保留了“直连用默认客户端”，去掉前缀的开关在 I01.1 加了、默认关 → [Q03.1](../../Q03-原生HTTP和WebSocket/Q03.1-弹幕握手的UA去掉Dart前缀/README.md)。
