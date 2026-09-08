# 克拉克拉双协议原生录制与尾部缺帧审计（2026-09-08）

## 结论

基线 `f0886866eaadeb2ed4775ad0b05c9014a8115d60`；修复提交 `26de437813b5a2b26dc531a30fb6fe5ee6159418`。本轮新增 Windows 原生 FFmpegKit 录制探针，实际发现 FLV 尾部缺帧，并修复了**转存误报成功后删除源分片**的保护盲点。**不是 FLV 录像质量修复完成**，也不是 Android/UI/长录验收通过。

当前 Android 候选仍 [ae5232b2](KILAKILA_FIXED_ANDROID_CANDIDATE_2026_09_08.md)，没有本次完整性保护；未重新构建、安装或发布。新问题已记录在 `candidate-readiness.json`，不可把此前 APK 完整门禁当作本次媒体缺陷已通过。Windows 最新 GUI 候选仍 f3de664a。

## 实际双协议录制

通过注册 KilakilaSite 的萌星目录选择公开免费 UID，再分别重新调用生产 StreamResolverService、请求头工厂、命令生成器、FFmpegManager 和 MP4 转存服务。第二次 FLV 使用同一 UID，不复用旧签名 URL。HTTP/媒体匿名直连；进程临时 Hive 与环境变量隔离，未使用用户配置、手机或系统代理变更。

- 萌星目录返回 10 条；质量 ID 与 URL 协议后缀分别核对，未杜撰硬失效时间。
- 每次约 26 秒增长采样用于跨越 10 秒切片边界，不作为长时稳定性结论。
- HLS：4 段，源大小 1,035,692 B；MP4 **852,088 B / 32.864 秒**，H.264 320×240 + AAC；SHA `3F03A4F10D245E45BDD1B390619BD66D5CA1626FF0A91B9BA7BC55B5940BE758`。
- FLV：采集停止 code=0、inputDrained=true、forcedCancel=false；转存也 code=0，但成品 **659,962 B** 严格解码失败，SHA `B43BA3B00D2259F2273B53E8567385A4FE74639295109A4D57427D4647D8D26A`。原始 TS 当时已被旧逻辑删除，MP4 保留。
- 失败 MP4 有 257 个视频包，最后一包在偏移 659925、长度 37 B，仅含长度前缀 + 33 B type-6 SEI，没有 VCL 画面；错误为 `missing picture in access unit with size 37` 和解码失败。

首次记录 `20260908T032352653Z-kilakila-native-integration.json`：HLS 1/1、FLV 0/1，总体 failed；探针初版单文件 analyze 79.9 秒无诊断。记录不能改写成双协议通过。

### 独立解码检查自身的校正

首次检查只断言退出码。HLS 虽退出 0，默认 null 输出时基仍有 DTS 提示。检查 MP4 的全部视频 PTS 严格递增，最小正间隔 3000/90000 秒；改用 `-fps_mode passthrough -enc_time_base demux` 后，对**同一未改变文件**全解码，HLS 退出 0 且错误输出为空，FLV 仍因缺帧失败。该设置保留解码输出时基，不过滤错误、删帧或修改原文件。时基选项依据 [FFmpeg 官方文档](https://ffmpeg.org/ffmpeg.html#Advanced-options)。

探针最终版增加 stderr 必须为空的断言、先保存解码诊断，并在生产转存前复制原 TS 到单独取证子目录。最终版本通过三文件 analyze；默认关闭的探针实际结果为 **1 skipped**，不计原生 PASS。初次联网运行的原始版本另存 `native-probe-first.dart`，避免用后改脚本冒充已运行输入。

## 不依赖新直播时序的边界复现

同一主播另取 12.041 秒、316,784 B 的原始完整 FLV 标签，SHA `FB26AE91222B6639B2C3DFB8FAA7B5FFD5F1E441530A0DAB67962BA1F9695596`。共 688 标签加文件头，其中 42 个视频标签在画面 NAL 后仍有 SEI；没有独立 SEI-only FLV 标签。前一“独立 SEI 标签”假设被实际输入否定，因此没有按该假设改写转发器。

选定 3000 ms 的完整 AVC 标签含 NAL 7/8/5/6，下一视频标签 3100 ms 含 type 1。仅截取原文件不同完整标签前缀，未改媒体字节，以独立 FFmpeg CLI 做 FLV→TS→MP4 与完整解码：

| 截止点 | 输入字节 | 采集/转存退出 | 严格完整解码 |
| --- | ---: | --- | --- |
| 含尾 SEI 视频标签之前 | 80,009 | 0 / 0 | 0，错误为空 |
| 该完整视频标签之后 | 80,338 | 0 / 0 | 缺帧失败 |
| 再包含下一视频标签 | 82,488 | 0 / 0 | 0，错误为空 |

这证明当前输入与转封装链存在可重复的尾部边界问题，**FLV 标签完整不保证后续 Annex-B 访问单元尾部完整**。FFmpeg [H.264 parser 源码](https://www.ffmpeg.org/doxygen/7.0/h264__parser_8c_source.html)把未找到画面的访问单元作为解析错误。具体应如何保留尾 SEI、画面和其他元数据仍待设计验证，不对所有 SEI 做全局删除，也不把延长固定等待当作修复。

边界记录 `20260908T033210582Z-kilakila-flv-boundary-reproduction.json`；原始、派生媒体与包索引都在忽略目录，未提交直播媒体。取证过程中 FFprobe `-show_data` 原生工具崩溃，改用包位置/长度读取 MP4 字节；一次本地脚本名 inspect.py 与标准库撞名，重命名为 inspect_media.py 后消除；首次独立-SEI选择器 StopIteration 也保留，不记成功复现。

## 已修复的源保留盲点

维护分支 `f66cff51a1522d160a6ec7fa683b5f0ef308e1e8` 引入完整性分类器，本次发现精确的缺帧解析错误没有被识别。冻结上游 `c6c9bd70aedc503c003110dae10a83ad0bb891d8` 没有同名分类器；保护覆盖遗漏归为 **fork-regression**，并非本次同步上游。原媒体/原生解析器组合的全部历史来源尚待核验，不据单次现网输入宣称 external-drift。

修订只有 FFmpegMediaIntegrity 两组诊断中加入精确缺帧信息：

1. 采集时若观察到该错误，沿现有损坏字段锁存并传递，不被有界日志滚动擦除。
2. 严格转存即使 native code=0，也判为失败，现有事务路径保留 TS、移除自己的部分成品并释放操作。
3. 普通时间戳修正、停止 I/O、原生线程退出提示仍按现有分类，不 blanket 拦截警告；新 session 不继承前次损坏。

真实 FFmpegKit 对上面的正常/缺帧 TS 做生产 VideoProcessorService 对照（输入只是复制，原始证据保持）：

| 源 | 修复前 | 修复后 |
| --- | --- | --- |
| 正常画面尾部 | 成功、删除工作副本 TS | 成功、删除工作副本 TS |
| 缺帧尾部 | 错误地成功、删除工作副本 TS | **报告失败、保留 TS、0 个最终 MP4** |

两次均无遗留 processing。这里证明的是错误识别/源保留，未把失败媒体变为健康录像。原生夹具使用已有 task 构造中的 huya 标记，不进行虎牙网络请求；媒体来源仍是保存的克拉克拉输入。

## 回归、工具链与交付边界

- 有效红测：2 个新增分类器用例失败，已有 9 项通过；真实原生源保留对照 1 项失败（坏输入实际返回 true）。记录 `20260908T033728825Z-kilakila-pictureless-red.json`。
- 首次绿色入口错写不存在的 live_record_task_test.dart，48 项通过但载入失败，未进入 analyze；记录 `20260908T033910252Z-kilakila-pictureless-green.json`。仅修正入口为已存在的 persistence 测试文件，保留原日志。
- 最终 **65/65** 六文件录制回归、**三文件 analyze 73.7 秒无问题**；真实原生正常/缺帧对照 **1/1**。记录 `20260908T034548958Z-kilakila-pictureless-green.json`，367.926 秒，峰值 CPU 52.67%、13,745,496,064 B，结束活跃重型进程 0。
- 本批部分 Flutter 原生钩子报告远端 SHA 查询缺失并跳过；没有把它写作远端验证通过。实际已缓存 DLL 54,565,256 B，SHA `888A15993862950FEED714990E459F653B68BBC2CE30DA7D4BDA8DB9A5212C06` 与此前已验证版本一致。外部 FFmpeg/FFprobe 与 DLL 的本机哈希另存 runtime-inputs.json。
- 本轮没有重启、安装、Root/LSP/MT/ADB、手机前台或发布动作；用户数据未改。应用源码变更不借用旧 APK 的 2087 项作为新完整门禁。
- 历史 42 个大项/12 个参考平台未注册保持；W3-05 只增加证据，状态仍 RUN，其他平台/长录/可见 UI 未由本次覆盖。

下一步：使用保存的 FLV 标签与原生重放修复尾部访问单元边界，验证合法画面、音频、SPS/PPS、正常 SEI 和异常源都保留正确语义；之后再重新做两协议原生录制、候选构建和设备验收。回滚本次保护会恢复坏源误删风险，回滚前保留相关 attempt 源文件；本轮不提升版本或提前发布 3.2.0。

本机证据：`local-artifacts/kilakila-native-20260908/`，含原始/派生媒体、首版探针、红绿日志、原生对照、输入/工具哈希、终态 checkpoint 与 validation-source.json。
