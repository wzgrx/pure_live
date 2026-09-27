# 录制分段时钟生产接入（2026-09-10）

前置证据：[同输入定位](RECORDING_CONCAT_CLOCK_DRIFT_2026_09_10.md)、[原生合成素材与精确复核](RECORDING_CLOCK_NATIVE_REGRESSION_2026_09_10.md)。本轮不合并上游，也不发布 3.2.0。

## 生产合同

- 新分段命名为 `PREFIX_000000.clock-v1.ts`，清单为 `PREFIX.clock-v1.csv`。版本写在每个 TS 文件名中，清单丢失时仍能识别新格式，避免退回旧的拼接方式。
- 保留外层 `avoid_negative_ts=make_non_negative` 与 `reset_timestamps=1`；子 TS 使用 `flush_packets=1:avoid_negative_ts=disabled`，由实际 FFmpeg segment muxer 写入 CSV。
- 合并按同一尝试的文件名、连续序号、目录、非空分段、完整末行、有限数值和递增起点验证清单；限制 8 MiB / 100000 段。每段显式 `inpoint 0`，duration 来自相邻起点差，不使用设置中的名义分段时长或前一行 end。
- 缺失、截断、错序、外来、混合新旧格式、空尾段等情况在原生合并前停止，保留 TS 与已有清单；不猜测缺失时钟，不静默舍弃末段。
- 旧前缀 TS 使用原来的 file-only 清单；显式旧版恢复不会借用另一尝试的 clock-v1 分段。前缀相似但不相同的尝试相互隔离。
- 新输出持有进程内路径预留，原生结束并关闭输入后才释放；磁盘上的同尝试输出（包括只剩非零序号的旧/新 TS）也会阻止重用。辅助 CSV 另有写入路径，防覆盖由显式预留与磁盘检查承担，而非只依赖 `-n`。[FFmpeg segment.c](https://ffmpeg.org/doxygen/trunk/segment_8c_source.html) 的 `segment_list_open` 使用写模式打开清单，这也是本实现采用预检查的依据。
- MP4 原子提交成功后才清理来源。`deleteSourceTs=false` 同时保留 TS 与 CSV；源 TS 删除失败时保留清单。取消/超时的实际原生 writer 仍未退出时，继续持有原有合并与目录所有权。
- 字节统计及增量跟踪识别新旧命名，不把 CSV 计入录制大小。定位起始序号后仍只跟踪当前与下一分段，避免每次 UI 采样重扫历史文件。

## 验证记录

本轮通过 167 项定向测试、15 个修改 Dart 文件严格分析，以及 5 组实际原生回归。三阶段证据分列如下，没有以源码接入替代运行证据。

首轮记录 `20260910T153813525Z-recorder-clock-production-first.json`：121 项通过，两个测试文件加载失败（`recorder_output_lifecycle_test.dart`、`recorder_lease_lifecycle_test.dart` 的旧替身缺少之前新增的 `flvDiagnostics` 参数），分析与原生阶段未进入。相邻 `record_source_query_metadata_test.dart` 也存在同类签名，已一起补齐并纳入下一轮定向范围；原失败日志保留。

原生探针显式把 single/legacy 参数还原到旧 profile，避免生产 builder 更新后基线随之变绿；所有实际合并均调用 `VideoProcessorService`。另增加本机 HTTP FLV 保持上游连接打开后的主动停止，对比精确提交的 FLV 字节、单段参考与实际多段输出，不把自然 EOF 当主动停止证据。

第二轮记录 `20260910T154652469Z-recorder-clock-production-signatures-and-stop.json`：**167/167 定向测试通过**；严格分析指出一个已无引用的 import 和两个多行 if 的花括号风格问题，原生阶段未进入。随后仅移除该 import、补齐花括号并修正一处注释；测试证据复用，分析与原生阶段继续，未为风格修正重新运行整套测试。

最终记录 `20260910T155443746Z-recorder-clock-production-lint-fixed.json`：**15 文件严格分析无问题，5/5 原生回归通过**。日志前缀 `local-artifacts/recorder-clock-production-20260910/20260910T154935378Z-lint-fixed.log`；结束后逐项核对 15 个源码文件指纹与该记录一致。28 个实际 FFmpegKit 录制/合并会话全部退出码为 0，逐轨完整解码均通过。

| 场景 | 视频 / 音频解码帧 | 新多段相对单段的时钟偏移范围 | 留存目录（统一位于 `local-artifacts/recorder-clock-native-20260910/runs/`） |
| --- | --- | --- | --- |
| 固定帧率 + AAC | 520 / 1121 | 视频 0，音频 2 个采样点 | `av_cfr-1789055666834491` |
| VFR + AAC | 506 / 1121 | 视频 0，音频 2 个采样点 | `av_vfr-1789055669514557` |
| 纯视频 | 520 / — | 视频 0 | `video_only-1789055671979639` |
| 纯音频 | — / 1121 | 音频 2 个采样点 | `audio_only-1789055673308120` |
| 主动停止 HTTP FLV | 520 / 1121 | 视频 0，音频 2 个采样点 | `manual-stop-1789055674717135` |

上述有序帧内容均一致。固定帧率旧路径仍复现视频约 176.844 ms、音频约 176.848 ms 的阶跃，VFR 旧路径约 175 ms，纯音频旧路径约 510.884 ms；没有改变原门槛或以名义 FPS 修平源间隙。
主动停止场景保存的 FLV 与完整自生成素材字节一致（SHA-256 `6be557a2102c3a9997f48056cbb5eb1f559b57b5bbd10a4bc1e9e81e6a3ea084`）；三段 CSV 完整，`manualStop=true / forcedCancel=false / inputDrained=true / inputIntegrityError=false`，合并与内容/时钟对照通过。该本机已缓冲样本停止耗时 9 ms，不作为真实网络停止延迟保证。

原始 summary 和帧哈希再次冻结到 `local-artifacts/recorder-clock-production-20260910/passed-native-inputs.json`。原生 DLL 与外部解码器在运行前后维持锁定指纹；阶段耗时 308.132 秒，资源采样峰值 CPU 20.75%、工作集 10334289920 B，收尾活跃重型进程为 0。日志仍有原生 `pthread_join ESRCH`、纯音频 TS 警告和未初始化翻译资产的测试提示，不把退出码成功称为所有日志无警告。

## 待补范围

当前原生素材范围为 H.264 / AAC 的固定帧率、VFR、纯视频、纯音频及正常 FLV 主动停止。HEVC、多音轨、其他采样率、编码参数切换、非 FLV 输入、强制取消后的异常恢复和 Android 实机仍须分别补证；原微博实际留存样本还需走新生产路径复验。操作系统级跨进程并发不是进程内路径预留的保证范围。

录制缺陷闭环、微博平台注册/UI 接入、全功能双端验收及全平台稳定发布仍按主目标继续；定向检查不替代完整质量门禁、实际构建和设备验收。
