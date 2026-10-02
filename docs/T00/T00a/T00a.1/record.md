# T00a.1 工程底座

- 日期：2026-09-28
- 上传内容：工具链文件、workspace 根配置、门禁、版本检查工具、代码规范、仓库说明、重构方案。

## 从归档 v4 沿用的部分

只沿用工程工具，不涉及界面：

| 内容 | 文件 | 说明 |
|---|---|---|
| 工具链版本 | `toolchain.env` | 唯一来源 |
| workspace 结构 | `pubspec.yaml` | 所有成员共用一个 `pubspec.lock`；依赖覆盖只能写在根目录 |
| 门禁 | `tools/gate/gate.sh` | 依次检查格式、依赖方向、`dart analyze --fatal-infos` 和测试；有全局锁，同时只跑一个 |
| 依赖方向检查 | `tools/gate/check_deps.py` | 按 docs/PLAN.md 第 4 节的分层写规则表；新成员不在表里就报错，逼着先定方向 |
| 版本检查 | `tools/check_latest` | 对照官方渠道检查工具链、media_kit 上游和 pub 依赖 |
| Claude Code 钩子 | `.claude/settings.json`、`tools/gate/hooks/format_dart.sh` | 改完 Dart 文件自动格式化，结束时跑门禁 |
| 忽略规则 | `.gitignore`、`.gitattributes` | 签名文件不进 Git |

## 和 v3 工程的对比

| v3 的问题 | 这次的做法 |
|---|---|
| 11 个 CI 工作流：没有 push 和 PR 触发；发布工作流引用了不存在的 Secret | 不用 GitHub Actions，只在本机构建和跑门禁 |
| `tool/` 下有 174 个脚本，共 2.56 万行，大部分是一次性的 | 只保留门禁和版本检查；其余按模块需要时再加 |
| 工具链版本散落在多个文件 | 集中在 `toolchain.env`，由 `check_latest` 核对 |
| 依赖方向靠约定（平台层、播放层、界面层互相引用） | 由门禁强制 |

## 环境版本（2026-09-28 核对，全部是最新稳定版）

| 项目 | 版本 |
|---|---|
| Flutter | 3.47.5（Dart 3.13.4） |
| Gradle | 9.8.0 |
| Android Gradle Plugin | 9.4.1 |
| Kotlin | 2.4.20 |
| JDK（Temurin） | 27 |
| Android NDK | 30.0.16248370 |
| compileSdk | 37.2 |
| build-tools | 37.0.0 |
| mpv | 0.41.0 |
| FFmpeg | 9.0.2 |
| media_kit 上游（Predidit/media-kit） | `803c4a2` |
| pub 依赖（args、pub_semver、test、very_good_analysis、yaml） | 全部最新 |

- 查询方式：`GITHUB_TOKEN=$(gh auth token) dart run tools/check_latest/bin/check_latest.dart`，16 项，落后 0，失败 0。
- 不带令牌时，GitHub 接口会限流返回 403；带上令牌后可以正常查询。

## 其他

- 清空 master 时，已安装的 3.x 检查更新要读的 `assets/version.json` 和 `assets/releases.json` 也被删了，导致更新检查返回 404。已原样恢复（提交 `ac40984d8`），AGENTS.md 里注明不能删。
