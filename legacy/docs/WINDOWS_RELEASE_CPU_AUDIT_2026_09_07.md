# Windows Release 候选与空闲 CPU 验收（2026-09-07）

## 本轮结论

当前累计源码已构建为 **Windows x64 Release / unsigned，3.1.8+4121**，完成隔离便携启动、运行库实际加载、空关注页可见/最小化/恢复三段采样与正常退出。**CPU现象在产品Release仍存在**；不是只凭Debug样本推断，也尚未获得根因或性能PASS。3.2.0及全平台发布继续暂缓。

手机按明确 `-s 192.168.1.2:5555` 只读确认 `25102RKBEC / myron`，当前前台仍为哔哩哔哩。保留该任务状态，没有启动/停止手机应用、覆盖安装、MT、LSP、Root或设备设置操作。

## 构建与产物

- 干净源码 **`2d8e4e0c67ba14edbc2cf886140b9f26315602d1`**；相对此前 fadd5bdb，应用、插件、Windows runner、资源和依赖未变化，后续只有审计文档。
- 实际命令：`tool/build_local_release.ps1 -Target WindowsX64 -Configuration Release -SkipQuality -SkipInstaller`。资源记录的 command 字段当前省略了 SkipInstaller；本轮明确只生成便携ZIP，旧setup文件不属于本候选。
- 复用 af88a032 的 **1522/1522 + 42/42、analyze无诊断**，以及之后仅历史数量标签批的 **43/43 / analyze无诊断**。记录分别为 `20260907T015733844Z-quality-full.json`、`20260907T022905531Z-quality-focused.json`。本轮没有重新全测，不把已有证据改称为本提交的新门禁。
- 构建记录 **`20260907T042439198Z-build-windowsx64-release.json`**：成功、635.246秒，Flutter Windows构建333.7秒；结束仍有2个活跃重型进程，未终止其他项目工作。既有 CMake CMP0175、MSB8028 和 LNK4078 警告保留。
- ZIP：`local-artifacts/3.1.8-4121/PureLive-3.1.8-4121-windows-x64-portable.zip`，**74,603,787 B**，SHA-256 **`2C5E181D1369F2A23C7427CB227C3093F1FF8EC0328DED53CDE0730362FF0911`**。
- 1306个ZIP条目，检查未含AppData；exe、Flutter DLL及3个VC++运行库均存在。exe报告 `3.1.8+4121`，SHA-256 `5118BA0B33ADF34A8F898EABB792D5D84E70FAF899ED0AF6830DC4B08312810C`。
- 旧便携ZIP、setup及Windows元数据/校验清单先复制到 `local-artifacts/candidate-archive/windows-pre-2d8e4e0c/`，逐一核对哈希。没有改旧安装器、Android候选、版本或远端发布。

## 隔离启动和测量条件

ZIP独立解压到 `local-artifacts/candidates/windows-release-2d8e4e0c/`，使用新实例 `--instance=cpu_release_2d8e4e0c`；仅该实例的PLUGIN_SUPPORT中预置空 `{}`，避免导入主实例插件偏好。没有使用用户主资料，截图为“无已开播直播间”的空关注页。

**PID78232** 的模块清单实证 `msvcp140.dll`、`vcruntime140.dll`、`vcruntime140_1.dll` 从该解压目录加载，三者版本14.52.36615.0。Flutter DLL SHA-256 `8F989F1255D14D8521C20D8869484E65A9661DAB5E90DC00B7DA97490EAED220`，与[上一轮最小Release模板](WINDOWS_CPU_CONTEXT_AUDIT_2026_09_07.md)完全相同；stderr同样报告Impeller OpenGLESSDF。

每段由 `sample_windows_runtime.ps1` 采样60秒、5秒间隔、排除首个CPU基线，24逻辑核归一化。可见/恢复阶段开始前截图核对同一静态页面；最小化后工具明确返回 `window is minimized`。采样期间不再抓取截图/无障碍树、不启用Dart CPU profiler。屏幕元数据为RTX5090 Laptop、3840×2400@200Hz，另有Oray虚拟显示驱动；GPU未采样。其他任务仍可能运行，窗口遮挡没有连续监控，不把跨轮百分比差额归因为单一代码因素。

| 条件 | 实际秒数 | CPU均值 / P95 | 工作集MiB 首→末 | Private MiB 首→末 | 句柄 首→末 | 线程 首→末 |
| --- | ---: | --- | --- | --- | --- | --- |
| 空关注页可见 | 60.594 | 1.2079% / 1.4447% | 202.5391→202.4570 | 496.1328→495.9883 | 1151→1144 | 158→154 |
| 同实例最小化 | 60.687 | 0.0166% / 0.0428% | 203.1992→203.2070 | 496.9531→496.9531 | 1146→1145 | 153→153 |
| 恢复空关注页 | 60.567 | 1.3300% / 1.4859% | 195.1641→195.1602 | 490.5430→488.4336 | 1167→1147 | 157→152 |

三段均13/13响应，未观测到进程退出。短期静态内存/句柄未持续上升；该结论不覆盖播放、录制、长时缓存或资源释放。该版本仍有 `Problem getting monitor brightness` 日志；没有把其直接认定为CPU根因。

## 原生采样尝试及未完成部分

已安装Windows Performance Recorder/Toolkit；先查WPR未录制，再用唯一实例 `PureLiveCPU78232_20260907` 请求30秒CPU采样。**启动立即返回 `0xc5585011`：Failed to enable the policy to profile system performance**。没有进入30秒录制阶段，没有ETL或函数级热栈；再次查该实例为未录制。未另行提权、调整系统策略或停止其他跟踪会话。

因此下一步采用**隔离runner的进程内消息计数/耗时仪表**，先解释模板可见性负载，再对产品插件/窗口路径做有依据的对照；不继续把百分比重复采样当根因证明，不在产品加入猜测性消息延时。当前Release候选也可复用于后续实际播放/录制、窗口与多平台验收，避免重复构建同输入。

所有3段采样、构建和解压会话都已终止。通过标题栏关闭→退出确认正常结束后，PID78232查询消失；没有遗留本轮WPR会话。证据目录 `local-artifacts/windows-release-2d8e4e0c-20260907/` 包含candidate/process、运行库加载清单、CSV/summary、stdout/stderr、WPR失败状态和cleanup记录。Windows W0-04/W3-02仅追加子项证据，仍为RUN；42个历史未闭环大项不变。
