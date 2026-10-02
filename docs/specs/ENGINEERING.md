# 工程规范

- 更新：2026-10-02（从模块重构计划整理，改正了测试包名和多语言两处过时的说法）
- 代码和门禁脚本里写的“docs/specs/ENGINEERING.md §3、§4”指这里的第 3、4 节。

## 1. 范围

整个仓库的工程规则：工具链、仓库结构、门禁、构建、安全、依赖和分层、参考仓库、测试包和正式包。界面规则见 [UI.md](UI.md)，做事的流程见 [PROCESS.md](../PROCESS.md)。

## 2. 原则

1. **行为不变**：重构前后对照 3.x 的行为，依据是 3.x 原有的测试、平台接口样本和真机。
2. **先找根因**：每个问题写清根因（文件:行）再动手。
3. **不照搬**：3.x 的代码是起点，GetX、全局单例、界面线程上的重活等结构问题在各自的任务里一并改掉。
4. **最新稳定版**：工具链和依赖用最新稳定版，升级时连同本机环境一起验证（[W01](../W-上游借鉴/W01-定期对照/README.md)）。
5. **参考上游**：做相关任务前先更新并阅读第 5 节的参考仓库，借鉴代码时注明来源。

## 3. 工程底座

- **工具链**：`toolchain.env` 是唯一来源。`tools/check_latest` 对照官方渠道检查 Flutter、Dart、Gradle、AGP、Kotlin、JDK、NDK、Android SDK、mpv、FFmpeg 和 pub 依赖的最新稳定版：`GITHUB_TOKEN=$(gh auth token) dart run tools/check_latest/bin/check_latest.dart`。
- **结构**：pub workspace，全部成员共用根目录的 `pubspec.lock`；依赖覆盖只能写在根 `pubspec.yaml`。
- **门禁**：`tools/gate/gate.sh`，依次检查依赖、FFmpeg 包、依赖方向（`check_deps.py`）、样本隐私（`check_fixtures.py`）、界面结构（`check_ui_structure.py`）、文档（`tools/docs/docs.py --check`），再对每个成员检查格式、`dart analyze --fatal-infos` 和测试。`--all` 是每次推送前必跑的，日志里出现 `gate: passed` 才算通过。
- **构建**：只在本机构建。Android 在 WSL，Windows 在主机；不用 GitHub Actions。同一时间只跑一个重任务；不要在门禁运行时在同一份代码里构建正式包。
- **FFmpeg 包**：`tools/ffmpeg_kit/fetch.sh`（Windows 用 `fetch.ps1`）缓存到 `~/.cache/pure_live/ffmpeg_kit/` 并链接到 `.ffmpeg_kit/`；克隆或新建工作区后先跑一次。
- **时间炸弹**：发布前可跑 `tools/timeshift/run.sh`（+30 天、+1 年、+5 年）；用到样本时间的测试把“现在”固定成录制时间，被测代码能注入时间。
- **安全**：签名文件和密钥不进 git；GitHub 保留 4 个签名密钥（不用于 4.x，见 [D-006](../DECISIONS.md)）；Cookie 和密码加密存储、不写进日志；样本里的客户端地址必须脱敏（门禁检查）。
- **不强推**；版本号只在发布时改。

## 4. 核心依赖和分层

| 方面 | 选择 |
|---|---|
| 语言和框架 | Flutter、Dart 最新稳定版；Dart 主构造函数写 `const new(...)` |
| 代码检查 | very_good_analysis，行宽 120，公开接口要有文档注释 |
| 分层 | 内核是纯 Dart 包（能用 `dart test` 测）；Flutter 只出现在播放绑定、界面组件和应用里；依赖方向由门禁强制 |
| 播放 | 全平台只用 mpv：自维护的 media_kit 分支（`third_party/media_kit`），libmpv 和 FFmpeg 原生包在 GitHub Releases 的 `native-*` |
| 状态和路由 | Riverpod 3（手写 provider）、go_router；页面跳转用 `AppNavigator`（对应 3.x 的同名接口） |
| 多语言 | 应用自带的翻译：`apps/pure_live/assets/translations/zh.json`、`en.json`（中文、英文），键名排序、4 空格缩进 |
| 存储 | drift + sqlite3；3.x 的 Hive 数据在首次启动时自动迁移；Cookie 和密码加密存储 |
| 网络 | 纯 Dart 的 `dart:io` HTTP 客户端，按平台分配代理；Twitch、Kick 用系统 TLS 的原生 HTTP 通道 |

包的划分（依赖只能从上往下）：

```text
apps/pure_live
  ├─ live_ui（主题、通用组件）
  ├─ live_player（media_kit 绑定） → live_media（取流管线、中继、恢复）
  ├─ live_record → live_media
  ├─ live_danmaku、live_iptv、live_cast、live_vod
  ├─ live_store（存储、设置、迁移）
  └─ live_core（模型、平台接口、平台适配器） → live_net（HTTP、WebSocket、代理）
tools/live_cli（平台探针、样本录制）、tools/check_latest、tools/gate、tools/docs
```

每个包归哪个组见 [README.md](../README.md#20-组按优先级)。

## 5. 参考仓库

| 仓库 | 许可证 | 用途 |
|---|---|---|
| [liuchuancong/pure_live](https://github.com/liuchuancong/pure_live) | AGPL-3.0 | 3.x 的上游，在 v3.2.11 上接着开发：平台、录制、播放的修复（主仓库的远程 `upstream`，不拉标签） |
| [liuchuancong/pure_live_TV](https://github.com/liuchuancong/pure_live_TV) | AGPL-3.0 | 电视端的代码基础（X）；平台层的新修复（E、D），例如 Kick |
| [liuchuancong/flame_barrage](https://github.com/liuchuancong/flame_barrage) | MIT | 弹幕渲染和交互（A08） |
| [liuchuancong/media_core](https://github.com/liuchuancong/media_core) | AGPL-3.0 | 播放器会话、恢复、池化、系统媒体控制（G、N） |
| [liuchuancong/flv_lzc](https://github.com/liuchuancong/flv_lzc) | MIT | FLV 和 H.265 的低延迟经验（G） |
| 之前从零写的版本（分支 `archive/v4`） | AGPL-3.0 | 已写好并测过的各包实现，按任务借鉴 |

本机副本在 `~/ref/`，对照笔记在 `~/ref/notes/`；每次对照的结论写进 [Z 的上游对照](../Z-工程文档和维护/README.md)（例如 `upstream-2026-10-03.md`）。AGPL-3.0 的代码借鉴时注明来源仓库和提交；MIT 的保留版权声明。

## 6. 测试包和正式包

- **测试包**：Android 包名加 `.v4dev`（`com.mystyle.purelive.v4dev`，debug 和 profile 构建），和用户手机上的正式包并存，不碰正式包和它的数据。Windows 测试版放在工作目录，不碰 `D:\Soft` 下的安装。
- **正式包**：包名 `com.mystyle.purelive`，覆盖安装 3.x，数据由迁移保留（[J06](../J-设置和数据/J06-3.x数据迁移/README.md)）；发布步骤见 [PROCESS.md](../PROCESS.md) 第 11 节。

## 7. 代码规则

- 功能目录（`apps/pure_live/lib/features/<模块>/`）之间不互相引用；共用的放 `apps/pure_live/lib/shared/` 或 `packages/live_ui`（门禁“界面结构”检查，基线 `tools/gate/ui_baseline.json` 只减不增）。
- 颜色和图标从 `live_ui` 取（颜色角色、`AppIcons`），不在功能目录里直接写。
- 提交信息用英文，说清改了什么和为什么；任务的提交以 `[任务编号]` 开头。
