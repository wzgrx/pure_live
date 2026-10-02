<!-- 由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改 -->

# T02f 平台层升级

属于 [T02 直播平台适配](../README.md)。已批准的升级（`docs/specs/UPGRADES.md`）和平台新数据接到界面。

- 代码：`packages/live_core`、`apps/pure_live/lib/app/platforms.dart`
- 进度：`██████████░░░░░░░░░░` 50%

## 任务

| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| T02f.1 | 已批准升级的余项（UPGRADES 回填、平台层和弹幕层、列表、数据、文字） | 平台 | 完成 | 2026-10-02 | 069be46e4 | [设计或说明](T02f.1/README.md)、[记录](T02f.1/record.md)、[记录 2](T02f.1/record-2.md) |
| T02f.2 | 平台层新数据接到界面：哔哩哔哩轮播、17LIVE 名字颜色和徽章、酷狗 PK 标签、Twitch Cookie 提示和编码、恢复后的实际清晰度、FC2 接手 | 功能 | 暂停 | — | — | [任务书](T02f.2/brief.md) |

## 还没完成的

- **T02f.2 平台层新数据接到界面：哔哩哔哩轮播、17LIVE 名字颜色和徽章、酷狗 PK 标签、Twitch Cookie 提示和编码、恢复后的实际清晰度、FC2 接手**（暂停，第二档，规模 中）
  - 阶段：哔哩哔哩轮播 → 名字颜色和徽章 → 酷狗 PK → Twitch → 实际清晰度 → FC2
  - 接着做：按任务书从头做；旧工作区里的半成品可参考
  - 分支：worktree-agent-af6f5e80c4e19804f（半成品，未提交）
