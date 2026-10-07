# Y01.2 4.0.0 发布（Android）

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：发布
- 来源：4.x 第一个稳定版。D-004 定了“当前只做 Android”；Y01.1 修完发布前审查的问题后当天发布。
- 旧编号：T16a.2
- 相关：Y01.1（发布前修复）；Y01.3（当晚覆盖发布为构建号 5001）；Y03.1（README 和发布说明）；Y02（更新文件）；决定 D-004、D-006、D-007、D-015

## 目标

把 4.0.0（Android，构建号 5000）发出去：正式包能直接覆盖安装 3.x 并保留数据；发布页有三个 ABI 的 APK 和校验和；已安装的 3.x 在应用内收到“新版本 4.0.0”的提示并能下载对应 ABI 的包；Windows 等其他平台的 3.x 用户不受影响。

## 3.x 和现状

| 方面 | 3.x（3.2.11，2026-09-27） | 4.0.0（构建号 5000，2026-10-02） |
|---|---|---|
| 版本 | `3.2.11+4134` | `4.0.0+5000`（`apps/pure_live/pubspec.yaml`、`features/version/app_version.dart`） |
| 构建 | GitHub Actions | 本机 WSL：`flutter build apk --release --split-per-abi`（Gradle `assembleRelease` 335 秒，日志 `~/ref/notes/apk_release_400.log`）；同一提交的 profile 测试包 `apk_profile_e3a0799cf.log` |
| 签名 | 维护者调试密钥（`debug-signed`） | 同一把调试密钥（D-006），能覆盖安装 3.x |
| 安装包 | 每个平台多种包 | 只有 Android：arm64-v8a（110462934 字节）、armeabi-v7a（97419862）、x86_64（122062780）+ `SHA256SUMS.txt`，命名照 3.x：`PureLive-4.0.0-5000-debug-signed-android-<ABI>-release.apk` |
| 更新文件 | `version.json` 顶层和 `platforms.android` 是 3.2.11 / 4134 | 顶层和 `platforms.android` 改成 4.0.0 / 5000 / `version_num` 400005000、`download_url` 指向 `v4.0.0`，`android_abis` 三个；`windows`、`linux` 等块不变（3.x 先读自己平台的块）；`releases.json` 加 4.0.0 一条，带三个 ABI 的文件（3.x 的更新器按文件名挑 ABI） |

## 结果

- 提交：`e3a0799cf`（08:58，“chore(release): v4.0.0+5000 (Android)”：版本号两处、`version_page_test.dart` 跟着改、`assets/version.json`、`assets/releases.json`）；`da69896ba`（09:18，`releases.json` 里填上三个包的实际大小）。登记表没写 `commit`。
- 发布页：GitHub Release“纯粹直播 v4.0.0”，发布时间 2026-10-02 09:16（`publishedAt` 01:16:53Z），正文是 `releases/v4.0.0.md` 加“下载哪个”和“SHA-256”两节（本机留了一份 `~/ref/release/v4.0.0/body.md`）。
- 5000 的校验和（`~/ref/release/v4.0.0/SHA256SUMS.txt`）：arm64-v8a `b3cc3aa7…93b23`、armeabi-v7a `7e7601e1…71be`、x86_64 `a7456f16…7c3b`。
- 当晚覆盖发布后（Y01.3），发布页上的 5000 安装包被 5001 替换，标签 `v4.0.0` 移到 `4b039e0c7`；5000 的包只留在本机 `~/ref/release/v4.0.0/`。
- 偏差：无记录（这次发布没有单独的 `record.md`；以上从 git 历史、发布页和本机的发布文件夹查实）。

## 验证

- 发布前：Y01.1 的 release 构建和检查（`aapt2 dump resources`、lint）；同一提交的 profile 测试包构建成功。
- 发布后：K90 上的冒烟和主流程验证是 S02.2（`288fec0ec` 的 arm64 profile 包）、S02.3；覆盖安装真实 3.x 数据的验证还没做（S04.1、J06.1）。发布说明的“已知问题”写明了哪些还没在真机上完整走过。
- 3.x 收到更新提示：没有专门验证记录；issue #36（11:14）、#37（11:24）在发布后两小时内由装了 4.0.0 的用户提出，说明发布页和安装可用（回复在 V02.1）。

## 留下的问题

- 当天发现的问题催生了构建号 5001 的覆盖发布（Y01.3）；装了 5000 的用户应用内收不到 5001（Y02.1）。
- 覆盖安装 3.x 的真机验证 → S04.1（第一档）。
