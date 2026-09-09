# HLS 响应预算与完整发布等待协调（2026-09-09）

承接[空闲超时审计](HLS_BODY_IDLE_AUDIT_2026_09_09.md)及[滚动交付控制](HLS_ROLLING_DELIVERY_AUDIT_2026_09_09.md)。本批解决连续涓流/重定向累计等待，以及 native 在完整分片发布前先行超时；**真实 TTing 仍存在内容缺口，未通过稳定录制验收**。

## 实现、来源与边界

- `41b3bf8b024bf33871913b88866e34efba284771`：一次逻辑请求共享 `_HlsResponseBudget`，跨重定向响应头、响应体与最终清单/媒体读取累计计时。
- `d9e1b613ab2999da98516294ae3b657fcfdeabce`：协调录制输入的 loopback 等待，补自然 TLS 连接期限与真实 native 参数验证。
- `57c4221259e692b0f7875855b051422d3a03a2a5`：TTing 探针在失败退出时也保存停止后的脱敏原生证据，未放宽采集门禁。

首个错误状态有两层：仅逐次空闲计时会被持续小块/多次重定向不断延长；另一方面，完整暂存期间 loopback 尚无 body，native 使用与上游相同的 10 秒预算，会先于持续 12 秒的完整分片交付退出。二者都是维护 relay 的 **fork-regression**。冻结上游 `c6c9bd70aedc503c003110dae10a83ad0bb891d8` 与 merge base `527fea1b40885e3621d53c9646b523dd8522290c` 没有此 relay；完整媒体暂存来自 `6415d42e71aa76d5ab3304f737bebf593cb6a792`。本批局部修订，无上游合并。

录制路径保留用户输入空闲预算，完整响应读取总预算为其 **4 倍**；每个等待使用剩余总量与空闲量的较小值。请求头超时会 abort 尚未完成的 request，body 由 StreamIterator 的 finally 取消。重定向、HEAD 和错误响应的丢弃读取也受同一预算约束。停止仍按已有请求级收尾处理，不关闭其他请求的共享 client。

录制 native 输入等待改为 **4 × 上游空闲秒数 + 15 秒连接预算 + 5 秒调度余量**。10 秒输入对应 60,000,000 微秒，缺省 15 秒对应 80,000,000 微秒。只重写第一个 `-i` 之前的同名参数，缺失时补入；输出侧参数、原始参数列表和非录制路径保持。用户设置、质量、PTS/PDT、2 MiB 内存阈值、128 MiB 单响应上限、8 暂存名额以及完整媒体后发布保护保持。

4 倍是应用策略，不是协议规定。创建连接仍由 HttpClient 的 15 秒 connectionTimeout 承担；代码在 openUrl 前后检查总预算，而非遗弃未结束的连接 Future。磁盘工作也等待实际结束。因此这不是所有 IO 都在同一绝对时刻强行结束的承诺。[Dart 连接期限说明](https://api.dart.dev/dart-io/HttpClient/connectionTimeout.html)与[request.abort 生命周期](https://api.dart.dev/dart-io/HttpClientRequest/abort.html)支持区分连接、响应头和 body 取消所有权。[FFmpeg 协议文档](https://ffmpeg.org/ffmpeg-protocols.html#Protocols)规定 rw_timeout 单位为微秒；本批另从实际 C 层 session 命令提取并断言数值，不存完整带源地址的命令。

## 红绿与相邻验证

1. 第一轮红测为 4 通过/2 失败；重定向夹具错误地把含 query 的路径当媒体，形成误通过。保存 first-red 原件后修订 URI path 判断，得到 **3 通过/3 有效失败**：持续涓流越过观察上限、慢响应头返回 200、累计重定向返回 200。
2. 响应预算实现后 **47/47 定向、2/2 原生控制、两文件 fatal-infos 分析通过**。这一阶段还保留旧 native 等待，勿将后续改善归给此提交单独完成。
3. TLS 预检首轮确实触发 15 秒连接期限，但测试未注册 LogController，日志异常遮蔽了预期 502；下一轮 QuietLog 继承形式引发 onInit 返回类型编译错误。两次均为夹具问题，原始日志保留，没有修改生产日志行为。最终正确 GetxController/implements 夹具下 **2/2 通过**：主动停止 410/尾片标志与自然连接期限 502/无尾片标志分别验证，真实 TCP 断开且另一 relay 仍健康。
4. 最终 **51/51 定向（7 文件）、2/2（统计回归与四场景原生控制）、四文件严格分析通过**。包含同请求跨重定向总预算、停止、真实取消、暂存清理、重复输入参数、缺省参数及输出参数隔离。

## 原生控制结果

原件：`local-artifacts/hls-loopback-budget-20260909/controls/rolling-1788946441039147/`。固定媒体哈希与原控制一致；正常暴露 12 秒，慢场景 34 秒。

| 场景 | 实际 native 等待 μs | started ms | 输出 B | 完整接收视频 sequence | 停止 ms |
|---|---:|---:|---:|---|---:|
| healthy-10 | 60000000 | 919 | 1884324 | 0–7 | 698 |
| continuous-body-10 | 60000000 | 12700 | 451952 | 0、6 | 2611 |
| continuous-body-15 | 80000000 | 12703 | 451952 | 0、6 | 2557 |
| delayed-headers-15 | 80000000 | 12634 | 451952 | 0、6 | 2557 |

四场景均 forcedCancel=false、inputDrained=true、inputIntegrityError=false。健康场景无缺片警告，三个慢场景各一次。10 秒慢 body 从历史零输出转为启动，且不再于首个完整 body 前刷新；这是受控修复证据。健康 video480/audio750 包；慢场景均 video120/audio188，仍仅约 4 秒内容，证明预算协调没有修复持续交付不足。此前零输出场景约 7 秒强制取消的历史记录保持，本轮全部启动后的正常停止不等于全部零输出竞态已消除。

## 真实 TTing 复验与原件检查

生产注册适配器、StreamResolver、请求头工厂和 relay 经本地 Clash 7897 请求公开频道 1013062、720 档。应用输入 `d9e1b613`，最终探针 `57c42212`；实跑源码哈希已留存。**采集 0/1，后续合并测试跳过**：100.376 秒仍未在采集中达到 30 媒体秒且两段文件的门禁。

- 首个非零文件采样为 88.337 秒；停止前 1 段、1,110,704 B、计数 22 秒。
- 诊断时钟含约 9 秒前置请求：startAck=8988 ms、缺片事件=17907 ms、started=68615 ms。started 与首次文件数据是不同观察点。
- native 实际读预算 60,000,000 μs；停止约 3008 ms，code=0、manualStop=true、缺片=true、尾片舍弃=true、inputIntegrityError=false、inputDrained=true、forcedCancel=false。
- 165 条请求、零省略；上游 200 共 15、206 共 20，其余 130 未取得上游状态；36 completed、129 stopped。停止后的本地初始化请求 410 不是 CDN 403。
- 停止后留下两段 TS，共 **5,224,144 B**。原始文件保留，未拼接或改写。

原件目录：`local-artifacts/tting-budget-recheck-20260909/native/TTing 录制 1788946765722698/`。独立 FFprobe 与 FFmpeg `-xerror` 全量解码均退出 0，但逐轨 PTS 仍显示实质缺口：

| 原件尾号 | 字节 | 视频包 / 累计包时长 | 视频最大空档 | 音频包 / 累计包时长 | 音频最大空档 |
|---|---:|---|---:|---|---:|
| 000000.ts | 3990300 | 180 / 约 6 秒 | 4.288 秒 | 465 / 约 9.920 秒 | 5.952001 秒 |
| 000001.ts | 1233844 | 60 / 约 2 秒 | 0 | 0 / 0 秒 | 无音频包 |

第一段视频首 PTS 13.976，音频首 PTS 1.4；第二段视频首 PTS 1.4。检查按呈现时间排序，以包结束点计算大于 5 ms 的间隔，不是原始解复用顺序分析，也不证明音画载荷同步。native 停止后的 32 秒进度计数、code=0 与解码成功都不是连续内容证据。实网与早前网络条件不同，首数据 88 秒也没有证明较历史 75 秒采集更快；因果改善仅在上述固定控制成立。

SHA-256：

- 000000.ts：`397073D6EA8F866E76EC7A176C34DB855D5789DE65FE4133F941D2E6CFC25BAE`
- 000001.ts：`6EE84E5370D2FD7B90717B99DE981896CC38DA513C80216B0DBB1751CE68D8B3`

## 资源与证据复现

记录均位于 `local-artifacts/build-records/`，下表文件名前缀日期为 20260909。

| 记录后缀 | 结果 | 时长 s | 峰值 CPU % | 峰值 WS B |
|---|---|---:|---:|---:|
| T091709971Z-hls-response-budget-red.json | 首轮夹具红测 | 77.444 | 11.48 | 7852998656 |
| T091846474Z-hls-response-budget-red.json | 三项有效红测 | 54.980 | 8.63 | 7715377152 |
| T092437924Z-hls-response-budget-final.json | 47 + 2 通过 | 296.001 | 32.89 | 8526643200 |
| T092812575Z-hls-tls-deadline-preflight.json | 夹具编译失败 | 49.021 | 8.52 | 9049022464 |
| T092926723Z-hls-tls-deadline-preflight.json | TLS 2 通过 | 61.071 | 9.74 | 8252010496 |
| T093607937Z-hls-loopback-budget-final.json | 51 + 2 通过 | 335.196 | 65.51 | 8783822848 |
| T094120598Z-tting-bounded-budget-recheck.json | 真实采集 0/1 | 224.092 | 17.61 | 8226037760 |
| T094448955Z-tting-budget-raw-inspection.json | 两原件解码通过、保留缺口 | 67.738 | 0.00* | 7163691008 |

全部结束活跃重型数为 0。时长含资源等待。*离线检查仅 1 次资源样本，CPU=0 是采样记录，不表示 FFmpeg 没有消耗 CPU。最早缺 LogController 的 TLS 预检使用互斥但未生成资源监控记录，只有直接日志，不补造峰值。所有工作沿原句柄等待，没有终止其他任务；排队/运行中未编辑源码或测试。

三个证据根目录 `hls-response-budget-20260909`、`hls-loopback-budget-20260909`、`tting-budget-recheck-20260909` 已各生成 artifact-index.json，包含脚本、直接 Tee 日志、源码哈希、统计和媒体原件（排除索引自身及 Hive/lock）。FFmpegKit DLL 本地 SHA `888A15993862950FEED714990E459F653B68BBC2CE30DA7D4BDA8DB9A5212C06`；FFmpeg `7D4B7BE4498D2677DAF2888CB15A62ED14DD8779FEE2410EDE9B6885A58D578B`；FFprobe `02A6801CE4AA4B84706771C511C6802AFF5EFD2FE15EE305F9303E74413ECEF6`。下载 hook 的远程 SHA 可用性曾变化，本地固定运行库哈希验证与其分开记录。

## 剩余与回滚

下一步用固定控制区分总带宽不足与逐请求等待/预取串行化，评估有界并发和音视频清单窗口协调，而非继续盲增超时或压平时间戳。现有错误响应 body 在预算内丢弃后才返回状态，仍可能延后错误显现；停止后的初始化 map 重试也需单独评估。以上是待验证方向，尚未实施预取或初始化缓存。

本批没有手机/MT 操作、安装、模块更新、重启、候选重建或发布。当前 18 直播站点 + IPTV，9 组未注册；62 宏观项中 20 PASS、32 RUN、10 NR，即 **42 项未闭环**，不是 42 个已知 Bug。版本 3.1.8+4121；Android 候选 bee143e2、Windows f3de664a 均不包含本批。回滚按实现依赖逆序对 d9e1b613、41b3bf8b 作反向补丁会重新暴露本批已复现问题，应保留失败探针与证据。
