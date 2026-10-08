# W01.3 2026-10-08 上游对照：pure_live 321 个、pure_live_TV 24 个、media_core 44 个、flame_barrage 2 个

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)（完成，2026-10-08）
- 类型：工程（上游对照）
- 来源：D-027（每周对照上游）；第一次按 [W01.2](../W01.2-上游跟踪/README.md) 的每周流程做
- 相关：上一次 [W01.1](../W01.1-2026-10-03上游对照/README.md)；决定 D-027、D-026；开出的任务见“结果”

从 W01 子分类说明“上次看到的提交”接着看了五个上游仓库（2026-10-08 拉取），逐条对照 4.x 现在的代码（master `2c1e9900b`）。手机版上游这一周的 321 个提交里，96 个是把 4.x 的平台层、弹幕和模型改动移植过去（提交说明写着“摘取 4.x”“上游 4.x”“M5.x”），45 个是新做的录像播放页，真正要对照的修复不多。

## 看了哪些

| 仓库 | 范围 | 提交数 | 说明 |
|---|---|---:|---|
| [liuchuancong/pure_live](https://github.com/liuchuancong/pure_live)（手机和桌面版） | `20817480d` → `4bf28f0b6`（2026-10-03 ～ 10-08） | 321 | 主仓库远程 `upstream`：`git log 20817480d..upstream/master`；没有合并提交 |
| [liuchuancong/pure_live_TV](https://github.com/liuchuancong/pure_live_TV)（电视版） | `37660afc` → `6a118663`（2026-10-03 ～ 10-06） | 24 | 一半是遥控器焦点；`~/ref/pure_live_TV` 的 `origin/main` |
| [liuchuancong/media_core](https://github.com/liuchuancong/media_core)（播放核心） | `69af860` → `5b04714`（2026-10-03 ～ 10-07） | 44 | 取流管线（ingest）、画中画、弹幕层改接 flame_barrage |
| [liuchuancong/flame_barrage](https://github.com/liuchuancong/flame_barrage)（弹幕引擎） | `3eddae8` → `1f1dec4`（2026-10-03 ～ 10-04） | 2 | 按条撤回、点播时间轴 |
| [liuchuancong/flv_lzc](https://github.com/liuchuancong/flv_lzc) | 没有新提交（`162030d`） | 0 | — |

pure_live 321 个提交的归类（每类的去向见下面各节）：

| 类 | 个数 | 例子 | 结论 |
|---|---:|---|---|
| 从 4.x 移植过去的平台层、弹幕、模型 | 96 | `907a34d35`～`021741490`（各平台“摘取 4.x”、受限直播种类、开播时间）、`89248f0ff`～`133725ed7`（弹幕撤回、礼物、表情、平台公告）、`1990e1243`～`2958e35a5`（17 站聊天引擎）、`41dfe0616`、`360f2aff5`、`c2aca612b`（粉丝牌、头像、昵称提示条）、`ee6bf4c9a` | 已经有 |
| 录像播放页（应用内播放录像） | 45 | `0b23c32fa`、`796823afd`、`555c0bbd3`、`d8dc94af5`～`8434bc1c0` | 新功能 → V01.8 |
| 上游自己架构的修复和重构 | 46 | 共享层和站点自包含 `3ac0012d8`～`56a379b0d`；取流声明和 FFmpeg 转封装 `c17d9316a`～`c7298755f`、`b749c3f3e`；mpv 属性归属 `c5ada971d`；GetX 返回 `d0247eebe`、`8cf062eda`；超分 `9fed7d973` | 不适用 |
| 上游自己修好、4.x 本来就有 | 25 | `7285eb625`、`102b84523`、`db351a6d6`、`6974e8105`、`784b00da3`、刘海适配 7 个 | 已经有 |
| 壁纸、主题、字体、换台面板样式 | 21 | 壁纸 15 个、MI Sans `d8b8719f3`、换台面板 `fc5d637dd`、`555ed5d3d` | 不适用 |
| 小窗、画中画、应用内悬浮窗 | 15 | Windows 小窗 `9a845e69d`、`e96878ae3`；手机画中画 `07aa2a245`、`cb6d72901`；悬浮窗弹幕和几何 `6fabc7d0d`～`2cfbf8d3e` | 不适用（几何的想法并进 V01.5） |
| 桌面：托盘、Windows 代理、键盘快捷键 | 5 | `0a299dd00`、`8f55b49c6`、`523f84921`、`c7cf5463e`、`a4ee80b29` | 不适用（X 组开工时再看） |
| 4.x 也有的问题 | 8 | 见下节 | 开任务 |
| 新功能（录像之外） | 3 | `15cec5bbf`、`a7783b525`、`b8f5c5873` | V01.7；并进 V01.4、V01.6；一个不登记 |
| 文档（上游的移植账本） | 28 | `docs(ledger)` | 只计数 |
| 版本、CI、构建、依赖、注释、翻译搬家 | 29 | `bdce5600a`、`141b4f9b6`、`80141d545`、`e40bd2822`～`83e06baf7` | 只计数 |

pure_live_TV 24 个：遥控器焦点 12（`7ed3e452`～`2f3f2a93`）、点播和音乐 3（`868f2569`、`1bd82c26`、`ce36bcf8`）、播放运行时和 DASH 4（`6a118663`、`acf02e1a`、`661114f7`、`f6b665ae`）、同步手机版 3（`3cd93ae6`；`ca5277b2`、`afd41fdc` 4.x 已经有）、注释 1（`e8344456`）、备份勾选模块 1（`699b74e9`，并进 V01.6）。

media_core 44 个：4.x 已经有 4（`10688c5`、`c6f5917`、`e2a06bf`、`e46d763`）、小窗和画中画 8（`7319d2d`、`c073f52` 并进 V01.5，其余 6 个是桌面画中画）、取流管线 6、弹幕层改接 flame_barrage 5、内核其他 7、界面透传和录像 feed 4、mpv 列表选项 2（`2cd2bfd`、`d37c379`）、测试文档杂项 8。

flame_barrage 2 个：`efada9c` 按条撤回（4.x 已经有），`1f1dec4` 点播时间轴（不适用）。

## 4.x 也有的问题（要修）

| 上游提交 | 问题 | 4.x 的位置 | 任务 |
|---|---|---|---|
| pure_live `a858550bb` | 虎牙播放 UA 跟 simple_live 升到 `pc_exe&7100004`、`SDK(trans&2.40.0.6448)`；斗鱼匿名会话拿到的 `expire=300&fcdn=ws` 线路 5 分钟就失效，上游加 `&expire=0` | 虎牙：`packages/live_core/lib/src/sites/huya/huya_api.dart:236` 内置还是 `7090000`/`2.35.0.5996`；`huya_site.dart:117-120`、`:402-405` 启动时读上游仓库的 `assets/play_config.json`（那里也还是 `7090000`），读到就用它。斗鱼：`douyu/douyu_api.dart:623-627`（`statedLifetime`）按 `expire` 算租约、到期前 45 秒续期接上（`:159-161`），不加 `expire=0` | [E01.8](../../../E-直播平台/E01-国内五大平台/E01.8-虎牙UA和斗鱼expire/README.md)（第二档） |
| pure_live `559690d48`、`01fd4fec5` | 猫耳FM 的流只有一路 16×16 的占位画面，克拉克拉是纯色或背景图，拉满整个画面像“蓝屏”“卡住”；上游改成显示房间封面 | `packages/live_core/lib/src/sites/missevan/missevan_api.dart:70-72`（“播放器按找到的轨道来”）；`apps/pure_live/lib/features/live_play/player/player_view.dart:725-738` 的封面层 `AudioOnlyCover`（`player_status.dart:333`）只在纯音频模式下显示 | [A07.20](../../../A-界面设计/A07-直播间界面/A07.20-语音直播显示房间封面/README.md)（第三档） |
| pure_live `2e84d68d3`、`3a960050b`、`21e981da5` | BIGO 的防火墙按请求指纹降级：只带 `Mozilla/5.0` 时 `www.bigo.tv` 的接口回 418，`getInternalStudioInfo` 回 `needLogin:true` 的空壳；上游换完整浏览器请求头，并加了账号 Cookie | `packages/live_core/lib/src/sites/bigo/bigo_api.dart:308-314`：所有请求和媒体都是 3.x 的 `user-agent: Mozilla/5.0` | [E03.19](../../../E-直播平台/E03-海外平台/E03.19-BIGO请求头/README.md)（第三档） |
| pure_live `6229284a8` | 小红书分享文案里的短链是 `xhslink.com/o/<码>`，只认 `/m/` 前缀时整段粘贴打不开 | `packages/live_core/lib/src/sites/xiaohongshu/xiaohongshu_api.dart:534`（`_shortPath` 只认 `/m/`）、`:585-588`（`shortLink`）；从文案里抽链接已有（`packages/live_core/lib/src/links.dart:227` `sharedHttpUrls`） | [E04.2](../../../E-直播平台/E04-链接解析和分享口令/E04.2-小红书o前缀短链/README.md)（第三档） |
| pure_live `14d965326`、`960bcf7e3` | FC2 的 HLS 分片不带 `l_ortkn` 会话 Cookie 时 403；微博 CDN 对不带 Referer 和 UA 的连接建连后不给数据 | FC2：`packages/live_core/lib/src/sites/fc2live/fc2live_api.dart:258-264`（媒体请求头只有 UA、Origin、Referer，`l_ortkn` 只在控制连接握手里，`:188-193`）。微博：`weibo/weibo_api.dart:112-117`（媒体不带请求头；2026-09-28 实测不需要） | [E07.2](../../../E-直播平台/E07-平台巡检/E07.2-FC2和微博取流复查/README.md)（第三档，先巡检确认） |

没有第一档：五条都不在国内五大平台的主路径上，或者现在还能用（虎牙、斗鱼那条是预防，见 E01.8）。

## 可以借鉴的新功能

| 上游提交 | 内容 | 任务 |
|---|---|---|
| pure_live `15cec5bbf` | 退到后台继续播放时关掉视频解码省电，回到前台再开 | [V01.7](../../../V-需求和反馈/V01-新功能提议/V01.7-后台停止视频解码/README.md) |
| pure_live `0b23c32fa`、`796823afd`、`555c0bbd3`、`d8dc94af5` 等 45 个 | 录像在应用内播放：按房间的录像列表、每个文件记住看到哪、倍速、选集、±10 秒、小窗和画中画 | [V01.8](../../../V-需求和反馈/V01-新功能提议/V01.8-录像在应用内播放/README.md) |
| pure_live `a7783b525` 的一半 | 弹幕“海量模式”：到了就上屏，不受同屏条数上限 | 并进 [V01.4](../../../V-需求和反馈/V01-新功能提议/V01.4-同屏最大弹幕条数可以设置/README.md) 的评估 |
| pure_live `a7783b525` 的另一半、pure_live_TV `699b74e9` | 本地备份、WebDAV、设备同步共用一个“勾选模块”页：导出只写勾选的，导入只覆盖勾选的 | 并进 [V01.6](../../../V-需求和反馈/V01-新功能提议/V01.6-设备同步选择同步内容/README.md) 的评估 |
| media_core `7319d2d`、`c073f52`；pure_live `e437b5bd8`、`dc7298500`、`a25facd94` | 小窗四条边和四个角都能拖改大小；横屏、竖屏（按直播流方向）各记一套位置和尺寸 | 并进 [V01.5](../../../V-需求和反馈/V01-新功能提议/V01.5-小窗拖角改尺寸/README.md) 的评估 |
| pure_live `b8f5c5873` | 账号页“退出所有账号” | 不登记：各平台各自退出已经够用，价值低 |

## 4.x 已经有的（不用做）

- 从 4.x 移植过去的 96 个提交：本来就是 4.x 的（上游在提交说明里写了来源）。
- 连不上站点和房间读不出分开说（pure_live `6974e8105`、pure_live_TV `afd41fdc`）：`apps/pure_live/lib/shared/rooms/room_texts.dart:160`、`:176`，`TransportFailure` 和 `NetworkFailure` 显示“网络连接失败，请检查网络或代理后重试”。
- 签名地址过期时换新地址而不是重试旧的（pure_live `784b00da3`、media_core `10688c5`）：`packages/live_player/lib/src/session.dart:119-121`（网络或源失败先刷新计划再重开）、`:660-665`（中继按新计划续期）。
- “打开了但没在播”有总的期限（media_core `c6f5917`）：`session.dart:45` `sourceOpen` 18 秒，`bufferingStall` 12 秒。
- 多画面一键静音（media_core `e46d763`）：`apps/pure_live/lib/features/multiview/logic/multiview_controller.dart:794`，静音时一律 0，只有音频焦点那格出声。
- 视频暂停时弹幕跟着停（media_core `e2a06bf`）：设置“暂停时的弹幕”，小窗 `features/live_play/mini/compact_danmaku.dart:52`。
- 按条撤回弹幕（flame_barrage `efada9c`）：`compact_danmaku.dart:186` 和直播间的 `retractions`。
- 斗鱼退出清掉整组凭据（pure_live `bbb23e521`、pure_live_TV `ca5277b2`）：`apps/pure_live/lib/features/account/account_services.dart:134-149` 连 LTP0、dy_did、保存时间一起清。
- 小窗关闭按钮停掉播放（pure_live `7285eb625`）：`features/live_play/mini/floating_window.dart:98`。
- 系统媒体通知显示房间名（pure_live `db351a6d6`）：`features/live_play/logic/background_playback.dart:352`。
- 纯音频模式盖住画面、视频照常解码（pure_live `102b84523`）：`player_view.dart:725-738`。
- 刘海和挖孔（pure_live `aecc62c10`、`bb3c2c507`、`45289b01f`、`9ffb4f133`、`05610aded`、`60f2a69db`、`9a0a08d37` 的一半）：`apps/pure_live/android/app/src/main/res/values/styles.xml:18` 已是 `shortEdges`；控制栏用 `SafeArea`（`player_controls.dart:364`），Flutter 在沉浸模式下也把挖孔的安全区并进 `padding`；横屏录制角标让开刘海是 A07.11 c2。
- Android 硬解兼容（pure_live `0f2cda489` 的“花屏修复”）：`packages/live_player/lib/src/mpv_options.dart:102`（兼容模式 `mediacodec_embed`）。
- 返回先退全屏（pure_live `33499909b`）：`features/live_play/live_play_page.dart:589`（A07.4）。
- 翻译缺键（pure_live `958f72156`）：`apps/pure_live/test/i18n_test.dart`。
- 虎牙搜索带 UA（pure_live `ac69fc2c1`）：`huya_site.dart:262-265`。
- 六间房聊天服务器列表按文本解析（pure_live `462f9b45c`）：`packages/live_danmaku/lib/src/sites/sixroom.dart:168-176`。
- BIGO 要登录时说要登录（pure_live `21e981da5`）、`passRoom` 为空（`91e2c75b3`）：`bigo_api.dart:89`、`:175-185`。
- 录制不进 Android 私有目录（pure_live `3adf25585`、`015ff3b4e`、`81ba87158` 的私有目录提示）：`packages/live_record/lib/src/storage.dart:62`、`:76`，选了私有目录也按默认目录（3.x）。
- 小窗弹幕设置生效（pure_live `2ee3ee8fd`、`873344eb5`、`a4eeb7adb`）：4.x 的小窗弹幕有自己的一组设置（`compact_danmaku.dart:146-160`），上游修的是它重构时丢掉的接线。

## 不适用

- **cache-pause**（pure_live `98f20b533`、`e03f4d98a`、`c5ada971d`）：上游“直播先播两秒停下缓冲再续播”的原因是它自己设了 `cache-pause-wait=4`、`cache-secs=30`、`readahead 8`，直播边缘等不来 4 秒数据。4.x 不设 `cache-pause`、`cache-pause-wait`（用 mpv 默认的 1 秒），`cache-secs` 6、`demuxer-readahead-secs` 2（`mpv_options.dart:133-148`），和 3.x 一样（3.x 只设了 `force-seekable`，`v3.2.11:lib/player/adapters/media_kit_adapter.dart:77`）。
- **mpv 列表选项**（media_core `2cd2bfd`、`d37c379`，pure_live `9fed7d973`、`80d4fed29`）：把逗号串写进列表型属性会被当成一条。4.x 不用字符串写列表选项：请求头走 media_kit 的 `Media(httpHeaders:)`（`mpv_engine.dart:193`），没有超分着色器。
- 上游自己的新架构（取流管线 ingest、回环中继、线路声明、内核属性归属、GetX 路由和返回、facade 重构）以及它们带来的回归：4.x 自己做了播放层（W01.1 已判断）。
- 代理证书（pure_live `e2fe28aab`、`27334f412`、`ce44ab6c7`、`d11efadba`）：只在用户的代理对 HTTPS 做解密重签时出现；“开了代理就信任代理证书”有安全代价，4.x 不这样做。
- Steam 广播 CDN 按请求 IP 认（pure_live `321f184a9`、`6c29c7047`）：只在应用代理和播放器代理出口不同的时候出现，记在“留下的问题”。
- 壁纸、主题、MI Sans、换台面板样式、平台选择器 logo：4.x 的界面另有设计（A 组）；壁纸是电视端的事（A17.8）。
- 桌面：托盘、Windows 系统代理、直播间键盘快捷键（M 静音、F 全屏）、Linux 打包：Windows 客户端开工（X01）时再看。
- 手机画中画的控件和拖动（pure_live `07aa2a245`、`cb6d72901`）：上游用 media_core 自己做画中画，4.x 用系统画中画（O 组）。
- 电视版的遥控器焦点、点播和音乐、DASH 和 FFmpeg 运行时（minSdk 提到 26）：电视端、点播开工时再看（X、L 组）。
- flame_barrage `1f1dec4` 点播时间轴：点播（L 组）开工时再看。

## 结果

- 看到的提交范围（下次从这里接着看）：pure_live `4bf28f0b6`（2026-10-08）、pure_live_TV `6a118663`（2026-10-06）、media_core `5b04714`（2026-10-07）、flame_barrage `1f1dec4`（2026-10-04）、flv_lzc `162030d`；已写进 W01 子分类说明的表。
- 开出的任务：

| 任务 | 对应上游 | 档位 | 状态 |
|---|---|---|---|
| [E01.8](../../../E-直播平台/E01-国内五大平台/E01.8-虎牙UA和斗鱼expire/README.md) 虎牙播放 UA 跟到 7100004；斗鱼 5 分钟线路加 expire=0 | pure_live `a858550bb` | 第二档 | 未开始 |
| [A07.20](../../../A-界面设计/A07-直播间界面/A07.20-语音直播显示房间封面/README.md) 语音直播显示房间封面 | pure_live `559690d48`、`01fd4fec5` | 第三档 | 未开始 |
| [E03.19](../../../E-直播平台/E03-海外平台/E03.19-BIGO请求头/README.md) BIGO 请求头换完整浏览器形态 | pure_live `2e84d68d3`、`3a960050b`、`21e981da5` | 第三档 | 未开始 |
| [E04.2](../../../E-直播平台/E04-链接解析和分享口令/E04.2-小红书o前缀短链/README.md) 小红书短链认 /o/ 前缀 | pure_live `6229284a8` | 第三档 | 未开始 |
| [E07.2](../../../E-直播平台/E07-平台巡检/E07.2-FC2和微博取流复查/README.md) 巡检复查 FC2 会话 Cookie、微博媒体请求头 | pure_live `14d965326`、`960bcf7e3` | 第三档 | 未开始 |
| [V01.7](../../../V-需求和反馈/V01-新功能提议/V01.7-后台停止视频解码/README.md) 退到后台停止视频解码（提议） | pure_live `15cec5bbf` | 第三档 | 未开始 |
| [V01.8](../../../V-需求和反馈/V01-新功能提议/V01.8-录像在应用内播放/README.md) 录像在应用内播放（提议） | pure_live 录像播放页 45 个提交 | 第三档 | 未开始 |

- V01.4、V01.5、V01.6 的评估初稿各加了一句上游的新做法（“留下的问题”）。

## 验证

- 对照没有测试；每条“4.x 也有的问题”都写了 4.x 的文件:行，开出的任务各自先写改之前会失败的测试再修（平台类先用 E07 的巡检工具确认）。
- `python3 tools/docs/docs.py`、`tools/gate/gate.sh` 通过。

## 留下的问题

- 小窗弹幕的放大上限：上游 `2ee3ee8fd` 把小窗弹幕的倍率钳到 1（“小窗比房间画面小，弹幕不该更大”），4.x 在 D03.3 照上游之前的 `b2cca41c7` 放到 2（`features/live_play/logic/mini_window.dart:220`）。手机上的小窗一般不到 350 宽，碰不到；平板或桌面的大小窗里弹幕会比主画面大。K90 上看过以后再决定要不要跟（D03）。
- cache-pause：如果 K90 上出现“播一两秒停一下再续上”（尤其是 HLS 房间），先查这一条（G 组）。
- 虎牙 UA 由上游仓库的 `assets/play_config.json` 远程决定（`huya_site.dart:117-120`）：上游改这个文件会直接改变 4.x 的行为。E01.8 里一并决定要不要换成自己仓库的配置。
- Steam 直播在“应用代理开、播放器代理关”（或反过来）时分片可能 410（上游 `321f184a9`）；遇到再开 E03 任务。
- 读 `~/ref/` 的副本：在 git 工作区里做对照时，工作区隔离不让直接对 `~/ref/*` 运行 git，这次把四个仓库的 `.git` 复制到临时目录再读（副本本身没动）。建议 W02 写一句：工作区里的执行者这样读，或者由主会话把 `git log` 的输出交给执行者。
- 节奏：这次一周 391 个提交约 1.5 小时；pure_live 大部分是移植 4.x，先按提交说明里的“摘取 4.x”“上游 4.x”“M5.x”归类能省一半时间。建议照旧每周一一次。
