# v4 重构进度

方案：[PLAN.md](PLAN.md) · 原则与决定：[spec/constitution.md](../../spec/constitution.md) · 决策记录：[docs/adr/](../adr/README.md)

## 阶段

| 阶段 | 状态 | 产出 | 完成标准 |
|---|---|---|---|
| 0 诊断与基线 | **完成**（2026-09-27） | `docs/rewrite/DIAGNOSIS.md`、`docs/rewrite/BASELINE.md` | 诊断报告和基线数据落档 |
| 1 规格与样本 | 进行中：规格已写完，样本未开始 | `spec/`、`spec/regressions.md`、`fixtures/` | 每条结论附旧代码位置；待确认项清零 |
| 2 设计方向与设计系统 | 进行中：原则、设计系统、第一批页面稿已完成，待独立复核和图标重绘 | `spec/design/`、设计系统、页面稿 | 独立复核通过 |
| 3 工程底座 | 完成：workspace、本机门禁、hooks、`live_cli`、`check_latest`；旧应用收进 `legacy/` | workspace、门禁、hooks、`live_cli`、`check_latest` | 本机门禁全绿（ADR 0014：构建和门禁在本机运行） |
| 4 平台与网络层 | **完成**：5 个平台的解析器、适配器、`live_net` 和真实网络探针全部完成；3.x 不再发布（ADR 0014） | `live_net`、`live_core`（5 个主力平台） | 样本测试和探针全过 |
| 5 播放、弹幕、录制层 | 代码完成，待真机：`live_media`、`live_player`（ADR 0018）、`live_danmaku`（ADR 0019，现 17 个平台有弹幕）、弹幕渲染（ADR 0020）、`live_record`（ADR 0021，纯 Dart FLV→MP4、后台录制 ADR 0029）、`live_cast`（ADR 0027）；HLS 录制在做 | `live_media`、`live_danmaku`、`live_record` | 契约测试、真机播放和录制、体积门禁 |
| 6 新应用界面 | 代码基本完成，待真机：全部一级页面、直播间（ADR 0023）、多画面、录制中心、IPTV（ADR 0024）、系统集成（ADR 0025）、开播提醒（ADR 0028）、账号与网页组件（ADR 0032）、设置八个分组；多语言在做 | `live_ui`、`apps/pure_live`（预览版 `.next`） | 截图测试、五个宽度等级、性能门禁 |
| 7 其余平台、TV、桌面 | 进行中：第二批 5 个、第三批 23 个平台完成（Bigo 有条件保留，等 HLS 解扰中继后接入）；TV 模式完成（ADR 0026）；Windows 外壳完成 | 其余平台、TV 焦点体系、Windows 细节 | 每个平台探针通过或明确下线 |
| 8 对齐验收与切换 | 未开始 | v4.0.0 | 删除 `legacy/` |

## 第 1 阶段：规格

| 文件 | 内容 |
|---|---|
| [spec/product.md](../../spec/product.md) | 旧版用户可见功能逐项清单、v4 处置、旧入口到 v4 四个一级入口的对照 |
| [spec/sites/](../../spec/sites/) | 斗鱼、虎牙、B 站、抖音、快手：身份、目录、搜索、详情、画质线路、取流、租期、弹幕、登录、风控、样本清单 |
| [spec/modules/](../../spec/modules/) | 播放、弹幕、直播间、多画面、录制、存储（含 230 个旧设置键的逐项清单和导入规则） |
| [spec/regressions.md](../../spec/regressions.md) | 211 条回归条目（13 个领域）和 23 项没有自动化测试的缺口 |

样本（ADR 0009）：

- 录制工具 `live_cli fixture capture`（脱敏、防泄漏自检）和期望值测试框架 `test/fixtures_expected/` 已完成；斗鱼 S05 已录制。
- HTTP 样本：5 个平台共 129 个（斗鱼 31、虎牙 23、B 站 32、抖音 21、快手 22），每个都有旧版期望值，CI 中比对。需要登录、需要特定房间状态或被限流的少数样本未录，列在各平台录制报告里。
- 播放器事件轨迹：Linux 无视频输出的 8 个场景已录入 `fixtures/player/`，补出播放规格 EVT-13～EVT-19。
- `spec/regressions.md` 的平台编号已回填。

还没做：

- 弹幕二进制帧、FLV 文件头、续期时间线的样本（需要给 `live_cli` 增加对应的录制方式）。
- Windows 和 K90 上带真实视频输出的播放器轨迹。
- 各规格的 [待确认] 逐项查证。

## 第 3 阶段：工程底座

已完成：

- pub workspace：最初旧应用留在根目录作为 workspace 根（ADR 0007）；现在旧应用收进 `legacy/`，根目录只放 v4 和仓库级文件，根 `pubspec.yaml` 只声明 workspace（ADR 0013）。成员 `legacy`、`packages/live_core`、`packages/live_net`、`tools/live_cli`、`tools/check_latest`，共用一个 `pubspec.lock`。已安装的 3.x 检查更新读的 `assets/version.json`、`assets/releases.json` 留在根目录，旧应用测试检查它和 `legacy/assets/` 里的副本一致。加入 workspace 后旧应用 `flutter analyze` 无问题，全量测试 4954 个通过、90 个跳过。
- `toolchain.env`：工具链版本的唯一来源，CI 从这里读取 Flutter 版本。
- `live_core`：第一个类型 `RoomRef`（房间身份的规范化和校验）。
- `live_cli`：命令骨架（probe、record、danmaku、lease），第 4 阶段实现。
- `check_latest`：对比工具链、media_kit 上游和全部直接依赖的官方最新稳定版。
- `tools/gate/check_deps.py`：依赖方向检查，纯 Dart 包禁止依赖 Flutter，旧应用只能依赖允许的 v4 包。
- `tools/gate/gate.sh`：格式、依赖方向、静态检查、测试，带锁，同一时间只跑一个。
- `.github/workflows/ci.yml`：push 到 master 和 PR 时运行 `tools/gate/gate.sh --all`；其余旧应用工作流默认在 `legacy/` 下运行。
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

## 第 4 阶段：平台与网络层

已完成：

- `live_core` 领域模型与类型化错误（ADR 0010，含解析器完成后的修订）。
- 5 个平台的解析器，全部用录制样本验证并和旧版期望值逐项对照：斗鱼 39、虎牙 43、B 站 47、抖音 39、快手 54 个测试。
- `live_net`（ADR 0011）：dart:io 传输、按平台代理、`CookieVault`、`ThrottledHttp`、`ReplayHttp`。
- 适配器：斗鱼、虎牙（原生 WUP 令牌，编解码与旧版逐字节一致）、B 站（WBI）、抖音（a_bogus 移植，与旧版逐字节一致）、快手，全部有回放测试。
- `live_cli probe`：5 个平台在真实网络上都跑通“解析链接 → 详情 → 取流 → 读 FLV 文件头”（2026-09-27）。
- 旧应用接入（ADR 0012）：斗鱼的分类、分区、推荐、搜索和别名链接走 v4；桥接输出与旧版期望值逐字段一致；真实网络探针通过。

还没做：

- 虎牙样本的 `fm` 需要按“保留占位符的模板”重新脱敏（录制工具加模板规则），网页签名目前用合成模板测试。
- 虎牙列表接入旧应用；B 站、抖音、快手的搜索和快手的分区、推荐暂不接入（ADR 0012 修订）。
- 其余 [待确认] 和缺失的样本（需要登录或特定房间状态的）。
- 3.3.x 发布前的真机冒烟（含工具链升级后的 NDK 30 运行库）。

## 功能完成清单（第 5–7 阶段，对照 spec/product.md）

按用户要求：全部功能重写完之后再统一构建（2026-09-27）。

| 领域 | 状态 | 负责 |
|---|---|---|
| 设计系统、应用骨架、关注（开播/全部/分组）、发现（推荐、分区、收藏分区）、搜索（综合、按平台、链接）、观看历史、设置分组、备份与恢复（含 3.x 备份）、平台账号（系统密钥加密）、分享接收、多画面、桌面窗口与快捷键 | 完成 | 主会话 |
| 播放（mpv、斗鱼续期拼接）、弹幕连接（5 个平台）、画面弹幕渲染 | 完成 | 子代理 |
| 代理设置（统一代理、按平台）、关注分组、收藏分区、综合搜索 | 完成（播放器代理随直播间合并接入） | 主会话 |
| 直播间完整化：弹幕列表与画面弹幕接入、屏蔽词、定时关闭、房间音量、纯音频、锁定、手势、快捷面板、切换直播间、竖屏适配、剧场模式、菜单 | 完成（ADR 0023）；录制按钮、本地弹幕输入、屏蔽即时移除在屏弹幕、画中画和后台返回重连弹幕已补；投屏在做 | 子代理 → 主会话 |
| 录制（`live_record`）与录制中心、录制设置 | 完成（斗鱼真实录制 600 s 两次续期 0 缺口；回放不录）；纯 Dart 转 MP4 完成并接入（斗鱼、虎牙含 H.265、B 站真实录制验证，负载与原文件一致） | 子代理 → 主会话 |
| IPTV（独立模块 `live_iptv`，ADR 0024） | 完成 | 子代理 |
| WebDAV、局域网同步、诊断包、首次启动向导、应用内更新、关于、分享口令 | 完成 | 子代理 |
| Android 画中画、后台播放与通知、应用内小窗；Windows 单实例、新窗口、托盘、关闭行为、开机自启、系统媒体控制 | 完成（ADR 0025），已接入直播间 | 子代理 → 主会话 |
| 第二批平台：cc、yy、soop、acfun、twitch | 完成，五个都保留并接入应用（CC 暂无弹幕；Twitch 列表只有第一页，翻页要 WebView 完整性令牌） | 子代理 → 主会话 |
| 第三批平台前半：chzzk、missevan、kilakila、inke、picarto、twitcasting、showroom、pandalive、17live | 完成，九个都保留并接入应用（ADR 0031；映客无匿名弹幕；17LIVE 手机开播的高画质是 codec 12，默认 H.264 档；TwitCasting 分片要带响应 Cookie） | 子代理 → 主会话 |
| 第三批平台后半：liveme、steambroadcast、sixroom、kugoulive、jdlive、baidulive、looklive、weibo；niconico；候选下线 tiktok、youtube、bigo、fc2live；小红书仅链接 | 完成，13 个接入应用（ADR 0031 第 10 条）：YouTube、FC2 保留，TikTok、小红书仅链接；Bigo 有条件保留，等 live_media 的 HLS 解扰中继后再注册；发现和搜索按适配器能力筛选；弹幕新增 fc2live、niconico、steambroadcast、youtube；niconico 分片的按路径 Cookie 待真机验证 | 子代理 → 主会话 |
| 缓存清理、平台健康状态 | 完成 | 主会话 |
| 深链 `purelive://`、按网络选画质与卡顿自动降一档、断网提示、录制拼音文件夹 | 完成 | 主会话 |
| DLNA 投屏（`live_cast`，ADR 0027） | 完成，已接入直播间菜单和 Android 顶栏 | 子代理 → 主会话 |
| 开播提醒（含 IPTV 节目提醒，ADR 0028） | 完成；Android desugaring 和 Windows 通知待统一构建时验证 | 子代理 |
| 多画面补全：常驻选台侧板、每格音量和暂停、多画面弹幕、沉浸和全屏、1–9 快捷键 | 完成 | 子代理 |
| 录制补全：强制开始、重新录制、出错环节、确认框、录制设置全部上界面、录制目录容量上限、Android 后台录制（specialUse 前台服务，ADR 0029）、录制任务进备份（ADR 0030） | 完成；前台服务待统一构建后真机验证 | 子代理 → 主会话 |
| 关注与搜索补全：排序（含自定义顺序）、录制中标记、按标签分区、关注失败回滚、启动校验中状态、封面定时刷新、标签描述、未支持平台标记、搜索排序与“综合”加载更多、宽屏平台侧栏、获取直链、回前台刷新 | 完成（粉丝排序待模型加粉丝数） | 子代理 |
| 平台账号（B 站扫码和网页登录、斗鱼会话续期状态、手动 Cookie、校验、退出确认）、内置网页组件（ADR 0032）、网页搜索兜底 | 完成；Twitch 翻页不做令牌伪造，停在第一页 | 子代理 |
| TV 模式（遥控器焦点、10 英尺界面、换台） | 完成（ADR 0026），Kotlin 和 TV 真机待统一构建时验证 | 子代理 |
| 多语言（简体、繁体、英文） | 界面稳定后统一做 | 主会话 |
| 统一构建：Android（WSL）、Windows（本机），真机检查 | 全部功能完成后 | 主会话 |

## 已完成的前置工作

这些在 v3.2.10–v3.2.11 周期完成，直接作为 v4 的输入：

- 斗鱼租期无缝续流 `FlvSpliceRelay`（`lib/player/core/flv_splice_relay.dart`），真实流验证两次换源无缺口。
- Kick 下线；现支持 33 个平台 + IPTV。
- Android armeabi-v7a、x86_64 改用自编 mpv 0.41.0 + FFmpeg 9.0.2。
- Linux 的 libmpv 依赖库系统优先、自带兜底（`LinuxMpvRuntime`）。
- media_kit 同步到 Predidit `803c4a27`（ADR 0002）。
- 仓库只保留 `master` 分支。

## 旧应用（3.3.x）待办（已取消）

3.x 不再构建和发布（ADR 0014），下面的事项不再修到旧应用里。它们都已写进规格或回归清单，由 v4 的实现覆盖。原列表：

- 多画面屏蔽词大小写不一致（含大写的屏蔽词在多画面不生效）。
- 移除 Syncfusion 滑块、fuzzywuzzy 和 13 个未使用的依赖（许可证合规，ADR 0006）。
- 发布时附上原生库（FFmpeg、mpv 等）的对应源码包。
- 增加“导出 v4 备份”，提示仅在 Firestore 上有配置的用户导出（ADR 0004）。
- 录制改为本地中继直写，FFmpegKit 保留一个版本作为回退（ADR 0005）。
- 第 1 阶段规格核对出的旧版缺陷（详见 [DIAGNOSIS.md](DIAGNOSIS.md#规格中核对出的旧版缺陷)）中用户可见的几项：虎牙弹幕不校验房间分组、B 站 412 与 -352 的处理、快手限流显示为“无结果”、录制在关闭轮询后停在“等待开播”、断网时录制 2 秒一次无限重试、Windows 新窗口交接文件明文写 Cookie。
- 录制样本时发现的旧版缺陷（[DIAGNOSIS.md](DIAGNOSIS.md#样本录制中发现的问题)）中用户可见的几项：抖音把在线人数当累计观看、抖音未登录时把错误当用户信息、斗鱼别名链接打不开、斗鱼标题里的 HTML 实体没解码、虎牙搜索第 2 页重复第 1 页的房间、B 站搜索卡片封面用了关键帧截图。

## 日志

- 2026-09-27：方案批准；同步方案、宪法、决策记录到 `master`；开始第 0 阶段。
- 2026-09-27：第 0 阶段完成：8 份模块诊断、旧版基线（Windows、K90）、决策记录 0003–0006；依据许可证诊断，播放内核改为全平台只用 mpv。进入第 1 阶段。
- 2026-09-27：第 1 阶段规格写完（产品、5 个平台、6 个模块、回归清单）。第 3 阶段开工：workspace、`live_core`、`live_cli`、`check_latest`、依赖方向检查、门禁脚本、CI、hooks。
- 2026-09-27：第 2 阶段设计原则定稿（[spec/design/principles.md](../../spec/design/principles.md)）：品牌蓝 `#2E6FE0`，一级入口为关注、发现、搜索、我的，PLAN 第 07–09 节与它冲突处以它为准。
- 2026-09-27：工具链升级到最新：JDK 27、NDK 30.0.16248370、Kotlin 2.4.20、compileSdk 37.2；ADR 0008 保留越过 SDK 锁定的依赖覆盖。
- 2026-09-27：样本工具与斗鱼试点；播放器事件轨迹 8 个场景；回归清单平台编号回填。CI 在 d2b96603 全绿。
- 2026-09-27：设计系统第一版（https://claude.ai/artifact/JA858yzW77FSJ9mMdNz7LK）：令牌按 fromSeed(#2E6FE0, fidelity) 生成，157 组对比度全部达标；第三色改用品牌青，浅色成功和警告色加深；17 个组件预览和封面。令牌同步到 `spec/design/tokens.json`。
- 2026-09-27：第一批页面稿（https://claude.ai/artifact/PAavLD9hN6VdLFgNYXkEr4）：关注和直播间（手机、桌面大）、多画面 2×2、TV 首页；设计系统按原则更正了导航轨宽度、TV 焦点和聊天栏宽度。
- 2026-09-27：5 个平台 128 个 HTTP 样本录完；`live_cli fixture` 支持响应头、JSON 路径和已知值替换。第 4 阶段开工：`live_core` 领域模型与类型化错误（ADR 0010），斗鱼解析器用全部斗鱼样本验证。
- 2026-09-27：第 4 阶段主体完成：5 个平台解析器、`live_net`、4 个适配器和真实网络探针；旧应用的斗鱼列表、搜索、链接接到 v4（ADR 0012）。
- 2026-09-27：旧应用整体收进 `legacy/`（ADR 0013），根目录只放 v4 和仓库级文件，README 换成 v4 版；门禁移到 `tools/gate/`，旧应用工作流默认在 `legacy/` 下运行。
- 2026-09-27：3.x 停止构建和发布（ADR 0014），全部归档进 `legacy/` 并移出 workspace（ADR 0016）；构建和门禁改在本机运行。第 5、6 阶段合并推进：`live_ui` 设计系统完成（令牌、尺寸等级、自适应导航、卡片）。
- 2026-09-27：v3 在 GitHub、WSL、Windows 全面清理归档（ADR 0016 执行记录）。`live_store` 完成（ADR 0017），应用接入关注、观看历史、设置、备份与恢复（可导入 3.x 备份）。
- 2026-09-27：`live_media`、`live_player`、`live_danmaku` 完成（ADR 0018、0019）；应用接入播放、多画面、平台账号（系统密钥加密）、分享接收、桌面窗口与快捷键。
