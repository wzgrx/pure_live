<h1 align="center">纯粹直播 v4（Pure Live）</h1>

<p align="center">开源的第三方多平台直播聚合播放器，正在整体重写为 v4。</p>

<p align="center">
  <a href="https://github.com/wzgrx/pure_live/releases/latest"><img alt="最新版本" src="https://img.shields.io/github/v/release/wzgrx/pure_live"></a>
  <a href="LICENSE"><img alt="许可证 AGPL-3.0" src="https://img.shields.io/badge/license-AGPL--3.0-blue"></a>
</p>

> **现在能下载使用的是 3.2.11**，安装包在 [Releases](https://github.com/wzgrx/pure_live/releases/latest)。它是 3.x 的最后一个版本：3.x 已停止开发，全部精力放在 v4 上，第一个 v4 预览版做好后会发布在同一页面（[ADR 0014](docs/adr/0014-v4-first.md)）。3.x 的源码和说明在 [`legacy/`](legacy/README.md)，v4.0.0 发布时整个目录删除。

## v4 是什么

v4 从头重新设计界面、布局、交互、各尺寸设备的适配和性能，工程上全部使用官方最新稳定版的工具链和依赖。

- **四个一级入口**：关注、发现、搜索、我的。手机、平板、桌面、电视按五个宽度等级分别排版，电视有完整的焦点体系。
- **平台层重写**：每个平台一个适配器，错误分类型（需要登录、被限流、风控、地区限制、接口变了等），界面能说清楚为什么看不了。全部用录制的真实接口样本测试，另有真实网络探针。
- **播放统一用 mpv**，弹幕、录制、多画面在第 5 阶段重写。
- **首批平台**：斗鱼、虎牙、B 站、抖音、快手，其余平台在第 7 阶段逐个评估去留。

## 进度

| 阶段 | 状态 |
|---|---|
| 0 诊断与基线 | 完成 |
| 1 规格与样本 | 规格完成；5 个平台 129 个接口样本 |
| 2 设计方向与设计系统 | 设计原则、令牌和第一批页面稿完成 |
| 3 工程底座 | workspace、本机门禁、工具链检查完成 |
| 4 平台与网络层 | 5 个平台的解析器、适配器和网络层完成 |
| 5 播放、弹幕、录制 | 进行中，和第 6 阶段一起做预览版 |
| 6 新应用界面 | 进行中：第一个预览版包括发现、搜索、关注、我的和直播间（播放、弹幕） |
| 7 其余平台、电视、桌面 | 未开始 |
| 8 对齐验收与切换到 v4.0 | 未开始 |

逐项进度见 [docs/rewrite/STATUS.md](docs/rewrite/STATUS.md)。

## 仓库结构

| 路径 | 内容 |
|---|---|
| [`packages/live_core`](packages/live_core) | 领域模型、类型化错误、5 个平台的解析器和适配器（纯 Dart） |
| [`packages/live_net`](packages/live_net) | 网络层：按平台的代理和 Cookie、节流、样本回放 |
| `apps/pure_live` | v4 应用（第 6 阶段建立） |
| [`tools/live_cli`](tools/live_cli) | 命令行工具：真实网络探针、接口样本录制、弹幕和续期检查 |
| [`tools/check_latest`](tools/check_latest) | 对比工具链和依赖与官方最新稳定版 |
| [`tools/gate`](tools/gate) | 门禁：格式、依赖方向、静态检查、测试 |
| [`spec/`](spec/constitution.md) | 行为规格：产品、各平台、各模块、回归清单、设计原则与令牌 |
| [`fixtures/`](fixtures/README.md) | 脱敏后的接口样本和播放器事件轨迹 |
| [`docs/rewrite/`](docs/rewrite/PLAN.md) | 重写方案、诊断、基线、进度 |
| [`docs/adr/`](docs/adr/README.md) | 架构决策记录 |
| [`third_party/`](third_party) | media_kit 自维护分支（[ADR 0002](docs/adr/0002-media-kit-fork.md)） |
| [`legacy/`](legacy/README.md) | 3.x 应用（已冻结，只作对照） |
| `assets/` | 只有 `version.json` 和 `releases.json`：已安装的 3.x 从这里检查更新 |
| [`toolchain.env`](toolchain.env) | Flutter、JDK、NDK、Gradle 等版本的唯一来源 |

## 开发

工具链版本以 [`toolchain.env`](toolchain.env) 为准（Flutter 3.47.5、JDK 27、NDK 30）。整个仓库是一个 pub workspace，`pubspec.lock` 只有根目录一份。

```bash
flutter pub get
```

```bash
bash tools/gate/gate.sh
```

```bash
dart run tools/live_cli/bin/live_cli.dart probe douyu 288016
```

`gate.sh` 只检查有改动的 v4 包；加 `--all` 检查全部 v4 包，每次推送前必须在本机跑通。构建和检查都在本机进行，GitHub Actions 只保留手动触发。

## 反馈

Issue 只受理 3.x 可以复现的问题。v4 的功能和界面以 [spec/](spec/constitution.md) 为准，发布预览版以后再开放反馈。

## 致谢与许可证

基于 [liuchuancong/pure_live](https://github.com/liuchuancong/pure_live)。许可证为 [AGPL-3.0](LICENSE)，许可证合规的处理见 [ADR 0006](docs/adr/0006-license-compliance.md)。安全问题见 [SECURITY.md](SECURITY.md)。
