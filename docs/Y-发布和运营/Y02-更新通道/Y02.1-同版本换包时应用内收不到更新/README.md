# Y02.1 同版本换包时应用内收不到更新提示：以后发布一律改版本号，或让比较带上构建号

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：发布
- 来源：D-008（2026-10-02，4.0.0 覆盖发布为构建号 5001）的后果：“已安装 4.0.0 的用户收不到应用内提示”；决定里写了“以后换包一律改版本号”，但没有任何东西保证这一点。
- 旧编号：T16b.1
- 相关：决定 D-008、D-007、D-015；Y01.3（覆盖发布）；Y01（发布步骤）；A15.2（关于和版本页的“新版本”角标和状态卡）、A06.3（新版本对话框）

## 目标

以后不会再出现“发了新包，已安装的人不知道”：

1. 规则层面：发布步骤里有一道检查，新的安装包如果和 `version.json` 里现有的版本号相同就不让发布（除非维护者明确再做一次 D-008 那样的例外）。
2. 代码层面（可选，维护者定）：4.x 的比较在版本号相同时再比构建号，这样即使再次同版本换包，4.x 用户也能收到提示。3.x 的比较改不了（已经装在用户手上），3.x 用户只能靠改版本号。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11`） | 现在（文件:行） | 要做到 |
|---|---|---|---|
| 比较 | `lib/common/utils/version_util.dart:250` `isNewerVersion`：去掉 `v`、`-`、`+` 后逐段比数字，构建号不参与；`latestBuildNumber`、`latestVersionNum` 读了但不用（`:178-185`） | `apps/pure_live/lib/features/version/update_feed.dart:88` `isNewer => isNewerVersion(version, appVersion)`，`app_version.dart:34` 同 3.x；`UpdateInfo.buildNumber` 读了不用 | （B）版本号相同、构建号更大也算新 |
| 已安装的构建号 | `packageInfo.buildNumber` | `app_version.dart` 的 `appBuild`（Flutter 编译进去的 `appBuildNumber`，没有时 `pubspecBuild`），现在 5001 | 用它比 |
| “跳过这个版本” | 按版本号字符串 | `update_prompt.dart:91-93`、`:129`、`:136`：`skippedUpdateVersion` 存版本号，`compareVersions(...) != 0` 才提示 | （B）跳过要带构建号，否则跳过 4.0.0 构建号 5001 也会跳过 5002 |
| 关于页角标、版本页状态 | 版本号 | `foundUpdate`（`update_feed.dart:20`、`:23`）、`about_page.dart:146` 显示“新版本 v4.0.0”；`version_page.dart:306` `info.isNewer` | （B）同版本时显示“v4.0.0（构建号 5002）” |
| 发布检查 | 无 | 无；PROCESS 第 11 节第 1 条只是文字 | （A）发布前检查版本号确实变了 |
| 这次的后果 | — | 4.0.0 构建号 5000 的用户（发布页上午 09:16 到晚上 22:59 之间下载的）应用内看不到 5001；发布说明写了“已经装了 4.0.0 的请到 Releases 下载新包覆盖安装” | 下一次发布（新版本号）时这些人自然会收到 |

## 方案

- c1（A，规则）：PROCESS 第 11 节第 1 条已经写“换安装包就必须改版本号”；加一道机械检查：发布检查（Y01.4 建议的 `tools/release/check_apk.sh`，或单独的 `tools/release/check_version.py`）读 `apps/pure_live/pubspec.yaml` 的版本号和 master 上 `assets/version.json` 的 `platforms.android.version`，相同就失败并提示“版本号没变（D-008 以后换包一律改版本号）”；维护者确实要例外时用 `--allow-same-version`。
- c2（B，代码，可选）：
  - `UpdateInfo.isNewer`：`isNewerVersion(version, appVersion) || (compareVersions(version, appVersion) == 0 && buildNumber > appBuild)`。
  - 跳过：`skippedUpdateVersion` 的值改成 `版本+构建号`（例如 `4.0.0+5002`）；读旧值（只有版本号）时按“版本号相同且构建号任意”理解，保持兼容（这是 4.x 自己的内部设置，不是 3.x 的键，D-018 不受影响）。
  - 显示：同版本时新版本对话框标题、关于页角标、版本页状态卡带上构建号（文字走翻译，zh、en 都加）。
- 两者都做时，B 只是保险：正常发布仍然改版本号。

## 验证

- 自动测试（B）：`apps/pure_live/test/features/version/version_page_test.dart` 加“版本号相同、构建号更大算新；构建号相同或更小不算新”；`update_dialogs_test.dart` 加“跳过 `4.0.0+5002` 后，`4.0.0+5003` 仍提示”“旧的跳过值 `4.0.0` 仍然生效”。
- 自动测试（A）：检查脚本的测试（版本号相同失败、不同通过、`--allow-same-version` 通过）。
- 真机：装一个构建号更小、版本号相同的测试包，启动后弹“发现新版本 v4.0.0（构建号 …）”（brief 的真机步骤）。

## 留下的问题

- 还没开始。B 只对装了包含 B 的 4.x 版本的人生效；4.0.0 构建号 5000、5001 的用户和全部 3.x 用户仍然只认版本号——所以 A 是必须的，B 是可选的。
