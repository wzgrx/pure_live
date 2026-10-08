# E06.2 平台层新数据接到界面：哔哩哔哩轮播、17LIVE 名字颜色和徽章、酷狗 PK 标签、Twitch Cookie 提示和编码、恢复后的实际清晰度、FC2 接手

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能
- 来源：[E06.1 的 record-2.md](../E06.1-已批准升级的余项/record-2.md)“交给界面”一节的 7 项：E06.1 第 2、4 条只做了 `live_core`、`live_danmaku`，界面上要显示的只给了数据和接口。对应 [specs/UPGRADES.md](../../../specs/UPGRADES.md) 的 1-1、8-8、11-1、26-2、B-7、B-14、B-16（V03.3 核对时这 7 条的“余下”都指到这里的各阶段）
- 旧编号：F01、T02f.2
- 相关：平台层 [E06.1](../E06.1-已批准升级的余项/README.md)；清晰度显示 C01.4（改同一处 `room_controller.dart` 的取流和刷新，最好一起做）；聊天行的样子 A08（A08.1 的名字配色规则）；哔哩哔哩访客昵称 D01.32（也改聊天行）；平台任务 [E01.1](../../E01-国内五大平台/E01.1-哔哩哔哩/README.md)、[E02.10](../../E02-其他国内平台/E02.10-酷狗直播/README.md)、[E03.2](../../E03-海外平台/E03.2-Twitch/README.md)、[E03.3](../../E03-海外平台/E03.3-Picarto/README.md)、[E03.13](../../E03-海外平台/E03.13-FC2LIVE/README.md)、[E03.15](../../E03-海外平台/E03.15-17LIVE/README.md)；决定 D-003、D-005、D-017
- 任务书：[brief.md](brief.md)；记录：[record.md](record.md)（2026-10-08 六个阶段做完，待真机；旧工作区 `worktree-agent-af6f5e80c4e19804f` 的 FC2 半成品已用上）

## 目标

平台层已经能给、界面还没用上的 7 样东西接到直播间（和多画面）：

1. 哔哩哔哩主播不在、正在轮播录像时，直播间能播这个轮播，从平台说的进度（`play_time`）开始，放完接下一个；
2. 17LIVE 等平台给的名字颜色和徽章在聊天列表里显示；
3. 酷狗 PK 时对方房间的发言在聊天列表里标“对方”；
4. Twitch 存的 Cookie 被平台拒绝时提示一次（已改为匿名观看）；建 `TwitchSite` 时告诉它播放器能解哪些编码；
5. 断线恢复时平台换了清晰度（Picarto 主播换了档），画质按钮显示实际在播的那一档；
6. FC2 画质探测时开的控制连接交给播放（少开一次连接、起播快），没用上的及时关掉。

## 3.x 和现状

| 方面 | 3.x（`~/ref/v3ref/lib/`） | 现在（文件:行） | 要做到 |
|---|---|---|---|
| 哔哩哔哩轮播 | `core/site/bilibili/bilibili_site.dart:699-711` 只认 `live_status == 1`，轮播当未开播，不能播 | 模型 `LiveStatus.carousel`（E05.2）；直播间画面状态“轮播”只有“切换直播间”“刷新”（`features/live_play/logic/room_status.dart:282-288`）；`load()` 里 `!_room.isPlayableNow` 直接进未开播（`room_controller.dart:387-392`）；平台层游客给一档“轮播”（`bilibili_site.dart:415-420`、`BilibiliApi.carouselQuality` `bilibili_api.dart:384`），取流走 `getRoundPlayVideo`（`bilibili_site.dart:436`、`:449`），`LivePlayUrlResolution.start`（`live_site.dart:194`）；`_plan` 没传 `start`（`room_controller.dart:515-519`，多画面 `multiview_controller.dart:636`） | 轮播房间有“播放轮播”入口（或直接播），`PlaybackPlan.of(start:)` 从 `play_time` 开始，`onDemand` 保持假（放完按直播结束处理，恢复时取下一段） |
| 名字颜色、徽章 | `EmptyDanmaku`（17LIVE 没有弹幕） | `LiveMessage.nameColor`、`badges`（`packages/live_core/lib/src/live_message.dart:299-300`、`:361`、`:365`；`LiveBadge` `:257`）；聊天行名字只用 `message.color`（`features/live_play/danmaku/chat_list.dart:738`），没有徽章；小窗重建消息时丢了这些字段（`mini/compact_danmaku.dart:109-117`） | 名字优先用 `nameColor`（仍过 `chatNameColor` 的 4.5:1），名字前画徽章图（约 16 像素高，加载失败不占位） |
| 酷狗 PK 对方 | 没有 | `LiveMessage.sourceRoomId`、`isFromOtherRoom`（`live_message.dart:298`、`:357`、`:368`），酷狗 400305 已上报对方聊天；聊天行没有标记（`chat_list.dart:713` `_tag()` 只有本地标签） | 名字前一个“对方”小标签 |
| Twitch Cookie 被拒 | 3.x 没有提示 | `LiveSiteCookieRefusals.cookieRefusals`（`live_site.dart:403-408`），`TwitchSite` 实现（`twitch_site.dart:196`）；应用没人监听 | 直播间（和多画面）收到时提示一次 |
| Twitch 编码 | 只要 H.264 | `TwitchSite(codecs:)`（`twitch_site.dart:147`、`:153`），应用没传（`app/platforms.dart:152-158`） | 传播放器能解的编码（mpv 自带 FFmpeg 都能软解，按硬解能力限制时在这里给） |
| 恢复后的实际清晰度 | 3.x 恢复后仍显示旧名称 | 用户点画质的 `_openQuality` 已调 `resolveAppliedPlayQuality`（`room_controller.dart:491`）；断线恢复走 `_refreshPlan`（`:546-549`），拿到的 `resolution.appliedQuality` 被丢掉；多画面的刷新同样（`multiview_controller.dart:611`） | 恢复后更新 `_qualities[_qualityIndex]`，画质按钮显示新档名称（和 C01.4 一起定规则） |
| FC2 控制连接 | 3.x `Fc2PlaybackInput` 每次自己开 | 平台层 `Fc2LiveSite(probeControl:)`（`fc2live_site.dart:59-67`、`:91`）；应用没传（`app/platforms.dart:178`）；`live_media` 的 `Fc2RecipeOpener.adopt` 按“频道:画质”配对（`packages/live_media/lib/src/inputs/recipes.dart:93-130`），探测连接是 `auto`，选了别的档就配不上；打开器只在 `app/recording.dart:34` 的 `recipeOpeners` 建一次（播放和录制共用，`bootstrap.dart:235`） | 按频道接手，任何档都用探测的连接（`Fc2LiveApi.playlistFor` 取那一档），没人接手的 20 秒后关掉 |

## 方案

- c1 哔哩哔哩轮播（UPGRADES 1-1）：画面状态“轮播”加一个“播放轮播”按钮（`PictureAction` 新值；或按 G1 选择直接播放）；点了走 `_startStream`，`_plan` 把 `resolution.start` 传给 `PlaybackPlan.of`；`isPlayableNow` 不改（免得关注分组、录制跟着变）。多画面格子同样（`multiview_controller.dart:636`）。
- c2 名字颜色和徽章（B-14）：`ChatLineView` 的紧凑行和卡片行用 `message.nameColor ?? message.color`，名字前画 `message.badges`；`compact_danmaku.dart:109` 重建消息时带上 `nameColor`、`badges`、`sourceRoomId`。
- c3 酷狗 PK（B-16）：`isFromOtherRoom` 的行名字前加“对方”小标签（新键 `danmaku_other_room`，zh、en）。
- c4 Twitch（B-7、8-8）：直播间对 `site is LiveSiteCookieRefusals` 订阅 `cookieRefusals`，收到时 `toast` 一次（新键 `twitch_cookie_expired`：“Twitch 的 Cookie 已失效，已改为匿名观看，请在账号页重新填写”）；`app/platforms.dart` 建 `TwitchSite` 时传 `codecs`。
- c5 实际清晰度（11-1）：`_refreshPlan` 拿到 `resolution` 后调 `resolveAppliedPlayQuality` 更新当前档并通知界面；多画面同样。和 C01.4（确认的编号不在列表里时按平台编号命名）一起做。
- c6 FC2（26-2 余项）：`live_media` 加 `Fc2ControlPool`（按频道、20 秒无人接手就关、同频道新连接替换旧的），`Fc2RecipeOpener` 打开时先 `pool.take(channelId)`，用 `Fc2LiveApi.playlistFor(control.playlists, quality)` 取那一档；`app/platforms.dart` 建 `Fc2LiveSite` 时传 `probeControl: (control) => Fc2ControlPool.of(site).adopt(control)`。

## 半成品（登记表 `branch`）

工作区 `/home/wzgrx/projects/pure_live/.claude/worktrees/agent-af6f5e80c4e19804f`，分支 `worktree-agent-af6f5e80c4e19804f`，HEAD `c695f45a1`（master 上已有的提交，之后 master 又前进了 47 个提交，但这几个文件只有 `room_controller.dart` 改了 1 行）。2026-10-07 逐个对照 `apps/pure_live/lib`、`apps/pure_live/test`、`packages/live_core`、`packages/live_media` 的结果：**只改了一个文件、没有提交、没有测试**：

- `packages/live_media/lib/src/inputs/recipes.dart`（+90 行左右）：新类 `Fc2ControlPool`（`unclaimedLifetime` 20 秒、可注入计时器、`static of(Fc2LiveSite)` 用 `Expando` 每个适配器一个池、`adopt`/`take`/`close`/`length`）；`Fc2RecipeOpener` 改成持有 `pool`，`adopt` 转给池，`open` 先 `pool.take(fc2.channelId)`，用 `Fc2LiveApi.playlistFor(control.playlists, fc2.quality)?.url ?? control.playlist` 取地址。
- 没做：`app/platforms.dart` 传 `probeControl`；池的测试；c1～c5 一样都没动。

即 c6 的 `live_media` 一半做了，可以直接拿来用（复制这段 diff，补测试）。

## 验证

- 自动测试：每个 c 至少一个（具体见 [brief.md](brief.md)“测试”）；用仓库样本（`fixtures/17live`、`fixtures/kugoulive/danmaku/S09` 等）和假平台，不访问真实平台。
- 真机：哔哩哔哩轮播在 K90 上看（游客能做）；Twitch、17LIVE、Picarto、FC2 要代理，酷狗 PK 要碰上时间，能看就看，看不了写进记录。待真机。

## 定稿（2026-10-08，按 D-003 取建议 A，维护者授权执行者选）

- **G1 轮播入口：A，画面上加“播放轮播”按钮，点了才播。** 画面状态“轮播”的两个按钮从“切换直播间、刷新”改成“播放轮播（主）、切换直播间”；只对能播轮播的平台（现在只有哔哩哔哩，`carouselPlatforms`）这样，别的平台的轮播照旧。理由：3.x 不播轮播，直接播会让“进房就有声音”的老习惯在主播没开播时也出声；按钮和画面上已有的“重试”“从头播放”是同一种做法。刷新不再占按钮：60 秒的自动刷新发现开播会自己载入直播。多画面的轮播格子在说明下面加同样的按钮（窄格子不放，和“重试”一样）。
- **G2 “对方”标签和徽章：照 A08.1 聊天行。** “对方”用和“本地”同一个小块（`ChatChip`：圆角 9、左右 6、12 号 600），配色用第三色容器（`tertiaryContainer`／`onTertiaryContainer`），和“本地”的主色容器分开；徽章 16 像素高、按平台给的顺序，一行里依次是“对方”、徽章、粉丝牌、名字，图片没加载出来或加载失败时不占位（连间隔也没有）。名字颜色仍过 `chatNameColor` 的 4.5:1。

## 留下的问题
- 17LIVE 徽章的绘制顺序按字段顺序，没和网页核对（E06.1 记录）；`getRoundPlayVideo` 只用合成回答测过，没有真实样本。
- 登录后的哔哩哔哩轮播 `getRoomPlayInfo` 会不会给地址没有核实（E01.1 留下的问题）。
