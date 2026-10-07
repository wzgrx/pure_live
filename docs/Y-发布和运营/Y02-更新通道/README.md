# Y02 更新通道

已经装在用户手上的 3.x 和 4.x 怎么知道有新版本、去哪下载：仓库 master 上的 `assets/version.json`、`assets/releases.json` 两个文件的格式和改法，应用里的启动检查、“新版本”对话框、版本页和下载，以及“哪个版本算更新”的比较规则。

## 范围

- 包括：
  - `assets/version.json`（每个平台的最新版本、构建号、说明、下载页、Android 的 ABI）、`assets/releases.json`（历次发布的说明和文件列表）——3.x 和 4.x 共用，必须留在 master（D-015）。
  - `apps/pure_live/lib/features/version/` 的逻辑部分：`update_feed.dart`（读文件、镜像赛跑、`UpdateInfo`、`isNewer`）、`app_version.dart`（版本比较）、`update_prompt.dart`（启动检查）、`update_download.dart`（下载安装包）。
  - 比较规则：现在只比版本号（Y02.1 要定以后怎么办）。
- 不包括（归哪里）：
  - 关于页、版本页、“新版本”对话框、下载对话框长什么样 → A15.2、A06.3（界面）；这里只管数据和规则。
  - 发布时改这两个文件的时机和顺序 → Y01（PROCESS 第 11 节第 7 条：最后改）。
  - 镜像列表本身（`GitHubMirror`）→ Q 组（`packages/live_net/lib/src/race.dart`）；这里只管用它读更新文件。
  - Windows 的安装包下载和安装（EXE、MSIX、便携 ZIP）→ X01.3。

## 现状：做到哪、怎么工作的

- 文件（2026-10-07）：`version.json` 顶层和 `platforms.android` 是 4.0.0 / `build_number` 5001 / `version_num` 400005001，`download_url` 指向 `releases/tag/v4.0.0`，`android_abis` 三个；`platforms.windows` 还是 3.2.11 / 4134（`windows_msix_available` false），`platforms.linux` 3.2.10 / 4133；其他平台没有块（读顶层）。`releases.json` 的 4.0.0 一条：作者、`changelog`（发布说明全文）、`files`（`SHA256SUMS.txt` 和三个 5001 的 APK，`downloads` 写的是 0）。
- 读文件（`update_feed.dart:316` 的 `UpdateFeed`）：`latest()`（`:352`）向 `raw.githubusercontent.com/wzgrx/pure_live/master/assets/version.json` 和十几个镜像同时请求，取最先答的（`raceJson`，10 秒），URL 加 `ts` 防缓存；设置 `useGitHubOriginForUpdates` 打开时只问 GitHub（`:340-346`）。`UpdateInfo.fromJson`（`:45`）先读顶层，再用 `platforms.<平台>` 覆盖（3.x `selectPlatformVersionData`），没有版本号或构建号不是正数就抛 `FormatException`；`releases()`（`:358`）读 `releases.json`（15 秒）。
- 比较：`UpdateInfo.isNewer`（`:88`）= `isNewerVersion(version, appVersion)`（`app_version.dart:34`）：去掉 `v` 和 `-`、`+` 后面的部分，按数字逐段比，缺的段算 0，读不出数字的永远不算新——**构建号不参与**，和 3.x `VersionUtil.isNewerVersion`（`git show v3.2.11:lib/common/utils/version_util.dart:250`）一样。
- 启动检查（`update_prompt.dart:34` 的 `checkForUpdateOnStartup`）：首页首帧后 2 秒（`:19`），设置 `enableAutoCheckUpdate` 开着才请求；更新而且版本号不是用户“跳过”的那个（`skippedUpdateVersion`，`:91-93`）就排队弹 `NewVersionDialog`（`:108`），只在首页在最上面时弹，不盖住直播间；失败不提示。
- 下载（`update_download.dart`）：版本页按平台和 ABI 挑安装包（`version_page.dart:22` 的 `platformPackages`，`PackageKind` `update_feed.dart:204`：Android 三个 ABI、Windows 安装包 / MSIX / 便携 ZIP 等），从 GitHub 或下载镜像（`downloadMirrorPrefixes` `:273`、`downloadSources` `:296`）下载，Android 交给系统安装器，Windows 运行安装包或打开 ZIP 所在文件夹（`:295-340`）。
- 和 3.x 的关系：格式和读取顺序照 3.x，所以 3.x 和 4.x 看同一份文件；3.x 读到 4.0.0 时提示升级到 4.x（覆盖安装）。**同一个版本号换包时（4.0.0 构建号 5000 → 5001），两边都不提示**（D-008、Y02.1）。
- 完成度：读取、比较、提示、下载都和 3.x 一致（A15.2、A06.3 的界面已完成）；Y02.1 未开始。

## 代码地图

| 文件 | 职责 |
|---|---|
| `assets/version.json` | 每个平台的最新版本（3.x、4.x 都读，D-015） |
| `assets/releases.json` | 历次发布（版本页的“历史版本”、下载文件列表） |
| `apps/pure_live/lib/features/version/app_version.dart`（61 行） | `appVersion`、`appBuild`、`versionParts`（`:20`）、`isNewerVersion`（`:34`）、`compareVersions`（`:48`，历史版本排序） |
| `apps/pure_live/lib/features/version/update_feed.dart`（389 行） | `updateRepository`（`:12`）、`foundUpdate`（`:20`，关于页的“新版本”角标）、`UpdateInfo`（`:31`）、`ReleaseFile`（`:92`）、`ReleaseInfo`（`:118`）、`parseReleases`（`:177`）、`PackageKind`（`:204`）、`downloadSources`（`:296`）、`currentUpdatePlatform`（`:305`）、`UpdateFeed`（`:316`）、`updateFeedProvider`（`:369`） |
| `apps/pure_live/lib/features/version/update_prompt.dart`（306 行） | 启动检查（`:34`）、跳过规则（`:91`）、`NewVersionDialog`（`:108`） |
| `apps/pure_live/lib/features/version/update_download.dart`（643 行） | `UpdateDownloadTools`（`:21`）、`showUpdateDownload`（`:74`）、下载目录（`:125`）、`UpdateDownloadDialog`（`:191`） |
| `apps/pure_live/lib/features/version/version_page.dart`（593 行）、`release_history_view.dart`（555 行） | 版本页和历史版本（界面在 A15.2） |
| `packages/live_net/lib/src/race.dart:92` | `GitHubMirror`：raw 地址和镜像前缀 |
| `packages/live_store/lib/src/settings/settings.dart` | `enableAutoCheckUpdate`、`useGitHubOriginForUpdates`、`skippedUpdateVersion`（`:49`，内部设置） |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `apps/pure_live/test/features/version/version_page_test.dart` | `:133` 安装的版本等于 `pubspec.yaml`；`:140` 按 3.x 读仓库里真实的 `version.json`（4.0.0、5001、三个 ABI、平台块覆盖顶层）；`:168-171` `isNewerVersion`（3.2.12 > 3.2.11、`v3.10.0` > `3.9.9+1`、相同不算新、读不出不算新）；版本页、历史版本、按 ABI 挑包 |
| `apps/pure_live/test/features/version/update_dialogs_test.dart` | 新版本对话框、跳过、下载对话框 |
| （没有） | “版本号相同、构建号更大”的情况没有测试（现在的行为是不提示） |

## 3.x 基线

- `git show v3.2.11:lib/common/utils/version_util.dart`：`:35-39` 用 `GitHubMirror` 读 `assets/version.json`（只用 GitHub 或镜像）；`:172-198` `_applyVersionData`（版本、构建号、`version_num`、说明、ABI、MSIX）；`:210-222` `selectPlatformVersionData`；`:250` `isNewerVersion`（只比版本号）。3.x 读了 `version_num` 和 `latestBuildNumber`，但比较时没用。
- `git show v3.2.11:lib/modules/version/version_controller.dart:58`：版本页也只用 `isNewerVersion`。
- 必须保留：两个文件的位置（master 的 `assets/`）和格式（字段名、平台块）——已安装的 3.x 永远按这个读。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 同一个版本号换包时应用内不提示（只比版本号） | `update_feed.dart:88`、`app_version.dart:34`；3.x 同样 | 装了 4.0.0 构建号 5000 的用户不知道有 5001 | Y02.1（D-008 写了以后换包一律改版本号） |
| `releases.json` 的 `downloads` 一直写 0，发布页的真实下载数（截至 2026-10-07 arm64 319 次）没同步 | `assets/releases.json` | 历史版本页的下载数不准 | 影响小；3.x 的 `update_releases.yml` 工作流同步过，4.x 不用 Actions；没有任务 |
| `platforms.windows` 还指向 3.2.11、`linux` 指向 3.2.10 | `assets/version.json` | Windows、Linux 上的 3.x 用户不会被推到 4.x（这是有意的：这两个平台还没有 4.x） | 发布 Windows（X01.3）、Linux（X02.1）时更新对应的块 |
| 更新文件被删或格式改坏时，3.x 用户永远收不到更新（2026-09-28 清空 master 时发生过，`ac40984d8` 恢复） | `assets/` | 3.x 用户卡在旧版本 | D-015；`version_page_test.dart:140` 读真实文件，格式坏了测试会失败 |

## 相关决定和规范

- D-015：`assets/version.json`、`assets/releases.json` 必须留在 master。
- D-008：4.0.0 覆盖发布，已安装 4.0.0 的用户收不到应用内提示；以后换包一律改版本号。
- D-007：版本号只在发布时改。
- PROCESS 第 11 节第 1 条（换安装包就必须改版本号）、第 7 条（最后改这两个文件）。

## 测试和验证

- `cd apps/pure_live && flutter test test/features/version/`。
- 真机：S02.4 的“应用内更新”一条（发布说明“已知问题”里列为还没完整走过）；做法：装一个版本号更低的测试包（不能动 K90 上的 3.x），看启动后是否弹“发现新版本”、下载的是 arm64 包。

## 路线

1. Y02.1（第二档，小）：定规则——只靠“一律改版本号”（文档和发布检查保证），还是让 4.x 的比较在版本号相同时比构建号（3.x 改不了，只对以后的 4.x 生效）；两者可以都做。下一次发布之前定。
2. Windows、Linux 发布时：对应平台块从 3.x 换到 4.x，下载的包类型和安装方式在 X01.3、X02.1 里验证。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [Y 发布和运营](../README.md)。

- 代码：`assets/`、`features/version/`
- 进度：`░░░░░░░░░░░░░░░░░░░░` 0%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| Y02.1 | 同版本换包时应用内收不到更新提示：以后发布一律改版本号，或让比较带上构建号 | 发布 | 未开始 | — | — | [设计或说明](Y02.1-同版本换包时应用内收不到更新/README.md) |

## 还没完成的

- **Y02.1 同版本换包时应用内收不到更新提示：以后发布一律改版本号，或让比较带上构建号**（未开始，第二档，规模 小）

<!-- docs:生成结束 -->
