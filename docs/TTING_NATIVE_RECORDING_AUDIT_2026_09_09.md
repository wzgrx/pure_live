# TTing/FLEX Windows 原生短录审计（2026-09-09）

后续[逐包时间线与 CMAF 对照](TTING_CMAF_TIMELINE_AUDIT_2026_09_09.md)确认晚起点/内部空档在原始 TS 中已存在；本地对照通过但实际采集根因仍待结构化时序取证。下文保留本批失败与离线解码的原始结论。

探针实现 `50b06c8eec4a0fced17cfffd82931c55b31acb4c`，应用基线 `b1cca6b3b50d5c843ce5226ed5dc9912b05c43e5`。继 [生产列表链路](TTING_PRODUCTION_RELAY_AUDIT_2026_09_09.md)，本批增加 opt-in 原生录制探针 `tool/probes/tting_recording_probe_test.dart`。测试使用注册 TtingSite、真实 Dio、StreamResolverService、生产 FFmpegManager/HLS relay 和 VideoProcessorService；不是 curl 下载后直接拼接，也不是 UI 自动化或已发布 Windows 包验收。

## 请求与录制输入

- 从当前公开首页目录选房间，详情确认状态及频道/主播/广播身份，以 API 720 档的实际标签调用录制解析；校验 cursor、有效期和 sourceQueryPolicy，再把策略传入 FFmpegManager。
- API 使用本次独立 Dio 经 Clash 7897；生产录制 relay 的上游代理回调也固定到同一 Clash，native 访问应用私有 loopback。设置只存在于隔离测试进程/临时 Hive，finally 恢复客户端并清理回调，不修改用户应用或系统代理。
- 使用当前 Windows FFmpegKit native DLL，随后生产分段计量、显式停止、MP4 合并提交与独立 ffprobe/FFmpeg 全文件解码。输入/输出都在 caller 的忽略目录，输出文件名前缀隔离，未覆盖既有录制。
- 目标是至少 30 秒 native 媒体进度和两段 TS，最长观察 100 秒后显式收尾并判定目标是否达到；不是盲目重复重启或把墙钟等待等同实际录制。独立解码使用 -xerror、完整文件和 demux 时基，退出 0 之外还检查 stderr 为空。

## 首轮失败与证据保留

首轮 **0/1**、单文件严格分析通过。native 生命周期约 62.6 秒，显式停止成功、code=0、无强制取消，实际仅一段 1,675,456 B TS。probe 将取流/探测启动时间计入固定 60 秒上限，随后两段要求失败，尚未执行 MP4 finalizer 或完整解码。初版探针、输入哈希及 TS 均保留，没有把中间 native code=0 写为端到端 PASS。

独立 ffprobe exit=0，文件 duration=20.165 秒，H.264 1280×720 + AAC；视频 start_time=11.405、音频=1.400，首段视频覆盖约 10.16 秒。720 API URL 的额外只读清单检查 HTTP 200、单 variant=1280×720，确认不是误选 Auto 的 1080 档。该 URL 来自前批保存的 API 响应，未宣称重新解析取得它。

首次 ffprobe 的 PowerShell 展示步骤在 StrictMode 下直接读取音轨不存在的 width 属性报错；ffprobe 原始 JSON 已成功写入，后续只修订摘要读取，没有重跑媒体检查。长启动与首段音视频起点差异的来源仍待定位，不据此立即修改生产时钟或统一拉长重试。

探针修订为实际媒体进度和分段驱动停止，持续落盘 elapsed/bytes/segments/recordedSeconds、firstBytesMs 和失败断言，保留录制目标而非降低到单段通过。


### 进度驱动复验仍失败：不是单纯的固定等待问题

第二次真实采集仍 **0/1**。首个非零文件采样在 **75,292 ms**；100 次采样到约 101.476 秒时，盘上仅 1 段、1,214,292 B，native recordedSeconds 停在 24 秒，未达到 30 秒/两段目标。显式停止后才形成两段合计 **2,533,300 B**，native 终止统计约 30.59 秒。native code=0、停止耗时 2.496 秒、inputDrained=true、forcedCancel=false 不代表实时采集目标已通过。

该复验改变下一步：保留长首字节等待、进度停滞与停止后集中输出三个现象，停止继续加长时限或重试现网。根因尚未定位到 API、Clash/CDN 传输、HLS relay 或 native 缓冲层，生产逻辑暂未修改。需要按资源请求/首字节/完整 body、relay 交付和 native 进度建立同一时间轴，并用受控独立音视频 HLS 输入复现。两次停止日志中的 410 出现在结束输入阶段，不直接当作运行中 CDN 拒绝访问的证据。

第二次留下的原始 TS 只读保留，另做隔离副本的生产 finalizer/完整解码测试。这个离线测试即使通过，也不回填在线采集 PASS；报告显式保存 captureGatePassed=false。
## 最终结果

| 记录 | 结果 | 总耗时 / 峰值 CPU / WS / 结束活跃重型进程 |
|---|---|---|
| `20260909T065556815Z-tting-native-recording.json` | 初版在线 **0/1**，strict analyze exit=0 | 285.550 秒 / 17.05% / 7,785,648,128 B / 0 |
| `20260909T065653875Z-tting-native-first-inspection.json` | ffprobe exit=0；随后 PowerShell 摘要字段展示失败，原 JSON 保留 | 10.133 秒 / 0.28% / 6,523,854,848 B / 0 |
| `20260909T070542151Z-tting-native-recording.json` | 进度驱动在线复验 **0/1**，strict analyze exit=0 | 386.040 秒 / 72.98% / 9,021,751,296 B / 2 |
| `20260909T071156754Z-tting-retained-finalization.json` | 离线保留片段 **1/1**，在线用例明确 skip；最终 strict analyze exit=0 | 208.759 秒（含排队） / 36.74% / 9,960,787,968 B / 0 |

离线测试 07:11:52 UTC：两份隔离 TS 副本经生产 finalizer 生成 **2,383,866 B、25.946622 秒 MP4**；复制的 TS 清理、原始两份 TS 保留、finalizer 释放。独立全文件解码 exit=0 且 stderr 为空，视频 H.264 1280×720、音频 AAC。测试结果明确 `networkUsed=false,captureGatePassed=false`，不把离线成功替代在线失败。

**成品仍有时间覆盖缺口**：视频 start=10.181000 秒、duration=15.765622 秒；音频 start=0、duration=19.157583 秒。即成品开头约 10.18 秒没有视频轨样本，末尾约 6.79 秒没有音频轨样本。解码器接受文件不等于同步体验合格，本批没有通过完整录制验收。前批单 TS 已有视频晚起点迹象；仍需对本次两段 TS 的逐包时间线与合并后的 offset 进行对照，区分采集输入问题和拼接影响。

最终源码只新增离线用例/诊断，未再次请求实时网络；提交前核对 retained-source.json 哈希一致。所有重型任务按原 handle 等到终止，没有结束或重启其他 Java/ADB 会话。下一步优先本地保留媒体与受控 HLS 复现，不做第三次无诊断现网重录。

## 运行时与证据归档

- `build/native_assets/windows/libffmpegkit.dll`，54,565,256 B，SHA-256 `888A15993862950FEED714990E459F653B68BBC2CE30DA7D4BDA8DB9A5212C06`；FFmpegKit 0.11.1 / 20260831 x86_64 LGPL。
- 独立 FFmpeg/ffprobe 位于 `D:\Soft\ffmpeg\bin\`；两者大小和哈希见 `local-artifacts/tting-native-20260909/runtime-inputs.json`，没有更换二进制。
- 同目录保留每次 guard 记录索引、源码哈希、原生录制文件、捕获样本、检查/解码输出及脱敏日志。原始源 URL/token 不进入 Git。探针未加载应用完整翻译环境，日志的 tting_auto / video_ts_total / video_delete_temp_files missing-key 是本次测试环境边界，不是发布资源缺键结论。

## 尚未覆盖

本批不是长时录制、断网重连、签名到期续录、全画质/双端实际播放、音视频同步主观验收或 Android UI 通过。源码支持 ncp 与 ncp_llh；当前保存片段只证明本次 HLS 输入的 720 档，其他组合继续单列。Bigo/浪 Live 的额外访问结果见[独立审计](BIGO_LANGLIVE_ACCESS_AUDIT_2026_09_09.md)。

版本仍 3.1.8+4121，Android bee143e2 / Windows f3de664a 候选没有因本批探针而重建；18 个直播站点 + IPTV、9 组未注册和历史 42 个宏观大项未闭环口径保持。没有操作手机、安装 APK、Root/LSP 修改、清数据、重启、上游同步或正式发布。全目标继续。
