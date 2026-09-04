# 共享 Android 实机轮转

## 当前任务覆盖规则（2026-09-05）

用户已暂停三个任务轮转。本次完整验收使用 `tool/run_android_device_test_turn.ps1 -NoRotation -CommandLine '…'` 直接执行本项目的串行设备步骤，保留唤醒、常亮恢复、前台校验和失败清理。网络 ADB 在线先测 Android，离线改测 Windows；不等待其他任务交棒，也不操作其他应用。恢复共享实机安排时再使用下面的默认租约流程。此开关只改变调度，不代表绕过设备检查。

国外平台可在同一包装器中调用 `tool/android_foreign_recording_smoke.ps1 -Platform twitch -ExerciseStreamSelection`，完成画质/线路选择与短录，结束后恢复代理默认值。录制器独立选择录制画质，短录通过不代表它继承了播放器选择。

同一台 Android 手机同时服务三个 Codex 任务。所有会读取或改变实机运行状态的测试按固定顺序串行：

| 代号 | lane | 任务 |
|---|---|---|
| A | `biliroaming` | 哔哩哔哩模块 |
| B | `xhs` | 小红书模块 |
| C | `purelive` | Pure Live |

正常逻辑顺序固定为 `A → B → C → A`。同一时刻只有一个 lane 持有文件租约；一轮命令结束后自动记录结果并交给下一 lane。预期 lane 已提交活动请求时，后续 lane 始终排队，不会越过，因此三个任务不会并发触摸、安装或重启同一部手机上的应用。本轮没有实机步骤时，当前 lane 应通过自己的包装器提交显式 `-Pass`。若预期任务崩溃或消失且 120 秒内没有活动请求，协调器会记录 `graceSkip` 后放行下一个已经排队的 lane，避免另外两个任务永久等待；这不是由其他任务冒充被跳过的 lane，其后仍按循环状态继续交棒。

## Pure Live 调用

Pure Live 的实机命令统一由仓库包装器进入 `purelive` lane：

```powershell
.\tool\run_android_device_test_turn.ps1 `
  -CommandLine '.\tool\android_ui.ps1 -Validate'
```

播放、弹幕、音频模式往返、系统画中画恢复以及 CPU/PSS/帧时间证据使用同一个可重复冒烟脚本，并放在一个 C 轮次内执行：

```powershell
.\tool\run_android_device_test_turn.ps1 `
  -CommandLine '.\tool\android_runtime_smoke.ps1' `
  -TimeoutMinutes 30
```

同一台手机同时出现 USB 与网络 ADB 时，脚本优先选取唯一网络 transport；出现多个手机或多个网络 transport 时必须传入 `-Serial`，脚本拒绝猜测目标设备。默认证据写入 `local-artifacts/diagnostics/android-runtime-smoke-<时间>`，不会进入 Git。音频模式切换使用 UI 状态轮询完成串行确认，不用固定短延时连续点击，避免把尚未完成的第一次切换误判为第二次恢复。

需要把安装、仅重启 Pure Live、测试和证据采集合并成一个有边界的测试轮次时，把这些命令放进同一个 `-CommandLine`。包装器会等待 A、B 完成本轮，再独占设备执行 C，最后把下一轮交回 A。

共享协调器位于：

```text
%USERPROFILE%\Documents\Codex\shared-device-test-rotation\Invoke-DeviceTestTurn.ps1
```

本轮没有 Pure Live 实机步骤时也要显式交棒，避免 B lane 完成后等待 C：

```powershell
.\tool\run_android_device_test_turn.ps1 -Pass
```

队列状态和历史位于 `%LOCALAPPDATA%\Codex\device-test-rotation`，不进入 Git，也不得写入配对码、Cookie、Token、账号或其他凭据。

## 一轮的边界

- 一轮只覆盖一个明确场景或一组不可拆分的连续步骤，默认等待上限 180 分钟。
- 安装、`force-stop`、启动、触控、旋转、UIAutomator、截图、`logcat -c`、`settings`、`appops`、MT、LSPosed 操作均属于实机轮次。
- 只操作本任务的包、进程和数据。Pure Live 不清理或重启哔哩哔哩、小红书模块及其宿主。
- 手机重启、全局 ADB 重置、LSPosed 重启、设备级数据清理不属于普通测试轮次。
- 租约只解决设备互斥。取得轮次后仍先核对明确的 IP ADB serial 与前台包名；前台不是 Pure Live 时停止本轮的坐标输入。
- K90 Pro 在 10 分钟后自动锁屏且没有密码。Pure Live 包装器会在取得 C 轮租约、执行任何真实设备命令之前统一调用 `tool/wake_android_device.ps1 -StayAwake`：优先选择唯一 IPv4 ADB transport，发送唤醒和 `dismiss-keyguard`，复核系统 Keyguard，并仅在当前测试租约内启用供电时常亮；`finally` 总会调用 `-ReleaseStayAwake` 恢复用户原有的 10 分钟锁屏策略。具体 UI/运行冒烟仍保留每次观察前的二次唤醒复核，因此长队列等待或无线 ADB 慢响应不会把锁屏页当成应用界面。
- 国外平台只在 C 轮内临时运行 `tool/android_configure_proxy.ps1 -Mode LocalClash`：脚本先确认主机 `127.0.0.1:7897` 正在监听，再建立同端口 ADB reverse，按语义和有界滚动定位设置项，同时启用应用层与播放器代理。测试命令必须用 `try/finally` 配对调用 `tool/android_restore_proxy_defaults.ps1`；清理脚本复核两个开关均关闭并移除 reverse，日常状态始终回到 DIRECT。不得依赖旧设备坐标或把代理状态遗留给日常使用。
- Twitch/Soop 的标准录制回归使用 `tool/android_foreign_recording_smoke.ps1`，由它负责上述代理启用与 `finally` 清理；该脚本本身仍须作为 C 轮包装器的 `-CommandLine` 执行。
- 新设备尚未建立网络 ADB transport 时，可仅在当前 PowerShell 进程临时设置 `PURELIVE_ADB_PAIR_ENDPOINT`、`PURELIVE_ADB_PAIR_CODE`，以及可选的 `PURELIVE_ADB_CONNECT_ENDPOINT`。唤醒脚本先完成一次配对、从 `_adb-tls-connect._tcp` 自动发现同一 IP 的连接端口，再继续唤醒检查；协调器状态与历史只保存脚本命令，不记录配对码。完成当前命令后立即清除这些临时环境变量。
- 各任务不得在租约外执行 `adb kill-server`。测试器取得 C 轮后会确认进程级 ADB server；若命令明确返回“daemon 未连接且命令尚未送达”，只重启 server 并有界重试一次，不对离线、超时或语义失败盲目重放触控。
- 命令成功、失败或抛出异常时都由包装器释放文件租约。测试失败也会交棒，避免后续任务长期排队。
- 没有实机步骤的代码审查、静态分析和本地单元测试不占用手机；重型构建仍单独遵守 `BUILD_POLICY.md` 的资源互斥规则。

## 轮转证据

共享历史按 NDJSON 记录 lane、退出码、完成时间、下一 lane 和循环编号。Pure Live 的测试报告还应记录：

1. 本轮场景与目标包版本；
2. 使用的明确 ADB serial；
3. 前台包守卫结果；
4. 命令退出码及证据路径；
5. 交棒后的 `nextLane`。

轮转记录只证明设备未被三个任务同时操作，不替代功能断言、截图、日志、性能采样或发布门禁。
