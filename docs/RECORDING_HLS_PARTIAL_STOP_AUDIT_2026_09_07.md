# HLS 在途停止本机复现与测试任务所有权（2026-09-07）

接续 [Android Cookie 候选复验](TWITCASTING_COOKIE_ANDROID_RETEST_2026_09_07.md)。本批只有本机诊断探针和 PowerShell 测试器修订，应用代码、APK、版本与手机均未改变；**录制损坏仍是 FAIL，不是修复交付**。

后续已增加内层TS逐包刷新，[输出缓冲审计](RECORDING_OUTPUT_FLUSH_AUDIT_2026_09_07.md)记录66/66定向回归及四场景生产原生严格解码通过；输入在途停止仍未完成，未部署新APK。以下保留本批原始红项。

## 原生对照：完整响应通过，暂停响应失败

新增 opt-in `tool/probes/recorder_hls_partial_stop_probe_test.dart`，使用生产 FFmpegManager、命令生成器、HLS relay 与实际 Windows FFmpegKit；只访问随机端口的 loopback 服务。输入是已有合成 fMP4 fixture，init 加固定 2 秒分片；完整原 fixture 先以外部 FFmpeg 全音视频严格解码通过。

本机源首次列表公开三个完整分片，随后公开第四片，不移除旧片、无直播窗口跳段、无鉴权/Cookie。等原生媒体统计 started 且第四片进入指定传输位置，再调用生产 stop。完整对照发送全部 224,908 B，三个暂停场景仅发送第四片的 25%/50%/90%，剩余字节等会话收尾后释放。输出保留原始 TS，不经过修复、裁剪或合并；外部解码使用 `-xerror -err_detect explode` 同时映射视频和音频。

最终证据：`local-artifacts/hls-partial-stop-20260907/hls-partial-1788787287665469/`。

| 第四片已发送 | stop 耗时 | forcedCancel / inputDrained | TS 字节 | 严格解码 |
| --- | ---: | --- | ---: | --- |
| 100% 对照 | 2034 ms | false / true | 929660 | 0，错误日志为空 |
| 25% | 6035 ms | true / false | 524288 | -1094995529，FAIL |
| 50% | 6035 ms | true / false | 524288 | -1094995529，FAIL |
| 90% | 6033 ms | true / false | 524288 | -1094995529，FAIL |

- 四个原生会话退出码都为 0，结束时均不再 running。三个失败场景均记录 `inputIntegrityError=true`、partial file、损坏包被丢弃、`Error writing trailer: Immediate exit requested`。因此退出码 0 与 discardcorrupt 都没有证明输出完好。
- `prefix-comparison.json`：三个坏 TS 的 SHA-256 完全相同，均为 `CA480A8C36A83C1C511075254A7C97D99EC5334D7B22F84CC5FF3F70BCF842C5`，且等于健康对照文件前 **524288 B** 的 SHA-256。它们长度除以 188 余 **144**；健康文件余 0。当前输出是健康前缀在非完整 TS 包边界被截断，而非三种输入比例产生三份不同的内容损坏。
- 这把本机问题进一步限定到在途停止/强制取消时的输出收尾：重点核对 native AVIO 中断、缓冲落盘与 trailer 生命周期。尚未定位到原生代码具体语句，也没有证明 Android MP4 的尾错与 4/8 秒样本延展均由此单一原因造成；Android 当时 `inputIntegrityError=false`，与本机不同。
- 真实直播/Android 仍需独立复验；保持既有 Picarto“强制取消但健康文件”的对照，不把所有 forcedCancel 归为损坏。不通过裁剪文件、降低解码要求或单纯延长停止预算掩盖失败。

## 运行记录与复现约束

重型任务均经过共享资源锁、监控与 CPU 收尾；三个原生探针记录的结束活跃重型进程为 0，其他 Java 工作排队等待，未被终止。后续 analyze 记录结束活跃数为 1，未冒充全机归零；随后进程观察只有其他项目 Java/Gradle 工作与 daemon，没有 Dart/FFmpeg 进程，保留它们正常运行。

- `20260907T130811860Z-hls-partial-stop-probe.json`：首次探针缺少必填 `threadQueueSize`，编译失败，未形成原生结果；已补 1024。
- `20260907T131620265Z-hls-partial-stop-probe.json`：首次三个暂停场景均复现失败，证据 `hls-partial-1788786950453279/` 保留。
- `20260907T132202460Z-hls-partial-stop-probe.json`：补同路径完整响应对照，140.527 秒；一个健康对照、三个失败场景，**测试命令整体失败如实记录**。不是四项全绿。
- `20260907T132618102Z-hls-partial-probe-analyze.json`：Dart 修改完成后只对新增探针 analyze，一次通过、无诊断，分析116.0秒；不外推全库分析或应用修复通过。

在重型资源锁内设置 `PURELIVE_HLS_PARTIAL_PROBE=1`、`PURELIVE_HLS_PARTIAL_FIXTURE`（含 init.mp4 及至少四个按文件名排序、每片 2 秒的 m4s）、`PURELIVE_RECORDING_PROBE_OUTPUT`（独立证据目录）、`PURELIVE_FFMPEG`（严格解码器），再通过固定 SDK 的 `tool/flutterw.ps1 test --no-pub --concurrency=12 tool/probes/recorder_hls_partial_stop_probe_test.dart` 执行。环境变量未启用时跳过，默认单测不会访问外部源或设备。当前探针保留失败断言，供下一批修复做红/绿回归；独立 Hive、媒体和日志全部保留在证据子目录。

## 测试器所有权修订

首个错误状态是测试器把“目标房间已有录制/监控”当作可先清理的残留；旧预检会点停止/取消，失败 finally 还会无条件停止整个应用。单独加预检异常不足以保护已有录制。

只读核对冻结本地 `upstream/master=c6c9bd70aedc503c003110dae10a83ad0bb891d8` 的同文件，也含预检停止/取消与 finally 无条件停止分支，本问题按该冻结对照为 `upstream-existing`；没有本轮远端刷新或合并。原生 HLS 输出问题本轮仅完成上述复现与状态缩小，未完成来源归因。

新增纯函数 `tool/recording_turn_ownership.ps1`，接入直接和海外代理包装器：

1. 代理变更前显式 serial 核对 25102RKBEC/myron，再检查本包 services；直接 smoke 在唤醒/导航前再次检查。活动或未知 services 保留，不开始新录制测试。
2. 目标录制弹窗必须具有唯一的三个语义控件；启动明确可用，停止/取消明确禁用，才发送启动。已有任务、缺失/重复或未知属性均退出，移除旧预检停止/取消分支。
3. 在发送新启动前记录本轮意图，避免传输结果不明确时遗失本轮状态。最终 app stop 同时要求本轮启动、监控移除确认、当前无录制服务；只有明确无服务或已知 AudioService 才继续。未知服务、观察失败或未完成移除均保留并记录 disposition。
4. 外层代理恢复始终 KeepAppOpen；代理事务先恢复自身变更，应用停止仅交给上述有条件路径。没有 daemon 重启、重新选设备、重放失败输入或修改设备配置。

验证均为本机假 ADB/AST，不运行设备脚本入口：

- 新增 **76 项断言通过**：身份、明确 transport、空/错误/未知服务、已停止/正在录制的旧监控、控件歧义、未获得/未结束任务、其他服务、命令失败，以及生产调用顺序。停止命令结果丢失单列为 uncertain，不误报进程保留，也不重放。
- 既有 recording guard **73 场景通过**；平台/能力/覆盖标记脚本通过；代理事务 **38 场景通过**。代理失败夹具产生预期 warning，最终测试退出 0。
- 服务/UI 检查是可观察快照，不是 Android 原子事务，也不证明全部持久化旧监控已逐项读取。后续仍需设备租约和前台保护；本批没有以真实用户已有任务来冒险验证保护路径。

## 下一步与回滚

先沿原生取消→AVIO 写入中断→输出缓冲/trailer 的路径定位，并用上述健康/暂停四场景核验；必要时评估完整媒体响应边界停止，但不直接用缓存或延时替代证据。还需补短实时窗口/源侧停顿对照，检查强制取消但未锁存损坏时的源保留判定，然后再构建、覆盖安装并原生复验。

本批回滚只需恢复这批工具与探针提交，应用未变更。Android 最近验证仍为 80b7431c / 3.1.8+4121，Windows 仍为 2d8e4e0c；未发布、未提升 3.2.0、未运行全库正式门禁，本轮 ADB/MT/LSP 操作数为 0。
