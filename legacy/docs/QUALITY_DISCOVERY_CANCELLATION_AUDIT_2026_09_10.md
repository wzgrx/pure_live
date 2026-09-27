# 主播放与工具箱画质发现的请求归属（2026-09-10）

## 来源与复现

基线 `9157543b8c27b04d8370e86faf160ca127516f86`，属于本分支新增 niconico 会话型发现与既有调用入口之间的 `integration-conflict`：适配器的 catalog 支持取消且拥有临时 seat，但 `LiveSite.getPlayQualites` 旧合同及调用者没有传递令牌。首个错误状态是页面请求已经作废、实际发现 transport 仍处于运行状态，而非最后显示了什么错误。

源码检查后以真实 NiconicoSite → NiconicoQualityCatalog 链路复现：分别作废主播放加载、取消工具箱操作，两个测试都观测到读取 token 仍为 false。固定 watch/master 与 session 替身仅替换网络；调用入口、请求归属和 catalog 清理使用生产实现。修改前 **0 PASS / 2 FAIL**，记录 `local-artifacts/build-records/20260910T074831591Z-quality-cancellation-baseline.json`。测试 finally 完成迟到响应并清理 seat，保留原始失败证据；没有访问真实节目或手机。

## 实现

- 新增可选 `LiveQualityDiscovery` 合同与统一发现扩展。合同明确要求向 transport 传递取消，并在临时会话/凭据释放后才结束；niconico 将 caller 传入已有独立请求 scope/catalog。旧入口仍调用同一实现。
- 旧平台沿用原 `getPlayQualites`，扩展只提供前后取消检查，不冒称已停止其底层网络，也不全局关闭共享 HTTP 客户端。
- 主播放在加载作废、新发现、站点替换、实际选流及关闭时取消上一发现；已关闭控制器不再分配发现请求。继续保留房间/站点/代次检查，较旧请求的 finally 不清空较新的令牌。
- 支持取消合同的发现清理以单独完成栅栏登记，销毁时等待这一范围；不将 native open 或无取消合同的旧请求一起纳入等待。销毁先捕获原视频控制器并立即开始其清理，后续状态清空只作用于同一实例，避免等待旧发现期间误销毁新房间的替换控制器。
- 工具箱对可取消发现使用独立 child deadline，超时取消 child 后等待清理，再报 TimeoutException；parent 仍活跃，让页面正常显示超时。用户退出/编辑则保持取消语义，迟到结果不触发选项、复制或投屏。原有普通请求和用户选择等待策略保持。

## 终态验证

首次集成遇到编译错误：当前固定 Dio 5.11.1 没有 `throwIfCancellationRequested`，且 PlayerController 新用 Completer 时缺少显式 dart:async 导入。读取本机实际依赖源码后使用已存在的 `isCancelled/cancelError`，补齐导入。重复同一编译错误时中断了本次命令；其目标进程已退出，分析未运行。原始日志和补记 `local-artifacts/build-records/20260910T075440470Z-quality-cancellation-integration.json` 保留；中断阶段资源监控终态摘要缺失，未伪填资源数值。

最终八文件 **148/148 PASS**，含新增 12 项：主播放作废/关闭/换站点/销毁、重复发现隔离与两次清理、清理期间的视频实例替换、工具箱取消与 child 超时、成功后 parent 保持、预取消零分配，以及旧适配器的成功/迟到取消行为。回归既有 niconico catalog/site/应用入口、主播放选流控制器、工具箱 flow/action 和真实双语 Widget 流程。测试检查 seat close 次数和凭据清空；原生视频对象和网络仍用替身，未据此宣称实机播放或真实网络长录通过。

六个修改/新增 Dart 文件严格分析 **No issues found**，记录 `local-artifacts/build-records/20260910T075817034Z-quality-cancellation-final.json`。耗时 215.76 秒（含编译、分析及守卫收尾），共享资源峰值 CPU 28.97%、工作集 13251911680 B，终态活跃重型进程 0。最终通过输入的文件哈希已对照；保留缓存，不停止其他工作区的 Java/Gradle。证据汇总于 `local-artifacts/quality-cancellation-20260910/evidence.json`。

## 后续验收，保持完整目标

这一批解决主播放和工具箱的画质发现；它不是全部请求类型的取消完成。多画面 `assignRoom` 的 resolver 仍需每格令牌，移除/换房/缩容/销毁需取消并收集发现清理。录制 `_runTask` 使用 TaskCancelToken，应在该任务取消回调向发现令牌转发且等清理；凭据预取还有独立请求身份，取消 timer 不等于取消正在预取的请求。搜索取消、room detail 和 URL 解析也需按各自合同继续核对。

保持 **20 个直播站点 + IPTV、7 组未注册、42 组历史验收未闭环**。还包括真实多画面、自然 EOF 恢复、长录、Android/Windows GUI/性能、其余平台扩展及全平台 3.2.0 构建签名发布/最终文档。未合并上游，未升级版本，未构建、安装、操作手机或变更 ADB/Root/LSP/MT；旧 Android/Windows 候选不包含本批源码。

回滚撤回本批可选发现合同、niconico 接线、主播放请求所有权和工具箱 child wait；保留此前已注册的应用路由与适配器。不要清除用户设置或收藏数据。
