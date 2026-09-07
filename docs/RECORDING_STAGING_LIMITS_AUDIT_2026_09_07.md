# HLS 大响应与暂存容量验证（2026-09-07）

基线 `d7193ab96f9d2f23514589b392c0307c88b200bc`，接续[完整响应暂存](RECORDING_HLS_STAGING_AUDIT_2026_09_07.md)与[尾片提示](RECORDING_TAIL_WARNING_AUDIT_2026_09_07.md)。这一批补此前缺少的HTTP到真实临时文件集成证据，不把小字节helper测试当作落盘路径已验收。

## 实现范围

仅为relay提取默认临时目录factory，并允许测试注入自有目录/受控失败，增加只读暂存数量测试观察点。Android默认仍用path_provider临时目录，其他native平台仍用systemTemp，每次创建独立purelive-hls-media目录；2MiB内存阈值、128MiB响应上限、8个暂存/发布响应上限、停止预算和录制参数均不变。

没有因为新增测试而提前宣称发现或修复生产Bug。来源属于此前 `6415d42e` 暂存设计的证据缺口；以下结果仅验证覆盖到的路径。

## 五个新增集成场景

| 场景 | 具体断言 |
| --- | --- |
| 3MiB完整响应 | 使用真实loopback HTTP及默认2MiB阈值，恰好溢写一次；成功响应长度与每个字节精确匹配；处理结束后自有临时文件/目录均消失，旁边keep.txt字节不变 |
| 8路已溢写占满 | 同时8个3MiB响应尚未结束，观察到8个独立自有目录、8个占用名额；第9路503且0字节，无第9个临时目录；finish后前8路410且0字节，名额和8个目录全部释放，退片标记为true |
| 目录分配中close | factory已创建目录但尚未返回时调用close；它不会提前宣称完成，释放factory后清理后续创建的文件/目录，映射/名额归零，不制造用户退片标记 |
| 存储分配失败 | factory抛FileSystemException，响应502且0字节、名额释放；恢复该factory后同relay下一响应正确传完3MiB，无错误退片标记 |
| 128MiB+1B资源 | origin以64KiB块flush，真实触及硬上限后502且0字节；仅一个溢写目录，处理结束后移除，名额释放，不将未停止的上游失败标成停止退片 |

夹具每次只创建自己的随机根目录；keep.txt用于检查无关文件保护。收尾删除根目录不使用recursive，泄漏文件会令测试失败而非悄悄清理。3MiB数据采用可重算字节模式，检查每个发布字节，不只检查非空文件。容量测试统计的是暂存/发布响应，不是TCP连接、总堆内存或系统磁盘配额。

## 结果

证据目录 `local-artifacts/hls-staging-limits-20260907/`。4文件 **35/35定向回归通过**，含新增5场景及既有spool/HLS/终止快照，无失败重跑。

默认factory的生产原生探针1/1通过，内部四场景证据 `hls-partial-1788791962116103/summary.json`：完整/25%/50%/90%分别停止2040/2011/2013/2006ms，严格A/V解码均退出0、decode错误日志空、nativeRunning=false、forcedCancel=false、inputDrained=true、inputIntegrityError=false；退片标记分别false/true/true/true。输出929660/683756/683756/683756 B，逐文件SHA与上一批相同，output-hashes.json保留比较。没有把解复用I/O结束与退片解释为纯EOF。

当前Flutter test映射DLL仍为54,565,256 B，SHA256 `888A15993862950FEED714990E459F653B68BBC2CE30DA7D4BDA8DB9A5212C06`，匹配此前已核验归档entry；本轮Hook自身缺SHA跳过检查，独立核对见runtime-provenance.json。

2个修改Dart文件格式化后，范围analyze一次通过，无诊断，63.0秒。记录 `20260907T144115075Z-hls-staging-limits.json`，总计349.077秒，unit/native/analyze均退出0，结束活跃重型进程0。不是全库回归或APK构建。

## 未覆盖与下一步

- 这里是Windows真实文件I/O和loopback字节传递；3MiB载荷不是可播放媒体，不外推codec结果。另一个原生fMP4探针只覆盖小响应默认factory分支，不代表大分片原生吞吐验收。
- 注入的是目录分配异常，不是填满真实磁盘或真实写入中EIO；close中等待的分配最终被测试释放，不证明底层磁盘I/O永久不返回时仍能有界收尾。
- 尚待核对DNS/TCP/TLS建立阶段未取得HttpClientRequest的停止，现有15秒连接超时可能超过短HLS停止预算。
- 128MiB和8路上限确实生效，但其对长时间高码率、特别大HLS资源、复杂key/map/Range媒体及多任务总资源的适用性仍待验收；未测功耗或手机存储压力。
- Android默认临时目录和现有TwitCasting候选仍需新APK保留数据覆盖安装及实际录制复验。没有ADB、MT、LSP、Root/模块修改、构建、版本提升或发布，手机最后核验候选仍80b7431c。

回滚本批factory注入/只读观察点和新增测试即可；已有暂存行为、尾片提示与输出刷新不依赖这些测试接口。3.2.0整体目标保持未完成。
