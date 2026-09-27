# 0011 网络层 live_net

- 状态：已接受
- 日期：2026-09-27

## 背景

旧版所有平台共用一个 Dio 单例（`HttpClient.instance.dio`），有这些问题：

- 代理从 GetX 设置里现取。
- 各平台的 Cookie 散落在站点类的静态变量里，抖音的 Cookie 要重启才生效（REG-DOUYIN-017）。
- 错误统一包成字符串。
- 测试只能替换全局单例的适配器（`test/fixtures_expected/support.dart`）。

诊断 01 和 05 要求平台层不依赖设置和界面，错误有类型，并且能被命令行探针直接调用。

## 决定

1. **`live_net` 是纯 Dart 包**，只依赖 `dart:io`，不依赖 `live_core`（依赖方向是 `live_core → live_net`），可以在 Flutter 应用、`live_cli` 和测试里直接用。不用 Dio：需要的功能（代理、重定向控制、超时、取消、解压）`dart:io` 的 `HttpClient` 都有，少一层依赖，也少一套拦截器语义。
2. **接口**：适配器只依赖 `LiveHttp.send(LiveRequest) → LiveResponse`。
   - 请求带：方法、URL、请求头、正文、是否跟随重定向、超时、取消令牌、所属平台。
   - 响应带：状态码、响应头（重复的头保留全部值）、正文字节和按字符集解码后的文本。
   - HTTP 4xx、5xx 照常返回响应，由适配器按平台规格判断；只有连接、TLS、超时、取消这类传输层失败抛 `live_net` 自己的 `TransportFailure`，适配器把它映射成 `live_core` 的 `NetworkFailure`。
3. **代理**：`ProxyPolicy` 按平台决定走直连、全局代理还是平台专属代理，由应用从设置里注入，`live_net` 不读设置。播放器用的媒体代理不归这里管（REG-NET-003）。
4. **Cookie**：`CookieVault` 按平台保存用户凭据；匿名会话 Cookie（ttwid、buvid 这类）由适配器自己维护，和用户凭据分开。凭据变化会发出通知，适配器据此让自己的缓存失效，不再用进程级静态变量。媒体请求要不要带 Cookie，由线路的 `headers` 决定。
5. **测试**：`ReplayHttp` 按“方法 + 主机 + 路径 + 查询参数”回放 `fixtures/` 里的录制样本，没有匹配的请求直接让测试失败。适配器测试和旧版期望值测试用同一批样本。
6. **限速和并发**：每个平台一个串行化的请求队列，可配置最小间隔（快手搜索有接口级限流），由平台适配器声明。

## 备选方案与放弃理由

- **继续用 Dio**：拦截器、转换器、适配器三层语义，旧版在上面叠了日志和错误改写，测试替换还要动全局单例。
- **package:http**：没有取消、重定向控制和按请求设置代理。
- **把 Cookie 放进 `live_core`**：凭据存储要加密、要持久化，属于 `live_store`；`live_net` 只定义接口，由应用注入实现。

## 影响

- 第 4 阶段的平台适配器在 `live_core` 里组合“解析函数（已完成）+ `LiveHttp` 请求”，适配器测试用 `ReplayHttp`。
- 旧应用接入 v4 适配器时，由它把设置里的代理和 Cookie 转成 `ProxyPolicy` 和 `CookieVault`。
