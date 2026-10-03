# A07.9 已合并界面任务的收尾：说明（没有新设计，已完成）

- 状态：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 范围：四条“跨任务待同步”：①投屏只在 Android（A07.4、A07.5 → 直播间菜单）；②多画面的点击区域补到 48（A13.2）；③账号页内退出和列表上的退出同一套文字（A12.1、A12.2）；④平台名统一（SOOP、网易CC）。后两条不在直播间，当时一起做，记在这里
- 来源：当时的任务清单第 7 节“跨任务待同步”里的四条；设计都已确认（2026-10-01“后续全部通过”），没有新的选择题
- 对应：直播间菜单在 [A07.4](../A07.4-横屏全屏/README.md)“各客户端”（投屏只有 Android）、[A07.5](../A07.5-宽屏左右分栏/README.md) 按钮表第 7 条；多画面在 [A13.2](../../A13-网络电视和多画面界面/A13.2-多画面/README.md)；账号在 [A12.1](../../A12-账号和数据界面/README.md)；[specs/UI.md](../../../specs/UI.md) 第 4 节（投屏只有 Android）、第 5.4 节（点击区域至少 48×48，间距至少 8）、第 3 节第 6 条（同一件事一套文字）
- 评审页：无（没有新设计，照已确认的设计收尾）
- 旧编号：U.2-followups、T05a.3

## 界面清点表

| 编号 | 界面 | 从哪打开 | 形态 | 状态 |
|---|---|---|---|---|
| A07.9-01 | 直播间右上角菜单、全屏上栏的投屏按钮 | 顶栏四宫格；全屏上栏 | Android、iOS 393×852；Windows、Linux、macOS 1280×800 | 各平台的菜单项 |
| A07.9-02 | 多画面选中格的控制区（五个按钮）和工具条开关 | 多画面 | 竖屏 393、360；1+3；横屏 740×360；宽屏 1280×800 | 点击区域 |
| A07.9-03 | 退出登录的确认（列表、Cookie 页、清空后保存、斗鱼页） | 设置 → 账号 | 居中对话框 | — |
| A07.9-04 | 平台名“SOOP”“网易CC” | 平台列表、直播间“在<平台>打开”、账号页、Cookie 页标题 | 全应用 | 中文、英文 |

## 3.x 的样子和问题

- 投屏：v3 的直播间菜单在所有平台都有“投屏”（`git show v3.2.11:lib/modules/live_play/widgets/button/live_play_menu_button.dart:193`，没有平台判断），上栏的投屏按钮只在 Android。4.x 设计确认的是“投屏只有 Android”（菜单也一样），合并 A07.4、A07.5 时菜单还按“不是 iOS 就放”，电脑上有投屏。
- 多画面点击区域：不是 3.x 的问题，是 A13.2 记录偏差 4“按钮 40、工具条开关 38，比 48 小”。
- 账号退出：v3 的确认是标题“退出登录”、正文“确定退出“{name}”账号吗？”、按钮“取消”“退出登录”（`git show v3.2.11:lib/modules/account/account_page.dart:244`）；A12.2 的平台页另有一套“退出{name}？”“将删除本机保存的{name} Cookie……”，两处不一样（A12.2 记录偏差 1）。
- 平台名：v3 自己就不一致：`site_soop` 写“Soop”（`git show v3.2.11:assets/translations/zh.json:1656`），另外 5 处都是“SOOP”（`soop_cookie_hint` 等）；网易 CC 只有 `audience_metric_support_detail` 一处写“网易 CC”（带空格），其余“网易CC”；4.x 账号页写“网易 CC”。平台官方写法是 SOOP（2024 年 AfreecaTV 改名）、网易CC直播。

问题：

| 编号 | 问题 | 位置（当时） |
|---|---|---|
| P1 | 电脑（Windows、Linux、macOS）的直播间菜单有“投屏”，点了也投不了 | `features/live_play/buttons/room_menu_button.dart`（`roomMenuGroups` 按“不是 iOS”判断） |
| P2 | 多画面选中格的五个按钮 40、工具条开关 38，点击区域小于 48 | `features/multiview/` |
| P3 | 同一个“退出登录”两套确认文字 | `features/account/` 的 `confirmPageSignOut` |
| P4 | 同一个平台两种写法（Soop / SOOP，网易 CC / 网易CC） | `assets/translations/zh.json`、`en.json` |

必须保留的操作习惯（[specs/UI.md](../../../specs/UI.md) 附录 A）：第 13 条（多画面点格子切换声音焦点、长按或右键格子菜单）——这次只放大点击区域，不改操作。

## 各版的经过

| 版 | 内容 | 用户意见 |
|---|---|---|
| — | 没有新设计；四条都是已确认设计里写了、合并时没同步的 | 2026-10-01“后续全部通过” |

## 对比页（按章节导出）

无：没有新设计，没有评审页。

## 单张图

无。多画面点击区域的尺寸是测试里用 Roboto 和思源黑体渲染后量的数（见下面“确认的改动”c2 的表），没有出图。

## 确认的改动

| 编号 | 类型 | 内容 | 对应问题 |
|---|---|---|---|
| c1 | 修改 | 电脑（Windows、Linux、macOS）的直播间菜单去掉“投屏”；上栏投屏按钮和菜单都看 `castSupported(platform)`（只有 Android 为真），以后只改一处；`roomMenuGroups` 的 `cast` 参数改成必填；iOS 照旧没有（A18.1）；Windows 的“在新窗口打开”不变，仍在第二组最后 | P1 |
| c2 | 修改 | 多画面选中格控制区五个按钮、工具条开关（弹幕、弹幕设置、全部静音、小格省流）都放进 48×48 的点击区域（`MaterialTapTargetSize.padded`），圆和图标大小不变；圆旁边的内边距减去多出的那一圈，看起来的位置不变；相邻两个圆之间的空隙从 2 变成 8（按钮）、10（开关） | P2 |
| c3 | 修改 | 平台页（Cookie 页、斗鱼页）的“退出登录”、清空后保存改用列表的 `confirmSignOut`（v3 原文）；页内自己的确认和它的两条文字删除 | P3 |
| c4 | 修改 | 统一成“SOOP”“网易CC”：中文 `site_soop`“Soop”→“SOOP”、`account_site_cc`“网易 CC”→“网易CC”、`audience_metric_support_detail` 里的“网易 CC”→“网易CC”；英文 `site_soop`“Soop”→“SOOP”（`site_cc`、`account_site_cc` 本来都是“NetEase CC”） | P4 |

c2 的连带调整：

| 位置 | 之前 | 现在 |
|---|---|---|
| 竖屏 393 宽：按钮和音量一行 | 按钮占 12～220，滑块（含两侧留白）97，滑轨约 73 | 按钮占 8～248（点击区域），滑块 73，滑轨约 49；音量图标离最后一个圆仍是 8 |
| 竖屏窄于 384（例如 360） | 一行，滑轨约 40 | 一行放不下五个 48 再加一个能用的滑块（留白后滑轨至少 40），音量换到下一行，图标和头像对齐；控制区高 48 |
| 工具条的布局分段按钮 | 放不下时整体缩小（393 宽的 1+3 缩到 0.92，360 宽缩到 0.96，360 宽的 1+3 缩到 0.78） | 先把每段从 56 收窄到 48 再缩小：393 宽不变；393 宽的 1+3 缩到 0.95；360 宽不缩；360 宽的 1+3 仍是 0.78。只在手机工具条（不带图标）上收窄 |
| 横屏手机右栏 | 最窄 240（740×360 时就是 240） | 最窄 256，五个 48 的按钮一行放得下，两边各 8；740×360 时画面区从 500 宽变成 484 宽；852×393 不变（260） |
| 宽屏右栏、全屏格子面板 | 360 | 不变；按钮仍一行 |

## 按钮的作用和用法

直播间菜单（c1 之后，竖屏顶栏的完整菜单；全屏菜单再去掉栏上已有的项，见 A07.13 c12）：

| 平台 | 第一组 | 第二组 | 第三组 |
|---|---|---|---|
| Android | 切换直播间、定时关闭、房间音量、画面比例 | 投屏、获取直链、分享、在<平台>打开 | 本地互动（开着时） |
| iOS | 同上 | 获取直链、分享、在<平台>打开 | 同上 |
| Windows | 同上 | 获取直链、分享、在<平台>打开、在新窗口打开 | 同上 |
| Linux、macOS | 同上 | 获取直链、分享、在<平台>打开 | 同上 |

多画面、账号、平台名的操作不变。

## 各客户端

| 客户端 | 怎么做 |
|---|---|
| Android 手机 | 菜单和上栏有投屏；多画面 48 点击区域 |
| 宽屏（平板、Windows、Linux、iPad、macOS） | Android 平板有投屏；电脑没有；多画面宽屏右栏 360 不变 |
| 电视 | 不涉及 |
| 苹果平台差异 | iOS 没有投屏（A18.1） |

## 待选和决定

- 平台名的写法：任务书写“v3 和账号页不一致时用 v3 的”，但 SOOP 这一条 v3 自己就不一致（只有 `site_soop` 写“Soop”，其余 5 处“SOOP”）；按 v3 多数的写法和官方写法用“SOOP”，账号页不用改。要“Soop”时改回 `site_soop` 一处，并把账号页和那 5 处一起改。→ 维护者按记录接受了 SOOP（现在 `apps/pure_live/assets/translations/zh.json:2124`）。
- 账号页内确认原来多说一句“将删除本机保存的 Cookie”，现在照 v3 不说；页底“Cookie 只加密保存在本机”的说明还在。

## 实现和验证

**实现**（详见 [record.md](record.md)；2026-10-02，每条一次提交：`c1f4c121c`（投屏只在 Android）、`ef295adfc`（多画面 48）、`8f6a925b6`（账号退出）、`6d90f6649`（平台名）；合并提交 `a88f26dfc`“Merge U.2, U.8 and U.10 follow-ups”；登记表记的是记录提交 `085fb71a3`）

- c1：`apps/pure_live/lib/features/live_play/buttons/room_menu_button.dart:148` 的 `castSupported`、`:158` 的 `roomMenuGroups`（`cast` 必填，调用处 `:332`）；上栏 `player/player_controls.dart:96` 的 `topBarSlots` 也用它。
- c2：`apps/pure_live/lib/features/multiview/` 的选中格控制区和工具条（A13.2 的文件）。
- c3：`apps/pure_live/lib/features/account/account_widgets.dart:200` 的 `confirmSignOut`，`cookie_editor.dart:244`、`account_list_view.dart:118` 都调它；删掉 `account_sign_out_title`、`account_sign_out_message`（v4 自己加的）。
- c4：`apps/pure_live/assets/translations/zh.json`（`site_soop`、`account_site_cc`、`audience_metric_support_detail`）和 `en.json`（`site_soop`）；`account_platforms.dart` 的名字键注释改成“和平台列表同一个写法”。
- 没有改 `packages/`、`shared/`，没有原生改动；门禁 `live_play` 仍是 8，`multiview`、`account` 仍是 0。

**验证**

- 自动测试：`apps/pure_live/test/features/live_play/live_play_layouts_test.dart`“the room menu on each platform”（Android、iOS、Windows、Linux、macOS 各打开一次顶栏菜单和全屏上栏菜单，固定整份菜单和全屏上栏的投屏按钮只在 Android）；`live_play_popups_test.dart` 的 `roomMenuGroups` 补 `cast:`；`test/features/multiview/multiview_page_test.dart`“tap targets (specs/UI.md 5.4)”（393、1+3、360、740×360、1280×800）；`test/features/account/account_page_test.dart` 四处退出同一套文字、平台名中英文一致。新增 3 个、改了 5 个；当时全部 465 个里 464 个通过——没过的 `test/features/iptv/iptv_page_test.dart`“one page: counts, playlists, guides…”是时间炸弹（页面时钟固定在 2026-10-01 20:00，导入的播放列表记真实时间），和这次无关，属于 A13.1 的测试。
- 真机：[S02.3](../../../S-质量和验证/S02-真机验证/S02.3-K90验证主流程/record.md) 看了 Android 直播间菜单（切换直播间、定时关闭、房间音量、画面比例 / 投屏、获取直链、分享、在平台打开 / 本地互动体验），通过。多画面点击区域、账号退出、平台名没有在真机上单独看；电脑菜单没有投屏只有测试。
- 留下的问题和去向：`iptv_page_test` 的时间炸弹 → A13.1（时间炸弹的规则见 D-017）；多画面在真机上看 → S02.6（CHECKLIST 第 1 节第 16 条）。
