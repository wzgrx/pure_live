# U.2e 直播间的四个标签：设计（第 1 版）

- 状态：已确认（2026-10-01，用户：“重构评审全部通过，你设计的挺好的，后续全部通过”；“需要你选的”按建议）。原状态：待确认（第 1 版，2026-10-01）
- 范围：直播间画面和信息行下面的四个标签（宽屏时在右侧聊天栏里）：弹幕列表、醒目留言、弹幕设置、屏蔽管理，以及它们的各种状态
- 对应：[TASKS.md](../../TASKS.md)、[INVENTORY.md](../../INVENTORY.md#u2e)、[TASK_FILES.md](../../TASK_FILES.md#u2e)
- 已确认、这里不再改的：弹幕紧凑行和“卡片”样式设置、系统消息小标签（[U.2a](../U.2a/README.md) 选择 A）；长按弹幕面板、弹幕设置的内容和分组（[U.2f](../U.2f/README.md)）。弹幕设置标签显示的就是 U.2f 的那个组件
- 评审页：claude.ai 私有页面（只有项目所有者能打开）；源文件 [page.json](page.json)，效果图源文件 [src/gen.py](src/gen.py)
- 图片：v3 按 `v3.2.11` 代码还原（文字取自 `assets/translations/zh.json`）；画面、头像、醒目留言的人和颜色是示意数据（颜色用哔哩哔哩醒目留言的档位色）

## 界面清点表

| 编号 | 界面 | 从哪打开 | 形态 | 状态 |
|---|---|---|---|---|
| U.2e-01 | 四个标签（`DanmakuTabView`、`DanmakuSectionTabBar`） | 直播间画面和信息行下面；宽屏在右侧聊天栏 | 竖屏、宽屏、手机横屏（不是全屏时） | 加载中（整块转圈）；醒目留言条数；详情打开期间的新弹幕数（U.2a）；栏窄时条数角标 |
| U.2e-02 | 弹幕列表（`DanmakuListView`） | 第 1 个标签 | 同上 | 跟随最新；往上翻（“N 条新弹幕”）；还没有弹幕：连接中、连上了没人说话、连接失败、平台不提供；“显示弹幕”关闭；本地互动输入框；卡片样式；深色 |
| U.2e-03 | 醒目留言（`SuperChatPage`、`SuperChatCard`） | 第 2 个标签 | 同上 | 有（每张倒计时、到点移除）；空；平台不提供；窄栏或大字体时卡片头部竖排 |
| U.2e-04 | 弹幕设置标签（`DanmakuSettingsPage` → `DanmakuSettingsContent` + `PipDanmakuSettingsSection`） | 第 3 个标签；横屏全屏时用 U.2f 的右侧面板 | 同上 | 同 U.2f；另有小窗弹幕开 / 关、保留平台颜色开 / 关 |
| U.2e-05 | 屏蔽管理（`KeywordBlockPage`） | 第 4 个标签 | 同上 | 有内容；空；空关键词；重复关键词；删除后撤销；相似过滤开 / 关 |
| U.2e-06 | 提示条 | 双击复制、发送本地弹幕、添加空关键词、删除 | — | “已复制到剪贴板”“发送成功，将在 2 秒后同步显示”“请输入关键词”；新：“已移除‘…’ · 撤销” |
| 相关 | 长按弹幕面板、屏蔽关键词输入框 | 长按或右键弹幕 | — | U.2f 已定 |

## v3 的样子

文件都在 `lib/modules/live_play/` 下（另注的除外）。

**标签**（`widgets/danmaku/danmaku_tab.dart`）
- 房间详情或播放器还没好时，整块是 `AppStatusView(loading)`（:15-17）。
- `TabBar` 四个等宽标签（`isScrollable: false`、`TabAlignment.fill`、标签内边距 4，:65-73），文字“弹幕列表、醒目留言、弹幕设置、屏蔽管理”（`live_play_controller.dart:73`）；主题里标签是 `titleMedium`（15），选中 600、主色，未选中 400、`onSurfaceVariant` 80%，指示条和文字一样宽（`common/style/theme.dart:122-129`）。内容可左右滑（:24-26）。
- 网络电视和房间加载失败时整块不显示（`widgets/layout/live_play_content.dart:593-595`）；全屏时不显示（:597-599）。

**弹幕列表**（`widgets/danmaku/danmaku_list_view.dart`）
- “显示弹幕”（设置 → 视频，`modules/settings/pages/video_settings_page.dart:266-271`）关闭时，列表换成居中的一句“全局弹幕显示已关闭；仍可切换到“弹幕设置”调整主播放器和小窗弹幕。”（13 号，内边距 24，`danmaku_tab.dart:28-35`）。
- 列表倒序（新的在下），内边距 10/6，80 毫秒一批更新（:65、:148-153），最多 500 条（`live_play_controller.dart:97`），行组件缓存 160 个（:76）。列表本身宽于 680 时整块加圆角 10 和阴影（:291-305）；分栏时聊天栏最宽 400，所以平时看不到。
- 每条（`DanmakuItem`，:446-531）：外边距 8/4，底色白 72%（深色 `cardColor` 65%），圆角 10，0.5 细边；左边 8 像素圆点（弹幕颜色，白或黑时用黑或白）；“用户名: ”14 号 700 + 内容 14 号 500、行高 1.45，表情是图片（字号 1.25 倍）。长按、右键打开长按弹幕面板（:501-502），双击复制“用户名: 内容”并提示“已复制到剪贴板”（:452-455、:503）。
- 系统消息也是一条普通卡片，用户名“系统消息”（`live_play_controller.dart:629-637`）：“开始连接弹幕服务器”“弹幕服务器连接正常”“弹幕服务器连接超时，已自动释放并可重新连接”（`controllers/danmaku_controller.dart:172`、`:244`）。网易 CC 和网络电视不连弹幕（:330）。
- 手指一碰就停止跟随（:313-325、:240-246）；右下角 `FilledButton.icon`：`Icons.arrow_downward_rounded` 18 + “{count} 条新弹幕，点击回到底部”或“回到底部”，600 字重，主色 92% 底、**固定白字**，圆角 14，内边距 14/10，离右下各 12（:352-382）。只有点它才恢复跟随（:248-252）。
- 开了本地互动时底部一栏（`surfaceContainerLow`，内边距 10/8/8/8）：圆角 22 的输入框，左边 `Icons.auto_awesome_rounded` 19（本地弹幕样式），提示“发送一条本地字幕”；右边 `IconButton.filled` + `Icons.send_rounded`（:386-436）；发送后提示“发送成功，将在 2 秒后同步显示”（:265）。

**醒目留言**（`pages/super_chat_page.dart`、`widgets/layout/super_chat_card.dart`）
- 空：`Remix.chat_smile_3_line` 42 主色 → 16 → “暂无醒目留言”（18 号 700）→ 8 → “当前直播间的付费留言会显示在这里。”（13 号次要色），内边距 24/48（:12-34）。
- 列表内边距 8，每张下面 8（:39-52），按到达顺序，新的在下（`live_play_controller.dart:365-376`），到点自动移除（:334-350）。
- 卡片：外边距 10/6，圆角 12，黑 8% 细边，黑 10% 阴影（模糊 10、下移 3）（:112-126）。头部底色是平台给的颜色，没有时 `primaryContainer`；内容底色是平台的第二个颜色，没有时 `surfaceContainerHighest`（:105-106）。头部内边距 12/9：头像 44（1.8 的圈，`Remix.user_2_fill` 兜底）→ 10 → 名字 14/600 + 5 + 价格（`Remix.money_cny_circle_fill` 16 黄 + “￥30”15/700 等宽）→ 右侧“SC”小块（`Remix.vip_diamond_fill` 11 黄 + “SC”12/700）和倒计时（`Remix.time_line` 13 + “00:42”12/500 等宽）（:142-301）。宽度 <280 或字体放大时头部竖排（:153-185）。内容内边距 14/10/14/13，14 号行高 1.5，可选中，双击复制（:308-325）。字色按底色亮度 0.55 分界选黑白（:79-85）。每张卡片自己一个每秒计时器（:44-69）。
- 平台：哔哩哔哩、虎牙有接口和弹幕流，斗鱼从弹幕流来（`core/danmaku/bilibili_danmaku.dart`、`huya_danmaku.dart`、`douyu_danmaku.dart`）；其余平台都没有（`core/interface/live_site.dart:256-258` 默认返回空）。

**弹幕设置标签**（`pages/danmaku_settings_page.dart`）
- 标签里用 `DanmakuSettingsContent(embedded: false, includePipSettings: true)`（:9-16、:25-30）；画面上的面板用 `embedded: true, includePipSettings: false`（`widgets/video_player/video_controller_panel.dart:2206`）。
- 不嵌入的样子：整页内边距 16/12（:194-198）；组标题 12 号粗体主色 65%（`common/widgets/widget_extensions.dart:21-36`）+ 8；卡片是 `surfaceContainerHighest` 15% 底、圆角 20（`widget_extensions.dart:101-111`）。模板芯片 `ChoiceChip`（选中主色底白字 + 勾，未选中 `surfaceContainerHighest` 底；“均衡”未选中时 `Icons.auto_awesome_rounded`），“保存当前模板”“恢复已保存模板”是 48 高的描边按钮（:97-157）；说明两行 12 号（:160-168）。
- 分组和设置项与 U.2f 第四版清单一致（`:202-413`），之后多一节 **小窗弹幕**（:416-418 → `modules/settings/pages/pip_danmaku_settings_page.dart:153-321`）：小窗显示弹幕；开着时再有 纯文字模式（隐藏表情）、根据小窗尺寸自动缩放、保留平台弹幕颜色、统一弹幕颜色（关掉保留颜色时才有，色块 + “#FFFFFFFF”）、字体大小（8–24，显示“12.0”）、字体粗细、滚动速度（像素/秒）（20–400，显示“90”）、透明度（10–100%）、画面顶部占用高度（10–100%）、最大同时显示数量（1–20 计数）、发送间隔（0.05–2，显示“0.35s”）、弹幕帧率 · 跟随界面刷新率策略（说明“开启：小窗弹幕跟随同一全局档位；关闭：小窗使用独立手动帧率，不影响主画面。”），关掉时手动帧率 15–240。默认值见 `danmaku_settings_controller.dart:17-31`。

**屏蔽管理**（`pages/keyword_block_page.dart`）
- 内边距 16/12/16/0，从上到下：**平台弹幕过滤**（过滤斗鱼疑似自动弹幕 + 说明“开启后按启发式标记隐藏疑似自动或活动弹幕，也可能隐藏普通聊天”，默认关）→ 20 → **相似弹幕过滤**（启用相似弹幕过滤，默认关；开着时 相似度阈值 50–100%（85）、缓存时间 1–60 秒（3）、最大缓存数量 20–1000（100））→ 20 → **弹幕关键词屏蔽**（输入框：提示“请输入关键词”，最多 40 字带计数，`surfaceContainerLow` 底、圆角 12，聚焦时主色 2 像素边；右边 `Remix.add_circle_line`，提示“添加”）（:69-148、:198-226）。
- 下面两节：“已添加{count}个关键词”“已屏蔽用户（{count}）”（15 号 600 次要色），每项一行：`surfaceContainerLow` 圆角 12，左 `Icons.filter_alt_off_rounded` / `Icons.person_off_rounded` 19 主色，右 `Remix.close_line` 18，悬停提示“点击移除: 词”（:151-274）。没有内容时整节不显示（:160-161）。
- 添加：空的提示“请输入关键词”；重复的 `addShieldList` 返回 false，界面不理会，照样清空（:43-55、`common/services/settings/favorite_room_controller.dart:446-455`）。删除立即生效（:176-186）。
- 设置里另有一页“弹幕关键词屏蔽”（`modules/shield/danmu_shield_page.dart`，U.12d），同一份关键词列表，用一行排多个的小标签，点整个标签就删除（:76-125），有空状态“暂无屏蔽关键词”。

**宽度分支**：只有 `useEdgeToEdgeDanmakuList(width <= 680)`（列表 :32）和醒目留言头部 `<280` 竖排；宽屏时整块放进右侧聊天栏（`live_play_content.dart` 的左右分栏，宽 34%、300–400）。

**手势和快捷键**：标签左右滑；弹幕长按、右键、双击；醒目留言内容双击、可选中；输入框回车提交。没有专门的快捷键。

## v4 现在的偏差（`apps/pure_live/lib/features/live_play/danmaku/chat_panel.dart`）

- 弹幕设置标签最上面是“在聊天列表显示礼物”“弹幕列表样式”，后面是 v4 自己的设置面板（`shared/danmaku/danmaku_settings.dart`），混进了相似过滤、平台过滤，**没有小窗弹幕**。
- 屏蔽管理只有输入框和两组小标签，**没有平台弹幕过滤和相似弹幕过滤**；点标签本身就删除，没有撤销。
- 醒目留言新的在上（和这里的建议一致），卡片是 `Card` + `ListTile`，没有“SC”和价格图标。
- 弹幕列表已按 U.2a 改成紧凑行和系统消息小标签。

## 各版的经过

| 版 | 内容 | 用户意见 |
|---|---|---|
| 第 1 版 | 四个标签的对比、各种状态、按钮用法、四处待选 | 待评审 |

## 对比页（按章节导出）

- [说明](page/01-说明.jpg)
- [对比：弹幕列表](page/02-对比-弹幕列表.jpg)
- [弹幕列表的各种状态](page/03-弹幕列表的各种状态.jpg)
- [深色主题下的“N 条新弹幕”](page/04-深色主题下的-N-条新弹幕.jpg)
- [对比：醒目留言](page/05-对比-醒目留言.jpg)
- [对比：弹幕设置标签](page/06-对比-弹幕设置标签.jpg)
- [对比：屏蔽管理](page/07-对比-屏蔽管理.jpg)
- [屏蔽管理的各种状态](page/08-屏蔽管理的各种状态.jpg)
- [对比：宽屏和手机横屏](page/09-对比-宽屏和手机横屏.jpg)
- [v3 的问题](page/10-v3-的问题.jpg)
- [改了什么](page/11-改了什么.jpg)
- [每个按钮是干什么的、怎么用](page/12-每个按钮是干什么的-怎么用.jpg)
- [各客户端](page/13-各客户端.jpg)
- [需要你选的](page/14-需要你选的.jpg)
- [性能要点](page/15-性能要点.jpg)

## 单张图

| 图 | 内容 |
|---|---|
| [v3-list.jpg](v3-list.jpg)、[v4-list.jpg](v4-list.jpg)、[v4-list-n.jpg](v4-list-n.jpg) | 弹幕列表（往上翻、开着本地互动）：v3 / 新设计 / 编号 |
| [v3-list-dark.jpg](v3-list-dark.jpg)、[v4-list-dark.jpg](v4-list-dark.jpg) | 同上，深色主题（“N 条新弹幕”按钮的对比度） |
| [v3-list-states.jpg](v3-list-states.jpg)、[v4-list-states.jpg](v4-list-states.jpg)、[v4-list-states-n.jpg](v4-list-states-n.jpg) | 弹幕列表的状态：连接中、没人说话、连接失败、平台不提供、“显示弹幕”关闭、有第一条以后、卡片样式 |
| [v3-sc.jpg](v3-sc.jpg)、[v4-sc.jpg](v4-sc.jpg)、[v4-sc-n.jpg](v4-sc-n.jpg) | 醒目留言（三张） |
| [v3-sc-empty.jpg](v3-sc-empty.jpg)、[v4-sc-states.jpg](v4-sc-states.jpg) | 醒目留言：空 / 空、平台不提供、窄栏竖排 |
| [v3-settings.jpg](v3-settings.jpg)、[v4-settings.jpg](v4-settings.jpg) | 弹幕设置标签第一屏 |
| [v3-settings-full.jpg](v3-settings-full.jpg)、[v4-settings-full.jpg](v4-settings-full.jpg)、[v4-settings-full-n.jpg](v4-settings-full-n.jpg) | 弹幕设置标签完整内容（含小窗弹幕） |
| [v3-block.jpg](v3-block.jpg)、[v4-block.jpg](v4-block.jpg)、[v4-block-n.jpg](v4-block-n.jpg) | 屏蔽管理第一屏 |
| [v3-block-full.jpg](v3-block-full.jpg)、[v4-block-full.jpg](v4-block-full.jpg)、[v4-block-full-n.jpg](v4-block-full-n.jpg) | 屏蔽管理完整内容（相似过滤打开） |
| [v4-block-states.jpg](v4-block-states.jpg)、[v4-block-states-n.jpg](v4-block-states-n.jpg) | 屏蔽管理：空、重复关键词、删除后撤销 |
| [v3-wide.jpg](v3-wide.jpg)、[v4-wide.jpg](v4-wide.jpg)、[v4-wide-block.jpg](v4-wide-block.jpg) | 宽屏 1280×800：醒目留言、屏蔽管理 |
| [v3-land.jpg](v3-land.jpg)、[v4-land.jpg](v4-land.jpg) | 手机横屏不是全屏 852×393：弹幕列表 |

## v3 的问题

| 编号 | 问题 | 位置 |
|---|---|---|
| L1 | 列表还没有弹幕时看不出状态（连接中、没人说话、连接失败、网易 CC 不连弹幕都一样）；失败后没有“重新连接” | `danmaku_list_view.dart:327-349`、`controllers/danmaku_controller.dart:172`、`:330` |
| L2 | “显示弹幕”关闭时只有一句话，没有按钮，也不说开关在哪 | `danmaku_tab.dart:28-35`、`settings/pages/video_settings_page.dart:266-271` |
| L3 | “N 条新弹幕”固定白字，深色主题下约 1.7:1 | `danmaku_list_view.dart:363-367` |
| S1 | 新的醒目留言在最下面 | `live_play_controller.dart:365-369`、`super_chat_page.dart:37-52` |
| S2 | 卡片字色按亮度 0.55 分界，￥100 档金黄底配白字约 1.9:1 | `super_chat_card.dart:79-85` |
| S3 | 平台不提供醒目留言时也说“会显示在这里” | `super_chat_page.dart:12-34`、`core/site/douyin/douyin_site.dart:867-869` |
| S4 | 每张卡片一个每秒计时器；卡片带阴影 | `super_chat_card.dart:44-50`、`:118-125` |
| D1 | 弹幕设置标签和画面上的面板两种样子、两套内容 | `danmaku_settings_page.dart:19-30`、`:67-86`、`:416-420`、`video_controller_panel.dart:2206` |
| D2 | 小窗弹幕数值不带单位 | `settings/pages/pip_danmaku_settings_page.dart:207`、`:235`、`:281` |
| K1 | 关键词输入框在两组过滤开关下面，键盘弹出后几乎看不到列表 | `keyword_block_page.dart:73-146` |
| K2 | 重复关键词没反应，还清空了输入框 | `keyword_block_page.dart:43-55`、`favorite_room_controller.dart:446-455` |
| K3 | 没有关键词、没有屏蔽用户时整节不显示 | `keyword_block_page.dart:160-161` |
| K4 | 一个关键词一整行；设置页里同一份列表是小标签 | `keyword_block_page.dart:246-274`、`shield/danmu_shield_page.dart:76-125` |
| K5 | 删除没有撤销 | `keyword_block_page.dart:176-186` |
| K6 | 相似过滤关闭时滑块消失（U.2f 定的是变灰） | `keyword_block_page.dart:97` |

## 改动（待确认）

| 编号 | 类型 | 内容 | 对应问题 |
|---|---|---|---|
| c1 | 保留 | 标签和顺序、左右滑；长按 / 右键 / 双击弹幕；“N 条新弹幕”；本地互动输入框；醒目留言卡片结构和空状态；屏蔽管理全部设置项和范围 | — |
| c2 | 增强 | 还没有聊天弹幕时中间显示状态：连接中、还没有弹幕、连接超时 +“重新连接”、平台不提供 | L1 |
| c3 | 增强 | “显示弹幕”关闭时加“开启弹幕显示”按钮 | L2 |
| c4 | 修改 | “N 条新弹幕”用主色上的文字色 | L3 |
| c5 | 修改 | 醒目留言新的在上（E2） | S1 |
| c6 | 修改 | 卡片字色按对比度选；去阴影；共用一个倒计时 | S2、S4 |
| c7 | 增强 | 平台不提供醒目留言时写明 | S3 |
| c8 | 修改 | 弹幕设置标签用 U.2f 组件，去掉标题栏和关闭，“改动立即生效”放第一节右边 | D1 |
| c9 | 增强 | 组件末尾加“弹幕列表”“小窗弹幕”两组（E1） | D1 |
| c10 | 修改 | 小窗数值带单位；统一弹幕颜色变灰不消失 | D2 |
| c11 | 修改 | 屏蔽管理顺序：关键词 → 已屏蔽用户 → 平台过滤 → 相似过滤（E3） | K1 |
| c12 | 修改 | 关键词和用户用小标签，只有 × 删除，触控区 48 | K4 |
| c13 | 增强 | 重复关键词在输入框下面提示，不清空 | K2 |
| c14 | 增强 | 两节为空时显示说明 | K3 |
| c15 | 增强 | 删除后提示条可撤销（4 秒） | K5 |
| c16 | 修改 | 相似过滤关闭时滑块变灰；行样式和弹幕设置组件统一 | K6 |
| c17 | 保留 | 宽屏、横屏同一套标签和内容；栏窄时条数角标、信息行只留在线和时长 | — |

新加的文字（开发时加进翻译）：“还没有弹幕”“弹幕服务器连接正常，新弹幕会显示在这里”“弹幕服务器连接超时”“已自动释放，可以重新连接”“重新连接”“{平台}的直播间没有弹幕”“醒目留言、弹幕设置、屏蔽管理照常可用”“开启弹幕显示”“{平台}的直播间没有醒目留言。”“‘{词}’已经在屏蔽列表里”“已移除‘{词}’”“撤销”。其余文字都用 v3 或 v4 已有的键。

## 按钮的作用和用法

| 编号 | 控件 | 怎么用 |
|---|---|---|
| 1 | 四个标签 | 点或左右滑切换；“醒目留言”带条数 |
| 2 | 弹幕行 | 长按、右键：长按弹幕面板（U.2f）；双击复制 |
| 3 | N 条新弹幕 | 往上翻时出现；点了回到最新并继续跟随 |
| 4 | 本地弹幕样式 | 改本地弹幕样式（开了本地互动才有） |
| 5 | 本地字幕输入框 | 输入后回车或点发送 |
| 6 | 发送 | 发送本地弹幕 |
| 7 | 开启弹幕显示（新） | 打开全局“显示弹幕” |
| 8 | 重新连接（新） | 重新连接弹幕服务器 |
| 9 | 醒目留言内容 | 可选中，双击复制 |
| 10 | 弹幕列表样式 | 紧凑 / 卡片（U.2a） |
| 11 | 在聊天列表显示礼物 | v4 已有 |
| 12 | 小窗显示弹幕 | 关闭时其余小窗项收起；其他弹幕设置项同 U.2f |
| 13 | 关键词输入框 | 最多 40 字，回车也能添加 |
| 14 | 添加 | 加入关键词，列表里含这个词的弹幕马上去掉 |
| 15 | 关键词的 × | 删除，可撤销；电脑悬停“点击移除: 词” |
| 16 | 已屏蔽用户的 × | 取消屏蔽，可撤销 |
| 17 | 过滤斗鱼疑似自动弹幕 | 开关 |
| 18 | 启用相似弹幕过滤 | 开关；三个滑块关闭时变灰 |
| 19 | 撤销（新） | 删除后 4 秒内恢复 |

## 各客户端

| 客户端 | 怎么做 |
|---|---|
| Android 手机 | 竖屏在画面和信息行下面；横屏全屏时没有这四个标签（照 v3），弹幕设置用 U.2f 的右侧面板（同一组件） |
| 宽屏（平板、Windows、Linux、iPad、macOS） | 在右侧聊天栏（U.2d），内容和操作一样；栏 <340 时条数角标；电脑右键 = 长按，悬停有说明，回车添加 |
| 电视 | 没有弹幕列表和醒目留言（pure_live_TV 也没有）；弹幕设置和“弹幕关键词过滤”在播放设置侧面板，同一组件的电视样式，U.15d 出图 |
| 苹果平台差异 | iPhone：键盘弹出时输入框保持可见，避开主屏指示条；iPad、macOS 同宽屏 |

## 待选（A 是建议）

- E1 “弹幕列表”“小窗弹幕”两组：A 放在组件末尾，标签和画面上的面板完全一样；B 只放在标签里，面板保持 U.2f 定稿。
- E2 醒目留言顺序：A 新的在上；B 照 v3 新的在下。
- E3 屏蔽管理顺序：A 关键词、已屏蔽用户在前；B 照 v3 过滤开关在前。
- E4 设置里的“弹幕关键词屏蔽”页（U.12d）：A 用这里的同一个组件；B U.12d 另外设计。

## 拿不准的地方

1. 手机横屏但不是全屏（852×393）时的排法属于 U.2c、U.2d；这里照 U.2d 第 1 版（宽度 840 以上分栏）出图，只确认标签区在 300 宽的矮栏里能用（信息行放不下热度时只留在线和时长，这一条也要 U.2d 确认）。
2. 哪些平台提供醒目留言：按 v3 代码只有哔哩哔哩、虎牙（接口和弹幕流）、斗鱼（弹幕流）；其余平台的 `getSuperChatMessage` 返回空（默认实现 `core/interface/live_site.dart:256-258`），弹幕流里也没有醒目留言。做“平台不提供”的说明需要一个平台能力标记，现在没有。
3. 网易 CC 不连弹幕（`danmaku_controller.dart:330`）是平台没有弹幕还是还没接，文字写“没有弹幕”是否准确。
4. v3 标签里模板芯片和描边按钮的字号按主题推算是 13（`labelLarge` = 正文中号），没有真机截图核对。
5. “小窗显示弹幕”关闭时子项收起（v3 同），没有照 U.2f 的“变灰不消失”：一组 11 项全变灰太长。如果要统一成变灰，在评审时说。
6. “在聊天列表显示礼物”是 v4 加的（v3 没有），这里随 E1 放在“弹幕列表”一组。

## 需要改工具的地方

- 无。（`render.py` 的 `--dark` 只能整体加，这次对两张图单独跑了一次。）
