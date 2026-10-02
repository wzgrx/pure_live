# Q01.1 网络

- 日期：2026-09-28
- 目标包：`packages/live_net`（纯 Dart，只依赖 `meta`）
- 参考仓库核对：pure_live_TV `9fb40418`、flame_barrage `3eddae8`、media_core `34b3cca`、flv_lzc `162030d`

## 对照

| v3 文件 | 行数 | 重构后 | 说明 |
|---|---|---|---|
| `core/common/http_client.dart` | 228 | `io_http.dart`、`calls.dart`、`request.dart`、`response.dart`、`streamed_response.dart` | dio 单例改为注入的 `LiveHttp`；保留 `getText`、`getJson`、`postJson`、`head`、`download` 这几种用法 |
| `core/common/custom_interceptor.dart` | 74 | `diagnostics.dart` | 失败诊断只记结构，改成包装器 `LoggingHttp` |
| `core/common/http_header_policy.dart` | 53 | `headers.dart` | 行为不变 |
| `core/common/proxy_routing.dart` | 78 | `proxy.dart` | 地址纠错、端口校验、局域网识别；按平台选路（来自归档 v4） |
| `core/common/request_scope.dart` | 20 | 删除 | 只是 dio 5.11.1 取消不传到底层的补丁；`dart:io` 取消时直接断开连接 |
| `core/common/web_socket_util.dart` | 354 | `socket.dart` | 重连策略不变，代理改为注入 |
| `core/common/core_error.dart`（`HttpError`） | 47 | `transport_failure.dart`（`HttpStatusFailure`、`TransportFailure`） | 错误带类型；界面文字由界面层按状态码给出 |
| `plugins/race_http.dart` | 129 | `race.dart` | 修掉不提前结束、不取消其余请求 |
| `plugins/fake_useragent.dart` | 153 | `user_agent.dart` | 修掉格式错误，版本更新到当前 |

来自归档 v4 的部分：
- 传输核心：`LiveRequest`、`LiveResponse`、`TransportFailure`、`ProxyPolicy`、`IoLiveHttp`；
- `CookieVault`（Cookie 放在加密存储里，由应用实现）；
- `ThrottledHttp`（按平台限速）；
- `ReplayHttp`（测试时回放录下的样本）。

## 审查发现的 v3 问题

| # | 问题 | 位置 | 根因 | 处理 |
|---|---|---|---|---|
| 1 | 伪造的 macOS UA 里版本号整个变成横线：`Mac OS X ------` | `plugins/fake_useragent.dart:13,15` | `replaceAll(RegExp(r'.'), '-')` 里的 `.` 没转义，匹配任意字符 | 按当前浏览器的 UA 精简写法固定为 `10_15_7` |
| 2 | Safari 的版本号用的是 Chrome 的（如 `88.0.4324`） | `plugins/fake_useragent.dart:88`（`sarariVersions`） | 数据抄错（变量名也拼错） | 改为 Safari 26.6 和 27.0 |
| 3 | 版本停在 2021–2023 年（Chrome 88–110、Edge 95–106），而且写了完整构建号；Chrome 113 之后真实 UA 是 `<主版本>.0.0.0` | 同上 | 数据多年没更新 | Chrome 153–155、Edge 153–154，按 UA 精简写法 |
| 4 | 快手拼客户端提示时，随机到 Safari 也发 Chrome 的品牌；平台值没加引号 | `core/site/kuaishou/kuaishou_site.dart:489-492` | UA 和客户端提示分开拼 | `BrowserUserAgent.clientHints` 按所选浏览器给出一致的请求头；E 快手改用它 |
| 5 | 竞速请求在所有镜像都失败时不提前结束，一直等到超时（检查更新要等 30 秒）；赢家出来后其余请求继续跑；超时计时器不取消；静态 `http.Client` 从不关闭 | `plugins/race_http.dart:100-129` | `_race` 只在“拿到结果”和“超时”两处完成 | `raceFirst` 在全部结束时就返回，赢家出来后取消其余请求 |
| 6 | `fetchText`（带 GBK 回退）没有调用方 | `plugins/race_http.dart:77-98` | 死代码 | 不再保留；GBK 解码在 L01.1（IPTV 导入）处理 |
| 7 | 代理设置通过 GetX 全局读取，改设置后要重建 dio | `core/common/http_client.dart:35-53` | 网络层依赖设置服务 | 注入 `ProxyPolicy`，每个请求按平台选路 |
| 8 | WebSocket 的代理是全局可变函数 | `core/common/web_socket_util.dart:17-60` | 同上 | `LiveSocket` 注入 `ProxyPolicy`，每次握手时读取 |
| 9 | 网络错误类直接调用界面翻译 `i18n()` | `core/common/core_error.dart:22-46` | 网络层依赖界面 | `HttpStatusFailure` 只带状态码、内容预览和响应头，文字由界面层给出 |
| 10 | 下载失败或取消后留下 `.part` 文件 | `core/common/http_client.dart:160-200` | 只在成功时处理临时文件 | 失败时删除 `.part` |
| 11 | 局域网代理判断只看 IPv4 的前两段，`192.168.1.999` 也算局域网 | `core/common/proxy_routing.dart:70` | 其余两段没校验 | 四段都校验 |
| 12 | 用户取消请求也当作错误写进日志 | `custom_interceptor.dart`（dio 把取消当 `DioException`） | — | 取消不算失败，不记录 |
| 13 | 为 `json;charset=utf-8` 这类响应头专门写了转换器 | `core/common/http_client.dart:217-228` | dio 按 Content-Type 决定是否解析 JSON | `getJson` 总是按 JSON 解析，不需要这个补丁 |

上游核对：pure_live_TV 的 `shared/platform/race_http.dart` 仍有问题 5；新增的 `shared/common/browser_user_agents.dart` 是一张 2023 年的 UA 表，没有调用方，而且 `nextInt(length - 1)` 永远选不到最后一个。所以没有更新的修复可借鉴。

## 保留的 v3 行为

- **超时**：20 秒（v3 的连接、发送、接收超时）。
  - `send` 限制整个请求；
  - `open` 限制等待响应头的时间，以及响应体两个块之间的间隔（v3 的接收超时语义）。
- **查询参数**：追加在原查询串后面，原有部分逐字节保留，和 dio 一样。签名参数不会被重新编码。
- **请求头规范化**：别名（`http-user-agent`、`referrer`、`cookies`、前导 `!`）、去掉控制字符、按名字排序。
- **代理**：
  - 中文输入法打出的“。”“．”“：”“［］”都能纠正；
  - 端口不完整或越界时不用代理；
  - 主机名里带分号或换行（注入）时不用代理；
  - IPv6 地址加方括号；
  - 默认端口 7897。
- **失败诊断只记结构**：
  - 只记来源地址、方法、状态码、路径段数、查询参数名和请求头名，以及请求体和响应体的大小；
  - 不像字段名的键写成 `(redacted-key)`，最多 24 个；
  - 日志函数出错不影响原来的失败。
- **WebSocket**：
  - 失败后立刻换下一个地址，每轮之后多等一点（最多 6 倍基础间隔）；
  - 连续失败 8 次就放弃；收到任何消息，失败计数清零；
  - 心跳期间超过 max(3 个心跳间隔, 90 秒) 没有消息，就当作半开连接替换掉；
  - 关闭时中止挂起的握手，等待关闭握手最多 2 秒；
  - 直连时用 `dart:io` 默认客户端。v3 实测 Android 上自定义一个只回答 DIRECT 的客户端，会让握手挂到超时。
- **竞速请求**：`raceJson` 取第一个 200 的 JSON 对象；`fastestUrl` 用 1 字节的范围 GET 探测镜像，接受 200 和 206。
- **下载**：先写 `<目标>.part`，200 或 206 完整读完才改名；有进度回调。
- **HEAD**：任何状态码都返回。

## 放到其他模块的部分

| v3 文件 | 去向 | 原因 |
|---|---|---|
| `core/common/android_native_http.dart` | E Twitch、I01.1 原生 | Android 上 Twitch 的 GraphQL 要走系统 TLS（经过 HTTP CONNECT 代理后，`dart:io` 的 TLS 连接会被断开），需要 Flutter 通道。做法：应用给 Twitch 注入一个走原生通道的 `LiveHttp` |
| `common/services/local_network_access.dart` | I01.1 | Android 17 的局域网权限；本包的 `isLocalNetworkProxyHost` 提供判断 |
| `core/utils/webview_proxy_scope.dart` | M13 账号 | 网页登录的代理 |
| `core/common/core_log.dart`、`log.dart` | I01.1 | 应用日志；本包只提供 `LoggingHttp.onFailure` |
| `core/common/hls_*.dart` | G | 属于播放 |
| `core/common/binary_writer.dart`、`convert_helper.dart` | E05.1 | 属于基础工具 |
| 界面代理开关和播放代理开关分开（pure_live_TV `api_proxy_policy.dart`） | G、J02.1 | 本包的 `ProxyPolicy` 由应用按接口代理设置注入，每个客户端都经过它；播放代理由播放模块单独处理 |

## 依赖变化

- v3 网络层用到 dio、http、web_socket_channel、charset_converter（Flutter 插件），还通过 GetX 读设置。
- 重构后只依赖 `meta` 和 `dart:io`，是纯 Dart，可以直接用 `dart test` 测试，也可以给命令行工具用。

## 测试

64 个用例，连续跑 5 次全部通过：

| 测试文件 | 内容 |
|---|---|
| `io_http_test.dart` | 文本和重复响应头、表单编码、重定向、4xx 也是响应、gzip、超时、取消、连接被拒、按平台走代理；流式响应的逐块读取、块间超时、读取中取消、等待响应头超时、`collect` 和 `discard` |
| `request_test.dart` | 查询串原样保留、空值和列表、默认 20 秒、表单和 JSON 请求体、任意 Content-Type 都能解析 JSON |
| `calls_test.dart` | `getText`、`getJson`、`postJson` 的三种请求体；`HttpStatusFailure` 的内容预览（256 字符）和响应头；`head`；下载的改名、进度、206、失败时删除 `.part` |
| `diagnostics_test.dart` | 移植 v3 的 4 个用例：不泄露签名地址、载荷、凭证和嵌套错误；日志函数出错不影响原失败；大响应体只记大小；时钟回拨写 unknown。另加：取消不记录，流式请求失败也会记录 |
| `proxy_test.dart` | 移植 v3 两个测试文件的全部用例，另加 IPv6 方括号、`192.168.1.999` 这类非法地址、按平台选路 |
| `headers_user_agent_test.dart` | 请求头规范化和编解码；UA 覆盖五种浏览器和平台组合、格式符合 UA 精简、客户端提示和浏览器一致 |
| `race_test.dart` | 第一个结果获胜并取消其余请求；全部失败时立即结束，不等超时；超时返回 null；`raceJson`；`fastestUrl` 发送 `range: bytes=0-0` 并接受 206 |
| `socket_test.dart` | 移植 v3 的 9 个用例：半开连接换地址、有流量时保持连接、关闭码和原因、中止挂起的握手、重复连接合并、真实握手可以放弃、关闭握手有时限。另加：每次握手读取代理策略、达到最大次数后放弃、真实回声服务器双向收发 |
| `throttle_replay_test.dart` | 按平台限速，以及样本回放（来自归档 v4） |
