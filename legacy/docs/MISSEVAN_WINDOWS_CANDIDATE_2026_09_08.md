# Windows 累计候选与 MT 只读连通检查（2026-09-08）

## Windows 构建与归档

- 干净源码：`f92aa1a7842ec2148aaee50458ff0280975aa1cb`；业务内容包含猫耳应用接入、分类收藏身份修订及此前 TLS 录制修订。
- 实际命令：`tool/build_local_release.ps1 -Target WindowsX64 -Configuration Debug -SkipQuality -SkipInstaller`。版本仍为 `3.1.8+4121`，unsigned Debug，不是正式 3.2.0。
- 构建记录：`local-artifacts/build-records/20260907T183312638Z-build-windowsx64-debug.json`，成功，439.706 秒；Flutter 编译 152.5 秒。峰值 CPU 49.13%，工作集 13,263,683,584 B；记录结束时活跃重型进程数为 1，不报告为全部归零。
- 归档：`local-artifacts/candidates/windows-f92aa1a7/PureLive-3.1.8-4121-windows-x64-debug.zip`，141,375,456 B。
- SHA-256：`47B9B39D1193A17624FAC1A2871CB0D9CD6BA44F0E44948733932CDF70A053F1`；输出与归档重新计算一致，元数据和资源记录一起保留。
- ZIP 可打开，含 1,303 项，核对 runner、FFmpegKit DLL 和版本资源存在。构建保留现有 CMake CMP0175 / MSB8028 警告。
- 复用[猫耳接入审计](MISSEVAN_APPLICATION_INTEGRATION_AUDIT_2026_09_08.md)的 201 项定向、静态分析及双协议原生短录证据；本批没有重新执行完整发布门禁，也尚未启动此候选完成可见 UI 验收。

旧 fadd5bdb Windows Debug ZIP 已在构建前归档并核对历史 SHA；旧候选没有被当作新版本原生证据。

## 用户补充的 MT APK MCP

本次按用户明确设备请求完成只读预检，未唤醒、切换前台、安装、输入或修改模块：

- 指定 `-s 192.168.1.2:5555`，transport 为 device；型号 `25102RKBEC`、代号 `myron` 一致后才执行 Root 身份检查，返回 `uid=0(root)`。
- 现有转发为该设备 `tcp:18787 → tcp:8787`，没有重建转发或变更 ADB 服务。
- 通过本机 HTTP JSON-RPC 调用 `initialize`、`notifications/initialized`、`tools/list` 成功。服务报告 `MT APK MCP 0.1.0`，协商返回协议 `2025-06-18`。
- 已读取 APK 列举接口实际输入 schema；本轮未列举/打开 APK，也没有创建编辑会话、补丁、重打包或签名。
- 普通 shell 的 `command -v lspctl` 未输出路径，仅说明当前 PATH 未发现该命令；没有据此判断 LSP 未安装，也没有更改开发者模式。
- 上述为直接只读 ADB/HTTP 预检，未进入设备 UI 测试包装器，不构成有租约的应用实机验收证据。后续安装及 UI 操作仍走仓库包装器与前台守卫。

Android 最新候选仍为[7aaecb8e](MISSEVAN_ANDROID_CANDIDATE_2026_09_08.md)，本轮没有覆盖安装。MT 的开放能力不是本项目必须使用 APK 补丁或 LSP 的理由；优先维护可复现源码构建。

## 下一步与剩余范围

复用新 Windows 候选，在独立实例和独立偏好目录中执行猫耳目录、分类收藏、搜索能力提示以及真实播放/录制 UI 验收；手机切换窗口仍待确认。历史 42 个未闭环验收大项、14 组未注册参考平台和最终发布门禁保持，不从构建成功推导整体完成比例或交付日期。
