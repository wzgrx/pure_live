# 多画面会话型输入接入审计（2026-09-10）

## 范围与来源

基线 `5a92e34afe595897e09895f554a96e5b0a30f299`，版本仍 3.1.8+4121。源自维护分支增加 owned input 后的 `fork-regression` 消费者接线缺口，不同步上游。此前直链入口的能力提示不是多画面播放实现，本轮实际接入每格播放器和控制器。

第一处错误是 `MultiviewController.resolveStreamForSite` 将 `resolution.urls.isEmpty` 当作无播放源，丢掉有效的 `inputRecipe`。随后 `MultiviewStreamSource`、格状态、`start/open` 契约也都只有 URL。直接复制主播放器的私有地址会让多个格子共用同一 seat、中继和退出路径，因此使用公开 factory 逐格、逐次创建。

## 实现与不变量

- 严格元数据解析路径与服务端画质确认保留。解析器只绑定配方，不创建 seat；默认绑定使用既有 niconico 生产工厂，跳过普通 URL 请求头解析。
- `MultiviewStreamSource.owned` 和格状态保留公开 `OwnedPlaybackSource`。逻辑线路为一条，导出 URL、headers、policies 和真实 URL 线路列表为空；地址只在 native dispatch 内出现。
- 新增可选 `MultiviewOwnedInputHandle.startOwned/openOwned`，现有 URL-only 后端契约保持兼容。实际 `MultiviewCellPlayer` 使用共享 `PlaybackSourceTransport.openOwned`，每格独立拥有 transport。
- 换画质在同一后端重新打开；新输入成功后再释放旧输入，失败候选自行清理。owned 与 direct 双向转换时清除旧来源、线路和 private-input 代理标志，保持音量/静音状态。
- 新请求在等待原生串行队列之前取消旧 owned acquisition，并等待其迟到返回/清理。第一次创建在进入原生前被取代时，新请求仍执行该后端唯一一次 start，而不是对尚未创建的播放器执行 open。
- 暂停期间完成的打开再次落实暂停。有效会话的普通恢复继续使用当前输入；会话已经关闭时通过公开 factory 重建，不复用过期 URI。重复恢复共用一个任务，恢复还受请求代次保护，避免旧恢复覆盖新的用户换源。
- 控制器的播放/暂停操作核对格子的 epoch 与 handle 后再更新按钮状态。失效会话恢复可能执行网络请求，其失败进入已有 startFailure 错误呈现；在恢复期间移除/换房间后，迟到的完成和错误不写回新格子。
- 已移除的格子可能仍在释放输入，控制器跟踪这些清理任务，页面 `disposeAll` 等待它们；同步移除产生的后台错误有观察者，每格 disposePlayer 的异常仍向调用者报告，页面 disposeAll 沿用记录错误后继续清理其他格的策略。保持 pause → dispose 后端顺序。

## 验证记录

- 第一轮五文件 82 项：81 PASS / 1 FAIL，失败是测试把包含 Map 的 Dart record 当作深相等；按 URL、headers 内容和 private 标志分别断言后修订，生产实现未为此改变。记录 `local-artifacts/build-records/20260910T060833911Z-multiview-owned-initial.json`，分析开关虽已请求，但测试失败后未进入分析。
- 进一步审查发现并稳定复现本轮新增恢复路径的真实竞态：失效会话 resume 等待队列时，用户发出新源请求；旧 resume 随后重新打开旧配方，将新请求判为 superseded。单项复现 FAIL，记录 `local-artifacts/build-records/20260910T061057775Z-multiview-owned-resume-repro.json`。修订为捕获/复核请求代次，且新源的打开自行遵循当前播放意图。
- 恢复代次修订后的七文件 109/109 与五文件严格分析通过，记录 `local-artifacts/build-records/20260910T061359425Z-multiview-owned-regression.json`。随后对控制器的恢复失败/退出呈现继续补齐两项生命周期测试。

- 最终七个测试文件 **111/111 PASS**（含 **19 项新增**），五个修改/新增 Dart 文件严格分析 **No issues found**，记录 `local-artifacts/build-records/20260910T062051386Z-multiview-owned-intent-lifecycle.json`。Flutter 3.47.0、`--no-pub --concurrency=12`；耗时 327.05 秒（含其他工作区 Java 活动排队、编译、分析及资源检查），共享峰值 CPU 38.95%、工作集 11380527104 B，终态活跃重型进程 1。没有终止其他工作区进程，缓存保留。逐文件散列与全部运行记录索引见 `local-artifacts/multiview-owned-20260910/evidence.json`。旧失败保留，不将多轮计数相加冒充覆盖量。

新增测试使用实际生产 resolver、MultiviewController、MultiviewCellPlayer 与 PlaybackSourceTransport，网络 seat 和底层 MediaKit 后端是可控替身。相邻传输测试含本机 HTTP 中继，Widget 回归覆盖既有多画面全屏呈现与房间选择。它们不代表真实 niconico 多路原生解码、Android/Windows 新候选界面或长时间多画面性能已经通过。

## 剩余、交付与回滚

niconico Site 的目录/搜索/分享/导航和平台注册、真实网络长录、多画面原生窗口/手机验收继续；自然结束后的自动恢复尚未实现，本轮只接入用户主动恢复；长时间多路性能仍待原生场景验证。19 站点 + IPTV、8 组未注册，历史 62 组中 42 组未闭环保持。

本轮未操作手机、安装、构建或发布。Android 仍 `152cf151` Debug（61 场景 not-run），Windows 仍 `2fb471d3`，均不包含本轮。完成全目标验收后才进入 3.2.0 正式发布。

回滚撤回本批三个 multiview 文件、transport 的只读有效性 getter 及本批测试/审计，保留已完成的主播放器和录制器 owned input 实现。没有全局 Root/LSP、ADB 或设备配置变更。
