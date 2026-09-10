# 多画面与录制器画质发现归属（2026-09-10）

## 范围与来源

基线 `2ffa3b05e172b3471ba37c206ae5a94dc612c673`。上一批已接通主播放和工具箱；本批沿实际多画面 assignRoom、录制 _runTask 和凭据预取路径继续，保留完整 3.2.0 范围。未合并上游。

来源分类为 `integration-conflict`：本分支会话型 niconico 发现已支持 token/seat 清理，但多画面旧 resolver、StreamResolverService 与任务调用者仍是无取消参数的旧链路。只递增 UI 代次或取消 timer 不会终止正在执行的发现。按资源守卫查询全部相关派生类和引用，另有两个 opt-in 原生探针覆盖签名需同步；记录 `local-artifacts/build-records/20260910T080513621Z-discovery-owner-map.json`，资源排队 209.74 秒在内，未中断其他工作区 Java。

## 实现与归属边界

- 增加 LiveQualityDiscoveryScope：单个消费者拥有 token，拒绝关闭后新请求，关闭幂等；只等待实现可选发现合同的临时资源清理。它不关闭共享网络客户端，也不把普通 metadata/URL 或 native 播放生命周期混作同一资源。
- 多画面默认 resolver 经过站点注入入口和 scope，房间信息返回后先检查取消再发现画质；返回首次源后再检查。每格有独立 scope，替换/移除/缩容/关闭取消原 scope；已移除但清理中的 scope 保留在退休集合，disposeAll 加入等待。
- 缩容先同步取消所有被移除格，再并行等待各自清理；一个慢清理不会延后其他格的取消。可复用画质 URL loader 不捕获已结束的首次发现 scope，后续选流仍沿既有 owner 管理。
- 录制解析增加可选 discoveryScope；metadata、质量、URL 及换线路重试边界检查取消，取消错误不转成可重试的 CDN/网络错误。普通调用和旧适配器保持原有入口行为。
- 每个 _runTask 有独立 scope，TaskCancelToken 回调先传递取消，同时停止原生录制/处理并等待发现清理；runner finally 再加入幂等清理，不提前释放任务归属。
- 凭据预取持有不同于当前录制任务的 scope。取消定时器时同时取消已开始的预取；按任务 ID 保留退休清理，stopTask 和后台 shutdown 等待这一层。预取失败仍不停止健康的媒体采集，完成后的旧请求不重新挂定时器。
- 两个原生探针与两个测试 resolver 的派生方法签名同步。探针仅做本轮静态验证，没有启动实际录制或外部平台请求。

## 验证

首轮九文件 178/178 PASS，含新增 12 项：多画面移除/销毁/关闭/缩容、同格替换和其他格隔离、同时取消所有缩容格、metadata 迟到栅栏、实际录制解析和 scope 幂等，以及真实 RecorderController 的任务/预取/shutdown 取消。NiconicoSite 与 catalog 使用生产实现，网络和 seat/native 使用可控替身；检查实际子 token、seat close 次数、凭据清空、在清理门闩结束前保持 owner 等待。相邻主播放、工具箱取消、录制器/输出/选流与多画面既有合同全部随首轮回归。

首轮分析发现两项问题，记录 `local-artifacts/build-records/20260910T081219894Z-discovery-owners-initial.json`：构造参数使用 initializing formal 的样式提示，以及旧 Huya 原生探针 _RetainingManager.start 漏了已存在的 hlsPrefetch 参数。前者改用初始化形式；后者补齐接收并透传，不丢弃录制调用者的 HLS 预取选择。这是探针合同的既有遗漏，本轮静态范围覆盖到后才发现；没有据此宣称新的实际原生录制结果。

### 相邻缺陷：缩容后索引重用

旧实现每个数组槽位从 0 计数；缩容丢掉槽位，扩容又从 0 开始。同索引的新请求可能与缩容前旧请求具有相同 epoch。即使保留正常代次检查，一个未支持传输取消的旧 resolver 在这时返回，也会被误当成新房间结果并创建播放器。这是本分支多画面生命周期中的 `fork-regression`，不是外部直播接口漂移。

新增确定性复现：第 4 格请求挂起 → 双格缩容 → 四格扩容 → 第 4 格分配新房间 → 旧请求返回。修改前 **0 PASS / 1 FAIL**，明确触发 `unexpected stale native allocation`，记录 `local-artifacts/build-records/20260910T081503005Z-discovery-owners-epoch-repro.json`。以控制器内单调序号取代槽位重置计数，分配、画质/线路变更和捕获释放统一推进；保留现有状态与原生 owner 身份防护。没有通过删除旧回调或取消测试来掩盖问题。

最终三文件 **81/81 PASS**，覆盖全部多画面与 owned 输入相邻测试，以及新增的索引重用复现；旧结果不分配原生播放器，新格子保持新房间的 resolving 状态。首轮其余 **98 项**同业务输入通过证据复用，本轮去重覆盖 **179 项**、新增 **13 项**。不是把重复运行数累加成新覆盖。

九个 Dart 文件严格分析 **No issues found**，包含两个 opt-in 原生探针的静态签名核对；记录 `local-artifacts/build-records/20260910T081914045Z-discovery-owners-final.json`。最终三文件回归与分析耗时 219.60 秒，共享资源峰值 CPU 10.1%、工作集 13116248064 B，终态活跃重型进程 0。最终输入哈希已核对，证据与失败记录汇总于 `local-artifacts/discovery-owners-20260910/evidence.json`。

## 尚待完成

上述证据不等于真实平台、长录或双端 GUI 验收。它聚焦画质发现；metadata 和 URL 的传输级主动取消、搜索取消仍应继续核对，而不是把结果栅栏宣称为网络已经停止。保留多画面自然 EOF 自动恢复、实际多路解码与性能、真实长录、Android/Windows 全功能验收、其他平台扩展与全平台 3.2.0 签名发布及最终 README/更新日志交付。

当前仍为 20 直播站点 + IPTV、7 组未注册、42 组历史验收未闭环。版本及 Android/Windows 候选不变；本轮未操作手机、安装、构建、发布或变更 ADB/Root/LSP/MT/系统代理。

回滚撤回本批新增 scope 与多画面/录制任务接线和对应测试、探针签名；保留上一批主播放/工具箱及已注册平台。用户数据与配置保持。
