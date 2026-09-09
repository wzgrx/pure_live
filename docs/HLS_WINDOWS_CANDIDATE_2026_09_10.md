# 累计 Windows 候选与设置持久化验收（2026-09-10）

**Windows Debug 构建、独立归档及有限 GUI 冒烟通过；全量原生验收与稳定版发布仍待完成。** 本轮没有应用源码修改，不把成功启动等同于播放、录制或全平台验收通过。

## 候选身份

- 干净源码 `2fb471d3e8c2841f25acb05221033f11f46e731c`，相对[Android fb106ed6 候选](HLS_ANDROID_CANDIDATE_2026_09_10.md)仅增加文档提交，业务代码一致。
- Windows x64 Debug，版本 `3.1.8+4121`，未签名、未安装、未发布。执行 `tool/build_local_release.ps1 -Target WindowsX64 -Configuration Debug -SkipQuality -SkipInstaller`。
- ZIP `local-artifacts/candidates/windows-2fb471d3/PureLive-3.1.8-4121-windows-x64-debug.zip`，142,623,043 B，SHA256 `80C68840818C7371517E2FB84590D5A480CCA63C2830EEBEBD88F96CFB7470B2`。
- EXE SHA256 `FD07986243E276D5C244AA0E2F20BD413CCAEE8C6AB97C3CCEA0E4FE5B622529`。元数据、构建记录、归档核验和独立 runtime 同目录保留；包内双语资源与源码逐值一致。
- 旧 windows-f3de664a 独立 ZIP 保持原哈希与 141,375,729 B。测试数据仅在新 runtime 的 `AppData/acceptance_2fb471d3_20260910`，预置空插件偏好避免导入主实例设置。

## 构建环境失败与定点恢复

首次构建在 CMake 配置阶段失败，分类为 `environment-or-data`：增量缓存的 `MSVC_REDIST_DIR` 指向已不存在的 `14.52.36615`，当前实际目录为 `14.52.36725`。应用尚未编译，根因不属于业务源码。

保留修改前后 CMakeCache，只执行 `cmake -U MSVC_REDIST_DIR` 后重新配置，验证新路径的 msvcp140/vcruntime140/vcruntime140_1 三库存在。其余增量目录保持，未升级工具链；`windows/CMakeLists.txt` 三库门禁与仅 Release 分发规则原样保留。CMake 成功缓存会跳过重新搜索，参见 [find_path 文档](https://cmake.org/cmake/help/v4.2/command/find_path.html)。

首次辅助脚本因 PowerShell `$home` 只读变量名失败，尚未运行 CMake；更名 `$sourceHome` 后执行成功。首次构建和辅助脚本失败记录均保留，未用成功重试覆盖。证据目录 `local-artifacts/windows-candidate-20260910/` 含 refresh-redist.ps1、两份缓存、redist-refresh.json 与归档脚本。

| 阶段 | 资源记录文件（local-artifacts/build-records） | 秒 | 峰值 CPU | 峰值工作集 B | 结束活跃重型进程 |
| --- | --- | ---: | ---: | ---: | ---: |
| 首次构建失败 | 20260909T181204375Z-build-windowsx64-debug.json | 30.413 | — | — | — |
| 定点重配置 | 20260909T181410430Z-windows-redist-rediscovery.json | 7.696 | 0% | 7153811456 | 0 |
| Debug 构建成功 | 20260909T181707782Z-build-windowsx64-debug.json | 150.569 | 79.94% | 8709873664 | 2 |
| 独立归档核验 | 20260909T181830430Z-windows-archive-2fb471d3.json | 13.324 | 14.03% | 7475822592 | 0 |

各重型阶段串行互斥。构建后的进程计数仅为采样结果，不直接归因为泄漏或本任务所有。保留 CMP0175、Firebase PDB LNK4099、MSB8028 等警告，没有修改门禁或静默警告。本次 `-SkipQuality` 复用逐批定向证据，**没有执行当前累计提交完整发布门禁**。

## 实际 GUI 结果与边界

以 `--instance=acceptance_2fb471d3_20260910` 启动独立包；窗口 1280×720，首次进程 26828，第二次 29188。Windows UI 使用 Computer Use，未通过直接修改数据文件伪造设置变更。

1. 首页空关注正常显示；导航和可见区域无明显溢出。无障碍树含全部、18 个直播站点及 IPTV，OPENREC/TTing 名称已进入树；水平条未同时显示所有站点，不外推每站 UI 已验。
2. 录制中心可打开，九个状态筛选及空任务文案正常；进入录制设置、滚动与超时弹窗正常。
3. 默认超时 15s；通过弹窗选择 30s，页面更新。正常退出并确认原进程结束，再启动同一实例，页面仍显示 30s，弹窗也选中 30s：**跨进程持久化通过**。
4. 通过界面恢复 15s 并观察页面更新，随后正常确认退出。两次测试进程均结束；最后恢复值未再做第三次重启验收。

操作后即时截图偶尔处于弹窗淡出动画；随后重新观察终态，未据过渡帧判定失败。一次旧无障碍索引报缓存不可用后重新观察并使用截图坐标，属于工具状态，不记应用缺陷。未触发清理、登录、主实例数据迁移或实际 GUI 录制；归档原始 `native_ui_verified=false` 保留，其含义仍是完整原生交接未验，本节另记有限冒烟。

## 手机与剩余工作

02:10+08 只读预检确认 25102RKBEC/myron、5555 在线、息屏 Dozing、Pure Live 未运行，前台是其他维护应用；本轮后续再次明确指定 5555 核对型号和代号一致。未接管手机前台，未唤醒、安装、Root/MT 操作、切换网络或更新模块。Android 累计候选仍未安装。

宏观台账继续为 20 PASS / 32 RUN / 10 NR，42 组未闭环；不是 42 个缺陷，也不是完整开发目标的工时估算。本轮仅增加候选和设置证据，不更改整组状态。后续优先在设备测试窗口进行保留数据的同签名覆盖安装及候选原生验收；Windows 继续累计候选播放/实录/多任务、未完成平台与边界验收，再进入全量质量及 3.2.0 正式交付。相关录制源码/原生证据见 [控制器审计](HLS_CONTROLLER_PREFETCH_AUDIT_2026_09_10.md)。
