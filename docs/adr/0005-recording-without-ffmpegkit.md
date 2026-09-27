# 0005 去掉 FFmpegKit 后的录制方案

- 状态：已接受
- 日期：2026-09-27

## 背景

FFmpegKit 在 arm64 包里占 29.1 MB，在 Windows 包里与 FFmpeg DLL 合计 52 MB。取消 FFmpegKit 会截断输出，由此衍生出 FLV 输入桥、AVC 边界等待、HLS 整片暂存与预取等约 4400 行补丁；每次续期都新开一次尝试，录制文件有缺口；TS 分段拼接有约 90 ms 时钟阶跃。诊断见 [diagnosis/04-recorder.md](../rewrite/diagnosis/04-recorder.md)。

## 决定

1. **来源按租期类型处理**：到期会断开连接的（斗鱼 `expire`）用 FLV 拼接续流；只限制新建连接的（虎牙原生 FLV）只在真正 EOF 时续接；没有租期的在 EOF 后续接。拼接会话外面再套一层会话循环，处理旧流先结束的情况。
2. **FLV 写入器**（纯 Dart）：文件头和脚本 tag 只写一次；时间戳单调；断流后重定基准，缺口写入 `gaps.json`；编解码配置变化或按时间、大小切分时，在关键帧处开新分段；旧式 codec 12 HEVC 改写为 Enhanced FLV；写入有背压。
3. **HLS 下载器**（纯 Dart）：自己轮询播放列表，整片下载，按序号去重，跳号记为缺口；保存为本地 VOD 归档（分片 + 本地化的 KEY / MAP + ENDLIST）。Bigo、FC2、niconico 的会话输入接到这里。
4. **转封装**：以 FFmpeg `doc/examples/remux.c` 为蓝本写一个 C 垫片，链接与 libmpv 共享的 libavformat（只需要 flv、mpegts、hls、mov 解复用和 mp4 复用、file / crypto 协议、parser 与 bsf，不需要解码器、swscale、swresample、avfilter）；在后台 isolate 运行，可中断，按字节报告进度，失败时保留源文件。libmpv 的构建配方改为共享 FFmpeg 库。退路：如果共享构建不可行，单独附带一个只含上述组件的精简 FFmpeg。（2026-09-28：改为纯 Dart 转封装，不链接 libavformat，见 ADR 0021 补充决定。）
5. **后台**：保留 Android 独立前台服务（保活引擎和锁）；Android 15 起 dataSync 类型每天限 6 小时，第 5 阶段在真机上评估改用其它类型。Windows 退出前提示正在录制；FLV 没有尾部结构，直接关闭文件即可。
6. **上线方式**：在 3.3.x 以开关接入，FFmpegKit 保留一个版本作为回退。门禁：斗鱼录 30 分钟，DTS 最大间隔不超过一帧；虎牙录 60 分钟无断开；各 HLS 平台完整解码无错误输出；杀进程后能恢复。
7. **旧录制的收尾**：遗留的 clock-v1 TS 分段在首次启动时用 concat 一次性合并。

## 备选方案与放弃理由

- 保留 FFmpegKit：体积大，截断问题需要继续靠补丁维持，而且无法无缝续流。
- 录制直接用 libmpv 的 stream-record：受播放参数影响，无法独立于播放运行，也不能控制分段。

## 影响

- 第 5 阶段需要修改 libmpv 的原生构建（Android 三个架构、Windows、Linux）。
- 录制相关的 13 个 FFmpegKit 会话替身测试随之作废。
