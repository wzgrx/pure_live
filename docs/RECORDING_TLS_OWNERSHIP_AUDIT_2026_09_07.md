# HLS 握手取消：网络连接所有权修订（2026-09-07）

基线 `3a8f4cf32cd2015a9781cfe56c808c4d96057eeb`。本批接续[已复现的 TLS 停止红项](RECORDING_TLS_STOP_AUDIT_2026_09_07.md)，不通过提早返回 Future 隐藏仍存活的网络连接。

## 结论与边界

原 ClientHello 后停止红测已通过并从 opt-in 探针移到日常 `test/ffmpeg_hls_connect_stop_test.dart`。保留原来的3秒预算、410/零字节、尾片舍弃、缓存ENDLIST、对端断开和另一relay不受影响全部断言；不是删除失败断言。

**56/56 定向测试通过，原生四个既有停止场景严格解码通过。** 新连接层已在本机验证直接/代理 TLS、证书与主机名校验、完整大响应和取消清理；尚无 Android 新包或手机原生证据，不把本批计为全场景停止/性能验收完成。

## 方案取舍与生产实现

1. 先独立测试了把 HttpClient 放进工作 isolate 再结束 isolate 的方案。已观察到 ClientHello，并等到 isolate 退出；随后等待对端断开3秒仍超时。记录 `20260907T152559009Z-hls-isolate-cancel-primitive.json`，Dart退出255，**未将此方案接入应用**。这不证明网络永远不关闭，只说明它未满足此取消合同。[官方 Isolate.kill](https://api.dart.dev/dart-isolate/Isolate/kill.html)描述的是关闭请求，不作为即时资源释放证明。
2. 新 `CancellableHttpConnections` 作为每个 HLS relay 自己的 `HttpClient.connectionFactory`，持有 TCP 建连任务及网络侧 socket。普通 HTTP 保持直接连接；HTTPS 增加一对仅绑定 loopback 的 TCP 桥端点，由工厂实际连接的源端口配对，非配对连接关闭，监听口配对后关闭，不接受客户端指定目标地址。
3. 直接 HTTPS 仍由 `SecureSocket.secure` 按原 URI 主机名和默认信任上下文完成端到端 TLS；代理 HTTPS 返回到代理的 TCP 流，由 HttpClient 继续执行 CONNECT、TLS 和验证。桥不终止 TLS、不解析 HTTP，也不输出密钥。保留代理参数遵循[官方 connectionFactory 合同](https://api.dart.dev/dart-io/HttpClient/connectionFactory.html)；本地源码核对为固定 Dart3.13.0，网页显示的较新补丁号不视为本机已升级。
4. 双向使用 `addStream` 和写出完成等待传递背压；正常 EOF 先排出写入并半关闭对应方向，两个方向结束后释放，避免主动关闭截断最后一批 TLS 记录。取消则立即关闭本连接的网络、桥端与等待；后到的本地分配继续清理，relay.close 等待其收尾。
5. `_stopFetching` 在既有宽限窗口后关闭自己这一组连接及 HttpClient；`_openUpstream` 将停止期间建连异常归一为既有舍弃结果。完整已暂存且正在向 FFmpeg 发布的本地响应不依赖上游连接，不因上游关闭而被截断。

独立桥原型记录 `20260907T153100579Z-hls-bridge-cancel-primitive.json`：请求已结束、对端在夹具清理前断开、连接计数0，合计4ms。该记录原 `source_dirty=false` 只统计已跟踪文件，遗漏当时新建的原型文件；已追加来源更正，**不是干净HEAD的生产证据**。生产依据为后续完整定向验证。

## 测试与失败保留

新增连接层12项测试覆盖：

- 直接与 CONNECT 内 ClientHello 后取消：结果结束、对端断开、所有权计数归零。
- 默认连接超时取消和10次立即取消/后到分配清理；关闭后的新请求拒绝；不同 owner 的普通HTTP互不影响。
- 直接与 CONNECT 下连续两次 `3MiB+17B` 响应逐字节一致，请求/响应头保留。
- 直接与 CONNECT 下拒绝未受信证书及“受信链但主机名错误”的证书；代理负向场景还确认错误证书回调实际发生且返回false，没有只靠连接提前失败通过负向测试。
- 证书和公开测试私钥仅位于 `test/fixtures/tls/`；正向信任仅存在于夹具 SecurityContext。生产没有信任测试证书、关闭验证或修改系统证书库。

失败及修订分层：

| 批次 | 结果 | 说明 |
| --- | --- | --- |
| `20260907T154003074Z-hls-owned-connections-first.json` | 32通过/4失败 | 原HLS握手红测及相邻HTTP/容量已通过；新测试有代理取消异常类型、连接池假设和负向夹具问题 |
| `20260907T154326207Z-hls-owned-connections-refine.json` | 9通过/2失败 | 明确直接/代理取消分别表现为SocketException/HandshakeException；直接池约束通过，代理池与IP形式CONNECT负向夹具仍失败 |
| `20260907T154614340Z-hls-owned-connections-contracts.json` | 12/12 | 补上未修改HttpClient的代理池对照，改用相同localhost目标配合受信的错误DNS名称证书，验证实际TLS拒绝 |
| `20260907T155200589Z-hls-owned-connections-final.json` | 56/56；原生1/1含4场景；分析2条info | 七文件回归通过；分析提示初始化形式和benchmark导入路径，随后只修订这两处风格/导入 |
| `20260907T155544925Z-hls-owned-connections-style.json` | 五文件analyze无诊断（50.9秒）；benchmark再次通过 | 初始化形式保留同一构造参数，探针使用package导入；重跑独立VM确认包解析和六次传输，复用未改行为的56项/原生证据 |

原始日志均保留在 `local-artifacts/hls-isolate-stop-20260907/`。未受信/错误名称没有通过放宽断言为“任意错误”收口。原IP形式CONNECT夹具在证书阶段之前返回HTTP连接错误，不用它证明主机名校验。

完整定向批耗时279.766秒，峰值CPU65.17%、工作集17,281,724,416 B，结束活跃重型进程0；该批总状态因两条分析info为failed，保留原记录而不改写。后续风格核验单独记录；重型任务串行并等待其他项目的Java测试，未结束那些进程。

**发现一个既有池行为**：固定SDK的默认HttpClient在本夹具连续两次CONNECT请求时也创建两个隧道；新工厂结果一致，关闭后所有计数归零。它不是本批桥导致的连接累积，但真实国外平台的长期连接池/功耗仍待性能审计。直接TLS在显式单连接池下复用一个连接。

## 本机吞吐与原生文件对照

`tool/probes/recorder_http_connection_benchmark.dart` 显式启用后，交错执行默认HttpClient与新桥各三次64MiB TLS下载。首次六响应均完整，默认约30.62–38.92MiB/s，新桥约34.82–38.59MiB/s；进程RSS约206–214MB。这只是本机、单进程/同机服务端的比较，不把次序/JIT/系统波动解释为桥能加速，也不外推Android CPU/功耗或代理吞吐。大响应逐字节完整性由前述单元测试另行覆盖；benchmark只核对总长度与各块边界样本。

package导入修订后又一次完整运行：默认34.17–37.27MiB/s、新桥37.44–40.43MiB/s，六响应仍全部完整。该次用于验证实际CLI入口及重现比较，不追加成12个单元测试或声称无性能开销。

原生结果目录 `hls-partial-1788796182831706`：

| 输入已送比例 | 停止ms | TS字节 | 严格A/V解码 | 尾片舍弃 |
| --- | ---: | ---: | --- | --- |
| 完整 | 2040 | 929660 | 0，错误日志空 | false |
| 25% | 2011 | 683756 | 0，错误日志空 | true |
| 50% | 2009 | 683756 | 0，错误日志空 | true |
| 90% | 2006 | 683756 | 0，错误日志空 | true |

四场景 `forcedCancel=false`、`inputDrained=true`、`inputIntegrityError=false`，结束 `nativeRunning=false`；与前批对应输出SHA逐字节相同。完整SHA `1A225450A9CF14EF75BE6FE24619BCDEA4C60ECAC12B81CACFEBD72D666A4ED0`，三种暂停SHA均为 `77B17E5CC1C8C5F88F1DFA161884DE0DBCC6EC0ADB439913B0E97B8346C5910C`。

此原生探针上游为HTTP；TLS在新连接层及生产relay握手回归中验证，不将两者冒充“原生HTTPS全部场景已测”。暂停场景仍有410、跳过第4片和解复用I/O日志，健康文件不代表未丢失输入。默认原生DLL映射重新读取，54,565,256 B、SHA `888A15993862950FEED714990E459F653B68BBC2CE30DA7D4BDA8DB9A5212C06`，与前批已核验固定归档一致；详见本批 `runtime-provenance.json`。

## 剩余与交付

手机切换窗口尚待用户确认，本轮未运行ADB、MT、LSP、Root或设备输入。已有c442380c APK不包含本次连接层；没有版本提升、同步上游、推送或发布。后续需新候选构建、保留数据覆盖安装、原手机录像复验、HTTPS原生/代理长期性能及DNS/永久磁盘I/O等剩余边界，不以本批56项代替3.2.0整体验收。
