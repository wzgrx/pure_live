# Picarto 累计 Android 候选（2026-09-07）

候选源码 `2006c04403c6a7e93a6c0bfc7edabc5d8f1a9024`，构建时 tracked files 干净。包含 [Picarto 接入](PICARTO_ADAPTER_AUDIT_2026_09_07.md)、[录制卡片布局](RECORDER_PAGE_LAYOUT_AUDIT_2026_09_07.md)及此前累计修复。版本仍为 3.1.8+4121；这是本机 Debug 候选，不是 3.2.0 发布。

## 测试失败与闭合

- `9fc0aff9` 为国外录制包装器增加 Picarto 参数，同时补静态输入合同检查。该检查只证明参数/标签接受范围，不证明整个设备流程成功。
- 完整门禁记录 `20260907T070640247Z-quality-full.json`：全库 analyze 无诊断（292.2 秒），完整测试 **1581 通过、1 失败**。失败是 `recording_platform_contract_test.dart` 的固定内置平台列表漏加 Picarto；同文件的逐 CDN 惰性游标用例通过。全流程 1084.646 秒包含资源排队。
- 构建因此在 Gradle 编译前终止，失败记录 `20260907T070640502Z-build-androidarm64-debug.json` 的 outputs 为空。这次失败未生成新 APK。
- `2006c044` 只在上述测试的期望列表增加 `Sites.picartoSite`。与 `9fc0aff9` 比较，`lib/`、`assets/`、依赖及 Android 源码均无变化。
- 定向复验 **2/2 通过**，记录 `20260907T070926272Z-quality-focused.json`，88.809 秒。复用未变应用输入的分析和其余测试证据；不描述为一次完整 1582/1582 全绿运行。
- 补跑此前因失败未执行的真实接口检查：**42/42 通过**，记录 `20260907T072113566Z-android-candidate-interface-probes.json`，290.899 秒含排队，结束活跃重型进程 0。仅本次子进程设置 HTTP/HTTPS 代理到用户 Clash 127.0.0.1:7897，结束恢复环境变量，未改全局或手机代理。该旧平台探针集不替代 AcFun/Picarto 专项证据；Picarto 的真实生产 HTTP 探针沿用接入审计中的 06:42:51Z 记录。

## 构建与回滚

基于以上分层证据，以 `build_local_release.ps1 -Target AndroidArm64 -Configuration Debug -SkipQuality` 构建候选，没有再次重复完整回归。正式稳定版的最终完整门禁仍待执行。

记录 `20260907T073059906Z-build-androidarm64-debug.json`：成功，565.127 秒含排队，Gradle 327.0 秒；workers 16，结束活跃重型进程 0。监控范围内峰值 CPU 70.69%、工作集 13,447,208,960 B；它包含被监控的重型进程，不等于应用运行性能。增量状态保留、缓存配置启用；日志未证明本次 Configuration Cache 复用，不能把启用等同命中。Firebase 插件 KGP 未来兼容警告仍保留。

| 项目 | 结果 |
| --- | --- |
| 包名 / ABI | com.mystyle.purelive / arm64-v8a |
| versionName / 基础 build / Manifest code | 3.1.8 / 4121 / 6121 |
| 文件大小 | 287,023,145 B |
| SHA-256 | `41223C88A81A62F54AC790EF5878D9C136EB725B3807D9E4A55B273C15BB8B4D` |
| 完整性 | 1262 个 Flutter assets；16 个原生库；APK 与 ELF LOAD 16 KB 对齐通过 |
| 签名 | 本机 Debug，未正式签名或发布 |

当前输出为 `local-artifacts/3.1.8-4121/PureLive-3.1.8-4121-android-arm64-v8a-debug.apk`；按源码归档到 `local-artifacts/candidates/android-2006c044/` 并重新核对哈希。旧已安装候选的回滚 APK 保存在 `local-artifacts/candidates/android-af88a032/`，SHA-256 `EFD5A76AE8B4A8823B95FC50087EEBC5999690C7E796E39F9A41FFFF82C130E8`。同一版本产物目录还有历史平台包；目录列表不代表本轮重建了所有文件。

## 设备与测试工具边界

本轮明确 `-s 192.168.1.2:5555` 只读复核 25102RKBEC / myron；构建前后前台均为 `com.bilibili.app.in/tv.danmaku.bili.MainActivityV2`。未安装、启动、停止或输入，未改代理、常亮、Root/LSP、MT 或 ADB 配置。手机仍是旧 af88a032 候选；新包的启动、配置迁移、布局和 Picarto 原生验收均待补。

脚本预检发现以下尚未修复的问题，记录在 `local-artifacts/android-candidate-9fc0aff9-20260907/smoke-harness-preflight.json`：

1. `android_recording_smoke.ps1` 的 `Select-PlatformTab` 仍依赖硬编码序号，漏 Picarto，也不适配用户隐藏/排序。提取真实函数、用假的 UI 观察函数执行后，Picarto 在任何观察前抛出缺序号错误；证据 `local-artifacts/android-candidate-2006c044-20260907/selector-reproduction.json`，设备命令 0 次。
2. 运输层错误恢复会调用未传 Serial 的唤醒脚本、改写目标后重放命令；应固定已核验目标，失败后停止，避免输入结果未知时重放。
3. UI dump 的前台丢失分支会自动重新启动应用并重试；应停止当前轮次而不是抢回前台。
4. 国外平台代理配置脚本还需按每次输入复核前台、检查 reverse 所有权和清理边界。

这些是自动化工具缺口，不据此推断产品播放或录制失败。修复并通过离线 fake-ADB/语义夹具前，不运行整套国外录制脚本。后续优先修复工具边界，再在手机空闲时保留数据覆盖安装并验证迁移和原生功能；不卸载、不清数据、不重启手机。历史 42 个未闭环验收大项与另 16 个未注册平台组均未因本次构建而自动关闭。
