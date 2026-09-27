# 0016 v3 全部归档

- 状态：已接受（在 0014 的基础上更进一步：旧应用移出 workspace）
- 日期：2026-09-27

## 背景

用户 2026-09-27 要求：“按照 PLAN 全速构建 v4，v3 的所有东西全部停止，清理归档”，本地的 v3 内容也一样。

ADR 0014 冻结了旧应用，但它还是 workspace 成员。它有一百多个依赖和十几个依赖覆盖，都在约束 v4 的依赖解析；仓库根目录也还留着 3.x 的发布工作流、Codex 配置和维护规范。

## 决定

1. **旧应用移出 workspace。**
   - 根 `pubspec.yaml` 只列 v4 成员。依赖覆盖只保留 media_kit 分支和 ADR 0008 里 v4 仍需要的 SDK 锁定越过项。
   - 旧应用专用的覆盖、fvp 路径和 FFmpeg 配置写回 `legacy/pubspec.yaml`，只作记录。
   - 删掉旧应用后，锁文件从约 2700 行减到约 670 行。
2. **3.x 的仓库级文件移进 `legacy/`**（用 `git mv`，保留历史）：
   - 11 个发布工作流和 Issue、PR 模板、dependabot 配置 → `legacy/.github/`，GitHub 不再运行它们；
   - Codex 的技能和环境 → `legacy/.agents/`、`legacy/.codex/`；
   - 旧的 `AGENTS.md`（3.x 维护规范入口）→ `legacy/AGENTS.md`；
   - fvp 源码（只有 3.x 用，ADR 0006）→ `legacy/third_party/fvp`。
   根目录的 `AGENTS.md`、`CLAUDE.md` 重写为 v4 内容。
3. **旧应用不再可构建。** 最后一次能完整构建和测试的是提交 `a3f9824d`。要复现 3.x，检出该提交即可。门禁去掉 `--legacy`。
4. **本地清理。** 3.x 的构建输出和缓存（`legacy/build` 等，约 9.5 GB）已删除。它们都能重新生成，不含源码或用户数据。
5. **保留在根目录的 3.x 相关内容只有 `assets/version.json` 和 `assets/releases.json`**，已安装的 3.x 从这里检查更新（ADR 0014 第 6 条）。

## 影响

- v4 的依赖只受 v4 自己约束，升级不再迁就旧应用。
- `legacy/` 下的脚本、测试和工作流引用的路径不再维护，可能失效。

## 执行记录（2026-09-27 全面清理）

- **GitHub**：
  - 只剩 `master` 分支；根目录只有 v4 和仓库级文件；只注册了手动触发的 CI 和每周版本检查两个工作流；没有自托管运行器。
  - 已删除 3.x 的构建产物（5 个，812 MB）和 Actions 缓存（6 个，5.4 GB）。
  - 仓库简介改为 v4。
  - 保留：
    - 全部 Release 和标签：3.2.11 是现在可下载的版本，已安装的 3.x 从这里检查更新；
    - `native-*` 预发布：原生库和对应源码，v4 的 media_kit 也用；
    - 4 个签名 Secret：只能写不能读，可能是某个旧签名密钥仅存的副本，v4 定签名和密钥轮换时再处理。
- **WSL**：
  - 删除：3.x 构建输出和缓存，`pure_live-linux` 工作树，`upstream` 远程，自编 libmpv/FFmpeg 构建目录，FFmpeg 7.1 复现工具，NDK 27.3 和 30.0.14904198，3.x 的 Gradle 缓存（21 GB），Linux 构建镜像，会话临时文件（7.6 GB）。
  - 环境脚本 `~/tools/purelive-env.sh` 改为 v4 环境，使用新的 Gradle 目录 `~/.gradle-purelive-v4`。
  - 不能从 GitHub 重新得到的 3.x 文件（设置备份、容器定义、手机拉取的设置文件）移到 `~/archive/pure_live-v3/`。
- **Windows**：
  - `claude-work` 下删除：3.x 构建输出、三个 3.x 测试安装目录、JDK 25 和 26、截图和日志。
  - `claude-work\pure_live` 更新到最新 `master`，供 v4 的 Windows 构建使用；Windows 的 Flutter 改用 JDK 27。
- **保留**：
  - 用户自己安装、正在使用的 3.x（手机和 `D:\Soft\PureLive`）；
  - 其它项目共用的工具（NDK 28.2、Temurin 25/26、`~/.gradle`、pub 缓存）。
- **Codex 的 3.x 工作目录**（`Documents\Codex\2026-08-12\https-github-com-liuchuancong-pure-live`，132 GB）：用户确认后于 2026-09-27 删除。删除前核对过：
  - 仓库是浅克隆加部分克隆，4 个本地分支的提交全部已在 GitHub；
  - 只有 3 个 stash 是独有的，已打成增量包 `~/archive/pure_live-v3/codex-workspace/codex-stashes-v3.bundle`，并验证过能在 v4 仓库里完整还原；
  - 目录里没有签名密钥。
