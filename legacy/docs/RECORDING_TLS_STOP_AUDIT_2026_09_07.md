# HLS TLS 握手停止红测（2026-09-07）

**后续状态**：[网络侧所有权修订](RECORDING_TLS_OWNERSHIP_AUDIT_2026_09_07.md)已保留本页原失败合同并通过，移为日常 `test/ffmpeg_hls_connect_stop_test.dart`。本页以下为原诊断批历史，不代表后续源码仍未修订；APK/Android及完整验收仍有缺口。

基线 `f0554973d7337d23a973070eb7fa9331375b9754`。接续[暂存容量验证](RECORDING_STAGING_LIMITS_AUDIT_2026_09_07.md)，本批发现并保留**尚未修复**的连接建立阶段停止问题。无效应用修改已精确撤回；最终应用代码与基线一致，不把诊断结果写成修复交付。

## 可重复输入与两次红测

本机HTTP播放列表指向另一个本机HTTPS端口。该端口只接收TLS ClientHello，故意不发送ServerHello；无外部网站、证书豁免或手机操作。relay.finish应在既有停止窗口内退掉未发布输入，但当前请求仍等待openUrl完成。

- 首轮新合同测试0通过/1失败，3秒TimeoutException；记录 `20260907T144507902Z-hls-connect-stop-red.json`，59.36秒，结束活跃重型进程0。原日志tls-handshake-red.log。初版超时文本未区分等待ClientHello与等待停止，后一轮补上阶段说明。
- 尝试在_stopFetching关闭本relay的HttpClient，并将openUrl取消异常转为_HlsFetchStopped。**35通过/1失败**，错误明确为“Stop budget expired after ClientHello was observed”；记录 `20260907T144928234Z-hls-connect-stop.json`，118.321秒，结束活跃重型进程2（其他项目活动），日志client-close-still-red.log。没有运行随后被门禁阻止的原生媒体探针/analyze。
- 无效差异保留于 `local-artifacts/hls-connect-stop-20260907/ineffective-client-close.patch`，已从生产文件撤回；不得重复套用或声称该方案可取消TLS握手。

原合同保留为显式启用的 `tool/probes/recorder_hls_connect_stop_probe_test.dart`，用环境变量PURELIVE_HLS_CONNECT_STOP_PROBE=1运行时预期仍红，不混入日常绿色回归。它仍要求410/零字节、输入舍弃标记、缓存ENDLIST、底层连接断开及另一relay不受影响；没有删掉未满足的要求。

## SDK 与独立观察

当前固定Flutter3.47.0内Dart **3.13.0**。本地源码`lib/_http/http_impl.dart`2630附近遍历ConnectionTask并cancel，HttpClient.close遍历连接目标；`lib/io/secure_socket.dart`中SecureSocket/RawSecureSocket.startConnect最终沿用原始TCP任务的_onCancel，再把其socket Future衔接TLS握手。源码核对和摘录见sdk-provenance.json、dart-http-close-excerpt.txt。

来源分层：Pure Live的响应头后取消设计存在 `fork-regression` 覆盖缺口；底层行为在无Flutter/FFmpeg的独立Dart VM脚本也成立，属于当前依赖能力限制。公开[Dart Issue #51267](https://github.com/dart-lang/sdk/issues/51267)讨论openUrl建立连接阶段缺少可取消请求对象，本次读取页面仍Open；它是相关设计背景，不代表已经对本次TLS细节给出根因修复。官方[startConnect实现](https://api.flutter.dev/flutter/dart-io/SecureSocket/startConnect.html)也展示转交_onCancel的结构。未更新SDK或修改SDK缓存。

独立脚本 `tool/probes/dart_tls_cancel_probe.dart`直接运行Dart VM，仅dart:io：

| 在ClientHello后执行 | 1.5秒后对端已断开 | Future已结束 |
| --- | --- | --- |
| HttpClient.close(force:true) | false | false |
| 保留RawSocket句柄后raw.close() | true | false |

第一项独立记录 `20260907T145520752Z-hls-client-close-observation.json`，42.475秒（含等候其他Java），结束活跃重型进程0。第二项证明“网络资源断开”和“等待握手的Future结束”需要分别处理；不是可以直接替换生产HttpClient的成品。

两模式首次记录 `20260907T145732403Z-hls-tls-cancel-primitives.json`：原始Dart进程退出255，RawSecureSocket握手Future在最终2秒等待中仍不结束，外层脚本退出1。随后把监听服务清理移到finally保证超时也执行；复跑 `20260907T145932235Z-hls-tls-diagnostic-final.json`得到相同两组观测和Dart退出255。该包装器错误地把预期非零具体写成1，因此它也报失败，未运行analyze；这不是另一种应用故障。两次日志分别保留tls-cancel-primitives-first.log与tls-cancel-primitives.log。

**未采用仅Future.any/timeout提前返回方案**：第一种路径实际连接仍存活，靠UI先结束会隐藏资源占用。也未降低TLS验证、盲目缩短全局连接超时、发送全局信号或临时重写整个TLS/Socket传输层。下一步需同时持有可关闭网络资源并结束本次等待，在有效证书验证、代理CONNECT、响应背压和并行会话隔离测试之后再接入生产。

## 验证与剩余状态

最终两个新诊断文件已格式化；范围analyze一次通过，无诊断，71.7秒。记录 `20260907T150253978Z-hls-connect-stop-analyze.json`，总计122.424秒（含资源排队），结束活跃重型进程0；git diff核对生产relay相对基线没有差异。此批没有绿色修复验收；前批35项容量/HTTP回归的证据仍只覆盖其原范围。

该TLS边界及其他DNS/TCP阶段、永久磁盘I/O、Android短录/首帧/长录、平台能力和3.2.0整体门禁继续未完成。没有新APK、版本提升、推送或发布，也没有ADB、MT、LSP、Root或模块操作。应用仍是f0554973的业务源码，手机最后核验候选仍80b7431c。回滚本批只涉及诊断探针与文档，无用户数据迁移。
