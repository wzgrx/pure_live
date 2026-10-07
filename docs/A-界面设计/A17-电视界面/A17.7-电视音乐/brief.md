# A17.7 电视音乐：任务书

## 背景

- 来源：界面重做的电视部分（旧编号 U.15g、T18d.3）。设计第 1 版 2026-10-01 评审确认（“后续全部通过”，确认记录 `1e4b0b24e`），待选按建议 A（D-003）：播放模式在控制栏、正在播放页、队列面板各一个带文字的“列表循环 ⌄”（Y1）；两个“UP主”分开叫——“我的”下的叫“B站关注”，关注里的叫“关注的UP主”（Y2）；歌单网格照 pure_live_TV，自建 6 列、收藏夹 4 列（Y3）；视频、音乐从模式按钮进（A17.6 的 X1）。设计正文在本文件夹 [README.md](README.md)（界面清点表 35 项、g1～g11、M1～M10、按键表、焦点路线），评审页导出在 `page/`。
- 这是一个新功能的界面：手机版没有音乐模式；逻辑在 `packages/live_vod` 的 `music/`（L03.1 完成：`BilibiliMusicApi`、`PlayQueue`、`PlayMode`、`LyricLookup`、`DailyRecommender`、`PlaylistImporter`、`AudioCache`），应用还没依赖 `live_vod`。
- 为什么现在做：第三档（D-004）。**必须在 A17.6 之后**：g5、g10、g11 用 A17.6 的控制栏、视频卡片、历史行、视频详情、状态组件和登录门；外挂音轨（DASH 音频）也在 A17.6 的第 0 阶段。
- 半成品：旧分支 M14.4，工作区 `/home/wzgrx/projects/pure_live/.claude/worktrees/agent-a38e678e236092db4`，两个提交（基于 `09c352cb7`，提交之后工作区里没有再改动的文件）：
  - `e5a6ede7f`“feat(live_store): music mode settings and meta prefix reads (M14.4)”：`packages/live_store` 加了音乐设置 `musicPlayMode`、`musicAudioOnly`（默认开）、`musicResumeOnOpen`（默认关）、`musicProgressLine`（默认开）、`musicLossless`、`musicCacheLimitMb`、`musicThirdPartyEndpoints`（`settings.dart:1027-1066`），`live_store.dart` 加按前缀读 meta，测试 +17 行——这部分是纯逻辑，可以照搬（注意 master 的 `settings.dart` 之后加了很多设置，要重新放位置）；
  - `f712f2bd9`“WIP M14.4 (stopped 2026-10-01 at the UI redesign; not merged)”：`apps/pure_live/lib/app/music_catalog.dart`（208）、`music_library.dart`（530，歌单、喜欢、最近、同步的收藏夹）、`music_player.dart`（719，播放器和队列接线）、`lib/pages/live_play/background_playback.dart`（93，旧目录）、`tv/music/` 四个文件（`tv_music_pane.dart` 156、`tv_music_discover.dart` 319、`tv_music_library_pages.dart` 1110、`tv_music_widgets.dart` 793）。界面是重做前的样子、建在旧目录：逻辑（歌单存储、播放器接线、后台播放）参考，界面照新设计重写。

## 目标和验收

1. （g1）保留：导航五项（正在播放、搜索、歌单、推荐、我的）和标签分组（推荐：每日、动态、排行；我的：关注、B站关注、最近、云端）、默认页（我的 · 关注）、迷你播放条（队列不空时常驻内容区底部）、打开时继续上次播放（设置）、遥控器操作、歌词、控制栏全部功能、队列、歌单功能、导入（网易云、酷狗、QQ）、同步、每日推荐、多选。
2. （g2）一个队列行组件，正在播放页、队列面板、歌单详情、最近、收藏夹详情共用；正在播的一行主色标出。
3. （g3）播放模式写出来：“列表循环 ⌄”小菜单（列表循环、单曲循环、随机），在控制栏、正在播放页、队列面板各一个。
4. （g4）音质、播放内核的选项用手机的清晰度小菜单（`showAnchoredMenu` 电视样式）。
5. （g5）播放器和视频（A17.6）用同一个控制栏组件；控制栏显示时 ↑ 打开队列面板；内核写“Mpv”，设置按钮只放图标，一行放得下。
6. （g6）一个歌曲菜单：移除项按位置写“从队列移除”“移出歌单”“从最近播放移除”“从喜欢的歌曲移除”，默认焦点在第一项（不在删除上）。
7. （g7）加入歌单时写“已在”；有“新建歌单并加入”（建完把歌加进去）。
8. （g8）清空最近播放先确认（焦点在“取消”）。
9. （g9）两个“UP主”分开：我的下的叫“B站关注”（账号关注），关注里的叫“关注的UP主”（本机关注）。
10. （g10）视频卡片、历史行、曲目列表的操作按钮用 A17.6 的组件。
11. （g11）子页面（歌单详情、收藏夹详情、曲目列表）默认焦点在“播放全部”；字号、焦点、状态组件同 A17.6。
12. 离开播放器音乐继续播；切走音乐模式时停音乐（A17.2 c7）；媒体键（播放 / 暂停、上一首、下一首）任何时候有效。
13. 手机界面一点不变；`flutter test` 全部通过；`tv` 直接写的颜色和图标保持 0。

## 现状（读代码得出，写文件:行）

- 入口：`apps/pure_live/lib/tv/home/tv_home_page.dart` 的 `TvPane.music`（`:51`，`available: false`），内容“建设中”（`:314-316`）。
- 逻辑包 `packages/live_vod/lib/src/music/`：`music_api.dart`（146 行，`MusicTrack`、`BilibiliMusicApi`：曲目、补 cid、最好的音频档、UP 主合集和系列、BGM 歌词）、`queue.dart`（252，`PlayQueue<T>`、`PlayMode`，随机是洗牌顺序）、`lyrics.dart`（309，`Lrc`、`LyricLookup`：手选 > 已存 > 各来源）、`daily.dart`（171，`DailyRecommender`，历史上限 2000）、`matcher.dart`（238，`TrackMatcher`、`PlaylistImporter`，逐首匹配、间隔 1.2 秒、可取消）、`third_party.dart`（418，`PlaylistImportSource` 网易云 / 酷狗 / QQ、`ThirdPartyLyrics`）、`audio_cache.dart`（173，LRU，默认 1 GB）。存储接口 `src/store.dart`（`VodKeyValueStore`）要应用用 `live_store` 实现。
- `live_store` 现在**没有**任何音乐设置，也没有歌单、喜欢、最近的存储表（旧分支 `music_library.dart` 用 meta 存的）。
- 后台播放：`apps/pure_live/lib/features/live_play/logic/background_playback.dart`（直播的后台播放和媒体会话）；音乐要离开播放器继续播、通知栏有控制，需要一份不依赖直播间的会话。
- 可以用的组件：A17.6 做的视频卡片、控制栏、评论、登录门（先做 A17.6）；`tv/widgets/tv_dialogs.dart` 的选择框、确认框、输入框；`tv_tabs.dart`、`tv_grid.dart`、`tv_status.dart`。

## 3.x 基线

- 3.x 和手机版都没有音乐。基线是 pure_live_TV（设计用 `b9d2f739`，本机 `37660afc`，开工前看 `git log b9d2f739..HEAD -- lib/modules/music`，新功能先进 V01）：
  - 外壳 `lib/features/home/home_page.dart:160-184`、`lib/modules/music/music_section.dart:12-34`；迷你播放条 `widgets/music_mini_bar.dart`；正在播放 `pages/playback/music_now_playing_queue_widgets.dart`、`widgets/now_playing_source_card.dart`、`widgets/music_song_row.dart`；播放器 `pages/playback/music_player_page.dart`、`widgets/player_now_playing_view.dart:205-273`、`widgets/player_control_bar_parts.dart:417-490`；队列 `widgets/player_queue_panel.dart`；歌单 `pages/playlist/music_fav_folders_page.dart`、`music_user_playlist_detail_page.dart:300-360`、`music_playlist_dialogs.dart`；每日 `pages/discover/music_daily_page.dart`；我的 `pages/mine/music_recents_page.dart`、`music_follow_section.dart`、`music_cloud_history_page.dart`；歌曲菜单 `widgets/music_song_menu.dart`。
  - README 的“pure_live_TV 的问题”M1～M10 写了文件:行；L03.1 记录写了 pure_live_TV 音乐逻辑的 9 个问题和修法（歌词、随机、缓存淘汰……），界面不要把那些问题带回来。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5、8、14 节）。
2. `docs/specs/ENGINEERING.md`（第 5 节 AGPL）；`docs/specs/UI.md` 第 5.5 节。
3. 本文件夹 `README.md` 和 `page/`；`A17.6-电视点播/README.md` 和 `brief.md`（共用组件）；`A17.2-电视外壳/README.md`（模式按钮、切走停音乐）。
4. `docs/L-网络电视和点播/L03-点播和音乐/L03.1-哔哩哔哩点播和音乐核心包/record.md`。
5. 旧分支 M14.4 的两个提交（只读）。

## 范围

- 可以改：新目录 `apps/pure_live/lib/tv/music/`、`apps/pure_live/lib/app/`（音乐的 provider、歌单存储接线、播放器和媒体会话，新文件）、`tv/home/tv_home_page.dart`（只为接入音乐模式）、`tv/widgets/`（队列行、歌曲菜单）；`packages/live_store`（只加音乐设置和歌单存储，D-018）；`packages/live_vod`（只修 bug 或补接口，带样本测试）；翻译文件（只加键）；测试；本文件夹。
- 不能改：手机界面；直播的后台播放规则（`background_playback.dart` 只读；要共用时把共同部分提出来，直播行为不变，并让维护者审）；设置键名和含义；版本号、`assets/version.json`、`assets/releases.json`；签名配置；原生代码（媒体会话用现有插件）。

## 方案和阶段

| 阶段 | 做什么（对应 g 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | 音乐设置和歌单存储（照 `e5a6ede7f`）；播放器会话（队列、播放模式、纯音频 / 显示画面、离开播放器继续播、媒体键、切走模式停） | `live_store`、`app/` 新文件 | `live_store` 测试：默认值、歌单增删改、喜欢、最近；会话测试：队列前后、三种模式、媒体键（假播放会话） |
| 2 | 音乐模式外壳（五项和标签）、迷你播放条、正在播放页（g1、g2、g3、g6） | `tv/music/`、`tv/home/` | 新用例：切到音乐默认进“我的 · 关注”；迷你播放条只在队列不空时出现；队列行焦点、正在播的一行；“列表循环 ⌄”小菜单；歌曲菜单默认焦点在第一项、移除项文字按位置 |
| 3 | 播放器（g4、g5）：同一个控制栏、音质和内核小菜单、↑ 队列面板、歌词（加载中、暂无歌词、选择歌词）、设置面板 | `tv/music/` | 新用例：控制栏一行放下；音质小菜单贴按钮；↑ 打开队列；返回收起控制栏再离开、音乐继续 |
| 4 | 歌单、歌单详情、收藏夹详情、加入歌单、导入歌单三步（g7、g11） | `tv/music/` | 新用例：加入歌单写“已在”、“新建歌单并加入”后歌在里面；导入用样本走完三步（匹配用假搜索，间隔用可注入时钟） |
| 5 | 推荐（每日、动态、排行）、我的（关注、B站关注、最近、云端）、搜索（g8、g9、g10） | `tv/music/` | 新用例：两个“UP主”名字；清空最近先确认；云端删除一条先确认 |

每个阶段都要能单独合并（阶段 2 合并后音乐模式能进，没做完的入口不显示）。登记表的阶段（设计 ✓ → 开发 → 真机）开工时按上表拆开。

## 测试

- 改之前会失败：`test/tv/` 加“电视首页切到音乐模式后默认在‘我的 · 关注’”（现在 `TvPane.music` 不可用）。
- 每个阶段的用例见上表。全部用 `fixtures/live_vod` 的样本和假 HTTP，不访问哔哩哔哩和第三方（网易云、酷狗、QQ、歌词站）；导入匹配的 1.2 秒间隔用可注入时钟，测试里的定时器至少 1 秒。
- 1080p@2x 和 720p 各一个布局测试：歌单 6 列 / 4 列、迷你播放条、控制栏不出屏、字不小于 14。

## 真机验证（维护者在电视或盒子上做）

| 步骤 | 期望 |
|---|---|
| 1. 模式按钮切到“音乐” | 默认“我的 · 关注”；没登录是登录门 |
| 2. 推荐 · 排行里播一首 | 迷你播放条出现在内容区底部 |
| 3. 进播放器（纯音频） | 封面和歌词，当前行高亮；控制栏一行放下 |
| 4. 控制栏显示时按上 | 队列面板；“列表循环 ⌄”能换成随机 |
| 5. 返回离开播放器，切到别的入口 | 音乐继续播；通知栏或遥控器媒体键能暂停、下一首 |
| 6. 在一首歌上长按 OK | 歌曲菜单，焦点在第一项；“加入歌单”里已有的写“已在”，“新建歌单并加入”后歌在新歌单里 |
| 7. 导入一个网易云歌单链接（手机或遥控器输入） | 三步：识别 → 匹配中（进度、可停止）→ 完成 |
| 8. 模式切回“直播” | 音乐停止 |

## 风险和注意

- 规模大，必须按阶段合并；后台播放和媒体会话最容易出问题（和直播的后台播放、画中画抢会话），阶段 1 先做通再做界面。
- 第三方接口（网易云、酷狗、QQ、歌词站）地址可配（`musicThirdPartyEndpoints`），默认值照 L03.1；测试不访问它们。
- 音频缓存默认 1 GB，电视盒子存储小：缓存上限要能在设置里改（A17.9 的音乐设置页），默认值请维护者确认。
- 可能冲突的文件：`tv/home/tv_home_page.dart`（A17.2、A17.6）、A17.6 的控制栏和卡片组件、`live_store` 的 `settings.dart`、`background_playback.dart`（C 组）。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 分支 `ai/A17.7` 或本机工作区；提交信息以 `[A17.7]` 开头（英文）；不推 master。
- 提交前：改过的包跑 `dart format --output=none --set-exit-if-changed .`、analyze、测试；`apps/pure_live` 跑全部 `flutter test`；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”、更新登记表的 `done`、`next`、`branch`。

## 报告（中文，简洁）

每条验收做到没有；后台播放和媒体会话怎么做的、和直播怎么共存；从旧分支 M14.4 借了哪些；测试数量（改之前失败几个）；新设置（键名、默认值）、新存储和翻译键；要在电视上看的；可能冲突的文件。
