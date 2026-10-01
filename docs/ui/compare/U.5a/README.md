# U.5a 搜索：设计（第 1 版）

- 状态：完成（2026-10-01，[记录](../../records/U.5a.md)）。设计已确认（2026-10-01，用户：“重构评审全部通过，你设计的挺好的，后续全部通过”；“需要你选的”按建议）
- 范围：搜索页（搜索框、平台条、筛选、结果、各种状态）、排序菜单、搜索范围面板、Windows 缺 WebView2 的提示；见下面的界面清点表
- 对应：[TASKS.md](../../TASKS.md)、[INVENTORY.md](../../INVENTORY.md#u5a)、[TASK_FILES.md](../../TASK_FILES.md#u5a)
- 评审页：claude.ai 私有页面（待发布）；源文件 [page.json](page.json)，效果图源文件 [src/gen.py](src/gen.py)
- 图片：v3 按 `v3.2.11` 代码还原（文字取自 `assets/translations/zh.json`，`tools/ui/strings.py` 列出）；封面和头像是示意图片
- 结果卡片：画的是 v3 的卡片原样（`lib/common/widgets/room_card.dart`，默认“标准”样式、`dense: true`）；**卡片的新样子跟 U.4a 走**，这里只定页面的排法

## 界面清点表

| 编号 | 界面 | 从哪打开 | 形态 | 状态 |
|---|---|---|---|---|
| U.5a-02 | 搜索页 | 手机首页右上角 `Remix.menu_search_line` 菜单“搜索直播”（`common_appbar_actions.dart:13-72`）；宽屏侧边栏 `CustomIcons.search`（`tablet_view.dart:129-136`） | 竖屏、横屏、宽屏 | 刚打开（键盘弹出）、搜索中、有结果（全部 / 单个平台）、还有平台没回来、部分平台失败、没有结果（单个平台可网页搜索）、结果都没开播（关了包含未开播）、选中的平台不能搜索、加载更多 / 已加载全部 |
| U.5a-03 | 排序小菜单 | 筛选行“综合：直播→观众→粉丝” | 同上 | 当前项 |
| — | 说明的展开 / 收起 | 说明行下“展开说明” | 同上 | 收起、展开 |
| — | 部分失败横幅 | 搜索后有平台失败 | 同上 | 全部（只有“关闭”）、单个平台（多“继续网页搜索”） |
| U.5a-01 | 系统组件缺失（WebView2） | Windows 每次打开搜索页时自动检查 | 宽屏 | — |
| — | 提示条（7 处） | 请输入关键字（2）、请先选择一个平台、{site} 暂无网页搜索入口、系统浏览器未打开…、无法打开下载链接…（2） | 全部 | — |
| — | 卡片长按菜单 | 长按或右键卡片 | — | 在 U.4a |
| v4 新增 | 搜索历史、识别到直播链接、搜索范围（说明面板 + 勾选对话框）、骨架卡片、失败说明卡 | M13.4、M13.16 | 竖屏、横屏、宽屏 | 这一版都保留，搜索范围的两个窗口合成一个 |

## v3 的样子

- **顶栏**：`AppBar(automaticallyImplyLeading: false)`，标题是输入框：提示“输入直播关键字”，圆角 24 描边、底色 surfaceContainerLow（主题 `filled`），左边返回 `Icons.arrow_back`，右边搜索 `Icons.search`（提示“搜索直播”）；自动获得焦点，回车搜索（`search_page.dart:20-48`）。获得焦点时边框换成主题的 focusedBorder：圆角 12、主色 1.5（`common/style/theme.dart:160-174`）。输入字 14 号（bodyLarge），提示 13 号、onSurfaceVariant 60%。
- **平台条**：高 56，横向列表，左右 12、间距 8；`ChoiceChip` 不带勾，选中描边主色、底色 secondaryContainer，未选描边 outlineVariant，字 13 号 500（`search_platform_strip.dart:63-95`）。第一项“全部”，其后是“平台显示”（`hotAreasList`）里的平台，默认 34 个：哔哩哔哩、斗鱼、虎牙、抖音、快手、网易CC、Twitch、Soop、YY、AcFun 直播、Picarto、TwitCasting、猫耳 FM、映客、克拉克拉、小红书、niconico、微博直播、SHOWROOM、CHZZK……网络（`core/sites.dart:217-280`、`:419-433`）。选中项自动滚到中间（`:49-61`）。
- **选项区**（跟着结果一起滚）：surfaceContainerLow 底，内边距 12/8/12/9（`search_page.dart:237-306`）。第一行横向可拖：`FilterChip` “包含未开播”（`Icons.offline_bolt_rounded`，默认开）→ 排序 `Chip`（`Icons.sort_rounded`，文字“综合：直播→观众→粉丝”，外面包 `PopupMenuButton`，四项：综合：直播→观众→粉丝、平台优先：按主页顺序、观众优先、粉丝优先，`:230-280`）→ 选了单个平台且有网页搜索时 `ActionChip` “继续网页搜索”（`Icons.open_in_browser_rounded`，`:281-288`）。第二行 `Icons.info_outline_rounded`（16、主色）+ 说明（12 号、一行省略），放不下时下面有“展开说明 / 收起”（`:309-370`）。说明文字：全部时由 `search_coverage_all_native`、`search_coverage_channel_lookup`、`search_coverage_room_lookup`、`search_coverage_weibo`、`search_coverage_showcase_snapshot` 拼成一段（`search_controller.dart:440-498`）；单个平台时一句，如“哔哩哔哩 原生搜索会返回直播中及部分未开播房间，可用上方开关筛选。”
- **状态**（`search_page.dart:185-222`，`AppStatusView`：圆 86、图标 42 主色 60%，标题 15 号 600，副标题 13 号，按钮 `TextButton.icon` 固定刷新图标）：搜索中是中间一个转圈；没搜过是 `travel_explore_rounded`“全平台原生搜索”+“输入关键词后汇总各平台直播间，可筛选未开播结果并切换综合、平台、观众或粉丝排序”；没结果是 `search_off_rounded`“没有找到直播间”或“结果里暂时没有正在直播的房间”，副标题是错误信息，按钮依次是“显示未开播结果 / 重试 / 继续网页搜索”。
- **进度和失败**：还有平台没回来时选项区下一条 2 像素进度条（`:84-85`）。部分失败：`MaterialBanner`“部分平台请求失败：{名字}”，按钮在下面：“继续网页搜索”（单个平台时）、“关闭”（`:89-103`、`search_controller.dart:304-306`）。
- **结果**：外边距 8、间距 8；列数 >1280 五列、>960 四列、>640 三列、其余两列（`:77`）；一行一行懒加载（`:104-141`）。底部：加载中转圈 /“加载更多结果”（`Icons.expand_more_rounded`）/“已加载全部结果”（`:142-164`）；离底 480 自动加载（`search_controller.dart:94-97`）。
- **卡片**（默认“标准”样式、`dense: true`）：白底（深色 `grey[900]`）、圆角 20；封面 16:9 圆角 20，右下角人数徽标（`people_alt` / `whatshot` / `visibility` / `favorite` + “1.2万”，11 号 700，黑 48% 底）；下面头像 34、标题 13 号 600、主播名 12 号 500 `grey[700]`；dense 时不显示平台标（`room_card.dart:1054-1229`、`:858-886`、`:1350-1411`）。
- **WebView2**：Windows 上 `onInit` 用 `reg query` 查两处注册表（`search_controller.dart:146-173`、`:616-629`），没装就弹对话框：`Icons.report_problem_rounded`（错误色）“系统组件缺失”，内容“您的 Windows 系统缺少网页核心组件 (WebView2 Runtime)。如果不安装，应用内的网页搜索功能将完全无法使用。\n\n是否立即前往微软官网下载安装？”，按钮“取消”“打开下载页”（主色实心），点外面不关（`:553-613`）。
- **按宽度分支**：只有列数（`:77`）和预加载距离 320 / 480（`:66`）；排法不变。
- **手势和键盘**：拖动结果收起键盘（`:67`）；回车搜索；iOS 回弹（`:7-12`）；电脑上鼠标不能拖动（`desktop_manager.dart:830-847`）。

## v3 的问题

| 编号 | 问题 | 位置 |
|---|---|---|
| P1 | 横屏手机上搜索框和平台条固定占 112（加状态栏 136），再加约 120 的选项区，结果只露出卡片上半截 | `search_page.dart:20-58`、`:83` |
| P2 | 宽屏搜索框横贯整个窗口；列数按固定宽度跳，拖窗口时卡片忽大忽小 | `search_page.dart:20-48`、`:77` |
| P3 | 选了单个平台时“继续网页搜索”被挤出屏幕右边 | `search_page.dart:248-290` |
| P4 | 排序按钮像标签，没有下拉箭头；文字太长 | `search_page.dart:261-280` |
| P5 | “全部”的说明是开发者口吻的一长段，展开后七八行把结果往下推 | `search_controller.dart:440-498`、`search_page.dart:309-370` |
| P6 | 搜索框获得焦点时圆角从 24 变 12 | `theme.dart:170-173`、`search_page.dart:27` |
| P7 | 空状态按钮永远是刷新图标，没结果时没有说明 | `app_status_view.dart`、`search_page.dart:197-219` |
| P8 | “全部”没配代理时每次都有一条列十几个名字的失败横幅 | `search_page.dart:89-103` |
| P9 | 等待时只有一个转圈，之后只有 2 像素细线，看不出还在等几个平台 | `search_page.dart:84-87`、`:186-188` |
| P10 | “全部”的结果卡片看不出平台（dense 不显示平台标） | `room_card.dart:1066-1067`（U.4a） |
| P11 | 回车键不是“搜索”，没有清除按钮 | `search_page.dart:22-48` |
| P12 | Windows 缺 WebView2 时每次打开搜索页都弹框，点外面关不掉 | `search_controller.dart:616-629` |
| P13 | 电脑上平台条鼠标拖不动、滚轮不能横滚（推断，待核对） | `desktop_manager.dart:830-847`、`search_platform_strip.dart:66-75` |

## v4 现在的偏差

M13.4、M13.16 已经加了：粘贴 / 清除按钮、识别直播链接直接进房、搜索历史、直播间 / 主播切换、搜索范围（说明面板 + 勾选对话框两个窗口）、平台芯片带标志、骨架卡片、“还有 N 个平台在搜索…”、失败说明卡、四种空状态。这一版全部保留；搜索范围的两个窗口合成一个；排法回到 v3（顶栏、平台条、筛选区），筛选行改成换行。

## 对比页（按章节导出）

- [说明](page/01-说明.jpg)
- [对比：竖屏](page/02-对比-竖屏.jpg)
- [刚打开](page/03-刚打开.jpg)
- [搜索中、失败、没有结果](page/04-搜索中-失败-没有结果.jpg)
- [排序菜单、搜索范围面板](page/05-排序菜单-搜索范围面板.jpg)
- [横屏手机](page/06-横屏手机.jpg)
- [宽屏](page/07-宽屏.jpg)
- [Windows 缺少 WebView2](page/08-Windows-缺少-WebView2.jpg)
- [v3 的问题](page/09-v3-的问题.jpg)
- [改了什么](page/10-改了什么.jpg)
- [每个按钮是干什么的、怎么用](page/11-每个按钮是干什么的-怎么用.jpg)
- [各客户端](page/12-各客户端.jpg)
- [需要你选的](page/13-需要你选的.jpg)
- [性能要点](page/14-性能要点.jpg)

## 单张图

| 图 | 内容 |
|---|---|
| [v3-phone.jpg](v3-phone.jpg)、[v4-phone.jpg](v4-phone.jpg)、[v4-phone-n.jpg](v4-phone-n.jpg) | 竖屏，全部平台：v3 / 新设计 / 按钮编号 |
| [v3-phone-platform.jpg](v3-phone-platform.jpg)、[v4-phone-platform.jpg](v4-phone-platform.jpg)、[v4-phone-platform-n.jpg](v4-phone-platform-n.jpg) | 竖屏，选了哔哩哔哩 |
| [v3-start.jpg](v3-start.jpg)、[v4-start.jpg](v4-start.jpg)、[v4-link.jpg](v4-link.jpg) | 刚打开（键盘弹出）；新设计粘贴了直播链接 |
| [v3-states.jpg](v3-states.jpg)、[v4-states.jpg](v4-states.jpg) | 搜索中、部分失败、没有结果、结果都没开播 |
| [v4-sort.jpg](v4-sort.jpg)、[v4-scope.jpg](v4-scope.jpg) | 排序小菜单、搜索范围面板 |
| [v3-land.jpg](v3-land.jpg)、[v4-land.jpg](v4-land.jpg)、[v4-land-scrolled.jpg](v4-land-scrolled.jpg) | 横屏手机 852×393；新设计往下滑以后 |
| [v3-wide.jpg](v3-wide.jpg)、[v4-wide.jpg](v4-wide.jpg)、[v4-wide-n.jpg](v4-wide-n.jpg) | 宽屏 1280×800 |
| [v3-webview2.jpg](v3-webview2.jpg)、[v4-webview2.jpg](v4-webview2.jpg) | Windows 缺 WebView2 |

## 改动（待确认）

| 编号 | 类型 | 内容 | 对应问题 |
|---|---|---|---|
| c1 | 保留 | 页面结构、平台条、包含未开播、四种排序、继续网页搜索、结果网格、自动加载、底部文字 | — |
| c2 | 修改 | 焦点时保持圆角 24；清除 / 粘贴（v4 已有）；回车键“搜索”；提示改短 | P6、P11 |
| c3 | 修改 | 筛选行放不下就换行 | P3 |
| c4 | 修改 | 排序按钮“综合 ⌄”，菜单当前项主色加勾 | P4 |
| c5 | 修改 | 一句通俗说明，最多两行，点开搜索范围面板 | P5 |
| c6 | 增强 | 搜索范围合成一个面板（国内 / 海外、勾选、每个平台能搜到什么） | — |
| c7 | 增强 | 直播间 / 主播切换（v4 已有） | — |
| c8 | 修改 | 骨架卡片、“还有 N 个平台在搜索…”（v4 已有） | P9 |
| c9 | 修改 | 失败说明卡（v4 已有） | P8 |
| c10 | 修改 | 四种空状态各有说明，按钮配对应图标（v4 已有） | P7 |
| c11 | 增强 | 搜索历史、识别直播链接（v4 已有） | — |
| c12 | 修改 | 横屏和宽屏搜索框和平台条一行；往下滑收起筛选行 | P1 |
| c13 | 修改 | 宽屏搜索框最宽 480；列数按计划书 5.3 节 | P2 |
| c14 | 修改 | 交 U.4a：“全部”的结果卡片要能看出平台 | P10 |
| c15 | 修改 | WebView2 提示只在点网页搜索时出现，可点外面关，多“用系统浏览器打开” | P12 |
| c16 | 修改 | 滚轮横滚平台条；Tab 顺序 | P13 |

## 按钮的作用和用法

| 编号 | 控件 | 怎么用 |
|---|---|---|
| 1 | 返回 | 离开搜索页；返回键、Esc 一样 |
| 2 | 搜索框 | 关键词、房间号或直播链接；回车搜索 |
| 3 | 清除 / 粘贴 | 有字时清空；没字时贴入剪贴板文字 |
| 4 | 搜索 | 按当前平台搜索；是直播链接时直接进房 |
| 5 | 平台 | 全部或单个平台；有字时换平台自动重搜 |
| 6 | 直播间 / 主播 | 搜直播间或主播 |
| 7 | 包含未开播 | 关掉只看在播（回放照常） |
| 8 | 排序 | 四种排序，小菜单 |
| 9 | 说明行 | 打开搜索范围面板 |
| 10 | 房间卡片 | 点进直播间；长按 / 右键卡片菜单（U.4a） |
| 11 | 继续网页搜索 | 单个平台有网页搜索时出现（U.5b） |
| 12 | 加载更多结果 | 滑到底自动加载，也可以点 |

## 各客户端

| 客户端 | 怎么做 |
|---|---|
| Android 手机 | 竖屏如图；横屏搜索框和平台条一行，筛选一行 |
| 宽屏（平板、Windows、Linux、iPad、macOS） | 同横屏排法；搜索框最宽 480；列数随宽度；搜索范围面板在右侧；悬停显示名称 |
| 电视 | 在 U.15c（pure_live_TV 搜索页也有直播间 / 主播和搜索历史）；内容和顺序对齐本页 |
| 苹果平台差异 | iPhone 同手机（滑动返回）；iPad、macOS 同宽屏，Cmd 快捷键；macOS 没有 WebView2 问题 |

## 待选（A 是建议）

- X1 往下滑时收起什么：A 所有尺寸一样收起筛选行（竖屏连平台条）；B 只在横屏手机收起。
- X2 排序按钮的字：A 短名“综合 ⌄”；B 照 v3 完整文字。
- X3 搜索范围：A 合成一个面板；B 照 v4 分开两个窗口。
- X4 缺 WebView2 时点网页搜索：A 弹对话框（取消、下载、用系统浏览器打开）；B 直接用系统浏览器打开。

## 拿不准的地方

- P13：电脑上鼠标滚轮能不能横滚平台条，是按 Flutter 默认行为和 `MyCustomScrollBehavior` 推断的，没在 Windows 上试。
- 选中的 `FilterChip` 带头像时，v3 是在图标上盖一个勾（带暗色底）；图里简化成勾。
- 排序菜单的当前项在 v3 有没有底色（`PopupMenuButton.initialValue`），图里没画 v3 的菜单。
- 横屏手机的状态栏按显示画（24 高）；全面屏手机横屏时可能藏起来。
- 新文字（排序短名“综合”、WebView2 对话框的新说明、搜索框新提示、排除平台后的说明）定稿后要加进翻译。
