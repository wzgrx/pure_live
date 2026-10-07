# X05.2 macOS 签名、公证和分发，应用内更新

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：发布
- 来源：[X05 子分类说明](../README.md)的“路线”；docs v2 时登记
- 相关：D-006（签名材料不进 git）、D-007（版本号只在发布时改）、D-008（同一版本号不再换包）、D-015（`assets/version.json`、`assets/releases.json` 留在 master）；依赖 [X05.1](../X05.1-macOS工程和构建/README.md)；[Y01](../../../Y-发布和运营/Y01-版本签名和发布/README.md)（发布步骤）、[Y02](../../../Y-发布和运营/Y02-更新通道/README.md)（更新通道）、[A18.2](../../../A-界面设计/A18-苹果平台界面/A18.2-macOS差异设计/README.md) c10（更新下载完“在访达中显示”）

## 目标

Mac 用户能下载、打开（不被系统拦“无法验证开发者”）、并在应用内收到 4.x 的更新提示。

## 3.x 和现状

| 方面 | 3.x（文件:行） | 现在（文件:行） | 要做到 |
|---|---|---|---|
| 出包 | 发布工作流构建 macOS 通用包（`git show v3.2.11:.github/workflows/build_pure_live_release.yml:512-565`） | 没有工程（X05.1） | 本机（Mac）构建通用包 |
| 签名和公证 | 3.x 的 macOS 包没有公证（工作流里没有 notarytool 步骤，开工时再核对） | — | Developer ID 签名 + 公证 + staple；没有开发者账号时写清“右键打开”的说明 |
| 包的格式 | — | 更新通道认 `macos-universal.dmg`、`macos-universal.zip`（`apps/pure_live/lib/features/version/update_feed.dart:224`、`:227`），平台名 `macos`（`:308`） | 发布页上传这两个文件名 |
| 更新信息 | — | `assets/version.json` 的 `platforms.macos` 还是 3.2.10 的内容 | 发布 macOS 版时改这一块（最后改，D-015） |
| 下载完 | — | 更新下载对话框没有“在访达中显示”（A18.2 c10） | 照 A18.2 c10 |

## 方案

- c1：签名方式（有没有 Apple 开发者账号；没有时只出未签名包并写说明）；证书和公证密钥放在本机哪里（不进 git），怎么在构建时读。
- c2：构建脚本：`flutter build macos --release` → `codesign`（Developer ID Application，开启 hardened runtime）→ 打 `.dmg` 和 `.zip` → `xcrun notarytool submit --wait` → `xcrun stapler staple`。
- c3：发布步骤写进 `docs/PROCESS.md` 第 11 节的 macOS 部分（和 Android 的一样：最后改 `version.json`、`releases.json`）。
- c4：A18.2 c10 的更新下载完成界面（“在访达中显示”）。

## 验证

- 在另一台没装过的 Mac 上下载 `.dmg`、拖进“应用程序”、双击打开：不出现“无法验证开发者”（已公证时）；`spctl -a -vv` 显示 `Notarized Developer ID`。
- 应用内检查更新能识别 `macos-universal.dmg`。
- 现在：待开工。

## 留下的问题

- 无。
