# S02.1 真机问题修复

- 日期：2026-10-01
- 来源：两轮真机测试（K90，开发版 `com.mystyle.purelive.v4dev`；第一轮 8df75a12a，第二轮 e62c995e4），`~/ref/notes/m13_notes.md` 的 “DEVICE TEST 2026-10-01” 条目和协调员补充的 4 个直播间问题
- 范围：`apps/pure_live`；`packages/live_core`（文字规范化、`LiveMessage` 只加字段、快手表情表、YY 分区预置表）；`packages/live_danmaku`（文字规范化、表情片段、快手表情表）；`packages/live_ui`（状态视图按钮图标、`EmoteText` 本地图片）
- 不往手机安装。真实环境只读探测约 5 分钟（YY 82 个在播详情、快手房间页一次）；手机当时在前台运行别的应用，没有操作，只读了一次 logcat（只有最近 20 分钟，没有开发版的记录）。

## 问题一览

| # | 现象 | 根因 | 改法 | 提交 |
|---|---|---|---|---|
| 1 | 关注页没有关注时“搜索直播”按钮是刷新图标 | `AppStatusView` 的按钮图标写死为刷新（3.x 同） | `AppStatusView`/`EmptyView` 加 `buttonIcon`；所有非重试按钮配上对应图标 | `bbc7aa6b0` |
| 2 | 快手标题里的 U+FFFC 显示成“OBJ” | 平台文字原样进模型，没有统一去掉占位字符 | `live_core` 的 `stripInvisiblePlaceholders`；`LiveRoom` 创建时、弹幕运行时统一去掉 | `aadad46ef` |
| 3 | 卡片“已播 51 小时 49 分”、直播间“已开播 2 天” | 两个函数各写一套规则 | 一个格式化函数 `elapsedText` | `13e0f7f09` |
| 4 | 关注页标签“已开播 1”右侧被截断变淡 | 三个标签挤在标题栏中间，默认 16 的内边距吃掉宽度，标签用渐隐截断 | 内边距 4、标题间距 4、数字改小徽标，太窄时整体缩小不截断 | `edb8531fb` |
| 5 | YY 部分直播间标题栏没有分区名 | C-21 预置表只覆盖有列表模块的分区 | 读出 `zonghe` = 综合，补进表 | `dfcb14000` |
| 6 | 搜索“全部”时海外平台每次都失败，红色横幅列一长串 | “全部”就是“平台显示”里的平台（默认全部）；失败横幅每次列出所有名字 | 温和提示 + 可展开名字 + 搜索范围（记住） | `ef1380904` |
| 7 | 从直播间返回后约 2 秒内点平台标签没反应（一次） | 返回时下面的页面从左侧四分之一屏滑回（450 毫秒），手指按在标签的静止位置上点到的是别的标签 | 直播间用自己的转场页，下面的页面不再滑动 | `95c8b4da7` |
| 8 | 快手 `[笑哭]`、CHZZK、YouTube 表情显示成文字 | 消息模型没有表情片段，直播间只显示文字 | `LiveMessage.emotes`；四个平台解码填上；带上 3.x 的表情包；聊天列表显示图片 | `fffd28b31`、`bfcca456b` |
| a | 从画中画回来后控制条一直显示、按钮没反应，直到退出直播间 | 见下文（真机未复现） | 播放器在三种布局间保持同一个元素；回来时控制条重新计时、解锁、强制出一帧 | `6e0be540b` |
| b | 控制条没有深色衬底，亮画面上白图标看不清 | 渐变只有栏高、54% 黑 | 70% 起、超出栏 28 像素；图标加阴影 | `6e0be540b` |
| c | 标题栏录制按钮只是空心圆 | 窄栏只显示 `fiber_manual_record_outlined` | 录制图标（圆环里一个点），监控中加橙点，录制中红点加“录制中” | `f01c87861` |
| d | 调过音量手势后画面左侧出现蓝色喇叭按钮并一直留着 | 不是应用画的（见下文） | 无代码改动；记录排查结果 | — |

## 1 空状态按钮图标

- 现象：关注页空状态的“搜索直播”按钮用的是刷新图标。
- 根因：`live_ui` 的 `AppStatusView` 按钮固定 `Icons.refresh_rounded`（3.x `app_status_view.dart:474` 也是），按钮文字换成“搜索直播”“前往登录”“显示”时图标还是刷新。
- 改法：`AppStatusView`、`EmptyView` 加 `buttonIcon`（不传仍是刷新）。逐个检查了应用里所有带按钮的空状态/错误状态：

| 页面 | 按钮 | 图标 |
|---|---|---|
| 关注（无关注） | 搜索直播 | 搜索 |
| 关注（当前分组为空） | 查看未开播 / 刷新（原来写“重试”，空列表没有失败，改成“刷新”） | 眼睛 / 刷新 |
| 推荐、分区（没有平台） | 平台显示 | 调节 |
| 推荐、分区列表、分区房间（要登录） | 前往登录 | 登录 |
| 推荐、分区房间（全部被隐藏） | 显示 | 眼睛 |
| 搜索（无结果） | 继续网页搜索 / 显示未开播结果 | 浏览器 / 眼睛 |
| WebDAV | 创建新配置 / 打开配置列表 | 加号 / 侧栏 |

  重试、刷新类按钮保持刷新图标。
- 测试：`live_ui/status_view_test` 1 个；`favorite_test` 空页断言搜索图标、没有刷新图标。

## 2 不可见占位字符

- 现象：快手房间标题里有 U+FFFC（对象替换符，快手 App 在标题里放图片的位置），字体画成带“OBJ”的方框。
- 根因：各平台的文字原样进模型，没有统一的显示文字清理。
- 改法：
  - `live_core/json.dart` 加 `stripInvisiblePlaceholders`（和 `…OrNull`）：去掉 U+FFFC、U+FFF9～U+FFFB（行间注释符）、U+FFFE/U+FFFF（非字符）、C0/C1 控制字符（保留制表、换行、回车）；没有这些字符时原样返回同一个字符串。
  - **保留**零宽空格 U+200B、连接符 U+200C/U+200D/U+2060、U+FEFF 和替换符 U+FFFD：它们渲染时本来就不可见（或是乱码的可见标志），而且有含义——emoji 序列、猫耳弹幕“敲​黑​板”式的防屏蔽零宽空格、YouTube 颜文字里防止折行的 U+2060。最初一版去掉了它们，猫耳、YouTube、LiveMe 的样本对比测试立即报差异，所以收窄了范围。
  - `LiveRoom` 构造时清理 `title`、`nick`、`introduction`、`notice`（所有平台、关注和历史记录、`copyWith`、`fromJson` 都经过构造）。
  - `live_danmaku` 的 `DanmakuRun.message`（所有平台的弹幕都经过它）调用 `cleanDanmakuText`：清理消息文字、发送者名、粉丝牌名和醒目留言的名字、文字；没有要清理的就原样传递同一个对象。没有在快手里特判。
- 测试：`live_core/live_room_test` 2 个（字符集；四个字段从构造、`copyWith`、`fromJson` 来都清理）；`live_danmaku/connection_test` 1 个（文字、名字、粉丝牌、醒目留言都清理，其余字段不变，干净的消息原样通过）。

## 3 开播时长格式

- 根因：卡片用 `liveDuration`（分钟、小时+分），直播间用 `startedAgo`（分钟、小时+分，48 小时以上只写天）。
- 改法：`shared/rooms/room_texts.dart` 的 `elapsedText(Duration)`：不到 1 小时“N 分钟”（至少 1），不到 24 小时“N 小时 M 分”，24 小时起“N 天 M 小时”。卡片“已播 {时长}”、直播间“已开播 {时长}”都用它；不到 1 分钟两处都是“刚刚开播”。
- 翻译键：新 `duration_minutes`、`duration_hours`、`duration_days`、`live_play_started`、`room_live`；删 `live_play_started_days/hours/minutes`、`room_live_hours/minutes`。
- 测试：`live_play_controller_test` 的文字测试加 6 个断言（51 小时 49 分两处都是“2 天 3 小时”、边界）。

## 4 关注页状态标签

- 根因：手机首页的关注页把三个状态标签放在 AppBar 标题里（左边菜单按钮、右边“更多”），`TabAlignment.fill` 均分剩下的宽度；`TabBar` 默认每个标签左右各 16 的内边距，360 宽时每个标签内容只剩约 66 像素，“已开播”+数字放不下，`Flexible` 里的标签被渐隐截断（测试量到“已开播”只得到 12.5 像素）。
- 改法：标签内边距 4、手机上标题间距 4；数字改成标签后面的小圆角徽标；整个标签放在 `FittedBox(scaleDown)` 里，再窄也只缩小不截断。
- 测试：`favorite_test` 1 个（360 宽、12 个开播：三个标签文字都完整，数字在标签内，缩放不小于 0.9；修改前失败）。

## 5 YY 分区名

- 根因：C-21 的预置表来自 18 个分区页的列表模块，没有列表模块的分区（综合、手机直播、英雄联盟）的房间详情另有 `biz`，没覆盖。
- 探测（2026-10-01，只读，直连）：读了全部分区页和 10 个有房间的分区的 82 个在播详情：综合的房间是 `zonghe`（分区页路径 `/others/zonghe`），其他分区不用；手机直播的房间带内容分区的 `biz`（`talk`、`dance`、`red`、`pretty`、`sing`、`other`），已在表里；推荐页房间仍是 `other`（没有分区）；英雄联盟、体育、二次元、四个吃鸡分区当时没有在播房间。
- 改法：`YyApi.bizAreaNames` 加 `'zonghe': '综合'`；读不出的仍为空。只改了这张表和测试。
- 测试：`yy_api_test` 的预置表断言加一项和一个 `zonghe` 房间。

## 6 搜索“全部”和失败提示

- 根因：搜索的“全部”本来就只搜“平台显示”（`hotAreasList`）里的平台，但它默认是全部平台，没有代理时海外平台每次都失败；失败用 `MaterialBanner`（错误图标）列出全部名字。
- 改法（界面改进）：
  - 失败提示改成浅色说明卡：“有 N 个平台连接失败”，其中有海外平台时加“海外平台可能需要在设置里配置代理”；名字收起，点“查看是哪些”再展开；按钮：重试、搜索范围（选“全部”时）、代理设置（有海外平台失败时，打开设置的网络分区）、继续网页搜索（选了单个平台时）；右上角关闭。没有结果时的错误页同样用这段话和名字。
  - 新“搜索范围”：选“全部”时选项栏有“搜索范围 N/M”，点开按国内/海外分组勾选“全部”要搜的平台，有“只搜国内平台”“全选”两个快捷按钮，至少留一个。没勾的平台单独选它时照样能搜。设置记在 `MetaStore` 的 `search.allExcluded`（JSON 数组，和搜索历史一样），打开搜索页时先读出来再开始第一次搜索。
  - 海外平台的划分（`search_scope.dart` 的 `overseasPlatforms`）：Twitch、SOOP、Picarto、TwitCasting、niconico、SHOWROOM、CHZZK、LiveMe、TikTok、YouTube、BIGO、PandaTV、FC2、Steam、17LIVE。
  - 翻译键：新 `search_scope*`（6 个）、`search_failures_*`（4 个）、`search_proxy_settings`；删 `search_partial_failure`。
- 测试：`search_test` 2 个（模型：排除后重搜、不再请求被排除的平台、全排除等于不排除、单独选被排除的平台仍搜；页面：海外失败提示代理、范围对话框“只搜国内”、记住并在新页面生效），原有页面测试改为先展开名字。

## 7 返回后点平台标签没反应

- 复现（组件测试）：从推荐页进直播间再返回，在标签的静止位置点另一个平台：返回后 0 毫秒和 60 毫秒点都没切换，150 毫秒后正常。
- 根因：直播间是普通 `MaterialPage`，返回时下面的首页跟着跑 fade-forwards 转场的后半段——从左边四分之一屏宽处滑回原位，450 毫秒、强调曲线（开始很慢），前一段时间标签还在左边约 80～100 像素处。手指按在标签原来的位置，实际点到的是右边相邻的标签（常常就是当前选中的那个），看起来“没反应”。真机上释放播放器时如果卡一下，这段时间更长。不是路由过渡吞了点击，也不是标签控制器在重建（关闭中的直播间在反向动画时本来就不拦截点击，测试里点击都送到了首页）。
- 改法：直播间改用 `CustomTransitionPage`，自身仍是同样的 fade-forwards 进出动画；不是 Material 的页面路由不会带动下面的页面（`MaterialRouteTransitionMixin.canTransitionTo`），所以返回时首页一直在原位，点哪里就是哪里。其他页面不变。
- 测试：`popular_test` 1 个（返回后 0、60、150、300 毫秒在静止位置点击都切换；首页文字位置不动。修改前是“0 毫秒、60 毫秒没切换”）。

## 8 表情图片

### 模型（`live_core`，只加不改）

- 新类 `LiveEmote(code, url)`：消息文字里代表图片的那段文字（每次出现都是这张图）和图片地址。
- `LiveMessage` 加 `emotes`（默认空列表）。
- 快手：`KuaishouDanmakuArgs` 加 `emotes`（表情码 → 图片地址）；`KuaishouApi.emojiTable` 读房间页 `__INITIAL_STATE__` 的 `pcConfig.pcConfig.config["pcLive.webConfig.emojiPanel"]`（2026-10-01 共 207 个，`[笑哭]` → `//ali2.a.yximgs.com/bs2/emotion/….png`，改成 https），`roomDetail` 把它放进弹幕参数。这就是网页显示评论表情用的表；评论接口本身不带图片。从卡片进房（没读房间页）时表为空，表情码保持文字，由下面的本地表情包补上。

### 弹幕解码（`live_danmaku`）

| 平台 | 来源 | 表情码 |
|---|---|---|
| CHZZK | 聊天行 `extras.emojis`（名字 → 地址） | `{:名字:}`，只取文字里出现、地址是 http(s) 的 |
| YouTube | `runs` 里 `isCustomEmoji` 的 emoji：第一个 `shortcuts`，图片取 `image.thumbnails` 最大的一张 | `:名字:`（聊天、醒目留言、会员消息）；标准 emoji 本来就是字符，不需要图片 |
| 哔哩哔哩 | 表情包弹幕（`info[0][12]` 为 1，图片 `info[0][13].url`，录制样本里有 48 条）是整条文字；普通弹幕里的 `info[0][15].extra.emots`（码 → `{url}`） | 整条文字 / `[dog]`；`hdslb.com` 的 http 改 https |
| 快手 | 房间页的表情表 | `[笑哭]` |

`cleanDanmakuText` 清理文字时保留 `emotes`。`DanmakuEmoji` 也能读快手的本地表（格式同哔哩哔哩；3.x 打包了但没读）。

### 本地表情包（应用）

- 来源：3.x `assets/emo`（`~/ref/pure_live_archive/legacy/assets/emo`，和上游电视版 `~/ref/pure_live_TV/assets/emo` 的表完全一样，3.x 另多 32 张表里没引用的图片）。
- 带进 `apps/pure_live/assets/emo/`：哔哩哔哩 127、抖音 349、斗鱼 364、虎牙 303、快手 207 个表情，表 5 个、图片 1350 张，共 11.6 MB；`pubspec.yaml` 登记 `assets/emo/json/` 和五个图片目录。
- 没带：网易 CC 的表和图片（8.8 MB，599 张里只有 139 张对得上表）——CC 在 v4 没有弹幕（D01 未接入），带了也用不上；表里没引用的 32 张图片。
- `shared/danmaku/emotes.dart`：`EmoteLibrary` 第一次打开某个平台的直播间时读它的表（以后复用），`EmoteTable` 存表情码 → `(asset, url)`，虎牙的转义码（`/{dx`、`/{s_666` 等）也算表情码。
- `chatSegments(message, table)`：消息自带的表情码和本地表的表情码变成图片片段，其余是文字；同一个表情码**本地图片优先**，地址作为它的后备（消息自带的地址优先于表里的地址）。
- `live_ui`：`ChatEmoteSegment` 加 `asset`；`EmoteText` 先显示本地图片，读不出时用地址，再不行显示表情码。
- 只用在直播间的聊天列表；飞行弹幕仍是文字（3.x 的飞行弹幕表情图集属于渲染层，没在本任务范围）。

### 测试

`live_core/models_test` 1 个、`kuaishou_api_test` 1 个（样本房间页 207 个、https、过滤）；`live_danmaku/emotes_test` 4 个（CHZZK、哔哩哔哩表情包和 emots、快手、清理后保留）、`youtube_test` 1 个（S07 录制样本的频道表情）、`emoji_test` 改 1 个（快手表）；`live_ui/widgets_test` 1 个（本地图片、读不出时显示表情码）；应用 `shared/emotes_test` 4 个（五个平台的表都能读、每个表情码的图片文件都在、`pubspec` 登记了目录；读不出的表为空；本地优先、地址后备、未知码保持文字、虎牙转义码、CHZZK/哔哩哔哩表情包/快手地址）、`live_play_page_test` 加断言（哔哩哔哩 `[dog]` 在聊天列表里是本地图片）。

## 直播间补充问题（第二轮）

### a 画中画回来后控制条卡住

- 现象：从画中画回到应用后，控制条一直显示，按钮（包括全屏）点了没反应，直到退出直播间；新进直播间正常。
- 排查：真机没能复现（手机在用）。代码上，直播间页按 `_pip`/`_fullscreen` 在三种布局之间切换（画中画只画播放器、全屏、普通），播放器 `RoomPlayer` 在三处各建一个，所以进出画中画都会**丢掉播放器的整棵子树重建**：控制条状态、手势层、视频视图（media_kit 的 `Video`/纹理）都是新的。3.x 的做法正相反：先在原播放器上切到紧凑布局、等一帧再进画中画，避免纹理重新挂接。重建后控制条本该 4 秒后隐藏，而现象是一直不隐藏、点了也不变，最符合“界面帧没再更新、只有视频纹理在刷新”的情况（纹理更新不需要新的界面帧），但无法在没有真机日志的情况下确认是哪一步。
- 改法（防御性，按上面的原因收紧）：
  - `LivePlayPage` 给 `RoomPlayer` 一个 `GlobalKey`，`RoomPlayer` 给 `LiveVideoView` 一个 `GlobalKey`：三种布局之间移动同一个元素，不再重建播放器和视频视图。
  - `RoomPlayer.didUpdateWidget`：进入画中画时停掉隐藏计时；从画中画回来时控制条重新显示并重新计时、解除锁定，并 `scheduleForcedFrame()` 立即出一帧（即使窗口的生命周期通知还没到）。
  - 因为状态不再随布局重建：退出全屏时解除锁定（锁定时返回键仍能退出全屏，以前靠重建清掉锁）；切换全屏时控制条显示并重新计时（以前新播放器也是这样）。
- 测试：`live_play_page_test` 1 个（进出画中画是同一个播放器状态；回来时控制条显示、5 秒后隐藏；点画面再点全屏能进全屏；返回退出全屏）。
- 留给真机：需要在 K90 上重做一遍画中画进出，确认不再卡住；如果仍卡，抓 `adb logcat` 里开发版的生命周期（`onPause/onStop/onResume`）和 Flutter 的帧日志。

### b 控制条衬底

- 根因：底栏（和全屏顶栏）的渐变是 `black54 → transparent`，只有栏本身高度。
- 改法：渐变 `0xB3000000 → 0x66000000 → 透明`，往画面里多延伸 28 像素（`controlShadeReach`）；底栏和全屏顶栏的图标加柔和阴影。
- 测试：上面的直播间测试断言底栏衬底的起始颜色、全屏时有顶栏衬底。

### c 录制按钮

- 根因：手机标题栏是窄栏（`compact`），只显示图标，空闲时是 `fiber_manual_record_outlined`（空心圆）。
- 改法：空闲是录制图标（圆环里一个点，`radio_button_checked`），提示“录制”；已监控（等开播）加橙色小点，提示“已监控”；录制中在窄栏上也显示红点加“录制中”的浅红底按钮。宽栏仍是图标加文字。
- 测试：`recorder_page_test` 1 个（窄栏：没有空心圆，两个录制图标，监控中的有橙点，提示文字）。

### d 左侧的蓝色喇叭按钮

- 排查：直播间里应用自己画的东西，没有喇叭形状的按钮：音量/亮度手势的提示是画面**中间**的黑色圆角条（白色喇叭或太阳图标、进度、百分比），1 秒后消失；画面左侧唯一的按钮是全屏锁定后的“解锁”按钮（浅蓝底、锁图标，随控制条一起隐藏）；底栏的纯音频按钮选中时是蓝色耳机图标（在底栏，不在左侧）。`LiveVideoView` 不用 media_kit 自带的控制层（`controls: null`）。手势改音量调用的是 `AudioManager.setStreamVolume(STREAM_MUSIC, …, 0)`（不要求系统显示音量条）。
- 结论：最可能是 HyperOS 在媒体音量被应用改动后显示的系统音量指示，不是应用的按钮；没有代码改动。需要一张真机截图确认；如果确认是系统的，可以考虑手势改播放器音量而不是系统媒体音量（这会改变 3.x 的行为，要先问用户）。
- 顺带：本任务的播放器状态保持改动会让“锁定”跨越全屏切换，已在 a 里让退出全屏时解除锁定，避免解锁按钮留在普通布局的左侧。

## 测试和检查

- `live_core`：`dart analyze` 无问题，3590 个测试通过（新增 4 个）。
- `live_danmaku`：无问题，1568 个通过（新增 7 个）。
- `live_ui`：无问题，39 个通过（新增 2 个）。
- 应用：`flutter analyze` 无问题，`flutter test` 215 个通过（新增 10 个）。
- 观察到的不稳定测试：整套应用测试并发跑时，`live_play_more_test` 的“audio only keeps the stream; a sleep session …”有两次失败（`sleeping.audioOnly` 用真实计时等待，机器忙时来不及），单独跑和其余几次整套都通过；和本任务的改动无关，没有改它。

## 合并时注意（冲突点）

- 翻译文件 `zh.json`、`en.json`：加删了上面列出的键（第 3、6 节），按键名排序合并。
- `apps/pure_live/pubspec.yaml` 的 `assets`：加了表情目录；`assets/emo/` 新增约 1355 个文件（11.6 MB）。
- `live_core`：`live_room.dart` 的构造函数（`title`、`nick`、`introduction`、`notice` 不再是字段形参）、`live_message.dart`（新类和字段）、`json.dart`、`kuaishou_api.dart`（`roomDetail` 先读整页状态再取 `playList`）、`yy_api.dart`。
- `live_danmaku`：`connection_base.dart`（`DanmakuRun.message`）、`emoji.dart`、`sites/{bilibili,chzzk,kuaishou,youtube}.dart`。
- `live_ui`：`status_view.dart`、`emote_text.dart`。
- 应用：`routes/app_router.dart`（直播间页）、`pages/live_play/{player_view,live_play_page,chat_panel,record_button}.dart`、`pages/search/*`、`pages/favorite/favorite_page.dart`、`shared/rooms/room_texts.dart`、新文件 `shared/danmaku/emotes.dart`、`pages/search/search_scope.dart`。
- `docs/PLAN.md` 第 6 节 M13.x 行末尾加了 S02.1。

## 留给后续

| 内容 | 去向 |
|---|---|
| 画中画进出、蓝色喇叭按钮的真机确认 | 下一轮真机测试 |
| 飞行弹幕里显示表情图片（3.x 的图集） | 弹幕渲染层 |
| CC 的表情包 | CC 弹幕接入时一起带上 |
| UPGRADES 附录 B-12、B-13 的状态（“余下：消息模型带表情片段”已完成） | 合并时更新 `docs/specs/UPGRADES.md` |
