# IPTV 直连播放器启动事务审计（2026-09-12）

## 范围与基线

- 本批基线：`8f21978319136469cd823ef725879ca7448a3451`。
- 对照的本地冻结上游对象：`c6c9bd70aedc503c003110dae10a83ad0bb891d8`。
- 归因：`upstream-existing`。冻结对象中同样存在 IPTV 初始化不等待播放器、直连源没有请求代次、回看迟到结果可覆盖新请求的路径。
- 本批只修订用户仓库，未执行 fetch、merge 或上游同步。

## 首个无效状态

1. `onInitPlayerState` 调用 `_initIptvPlayer` 后立即返回，`setPlayer` 的异步错误绕过外层初始化事务，页面又在真实源打开前标记成功。
2. IPTV 直连路径绕过 `PlayerController` 的 `_loadEpoch` 栅栏；换房或新回看开始后，旧任务仍有机会继续创建或附着播放器。
3. 回看切换只等待 `setPlayer` 构造返回，没有等待 `VideoController.initialization`。旧回看迟到成功/失败也可写入新回看的页面状态。
4. 节目点击无法区分“已真正开始”和“已被更新请求取代”，因而可能发布错误的回看成功提示。

## 修订

- 初始 IPTV 路径现在等待 `_initIptvPlayer`，并将房间请求代次传入完整启动过程。空房间标识或空地址明确结束加载并保留失败状态。
- `PlayerController.setDirectPlayer` 将直连源纳入标准 `_loadEpoch` 所有权，创建后等待 `VideoController.initialization`，换房/替换后的迟到结果返回空结果。
- `LivePlayController` 新增独立 IPTV 播放代次。每次直播直连或回看切换都是 latest-wins；换房和控制器关闭会立即使旧事务失效。
- 成功、失败、加载和 `loadError` 由当前事务一次提交；迟到的旧成功或旧异常只返回 `false`，不改写新请求。
- `startCatchUp` 返回可观测的布尔结果。`VideoController` 对被取代的开始返回 `superseded`，释放 single-flight 状态但不发布假成功或假失败提示。
- 丹幕停止是 IPTV 清理步骤；其异常单独记录，不反向污染已打开的媒体源。

## 回归证据

### 定向检查

- `test/iptv_playback_transaction_test.dart`：新增 7 项，覆盖启动等待、拒绝/异常、新旧请求竞态、迟到旧异常、空身份/空地址及初始直连接线。
- `test/video_source_commit_listener_test.dart`：新增“被取代的回看不发布假成功”。
- 直接定向：`iptv_playback_transaction + video_source_commit_listener + player_load_fence` 共 **37/37 PASS**。

### 最终联合门禁

`tool/local_ci.ps1 -Scope Focused -Analyze -SkipPubGet` 覆盖：

- IPTV 直连事务、节目点击、节目单布局与 URL 策略；
- 播放器请求栅栏、画质/线路事务、播放恢复与发现取消；
- 静态资源、依赖锁、Kotlin 配置及仓库审计。

结果：

- Flutter 联合回归 **205/205 PASS**。
- Flutter analyze：**No issues found**。
- 质量记录：`local-artifacts/build-records/20260912T064517072Z-quality-focused.json`。
- 门禁中真实 ADB 命令：**0**。

## 验收边界与剩余工作

- 本批是源码与确定性测试修订，没有构建 APK/Windows 包、安装、操作手机或发布。
- 提供方通用 M3U 回看元数据、真实 IPTV 网络/解码、从回看返回直播、Android/Windows GUI 候选仍待续。
- A1-05/A3-04 保持 RUN；宏观保持 **20 PASS / 33 RUN / 9 NR，42 组未闭环**。

## 回滚

本批不涉及 schema、用户设置、数据迁移或安装包。若需回滚，反向本批提交即可；现有数据与已安装候选不受影响。
