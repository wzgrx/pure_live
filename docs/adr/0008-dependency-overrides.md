# 0008 依赖覆盖（dependency_overrides）的去留

- 状态：已接受
- 日期：2026-09-27

## 背景

根 `pubspec.yaml` 有 18 个 `dependency_overrides`。依赖诊断（[diagnosis/07-dependencies.md](../rewrite/diagnosis/07-dependencies.md)）建议把其中 9 个“越过 Flutter SDK 锁定”的覆盖直接删除。

第 3 阶段建立 workspace 后做了实验（Flutter 3.47.5）：

- 全部删除：解析失败。workspace 成员用的 `test 1.32.0`（最新版）需要 `test_api 0.7.14`，而 `flutter_test` 锁定 `test_api 0.7.12`。
- 只保留 `test_api`：能解析，但 8 个包降到非最新版：`_fe_analyzer_shared` 108→103、`analyzer` 14.4→13.3、`cli_util` 0.6→0.4.2、`dbus` 0.8→0.7.15、`file_picker_linux` 2.0.1→2.0.0、`material_color_utilities` 0.13.1→0.13.0、`nm` 0.6→0.5、`source_gen` 4.3→4.2.4。

保留这些覆盖时，旧应用 `flutter analyze` 无问题，全量测试通过（4954 个通过、90 个跳过）。

## 决定

1. **保留 9 个越过 SDK 锁定的版本覆盖**。删除它们会违反宪法原则 3（依赖用官方最新稳定版），`test_api` 还是 workspace 成员使用最新 `test` 的前提。
2. **升级 Flutter 时逐个复查**：临时删掉这些覆盖运行 `flutter pub get`，解析结果已是最新版的就删掉。
3. **路径和 git 覆盖按替代进度移除**：
   - `media_kit`：长期保留，自维护分支（ADR 0002）。
   - `fvp`：随许可证整改移除（ADR 0006）。
   - `flutter_inappwebview_android`、`share_handler_android`：本地兼容补丁，在 v4 用 `live_platform` 替代对应功能后移除。
   - `screen_retriever`：git 固定提交，Windows 多窗口功能迁到 v4 后移除。
4. **兼容覆盖**：`hooks`、`code_assets` 在 media_kit 的 Native Assets 钩子随上游升级验证后再决定；`xml`、`wakelock_plus` 在依赖它们的上游包放宽约束后删除。
5. 新增任何覆盖都要在 `pubspec.yaml` 注释里写明原因，并在本文件登记。

## 备选方案与放弃理由

- **按诊断建议删除 9 个覆盖**：8 个包落后于最新版，而且会让 workspace 成员无法使用最新 `test`。
- **成员包降级 `test` 以配合 `flutter_test` 的锁定**：同样违反“用最新”，也只解决了 `test_api` 一项。

## 影响

- 越过 SDK 锁定意味着这些版本组合没有经过 Flutter 官方测试，风险由 CI 门禁（`tool/gate.sh --all`，含旧应用全量测试）兜底。
- 第 8 阶段删除旧应用后，根 `pubspec.yaml` 只剩 workspace 声明，这些覆盖随之按上面的规则重新评估。
