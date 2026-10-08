# E03 海外平台

16 个海外平台的适配器：SOOP、Twitch、Picarto、TwitCasting、niconico、SHOWROOM、CHZZK、LiveMe、TikTok、YouTube、BIGO、PandaTV、FC2、Steam、17LIVE，以及 3.2.11 下线、4.x 恢复的 Kick。在国内要用户开代理（应用代理走请求，播放代理走媒体，`apps/pure_live/lib/app/platforms.dart:13-48`）；几个平台的取流是“配方”（会话型输入）而不是地址。

## 范围

- 包括：`packages/live_core/lib/src/sites/{soop,twitch,picarto,twitcasting,niconico,showroom,chzzk,liveme,tiktok,youtube,bigo,pandalive,fc2live,steambroadcast,seventeenlive,kick}/`，它们在 `platforms.dart` 的构造（Twitch `:152-158`、SOOP `:159`、Picarto `:162`、TwitCasting `:163`、niconico `:168`、SHOWROOM `:170`、CHZZK `:171`、Kick `:172`、LiveMe `:173`、TikTok `:174`、YouTube `:175`、BIGO `:176`、PandaTV `:177`、FC2 `:178`、Steam `:179`、17LIVE `:185`），样本和测试；3.x 关注身份的迁移规则（niconico、YouTube 按主播，`platforms.dart:265-277`）。
- 不包括（归哪里）：
  - 弹幕协议 → [D01](../../D-弹幕/D01-平台弹幕协议/README.md)（D01.8 SOOP、D01.9 Twitch、D01.11 Picarto、D01.12 TwitCasting、D01.15 niconico、D01.16 SHOWROOM、D01.17 CHZZK、D01.18 LiveMe（受阻）、D01.19 TikTok（受阻）、D01.20 YouTube、D01.21 BIGO、D01.22 PandaTV、D01.23 FC2、D01.24 Steam、D01.30 17LIVE、D01.31 Kick）。
  - 会话型输入的打开（niconico 座位、FC2 控制连接、BIGO 分片解扰）在 `packages/live_media/lib/src/inputs/recipes.dart` → G 组；录制 → H 组；Twitch 的 Android TLS 和浏览器令牌后备、Kick 的原生 HTTP 通道（`apps/pure_live/lib/platform/native_http.dart:16`）→ Q 组。
  - 平台层新数据接到界面（Twitch Cookie 提示和编码、Picarto 实际档名、FC2 控制连接接手、17LIVE 名字颜色和徽章）→ [E06.2](../E06-平台层升级/E06.2-平台层新数据接到界面/README.md)；Kick 的 Windows 通道 → X01.2。

## 现状：做到哪、怎么工作的

- 用户看得到的（[FEATURES.md](../../inventory/FEATURES.md) 第 14 节）：16 个平台的播放、清晰度、弹幕（LiveMe、TikTok 除外）、搜索、关注都完成，**都没有在 K90 上专门看过**（要代理）；Twitch、Kick 的真机验证归 S02.4。

| 平台 | 搜索 | 分区 | 关注身份 | 特有的 |
|---|---|---|---|---|
| SOOP | 只搜直播中 | 完成 | 主播 id（不分大小写） | 19 禁、密码房、订阅者专用标受限（7-8 输入密码受阻） |
| Twitch | 直播和未开播 | 完成 | 登录名（不分大小写） | GraphQL 有 Android TLS、浏览器两个后备；按语言筛选（`twitchLanguages`） |
| Picarto | 直播和未开播 | 完成 | 频道名（不分大小写） | 恢复时主播换档播最好一档（11-1） |
| TwitCasting | 只搜直播中 | 完成 | 频道名（不分大小写） | 私密直播进房显示未开播（平台限制） |
| niconico | 只搜直播中 | 完成 | `user/<id>`、`ch<号>`（17-1） | 观看座位、配方取流 |
| SHOWROOM | 只搜直播中 | 完成 | 房间号 | 付费标注受阻（19-5） |
| CHZZK | 直播和未开播 | 完成 | 频道号 | 累计观看受阻（20-3） |
| LiveMe | 直播和未开播 | 无（3.x 同） | 主播 | 弹幕受阻（要登录 IM） |
| TikTok | 只能精确查频道 | 受阻（无推荐和分区，22-8） | 用户名（不分大小写） | 弹幕受阻（要签名） |
| YouTube | 只搜直播中 | 无（推荐是“直播”频道页） | 频道（23-1） | 3.x 的视频号关注启动时迁移 |
| BIGO | 推荐里筛选 | 完成 | id（不分大小写） | 匿名网页令牌、分片解扰（配方） |
| PandaTV | 直播和未开播 | 完成 | 登录 id（不分大小写） | 开播时间是韩国时间（25-12） |
| FC2 | 直播和未开播 | 完成 | 频道号 | 控制 WebSocket、三档（26-2）、配方取流 |
| Steam | 直播和未开播 | 完成 | Steam id | 国内 CDN 受阻（27-3） |
| 17LIVE | 只搜直播中 | 新增 | 房间号 | 三个地区分区；名字颜色和徽章（界面 E06.2） |
| Kick | 一页频道 | 完成 | slug（不分大小写） | 只在 Android：API 走系统 TLS |

- 内部怎么工作：和 E01、E02 一样分解析、编排两层。取流有三种：普通线路（地址 + 请求头 + 租期）；带中转的 HLS（播放层的 `LoopbackRelay` 加每个路径的 Cookie）；配方 `LivePlayUrlResolution.owned(...)`（niconico、FC2、BIGO：平台层只给参数，播放和录制各自用 `RecipeOpener` 打开，`apps/pure_live/lib/app/recording.dart:31-36`）。代理：请求按平台走应用代理，媒体走播放代理（3.x 同样分开），niconico、FC2 的 WebSocket 按 `proxy` 策略连。
- 完成度（和 3.x 对照）：3.x 的功能都在；UPGRADES 第 7、8、11、12、17、19～27、33 节和 X-1（Kick 恢复）在 2026-09-29～10-01 落地；3.x 里只有 Twitch、SOOP 等少数有弹幕，D01 补全了 14 个。

## 代码地图

| 平台 | 代码（两到三个文件合计行数） | 测试 api / site（`test(` 写法） | 接口样本 | 3.x 行数 | 任务 |
|---|---|---|---|---|---|
| SOOP | `soop/`（1267） | 54 / 31 | 31 | 698 | [E03.1](E03.1-SOOP/README.md) |
| Twitch | `twitch/`（1569） | 56 / 55 | 26 | 1029 | [E03.2](E03.2-Twitch/README.md) |
| Picarto | `picarto/`（1084） | 52 / 35 | 15 | 578 | [E03.3](E03.3-Picarto/README.md) |
| TwitCasting | `twitcasting/`（1176） | 41 / 38 | 17 | 508 | [E03.4](E03.4-TwitCasting/README.md) |
| niconico | `niconico/`（1993，含 `niconico_seat.dart`） | 76 / 64 | 13 | 1241 | [E03.5](E03.5-niconico/README.md) |
| SHOWROOM | `showroom/`（1195） | 32 / 28 | 10 | 797 | [E03.6](E03.6-SHOWROOM/README.md) |
| CHZZK | `chzzk/`（1504） | 69 / 46 | 22 | 779 | [E03.7](E03.7-CHZZK/README.md) |
| LiveMe | `liveme/`（1486） | 35 / 27 | 12 | 1068 | [E03.8](E03.8-LiveMe/README.md) |
| TikTok | `tiktok/`（1316） | 39 / 32 | 4 | 803 | [E03.9](E03.9-TikTok/README.md) |
| YouTube | `youtube/`（2160） | 46 / 56 | 27 | 1020 | [E03.10](E03.10-YouTube/README.md) |
| BIGO | `bigo/`（1550） | 43 / 40 | 9 | 927 | [E03.11](E03.11-BIGOLIVE/README.md) |
| PandaTV | `pandalive/`（1594） | 60 / 45 | 12 | 1078 | [E03.12](E03.12-PandaTV/README.md) |
| FC2 | `fc2live/`（1817，含 `fc2live_control.dart`） | 30 / 47 | 8 | 1016 | [E03.13](E03.13-FC2LIVE/README.md) |
| Steam | `steambroadcast/`（1791） | 39 / 27 | 19 | 799 | [E03.14](E03.14-Steam直播/README.md) |
| 17LIVE | `seventeenlive/`（1179） | 49 / 38 | 11（`fixtures/17live/`） | 721 | [E03.15](E03.15-17LIVE/README.md) |
| Kick | `kick/`（935） | 20 / 17 | 18 | — | [E03.16](E03.16-Kick/README.md) |

应用：`apps/pure_live/lib/app/platforms.dart`（构造、代理策略 `:13-48`、`PlatformDeps.twitchFallbacks` `:121`、`kickApi` `:126`）；`apps/pure_live/lib/app/bootstrap.dart:175-179`（Twitch 后备和 Kick 的原生通道在启动时给）；`packages/live_media/lib/src/inputs/recipes.dart`（配方打开器）。

## 3.x 基线

- `git show v3.2.11:lib/core/site/<平台>/`（合计行数见上表）。3.x 3.2.11 删掉了 `lib/core/site/kick/`（Cloudflare 拦 dart:io），只在 `lib/core/sites.dart` 的已下线列表里留着 `kick.com`。
- 3.x 已经不能构建，除 Twitch（`legacy_expected.py`）外各平台的 `expected.json` 由 `fixtures/<平台>/legacy_expected.dart` 生成。
- 必须保留：清晰度名称和 id、房间身份（niconico、YouTube 的身份变化有迁移规则）、3.x 的设置键名（`twitchLanguages`、`youtubeShowAllChat` 等，D-018）。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 平台层新数据没接到界面：Twitch Cookie 失效提示和编码、Picarto 恢复后的档名、FC2 控制连接接手、17LIVE 名字颜色和徽章 | `platforms.dart:152-158`、`:178`；直播间 | 已批准的升级用户看不到 | [E06.2](../E06-平台层升级/E06.2-平台层新数据接到界面/README.md) |
| Steam 27-7：每档的线路都是整个主列表，档位只在画质 `data` 里（`SteamBroadcastVariant.selectIn`，`steambroadcast_api.dart:82`），播放没用它限定变体，选“720p”实际仍自适应；UPGRADES 写“完成（G01.1）” | `steambroadcast_api.dart:82`、`:1024-1030` | 界面显示的档位和实际播放的不一定一致 | UPGRADES 27-7 已改“部分完成”；按档播放 → [G01.4](../../G-播放/G01-引擎/G01.4-Steam选清晰度实际仍是自适应/README.md)（2026-10-07 登记） |
| PandaTV 目录说明的中文还是旧说法（没提“新人主播”），UPGRADES 25-7 写“中文界面完成” | `apps/pure_live/assets/translations/zh.json:1152`（`pandalive_directory_scope`） | 说明和实际不符 | Z05.2 一并核对 |
| GitHub 归档分支 `archive/v4` 的 17LIVE 搜索样本里还有主播私人账户记录的原值（令牌、密码散列、邮箱、电话、IP） | 远端分支 `archive/v4` 的 `fixtures/17live/` | 隐私 | 写进本组报告：要维护者决定（重写归档分支或删掉那几个文件），没有任务管 |
| LiveMe、TikTok 弹幕受阻（要登录 IM、要网页安全 SDK 签名） | D01.18、D01.19 | 没有弹幕 | 受阻 |
| TikTok 没有推荐和分区（22-8）、SHOWROOM 付费标注（19-5）、CHZZK 累计观看（20-3）、Steam 国内 CDN（27-3）、SOOP 密码房输入密码（7-8） | 各平台 | — | 受阻（UPGRADES 写明原因） |
| SOOP 分享文本带 App 深链（7-9 后半） | 分享在 `shared/rooms/share_code.dart` | — | 未排（要先定分享格式） |
| Kick、Twitch 在电脑上没有 Android TLS 通道 | `platforms.dart:119-126` | Windows 上 Kick 不登记；巡检工具在电脑上可能被拒 | X01.2；巡检报告单独标（E07.1） |
| 都没有 K90 真机记录 | FEATURES 第 14 节 | 不知道真机上代理下的表现 | Twitch、Kick 在 S02.4；其余没有任务管 |

## 相关决定和规范

- D-001、D-004（只做 Android：Kick 只在 Android 登记）、D-017、D-018；[specs/UPGRADES.md](../../specs/UPGRADES.md) 第 7、8、11、12、17、19～27、33 节、X-1、统一原则（受限的直播仍是直播）。

## 测试和验证

- 自动测试：`cd packages/live_core && dart test test/sites/<平台>_api_test.dart test/sites/<平台>_site_test.dart`（16 个平台 32 个文件）；配方的打开在 `packages/live_media/test/`。
- 真实接口：各平台 record.md 的“真实环境检查”（2026-09-28～10-01，经代理）；以后由 [E07.1](../E07-平台巡检/E07.1-平台巡检工具/README.md) 的工具带 `--proxy` 定期跑。
- 真机：[S02 的 CHECKLIST.md](../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 5 节第 6、7 条（播放代理、Twitch 和 Kick，S02.4）；其他海外平台没有真机条目。

## 路线

1. [E06.2](../E06-平台层升级/E06.2-平台层新数据接到界面/README.md)：Twitch、Picarto、FC2、17LIVE 的界面余项。
2. [E07.1](../E07-平台巡检/E07.1-平台巡检工具/README.md)：工具做好后经代理巡检 16 个平台，失效的在这里开修复任务（标题写“接 E07.1”）。
3. 维护者决定：Steam 27-7 去 G 组、17LIVE 归档样本的隐私处理。新想法写进 V01 提议，不直接加任务。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [E 直播平台](../README.md)。

- 代码：`packages/live_core/lib/src/sites/`
- 进度：`███████████████████░` 97%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| E03.1 | SOOP | 平台 | 完成 | 2026-09-28 | 71fbb1982 | [设计或说明](E03.1-SOOP/README.md)、[记录](E03.1-SOOP/record.md) |
| E03.2 | Twitch | 平台 | 完成 | 2026-09-28 | a312c7267 | [设计或说明](E03.2-Twitch/README.md)、[记录](E03.2-Twitch/record.md) |
| E03.3 | Picarto | 平台 | 完成 | 2026-09-28 | b8bcd1eb3 | [设计或说明](E03.3-Picarto/README.md)、[记录](E03.3-Picarto/record.md) |
| E03.4 | TwitCasting | 平台 | 完成 | 2026-09-28 | 2badf4756 | [设计或说明](E03.4-TwitCasting/README.md)、[记录](E03.4-TwitCasting/record.md) |
| E03.5 | niconico | 平台 | 完成 | 2026-09-28 | 5442c7303 | [设计或说明](E03.5-niconico/README.md)、[记录](E03.5-niconico/record.md) |
| E03.6 | SHOWROOM | 平台 | 完成 | 2026-09-28 | eaca04cc0 | [设计或说明](E03.6-SHOWROOM/README.md)、[记录](E03.6-SHOWROOM/record.md) |
| E03.7 | CHZZK | 平台 | 完成 | 2026-09-28 | be431b915 | [设计或说明](E03.7-CHZZK/README.md)、[记录](E03.7-CHZZK/record.md) |
| E03.8 | LiveMe | 平台 | 完成 | 2026-09-28 | 6fe261aa8 | [设计或说明](E03.8-LiveMe/README.md)、[记录](E03.8-LiveMe/record.md) |
| E03.9 | TikTok | 平台 | 完成 | 2026-09-28 | 1ea332247 | [设计或说明](E03.9-TikTok/README.md)、[记录](E03.9-TikTok/record.md) |
| E03.10 | YouTube | 平台 | 完成 | 2026-09-28 | af6e14961 | [设计或说明](E03.10-YouTube/README.md)、[记录](E03.10-YouTube/record.md) |
| E03.11 | BIGO LIVE | 平台 | 完成 | 2026-09-28 | b336f2d27 | [设计或说明](E03.11-BIGOLIVE/README.md)、[记录](E03.11-BIGOLIVE/record.md) |
| E03.12 | PandaTV | 平台 | 完成 | 2026-09-28 | c33ee7611 | [设计或说明](E03.12-PandaTV/README.md)、[记录](E03.12-PandaTV/record.md) |
| E03.13 | FC2 LIVE | 平台 | 完成 | 2026-09-28 | eb7cd2497 | [设计或说明](E03.13-FC2LIVE/README.md)、[记录](E03.13-FC2LIVE/record.md) |
| E03.14 | Steam 直播 | 平台 | 完成 | 2026-09-28 | 9965e3c7f | [设计或说明](E03.14-Steam直播/README.md)、[记录](E03.14-Steam直播/record.md) |
| E03.15 | 17LIVE | 平台 | 完成 | 2026-09-28 | 0141660c6 | [设计或说明](E03.15-17LIVE/README.md)、[记录](E03.15-17LIVE/record.md) |
| E03.16 | Kick（恢复，仅 Android） | 平台 | 完成 | 2026-10-01 | 6c68f0010 | [设计或说明](E03.16-Kick/README.md)、[记录](E03.16-Kick/record.md) |
| E03.17 | 接 E07.1：Twitch 推荐的 GraphQL 语言参数类型变了 | 平台 | 待真机 | 2026-10-08 | — | [设计或说明](E03.17-Twitch推荐语言参数/README.md)、[记录](E03.17-Twitch推荐语言参数/record.md) |
| E03.18 | 接 E07.1：17LIVE 线路全部不通、第 2 页只给重复的一个 | 平台 | 待真机 | 2026-10-08 | — | [设计或说明](E03.18-17LIVE线路和翻页/README.md)、[记录](E03.18-17LIVE线路和翻页/record.md) |
| E03.19 | BIGO 请求头换成完整浏览器形态：只带 Mozilla/5.0 会被平台防火墙降级（接口 418、详情回 needLogin 空壳） | 平台 | 未开始 | — | — | [设计或说明](E03.19-BIGO请求头/README.md) |

## 还没完成的

- **E03.19 BIGO 请求头换成完整浏览器形态：只带 Mozilla/5.0 会被平台防火墙降级（接口 418、详情回 needLogin 空壳）**（未开始，第三档，规模 小）
  - 说明：先用 E07 的巡检工具确认 4.x 现在拿不拿得到流；换请求头后仍要登录才加账号 Cookie（另开任务，K 组）
  - 来源：上游 pure_live 2e84d68d3、3a960050b、21e981da5（W01.3 对照）

<!-- docs:生成结束 -->
