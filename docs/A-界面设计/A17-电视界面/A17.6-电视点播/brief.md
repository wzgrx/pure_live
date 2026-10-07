# A17.6 电视点播：任务书

## 背景

- 来源：界面重做的电视部分（旧编号 U.15f、T18d.2）。设计第 1 版 2026-10-01 评审确认（“后续全部通过”，确认记录 `1e4b0b24e`“U.15f-h confirmed”），待选 X1～X4 按建议 A（D-003）：视频、音乐从导航轨顶上的模式按钮进（X1，随 A17.2）；去掉快退、快进按钮（X2）；分区标签只写文字（X3）；视频模式导航顺序照 pure_live_TV：搜索、我的、首页、分区、影视（X4）。设计正文在本文件夹 [README.md](README.md)（界面清点表 13 组、c1～c18、P1～P17、按键表、焦点路线），评审页导出在 `page/`。
- 跨任务记录（2026-10-01）：视频、音乐模式从哪进和导航顺序随 A17.2 的导航栏定；点播播放器的画质用手机的清晰度小菜单（c13）、弹幕设置用直播间的侧面板（c14），同一个组件；颜色、字号、焦点以 A17.1 为准（设计图是按当时 `tv/tv_theme.dart` 画的）。
- 这是一整个新功能的界面：手机版没有点播，4.x 只有逻辑包 `packages/live_vod`（L03.1，2026-10-01 完成，`11d579e05`，合并 `3b94b9f55`），**应用还没有依赖它**（`apps/pure_live/pubspec.yaml` 里没有 `live_vod`）。
- 为什么现在做：第三档（D-004）。电视阶段里在 A17.2（模式按钮）之后；A17.7 音乐要用这里的卡片、控制栏、状态组件，所以先做 A17.6。
- 半成品：旧分支 M14.3，工作区 `/home/wzgrx/projects/pure_live/.claude/worktrees/agent-a3224b95b79a5b0be`，提交 `e6dd43c8f`（“WIP M14.3 (stopped 2026-10-01 at the UI redesign; not merged)”，基于 `09c352cb7`，提交之后工作区里没有再改动的文件），4891 行：
  - `apps/pure_live/lib/app/vod.dart`（20 行：`vodClientProvider`、`vodUgcProvider`、`vodPgcProvider`，用应用的 `http` 和直播的哔哩哔哩 Cookie）——可以直接借鉴；
  - `apps/pure_live/lib/tv/video/` 12 个文件：`video_pane.dart`（470，把视频模式做成导航栏的一项、分区是第一行标签，即 X1 的 B 方案，和确认的设计不同）、`video_detail_page.dart`（512）、`video_season_page.dart`（291）、`video_playback.dart`（602，播放器和按键）、`video_comments.dart`（349）、`video_personal.dart`（437）、`video_search.dart`（330）、`video_space_page.dart`（196）、`video_source.dart`（422）、`video_store.dart`（248，进度和设置）、`video_widgets.dart`（822）、`video_navigation.dart`（55）；
  - `packages/live_player`：`engine.dart`、`mpv_engine.dart`、`session.dart` 加了外挂音轨 `ExternalAudio`（DASH 视频和音频分开时 mpv `audio-files`），测试 `session_test.dart` 加了用例——**点播播放必须有这一步**（L03.1 记录“点播的 DASH 怎么交给播放器”），现在 master 的 `live_player` 没有。
  - 它建在重构前的目录，界面是重做前的样子：逻辑（取数、进度上报、心跳、DASH 外挂音轨）可以照搬思路，界面照新设计重写；`live_player` 的改动属于 G 组，要单独审。

## 目标和验收

1. （c1）视频模式的五个入口和顺序（搜索、我的、首页、分区、影视）、页面结构和内容、卡片信息、遥控器操作、播放器全部功能、进度记录、心跳、字幕、在线人数、底缘进度线、“显示视频详情”设置都有，照 pure_live_TV。
2. （c2）尺寸按计划书 5.5 节（逻辑 960×540、边距 48 / 28、正文 14、标题 15～20、角标 12、4 列）；焦点照 A17.1（1.05 加 3 像素近白描边）。
3. （c3）子页面默认焦点在主要操作：详情页“播放 / 继续”、番剧“第 1 话”、UP 主空间第一个投稿、评论页第一条评论。
4. （c4）详情页主按钮“播放”或“继续 P1 · 01:46”；单 P 不列播放列表；分 P 行写“看到 01:46”。
5. （c5、c6）一种视频卡片（结构同手机房间卡片 A09.1 的电视样式，A17.1 的 `TvRoomCard` 一族），番剧卡片同一外框；所有顶部标签用同一个 `TvTabBar`。
6. （c7）状态用 A17.1 的状态组件：出错写原因加“重试”，空状态配对应图标和下一步，第一次加载用静态骨架。
7. （c8、c9、c10、c11）分区标签只写文字（不用 emoji）；选集写“第 1 话”加标题、会员集带标；“影视”用胶片图标；文字：“搜索”“输入关键词搜索视频”“返回收藏夹”（不借直播、音乐的文字）。
8. （c12）播放器控制栏两组一屏放下，没有快退、快进按钮（←→ 和进度条照旧）；播放图标跟状态；用不了的按钮变灰写原因；弹幕按钮用直播间的弹幕图标。
9. （c13、c14）画质用手机的清晰度小菜单（`showAnchoredMenu` 的电视样式），贴着按钮；倍速照旧循环；弹幕设置用直播间同一个面板（A17.4 做的右侧面板里的弹幕设置），放右侧，不盖住画面。
10. （c15）播放器的评论面板和评论页是同一个评论组件：热门 / 最新、空、出错、加载更多。
11. （c16、c17、c18）长按确认或菜单键打开统一的卡片弹窗（A17.1 c9 的样子，动作写明：稍后再看、UP 主主页、删除……）；取消关注、删除历史、取消追番先确认，补“已取消追番”的中文；UP 主空间“＋ 关注 / ✓ 已关注”，排序“最新发布 ⌄”小菜单。
12. 未登录时视频模式整块换成登录门（视频、音乐共用），扫码登录用的是直播的哔哩哔哩账号（同一份 Cookie）。
13. 手机界面一点不变；`flutter test` 全部通过；`tv` 直接写的颜色和图标保持 0。

## 现状（读代码得出，写文件:行）

- 入口：`apps/pure_live/lib/tv/home/tv_home_page.dart` 的 `TvPane.video`（`:48`，`available: false`），内容是“建设中”（`:314-316`）。模式按钮是 A17.2 的。
- 逻辑包 `packages/live_vod`（4792 行，纯 Dart）：`BilibiliVodClient`（`src/client.dart`，Cookie 来自 `CookieVault.cookieFor('bilibili')`，游客取流不带 buvid）、`BilibiliUgcApi`（`src/ugc_api.dart`：热门、排行、推荐、详情、取流、字幕、弹幕分段、评论（游标）、动态、UP 主空间、点赞投币收藏三连、收藏夹、稍后再看、历史和进度上报、搜索）、`BilibiliPgcApi`（`src/pgc_api.dart`：时间表、索引、番剧、追番）、`VodStreams`（`src/streams.dart`，`linesOf` 把一档变成 `LivePlayLine`）、点播弹幕 `src/danmaku.dart`、存储接口 `src/store.dart`（`VodKeyValueStore`）。样本在 `fixtures/live_vod`（38 个）。
- 播放：`packages/live_player`（`src/engine.dart` 的 `EngineMedia` 没有外挂音轨；`src/mpv_engine.dart`；`src/session.dart`）。手机直播间的播放会话 `LiveRoomController` 是直播专用的，点播要自己的会话（旧分支 `video_playback.dart` 有一版）。
- 可以用的电视组件：`tv/widgets/tv_room_card.dart`（卡片、角标、`TvMarquee`）、`tv_grid.dart`、`tv_tabs.dart`、`tv_status.dart`、`tv_dialogs.dart`、`tv_room_dialog.dart`（卡片弹窗的样子）、`tv_page_header.dart`；A17.4 做的播放设置面板、弹幕设置电视样式（先做 A17.4）。
- 飞行弹幕层：`apps/pure_live/lib/shared/danmaku/danmaku_overlay.dart`（`DanmakuOverlay` `:151`），点播弹幕按时间轴上屏需要喂入方式（直播是实时流）。
- 登录：直播的哔哩哔哩扫码登录在 `features/account/`、`features/auth/`（A12.2）；电视的登录门是新的。

## 3.x 基线

- 3.x 和手机版都没有点播。基线是 pure_live_TV（设计用 `b9d2f739`，本机 `37660afc`；W01.1 记“167 个提交，大部分是点播、音乐和电视界面”，开工前必须看 `git log b9d2f739..HEAD -- lib/modules/video lib/modules/vod`，新加的功能先在 V01 提议，不直接做）：
  - 外壳 `lib/features/home/home_page.dart:186-241`（视频模式五项、登录门）；模块 `lib/modules/video/`（`video_section.dart`、`video_section_view.dart`、`pages/`、`widgets/video_card.dart`、`video_control_bar.dart`、`video_quality_menu.dart`、`video_parts_panel.dart`、`video_comments_panel.dart`、`video_hotword_board.dart`）、`lib/modules/vod/`（`pages/ugc_comments_page.dart`、`ugc_user_space_widgets.dart`、`widgets/ugc_space_header_card.dart`）。
  - 播放器按键 `pages/playback/video_player_widgets.dart:234-323`（←→ 快退快进 10 秒、连按加速到 60 秒，↑↓ 换集，5 秒收起，返回逐层）。
  - README 的“pure_live_TV 的样子”逐项写了尺寸和位置，“pure_live_TV 的问题”P1～P17 写了文件:行。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5、8、14 节）。
2. `docs/specs/ENGINEERING.md`（第 5 节 AGPL；包的依赖方向）；`docs/specs/UI.md` 第 5.5 节。
3. 本文件夹 `README.md` 和 `page/`；`A17.1`、`A17.2` 的 README（组件、模式按钮）；`A17.4-电视直播间/brief.md`（播放设置面板和弹幕设置电视样式的做法）。
4. `docs/L-网络电视和点播/L03-点播和音乐/L03.1-哔哩哔哩点播和音乐核心包/record.md`（接口、DASH、游客取流、样本）。
5. 手机：`docs/A-界面设计/A09-浏览界面/A09.1-房间卡片/README.md`（卡片结构和长按弹窗）、`docs/A-界面设计/A02-组件/A02.3-贴着按钮的小菜单/README.md`、`docs/A-界面设计/A12-账号和数据界面/A12.2-登录和Cookie/README.md`（哔哩哔哩扫码）。
6. 旧分支 M14.3 的 `app/vod.dart`、`tv/video/video_playback.dart`、`video_store.dart`、`packages/live_player` 的改动（只读）。

## 范围

- 可以改：`apps/pure_live/pubspec.yaml`（加 `live_vod` 依赖）、新目录 `apps/pure_live/lib/tv/video/`、`apps/pure_live/lib/app/vod.dart`（新）、`tv/home/tv_home_page.dart`（只为接入视频模式）、`tv/widgets/`（加视频卡片、评论组件、登录门）；`packages/live_vod`（只修 bug 或补接口，带样本测试）；翻译文件（只加键）；`test/tv/`、`packages/live_vod/test/`；本文件夹。
- 要单独审的（G 组）：`packages/live_player` 的外挂音轨。建议先在 G 组开一个小任务做它（参考 `e6dd43c8f` 的改动和 `session_test.dart` 的用例），本任务依赖它；维护者同意在本任务里做时，单独一个阶段、单独提交。
- 不能改：手机界面；直播的哔哩哔哩登录和 Cookie 存储的规则（只读）；设置键名和含义；版本号、`assets/version.json`、`assets/releases.json`；签名配置。

## 方案和阶段

| 阶段 | 做什么（对应 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 0 | 前提：`live_player` 支持外挂音轨（G 组任务或本任务单独一步）；核对 pure_live_TV 设计基线之后的点播变化 | `packages/live_player`（如在本任务）、record.md | `live_player` 测试加 DASH 外挂音轨用例并通过；record.md 写清上游变化 |
| 1 | 接入 `live_vod`、视频模式外壳和登录门（c1 外壳部分、验收 12）、视频卡片（c5）、首页（动态、推荐、热门）、分区（c8）、影视（c10）；状态组件（c7）；文字（c11） | `pubspec.yaml`、`app/vod.dart`、`tv/video/`、`tv/home/` | 新用例：模式切到视频后五个入口和顺序；未登录整块是登录门；首页三个标签、当前标签再按 OK 刷新；出错写原因加“重试”（用 `fixtures/live_vod` 样本，假 HTTP） |
| 2 | 视频详情（c3、c4）、番剧（c9）、UP 主空间（c18）、卡片弹窗（c16）、确认（c17） | `tv/video/` | 新用例：详情默认焦点在“播放 / 继续”；单 P 没有播放列表；番剧“第 1 话”；卡片长按弹窗动作写明；取消关注先确认 |
| 3 | 播放器（c12、c13、c14）：控制栏两组、画质小菜单、倍速、弹幕设置面板、字幕、底缘进度线、进度上报和心跳；←→ 快退快进加速、↑↓ 换集、返回逐层 | `tv/video/` 播放器、A17.4 的面板组件 | 新用例：控制栏一屏放下、没有快退快进按钮、暂停时图标变；画质小菜单贴按钮；←→ 连按加速（定时器 ≥1 秒的写法）；返回逐层 |
| 4 | 评论（c15）：一个评论组件用在播放器面板和评论页；我的（UP主、稍后再看、收藏夹、历史记录、我的追番）；搜索（热搜、视频 / 用户 / 影视） | `tv/video/` | 新用例：评论热门 / 最新、空、出错、加载更多；历史删除先确认；搜索三种结果 |

每个阶段都要能单独合并（视频模式在阶段 1 合并后就能进，后面的页面没做完时入口不显示或写“建设中”，不能出现坏掉的界面）。登记表的阶段（设计 ✓ → 开发 → 真机）开工时按上表拆开。

## 测试

- 改之前会失败：`test/tv/` 加“电视首页切到视频模式后有‘首页’入口”（现在 `TvPane.video` 不可用）。
- 每个阶段的用例见上表。全部用 `fixtures/live_vod` 的样本和假的 `LiveHttp`，不访问哔哩哔哩；播放用假的播放会话（照 `packages/live_player/test/support/fake_engine.dart`）。
- 进度上报、心跳：断言调用了 `reportProgress`、间隔和参数；失败时不打断播放。
- 1080p@2x 和 720p 各一个布局测试：卡片 4 列、控制栏一屏放下、字不小于 14。
- 定时器至少 1 秒；`DateTime.now` 用可注入的时钟。

## 真机验证（维护者在电视或盒子上做）

需要登录过哔哩哔哩的电视（游客最高 480P）。

| 步骤 | 期望 |
|---|---|
| 1. 导航栏模式按钮切到“视频” | 入口是搜索、我的、首页、分区、影视；没登录时是登录门，扫码后进首页 |
| 2. 首页“推荐”，选一个视频 | 详情页焦点在“播放”；单 P 视频没有播放列表 |
| 3. 播放 | 控制栏一屏放下；←→ 快退快进、连按加速；暂停时图标变成播放 |
| 4. 控制栏“画质” | 小菜单贴着按钮，选 1080P 后画面变清楚、有声音（DASH 外挂音轨） |
| 5. 控制栏“弹幕设置” | 右侧面板，画面不被盖住；改字号立即生效 |
| 6. 看一半返回，再进详情 | 主按钮写“继续 P1 · mm:ss”；“我的 · 历史记录”里有这一条 |
| 7. 番剧（影视 → 番剧） | 焦点在“第 1 话”，会员集有标记 |
| 8. 卡片上长按 OK | 弹窗写明“稍后再看”“UP 主主页”；UP 主空间里关注后再取消要确认 |

## 风险和注意

- 规模大（13 组界面），按阶段合并，每个阶段都要能单独用；额度不够时按 PROCESS 第 5.2 节停在阶段边界。
- 外挂音轨是播放层的改动（G 组），影响直播；必须有测试证明直播不受影响（没有 `audio` 时行为和现在一样）。
- 哔哩哔哩接口风控（-352、412）：`live_vod` 已有续签和类型化错误，界面要按 `SiteError` 写原因，别显示原文。
- pure_live_TV 之后加的点播功能不要顺手做，先进 V01。
- 可能冲突的文件：`tv/home/tv_home_page.dart`（A17.2、A17.7）、`tv/widgets/`（A17.3、A17.4）、`packages/live_player`（G 组任务）、`apps/pure_live/pubspec.yaml`。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`（加依赖后根 `pubspec.lock` 会变，要提交）。
- 分支 `ai/A17.6` 或本机工作区；提交信息以 `[A17.6]` 开头（英文）；不推 master。
- 提交前：改过的包（`apps/pure_live`、`live_vod`、`live_player`）跑 `dart format --output=none --set-exit-if-changed .`、analyze、测试；`apps/pure_live` 跑全部 `flutter test`；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”、更新登记表的 `done`、`next`、`branch`。

## 报告（中文，简洁）

每条验收做到没有；外挂音轨在哪做的、直播是否受影响；从旧分支 M14.3 借了哪些逻辑；pure_live_TV 设计基线之后的点播变化和处理；测试数量（改之前失败几个）；新设置和翻译键；要在电视上看的；可能冲突的文件。
