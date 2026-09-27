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
