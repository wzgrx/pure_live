# Android Debug 资源缺失与构建路径（2026-09-06）

## 已验证事实

- 应用提交 `7ba627fd` 完整质量门禁通过：1162/1162 测试、42/42 接口检查、analyze 80.0 秒无诊断。记录 `20260906T002133716Z-quality-full.json`，307.489 秒。结束时共享机器活跃重型进程计数为 2，不宣称机器空闲。
- 网络 ADB 在线，按用户平台优先级转入 Android；未操作或安装旧候选。
- `20260906T002937323Z-build-androidarm64-debug.json`：构建阶段生成 APK，但完整性检查失败，原文 `Android APK is incomplete; required entry is missing: assets/flutter_assets/AssetManifest.bin`。总耗时 471.552 秒，结束活跃重型进程 0。
- APK 仅包含 6 个 assets 条目：3 个 Flutter JIT 快照/内核和 3 个 MLKit 模型；翻译、版本、图片与 AssetManifest 均缺失。构建中的 Flutter debug 资源目录也只剩 3 个文件，故不是仅校验规则不适配。
- 构建日志 `20260906T002142689Z-androidarm64-debug.log` 同时记录 Kotlin 增量缓存异常：`this and base files have different roots`，路径为 C: Pub 缓存与 P: Android 工程。

## 路径分析与处理

从 SUBST `P:` 调用原 `flutterw.ps1` 时，仓库字符串长度短于 80，跳过了 Android 同盘短路径分支。映射实际指向 C: 长目录；不同调用入口使 Flutter 输出记录在物理路径与 P: 别名间切换。

固定 SDK 3.47.0 的 `build_system.dart` 在写入新输出后，按字符串集合删除不再匹配的旧输出（954–964 行）。现存 debug 资源 stamp 声明 1262 个输出，但这些输出实际缺失。结合构建产物与路径切换，旧输出别名清理是资源消失的主要解释；本次不修改 SDK。

- 新增纯函数 `Resolve-PureLiveSubstPath`，先归一化 SUBST/嵌套映射，再选择 Android junction 与 Windows/test SUBST。保留现有映射，不重建全量缓存。
- 8 项路径断言覆盖物理路径、SUBST、嵌套映射、大小写、其他盘、根路径、普通循环与增长循环；包装器语法检查通过，测试加入本地质量入口。构建策略静态检查通过。
- 只隔离 6 个已声明 AssetManifest、但对应文件实际缺失的 `debug_android_application.stamp`；原记录保留在 `local-artifacts/diagnostics/android-assets-7ba627fd/`。未删除 build、Gradle、SDK 或全部 Dart 缓存。

## 下一验证

从归一化入口重建同一应用源码 Android Debug，仍须通过原 APK 资源/ABI/版本/16 KB 对齐门禁，再进入安装与实际观看录制验收。构建脚本修复不改变应用源码，复用上述完整质量证据。缺失资源候选未安装，3.2.0 未发布。

## 实际重建结果

1. 首次归一化后的构建 `20260906T003623654Z-build-androidarm64-debug.json` 仍失败于 `:app:compressDebugAssets`。进一步读取固定 SDK 的 `trackSharedBuildDirectory` 证实：除单节点 stamp 外，跨配置的 `outputs.json` 也在新输出生成后按路径字符串清理旧产物。此前 P: 配置 `051c50784328b16ebb0abf7cfd79423b` 切换到物理路径配置 `241c164f2276c6b4dcf2715b34197897` 时，别名指向同一文件；`.last_build_id` 已更新，而资源再次只剩 3 个。补充证据为 `shared-output-cleanup.json`。不把第一次归一化构建计为成功。
2. 保持归一化后的同一配置、不再切换别名，增量重建通过原有门禁：`20260906T003956314Z-build-androidarm64-debug.json`，提交 `c252e522`，154.683 秒，结束活跃重型进程 0。应用源码与已通过完整门禁的 `7ba627fd` 一致。
3. APK **286,927,827 字节**，SHA256 `1bf557676633f4b0f3e23058d8e8ec2835c8a86726ed72f800326ff3b4fda99f`；包名 `com.mystyle.purelive`，开发版本 3.1.8，基础 build 4121 / Manifest code 6121，唯一 arm64 ABI，16 个 ELF 的 LOAD 对齐 ≥ 0x4000、ZIP 16 KB 对齐通过。
4. Flutter 资源 **1262 个 / 202,005,087 字节**，原资源清单、翻译、版本等门禁全部通过；没有手工向 APK 补资源。最新日志未再出现 Kotlin 跨盘根目录错误，但保留 firebase_auth/core 的旧 KGP 迁移警告。

产物在 `local-artifacts/3.1.8-4121/PureLive-3.1.8-4121-android-arm64-v8a-debug.apk`；同目录旧 Release APK、Windows ZIP/安装器均不属于本轮构建。进入 Android 候选实机验收，不是正式 3.2.0 交付。
