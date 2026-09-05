# 虎牙持续缓冲期限与抗抖边界再审计

## 冻结基线及范围

- 本地：`3d2755f4aea8b3560711711b506537bcb189c822`。
- 再次远程只读核对 upstream/master：`c6c9bd70aedc503c003110dae10a83ad0bb891d8`；本轮未合并上游、未连接手机。
- 重新追踪 HuyaSite、HuyaTransportPolicy、MediaKitAdapter、FijkAdapter/FijkHelper、LiveBufferPolicy、PlayerManager 的缓冲/播放/暂停/恢复/退出边界，并阅读对应测试及既有原生采样。结构扫描与人工语义审查分别记账，不宣称逐字审查全部 4,050 个文件。
- 前序 WUP、健康原生 FLV 不定时重开、FLV/HLS 凭据隔离保持；画面几何、弹幕布局、编码器、CDN 排序、生产缓冲默认值均保持。

## 先区分三类故障

1. **凭据/连接寿命**：上游 WUP 改动及本地前序修复解决的层。正确原生凭据的连接在多次 330 秒采样中未 EOF；这不保证每秒都有可播放媒体。
2. **媒体到达间歇**：同会话 FLV 观测已找到 TX 2,326 ms 与 AL 1,443 ms 输入 read 等待，对应 native 缓冲耗尽；相应样本无 DTS 大跳变，本地写入只等待 2–3 ms。它不是已经证明的全站服务器故障，也不是此次计时修复会消除的网络间断。详见 `HUYA_FLV_CORRELATION_2026_09_06.md`。
3. **持续故障恢复被延后**：此次新增的可复现 fork-regression。播放状态通知不等于媒体恢复，但旧计时器把它们当成了新的缓冲起点。

## 新缺陷的根因及修复

`PlayerManager._scheduleBufferingStallRecovery` 的调用入口包含 onLoading、onPlaying 和 onStateChanged。`onLoading.distinct()` 只去重 loading 事件，挡不住 playing 真/假切换或重复 paused 状态。

旧实现每次调用都会 cancel 旧 Timer，再增加 continuity revision、重新计时。连续缓冲中若状态事件间隔始终小于 12 秒，恢复期限会不断后移。`git blame` 指向 `a718199de`；冻结上游没有本地这套 bufferingStall 计时实现，归类为 **fork-regression**，不归咎上游。

修复只增加已有 Timer 的所有权检查：同一次尚未结束的缓冲保留最初期限，状态通知不续期。缓冲结束、用户暂停、会话更换和退出仍经既有取消路径释放所有权，新的缓冲重新计满期限。默认 12 秒保持，未增加轮询、提前换源或延迟重试。

## 定向验证

- 新增两个状态脚本：持续缓冲中每 400 ms 通知 paused，或交替通知 playing=false/true。2 秒测试期限前不替换，期限后必须进入现有有界恢复。
- 新增三个相邻场景：短缓冲自行结束不重开；用户暂停不自动恢复；下一次缓冲独立计时，不继承上一段剩余时间。
- 最终红基线 `local-artifacts/huya-deadline-red-time.log`：3 通过、2 失败；两个失败都是旧逻辑维持 creations=1 而期望 2。运行期间保持生产计时实现为原始版本。
- 早期 Widget 假时钟尝试因真实/虚拟异步 zone 不一致而无效，已移除，不计作产品复现证据。最终脚本与现有恢复测试一致使用真实异步计时，不依赖手机或网络；记录给出具体间隔，避免冒充虚拟时间证明。
- 最终全目录测试 **1106/1106**：`20260905T195206590Z-quality-focused.json`，131.207 秒（Flutter 测试报告 101 秒）。结束活跃重型进程 0；验证工具峰值工作集 14,541,176,832 B、CPU 9.22%，不是客户端资源占用。命令 `tool/local_ci.ps1 -Scope Focused -TestPath test -SkipPubGet`，不包含 Full 外部接口阶段。
- 本轮唯一 analyze：`local-artifacts/huya-deadline-green.log`，53.6 秒、无诊断。该次组合运行因早期无效 Widget 夹具失败，不能把整条记录标为通过；最终生产修复与该次 analyze 的实现一致，后续变更为测试夹具与诊断工具。

## 相同故障输入对照

`tool/probes/live_jitter_fixture_probe.py` 使用 FFmpeg 生成的色彩图和正弦音，不录取主播媒体。原始 FLV 字节与 DTS 不变，loopback 按 DTS 实时喂给同一 libmpv 版本。在媒体 12 秒位置停止输送，然后集中补发积压包：

| 对照 | 输入中断 | 播放策略 |
| --- | --- | --- |
| baseline-short | 2.4 秒 | 已保存真实探针的生产缓冲属性快照 |
| reserve3-short | 2.4 秒 | 相同属性，加 3 秒初始/恢复缓冲 |
| reserve3-long | 8 秒 | 同上，验证超出余量后的边界 |

每项 32 秒，串行；仅合成 loopback 测试允许短观测窗口，真实虎牙探针仍最低 130 秒。记录打开次数、注入是否完成、运行中缓存暂停、采样时钟、内存和 handler 退出。候选对照失败则非零退出，不改断言让结果变绿。

生成命令使用 `-filter_threads 1`、视频 `-threads 2`、256×144/30fps AVC/AAC、40 秒、`-flvflags no_duration_filesize`。工具要求显式媒体、DLL、基线结果与输出路径；媒体上限 8 MiB，无外站连接、Cookie 或签名材料。

对照门禁通过，合计 106.467 秒：

- baseline-short：运行中缓冲 12.985–14.795 秒，约 1.810 秒。
- reserve3-short：运行中缓冲 0 次；启动缓冲 1.587–3.819 秒，额外等待具有实际代价。
- reserve3-long：运行中缓冲 15.203–20.054 秒，约 4.851 秒；证明三秒余量没有消除超出预算的输入中断。
- 每项 EOF=0、只打开一次、注入完成、handler 释放。结果为 `local-artifacts/huya-synthetic-jitter-results.json`，资源/命令索引 `local-artifacts/build-records/huya-synthetic-jitter-comparison.json`。

这只是受控供给/软件解码实验，不代表 Huya CDN、Flutter 纹理、设备扬声器或硬解全部通过。前序真实六秒预缓冲仍发生卡顿的反例保留，不因短故障夹具成功而默认启用某个缓冲值。

### 三秒候选的真实 TX 观测

记录 `20260905T200110835Z-quality-focused.json`，原始结果 `local-artifacts/huya-correlated-tx-buffer3.log`：房间 660000、TX、请求码率 10000、网页令牌刻意为空、WUP FLV、同会话 relay，330.147 秒。

- EOF=0、原生 pause=0；buffering 只发生在启动 1.504–3.915 秒，运行中缓存暂停为 0。9 个 cachePauseSamples 全在同一启动区间，不是九次运行中卡顿。
- 一次连接、120,479,680 B、FLV 解析无错误、DTS 无大跳变；停止归因为 probe_stop，handler 退出。最大 read 等待 612 ms、最大 write 等待 3 ms。
- **本次没有出现之前 1.4–2.3 秒的实网收包间断**，所以此样本通过不能单独证明三秒候选比默认更好；相同故障输入的差异来自上面的独立合成对照。
- 呈现丢帧计数 2、解码丢帧 0；整机归一软件解码 CPU 均值 0.715%，停止后私有字节 57,339,904 B、销毁后 43,491,328 B。这是 headless 原生进程，不是客户端 GUI/硬解/真实音频或 Android 验收。
- Python FLV 观测回归再次 **7/7**，1.080 秒、无 ResourceWarning；新增/修改两个 Python 探针 AST 检查通过。真实样本与最终全目录测试收尾均记录活跃重型进程 0。

## 网络与 GitHub 核对

- [上游 c5944dd5](https://github.com/liuchuancong/pure_live/commit/c5944dd5a529cd93eb29486500abd5d496618f80)：冻结 Git 源码确认 `getCdnTokenInfoEx` 和 `sFlvToken`，不按提交标题推断。
- [biliup WUP 实现](https://github.com/biliup/biliup/blob/master/crates/biliup/src/downloader/live/huya_wup.rs)：交叉核对凭据契约，非“所有客户端永久流畅”的承诺。
- [mpv 缓冲选项](https://mpv.io/manual/stable/#options-cache-pause)：缓存上限与开始/恢复播放的缓冲门槛不同；暂停等待会增加延迟。关闭等待不产生缺失的帧。
- [mpegts.js 配置契约](https://github.com/xqq/mpegts.js/blob/master/d.ts/mpegts.d.ts)：其文档明确把 IO stash 的低延迟与网络抖动风险区分，另设追赶延迟选项。可借鉴“抗抖余量与追赶延迟分开”的设计，不把 Web MSE 的参数照抄到 libmpv，也不默认加速 ASMR 音频或换成 WebView 播放器。

## 下一层仍需核实的适配器边界

`MediaKitAdapter` 中 playing=true、解码帧/音频参数和当前状态快照均存在清除 loading 的路径。原生 playing 表示播放意图/状态，并不总能证明 demuxer 已退出 buffering；缓冲尾帧也不是新连接到达证据。需要补真实适配器事件序列夹具，区分首帧准备与原生缓冲，再验证这些路径是否抵消上层计时所有权。不要把本次只改 Manager 的期限 guard 宣称为已修复这一层，也不要在缺少事件顺序验证时再次扩大发布批次。

## 交付与后续验收

本次状态恢复修复与剩余输入抖动分开验收。只有实际对应原因的改善得到证据，才修改默认抗抖/线路策略。保留有限内存、单播放器正常连接、真实失败才恢复、手动暂停/关闭优先等不变量。

全平台 3.2.0 的无明显观看中断验收仍未完成；不把旧 APK 或旧 Windows 候选称为本次源码构建，不以删除提示掩盖卡顿。独立回滚此次计时 guard 与五个测试即可，不触及前序签名和播放链路修复。
