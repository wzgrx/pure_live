# 第 0 阶段诊断汇总

基于 `master@49ceccb0`（代码与 v3.2.11 相同）。8 个子代理并行只读调研，各模块的完整报告在 [diagnosis/](diagnosis/)。性能与体积基线见 [BASELINE.md](BASELINE.md)。

## 模块总览

| 模块 | 规模 | 最大问题 | 处置 | 目标包 |
|---|---|---|---|---|
| 平台适配器 | 34 个（33 站 + IPTV），`lib/core/site` 2.9 万行，弹幕 1.2 万行 | 老 9 站依赖 GetX、设置和界面；错误被吞或只剩字符串；请求头、租期靠旁路；13 个标记接口靠 `is` 判断 | 重写；新 24 站的 `*_api/*_link/*_site` 结构作为模板 | `live_core` |
| 播放 | `lib/player` 1.35 万行；PlayerManager 5028 行、98 个可变字段、13 个 Timer、13 套代次计数 | 20 多个职责集中在一个类；单房间与多画面两套恢复规则；Android 没有画面进度信号 | 拆成引擎、源管线、会话、健康监测、恢复策略、租期协调、引擎交接等单元 | `live_media` |
| 直播间、多画面、弹幕 | 直播间 1.85 万行、多画面 4321 行、弹幕协议 1.16 万行 | 弹幕解码和过滤全在 UI isolate；三个控制器成环；全屏状态两份真相；多画面缺资源调度 | 界面重做；弹幕协议与过滤移入后台 isolate；渲染改为画布直绘 | `live_danmaku`、`apps/pure_live` |
| 录制 | `lib/recorder` 1.42 万行 | 每次续期都新开一次尝试，文件有缺口；FFmpegKit 截断输出衍生出约 4400 行 HLS 补丁；TS 分段拼接有约 90 ms 时钟阶跃 | 中继直写 FLV、自带 HLS 下载器、共享 libavformat 转封装；去掉 FFmpegKit | `live_record` |
| 应用骨架与数据 | 内置 GetX 1.57 万行；`lib/common` 2 万行；约 230 个设置键 | GetX 渗透 43% 的文件；所有数据在一个 Hive box，Cookie 和密码明文；启动全程串行 | Riverpod + go_router 重写；drift 存储 + 加密密钥；旧数据只读导入 | `live_store`、`apps/pure_live` |
| 测试 | 469 个文件、9.9 万行、3565 个用例 | 82% 绑定旧实现；5 个主力平台没有录制样本；替身事件顺序与真实库不一致；66 个 Windows 专属用例在 CI 上从不运行 | 行为转为规格和样本；替身改为回放真实内核录下的事件轨迹 | 各包测试、`tools/live_cli` |
| 依赖 | 143 个直接依赖（运行时 120 个） | 13 个完全未用；冗余组 18 类；flutter_inappwebview 实际用 beta 分支；fvp 的 libmdk、Syncfusion、ML Kit、GMS 是专有组件；FFmpeg（LGPLv3）发布时没有附对应源码；Windows 的 libmpv 是 Predidit 预编译的开发版 | 运行时依赖精简到约 60 个；移除专有组件；每个平台一份共享 FFmpeg | — |
| 原生与工程 | Android 原生约 1600 行；`tool/` 174 个文件 2.56 万行；CI 11 个工作流 | CI 没有 push/PR 触发；发布工作流引用不存在的 Secret；近两个月工程维护提交占全仓的大头（tool 349、workflows 192、docs 913） | 新 CI（ci / nightly / weekly / release）；原生代码收进 `live_platform` 插件；脚本大部分删除 | `live_platform`、`tools/` |

## 跨模块结论

1. **状态和依赖是根本问题**。GetX 与全局单例让平台层、播放层、界面层互相引用：播放层导入直播间控制器，平台层通过 GetX 取当前房间兜底，录制页直接 `Get.find` 播放控制器。v4 的依赖方向必须由 lint 和 CI 强制，而不是靠约定。
2. **数据要自描述**。请求头、租期、线路身份、画质确认目前都在旁路（`PlaybackHeaderResolver` 按平台分支、URL 键的租期接口、静态表）。v4 的 `StreamLine` 自带这些信息，租期带 `cutsConnection` 区分斗鱼（拼接）和虎牙（只预取）。
3. **错误要有类型**。平台层返回“状态未知”的房间掩盖失败，录制按日志字符串分类，弹幕回调传中文句子。v4 全部改为 sealed 类型，界面按类型显示文案。
4. **主线程太忙**。弹幕解码、过滤、历史整表复制、整页 `Obx`、根组件 `Obx`、启动时全量迁移检查都在 UI isolate。这是内存和帧耗时基线偏高的主要原因之一。
5. **测试不能证明新旧等价**。必须先为 5 个主力平台录制接口和弹幕样本，并用旧版的静态解析器生成期望值，冻结后作为 v4 的验收标准。

## 由诊断得出的决定

写入架构决策记录：

- [0003](../adr/0003-platform-batches.md)：平台分批与去留标准。
- [0004](../adr/0004-storage-and-migration.md)：存储与旧数据迁移。
- [0005](../adr/0005-recording-without-ffmpegkit.md)：去掉 FFmpegKit 后的录制方案。
- [0006](../adr/0006-license-compliance.md)：许可证合规——保留 AGPL-3.0，移除 fvp（libmdk）、Syncfusion、ML Kit、GMS 和 GPL-2.0 组件，发布附原生库源码。播放内核因此改为全平台只用 mpv。

## 计划调整

| 阶段 | 调整 |
|---|---|
| 1 规格与样本 | 为 B 站、斗鱼、虎牙、抖音、快手录制分类、推荐、搜索、详情（在播 / 离线 / 回放）、取流地址、弹幕握手和二进制帧；用 v3 静态解析入口生成 `expected.json`，审核后冻结。导出 3565 个测试名作为 `spec/regressions.md` 初稿。用真实 libmpv 录制播放器事件轨迹（流结束、断流、解码失败、403 重开、暂停恢复） |
| 3 工程底座 | 迁移旧应用时同一提交里修正所有相对路径；先验证 workspace 下 `dependency_overrides` 和共享 lock 的约束；新增 `packages/live_platform`（Kotlin + C++，Pigeon 生成接口）；一个工具链文件同时驱动 CI 和本地环境；`tool/gate.sh` 加锁；CI 先加 push/PR 触发的门禁 |
| 5 播放、弹幕、录制 | 单房间与多画面共用一套恢复策略；Android 补画面进度信号；中继统一为一个回环服务器；录制外层会话循环（旧流先结束时续接） |
| 3.3.x（旧应用） | 增加“导出 v4 备份”，并提示仅在 Firestore 上有配置的用户导出；这是预览包无法自动迁移、以及更换签名需要重装时的保底手段 |
| 性能预算 | 内存按“比旧版降低一半”设定（旧版 Windows 直播间 801 MB 私有内存） |

## 诊断中发现的旧版缺陷

这些问题在旧版中真实存在，登记在此；影响用户的在 3.3.x 修复，其余由 v4 覆盖：

| 缺陷 | 影响 | 位置 | 处理 |
|---|---|---|---|
| 多画面弹幕过滤只把消息转小写、屏蔽词没有转，含大写字母的屏蔽词和屏蔽用户在多画面中不生效 | 用户可见 | `lib/modules/multiview/danmaku/multiview_danmaku_session.dart:199-201` | 3.3.x 修复 |
| `feature-build.yml` 用 3.0.x 时代的证书签名，产物无法覆盖安装在现有用户手机上 | 发布风险 | `.github/workflows/feature-build.yml` | 第 3 阶段随 CI 重写移除 |
| 发布工作流引用的 `KEYSTORE_BASE64`、`CERTIFICATE` Secret 不存在 | 发布必然失败 | `.github/workflows/build_pure_live_release.yml` | 第 3 阶段重写 |
| Manifest 声明了 `purelive://`、`mystyle://` 的 VIEW 过滤器，Dart 侧没有处理 | 链接打不开 | `android/app/src/main/AndroidManifest.xml:66-76` | v4 统一由路由处理 |
| 应用内更新下载的安装包没有哈希校验 | 安全 | `lib/common/utils/version_util.dart` 等 | v4 校验 `SHA256SUMS` |
| Windows 首次启动默认注册开机自启（`enableStartUp=true`） | 行为可疑 | 设置默认值 | 待核实是否有意，v4 默认关闭 |
| 录制合并进度事件没有订阅者，界面只能显示“处理中” | 体验 | `lib/recorder/services/video_processor_service.dart` | v4 覆盖 |

## 待确认事项

诊断报告中标为 [待确认] 的条目由第 1 阶段逐项查证；影响决定的几项：

- ~~Windows 版 libmpv 的 FFmpeg 版本~~：已查明是 FFmpeg master（Lavc63.13），所有平台都 ≥ 8，能直接识别 codec 12 HEVC，旧式 HEVC 转写中继可以删除。
- HLS 查询策略是否还有平台产出（唯一产出者 TTingLive 已下线）。
- 3.0.x 时代签名证书（`c0bb9574…`）的原始 keystore 是否仍在：决定签名轮换谱系怎么建。
- Android 15 起 dataSync 前台服务每天限 6 小时：长时间录制是否改用其它服务类型。
