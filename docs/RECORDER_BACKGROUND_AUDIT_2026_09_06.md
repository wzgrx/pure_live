# Android 独立录制后台保障审计（2026-09-06）

## 状态

实现、Android arm64 Debug 编译及关闭后台播放后的锁屏独立录制通过，仍是开发候选；系统中断和完整原生生命周期矩阵未完成，不作为 3.2.0 稳定版发布证据。构建来自 `205b75f4` 基线加本轮未提交修改，不能仅用基线 SHA 代表 APK 源码。

## 改动与已修问题

- 新增独立 `dataSync` 前台服务和持续通知；录制持有独立 CPU/WiFi 锁，显式绑定共享 AudioService 保留 Dart engine，不改变播放的后台开关。
- Dart 使用身份租约共享服务。启动失败阻止录制入队；显式重试恢复，自动重试不反复触发受限服务启动。
- 任务停止、关闭与系统中断先等待实际录制/收尾完成，再持久化和释放最后租约；取消请求返回不是原生任务已结束的证明。
- 异常服务销毁与系统超时均进入有界收尾阶段，避免通知中断后立刻解绑 engine。正常停止在 Service.onDestroy 后回复。
- 修复持久化写入进行中时 flush 提前返回：等待旧写入与后续 dirty 快照，避免最后解绑丢失终态；补可控两阶段写入测试。
- 修复 native 停止失败后缓存仍显示启用，后续任务跳过服务启动的问题。
- `background` 错误阶段加入持久化解析白名单，重载后保持故障分类。
- 首次实际 Kotlin 编译发现 `Unresolved reference 'Listener'`：接口声明位于 companion 而调用者引用类作用域；移到类作用域后构建通过。静态合同检查不替代编译。

## 两阶段引擎交接

`setActive(false)` 等本代前台服务结束后回执，但保留 AudioService 绑定；Dart 等状态队列完全结束且没有 owner，再发送 `releaseIdle`。此期间到达的新 true 复用既有绑定，包括已受理但尚未连接完成的绑定；连接回调按当前连接对象身份隔离，不使用旧录制代次判断新绑定。Native 只在 IDLE 接受释放确认，非空闲状态忽略旧确认；15 秒丢失确认兜底不作为交接成功证据，系统中断原 45 秒硬上限保持不延长。

- 新增可控顺序测试：false 未结束不释放、false 中新 owner 保持引擎、新 owner 又取消后仅确认一次空闲；38 项定向回归通过，记录 `20260906T032215977Z-quality-focused.json`。
- 新候选编译/完整性通过：`20260906T032710407Z-build-androidarm64-debug.json`，183.615 秒，结束活跃重型进程 0。APK 286,942,215 字节，SHA-256 `DB3F94514F667D52ABF18AA913777C0D16EFA5978BB8CCDD7BA068A974704EB5`；覆盖下述旧候选同名路径。

## Android 实际独立录制

- 中断试跑 `android-recording-smoke-20260906T112756339` 没有 summary，不计通过。恢复后走“停止录制”正常收尾，确认录制服务已消失，不先强杀活跃写入。
- 初次完整试跑 `android-recording-smoke-20260906T113631094` 仅 `playbackNotForeground` 失败。UI 证实用户后台播放原值 true，播放服务与录制服务同时前台，此记录不证明独立保障，也不把用户配置判成代码故障。
- 关闭后台播放后的重测 `android-recording-smoke-20260906T114324671/summary.json`：所有已执行断言通过，未执行画质/线路切换仍为 SKIP。30 秒黑屏期间同一文件从 2,097,152 增至 15,204,352 字节，增长 13,107,200 字节；进程存活，录制服务前台、录制 CPU 锁存在、AudioService 仅绑定而非前台。
- 正常录制停止后的独立快照确认 RecorderForegroundService 已消失且录制 CPU 锁释放；这组证据采集早于测试末尾 force-stop。前台恢复播放后 AudioService 再次前台属观看行为，不判为录制泄漏。
- 实际 MP4 19,658,331 字节，51.010667 秒，音视频流均存在。另执行全文件严格解码（`-xerror -err_detect explode`），退出 0、错误日志 0 字节，记录 `strict-decode-result.json`；媒体 SHA-256 `7EF649468B2CA5CB60AC8656A37A074DD9E2C4A5F3E7C842204C1CFF3A5C97DD`。
- finally 已恢复后台播放原值 true，并再次读取 UI checked=true；恢复前后 XML 位于初次完整试跑目录。外层常亮恢复完成，录制监控已清理。

## 验证证据

- 两阶段交接最终状态：`local-artifacts/build-records/20260906T035430893Z-quality-focused.json`，78 项相关测试通过，analyze 188.3 秒无诊断；包含脚本独立服务/活跃锁解析夹具。

- 最新状态：`local-artifacts/build-records/20260906T031813407Z-quality-focused.json`，修复后 75 项相关回归全部通过，analyze 76.0 秒无诊断；覆盖输出生命周期、签名租约、轮询、用户意图和后台服务。

- `local-artifacts/build-records/20260906T030618343Z-quality-focused.json`：相关 73 项测试与 analyze 通过；该记录早于最后持久化屏障/失败缓存修复。
- `local-artifacts/build-records/20260906T030902026Z-quality-focused.json`：最后修复后的 35 项定向测试通过，包括原生 drain、最终 false 前 Hive 状态、受控 in-flight 写入。
- 编译失败记录：`local-artifacts/build-records/20260906T031253928Z-build-androidarm64-debug.json`，退出 1，错误层为 Kotlin 编译。
- 修复后构建：`local-artifacts/build-records/20260906T031528104Z-build-androidarm64-debug.json`，退出 0，139.671 秒，结束活跃重型进程 0。
- APK：`local-artifacts/3.1.8-4121/PureLive-3.1.8-4121-android-arm64-v8a-debug.apk`，286,932,531 字节；SHA-256 `429F181CF5D6350B48A2D67EC5CE5703A5761EA14390808299C255DBB67CCCB0`。
- 包 `com.mystyle.purelive`，版本 3.1.8，基础 build 4121，Manifest code 6121；arm64，16 个原生库、1262 个 Flutter 资源、16 KB ELF/ZIP 对齐通过。不是正式签名稳定包。

## 未完成的关键验收

### 无 Activity 服务中断（2026-09-06）

`android_recording_smoke.ps1 -Interruption timeout|serviceStop` 使用独立结果分支，要求同时启用 Activity 销毁和独立后台检查。先确认黑屏录制增长，再注入；只验证中断收尾，不冒充正常停止、前台恢复或用户重试通过。

- `android-recorder-timeout-20260906T124946057/smoke/summary.json`：10 项中断断言通过，562 ms 时已观察到录制服务/CPU锁释放及新 MP4；严格完整解码退出 0、错误日志为空。SHA-256 `9697B66797899CEC7D1C8527048F41408B6E40D73A59F1CEEFACF208C7474341`。
- `android-recorder-service-stop-20260906T125304021/smoke/summary.json`：10 项中断断言通过，764 ms 时观察到同样终态；严格完整解码退出 0、错误日志为空。SHA-256 `FA2648488BFC98ACFC3F0C0E99A8CF26B5E8D55E1AC2929F821CE7F346D38CEF`。
- 两次均在销毁 Activity、后台播放关闭、黑屏录制已增长后注入，结束无 FATAL，最终进程/锁清理通过，原后台播放 true 与常亮策略恢复。记录根目录均在 `local-artifacts/diagnostics/`。
- serviceStop 后再次冷启动，`record-center-restarted.xml` 确认卡片仍为“失败”、最近失败阶段“后台保障”、中断说明和“重试”按钮；录制时长 21 秒、6.23 MB。冷启动持久化已验证，尚未点击重试。菜单不含录制入口，实际入口是底部“录制中心”标签；首次菜单定位失败不计产品失败。
- 后续手动重试完成：`android-recorder-retry-20260906T130105452` 的 `before-retry.xml` 核对同一失败卡片，点击“重试”后 `active.png` 显示新录制 43 秒/14.75 MB；正常停止后 `after-stop.xml` 的目标甜星kitty卡片为“已停止”、69 秒/22.97 MB。服务及 CPU 锁快照确认释放。新成片 24,081,597 字节、69.693667 秒，严格解码退出 0、错误日志为空，SHA-256 `BBA95B6435DE9376A5A397A1E21A8C67DBDA10D861C24E1480618BBA5B9006D5`。
- 重试脚本原退出 1：录制页持续更新导致 UIAutomator 定位停止按钮时 idle timeout。未把该脚本计为整体 PASS；后续以新截图和前台守卫完成正常停止，汇总 `recovered-acceptance.json` 明确保留原失败与补验。没有强杀活跃录制。两次文件匹配中首次未限定日期找到两个历史文件，收窄至当天唯一文件后才复制，未删除历史成片。
- 以上是目标服务回调注入，不是 Android 累计时限计时测试。采样在 15 秒兜底窗口之前，但服务/锁释放与成片存在本身不证明原生 idle ACK 的精确顺序；该证据边界保留。

### Activity 销毁扩展（新候选真机复验通过）

- Debug 增加仅 shell/system 可调用的 `android.permission.DUMP` 生命周期探针；执行实际 Activity.finish、服务 timeout 回调或 stopSelf。Release source set 不注册接收器；回调注入不等于系统六小时计时验收。
- 旧候选 `20260906T041417166Z-build-androidarm64-debug.json` 编译通过。实际记录 `local-artifacts/diagnostics/android-recorder-activity-finish-20260906T120630398/smoke/summary.json` 确认 Activity 已销毁且黑屏录制增长 12,845,056 字节，但 `playbackNotForeground` 失败；此次已核实后台播放关闭，区别于前面的用户配置场景。正常停止释放录制服务与锁，用户后台播放原值已恢复。
- 源码定位到 hidden/paused 后 detached 会令延迟暂停条件失效。新增直接 detached、hidden/paused→detached 两例在旧实现均失败（期望暂停 1 次、实际 0 次），记录 `20260906T042905769Z-quality-focused.json`。修复将 detached 纳入非可见状态，并保留快速重建合并、后台播放设置和原有恢复 token。
- 原生 HTTP 从 Activity 字段改为 `NativeHttpPlugin` 引擎级所有权；只在引擎分离时销毁通道/线程池，避免录制保留引擎但 Activity 销毁后丢失 Twitch HTTP 回退。未改变请求白名单或代理设置；该条件下 Twitch 网络重连仍待实际验证。
- 同批修复 RecorderController.onClose 最终持久化进入统一 `_flushPersist` 屏障，避免解绑早于最终快照完成。
- 最终 Dart 定向 49 项和 analyze 通过：`20260906T043335089Z-quality-focused.json`。该证据不替代新候选 Activity 销毁或系统中断验收。
- 新候选 Android arm64 Debug 编译通过：`20260906T044010250Z-build-androidarm64-debug.json`，Gradle 311.3 秒，APK 286,923,129 字节，16 个原生库及 1262 个 Flutter 资源完整性、16 KB 对齐通过。此包覆盖同名旧候选。
- 新包实际复验 `local-artifacts/diagnostics/android-recorder-activity-finish-20260906T124124846/smoke/summary.json` 通过全部已执行断言。Activity.finish 回执及任务栈消失均确认；30 秒黑屏期间同一文件增长 12,058,624 字节，录制服务前台/CPU锁存在，AudioService 非前台。重建 Activity 恢复观看，正常停止录制后服务和 CPU 锁消失（早于末尾 force-stop）。
- 成片 20,839,141 字节、57.951667 秒，音视频流均存在；严格完整解码退出 0、错误日志 0 字节（同目录 `strict-decode-result.json`），SHA-256 `81A8BB6F2E65E3599D22383842646809E3F501696EDAE3933D60EA5641A85B53`。设置 XML 确认原后台播放 true 已恢复，包装器退出 0、常亮恢复 false；画质/线路切换本轮未执行，不作为新增覆盖。

1. 两阶段交接的代码、Dart 可控顺序与编译已完成；无 Activity 时的原生交接故障注入仍待集成验证。空闲释放已确认之后到达的全新请求不属于此交接窗口。
2. 关闭播放后台保活后的锁屏增长/独立前台服务/CPU锁/正常释放、Activity 真正销毁及重建已通过；更多平台和较长连续录制仍待覆盖。
3. 系统超时/意外服务销毁的无 Activity 回调注入与成片已通过；serviceStop 冷启动错误分类和显式重试通过。精确 idle ACK 顺序、timeout 冷启动分类仍待补足。
4. 原生收尾窗口最多 45 秒；超长封装可能超出窗口。该上限不是成功收尾证明，需保留中断片段恢复能力。
5. 当前保障覆盖已启动录制及其收尾，不宣称应用完全空闲后仍能无限后台轮询/自动启动；受系统前台服务限制的启动应真实显示失败。
6. 全平台正式发布门禁、设备完整矩阵、版本与说明同步继续由主验收入口跟踪。
