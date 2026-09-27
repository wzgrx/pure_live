# 用户录制入口启用有界 HLS 保留（2026-09-10）

起点 `c686d868`，源码提交 `a10327be`。上轮已完成一次真实解析→原生录制→排空→合并→源交付与时间线→全解码，属于 progress；结果见[录制合同实录增量](HLS_CAPTURE_CONTRACT_AUDIT_2026_09_10.md)。本轮将已验证能力接入用户实际入口，而非再运行同一个显式开启探针。

## 来源、变化与范围

此前 `RecorderController` 的公共录制尝试方法调用 `FFmpegManager.start` 时没有传 `hlsPrefetch`，沿用默认false。这是分阶段开发时刻意保留的开关，并非新发现的上游缺陷；本轮属于维护分支能力启用。冻结上游没有该保留模块，本轮不合并上游。

- 控制器公共尝试方法现在显式传true；首次启动、手动停止后重启、断流续接/签名续期均走同一入口。
- Manager/Service底层默认仍false，没有更改所有FFmpeg任务的默认值。离线合并走独立入口，不开启预取；FLV根本不创建HLS relay。
- HLS仍按实际选中清单整批准入；未支持、超预算、多选源等保持已有原始relay路径，继续保留明确源查询策略，不按token字段名猜测签名传播。
- 不变更已有池/下载/清单预算、超时、停止、已提供内容保留和源文件清理策略。没有新设置项、Hive迁移、版本变化或UI文案变化。

## 实际验证

1. 修改生产入口前，新增真实控制器调用测试，带查询策略HLS、普通HLS、FLV三种首次启动均收到false；断流续接也收到false/false。首轮 **10 PASS / 4 FAIL**，保留预期与实际值。FLV项检验公共入口请求参数，并非声称FLV应进入HLS缓存。
2. 入口显式启用后，上述三种启动/手动重启与断流续接均收到true，并保留源URL/查询策略归属、liveRecording标记及用户停止状态。
3. 实际Manager测试核对true/false、诊断对象、源策略和原始参数向Service传递；随后离线任务恢复false、无策略/诊断。同步补齐旧Service测试替身漏掉的可选参数，生产Manager/Service未修改。
4. 真实loopback relay测试核对FLV/本地TS输入不创建HLS relay；非live即使传true也不预取媒体，首次GET后才下载正文。复用并执行第二rendition不支持、超大有限清单、失败状态传播、重复读取/范围、迟到根响应、LL完整父片和停止排空控制。
5. 最终七文件 **103/103 PASS**；四个改动Dart文件严格分析无诊断。相邻控制器输出/完整性警告、手动取消/目录释放、续签回调归属和过期凭据回归通过。

这证明源码接线与所列确定性行为，**不等同实际控制器→原生→最终卡片完整运行**。上轮真实TTing探针直接调用Manager，虽底层相同，但没有覆盖本轮控制器生命周期；不得外推成Android或GUI通过。

## 证据与资源

根目录 `local-artifacts/hls-controller-prefetch-20260910`：`red-tests.log`、`enabled-tests.log`、`enabled-analyze.log`、`enabled-source-hashes.json`。提交前复核四文件SHA与最终执行输入一致。

| 阶段 | 资源记录 | 秒 | 峰值CPU | 峰值工作集B | 结束活跃重型进程 |
| --- | --- | ---: | ---: | ---: | ---: |
| 入口未启用的四项失败 | 20260909T175313749Z-hls-controller-prefetch-red.json | 36.413 | 25.07% | 5748535296 | 0 |
| 103通过/四文件严格分析 | 20260909T175436442Z-hls-controller-prefetch-enabled.json | 39.139 | 9.11% | 5831798784 | 0 |

红测阶段先按共享资源守卫等待其他Java任务结束，没有终止其他进程。开发中的一次复合PowerShell编辑命令在启动前被执行器拒绝，随后使用文件补丁工具；该次没有源码写入或测试进程，不计红测结果。

## 下一步、交付与回滚

下一步使用真实RecorderController和本机原生后端，验证启动→采样→用户停止→自动合并→最终指标与资源释放，优先固定本地输入以避免把源站波动混入控制器接线问题。随后纳入累计候选，推进Android/Windows可见UI、多任务资源与长期验收；旧单ticket停止超时及其他平台缺口仍保留。

撤回 `a10327be` 可恢复应用入口的false默认，不改变底层能力。现有Android/Windows候选不含本次启用；本轮无构建、安装、手机/MT/Root/LSP操作、发布或上游合并。历史仍20 PASS/32 RUN/10 NR，42组未闭环，另9组参考平台未接入，全平台3.2.0目标保持。

## 真实控制器原生闭环增量

探针提交 `9b8f29a8`，生产仍为上述 `a10327be` 行为。新增 `tool/probes/recorder_controller_native_probe_test.dart`：通过实际RecorderController调用实际FFmpegManager/Service、原生FFmpegKit和VideoProcessorService。仅注入固定源Resolver、独立Hive/录制目录、容量1且无启动间隔的测试调度配置、100毫秒采样与不支持手机后台服务的测试构造器；这不是原生GUI或Android后台服务验收。

固定输入复用已校验SHA的fMP4夹具，音视频各三片，使用不同媒体序号200/100，清单保持LIVE且不向源站发请求。两轮均由同一控制器的用户入口启动→读取两路预取→用户停止→自动合并；第二轮是同一任务停止后重新开始，没有绕过控制器直接启动或手动合并。

- **实际原生测试1/1 PASS，包含连续两轮录制/自动合并**。每轮180视频包、282音频包，无包时间线内部空档或DTS倒退；两份MP4均全文件严格解码退出0、stderr空。
- 每轮临时TS统计698,420 B，停止后任务 `fileSize` 自动回写为MP4的648,853 B，而非沿用临时大小。两个不同目录/文件前缀，完整成品SHA均为 `9821CBE7A110E1C836AA81D1608FC2BB12F6AFC8AB501664C70D92C3F42EFD7B`。
- 停止连自动合并分别1557/1530毫秒；任务stopped、wasStoppedByUser=true、pendingAttempts空、无lastError。native code0、manualStop/drained=true，四项强制取消/丢尾/覆盖/完整性标记false。
- 停止前目录受保护；完成后目录保护释放，scheduler运行/排队均0，Manager无该任务、VideoProcessor无处理任务、原relay池0条目，TS清理完成。这里只验证进程内资源归属，不据此宣称长期CPU/内存平台期或用户数据重启往返。

开发过程明确分层：首轮因Get.put的可空泛型推断而编译失败，尚未运行原生；修订后两轮原生通过，但严格分析报工具目录内四处测试可见成员访问和一处花括号问题。最后仅补精确的测试目录诊断标注与花括号，复用已通过的原生行为证据，执行加载检查（1项opt-in跳过）和单文件严格分析通过，未重复采集。

| 阶段 | 资源记录 | 秒 | 峰值CPU | 峰值工作集B | 结束活跃重型进程 |
| --- | --- | ---: | ---: | ---: | ---: |
| 编译失败，未录制 | 20260909T180039676Z-controller-native-first.json | 16.080 | 8.55% | 5485281280 | 0 |
| 原生1通过/分析失败 | 20260909T180120852Z-controller-native-typed.json | 32.120 | 8.96% | 5479206912 | 0 |
| 仅加载/严格分析通过 | 20260909T180239200Z-controller-native-lint.json | 26.733 | 8.99% | 5482274816 | 0 |

证据根 `local-artifacts/controller-native-20260910`，原生目录 `output/controller-1788976863397144`；`summary.json`记录两轮任务、原生终态、包时间线和请求路径，`media-hashes.json`固定两份成品，`typed-source-hashes.json`和`lint-source-hashes.json`分别固定行为验证与最终静态输入。没有新生产修复，不把夹具或lint修订计为用户Bug。

W3-05新增当前源码的控制器→原生→自动合并子项，仍RUN：尚缺累计候选可见卡片/交互、Android、多任务与长时/续签。下一步将此前累计平台、录制和界面修订纳入新的Android arm64 Debug候选并核验产物，实际安装/前台操作另走设备租约与用户设备约束；不更新模块、不清数据、不发布3.2.0。
