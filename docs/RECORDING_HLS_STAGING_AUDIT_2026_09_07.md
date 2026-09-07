# HLS 完整响应暂存与停止边界（2026-09-07）

接续 [输出刷新审计](RECORDING_OUTPUT_FLUSH_AUDIT_2026_09_07.md)。基线为 `a65638bd29eca7a4ad5c827f7a20c9b451fdd1f6`：逐包刷新已经保护输出，但25%/50%/90%暂停响应仍约6秒后强制取消、输入损坏标记仍为true。当前批次只做源码与本机验证，未构建APK、安装、发布或操作手机、MT、LSP。

## 第一个错误状态与设计

旧转发器把正在接收的媒体响应直接送给FFmpeg；停止冻结播放列表并不能收回已交给解复用器的半个fMP4响应。这个问题不同于上一批原生输出AVIO截断。此处来源记为维护分支转发/停止设计的 `fork-regression`；沿用上一批真实红测，不宣称已证明Pure Live原项目同场景或最早引入版本。

- 只在录制 `drainOnStop` 路径，对成功的200/206非播放列表GET响应先完整接收，再发布HTTP成功响应和实际长度。普通TLS转发仍流式传递。
- `HlsMediaSpool` 默认每个响应2MiB内存阈值，超过后写入单独拥有的临时文件；每响应128MiB上限，每转发器最多8个正在暂存/发布的响应，超额返回503。16MiB只是主要暂存缓冲预算，不包括网络块、复制及运行时开销；临时文件理论预算最高1GiB，不是整机磁盘配额。
- 已知Content-Length必须匹配；自动解压响应按解压后实际字节数发布，避免拿压缩长度误判。无长度响应依赖HTTP流正常结束，不宣称进行了codec或容器完整性验证。
- 停止先冻结最后完整播放列表并追加ENDLIST；给下载一个target duration（限制1至10秒）的完成窗口，再退掉未发布的响应，返回空410而非半个200。已经完整接收并开始发布的响应不受该下载计时器中断。原生总体停止预算不增加。
- 请求头、播放列表刷新体、重定向响应体和媒体下载分别登记中断处理；停滞的刷新返回最后完整列表。close关闭输入/服务后等待已登记处理器结束，再释放映射与暂存文件。删除只针对本次拥有的body.bin和空目录，不递归清理共享父目录。

这里“完整响应边界”**不是保留停止前已从网络收到的每个字节**：未收完的整片会被舍弃，其时长可能大于零。主列表中尚未读取的尾片也可能在下载窗口结束后不再获取。`inputDrained`原有定义只是finish后无需forcedCancel而结束，不保证纯EOF、全部输入抵达或媒体无损；记录结果不能外推为无丢帧、无时长缺口或所有平台通过。

## 相邻合并停止竞态

首轮8文件定向回归出现一次停止请求调用2次。`VideoProcessorService._stopNative`在停止应答后清空stopRequest，而原生执行Future/迟到startAck尚未结束，可再次进入停止。`git blame`定位该生命周期逻辑到维护提交 `9f9ce5c5d0345bd903025fe07ee144f8dcdbe40c`，记为 `fork-regression`。

现在先发布Completer所有权再调用native，直到本次operation释放都保留同一停止应答Future；应答不是writer终止证明。新增exitGate夹具让writer明确停留在应答之后，多次cancel/onClose只发一次停止，退出前保留源文件与任务所有权。若停止调用本身抛错会记录日志并保留该应答，源所有权仍等待实际执行结束，不把抛错视为已结束。

原有30ms超时测试还错误地假定convertToMp4返回false时writer及文件清理都已同步结束；两轮失败都指向native.running断言。修改为等待已存在的有界任务所有权释放条件，再核对writer退出、源保留和临时文件消失；没有延长生产超时，也没有降低只停止一次的断言。

## 验证账目

证据根目录 `local-artifacts/hls-staged-input-20260907/`。

- 第一轮74通过/1失败：重复停止；记录 `20260907T140432271Z-hls-staged-input.json`，114.474秒，结束活跃重型进程0。原日志保留为unit-first-stop-race.log。记录command文字沿用了旧数量，实际脚本为4个格式化文件、8个定向测试文件。
- 第二轮76通过/1失败：超时测试native.running断言；记录 `20260907T141045223Z-hls-staged-input.json`，131.272秒，结束活跃重型进程1（不归本批的活动任务）。原日志unit-second-cleanup-order.log。该轮记录声称格式化7文件，实际输出为4文件，随后已修正脚本。
- 第三轮76通过/1失败：等待清理放在native.running断言之后，未覆盖失败位置；记录 `20260907T141417078Z-hls-staged-input.json`，74.712秒，结束活跃重型进程0；日志unit-third-native-exit-order.log。格式化已是7文件。
- 以上三轮均在单元测试门禁停止，未运行原生探针或analyze。

最终修改后，**77/77定向测试通过**；生产原生探针1/1通过，内部四个场景严格A/V解码均退出0、decode错误日志均空、nativeRunning均false，且inputDrained=true、forcedCancel=false、inputIntegrityError=false。原生证据 `hls-partial-1788790606238400/summary.json`：

| 第四片 | 停止耗时ms | 输出TS字节 | 与停止前已接收数据的关系 |
| --- | ---: | ---: | --- |
| 完整对照 | 2049 | 929660 | 四片均发布，文件SHA与上一批完整对照相同 |
| 25%后暂停 | 2007 | 683756 | 第四片未发布，保留前三片 |
| 50%后暂停 | 2009 | 683756 | 同上 |
| 90%后暂停 | 2006 | 683756 | 同上 |

所有文件长度对188取余为0。三个暂停场景输出SHA相同：`77B17E5CC1C8C5F88F1DFA161884DE0DBCC6EC0ADB439913B0E97B8346C5910C`；完整对照为`1A225450A9CF14EF75BE6FE24619BCDEA4C60ECAC12B81CACFEBD72D666A4ED0`。这些文件和output-hashes.json原样保留，未裁剪或转码修补。

**原生诊断并非空日志**：暂停场景明确包含HTTP410、segment3跳过以及`Error during demuxing: I/O error`。成功的是严格解码健康前段以及避免会话强制取消，不是无错误EOF或完整第四片保留。没有修改既有错误分类器来取得false；后续需要审计尾片舍弃的用户可见诊断及结果语义。强断言中的“normally”仅按现有终止字段定义，不应解释为未发生输入I/O结束错误。

本轮Flutter test映射仍指向`build/native_assets/windows/libffmpegkit.dll`，54,565,256 B，SHA256 `888A15993862950FEED714990E459F653B68BBC2CE30DA7D4BDA8DB9A5212C06`，与上一批核验的归档entry一致；当前native.log中的Build Hook自身SHA校验也通过。未改原生库或依赖；核对保存于runtime-provenance.json。

7个修改Dart文件格式化后范围analyze一次通过，无诊断，45.4秒。最终记录 `20260907T141808874Z-hls-staged-input.json`，总计196.075秒，unit/native/analyze均退出0，结束活跃重型进程0。该轮不是全库门禁或APK构建。

## 剩余验收与回滚

1. 原生探针新增强断言：四场景必须严格A/V解码退出0、错误日志空、native停止，同时inputDrained=true、forcedCancel=false、inputIntegrityError=false。保持输入损坏分类与源保留规则，禁止为了过测消除真实错误。
2. Android临时目录插件路径、真机短录/高画质首帧、长录/后台/两次续签及高码率磁盘和功耗仍待验证。暂存增加首片延迟与磁盘I/O，当前小片探针不是性能验收。
3. 8路容量、128MiB大资源、磁盘满、磁盘写入/读取中close以及真实加密/复杂Range媒体仍需进一步边界验证。helper的溢写测试仅证明单个自有临时文件字节与清理，不是大媒体端到端证据。
4. openUrl建立连接阶段在取得HttpClientRequest前仍依赖15秒连接超时；这一停滞边界没有当前原生证据。HTTP流正常结束也不证明媒体结构完整。

回滚以本批relay/helper、合并停止锁存和对应测试为边界；保留上一批输出flush修订和所有原始录像/红测证据。完整3.2.0门禁未完成，版本仍3.1.8+4121，手机最后核验候选仍80b7431c。
