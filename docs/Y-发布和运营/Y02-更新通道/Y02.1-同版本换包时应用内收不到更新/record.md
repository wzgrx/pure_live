# Y02.1 同版本换包时应用内收不到更新提示：记录

- 日期：2026-10-08
- 执行者：Claude
- 分支和提交：本机工作区 `ai/Y02.1`（从 master `d3c219876` 开始）
- 任务书：[README.md](README.md)

## 逐条对照

A、B 都做了（维护者让按确认过的方向选最好的；B 只是保险，正常发布仍然改版本号）。

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| c1（A）发布检查 | 做了 | `tools/release/check_version.py`：`apps/pure_live/pubspec.yaml` 对比 `origin/master` 的 `assets/version.json`（Android 块）；版本号相同（除非 `--allow-same-version`）或构建号没变大都失败。PROCESS 第 11 节第 1 条写进去 |
| c2（B）比较 | 做了 | `UpdateInfo.newerThan(版本, 构建号)`：版本更新，或版本相同、构建号更大；`isNewer` 用已安装的 `appVersion`、`appBuild` |
| c2（B）跳过 | 做了 | `skippedUpdateVersion` 存 `4.0.0+5002`（`skipToken`）；旧值只有版本号时按“这个版本的所有构建号都跳过”理解（`skippedAs`） |
| c2（B）显示 | 做了 | 版本相同时新版本对话框标题、版本页“发现新版本”、关于页角标写“4.0.0（构建号 5002）”；新键 `version_with_build`（zh、en） |

## 根因

见 README：3.x 和原来的 4.x 只比版本号，`UpdateInfo.buildNumber` 读了不用（`update_feed.dart:88`）。

## 测试

- `version_page_test.dart`：`newerThan` 四种情况。
- `update_dialogs_test.dart`：同版本、构建号 +1 时弹窗、标题带构建号；跳过后存 `版本+构建号`、同一构建号不再问、再 +1 又问；旧的只有版本号的跳过值仍然跳过。原有“不再提醒这个版本”用例的存储值改成带构建号。
- `tools/gate/tests/test_check_version.py` 5 个；对现在的 master 跑脚本：版本 4.0.0+5001 和已发布相同，按预期不通过。
- `flutter test test/features/version` 28 个全过；`python3 -m unittest discover -s tools/gate/tests` 全过。
- 真机：要等下一次发布（`version.json` 换了）才看得到，发布时顺带看对话框标题。
