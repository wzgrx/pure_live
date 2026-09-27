# 架构决策记录

每个有长期影响的技术或设计选择写一份记录，编号递增，不修改已接受的记录；要推翻时新写一份并在旧记录里注明“被 NNNN 取代”。

## 索引

| 编号 | 标题 | 状态 |
|---|---|---|
| [0001](0001-v4-rewrite-decisions.md) | v4 重写的 12 项基础决定 | 已接受（播放内核一项被 0006 取代，仓库布局被 0007 取代） |
| [0002](0002-media-kit-fork.md) | media_kit 使用 Predidit 分支的自维护副本 | 已接受 |
| [0003](0003-platform-batches.md) | 平台分批与去留标准 | 已接受 |
| [0004](0004-storage-and-migration.md) | 存储与旧数据迁移 | 已接受 |
| [0005](0005-recording-without-ffmpegkit.md) | 去掉 FFmpegKit 后的录制方案 | 已接受 |
| [0006](0006-license-compliance.md) | 许可证合规：保留 AGPL-3.0，移除不兼容组件 | 已接受 |
| [0007](0007-repo-layout-workspace.md) | 仓库布局：旧应用留在根目录作为 workspace 根 | 已接受 |
| [0008](0008-dependency-overrides.md) | 依赖覆盖的去留：保留越过 SDK 锁定的最新版覆盖，升级 Flutter 时复查 | 已接受 |
| [0009](0009-fixture-format.md) | 平台样本的格式、录制与期望值 | 已接受 |
| [0010](0010-core-domain-model.md) | live_core 的领域模型与错误类型 | 已接受 |
| [0011](0011-live-net.md) | 网络层 live_net：dart:io 实现、按平台的代理与凭据、样本回放 | 已接受 |

## 模板

```markdown
# NNNN 标题

- 状态：提议 / 已接受 / 被 NNNN 取代
- 日期：YYYY-MM-DD

## 背景
## 决定
## 备选方案与放弃理由
## 影响
```
