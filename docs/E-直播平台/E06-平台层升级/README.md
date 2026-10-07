# E06 平台层升级

[specs/UPGRADES.md](../../specs/UPGRADES.md) 里已批准、跨了好几个平台或者平台层做完还要接到应用里的升级：E01～E03 各平台任务和 2026-09-29 的“升级落地”做不完的余项，在这里收尾。

## 范围

- 包括：
  - E06.1：2026-10-02 一次做完的余项（UPGRADES 状态列回填；平台层和弹幕层的 8 条：A-3、A-6、B-7、B-16、11-1、1-1、B-14、8-8；`live_core` 收尾 4 条；列表、数据、文字）。
  - E06.2：E06.1 交回的界面余项（1-1、8-8、11-1、26-2、B-7、B-14、B-16），改应用 `features/live_play/`、`features/multiview/`、`app/platforms.dart`、`packages/live_media` 的 FC2 打开器。
  - E06.3：UPGRADES 6-1（YY FLV 优先）在应用里打开开关、录制任务的旧画质 id 换算。
  - 以后：UPGRADES 里平台层“部分完成”的余项需要接到应用时，在这里开任务。
- 不包括（归哪里）：
  - 只属于一个平台的升级（例如 7-9 SOOP 开播时间、23-2 YouTube 推荐）：在平台自己的任务里做完了，见 [E01](../E01-国内五大平台/README.md)～[E03](../E03-海外平台/README.md)。
  - 弹幕协议层的升级（附录 B、C 的弹幕条目）→ [D01](../../D-弹幕/D01-平台弹幕协议/README.md)；聊天行的样子 → A08。
  - 清晰度命名规则（录制和直播间一致）→ C01.4（和 E06.2 第 5 阶段改同一处）；英文界面下平台层的中文文字 → Z05.2；京东直播间模糊背景 28-3 → A07.16；YouTube 硬解 22-3 → G01.2；Kick 的 Windows 通道 X-1 → X01.2。

## 现状：做到哪、怎么工作的

- 用户看得到的（2026-10-07）：
  - E06.1 完成的：快手从卡片进房标题是直播标题而不是主播简介；卡片主播名后“已播 N 分钟”；观看记录里轮播、封禁的卡片有标记；完整备份带网络电视列表和多画面会话；投屏标题“主播名 - 标题”；分区页目录说明、“各平台口径说明”改成通俗文字。
  - 平台层有了、界面还没接的（E06.2）：哔哩哔哩轮播能播（游客走 `getRoundPlayVideo`，从 `play_time` 开始）、17LIVE 名字颜色和徽章、酷狗 PK“对方”、Twitch Cookie 失效提示和编码、恢复后的实际档名、FC2 探测连接接手。
  - YY 仍是移动 HLS 在前（“高清 · 720p”“流畅 · 360p”）；FLV 优先的开关 `YySite.flvFirst` 默认关，应用没打开（E06.3）。
- 内部怎么工作：平台层新加的东西都是“可选”的：新字段有默认值（`LiveMessage.nameColor` 为 null、`badges` 为空、`sourceRoomId` 为空；`LivePlayUrlResolution.start`、`appliedQuality` 为 null），新能力是可选接口（`LiveSiteCookieRefusals`）或构造参数（`TwitchSite(codecs:)`、`Fc2LiveSite(probeControl:)`、`YySite(flvFirst:)`），应用不接时行为和以前一样。所以平台层可以先合并，界面后接。
- 完成度：UPGRADES 222 条主表 2026-10-03 核对后完成 196、部分完成 17、受阻 9（[UPGRADES.md](../../specs/UPGRADES.md) 第 33 行）。部分完成里归本子分类的 8 条（1-1、6-1、8-8、11-1、26-2、B-7、B-14、B-16）都已有任务；仍“未排”的 3 条：7-9 SOOP 分享深链（要先定分享格式）、C-17 快手登录后直播搜索、C-22 CC 登录后弹幕（都要用户的登录 Cookie，V03.3 列为“需要维护者决定”）。

## 代码地图

平台层（已完成，E06.1）：

| 文件 | 职责 | 条目 |
|---|---|---|
| `packages/live_core/lib/src/live_site.dart`（518 行） | `LivePlayUrlResolution.appliedQuality`（`:190`）、`start`（`:194`）；`resolveAppliedPlayQuality`（`:224`）认 `appliedQuality`；`LiveSiteCookieRefusals`（`:403`） | 11-1、1-1、B-7 |
| `packages/live_core/lib/src/live_message.dart`（434） | `LiveBadge`（`:257`）、`sourceRoomId`（`:357`）、`nameColor`（`:361`）、`badges`（`:365`）、`isFromOtherRoom`（`:368`） | B-14、B-16 |
| `packages/live_core/lib/src/live_room.dart` | `fillFromDetail` 补标题（`:652`） | A-3 |
| `packages/live_core/lib/src/hls_master.dart` | `HlsStreamInf`（`:281`，YouTube、PandaTV 共用） | G01.1 收尾 |
| `sites/bilibili/bilibili_site.dart` | 游客轮播一档（`:415-420`）、`_carousel`（`:436`、`:449`） | 1-1 |
| `sites/twitch/twitch_site.dart` | `codecs`（`:147`）、`cookieRefusals`（`:196`） | 8-8、B-7 |
| `sites/fc2live/fc2live_site.dart` | `probeControl`（`:59-91`） | 26-2 |
| `sites/yy/yy_site.dart`、`yy_api.dart` | `flvFirst`（`yy_site.dart:36`、`:407`）、`flvQualityId`（`yy_api.dart:756`）、FLV 租期（`:772`） | 6-1 |
| `packages/live_danmaku/lib/src/sites/kugoulive.dart`、`seventeenlive.dart` | 酷狗 400305 对方聊天、17LIVE 名字颜色和徽章 | B-16、B-14 |

应用（待接，E06.2、E06.3）：

| 文件 | 要改的地方 |
|---|---|
| `apps/pure_live/lib/app/platforms.dart`（278） | `TwitchSite` 传 `codecs`（`:152-158`）、`Fc2LiveSite` 传 `probeControl`（`:178`）、`YySite` 传 `flvFirst: true`（`:160`） |
| `features/live_play/logic/room_controller.dart` | 轮播走取流（`:387-392`）、`_plan` 传 `start`（`:515-519`）、`_refreshPlan` 调 `resolveAppliedPlayQuality`（`:546-549`）、订阅 `cookieRefusals` |
| `features/live_play/logic/room_status.dart` | 轮播画面状态加“播放轮播”（`:282-288`） |
| `features/live_play/danmaku/chat_list.dart`、`mini/compact_danmaku.dart` | 名字颜色、徽章、“对方”（`chat_list.dart:713-760`）；小窗重建消息带上新字段（`compact_danmaku.dart:109`） |
| `features/multiview/logic/multiview_controller.dart` | 刷新后实际档名（`:611`）、`_plan` 传 `start`（`:636`） |
| `packages/live_media/lib/src/inputs/recipes.dart` | `Fc2RecipeOpener` 按频道接手（`:93-130`；半成品在 E06.2 的旧工作区） |
| `packages/live_record/lib/src/resolver.dart` | YY 旧画质 id 换算（`:234-236`） |

测试：E06.1 加的用例分布在 `packages/live_core/test/sites/`（快手、Twitch、哔哩哔哩、PandaTV、FC2）、`packages/live_core/test/hls_master_test.dart`、`packages/live_danmaku/test/sites/`（酷狗、17LIVE）、`apps/pure_live/test/shared/room_lists_test.dart`、`test/shared/backup_extras_test.dart`、`test/i18n_test.dart`、`packages/live_cast/test/controller_test.dart`。

## 3.x 基线

- 3.x 没有这些升级：哔哩哔哩轮播当未开播（`git show v3.2.11:lib/core/site/bilibili/bilibili_site.dart` 的 `:699-711`）；17LIVE、酷狗没有弹幕（`EmptyDanmaku`，`lib/core/site/seventeenlive/seventeenlive_site.dart:38`、`lib/core/site/kugoulive/kugou_live_site.dart:42`）；Twitch 只要 H.264、Cookie 失效不提示（`lib/core/site/twitch/twitch_site.dart:38`、`:146`、`:560-577`）；YY 先 stream-manager 但请求一直坏，实际是移动 HLS（`lib/core/site/yy/yy_site.dart:437-445`）；快手详情把简介当标题（`lib/core/site/kuaishou/kuaishou_site.dart:292`、`:469`）。
- 必须保留：3.x 的设置键名和含义（D-018；这些升级都没有新设置）；关注分组（轮播在“未开播”）；录制不录轮播。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 平台层的 7 项界面没接 | 见上表“应用（待接）” | 已批准的升级用户看不到 | [E06.2](E06.2-平台层新数据接到界面/README.md)（暂停，0/6） |
| `Fc2RecipeOpener.adopt` 按“频道:画质”配对，探测连接是 `auto`，就算接上也几乎配不上 | `packages/live_media/lib/src/inputs/recipes.dart:104-118` | 接了 `probeControl` 反而会挂着没人关的连接 | E06.2 第 6 阶段（半成品 `Fc2ControlPool` 已改成按频道） |
| YY FLV 优先没打开 | `app/platforms.dart:160` | 延迟高、少一档“蓝光” | [E06.3](E06.3-YY优先用FLV/README.md) |
| E06.1 登记为“完成”，两份记录的“要在 K90 上看的”9 条（`record.md` 5 条、`record-2.md` 4 条；拆开是 11 项，见 E06.1 README“验证”）都没有结果 | [E06.1 record.md](E06.1-已批准升级的余项/record.md)、[record-2.md](E06.1-已批准升级的余项/record-2.md) | 不符合 PROCESS 3.2 | 写进本组报告：建议能直接看的 5 条并入 S02.6，其余随 E06.2 的真机验证 |
| Steam 27-7（按档位选变体）：每档的线路都是整个主列表，档位只在画质的 `data` 里，播放没用它限定变体，选“720p”实际仍是自适应 | `sites/steambroadcast/`（`SteamBroadcastVariant.selectIn`）；UPGRADES 27-7 写“完成（G01.1）” | 界面显示的档位和实际播放的不一定一致 | 写进本组报告：建议 UPGRADES 27-7 改回“部分完成”，在 G 组开任务 |
| 平台层的中文文字（公告、目录说明、画质名、分区名）在英文界面仍是中文 | 各平台 `*_api.dart` | 英文界面混中文 | Z05.2 |

## 相关决定和规范

- D-003（E06.1 两处选择、E06.2 的 G1、G2 按建议 A）、D-016 和 D-024（E06.1 删了 930 个翻译键；以后不再清理）、D-017、D-018。
- [specs/UPGRADES.md](../../specs/UPGRADES.md)：统一原则（受限的直播仍是直播、默认编码）和本页提到的条目；[V03.3 核对](../../V-需求和反馈/V03-审查和调研/V03.3-功能清点和已批准升级核对/README.md)（第 74～75 行：这些条目的去向）。

## 测试和验证

- 自动测试：平台层 `cd packages/live_core && dart test`、`cd packages/live_danmaku && dart test`；应用 `cd apps/pure_live && flutter test test/shared/ test/i18n_test.dart`。E06.2、E06.3 的用例写在各自的任务书里。
- 真机：E06.1 的 9 条（拆开 11 项）见“已知问题”；E06.2、E06.3 的步骤在各自的任务书“真机验证”。[S02 的 CHECKLIST.md](../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 5 节第 1 条（备份恢复）、第 7 条（Twitch、Kick）也覆盖一部分。

## 路线

1. [E06.3](E06.3-YY优先用FLV/README.md)（第二档，小）：打开 `flvFirst`、换算旧 id，先在 K90 上看 FLV 续签。
2. [E06.2](E06.2-平台层新数据接到界面/README.md)（第二档，中，6 个阶段）：从哔哩哔哩轮播开始；第 5 阶段和 C01.4 一起做；第 6 阶段用旧工作区的半成品。
3. 以后：UPGRADES 仍“未排”的 7-9、C-17、C-22 等维护者决定后再开任务；新想法写进 V01 提议，不直接加任务。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [E 直播平台](../README.md)。

- 代码：`packages/live_core`、`app/platforms.dart`
- 进度：`████████░░░░░░░░░░░░` 40%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| E06.1 | 已批准升级的余项（UPGRADES 回填、平台层和弹幕层、列表、数据、文字） | 平台 | 完成 | 2026-10-02 | 4f1a8b4a8 | [设计或说明](E06.1-已批准升级的余项/README.md)、[记录](E06.1-已批准升级的余项/record.md)、[记录 2](E06.1-已批准升级的余项/record-2.md) |
| E06.2 | 平台层新数据接到界面：哔哩哔哩轮播、17LIVE 名字颜色和徽章、酷狗 PK 标签、Twitch Cookie 提示和编码、恢复后的实际清晰度、FC2 接手 | 功能 | 暂停 | — | — | [设计或说明](E06.2-平台层新数据接到界面/README.md)、[任务书](E06.2-平台层新数据接到界面/brief.md) |
| E06.3 | YY 优先用 FLV：应用打开 YySite.flvFirst，换算存下的画质 id（UPGRADES 6-1） | 平台 | 未开始 | — | — | [设计或说明](E06.3-YY优先用FLV/README.md)、[任务书](E06.3-YY优先用FLV/brief.md) |

## 还没完成的

- **E06.2 平台层新数据接到界面：哔哩哔哩轮播、17LIVE 名字颜色和徽章、酷狗 PK 标签、Twitch Cookie 提示和编码、恢复后的实际清晰度、FC2 接手**（暂停，第二档，规模 中）
  - 阶段：哔哩哔哩轮播 → 名字颜色和徽章 → 酷狗 PK → Twitch → 实际清晰度 → FC2
  - 接着做：按任务书从头做；旧工作区里的半成品可参考
  - 分支：worktree-agent-af6f5e80c4e19804f（半成品，未提交）
  - 说明：UPGRADES 1-1、8-8、11-1、B-7、B-14、B-16 和 26-2 的界面余项都在这里（V03.3 核对）；“实际清晰度”阶段和 C01.4 改同一处（room_controller.dart 的取流和刷新），最好一起做
- **E06.3 YY 优先用 FLV：应用打开 YySite.flvFirst，换算存下的画质 id（UPGRADES 6-1）**（未开始，第二档，规模 小）
  - 阶段：打开 flvFirst，核对默认档 → 录制任务旧画质 id 换算
  - 来源：UPGRADES 6-1（V03.3 核对）

<!-- docs:生成结束 -->
