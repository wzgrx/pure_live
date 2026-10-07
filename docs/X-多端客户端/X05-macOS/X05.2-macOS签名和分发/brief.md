# X05.2 macOS 签名、公证和分发，应用内更新：任务书

## 背景

- 来源：X05 子分类说明的“路线”（docs v2 时登记）。
- 现象：4.x 没有 macOS 包；更新通道已经认 `macos-universal.dmg`、`macos-universal.zip`（`apps/pure_live/lib/features/version/update_feed.dart:224`、`:227`），`assets/version.json` 的 `platforms.macos` 还是 3.2.10。
- 为什么现在做：第三档，**以后**；在 X05.1 之后。
- **前置条件**：X05.1 完成（能在 Mac 上构建运行）；维护者定了签名方式（有没有 Apple 开发者账号）；有 Mac。
- 已经做过的：更新通道的 macOS 文件名和平台名（`update_feed.dart:224`、`:227`、`:308`）。

## 目标和验收

1. `record.md` 写清签名方式和签名材料放在哪（只写位置和用法，不写内容，D-006）。
2. 一条命令（脚本）在 Mac 上出 `macos-universal.dmg` 和 `macos-universal.zip`；有账号时已签名、已公证、已 staple。
3. 另一台 Mac 上按发布说明安装能打开；`spctl -a -vv` 结果写进 `record.md`。
4. 应用内“检查更新”在 macOS 上能找到 `.dmg`；下载完成后有“在访达中显示”（A18.2 c10）。
5. `docs/PROCESS.md` 第 11 节写了 macOS 的发布步骤。

## 现状（读代码得出，写文件:行）

- `apps/pure_live/lib/features/version/update_feed.dart:224`（`macosDmg`）、`:227`（`macosZip`）、`:308`（`currentUpdatePlatform` 返回 `macos`）。
- 更新下载：`apps/pure_live/lib/features/version/update_download.dart`（下载完成后的按钮，A18.2 c10 要改的地方）。
- `assets/version.json` 的 `platforms.macos`（3.2.10，发布时改）。
- `.gitignore` 没有苹果签名文件（X04.1、X05.1 开工时补 `*.p12`、`*.mobileprovision`、`*.p8`）。

## 3.x 基线

- `git show v3.2.11:.github/workflows/build_pure_live_release.yml:512-565`：3.x 构建和打包 macOS 的步骤（文件名、是否签名，开工时逐行核对）。
- 要保留：3.x 的更新文件名（`macos-universal.dmg`、`.zip`），3.x 用户的应用内更新靠它找包。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 8 节、第 11 节、第 14 节）。
2. `docs/DECISIONS.md` 的 D-006、D-007、D-008、D-015。
3. 本文件夹的 `README.md`；`docs/X-多端客户端/X05-macOS/X05.1-macOS工程和构建/README.md`；`docs/Y-发布和运营/Y01-版本签名和发布/README.md`；`docs/A-界面设计/A18-苹果平台界面/A18.2-macOS差异设计/README.md`（c10）。

## 范围

- 可以改：构建和打包脚本（放 `tools/` 下，维护者定目录）；`apps/pure_live/lib/features/version/update_download.dart`（c10）；`docs/PROCESS.md` 第 11 节；本文件夹的文档。
- 不能改：Android 和 Windows 的签名、发布流程；版本号（只在发布时改）；`assets/version.json`、`assets/releases.json`（发布时最后改）。
- 绝对不能：证书、`.p12`、App Store Connect 的 API 密钥、公证用的应用专用密码进 git、文档或日志。

## 方案和阶段

| 阶段 | 做什么（README 的 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 方案 | c1 | `record.md` | 维护者确认 |
| 2 打包脚本 | c2 | `tools/` 下的脚本 | 验收 2、3 |
| 3 更新和文档 | c3、c4 | `update_download.dart`、`docs/PROCESS.md` | 验收 4、5 |

登记表现在没有写阶段，开工时按上表补上。

## 测试

- c4：`update_download` 在 `TargetPlatform.macOS` 下下载完成只显示“在访达中显示”（widget 测试）。
- 打包脚本：在 Mac 上跑一次，输出和 `spctl` 结果贴进 `record.md`。

## 真机验证（维护者在两台 Mac 上做）

| 步骤 | 期望 |
|---|---|
| 1. 打包机上跑脚本 | 生成 `macos-universal.dmg`、`.zip` |
| 2. 另一台 Mac 下载 `.dmg`，拖进“应用程序”，双击 | 能打开（已公证时没有警告；未签名时按说明右键打开） |
| 3. 装一个旧版本，检查更新 | 找到新版本，下载完成后“在访达中显示” |

## 风险和注意

- 公证要求 hardened runtime，mpv、FFmpeg 的动态库也要签名，否则公证失败。
- 3.x 的包名 `com.mystyle.pureLive` 和签名身份要和 3.x 的包一致才能覆盖（X05.1 的方案先定）。
- 可能冲突的文件：`update_download.dart`（A15.2、A06.3 的更新界面）。

## 环境和提交

- Mac：Xcode 命令行工具（`codesign`、`notarytool`、`stapler`、`hdiutil`）。
- 分支 `ai/X05.2` 或本机工作区；提交信息以 `[X05.2]` 开头（英文）；不推 master。
- 提交前（WSL）：`tools/gate/gate.sh --all`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”、更新登记表的 `done`、`next`、`branch`。

## 报告（中文，简洁）

签名方式；脚本在哪、怎么用；公证结果；另一台 Mac 上的安装结果；需要维护者决定的（开发者账号、包名）。
