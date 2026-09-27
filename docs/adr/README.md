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
| [0007](0007-repo-layout-workspace.md) | 仓库布局：旧应用留在根目录作为 workspace 根 | 被 0013 取代 |
| [0008](0008-dependency-overrides.md) | 依赖覆盖的去留：保留越过 SDK 锁定的最新版覆盖，升级 Flutter 时复查 | 已接受 |
| [0009](0009-fixture-format.md) | 平台样本的格式、录制与期望值 | 已接受 |
| [0010](0010-core-domain-model.md) | live_core 的领域模型与错误类型 | 已接受 |
| [0011](0011-live-net.md) | 网络层 live_net：dart:io 实现、按平台的代理与凭据、样本回放 | 已接受 |
| [0012](0012-legacy-bridge.md) | 旧应用接入 v4：3.3.x 只接列表、搜索和链接，标识与旧版逐字段一致 | 已接受（发布 3.3.x 被 0014 取消） |
| [0013](0013-legacy-folder.md) | 旧应用整体收进 `legacy/`，根目录只放 v4 和仓库级文件 | 已接受 |
| [0014](0014-v4-first.md) | 停止构建 3.x，直接推进 v4；构建和门禁改在本机运行 | 已接受 |
| [0015](0015-v4-app-structure.md) | v4 应用与播放层的包结构：live_media 纯 Dart + live_player，手写 Riverpod provider | 已接受 |
| [0016](0016-archive-v3.md) | v3 全部归档：旧应用移出 workspace，3.x 的仓库级文件移进 legacy/ | 已接受 |
| [0017](0017-live-store.md) | live_store 的实现选择：库结构、加密接口、设置常驻内存、备份细节 | 已接受 |
| [0018](0018-playback-layer.md) | 播放层的实现方式：事件契约、回环中继与恢复分类 | 已接受 |
| [0019](0019-danmaku-layer.md) | 弹幕包 live_danmaku 的结构与协议选择 | 已接受 |
| [0020](0020-danmaku-render.md) | 画面弹幕渲染：单一 RenderBox、统一速度与按需排版 | 已接受 |
| [0021](0021-recording.md) | 录制：进程内拼接直写 FLV、任务管理与恢复、回放不录 | 已接受 |
| [0022](0022-sync-and-updates.md) | 同步、备份扩展、诊断、更新、分享口令与首启向导 | 已接受 |
| [0023](0023-room-page.md) | 直播间页面：展示状态、单一视频表面、弹幕接入与手势 | 已接受 |

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
