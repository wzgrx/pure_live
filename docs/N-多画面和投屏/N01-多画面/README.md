# N01 多画面

多画面布局、格子控制、会话。

一个页面同时看几个直播间：布局（1×1、1×2、2×2、一大多小）、往格子里选台、每格的播放会话、声音只出一路、每格音量 / 画质 / 线路、小格省流、看不见的格只留声音、页级弹幕（只连一路）、沉浸和全屏、安全退出、记住上次的画面。页面和格子的样子归 A13.2。

## 范围

- 包括：
  - `apps/pure_live/lib/features/multiview/logic/multiview_controller.dart`：`MultiviewLayout`、`CellStage`、`MultiviewCell`、`MultiviewController`（全部行为）。
  - `logic/multiview_geometry.dart` 的格数上限 `multiviewMaxCells` 和可见范围 `visibleRailRange`（格子位置的计算归 A13.2）；`logic/multiview_session.dart`（上次的画面存在 `meta` 的 `multiview.session`，也进完整备份）。
  - `multiview_page.dart` 里的逻辑：显示模式（正常、沉浸、全屏）和全屏时的系统栏和方向（`:402-403`）、安全退出（先撤视频、等两帧再出栈 `:424-428`）、格子里飞行弹幕的参数（`:868-884`：外观、暂停时的弹幕；帧率 N01.2）。
  - 多画面里要跟随的全局设置：弹幕的全部设置（同直播间）、首选清晰度、优先 H.264、房间音量 `roomVolumes`、“暂停时的弹幕”；以及没跟随的“弹幕帧率”（N01.2）、“屏幕常亮”。
- 不包括（归哪里）：
  - 页面、工具栏、格子上的按钮、选台面板、一大多小的排法 → [A13.2](../../A-界面设计/A13-网络电视和多画面界面/A13.2-多画面/README.md)（`widgets/`、`multiview_geometry.dart` 的 `WallGeometry`）。
  - 每格的 `PlaybackSession`（恢复、换线、软解、租期、帧看门狗、`setPresentationVisible`）→ G02；飞行弹幕层 `DanmakuOverlay` 怎么画 → D03；弹幕设置怎么算帧率 → D05（`resolvedDanmakuFps`）。
  - 全屏方向的原生部分（`ScreenOrientation.landscape`、按传感器翻转 D-023）→ O05；屏幕常亮的计数（`ScreenWake`）→ O05、G。
  - 首页“多画面”入口和导航设置的开关（`enableMultiView`）→ I01、J01。

## 现状：做到哪、怎么工作的

- 用户看得到的（首页 → 多画面）：默认 2×2（上次用过的布局会记住）；点空格弹出选台（关注、历史、搜索，开播优先、按人数排）；选进去的直播间开始播并成为声音来源，其他格静音；一大多小里点小格就晋升为大画面；格子的“更多”菜单：暂停 / 继续、播放这一格的声音、画质、线路、音量、刷新、进入直播间、换台、关闭；工具栏：布局、全部静音、小格省流（只在一大多小）、弹幕开关和弹幕设置；沉浸（只留格子）、全屏（手机隐藏系统栏并转横屏）；返回和 Esc 先回到正常；再次打开时问“上次看了 N 个直播间，要恢复吗？”。同一个直播间不会进两个格（提示“已在第 N 格播放”并切过去）。
- 内部怎么工作：

```text
MultiviewPage（multiview_page.dart）建 MultiviewController（logic/multiview_controller.dart:146）
  maxCells = multiviewMaxCells(mobile, processors)（geometry:10：手机 4；电脑 ≥8 核 9、6～7 核 6、其余 4）
  start（:270）：订阅屏蔽表和过滤设置（:274-290）→ _load（:309）读 multiview.session，恢复布局，记下可恢复的房间
选台 assign（:462）：总是先取详情（有 LiveSiteRecordRoomResolver 就用严格接口）→ 合并卡片 → 关注里有就更新快照
  → 不能播（:501，下播、封禁、轮播）→ CellStage.offline，可“重新检查”
  → 画质发现 → 首选清晰度（小格省流时最低档）→ resolvePlayUrls → PlaybackPlan(preferH264:, onDemand:) → session.open
  → 每次分配有序号，晚到的结果丢掉；成为声音来源（一大多小里往小格选台不抢声音，:534）
声音：_applyVolumes（:785）：出声的格 = 房间音量（_roomVolume :766，和直播间同一个 roomVolumes），其他 0；全部静音全 0；
  关掉出声的格，声音转到第一个在播的（_refocus :755）
画质 / 线路：selectQuality（:640，旧流继续播直到新流解析好，失败只提示）、selectLine（:659，会话管理）
省流：setSmallCellsLowQuality（:832）；promote（:436）时晋升的换回正常档、被换下来的换最低档
看不见的格：setOffscreen（:623）→ 只留声音、停帧看门狗（A13.2）
弹幕：setDanmakuEnabled（:849，默认关）→ _danmakuTarget（:861：选中的格、在播、平台支持弹幕、不是网络电视）
  → _syncDanmaku（:872，同一个房间不重连）→ DanmakuMessageFilter（屏蔽词、用户、去重、相似）→ flying / retractions → 格子里的 DanmakuOverlay
保存：_save（:344）布局、省流、弹幕开关、各格房间（只存身份和卡片字段）→ meta[multiview.session]
退出：_exitSafely（multiview_page.dart:424）先撤视频、等两帧再出栈（3.x 规避纹理注销的竞态）
```

- 完成度：N01.1（2026-10-01，`6ac31a036`）做完全部行为并修了 3.x 的 8 个问题；A13.2（`b601b444e`）按确认的设计重做界面，并加了“看不见的格只留声音”（会话的 `setAudioOnly` + `setPresentationVisible`）；A07.10 给格子里的弹幕接上“暂停时的弹幕”。清点：F-MV-01～04 “完成”，F-MV-05“部分”（帧率，N01.2），F-MV-06（4 路解码、沉浸、全屏、返回）“没验证”→ S02.6 第 2 阶段。

## 代码地图

| 文件 | 职责 |
|---|---|
| `apps/pure_live/lib/features/multiview/logic/multiview_controller.dart`（952 行） | `MultiviewLayout`（`:19`：容量、行列）、`CellStage`（`:48`：空、解析中、播放中、未开播、失败）、`UnsupportedPlatform`（`:66`）、`MultiviewCell`（`:78`：画质、切换中、音量、`assignable`、`offscreen`）、`MultiviewController`（`:146`）：`desktopMaxCells = 9`（`:169`）、`start`（`:270`）、`_load`（`:309`）、`_save`（`:344`）、`restoreLast`（`:373`）、`setLayout`（`:407`）、`addCell`（`:427`）、`promote`（`:436`）、`assign`（`:462`）、`_fail`（`:546`）、`_openQuality`（`:559`）、`setOffscreen`（`:623`）、`selectQuality`（`:640`）、`selectLine`（`:659`）、`togglePlay`（`:667`）、`retry`（`:676`）、`pauseAll`/`resumeCells`（`:695`、`:707`，进入直播间时）、`remove`（`:716`）、`_roomVolume`（`:766`）、`setAudioFocus`（`:793`）、`toggleMuteAll`（`:802`）、`setVolume`（`:812`）、`setSmallCellsLowQuality`（`:832`）、弹幕（`:850-905`） |
| `.../logic/multiview_geometry.dart`（160 行） | `multiviewMaxCells`（`:10`）、`visibleRailRange`（`:21`）；格子位置 `WallGeometry`（A13.2） |
| `.../logic/multiview_session.dart`（45 行） | `multiviewSessionKey = 'multiview.session'`（`:10`）、`readMultiviewSession`（`:13`）、`writeMultiviewSession`（`:25`）、`multiviewSessionOf`（`:31`） |
| `.../multiview_page.dart`（962 行） | `_DisplayMode`（`:58`）；建控制器（`:130`）；全屏的系统栏和方向（`:402-403`）、离开全屏恢复（`:164`）；`_exitSafely`（`:424`）；格子里的弹幕层（`:868-884`：`danmakuLookOf`、`danmakuPausedBehavior`，没有 `fps`） |
| `.../widgets/cell_view.dart`（514 行） | 格子：`LiveVideoView(session:, outputSize:)`（`:92`，**没传 `keepScreenOn`**，默认常亮）、弹幕层叠在上面、播放状态层 |
| `.../widgets/`（`cell_controls.dart`、`focus_bar.dart`、`room_picker.dart`、`toolbar.dart`、`wall.dart`） | 界面（A13.2） |
| `apps/pure_live/lib/shared/backup/backup_data.dart` | 完整备份里的 `multiview` 分区（`:35`、`:75`，J03） |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `apps/pure_live/test/features/multiview/multiview_controller_test.dart`（6） | 选台后播放、成为声音来源、其他格静音（`:18`）；未开播、失败、重试、关格（`:57`）；布局缩小释放、一大多小小格不抢声音、加格（`:93`）；弹幕跟着选中的格、过滤（`:139`）；保存和恢复（`:173`）；看不见的格不解码视频（`:196`） |
| `.../multiview_page_test.dart`（7） | 竖屏、横屏手机、宽屏的布局；暂停时的弹幕（`:296`）；点击区域 48；竖屏一大多小；未开播和失败的说明 |
| `.../multiview_geometry_test.dart`（4） | 格数按设备、可见范围、格子位置 |
| `.../multiview_support.dart` | 假平台、假会话、假弹幕 |

## 3.x 基线

- `git show v3.2.11:lib/modules/multiview/`（11 个文件 4321 行）：`multiview_controller.dart`（布局 `:49`、画质 `:414`、声音焦点 `:649`；选台时相信存的“未开播” `:712-715`；失败显示异常原文 `:739`、`:766`；换画质失败整格出错 `:856-864`）、`multiview_page.dart`（`:36` 起；弹幕配置 `:1296-1312`，帧率 `:1306-1308` 跟 `danmakuAutoFps` / `danmakuFps`；格子用 media_kit 的 `Video` `:994`，默认常亮）、`danmaku/multiview_danmaku_session.dart`（弹幕平台写死 8 个 `:54-67`）、`cells/`（每格自建播放器和帧看门狗）、`widgets/multiview_room_picker.dart`、`focus_rail_visibility.dart`、`multiview_fullscreen_surface.dart`。
- 必须保留：四种布局和一大多小加格的上限；只有一格出声；一大多小里往小格选台不抢声音；小格省流的规则；弹幕只连一路（一大多小是大画面，其他是出声的格）、用全局弹幕设置；安全退出的“先撤视频、等两帧”。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 飞行弹幕不跟“弹幕帧率”设置，每个刷新周期都画（3.x 跟） | `multiview_page.dart:877-882` 的 `DanmakuOverlay` 没传 `fps`、`refreshRate` | K90 上按 120 帧画，4 格时耗电；关了“跟随界面刷新率”选 30 帧也没用 | [N01.2](N01.2-多画面弹幕跟随帧率设置/README.md) |
| 飞行弹幕不传表情表 | 同上（没有 `emotes`） | 表情显示成文字（直播间显示图片） | N01.2 第 2 阶段（可选，2026-10-07 登记进登记表，做不做开工前由维护者定） |
| 六间房、AcFun、克拉克拉的格子没有弹幕：多画面用录制详情建格子（`logic/multiview_controller.dart:486-490`），这三家的录制详情不带弹幕参数，`:865` 就不连 | `packages/live_core/lib/src/sites/sixroom/sixroom_site.dart:416` 等 | 这几个平台在多画面里没有聊天（直播间里有） | [E05.4](../../E-直播平台/E05-平台框架和模型/E05.4-平台层小问题合集/README.md) 第 2 阶段（2026-10-07 登记：录制详情也带弹幕参数） |
| 不看“屏幕常亮”设置，播放时总是常亮 | `widgets/cell_view.dart:92`（`LiveVideoView` 的 `keepScreenOn` 默认 `true`） | 设置里关了常亮，多画面照样不灭屏；3.x 一样（media_kit `Video` 默认常亮，`multiview_page.dart:994`），O 组发现 | N01.2 第 2 阶段（可选，2026-10-07 登记；传 `keepScreenOn: watchSetting(Settings.enableScreenKeepOn)`）；O05 记为“等用户反馈” |
| 4 路解码、沉浸、全屏和返回没在 K90 上看过 | — | 不知道 4 路时的帧时间、发热、退出时的纹理释放 | [S02.6](../../S-质量和验证/S02-真机验证/S02.6-K90补验/README.md) 第 2 阶段（CHECKLIST 第 1 节第 16 条） |
| 网络电视频道在多画面里没有弹幕 | `multiview_controller.dart:866` | 网络电视本来就没有弹幕 | 照设计 |
| 进入直播间时先暂停所有格、回来再继续 | `:695-714` | 回来后要重新缓冲 | 照设计（避免两边同时解码） |

## 相关决定和规范

- D-023（多画面的全屏同样按传感器翻转）、D-018（`roomVolumes`、`enableMultiView` 键不变）、D-017（测试用假会话）。
- A13.2 的设计（W1～W4 按建议 A，D-003）；UI_PLAN 第 9.3 节“多画面的格数跟设备能力”（`multiview_geometry.dart` 的注释）。

## 测试和验证

- 自动测试：`cd apps/pure_live && flutter test test/features/multiview/`。缺：多画面的弹幕层拿到设置的帧率（N01.2 加）。
- 真机：CHECKLIST 第 1 节第 16 条（2×2 四路国内直播、点格子切声音、沉浸和全屏、返回）→ S02.6 第 2 阶段；性能用 profile 构建看 `dumpsys gfxinfo`。

## 路线

1. **N01.2**（第二档，小）：弹幕帧率；可选：表情表、屏幕常亮。
2. S02.6 第 2 阶段真机；结果写回 N01.1 的“验证”。
3. 以后：“按格子尺寸自动降清晰度”（A13.2 留下的想法）要先定阈值，进 V01 提议。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [N 多画面和投屏](../README.md)。

- 代码：`features/multiview/`
- 进度：`███████████████████░` 97%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| N01.1 | 多画面 | 功能 | 完成 | 2026-10-01 | 6ac31a036 | [设计或说明](N01.1-多画面/README.md)、[记录](N01.1-多画面/record.md) |
| N01.2 | 多画面的飞行弹幕跟随弹幕帧率设置（3.x 跟随，v4 每个刷新周期都画） | 功能 | 待真机 | 2026-10-08 | — | [设计或说明](N01.2-多画面弹幕跟随帧率设置/README.md)、[任务书](N01.2-多画面弹幕跟随帧率设置/brief.md)、[记录](N01.2-多画面弹幕跟随帧率设置/record.md) |

<!-- docs:生成结束 -->
