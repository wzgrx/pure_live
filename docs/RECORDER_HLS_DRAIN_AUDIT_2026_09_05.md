# HLS 录制停止与分片地址生命周期（2026-09-05）

## 基线、归属与复现

本批基线 `263e458a4e89d86d568efcdafe3d272aab3c6836`。沿用本仓库实现，不合并上游、不操作手机。
上一批只修复 HTTP-FLV 的停止排空；HLS、RTMP 是明确保留的独立验收项。本批处理 HLS。

原生停止的同一合同问题仍存在：FFmpegKit session cancel 同时中断输入和输出 IO，而本项目
把录制停止直接交给 cancel。这是依赖中断合同与本地停止策略的 `integration-conflict`，
不归因于直播平台、登录或 CDN。原 HLS TLS 中转为本分支 `e35247d0` 引入；其两个地址 Map
仅在整个会话关闭时清空，滚动播放列表不断追加地址属于本分支资源生命周期缺陷。

`tool/probes/recorder_hls_stop_probe_test.dart` 使用本地生成 H.264/AAC HLS、动态滚动 HTTP
播放列表、生产 FFmpegManager/FFmpegService/录制命令，独立 FFmpeg 完整解码作为额外检查。
原始 TS 不经修剪或重新编码后再验收。

旧代码红测 `20260905T121032538Z-quality-focused.json`：三个停止时点 150/700/1200 ms
均产生 **262,144 B、不满足 188 字节 TS 包对齐**的文件，native 输出写尾错误、forcedCancel=true。
这次三份文件独立解码都退出 0 且未报告错误，说明解码器会容忍部分截断；单独解码退出码仍不足。
故同时检查输出写尾、包对齐、完整音视频解码、真正结束和是否使用强制取消。
摘要 `local-artifacts/recording-probes/hls-stop-1788610225197341/summary.json`。

## 正常结束输入，而不是取消写盘

1. 原 HLS TLS 校验中转继续覆盖 Android/Linux HTTPS；仅 **liveRecording** 的 HTTP(S)
   m3u8 输入在所有原生平台启用正常停止。普通观看、纯音频播放、文件重封装不新增停止策略。
2. 每个媒体播放列表保存最近一次实际发布的重写内容。用户停止后冻结该代，并加 `EXT-X-ENDLIST`；
   master 多码率目录保持原状。正在等待的刷新结果在停止后不会把新分片扩展进已冻结的列表。
3. 不在分片中间强行关连接。已在读的媒体分片、AES 密钥、fMP4 初始化段、Range 响应继续完成。
   原始媒体字节、时间戳、加密合同、音视频映射不变，不借机改播放器比例、弹幕或界面。
4. HLS 的轮询受目标分片时长影响，排空预算为 `2 × 已见最大 TARGETDURATION + 2 秒`，
   限定 3–20 秒；与 FLV 的 3 秒预算分开。不是新增定时重连，也不缩短平台原始播放列表的分片时长。
   预算耗尽才用原有强制取消故障终止并继续等待原生完成，不把超时当作文件已收尾。
5. 立即停止未取到播放列表时，返回本地终止列表；不为已撤销的录制再请求远端。
6. 终止事件继续记录 inputDrained/forcedCancel；重复停止共用原有每会话 Future。

正常 HLS 停止可能等待当前分片和下一次列表轮询，界面沿用正在停止/收尾状态，不同步阻塞 UI。
超长分片、卡住的服务器仍可能进入有界强制终止；损坏输出检查和源文件保护继续保留，
不把这些故障写成“任何网络下都完整、立即停止”。

## 有界分片地址与传输

- 每个播放列表仅保留当前/前一代引用，包含嵌套列表、密钥和初始化段；从根列表递归标记，
  再删除不再引用的地址及相关缓存。正在处理的旧分片额外保留到请求结束，避免回收正在使用的地址。
- 200 次滚动更新的单列表测试始终只保留根节点加两代各两个地址（最多 5 个），
  当前与前一代继续可读，更老地址返回 404，关闭后计数为 0。
- 新代发布前同步清理。第一轮候选把清理放在 HTTP close 后，测试读取到暂留第三代的 7 个条目，
  整轮为 FAIL：`20260905T121628086Z-quality-focused.json`。已调整时序，不通过放宽上限消除失败。
- 每份上游列表最多 4 MiB，重写列表树合计最多 8 Mi UTF-16 code units；限制用于拦截超大输入，
  不是缓存整个视频。地址保留量按有效列表窗口/正在使用的引用决定，不按观看时长增长。
- 关闭使用同一个 Future，先结束 HTTP 服务端连接，再取消监听；迟到读完的列表不重建已清空资源。
- 媒体响应关闭额外 HTTP 输出缓冲，短数据块及时下传；上游证书校验、请求头与 Range 仍保留。
  非成功状态不当作可缓存播放列表，保持远端 HTTP 状态。

## 验证记录

离线 `20260905T122046292Z-quality-focused.json`：24/24，包含 9 项 HLS 与 15 项 FLV/排空回归。
覆盖嵌套 master、AES KEY、fMP4 MAP、字节范围、冻结、迟到刷新、200 次窗口更新、旧分片读取期间
清理、关闭时等待响应头、重复停止和正常 FLV 路径。实际 native 与离线 URL 重写证据分开。

| 固定输入 | native 记录 | 当前结论 |
|---|---|---|
| 普通 MPEG-TS，2 秒分片 | `20260905T122227169Z-quality-focused.json` | 三时点停止均通过 |
| AES-128 MPEG-TS，2 秒分片 | `20260905T122320787Z-quality-focused.json` | 三时点停止均通过 |
| fMP4，2 秒分片 | `20260905T122735532Z-quality-focused.json` | 三时点停止均通过 |
| MPEG-TS，6 秒分片 | `20260905T122829577Z-quality-focused.json` | 三时点停止均通过 |

fMP4 的首轮失败 `20260905T122427889Z-quality-focused.json` 发生在首包前：生成器把 init.mp4
写入调用目录，固定 HTTP 源目录缺少初始化文件。属于探针夹具错误，不作为产品 fMP4 失败结论。
原失败日志保留；已把已生成初始化文件归入夹具目录，并为探针增加密钥/init 文件前置检查、
HTTP 源失败立即返回状态、native 首包前失败即时报告。修正后的 fMP4 和较长分片已按上表复验。

12 个实际 native 停止案例均无输出写尾错误、TS 包对齐、完整音视频解码退出 0 且错误日志为空；
inputDrained=true、forcedCancel=false、nativeRunning=false。两秒分片三个停止时点实际收尾约
0.31–1.40 秒；六秒分片为 5.408/4.790/4.349 秒，验证了更长的 HLS 排空预算确有必要。
保留的输入结束 demux I/O 诊断不与输出写尾错误混为一谈，不隐藏 native 原始日志。
这些是停止后源 TS 的实际完整性证据，不冒充最终 GUI 操作、MP4 中心显示或客户端播放卡顿的测量。

四类对应 ignored 摘要目录分别为 `hls-stop-1788610936668456`、`hls-stop-1788610979973988`、
`hls-stop-1788611245682764`、`hls-stop-1788611287950341`，位于 `local-artifacts/recording-probes/`。
原始失败、成功媒体和 JSON 均保留；没有把 RED 或夹具失败重新标为 PASS。

### 完整质量门禁

`20260905T123435714Z-quality-full.json`：**1046/1046** 单元/Widget 测试、**42/42** 外部接口
探测通过，全仓结构扫描 4026 文件、0 错误、1 项既有 empty-catch 盘点提示。
本批唯一一次 analyze 为 44.5 秒、0 error/0 warning，探针一处 if 花括号 info 已等价整理，
随后只格式核验、不重复 analyze。生产业务代码保持与受测版本一致，另完善类注释及本文记录。

完整门禁总耗时 251.249 秒、并发 12；工具进程峰值工作集 11,204,718,592 B、CPU 22.01%，
结束活跃重型进程 0。四次 native 门禁分别用时 41.495/40.089/39.258/51.659 秒，均串行且
结束活跃重型进程 0。保持增量缓存与锁定依赖，未 clean；上述工具采样不当作客户端占用数据。
质量记录 source_commit 为基线 `263e458a`，运行包含本批未提交补丁；随后提交相同受测业务代码。
自动文件扫描不等同于对全部文件逐字语义审阅，外部短接口检查也不代替 CDN 持续录制。

本轮没有构建/签名/上传新的 APK 或 Windows 安装包，未递增正式版本；3.2.0 的完整客户端、
Android 原生、历史 PiP 和 GUI 资源回落等验收继续推进，不以本批质量门通过提前宣布完成。

## 重复执行

本地媒体统一由独立 FFmpeg 的 lavfi testsrc2（320×180@30）和 sine（48 kHz）生成，H.264
libx264 ultrafast、AAC、固定 GOP 对齐分片。两秒分片用 24 秒媒体/GOP 60；六秒分片用
48 秒媒体/GOP 180。HLS list_size=0，探针按时间取其中的四片窗口，不把生成的 ENDLIST 暴露为直播结束。
AES 测试使用随机生成、仅夹具使用的 16 字节密钥及固定 IV；fMP4 的 init.mp4 必须与 manifest 同目录。
生成时在独立夹具目录中运行 FFmpeg，避免相对 init 文件落在仓库根目录。

显式设置 PURELIVE_HLS_STOP_PROBE=1、PURELIVE_HLS_STOP_FIXTURE（夹具目录）、
PURELIVE_RECORDING_PROBE_OUTPUT（ignored 输出目录）和 PURELIVE_FFMPEG（独立解码器），
通过资源守卫下的 `tool/local_ci.ps1 -Scope Focused -TestPath tool/probes/recorder_hls_stop_probe_test.dart
-TestConcurrency 1 -SkipPubGet` 运行。不同夹具串行，不启动全平台构建，不访问外部直播或设备。

## 来源与交付边界

- [HLS ENDLIST 与列表合同](https://www.rfc-editor.org/rfc/rfc8216#section-4.3.3.4)。
- [FFmpeg HLS 轮询/结束处理](https://github.com/FFmpeg/FFmpeg/blob/master/libavformat/hls.c)。
- 上一批 [FLV 停止与输出排空](RECORDER_GRACEFUL_FLV_STOP_2026_09_05.md) 的锁定 FFmpegKit 取消实现。

无依赖、数据库或设置迁移。本批可以独立回退 HLS drainOnStop 和地址回收，不回退已验证的 FLV
排空、原生虎牙健康连接不定时重开或损坏源文件保护。回退会恢复已复现的 HLS 写尾截断风险。
Windows native 固定输入不代替 Android 原生、外部 CDN、完整 GUI 资源趋势与 3.2.0 最终发布验收。
