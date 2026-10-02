# T01c.1 记录：通用组件（T01c.1）

- 日期：2026-10-02
- 任务单：[tasks/U01.md](brief.md)；设计：[docs/T01/T01c/T01c.1/README.md](README.md)（已确认，C1～C4 按 A）；[docs/TASKS.md](../../../TASKS.md) 第 7 节写给 T01c.1 的条目；组件说明见 [docs/T01/T01c/T01c.1/record.md](record.md)。
- 本地 worktree 任务：开始前合并了本地 master（T01d.1、T14c.1），提交前又合并了两次（T05h.2、T14c.2、T06d.3 没有冲突；T05g.2 在 `app_menu.dart` 的 `AppMenuButton` 参数处冲突，两边都保留）。没有出效果图（任务单写“不用”）；用临时 widget 测试把组件渲染成图片自己看过（脚本没留在仓库里）。
- 范围：组件在 `packages/live_ui`；各功能目录只换成统一组件；**没有改 `features/live_play/`**（T05h.2、T05g.2 在改）。维护者另交的两条（设置对话框按钮写明动作、剩下 3 个原生 `PopupMenuButton`）一并做了。

## 任务单逐条对照

| 编号 | 条目 | 做到 | 说明 |
|---|---|---|---|
| c1 | 照 T01c.1 设计逐条实现 | 完成 | 见下表“设计 c1～c21” |
| c2 | 第 7 节写给 T01c.1 的条目；检查各列表用 T14c.1 的刷新组件 | 完成 | 见下表“第 7 节”；没有 `RefreshIndicator`，能下拉刷新的列表（关注、热门、分区房间、分区、观看记录、备份、WebDAV）都用 `AppRefreshView` |
| c3 | 设置里的卡片预览改用 `LiveRoomCard` | 完成 | `features/settings/appearance_pages.dart`：预览就是列表里的卡片（高度用 `LiveRoomCardMetrics.extent`）；旧的 `RoomCard`（`live_ui`）没人用了，删掉 |
| c4 | 各页改用统一组件、删重复实现；`ui_baseline.json` 降到实际值 | 完成 | 删掉 3.x 的设置构建函数（`buildGroupTitle`、`buildModernCard`、`buildSwitchTile`、`buildTile`、`buildSliderTile`、`SectionTitle`、`MenuListTile`、`CardTile`、960 列宽）、旧 `RoomCard`、关注页的 `_CountTab`、扫码登录自己画的二维码卡片、列表外壳自己画的横幅和回到顶部；直接写的颜色图标数没变（基线不用改，合并后是 live_play 7、settings 25） |

## 设计 c1～c21

| 编号 | 做到 | 怎么做的 |
|---|---|---|
| c1 保留 | 完成 | 没改：状态出现的时机、加载样式、头像尺寸、二维码画法、一级标签样子、设置页结构、窄屏换行、翻页栏、滚动手感 |
| c2 一个状态组件 | 完成 | `AppStatusView` 加“受限”“离线”两种；`compact`（区块）、`isMini`（卡片）；画面上沿用 T05i.1 的 `VideoStateView`；列表的出错统一走 `loadErrorStatus`（受限 / 离线 / 出错，分区页也改用它） |
| c3 骨架和加载 | 完成 | 加载默认带一句“加载中...”；新 `StatusSkeleton`（行骨架）用在标签页，观看记录第一次加载改用卡片骨架（关注、热门、分区、搜索原来就是骨架） |
| c4 出错写人话、原文进“详情” | 完成 | `details` → 第二个按钮“详情”，整段可选中、可复制；列表、观看记录、标签、本地配置预览都把原文收进去 |
| c5 按钮 | 完成 | 第一个浅色实心、图标跟动作（受限是登录图标），第二个文字按钮；`busy` 转圈 |
| c6 圆圈实色、不弹跳；转圈看区域 | 完成（有偏差） | 圆圈 80 表面容器色、图标 40 主色不透明，去掉 1 秒弹性入场；转圈：区块和卡片 24、页面按窗口宽度 28 / 32（偏差见下） |
| c7 横屏左图右文 | 完成（有偏差） | 窗口高 <480 且宽大于高时横排（偏差见下） |
| c8 页顶横幅三种颜色 | 完成 | `StatusBanner`：列表的平台说明、移动流量提醒（“不再显示”+ ✕）、刷新失败（“重试”“详情”+ ✕，代替 `MaterialBanner`）、分区刷新失败、录制中心“开播检测关着” |
| c9 头像 | 完成 | `CommonAvatar`：加载中、首字、人形；`onTap` 时悬停、按下、焦点框（直播间顶栏的可点头像在 `live_play`，没接） |
| c10 计数 | 完成 | `CounterControl`/`CountButton` 描边 36、点击 48、上下限变灰、不可用变灰、← →；设置的计数行和弹幕面板的计数行都用它 |
| c11 二维码 | 完成 | `QrCodeWidget` 圆角 12、白底；`QrCodeCard` 状态盖在码上；哔哩哔哩扫码登录用它，设备同步的码也变圆角 |
| c12 标签栏 | 完成 | `TabLabel`（数量、角标、键盘焦点框）用在关注、热门、分区、关注分区；`SecondaryTabBar` 用在分区的分类；主题：悬停 / 按下只亮标签自己的圆角 8 块。“全部平台 ⌄”是 T07b.2 已做的 |
| c13 芯片一种 | 完成（直播间的除外） | `AppChip` + `chipTheme`：关注分组、搜索平台条、观看记录保留数量、设置的数字预设和窗口大小、弹幕观看模板、设置行的短选项；录制清晰度芯片在直播间，没动 |
| c14 开关一种 | 完成 | 已经没有 `activeThumbColor`；主题不覆盖开关颜色，测试锁住 |
| c15 设置配色 | 完成 | 最后几页（网络电视、账号、三方认证、平台显示）从 3.x 构建函数换成 `SettingsGroup` 和设置行 |
| c16 行标题 15、字重 C3 | 完成 | 设置行标题 600 → 400（C3 按 A）；`ListTile` 主题 15/400、说明 12 次要色、图标次要色、最少 56 高、选中次色容器 |
| c17 选择 ⌄、跳转 › | 完成 | `SettingsLinkRow(choice: true)`：所有点开单选对话框的行（设置里的选择行、主题模式、语言、关闭窗口、首选平台、录制的清晰度等 3 行、网络电视的节目单和同步间隔）；› 次要色 24 |
| c18 阅读内容最宽 720 | 完成 | 960 的列宽随旧构建函数删掉 |
| c19 下拉刷新文字 | T14c.1 已做 | 只检查（见任务单 c2） |
| c20 回到顶部点击区域 48 | 完成 | `ScrollJumpButtons`：看起来 40 圆形、点击 48、表面容器最高色、焦点框 |
| c21 悬停、焦点框、按下、禁用、进行中 | 完成 | 主题里的按钮（实心、描边、文字、图标、凸起）和芯片在用键盘时有 2 像素主色框；标签、头像、计数、回到顶部有焦点框；状态按钮有进行中 |

## 第 7 节写给 T01c.1 的条目

| 来源 | 条目 | 做到 | 说明 |
|---|---|---|---|
| T11a.4、T10 | 标题居中 | 完成（按维护者 2026-10-02 的决定改过） | 第 7 节原文“v3 所有标题栏居中”不对（见“根因”）。照 3.x 实际运行的样子：主题不设居中（Android 靠左）；3.x 自己写了居中的 6 页——录制中心、关注、分区、热门、观看记录（`PageTitle(centred: true)`，标题和条数都居中）、工具箱——用 live_ui 的共用常量 `centredPageTitle`；首页三个页的“建设中”占位跟着居中。其余页面（设置和设置类页面、网络电视、账号、三方认证、标签、版本、屏蔽、设备同步、WebDAV、多画面等）去掉了单独写的居中，`settingsPageAppBar` 默认改为靠左。第 7 节那条已改成实际情况 |
| T10a.3 | 设置行说明对比度 ≥4.5:1 | 完成 | 说明是 `onSurfaceVariant`（浅色、深色在 `surfaceContainerLow` 上都 ≥4.5:1，测试锁住），最多两行；还用 3.x 构建函数（提示色 75%、一行）的页面都换掉了 |
| T07c.4 | 开关打开时看不出滑块 | 完成 | 见 c14 |
| T07f.2～c | Esc 返回做成共用组件 | 完成 | `EscapeBack`（`CallbackShortcuts` + `FocusScope`，放在 `Scaffold` 外面）：搜索、网页搜索、观看记录改用它 |
| T09～T07 | 设置页都用 T09a.2 的设置行 | 完成 | 见 c15 |
| T01c.1 → T05g.1 | 观看模板芯片和录制清晰度芯片圆角 8 | 部分 | 观看模板完成；录制清晰度芯片在 `live_play`，留给 T05h.2/B07 |
| T01c.1 → tools/ui/mock | kit.css 的提示条反色等 | 没做 | 任务单范围外（“其他目录不改”） |

## 维护者另定的两条

1. 设置类对话框的主要按钮写明动作：主题颜色（原“确定”）、弹幕颜色、卡片间距、每页条数、Twitch 语言、录制目录、设置标签 → “保存”；网络电视文件路径 → “导入”；设备同步配对码 → 发送时“发送”、接收时“接收”。电视（`tv/`）的对话框不在这次范围。
2. 剩下 3 个原生 `PopupMenuButton` 换成小菜单：录制中心任务卡片的“⋮”（`AppMenuButton`；“开播自动录”一行末尾仍有开关，点这一行切换后菜单关闭，长按和右键卡片也从“⋮”处弹出）、字体管理的“⋮”、翻页栏的“每页条数”（`showAppMenu`，当前值主色加勾）。为此 `AppMenuEntry` 加了 `switchValue`，`AppMenuButton` 加了 `enabled`、`buttonKey` 和可从外面调用的 `show()`。

## 根因

- 3.x 和 v4 的通用组件是逐页长出来的：状态页只有加载 / 空 / 出错三种，离线、受限和出错一个样，原始英文报错直接显示，圆圈 15% 透明加弹跳；同类东西各页自己画（三种芯片、两套二维码、两种开关、三种行标题、两种 ›、刷新失败的 `MaterialBanner`）；3.x 的设置构建函数（组标题主色 65%、说明提示色 75% 一行、卡片 15% 透明、最宽 960）还留在网络电视、账号等几页。
- 标题居中：3.x 主题 `common/style/theme.dart:119` 有 `centerTitle: true`，但 `lib/main.dart:162-169` 用 `AppBarTheme(surfaceTintColor: …)` 整个替换了主题的标题栏样式，那一项从没生效；3.x 在 Android 上标题靠左，只有 `recorder_page`、`favorite_page`、`areas_page`、`history_page`、`popular_page`、`toolbox_page` 自己写了居中。第 7 节那条（“v3 所有标题栏居中”）是只看了主题文件得出的。

## 和设计不同的地方

- 转圈大小、横屏左图右文按**窗口**判断，不是按所在区域的约束：搜索页把状态放在 `SliverFillRemaining` 里，那里要先量子组件高度，`LayoutBuilder` 会报错（全量测试里 30 多条因此失败过）。区块里的状态由页面传 `compact`。
- “离线”的“连上网络后会自动刷新”：热门、分区房间、分区的离线状态接了网络变化（新 `networkChangesProvider`，桌面上为空），连上后自动重试；别的页面没有离线状态。
- 账号页的说明横幅（带链接、多段文字）、搜索的链接横幅保持原样，没有并进 `StatusBanner`。
- 录制中心的筛选（等宽分段，T08b.2）不是芯片，没改。
- 计数的“点数字输入”保留（T09a.5 的设置计数行），数字下有点线。

## 测试

- `packages/live_ui`：新 `test/components_test.dart` 26 条——状态页四种类型的文字、图标、圆圈颜色、没有入场动画、受限按钮；加载的一句话和转圈大小（393 宽 28、1280 宽 32、区块 24）；“详情”看全文、可选中、复制后提示；横屏 852×393 左图右文、区块不横排；区块 32 图标无圆圈；按钮进行中；深浅主题对比度；骨架无动画。横幅三种底色、按钮在文字下、✕ 48、三种底上文字 ≥4.5:1（深浅）；说明两行、点开全文。头像首字和人形、可点头像的键盘焦点框。计数框 36、半边 48、下限变灰、不可用变灰、← →。二维码每种状态码的位置不变、深色主题白底。标签数量、角标、键盘焦点框、主题叠层；二级标签样式。芯片 36 高（Android 密度）、圆角 8、选中勾、描边状态。设置行标题 15/400、说明 12 次要色 ≥4.5:1（深浅）、组标题 13/600 主色、⌄ 和 ›；开关处理中；开关主题不覆盖、滑块对比；列表行主题。回到顶部 400 后出现、48、点了回顶。`EscapeBack` 返回和页面自己的一步。焦点框只在键盘时、主题重建后相等（不触发主题动画）。另改了 `status_view_test`（出错默认“加载失败”）、`theme_test`（主题不设居中）、`widgets_test`（计数：图标、长按不多加一次、到上限停）、`room_card_test`（删掉旧 `RoomCard` 的用例）、`settings_row_test`（芯片查找）。live_ui 全部 **183 条**通过（合并 T05g.2 之后）；`dart format`、`flutter analyze` 无问题。
- `apps/pure_live`：按新设计改了断言——热门出错标题“加载失败”并有“详情”、翻页栏每页条数是小菜单且当前值打勾、搜索排序菜单里只有当前项打勾（平台芯片也有勾）、扫码登录码的键、分区的二级标签、观看记录的芯片查找；新增 8 处“主要按钮写明动作”的断言（录制目录、网络电视文件、配对码发送 / 接收、主题颜色、间距、每页条数、设置标签）。`flutter analyze` 无问题；全部 `flutter test` **829 条**通过（合并 master 到 T05g.2 之后）。
- 根目录 `python3 tools/gate/check_ui_structure.py` 通过。
- 没改 Android 原生代码，没有构建 APK。

## 改了哪些文件

- `packages/live_ui`：新增 `app_chip.dart`、`escape_back.dart`、`focus_ring.dart`、`jump_buttons.dart`、`status_banner.dart`、`tab_label.dart`、`test/components_test.dart`；改 `status_view.dart`、`avatar.dart`、`count_button.dart`、`qr_code_widget.dart`、`settings_row.dart`、`settings_tiles.dart`（只剩 720 的阅读列）、`room_card.dart`（只剩卡片数据）、`app_menu.dart`、`theme/live_theme.dart`、`theme/live_colors.dart`（提醒横幅底色）、`scope.dart`（新词）、`live_ui.dart`。
- `apps/pure_live/lib`：`app/network.dart`（网络变化）、`i18n/i18n.dart`；`shared/rooms/room_grid.dart`（出错状态、横幅、回到顶部）、`paging.dart`、`room_tags_dialog.dart`、`shared/danmaku/`（计数行、观看模板、颜色对话框）、`shared/under_construction.dart`；`features/` 下 account、area_rooms、areas、auth、favorite、history、hot_areas、iptv、popular、record_settings、recorder、remote_receiver、search、settings、shield、tags、toolbox、version。
- 翻译：`apps/pure_live/assets/translations/zh.json`、`en.json`。
- 文档：本记录、`docs/T01/T01c/T01c.1/record.md`、`docs/TASKS.md` 第 7 节标题居中那一条（按维护者要求更正）。

## 新设置和翻译键

- 没有新设置。
- 新翻译键：`details`（详情）、`refresh_load_failed`（加载失败，3.x 有这个键）、`status_offline_title`（没有网络连接）、`status_offline_subtitle`（检查网络后重试；连上网络后会自动刷新）。

## 要在 K90 上看的地方（Redmi K90 Pro Max，Android 17，120Hz）

1. 标题：录制中心、观看记录（标题和条数一起居中）、工具箱、首页三个底部页的标题居中；设置、录制设置、设备同步、网络电视、账号等其他页面标题靠左（和 3.x 在手机上一样）。
2. 浅色主题下设置 → 视频：每行说明是深灰色、清楚（不再是浅灰一行省略），最多两行；行标题不加粗；“首选清晰度”等选择行右边是“原画 ⌄”，“竖屏直播适配”等跳转行是 ›。
3. 设置里任意开关打开：蓝色底、白色滑块，看得见滑块；“后台播放”这类保存时有转圈的行，转圈在开关左边、开关变灰。
4. 关闭网络后打开热门：显示“没有网络连接 / 检查网络后重试；连上网络后会自动刷新”和“重试”；打开网络后自动加载出来。
5. 热门列表滑下去再刷新失败（如开飞行模式后下拉）：卡片上方出现红色横幅“刷新失败：…”，下面“重试”“详情”，右边 ✕；点“详情”看到原始报错，可复制。
6. 关注页：分组芯片 36 高、选中有勾、浅蓝底；状态标签后面的数字；回到顶部按钮滑下去出现，好点。
7. 弹幕设置（设置里或直播间）：顶部留白等计数是描边样式，到 0 时“−”变灰；“合并相同弹幕”关着时合并时间那一行变灰。
8. 账号 → 哔哩哔哩扫码：码在浅色卡片里、圆角；过期时“二维码已失效 / 刷新二维码”盖在码上，码的位置不动。
9. 录制中心任务卡片“⋮”（或长按卡片）：小菜单，“开播自动录”一行末尾有开关，点了切换并关闭菜单；“删除任务”红色在分隔线下。
10. 横屏手机打开一个出错的列表（例如关网后热门）：状态左图右文，不用滚动。

## 需要维护者决定的

已定（维护者 2026-10-02）：设置行标题保持 400（T01c.1 C3 选 A）；标题居中照 3.x 实际运行的样子（见第 7 节一表）；状态页按窗口大小判断，接受。

还剩：第 7 节里“T01c.1 → tools/ui/mock”的 kit.css 两处工具修改没做（不在可改目录）。另外 T07g.2 的设计把观看记录的标题画成靠左，这次按维护者的决定居中了。

## 可能和别的任务冲突的文件

- `packages/live_ui/lib/src/theme/live_theme.dart`：主题新加了标签叠层、芯片主题、按钮焦点框（标题对齐不变，仍是 3.x 的样子），`ListTile` 主题改成 15/400、图标次要色、选中次色容器——**直播间里的 `ListTile`、芯片、按钮也会跟着变**（T05h.2、T05g.2 合并后请看一眼长按弹幕面板、切换直播间、录制面板）。
- `packages/live_ui/lib/src/scope.dart`、`live_ui.dart`：加了词和导出（别的任务也常加）。
- `packages/live_ui/lib/src/widgets/settings_row.dart`、`count_button.dart`、`status_view.dart`、`app_menu.dart`：U.6x、T05g.2 若改设置行、计数、状态页或小菜单会碰到。
- `apps/pure_live/lib/shared/rooms/room_grid.dart`、`shared/danmaku/setting_rows.dart`、`danmaku_settings_content.dart`：直播间也用（弹幕面板、列表外壳）。
- `features/areas/`、`features/favorite/`、`features/popular/`：T14c.2 改过同文件的 physics 行，这次合并没有冲突。

## 留给直播间（T05h.2、T05g.2）的

- `features/live_play/danmaku/chat_panel.dart` 的 `_TabLabel` 可换成 `TabLabel`（数量、角标、键盘焦点框）。
- 录制清晰度芯片换成 `AppChip`（T01c.1 → T05g.1：圆角 8）。
- 直播间顶栏的可点头像可以用 `CommonAvatar(onTap:, tooltip:)`（悬停、按下、焦点框）。
- 直播间里的状态（弹幕列表空、节目单）用 `AppStatusView(compact: true)`。
