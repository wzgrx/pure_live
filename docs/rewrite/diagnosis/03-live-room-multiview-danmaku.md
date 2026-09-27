# 第 0 阶段诊断：直播间、多画面、弹幕

诊断基于 master@49ceccb0。这个提交与 9bbaf11b 相比，lib 和 plugins 没有差异。全程只读，没有改动仓库。

## ① 规模与结构

| 模块 | 文件 / 行数 | 最大文件 | 职责 |
|---|---|---|---|
| live_play | 67 / 18,475 | video_controller_panel.dart 2213、video_controller.dart 1569、live_play_controller.dart 1178、player_controller.dart 908 | 页面、控制层、弹幕列表与设置、画质线路、IPTV、DLNA、定时、本地互动 |
| multiview | 11 / 4,321 | multiview_controller.dart 1424、multiview_page.dart 1390 | 布局、每格独立 media_kit、卡顿恢复、大画面弹幕 |
| core/danmaku | 13 / 11,563（其中抖音 protobuf 生成代码 8,809 行） | bilibili 544、huya 474 | 各平台弹幕协议 |
| flame_barrage（本地副本 0.0.4 加补丁） | 59 / 3,353 | barrage_engine.dart 642 | 画面上的弹幕渲染 |
| 小窗 / 画中画界面 | 写在 player_manager.dart 的 2808–3480 行 | — | 系统 PiP、Windows 小窗、应用内浮窗、纯音频界面 |
| 测试 | 92 个文件、2.68 万行引用上述模块 | — | 其中 36 个直接依赖 GetX |

| 状态 | 位置 | 问题 |
|---|---|---|
| 房间、播放、界面合成一个 `Rx<LivePlayState>` | live_play_controller.dart:63；states/*.dart | 整页 Obx 订阅这一个状态（live_play_page.dart:14-18），观众数更新（:541-566）也会让整页重建 |
| 弹幕历史、SC、礼物特效 | RxList，:64、:68-69 | 每 64 ms 把最多 500 条整表复制一次，再 assignAll（:515-525） |
| 控制层显隐、锁定、菜单，以及 12 项弹幕样式 | VideoController 里 30 多个 Rx，video_controller.dart:365-405 | 弹幕样式是 SettingsService 的镜像，靠 worker 双向同步（:71-130） |
| 全屏 / 宽屏 | 全局 GlobalPlayerState 和 UIState.screenMode 各一份 | 两份真相，需要手动同步（live_play_controller.dart:394-420） |
| 内核、PiP、浮窗 | PlayerManager 单例的 Rx，player_manager.dart:399-415 | — |
| 多画面 | `cells` 加 9 个按下标平行的数组，multiview_controller.dart:300-362 | 改布局和加格子时必须逐个同步增删（:552-611） |

范围内共有 Rx 104 处、Obx 68 处、Worker 15 个、setState 65 处。

### ①.2 现有操作逻辑清单

| 操作 | 行为 | 位置 |
|---|---|---|
| 单击（手机） | 控制层可见且正在播放时隐藏控制层；否则显示控制层，暂停中则同时继续播放；命中弹幕时打开弹幕操作；控制条高度内的点击不做弹幕命中 | video_controller_panel.dart:201-232、74-83 |
| 单击（桌面） | 只显示控制层；暂停中则继续播放 | 同上 |
| 双击 | 宽屏时退出宽屏；竖屏源（Android、开启竖屏适配）进入或退出竖屏全屏；其余情况切换普通全屏；锁定时无效 | :246-252；video_controller.dart:1355-1372 |
| 长按 | 只有命中弹幕时才有反应：打开复制 / 屏蔽菜单，同时暂停弹幕层 | :234-245；video_controller.dart:132-149 |
| 上下滑 | 左半边亮度（仅手机），右半边音量；锁定时无效 | :851-903 |
| 竖屏全屏底部 96dp 内上滑 | 退出竖屏全屏 | :904-930；portrait_fullscreen_interaction.dart:7、39 |
| 竖屏房间面板把手 | 三档拖动；拖过最低档或点把手进入竖屏全屏；另有“横屏全屏”悬浮按钮 | live_play_content.dart:162-253、390-431 |
| 双指缩放 | 无 | — |
| 画面比例 | 文字按钮循环切换 | panel:2068-2117 |
| 锁定 | 全屏右侧锁按钮；锁定后隐藏控制条，禁用滑动和双击 | :1009-1046 |
| 控制层自动隐藏 | 4 秒；鼠标悬停在控制条上或菜单打开时不隐藏；隐藏时同时隐藏指针 | video_controller.dart:319-323、864-944 |
| 鼠标滚轮 | 与上下滑相同；Windows 上左半边无效 | panel:951-956、862 |
| 右键 | 直播间没有；多画面中等于格子操作菜单 | multiview_page.dart:984 |
| 键盘（直播间） | Esc 依次退全屏、退宽屏、返回；Space 和媒体键播放暂停；R 刷新；↑↓ 音量 ±5% | video_keyboard.dart:53-84、92-101 |
| 键盘（多画面） | 只有 Esc：退出沉浸或全屏 | multiview_page.dart:162-168 |
| TV 方向键 | 没有焦点模型；Manifest 声明了 LEANBACK_LAUNCHER；↑↓ 被音量快捷键占用 | AndroidManifest.xml:63、132 |
| 返回键 | 有弹窗先关弹窗；全屏或宽屏先恢复普通；普通状态出栈，“浮窗播放”开启且有画面时转为应用内浮窗 | live_play_back_scope.dart:171-193；navigation_observer.dart:50-58 |
| 默认全屏 | 设置开启时，进房 1 秒后自动全屏 | video_controller.dart:626-643 |
| 全屏方向 | 跟随源、跟随系统、强制横屏三种；竖屏房间可一次性强制横屏，退出时恢复竖屏 | :1374-1494 |
| 宽屏（桌面） | 隐藏右侧弹幕栏 | :1496-1516 |
| 画中画 | Android 进入系统 PiP；Windows 把主窗口缩成小窗，可拖动，双击退出 | player_manager.dart:2808-2900、3219-3290 |
| 应用内浮窗 | 离开房间时自动出现；手机上第一次点显示控件，再点回到房间；有关闭按钮；有弹窗时整体隐藏 | player_manager.dart:2973-3120 |
| 画质 / 线路 | 普通模式是两个下拉菜单；全屏是合并面板；切换不重建控制器，以最后一次请求为准 | resolution_selector/*；panel:1048-1390；player_controller.dart:686-847 |
| 弹幕设置入口 | 控制条的开关和设置对话框、普通布局的“弹幕设置”“屏蔽”两个标签页、全局设置里的 PiP 弹幕设置，共多处入口 | panel:1797-1880；danmaku_tab.dart:27-41 |
| ⋮ 菜单 | 打开原站、切换直播间、投屏、定时关闭、房间音量、直链、分享、本地互动、新窗口打开（仅 Windows） | live_play_menu_button.dart:189-206 |
| 全屏顶栏 | 返回、时间电量、切换直播间、纯音频、投屏、PiP | panel:35-66 |
| 多画面 | 四宫格等布局中点格子 = 切换声音焦点；一大多小中点小格 = 晋升为大画面，点大格 = 显示或隐藏控制条；长按或右键 = 换房、选清晰度、关闭；点空格 = 选台；工具条有布局、弹幕、全部静音、音量、小格降质 | multiview_page.dart:903-927、436-560 |

### ①.3 尺寸适配

| 断点 | 用途 | 位置 |
|---|---|---|
| 宽 680 | 直播间竖排或分栏、弹幕列表贴边、多画面侧板、首页 | live_play_content.dart:21、560；danmaku_list_view.dart:32；multiview_page.dart:45 |
| 宽 600 | 紧凑标题栏 | live_play_content.dart:549 |
| 宽 760 | 全屏底栏精简 | panel:1439 |
| 720×520 | 全屏面板紧凑 | content_first_panel_layout.dart:25 |
| 高 620 | 横屏设置面板紧凑 | panel:2131 |

问题：断点散落在 600、680、720、760 几处，和 PLAN 的等级对不上。多画面的侧板还要求设备是桌面（multiview_page.dart:379），Android 平板永远看不到侧板。分栏的侧栏固定为 34%，夹在 300–400dp，没有剧场模式。TV（960dp）只会落到桌面分栏布局，也没有焦点模型。多处读整屏尺寸（`Get.width`、`MediaQuery.sizeOf`），不是父组件约束。普通和全屏是两棵不同的界面树，靠 `videoKey` 保住视频纹理（live_play_content.dart:488-541）。

### ①.4 弹幕

| 环节 | 现状 | 位置 |
|---|---|---|
| 解码 | 全部在 UI isolate 上，WebSocket 回调里同步解码：B 站 zlib/brotli 加 JSON、抖音 gzip 加 protobuf、虎牙 TARS、斗鱼 STT；快手是 HTTP 轮询。全局搜索没有任何 Isolate 用法 | web_socket_util.dart:214、264；bilibili:260-366；douyin:201-211；huya:171-192；douyu:115-150 |
| 消息模型 | LiveMessage{type: chat/gift/online/superChat, userName, userId, message, color, messageId, sentAt, isLocal, style, data: dynamic} | live_message.dart:1-120 |
| 过滤（按执行顺序） | ① 去重闸门：超过 45 秒的丢弃；有平台 ID 的 10 分钟内去重，无 ID 的按文本 2.5 秒去重 ② 屏蔽用户和关键词 ③ 重复合并（可选，窗口 1–30 秒） ④ 相似度过滤（fuzzywuzzy，每条最多比较 96 次） ⑤ 斗鱼疑似机器人（协议层过滤，默认关闭） | danmaku_message_gate.dart:24-52；danmaku_controller.dart:191-222；danmaku_similarity_filter.dart:96-112；douyu_danmaku.dart:128-129 |
| 渲染 | flame_barrage：FlameGame，每条 Paragraph 转成 Picture 缓存；每个 VideoController 有两个引擎（画面一个、PiP 一个），多画面再另有一个 | video_controller.dart:481-482 |
| 本地补丁 | 没有弹幕时停止 ticker；按配置帧率由 vsync 驱动；修复弹幕区域百分比被重复应用；ExcludeFocus；dispose 时立即释放 Picture | barrage_engine.dart:26-31、125-185、72-85；flame_barrage_widget.dart:81-100 |
| 密度上限 | 每 50 ms 发一条；同屏最多 48 条；待发队列 120 条，超出丢最旧；待发超过 5 秒丢弃 | video_controller.dart:955-975；barrage_engine.dart:321-338、407-415 |

### ①.5 多画面

| 项 | 现状 | 位置 |
|---|---|---|
| 布局 | 单画面、双画面、四宫格、一大多小（手机最多 4 格，桌面最多 9 格） | multiview_models.dart:15-45；controller:73、84 |
| 渲染尺寸 | 创建播放器时按屏幕物理像素除以行列数；Windows 挂载后再按实际格子尺寸重设；Android 忽略宽高设置，按原分辨率解码 | controller:1391-1398；page:1002-1011；cell_player:207-217 |
| 自动降质 | 只在一大多小布局生效，由手动开关控制，默认关闭 | controller:414、493-504、641-665 |
| 不可见时暂停 | 没有。小格滚出视口、应用进入后台都继续解码；后台继续播放是否是有意为之 [待确认] | page:999 |
| 卡顿恢复 | 每格 10 秒画面看门狗（只在 Windows 上运行）加上源结束检测；每格 3 分钟内最多恢复 2 次；恢复时先还原画质再还原线路；用户手动操作会让进行中的恢复作废；暂停的格子不恢复 | controller:92-98、1172-1285 |
| 租期续流 | `MultiviewSourceLease{refreshAt, renew}`：按同一线路、同一画质重新解析，交给每格的 FlvSpliceRelay 无缝拼接 | controller:219-265、944-947；提交 31982153 |
| 弹幕 | 页级开关，只显示在大画面或声音焦点格上；过滤链是 live_play 那套的复制品 | controller:506-550；multiview_danmaku_session.dart:194-226 |

## ② 依赖与耦合

| 耦合点 | 位置 |
|---|---|
| LivePlayController、PlayerController、VideoController 三者互相调用成环；放在 widgets 目录下的 VideoController 反过来调用 `setFullScreen`、`onInitPlayerState` | video_controller.dart:637-643、1269-1283；player_controller.dart:188-193 |
| 播放单例负责构建界面：控制层通过 `controls:` 注入；PiP、浮窗、纯音频界面都写在 PlayerManager 里 | video_player.dart:179-188；player_manager.dart:2973-3292、3479 |
| 界面直接读全局对象：SettingsService 92 行、GlobalPlayer* 79 行、Get.* 23 行 | 分布在范围内各文件 |
| 按设备平台分支而不是按尺寸分级：48 行 | 例如 panel:862 |
| 弹幕协议文件依赖 Flutter 或应用层 | kuaishou:6、bilibili:8、huya:4、twitch:77；douyu_site.dart:71 |
| 控制器生命周期靠 GetX tag 管理 | live_play_controller.dart:222-230、1140-1146 |

## ③ 技术债（按风险×收益排序）

1. **弹幕解码和过滤全在 UI isolate 上。** 热门房间有掉帧风险（见 ①.4）。
2. **三个控制器成环，加上播放单例构建界面。** 界面重做必然会改动 5028 行的核心。
3. **全屏状态有两份真相。** 多画面还会写全局全屏标志来控制桌面标题栏（multiview_page.dart:185）。
4. **整页订阅一个大状态，历史列表整表复制。** 见 ① 状态表。
5. **多画面缺少资源调度。** 没有不可见暂停；Android 按原分辨率解码；降质默认关闭；卡顿检测只在 Windows 上工作。每格状态分散在 10 个平行数组里。
6. **两份过滤链已经不一致，多画面有真实缺陷。** 多画面只把消息转小写，不转屏蔽词（multiview_danmaku_session.dart:199-201），而屏蔽词按原大小写保存（favorite_room_controller.dart:446-453）。结果是含大写字母的屏蔽词和屏蔽用户在多画面里不生效。
7. **弹幕配置有两条下发路径，字段不一致。** DanmakuViewer（panel:771-813）和 updateDanmaku（video_controller.dart:946-978）各发一份，后者缺少字体和竖屏区域限制 [是否有可见错误待确认]。
8. **断点和平台判断散落各处，TV 没有焦点模型。**

## ④ 处置建议

| 对象 | 处置 |
|---|---|
| 弹幕协议、三个过滤器 | 在 live_danmaku 里重写，运行在 isolate；把现有 *_protocol_test 转成样本 |
| flame_barrage | 弃用，改为画布直绘；把补丁行为写进规格 |
| 直播间几个控制器、VideoController、控制层面板 | 丢弃重写；保留几个纯判定函数作参考：shouldHandleVideoSurfaceTap、resolveEscapePresentationAction、portraitPanelRange、canEnterPortraitPanelFullscreen |
| PlayerManager 里的界面代码 | 移到 live_ui，PlayerManager 只暴露状态流 |
| 多画面 | 沿用恢复、租期、纪元（epoch 防过期结果）的算法，按每格一个会话对象重写 |
| 本地互动（虚拟金币等，约 1780 行） | 是否保留需要产品决定 [待确认] |
| 测试 | 只提取断言语义到 spec/regressions.md |

## ⑤ 必须继承的行为与坑

| # | 现象 | 根因 | 正确做法 | 提交 / 测试 |
|---|---|---|---|---|
| 1 | 浮窗下面弹出的菜单点不动 | 浮窗是 Overlay 条目，之后打开的弹窗在它下层；flutter_floating 自带不透明的拖动手势，加 IgnorePointer 也拦不住 | 有弹窗打开时把整个浮窗 Offstage，弹窗关闭后恢复 | 44e3cb1b、c766d319；popup_route_tracker_test:66 |
| 2 | 竖屏源双击进了横屏式全屏 | 双击没区分竖屏源 | 双击统一走 toggleFullScreenFromGesture | 6d6b97ee（没有自动化测试，v4 需要补） |
| 3 | 手机单击无法收起控制栏 | — | 可见且正在播放时单击隐藏；暂停时单击显示并继续播放；桌面单击只显示 | 6d6b97ee；panel:216-231 |
| 4 | 点控制条上的按钮却弹出弹幕菜单 | 全屏手势层仍会收到点击 | 控制条高度范围内不做弹幕命中 | bab0af08；live_play_navigation_ui_test:72-98 |
| 5 | 多画面卡顿恢复后丢了手动选的线路 | 重新解析后按默认线路开流 | 按 selectionId 还原画质，再还原线路；手动操作让恢复作废 | 4fe4f7b7；multiview_test:1472、1507 |
| 6 | 斗鱼格子每 5 分钟冻结 | CDN 在 300 秒断开，播放器进入 completed 而不是卡顿，看门狗不触发；恢复次数一辈子只有 2 次 | 订阅 completed 事件触发重载；恢复次数改为 3 分钟内 2 次 | bf570796；multiview_test:1540、1560 |
| 7 | 源结束被误当成用户暂停 | media_kit 先发 playing=false 再发 completed | 单独记录用户的播放意图 | 42cbded2；controller:355 |
| 8 | 退出多画面时崩溃 | 返回动画期间，外部纹理注销和合成冲突 | 先卸载所有 Video，等两帧，再出栈 | 6ec8713d；page:145-160 |
| 9 | 被其他页面覆盖后视频黑屏或崩溃 | Android 和 Windows 的纹理生命周期不同 | Android 保持挂载、只 Offstage；Windows 卸载，等覆盖页完全返回后再挂载 | 1e609cb0；video_player.dart:166-234 |
| 10 | Esc 失效 | Flame 的 GameWidget 自动抢焦点 | ExcludeFocus 并关闭 autofocus | 1c22bffe；danmaku_keyboard_focus_test:68 |
| 11 | 返回键层级错乱 | Android 原生返回回调注册晚 | 在整个路由生命周期注册；弹窗先关，全屏先退 | c00b2069、81433454；live_play_back_scope_test:56、81 |
| 12 | 加载失败的房间留下黑色浮窗 | 离开房间时一律转浮窗 | 只有在有画面且没有加载错误时才浮窗 | 928ea47d；live_play_placeholder_test:15-17 |
| 13 | 浮窗相关资源释放过早 | 旧页面的返回动画还在订阅状态 | 等页面卸载后再释放（最多等 50 ms） | 5d4778f3；live_play_controller.dart:1081-1085 |
| 14 | 切到纯音频后一直显示加载 | copyWith 的可空参数分不清“没传”和“清空”，把播放器清掉了 | 用显式的 clear 标志 | player_state.dart:108-111 |
| 15 | 快速切房时弹幕串到新房间 | 旧连接的回调没有会话令牌 | 串行化加令牌加房间 key | danmaku_controller.dart:13-18、248-250 |
| 16 | 从 PiP 返回后弹幕列表停住 | PiP 期间列表被移出界面树，收不到状态恢复 | 由房间级控制器发布恢复通知，并补刷积压的批次 | live_play_controller.dart:195-220；danmaku_presentation_recovery_test |
| 17 | 进入 Android PiP 时闪出图标或黑块 | 系统在动画开始时截图 | 先渲染一帧紧凑画面再进入 PiP | player_manager.dart:2836-2841 |
| 18 | 进房时覆盖了设备音量 | 回放了房间保存的音量 | 手机音量属于设备，只读不写；全局静音例外 | 789f03cc |
| 19 | 强制横屏全屏退出后不回竖屏 | — | 一次性记录恢复竖屏的意图 | 039f8ff3；fullscreen_orientation_restore_test |
| 20 | 斗鱼弹幕需要默认完整 | 上游重构丢了机器人过滤开关 | 疑似机器人过滤默认关闭；那次重构已回滚 | 31ee5cd7、4cbb43ba；douyu_danmaku_protocol_test |

## ⑥ 对 v4 重新设计的具体建议

**直播间**
- 展示状态只用一个枚举：内嵌、剧场、全屏、竖屏全屏、画中画、小窗。系统栏和屏幕方向由副作用层订阅这个枚举。
- 控制层显隐单独管理，观众数等高频字段单独一个 provider，避免整页重建。
- 视频表面在所有模式下只挂载一个，靠移动而不是建两棵树。
- 手势按 PLAN §07 实现，保留 ⑤ 第 2、3、4 条的行为。长按时命中弹幕优先，否则打开快捷面板。双指缩放替代现在的画面比例按钮。
- 滚轮在整个画面上调音量，并补上右键菜单和 PLAN 里的快捷键。TV 模式下方向键不绑定音量。

**多画面**
- 每格一个会话对象，替代 10 个平行数组。
- 调度器负责：按显示尺寸降低解码尺寸（Android 上的实现手段 [待确认]）、小格自动降档、不可见或后台时暂停、跨平台卡顿检测。
- 侧板改由尺寸等级决定，不再要求是桌面设备。

**弹幕**
- isolate 里完成连接、解码、过滤和抽样，按 16–64 ms 批量发到主线程；先去掉协议文件对 Flutter 的依赖。
- 过滤链只保留一份，统一大小写处理；相似度算法换成代价更低的实现。
- 渲染用 CustomPainter 加空闲时停止的 Ticker，滚动和固定弹幕分层，缓存排版结果；以现有上限（50 ms、48 条、120 条、5 秒）作为初始预算。
- 历史列表改为环形缓冲、增量通知。

**尺寸**
- 按 WindowClass 设计布局：紧凑沿用竖屏三档面板，展开用右侧栏，大和超大用剧场模式加可拖宽的侧栏。TV 使用独立的焦点模型。
