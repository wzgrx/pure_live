# HLS 响应头阻塞与原生预取对照（2026-09-09）

探针提交 `22934f8feb6e31e1520433876d60ec2927534457`，输入应用提交 `3899e594`。承接[预算协调审计](HLS_BUDGET_COORDINATION_AUDIT_2026_09_09.md)。本批仅新增可重复诊断，生产录制、完整分片保护、候选和版本未变。

## 问题、来源及对照设计

前一批已排除 native 过早超时，但 12 秒慢交付的 2 秒视频片段在 6 秒滚动清单中仍从 sequence 0 跳到 6。待验证假设：relay 的完整分片暂存同时延后了响应头交付，native 的下一片预取要等当前连接打开完成，因而退化为串行获取。

生产 `_publishCompleteBody` 在 body.seal 和预算检查之后才向本地 HttpResponse 写入及关闭；`FFmpegService.start` 在 liveRecording=true 时接入此 relay。直连对照通过同一个生产 manager、命令工厂与固定 FFmpegKit，设置 liveRecording=false，仅针对本地 HTTP 夹具形成无 relay 输入；此差异还影响进度解释、缺片事件和停止行为，因此比较范围严格限定为**停止前源请求时序**。

[FFmpeg 当前 HLS 源码](https://raw.githubusercontent.com/FFmpeg/FFmpeg/master/libavformat/hls.c)中 read_data_continuous 先 open_input 当前分片，再根据 http_multiple 调用下一分片 open_input。它支持该假设，但当前 master 并不等于本机嵌入版本；实际结论以下述固定 native 对照为准。读取快照 SHA-256 `65EBF928221EA73AA3623E7227C9A5E5EA2E734F4784B08AFE9FD75CC21676DF`，UTC 09:54:52 保存。

来源仍为 **fork-regression**：完整分片暂存由维护提交 `6415d42e71aa76d5ab3304f737bebf593cb6a792` 引入；冻结上游 `c6c9bd70aedc503c003110dae10a83ad0bb891d8` 和 merge base `527fea1b40885e3621d53c9646b523dd8522290c` 无此 relay，见前篇。与之并存的慢源/短窗口跳片并非全部来自此问题。本批无上游合并，也没有把所有 TTing 缺口归因于已定位的单一机制。

## 固定输入与结果

原 60 秒 H264/AAC 分离 CMAF 夹具逐文件哈希复核，2 秒分片、6 秒窗口，仅接收请求时仍在窗口的片段；已接纳请求即使后来离窗也完成。视频 body 用 13 块、12 次 1 秒间隔持续发送，或延迟响应头 12 秒后一次交付；音频与初始化资源不加延迟。各场景运行约 34 秒，串行执行，不使用公网或手机。

所有 native 实际 rw_timeout 均为 **60,000,000 μs**，并从 C 层 session 命令提取数值核验，不保存完整命令。relay 的上游空闲为 10 秒，足以覆盖每次 1 秒 body 间隔；直连为 60 秒，避免超时混淆。http_multiple 显式设置并从实际命令复核。

| 场景 | relay | http_multiple | 完成视频请求重叠 | 停止前完整源片 sequence | 完整源视频字节 |
|---|---|---:|---|---|---:|
| 早响应头 + 慢 body | 无 | 1 | 是 | 0、1、7、8 | 768898 |
| 早响应头 + 慢 body | 无 | 0 | 否 | 0、6 | 361543 |
| 晚响应头 + 一次 body | 无 | 1 | 否 | 0、6 | 361543 |
| 生产完整暂存 + 慢 body | 有 | 1 | 否 | 0、6 | 361543 |

关键时序（源单调时钟 ms）：

- 直连预取：片 0 在 58 请求、12088 关闭；片 1 在 73 请求、12100 关闭，清楚重叠。下一组为 12110/12113 请求片 7/8。
- 直连单连接：片 0 在 14 请求、12043 关闭；片 6 在 12053 才请求。
- 延后响应头：片 0 在 58 请求、12063 关闭；片 6 在 12179 请求。
- 生产 relay：片 0 在 81 请求、12112 关闭；片 6 在 12203 请求。即使强制 http_multiple=1，也未恢复重叠。

这组证据支持“完整暂存的响应头门槛推迟 native 预取”，而非“只需打开 http_multiple”。对比直连的早/晚响应头时保持 liveRecording=false、相同命令与 native 预算，进一步隔离 manager 模式差异。

**直连预取也没有保持连续内容**：sequence 1 后直接到 7，四个完整视频分片只代表 8 秒源内容；比串行多收两片不是完整录制。直连两个 body 场景没有 expiredAtRequest 请求，但仍存在 sequence 跳跃，说明“没有 HTTP 410”也不是完整性证明。前述字节是源完整响应，不是输出媒体验收值。

## 探针质量与停止边界

扩展 `tool/probes/hls_rolling_delivery_probe_test.dart`，新增独立开关 PURELIVE_HLS_SCHEDULING_PROBE。原四场景控制保留原开关与断言，不扩大默认测试网络范围。新增统计单测排除空失败、未完成 body，仅按停止前已完整交付的视频请求计算重叠；另保存当时深拷贝的 origin-before-stop.json，避免 finally 收尾改变比较样本。

本批 **3/3 通过（两项统计测试、一项四场景原生对照）**，旧滚动四场景测试跳过、复用前篇证据；单个改动 Dart 文件 fatal-infos 分析通过。每个场景停止前请求记录分别 29、19、25、25 条，事件 61、62、46、52 条，均低于 512 容量。停止前未完成视频请求分别 2、1、1、1，不计作完整接收。使用未完成请求也参与统计会虚增吞吐，本批没有这样计数。

三个直连实验按现有 manager 取消停止：forcedCancel=true、inputDrained=false，停止观测 43/81/70 ms；日志明确出现 packet mux/trailer 的 immediate exit。生产 relay 场景停止约 2640 ms，forcedCancel=false、inputDrained=true、inputIntegrityError=false。直连 code=0、inputIntegrityError=false 在 liveRecording=false 的模式下也没有证明输出无损，本批没有执行成品全量解码或合并验收。直连产物只是诊断附件，**不建议用移除保护替代修复**。

## 证据与资源

本地根 `local-artifacts/hls-scheduling-20260909/`：

- controls/scheduling-1788947735195349：四场景 result.json、origin-before-stop.json、origin.json、诊断 TS，以及总 summary.json。
- check.ps1、format.log、analyze.log、直接 Tee 的 native.log、source-hashes.json、FFmpeg 参考快照、post-run-processes.json；artifact-index.json 覆盖上述原件，排除自身及 Hive/lock。
- 测试源码 SHA-256 `88F31B4BB93A60922F1CD23F65A3481F9F3203D41653AD8840BE5B9A91734F46`；FFmpegKit DLL 与前篇固定哈希一致。
- 资源记录 `local-artifacts/build-records/20260909T095816174Z-hls-native-scheduling-control.json`：251.090 秒（含资源等待），峰值 CPU 78.07%、WS 9960132608 B、213 样本，阶段 format/analyze/native 均退出 0。
- **结束活跃重型数为 2，不是 0**。本次 exec 已退出 0；后续进程快照只有 Java，没有 Dart/Flutter/rg。保留记录，没有宣称机器全空闲，也没有终止其他构建。运行期间未编辑源码或测试，没有重启任务。

## 下一步与未完成范围

下一步设计并验证独立于 native 请求节奏的**有界媒体预取和保留清单窗口**：仅围绕实际选中媒体清单，不下载 master 中全部画质；下载与已完成缓存共同计入容量，保留原始序列、PDT、字节范围、初始化段/密钥归属。必须先覆盖短窗口过期、音视频不同步刷新、消费者暂停、停止与来源代次变化等条件，再接入生产 relay。

提前向 native 发送 200 响应头会失去暂存失败/停止时返回独立 HTTP 状态的机会，直接流式媒体又会重新暴露已证实的半片封装问题；本批未作这两种改动。独立预取若受总带宽限制也会失败，应明确标记缺片而非伪造连续时间线。该方案尚未实施，不计为解决真实 TTing 缺口。

本批无生产逻辑修改、实网重录、设备/MT/Root/LSP 操作、安装、候选构建或发布。仍为 18 直播站点 + IPTV、9 组未注册；宏观 20 PASS、32 RUN、10 NR，42 项未闭环。Android bee143e2、Windows f3de664a 候选及 3.1.8+4121 不变。探针回滚可反向应用 22934f8f，不改变生产行为；原始证据仍保留。
