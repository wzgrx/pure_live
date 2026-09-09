# 小红书真实控制器原生录制验收（2026-09-10）

## 结论与范围

生产接线保持 `69f6db996b540430e0bb922fa846447e789a6c58`；新增探针提交 **`4f84013d8526de28138bc2e0cb1a62a910cad1ce`**，没有应用行为、版本或依赖变更。承接[应用接入审计](XIAOHONGSHU_APPLICATION_INTEGRATION_AUDIT_2026_09_10.md)，本轮 Windows 原生探针 **1/1 PASS，包含同一任务连续两轮启动、停止、自动合并及再次启动**；最终单文件严格分析通过。

本轮使用实际注册适配器、`StreamResolverService`、`RecorderController`、FFmpegManager/FFmpegKit 和 VideoProcessorService。没有假 Resolver、固定媒体 URL 或手工替代合并。测试构造器隔离 Hive/输出目录、调度与 100 ms 文件采样，网络显式 DIRECT，未修改系统代理或注入账号 Cookie；不是 GUI、Android 后台服务或完整用户配置验收。

真实公开房间 `570429070963278308`，两轮分别重新获取分享页，均 HTTP 200 且禁止自动跳转；原生录制开始于北京时间约 **03:59:08 / 03:59:15**。源状态具有时效性，不保证未来仍在播。达到至少八秒原生媒体进度且存在输出后主动停止；该触发边界用于短时生命周期验收，不是“录够八秒即完整”的判据。

## 两轮成品与资源结果

| 项目 | 第 1 轮 | 第 2 轮 |
| --- | ---: | ---: |
| MP4 文件名 | 20260910_035907_841.mp4 | 20260910_035915_254.mp4 |
| 成品字节 | 8,883,436 | 6,767,560 |
| 停止前采样字节 | 9,089,236 | 4,277,752 |
| 原生停止前进度（整秒） | 10 | 9 |
| 停止及自动合并 | 2,306 ms | 1,159 ms |
| 视频/音频包数 | 273 / 512 | 225 / 422 |
| 视频覆盖秒数 | 10.920000 | 9.000000 |
| 音频覆盖秒数 | 10.922666 | 9.002666 |
| A/V 实际共同覆盖秒数 | 10.858666 | 8.930666 |
| 音频相对视频起点差 | -64 ms | -72 ms |
| 音频相对视频终点差 | -61.334 ms | -69.334 ms |

两份文件均 **1920×1080 H.264 + AAC**；包时间戳和时长完整，没有已知轨内空档或 DTS 倒退。外部 FFmpeg 对完整 MP4 逐包严格解码，退出 0、stderr 空。探针预设的共同覆盖至少 7.5 秒及首尾差绝对值不超过 100 ms 均成立；这些测量不代表感知口型同步或源端分片全部保全。

- 两轮录制原生终态 code=0、manualStop/inputDrained=true；forcedCancel、inputTailDiscarded、inputCoverageIncomplete、inputIntegrityError 均 false。
- 任务 stopped、wasStoppedByUser=true、lastError 空、pendingAttempts 空；最终 fileSize 精确更新为成品字节，不沿用停止前临时采样值。
- 停止前输出目录受保护；结束后保护释放，运行/排队均 0，Manager 和 VideoProcessor 无该任务，relay 预取池条目 0，临时 TS 清理完成。两轮使用不同路径。
- 原生停止日志仍有 `error during demuxing: i/o error` 和 FFmpegKit 的线程收尾诊断，原始日志已保留，没有删除警告或以 code=0 代替成品检查；完整成品解码与源交付完整性是不同证据。

成品 SHA-256：

- 第 1 轮：`D01EEA19A44FDE919E6D042EEC2F5B3CC8B8430F0CB732DEC80B26AF90CA6BC2`
- 第 2 轮：`FA3B3B04C105CCCC19002321495AB1F7B1BDD5EF37608AAF25EC6E22EA4F7649`

## 首次失败与准入口径修正

第一版探针错误地把 `prefetchEnabled=true` 等同于“一条已准入 feed”，实际 `prefetchFeedCount=0`，在停止前断言失败；finally 仍停止并自动合并，失败报告保留。它是**探针预期错误**，未据此修改生产准入规则。

已有[公开媒体证据](XIAOHONGSHU_SHARE_API_AUDIT_2026_09_10.md)保存的清单包含 `EXT-X-ALLOW-CACHE:YES`。当前解析器将此标签列为 unhandled，保留窗口拒绝未支持的标签，`_preparePrefetch` 整批退出并保持原 relay 路径；启用选项不保证准入。这解释了既有清单的行为，但该轮探针未采集原始媒体清单，不把旧快照当作该轮逐请求的唯一原因。

最终探针记录真实 feed 数，不强行要求预取准入；两轮均为 **0**。这次是普通 relay 路径的控制器原生验收，**不是小红书预取保留合同通过**，也不借用 TTing 的两路音视频源保全证据。

第二阶段两轮原生与成品检查通过，随后严格分析发现测试清理中对同步 bool 使用 await。最后仅删除该 await，执行 opt-in 关闭的加载检查和严格分析，无问题；未为 lint 重录直播。普通单元环境的本地化 missing-key 日志仍保留，双语资源及 Widget 已由前批验证，本轮不重复宣称 GUI 验收。

## 执行输入、资源与证据

本地根：`local-artifacts/xiaohongshu-controller-native-20260910/`。原生通过目录 `output/xhs-controller-1788983947791247`，含 summary、两份 packets JSON、两份 MP4 与 media-hashes；首次失败目录 `output/xhs-controller-1788983593020797`。各阶段 source-hashes 记录探针和关键生产输入，提交前核对最终哈希。

原生 DLL 和外部检查工具均核对固定 SHA：FFmpegKit `888A15993862950FEED714990E459F653B68BBC2CE30DA7D4BDA8DB9A5212C06`；ffprobe `02A6801CE4AA4B84706771C511C6802AFF5EFD2FE15EE305F9303E74413ECEF6`；FFmpeg `7D4B7BE4498D2677DAF2888CB15A62ED14DD8779FEE2410EDE9B6885A58D578B`。

所有重型阶段串行经资源守卫运行；等待其他工作区活跃 Java 任务结束，没有终止其他任务、删除缓存或绕过排队。

| build-records 记录 | 结果 | 耗时（含排队） | 峰值 CPU / 工作集 | 结束活跃重型进程 |
| --- | --- | ---: | --- | ---: |
| 20260909T195318800Z-xiaohongshu-controller-native-first.json | feed 预期错误，原生 0/1 | 83.22 s | 14.21% / 10,771,894,272 B | 0 |
| 20260909T195950781Z-xiaohongshu-controller-native-admission-corrected.json | 原生 1/1，分析 1 info | 339.77 s | 8.95% / 12,492,394,496 B | 0 |
| 20260909T200121723Z-xiaohongshu-controller-native-lint.json | 加载 1 skip，严格分析 PASS | 80.85 s | 13.96% / 10,542,166,016 B | 0 |

## 剩余工作

接下来补累计候选的可见播放/录制卡片与交互、Android 实机、断网/重连、长时和源完整性。小红书目录、关键词搜索、弹幕、主播跨开播跟随等未接入能力仍按前批范围保留。

宏观仍 **20 PASS / 32 RUN / 10 NR，42 组未闭环**；19 个直播站点 + IPTV，另 8 组参考平台未注册。Android fb106ed6 与 Windows 2fb471d3 候选均早于小红书接入，本轮没有构建或安装；手机仅作既有只读身份/前台核对，其他应用前台保持，无 MT/Root/LSP 修改。版本 3.1.8+4121、3.2.0 全面验收后再发布的门禁保持。
