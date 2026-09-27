# 第 0 阶段诊断：测试体系（master@49ceccb0，全程只读）

**范围与规模**
- `test/`：469 个文件，99,172 行，3,565 个 test 声明。
- `integration_test/`：2 个文件，248 行。
- `tool/probes`：68 个 Dart 文件（11,649 行）和 5 个 Python 文件（906 行）。
- `tool/tests`：10 个 Python 文件，883 行。
- 相关但不在范围内：`tool/interface_probe.py`（1,558 行），`tool/test_*.ps1`（15 个，1,854 行）。

分类方法：按文件名、import 和特征用启发式归类，误差约 ±5%。

## ① 规模与分类

**表 1　test/ 按被测对象 × 主类型**（格式为 文件数/千行；主类型按优先级取一个：Widget > 录制样本 > 本地 HttpServer > 替身 > 内联解析 > 纯逻辑）

| 被测对象 | 文件 | 行 | 纯逻辑 | 解析·内联构造 | 解析·录制文件 | 服务/控制器替身 | 本地服务器契约 | Widget/布局 | 用 GetX |
|---|---|---|---|---|---|---|---|---|---|
| 平台适配器 | 106 | 19,312 | 16/1.6k | 39/7.9k | 15/4.1k | 24/3.1k | 3/0.3k | 9/2.4k | 31 |
| 浏览/账号/搜索/工具 | 60 | 15,289 | 14/1.4k | 2/0.4k | - | 10/2.4k | 1/0.3k | 33/10.7k | 33 |
| 播放器 | 38 | 12,685 | 16/1.0k | 1/0.1k | - | 8/7.6k | - | 13/4.0k | 12 |
| 设置/存储/同步 | 62 | 12,332 | 10/0.7k | 3/0.3k | - | 14/2.6k | 5/0.8k | 30/8.0k | 40 |
| 中继/网络 | 56 | 11,605 | 15/1.2k | 7/1.4k | 2/0.8k | 6/1.9k | 25/6.3k | 1/0.1k | 7 |
| 录制 | 35 | 7,319 | 15/1.5k | 3/0.5k | - | 10/3.8k | 2/0.4k | 5/1.1k | 10 |
| 直播间界面 | 37 | 6,082 | 14/1.5k | 3/0.6k | - | 3/0.4k | - | 17/3.5k | 11 |
| 弹幕 | 32 | 4,993 | 19/1.8k | 2/0.3k | - | 1/0.3k | - | 10/2.6k | 8 |
| IPTV | 14 | 4,942 | 5/0.4k | 1/0.4k | - | 3/1.4k | - | 5/2.8k | 8 |
| 多画面 | 4 | 2,038 | 1 | - | - | - | - | 3/2.0k | 0 |
| 桌面/壳/路由 | 15 | 1,262 | 5/0.2k | - | - | - | - | 10/1.0k | 2 |
| 更新/发布 | 8 | 1,196 | 3/0.2k | 2/0.2k | - | - | - | 3/0.8k | 3 |
| 其它 | 2 | 117 | 2 | - | - | - | - | - | 0 |
| **合计** | **469** | **99,172** | 135/11.7k | 63/12.1k | 17/4.9k | 79/23.5k | 36/8.0k | 139/39.0k | 165 |

**范围外目录**

| 目录 | 类型 | 文件/行 |
|---|---|---|
| integration_test | 真机 + 真实网络 | 2 / 248 |
| tool/probes | 真实网络和本机探针 | 68 Dart / 11,649 + 5 Python / 906 |
| tool/tests | 仓库和脚本工具测试（Python） | 10 / 883 |

- 没有用 mocktail、mockito 或 fake_async，替身全部手写（测试里自定义的类有 485 个）。
- 没有任何截图对比（golden）测试。

## ② 可转成规格/样本的高价值测试（前 20）

| # | 文件 | 行 | 覆盖的外部可观察行为 |
|---|---|---|---|
| 1 | test/huya_play_url_test.dart | 651 | 虎牙 FLV/HLS 签名、fm 模板、WUP 租期不在本地延长、CDN token 请求合同、清晰度 ratio、日志脱敏 |
| 2 | test/huya_transport_policy_test.dart | 125 | 表驱动的线路回退；原生签名 FLV 凭据过期不等于连接租期 |
| 3 | test/douyu_playback_parser_test.dart | 207 | H5 接口成功/失败、CDN 去重与兜底、rtmp_live 绝对地址 |
| 4 | test/douyu_quality_ack_test.dart | 227 | 服务端降档确认；缺少确认时视为“未知”，不冒充原画 |
| 5 | test/douyu_cookie_session_test.dart | 501 | Cookie 字段读取、JWT 到期判定 |
| 6 | test/douyin_playback_parser_test.dart（另有 douyin_parser_test） | 178 | stream_data 与旧 pull_url 映射、排除纯音频档、user_count 的含义 |
| 7 | test/bilibili_recommend_test.dart（另有 bilibili_play_quality_test） | 101 | 推荐接口、WBI 过期时拒绝、按 accept_qn 生成清晰度 |
| 8 | test/kuaishou_playback_parser_test.dart | 54 | H264 优先、HEVC 回退、CDN 合并 |
| 9 | test/bilibili_danmaku_protocol_test.dart | 268 | 嵌套/拼接包、畸形帧不会死循环 |
| 10 | test/huya_danmaku_protocol_test.dart（另有斗鱼/抖音/快手协议测试） | 211 | 心跳、分组注册、8006 是热度不是在线人数、丢弃跨房间消息 |
| 11 | test/web_socket_util_test.dart | 302 | 半开连接检测、心跳保活、代理路由、关闭超时 |
| 12 | test/flv_splice_relay_test.dart | 207 | 斗鱼 300 秒租期拼接：无缺口无重复、下一关键帧切换、时间线平移 |
| 13 | test/flv_legacy_hevc_relay_test.dart | 176 | codec 12 改写为 Enhanced FLV |
| 14 | test/player_error_classifier_test.dart | 166 | 错误分类到恢复通道的映射 |
| 15 | test/player_error_recovery_test.dart | 3,841 | 80 个“事件序列 → 恢复”场景（只取场景，代码绑定旧实现） |
| 16 | test/multiview_test.dart | 1,825 | 格状态机、音频焦点互斥、手动线路优先于卡顿恢复、5 分钟过期能持续恢复而紧密失败会停止 |
| 17 | test/portrait_stream_support_test.dart | 537 | 竖屏判定：连续 3 次一致采样才确认，近方形保持中性 |
| 18 | test/live_room_audience_metric_test.dart | 259 | 热度、在线人数、累计分开处理；未知时不显示 0 |
| 19 | test/backup_roundtrip_test.dart（另有 backup_import_validation、settings_upgrade_migration） | 361 | v3 备份格式兼容，非法段不污染其他数据；v4 导入旧数据的样本来源 |
| 20 | test/m3u_parser_test.dart | 359 | M3U 属性和逗号的边界情况 |

其次值得转换的：`live_short_link_test` / `live_url_tool_parser_test`（分享链接识别）、`recorder_continuation_policy_test`、`hls_retained_window_test`、`hls_master_selection_test`、`popup_route_tracker_test`（小窗吞掉菜单点击的问题）。

## ③ 绑定旧实现的测试

| 绑定程度 | 文件 | 行 |
|---|---|---|
| A　依赖 GetX 或旧页面/控制器 | 199 | 58.6k |
| B　不用 GetX 的 Widget 测试（依赖旧组件树） | 11 | 2.0k |
| C　依赖旧服务/管理器类或测试钩子 | 120 | 20.4k |
| D　纯函数/模型/解析，行为可直接转样本 | 139 | 18.2k |

- **结论：**约 330 个文件、8.1 万行（82%）不能作为代码复用。D 类可以直接转成“样本 + 期望值”；A、C 类只能提取其中的场景名。
- **绑定证据：**
  - 165 个文件调用 `Get.put/find/reset`。
  - `lib/` 里有 150 处 `@visibleForTesting`；26 个测试文件用了 `forTesting`、`headlessForTest`、`debugXxx=` 这类钩子。
  - 14 个文件断言内部调用日志的顺序（例如 `test/recorder_user_intent_test.dart` 有 12 处）。
  - Widget 测试依赖 `find.byType`（105 个文件）、`byKey`（78）、`find.text`（94）。
- **v4 已决定去掉的技术：**
  - IJK/Exo 相关：5 个文件，6.1k 行（含 player_error_recovery）。
  - FFmpegKit 会话替身：13 个文件，4.1k 行。
  - Firebase：4 个文件，1.3k 行。
  - `*_catalog_migration`（v3 Hive 键 `siteCatalogMigration`）：18 个文件，1.4k 行。

## ④ 样本与探针现状

**样本（test/fixtures，共约 200 KB）**

| 平台 | 文件 | 格式 | 来源 | 脱敏 | 覆盖接口 |
|---|---|---|---|---|---|
| bigo | directory, recommendations, studio-login, login-gate | 精简 JSON | 2026-09-09/10，经 Clash | ID/名称/图片替换，去掉 IP 和图片签名 | 目录、推荐、登录门禁；无媒体 |
| cc | dashen-games, dashen-live-config | 精简 JSON，记录了原始 SHA-256 | 2026-09-07 | 无凭据 | 分类配置 |
| kilakila | share-vectors | 28 组生成的加密向量 + 1 条真实分享 | 由 ps1 生成器产出 | 只有公开链接 | 分享链接解码 |
| niconico | live, region, scheduled, ended, stream | JSON 投影 | 2026-09-10 | ID/token/cookie 为合成值，过期时间改为 2099 | 观看页 4 种状态、stream 消息 |
| picarto | detail, master.m3u8 | JSON + M3U8 | 2026-09-07 | 名称/图片替换 | 频道详情、HLS master |
| twitcasting | 3 个 JSON + 2 个 HTML | 规整化 | 2026-09-07 | ID 规整、CDN 替换 | 目录、房间页、分类、在播/离线流信息 |
| weibo | recommend, live-detail, detail | JSON | 2026-09-10，直连 | 链接换成 example.test | 推荐、直播详情、错误响应 |
| xiaohongshu | live, ended | JSON | **没有 README [待确认]** | 看起来已替换 | 直播页状态 |
| **5 个主力平台** | **无** | — | — | — | 只有测试里手写的最小 Map |

- 5 个主力平台（B 站、斗鱼、虎牙、抖音、快手）没有任何录制文件；所有平台都没有录制的弹幕帧；媒体样本不入库。
- 各 README 说原始抓包放在 `local-artifacts/`（已在 `.gitignore:39` 忽略），当前这份检出里不存在 [待确认：Windows 机器上是否还保留]。

**探针（tool/probes）**

| 类别 | 数量 | 需要的环境 | 能否改造为 live_cli |
|---|---|---|---|
| 全站取流 `all_sites_playback_probe_test.dart` | 1 | 设 `PURELIVE_ALL_SITES_PROBE=1`，真实网络 | 可以，作为 `probe` 主干：按“目录 → 详情 → 清晰度 → 地址 → 媒体字节”分阶段判定，并嗅探 FLV 编码 |
| 平台目录/详情/搜索 | 27 | 各自的环境变量开关；海外站点需要 Clash（127.0.0.1:7897） | 可以合并为按阶段运行的用例 |
| 取流/续期（douyu_splice、huya_native_transport 等） | 5 | 另需 ffprobe | 可以，改成 `lease` 子命令 |
| 弹幕连接矩阵 | 2 | DIRECT/PROXY 两种路由 | 可以，改成 `danmaku` 子命令 |
| 录制/HLS 中继 | 25 | ffmpeg/ffprobe，以及仓库外的合成样本目录 | 需要重写（v4 录制方案改了） |
| 播放内核 `media_kit_buffering_probe` 和 `libmpv_continuity_probe.py` | 2 | libmpv 动态库 + 合成 FLV | 可以改造为真实事件序列录制器 |
| 支持库/其它 | 7 | — | 其中帧哈希、封包时间线的思路可沿用 |

- 68 个 Dart 探针里 58 个依赖 `flutter_test`，23 个依赖 GetX，24 个依赖 Hive，都不能直接当纯 Dart CLI 运行。
- `tool/interface_probe.py`（约 40 项检查，覆盖 5 个主力平台和 cc、twitch、soop、yy，无第三方依赖）是一个独立实现，可以用来交叉核对。
- 有过时内容：
  - 全站探针的 `_webViewSites` 仍列着已下线的 4 个站点。
  - `integration_test` 的注释引用了已不存在的 `webview_sites_test.dart`。

## ⑤ 测试替身与易碎测试问题

**替身和真实库不一致**
1. **media_kit 流结束的事件顺序：**真实顺序是 `playing=false` → `completed=true` → `buffering=false` → 清空音视频轨道（`third_party/media_kit/lib/src/player/native/player/real.dart:1779-1806`）。
   - 多画面替身到 42cbded2 才改对（`test/multiview_test.dart:89`）。
   - `test/support/owned_source_test_player.dart:80` 和 `test/player_error_recovery_test.dart:3540` 只发前两个事件。
   - 驱动真实适配器的测试里 `completed` 是 `Stream.empty()`（`test/media_kit_buffering_state_test.dart:294`），所以 MediaKitAdapter 的“流结束”映射没有任何测试。
2. **同步 vs 异步：**10 个文件（包括共享替身）用 `broadcast(sync: true)`，而真实库是异步广播（`platform_player.dart:314` 起）。替身里的事件在调用栈内同步到达，重入和交错情况与真实不同。
3. **替身各自为政：**同一个 `UnifiedPlayer` 接口至少有 7 份不同的替身，没有任何测试核对替身和真实库是否一致；多画面替身一 start 就 `playing=true`，没有缓冲和首帧阶段。
4. **B 站弹幕压缩格式：**握手时声明 `protover: 3`，即 brotli（`lib/core/danmaku/bilibili_danmaku.dart:188`），但测试只构造了 zlib（v2）包，线上实际走的路径没测到。
5. **载荷全靠手写：**弹幕帧和平台接口响应都由测试作者手写，接口变了测试也看不出来。Dio 拦截器直接返回已解码的 Map，跳过了字符串解码那一步（`test/douyu_quality_ack_test.dart:30` 起）[待确认影响]。

**易碎测试**
- **Windows 专属：**12 个文件共 66 个用例 `skip: !Platform.isWindows`（player_error_recovery 29 个、video_settings_resolution_dialog 14 个）。
  - GitHub CI 在 ubuntu 上跑 `flutter test`（`.github/workflows/build_pure_live_release.yml:89`），这些用例在 CI 上永远不执行，只在 Windows 本地 local_ci 跑。
  - `test/version_page_layout_test.dart:48` 在非 Windows 上直接 return，属于假通过。
  - `test/media_kit_video_geometry_test.dart:11` 的期望值随宿主系统变化。
  - 根因是业务代码直接读 `Platform.isWindows`。
- **Linux 专属：**没有 Linux 专属的 skip。另有依赖 pwsh 的 Python 测试（没装 pwsh 时 skipUnless 跳过）。
- **依赖时间：**
  - 没有任何文件用 fakeAsync，只有 12 个文件注入了时钟。
  - 有 44 处 ≥100 ms 的真实等待；`player_error_recovery_test` 里有 98 次 `Future.delayed`，最长 3 秒。
  - 有按秒表阈值断言的：`test/race_http_test.dart:44`、`test/hls_prefetch_pool_test.dart:333`、`test/ffmpeg_hls_body_idle_test.dart:74`。
  - 18 个文件直接用 `DateTime.now()`。
  - 以下来自记忆 [待确认]：v3.2.5 在 Windows 高负载下 hls_prefetch_scheduler、player_error_recovery 偶发失败，当时靠放宽余量解决；Linux 上曾因 Dart Timer 截断到毫秒出过一个真 bug（5fe31c86）。

## ⑥ 对 v4 验证体系的建议

1. **先补样本再写代码：**
   - 第 1 阶段为 5 个主力平台录制：分类、分类房间、推荐、搜索、详情（在播/离线/回放）、取流地址、弹幕握手和帧（二进制）。
   - 每个样本附带：来源信息（URL、时间、DIRECT 或 Clash、原始 SHA-256、脱敏字段）和一份标准化期望值 `expected.json`。
   - 脱敏沿用现有 README 的做法。
2. **新旧对照：**`expected.json` 先用 v3 的静态解析入口生成（B 站 4 个、斗鱼 7 个、虎牙 8 个、抖音 3 个、快手 2 个），人工审核后冻结，v4 对同一批样本做比对。
3. **规格抽取：**用脚本导出 3,565 个测试名，归并后作为 `spec/regressions.md` 的初稿；表驱动的测试（例如虎牙线路回退）直接转成 YAML。
4. **播放器契约：**
   - 用 ② 中的播放内核探针在真实 libmpv 上录制事件序列（jsonl）：流结束、断流、解码失败、403 重开、暂停恢复。
   - v4 只保留一个按录制序列异步回放的替身。
   - 每晚重录一次并和仓库里的版本比对，及时发现真实库行为变化。
5. **可重复性：**
   - 测试里禁止 `DateTime.now()` 和真实 sleep（用 lint 加 hook 强制），统一用 `package:clock` + fake_async。
   - 平台差异通过注入宿主平台对象处理，让 Windows 分支也能在 Linux CI 上跑。
   - CI 同时跑 Linux 和 Windows。
6. **live_cli：**以全站探针为主干，改成纯 Dart（去掉 GetX 和 Hive）；子命令设 `probe`、`record`、`danmaku`、`lease`。在 live_cli 追平之前，保留 `interface_probe.py` 做每日交叉核对。
7. **界面测试：**旧 Widget 测试不迁移。只把其中的不变量写进 `spec/design`（例如各宽度等级和大字号下不溢出、手势区、弹出菜单不被小窗挡住），再用截图测试实现。
8. **回归清单缺口：**Android 17 本地网络权限、Windows 系统代理、Kick TLS 指纹目前都没有自动化测试；codec 12 只覆盖了 17LIVE（Shopee 已下线）。
9. **过渡期：**第 4–5 阶段让旧测试继续在 `apps/legacy` 上跑，为“开关接回旧应用”兜底。`tool/tests` 里的密钥审计、发布数据、设备租约测试作为工具测试保留；FFmpegKit AAR 相关的随录制方案一起下线。
