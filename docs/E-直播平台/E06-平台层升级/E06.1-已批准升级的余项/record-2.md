# E06.1 第 2、4 条 记录（平台层、弹幕层）

- 日期：2026-10-02
- 范围：[E06.1 README](README.md) “要做的”第 2 条（A-3、A-6、B-7、B-16、11-1、1-1、B-14、8-8）和第 4 条（`live_core` 收尾）。第 1、3、5、6 条另有记录。
- 改动的包：`packages/live_core`、`packages/live_danmaku`；没有改 `live_net`、应用、翻译、设置。
- 做法：按授权直接开发；两处选择按 A 做（快手从链接进房标题为空；游客也能看哔哩哔哩轮播）。

## 逐条对照

| 编号 | 条目 | 做了没有 | 内容和偏差 |
|---|---|---|---|
| c1 | A-3 快手详情标题 | 完成 | `KuaishouApi.roomDetail` 不再把主播简介写进 `title`（简介仍在 `introduction`、`notice`）；`LiveRoom.fillFromDetail` 在详情没有标题时取卡片的标题。直播间进房本来就调用 `fillFromDetail(requested)`，60 秒刷新和关注刷新用 `mergeFrom`（空标题不覆盖），所以不用改界面就生效 |
| c2 | A-6 未开播显示为未开播 | 保留 | 不改代码。已有测试：`cc_site_test.dart` “an offline anchor on room entry: the room page fills the room”、`baidulive_site_test.dart` “an announced broadcast (S02-room-preview) opens as offline” |
| c3 | B-7 Twitch Cookie 失效提示 | 平台层完成 | 新接口 `LiveSiteCookieRefusals.cookieRefusals`（`live_site.dart`）；`TwitchSite` 播放令牌拒绝存下的 Cookie（401 或完整性质询）时报一次，同一份 Cookie 不再发送也不再报，换了 Cookie 再被拒再报。弹幕层的提示 D01 后续升级（原 M5.F） 已有。界面提示见“交给界面”1 |
| c4 | B-16 酷狗 PK 对方聊天 | 弹幕层完成 | `LiveMessage.sourceRoomId`（和 `isFromOtherRoom`）；`KugouLiveDanmakuProtocol` 读 400305 的 `source{roomid 1, tags 2}`（字段 18），`tags & 1` 且对方房间号有效时作为聊天上报，颜色、等级、粉丝牌和本房间聊天同样读。网页 PK 模块是否另外拦截没法知道（唯一的样本 S09 是显示的），写在注释里 |
| c5 | 11-1 Picarto 恢复取最好一档 | 平台层完成 | `LivePlayUrlResolution.appliedQuality`：平台换了档时给出那一档；`resolveAppliedPlayQuality` 在确认的 id 不在列表里、但和 `appliedQuality` 的 id 相同时显示它（不再标“未确认”）。Picarto 恢复和列表卡片取流换档时填。恢复路径（播放器内部刷新）的显示见“交给界面”4 |
| c6 | 1-1 哔哩哔哩轮播 | 平台层完成 | `getRoomPlayInfo` 给了地址（登录后）照常播；不给时（游客，`BilibiliApi.carouselWithoutStream`）画质只有一档 `BilibiliApi.carouselQuality`（“轮播”），取流走 `live/getRoundPlayVideo` → `x/player/playurl`（html5 MP4，和 TV 端、`live_vod` 同一个请求）：一个文件一条线路（`StreamFormat.other`，Referer 为视频页）。存下的直播画质（如 0）对游客轮播同样改走视频 |
| c7 | B-14 名字颜色和徽章 | 弹幕层完成 | `LiveMessage.nameColor`、`LiveMessage.badges`（新类 `LiveBadge`：图片地址、平台编号）；17LIVE 读 `name.textColor` 和评论的徽章：`prefixBadges`（再加 `prefixBadge`）、`middleBadge`、`roleBadge`、`attendanceBadge`、`mLevelBadge`、`topRightBadge`，按这个顺序；只收平台主机的图片（`SeventeenLiveApi.image`，http 改 https），同一张图只收一次。网页的绘制顺序没有核对（不访问网络），按字段在评论里的排列 |
| c8 | 8-8 按引擎能力请求 HEVC/AV1 | 平台层完成 | `TwitchSite(codecs:)`，`TwitchApi.supportedCodecs`：“优先 H.264”开时只要 `h264`；关时按引擎能解的编码（线路的叫法 `avc`、`hevc`、`av1`）给 `av1`、`h265`，`h264` 一直在；不给（默认）照旧三种都要。应用接上见“交给界面”6 |
| c9 | YouTube、PandaTV 主列表读法合并 | 完成 | `hls_master.dart` 加 `HlsStreamInf`：`read`（每个 `#EXT-X-STREAM-INF` 和后面的地址行，中间的别的标签跳过）、`attributesOf(strict:)`（严格：YouTube 和 `HlsMasterPlaylist` 的写法；宽松：PandaTV 的写法）。两个平台和 `HlsMasterPlaylist` 的属性解析都改用它。行为差别只有一处：PandaTV 的变体和地址之间夹了别的标签时不再丢掉这一档 |
| c10 | FC2 画质探测交出控制连接 | 平台层完成 | `Fc2LiveSite(probeControl:)`：给了就把探测时开的控制连接交给它（它负责关），没给照旧关掉。连接是按 `auto` 开的，`playlists` 里有全部档位，用 `Fc2LiveApi.playlistFor` 可以播任何一档。`live_media` 的接手方式见“交给界面”7 |
| c11 | 哔哩哔哩轮播从 `play_time` 开始 | 平台层完成 | `LivePlayUrlResolution.start`（c6 的轮播视频为 `play_time` 秒；负数、缺失从头开始）；`normalized()` 保留它和 `appliedQuality` |
| c12 | LiveMe、TikTok 租期是否断开 | 保留 | LiveMe 在 E06 平台层升级（21-8）已实测：过期不断流，线路不带租期；TikTok `expire` 约 14 天，只预取不切断。已有测试：`liveme_api_test.dart` “no lease (21-8)”、`tiktok_api_test.dart` 线路租期 `cutsConnection` 为假 |

## 根因

- A-3：快手房间页没有直播标题，v3（`kuaishou_site.dart:292`、`:469`）和 E01.5 都用简介填 `title`；进房时详情的非空标题盖掉卡片标题，之后每次刷新也一样。
- B-7：E03.2 只在平台层悄悄改匿名（`_rejectedSession`），没有出口告诉界面。
- B-16、B-14：`LiveMessage` 没有来源、名字颜色、徽章字段，D01 只能不报或不读。
- 11-1：恢复结果只有画质 id，新档不在播放器的列表里就只能显示旧名称并标“未确认”。
- 1-1：游客的 `getRoomPlayInfo` 对轮播不给地址，平台层没有轮播视频的取法；`getRoundPlayVideo` 自带的 `play_url` 已失效。
- 第 4 条：G01.1 留下的平台层接口（主列表读法、控制连接、起点、租期）。

## v3 文件 → v4 文件

| v3 | v4 |
|---|---|
| `core/site/kuaishou/kuaishou_site.dart` | `packages/live_core/lib/src/sites/kuaishou/kuaishou_api.dart`、`live_room.dart`（`fillFromDetail`） |
| `core/site/twitch/twitch_site.dart` | `packages/live_core/lib/src/sites/twitch/twitch_site.dart`、`twitch_api.dart`、`live_site.dart` |
| `core/site/picarto/picarto_site.dart` | `packages/live_core/lib/src/sites/picarto/picarto_site.dart`、`live_site.dart`（`LivePlayUrlResolution`） |
| `core/site/bilibili/bilibili_site.dart` | `packages/live_core/lib/src/sites/bilibili/bilibili_site.dart`、`bilibili_api.dart` |
| `core/site/kugoulive/kugou_live_site.dart`（`EmptyDanmaku`） | `packages/live_danmaku/lib/src/sites/kugoulive.dart` |
| `core/site/seventeenlive/seventeenlive_site.dart`（`EmptyDanmaku`） | `packages/live_danmaku/lib/src/sites/seventeenlive.dart` |
| `core/site/youtube/youtube_api.dart:369`、`core/site/pandalive/pandalive_api.dart:499` | `packages/live_core/lib/src/hls_master.dart`（`HlsStreamInf`） |
| — | `packages/live_core/lib/src/live_message.dart`（`LiveBadge`、三个新字段）、`packages/live_danmaku/lib/src/connection_base.dart`（清理文字时保留新字段） |

## 新设置和 3.x 迁移

没有新设置。新字段（`LiveMessage` 三个、`LivePlayUrlResolution` 两个）都不存盘；3.x 的关注、历史 JSON 不变。快手关注里 3.x 存下的标题（简介）照旧保留，以后刷新不再改写。

## 交给界面（我没有改，要在应用里接）

1. **B-7 提示**：直播间（和多画面）对 `site is LiveSiteCookieRefusals` 的平台监听 `cookieRefusals`，收到时提示一次。建议文字：“Twitch 的 Cookie 已失效，已改为匿名观看，请在账号页重新填写 Twitch Cookie”（建议键 `twitch_cookie_expired`，zh、en 都加）。
2. **B-16 “对方”标记**：`message.isFromOtherRoom` 的聊天行在名字前加“对方”小标签（建议键 `danmaku_other_room`）；飞行弹幕可照常显示。
3. **B-14**：聊天行的名字用 `message.nameColor`（为空用默认色），名字前画 `message.badges` 的图片（约 16 像素高，按列表顺序，加载失败不占位）。`live_play/mini/compact_danmaku.dart` 重建消息时丢了这些字段，要的话一起带上。
4. **11-1 显示实际画质**：`room_controller.dart` 的 `_refreshPlan`（和 `multiview_controller.dart` 的刷新）拿到 `resolution` 后用 `resolveAppliedPlayQuality` 更新 `_qualities[_qualityIndex]`，画质按钮就显示新档的名称；用户自己点画质的路径（`_openQuality`）已经调用它，不用改。
5. **1-1 轮播播放**：
   - 直播间对哔哩哔哩的轮播房间（`effectiveLiveStatus == LiveStatus.carousel`）给“播放轮播”入口或直接播放（`isPlayableNow` 对轮播仍为假，没有改模型，免得关注分组、录制跟着变）；
   - `_plan` 把 `start: resolution.start` 传给 `PlaybackPlan.of`（直播间和多画面两处）；`onDemand` 保持假：视频播完按直播流结束处理，恢复时 `resolvePlayUrls` 取到当时在轮播的下一个视频和它的 `play_time`。
6. **8-8**：`app/platforms.dart` 建 `TwitchSite` 时传 `codecs: () => {...}`（引擎能解的视频编码）。mpv 带的 FFmpeg 9 软解三种都能解，所以不传也可以；要按硬解能力限制时在这里给。
7. **FC2 控制连接**：`app/platforms.dart` 建 `Fc2LiveSite` 时传 `probeControl: fc2Opener.adopt`；同时 `live_media` 的 `Fc2RecipeOpener.adopt` 要改成按频道接手（现在按“频道:画质”配对，探测的连接是 `auto`，选了别的档就配不上），打开时用 `Fc2LiveApi.playlistFor(control.playlists, quality)` 取那一档的地址；接手后一直没用上的连接要在下一次打开别的频道或释放时关掉，免得多挂一个控制连接。不接时平台层照旧关掉，不会多开连接。

## 测试

- 新增 15 个用例：`live_core` 12 个（快手 A-3 1、`fillFromDetail` 1、Twitch B-7 1、8-8 2、`resolveAppliedPlayQuality`/`start` 1、哔哩哔哩 API 1 和站点 1、`HlsStreamInf` 2、PandaTV 夹标签 1、FC2 交出连接 1），`live_danmaku` 3 个（清理文字保留新字段 1、17LIVE 名字颜色和徽章 2）。
- 改了期望的原有用例（都因本任务的行为变化，测试里注明）：
  - `kuaishou_api_test.dart`：S09 两个样本和 3.x 对照时 `title` 列为“变化”（3.x 是简介，现在为空）；S11 未开播的标题从简介改为空、简介在 `introduction`；
  - `bilibili_site_test.dart` “1-1: a carousel room is its own state…”：游客的轮播从报 `StreamUnavailable` 改为只有“轮播”一档；
  - `kugoulive_test.dart` 3 处：S09 对方房间的聊天从“不报”改为上报并带对方房间号；合成帧里 400305 的几种情况；对方聊天的颜色；
  - `picarto_site_test.dart` 2 处只是加断言（`appliedQuality`）。
- 通过：`live_core` 3640 个、`live_danmaku` 1589 个全部通过，`dart analyze`、`dart format --set-exit-if-changed` 无问题；`apps/pure_live` 的 `flutter analyze` 无问题，全部 `flutter test` 696 个通过（第一次整体运行有 1 个失败，输出被截断看不到是哪个；紧接着重跑全部通过，`search_test.dart` 单独跑也通过，判断是偶发的计时问题，和本任务无关）；`check_ui_structure.py` 通过。
- 没有样本、只用合成回答测的：`getRoundPlayVideo` 的回答（字段按 E01.1 记录：`bvid`、`cid`、`play_time`）；Twitch 的 `codecs`；酷狗 400305 除 S09 外的几种来源写法。

## 要在 K90 上看的（界面接上之后）

1. 快手：从推荐或分区卡片进房，标题是卡片上的直播标题，房间信息里仍有简介；停留超过 1 分钟（定时刷新）标题不变；关注后回到关注页，标题不被简介替换。**这一条不用等界面**，下次装机就能看。
2. 哔哩哔哩：游客找一个轮播房间（首页“未开播”里的轮播标记），播放从视频中途开始，播完接下一个；登录后同一房间如果 `getRoomPlayInfo` 给地址，走直播流。
3. 酷狗：PK 中的房间，聊天里出现对方房间的发言并带“对方”。
4. 有代理时：Twitch 填一个失效的 Cookie 进房，提示一次、照常播放；17LIVE 聊天行名字有颜色和徽章；Picarto 主播换档后恢复播放显示新档名称。

## 合并时注意的冲突点

- `docs/E-直播平台/E06-平台层升级/E06.1-已批准升级的余项/README.md`：另一个代理同时写第 1、3、5、6 条；我的部分是“第 2 条”“第 4 条”“测试和验证（第 2、4 条）”“风险和性能（第 2、4 条）”四节和状态行。
- `docs/specs/UPGRADES.md` 我没有改（第 1 条回填状态列的是另一个代理）。建议状态：
  - A-3：完成（E06.1：快手详情不再用简介当标题，进房保留卡片标题）
  - A-6：完成（E02.2、E02.11；E06.1 确认）
  - B-7：平台层完成（E06.1：`LiveSiteCookieRefusals`），余下界面提示
  - B-16：弹幕层完成（E06.1：`LiveMessage.sourceRoomId`），余下聊天行“对方”标记
  - 11-1：平台层完成（E06.1：`LivePlayUrlResolution.appliedQuality`），余下恢复后显示实际画质
  - 1-1：平台层完成（E06.1：游客播放轮播视频，从 `play_time` 开始），余下直播间入口
  - B-14：弹幕层完成（E06.1：`nameColor`、`badges`），余下聊天行显示
  - 8-8：平台层完成（E06.1：`TwitchSite(codecs:)`），余下应用按引擎填能力
- `packages/live_core/lib/src/live_message.dart`、`live_site.dart`（`LivePlayUrlResolution` 的构造函数加了两个可选参数）、`bilibili_site.dart`：别的分支同时改这几个文件时注意。
- `apps/pure_live` 里如果有测试期望哔哩哔哩游客轮播取流报错，会受 c6 影响（本分支的全部 `flutter test` 已通过）。
