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
