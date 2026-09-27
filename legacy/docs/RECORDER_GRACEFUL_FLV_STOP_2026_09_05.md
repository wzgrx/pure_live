# FLV 录制停止与原生输出排空（2026-09-05）

## 基线与问题归属

本批基线 `f66cff51a1522d160a6ec7fa683b5f0ef308e1e8`。承接
[虎牙录制租约审计](HUYA_RECORDER_LEASE_AUDIT_2026_09_05.md)，不合并上游、不连接手机。
上一批仅修复多余断流和损坏封装误报成功，没有把取消截断标成已解决。

已锁定 native `ffmpeg-kit-extended 0.11.1` 输出也使用 session cancellation 回调。
本项目直接用 cancel 停止录制，取消同时阻止输出尾部落盘；本项目原先只按返回码判断成功，
放大了第三方原生中断合同的影响。归类为原生依赖与本地停止策略的 `integration-conflict`。

## 先用固定输入隔离服务器

`tool/probes/recorder_flv_stop_probe_test.dart` 使用自行生成的 H.264/AAC FLV、
按原始时间戳发送的本机 HTTP 源、实际生产 FFmpegService 和分段命令。
不需要远程直播、Cookie、账号或 Android。每次只有一个 native 录制，再独立全文件解码。

旧生产停止代码的原生红测 `20260905T113521899Z-quality-focused.json`：

| 开始产出后的停止延迟 | 原始 TS 大小 | 188 字节 TS 包对齐 | 全文件解码 |
|---|---:|---|---|
| 150 ms | 0 B | 否 | 失败 |
| 700 ms | 0 B | 否 | 失败 |
| 1200 ms | 262,144 B | 否 | 失败 |

三次都报告 `error writing trailer: immediate exit requested`，服务器是同一台机器的
固定测试源，故这处损坏不归因于虎牙 CDN。现场摘要保留在
`local-artifacts/recording-probes/flv-stop-1788608089843663/summary.json`。

## 实现边界

### 输入停止和输出取消分开

- 只为 **liveRecording 的 HTTP(S) `.flv` 输入**创建独立回环输入通道。播放器、观看模式、
  纯音频播放中转、文件封装任务都不进入此通道。
- 输入正常结束时，让 FFmpeg 写完它已经收到的完整媒体包和分片尾部，再释放会话。
  正常停止不设置 native cancel 标志。
- 输入结束或原生排空最多等待 3 秒。仍没有完成才使用旧 native cancel 作为故障终止，
  并继续等待真实原生完成；超时不等于资源已经退出。
- 同一个 session 的重复停止共用一个 Future；租约结束后用户再点停止会更新用户意图，
  不并行发第二次 native 取消。终止事件记录 `inputDrained` 与 `forcedCancel`。

### 传输与帧边界

- 回环服务只绑定 127.0.0.1，使用随机独立路径、单次读者和单个上游连接；不开放任意 URL 转发。
- 原始请求头用于上游，移除 Host/Range/逐跳头；上游 HTTPS 仍使用 Dart 系统证书校验。
- 转发完整 FLV 头和原始完整 tag，不解码、不重编码、不修改时间戳、比例或音轨。
  手动停止时正在接收但尚未组成完整 tag 的数据尚未交给 native，不会裁剪已落盘的文件。
- 最大待收单个 tag 受 FLV 24 位 DataSize 限定，头扩展最多 64 KiB，转发等待写入进度，
  不持有整个直播或按直播时长累计缓冲。
- PreviousTagSize 的部分生产者存在旧值/零值，FFmpeg 有兼容处理；此层以 DataSize 划分边界，
  原样保留尾字段，不抢在 native 前拒绝这些可解码流。
- 私有回环 URL 不保留 native HTTP 自动重连参数，真实断流继续交给录制控制器取新 URL；
  防止 native 对一次性输入重复 GET。远程 403 等状态原样传给 native，不伪装成功。
- 关闭 Future 可重入并等待同一次资源释放，先关闭服务端活动连接再取消请求订阅。

HLS、RTMP、非 `.flv` 的不透明地址保持现有路径，仍需独立停止收尾验收，不由本批结果推断正常。
后续 HLS 的独立修复与验证见 [HLS 排空审计](RECORDER_HLS_DRAIN_AUDIT_2026_09_05.md)，
不回填为本批 FLV 结果；RTMP 与不透明输入仍保留各自验收要求。
这不是对全部 FFmpeg 原生中断 API 的修补；后续若依赖提供可靠的分离停止合同，应重新评估中转层。

## 分层验证与失败记录

- 字节拆包、跨块输入、缺半个 tag、旧 PreviousTagSize、累计缓冲、立即/重复停止、两个任务隔离、
  错误状态、随机路径、请求参数、输入/原生停止时限均有离线测试。
- 新中转的最初小包测试发现 HTTP 默认缓冲会让少量数据等待；已显式禁用 response bufferOutput，
  并用停在半个 tag 的本地输入验证即时结束，不通过增加测试等待时间解决。
- 首轮新停止方式的原始 TS 已全部对齐、完整解码退出 0 且 stderr 为空，但探针还把
  输入结束的 `Error during demuxing: I/O error` 和输出写尾错误合成了一个布尔值，整轮记为 FAIL。
  两份失败记录 `20260905T113757687Z-quality-focused.json`、
  `20260905T114114479Z-quality-focused.json` 保留，不重新标绿。
- 验收拆分为：保留所有 native 日志；单独断言没有输出写尾/写包失败；TS 包对齐；
  TS 音视频完整解码无错误；未强制取消；native 会话已结束。独立完整解码标准没有降低。
  原始旧代码的空文件/截断文件仍会在这套标准下失败。
- 最终固定输入门禁 `20260905T114654798Z-quality-focused.json`：15/15，
  包含 14 项离线回归及 1 项三时点实际 native 对照，均没有强制取消、输出写尾错误或完整解码错误。
  此时探针的 stopMs 还包含后续独立解码耗时，不把该字段作为纯停止等待测量。

### 真实虎牙生产录制控制器复验

`20260905T115346874Z-quality-focused.json`：1/1 opt-in 原生探针通过。
2026-09-05 19:47:22（UTC+8）开始，使用实际 HuyaSite、录制控制器、FFmpegKit 和 MP4 收尾链路；
不是仅抓 URL 或只看返回码。摘要为
`local-artifacts/recording-probes/huya-controller-1788608841989884/summary.json`。

| 检查项 | 实际结果 |
|---|---|
| 持续录制观察 | 325 秒，325 次采样均为 running |
| native 输入启动 / 定时轮转 | 1 / 0 |
| 凭据解析 | 2 次，跨过凭据刷新时点但不重启健康输入 |
| 原始 TS | 保留 2 片；独立全文件音视频解码退出 0、错误日志为空 |
| 最终 MP4 | 133,122,288 B；独立全文件音视频解码退出 0、错误日志为空 |
| 收尾 | stage=complete，nativeStopped=true |

上一批相同生产探针因末片截断导致源 TS 和 MP4 解码失败；新批直接修复输入/输出停止合同，
而不是去掉解码门禁或删除失败原片。实时媒体本身不同，文件大小差异不作为吞吐或性能提升依据。

此次质量门总耗时 409.469 秒（含初始化、325 秒观察、封装和两次完整解码），结束活跃重型进程 0。
工具进程合计峰值工作集 23,893,254,144 B、CPU 49.15%，包含测试编译与独立解码，
不作为运行中客户端内存/CPU 指标。原生合并进度日志仍有已知无效大时间戳，展示层此前已有过滤；
文件有效性以独立解码结果为准，不据此声称全部原生日志异常已消失。

本次实际 native 证据来自 Windows、单个虎牙房间的一条 FLV 线路。Android 原生、其他平台/协议、
完整 GUI 录制同时观看及长时间性能仍在总体验收中。没有以本轮通过覆盖历史 Android PiP 故障。

### 最终受影响模块回归

另补充上游已接受请求但尚未响应 HTTP 头时的停止测试，覆盖首包前关闭及重复资源释放。

- `20260905T120210846Z-quality-focused.json`：31 个相关测试文件 **234/234** 通过；
  本批唯一一次 analyze 用时 47.2 秒，No issues found。全仓自动结构扫描 4024 文件、0 错误、
  1 项既有 empty-catch 盘点提示；不是声称逐字语义审读所有文件。
  总耗时 98.524 秒，测试并发 12，峰值工具工作集 12,334,813,184 B、CPU 9.57%，
  结束活跃重型进程 0。未 clean、未改变锁定依赖。
- 随后仅修正 native 探针计时：在真实 native 完成后停止 Stopwatch，独立解码耗时单独排除。
  不修改生产业务代码，不重复 analyze。
- `20260905T120400927Z-quality-focused.json`：串行 2/2 原生探针通过，
  一项再次执行三时点手动停止和完整解码；另一项用隔离副本复验已保留的正常/截断 TS：
  正常输入提交 MP4 后删除副本，损坏输入报告失败、保留副本且不提交 MP4。
  记录耗时 37.781 秒，结束活跃重型进程 0；未再次请求真实 CDN。
- 最后固定输入三次正常停止耗时 19/4/3 ms（仅该样本，不外推所有媒体），
  `inputDrained=true`、`forcedCancel=false`、独立解码退出 0 且错误日志为空。
  摘要 `local-artifacts/recording-probes/flv-stop-1788609819812558/summary.json`；
  原始损坏证据未改动，完整性对照位于
  `local-artifacts/recording-probes/source-integrity-1788609829192404/summary.json`。

以上门禁的 source_commit 记录为修改前 HEAD `f66cff51`，实际运行包括本批未提交业务补丁。
随后源码提交保存相同受测业务代码；文档收尾不冒充重新构建或 Android 原生验证。

## 回滚与迁移

无依赖、原生二进制、持久化数据或设置迁移。若需要回滚，只撤销本批录制输入中转及
FFmpegService 停止入口；保留上一批健康 FLV 不定时取消、损坏封装保留源文件的独立保护。
回滚会重新暴露固定输入已经复现的取消写尾问题，应在发布说明中明确，不悄悄恢复旧路径。

## 来源

- [锁定 native 中断实现](https://github.com/akashskypatel/ffmpeg-kit-builders/blob/4dc903c2a29741b8f9b61dd94b10185bae69a493/FFmpegKit/src/ffmpeg.c)
- [FFmpeg HTTP 重连选项](https://ffmpeg.org/ffmpeg-protocols.html#http)
- [FFmpeg FLV 解复用兼容逻辑](https://github.com/FFmpeg/FFmpeg/blob/master/libavformat/flvdec.c)

源码、离线回归、Windows native 和 Android 实机属于不同证据层。所有原始媒体仅存 ignored
本地诊断目录；没有新正式 APK、3.2.0 tag 或 Release，不把本批作为完整客户端验收完成。
