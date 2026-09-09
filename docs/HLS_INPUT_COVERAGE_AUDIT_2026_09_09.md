# 活动录制 HLS 缺片提示与终态证据（2026-09-09）

实现提交 `0c2fe8f48ab5ce9213a9ff94e4e4d4da35a1c483`，修订前 `9a0e802f`。本批承接[滚动 HLS 慢交付对照](HLS_ROLLING_DELIVERY_AUDIT_2026_09_09.md)，修复已明确丢片却未进入任务状态和结果界面的信息缺口；**没有修复慢网络的媒体吞吐、时间线或完整录制问题**。

## 根因与处置

最小复现是 6 秒滚动窗口、2 秒视频片段耗时 12 秒完整交付。生产 FFmpeg 已报告 skipping/expired，15 秒预算场景仍能 started、用户停止 code=0、生成可逐包读取的 TS，但 34 秒采集仅约 4 秒内容。第一个错误状态在日志回调：旧实现仅进入可裁剪的诊断尾部，没有独立保存活动采集缺口；控制器和任务 JSON 因而没有相应状态。包损坏、停止尾片舍弃、缺失媒体时段是三个不同维度。

只读对照冻结上游 `c6c9bd70aedc503c003110dae10a83ad0bb891d8`、merge base `527fea1b40885e3621d53c9646b523dd8522290c` 和本批修订前：三者 setLogCallback 都仅 appendDiagnostic，服务及模型均没有活动缺片字段。因此本批**信息丢失缺陷归为 upstream-existing**，选择局部接线，不合并上游。维护分支完整分片暂存与读取预算的协调缺口仍按前篇单独调查，不把所有实际媒体缺失归为这一信息缺陷。

## 状态合同和界面

- FFmpegRecordSession 只识别两种明确 HLS 缺片日志：跳过正数个过期片段，或某 playlist 的 segment 多次失败后明确跳过。通用 I/O、单次打开失败、重复 moov、跳过零片、包损坏本身均不推导覆盖缺口。
- 仅在 liveRecording 且未请求停止/续租排空时锁存；裁剪诊断尾部不清除。没有时点的终态备用文本不回填活动缺口。该机制是观测证据，false 不证明完整覆盖，也不推测准确丢失秒数。
- 每个 native 会话首次 false→true 发出一次 inputCoverage 事件，并将 inputCoverageIncomplete 放入终态。控制器检查当前 session，终态异步采样后再次检查所有权；过期事件不污染新会话。
- 任务在原有保存路径持久化可选 bool，旧 JSON 默认为 false，当前任务 JSON schema 9 与应用设置 schema 7 均不递增。原生重连、清理普通失败信息、成功合并不清除此标记；用户开始一轮新录制才重置。
- 此字段属于当前用户录制的任务级汇总，不是每个历史文件的完整性证书。新一轮录制后旧 pendingAttempts/历史成品的逐文件缺片追踪仍待独立设计；本批未增加历史归档索引。
- 录制卡片区分活动缺片和停止尾片舍弃；两者同时存在时显示两段提示。中英文、320/900 宽度、双倍字号验证提示和主操作可达；既有全部状态操作回归保持。
- 提示事件不伪造 started、字节、错误或重试，不修改停止与合并决策。已识别 packet damage 仍阻止对应损坏来源合并，活动缺片不阻止保留/合并有效已录片段。播放器、画中画、弹幕、代理、画质与时间戳参数未修改。

## 验证结果

最终 **147/147 定向测试（8 文件）+ 2/2 原生探针（1 项统计回归、1 项四场景控制）**；13 个改动 Dart 文件 fatal-infos 分析通过，中英文 JSON 解析通过。Huya 探针仅修订接口转发并静态分析，本批没有重新执行其在线录制。

定向覆盖：日志裁剪后的锁存、正常停止/续租排空/非直播负例、旧 JSON 与新录制重置、旧会话与异步终态隔离、正常合并保留提示、租约与用户停止，以及真实双语资源的布局与点击。模型恢复证据为 JSON 往返，控制器通过已有 updateTask/schedulePersist 接线；本批没有额外执行手机落盘重开验收。

原生输出：`local-artifacts/hls-coverage-20260909/controls/rolling-1788943843534745/`。复用并核对前篇固定 60 秒夹具哈希，调用生产 Manager/Service/relay/Windows FFmpegKit；所有媒体请求到 loopback。

| 场景 | started / 输出字节 | 缺片提示次数 / 首次 ms | 终态缺片 / 尾片舍弃 / 包损坏 | 停止耗时 ms |
|---|---|---|---|---:|
| healthy-10 | true / 1884324 | 0 / — | false / false / false | 433 |
| continuous-body-10 | false / 0 | 1 / 10238 | true / true / false | 2023 |
| continuous-body-15 | true / 451952 | 1 / 12167 | true / true / false | 2534 |
| delayed-headers-15 | true / 451952 | 1 / 12151 | true / true / false | 2531 |

四场景均有结构化 inputDrained=true、forcedCancel=false，非仅根据停止耗时推断。慢场景提示均在 34 秒停止请求前出现，15 秒两个场景甚至早于 started；零输出场景也保留缺片事实，没有把提示当启动。正常控制无误报。请求数分别 43、19、103、103，诊断省略数为零。

媒体结果保持前篇：正常 video480/audio750 包；两个 15 秒慢场景 video120/audio188 包、接收 video sequence 0 和 6、约 4 秒成品，仍不满足完整录制。没有本批全解码或逐帧内容对齐证据。

## 失败、续接与资源账目

1. `20260909T084421189Z-hls-input-coverage.json`：首轮分析退出 3，发现两处旧测试覆盖方法缺少之前新增的可选参数；未开始测试。115.949 秒、峰值 CPU 12.82%、WS 10303717376 B、结束活跃重型数 0。first-analyze.log 与 first-source-hashes.json 保留。
2. 同类实现只读检查额外发现租约测试与 Huya 委托探针，共补齐四处签名；委托同时原样转发 sourceQueryPolicy/hlsDiagnostics，未改变生产接口。随后 13 文件格式化成功，但续接时原工具句柄 3680 已消失；进程清单确认脚本 PID 78912 和 Dart 均不存在，分析日志只有开始行、没有测试日志。interruption-observation.json 与 interrupted-* 记录该事实，不计为分析通过或产品失败。
3. 校验已格式化的源码哈希后，从未完成的分析阶段恢复，没有重复格式化或重建夹具。`20260909T085249927Z-hls-input-coverage.json`：分析/147 测试/原生 2 项全通过；283.371 秒、峰值 CPU 12.08%、WS 1576976384 B、结束活跃重型数 0。

重型任务经 build_resource_guard 串行；排队/运行期间保持源码和测试固定。日志使用明确的 stdout/stderr Tee-Object 捕获，analyze.log/tests.log/native.log 是直接子进程输出，不仅依赖 transcript。FFmpegKit 构建钩子提示下载地址未附 SHA 文件；本机 DLL 实测 SHA-256 为 `888A15993862950FEED714990E459F653B68BBC2CE30DA7D4BDA8DB9A5212C06`，与前篇运行库相同，不据钩子提示声称远端校验完成。

本地证据目录另有 check.ps1/resume.ps1、source-hashes.json、native-runtime-hash.json、final-artifact-index.json 及每场景 origin/hls-timeline/result/packets JSON 和 TS。构建钩子不等于应用候选打包。

## 剩余工作与回滚

下一步在此控制上继续解决完整暂存与本地读取预算协调，保留中断半片不进入解复用器的不变量，并独立应对持续吞吐低于媒体码率；不以静默降画质、加等待或压缩时间轴代替验收。随后验证真实 TTing 采集和音画同步，以及累计 Android/Windows 原生界面。

全目标仍为 18 直播站点 + IPTV、9 组参考平台未注册、42 个宏观大项未闭环。版本仍 3.1.8+4121；未操作手机、MT、Root/LSP，未卸载、清数据、重启、重建候选、发布或合并上游。现有候选不包含本批。必要时以实现提交的反向补丁回退；旧读取器忽略可选 JSON 字段，回退也会失去缺片提示，不代表媒体问题消失。

后续：[上游 body 空闲超时与资源回收](HLS_BODY_IDLE_AUDIT_2026_09_09.md)已补齐；该批零输出停止兜底差异独立记录，继续预算与完整内容验收。
