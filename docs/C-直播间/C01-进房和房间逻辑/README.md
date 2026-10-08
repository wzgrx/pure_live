# C01 进房和房间逻辑

进房、房间控制器、播放接入、刷新、播放列表。

一个直播间从打开到离开的逻辑：取详情、选清晰度、开播放、接弹幕、定时刷新，以及房间拥有的对象怎么建、怎么交接、怎么释放。

## 范围

- 包括：
  - `LiveRoomController`：详情、清晰度和线路、播放、弹幕事件、醒目留言、人数、定时刷新、重试、纯音频、定时关闭的计时、房间音量、网络电视的请求头和回看。
  - `RoomRuntime` 的建和交接：页面 → 应用内小窗 `FloatingRoom` → 再回到页面；离开时交给 `PlayerStandby`（“播放器强制销毁”关）；原地换台（竖屏全屏上下滑、切换直播间面板里选房间）。
  - 房间状态的判断（`logic/room_status.dart` 的 `pictureStateOf`：画面上该显示哪种状态）和断流监视（`ReconnectWatch`）。
  - 页面一级的组装：`live_play_page.dart` 建运行时、全屏和方向、返回链、键盘快捷键。
- 不包括（归哪里）：
  - 各布局的样子、控制层、面板归 A07；状态画面的样式归 A07.7；切换直播间面板的样子归 A07.13。
  - 播放会话内部（恢复、换线、卡住检测、45 秒空闲释放引擎）归 G02；竖屏预判归 G04。
  - 弹幕过滤器（`DanmakuMessageFilter` 在 `packages/live_danmaku`）和弹幕数据流的性能归 D02、D04，这里只接线。
  - 小窗、画中画、后台归 [C02](../C02-小窗、画中画、后台播放/README.md)；菜单工具和返回接管归 [C03](../C03-直播间工具/README.md)；刷新率归 R02。

## 现状：做到哪、怎么工作的

用户看得到的：

- **进房**：卡片上的名字、头像、人数先显示，画面区转圈；拿到详情后标题、人数、开播时长更新；能播就按偏好选清晰度开始播放（移动数据下用“移动数据清晰度”）；弹幕同时开始连接，聊天列表里有“正在连接弹幕服务器”这类状态行。
- **不能播**：未开播、封禁、轮播、受限（要登录、地区、付费……）、取不到流时，画面区写原因，给“刷新”或“重试”（A07.7 的 18 种状态）；未开播的房间每 60 秒查一次，开播后自动开始播放，并说明“开播后会自动开始播放”。
- **播放中**：切清晰度和线路时旧画面继续播；平台实际给的清晰度和请求的不同时选中实际那档并提示“平台实际返回 超清，已按真实画质播放”；断流时显示“正在重连（第 N 次）”。
- **离开**：开着“离开直播间时小窗播放”且正在播 → 转应用内小窗；否则停播，“播放器强制销毁”关（默认）时播放器留 45 秒给下一个直播间。
- **换台**：竖屏全屏上下滑、切换直播间面板里选房间，都在同一个页面、同一个播放器上换房间（A07.3、A07.13）。

内部怎么工作：

```text
LivePlayPage.initState（live_play_page.dart:196）
  ├─ FloatingRoom.claim(room)（:220）：小窗里正在播同一个房间 → 直接接过它的 RoomRuntime
  └─ 否则 PlayerStandby.take(config) ?? 新建 PlaybackSession（:228）→ _newRuntime（:266）
        = LiveRoomController + ReconnectWatch + RoomBackgroundPolicy + RoomOrientationChoice
  controller.start()（room_controller.dart:304）：跟着过滤设置和屏蔽表 → load() → 每 60 秒 refreshDetail()
load()（:360）：_epoch 加一 → getRoomDetail
  ├─ 失败 → failed（保留卡片信息，状态改成待定 pendingAfterError）
  ├─ 不能播 → offline
  └─ _startStream（:413）：发现清晰度 → 默认档 → _openQuality（:462）
        → resolvePlayUrls → 局域网地址先申请本地网络权限（:489）→ session.open
        → 第一次打开成功记观看历史（:438）→ 连弹幕、拉醒目留言
dispose（live_play_page.dart:450）：转小窗（shouldFloatOnLeave）/ 交给 PlayerStandby / 直接释放
```

- **阶段**：`RoomStage`（`logic/room_controller.dart:20-37`）只有 loading、failed、offline、unplayable、playing 五个；播放中的细分（打开、缓冲、出错、暂停、播完）看会话的 `PlaybackState`。3.x 是四个可能互相矛盾的标志（C01.1 问题 1）。
- **晚到的回答**：每次 `load` 的 `_epoch`、每次连弹幕的 `_danmakuEpoch`；`_current(epoch)`（`:396`）不对就丢掉。
- **刷新（B-24）**：`refreshDetail`（`:758`）优先用平台的轻量接口（`LiveSiteRoomRefresher.getRoomDetailForRefresh`），状态待定时不动；不在播而现在能播 → `load()`；播放出错且平台说已下播 → `load()`；弹幕连接已结束而主播还在播 → 重连；其余只更新标题和人数。
- **弹幕**：首连超时 30 秒（`danmakuStartTimeout`，`:100`；3.x 20 秒，C01.1 问题 6）；连接状态 `ChatConnection` 给聊天列表的空状态用（A08.1）；哔哩哔哩游客的打码昵称提示 `ChatNameHint`（D02.1、D-013）。
- **完成度**：功能清点第 8 节 8.1（ROOM，25 项）除 F-ROOM-24（播放内核切换，不做，v4 只用 mpv）外都已实现；V03.3（2026-10-03）核对后清点表第 8 节没有“缺失”“有问题”，只有 F-ROOM-13 屏幕常亮是“没验证”（归 S02.6）。C01.1、C01.2 记录里“留给后续”的项已分别由 A07、A08、C02.1、C03.1、O03.1、O05.1 做完；C01.3（余项）因此按 D-029 改成“不做”。还没做的是 C01.4（清晰度显示平台实际给的档），以及 2026-10-07 为下面“已知问题”前四条登记的 C01.5（后台开播不出声）、C01.6（换场重连、YouTube 设置立即生效）。
- **清晰度的名字**：`_openQuality`（`logic/room_controller.dart:462`）按 `resolveAppliedPlayQuality`（`packages/live_core/lib/src/live_site.dart:224`）决定显示哪一档：平台确认的编号在列表里 → 那一档；平台说换成了哪档（`appliedQuality`）→ 那一档；否则显示请求的那档并标“未确认”，菜单里名字后面加“?”（`buttons/stream_menu.dart:51`）。录制已经改成按平台编号命名列表外的档（H01.3 的 `RecordStreamResolver.servedQuality`，`packages/live_record/lib/src/resolver.dart:334`），直播间还没跟上，归 C01.4。

## 代码地图

| 文件 | 职责 |
|---|---|
| `apps/pure_live/lib/features/live_play/live_play_page.dart` | 页面：建和拆 `RoomRuntime`（`initState` :196、`_newRuntime` :266、`dispose` :450）、原地换台（`_pickRoom` :342、`_switchRoom` :360）、全屏和方向（`_enterFullscreen` :526、`_exitFullscreen` :576、`_restoreSystemUi` :595）、返回链（`_poppable` :639、`_nativeBack` :646、`_back` :662）、快捷键（`CallbackShortcuts` :736：Esc、F、空格、↑↓、R、媒体键）、播放器配置 `_engineConfig`（:399）和比较键 `engineConfigKey`（:412） |
| `logic/room_controller.dart` | `LiveRoomController`（3.x `LivePlayController` + `PlayerController` + `DanmakuController`）：`start` :304、`load` :360、`_startStream` :413、`_openQuality` :462、`selectQuality` :715、`selectLine` :730、`retry` :744、`refreshDetail` :758、弹幕 `_syncDanmaku` :809 和 `_onMessage` :868、人数 `_applyAudience` :931、醒目留言 :959、屏蔽 `blockUser` :997 和 `blockKeyword` :1008、纯音频 `setAudioOnly` :591、定时关闭 `setSleepTimer` :614、房间音量 `setVolume` :575、回看 `playCatchup` :642 和 `backToLive` :705、网络电视请求头 `iptvPlayHeaders` :1050；`RoomStage`、`ChatConnection`、`ChatNameHint` |
| `logic/room_runtime.dart` | `RoomRuntime`：一个房间拥有的五样东西，`dispose(keep:)` 停完再交出播放器（:63）；`FloatingRoom`：应用内小窗持有的那一个房间（`show` :131、`claim` :146、`close` :157，打开多画面时关） |
| `logic/player_standby.dart` | `PlayerStandby` 和 `playerStandbyProvider`：离开直播间时留一个停下的会话，下一个房间的播放器配置相同就接着用，不同就释放（C02.1 c1） |
| `logic/room_playlist.dart` | `RoomPlaylist`：竖屏全屏上下滑换台的列表，两头循环（A07.3） |
| `logic/reconnect_watch.dart` | `ReconnectWatch`：只有会话自己的恢复才算“正在重连（第 N 次）”，慢起播、短暂卡顿、用户自己换清晰度不算（B02） |
| `logic/room_status.dart` | `pictureStateOf`：房间阶段 + 会话状态 + 重连 → 画面上显示哪种状态和哪些按钮（A07.7） |
| `logic/room_switch.dart` | 切换直播间面板的分组（已开播的关注、来源列表、观看历史、关注的回放）、排序、列数和卡片高度、“N 分钟前”（A07.13） |
| `logic/room_layout.dart` | 布局判断：`RoomDisplay`、`roomPageLayout`、竖屏面板三档 `portraitPanelStops`、`FullscreenOrientation`、拖动和上下滑换台的阈值（A07.2、A07.3） |
| `logic/room_orientation.dart` | `RoomOrientationChoice`：本直播间画面方向（自动、强制竖屏、强制横屏），开着“记住单个直播间方向”时存进 `portraitRoomOverrides` |
| `logic/area_lookup.dart` | `findAreaByName`：直播间信息里点分区名，找到平台的那个分区 |
| `logic/iptv_guide_rows.dart` | 节目单的行（按天分组、正在播、可回看）和时间文字（A07.7 c16～c19） |
| `logic/device_battery.dart` | 全屏顶栏的电量（Android 走 `pure_live/device_controls`，A07.4） |
| `logic/room_refresh_rate.dart` | 播放时把视频帧率告诉显示（属 R02，R02.1） |
| `logic/background_playback.dart`、`logic/mini_window.dart` | 见 [C02](../C02-小窗、画中画、后台播放/README.md) |
| `logic/predictive_back.dart` | 见 [C03](../C03-直播间工具/README.md) |

测试（都在 `apps/pure_live/test/features/live_play/`，用 `live_play_support.dart` 的假平台、假弹幕、假引擎）：

| 测试文件 | 覆盖什么 |
|---|---|
| `live_play_controller_test.dart`（13 个） | 进房选清晰度、开会话、记历史、连弹幕；屏蔽词、撤回、在线和热度分开、醒目留言、通知和重连状态行；未开播刷新后自动播放、弹幕结束后重连（B-24）；详情失败保留卡片、受限说明；画质降级提示；不支持弹幕的平台；移动数据清晰度 |
| `live_play_page_test.dart`（12 个） | 手机和宽屏布局、关注和取消、房间信息、全屏和返回、从画中画回来控制条重新计时（M13.16） |
| `live_play_room_test.dart`（14 个）、`live_play_states_test.dart`（21 个） | 各布局的房间、各种状态的画面和按钮 |
| `live_play_more_test.dart`（8 个）、`live_play_more_page_test.dart`（4 个） | 礼物行、纯音频、自动助眠、房间音量的 3.x 键、网络电视请求头和回看、后台规则、局域网源先申请权限、投屏和获取直链 |
| `room_extras_test.dart`（13 个） | 竖屏预判、快手 App、切换刷新、返回接管、播放器留给下一个房间、小窗比例、竖屏诊断、内存紧张、媒体键 |
| `room_swipe_test.dart`（9 个）、`room_switch_test.dart`（17 个） | 上下滑换台、切换直播间面板和原地换台 |

## 3.x 基线

- `lib/modules/live_play/controllers/live_play_controller.dart`（1178 行，`git show v3.2.11:lib/modules/live_play/controllers/live_play_controller.dart`）：`onInitPlayerState`（:682）用 `_roomLoadEpoch`（:81、:694）丢弃晚到的回答；`_handleLiveRoom`（:744）记历史、更新关注快照（:752-753）；`_handleNotLiveRoom`（:778）；`_updateFavoriteRoomSnapshot`（:794）；`switchRoom`（:884）在原页面换房间；屏幕常亮 `_updateWakelock`（:252）。
- `controllers/player_controller.dart`（908 行）：`getPlayQualites`（:571）、`_setDefaultResolution`（:611，WLAN 和移动数据各一个偏好）、`switchStreamSelection`（:686，旧流不断）。
- `controllers/danmaku_controller.dart`：首连超时 20 秒（:22）。
- `lib/player/core/player_manager.dart`：`useHardStopOnExit`（:234）、离开后 45 秒释放空闲播放器（`idlePlayerReleaseDelay` :306、`_scheduleIdlePlayerRelease` :3656、`softStop` :3686）。
- 必须保留的习惯（[specs/UI.md](../../specs/UI.md) 附录 A）：第 9 条切换画质和线路不重建播放器、以最后一次选择为准；第 10 条进房不改设备音量（全局静音除外）；第 11 条强制横屏全屏退出后恢复竖屏；第 12 条“默认全屏”。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 后台时未开播的房间开播会自动开始播放：定时刷新在后台照跑，不在播而现在能播就 `load()`；后台策略 `onHidden` 只在离开应用后 1.5 秒判断一次，那时会话是 `idle`/`stopped` 就直接返回、不记“我们暂停的”，之后才开始的播放没人管；后台时也不会补出媒体通知（`_syncNotification` 在 `_hidden` 时直接返回） | `logic/room_controller.dart:325-327`（定时器）、`:775-778`（`load()`）；`logic/background_playback.dart:472-490`（`onHidden`）、`:431-440`（通知） | 在未开播的直播间按 Home 或锁屏，主播开播后手机突然出声，通知栏也没有媒体通知可以停（读代码得出，未在真机确认；3.x 没有定时刷新，没有这个问题） | [C01.5](C01.5-后台时未开播的房间开播后/README.md)（2026-10-07 登记，第二档，小）：离开时没在播的房间后台不自动开播、回来再开始；后台播放中重新加载时保住媒体通知。原来归 C01.3 第 3 阶段（D-029 关掉）。2026-10-08 已改，待真机 |
| 定时刷新在后台也每 60 秒请求一次详情 | `logic/room_controller.dart:325` | 后台多一点流量和电（3.x 没有定时刷新） | C01.5 定为“照常刷新、只不自动开播”（回来时状态是新的）；耗电由 R05.1 测，明显时再降频 |
| 主播换场后弹幕参数变了，直播间不重连，弹幕停在旧的一场（TwitCasting、克拉克拉、SHOWROOM）：刷新只在弹幕连接已经结束时重连（`danmaku.status == DanmakuStatus.closed`），不比较参数；这几个平台换场后旧连接不会自己结束（SHOWROOM 只剩 `ACK`）。而且刷新用的轻量接口不带弹幕参数（SHOWROOM `_detail(entry: false)`、克拉克拉 `profileDetail`），`LiveRoom.mergeFrom` 保留旧的 `danmakuData`，所以就算重连也是旧参数。只有播放出错且平台说已下播时才会整个 `load()`、顺带用新参数连弹幕 | `logic/room_controller.dart:785`；`packages/live_core/lib/src/live_room.dart:619`；`packages/live_core/lib/src/sites/showroom/showroom_site.dart:290-310`、`:320`；`packages/live_core/lib/src/sites/kilakila/kilakila_site.dart:331`；`packages/live_core/lib/src/sites/twitcasting/twitcasting_site.dart:259` | 人留在直播间时主播下播又开播、播放会话自己恢复了（没走 `load()`），聊天列表不再有新弹幕，要重新进房。3.x 这三个平台没有弹幕 | [C01.6](C01.6-主播换场后弹幕参数变了要重连/README.md)（2026-10-07 登记，第二档，小）：刷新发现换场时按进房详情重取 `danmakuData` 并强制重连；连接结束后刷新没带参数时先取进房详情（百度签名过期同一处，平台层的刷新带参数在 [E05.4](../../E-直播平台/E05-平台框架和模型/E05.4-平台层小问题合集/README.md)） |
| 改设置“YouTube 显示全部聊天”要重新进房才生效：这个设置只在建 YouTube 弹幕连接时读一次（`allChat:`），控制器只跟 `enableDanmakuDisplay`、`enablePipDanmaku` 两个设置重连 | `apps/pure_live/lib/app/platforms.dart:227`；`logic/room_controller.dart:313-315` | 在直播间里改了这个开关，聊天还是原来的模式，用户以为没生效 | [C01.6](C01.6-主播换场后弹幕参数变了要重连/README.md) 第 2 阶段（2026-10-07 登记）：控制器对 YouTube 房间多跟这个设置，连接每次建连时读 |
| 平台给的清晰度不在列表里时直播间显示“原画?”，同一路流录制显示“超清” | `logic/room_controller.dart:491-497`；`packages/live_record/lib/src/resolver.dart:334-350` | 同一路流两个说法 | [C01.4](C01.4-直播间清晰度显示实际档/README.md) |
| 从画中画回来后控制条卡住（K90 第二轮出现过，S02.1 做了防御性修改） | `player/player_view.dart:241-268` | 未复验 | [O02.1](../../O-Android系统集成/O02-画中画/O02.1-画中画复验/README.md) |

## 相关决定和规范

- D-001（3.x 是基线）、D-012（暂停后单击只显示控制层）、D-017（测试定时器）、D-018（3.x 设置键不变）、D-022（切换直播间）、D-023（横屏全屏翻转）、D-029（C01.3 不再单独做，真机核对并入 S02.4、S02.6）。
- [specs/UI.md](../../specs/UI.md) 附录 A 第 7、9、10、11、12 条；[specs/UPGRADES.md](../../specs/UPGRADES.md) 的 B-24、C-4、14-3、19-4、28-2 等（C01.1 记录的“已批准的升级”表）。

## 测试和验证

- 自动测试：`cd apps/pure_live && flutter test test/features/live_play/`。缺：后台时开播的行为；刷新发现换场后弹幕参数变了的行为；`refreshDetail` 和用户点“刷新”交错的竞态没有专门的用例；平台给列表外清晰度时的显示（C01.4 补）。
- 真机：[CHECKLIST](../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 1 节第 1～5、9、14、15 条。S02.2、S02.3 看过第 1 条（七个国内平台能播）和第 5 条（全屏和返回）；第 3 条断网重连归 [S02.6](../../S-质量和验证/S02-真机验证/S02.6-K90补验/README.md)。C02.1 的播放器留给下一个房间（F-ROOM-21）、C03.1 的快手跳转（F-RT-05）和切换直播间刷新（F-RT-07）按 D-029 判为完成（关键部分不靠原生），没有专门的真机任务，日常回归时照第 1 节第 12、14 条看。

## 路线

1. **C01.4**（第二档，小，两个阶段）：清晰度按平台编号命名，和录制一致。和 E06.2 的“实际清晰度”阶段改同一段代码（`_openQuality`、`_refreshPlan`），最好一起做或紧接着做。
2. **C01.5**、**C01.6**（2026-10-07 登记，第二档，小）：后台时开播不出声、后台播放补出媒体通知；换场后弹幕参数变了要重连（含百度签名过期）、“YouTube 显示全部聊天”立即生效。两个任务和 C01.4、E05.4 都改 `room_controller.dart`，先后做。
3. 以后：G02.2（缓冲状态对账）合并后复看“正在重连”有没有误报；R03.1、R05.1 测内存和耗电时把直播间长时间播放作为主场景，结果可能回到这里开任务。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [C 直播间](../README.md)。

- 代码：`features/live_play/live_play_page.dart`、`logic/`
- 进度：`█████████████████░░░` 83%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| C01.1 | 直播间（主要流程） | 功能 | 完成 | 2026-10-01 | 0249e830e | [设计或说明](C01.1-直播间主要流程/README.md)、[记录](C01.1-直播间主要流程/record.md) |
| C01.2 | 直播间（第二部分） | 功能 | 完成 | 2026-10-01 | 13bc7fac1 | [设计或说明](C01.2-直播间第二部分/README.md)、[记录](C01.2-直播间第二部分/record.md) |
| C01.3 | 直播间功能余项：功能清点里直播间部分的 6 项缺失、1 项有问题 | 功能 | 不做 | — | — | [设计或说明](C01.3-直播间功能余项/README.md) |
| C01.4 | 直播间清晰度显示平台实际给的档：确认的编号不在列表里时按平台编号命名（和录制一致） | 功能 | 待真机 | 2026-10-08 | — | [设计或说明](C01.4-直播间清晰度显示实际档/README.md)、[任务书](C01.4-直播间清晰度显示实际档/brief.md)、[记录](C01.4-直播间清晰度显示实际档/record.md) |
| C01.5 | 后台时未开播的房间开播后不自动出声，后台播放补出媒体通知 | 功能 | 待真机 | 2026-10-08 | f357fd38d | [设计或说明](C01.5-后台时未开播的房间开播后/README.md)、[任务书](C01.5-后台时未开播的房间开播后/brief.md)、[记录](C01.5-后台时未开播的房间开播后/record.md) |
| C01.6 | 主播换场后弹幕参数变了要重连；改“YouTube 显示全部聊天”立即生效 | 功能 | 未开始 | — | — | [设计或说明](C01.6-主播换场后弹幕参数变了要重连/README.md)、[任务书](C01.6-主播换场后弹幕参数变了要重连/brief.md) |

## 还没完成的

- **C01.6 主播换场后弹幕参数变了要重连；改“YouTube 显示全部聊天”立即生效**（未开始，第二档，规模 小）
  - 阶段：换场和弹幕结束后按进房详情取新参数重连 → YouTube 显示全部聊天改了就重连
  - 说明：和 E05.4 的“百度刷新带弹幕参数”、C01.5 改同一个文件（room_controller.dart），先后做
  - 来源：docs v2 D 组核对（D06 余项、D01.14、D01.16、D01.27）和 C、O 组核对

<!-- docs:生成结束 -->
