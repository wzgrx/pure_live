# HLS 上游请求所有权与共享预取传输（2026-09-09）

起点 `1b7b9c41`，代码 `3a1647deb15fecf2b636e45bd50beacd5e938cd7`。承接[保留清单发布](HLS_RETAINED_PUBLICATION_AUDIT_2026_09_09.md)。

## 本批结论

1. 修复生产 relay 的一个独立连接泄漏：请求已分配后，构造 HTTP 头发生异常，原路径只回本地 502，未取消该上游请求。
2. 生产 relay 与预取 loader 现在共用 `HlsUpstreamClient`，保留原查询策略、Cookie、敏感头、重定向、读预算和停止规则；单个预取取消不关闭共享客户端。
3. 新增有界响应元数据与精确范围缓存准入，完整接收/封口后由读取租约携带。独立原生缓存探针已换成这一共享 loader。

**实际录制的后台清单轮询/预取调度仍未启用**，本批修复不是 TTing 慢源缺片的根因修复。130/130 定向、滚动控制 3/3（两统计 + 一个四场景原生测试）、缓存原生 1/1 通过。没有手机操作、构建、版本变化、上游合并或发布；宏观仍 **20 PASS / 32 RUN / 10 NOT RUN，42 项未闭环**。

## 生产 Bug 的复现与来源

`test/ffmpeg_hls_request_ownership_test.dart` 在纯本机 TCP 中提供含 NUL 的夹具请求头。`HttpClient.openUrl` 已与上游建立连接，随后 `request.headers.set` 抛出 FormatException。修订前本地客户端得到 502，上游在 2 秒断开观察中仍开放，且 relay 未收到 finish 意图；只有 finally 中整个 relay.close 才清理。

- 有效红测：`request-red-fixed` **0/1**，失败点为 `Rejected request TCP still open before relay.close`，不是连接未建立或 local HTTP 状态异常。
- 修订后同一断言通过，收到本地 502 后上游已关闭；检查发生在 relay.close 之前。
- 首次 `request-red` 误将项目 Get.reset 的 void 返回值 await，分析阶段失败；修正测试后才取得上述红测。这是测试编写错误，单独留账。
- 来源 **fork-regression**：该文件始于维护提交 `e35247d03849e12e0b5aedf1079c64e56fdb056f`；当前头处理行由 `80b7431c0` 引入/改写，失败清理未覆盖这一段。冻结上游 `c6c9bd70aedc503c003110dae10a83ad0bb891d8` 与 merge base `527fea1b40885e3621d53c9646b523dd8522290c` 均无此 relay 文件。没有合并上游，也未把该畸形输入复现说成真实 TTing 已观察到的故障。

新传输层从 request 分配到交付 response 的全部失败路径都有 request.abort，包括头设置、Cookie/重定向处理、预算与取消；同时观察 request.done，覆盖尚未调用 request.close 就失败的情况。返回的最终 body 仍由 relay 或 pool 明确接管。relay 请求错误日志由异常全文改为主机名及异常类型；红测旧日志确实包含夹具头值，新日志仅含 FormatException。时序/HTTP 状态诊断继续独立保留，未保存真实头值。

## 共享传输及缓存准入

- `HlsUpstreamClient.open` 已用于生产 `_openUpstream`：逐跳处理 Cookie、同源初始 Cookie/Authorization，跨源不携带这些初始敏感头；User-Agent 和普通业务头保留；显式来源绑定查询策略逐跳应用，不猜测 token 规则。
- 仍最多五次跳转，拒绝非法协议、凭据重定向与 HTTPS 降级；已知 m3u8 不转发媒体 Range。非录制模式重定向 body 保持整个 drain 的 20 秒上限，不改成逐 chunk 重置；录制模式共享原总响应预算。
- ticket 取消在响应头、重定向 body、最终 body 三个阶段都验证真实 TCP 关闭，并证明另一下载、已完成缓存和后续同客户端请求保持可用。尚未得到 request 的连接依旧由调用方的 connectionTimeout/连接所有者收尾，不遗弃迟到 Future。
- `loadMedia` 校验 response 后直接交给 pool；被拒且尚未读取的响应使用 HlsBodyReader 真正订阅/取消。元数据仅包含状态码、预期长度、Content-Type、Content-Range、Accept-Ranges，不带来源 URL、Cookie、Authorization 或 Set-Cookie。
- 全资源缓存要求无 Content-Range 的 200；有限范围缓存要求精确 206、首尾与声明范围一致、总长度合理、Content-Length 一致。未知传输长度时仍按请求范围长度封口；错位、截短、溢出、多个/非法范围、非成功状态等不成为就绪缓存。
- 这是**缓存身份准入**，不是宣称所有 200-for-Range 都违反 HTTP：服务器可以忽略 Range。编码后的范围对应的是编码字节，故当前准入拒绝压缩范围和未解码压缩媒体；整资源 gzip 经 Dart 自动解码后按解码数据封口，不拿压缩 wire length 比较。依据 [RFC 9110 §14.1.2、§14.2、§14.4](https://www.rfc-editor.org/rfc/rfc9110.html#section-14)。既有非缓存生产路径的 Range/HTTP 透传行为保持。
- 头字段有字符上限与控制字符检查；池检查 response.expectedLength 与 metadata.expectedLength 一致。元数据在封口和预算检查后归入条目，仅完整 acquire 的 lease 可见；内容损坏/字节截短仍由已有池检查。
- 池仍全局 8 条目、6 并发、8 读者、128 MiB，未扩容，也未按轨道开多个池。

## 验证范围与实际结果

八个变更 Dart 文件格式化、`dart analyze --fatal-infos` 通过。最终 **130/130，14 个定向文件**：新请求所有权、上游客户端、HTTP 元数据，以及生产 relay、查询策略、body idle/ownership、TLS connect stop、staging limits、pool、body reader、cookies、query policy、diagnostics。共享传输首轮 129 项通过，补实际 gzip 回归后为 130；没有重跑无关全库门禁。

生产 FFmpegKit 四场景复用固定 fMP4 夹具，`controls/rolling-1788953554148270/summary.json`：

| 场景 | 输出 B | 完成视频序号 | 探针观察停止 ms | 视频/音频包 |
| --- | ---: | --- | ---: | --- |
| healthy-10 | 1884324 | 0–7 | 533 | 480 / 750 |
| continuous-body-10 | 451952 | 0, 6 | 2598 | 120 / 188 |
| continuous-body-15 | 451952 | 0, 6 | 2512 | 120 / 188 |
| delayed-headers-15 | 451952 | 0, 6 | 2475 | 120 / 188 |

全部 code 0、inputDrained=true、forcedCancel=false、inputIntegrityError=false；正常场景无覆盖警告，三慢场景各一次，仍仅约四秒媒体，缺片未解决。停止列是 probe 的 stoppedMs−stopRequestedMs，不冒充 native 内部精确计时。独立 direct scheduling 测试按开关跳过，不记 PASS。

缓存原生 `controls/publication-1788953708073114/`：现在通过 **同生产 HlsUpstreamClient.loadMedia** 下载，八个 lease 均携带已验证 200 元数据。关闭源站和传输后，视频 180 包、音频 189 包分别与直连参考逐包相等（排除 pos）；八条目 623258 B、源站请求数保持 18，关闭池后条目/计费字节归零。此有限夹具不是持续动态预取、加密原生解码或完整 A/V 同步验收。

固定夹具逐文件哈希已重验；本地 libffmpegkit.dll SHA `888A15993862950FEED714990E459F653B68BBC2CE30DA7D4BDA8DB9A5212C06`，ffprobe SHA `02A6801CE4AA4B84706771C511C6802AFF5EFD2FE15EE305F9303E74413ECEF6`。Flutter hook 有的阶段提示远端 SHA 验证通过、有的阶段提示缺少 SHA；不混同本机固定哈希与远端声明。

## 证据记录

根 `local-artifacts/hls-upstream-transport-20260909/`：red/check/complete.ps1、分阶段 format/analyze/test/native 日志、八文件源码哈希、修订前 open/blame/文件来源、源码提交和 artifact-index.json；原生结果路径见上。

| build-records 文件 | 结果 | 含排队 s | 峰值 CPU % | 峰值工作集 B | 结束活跃重型 |
| --- | --- | ---: | ---: | ---: | ---: |
| 20260909T111836607Z-hls-upstream-transport-request-red.json | 测试 Get.reset await 分析失败 | 60.4295634 | 8.92 | 11680694272 | 0 |
| 20260909T112107421Z-hls-upstream-transport-request-red-fixed.json | 有效 TCP 红测 0/1 | 102.394297 | 9.02 | 12939210752 | 0 |
| 20260909T112901256Z-hls-upstream-transport-shared-first.json | 七文件严格分析、129 定向通过 | 124.9609533 | 12.69 | 11108028416 | 0 |
| 20260909T113511542Z-hls-upstream-transport-shared-complete.json | 八文件严格分析、130 定向、3 滚动及 1 缓存原生通过 | 295.14055 | 10.61 | 10726617088 | 0 |

## 后续接线，不更改完整目标

下一步实现真正选中媒体清单的独立刷新、来源代次、视频/音频公平调度，以及已发布清单/下载/读取/消费后淘汰的共同所有权；同时把预取非成功响应映射到录制诊断/来源刷新策略（当前 ticket 的失败分类仍为 download 等通用类型）。现有范围准入有明确失败，不以重试或扩大超时吞掉错误，也不把这些基础接口当作调度已完成。

随后再用同一 12 秒交付/6 秒窗口控制证明持续序号改善，再复测 TTing 与 Android/Windows 候选。九个平台组、完整 UI/操作/平台验收、README/流程和最终全平台稳定 3.2.0 发布仍全部保留。
