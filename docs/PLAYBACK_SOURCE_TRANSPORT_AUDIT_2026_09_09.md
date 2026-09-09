# 主播放器 HLS 输入与连接所有权审计（2026-09-09）

实现提交 `06c1acf67a135101b5579d50c82ac53e6f78bfbe`。

基线 `9fe0128ce43c382ad3089478a6e6b12d06612157`。延续 [源策略元数据](PLAYER_SOURCE_QUERY_METADATA_AUDIT_2026_09_09.md)，本批接入实际播放器输入边界，未注册 TTing、未构建/安装候选，也未进行手机操作。代码、确定性 HTTP、原生解码和实机验收分别记账。

## 源链与资源所有权

- PlayerManager 为每个 UnifiedPlayer 持有独立 PlaybackSourceTransport。普通打开、引擎候选、Windows 同引擎暖切候选均按各自 selection 的精确远端 URL 查询策略，不使用旧源的 token 或数组下标推断新源。
- 仅显式策略创建已有 FFmpegHlsInputRelay，播放使用非排空模式。native 收到私有 loopback URL、单元素本地列表和空 HTTP headers；上游 headers 留在 relay，manager 的 URL 列表、恢复请求及提交快照仍为远端源身份。普通 URL 即使带 token，也继续走原直接输入。
- 创建前核对策略绑定，HTTP 字段编码前拒绝非法名字和 CRLF/NUL 值。relay 增加可选 findProxy 注入，默认录制回调不变；监听端口绑定失败时关闭已分配的 client/连接所有者。
- 成功 native 打开后才关闭前一输入；失败替换关闭自己的输入；超时撤销 pending 输入。lease 的关闭幂等，owner 跟踪正在清理的 lease，最终关闭会等待已经开始的清理，而不是只看 pending 集合是否为空。
- close/dispose 在用户意图派发时撤销 pending 输入代次，不等待 native 生命周期队列才撤销。迟到的 factory 结果自行关闭，不再调用 native open；迟到的 native Future 也不会重新取得输入所有权。尚未返回的 factory 不阻塞关闭 Future，其后返回的 lease 仍由原 open Future 收尾。
- 普通暂停及原位音频切换保留当前输入；softStop、暖切退役及 hardDispose 释放它。关闭输入失败时仍执行 native hardDispose，不以提前抛错跳过下一层资源释放。

## 媒体代理和原生源身份

PlaybackProxyPolicy 读取媒体开关 enableProxy/proxyHost/proxyPort，与录制 relay 使用的 enableAppProxy/appProxyHost/appProxyPort 分离。源打开时读取媒体路由，传入该源的 relay；没有修改用户设置。MediaKit/Fijk 在每次打开时消费 PrivateInputAwarePlayer 元数据：本地输入清空 native proxy，下次远端打开重新读取媒体配置。共享 applyNativeLiveProperties 仍设置媒体代理，保留多画面原有初始化行为；这不等于多画面已接入本次 relay。

MediaKit 的 SourceEventFence 继续核对真实 native loopback URL；软件解码回退改用远端 sourceIdentity。否则，同一远端源换一个 relay 端口就会被误判为新源，准备好的软件回退标志不再匹配。元数据只用于下一次打开，之后清空；未经过 manager 的直接打开仍使用自身 URL，hardDispose 清除残留身份。

## 暖切取消的既有缺陷

新 Windows 测试复现：请求同房间暖切后暂停，candidate 被放弃、旧播放器仍持有原输入，但 currentSourceCommit 已变成 null。第一处错误是 public play 在任何请求派发时都清空旧提交，而不是等实际替换。

`git blame` 指向维护提交 `a451e25293abc535159ab119c672afc62159005c`。冻结上游 `c6c9bd70aedc503c003110dae10a83ad0bb891d8` 对应 manager 文件没有 `_currentSourceCommit` / `PlaybackSourceCommitSnapshot` 符号；本项归为维护分支源事务能力的 `fork-regression`，没有归咎普通 HLS 或进行上游合并。

修订：换房立即清空；同房间暖切保留旧提交，直到新源真正提交；转入破坏性打开时再清空。成功暖切关闭旧 lease 并提交新远端身份；暂停取消关闭 candidate lease，旧输入与旧提交保持一致。该 manager 层红测已转绿，路由层对取消结果的消费仍列为下阶段的集成核对，未据此宣称整个界面取消流程验收完成。

## 验证与失败记录

新增 22 项：transport 13 项、真实 manager 8 项、真实 headless MediaKitAdapter 1 项。覆盖直接输入、替换成功/失败、关闭后的迟到 factory、代次覆盖、关闭/超时后的迟到 native Future、清理等待、字段边界、代理分离、真实本机 HLS 子请求及端口关闭、关闭派发、暂停/音频、soft/hard stop、引擎超时回退、Windows 暖切/取消和 decoder identity。

| 记录 | 实际结果 | 资源（含排队） |
|---|---|---|
| `20260909T013218451Z-playback-source-transport-green.json` | 3 项通过、9 文件加载失败；新 proxy helper 缺少 `.v` 扩展导入，改用 Rx 的公开 `.value`。分析未运行，不是产品红测 | 884.370 秒；CPU 56.86%；WS 13,805,375,488 B；结束活跃重型进程 0 |
| `20260909T013936409Z-playback-source-transport-green.json` | 15 项通过，暖切暂停旧提交为空的产品断言失败；fail-fast 中断另一 HTTP 场景并输出 Flutter 临时监听目录清理错误，未把中断场景记为通过 | 223.548 秒；CPU 40.54%；WS 12,466,647,040 B；结束活跃重型进程 1 |
| `20260909T015606819Z-playback-source-transport-green.json` | 十文件 **230/230**；严格分析因一项 prefer_initializing_formals 提示退出 1，整条 runner 不记通过 | 692.727 秒；CPU 59.95%；WS 12,857,901,056 B；结束活跃重型进程 2 |
| `20260909T020411937Z-playback-source-transport-analysis.json` | 十文件 `analyze --fatal-infos` **No issues found**、runner 退出 0；仅分析，testExit 为 null，明确复用上一记录的 230 项测试 | 400.730 秒；CPU 62.90%；WS 13,010,726,912 B；结束活跃重型进程 0 |

最后仅按提示把 constructor 的字段赋值转换为 initializing formal，不改变参数类型、默认值或执行语义；复用上述 230 项测试，对十份变更文件重新执行严格分析。提交前核对十个最终 SHA-256 均与 analysis-source.json 一致；reuse-check.json 证明九个测试输入文件未变，manager 反向替换这两处 formal 写法后也精确恢复测试时的 SHA-256，非仅凭“应该没变化”复用。原始日志、输入哈希、失败副本与脚本位于忽略目录 `local-artifacts/playback-source-transport-20260909/`。未因等待时长终止编译器、其他重型任务或 ADB。

实际启动的 HTTP server/client 都在本机：请求经真实 relay 读取重写清单和子资源，确认 scoped token、上游 Cookie、native 空 headers、录制代理回调未被调用，以及关闭后本地入口失效。manager 测试注入 lease/native 替身；headless adapter 只验证真实适配器逻辑，**没有启动 libmpv/Fijk 解码、没有录制成品、没有生产 TTing 媒体或实机 PASS**。

## 剩余、交付与回滚

1. 优先补实际 PlayerController → manager 的取消确认测试，核对暖切取消后 opener 的 void 完成与路由 fallback 提交是否一致，再检查刷新 resolver 的保留；当前只有 manager 级取消证据。
2. 多画面的统一解析、每格 relay 生命周期和媒体代理；再完成 TTing API/状态/身份、设置/双语/用户入口与平台注册。
3. Android/Windows native 的真实代理、TLS、画面声音、软解回退、后台/浮窗/多画面与录制验收，仍按候选及设备边界执行。

无 ADB/MT、Root/LSP 更新、重启、卸载/清数据、覆盖安装或发布。版本仍 3.1.8+4121；Android bee143e2 与 Windows f3de664a 候选未变、不包含本批；历史 42 个宏观未闭环项不减记。稳定 3.2.0 仍待完整目标验收。回滚本批须同时还原 manager、输入 helper、原生输入能力接口、两个 adapter、relay 可选参数及对应测试；没有数据库迁移。
