# Y01.7 5.0.0 全平台发布（Android、电视、Windows、Linux，构建号 5100）和新仓库

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：发布
- 来源：用户 2026-10-15：“完成整个项目，测试快速测试就行，最后发布最终版本，和仓库，全平台版本，新的仓库和redme”；选择：新建独立代码仓库、平台 Android + Windows + Linux + 电视（没有 Mac，不做苹果）、版本号 5.0.0
- 相关：Y01.6（4.2.0）；X01.3（Windows 打包）、X02.1（Linux）；A17.2、A17.4、A17.5（电视）；V01.8（录像播放）；发布说明 [releases/v5.0.0.md](../../Y03-发布说明和README/releases/v5.0.0.md)

## 目标

- 新仓库 `wzgrx/PureLive`（公开、独立，不是分支）：代码从 5.0.0 这一版开始一个干净的提交，README 写新版本和全部平台；发布页 v5.0.0 上传六个包和 `SHA256SUMS.txt`；`assets/version.json`、`assets/releases.json` 在新仓库的 master。
- 应用从 5.0.0 起读新仓库的更新文件（`update_feed.dart` 的 `updateRepository`）。
- 旧仓库 `wzgrx/pure_live` 保留：它的 `assets/version.json` 改成 5.0.0、下载地址指向新仓库的发布页，3.x、4.x 的设备照常收到提示；README 开头写“已搬到 wzgrx/PureLive”。

## 版本

| 方面 | 4.2.0（Y01.6） | 5.0.0（本任务） |
|---|---|---|
| 版本 | `4.2.0+5004` | `5.0.0+5100` |
| Android versionCode | 7004、6004、9004 | 7100、6100、9100 |
| Windows | — | 安装版（Inno Setup 6，和 3.x 同一个 AppId）、便携 ZIP |
| Linux | — | `linux-x64.tar.gz` |
| 签名 | 维护者调试密钥 | 同一把（D-006） |
