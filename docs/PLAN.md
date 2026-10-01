# 纯粹直播 v4：在 v3 代码上重构

> 状态：执行中（2026-09-28 起）。进度见下方“模块顺序与进度”表，每完成一个模块更新一次。

## 1. 目标

- v4 是 v3 的改进版：在 v3 的代码上逐模块审查、重构、优化、完善、增强。
- **界面、布局、操作逻辑和功能以 v3 为准。** 改变外观或操作习惯的改动，先征得用户同意。
- 代码质量、稳定性、性能、安全和许可证合规要明显好于 v3，并补上 v3 缺的功能。
- 正式版覆盖安装 3.x，保留用户的全部数据。

## 2. 原则

1. **行为不变**：每个模块重构前后对照 v3 的行为，依据是 v3 原有的测试、平台接口样本和实机。
2. **先找根因**：审查出的每个问题都写清根因（文件:行），再动手修。
3. **一个模块一次上传**：
   - 按第 6 节的顺序，工程底座优先，然后自底向上逐个模块重构；
   - 每个模块都走完第 7 节的流程后，推送一次到 GitHub。
4. **核心依赖和工具链沿用 v4 的设计**（第 4 节），环境依赖一律用最新稳定版。
5. **参考上游**：做每个模块前，先更新并阅读第 8 节的参考仓库里对应的部分，借鉴代码时注明来源。
6. **不照搬**：v3 的代码是起点，但不原样搬运。GetX、全局单例、界面线程上的重活等结构问题，在各自的模块里一并改掉，不留到最后一次性替换。

## 3. 工程底座

- **工具链**：`toolchain.env` 是唯一来源。
  - `tools/check_latest` 对照官方渠道检查 Flutter、Dart、Gradle、AGP、Kotlin、JDK、NDK、Android SDK、mpv、FFmpeg 和 pub 依赖的最新稳定版。
  - 升级时连同本机环境一起验证。
- **结构**：pub workspace，全部成员共用根目录的 `pubspec.lock`；依赖覆盖只能写在根 `pubspec.yaml`。
- **门禁**：`tools/gate/gate.sh`，依次检查格式、依赖方向（`tools/gate/check_deps.py`）、`dart analyze --fatal-infos` 和测试。`--all` 是每次推送前必跑的。
- **构建**：只在本机构建。Android 在 WSL，Windows 在主机。不用 GitHub Actions。
- **安全**：签名文件和密钥不进 Git；GitHub 保留 4 个签名密钥。
- **不强推**，版本号只在发布时改。

## 4. 核心依赖（沿用 v4 的设计）

| 方面 | 选择 |
|---|---|
| 语言和框架 | Flutter、Dart 最新稳定版；Dart 主构造函数写 `const new(...)` |
| 代码检查 | very_good_analysis，行宽 120，公开接口要有文档注释 |
| 分层 | 内核是纯 Dart 包（可以用 `dart test` 测，也可以给命令行工具用）；Flutter 只出现在播放绑定、界面组件和应用里；依赖方向由门禁强制 |
| 播放 | 全平台只用 mpv：自维护的 media_kit 分支（`third_party/media_kit`），libmpv 0.41.0、FFmpeg 9.0.2 原生包（GitHub Releases 里的 `native-*`），有新版就跟进 |
| 状态和路由 | Riverpod 3（手写 provider）、go_router |
| 多语言 | slang：简体、繁体、英文 |
| 存储 | drift + sqlite3；3.x 的 Hive 数据在首次启动时自动迁移；Cookie 和密码加密存储 |
| 网络 | 纯 Dart 的 `dart:io` HTTP 客户端，按平台分配代理 |

包的划分（依赖只能从上往下）：

```text
apps/pure_live
  ├─ live_ui（主题、通用组件）
  ├─ live_player（media_kit 绑定） → live_media（取流管线、中继、恢复）
  ├─ live_record → live_media
  ├─ live_danmaku、live_iptv、live_cast
  ├─ live_store（存储、设置、迁移）
  └─ live_core（模型、平台接口、平台适配器） → live_net（HTTP、WebSocket、代理）
tools/live_cli（平台探针、样本录制）、tools/check_latest、tools/gate
```

## 5. v3 的现状（审查起点）

- **规模**：`lib/` 约 18 万行，测试 486 个文件，约 3565 个用例。其中：
  - 平台适配器 2.9 万行；
  - 弹幕 1.2 万行；
  - 播放 1.35 万行（PlayerManager 一个类就有 5028 行）；
  - 录制 1.42 万行；
  - 直播间 1.85 万行；
  - 另有内置的 GetX 1.57 万行。
- **已知的主要问题**：
  - GetX 和全局单例让平台层、播放层、界面层互相引用；
  - 弹幕解码和过滤在界面线程；
  - PlayerManager 职责过多，单房间和多画面各有一套恢复规则；
  - 录制在续期时产生缺口，还有 FFmpegKit 截断的补丁；
  - 所有数据在一个 Hive box，Cookie 和密码是明文；
  - 专有组件和许可证问题：fvp/libmdk、Syncfusion、ML Kit、GMS；
  - 启动串行，整页 `Obx` 重建。
- v3 源码在归档分支 `archive/v4` 的 `legacy/` 目录下，比标签 `v3.2.11` 还多几处修复。本机有一份只读副本：`~/ref/pure_live_archive/legacy`。

## 6. 模块顺序与进度

每个模块的审查记录写在 `docs/modules/<编号>-<名称>.md`。

| 编号 | 模块 | v3 来源 | 目标 | 状态 |
|---|---|---|---|---|
| M0 | 工程底座 | 工具链、门禁、代码规范 | 根目录、`tools/` | 完成（2026-09-28，[记录](modules/M0-foundation.md)） |
| M1 | 网络 | `core/common` 中的 HTTP 客户端、拦截器、请求头策略、代理路由、请求作用域和 WebSocket，`plugins/race_http`、`fake_useragent` | live_net | 完成（2026-09-28，[记录](modules/M1-network.md)） |
| M1.1 | Brotli 解码（给猫耳弹幕、哔哩哔哩 protover 3 用） | — | live_net | 完成（2026-09-29，[记录](modules/M1.1-brotli.md)） |
| M2 | 基础模型与接口 | `core/interface`、`common/models`（直播间、分区、弹幕消息）、`model/`、画质标签、HLS 查询策略 | live_core | 完成（2026-09-28，[记录](modules/M2-core.md)） |
| M2.1 | 模型扩展（[升级决定](UPGRADES.md)）：开播时间、受限类型、轮播和“不可播放”状态、房间身份比较、合并时不被占位值覆盖 | `common/models` | live_core | 完成（2026-09-28，[记录](modules/M2.1-model.md)） |
| M3 | 平台框架与链接解析 | `core/sites.dart`，站点注册，`common/utils` 中的链接工具和短链 | live_core | 完成（2026-09-28，[记录](modules/M3-sites-links.md)） |
| M4.x | 各直播平台，一个平台一次上传（含该平台的链接规则、样本） | `core/site/<平台>` | live_core | 完成（2026-09-28，33 个平台）：M4.1 哔哩哔哩完成（[记录](modules/M4.01-bilibili.md)）、M4.2 斗鱼完成（[记录](modules/M4.02-douyu.md)）、M4.3 虎牙完成（[记录](modules/M4.03-huya.md)）、M4.4 抖音完成（[记录](modules/M4.04-douyin.md)）、M4.5 快手完成（[记录](modules/M4.05-kuaishou.md)）、M4.6 YY 直播完成（[记录](modules/M4.06-yy.md)）、M4.7 SOOP完成（[记录](modules/M4.07-soop.md)）、M4.8 Twitch完成（[记录](modules/M4.08-twitch.md)）、M4.9 网易 CC完成（[记录](modules/M4.09-cc.md)）、M4.10 AcFun 直播完成（[记录](modules/M4.10-acfun.md)）、M4.11 Picarto完成（[记录](modules/M4.11-picarto.md)）、M4.12 TwitCasting完成（[记录](modules/M4.12-twitcasting.md)）、M4.13 猫耳 FM完成（[记录](modules/M4.13-missevan.md)）、M4.14 映客完成（[记录](modules/M4.14-inke.md)）、M4.15 克拉克拉完成（[记录](modules/M4.15-kilakila.md)）、M4.16 小红书完成（[记录](modules/M4.16-xiaohongshu.md)）、M4.17 niconico完成（[记录](modules/M4.17-niconico.md)）、M4.18 微博直播完成（[记录](modules/M4.18-weibo.md)）、M4.19 SHOWROOM完成（[记录](modules/M4.19-showroom.md)）、M4.20 CHZZK完成（[记录](modules/M4.20-chzzk.md)）、M4.21 LiveMe完成（[记录](modules/M4.21-liveme.md)）、M4.22 TikTok完成（[记录](modules/M4.22-tiktok.md)）、M4.23 YouTube完成（[记录](modules/M4.23-youtube.md)）、M4.24 BIGO LIVE完成（[记录](modules/M4.24-bigo.md)）、M4.25 PandaTV完成（[记录](modules/M4.25-pandalive.md)）、M4.26 FC2 LIVE完成（[记录](modules/M4.26-fc2live.md)）、M4.27 Steam 直播完成（[记录](modules/M4.27-steambroadcast.md)）、M4.28 京东直播完成（[记录](modules/M4.28-jdlive.md)）、M4.29 酷狗直播完成（[记录](modules/M4.29-kugoulive.md)）、M4.30 百度直播完成（[记录](modules/M4.30-baidulive.md)）、M4.31 六间房完成（[记录](modules/M4.31-sixroom.md)）、M4.32 LOOK 直播完成（[记录](modules/M4.32-looklive.md)）、M4.33 17LIVE完成（[记录](modules/M4.33-17live.md)） |
| M4.U | 平台层升级：把 [升级决定](UPGRADES.md) 里标 M4.U 的条目逐平台做进适配器，一个平台一次上传 | `core/site/<平台>` | live_core | 进行中：M4.U.1 哔哩哔哩完成、M4.U.2 斗鱼完成、M4.U.3 虎牙完成、M4.U.4 抖音完成、M4.U.5 快手完成、M4.U.6 YY 直播完成、M4.U.7 SOOP完成、M4.U.8 Twitch完成、M4.U.9 网易 CC完成、M4.U.10 AcFun 直播完成、M4.U.11 Picarto完成、M4.U.12 TwitCasting完成、M4.U.13 猫耳 FM完成、M4.U.14 映客完成、M4.U.15 克拉克拉完成、M4.U.16 小红书完成、M4.U.17 niconico完成、M4.U.18 微博直播完成、M4.U.19 SHOWROOM完成、M4.U.20 CHZZK完成、M4.U.21 LiveMe完成、M4.U.22 TikTok完成、M4.U.23 YouTube完成、M4.U.24 BIGO LIVE完成、M4.U.25 PandaTV完成、M4.U.26 FC2 LIVE完成、M4.U.27 Steam 直播完成、M4.U.28 京东直播完成、M4.U.29 酷狗直播完成、M4.U.30 百度直播完成、M4.U.31 六间房完成、M4.U.32 LOOK 直播完成、M4.U.33 17LIVE完成 |
| M5.x | 弹幕：先框架和过滤，再一个平台一次 | `core/danmaku`、`core/emoji`、`plugins/emoji_manager` | live_danmaku | 完成（2026-10-01）：M5.0 框架完成（[记录](modules/M5.0-framework.md)）、M5.1 哔哩哔哩完成（[记录](modules/M5.1-bilibili.md)）、M5.2 斗鱼完成（[记录](modules/M5.2-douyu.md)）、M5.3 虎牙完成（[记录](modules/M5.3-huya.md)）、M5.4 抖音完成（[记录](modules/M5.4-douyin.md)）、M5.5 快手完成（[记录](modules/M5.5-kuaishou.md)）、M5.6 YY 直播完成（[记录](modules/M5.6-yy.md)）、M5.7 SOOP完成（[记录](modules/M5.7-soop.md)）、M5.8 Twitch完成（[记录](modules/M5.8-twitch.md)）、M5.9 AcFun完成（[记录](modules/M5.9-acfun.md)）、M5.10 Picarto完成（[记录](modules/M5.10-picarto.md)）、M5.11 TwitCasting完成（[记录](modules/M5.11-twitcasting.md)）、M5.12 猫耳 FM完成（[记录](modules/M5.12-missevan.md)）、M5.13 克拉克拉完成（[记录](modules/M5.13-kilakila.md)）、M5.14 niconico完成（[记录](modules/M5.14-niconico.md)）、M5.15 SHOWROOM完成（[记录](modules/M5.15-showroom.md)）、M5.16 CHZZK完成（[记录](modules/M5.16-chzzk.md)）、M5.17 LiveMe受阻（要登录），调查完成（[记录](modules/M5.17-liveme.md)）、M5.18 TikTok受阻（要签名），调查完成（[记录](modules/M5.18-tiktok.md)）、M5.19 YouTube完成（[记录](modules/M5.19-youtube.md)）、M5.20 BIGO LIVE完成（[记录](modules/M5.20-bigo.md)）、M5.21 PandaTV完成（[记录](modules/M5.21-pandalive.md)）、M5.22 FC2 LIVE完成（[记录](modules/M5.22-fc2live.md)）、M5.23 Steam 直播完成（[记录](modules/M5.23-steambroadcast.md)）、M5.24 京东直播完成（[记录](modules/M5.24-jdlive.md)）、M5.25 酷狗直播完成（[记录](modules/M5.25-kugoulive.md)）、M5.26 百度直播完成（[记录](modules/M5.26-baidulive.md)）、M5.27 六间房完成（[记录](modules/M5.27-sixroom.md)）、M5.28 LOOK 直播完成（[记录](modules/M5.28-looklive.md)）、M5.29 17LIVE完成（[记录](modules/M5.29-17live.md)）、M5.F 后续升级完成（[升级决定](UPGRADES.md)附录 B：B-1、B-3～B-15、B-22、B-23、B-25、B-26 在弹幕层完成，B-2 移到 M12，B-16、B-21、B-24 在 M13，B-17～B-20 不做；做法见各平台记录末尾“后续升级（M5.F）”一节）；收尾时三档时间前移检查全部通过 |
| M6 | IPTV 内核 | `core/iptv`、`core/site/iptv` | live_iptv | 完成（2026-10-01，[记录](modules/M6-iptv.md)） |
| M7 | 播放：media_kit 分支和原生包 → 播放核心（拆分 PlayerManager） → Flutter 绑定 | `player/` | live_media、live_player | 完成（2026-10-01：M7.1 播放核心（[记录](modules/M7.1-media.md)）、M7.2 播放器（[记录](modules/M7.2-player.md)）） |
| M8 | 录制 | `recorder/` 的内核部分 | live_record | 完成（2026-10-01，[记录](modules/M8-record.md)） |
| M9 | 存储、设置、备份、3.x 数据迁移 | `plugins/db_service`、`common/services/settings`、`plugins/backup_recovery_service` | live_store | 完成（2026-10-01，[记录](modules/M9-store.md)） |
| M10 | 投屏 | 直播间的 DLNA 部分 | live_cast | 完成（2026-10-01，[记录](modules/M10-cast.md)） |
| M11 | 界面基础：主题、通用组件、图标 | `common/style`、`common/styles`、`common/widgets` | live_ui | 完成（2026-10-01，[记录](modules/M11-ui.md)） |
| M12 | 应用骨架：入口、路由、首页外壳、多语言、Android 和 Windows 原生部分 | `main.dart`、`routes/`、`modules/home`、`assets/translations`、`android/`、`windows/`、`plugins/built_in_kotlin` | apps/pure_live | 完成（2026-10-01，[记录](modules/M12-app.md)） |
| M13.x | 各页面，一个页面一次上传 | `modules/*`、`recorder/pages` | apps/pure_live | 进行中：M13.5 分区（分区列表、分区房间、热门分区）完成（[记录](modules/M13.5-areas.md)） |
| M14 | 电视端：以 pure_live_TV 的代码为基础并入 | pure_live_TV | apps/pure_live 的电视模式 | 未开始 |
| M15 | 发布：正式签名、Windows 安装包、覆盖安装 3.x 验证 | — | — | 未开始 |

补充说明：
- **网络在模型之前**：v3 的模型和接口依赖网络层（取消令牌、请求头规则），所以网络是最底层，先做（2026-09-28 调整）。
- **虎牙的 tars 编解码**（`pkg/tars`、`core/tars`）随虎牙一起做（M4）。
- **二进制写入和列表工具**（`binary_writer`、`list_util`）只有弹幕协议使用，随 M5 一起做。
- **平台的顺序**：先哔哩哔哩、斗鱼、虎牙、抖音、快手，再 YY、SOOP、Twitch、网易 CC、AcFun，其余按使用量依次做。Kick 等 v3 没有的平台放在 M4 最后，作为增强。
- **页面的顺序**：关注 → 热门 → 分区（含分区房间、热门分区） → 搜索 → 直播间（分成几次上传） → 多画面 → 录制中心 → 网络电视 → 设置（分成几次上传） → 账号 → 历史、标签、屏蔽 → 备份和 WebDAV → 关于和版本 → 工具箱 → 远程同步 → 启动页。
- **应用何时能跑**：M12 之后应用就能运行，之后每上传一个页面，就在 Windows 和手机上对照 v3 实测。

## 7. 每个模块的流程

1. **读**：
   - v3 的代码和它的测试；
   - 归档 v4 的对应实现（如果有）；
   - 参考仓库的对应部分（先 `git pull`）。
2. **审查**：在 `docs/modules/<编号>-<名称>.md` 写清三件事：
   - v3 的问题：根因和位置；
   - 要保留的行为；
   - 从归档 v4 或参考仓库借鉴什么，为什么。
3. **重构**：
   - 按第 4 节的分层写进目标包，行为和 v3 一致，顺手修掉审查出的 bug；
   - 归档 v4 里有更好实现的，按这个模块接进来，并对照 v3 的行为验证。
4. **测试**：
   - 把 v3 测试中固定行为的部分移植过来，补上缺的；
   - 平台模块用真实接口样本和探针验证。
5. **门禁**：`tools/gate/gate.sh --all` 通过。
6. **上传**：更新第 6 节的进度表，提交（英文提交信息），推送。

## 8. 参考

| 仓库 | 许可证 | 用途 |
|---|---|---|
| [liuchuancong/pure_live_TV](https://github.com/liuchuancong/pure_live_TV) | AGPL-3.0 | 电视端的代码基础（M14）；平台层的新修复（M4、M5），比如 Kick |
| [liuchuancong/flame_barrage](https://github.com/liuchuancong/flame_barrage) | MIT | 弹幕渲染和交互（M5、直播间） |
| [liuchuancong/media_core](https://github.com/liuchuancong/media_core) | AGPL-3.0 | 播放器会话、恢复、池化、系统媒体控制（M7、多画面） |
| [liuchuancong/flv_lzc](https://github.com/liuchuancong/flv_lzc) | MIT | FLV 和 H.265 的低延迟经验，换算成 mpv 的选项（M7） |
| 归档 v4（分支 `archive/v4`） | AGPL-3.0 | 已写好并测过的各包实现，按模块借鉴 |

- 本机副本在 `~/ref/`，平台对照笔记在 `~/ref/notes/`。
- AGPL-3.0 的代码借鉴时，注明来源仓库和提交；MIT 的保留版权声明。

## 9. 测试包和正式包

- **测试包**：Android 包名加 `.next`，和手机上用户正在用的 3.x 并存，不碰它和它的数据。Windows 测试版放在工作目录，不碰 `D:\Soft` 下的安装。
- **正式包**：包名 `com.mystyle.purelive`，覆盖安装 3.x，数据由 M9 的迁移保留。
