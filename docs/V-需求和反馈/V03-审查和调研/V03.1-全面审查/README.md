# V03.1 全面审查（2026-10-02）：4.0.0（Android）只读审查报告

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：验证（只读审查）
- 来源：用户 2026-10-02 的问题 09“其他界面问题和 bug，要全面分析”（[V02.2](../../V02-用户反馈和issue/V02.2-用户10月2日的问题/README.md)），同时给问题 01～08 找根因；旧文档 `docs/4.0.x/audit-2026-10-02.md`（标签 `docs-archive-2026-10-02`）
- 相关：决定 D-012（暂停后单击）、D-013（打码昵称）、D-020～D-023；去向见文末“结果”；真机 [S02.5](../../../S-质量和验证/S02-真机验证/S02.5-4.0.0构建号5001/README.md)

云端审查代理在 4.0.0（`e3a0799cf`）上读代码、读测试、解码仓库里录好的哔哩哔哩弹幕帧得出的结论，没有上真机。`LP` = `apps/pure_live/lib/features/live_play`，`UI` = `packages/live_ui/lib/src`，v3 = 标签 `v3.2.11` 的 `lib/`。任务单里引用的编号（A-01、B-1……）都指这一页。

> 已处理：A-01（暂停后中间图标）和 A-07（暂停后点画面就继续播放）已在 `f24ca8540` 修复：中间改成 ▶ 并可点击继续；点画面其他地方只显示控制层；附录 A 第 1 条已改。下面 A-01、A-07 的“修复”里没做的部分（暂停时控制层常显、▶ 加 45% 黑底、和小窗共用组件、缓冲时转圈）归任务 A07.10。

## A. 用户报告的 8 个问题

### A-07 暂停后点画面任意位置就继续播放（严重，已修）
- 根因：`LP/player/player_view.dart` 的 `_onTap()` 在暂停时调 `togglePlayPause()`（照 v3 的习惯：v3 `video_controller_panel.dart:219-232`；附录 A 第 1 条；测试 `live_play_layouts_test.dart:680`）。控制层 4 秒后自动隐藏（`_scheduleHide` 不管是否暂停），之后点画面就会恢复播放。
- 还要做：暂停时控制层不自动隐藏（`_scheduleHide` 遇到 paused 直接返回）。

### A-01 暂停后画面中间的图标像“正在播放”（一般，已修）
- 根因：`LP/player/player_status.dart` 画的 `AppIcons.pausedOverlay` 原来是 `pause_circle_outline`（暂停键的样子）。外面包了 `IgnorePointer`，70% 白，没有底色，画面亮时看不清，没有读屏标签。应用内小窗暂停时用 `AppIcons.miniPlay`（实心播放圆），两处不一致。
- 还要做：▶ 放在 64dp 的圆形 45% 黑底上，和小窗共用同一个组件；暂停期间一直显示，不跟着控制层隐藏；缓冲时换成转圈；纯音频暂停时也显示（见 B-9）。

### A-05 暂停后飞行弹幕还在动；想要“随视频暂停 / 继续飘”的设置（一般）
- 主画面已接好：`player_view.dart` 传 `running: status == playing`，`shared/danmaku/danmaku_overlay.dart` 暂停时平台弹幕的时钟停走、不进新弹幕，本地弹幕照常飞；测试 `live_play_page_test.dart`、`test/shared/danmaku_overlay_test.dart` 覆盖。
- 用户看到还在飞的原因（按可能性）：
  1. **画中画、应用内悬浮小窗没接**：`LP/mini/compact_danmaku.dart` 的 `DanmakuOverlay` 没传 `running` 和 `held`（默认 true），`_take` 也不看播放状态。
  2. **多画面没接**：`features/multiview/multiview_page.dart` 一带（`docs/TASKS.md` 第 7 节已记）。
  3. 主画面受 A-07 影响（任何一次点画面都恢复播放）；自己发的本地弹幕按设计暂停时照飞。
  4. 没有设置项。
- 修复：新设置 `danmakuPausedBehavior`（随视频暂停，默认 / 继续飘过），放弹幕设置的“显示”组；公共函数 `danmakuRunning(status, setting)`，主画面、`compact_danmaku.dart`（订阅 `controller.session.states`，暂停时清掉待发队列）、多画面（`cell.playing`）三处都用它；三处补测试。

### A-03 横屏手机：清晰度、线路菜单从上往下展开，位置对不齐（一般）
- 位置怎么定：底栏 `LP/player/player_controls.dart` 用 `StreamPickers(preferAbove: true)` → `LP/buttons/stream_menu.dart` → `UI/widgets/stream_menu_button.dart` 的 `showSmallMenu`；`_menuPosition` 先估高度（`条数 × 48 + 16`），再判断方向，把菜单的“顶边”算成“按钮顶 − 4 − 估计高度”交给 Flutter 的 `showMenu`。
- 根因：
  1. `showMenu` 只认顶边（Flutter 3.47.5 `popup_menu.dart` `y = position.top`），展开动画 `Align(alignment: topEnd, heightFactor: 动画值)` 永远从顶边往下长，所以菜单先在按钮上方出现一条线，再往下掉到按钮。
  2. 位置靠估算：哔哩哔哩常有 6～7 档清晰度，393 高的横屏上按钮上方只有约 339dp；估计高度超出时仍选向上，顶边为负，被 `_fitInsideScreen` 推回屏内，菜单下半截压在底栏上。
  3. 同样写法：`UI/widgets/app_menu.dart`（`showAppMenu`）、`LP/player/bar_parts.dart` 的画面比例和竖屏全屏画面模式。
- 修复：`showSmallMenu`、`showAppMenu` 改成自己的 `PopupRoute`，用 `CustomSingleChildLayout` 按**实测高度**定方向（向上 `y = 按钮顶 − 4 − 子高度`，向下 `y = 按钮底 + 4`），`getConstraintsForChild` 把最大高度限制为那一侧的空间（长列表在菜单里滚动）；动画 `FadeTransition` + `SizeTransition(axisAlignment: up ? 1 : -1)` 约 150ms，系统要求减少动态效果时不做动画；保留 Esc、返回、方向键。另一条路是 `MenuAnchor`。

### A-04 哔哩哔哩弹幕昵称打码（一般；访客拿不到全名）
- 解析在 `packages/live_danmaku/lib/src/sites/bilibili.dart`（`_chat`、`_userName`、`_richName`）：取值顺序 `info[0][15]` 的 `user.base.name` 和 `origin_info.name` → `uinfo` → `data.uinfo` → `info[2][1]`；检测到打码时 `LP/logic/room_controller.dart` 每次连接在聊天列表插一条系统消息。3.2.11 的 `_preferredBilibiliUserName` 顺序和判断一样，不是退化。
- 登录后：鉴权包 `uid` 取 Cookie 的 `DedeUserID`，`key` 来自带 Cookie 的 WBI 签名 `getDanmuInfo`，握手带 Cookie，逻辑上能拿到全名（仓库没有登录态样本，未在线验证）。
- **访客拿不到全名**：解码 `fixtures/bilibili/danmaku/S13-protover2-paired` 和 `S13-live`（uid=0）：`info[2]` 是 `[0, "观***"]`，富字段也打码，`dm_v2` 为空；服务器按连接身份打码，换字段无用。访客帧里没打码的只有头像 `user.base.face`、粉丝牌 `user.medal{name, level}`（`info[3]` 也有）、财富等级、`info[0][7]` 发送者哈希。
- 修复：访客时聊天列表顶部常驻提示“访客模式下哔哩哔哩隐藏昵称 · 去登录”（`AppNavigator.toBiliBiliLogin()`，登录回来自动 `reconnectDanmaku()`；Cookie 失效提示“登录已失效”）；解析粉丝牌填 `LiveMessage.fansName`、`fansLevel`（`LP/danmaku/chat_list.dart` 的 `_fans` 已经会画），卡片样式加头像；打码名不提供“屏蔽此用户”（见 B-1）。

### A-02 录制按钮没在录也像在录（一般）
- 原因 1 图形：`UI/widgets/record_glyph.dart` 未录是灰圈加**红色实心点**，录制中是红底白点闪烁加光晕；“红点”本身就是“正在录”的信号。来自 A07.1 改动 13；v3 未录是中性色空心圈 `Remix.record_circle_line`，录制中才变红。用到：`LP/buttons/record_button.dart`、`apps/pure_live/lib/shared/record/record_status_card.dart`。
- 原因 2 状态：`record_button.dart` 和角标 `LP/player/recording_badge.dart` 用 `RecordStatus.isActive`（`packages/live_record/lib/src/task.dart`，把 running、reconnecting、processing、preparing 都算进去），合成 MP4、准备中时也显示红底闪烁和“● 录制中”。
- 新设计：未录——单色，不用红，2dp 圆环加中心小实心圆，和其他图标同色；录制中——红色实心圆底，中间白色圆角方块，外圈红色光晕慢慢呼吸（减少动态效果时常亮），全屏顶栏有空间时右边加 `mm:ss`；红色只给真正在写文件的 running。等待开播：圆环右下角小钟；准备中、合成中：中性色环形进度；重连中：琥珀色虚线圆环。角标文字按状态写“录制中 / 重连中 / 合成中”。`RecordGlyphState` 扩成这些状态，按 `task.status` 映射，不再用 `isActive`；状态卡、录制中心、小窗角标、通知用同一组。

### A-06 竖屏右上角“切换直播间”很简陋（一般；比 v3 退化）
- 现在：入口三个（竖屏四宫格菜单第一项、竖屏全屏第二行 ⇄、未开播或失败状态里的按钮），都打开 `LP/dialogs/room_switcher.dart` 的底部表单：高 70%，三个标签（已开播 / 关注的回放 / 观看记录），普通 `ListTile`。没有封面、人数、开播时长；观看记录不标是否在播；没有搜索；看不到当前房间；空列表也占 70%；刷新失败不提示；横屏只露两三行。
- **选中后整页替换**（`AppNavigator.offAndToRoomDetail` → `pushReplacement`）：退出全屏、新页初始化早于旧页释放而用不上保留的播放器（C02.1）、来源列表（A07.3）丢失。v3 是靠右半屏的面板、封面卡片、`controller.switchRoom(room)` 原地换台。
- 设计：做成直播间面板 `RoomPanelKind.switchRoom`（`RoomSidePanel`，和录制、弹幕设置同一套）。竖屏普通布局从画面下沿升起盖住聊天区；竖屏流三档面板里；竖屏全屏底部 60%；横屏全屏和宽屏右侧 360dp 全高。头部：标题、刷新（显示上次刷新时间，失败提示）、关闭；分段：关注在播（数量）/ 来源列表（从热门、分区进来时才有）/ 观看记录 / 关注回放；可选按主播名过滤。每行：16:9 封面 112×63（左上“直播中”和人数），主播名、标题一行、“平台 · 分区”；未开播压暗写“未开播 · 上次看 2 小时前”；最上面固定一行“正在观看”。点一行调页面已有的 `_switchRoom(room)`（和上下滑换台同一条路：同一个播放器、保持全屏和方向、播放列表换成所选分组）；长按弹出卡片菜单。

### A-08 横屏右上：“切换直播间”按钮和菜单里的同一项重复（小）
- 横屏顶栏 `_trailing(switchRoom: true)` + `_roomActions()`（四宫格菜单用和竖屏同一份 `roomMenuGroups`），所以切换直播间、投屏、画面比例在栏上和菜单里各有一份；竖屏全屏第二行也重复了切换直播间和投屏。393 高的横屏上菜单要滚动。
- 建议：保留顶栏 ⇄；`roomMenuGroups` 加参数（例如 `onBars: {switchRoom, cast, videoFit}`），画面上的菜单不再列出栏上已有的项；竖屏普通布局的菜单不变。⇄ 打开 A-06 的同一个面板。

## B. 其他问题

| 编号 | 严重 | 位置 | 问题 | 建议 |
|---|---|---|---|---|
| B-1 | 严重 | `LP/danmaku/chat_list.dart`、`LP/logic/room_controller.dart`、`packages/live_danmaku/lib/src/filters/block_list.dart` | 哔哩哔哩访客的打码昵称（“观***”）照样能“屏蔽此用户”；屏蔽按名字全等（小写）、全局、持久：屏蔽一个“观***”会让所有以“观”开头的观众在所有哔哩哔哩直播间被永久屏蔽，并删掉列表里所有同名行 | 打码名不显示这一项（`BilibiliDanmakuProtocol.isMaskedName`），或按发送者哈希只在本场生效；屏蔽管理页标出已存的打码名并提示清理 |
| B-2 | 一般 | `LP/logic/reconnect_watch.dart`、`packages/live_player/lib/src/session.dart` | 暂停后继续播放时 `resume()` 先发 `buffering`，`ReconnectWatch` 在 paused 时没清 `_playingSince`，当成断流，显示“正在重连（第 N 次）”，次数累加 | paused、completed 时把 `_playingSince` 设为 null，或恢复前 `expectReopen()`；补测试 |
| B-3 | 一般 | `room_controller.dart`（`if (mobile) return 1`）、`LP/dialogs/room_dialogs.dart` | 手机上“房间音量”改的是 mpv 音量也存进 `roomVolumes`，但进房一律 1.0，下次不恢复；手势调系统音量，两层互不知道。v3 手机上房间音量就是系统音量 | 手机上“房间音量”直接调系统音量（和手势、v3 一致） |
| B-4 | 一般 | `LP/player/player_view.dart`（锁按钮条件 `lockable && controls`）、`LP/logic/room_status.dart` | 全屏锁定后房间下播或加载失败，锁按钮消失但 `_locked` 仍为真，顶栏也不显示，屏幕上无法解锁或退出全屏 | 只要 `_locked` 就显示锁按钮；或离开 playing 时自动解锁 |
| B-5 | 一般 | `LP/danmaku/chat_list.dart`（昵称颜色只设 HSL 亮度 0.42 / 0.72） | 浅色主题黄色昵称对白底约 1.6:1，青、绿也不到 3:1 | 按相对亮度逐步加深或提亮到对背景 ≥ 4.5:1 |
| B-6 | 一般 | `room_controller.dart`（每条弹幕通知一次）、`chat_list.dart`（每条 `setState`、下一帧 `jumpTo`） | 热门房间每秒几十上百条时中端机掉帧 | 弹幕批量通知（每帧或每 100ms）；聊天列表单独监听；跟随到底时每批只 `jumpTo` 一次 |
| B-7 | 一般 | 直播间各弹窗 | 右上菜单是原生 `PopupMenuButton` + `ListTile`（图标 20dp）；清晰度用 `showSmallMenu`，别处用 `showAppMenu`（图标 24dp）；画面比例从菜单进是居中对话框（当前项只有对勾、文字不变色），从横屏底栏进是小菜单；方向、定时关闭、房间音量、获取直链、投屏都是居中对话框；切换直播间、长按弹幕是底部表单；录制、弹幕设置是侧面板。横屏全屏时对话框和底部表单压在画面中间 | 落实 A02.2：小菜单、对话框、面板各统一成一个组件；直播间里的“设置”和“选择”一律用面板或贴着按钮的小菜单 |
| B-8 | 小 | `player_view.dart`（画面挂了双击） | 每次单击都要等双击超时（约 300ms），显示控制层、点弹幕慢半拍 | 单击立即处理，第二下到来时撤销并切全屏 |
| B-9 | 小 | `room_status.dart`、`player_status.dart` | 纯音频判断排在暂停之前，暂停后仍写“纯音频播放中” | 区分纯音频播放中和已暂停，暂停时显示 ▶ |
| B-10 | 小 | `player_view.dart`（控制层隐藏时录制小角标 `left: 12`） | 横屏刘海在左边时被挡住 | 横屏时左边距加 `padding.left` |
| B-11 | 小 | `player_controls.dart`（竖屏全屏上下栏第二行是不能滚动的 Row） | 7 个 48dp 按钮约 352dp，分屏、自由窗口或系统“显示大小”调大后溢出 | 宽度不够时横向滚动，或把方向、画面模式收进“更多” |
| B-12 | 小 | `LP/live_play_page.dart`（普通布局和全屏是两棵树） | 退出全屏后聊天区标签回到第一个，滚动位置、三档面板高度被重置 | 标签序号、面板档位存到页面 State 或 `PageStorage` |
| B-13 | 小 | `LP/dialogs/stream_dialogs.dart` | 获取直链和投屏：进入线路列表后回不去；不标当前线路；对勾直接写 `Icons.check_rounded` | 线路页加返回；标当前线路；用 `AppIcons.selected` |
| B-14 | 小 | `room_dialogs.dart` | 房间音量取消静音直接跳 100% | 记住静音前的值 |
| B-15 | 小 | `LP/buttons/follow_button.dart` | 取消关注确认按钮写“确认”（A02.2 D2 要求写“取消关注”）；取消成功没有反馈 | 按 D2 改；取消后给提示 |
| B-16 | 小 | `LP/layout/room_info_bar.dart`、`UI/widgets/record_glyph.dart` | 开播时长“时:分”、录制时长“分:秒”，容易看错 | 开播时长写“2 小时 18 分” |
| B-17 | 小 | `LP/layout/portrait_panel.dart` | 三档面板把手读屏读“250 px” | 改成“最低 / 中间 / 最高” |
| B-18 | 小 | `LP/player/bar_parts.dart` | 电量数字 9 号字 | 至少 11 号 |
| B-19 | 小 | `LP/live_play_page.dart`（聊天栏收起把手 40×64 盖在画面右缘中间） | 挡住音量手势和右侧弹幕点按 | 放到画面和聊天栏的分隔线上，或跟控制层一起隐藏 |
| B-20 | 小 | `LP/record/record_panel.dart` | 每次重建都同步 `File.existsSync()`，录制中约每秒一次 | 异步检查并缓存 |

## C. 还没重新设计或增强的 Android 部分

1. 通用组件和弹窗组件（A02.1、A02.2）设计已确认，没开发；A-03 和 B-7 的根源。
2. A07.6 推迟的子弹窗：切换直播间、定时关闭、房间音量、投屏、获取直链（`LP/dialogs/room_switcher.dart`、`room_dialogs.dart`、`stream_dialogs.dart`，还留着 9 处直接写的颜色和图标）。
3. 暂停状态没人设计（A07.7 第 9 条留给 A07.1/U.2c）：中央图标、暂停时控制层是否常显、点画面的规则、暂停时的弹幕、纯音频暂停。
4. 录制图标（A07.1 c13）按 A-02 修订，状态卡、录制中心、角标、通知一起改。
5. 多画面和小窗的弹幕层没接 D03.1 的新参数（暂停时停住、帧率上限等）。
6. E06.1“交给界面”的 7 项（`docs/E-直播平台/E06-平台层升级/E06.1-已批准升级的余项/record-2.md`）：Twitch Cookie 失效提示、酷狗 PK“对方”标签、17LIVE 名字颜色和徽章、恢复后显示实际清晰度、哔哩哔哩轮播播放入口和起始位置（现在只显示“轮播中”无法播放）、Twitch 按播放器能解的编码请求、FC2 控制连接接手。
7. 真机验证空缺：S02.4（备份恢复、WebDAV、设备同步、扫码、应用内更新、字体）；`docs/S-质量和验证/S02-真机验证/S02.3-K90验证主流程/record.md` 的“没测的”；INVENTORY 里“没验证”的各项；S03.1 统一验证。
8. `docs/TASKS.md` 第 7 节没落地的：主题 `centerTitle`；设置行说明对比度约 3.4:1；开关打开时滑块和底色同为主色；“录制已停止”通知点开定位不到任务；设置里的弹幕设置页加路由并和直播间用同一组件；设置里的卡片预览还在用旧 `RoomCard`（`features/settings/appearance_pages.dart`）；不再使用的翻译键清理。

## 结果

报告当天（2026-10-02）按下表开了 9 个任务（旧编号 B01～B09）加上已经确认的 A02.1、A02.2（U01、U02），全部当天合并、随构建号 5001 发布（D-008）。表里“状态”是 2026-10-07 的登记表。

| 报告条目 | 内容 | 去向 | 状态 |
|---|---|---|---|
| A-01、A-07 | 暂停后中间图标、点画面就继续播放 | 热修 `f24ca8540`；其余（常显、黑底、缓冲转圈、和小窗共用）→ [A07.10](../../../A-界面设计/A07-直播间界面/A07.10-暂停状态/README.md)；规则 D-012 | 待真机 |
| A-05、B-2、B-4、B-9 | 暂停时的弹幕（小窗、画中画、多画面没接）；继续播放误报重连；锁定后失败没法解锁；纯音频暂停 | [A07.10](../../../A-界面设计/A07-直播间界面/A07.10-暂停状态/README.md) | 待真机 |
| A-03 | 横屏清晰度、线路菜单从上往下出 | [A02.3](../../../A-界面设计/A02-组件/A02.3-贴着按钮的小菜单/README.md) | 待真机 |
| A-04、B-1 | 哔哩哔哩访客打码昵称；打码名“屏蔽此用户”误伤 | [D01.32](../../../D-弹幕/D01-平台弹幕协议/D01.32-哔哩哔哩访客昵称和粉丝牌/README.md)（登录引导、粉丝牌、头像）、[D02.1](../../../D-弹幕/D02-过滤和屏蔽/D02.1-打码昵称不能屏蔽/README.md)（打码名不能屏蔽、清理已存的）；还原昵称不做（D-013，[V04.1](../../V04-不做的/V04.1-还原哔哩哔哩打码昵称/README.md)） | 待真机 |
| A-02 | 录制按钮没在录也像在录 | [A10.3](../../../A-界面设计/A10-录制界面/A10.3-录制按钮和状态图标/README.md)；通知标题随后 [H05.1](../../../H-录制/H05-录制通知/H05.1-录制通知按状态写标题/README.md) | 待真机 |
| A-06、A-08 | 切换直播间简陋、整页替换；横屏入口重复 | [A07.13](../../../A-界面设计/A07-直播间界面/A07.13-切换直播间面板/README.md)（D-022） | 待真机 |
| B-3、B-7、B-13、B-14、B-15 | 房间音量两层互不知道；各弹窗不统一；获取直链和投屏的线路页；取消静音跳 100%；取消关注的按钮文字和反馈 | [A07.12](../../../A-界面设计/A07-直播间界面/A07.12-直播间子弹窗统一/README.md)（D-021） | 待真机 |
| B-5、B-6、B-20 | 昵称对比度；每条弹幕一次通知；录制面板同步查文件 | [D04.1](../../../D-弹幕/D04-数据流和性能/D04.1-弹幕性能和可读性/README.md) | 待真机 |
| B-8、B-10、B-11、B-12、B-15～B-19 | 单击慢半拍、录制角标被刘海挡、竖屏全屏按钮溢出、全屏前后状态丢、开播时长写法、把手读屏、电量字号、聊天栏把手挡手势 | [A07.11](../../../A-界面设计/A07-直播间界面/A07.11-直播间小问题合集/README.md) | 待真机 |
| C-1 | 通用组件和弹窗组件没开发 | [A02.1](../../../A-界面设计/A02-组件/A02.1-通用组件/README.md)、[A02.2](../../../A-界面设计/A02-组件/A02.2-弹窗组件/README.md) | 待真机 |
| C-2 | A07.6 推迟的子弹窗 | A07.12 | 待真机 |
| C-3 | 暂停状态没人设计 | A07.10 | 待真机 |
| C-4 | 录制图标按 A-02 修订 | A10.3 | 待真机 |
| C-5 | 多画面和小窗的弹幕层没接新参数 | 暂停时停住 → A07.10；多画面弹幕帧率 → [N01.2](../../../N-多画面和投屏/N01-多画面/N01.2-多画面弹幕跟随帧率设置/README.md)（V03.3 开的，未开始） | 部分 |
| C-6 | E06.1“交给界面”的 7 项 | [E06.2](../../../E-直播平台/E06-平台层升级/E06.2-平台层新数据接到界面/README.md) | 暂停 |
| C-7 | 真机验证空缺 | S02.4、S02.5、S02.6、S03.1 | 未开始 |
| C-8 | 主题 `centerTitle`、设置行说明对比度、开关滑块颜色 | A02.1（标题位置 D-011） | 待真机 |
| C-8 | “录制已停止”通知定位任务；设置里的弹幕页 | [A08.5](../../../A-界面设计/A08-弹幕界面/A08.5-设置里的弹幕页/README.md) | 待真机 |
| C-8 | 设置里卡片预览用旧 `RoomCard` | 已换成 `LiveRoomCard`（`apps/pure_live/lib/features/settings/appearance_pages.dart:886`，A11.2） | 完成 |
| C-8 | 不再使用的翻译键清理 | Z05.1；清理时误删了刷新率说明（D-016），之后不再清理（D-024） | — |

## 验证

- 报告本身是只读结论，没有测试；每条的验证在去向任务里（修 bug 先写改之前会失败的测试；真机步骤在各自的 `verify.md`，S02.5 汇总）。
- 报告里“未在线验证”的推断（A-04 登录后能拿到全名）由 D01.32 的真机步骤（S02.5 2A-06）验证。

## 留下的问题

- 去向任务都“待真机”：S02.5 看完后，不通过的开返工任务并在上表补一行。
- C-5 的多画面弹幕帧率（N01.2）、C-6（E06.2 暂停）还没做。
