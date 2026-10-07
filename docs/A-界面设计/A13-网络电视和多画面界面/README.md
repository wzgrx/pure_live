# A13 网络电视和多画面界面

网络电视管理、多画面。

一句话：两块相对独立的界面：设置里的“IPTV 设置”页（播放列表和节目单的导入、同步、选择），以及多画面页（多个直播同时看，选中格的控制、选台、沉浸和全屏）。

## 范围

- 包括：
  - 网络电视管理（A13.1）：v3 的“IPTV 设置”和“订阅源管理”合成的一页：统计、播放列表组、节目单组、同步和播放组；导入方式、网络导入、粘贴文本、同名替换、删除、选节目单、同步间隔、请求头对话框；卡片的“更多”菜单。
  - 多画面（A13.2）：四种布局（单个、左右两格、2×2、1+3）、格子的编号和状态、选中格的控制（清晰度、线路、暂停、刷新、换台、关闭、房间音量）、选台、工具条（布局、弹幕、弹幕设置、全部静音、小格省流）、沉浸和全屏、格子面板、弹幕设置面板。
- 不包括（归哪里）：
  - 导入、解析 m3u、节目单、同步的逻辑在 [L01 网络电视](../../L-网络电视和点播/L01-网络电视/README.md)（`packages/live_iptv`）；网络电视频道在分区页里浏览属于 I03 / [A09](../A09-浏览界面/README.md)；直播间里的节目单和回看在 [A07.7](../A07-直播间界面/A07.7-直播间的状态/README.md) 和 [L02](../../L-网络电视和点播/L02-节目单和回看/README.md)。
  - 多画面的播放会话、格数、省流等逻辑在 [N01 多画面](../../N-多画面和投屏/N01-多画面/README.md)；直播间的清晰度、线路小菜单和弹幕设置面板是 A07.6 的组件，多画面直接用。
  - 电视上的网络电视页在 [A17.5](../A17-电视界面/A17.5-电视网络电视和影片/README.md)；pure_live_TV 没有多画面，电视不做。

## 现状：做到哪、怎么工作的

- **网络电视管理**：设置 →“IPTV 设置”（路由 `RoutePath.kIptv`）。一页从上到下：统计（播放列表、频道、节目单，20 号等宽数字）→ 播放列表组（导入行 + 卡片）→ 节目单组（导入行、“当前使用的节目单”+ 卡片）→ 同步和播放（启动时全自动同步、同步间隔、请求头）。卡片按网络在前、名字排序，“网络 / 本地”是灰标签；点卡片不打开地址，右上角“更多”或右键：在浏览器中打开 / 打开文件、复制地址；按钮同步、删除、自动同步（卡片宽 ≥520 一行）。标题栏“同步”同步全部网络来源，统计位置换成“正在同步网络来源 1 / 3”。一栏最宽 720 居中。数据来自 `IptvOverview.load`（`features/iptv/iptv_data.dart:35`），IPTV 表变化时自动刷新（`database.watch`）；导入走 `packages/live_iptv` 的 `IptvImporter`。
- **多画面**：首页菜单或宽屏导航栏进入。竖屏：格子按 16:9 在上（最多占页面一半），下面是选中格的控制和选台；宽 ≥840：右栏 360 同时放控制和选台；横屏手机（高 <480）：右栏宽 = 页面宽 − 画面区宽（256～360），平时放控制、点空格或“换台”换成选台，工具条并进顶栏，右栏能收起。点格子 = 选中并成为声音来源（附录 A 第 13 条）；1+3 点小格晋升大格；长按 / 右键普通模式下选中、沉浸和全屏下打开格子面板。每格只挂一次画面（`GlobalKey`），看不见的格（1+3 滚出视野、应用隐藏）关视频解码只留声音。格数：手机 4，电脑 8 核以上 9、6～7 核 6、更少 4（`multiviewMaxCells`，`features/multiview/logic/multiview_geometry.dart:10`）。
- **完成度**：两个任务都完成（2026-10-01 合并）；多画面的点击区域在收尾里补到 48（[A07.9 记录](../A07-直播间界面/A07.9-已合并界面任务的收尾/record.md)第 2 节）。3.x 的功能一项不少；确认过的改动见两个任务 README（H1～H4、W1～W4 按建议 A）。真机：两块都还没在 K90 上看（S02.3 写明“多画面、网络电视”没测）。

## 代码地图

| 文件 | 职责 |
|---|---|
| `apps/pure_live/lib/features/iptv/iptv_page.dart` | IPTV 设置页 `IptvPage`（:29）：四组的排法、全部同步、默认节目单只自动导入一次（`defaultGuideMetaKey` :42）、各状态 |
| `apps/pure_live/lib/features/iptv/iptv_cards.dart` | 卡片 `IptvSourceCard`（:24，一行按钮的分界 520 :17）、网络 / 本地标签 `IptvTag`（:291）、自动同步行、“更多”菜单行、统计 `IptvStats`（:427）、同步进度（:471）、状态卡（:514，读取失败、未启用、空、默认节目单导入中）、骨架（:622） |
| `apps/pure_live/lib/features/iptv/iptv_import.dart` | 导入方式对话框 `chooseImportOrigin`（:84）、文件选择（`iptvFilePickerProvider` :41，标题“选择播放列表文件 / 选择节目单文件” :48）、同名替换（:240）、网络导入（:273）、粘贴文本（:430） |
| `apps/pure_live/lib/features/iptv/iptv_settings.dart` | 同步间隔（2～72 小时，:7、:12）、请求头（最多 500 字，:29、:35） |
| `apps/pure_live/lib/features/iptv/iptv_data.dart` | 页面数据 `IptvOverview`（:35）、格式标记、名字、千分位、“今天 08:00 更新”（`updatedText` :127，时钟 `iptvClockProvider` :15 测试可固定） |
| `apps/pure_live/lib/features/multiview/multiview_page.dart` | 多画面页 `MultiviewPage`（:41）：显示模式（普通、沉浸、全屏 :58）、三种排法（竖屏、横屏手机、宽屏 :62）、浮层（:76）、右栏宽度（:92、:96）、收起把手（:908）、退出按钮（:939）、返回和 Esc 链 |
| `apps/pure_live/lib/features/multiview/logic/multiview_controller.dart` | 四种布局 `MultiviewLayout`（:19）、格子阶段（:48）、格子 `MultiviewCell`（:78）、控制器（:146：选台、声音来源、省流、暂停、房间音量、`setOffscreen` 停解码） |
| `apps/pure_live/lib/features/multiview/logic/multiview_geometry.dart`、`multiview_session.dart` | 格数（:10）、可见范围（1+3 那一列）、格子位置 `WallGeometry`（:43，16:9）；上次的画面（`multiview.session`） |
| `apps/pure_live/lib/features/multiview/widgets/wall.dart`、`cell_view.dart` | 画面区 `MultiviewWall`（:16）；一格 `MultiviewCellView`（:15：编号、声音来源描边和角标、省流标、暂停压暗、空格 `AddCellSlot` :473、选台目标虚线框 :445、出错和未开播 :246） |
| `apps/pure_live/lib/features/multiview/widgets/cell_controls.dart` | 选中格的控制 `MultiviewCellControls`（:46）：房间行和两个小菜单按钮、五个按钮（圆 40、点击区域 48）、房间音量（窄于 384 时换到下一行） |
| `apps/pure_live/lib/features/multiview/widgets/toolbar.dart`、`focus_bar.dart` | 工具条：布局分段（:10）、开关（:75、:146，圆 38、点击区域 48）；1+3 大格在沉浸 / 全屏时的控制条 `FocusControlBar`（:15） |
| `apps/pure_live/lib/features/multiview/widgets/room_picker.dart` | 选台 `MultiviewRoomPicker`（:128）：关注 / 历史等来源、“第 N 格”排最后（:21、:40）、标题（:70） |
| `apps/pure_live/lib/shared/panels/side_panel.dart` | 直播间和多画面共用的面板 `RoomSidePanel`（:24，横屏宽屏右侧 360）、面板里的跳转行 |
| `apps/pure_live/lib/shared/danmaku/danmaku_settings_content.dart` | 弹幕设置内容（直播间、多画面、设置的弹幕页共用） |
| `packages/live_ui/lib/src/widgets/stream_menu_button.dart` | 清晰度、线路的小菜单按钮（从直播间移来） |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `apps/pure_live/test/features/iptv/iptv_page_test.dart` | 一页的顺序和图标、竖屏卡片两行 / 宽屏一行、340 宽 1.3 倍字号不溢出、骨架、读取失败、两组空状态、未启用、全部同步进度、默认节目单只下载一次；各对话框；单个同步、删除、改用下一个节目单；“更多”菜单和右键 |
| `apps/pure_live/test/iptv_store_test.dart` | IPTV 数据的读写 |
| `apps/pure_live/test/features/multiview/multiview_page_test.dart` | 竖屏、竖屏 1+3、横屏手机、宽屏四种排法的布局和操作，格子状态，Esc 链，点击区域 48（393、360、740×360、1280×800） |
| `apps/pure_live/test/features/multiview/multiview_geometry_test.dart`、`multiview_controller_test.dart` | 格数按设备、可见范围、格子位置 16:9；看不见的格只有声音、回来恢复 |

## 3.x 基线

- 网络电视：`git show v3.2.11:lib/modules/iptv/iptv_page.dart`（943 行，“IPTV 设置”：导入方式、网络导入、间隔、请求头、选 EPG）、`lib/modules/iptv/iptv_manage.dart`（902 行，“订阅源管理”：卡片、统计、删除）；同名对话框和文件选择在 `lib/core/iptv/services/iptv_import_manager.dart`、`epg_import_manager.dart`；设置页写法 `lib/common/widgets/widget_extensions.dart:21-258`；设置总览的入口 `lib/modules/settings/settings_page.dart:66-74`。
- 多画面：`lib/modules/multiview/multiview_page.dart`（1390 行：显示模式、顶栏、工具条、格子区、1+3、大画面控制条、底部面板）、`multiview_controller.dart`（1424 行）、`widgets/multiview_room_picker.dart`、`widgets/multiview_fullscreen_surface.dart`、`widgets/focus_rail_visibility.dart`。
- 必须保留（[specs/UI.md](../../specs/UI.md) 附录 A 第 13 条）：点格子切换声音焦点；一大多小中点小格晋升；长按或右键打开格子菜单（现在是选中 / 格子面板）；点空格选直播间。返回和 Esc 先退沉浸、全屏（第 7 条）。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 多画面、网络电视管理都没在真机上看过 | A13.1、A13.2 | 4 路同时播放的流畅度、导入真实 m3u 只在测试里模拟 | [S03.1](../../S-质量和验证/S03-统一验证/README.md)；CHECKLIST 第 1 节第 16、17 条 |
| “小格自动降画质”按 3.x 的“小格省流”（手动开关）做，没有按格子尺寸自动选低清晰度 | `multiview_controller.dart` | 不开省流时小格仍拉高清晰度 | A13.2 记录“需要决定的事”第 1 条，没有登记任务；要做时走 V01 提议 |
| 标题居中由 IPTV 页自己设（`centerTitle: true`），全局主题没有这一项 | `iptv_page.dart` | 和 D-011（只有部分页面居中）一致，不用改 | 不改（D-011 已定） |
| 默认节目单导入失败的状态设计没画，沿用 v4 的读取失败卡 | `iptv_cards.dart` 的 `IptvStateCard` | 文字和按钮是开发时定的 | 真机看时一并确认 |

## 相关决定和规范

- D-003（H1～H4、W1～W4 按建议 A）、D-011（标题位置：IPTV 设置页居中照 3.x）、D-017（测试里的“现在”固定：`iptvClockProvider`）、D-018（`isAutoSyncEnabled`、`autoSyncHoursInterval`、`customIptvUserAgent`、`roomVolumes`、`multiview.session` 等键不变）。
- [specs/UI.md](../../specs/UI.md) 第 5.3 节（多画面按父组件宽高排、宽屏右栏 360）、第 5.4 节（点击区域 48）、第 7 节（弹幕设置、格子面板是面板；IPTV 的对话框照 3.x）、第 9.3 节（多格的播放器：格数按设备、看不见的格停解码）。

## 测试和验证

- 自动测试：`cd apps/pure_live && flutter test test/features/iptv test/iptv_store_test.dart test/features/multiview`。缺：多画面真实解码的帧时间（只在测试里用假会话）。
- 真机：[S02 的 CHECKLIST](../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 1 节第 16 条（多画面 2×2 放 4 个国内直播）、第 17 条（网络电视导入 m3u、播放、节目单和回看）、第 4 节第 11 条（分享 m3u 文件导入）。都还没做。

## 路线

1. [S03.1](../../S-质量和验证/S03-统一验证/README.md) 里补多画面和网络电视管理的真机（第二档）。
2. 电视的网络电视页 [A17.5](../A17-电视界面/A17.5-电视网络电视和影片/README.md) 开发时复用这里的数据层（`IptvOverview`、导入对话框的逻辑），界面换电视样式。
3. 多画面的新需求（自动降清晰度、更多布局）先进 [V01](../../V-需求和反馈/V01-新功能提议/README.md)。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [A 界面设计](../README.md)。

- 代码：`features/iptv/`、`multiview/`
- 进度：`████████████████████` 100%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| A13.1 | 网络电视管理 | 界面 | 完成 | 2026-10-01 | 7c6d685cb | [设计或说明](A13.1-网络电视管理/README.md)、[记录](A13.1-网络电视管理/record.md)、[评审页](A13.1-网络电视管理/page/01-说明.jpg) |
| A13.2 | 多画面 | 界面 | 完成 | 2026-10-01 | b601b444e | [设计或说明](A13.2-多画面/README.md)、[记录](A13.2-多画面/record.md)、[评审页](A13.2-多画面/page/01-说明.jpg) |

<!-- docs:生成结束 -->
