<h1 align="center">纯粹直播 v4（Pure Live）</h1>

<p align="center">开源的第三方多平台直播聚合播放器，正在整体重写为 v4。</p>

<p align="center">
  <a href="https://github.com/wzgrx/pure_live/releases/latest"><img alt="最新版本" src="https://img.shields.io/github/v/release/wzgrx/pure_live"></a>
  <a href="LICENSE"><img alt="许可证 AGPL-3.0" src="https://img.shields.io/badge/license-AGPL--3.0-blue"></a>
</p>

> **现在能下载使用的是 3.2.11**，安装包在 [Releases](https://github.com/wzgrx/pure_live/releases/latest)。它是 3.x 的最后一个版本：3.x 已停止开发，全部精力放在 v4 上，第一个 v4 预览版做好后会发布在同一页面（[ADR 0014](docs/adr/0014-v4-first.md)）。3.x 的源码和说明在 [`legacy/`](legacy/README.md)，v4.0.0 发布时整个目录删除。

## v4 是什么

v4 从头重新设计界面、布局、交互、各尺寸设备的适配和性能，工程上全部使用官方最新稳定版的工具链和依赖。

- **四个一级入口**：关注、发现、搜索、我的。手机、平板、桌面、电视按五个宽度等级分别排版，电视有完整的焦点体系；界面有简体、繁体、英文三种语言。
- **平台层重写**：33 个直播平台加 IPTV，每个平台一个适配器，错误分类型（需要登录、被限流、风控、地区限制、接口变了等），界面能说清楚为什么看不了。全部用录制的真实接口样本测试（478 个），另有真实网络探针。
- **播放统一用 mpv**：斗鱼等平台的租期续流不断流，需要改写的 HLS 走本地中继；21 个平台有弹幕；录制支持 FLV、HLS 和 IPTV 连续 TS，纯 Dart 转 MP4；多画面、画中画、后台播放、投屏、开播提醒都已重写。

## 进度

更新于 2026-09-28。**功能代码已全部写完，第一次构建完成；真机验证、预览版发布和 v4.0 切换还没做。**

| 阶段 | 状态 |
|---|---|
| 0 诊断与基线 | 完成 |
| 1 规格与样本 | 规格完成，33 个平台共 478 个接口样本；各规格里标“待确认”的项还没全部查证 |
| 2 设计方向与设计系统 | 完成：设计原则、令牌、组件库；独立复核的问题已全部修复（含图标换成 Material Symbols） |
| 3 工程底座 | 完成：workspace、本机门禁、工具链检查 |
| 4 平台与网络层 | 完成：首批 5 个平台的解析器、适配器和网络层 |
| 5 播放、弹幕、录制 | 代码完成，待真机验证：mpv 播放、HLS 中继、21 个平台的弹幕、FLV/HLS/IPTV 录制和转 MP4 |
| 6 新应用界面 | 代码完成，待真机验证：全部页面、三种语言、93 张截图测试；Android 和 Windows 第一次构建完成，Windows 实测能正常播放 |
| 7 其余平台、电视、桌面 | 代码完成，待真机验证：33 个平台加 IPTV 都已接入（Bigo 有条件保留），电视模式，Windows 外壳 |
| 8 对齐验收与切换到 v4.0 | 未开始 |

逐项进度见 [docs/rewrite/STATUS.md](docs/rewrite/STATUS.md)。

## 仓库结构

| 路径 | 内容 |
|---|---|
| [`apps/pure_live`](apps/pure_live) | v4 应用（预览版包名 `com.mystyle.purelive.next`） |
| [`packages/live_core`](packages/live_core) | 领域模型、类型化错误、33 个平台的解析器和适配器（纯 Dart） |
| [`packages/live_net`](packages/live_net) | 网络层：按平台的代理和 Cookie、节流、样本回放 |
| [`packages/live_media`](packages/live_media) | 播放会话与本地中继（FLV 续流拼接、HLS 中继），纯 Dart |
| [`packages/live_player`](packages/live_player) | 播放内核（media_kit / mpv）的 Flutter 绑定 |
| [`packages/live_danmaku`](packages/live_danmaku) | 各平台弹幕连接、过滤和合并 |
| [`packages/live_record`](packages/live_record) | 录制：FLV、HLS、IPTV 连续 TS，崩溃恢复，纯 Dart 转 MP4 |
| [`packages/live_iptv`](packages/live_iptv) | IPTV：播放列表、节目单、回看 |
| [`packages/live_store`](packages/live_store) | 存储（drift）、设置注册表、备份与 3.x 数据导入 |
| [`packages/live_cast`](packages/live_cast) | DLNA 投屏 |
| [`packages/live_ui`](packages/live_ui) | 设计系统：主题令牌、图标、尺寸等级、自适应导航、卡片、弹幕渲染、电视焦点 |
| [`tools/live_cli`](tools/live_cli) | 命令行工具：真实网络探针、接口样本录制、弹幕和续期检查 |
| [`tools/check_latest`](tools/check_latest) | 对比工具链和依赖与官方最新稳定版 |
| [`tools/gate`](tools/gate) | 门禁：格式、依赖方向、静态检查、测试 |
| [`spec/`](spec/constitution.md) | 行为规格：产品、各平台、各模块、回归清单、设计原则与令牌 |
| [`fixtures/`](fixtures/README.md) | 脱敏后的接口样本和播放器事件轨迹 |
| [`docs/rewrite/`](docs/rewrite/PLAN.md) | 重写方案、诊断、基线、进度 |
| [`docs/adr/`](docs/adr/README.md) | 架构决策记录 |
| [`third_party/`](third_party) | media_kit 自维护分支（[ADR 0002](docs/adr/0002-media-kit-fork.md)） |
| [`legacy/`](legacy/README.md) | 3.x 的归档：应用代码、发布工作流和维护规范，不再构建（[ADR 0016](docs/adr/0016-archive-v3.md)） |
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
