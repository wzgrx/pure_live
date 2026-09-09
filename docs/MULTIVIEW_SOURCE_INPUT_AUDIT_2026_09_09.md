# 多画面源策略与单格输入审计（2026-09-09）

实现 `fdb63269b3493393bb38fe9ca3a7005130759c96`，基线 `7dd983676bfa39bdd6dd9385644e738118b5e869`。延续 [主播放器输入](PLAYBACK_SOURCE_TRANSPORT_AUDIT_2026_09_09.md) 与 [切源确认](STREAM_COMMIT_RECEIPT_AUDIT_2026_09_09.md)，本批接通独立于 PlayerManager 的多画面路径。未注册 TTing，未进行原生解码、打包或手机操作。

## 发现与来源

1. 默认解析与画质 loader 直接调用 getPlayUrls，源策略、平台实际画质确认信息未进入单格状态。每格 start/open 直接把远端 URL 交给 MediaKit，缺少主播放器已经具备的输入所有者。此项为维护分支新增显式源策略能力的多画面接线缺口，不声称冻结上游应当具备尚未存在的策略。
2. setCellQuality 使用 next.headers 打开，成功后只提交质量/线路下标，后续 setCellLine 重新使用 state.headers。对于更新请求头的 loader，出现新源搭配旧请求头。冻结上游 `c6c9bd70aedc503c003110dae10a83ad0bb891d8` 中同样存在该结构，`git blame` 指向 `6ec8713dc`，归类 `upstream-existing`。
3. playingStream listener 捕获分配房间时的 epoch；质量/线路切换推进同一 epoch，之后原句柄的播放事件均被忽略。冻结上游同样使用 `_isStale(cellIndex, epoch)`，归类 `upstream-existing`。新测试在换画质及换线路之后发出暂停事件，检查按钮状态流继续更新。
4. 待 start 完成后才登记句柄，移除正在解析/起播的格子时没有句柄可以回收新输入。新测试将实际单格输入 factory 挂起，移除格子，再返回 lease，核对 native 从未 start 且 lease 只关闭一次。

本批没有先把全套旧源码运行成红测；来源证据是冻结源码/调用时序，修订行为由下述确定性测试证明。没有用模拟测试成功推断生产平台或解码器正常。

## 实现链

- 默认解析链仍复用平台完整房间查询和 LiveSite adapter，改用 resolvePlayUrls；清晰度确认复用 resolveAppliedPlayQuality。实际匹配的质量及 unconfirmed 标志传入初始和后续结果，未知平台 ID 不伪造成已确认画质。
- 每次画质解析重新解析请求头。源结果、CellState、start/open 都携带按精确远端 URL 选取的 HlsSourceQueryPolicy。copyWith 新线路未提供策略时清空旧策略；clearQuality 同时清空。
- 画质成功提交同步更新 headers、质量列表/实际下标、线路和策略，后续换线路使用同一批次配置。播放订阅以当前槽位持有的句柄身份校验，不再被质量请求 epoch 永久废弃。
- MultiviewCellPlayer 是每格独立的 PlaybackSourceTransport 所有者；默认后端为原 MediaKit 单格实现，可注入后端和 input factory 做时序测试。显式策略才创建 relay，后端接收私有 URL、空 headers；没有策略继续使用直接输入。
- 后端通过 MultiviewNativeInputRouting 得到 private-input 标志；每次打开前清空 loopback 输入的 native http-proxy，直接远端输入恢复媒体代理。relay 使用共享 transport 的媒体代理策略，和录制代理独立；没有改动用户代理设置。
- 每格 native open 串行化，迟到的 factory 不启动已经释放的后端；关闭即撤销输入代次，并在输入关闭异常时仍销毁后端。暂停保留活跃 lease，打开完成时重新服从暂停意图。原 VideoController 仍只通过 native player.dispose release hook 清理。
- 控制器在异步 start 前登记句柄，移除/缩容/退出即可回收待创建输入；旧分配等待释放后重新检查 epoch，避免覆盖新分配。后端初始化在关键 await 后核对 disposed，退出后不再创建新渲染控制器。

## 验证

新增 7 项：默认真实解析链的策略/画质确认；更新 headers、策略和播放订阅；两个真实单格 owner 隔离；factory 中关闭；native open 中暂停；真实控制器移除待创建输入；同格连续 open 串行与旧 lease 释放。

| 记录 | 结果 | 资源 |
|---|---|---|
| `20260909T050539274Z-multiview-source-input-green.json` | 四文件 66/66，四变更文件严格分析 No issues found | 234.635 秒；CPU 25.08%；WS 4,183,019,520 B；结束活跃重型进程 0 |
| `20260909T051015147Z-multiview-source-input-green.json` | 增补两条所有权测试后，四文件 **68/68**，四变更文件 `analyze --fatal-infos` **No issues found**；两退出码 0 | 215.038 秒；CPU 14.84%；WS 3,942,641,664 B；结束活跃重型进程 1（资源采样值，不代表本 runner 仍运行） |

范围：multiview_test、multiview_fullscreen_surface、multiview_room_picker、playback_source_transport。最后一组包含真实本机 HTTP relay 子请求，但单格后端测试使用可控替身，并未启动 libmpv。原始日志、两个版本输入哈希和脚本在忽略目录 `local-artifacts/multiview-source-input-20260909/`。最终四文件 SHA-256 与 green-source.json 核对一致后提交。未因静默或等待结束其他进程。

## 剩余与交付

源码仍 3.1.8+4121，无设置/数据库迁移。Android bee143e2、Windows f3de664a 候选不含本批；没有覆盖安装、重启、ADB/MT、Root/LSP 修改、清数据或发布。历史 42 个宏观未闭环项仍保留。

接下来推进 TTing/FLEX 平台适配与入口/录制，同时继续多画面布局晋升渲染尺寸、错误后资源状态及真实代理/解码/音量/退出验收。生产接口时效、原生性能和跨平台发布均无本批通过证据；稳定 3.2.0 仍以完整目标验收为条件。

回滚需同时还原上述实现提交中四文件，特别是 handle 的新可选 sourceQueryPolicy 参数与调用端；不触及用户数据。
