# 产品功能清单（v4）

- 状态：第 1 阶段规格，2026-09-27
- 依据：master@9bbaf11b（v3.2.11；第 0 阶段诊断确认当前工作树的 `lib/` 与之相同）。行号已对照当前工作树核对；提交哈希来自第 0 阶段诊断
- 本文件列出旧版全部用户可见功能，给出优先级和 v4 处置。界面会整体重新设计，**功能对齐，外观不沿用**。行为细节见 `spec/modules/*`
- 只写行为和契约，不写类名和代码拆分

## 0 约定

**优先级**（按任务给定规则）

| 级别 | 范围 |
|---|---|
| P0 | 播放（含全屏、手势、返回等直播间基本操作）、关注（含分组/标签）、搜索（含链接解析）、弹幕（显示、列表、设置、屏蔽）、画质线路切换 |
| P1 | 多画面、录制 |
| P2 | 其余全部 |

“发现（热门/分区）”按规则是 P2，但它是一级入口，第 6 阶段搭界面骨架时必须占位。

**v4 处置**

| 处置 | 含义 |
|---|---|
| 保留 | 功能和行为沿用，界面按新设计重做 |
| 重新设计 | 功能目标保留，交互、结构或入口改变（写明改什么） |
| 合并 | 并入另一功能或入口 |
| 删除 | 不再提供，必须写理由；涉及用户数据的，数据仍按存储规格（`spec/modules/store.md`）迁移或导出 |

**标记**：【旧版未上线】= 旧代码里只有数据结构或接口、没有界面入口，不属于对齐验收范围；[待确认] = 需要查证后再定。

## 1 信息架构对照

| 旧入口 | 旧位置 | v4 位置（PLAN §07） |
|---|---|---|
| 首页标签：关注 / 热门 / 分区 / 录制（可排序、可隐藏） | `lib/modules/home/mobile_view.dart:23-61`、`tablet_view.dart:52-79` | 一级入口固定为 关注 / 发现 / 搜索 / 我的 |
| 顶栏“更多”：搜索、打开链接、多画面 | `lib/common/widgets/common_appbar_actions.dart:13-67` | 搜索（链接并入）；多画面放到“我的”和关注页 |
| 菜单按钮：设置、关于、历史、备份 | `lib/common/widgets/menu_button.dart:11` | 我的 |
| 设置 14 个子页 | `lib/modules/settings/settings_page.dart:62-176` | 我的 › 设置：播放 / 弹幕 / 网络 / 外观 / 数据 / 关于 |
| 录制标签（宽度 > 680 时改为顶栏按钮） | `lib/modules/home/home_page.dart:118,232`；`tablet_view.dart:143` | 我的 › 录制中心；直播间录制按钮不变 |

## 2 应用骨架与入口

| 编号 | 功能与旧版行为 | 优先级 | v4 处置 | 旧代码入口 |
|---|---|---|---|---|
| F-APP-01 | 启动页：固定显示 1 秒，再最多等 350 ms 关注校验；可在设置关闭 | P2 | **删除**：改用系统启动页 API，冷启动不额外等待（PLAN §09、§10） | `lib/routes/app_pages.dart:189-235`；`lib/modules/splash/splash_screen.dart` |
| F-APP-02 | 首页导航：手机底部栏，宽度 > 680 侧边导航；标签可在“导航显示设置”排序和隐藏（至少留一个） | P0 | **重新设计**：按窗口等级切换底部栏 / 导航轨 / 侧边栏；一级入口固定 4 个，删除自定义排序（入口从 4 个可变变为 4 个固定，录制移到“我的”后已无隐藏需求） | `lib/modules/home/home_page.dart:113-235`；`lib/modules/settings/pages/navigation_settings_page.dart` |
| F-APP-03 | 回到前台时，如果离开 ≥ 15 秒，450 ms 后刷新当前首页标签 | P2 | 保留：关注由关注刷新负责（“回到应用时刷新关注”开启、距上次刷新 ≥ 15 秒时，450 ms 后刷新，不论当前是哪个标签，开播提醒也靠它）；当前标签是发现时，刷新正在看的推荐或分区列表（2026-09-28） | `lib/modules/home/home_page.dart:141-160` |
| F-APP-04 | 冷启动带房间参数（Windows `--open-room=`）时首帧后直接进房 | P2 | 保留：并入统一的深链路由 | `lib/modules/home/home_page.dart:83-93`；`lib/common/utils/windows_multi_instance_launcher.dart:19-66` |
| F-APP-05 | Android Manifest 声明 `purelive://`、`mystyle://`、m3u 的 VIEW 过滤器，但 Dart 侧没有处理代码（点击无效果） | P2 | **重新设计**：实现 `purelive://` 房间深链和 m3u/EPG 文件打开，统一走路由重定向；`mystyle://` **删除**（上游遗留，从未生效，无用户行为可对齐） | `android/app/src/main/AndroidManifest.xml:66-76` |
| F-APP-06 | 界面语言：简体中文、English（英文不完整）；语言存了两份（Hive 与 SharedPreferences） | P2 | 保留并扩展：简体、繁体、英文，缺失翻译 CI 报错；语言只存一份（PLAN §12）。实现（2026-09-28，ADR 草稿 docs/adr/draft-i18n.md）：slang，基础语言简体（原中文文案不改意思），另有繁体（台湾用语）和英文，按功能分 32 个命名空间，在 `apps/pure_live/lib/i18n/`；设置 › 通用 › 语言：跟随系统、简体中文、繁體中文、English，只存 `theme.locale`（3.x 的 `language` / `languageName` 导入时换算）；跟随系统取系统语言列表里第一个中文或英文：Hant 文字或台湾、香港、澳门地区为繁体，其它中文为简体，没有中文和英文时为英文，系统语言改变时立即生效；切换后当前页面原地换成新语言，不丢页面状态；Material 自带文字随所选语言（繁体按台湾习惯）；文字样式带界面语言的 locale，Windows 繁体用正黑体（principles §2.3）；人数写成“1.2万”“1.2萬”“12K”；少键的译文不能编译，`test/i18n_test.dart` 拦下缺键、多键、空文案、占位符不一致、繁体混入简体字、英文混入汉字和过期的生成代码。与平台画质名比对的“原画 / 蓝光8M …”是数据，保持中文 | `assets/translations/zh.json`、`en.json`；`lib/modules/settings/pages/theme_settings_page.dart` |

## 3 关注、分组与标签

| 编号 | 功能与旧版行为 | 优先级 | v4 处置 | 旧代码入口 |
|---|---|---|---|---|
| F-FAV-01 | 关注列表：“开播 / 录制中 / 未开播”三个标签页；每页再按平台分标签；卡片显示直播状态、人数、平台 | P0 | **重新设计**：开播 / 全部 / 分组 三个视图，支持排序（PLAN §07）；“录制中”改为卡片状态标记，并可在录制中心查看。细则（2026-09-28）：排序为人数（默认，与旧版一致）、开播时间（本次刷新得到的开播时刻，最近开播的在前；平台不给开播时刻的排在后面按人数）、平台（平台顺序，再按人数）、自定义（在“调整顺序”页拖动），选择记在设置 `follows.sort`；未开播的紧凑行除“平台”“自定义”外按上次开播时间排。录制器的任务处于准备、录制、重连时，卡片和紧凑行显示“录制中”。“分组”视图按标签分区：每个标签一节（标题带人数，下面是描述），开播的用卡片、未开播的用紧凑行，一个房间可以出现在多节，没有标签的放在最后的“未分组” | `lib/modules/favorite/favorite_page.dart:33-35,106-117` |
| F-FAV-02 | 关注 / 取消关注：直播间顶栏按钮；卡片长按对话框里关注（带确认）；写入等待落盘，失败回滚并提示 | P0 | 保留：写库失败时不改变关注状态（事务回滚），提示“关注失败 / 取消关注失败”；撤销失败同样提示 | `lib/common/widgets/room_card.dart:141-170`；`lib/modules/live_play/widgets/layout/live_play_header.dart:68-92`；`lib/common/services/settings/favorite_room_controller.dart:404-436` |
| F-FAV-03 | 启动校验：启动时全部关注显示为“校验中/未知”，校验结果一次性发布，避免卡片跳动 | P0 | 保留。细则（2026-09-28）：第一次刷新完成前，页面顶部显示“正在检查开播状态”，全部关注以紧凑行列出，不按上次保存的状态显示开播；刷新写库是一个事务，完成后一次性发布。获取失败的房间显示“状态未知”（不沿用上次的状态，store.md §6.4.10），直到下一次刷新成功或本次运行里打开过该房间；平台明确说房间不存在的显示“房间不存在” | `lib/modules/favorite/favorite_controller.dart:639-706`；`favorite_startup_policy.dart`；提交 d6c3d8df |
| F-FAV-04 | 自动刷新关注状态：开关（默认关）、间隔、最大并发（默认 4）；回前台刷新；封面缩略图定时刷新 | P0 | 保留：封面定时刷新有独立的开关（默认关）和间隔（默认 30 分钟，5–360，沿用旧键 `autoRefreshThumbnails`、`thumbnailRefreshInterval`）；开启后开播卡片的封面按时间段换缓存键，每个间隔重新下载一次，旧图在新图到达前继续显示 | `lib/modules/settings/pages/refresh_settings.dart`；`lib/modules/favorite/favorite_controller.dart:585-706` |
| F-FAV-05 | 标签（即分组）：新建、改名、描述、拖动排序、删除；给已关注房间分配多个标签；关注页顶部按标签筛选；未关注房间不能打标签 | P0 | **重新设计**：v4 的“分组”就是标签，关注页“分组”视图按标签分区显示；映射以“平台:房间号”为键；“管理分组”里可以新建、改名、编辑描述、拖动排序、删除（可撤销） | `lib/modules/tags/tag_management_page.dart`；`tag_management_controller.dart:9-10,78-121`；`lib/common/widgets/room_card.dart:224-236`；提交 4d8ed292 |
| F-FAV-06 | 卡片长按或右键：对话框里有分享、设置标签、关注、房间号 | P0 | **重新设计**：长按改为静音预览（PLAN §07，见 F-NEW-03）；分享、设置标签、关注、复制房间号移到卡片的更多菜单和右键菜单 | `lib/common/widgets/room_card.dart:177-310,1077-1078` |
| F-FAV-07 | 关注分区：在分区页收藏某平台的分区，单独页面查看 | P2 | **合并**到“发现”：分区列表内置“已收藏”分组 | `lib/modules/areas/areas_page.dart:58`；`lib/modules/areas/favorite_areas_page.dart` |
| F-FAV-08 | 已下线或不支持的平台：关注和历史照常保留，打开时提示“平台已下线” | P0 | 保留：标记“未支持”，随备份导出，不因首批只做 5 个平台而删除数据。关注页的紧凑行带“未支持”标记，点击只提示“这个平台暂不支持”，不进直播间；刷新跳过这些房间；从链接或历史进入时，直播间显示“平台暂不支持”提示页（类型化错误，不崩溃） | `lib/routes/app_navigation.dart:40-44`；`lib/common/services/settings/favorite_room_controller.dart:58-120` |

## 4 发现：热门与分区

| 编号 | 功能与旧版行为 | 优先级 | v4 处置 | 旧代码入口 |
|---|---|---|---|---|
| F-DSC-01 | 热门：按平台分标签推荐直播间，分页加载 | P2 | **合并**：热门与分区合为“发现”，按平台切换（PLAN §07） | `lib/modules/popular/popular_page.dart`；`popular_controller.dart` |
| F-DSC-02 | 分区：平台分类列表 → 分类房间列表；CC 的官方入口用外部浏览器打开 | P2 | **合并**到“发现” | `lib/modules/areas/areas_page.dart`；`lib/modules/area_rooms/area_rooms_page.dart`；`lib/routes/app_navigation.dart:15-35` |
| F-DSC-03 | 平台显示与排序：选择首页显示哪些平台及顺序；首选平台；新平台按版本表追加，退役平台保留槽位 | P2 | 保留（设置 › 数据/平台） | `lib/modules/hot_areas/hot_areas_page.dart`；`lib/modules/settings/pages/platform_settings_page.dart`；`favorite_room_controller.dart:58-120` |
| F-DSC-04 | 分页设置：每页数量、跳页按钮、回到顶部按钮 | P2 | **删除**：v4 列表统一为无限滚动加预取（PLAN §10），不再有“页”的概念；“回到顶部”由设计系统的列表组件统一提供 | `lib/modules/settings/pages/page_settings.dart` |
| F-DSC-05 | 观众数显示规则：各平台人数口径说明、显示方式 | P2 | 保留 | `lib/modules/settings/pages/audience_metric_settings_page.dart` |

## 5 搜索与链接解析

| 编号 | 功能与旧版行为 | 优先级 | v4 处置 | 旧代码入口 |
|---|---|---|---|---|
| F-SRC-01 | 跨平台搜索：关键词；平台筛选（全部/单个）；排序（智能、平台、人数、粉丝）；“包含未开播”开关；加载更多 | P0 | 保留；布局按窗口等级（紧凑、中等：顶部平台标签；展开及以上：左侧平台筛选栏，见 principles §5.2）。细则（2026-09-28）：排序沿用旧版 `search_ranking.dart` 的规则：开播的总在前；平台 = 平台顺序 → 人数，人数 = 人数 → 平台顺序，最后按标题和房间号稳定排序。**“粉丝”**：卡片模型的 `followers` 是主播粉丝数，只在搜索接口给出时填写（B 站 `attentions`、快手 `counts.fan`、CHZZK、Picarto、17LIVE、酷狗、Twitch；LiveMe 恒为 0，不用），排序 = 粉丝 → 人数 → 平台顺序，没有粉丝数的按 0 排在后面（2026-09-28 补上）。**“智能”改为按相关度**：旧版智能 = 人数 → 粉丝 → 平台，没有粉丝数后就和“人数”完全一样；v4 的智能改为保留各平台自己的相关度顺序，按名次轮流合并（各平台第 1 名、再各平台第 2 名……，同名次按平台顺序），这样搜主播名时精确匹配的小主播不会被人数多的无关房间挤到后面；默认用智能。“综合”对每个平台分别翻页，滚到底时只请求还有下一页的平台；单个平台失败不影响其它平台 | `lib/modules/search/search_page.dart:26-256`；`search_controller.dart:175-370` |
| F-SRC-02 | 网页搜索兜底：没有原生搜索的平台，在内置网页打开平台搜索页并识别房间链接；Windows 需要 WebView2，缺失时提示 | P0 | 保留：网页组件封装在接口后面（PLAN §04 对 inappwebview 的评估；docs/adr/0032-webview.md）。只对适配器没有实现 SearchSource、又有已知搜索页的平台显示入口；前两批十个平台都有原生搜索，入口要等第三批才会出现。网页里点开的房间链接和“本页的房间”都用链接识别（F-SRC-03 同一套）判断 | `lib/modules/search/web_search_controller.dart`；`web_search_room_parser.dart`；`search_controller.dart:147,523-559` |
| F-SRC-03 | 链接跳转：粘贴直播间链接或“平台+房间号”打开直播间；页面列出支持的链接格式 | P0 | **合并**到搜索框：输入识别为链接时直接给出“打开直播间” | `lib/modules/toolbox/toolbox_page.dart:23-41,140-147`；`toolbox_controller.dart:120` |
| F-SRC-04 | 获取直链：解析链接 → 选画质、线路 → 复制播放地址（工具箱和直播间菜单两处入口） | P2 | 保留：入口为直播间菜单、卡片的更多菜单（关注、发现、搜索、历史共用，principles §4.2）。卡片入口先加载详情和线路，再让用户选画质和线路，剪贴板写入成功后才提示已复制；未开播时提示拿不到直链 | `lib/modules/toolbox/toolbox_controller.dart:129`；`lib/modules/live_play/dialogs/known_room_link_dialog.dart`；`lib/common/utils/live_url_tool.dart:388` |
| F-SRC-05 | 工具箱打开时自动读剪贴板识别链接 | P2 | **重新设计**：并入搜索页，读剪贴板可在设置关闭（PLAN §05 建议） | `lib/modules/toolbox/toolbox_controller.dart:250` |

## 6 直播间（详见 `spec/modules/live-room.md`）

| 编号 | 功能与旧版行为 | 优先级 | v4 处置 | 旧代码入口 |
|---|---|---|---|---|
| F-ROOM-01 | 打开直播间：加载详情 → 画质 → 地址 → 起播；未开播、封禁、获取失败、播放失败各有提示和重试；刷新 | P0 | 保留 | `lib/modules/live_play/controllers/live_play_controller.dart:744-840`；`player_controller.dart:571-684` |
| F-ROOM-02 | 画质与线路：普通模式两个下拉框，全屏合并面板；蜂窝网络单独的画质偏好；切换不重建页面，以最后一次为准 | P0 | 保留（规则见 live-room §4） | `lib/modules/live_play/widgets/resolution_selector/*`；`video_controller_panel.dart:1048-1392`；`player_controller.dart:611-847` |
| F-ROOM-03 | 画面弹幕、弹幕列表、醒目留言、在线人数 | P0 | 保留（见 `spec/modules/danmaku.md`） | `lib/modules/live_play/widgets/danmaku/*`；`live_play_controller.dart:73,315-385,500-566` |
| F-ROOM-04 | 手势、键盘、鼠标、返回键、自动隐藏、锁定 | P0 | **重新设计**：按 PLAN §07 映射（live-room §3） | `video_controller_panel.dart:195-253,817-1046`；`lib/modules/live_play/widgets/keyboard/video_keyboard.dart` |
| F-ROOM-05 | 展示状态：普通、宽屏（桌面隐藏右侧栏）、全屏、竖屏全屏 | P0 | **重新设计**：内嵌 / 剧场 / 全屏 / 竖屏全屏，单一状态源（live-room §2） | `lib/modules/live_play/states/ui_state.dart`；`video_controller.dart:1311-1516` |
| F-ROOM-06 | 竖屏直播适配：自动识别竖屏源；三档底部面板；按房间覆盖方向（自动/竖/横，可记忆）；全屏方向策略（跟随源/跟随系统/强制横屏）；竖屏全屏铺放方式（完整/氛围/平衡/裁切）；竖屏弹幕区域（跟随/上四分之一/减半/隐藏）；画中画跟随源方向；诊断角标 | P0 | **重新设计**：保留识别、覆盖、方向策略、弹幕区域；面板和铺放方式随新设计重做；诊断角标移到开发者选项 | `lib/modules/settings/pages/portrait_live_settings_page.dart`；`lib/common/services/settings/player_settings_controller.dart:56-71`；`live_play_content.dart:130-477` |
| F-ROOM-07 | 画面比例：文字按钮在 6 种之间循环（适应、居中裁切、拉伸、适应高度、适应宽度、缩小） | P0 | **重新设计**：双指缩放和菜单在“适应 → 填充 → 裁切”三种之间切换（PLAN §07）；删除适应高度/宽度/缩小（直播画面上与“适应”“裁切”效果重复） | `video_controller_panel.dart:2068-2117`；`lib/common/consts/app_consts.dart:41-48` |
| F-ROOM-08 | 全屏锁定 | P0 | 保留 | `video_controller_panel.dart:1009-1046` |
| F-ROOM-09 | 纯音频（耳机按钮，只作用于当前房间） | P2 | 保留（`spec/modules/playback.md` AUD-*） | `video_controller_panel.dart:1927-1957`；`video_controller.dart:604-626,1246-1267` |
| F-ROOM-10 | ASMR 助眠模式（Android）：进房自动纯音频并启动睡眠定时；手动恢复画面时结束定时 | P2 | **合并**：作为“定时关闭”的一个预设（进房自动纯音频 + 定时），行为不变 | `lib/common/services/settings/app_settings_controller.dart:45-46`；`live_play_controller.dart:605-628,913-920` |
| F-ROOM-11 | 切换直播间：对话框列出开播关注、录制中、观看历史，点选即切换（全屏顶栏和菜单两处入口） | P2 | **重新设计**：保留列表面板；新增竖屏全屏上下滑和 TV 上下键换台（F-NEW-04） | `lib/modules/live_play/dialogs/play_other.dart`；`video_controller_panel.dart:393-410` |
| F-ROOM-12 | ⋮ 菜单：打开原站/App、切换直播间、投屏、定时关闭、房间音量、获取直链、分享、本地互动、新窗口打开（仅 Windows） | P2 | **重新设计**：保留各项，按设备放入更多菜单、右键菜单、长按快捷面板 | `lib/modules/live_play/widgets/button/live_play_menu_button.dart:41-206` |
| F-ROOM-13 | 房间音量：桌面按房间记忆；手机默认音量；全局静音 | P2 | 保留（手机音量只读不写，见 live-room INV-ROOM-03） | `lib/modules/live_play/dialogs/room_volume_dialog.dart`；`video_controller.dart:540-566` |
| F-ROOM-14 | 直播间录制按钮：立即录制、加入/移除监控、停止录制、去录制中心 | P1 | 保留 | `lib/modules/live_play/widgets/button/record_action_button.dart`；`live_play_controller.dart:1055-1073` |
| F-ROOM-15 | 进房默认全屏（设置，默认关；进房 1 秒后生效） | P2 | 保留 | `video_controller.dart:626-643`；`app_settings_controller.dart:51` |
| F-ROOM-16 | 播放时屏幕常亮（设置，默认开） | P2 | 保留 | `live_play_controller.dart:252-259`；`app_settings_controller.dart:48` |
| F-ROOM-17 | 全屏顶栏显示时间和电量（Android 在返回键旁，桌面在右侧） | P2 | 保留 | `video_controller_panel.dart:38-66,460-543` |
| F-ROOM-18 | 打开原站或原生 App | P2 | 保留 | `live_play_controller.dart:941-1041`；`lib/modules/live_play/services/room_external_opener.dart` |

## 7 多画面（P1，详见 `spec/modules/multiview.md`）

| 编号 | 功能与旧版行为 | 优先级 | v4 处置 | 旧代码入口 |
|---|---|---|---|---|
| F-MV-01 | 布局 1×1、1×2、2×2、1+3（一大多小）；手机最多 4 格，桌面一大多小可加到 9 格；入口在首页“更多”菜单（设置可隐藏） | P1 | **重新设计**：布局按窗口等级；入口移到“我的”、关注页“一键多画面”、卡片预览“加入多画面” | `lib/modules/multiview/models/multiview_models.dart:15-51`；`multiview_controller.dart:73,84`；`common_appbar_actions.dart:56-67` |
| F-MV-02 | 选台：从关注或历史中选，可搜索；桌面宽屏为常驻侧板，其它为底部弹窗；选完自动把目标移到下一个空格 | P1 | 保留；侧板按窗口等级显示 | `lib/modules/multiview/widgets/multiview_room_picker.dart`；`multiview_page.dart:214-266` |
| F-MV-03 | 声音焦点（点格子切换，只有一格出声）、全部静音、所选格音量（按房间保存） | P1 | 保留 | `multiview_controller.dart:1006-1110`；`multiview_page.dart:494-545` |
| F-MV-04 | 每格：换房、画质、线路、刷新、暂停、关闭 | P1 | 保留 | `multiview_page.dart:268-340,697-770` |
| F-MV-05 | 弹幕：页级开关（默认关），只在大画面或声音焦点格显示 | P1 | 保留 | `multiview_controller.dart:414-550` |
| F-MV-06 | 小格自动降画质：手动开关，默认关，只在一大多小生效 | P1 | **重新设计**：由资源调度自动决定（multiview §7），手动选择优先 | `multiview_controller.dart:409-414,493-504,641-665` |
| F-MV-07 | 沉浸模式（隐藏工具条）、全屏模式 | P1 | 保留 | `multiview_page.dart:171-213,361-418` |
| F-MV-08 | 卡顿自动恢复（只在 Windows 有画面检测）、斗鱼租期续流 | P1 | **重新设计**：全平台卡顿检测，与单房间共用恢复策略 | `multiview_controller.dart:1165-1285,216-235`；提交 31982153 |

## 8 录制中心（P1，详见 `spec/modules/record.md`）

| 编号 | 功能与旧版行为 | 优先级 | v4 处置 | 旧代码入口 |
|---|---|---|---|---|
| F-REC-01 | 任务列表：立即录制、停止、重新录制、强制开始；状态（排队、等待、准备、录制中、重连、处理中、完成、失败、已停止）；显示大小、最后错误和出错环节；打开文件夹 | P1 | 保留 | `lib/recorder/pages/recorder/recorder_page.dart`；`recorder_controller.dart:715-1260` |
| F-REC-02 | 监控：加入后轮询开播状态，开播自动录制；取消监控（确认） | P1 | 保留 | `lib/modules/live_play/widgets/button/record_action_button.dart`；`recorder_page.dart` |
| F-REC-03 | 录制设置：默认画质、优先最佳流、分段时长、最大任务数、重试次数与间隔、退避、轮询开关与间隔、读写超时档位、缓存上限、存储目录、拼音文件夹名、开机自动开始、录制弹幕、性能档位 | P1 | 保留；分段语义随中继直写调整（ADR 0005） | `lib/recorder/pages/record_settings/record_settings_page.dart`；`lib/recorder/consts/recorder_config.dart:99-296` |
| F-REC-04 | 录制弹幕与视频同步保存 | P1 | 保留 | `lib/recorder/services/recording_danmaku_service.dart` |
| F-REC-05 | 录制文件处理与合并（FFmpegKit 转封装） | P1 | **重新设计**：中继直写 FLV/TS，按需用共享 FFmpeg 转 MP4；去掉 FFmpegKit（ADR 0005） | `lib/recorder/services/video_processor_service.dart`；`ffmpeg_service.dart` |
| F-REC-06 | Android 后台录制：前台服务、唤醒锁、异常中断处理 | P1 | 保留；服务类型改为 `specialUse`，避开 Android 15 起 dataSync 每天 6 小时的上限（spec/modules/record.md §16.1，2026-09-28） | `android/app/src/main/kotlin/com/mystyle/pure_live/RecorderForegroundService.kt`；`recorder_controller.dart:1013-1060` |
| F-REC-07 | 启动 3 秒后按需恢复未完成的录制任务 | P1 | 保留 | `lib/common/global/initial_services.dart:50-92`（诊断 05 §④7） |

## 9 历史

| 编号 | 功能与旧版行为 | 优先级 | v4 处置 | 旧代码入口 |
|---|---|---|---|---|
| F-HIS-01 | 观看历史：进房自动记录（IPTV 除外），按最近观看排序；单条删除、清空（确认）；数量上限（默认 50，可选“不限”，升级不得截断） | P2 | 保留；删除和清空增加撤销（PLAN §07 一致性规则） | `lib/modules/history/history_page.dart`；`lib/common/services/settings/history_controller.dart:84-165`；`live_play_controller.dart:750-753` |

## 10 IPTV

| 编号 | 功能与旧版行为 | 优先级 | v4 处置 | 旧代码入口 |
|---|---|---|---|---|
| F-IPTV-01 | 播放列表导入：本地文件或网络地址，M3U / TXT / JSON；列表管理（逐个或全部同步、删除、打开来源）；从 Android 分享接收播放列表 | P2 | 保留 | `lib/modules/iptv/iptv_page.dart:188-199`；`iptv_manage.dart:146-206`；`lib/core/iptv/services/iptv_import_manager.dart`；`lib/main.dart:105-131` |
| F-IPTV-02 | EPG 导入：XMLTV / JSON；选择当前 EPG 源；频道自动匹配 | P2 | 保留 | `iptv_page.dart:201-206`；`lib/core/iptv/services/epg_import_manager.dart`；`epg_auto_mapper.dart` |
| F-IPTV-03 | 自动同步：开关（默认关）和间隔（默认 24 小时），启动 3 秒后执行 | P2 | 保留 | `iptv_page.dart:153-176`；`lib/common/services/settings/iptv_settings_controller.dart:31-39`；`lib/core/iptv/services/auto_sync_scheduler.dart` |
| F-IPTV-04 | 自定义请求 UA | P2 | 保留 | `iptv_page.dart:181` |
| F-IPTV-05 | 频道浏览：作为“网络电视”平台出现在热门和分区里，按分组列出；单画质“原画”、单线路；频道可以像普通房间一样关注 | P2 | 保留 | `lib/core/site/iptv/iptv_site.dart:29-307`；`live_play_controller.dart:850-873`；`live_play_header.dart:68-92` |
| F-IPTV-06 | 节目单与回看：直播间顶栏显示当前节目；节目单对话框（前 2 天到后 1 天）；过去节目按 default / playseek / offset 规则回看，可“回到直播” | P2 | 保留 | `lib/modules/live_play/widgets/video_player/iptv_schedule_dialog.dart`；`iptv_programme_policy.dart:7-17`；`video_controller.dart:1007-1066`；`video_controller_panel.dart:358-386` |
| F-IPTV-07 | Xtream Codes 登录导入 | P2 | 【旧版未上线】只有数据模型（`lib/core/iptv/provider/provider.dart:144`、`lib/core/iptv/models/channel.dart:104`），没有导入界面和调用方。v4：第 7 阶段实现导入，账号密码进加密存储 | 同左 |
| F-IPTV-08 | 频道收藏夹 | P2 | 【旧版未上线】只有表结构（`lib/core/iptv/local/tables.dart:115-136`），无调用方。v4：**合并**到普通“关注”（旧版频道已可关注），不单独做收藏夹 | 同左 |
| F-IPTV-09 | 节目提醒 | P2 | 【旧版未上线】只有表和增删接口（`tables.dart:138-152`；`lib/core/iptv/local/database.dart:547-560`），无调用方。v4：**合并**到开播/节目提醒（F-NEW-01），P2 | 同左 |
| F-IPTV-10 | 定时录制 | P2 | 【旧版未上线】只有表和增删接口（`tables.dart:171-184`；`database.dart:562-565`）。v4：**合并**到录制中心的定时任务，P2 | 同左 |
| F-IPTV-11 | 故障切换组（同一频道多个源自动切换） | P2 | 【旧版未上线】只有表和增删接口（`tables.dart:154-169`；`database.dart:582-627`）。v4：**合并**为“同一频道的多个源 = 多条线路”，由播放层换线路步骤处理（playback REC-1） | 同左 |

行为细节见 [spec/modules/iptv.md](modules/iptv.md)。**修订（2026-09-28，ADR 0024）**：v4 的 IPTV 数据放进主库（schema 2），旧版 IPTV 库只读导入、不升级结构，回退到 3.x 时旧库仍可用（原定“原样沿用、继续编号升级”会让回退后的旧版因 schemaVersion 过高报错，REG-STORE-021）。

## 11 弹幕设置与屏蔽（P0，详见 `spec/modules/danmaku.md`）

| 编号 | 功能与旧版行为 | 优先级 | v4 处置 | 旧代码入口 |
|---|---|---|---|---|
| F-DM-01 | 弹幕开关（控制条按钮）；全局“显示弹幕”设置关闭时隐藏弹幕按钮并断开连接（除非开了画中画弹幕） | P0 | 保留 | `video_controller_panel.dart:1797-1840`；`live_play_controller.dart:767-776` |
| F-DM-02 | 样式：字号、字重、速度、透明度、描边、显示区域、顶部/底部留白、帧率（自动或手动 30–240）、不显示表情；位置预设；样式模板保存与恢复；改动即时生效 | P0 | 保留；入口统一为一个设置面板（旧版有控制条对话框、房间标签页、全局设置三处入口） | `lib/modules/live_play/pages/danmaku_settings_page.dart`；`video_controller_panel.dart:1843-1880,2120-2213`；`lib/modules/live_play/widgets/danmaku/danmaku_viewing_preset.dart` |
| F-DM-03 | 过滤：重复合并（窗口 1–30 秒）、相似度过滤（阈值、缓存时长、缓存条数）、斗鱼疑似机器人过滤（默认关） | P0 | 保留 | `lib/modules/live_play/pages/keyword_block_page.dart`；`danmaku_similarity_filter.dart`；`lib/core/danmaku/douyu_danmaku.dart:128-129` |
| F-DM-04 | 屏蔽关键词、屏蔽用户：房间内“屏蔽”标签页和独立的屏蔽页；在弹幕上点击或长按 → 复制、屏蔽关键词、屏蔽用户 | P0 | 保留；独立屏蔽页与房间内标签页**合并**为一个管理页 | `lib/modules/shield/danmu_shield_page.dart`；`keyword_block_page.dart`；`lib/modules/live_play/widgets/danmaku/danmaku_message_actions.dart` |
| F-DM-05 | 点击弹幕、长按弹幕的交互开关（默认都开） | P0 | 保留（danmaku.md REN-8） | `lib/common/services/settings/danmaku_settings_controller.dart:72-73`；`danmaku_settings_page.dart:398-412` |
| F-DM-06 | 弹幕字体：选择字体、下载字体 | P2 | 保留：只允许许可证明确的字体 | `lib/modules/settings/pages/font_family_manager_page.dart`；`video_settings_page.dart` |
| F-DM-07 | 画中画弹幕：开关、字号、速度、同屏上限、发射间隔、帧率、区域、颜色（原色或统一色）、自动缩放、预览 | P2 | 保留 | `lib/modules/settings/pages/pip_danmaku_settings_page.dart` |

## 12 本地互动

| 编号 | 功能与旧版行为 | 优先级 | v4 处置 | 旧代码入口 |
|---|---|---|---|---|
| F-LI-01 | 本地发弹幕：全屏底栏和竖屏面板里的输入框，只在本机显示（不冒充平台账号），进入列表和画面 | P2 | **合并**：保留为弹幕面板里的本地输入框，行为不变 | `video_controller_panel.dart:1584-1750`；`lib/modules/live_play/widgets/local_interaction/local_message_delivery_queue.dart` |
| F-LI-02 | 虚拟经济与特效：体验金币（初始 1000）、礼物中心、全屏礼物特效、等级徽章、平台徽章、头衔、平台礼物包、本地样式编辑、本地历史；共 29 个设置键 | P2 | **删除**：纯本机模拟，与直播内容和平台账号无关，约 1780 行代码加 29 个设置键的维护成本，PLAN 未列入；删除写进 v4 更新说明，对应设置不迁移 | `lib/modules/live_play/widgets/local_interaction/*`；`lib/modules/settings/pages/local_interaction_settings_page.dart`；`local_interaction_controller.dart:86-114` |

## 13 投屏、定时、分享

| 编号 | 功能与旧版行为 | 优先级 | v4 处置 | 旧代码入口 |
|---|---|---|---|---|
| F-CAST-01 | DLNA 投屏：搜索局域网设备，把当前房间的播放地址投过去；无设备、搜索失败、地址无效各有提示；入口在 Android 顶栏和菜单 | P2 | 保留 | `lib/modules/live_play/dialogs/live_dlna_dialog.dart`；`lib/common/utils/live_url_tool.dart:405`；`video_controller_panel.dart:1959-1984` |
| F-TMR-01 | 房间定时关闭：开关 + 时长（预设或自定义分钟），到点暂停并停止后台音频、提示 | P2 | 保留 | `lib/modules/live_play/dialogs/room_timer_dialog.dart`；`timer_controller.dart`；`live_play_controller.dart:534-540,676-740` |
| F-TMR-02 | 应用倒计时关闭：设置里开关 + 时长（默认 120 分钟，1 分钟–1 年），显示剩余时间 | P2 | **合并**：与 F-TMR-01 合为一个“定时关闭”，可选“暂停播放”或“退出应用” | `lib/common/services/settings/exit_settings_controller.dart:13-26`；`lib/modules/settings/pages/general_settings_page.dart` |
| F-SHR-01 | 分享直播间：生成分享口令 `base64url(msgpack{m:'pure_live',…})`；桌面复制到剪贴板，手机调系统分享 | P2 | 保留；口令格式必须兼容旧版 | `lib/common/utils/share_command_handler.dart:174-210`；`lib/plugins/share_command_handler.dart:4-47` |
| F-SHR-02 | 识别分享口令：回到前台 1 秒后读剪贴板；Android 分享接收（文本或文件，依次识别口令、直播链接、播放列表、EPG）；识别后弹窗确认进房；冷启动时等导航就绪（最多 8 秒） | P2 | 保留；读剪贴板可关闭 | `lib/common/global/platform/desktop_manager.dart:611-667`；`lib/main.dart:105-131`；`lib/common/widgets/share_command_import_dialog.dart` |

## 14 同步、备份与账号

| 编号 | 功能与旧版行为 | 优先级 | v4 处置 | 旧代码入口 |
|---|---|---|---|---|
| F-SYNC-01 | 局域网同步：本机开启接收服务，显示地址和二维码 `purelive://ip:port/sync?code=`；对方扫码或手动输入地址 + 配对码；发送或接收设置；可选包含账号 Cookie；接收前本机确认 | P2 | 保留；统一 v4 备份格式；Cookie 默认不包含（宪法 §8） | `lib/modules/remote_receiver/remote_sync_page.dart`；`remote_sync_service.dart:145-546`；`remote_sync_protocol.dart:39` |
| F-SYNC-02 | 旧电视接口：把设置作为 URL 参数推到 `/api/setSettings` | P2 | **删除**：设置明文放在 URL 里；功能由 F-SYNC-01 覆盖 | `lib/plugins/backup_recovery_service.dart:119-127`；`backup_page.dart`（sync_tv_data） |
| F-DAV-01 | WebDAV：多个配置（名称、地址、用户名、密码）；上传全部设置或仅关注；浏览、删除远端文件；恢复全部或仅关注（确认）；帮助教程 | P2 | 保留；密码进加密存储 | `lib/modules/web_dav/web_dav_page.dart`；`web_dav_controller.dart:326`；`lib/common/services/settings/web_dav_controller.dart:15-26` |
| F-BAK-01 | 本地备份：创建全部备份或仅关注备份；从文件恢复全部或仅关注；备份目录设置；兼容无版本、v2、v3 和仅关注格式；恢复先整体校验再写入，失败回滚 | P2 | 保留；统一为带版本号的 v4 备份格式，兼容全部旧格式；范围补上录制设置和任务、IPTV（诊断 05 ⑦7） | `lib/modules/backup/backup_page.dart`；`lib/common/services/settings/backup_controller.dart:33,355-476`；`lib/plugins/backup_recovery_service.dart:28,59` |
| F-BAK-02 | 日志：开启本地日志、打开日志目录、在浏览器查看 | P2 | **重新设计**：本地滚动日志 + 一键导出脱敏诊断包（PLAN §12） | `lib/modules/backup/backup_page.dart`；`lib/core/common/log.dart:551-559` |
| F-ACC-01 | 平台账号：B 站扫码登录和网页登录；斗鱼 Cookie（含会话续期状态）；虎牙、抖音、快手、Twitch、SOOP、YY 手动填 Cookie；显示登录状态、校验、退出（确认） | P2 | 保留；Cookie 加密存储（宪法 §8）；网页登录组件封装在接口后（docs/adr/0032-webview.md）。用户名来自适配器已有的用户信息接口（B 站、抖音），其余平台显示“已填 Cookie”；网易 CC、AcFun 在 v4 不登录（spec/sites/cc.md §8、acfun.md §8），不出现在账号页；界面和日志不显示 Cookie | `lib/modules/account/account_page.dart`；`bilibili/qr_login_controller.dart`；`bilibili/web_login_controller.dart:176`；`douyu/douyu_cookie_controller.dart`；`widgets/account_cookie_editor.dart`；`lib/common/services/settings/cookie_settings_controller.dart:10-43` |
| F-ACC-02 | Firebase 账号：邮箱注册登录、GitHub 登录、云端备份与自动恢复、管理员用户管理 | P2 | **删除**：已确认移除 Firebase（宪法“已确认的决定”），由 WebDAV 和局域网同步替代；3.3.x 提示仅在 Firestore 有配置的用户先导出（ADR 0004） | `lib/modules/auth/*`；`lib/modules/auth/utils/firebase_manager.dart:138-345`；`backup_page.dart:82` |

## 15 应用内更新与关于

| 编号 | 功能与旧版行为 | 优先级 | v4 处置 | 旧代码入口 |
|---|---|---|---|---|
| F-UPD-01 | 自动检查更新（设置，默认开；首页首帧后 2 秒）；版本信息从 raw GitHub 或 14 个第三方镜像获取；可选“只用 GitHub 源” | P2 | 保留；更新包校验 SHA256（PLAN §12 发布流水线）；远程数据迁到自有仓库并加签名或哈希 | `lib/common/utils/version_util.dart:33-39,77`；`lib/modules/home/home_page.dart:95-104`；`general_settings_page.dart` |
| F-UPD-02 | 版本页：更新日志；Android 按架构下载 APK 并安装；Windows 安装包、MSIX、便携版；macOS 包；复制链接 | P2 | 保留；**删除** MSIX（证书缺失、从未能发布，诊断 08 ②） | `lib/modules/version/version_page.dart`；`lib/common/widgets/download_apk_dialog.dart` |
| F-UPD-03 | 关于：项目主页、开源许可、历史版本列表 | P2 | 保留；开源许可页自动生成（ADR 0006） | `lib/modules/about/about_page.dart`；`version_history.dart` |

## 16 设置

| 编号 | 功能与旧版行为 | 优先级 | v4 处置 | 旧代码入口 |
|---|---|---|---|---|
| F-SET-01 | 外观：主题模式（跟随系统/浅/深）、主题色、动态取色、语言、界面字号、字体 | P2 | 保留；主题增加纯黑；字号跟随系统缩放（PLAN §09） | `lib/modules/settings/pages/theme_settings_page.dart`；`font_settings_page.dart` |
| F-SET-02 | 网格间距（主轴、交叉轴） | P2 | **删除**：由设计系统的 4 点网格统一 | `theme_settings_page.dart` |
| F-SET-03 | 卡片外观：预设（紧凑/标准/详细/自定义）、布局（封面/紧凑）、圆角、显示主播/头像/人数/平台/回放标记，手机和桌面分开 | P2 | **重新设计**：只保留“信息密度”预设和平台标识显示方式，细项由设计系统决定 | `lib/modules/settings/pages/room_card_settings_page.dart` |
| F-SET-04 | 加载动画样式和颜色 | P2 | **删除**：设计系统只有一个加载动画（PLAN §04 依赖瘦身） | `lib/modules/settings/pages/loading_style_settings_page.dart` |
| F-SET-05 | 播放：画质偏好（Wi-Fi、蜂窝分开）、后台播放、离开直播间时小窗播放、全局静音、手机/桌面默认音量、默认全屏、屏幕常亮、ASMR、Windows 画中画置顶 | P0（画质偏好）/ P2 | 保留 | `lib/modules/settings/pages/video_settings_page.dart`；`player_settings_controller.dart:33-71` |
| F-SET-06 | 播放内核：切换内核（mpv / IJK / Exo / fvp）；mpv 硬解开关、硬解方式、视频/音频输出驱动、兼容模式、退出时强制销毁、RTX 超分（Windows）；自定义 mpv 参数；播放器代理 | P2 | **重新设计**：删除内核切换（宪法：全平台只用 mpv）；其余作为“高级”设置保留；旧值 ijk/exo 迁移为 mpv | `lib/modules/settings/pages/player_kernel_settings_page.dart`；`mpv_option_page.dart` |
| F-SET-07 | 网络代理：应用代理、播放器代理（地址、端口，默认端口 7897） | P2 | **重新设计**：默认跟随系统代理（原生网络栈），手动代理和按平台规则作为覆盖（PLAN §12） | `lib/modules/settings/pages/network_proxy_settings_page.dart` |
| F-SET-08 | 通用：刷新率模式（省电/平衡/性能，新装默认省电）、Windows 动态刷新率、退出确认、窗口大小、新窗口打开（Windows）、启动页开关、自动检查更新 | P2 | 保留（启动页开关随 F-APP-01 删除） | `lib/modules/settings/pages/general_settings_page.dart`；`lib/common/widgets/adaptive_refresh_rate_scope.dart` |
| F-SET-09 | 缓存与数据：显示缓存大小、清理本地缓存（确认）、刷新缩略图、下载目录（选择、重置） | P2 | 保留（设置 › 数据） | `lib/modules/settings/pages/cache_data_settings_page.dart`；`lib/common/services/settings/cache_controller.dart:44-54,108-135` |
| F-SET-10 | 本地配置预览：查看当前全部设置的 JSON | P2 | **合并**到诊断包导出（F-BAK-02） | `lib/modules/settings/pages/local_config_preveiw.dart` |

## 17 桌面（Windows）

| 编号 | 功能与旧版行为 | 优先级 | v4 处置 | 旧代码入口 |
|---|---|---|---|---|
| F-WIN-01 | 单实例：无参数重复启动时把已有窗口置前 | P2 | 保留（诊断 08 建议改为命名管道转发参数） | `windows/runner/main.cpp`；`lib/common/global/initialized.dart:61,152-160` |
| F-WIN-02 | 多窗口：直播间菜单“新窗口打开”启动独立进程（`--instance`、`--open-room`、`--config-file`），用临时文件交接设置，只接受启动器自己写入的路径 | P2 | 保留 | `lib/common/utils/windows_multi_instance_launcher.dart:19-66,119-152`；提交 ef5f05c0 |
| F-WIN-03 | 托盘：点击显示/隐藏窗口；右键菜单（显示/隐藏、退出）；菜单文字随语言更新 | P2 | 保留 | `lib/common/global/platform/desktop_manager.dart:139-236`；`desktop_tray_service.dart` |
| F-WIN-04 | 关闭窗口：退出或最小化到托盘，可“不再询问” | P2 | 保留 | `lib/common/services/settings/exit_settings_controller.dart:10-26`；`desktop_manager.dart:673-679` |
| F-WIN-05 | 开机自启（默认开：首次启动即注册） | P2 | 保留，**默认改为关**：开机自启应由用户主动开启（诊断 05 §⑤ 标为待确认；按“隐私默认安全”取保守值） | `lib/common/services/settings/startup_controller.dart:25-53` |
| F-WIN-06 | 窗口：Mica 效果、自绘标题栏（全屏时隐藏）、窗口大小和位置记忆、便携版数据跟随安装目录 | P2 | 保留；多显示器按各自缩放渲染（PLAN §08） | `desktop_manager.dart:48-99`；`lib/common/global/app_path_manager.dart:47-293` |
| F-WIN-07 | 显示器刷新率：枚举当前显示器支持的刷新率，窗口移动或换显示器时更新 | P2 | **不再需要（2026-09-28）**：3.x 用它给弹幕选帧率；v4 的弹幕帧时钟跟随显示器的垂直同步（`DanmakuFrameClock`），Flutter 在换显示器时自动切换刷新率，所以不枚举 | `windows/runner/flutter_window.cpp` |

## 18 Android TV、画中画与小窗、后台播放

| 编号 | 功能与旧版行为 | 优先级 | v4 处置 | 旧代码入口 |
|---|---|---|---|---|
| F-TV-01 | Android TV：Manifest 有 LEANBACK_LAUNCHER 和横幅，触屏非必需；**没有焦点模型**，方向键 ↑↓ 被音量快捷键占用 | P2 | **重新设计**：同一安装包内的 TV 模式（宪法），方向键焦点模型、10 英尺字号、换台（PLAN §07、§08） | `android/app/src/main/AndroidManifest.xml:45,63,132-133`；`video_keyboard.dart:62-79` |
| F-PIP-01 | Android 系统画中画：按钮进入；比例跟随画面；画中画里有播放/暂停和精简弹幕 | P2 | 保留（playback PIP-2） | `lib/player/core/player_manager.dart:2808-2869,3219-3290` |
| F-PIP-02 | Windows 画中画：主窗口缩成小窗，可拖动，双击退出，悬停显示播放/暂停和退出；可设置置顶（默认关） | P2 | 保留（playback PIP-3） | `player_manager.dart:2870-2958,3219-3290`；`player_settings_controller.dart:47` |
| F-PIP-03 | 应用内小窗：离开直播间时出现（设置“离开时小窗播放”，默认关）；可拖动；点击回房；有弹窗时隐藏 | P2 | 保留（playback PIP-4；live-room §2） | `player_manager.dart:2970-3156`；`lib/routes/navigation_observer.dart:45-67,109-121` |
| F-BG-01 | 后台播放：设置（默认关）；开启时后台继续播放声音，通知栏、锁屏控制、耳机线控，持有唤醒锁和 Wi-Fi 锁；关闭时隐藏 1.5 秒后暂停，回前台恢复；来电等音频打断时暂停并恢复 | P2 | 保留（playback INT-3、INT-4、PERF-2） | `lib/player/core/live_audio_service.dart:28,192`；`lib/player/core/playback_lifecycle_coordinator.dart`；`MainActivity.kt`（pure_live/background_playback） |

## 19 v4 新增（不计入对齐验收）

| 编号 | 功能 | 来源 |
|---|---|---|
| F-NEW-01 | 开播提醒（关注房间开播时通知），并承载 IPTV 节目提醒。检测、去重、合并和存储规则见 ADR 草稿 `docs/adr/0028-live-alerts.md` | PLAN §07 |
| F-NEW-02 | 关注页“一键多画面”：把选中的开播关注直接排进多画面 | PLAN §07 |
| F-NEW-03 | 长按直播间卡片：静音小窗预览；抬起后可选“进入 / 加入多画面 / 关注” | PLAN §07 |
| F-NEW-04 | 竖屏全屏上下滑（默认关闭，principles §6.1）、TV 上下键和频道键、桌面 PageUp/PageDown：切换到同列表的上一个/下一个开播直播间 | PLAN §07 |
| F-NEW-05 | 双指缩放切换画面比例；长按画面打开快捷面板（画质、线路、弹幕开关、截图、定时关闭）；截图 | PLAN §07 |
| F-NEW-06 | 桌面快捷键扩充（F、M、D、Q、L、P、Ctrl+F、Ctrl+R、1–9、?）和右键菜单 | PLAN §07 |
| F-NEW-07 | 手机紧凑宽度下横屏自动全屏 | PLAN §08 |
| F-NEW-08 | 首次启动向导：从文件、WebDAV 或局域网导入 | 诊断 05 ⑥ |
| F-NEW-09 | 平台健康状态：显示“某平台当前异常” | PLAN §12 |
| F-NEW-10 | 弱网时自动选低画质；离线提示 | PLAN §12 |
| F-NEW-11 | 可选崩溃上报（默认关） | 宪法“已确认的决定” |
| F-NEW-12 | 系统媒体控制（Windows SMTC）、跟随系统代理、Cookie 加密存储 | PLAN §11、§12 |

## 20 待确认

1. ~~F-REC-06：Android 15 起 dataSync 前台服务每天 6 小时的限制下，长时间录制怎么办（诊断 08 ①）~~：2026-09-28 改用 `specialUse` 类型，没有时间上限（spec/modules/record.md §16.1，docs/adr/0029-record-service.md）。
2. 旧数据迁移相关的待确认（安卓旧路径 `pure_live/app_settings.hive` 是否有正式版用过、语言两份存储的优先级）归存储规格（`spec/modules/store.md`）处理，本清单不重复。
