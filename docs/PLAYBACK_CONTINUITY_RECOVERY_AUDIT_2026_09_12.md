# 播放连续性与有界恢复增量审计（2026-09-12）

## 范围与结论

本轮对应验收账本 **A3-06**：播放意外暂停、buffering、EOF、签名过期的有界恢复，以及用户主动暂停不被自动恢复。当前生产路径原有意外暂停宽限、buffering/视频帧停滞看门狗、签名源刷新、线路/内核回退、有限重试预算和用户暂停意图隔离；继续检查发现两个异步边界仍可能让恢复队列长期停住。

A3-06 从 **NR** 调整为 **RUN**。当前源码已对原生恢复播放命令和签名源解析建立明确截止时间，相关播放器、源所有权、缓冲、生命周期、音频与传输回归通过；精确候选也已在 K90 完成正常播放、音频往返、PiP 返回和退出清理。真实 buffering/EOF/签名到期故障注入、长时连续恢复及 Windows 客户端仍需继续，因此不记完整 PASS。

## 缺口、有效红灯与修订

稳定复现的两个缺口：

1. 意外暂停后的 `player.play()` 若因解码器或平台通道卡住而不返回，播放器生命周期队列会一直等待，既不进入后续线路/内核回退，也会阻塞后来的用户操作。
2. EOF 或签名错误触发的播放源 resolver 若一直不完成，恢复事务会停在源刷新；预取与后续实际恢复共享该操作时也会继承同一停滞。

新增两项确定性测试后，旧实现为 **0/2**：300 ms 观察窗内仍停留 media_kit，没有进入预期 fijk 回退。提交 `8a4a417c2476695c457bd9a84abb32592bdfa0c3` 完成：

- 意外暂停重申播放使用既有 `unexpectedPauseFailureGrace` 作为原生命令确认上限；超时按 `unexpected_pause_resume_failed` 进入原有有限恢复状态机。
- 新增默认 12 秒的 `sourceRefreshTimeout`，所有签名源 resolver 调用统一通过 `_resolvePlaybackSource`；超时产生类型化 `source_refresh_timeout`，随后继续既有线路/内核/同内核回退。
- 超时只释放当前恢复等待并阻止迟到结果提交，不改写用户播放意图；主动暂停、换房、关闭及恢复候选所有权继续由既有代次和栅栏管理。

## 定向质量门禁

| 验证 | 结果 |
| --- | --- |
| 两项新增恢复边界 | 2/2 PASS |
| `player_error_recovery_test.dart` 完整文件 | 116/116 PASS |
| 九个相邻播放器/缓冲/生命周期/音频/传输文件 | 129/129 PASS |
| 最终 focused CI（十文件去重） | 245/245 PASS |
| 全库 `flutter analyze` | No issues found |
| 质量记录 | `local-artifacts/build-records/20260912T131443625Z-quality-focused.json` |

相邻范围包括错误分类、media_kit/fijk 缓冲状态、owned source、查询元数据、播放生命周期协调、音频服务所有权、音频模式切换及播放源传输。最终检查 `git diff --check` 通过。

## Android 精确候选与 K90 冒烟

从干净提交 `8a4a417c` 构建 Android arm64 Debug：

| 项目 | 结果 |
| --- | --- |
| 构建记录 | `local-artifacts/build-records/20260912T131635467Z-build-androidarm64-debug.json` |
| 耗时 | 73.801 秒；Gradle 56.7 秒；结束活跃重型进程 0 |
| APK | `local-artifacts/3.1.8-4121/PureLive-3.1.8-4121-android-arm64-v8a-debug.apk` |
| 大小 / SHA-256 | 288815839 B / `DFA6C4129B97F0997F4DE1963B3AB1A8662B19D803E47FEE7351E89354E70442` |
| 包信息 | `com.mystyle.purelive`，3.1.8，manifest code 6121，arm64-v8a |
| 完整性 | 1262 项 Flutter 资源；16 个原生库；ELF LOAD 与 APK 16 KB 对齐通过 |

操作前按显式 `-s 192.168.1.2:5555` 核对 `25102RKBEC / myron / Android 17`，Root shell 返回 `uid=0(root)`。通过 `adb install -r` 覆盖安装，没有卸载或清数据；`firstInstallTime` 保持 `2026-07-21 18:07:53`，设备 `base.apk` SHA-256 与候选完全一致。安装核验：

- `local-artifacts/diagnostics/android-playback-continuity-20260912T211700-install.json`

`local-artifacts/diagnostics/android-playback-continuity-20260912T211700/summary.json` 的 **16/16** 断言通过：冷启动、Bilibili 直播间、10 条可见弹幕、清晰度/线路、音频进入与视频恢复、真实 PiP 状态、PiP 返回、致命日志检查及停止后进程释放均成立。本轮原生冒烟验证正常路径与候选可运行性，不冒充实际断流/签名到期注入。

测试结束 Pure Live 已停止，前台为 `com.miui.home/.launcher.Launcher`，`stay_on_while_plugged_in=0`。未改 Root、LSP、Wi-Fi、ADB 端口或调试授权。

## 仍需闭环

1. 在可恢复的受控输入上分别注入持续 buffering、解码帧停滞、EOF、resolver 超时和签名到期，核对恢复次数、耗时、最终线路/内核与用户可见状态。
2. Android 完成播放中主动暂停、后台/锁屏/PiP 与上述故障交叉组合，并采集长时资源和恢复日志。
3. Windows 客户端完成同组实际解码、窗口/音频组合和长时连续性；只有真实 GUI 操作需要 Computer Use 时才使用单个 Astra Light 任务。

本批 Astra Light 使用 **0** 次；没有发布 3.2.0。宏观账本更新为 **20 PASS / 37 RUN / 5 NR**，仍有 **42** 个历史大项未闭环。
