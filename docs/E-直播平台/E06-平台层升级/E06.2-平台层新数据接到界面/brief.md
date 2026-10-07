# E06.2 平台层新数据接到界面：任务书

## 背景

- 来源：[E06.1 的 record-2.md](../E06.1-已批准升级的余项/record-2.md)“交给界面（我没有改，要在应用里接）”第 1～7 条。E06.1 第 2、4 条（2026-10-02）按授权只改了 `packages/live_core`、`packages/live_danmaku`，界面要用的数据和接口都给了，应用没接。对应 [specs/UPGRADES.md](../../../specs/UPGRADES.md) 的 1-1（第 41 行）、8-8（第 69 行）、11-1（第 84 行）、26-2（第 195 行）、B-7（第 276 行）、B-14（第 283 行）、B-16（第 285 行），这 7 条的状态都是“部分完成，余下 → E06.2（阶段 …）”。
- 现象（现在用户看到的）：
  1. 哔哩哔哩一个正在轮播的房间：画面写“轮播”，只有“切换直播间”“刷新”，不能播；
  2. 17LIVE 聊天里的名字都是一个颜色，没有平台的徽章；
  3. 酷狗 PK 时，对方房间的人说话混在本房间的聊天里，分不出来；
  4. Twitch 存的 Cookie 失效后，直播间悄悄改成匿名，用户不知道要重新填；
  5. Picarto 主播中途换了档，断线恢复后画质按钮还写旧档名；
  6. FC2 进房时画质探测开过一次控制连接，播放又开一次（多一次握手、多占一个座位）。
- 为什么现在做：第二档；都是已批准升级的最后一步，平台层做完了一周没接上。
- 已经做过的：E06.1（`069be46e4`）；暂停的半成品见下面“现状”最后一条。

## 目标和验收

1. 定稿（阶段 1 开头，按 D-003 由维护者选建议 A，写进 README）：G1 轮播房间是 A“画面上加‘播放轮播’按钮，点了才播” / B 进房直接播；G2 “对方”标签、徽章的样子照 A08.1 聊天行（标签用和“本地”标签同样的小块，徽章 16 像素高）。
2. 哔哩哔哩轮播（游客）：轮播房间按 G1 能播，起点是平台的 `play_time` 秒（`LivePlayUrlResolution.start` 传到 `PlaybackPlan.of(start:)`）；放完按直播结束处理，恢复时取到下一段；关注分组、录制不受影响（`isPlayableNow` 不改）。多画面格子同样。
3. 17LIVE：聊天行（紧凑行和卡片行）名字用 `nameColor`（为空用 `color`，都过 `chatNameColor` 的 4.5:1），名字前按顺序画 `badges`（加载失败不占位）；应用内小窗、画中画的弹幕不丢这些字段。
4. 酷狗：`isFromOtherRoom` 的聊天行名字前有“对方”标签（新键 `danmaku_other_room`，zh“对方”、en“Opponent”）。
5. Twitch：存的 Cookie 被拒时直播间（和多画面）提示一次 `twitch_cookie_expired`；同一份 Cookie 不重复提示；`TwitchSite` 建时传 `codecs`。
6. 断线恢复后平台换了档：画质按钮和画质面板显示实际在播的档名（规则和 C01.4 一致）；多画面同样。
7. FC2：探测的控制连接交给播放，任何档都能用；20 秒没人用就关；同一频道新的替换旧的；应用退出时全部关。
8. 每个阶段各有测试；`apps/pure_live`、`packages/live_media` 测试和门禁通过；`tools/gate/ui_baseline.json` 不增加。

## 现状（读代码得出，写文件:行）

- 轮播：画面状态 `room_status.dart:282-288`（`PictureStateKind.carousel`，动作 `switchRoom`、`refresh`；`PictureAction` 在 `:70`）；`room_controller.dart:387-392`：`!_room.isPlayableNow` → `RoomStage.offline`，不取流；`_plan`（`:515-519`）调 `PlaybackPlan.of(resolution, preferH264:, onDemand: _room.isRecord)`，没传 `start`；`PlaybackPlan.of(..., Duration? start)` 在 `packages/live_media/lib/src/source.dart:156`，`start` 一路到 `live_player/lib/src/session.dart:487` 和 `mpv_engine.dart:167`。平台层：`bilibili_site.dart:415-420`（游客只有一档 `carouselQuality`）、`:436`（这一档走 `_carousel`）、`:449`（`getRoundPlayVideo` → `x/player/playurl`，html5 MP4，`StreamFormat.other`）；`live_site.dart:191-194`（`start`）。多画面：`multiview_controller.dart:636`。
- 聊天行：`features/live_play/danmaku/chat_list.dart`：`_tag()`（`:713`，只有本地标签）、`_fans()`（`:720`）、`_compact()`（`:735-760`，名字色 `chatNameColor(message.color, …)` `:738`）；卡片样式在同一个 `ChatLineView`（`:572` 起）。模型：`live_message.dart:257` `LiveBadge`、`:298-300` 构造、`:357` `sourceRoomId`、`:361` `nameColor`、`:365` `badges`、`:368` `isFromOtherRoom`。小窗：`mini/compact_danmaku.dart:109-117` 重建 `LiveMessage` 时只带 `type`、`userName`、`userId`、`message`、`color`、`messageId`、`isLocal`。
- Twitch：`live_site.dart:400-408`（`LiveSiteCookieRefusals`）、`twitch_site.dart:196`（`cookieRefusals` 流）、`:147`/`:153`/`:166`（`codecs`）、`:552`（请求 usher 时用）；应用 `app/platforms.dart:152-158`。
- 实际清晰度：`room_controller.dart:462-512` `_openQuality`（`:491` 调 `resolveAppliedPlayQuality`）；`:546-549` `_refreshPlan` 只返回 `_plan(resolution)`；`multiview_controller.dart:592`（打开时已调）、`:611`（刷新没调）。`resolveAppliedPlayQuality` 在 `live_site.dart:224`。C01.4 也要改这两处。
- FC2：`fc2live_site.dart:59-67`、`:91`（`probeControl`）；`app/platforms.dart:178` 没传；`packages/live_media/lib/src/inputs/recipes.dart:93-130`：`Fc2RecipeOpener.adopt` 按 `'${channelId}:${requestedQuality}'` 存（`:104-110`），`open` 按 `'${fc2.channelId}:${fc2.quality}'` 取（`:117`）、只用 `control.playlist`；打开器在 `app/recording.dart:31-36` 的 `recipeOpeners` 建一次，播放和录制共用（`bootstrap.dart:235`）。
- **半成品**（登记表 `branch`：`worktree-agent-af6f5e80c4e19804f`，工作区 `/home/wzgrx/projects/pure_live/.claude/worktrees/agent-af6f5e80c4e19804f`，HEAD `c695f45a1`，未提交）：只改了 `packages/live_media/lib/src/inputs/recipes.dart`：新类 `Fc2ControlPool`（`unclaimedLifetime` 默认 20 秒、计时器可注入、`static of(Fc2LiveSite)` 用 `Expando`、`adopt`/`take`/`close`/`length`），`Fc2RecipeOpener` 改为持有 `pool`、`open` 先 `pool.take(channelId)` 并用 `Fc2LiveApi.playlistFor(control.playlists, fc2.quality)`。没有测试，没有接 `platforms.dart`；其他 5 个阶段没动。用法：在那个工作区 `git diff packages/live_media` 拿到 diff，在新分支上应用后补测试（master 上这个文件从 `c695f45a1` 起没变）。

## 3.x 基线

- 3.x 哔哩哔哩：`git show v3.2.11:lib/core/site/bilibili/bilibili_site.dart` 的 `:699-711` 只认 `live_status == 1`，轮播当未开播；3.x 没有播放轮播。
- 17LIVE、酷狗：3.x 是 `EmptyDanmaku`，没有聊天（`lib/core/site/seventeenlive/seventeenlive_site.dart`、`lib/core/site/kugoulive/kugou_live_site.dart`）。
- Twitch：3.x 只请求 H.264，Cookie 失效不提示（`lib/core/site/twitch/twitch_site.dart`）。
- FC2：3.x `Fc2PlaybackInput` 每次播放自己开控制连接。
- 要保留的：聊天行现有的样子和配色规则（A08.1）；轮播在关注里归“未开播”（E05.2、I04.1）；录制不录轮播（H01.1）。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节分阶段、第 8 节合并审查、第 14 节规则）。
2. `docs/specs/ENGINEERING.md`；`docs/specs/UI.md` 第 3 节、第 8.1 节（语义色）、第 9.2 节（列表局部刷新）。
3. 本文件夹的 `README.md`；`docs/E-直播平台/E06-平台层升级/E06.1-已批准升级的余项/record-2.md`（逐条对照 c3～c10、“交给界面”）；`docs/A-界面设计/A08-弹幕界面/A08.1-弹幕列表和弹幕设置页/README.md`（聊天行）；`docs/C-直播间/C01-进房和房间逻辑/C01.4-直播间清晰度显示实际档/brief.md`（和实际清晰度同一处）。

## 范围

- 可以改：`apps/pure_live/lib/features/live_play/`（`logic/room_controller.dart`、`logic/room_status.dart`、`player/player_status.dart`、`danmaku/chat_list.dart`、`mini/compact_danmaku.dart`）、`features/multiview/logic/multiview_controller.dart`、`app/platforms.dart`、翻译 `assets/translations/zh.json`、`en.json`（只加键）；`packages/live_media/lib/src/inputs/recipes.dart` 和它的测试；对应测试；本文件夹。
- 不能改：`packages/live_core`、`packages/live_danmaku`（只读；需要改时停下写进报告）；`LiveRoom.isPlayableNow` 和关注分组；聊天行已有的配色规则；其他组的界面；版本号、`assets/version.json`、`assets/releases.json`；签名配置；3.x 的设置键名和含义。

## 方案和阶段

| 阶段 | 做什么（对应 README 的 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 哔哩哔哩轮播 | 定 G1、G2（写进 README）；c1：轮播房间的“播放轮播”（`PictureAction.playCarousel` 或按 G1 直接播），`room_controller` 对 `carousel` 走 `_startStream`；`_plan` 和多画面的 `_plan` 传 `start: resolution.start` | `room_status.dart`、`player_status.dart`、`room_controller.dart`、`multiview_controller.dart`、翻译 | 测试：假平台轮播房间，点按钮后 `session.open` 收到的计划 `start == 37 秒`、`onDemand` 假；关注分组不变 |
| 2 名字颜色和徽章 | c2：`ChatLineView` 两种样式用 `nameColor`、画 `badges`；`compact_danmaku.dart` 带上 `nameColor`、`badges`、`sourceRoomId` | `chat_list.dart`、`compact_danmaku.dart` | 测试：`nameColor` 优先于 `color`、对比度不够时退回次要色；两个徽章按顺序出现、图片失败不占位；小窗收到的消息带这些字段 |
| 3 酷狗 PK | c3：“对方”标签 | `chat_list.dart`、翻译 | 测试：`sourceRoomId` 非空的行有 `ValueKey('live-play-chat-other-room')`；用 `fixtures/kugoulive/danmaku/S09-pk-chat` 解出的消息 |
| 4 Twitch | c4：订阅 `cookieRefusals` 提示一次（直播间 dispose 时取消订阅）；`platforms.dart` 传 `codecs` | `room_controller.dart`、`multiview_controller.dart`、`platforms.dart`、翻译 | 测试：假平台实现 `LiveSiteCookieRefusals`，发两次只提示一次；`platforms_test.dart` 新用例：`TwitchSite` 拿到的编码集合 |
| 5 实际清晰度 | c5：`_refreshPlan` 和多画面刷新调 `resolveAppliedPlayQuality`，更新当前档并通知；和 C01.4 一起定命名规则 | `room_controller.dart`、`multiview_controller.dart` | 测试：恢复时 `resolution.appliedQuality` 是“1080p”，画质按钮从“720p”变“1080p”、不标未确认 |
| 6 FC2 | c6：拿半成品的 `Fc2ControlPool`，补测试；`platforms.dart` 传 `probeControl`（`late final` 适配器，回调里 `Fc2ControlPool.of(site).adopt`） | `recipes.dart`、`platforms.dart`、`packages/live_media/test/` 新文件 | 测试：池按频道接手、任何档用 `playlistFor`、20 秒（注入计时器）后关掉、同频道替换旧的、`close` 全关 |

每个阶段都要能单独合并（门禁通过、不留半截功能）。阶段顺序按用户最先感觉到的：轮播（国内、游客能看）在前。

## 测试

- 修 bug 式的“改之前会失败”：阶段 1 `apps/pure_live/test/features/live_play/live_play_controller_test.dart` 新用例 `'a carousel room plays its video from play_time (1-1)'`；阶段 5 同文件 `'a recovery that switched quality shows the quality now played (11-1)'`。
- 聊天行：`apps/pure_live/test/features/live_play/live_play_tabs_test.dart` 加 B-14、B-16 用例；颜色断言照现有“名字 4.5:1”的写法（`chat_names_test.dart`）。
- 平台接线：`apps/pure_live/test/platforms_test.dart` 加 Twitch `codecs`、FC2 `probeControl` 两个用例。
- FC2 池：`packages/live_media/test/fc2_control_pool_test.dart`（新）。
- 界面：轮播按钮竖屏和横屏全屏各一个布局测试。
- 测试里的定时器至少 1 秒（池的 20 秒用注入的计时器）；不访问真实平台（D-017）。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 游客，热门 → 哔哩哔哩，找一个卡片标“轮播”的房间进去 | 画面写“轮播”，有“播放轮播”（G1 A） |
| 2. 点“播放轮播” | 几秒内出画面，不是从视频开头开始；画质只有“轮播” |
| 3. 等这段放完（或拖到结尾附近） | 自动接下一段，不报错 |
| 4. 关注这个主播，回关注页 | 仍在“未开播”组 |
| 5.（有代理时）17LIVE 进一个聊天多的房间 | 名字有颜色、前面有徽章；离开成应用内小窗，小窗弹幕名字照常 |
| 6. 酷狗 PK 中的房间（碰上时） | 对方房间的发言名字前有“对方” |
| 7.（有代理时）账号页填一个失效的 Twitch Cookie，进 Twitch 直播间 | 提示一次“Cookie 已失效，已改为匿名观看”，照常播放 |
| 8.（有代理时）FC2 进房 | 起播比改之前快（少一次控制连接）；切换清晰度能播 |

## 风险和注意

- `room_controller.dart` 同时被 C01.4（清晰度命名）、E05.3（不改它，只改模型）改；阶段 5 最好和 C01.4 一起做或紧挨着做，先合并的那个写清楚改了哪几行。
- 聊天行同时被 D01.32（哔哩哔哩访客昵称，待真机）改过；阶段 2、3 别动 `ChatNameHintBar` 和打码昵称的分支。
- 轮播是 MP4 点播文件，`onDemand` 要保持假（E06.1 记录：放完按直播结束处理，恢复时取下一段）；设成真会在结尾停住。
- FC2 池用 `Expando` 挂在适配器上，测试里每个用例新建适配器，避免池跨用例残留；`platforms.dart` 里适配器和回调互相引用，用 `late final`。
- 订阅 `cookieRefusals` 要在直播间释放时取消，多画面每个格子都订阅时只提示一次（按平台去重）。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 分支 `ai/E06.2` 或本机工作区（不要在旧工作区 `agent-af6f5e80c4e19804f` 上继续，它的基线落后 master 47 个提交）；提交信息以 `[E06.2]` 开头（英文），一个阶段一个提交；不推 master。
- 提交前：`apps/pure_live`、`packages/live_media` 跑 `dart format --output=none --set-exit-if-changed .`、analyze、测试；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”、更新登记表的 `done`、`next`、`branch`（做完阶段 6 后旧工作区可以删，删之前确认 diff 已经用上）。

## 报告（中文，简洁）

G1、G2 的结论；每个阶段做到没有；测试数量（改之前失败几个）；改了哪些文件；新翻译键；半成品用了多少；要在真机上看的；和 C01.4 怎么分的；可能冲突的文件。
