# Y02.1 同版本换包时应用内收不到更新：任务书

## 背景

- 来源：D-008（2026-10-02）：4.0.0 覆盖发布为构建号 5001，版本名不变，“已安装 4.0.0 的用户收不到应用内提示；以后换包一律改版本号”。登记时的旧编号 T16b.1。
- 现象：装了 4.0.0 构建号 5000 的用户打开应用，启动检查读到 `version.json` 的 4.0.0 / 5001，判断“不是新版本”，不弹提示；关于页没有“新版本”角标；版本页显示“已是最新”。3.x 也一样（3.x 读 4.0.0 时会提示，因为 4.0.0 比 3.2.11 新）。
- 为什么现在做：第二档；下一次发布之前要有机械的保证，否则全靠记得。
- 已经做过的：PROCESS 第 11 节第 1 条写了“换安装包就必须改版本号”；发布说明和发布页写了“已经装了 4.0.0 的请到 Releases 下载新包覆盖安装”。

## 目标和验收

1. （A，必须）发布检查：`apps/pure_live/pubspec.yaml` 的版本号和 `assets/version.json` 的 `platforms.android.version` 相同时，检查失败并提示原因；`--allow-same-version` 时通过（维护者做例外时用）。有测试。
2. （B，维护者确认后做）4.x 在版本号相同、构建号更大时也提示更新：启动检查、新版本对话框、关于页角标、版本页状态卡都按新规则；同版本时显示构建号。
3. （B）“不再提醒这个版本”带上构建号；旧的只存版本号的值照旧生效（兼容）。
4. 新文字（如“v4.0.0（构建号 5002）”）zh、en 都加，按键名排序。
5. 测试和门禁通过；`docs/PROCESS.md` 第 11 节要加的一句（发布检查的命令）写进报告，由维护者改。

## 现状（读代码得出，写文件:行）

- 比较：`apps/pure_live/lib/features/version/update_feed.dart:88` `bool get isNewer => isNewerVersion(version, appVersion);`；`app_version.dart:34` `isNewerVersion` 逐段比数字；`app_version.dart:48` `compareVersions` 把 `+` 也当分隔符（`4.0.0+5002` 拆成 4、0、0、5002）。
- 已安装的版本：`app_version.dart:12` `appVersion`（`flutter.appBuildName ?? pubspecVersion`）、`:15` `appBuild`（`flutter.appBuildNumber`，现在 5001；注意不是 Android 的 versionCode 7001）。
- 用到 `isNewer` 的地方：`update_feed.dart:23` `noteCheckedUpdate`（关于页角标的数据）；`update_prompt.dart:46`（启动检查）；`version_page.dart:306`（状态卡 `version-newer` / `version-latest`）；`features/about/about_page.dart:146`（“新版本 v…”角标 `_NewVersionBadge(update.version)`）。
- 跳过：`update_prompt.dart:91-93` `_wanted`：`compareVersions(skippedUpdateVersion, info.version) != 0`；`:129` 对话框的勾选初值 `== widget.info.version`；`:136` 存 `info.version`。设置 `Settings.skippedUpdateVersion`（`packages/live_store/lib/src/settings/settings.dart:49`，`SettingScope.internal`，4.x 新加的，不是 3.x 的键）。
- 测试：`apps/pure_live/test/features/version/version_page_test.dart:140-145`（读真实 `version.json`，`android.isNewer` 为假，因为 5001 == 5001）、`:168-171`（`isNewerVersion`）；`update_dialogs_test.dart:287`（“不再提醒这个版本”只跳过这个版本）。
- 发布检查：仓库里没有（Y01.4 建议新建 `tools/release/`）。

## 3.x 基线

- `git show v3.2.11:lib/common/utils/version_util.dart:250` `isNewerVersion`（只比版本号）；`:172-198` `_applyVersionData` 读了 `build_number`、`version_num` 但比较不用；`lib/modules/version/version_controller.dart:58` 版本页同样。
- 要保留：`version.json` 的格式（3.x 照旧读）；3.x 用户的行为不变（改不了）；4.x 对“版本号更新”的判断和 3.x 一致，B 只是在版本号相同时多比一步。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 8 节、第 11 节、第 14 节）、`docs/DECISIONS.md` 的 D-007、D-008、D-015。
2. 本文件夹的 `README.md`；`docs/Y-发布和运营/Y02-更新通道/README.md`；`docs/A-界面设计/A15-小页面/A15.2-关于和版本/README.md`（关于页和版本页的设计）、`docs/A-界面设计/A06-首页和全局/A06.3-全局弹窗/README.md`（新版本对话框）。
3. `apps/pure_live/lib/features/version/` 全部文件；`apps/pure_live/test/features/version/` 两个测试文件。

## 范围

- 可以改：新建 `tools/release/check_version.py`（或并入 Y01.4 的检查脚本）和 `tools/gate/tests/test_check_version.py`；（B）`apps/pure_live/lib/features/version/update_feed.dart`、`app_version.dart`、`update_prompt.dart`、`version_page.dart`、`features/about/about_page.dart`（只改角标文字）、翻译文件、对应测试；本文件夹的文档。
- 不能改：`assets/version.json`、`assets/releases.json`、版本号（D-007、D-015）；`version.json` 的格式；3.x 的设置键名和含义；签名配置；界面布局（只改文字内容）。

## 方案和阶段

| 阶段 | 做什么（对应 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | c1（A）发布检查脚本和测试 | `tools/release/check_version.py`、`tools/gate/tests/test_check_version.py` | 现在的仓库上运行：版本号相同 → 失败（正是 D-008 的情况）；`--allow-same-version` 通过；测试全过 |
| 2 | c2（B）比较带构建号、跳过带构建号、显示构建号（维护者确认后） | `update_feed.dart`、`update_prompt.dart`、`version_page.dart`、`about_page.dart`、翻译文件、测试 | 改之前会失败的测试改之后通过；应用全部测试通过 |

## 测试

- 改之前会失败（B）：`version_page_test.dart` 新用例“same version, higher build is newer”：`UpdateInfo(version: appVersion, buildNumber: appBuild + 1).isNewer` 为真（现在为假）；“same version, same or lower build is not newer”。
- `update_dialogs_test.dart`：跳过存成 `4.0.0+<构建号>`，下一个构建号仍提示；旧值 `4.0.0`（只有版本号）时同版本的新构建号不提示（兼容旧行为）——或按维护者定的规则。
- 关于页角标、版本页状态卡在同版本新构建号时显示构建号（widget 测试，竖屏 393×852 一个、宽屏 1280×800 一个）。
- 检查脚本：临时目录里造 `pubspec.yaml` 和 `version.json`，相同 → 退出 1，不同 → 0，`--allow-same-version` → 0。
- 不访问网络；定时器至少 1 秒。

## 真机验证（维护者在 K90 上做，第 2 阶段合并后）

| 步骤 | 期望 |
|---|---|
| 1. 用 `--build-name 4.0.0 --build-number 5000` 构建测试包（profile，`.v4dev`），装到 K90，打开 | 首页 2 秒后弹“发现新版本 v4.0.0（构建号 5001）”（`version.json` 现在是 5001） |
| 2. 勾“不再提醒这个版本”关掉，重启 | 不再弹 |
| 3. 设置 → 关于 | 有“新版本”角标，写着构建号 |
| 4. 用 `--build-number 5001` 的测试包覆盖 | 不弹，版本页显示已是最新 |

## 风险和注意

- `appBuild` 是 Flutter 的构建号（5001），不是 Android 的 versionCode（7001）；不要拿 versionCode 比。
- `skippedUpdateVersion` 是 4.x 的内部设置，改格式要兼容旧值；它不进备份（`SettingScope.internal`）。
- B 改的是用户每次启动都会走的路径：失败必须安静（现在的行为），不能因为解析构建号出错而崩溃。
- 可能冲突的文件：`update_prompt.dart`、`version_page.dart`、`about_page.dart`（A15.2、A06.3 的界面任务）；翻译文件。

## 环境和提交

- `source ~/tools/purelive-env.sh`；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 分支 `ai/Y02.1` 或本机工作区；提交信息以 `[Y02.1]` 开头（英文）；不推 master。
- 提交前：`apps/pure_live` 跑 `dart format --output=none --set-exit-if-changed .`、`flutter analyze`、全部 `flutter test`；`python3 -m unittest discover -s tools/gate/tests`；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”、更新登记表的 `done`、`next`、`branch`（登记表现在没有写阶段，开工时按上表补上）。

## 报告（中文，简洁）

A、B 各做到没有；改之前失败的测试；新翻译键；跳过规则怎么兼容旧值；要在真机上看的；PROCESS 第 11 节要加的一句；可能冲突的文件。
