# HLS 独立清单刷新与有界预取调度（2026-09-09）

起点 `430322f3`，承接[共享上游传输审计](HLS_UPSTREAM_TRANSPORT_AUDIT_2026_09_09.md)。代码 `fc0fa50ebc2432f0e9d20a8a59335ba3e44a3a39`。

## 范围与接线层级

本批新增 `HlsPrefetchScheduler`，把选中的媒体清单独立刷新、元数据保留、完整分片预取和读取后淘汰接起来。仅由调用者选择最多两个媒体 feed（音频/视频）；不主动枚举 master 中的其他质量。生产默认路径尚未启用这个调度器。

原生探针通过一个实验 HTTP 适配层把调度器放在**现有生产 relay / FFmpegManager 之前**，仍使用原来的完整响应暂存保护、FFmpegKit 和滚动源站。多这一层不是直接生产接线，也不是 APK 已包含该功能；本批没有手机操作、构建、版本修改、上游合并或发布。

宏观验收仍 **20 PASS / 32 RUN / 10 NOT RUN，42 项未闭环**。这不是 42 个已确认 Bug。TTing 真实源持续录制、生产兼容回退、全平台验收和稳定版发布仍待完成。

## 生命周期与限额

- 每个已选 feed 以目标时长的一半刷新，500 ms–30 s，单 feed 同时只存在一个刷新；清单 body 通过共享 HTTP 策略、4 MiB 上限、严格 UTF-8、读预算、可取消读取进入保留窗口。
- 只有完整初始元数据和渲染合同通过后才开始下载；LL-HLS PART 等未支持标签仍退回调用者原路径。刷新失败使该 feed 的下一次发布显式失败，不无限重复旧清单；重试/来源更新由更上层负责。
- 同一池跨两个 feed 轮转准入，按最大支持 feed 数预留容量。早先开发中允许四个 feed 却只预留第二个，第三个可能被先到的两路占满；本批在启用前收紧到最多两个，不宣称任意多轨公平调度已验收。
- 池默认仍是 8 条目、6 下载、8 读者、128 MiB；可配置的条目硬上限从 8 扩至 32。本探针为 **32 条目 / 16 下载 / 每体 512 KiB 内存**，即缓存体内存阈值总计最多 16 MiB，溢出走有界磁盘暂存，总字节仍 128 MiB。现有生产 relay 的暂存预算另计，未称作两层共同的全局上限。
- 媒体键含 feed、sequence、URI、Range，防止同 URI 在后续序号复用旧体；MAP/KEY 按已有完整身份共享，资源 URL 通过新增 typed renderer 回调分配，而非只按来源 URI。
- 本地完整响应交付后通知 delivered，保留最近两段，并保护最近两次发布中尚未交付的依赖；从保留窗口退休的旧序号不因源站重叠刷新而复活。它是本地 HTTP 完成信号，不是解码器已消费证明。
- 所有待下载、已就绪、已退休但仍被租约引用的数据仍归同一池计费；满额回压，不启动无限队列或隐式重试。已发布有限 ENDLIST 也会随交付前缀释放容量，避免整份旧清单永久钉住早期资源。
- freeze 停止轮询并取消在途清单，迟到结果不改变代次；stopFetching 再终止未完整媒体，但就绪体留作排空。close 由调用者先结束本地 writer/释放租约，再等待真实下载、读取和清理 Future。

## 本批发现并修复的取消回归

`analyzer-fixed` 首次功能运行 92 通过、1 失败：`retiring redirect-body closes its real TCP...` 超过两秒。根因是响应已交付 reader 后，`HttpClientRequest.abort` 不再可靠地终止正在读取的重定向 body；原请求取消钩子虽存在，却未单独取消 reader。

来源 **fork-regression**，由共享传输提交 `3a1647de` 提取引入：提取前的录制 `_discardResponse` 会把 iterator.cancel 注册到 relay 停止表；提取后的 redirect reader 只依赖 request.abort。旧测试可在 headers 尚未完成时取消而通过，所以历史一次通过不足以覆盖此时序。

修订把重定向 body 的 reader.cancel 同时登记到共享 transport 停止表和单 ticket token，finally 撤销并 await reader.cancel。增强真实 TCP 测试以委托包装观察**实际 response.listen 订阅**后才取消，不靠 sleep 猜测阶段；随后仍验证另一缓存和同客户端后续请求保持可用。新增 snapshot-body 分支也验证真实 TCP 取消。

## 验证设计与失败保留

定向共七个文件：scheduler、retained manifest/window、pool、upstream client、HTTP metadata、body reader。滚动 HTTP 测试按 120 ms 前进一个序号、三段源站窗口、每体 600 ms 完成交付、30 ms 清单轮询，在两路各顺序读取 13 段时检查：首体完成前已刷新、无过期请求、无重复资源下载、无覆盖缺口、容量上界及最终零占用。网络为真实 loopback TCP，不把 mock 字节测试当成媒体解码证据。

原生实验复用 `local-artifacts/hls-rolling-20260909/fixture-hashes.json` 校验的同一组 fMP4：2 秒媒体段、6 秒滚动窗口、仅视频持续 12 秒 body 或等待 12 秒 headers，分别曝光 34 秒。基线是上批 `controls/rolling-1788953554148270`，同样配置未调度时只完成视频序号 0、6，约四秒视频。新实验保留原源站请求日志、本地 relay 日志及 ffprobe 包时间线；不重写媒体 PTS/PDT。

开发失败分别留档：

1. `first`：一个可空 ticket 捕获错误和一个未用 import，分析失败，未执行功能测试。
2. `analyzer-fixed`：分析通过、92/93，重定向 body 实际取消失败。
3. `redirect-cancel-fixed`：修复后 93/93。
4. `native-first`：本地脚本拼接时 PowerShell 字符串插值错误，原生阶段没有加入；实际仅九文件分析与 93/93 定向通过，不计为原生通过。

## 最终实测与资源记录

九个变更 Dart 文件严格分析通过，最终定向 **184/184**（调度/依赖 93，生产 relay 相邻回归 91，共 17 文件）；原生文件 **3/3**（两项统计、一项含两个场景的原生实验），历史无调度原生场景本次 skip，复用上批基线而非误记重跑。证据根目录 `local-artifacts/hls-prefetch-scheduler-20260909/`，本次原生目录 `controls/scheduled-1788956153790438/`。

| 34 秒曝光场景 | 输出字节 | 本地完整视频序号 | 视频/音频包 | 探针停止耗时 ms | 源站请求/过期 |
| --- | ---: | --- | --- | ---: | --- |
| 持续 12 秒视频 body | 3,329,668 | 0–13，连续 | 840 / 1407 | 2131 | 109 / 0 |
| 延迟 12 秒视频 headers | 3,329,668 | 0–13，连续 | 840 / 1407 | 2060 | 109 / 0 |

两场景均 `code=0, forcedCancel=false, inputDrained=true, inputIntegrityError=false, inputCoverageIncomplete=false`；**inputTailDiscarded=true**。视频首末 PTS 1.421033–29.387700，排序后最大步长 0.033334 秒；音频 1.400000–31.394667，最大步长 0.021334 秒。视频约 28 秒、音频约 30 秒，内部未见原基线的大间断，但停止末尾音频比视频长约两秒；未记全程 A/V 同步或最后已发布分片全部排空 PASS。

两场景各独立刷新 66 次，首视频体完成前已刷新；观察峰值 20 条目、7 下载，最终关闭后条目和字节均零。注意旧字段 `refreshBeforeFirstVideoComplete` 是外层 relay 按 native 请求刷新的统计，仍为 false；新 `prefetch.refreshBeforeFirstVideoComplete=true` 才是独立轮询证据，二者没有冲突。

实际源站日志的完整 video 为 0–14，最短完整请求分别 12024 / 12004 ms；外层 relay 向 native 完成交付的是 0–13。因此不把源站已发送等同于录制已收到，也不把外层已缓存资源的数毫秒读取当成原慢源交付已加速。停止附近序号 14 的完成与两层停止截止相撞，后续本地 410/503 和 FFmpeg demux I/O 日志仍存在，尾部协调继续修复。

资源守卫记录（文件名均位于 `local-artifacts/build-records/`）：

| 文件前缀 / 阶段 | 秒 | 峰值 CPU % | 峰值工作集 B | 结束活跃重型进程 |
| --- | ---: | ---: | ---: | ---: |
| 20260909T115924480Z / first | 21.798 | 8.63 | 11333677056 | 0 |
| 20260909T120803537Z / analyzer-fixed | 72.044 | 9.19 | 12241448960 | 0 |
| 20260909T120916981Z / redirect-cancel-fixed | 41.969 | 8.52 | 11416535040 | 0 |
| 20260909T121319626Z / native-first（未运行原生） | 86.556 | 9.80 | 11668025344 | 0 |
| 20260909T121709143Z / scheduled-native | 200.436 | 9.84 | 12961755136 | 0 |
| 20260909T121912461Z / production-decode | 87.079 | 9.50 | 12260732928 | 0 |

额外用固定 FFmpeg CLI 对两份 TS 的视频、音频执行 `-v error -xerror -map 0:v:0 -map 0:a:0 -f null`，**2/2 全量解码退出 0**，错误日志为空。两份 TS 均 3,329,668 B，SHA-256 同为 `ED27EFDAB0D4DD3944F6AACC10E88B4725B7B8BEFFA0F08AA5CCFE1F1772AFA3`；解码通过仍不抹去尾部覆盖差异。FFmpeg CLI SHA-256 为 `7D4B7BE4498D2677DAF2888CB15A62ED14DD8779FEE2410EDE9B6885A58D578B`。

复用的 FFmpegKit DLL SHA-256 为 `888A15993862950FEED714990E459F653B68BBC2CE30DA7D4BDA8DB9A5212C06`，ffprobe 为 `02A6801CE4AA4B84706771C511C6802AFF5EFD2FE15EE305F9303E74413ECEF6`，脚本在原生实验前逐项核对本地文件及夹具；本轮 build hook 提示未找到远端 ZIP hash，所以不声称完成了远端包哈希校验。

## 下一步与仍未解决的范围

生产接入必须先解决混合支持/未支持音视频清单的原子启用、缓存失败状态与原始 HTTP/续签策略的映射、来源代次及覆盖告警接线、与原 relay 临时体共享总预算、真实 LL-HLS 标签合同和停止前最后一批已发布资源排空。此次实验即使通过也不等于真实 TTing 修复、所有 A/V 组合通过或全功能验收完成。保留现有完整体保护，不以提前写出 200 绕过部分 CMAF 损坏防护。
