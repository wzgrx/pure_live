# Android 50 次进退房与资源恢复审计（2026-09-13）

## 范围与结论

本轮先复核直播页、播放器、弹幕、计时器和应用内悬浮播放的生命周期所有权，再在用户指定的 REDMI K90 Pro Max 上执行 A7-04 的首轮完整原生压力循环：

- 固定进入热门页第一个哔哩哔哩直播间；
- 每轮从视频呈现切换到纯音频，核对持久的“纯音频模式”状态；
- 系统返回首页，并在用户已开启应用内悬浮播放时显式关闭悬浮会话；
- 共执行 50 次，每 5 次采集 PSS/RSS、堆、线程、FD、Socket、DMA-BUF、GPU FD 与 SurfaceFlinger layer；
- 第 50 次结束后等待 52 秒，跨过 `PlayerManager` 的 45 秒空闲硬释放窗口，再采集最终回落状态；
- 每次输入前核对 Pure Live 是精确 `topResumedActivity`，并检查进程未重启、最终首页存活及 FATAL/ANR。

50/50 轮全部完成，50 次音频切换都只提交一次有效输入，应用内悬浮会话 50/50 次关闭。播放器相关线程、Codec 线程、FD、Socket、DMA-BUF、GPU FD 和 BLAST layer 在循环采样中均为平台值或稳定窄幅值；空闲释放后 FD 从循环态 300 降至 262、DMA-BUF 从 53 降至 25。最终 PSS 比预热首页基线高 16,684 KB，RSS 高 17,012 KB，线程高 3，均处于本工具的回收边界内，无 FATAL、ANR、Flutter 错误、超时或 OOM。

当前证据来自一个 Android 17 设备、一个 Debug APK、一个哔哩哔哩房间和视频→音频→退出组合。Release、其他平台、视频恢复、全屏/PiP/后台及更长轮次仍需对照，因此 A7-04 从 `NR` 更新为 `RUN`，暂不提升为 `PASS`。

## 生命周期源码复核

本轮复核的主要路径：

- `lib/modules/live_play/controllers/live_play_controller.dart`
- `lib/modules/live_play/controllers/player_controller.dart`
- `lib/modules/live_play/controllers/danmaku_controller.dart`
- `lib/modules/live_play/controllers/timer_controller.dart`
- `lib/player/core/player_manager.dart`
- `lib/core/common/web_socket_util.dart`

当前实现已具备与本次循环直接对应的资源所有权：

1. `PlayerController` 在替换房间视频控制器前先等待旧控制器 `destory()`，随后 `dispose()`，并用加载代次阻断迟到结果覆盖新房间。
2. `LivePlayController.onClose()` 递增房间/播放代次，释放 PiP 与亮屏 Worker、弹幕恢复器、礼物/批量弹幕定时器、队列、TabController 和流；普通退出时停止弹幕并释放带标签的 Timer/Danmaku/Player 子控制器。
3. 用户开启应用内悬浮播放时，路由退出会按设计保留会话。本轮没有把这条保留路径误判成泄漏，而是通过真实悬浮关闭动作结束所有权，再等待首页稳定。
4. `DanmakuController.stopDanmaku()` 通过串行队列断开当前连接；`onClose()` 释放设置/过滤 Worker 并清空消息门。`TimerController.onClose()` 取消结束订阅、停止并销毁计时器。
5. `PlayerManager.close()` 先使旧播放意图失效，退出时执行 `softStop()` 并关闭源传输；移动端默认保留空闲播放器 45 秒供快速再次进房，随后 `_releaseIdlePlayer()` 进入硬释放。本轮最终样本等待 52 秒，覆盖该所有权窗口。

源码复核与原生数据没有定位出需要修改产品代码的确定性泄漏；本批修改集中在可重复测试与证据完整性。

## 测试工具与失败驱动修订

初始工具提交 `614625735c0e1deb40f64bb884213020ac59c9f4` 增加：

- `tool/android_process_resource_metrics.ps1`：解析 `/proc/PID/status`、`dumpsys meminfo`、FD 软链接、逐线程 `comm` 与 SurfaceFlinger layer；
- `tool/test_android_process_resource_metrics.ps1`：覆盖资源文本和线性趋势解析；
- `tool/android_room_resource_recovery.ps1`：身份、Root、APK 哈希、房间循环、资源边界、致命日志与最终清理一体化门禁；
- `tool/local_ci.ps1`：固定运行纯资源解析回归。

早期诊断轮次暴露的测试工具问题均保留证据并逐项修订：

- 厂商 `dumpsys meminfo` 中的空诊断行与逐线程名称格式先被解析器拒绝；
- 瞬态控制栏中的动作提示曾被误当作持久纯音频状态；
- 应用内悬浮播放保留旧会话，使“新房间”实际重开保留会话；
- 静态坐标输入在一次循环中没有落到已就绪控件，旧汇总还在中途异常时丢弃前三轮成功记录。

最终工具提交 `1d29b9cb17ae325116115562a2cb4800a4c01367` 在每次音频输入前解析精确、可点击且启用的“切换到纯音频模式”动作。只有持久状态仍证明输入未生效时才保存前后 UI/截图并重试，成功后不会再次点击；最多三次，同时持续写回已完成轮次与样本，异常路径额外保存 PID 过滤日志。最终 50 轮中没有触发重试，所有轮次的 `audioAttempts=1`。

工具门禁：

- PowerShell AST 解析通过；
- Android 进程资源解析回归通过；
- `device_ui_map.json` 校验通过：4 profiles、170 points、39 sequences；
- 产品源码从已安装提交 `039f8ff3` 到测试提交 `1d29b9cb` 之间只有文档与工具变化；此前同产品源码的音频模式相邻回归为 **42/42 PASS**，记录在 `local-artifacts/build-records/20260912T145930955Z-quality-focused.json`。

## 候选与设备身份

- 设备：`25102RKBEC / myron / Android 17`
- Root：`su -c id` 返回 `uid=0(root)`
- 应用：`3.1.8+6121`
- 已安装 APK SHA-256：`0F28A5F0C61A1794F72E905A1E3C0CFA015FE412B9BB50FCAFFB6D21A7D4CD7F`
- APK 对应产品提交：`039f8ff37ef05d668ebfb462e34512755afd392f`
- 原生测试工具提交：`1d29b9cb17ae325116115562a2cb4800a4c01367`
- 原始汇总：`local-artifacts/diagnostics/android-room-resource-recovery-20260912T233823956/summary.json`
- 执行时间：2026-09-12 23:38:24 ～ 2026-09-13 00:16:40

本轮没有重新安装、清理数据、重启手机/adbd、切换 Wi-Fi、改变调试授权或 ADB 端口，也没有更新 Root/LSP/模块。

## 50 轮操作结果

| 指标 | 结果 |
|---|---:|
| 完整轮次 | 50 / 50 |
| 纯音频有效输入 | 50 / 50 均为一次 |
| 应用内悬浮会话关闭 | 50 / 50 |
| 进程重启 | 0 |
| 进房耗时 min / avg / max | 2,747 / 2,963.6 / 3,424 ms |
| 音频状态确认 min / avg / max | 8,544 / 8,767.0 / 9,874 ms |
| 返回并关闭悬浮 min / avg / max | 13,731 / 13,923.2 / 14,667 ms |
| 单轮总耗时 min / avg / max | 40,922 / 41,493.2 / 43,429 ms |

音频状态确认耗时包含唤出控制栏、UIAutomator 读取、原生命令和持久状态确认，不等同于用户看到图标变化的单帧延迟。

## 资源平台与空闲回落

| 指标 | 预热首页基线 | 第 5 轮 | 第 50 轮 | 空闲 52 秒最终 | 最终相对基线 |
|---|---:|---:|---:|---:|---:|
| TOTAL PSS KB | 686,646 | 759,397 | 772,940 | 703,330 | +16,684 |
| TOTAL RSS KB | 858,888 | 931,448 | 945,512 | 875,900 | +17,012 |
| Native Heap KB | 67,596 | 98,164 | 105,648 | 81,128 | +13,532 |
| Graphics KB | 44,864 | 70,972 | 71,976 | 45,940 | +1,076 |
| 线程 | 67 | 70 | 72 | 70 | +3 |
| 原生播放器线程 | 0 | 0 | 0 | 0 | 0 |
| Codec 线程 | 3 | 3 | 3 | 3 | 0 |
| FD | 274 | 300 | 300 | 262 | -12 |
| Socket FD | 20 | 20 | 20 | 20 | 0 |
| DMA-BUF FD | 25 | 53 | 53 | 25 | 0 |
| GPU device FD | 1 | 1 | 1 | 1 | 0 |
| Activity / ViewRoot | 1 / 1 | 1 / 1 | 1 / 1 | 1 / 1 | 0 / 0 |
| BLAST layer | 1 | 1 | 1 | 1 | 0 |

每 5 轮样本的线性拟合为：PSS `+221.19 KB/轮`、RSS `+235.893 KB/轮`、Native Heap `+134.982 KB/轮`、Graphics `+11.447 KB/轮`、线程 `+0.019/轮`；原生播放器线程、Codec、FD、Socket、DMA-BUF、GPU FD 和 BLAST layer 的拟合均为 `0/轮`。PSS/堆存在小幅高水位增长和波动，但第 20～35 轮已有回落，且最终跨过空闲释放窗口后回到有界基线附近；后续 Release 长轮次继续判断是否形成更长平台期。

## 日志与清理

PID 过滤的 5,000 行日志中：

- FATAL EXCEPTION：0
- ANR：0
- `E/flutter`：0
- `PlatformException` / `TimeoutException`：0 / 0
- `OutOfMemoryError`：0

日志仍出现 Android 媒体栈的 `AIBinder_linkToDeath`、`PlayerBase::setVolume() error -19`、OpenSLES 配置和 ColorUtils 警告；本轮没有伴随状态失败、进程重启或资源计数扩张。Release、另一播放器内核和不同平台复跑时继续对照这些原生警告。

脚本最终强制停止 Pure Live、恢复 MIUI 首页为前台，并把 stay-awake 从临时 `7` 恢复原值 `0`。所有目标 ADB 操作均显式使用 `-s 192.168.1.2:5555`。

## A7-04 后续

1. 在同一设备的精确 Release 候选上复跑，比较 Debug 与 Release 的 PSS、Native Heap 和警告频率；
2. 将循环扩展到哔哩哔哩以外的平台，并覆盖纯音频→视频恢复、横屏、系统 PiP、应用后台与快速切房；
3. 增加 100～200 轮长测和 Perfetto/native heap 对照，确认 PSS 与堆的长期平台；
4. 对媒体栈重复警告按播放器内核/音轨切换拆分，确认是否来自上游插件、设备实现或调用时序；
5. 在录制并行、网络恢复和温升场景下复跑资源边界。

宏观账本更新为 **20 PASS / 40 RUN / 2 NR**，仍有 **42** 组历史验收未闭环。本批 Astra Light 使用 0 次。
