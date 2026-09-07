# 录制输出缓冲截断修订（2026-09-07）

后续[完整响应暂存审计](RECORDING_HLS_STAGING_AUDIT_2026_09_07.md)已取得无需会话强制取消的本机四场景严格解码结果；尚有尾片舍弃/I/O日志、性能和Android复验限制。以下保留本批当时结论。

接续 [HLS 在途停止复现](RECORDING_HLS_PARTIAL_STOP_AUDIT_2026_09_07.md)。本批区分两个问题：**已封装数据的输出缓冲截断**与**停止时仍有未完整收到的输入分片**。前者已有源码修订和本机对照，后者仍待完整停止设计与原生验收；不把健康的已保存前段当作整段录制成功。

## 原生源码证据

固定 Flutter 插件0.6.2、builder0.11.1，未更新依赖。GitHub只读查询确认其 Android/Windows 发布标签都指向 `4dc903c2a29741b8f9b61dd94b10185bae69a493`。下载7个相关源码文件，Git blob SHA-1逐一匹配该提交tree；证据在 `local-artifacts/hls-output-flush-20260907/source-provenance.json`。这是发布标签关联源码核对，不宣称重新编译过整个原生库。

1. 插件本地 `Session.cancel()`调用`ffmpeg_kit_cancel_session(sessionId)`；[wrapper](https://github.com/akashskypatel/ffmpeg-kit-builders/blob/4dc903c2a29741b8f9b61dd94b10185bae69a493/FFmpegKit/src/ffmpegkit_wrapper.cpp#L803)转给按会话取消。[FFmpegKitConfig](https://github.com/akashskypatel/ffmpeg-kit-builders/blob/4dc903c2a29741b8f9b61dd94b10185bae69a493/FFmpegKit/src/FFmpegKitConfig.cpp#L955)在sessionMap锁存取消状态。
2. [decode_interrupt_cb](https://github.com/akashskypatel/ffmpeg-kit-builders/blob/4dc903c2a29741b8f9b61dd94b10185bae69a493/FFmpegKit/src/ffmpeg.c#L323)发现该会话被取消就返回1；[ffmpeg_init_interrupt_callback](https://github.com/akashskypatel/ffmpeg-kit-builders/blob/4dc903c2a29741b8f9b61dd94b10185bae69a493/FFmpegKit/src/ffmpeg_lib.c#L236)绑定同一context。[输出初始化](https://github.com/akashskypatel/ffmpeg-kit-builders/blob/4dc903c2a29741b8f9b61dd94b10185bae69a493/FFmpegKit/src/ffmpeg_mux_init.c#L3407)也使用该回调，而非仅输入网络使用。
3. [收尾](https://github.com/akashskypatel/ffmpeg-kit-builders/blob/4dc903c2a29741b8f9b61dd94b10185bae69a493/FFmpegKit/src/ffmpeg_mux.c#L770)仍调用av_write_trailer/avio_closep，因此可能遇到已经锁存的输出中断。更关键的是[最终返回处理](https://github.com/akashskypatel/ffmpeg-kit-builders/blob/4dc903c2a29741b8f9b61dd94b10185bae69a493/FFmpegKit/src/ffmpeg.c#L1183)把AVERROR_EXIT转为0，与探针中“写trailer报立即退出、但会话code=0”相符。

本机第一个可证实的错误状态不是后续MP4合并，而是原TS已停在健康对照的524288 B前缀、末尾不是完整188 B包。上述源码与单变量对照共同支持“会话取消影响输出缓冲收尾”。来源记为`upstream-existing`，限所选第三方FFmpegKit发布源码；Pure Live原项目同场景与最早引入版本未在本批证明。Android原MP4尾部错误是否由相同路径造成仍待复验。

排除取消全部session或发送进程级SIGINT方案：该源码中id=0使用全局signal路径，会扩大到其他原生任务。未修改本机DLL、共享Pub缓存或设备模块。

## 单变量诊断对照

原生产代码保持不变时，探针只在输出参数末尾加`-segment_format_options flush_packets=1`；实验差异保留为 `local-artifacts/hls-output-flush-20260907/packet-flush-experiment.patch`。它作用于segment内部的MPEG-TS muxer，不是只设置外层segment。

[FFmpeg格式文档](https://ffmpeg.org/ffmpeg-formats.html#Format-Options)说明flush_packets=1会在每个packet后刷新底层I/O；默认auto及关闭刷新有不同吞吐特征。此处不是fsync持久化保证，也不改变转码、时间戳或输入校验策略。

证据 `local-artifacts/hls-output-flush-20260907/hls-partial-1788788564192068/summary.json`：

| 第四片响应 | 原生产TS严格解码 | 加入内层刷新后TS字节 | 新严格解码 | 新inputIntegrityError |
| --- | --- | ---: | --- | --- |
| 完整对照 | PASS | 929660 | PASS，日志空 | false |
| 25%后暂停 | FAIL | 678116 | PASS，日志空 | true |
| 50%后暂停 | FAIL | 678116 | PASS，日志空 | true |
| 90%后暂停 | FAIL | 680560 | PASS，日志空 | true |

完整对照stop2038ms；三个暂停场景6032/6031/6038ms，仍强制取消，仍未drained。没有延长6秒预算。所有输出保留原文件并严格解码视频+音频，没有裁剪、补帧、转码或去掉-xerror。探针只断言保存的媒体有效，不把输入损坏标记变成false。

记录 `20260907T134319353Z-hls-output-flush-probe.json`：succeeded，518.33秒（含排队），结束活跃重型进程0。其他项目Java测试仍活动时等待，未终止或绕过共享资源守卫。

## 生产修订与验证范围

- `FFmpegCommandBuilder.buildRecordArguments`为录制的内部TS muxer设置`flush_packets=1`。保留stream-copy、分段时长、PTS策略、可选音视频映射、所有输入headers和超时；播放器音频转发、合并命令未改。
- 增加参数合同覆盖HLS/FLV/RTMP/本地输入：只出现一个内层配置，位于输入之后且输出路径之前，不误放成外层`-flush_packets`。
- 探针已移除诊断覆盖变量，直接使用生产参数，并把实际segmentFormatOptions写入证据，防止实验覆盖被当成应用实装。
- 输入损坏锁存、attempt持久化、阻止不确定源段删除的既有规则保持。三个暂停场景仍代表不完整输入，不允许仅因TS可解码而消除这些失败标记。

最终生产路径证据 `local-artifacts/hls-output-flush-production-20260907/`，与参数覆盖实验分开记账：

- **66/66定向测试通过**：7个文件覆盖录制参数、损坏分类/锁存、输入drain、终止证据、HLS转发、合并生命周期与录制输出所有权。不是全库门禁。
- 原生探针1/1通过，内部完整/25%/50%/90%四场景全部严格音视频解码退出0、错误日志为空、会话结束；实际参数均记录为`flush_packets=1`。证据 `hls-partial-1788788962496872/summary.json`。对应stop2033/6041/6026/6030ms，文件929660/678116/678116/680560 B，均为完整188 B边界；三个暂停场景的inputIntegrityError仍true、forcedCancel仍true。
- 三个修改Dart文件在最后一次编辑后范围analyze一次通过，无诊断，61.0秒。记录 `20260907T135127945Z-hls-output-flush-production.json`，整体290.34秒，unit/native/analyze均退出0，结束活跃重型进程0；期间按策略等待其他rg/Java工作。
- Build Hook提示其自身没有发布SHA，未直接把该提示当成“已验证”。单独核对实际Flutter test映射`build/native_assets/windows/native_assets.json`：运行DLL **54,565,256 B**，SHA-256 `888A15993862950FEED714990E459F653B68BBC2CE30DA7D4BDA8DB9A5212C06`，与固定Windows压缩包内对应entry完全一致；压缩包SHA为既有策略固定值`AC4F7C6893EB2D2A7D9C1C7A08E8CAD42105B509D097CE2B2ECEABCDCBD7CB47`。原生日志也显示0.11.1/20260831。
- 首次辅助哈希核对误用了Dart CLI的`.dart_tool/native_assets.yaml`，选中旧的54,284,635 B DLL而报不匹配；没有替换或清理它。随后使用本轮Flutter test映射完成上述核对，失败观察和修正后的结果一起保留在`runtime-provenance.json`，未把旧CLI产物冒充本次运行库。源码文件哈希也在该记录内。

## 未完成项与回滚

1. 继续解决在途分片停止：完整响应提交边界、慢/停滞上游、读写同时活动时取消的竞态，以及正常录制结束所需的完整输入。逐包刷新保护已封装数据，不保证任意时刻强制中断总是保留全部已下载帧。
2. 原生输入损坏标记未覆盖的强制取消场景仍需源保留审计；不把本批输出保护替代该项。
3. 逐包刷新可能增加I/O调用；短探针不是高码率长录、手机功耗、磁盘吞吐或多路并发性能验收。加入这些后续验收，尚未宣称性能无回归。
4. Android首帧/高档、短录严格解码、4/8秒样本延展、长录/会话续签/后台仍待复验。本批没有ADB、MT或LSP操作，也没有新APK、全库正式门禁、版本提升或发布；批次尚在修订和本机验证阶段。

回滚只需恢复本批命令生成器、参数测试和探针修改；旧录像/诊断文件保持原样。保留上一批838f4a1的失败证据，以实际同场景红/绿记录而非预期描述作为后续验收依据。
