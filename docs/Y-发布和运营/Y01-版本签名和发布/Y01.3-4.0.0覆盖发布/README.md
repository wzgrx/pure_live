# Y01.3 4.0.0 覆盖发布为构建号 5001

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：发布
- 来源：2026-10-02 当天 4.0.0（构建号 5000）发布后，用户的问题（暂停、录制图标、横屏菜单、哔哩哔哩昵称、issue #36 横屏翻转、#37 切换直播间等）和白天做完的一批修复；用户选择“覆盖发布”而不是发 4.0.1（D-008）。
- 旧编号：T16a.3
- 相关：决定 D-008（覆盖发布，以后换包一律改版本号）、D-007（不强推的例外）、D-006（签名）；Y01.2（被覆盖的 5000）；Y02.1（同版本换包收不到更新）；S02.5（这一批改动的真机验证）；V02.1、V02.3、V02.4（issue #36、#37）

## 目标

用同一个版本号 4.0.0、新的构建号 5001 重新发布 Android 包，替换发布页上的 5000：已经下载过的用户按发布页的说明覆盖安装就能拿到修复；3.x 用户的应用内更新直接给 5001。

## 3.x 和现状

| 方面 | 5000（Y01.2，上午） | 5001（本任务，晚上） |
|---|---|---|
| 版本 | `4.0.0+5000` | `4.0.0+5001`（`apps/pure_live/pubspec.yaml:5`、`features/version/app_version.dart:8`） |
| 标签 | `v4.0.0` 在构建号 5000 的提交上 | `v4.0.0` 移到 `4b039e0c7`（附注标签，22:57 重新打，信息“Pure Live 4.0.0 (Android), build 5001”）——这是 D-007“不强推”唯一的例外 |
| 安装包 | 5000 的三个 APK | 5001 的三个 APK：arm64-v8a 110526630 字节（SHA-256 `b6ddd159…150b`）、armeabi-v7a 97516326（`b5c5c1da…4c3e`）、x86_64 122126476（`abe0bb13…b02e`），22:59 上传，替换 5000 |
| versionCode | 7000（arm64） | 7001（arm64；armeabi-v7a 6001、x86_64 9001），比 5000 大，可以覆盖安装 |
| 发布说明 | `releases/v4.0.0.md` | 加“更新（2026-10-02，构建号 5001）”一节（直播间、弹幕、流畅度和刷新率、界面四组），写明“已经装了 4.0.0 的请到 Releases 下载新包覆盖安装（应用内不会提示，因为版本号没变）” |
| 更新文件 | `version.json` 的 `build_number` 5000 | 5001，`version_num` 400005001，`version_desc` 加一行“2026-10-02 更新：修复暂停、录制图标、横屏菜单、哔哩哔哩昵称、暂停时弹幕、切换直播间等问题，详见发布页。”；`releases.json` 的文件名、大小、`changelog` 换成 5001 |
| 应用内更新 | — | 3.x：版本号 4.0.0 比 3.2.11 新，提示并下载 5001；装了 5000 的：版本号相同，**不提示**（`isNewerVersion` 只比版本号，`apps/pure_live/lib/features/version/update_feed.dart:88`） |

## 结果

- 提交：`4b039e0c7`（22:46，“chore(release): 4.0.0 build 5001 with the 2026-10-02 fixes”：`pubspec.yaml`、`app_version.dart`、发布说明加 31 行）；`e3f644d67`（23:01，“chore(release): update files point at 4.0.0 build 5001”：`assets/version.json`、`assets/releases.json`、`version_page_test.dart` 的 5000 → 5001）。登记表的 `commit` 是 `e3f644d67`。
- 顺序照 PROCESS 第 11 节：先构建（本机文件 22:57）、移标签、上传安装包（22:59），最后改更新文件（23:01）。
- 发布页正文：`releases/v4.0.0.md` 加“下载哪个”（三个文件各适用什么设备，“签名和 3.2.11 相同，可以直接覆盖安装 3.x”）和“SHA-256”两节；本机留了一份 `~/ref/release/v4.0.0-5001/body.md`。
- 这一批包含的修复（发布说明“更新”一节）对应的任务：A07.10～A07.13、A08.5、A02.1～A02.3、A03.1、A03.2、A10.3、D01.32、D02.1、D04.1、H05.1、O05.2、R01.1、R02.2 等，现在大多是“待真机”，S02.5 排了一次看完的顺序。
- 截至 2026-10-07 发布页下载：arm64-v8a 319 次、armeabi-v7a 15 次、x86_64 12 次。

## 验证

- 2026-10-07 复核发布页的 arm64 包：`aapt2 dump badging` 得到 `package: name='com.mystyle.purelive' versionCode='7001' versionName='4.0.0'`、`minSdkVersion:'26'`；`apksigner verify --print-certs` 证书 `CN=Android Debug`、SHA-256 `1e832295a696cf8210bca063e458bad0be12dfa64939d3362ff11b8f237ff7b9`（和 3.2.11 相同），只有 v2 签名；`zipalign -c -P 16` 全部 `.so` 对齐。
- `version_page_test.dart:140`“reads the repository update files as 3.x does”断言 `build_number` 5001。
- 真机：5001 这一批改动的逐项真机验证是 S02.5（第一档，未开始）。

## 留下的问题

- 装了 5000 的用户应用内收不到 5001 → Y02.1；D-008 定了以后换包一律改版本号（PROCESS 第 11 节第 1 条）。
- 这一批 18 个“待真机”任务 → S02.5。
