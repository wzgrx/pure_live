# G01 引擎

media_kit 分支、libmpv 和 FFmpeg 原生包、软硬解、取流管线。

> 子分类说明还没写：照 [templates/sub.md](../../templates/sub.md) 写。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [G 播放](../README.md)。

- 代码：`packages/live_media`、`third_party/media_kit`
- 进度：`██████████░░░░░░░░░░` 50%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| G01.1 | 播放核心：media_kit 分支和取流管线 | 功能 | 完成 | 2026-10-01 | b4fb966e8 | [设计或说明](G01.1-播放核心/README.md)、[记录](G01.1-播放核心/record.md) |
| G01.2 | 高通硬解评估：在 K90 上看 HEVC 硬解，定“优先 H.264”的默认值（UPGRADES 22-3） | 验证 | 未开始 | — | — | [设计或说明](G01.2-高通硬解评估/README.md)、[任务书](G01.2-高通硬解评估/brief.md) |

## 还没完成的

- **G01.2 高通硬解评估：在 K90 上看 HEVC 硬解，定“优先 H.264”的默认值（UPGRADES 22-3）**（未开始，第二档，规模 中）
  - 阶段：K90 上逐平台测 HEVC 硬解 → 定默认值并写进 DECISIONS
  - 来源：UPGRADES 统一原则“默认编码”、22-3（V03.3 核对：S02.3 没有做这一项）

<!-- docs:生成结束 -->
