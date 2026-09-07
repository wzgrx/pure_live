# 录制暂存 Android 候选与实机前置守卫（2026-09-07）

## 本批结论

包含内部 TS 逐包刷新、HLS 完整响应暂存和尾片舍弃提示的 Android arm64 Debug 已构建。
**尚未安装本候选、尚未复验原手机录像损坏，也未发布 3.2.0。**
[TLS 握手停止红项](RECORDING_TLS_STOP_AUDIT_2026_09_07.md)保持未修复。

## 构建证据

- 源码干净提交：`c442380c41e36e2391a9d93f8c4dbb44263cc10a`。
- 命令：`pwsh -NoProfile -File tool/build_local_release.ps1 -Target AndroidArm64 -Configuration Debug -SkipQuality`。
- 记录：`local-artifacts/build-records/20260907T151104615Z-build-androidarm64-debug.json`。
- 耗时 294.532 秒；Gradle 252.1 秒，16 workers；峰值 CPU 68.35%、工作集 15,920,979,968 B，结束活跃重型进程 0。
- 版本 `3.1.8+4121`，Manifest code `6121`，包名 `com.mystyle.purelive`；16 个原生库、全部 ELF LOAD 至少 `0x4000`、APK 16 KB 对齐和 1262 个 Flutter 资源校验通过。
- APK：287,067,886 B，SHA-256 `3CED592BFA440D40B46EB0B6DACB2B8F319CF20CE45A4265E4A8B28EFE9378B9`。
- 独立保留：`local-artifacts/candidates/android-c442380c/PureLive-3.1.8-4121-android-arm64-v8a-debug.apk`，复制后重新核对哈希。
- 复用 [提示批 126/126](RECORDING_TAIL_WARNING_AUDIT_2026_09_07.md)及[容量批 35/35](RECORDING_STAGING_LIMITS_AUDIT_2026_09_07.md)定向证据，两批有重叠，不相加；本次不是完整质量门禁。已知 TLS 红测没有隐藏。
- Firebase KGP 未来兼容警告保留；未调整依赖、SDK、版本或签名策略。

## 手机只读预检

以明确 `-s 192.168.1.2:5555` 连接并读取，型号 `25102RKBEC`、代号 `myron` 一致。
本批预检时：

- `stay_on_while_plugged_in=0`；Pure Live 没有进程，服务查询为 `(nothing)`。
- 前台为 `com.bilibili.app.in/tv.danmaku.bili.MainActivityV2`，不是 Pure Live。
- reverse 列表为空；既有 forward 为 `tcp:18787 → tcp:8787`，没有改动。
- 在唤醒、安装、启动、触控之前停止；已询问用户是否现在切换到 Pure Live。没有抢回前台或将前台变化归因为应用崩溃。
- 没有调用 MT HTTP/API，也没有检验其服务层健康；**转发存在不等于 MT MCP 已实测可用**。
- 没有手机/adbd 重启、Wi-Fi/端口/授权变更、Root/LSP/模块操作、卸载或清除数据。

本地证据：`local-artifacts/android-c442380c-native-20260907/` 的 `candidate.json`、`device-preflight.json`。
该目录中安装与录制 helper 仅已准备，未执行，不作为成功证据。
手机最近一次有安装哈希证据的版本仍是 [80b7431c](TWITCASTING_COOKIE_ANDROID_RETEST_2026_09_07.md)，不是本次候选；本次没有重读已安装 APK 哈希。

## 本地工具缺口与修订

源码核对发现原唤醒脚本选定 transport 后直接唤醒/解锁，尚未核对型号与代号；清理一律 `stayon false`，会覆盖原先非零的供电常亮配置。
本次仅修改测试基础设施：

1. 唤醒和清理均先核对目标型号/代号；不一致只读退出。
2. 进入前读取并验证常亮原位掩码，唤醒后设置前再核对未被外部改变；返回原值和本轮取得值。
3. 包装器 finally 将这些值传给同一 serial 的清理；精确恢复原值并读回，不把原值 2 等同于 0。
4. 清理发现第三方改成其他值时保留并返回失败；已恢复则幂等。不传所有权值的单独清理调用停止，不猜原值。
5. 取得常亮写入已生效但应答失败时，唤醒脚本自行尝试回滚，避免包装器尚未拿到状态而跳过清理。回滚失败明确报告，未声称能处理永久断网。

这些为读取比较后写入，不是 Android 端原子 CAS；其他操作者恰好写入同一值时，比较结果不体现所有者变更。仍需串行设备轮次和前台守卫。
本批未在真实手机写入设置，原生回归待下一次已确认的设备轮次。

## 工具验证

- 新唤醒守卫 **9/9 测试方法通过**（28.295 秒），内部包含错误型号/代号、取得与清理、0/非零位掩码、无效配置、缺少所有权、外部改值、幂等和取得应答失败回滚的子场景。
- 包装器 **8/8 测试方法通过**（23.798 秒），保留显式 serial、环境 serial、正文改写环境仍清理原目标、失败 finally，并新增原值 2 在正文成功/失败时传递给清理。
- 测试运行真实 PowerShell 脚本，但使用进程内假 adb 或假唤醒脚本；无网络/手机操作。日志为本地证据目录的 `wake-guard-tests-final.log`、`device-turn-tests.log`；首版 8/8 守卫结果单独保留，不叠加计数。
- 两个 PowerShell 文件语法解析通过，`git diff --check` 通过。未改应用 Dart/依赖，因此未重复 Flutter 全测或构建。

## 下一步

确认切换窗口后重新读取身份、前台、服务/进程和常亮状态；使用 NoRotation 包装器执行保留数据 `install -r -t`，核对首次启动前 Hive 字节和安装 APK 哈希。
随后独立代理开启/恢复往返，再进行 TwitCasting 短录、完整 A/V 严格解码和所有权清理。复用本次 APK；工具/文档变化不触发重复构建。
