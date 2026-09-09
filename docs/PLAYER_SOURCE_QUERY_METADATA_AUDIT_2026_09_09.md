# 主播放器源策略元数据审计（2026-09-09）

实现提交 `9e8aeaf12f8ae4a056165d7458632bb1f830aa04`。

后续 [主播放器 HLS 输入与连接所有权审计](PLAYBACK_SOURCE_TRANSPORT_AUDIT_2026_09_09.md) 已接入实际输入边界、独立媒体代理与远端 decoder identity，230 项定向测试及严格分析通过。路由取消集成、多画面、平台注册和原生实机验收仍未完成；下文保留元数据批次的历史边界。

基线 `ea5c0d0b7c02f8f7a22b639c4bbd6a7144bcf1dc`。本批延续 [录制接线](RECORD_SOURCE_QUERY_METADATA_AUDIT_2026_09_09.md)，仅完成主播放器的内存元数据链；**尚未把原生输入换为 relay，也没有新增实机通过项**。这是新增平台所需的能力扩展，不把普通 HLS 的标准 query 解析归为上游 Bug。没有同步或合并上游。

## 第一处缺口与接线

公共解析已经返回逐 URL 的 `sourceQueryPolicies`，原 PlayerController 只提取 URL/画质；普通加载、切画质、签名恢复及浮窗返回因此没有向播放器源事务传递该元数据。

1. `PlaybackSourceQualitySelection` 承载同一解析批次的画质与源策略。构造时核对每个键与策略绑定的源 URI 一致，复制成不可修改的映射；错误不回显签名。策略按精确远端 URL 查询，不按画质名或线路下标猜测。URL 列表成员核验仍由公共 `LivePlayUrlResolution.withSourcePolicies` 执行。
2. 初次解析、VideoController 创建、签名刷新结果、切源 opener 和 source commit 都保留映射。沿用已有 selection 的源批次、引擎恢复及预取事务，不增加单独的全局 token 缓存。
3. 仅切线路且无需网络刷新的分支使用 `withSourcePolicies` 复制原批次，保持画质确认与策略。新解析显式传入新映射；原生打开或后续页面状态提交失败时恢复旧映射。已有较新 source commit 优先，不被旧请求结果回写。
4. PlayerState 和 RoomSessionSnapshot 的音频/展示字段更新保留策略；提供新 URL 列表却没有新策略的更新清空映射，覆盖直接链接/IPTV/legacy source 等入口。PlayerState 相等比较包含映射，hash 与映射遍历顺序无关，现有 toString 不新增签名输出。
5. 浮窗快照创建、manager 合并当前已提交源、无缓存的兼容返回及路由恢复均携带策略，仍使用当前音频意图而非历史 source commit 的音频值。策略不加入数据库、任务 JSON 或设置迁移。

## 验证

首次记录 `20260909T004830342Z-player-source-query-green.json`：181 通过、1 失败，分析未运行。新恢复夹具选择了已经播放的第 0 条线路，被既有 no-op 条件正常返回，因此从未安装 resolver，测试随后对空值断言失败。只修正测试：先断言重复选中确实不解析/不打开，再选择第 1 条线路安装 resolver；保留生产 no-op 逻辑。496.101 秒含排队，CPU 峰值 38.53%、Working Set 13,458,391,040 B，结束活跃重型进程 0。原始日志、输入哈希与测试文件副本独立保留；该失败不属于产品红测。

最终记录 `20260909T005904999Z-player-source-query-green.json`：七文件 **182/182**，九份修改 Dart 文件 `analyze --fatal-infos` **No issues found**，测试、分析及 runner 均退出 0。563.558 秒含排队与分析，CPU 峰值 36.11%、Working Set 13,298,397,184 B，峰值 8 个进程，结束活跃重型进程 0。提交前逐项核对 green-source.json 的九个 SHA-256 与工作文件完全一致，`git diff --check` 通过。资源排队期间未改动业务/测试源码，也未停止其他 Java/Flutter/ADB 进程。

新增 8 项：源批次复制/错配及无签名错误、页面局部更新保留与直接替换清空、映射相等/hash、浮窗快照复制、实际控制器正常解析到 opener 与本地换线、打开失败和打开后的页面提交失败两种回滚、刷新结果到提交及后续 legacy 清空。另增强已有实际 PlayerManager 的连续两次签名恢复/暂停继续测试，以及浮窗恢复后切音频的源策略断言。

七个定向文件：`player_source_query_metadata_test`、`stream_selection_controller_test`、`player_load_fence_test`、`player_error_recovery_test`、`player_audio_mode_transition_test`、`video_source_commit_listener_test`、`record_source_query_metadata_test`。九份修改 Dart 文件统一格式化和严格分析，所有重型步骤串行遵守资源守卫。原始证据位于忽略目录 `local-artifacts/player-source-query-20260909/`。

这些测试使用本地站点/原生播放器替身，检验真实控制器、manager 及状态事务，不证明原生解码、真实平台请求或媒体文件完整性。

## 下一批：实际输入与连接所有权

本次只读核对发现三个 `_openPlayerSource` 入口：普通打开、引擎候选和 Windows 同引擎暖切候选。需要用各自 selection 的精确源策略创建每播放器持有的 relay，并保持 manager 的 URL 列表和 source commit 为远端身份。

- 成功替换后释放旧输入；失败候选仅释放自己的输入；待创建输入在退出后到达时立即关闭；原生打开超时后的迟到完成不得重新接管连接。
- 普通暂停与原位音频切换保留输入，softStop、暖切退役与 hardDispose 释放输入。必须覆盖失败回退、引擎切换、待创建/待打开与关闭交错的确定性测试。
- **代理语义尚待处理**：已有录制 relay 的回调读取 `enableAppProxy/appProxyHost/appProxyPort`；MediaKit 原生输入读取独立的 `enableProxy/proxyHost/proxyPort`。直接复用录制 relay 会改变媒体代理路径；native loopback 也应直连而不是再走外部 HTTP 代理。下一批需要显式媒体代理注入与验证，不默改用户代理设置。
- 多画面仍需统一解析结果和每格输入生命周期。TTing 严格 API/状态/身份、注册及用户入口、媒体/录制和原生验收继续保持未完成。

## 交付边界与回滚

没有手机、ADB/MT、Root/LSP、构建、覆盖安装或发布操作。用户提供的 MT MCP 信息不等于本批需要修改 APK；此批直接维护仓库源码。设备连接与前台应在下一次实机步骤重新核对，保留数据安装及全部远程救援约束保持。

版本仍 3.1.8+4121，Android 候选 bee143e2、Windows f3de664a 不含本批。17 直播站点 + IPTV、10 组参考平台未注册、历史 42 个宏观未闭环项均未减记，稳定 3.2.0 仍待完整目标验收。回滚应一起反向还原 selection、两个状态类型、控制器及测试接口变更；没有设备数据迁移需要回退。
