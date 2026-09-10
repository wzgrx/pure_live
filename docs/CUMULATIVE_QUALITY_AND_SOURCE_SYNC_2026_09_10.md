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

## 第二轮完整门禁及分页/引擎夹具修订

干净 `a2b539cb2e63c9a1b685da4e417ee909b8739f56` 的完整门禁实际结束：全库 analyze **No issues found（202.1 秒）**，完整 Flutter 套件 **4069 PASS / 3 FAIL**。仓库审计 4631 个已跟踪文件、2560 个文本，0 错误、2 个既有警告。记录 `local-artifacts/build-records/20260910T092336871Z-quality-full.json`：518.441 秒，峰值 CPU 54.13%、工作集 14,765,363,200 B，结束活跃重型进程 0。因 Flutter 失败，公开接口阶段未执行，APK 构建未启动。

两文件单独复现为 **46 PASS / 3 FAIL**，同样三项失败，记录 `20260910T092550200Z-quality-focused.json`。不是把全库并发或随机时序猜作失败原因。

### 来源和修订范围

1. **CC 移动分页的两项测试准备错误**：`81b68544` 的夹具在宿主宽视口创建真实 `AreaRoomsBinding`，然后调用 `checkAndNotifyLayoutChange(false)` 并立即加载。`4b80212d785d5a1121f4e64f2194733e5766db5a` 已将布局提交延迟到 120 ms 防抖和当前请求结束；旧夹具的“移动端”仍实际按桌面切页，第二页拿到 21–40 而非 1–40。修订在构造之前设置 400 / 900 的真实测试视口，并显式断言实际分页模式；保留固定 30 行请求、全部尾部、页宽切换、刷新失败回滚和分类身份断言。采用 WidgetTester 视口是宿主移动布局模拟，不是 Android 原生证据。
2. **默认引擎恢复的前置状态错误**：旧测试在 initialize 后、从未 play 时调用自动切换，再假设回退引擎已安装。`9014bfa80c9099e818fa12b9ad71c32edee2363a` 的播放意图栅栏会退休这种缺少播放请求的候选。修订先播放 previous，再切 fijk，明确验证回退引擎和 previous 源已成为当前状态，之后进入 next 房间；仍要求默认引擎只打开 next 一次、回退只打开 previous、旧实例各销毁一次。没有删掉原本要保护的单次打开与旧 decoder 回收断言。

分类为 **fork-regression（测试夹具与维护分支契约脱节）**。业务源码、依赖、资源、数据 schema 与版本不变；不撤销布局事务或播放意图栅栏，也不把夹具修订宣传成手机分页/解码 Bug 修复。回滚只需恢复这两份测试及对应文档，不涉及用户数据。

### 夹具调度问题与最终验证

第一次 Widget 夹具修订在虚拟时钟里直接等待 Dio；锁定 Dio 5.11.1 的拦截器使用 `Future(() async ...)` 事件任务，缺少 pump/runAsync 时首个 CC 用例停在等待，其余五文件完成 266 项。只结束已核对完整命令行的本轮 Flutter 测试进程树，保留失败记录 `20260910T094321871Z-paging-engine-fixtures-repair.json` 及 `fixture-repair-cancellation.json`；没有停止其他 Java 构建，也没有把这次结果计为通过。该记录的 analysis=true 是请求参数，实际未到达分析。

修订为 `tester.runAsync` 承载夹具 HTTP 事件循环，最终六文件 **273/273 PASS**，两份修订文件 `dart analyze --fatal-infos` **No issues found**：CC 分类、音频模式/引擎切换、布局分页事务、目录池、owned source 和播放器错误恢复。保留相邻暂停/退出/过期候选、布局切回/关闭、连接预检迟到和游标事务用例；不是仅重跑三条失败。

最终记录 `local-artifacts/build-records/20260910T094740146Z-paging-engine-fixtures-final.json`：243.842 秒，峰值 CPU 78.86%、工作集 16,447,500,288 B、结束重型进程 0（监控为该时段重型进程汇总）。两文件 SHA-256 分别为 `E9CFB04B371DDFA9F6E9C4F4C6F8B829611F7B959B164EE0825FEC06FB38EAAA` 和 `EB0C07B05DA039E54503B80B7543D3485CC4B02FD6083C8BE129EBFF55C37B14`。记录 sourceCommit 为文档头 `71d8c340`，测试在上述未提交修订上执行，文件哈希绑定实际输入；随后提交并同步。完整回归须在新干净提交上重新执行，273 项不替代全库门禁。

同批 [Issue 增量审查](ISSUE_AUDIT_2026_09_10.md) 已先在 `71d8c340345bdd8860f4bb5fa65b0faec5a869a4` 推送并核对 origin；最新 #858/#859 保留未复现，手机仍无新增操作。待候选按下一次实际源 SHA 重绑定后继续完整门禁，旧 a2b539cb 目录只是失败/修订证据与未执行归档辅助脚本，不是已生成 APK。
