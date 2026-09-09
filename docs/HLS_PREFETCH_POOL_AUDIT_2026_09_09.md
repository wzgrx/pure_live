# HLS 未读响应取消与预取缓存所有权（2026-09-09）

起点 `216c118d`，承接[清单保留层](HLS_RETAINED_WINDOW_AUDIT_2026_09_09.md)。本批包含两项不同层级的进展：

1. `109d5fb2108d333980fcf0c7c25fefe1d08eaaa0` 修复**生产 relay 未读响应未真正取消**的问题。
2. `0eef1043299dc98396cccb87685071908e4c9b6b` 新增**有界预取池及读取租约**，目前仅测试导入，尚未接入实际录制清单和下载链路。

真实 TTing 的缺片仍未解决；上述基础实现和局部修复不计为稳定录制通过。

## 发现、根因及红绿证据

预取池首轮 46 通过/1 失败：任务在 loader 返回前已取消，返回的 body 还未调用 moveNext。代码调用 StreamIterator.cancel 后池关闭已结束，但响应流从未订阅，其 onCancel 未触发，测试随后等待 controller.close 到 30 秒超时。

读取本机固定 **Dart 3.13.0** 的 lib/async/stream_impl.dart（约 971–1113 行）确认：StreamIterator 在第一次 moveNext 才订阅；此前 cancel 清除持有的流，不替原始流建立并取消订阅。不是通过扩大观察期限来处理，SDK 原件哈希、节选和版本已保存。

相邻生产 relay 的 `_publishCompleteBody` 在达到八个暂存名额时，会先对第九个请求返回 503，再在 finally 中取消一个尚未读取的 StreamIterator；清单/丢弃响应的停止或预算早退也有同一模式。为区分已有生产缺陷与新组件失误，新增独立真实 TCP 红测：

- 八个上游响应给出部分 body 后持续等待，relay 实际 stagingBodyCount=8。
- 第九个响应同样只给部分 body；本地返回 **503、零字节**，但修订前该上游 TCP 在 3 秒观察内仍未断开。
- 首轮红测 0/1，之后给两个等待点加上不同标签再跑 0/1，明确失败点为 **ninth body TCP cancellation before finish**，不是八个请求尚未进入暂存。是同一个缺陷的确认，不计成两个 Bug。
- 修订后这一测试通过：第九个 TCP 已断开，finishRequested=false，前八个 TCP 尚未结束、名额仍是 8；随后主动停止得到八个 410，清理原所有权。

来源归为 **fork-regression**：该暂存路径来自维护提交 `6415d42e71aa76d5ab3304f737bebf593cb6a792`；冻结上游 `c6c9bd70aedc503c003110dae10a83ad0bb891d8` 与 merge base `527fea1b40885e3621d53c9646b523dd8522290c` 没有该 relay，沿用[预算审计](HLS_BUDGET_COORDINATION_AUDIT_2026_09_09.md)的来源核对。没有合并上游。

## 生产修订

新增 `HlsBodyReader`，保留 StreamIterator 的逐次读取语义：已开始读取时取消并等待原订阅；尚未读取时对源流执行 listen/cancel，等待实际清理。重复取消复用同一个 Future，避免第二个调用误认为第一次异步清理已结束。

relay 的媒体暂存、清单读取和有界丢弃响应统一使用它。只取消当前响应，不关闭共享客户端，不影响其他请求、质量、媒体时间戳、完整分片后发布、用户停止意图或本地 native 参数。

原有 `_HlsResponseBudget` 原逻辑移入同一辅助文件并命名为 `HlsResponseBudget`，供 relay 和预取池复用。4 倍空闲的总响应策略及 native 等待公式未变；相关 timeout、TLS、停止回归与原生控制通过。

## 预取池已实现的合同

`HlsPrefetchPool` 按一个录制来源代次创建，接受调用方提供的完整请求身份和 loader，不自行识别直播平台：

- 默认最多 **8 个条目**、同时 **6 个下载**、**8 个读取租约**。排队、下载、完成缓存、已淘汰但仍在读取的条目共同占用八个名额。同 key 合并请求，满额返回未接纳，不隐式淘汰或自动重试。
- 默认总媒体字节 **128 MiB**，单 body 上限也为 128 MiB。每个 chunk 在异步落盘前预留共享额度；失败、淘汰和正常关闭仅在实际清理后返还。每条目最多 2 MiB 内存，超出后使用原有 spool。
- 完整接收并通过长度核验、期限检查后才可 acquire；截断、声明超限、连续交付超限、超时和取消均不发布部分媒体。ready 返回布尔结果，failure 区分 cancelled/download/capacity/timedOut，不保存原始异常或秘密地址。
- body 默认空闲 15 秒，总逻辑预算 4 倍；预算在 loader 调用前开始，body 每次读取用剩余总量与空闲量的较小值，seal 后再次检查。测试覆盖无首字节与每 100 ms 持续交付而超过总量，均真实取消流并释放额度。
- loader 仍负责连接/响应头期限、HTTP 状态和范围校验、认证及请求级取消。超时前仍未返回的 loader、正在执行的磁盘 IO 或本地写入不会被遗弃；关闭等待真正结束。因此这不是对任意不合作回调的强制墙钟期限承诺。
- `HlsMediaSpool` 新增 reusable 参数，缺省 false 保持既有行为。池内设为 true；内存读取返回独立字节副本，修改一个消费者收到的 chunk 不污染后续读取。落盘内容保持只读使用。
- 租约 writeTo 以 StreamConsumer.addStream 的完成作为真实读取结束，既不提前删除 spool，也不替调用者关闭目标响应。租约在写入中 release 会等该次写入完成或失败；同租约并行写拒绝，其他读取受统一上限约束。
- 淘汰后新 acquire 失败，但旧租约仍保护原件；同 key 新一代也先受旧条目占用的名额约束。close 与淘汰等待活动读取，调用方应先结束本地响应并在 finally 释放租约，避免自己形成等待环。
- 删除失败仍保留计费条目，停止接纳并取消其他排队/下载，close 显式报错；不会删掉无关文件、把未清理磁盘记成成功或不断重复自动下载。

这些是所有权/容量上限，不是精确堆 RSS 测量。内存消费者副本、网络缓冲及对象开销另计；池内八个 2 MiB 的缓存和最多八个同大小读取副本都有数量约束。池没有选中清单轮询、原生清单生成、源代次业务接线或自动媒体缓存命中部署。

## 验证与原生结果

最终 **69/69 定向（10 文件）**、七个改动 Dart 文件 fatal-infos 分析通过。新池 15 项、reader 3 项、生产未读响应 TCP 1 项，另复验 spool、诊断、暂存上限、relay、body 空闲/累计预算、TLS 与停止。没有取消已有严格断言。

其他边界证据：排队条目淘汰不执行 loader；关闭等待迟到 loader；真正 TCP 断开；租约阻止落盘提前删除；读取中的 release 与 close 都等待；消费者异常后缓存仍可读；超限声明在零首字节时也取消；清理失败取消正在等待及排队的条目，保留无关 keep 文件。

固定 FFmpegKit 和原媒体逐文件哈希核验后，两次原生控制均 **3/3（两项统计 + 四场景原生测试）**；独立直连预取实验本批跳过。最终目录 `local-artifacts/hls-prefetch-pool-20260909/controls/rolling-1788950865489266/`：

| 场景 | 输出 B | 完整视频 sequence | 停止 ms | forcedCancel / inputDrained |
|---|---:|---|---:|---|
| healthy-10 | 1884324 | 0–7 | 476 | false / true |
| continuous-body-10 | 451952 | 0、6 | 2336 | false / true |
| continuous-body-15 | 451952 | 0、6 | 2395 | false / true |
| delayed-headers-15 | 451952 | 0、6 | 2483 | false / true |

四场景 inputIntegrityError=false；正常无缺片提示，三个慢源各一次。健康 video480/audio750 包；慢源 video120/audio188 包、约 4 秒内容，与前篇相同。说明响应取消修复未破坏完整发布和停止，但**预取池尚未接线，串行化与短窗口跳片没有改善**。没有实网重录、成品全量解码或跨平台完整验收新增。

## 证据、资源和交付边界

本地根 `local-artifacts/hls-prefetch-pool-20260909/` 保存脚本、各阶段直接日志/源码哈希、首轮池原件、SDK 节选、两轮 native JSON/TS 与 artifact-index.json（排除索引自身及 Hive/lock）。本次 native DLL 本地固定哈希已核验；下载 hook 报远程 SHA 缺失与本地验证分开，不宣称远程校验成功。

资源记录在 `local-artifacts/build-records/`，文件统一日期前缀 20260909：

| 后缀 | 结果 | 时长 s | 峰值 CPU % | 峰值 WS B |
|---|---|---:|---:|---:|
| T102901128Z-hls-prefetch-pool-first.json | 46 通过/1 超时失败 | 92.772 | 8.75 | 12540702720 |
| T103313913Z-hls-prefetch-pool-ownership-red.json | 生产红测 0/1 | 94.941 | 14.97 | 12282753024 |
| T103507039Z-hls-prefetch-pool-ownership-red-labeled.json | 标明失败边界后 0/1 | 85.731 | 29.94 | 12284051456 |
| T103736920Z-hls-prefetch-pool-final.json | 66 定向通过 | 105.731 | 9.11 | 12591095808 |
| T104317121Z-hls-prefetch-pool-complete.json | 67 定向 + 3 原生通过 | 262.074 | 9.29 | 12324122624 |
| T104952125Z-hls-prefetch-pool-bounded.json | 69 定向 + 3 原生通过 | 266.217 | 76.15 | 13558169600 |

全部串行使用资源互斥，结束活跃重型数 0，时长含等待；WS 是监控进程组峰值，不是新池的独立占用。沿已确认句柄等待，无终止或重启其他工作，排队/运行时未编辑源码或测试。

下一步将选中媒体清单、请求/范围身份、HTTP 响应元信息、现有认证/预算和预取池连接起来，补 LL-HLS/保留窗口发布、消费与淘汰策略，再用固定慢源证明连续内容覆盖改善。当前元数据窗口和池都不自动用于生产，严禁把基础层通过误记为 TTing 修复完成。

未操作手机、MT、Root/LSP、安装、重启、候选构建或发布。18 直播站点 + IPTV、9 组未注册；宏观仍 20 PASS/32 RUN/10 NR，42 项未闭环，版本及候选不变。回滚池可反向应用 0eef1043；反向应用 109d5fb2 会重新暴露已复现的未读响应泄漏，两者依赖关系应一并审查。
