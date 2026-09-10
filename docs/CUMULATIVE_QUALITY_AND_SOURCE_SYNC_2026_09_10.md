# 累计质量门与源码同步（2026-09-10）

## GitHub 同步

用户本轮明确要求每次修改同步 GitHub。此前源码仅在本机连续提交，正式 3.2.0 发布暂缓不应导致源码也积压。读取实际远端后，本地 master 领先 337 个提交、落后 0；本轮使用普通快进 push，将 `origin/master` 从 `73da6db24bdcf778eb49e4983ab5b3464c2ad945` 更新到 `5910890b56ccfa98943e1bee0d809c635e95b163`，`ls-remote` 核对一致，随后 ahead/behind 为 0/0。

没有合并 upstream、force-push、创建 tag、上传 APK 或发布 3.2.0。原始同步记录在 `local-artifacts/candidates/android-5910890b/github-sync.json`。规则已在 `9108ca5c87105256dc367959458dd04dddcfb7a7` 单独提交并推送，远端 SHA 已再次核对。AGENTS.md 增加持续规则：每批修改通过相应验证后提交并推送 origin，核对远端 HEAD；源码同步与原生验收、签名、正式发布分开。推送失败保留本地工作并检查差异，不强推覆盖远端。

## 本轮完整门禁

业务基线为干净 `5910890b56ccfa98943e1bee0d809c635e95b163`，实际执行 `tool/local_ci.ps1 -Scope Full`，并未仅把先前 142 项定向结果称为全量通过。

- 构建策略、路径、录制/代理/前台守卫的离线夹具与设备 UI map 通过；这些夹具实际 ADB 调用数为 0。
- `pub get --enforce-lockfile` 成功，未升级依赖；Secrets 审计回归 6/6、CC 探针回归 5/5。
- 仓库完整性审计覆盖 4,630 个已跟踪文件、2,559 个文本文件：0 错误、2 警告。警告为已审查公共 localhost TLS 测试私钥白名单和 30 处 empty-catch 清单，不是 APK 包含该测试私钥的结论。
- 原生依赖预取、10 个 Gradle 文件的 Kotlin 审计通过。
- 全库分析运行 710.8 秒，仅报告一处 `invalid_override`：`test/video_processor_lifecycle_test.dart:272` 的 `_NativeLifecycleFixture.start` 缺少生产 `FFmpegManager.start` 已有的 `bool hlsPrefetch = false`。
- **门禁失败；完整 Flutter 测试及真实公开接口探针尚未运行，Android 构建尚未开始。** JSON 中 test_paths/test_assets 是计划配置，不是这些步骤已完成的证据。

门禁记录 `local-artifacts/build-records/20260910T085758020Z-quality-full.json`，1,012.690 秒，峰值 CPU 68.96%、工作集 14,539,251,712 B。末尾记录活跃重型进程 2；下一批资源守卫确认其他 Java 活动后排队，没有为消除该计数停止其他任务。

## 测试夹具修复

来源 `fork-regression`：生产参数由 `5688d18c6779326a984f57584b86b26ef7d51f4f` 加入，而该夹具最后修改 `0c2fe8f48ab5ce9213a9ff94e4e4d4da35a1c483` 未同步接口。此次补齐默认参数；夹具只模拟转换/合并生命周期，不执行真实 HLS 预取，因此没有给它伪造网络行为。应用业务、数据 schema、录制实现均不变。

定向生命周期测试 **11/11 PASS**，修订文件执行 `dart analyze --fatal-infos` 得到 **No issues found**。记录 `local-artifacts/build-records/20260910T091251268Z-native-fixture-signature-repair.json`：852.87 秒（含资源排队），峰值 CPU 46.36%、工作集 13,865,984,000 B，收尾重型进程 0。测试覆盖损坏输入阻止 remux、合并超时/取消、迟到开始、实际 writer 退出前保留归属、自然完成不覆盖旧 MP4、原始片段保留等；使用生命周期替身，不是新增真实媒体证据。另执行规则/工作流静态审计：5 个指令文件、10 个工作流、4 个负向控制，0 错误。此前完整门禁的失败记录保留；这 11 项不代替尚未执行的完整套件及公开接口。

## 候选与设备

- 已按近期 170 个变更文件涉及的功能补充 Android 验收计划：继承 61 项，增加 17 项，合计 78 项全部 not-run。覆盖目录/刷新/用户管理、niconico 注册及真实解码/录制、会话归属、多画面重建和搜索退出；这是候选场景数量，不是全部剩余目标数。
- 计划及待用归档辅助脚本在本机忽略目录 `local-artifacts/candidates/android-5910890b/`。还没有该候选 APK；脚本只做语法检查，尚未运行。下一轮提交变化后须按新的实际源 SHA 更新候选身份，不把这个目录名当成已构建证明。
- 2026-09-10 08:45:24 UTC，本机 DESKTOP-F2H984F 只读核对 `-s 192.168.1.2:5555`，返回 25102RKBEC / myron / Android 17。除此之外没有读应用数据、切前台、唤醒、安装、重启或改 Root/LSP/ADB。
- 已询问 Pure Live 前台测试窗口，尚待回答；身份在线不等于已取得合适前台。后续安装仍需当前前台/录制状态、签名和一致备份核验，保留现有数据。

## 下一步

先在修复后的干净提交上继续完整质量门，解决新出现的失败后再构建、核验、归档累计 Debug APK；源码每批同步 origin，不等正式发布。双端原生验收、参考平台扩展、长时运行及全平台 3.2.0 仍未完成。历史 62 组中仍 42 组未闭环，另外 7 组参考平台未注册，不将两种计数合并或换算进度百分比。
