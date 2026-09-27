# v4 重构进度

方案：[PLAN.md](PLAN.md) · 原则与决定：[spec/constitution.md](../../spec/constitution.md) · 决策记录：[docs/adr/](../adr/README.md)

## 阶段

| 阶段 | 状态 | 产出 | 完成标准 |
|---|---|---|---|
| 0 诊断与基线 | **完成**（2026-09-27） | `docs/rewrite/DIAGNOSIS.md`、`docs/rewrite/BASELINE.md` | 诊断报告和基线数据落档 |
| 1 规格与样本 | 进行中：规格已写完，样本未开始 | `spec/`、`spec/regressions.md`、`fixtures/` | 每条结论附旧代码位置；待确认项清零 |
| 2 设计方向与设计系统 | 进行中：原则、设计系统、第一批页面稿已完成，待独立复核和图标重绘 | `spec/design/`、设计系统、页面稿 | 独立复核通过 |
| 3 工程底座 | 进行中：workspace、门禁、CI 已建 | workspace、CI、hooks、`live_cli`、`check_latest` | 旧应用照常构建发布，CI 全绿 |
| 4 平台与网络层 | 未开始 | `live_net`、`live_core`（5 个主力平台） | 样本测试和探针全过；旧应用接入后发布 3.3.x |
| 5 播放、弹幕、录制层 | 未开始 | `live_media`、`live_danmaku`、`live_record` | 契约测试、真机播放和录制、体积门禁 |
| 6 新应用界面 | 未开始 | `live_ui`、`apps/pure_live`（预览版 `.next`） | 截图测试、五个宽度等级、性能门禁 |
| 7 其余平台、TV、桌面 | 未开始 | 其余平台、TV 焦点体系、Windows 细节 | 每个平台探针通过或明确下线 |
| 8 对齐验收与切换 | 未开始 | v4.0.0 | 删除根目录的旧应用代码 |

## 第 1 阶段：规格

| 文件 | 内容 |
|---|---|
| [spec/product.md](../../spec/product.md) | 旧版用户可见功能逐项清单、v4 处置、旧入口到 v4 四个一级入口的对照 |
| [spec/sites/](../../spec/sites/) | 斗鱼、虎牙、B 站、抖音、快手：身份、目录、搜索、详情、画质线路、取流、租期、弹幕、登录、风控、样本清单 |
| [spec/modules/](../../spec/modules/) | 播放、弹幕、直播间、多画面、录制、存储（含 230 个旧设置键的逐项清单和导入规则） |
| [spec/regressions.md](../../spec/regressions.md) | 211 条回归条目（13 个领域）和 23 项没有自动化测试的缺口 |

样本（ADR 0009）：

- 录制工具 `live_cli fixture capture`（脱敏、防泄漏自检）和期望值测试框架 `test/fixtures_expected/` 已完成；斗鱼 S05 已录制。
- 5 个平台的 HTTP 样本正在录制。
- 播放器事件轨迹：Linux 无视频输出的 8 个场景已录入 `fixtures/player/`，补出播放规格 EVT-13～EVT-19。
- `spec/regressions.md` 的平台编号已回填。

还没做：

- 弹幕二进制帧、FLV 文件头、续期时间线的样本（需要给 `live_cli` 增加对应的录制方式）。
- Windows 和 K90 上带真实视频输出的播放器轨迹。
- 各规格的 [待确认] 逐项查证。

## 第 3 阶段：工程底座

已完成：

- pub workspace：旧应用留在根目录作为 workspace 根（ADR 0007），成员 `packages/live_core`、`tools/live_cli`、`tools/check_latest`，共用一个 `pubspec.lock`。加入 workspace 后旧应用 `flutter analyze` 无问题，全量测试 4954 个通过、90 个跳过。
- `toolchain.env`：工具链版本的唯一来源，CI 从这里读取 Flutter 版本。
- `live_core`：第一个类型 `RoomRef`（房间身份的规范化和校验）。
- `live_cli`：命令骨架（probe、record、danmaku、lease），第 4 阶段实现。
- `check_latest`：对比工具链、media_kit 上游和全部直接依赖的官方最新稳定版。
- `tool/check_deps.py`：依赖方向检查，纯 Dart 包禁止依赖 Flutter。
- `tool/gate.sh`：格式、依赖方向、静态检查、测试，带锁，同一时间只跑一个。
- `.github/workflows/ci.yml`：push 到 master 和 PR 时运行 `tool/gate.sh --all`。
- `.github/workflows/weekly.yml`：每周运行 `check_latest`。
- `.claude/settings.json` hooks：编辑后格式化 v4 的 Dart 文件；会话结束时运行门禁。
- `dependency_overrides` 复查：9 个越过 SDK 锁定的覆盖删掉会让 8 个包降到非最新版，保留；路径覆盖按替代进度移除（ADR 0008）。

`check_latest` 首次结果（2026-09-27）：141 项中 137 项已是最新，落后的 4 项已升级，现在 0 项落后：

| 项目 | 原来 | 现在 | 说明 |
|---|---|---|---|
| JDK（Temurin） | 26 | 27 | WSL、Windows 本地构建和 CI 工作流都改为 27；字节码目标仍为 17 |
| Android NDK | 28.2.13676358（Flutter 默认；`toolchain.env` 原先误写为 27.3） | 30.0.16248370 | 应用和全部插件模块统一用同一个 NDK，APK 里的 `libc++_shared.so` 随之换成 NDK 30 的 |
| Kotlin | 2.2.10（AGP 内置） | 2.4.20 | 在 `android/build.gradle.kts` 声明 KGP；`tool/audit_built_in_kotlin.py` 检查它与 `toolchain.env` 一致 |
| compileSdk | 37 | 37.2 | |

验证：arm64 正式包构建通过，22 个原生库都是 16KB 对齐。**真机冒烟（播放、弹幕、录制）在下一次 3.3.x 发布前做**，因为 C++ 运行库换了版本；自编的 libmpv 用 NDK 29 构建，第 5 阶段重建原生库时统一到 NDK 30。

CI：`ci.yml` 在 ab38717c 首次全绿（旧应用 analyze 与全量测试、v4 成员、`tool/tests` 58 个）。

还没做：

- 新增 `packages/live_platform`（第 5 阶段需要原生接口时再建）。

## 已完成的前置工作

这些在 v3.2.10–v3.2.11 周期完成，直接作为 v4 的输入：

- 斗鱼租期无缝续流 `FlvSpliceRelay`（`lib/player/core/flv_splice_relay.dart`），真实流验证两次换源无缺口。
- Kick 下线；现支持 33 个平台 + IPTV。
- Android armeabi-v7a、x86_64 改用自编 mpv 0.41.0 + FFmpeg 9.0.2。
- Linux 的 libmpv 依赖库系统优先、自带兜底（`LinuxMpvRuntime`）。
- media_kit 同步到 Predidit `803c4a27`（ADR 0002）。
- 仓库只保留 `master` 分支。

## 旧应用（3.3.x）待办

诊断发现、需要在 v4 切换前先修到旧应用里的事项：

- 多画面屏蔽词大小写不一致（含大写的屏蔽词在多画面不生效）。
- 移除 Syncfusion 滑块、fuzzywuzzy 和 13 个未使用的依赖（许可证合规，ADR 0006）。
- 发布时附上原生库（FFmpeg、mpv 等）的对应源码包。
- 增加“导出 v4 备份”，提示仅在 Firestore 上有配置的用户导出（ADR 0004）。
- 录制改为本地中继直写，FFmpegKit 保留一个版本作为回退（ADR 0005）。
- 第 1 阶段规格核对出的旧版缺陷（详见 [DIAGNOSIS.md](DIAGNOSIS.md#规格中核对出的旧版缺陷)）中用户可见的几项：虎牙弹幕不校验房间分组、B 站 412 与 -352 的处理、快手限流显示为“无结果”、录制在关闭轮询后停在“等待开播”、断网时录制 2 秒一次无限重试、Windows 新窗口交接文件明文写 Cookie。

## 日志

- 2026-09-27：方案批准；同步方案、宪法、决策记录到 `master`；开始第 0 阶段。
- 2026-09-27：第 0 阶段完成：8 份模块诊断、旧版基线（Windows、K90）、决策记录 0003–0006；依据许可证诊断，播放内核改为全平台只用 mpv。进入第 1 阶段。
- 2026-09-27：第 1 阶段规格写完（产品、5 个平台、6 个模块、回归清单）。第 3 阶段开工：workspace、`live_core`、`live_cli`、`check_latest`、依赖方向检查、门禁脚本、CI、hooks。
- 2026-09-27：第 2 阶段设计原则定稿（[spec/design/principles.md](../../spec/design/principles.md)）：品牌蓝 `#2E6FE0`，一级入口为关注、发现、搜索、我的，PLAN 第 07–09 节与它冲突处以它为准。
- 2026-09-27：工具链升级到最新：JDK 27、NDK 30.0.16248370、Kotlin 2.4.20、compileSdk 37.2；ADR 0008 保留越过 SDK 锁定的依赖覆盖。
- 2026-09-27：样本工具与斗鱼试点；播放器事件轨迹 8 个场景；回归清单平台编号回填。CI 在 d2b96603 全绿。
- 2026-09-27：设计系统第一版（https://claude.ai/artifact/JA858yzW77FSJ9mMdNz7LK）：令牌按 fromSeed(#2E6FE0, fidelity) 生成，157 组对比度全部达标；第三色改用品牌青，浅色成功和警告色加深；17 个组件预览和封面。令牌同步到 `spec/design/tokens.json`。
- 2026-09-27：第一批页面稿（https://claude.ai/artifact/PAavLD9hN6VdLFgNYXkEr4）：关注和直播间（手机、桌面大）、多画面 2×2、TV 首页；设计系统按原则更正了导航轨宽度、TV 焦点和聊天栏宽度。
