# 录制尾片舍弃的结果提示（2026-09-07）

基线 `6415d42e71aa76d5ab3304f737bebf593cb6a792`。接续[完整响应暂存审计](RECORDING_HLS_STAGING_AUDIT_2026_09_07.md)：四场景严格解码通过，但暂停响应以410退掉整片，native仍报告跳片/I/O结束，不能把inputDrained或code=0当成完整输入。这一批不改变录制字节、停止时限或错误分类，补齐结果可见性。

## 来源与最早缺失状态

`fork-regression`：上一批新增退片行为后，relay没有把这个事实带进终止事件。旧native summary中的暂停场景与完整对照都只有inputDrained=true、forcedCancel=false、inputIntegrityError=false；控制器只接收损坏标记，录制卡片没有输入丢弃提示。该证据证明上一批边界行为存在信息丢失，不推断Pure Live原项目是否具有同一实现。

## 修订与不变量

- relay在停止导致非播放列表请求退掉、尚未关闭服务时锁存 `inputTailDiscarded`。它包括可能影响媒体的key/map请求，不声称数出了媒体片数或丢失秒数；普通播放列表刷新退回缓存、正常完成的响应、非停止的上游失败以及仅close清理都不制造该标记。close不抹掉已知结果。
- `FFmpegRecordSession.terminalEvidence()`将该事实放进不可变终止快照及既有日志/事件，只用于liveRecording。没有根据任意错误字符串猜测或放宽输入损坏分类。inputDrained原有“finish后无需forcedCancel”的定义保持，不升级为纯EOF证明。
- 控制器在当前session、任务所有权和最终采样代次校验之后锁存到任务；迟到旧session不污染新session。后续重连startAck、进度、干净终止和成功remux均不抹除提示。
- 任务schema从8到9，旧数据缺字段默认false；该布尔值随任务存储/恢复，用户明确开始新一轮录制时重置，自动新attempt不重置。它是当前用户录制的汇总，不是每个历史文件的独立档案；旧pending attempt及媒体文件不删除、不迁移。
- 录制卡片新增中英文提示，完整换行、无省略号，与错误区域和操作按钮分开。提示不宣称文件一定存在、不杜撰丢失时长，也不把健康分段强制标为损坏。已知packet损坏仍阻止自动remux/源删除；健康分段仍可按原流程生成MP4。

## 验证

证据目录 `local-artifacts/hls-tail-warning-20260907/`。10个文件 **126/126定向测试通过**，无失败后重跑。

受影响范围包括HTTP停止/非停止对照、不可变终止快照、任务持久化、新录制与重连边界、迟到终止、损坏源保留、健康remux以及录制页。中英文页面测试使用320px宽/2倍文字，检查新提示存在、无布局异常且开始操作可达；这是Widget布局/动作证据，不是Android截图或真实屏幕验收。

原生探针继续要求四场景严格A/V解码健康、结束且不强制取消，同时新增完整响应false、三个暂停响应true的实际终止字段断言。不再用“normally”描述这组字段，避免被理解为没有I/O结束错误。

原生探针1/1通过，内部四场景证据 `hls-partial-1788791294705879/summary.json`：完整/25%/50%/90%分别停止2063/2010/2007/2007ms，inputTailDiscarded分别false/true/true/true；严格A/V解码均退出0、decode日志空、nativeRunning=false、forcedCancel=false、inputDrained=true、inputIntegrityError=false。输出仍为929660/683756/683756/683756 B，源文件原样保留；暂停场景的410、跳片/I/O结束不被解释为无错误EOF。

当前Flutter test运行DLL仍为54,565,256 B，SHA256 `888A15993862950FEED714990E459F653B68BBC2CE30DA7D4BDA8DB9A5212C06`，与先前固定归档entry核验结果一致。本轮Build Hook提示没有发布SHA而跳过自身检查，独立映射/文件哈希核对保留于runtime-provenance.json，没有将Hook提示当作成功验证。

12个修改Dart文件格式化后，范围analyze一次通过，无诊断，90.9秒。记录 `20260907T143048264Z-hls-tail-warning.json`，总计345.836秒，unit/native/analyze均退出0，结束活跃重型进程0。脚本最初command元数据误记11文件，已按格式化/analyze实际输出更正为12，并在记录中保留原文字；没有重跑或改动检查结果。两份翻译JSON解析与git diff空白检查通过。

四场景输出SHA与上一批逐一相同（output-hashes.json）：本批增加标记及提示没有改变该确定性输入的录制输出字节。此结论仅针对探针输入，不外推所有输入的行为等价。

## 剩余范围与交付

这一批补充已知退片的如实提示，不解决丢失内容本身，也不保证没有未被观察到的输入丢失。需要继续验证大分片溢写、容量/磁盘失败/连接建立与关闭边界、延迟/高码率/长录/续签/后台，以及Android现有TwitCasting首帧/短录问题。历史文件级告警不由当前任务布尔值覆盖。

没有新增APK、版本递增、发布、ADB、MT或LSP操作；手机最后核验的候选仍80b7431c。3.2.0全平台发布继续以完整目标验收为前置。回滚只恢复本批提示字段、UI、翻译和对应测试；上一批暂存和输出刷新可独立保留，schema9的可选布尔字段不影响旧版忽略未知键。
