# v4 重构进度

方案：[PLAN.md](PLAN.md) · 原则与决定：[spec/constitution.md](../../spec/constitution.md) · 决策记录：[docs/adr/](../adr/README.md)

## 阶段

| 阶段 | 状态 | 产出 | 完成标准 |
|---|---|---|---|
| 0 诊断与基线 | 进行中 | `docs/rewrite/DIAGNOSIS.md`、`docs/rewrite/BASELINE.md` | 诊断报告和基线数据落档 |
| 1 规格与样本 | 未开始 | `spec/`、`spec/regressions.md`、`fixtures/` | 每条结论附旧代码位置；待确认项清零 |
| 2 设计方向与设计系统 | 未开始 | `spec/design/`、设计系统、页面稿 | 独立复核通过 |
| 3 工程底座 | 未开始 | workspace、`apps/legacy`、CI、hooks、`live_cli`、`check_latest` | 旧应用照常构建发布，CI 全绿 |
| 4 平台与网络层 | 未开始 | `live_net`、`live_core`（5 个主力平台） | 样本测试和探针全过；旧应用接入后发布 3.3.x |
| 5 播放、弹幕、录制层 | 未开始 | `live_media`、`live_danmaku`、`live_record` | 契约测试、真机播放和录制、体积门禁 |
| 6 新应用界面 | 未开始 | `live_ui`、`apps/pure_live`（预览版 `.next`） | 截图测试、五个宽度等级、性能门禁 |
| 7 其余平台、TV、桌面 | 未开始 | 其余平台、TV 焦点体系、Windows 细节 | 每个平台探针通过或明确下线 |
| 8 对齐验收与切换 | 未开始 | v4.0.0 | 删除 `apps/legacy` |

## 已完成的前置工作

这些在 v3.2.10–v3.2.11 周期完成，直接作为 v4 的输入：

- 斗鱼租期无缝续流 `FlvSpliceRelay`（`lib/player/core/flv_splice_relay.dart`），真实流验证两次换源无缺口。
- Kick 下线；现支持 33 个平台 + IPTV。
- Android armeabi-v7a、x86_64 改用自编 mpv 0.41.0 + FFmpeg 9.0.2。
- Linux 的 libmpv 依赖库系统优先、自带兜底（`LinuxMpvRuntime`）。
- media_kit 同步到 Predidit `803c4a27`（ADR 0002）。
- 仓库只保留 `master` 分支。

## 日志

- 2026-09-27：方案批准；同步方案、宪法、决策记录到 `master`；开始第 0 阶段。
