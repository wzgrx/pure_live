# 0013 旧应用整体收进 legacy/

- 状态：已接受（取代 0007 中“旧应用留在根目录”的做法）
- 日期：2026-09-27

## 背景

ADR 0007 为了少改构建链路，把旧应用留在仓库根目录，并让根目录同时充当 workspace 根。结果是 GitHub 首页有约 50 项，大部分是旧应用的文件夹，v4 的内容混在里面不容易看出来。用户要求首页像一个新项目，只看到新增的 v4 内容。

## 决定

1. **旧应用的全部文件移进 `legacy/`**，用 `git mv` 保留历史。包括：
   - 代码与平台工程：`lib`、`android`、`ios`、`linux`、`macos`、`windows`；
   - 资源、测试、脚本与插件：`assets`、`test`、`integration_test`、`tool`、`plugins`、`shell`；
   - 旧的配置和说明文件，以及 `docs/` 下除 `rewrite/`、`adr/` 以外的文档。
   `legacy/` 是一个完整的 Flutter 应用，也是 workspace 成员。第 8 阶段切换到 v4.0 时整个删除。
2. **根目录只放 v4 和仓库级的内容**：
   - v4 代码与数据：`apps/`（第 6 阶段）、`packages/`、`tools/`、`spec/`、`fixtures/`、`docs/`（v4 方案和 ADR）、`third_party/`（media_kit 自维护分支，v4 也用）；
   - 仓库级文件：`.github/`、`README.md`（v4 版）、`LICENSE`、`AGENTS.md`、`CLAUDE.md`、`toolchain.env`；
   - workspace 声明：根 `pubspec.yaml` 只声明 workspace 和 `dependency_overrides`，`pubspec.lock` 仍然只有根目录一份。
3. **在线更新文件留在原路径**：已安装的 3.x 从 master 分支读取 `assets/version.json` 和 `assets/releases.json`（`version_util.dart`、`release_history_repository.dart`）。根目录保留一个只有这两个文件的 `assets/`；旧应用打包用的副本在 `legacy/assets/`。旧应用测试检查两份内容一致，发布时两份一起更新。
4. **v4 的门禁脚本**从 `tool/` 移到 `tools/gate/`（`gate.sh`、`check_deps.py`、hooks 和测试），不和旧应用的 `legacy/tool/` 混在一起。
5. 旧应用的构建、测试、发布命令都在 `legacy/` 目录下执行；CI 和工作流相应设置工作目录。

## 备选方案与放弃理由

- **另建 v4 仓库**：发布和在线更新都绑在现有仓库，拆开以后切换时还要迁移；v4 早期需要对照旧代码和旧期望值，跨仓库很不方便。
- **保持 ADR 0007**：首页直到 v4.0 都以旧文件为主。

## 影响

- 旧应用的脚本、测试里引用根目录路径的地方（`.github`、`third_party`、`fixtures`、`pubspec.lock`）要改成 `../` 开头。workspace 的 `.dart_tool`（`package_config.json` 和原生库钩子缓存）在仓库根目录，Windows 构建脚本用 `$workspaceRoot` 指向它。
- 规格、诊断和基线里引用的旧代码路径（`lib/`、`test/`、`tool/`、`android/`、旧 `docs/` 文档等）写于迁移之前，现在对应 `legacy/` 下的同名路径，不逐一改写。
- 发布工作流更新 `releases.json` 时同时写两份。
- Windows 本地构建和发布脚本的工作目录变成 `legacy/`，发布 3.3.x 前要在 Windows 上完整跑一遍构建。
