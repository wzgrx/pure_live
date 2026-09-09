# TTing 采集时间线与 CMAF 清单窗口对照（2026-09-09）

实现 `df4dbefe830c6c38cd75581aa313a61f0d9d2303`，基线 `29bfb98b`。本批在[原生短录失败](TTING_NATIVE_RECORDING_AUDIT_2026_09_09.md)后，核对保存的两段 TS 与 MP4，新增本地受控原生探针；**没有修改生产时间戳或再次进行真实网络录制**。

## 逐包时间线：缺口先于合并

读取前按上一批 artifact-index.json 核对 SHA-256，ffprobe 三次均 exit=0。PTS 单位为秒，以下是包起点范围，不把范围长度当作有效连续播放时长。

| 输入 | 视频包数 / PTS 范围 | 音频包数 / PTS 范围 | 已观察内部空档（相邻 PTS 差） |
|---|---|---|---|
| 原始 TS 0 | 120 / 11.581000—15.547667 | 465 / 1.400000—17.250622 | 音频 5.973334 秒 |
| 原始 TS 1 | 180 / 1.400000—11.590667 | 93 / 2.850956—4.813622 | 视频 4.257333 秒 |
| 生产合并 MP4 | 300 / 10.181000—25.913289 | 558 / 0—19.136250 | 视频 1.574955、4.257333 秒；音频 5.973333、1.322958 秒 |

所有单轨 DTS 均未发现倒退。合并前后包数为 120+180=300、465+93=558；这是数量核对，不声称完成逐包载荷哈希等价证明。

MP4 首个视频 PTS **10.181 = TS 0 的 11.581 − 1.400**，所以首段晚起点在采集产物中就已存在。合并不可能凭空恢复未捕获的视频或音频样本；禁止直接硬减 10 秒、补帧或全局抹平间隔来把测试改绿。

拼接边界仍有独立影响：TS 0 的 format.duration=15.722622，下一段视频起点被 concat 放在 15.722622；它与前段最后视频包之间形成额外约 1.575 秒间隔。[FFmpeg concat 文档](https://ffmpeg.org/ffmpeg-formats.html#concat)说明其按文件时长整体平移后续文件，不同轨道长度与时长估计可能产生间隙。该机制与观测一致，但原始包计时缺口及分段边界来源仍需分开诊断，尚未证明应该替换哪一层。

## 本地受控 CMAF：时延与媒体范围不是一回事

新增 `tool/probes/cmaf_rendition_window_probe_test.dart`：使用明确生成的 24 秒、320×180/30 fps H.264 与 48 kHz AAC、独立音视频 fMP4 HLS。所有资源只由本机 loopback 提供，并经生产 FFmpegManager/HLS relay/录制命令写入 TS，再独立读取逐包 PTS。

| 场景 | 输入差异 | 视频/音频包数 | 视频减音频首 PTS |
|---|---|---|---|
| aligned | 两轨均完整 24 秒 | 720 / 1126 | 0.021033 秒 |
| aligned-delivery-delay | 同样媒体，仅视频清单响应延迟 2500 ms | 720 / 1126 | 0.021033 秒 |
| video-window-ten-seconds-later | 视频清单省略前 5 个两秒分片，音频不变 | 420 / 1126 | 10.021033 秒 |

三组中视频相邻 PTS 最大约 0.033334 秒、音频约 0.021334 秒，已核对所有生成包数。相同输入的延迟响应没有变成时间戳偏移；有意缺少前十秒视频的输入则保留真实缺口，未伪造内容。**这仅提供区分原因的对照，不证明 TTing 真实房间的初始两路清单就是该错位，也不证明流动窗口、Clash 吞吐或重载都正常。** 本地文件预先完整就绪且有 ENDLIST，不用于声称直播启动耗时已改善。

首轮探针把有界夹具的自然 EOF 错期望为 liveRecording 的 complete，结果 0/1。对照 `FFmpegTerminalDecision.forSession` 后，修订探针为断言 code=0、error、failure_kind=unexpectedEof；生产直播自然 EOF 的续源语义保持原样。最终覆盖全部三个场景，不以改业务代码满足夹具。原首轮结果/源码哈希独立保留。

## 验证与复现

| 记录 | 结果 | 总耗时 / 峰值 CPU / WS |
|---|---|---|
| `20260909T071650765Z-tting-retained-packet-timeline.json` | 三个原件读取成功，probeExits=[0,0,0] | 30.989 秒 / 0%（采样值） / 9,323,094,016 B |
| `20260909T072609027Z-cmaf-rendition-window-controls.json` | fixture、format、analyze 均 0；首轮 EOF 断言失败 | 159.933 秒 / 39.49% / 10,805,993,472 B |
| `20260909T072927581Z-cmaf-rendition-window-controls.json` | **1/1 原生测试，内含三个场景**；最终单文件 fatal-infos 分析通过 | 114.266 秒 / 12.9% / 11,500,339,200 B |

三份记录结束活跃重型进程均为 0。最后复用并逐份校验既有夹具哈希，没有重新编码以改变输入；提交前源码与 control-source.json 一致。原始逐包 JSON、timeline-summary.json、fixture-hashes.json、请求时刻、三个场景的包表与 summary 都位于忽略目录 `local-artifacts/tting-timeline-20260909/`。本批源代码/模板未包含真实媒体、URL 签名或账号内容。

在 `tool/build_resource_guard.ps1` 的重型任务槽内可用以下 FFmpeg 参数生成同类夹具；`$fixture` 指向新建的本地忽略目录，先建 variant_0、variant_1 子目录，已有文件使用 -n 保护。当前实际工具 `D:\Soft\ffmpeg\bin\ffmpeg.exe` 的哈希见前批运行时账本。

```powershell
& 'D:\Soft\ffmpeg\bin\ffmpeg.exe' -n -hide_banner -loglevel error `
  -f lavfi -i 'testsrc2=size=320x180:rate=30' -f lavfi -i 'sine=frequency=440:sample_rate=48000' `
  -t 24 -map 0:v:0 -map 1:a:0 -c:v libx264 -preset ultrafast -threads:v 2 `
  -pix_fmt yuv420p -g 60 -keyint_min 60 -sc_threshold 0 -c:a aac -b:a 96k `
  -f hls -hls_time 2 -hls_list_size 0 -hls_segment_type fmp4 -hls_flags independent_segments `
  -var_stream_map 'v:0,agroup:aud a:0,agroup:aud,default:yes' -master_pl_name master.m3u8 `
  -hls_segment_filename "$fixture/variant_%v/segment_%03d.m4s" "$fixture/variant_%v/index.m3u8"
```

探针需显式设置 PURELIVE_CMAF_WINDOW_PROBE=1、PURELIVE_CMAF_WINDOW_FIXTURE、PURELIVE_RECORDING_PROBE_OUTPUT 与 PURELIVE_FFPROBE；未启用时跳过。实际受保护运行脚本为本地证据目录下 control.ps1/control-reuse.ps1，没有后台测试或设备动作。

## 下一步与全目标

优先补真实原生采集的只读、有界诊断：首次音/视频清单的 media sequence、PROGRAM-DATE-TIME 范围，资源请求/首字节/完整 body/relay 交付时间，再与 native 进度对照。只采集结构化时序和数量，避免写入签名 URL。取证后再判断是初始时间范围错位、传输跟不上滚动窗口还是 native 缓冲/时钟处理；生产 dts_delta_threshold=2 也需用对应复现验证，不因其与[FFmpeg 默认值](https://ffmpeg.org/ffmpeg.html)不同就直接修改。

TTing 实时采集、同步及完整录制仍未通过；离线解码/本地对照不替代该门禁。版本仍 3.1.8+4121、候选不变，18 直播站点 + IPTV、9 组未注册与 42 个宏观大项未闭环保持。没有真实网络重录、手机/Root/LSP 操作、构建、发布或上游合并。全目标继续。
