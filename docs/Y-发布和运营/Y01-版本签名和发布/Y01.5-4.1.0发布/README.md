# Y01.5 4.1.0 发布（Android，构建号 5002）

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：发布
- 来源：用户 2026-10-09：“开始测试，构建并发布新的 Android 版本 4.1.0，同步到 GitHub”。
- 相关：
  - Y01.3：上一次发布，4.0.0 构建号 5001，标签 `v4.0.0` 在 `4b039e0c7`；
  - Y02.1：版本号不变就收不到更新，所以这次改版本号；
  - Y03：发布说明 [releases/v4.1.0.md](../../Y03-发布说明和README/releases/v4.1.0.md)；
  - 决定 D-006（签名）、D-007（版本号只在发布时改）、D-008（以后换包一律改版本号）、D-015（更新文件留在 master）；
  - D-039、D-040：这一版里默认值有例外的新设置。

## 目标

把 4.0.0 之后合并进 master 的改动（`4b039e0c7..master`，约 520 个提交）发布成 4.1.0。要做到的有四点：

- 发布页上有三个 ABI 的 APK 和 `SHA256SUMS.txt`。
- 正式包能覆盖安装 3.x 和 4.0.0，数据保留。
- 装了 3.x 和 4.0.0 的用户都在应用内收到“新版本 4.1.0”的提示。
- 其他平台的 3.x 用户不受影响。

## 和上一次发布对照

| 方面 | 4.0.0（Y01.3，构建号 5001） | 4.1.0（本任务） |
|---|---|---|
| 版本 | `4.0.0+5001` | `4.1.0+5002`：`apps/pure_live/pubspec.yaml:5`、`features/version/app_version.dart:5`、`:8`，提交 `02f92af81`（维护者） |
| versionCode | arm64 7001、v7a 6001、x86_64 9001 | arm64 7002、v7a 6002、x86_64 9002 |
| 签名 | 维护者调试密钥，证书 SHA-256 `1e832295…7ff7b9` | 同一把密钥（D-006），能覆盖安装 3.2.11 和 4.0.0 |
| 标签 | `v4.0.0` 在 `4b039e0c7` | 新标签 `v4.1.0`（附注标签，信息“Pure Live 4.1.0 (Android), build 5002”），`v4.0.0` 不动 |
| 安装包 | `PureLive-4.0.0-5001-debug-signed-android-<ABI>-release.apk` | `PureLive-4.1.0-5002-debug-signed-android-<ABI>-release.apk`，本机留在 `~/ref/release/v4.1.0/` |
| 发布说明 | `releases/v4.0.0.md` | `releases/v4.1.0.md`：主要变化分十组，另有升级说明、已知问题、下载哪个和 SHA-256 |
| 应用内更新 | 3.x 提示 4.0.0；装了 5000 的不提示（版本号没变） | 版本号变了，3.x 和 4.0.0 都会提示；4.x 从 Y02.1 起还会比较构建号 |
| 数据 | 数据库 `schemaVersion` 1 | `schemaVersion` 2（D08.1 加了 `local_events` 表）：4.0.0 打不开 4.1.0 写过的库，发布说明写明不要装回 4.0.0；3.x 用 Hive，不受影响 |

## 步骤（PROCESS 第 11 节）

| 阶段 | 做什么 | 检查 |
|---|---|---|
| 1 版本号和发布说明 | `pubspec.yaml`、`app_version.dart` 改成 `4.1.0+5002`（已在 master `02f92af81`）；写 `releases/v4.1.0.md`；登记 Y01.5 | `python3 tools/release/check_version.py`：和 master 上的 `assets/version.json`（4.0.0 / 5001）比，版本号和构建号都变大了才通过 |
| 2 构建和检查 | 门禁不在跑时 `flutter build apk --release --split-per-abi`；改成发布的文件名，算 `SHA256SUMS.txt` | 按 [Y01](../README.md)“测试和验证”的命令查包名、versionCode、证书、保留的资源、16 KB 对齐，三个包都查 |
| 3 K90 冒烟 | 用同一提交的测试包 `com.mystyle.purelive.v4dev`，按 S02 的 CHECKLIST 第 1 节走一遍；不碰正式包和 3.x | 每次点按前确认前台是测试包 |
| 4 标签、发布页和安装包 | 打 `v4.1.0` 标签，推送标签，建发布页（`gh --repo wzgrx/pure_live release create`），上传三个 APK 和 `SHA256SUMS.txt` | 发布页正文是 `releases/v4.1.0.md`，填上 SHA-256；本机留一份 `~/ref/release/v4.1.0/body.md` |
| 5 更新文件 | **最后**改 `assets/version.json`、`assets/releases.json`，文字草稿见 [record.md](record.md)；`version_page_test.dart:142` 的期望一起改；门禁通过后推送 | 3.x 和 4.0.0 读这两个文件检查更新（D-015） |

## 留下的问题

- 这一版的新功能大多是“待真机”，发布说明的“已知问题”如实写了。发布后照 PROCESS 第 12 节、Z07.2 的清单，把 STATUS 里的“待真机”逐项看完。
- `pubspec.yaml:4` 的注释还写着“3.x's version until the first v4 release”（Y01 已知问题）。这次改版本号时没有一起改，下次发布时再改。
