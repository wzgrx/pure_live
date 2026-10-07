# A12.1 账号总览：设计（第 1 版，已确认，已开发，待真机）

- 状态：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)（登记为完成，2026-10-01；K90 上没有记录，见“实现和验证”）
- 旧编号：U.10a、T10a.2（见 [MAPPING.md](../../../MAPPING.md)）
- 范围：v3 的“三方认证”页（各平台登录状态），点平台后的退出确认和哔哩哔哩的“选择登录方式”；各平台的登录页和 Cookie 页在 [A12.2](../A12.2-登录和Cookie/README.md)
- 对应：[inventory/UI.md](../../../inventory/UI.md#a121)（A12.1-01、02）、[inventory/UI_FILES.md](../../../inventory/UI_FILES.md#a121)；功能点 F-ACC-01（[inventory/FEATURES.md](../../../inventory/FEATURES.md)）；登录和 Cookie 的逻辑在 [K01.1](../../../K-账号和登录/K01-账号和登录方式/README.md)；相关决定 D-003（K1～K3 按建议 A）、D-013（登录引导用 `RoutePath.kSettingsAccount` 加平台 id）、D-018（存储键不变）
- 评审页：claude.ai 私有页面（只有项目所有者能打开）；源文件 [page.json](page.json)，效果图源文件 [src/gen.py](src/gen.py)；按章节导出在 [page/](page/01-说明.jpg)
- 图片：v3 按 `v3.2.11` 代码还原（文字取自 `assets/translations/zh.json`）；用户名、昵称、账号 ID 都是编的占位（“示例用户”“example_user”“12345678”）
- 记录：[record.md](record.md)

## 界面清点表

| 编号 | 界面 | 从哪打开 | 形态 | 状态 |
|---|---|---|---|---|
| A12.1-01 | 三方认证（账号列表） | 设置 → 平台显示与授权 →“三方认证”（`platform_settings_page.dart:50-57`）；列表页“需要登录账号”的“前往登录”（`base_page_view.dart:203-212`）；路由 `kSettingsAccount` | 竖屏、横屏、宽屏（同一列，最宽 960） | 每个平台：未设置、已登录（哔哩哔哩名字、抖音昵称或“已登录”、其余“已登录”）、哔哩哔哩“正在核验账号…”、斗鱼四种会话状态 |
| A12.1-02 | 退出确认 | 点已登录的平台，或行尾退出按钮 | 对话框 | 同一时间只处理一个 |
| — | 选择登录方式 | 哔哩哔哩没登录时点它（只在 Android、iOS；电脑直接进扫码） | 对话框 | 两项都没选中 |
| — | 提示条 | 哔哩哔哩启动核验失效、退出时清理浏览器 Cookie 失败 | 底部 | “哔哩哔哩登录已失效，请重新登录”“本地账号已退出，浏览器 Cookie 清理需要再次尝试” |

## v3 的样子

`account_page.dart`：标题栏“三方认证”（`:17`）；分组标题也是“三方认证”（`:22`）；一张分组卡片 8 行，顺序哔哩哔哩、虎牙、YY、抖音、快手、Twitch、Soop、斗鱼（`:23-180`）。

一行（`:188-242`）：左边平台图标 24（`assets/images/bilibili_2.png` 等）；名字 15 号 600；状态 12 号，已登录主色 500、否则灰色，窄于 360 或字号放大 1.5 倍以上时两行；右边已登录是退出按钮 `Remix.logout_box_r_line`（18，红色 80%，点击区 48），没登录是箭头 20。点整行：已登录 → 退出确认，没登录 → 哔哩哔哩登录或该平台的 Cookie 页。

状态文字：哔哩哔哩已登录显示用户名，名字还没取到时“正在核验账号…”，否则“未登录”（`:24-44`）；虎牙、YY、快手、Twitch、Soop 有 Cookie 就是“已登录”，否则“设置cookie”；抖音显示昵称（`account_controller.dart` 用 Cookie 去取），取不到时“已登录”（`:77-97`）；斗鱼看会话：没有“设置cookie”、有效“Cookie 已保存在本机”、过期可续期“登录态已过期，播放时自动续期”（算已登录）、游客或过期“登录态已失效，点按重新粘贴 Cookie”（算没登录，点了进 Cookie 页）（`:150-180`）。

退出确认（`:244-287`）：标题“退出登录”，正文“确定退出“{name}”账号吗？”，按钮“取消”“退出登录”（红底）。选择登录方式（`app_navigation.dart:96-108`、`utils.dart:447-505`）：“请选择登陆方式”，单选“短信登陆”（进网页登录）、“二维码登陆”（进扫码），没有按钮。

没有按宽度的分支（只有上面的两行状态）；没有快捷键。

## v4 现在的偏差（K01.1 写的，未经对照）

已经做了：点平台进它的页面、状态写具体、分国内 / 海外两组、加 CC、顶部说明、读不出 Cookie 的提醒、标题栏菜单“退出全部账号”。标题仍是“三方认证”。新设计把这些逐条列出来请你确认，“退出全部账号”建议去掉（待选 K3）。

## 各版的经过

| 版 | 内容 | 用户意见 |
|---|---|---|
| 第 1 版 | 点平台进页面、退出只用行尾按钮、状态具体、分组和顺序、改名“平台账号”、三个选择 | 用户 2026-10-01 确认；K1～K3 按建议 A（D-003） |

## 对比页（按章节导出）

- [说明](page/01-说明.jpg)
- [对比](page/02-对比.jpg)
- [对话框和状态](page/03-对话框和状态.jpg)
- [v3 的问题](page/04-v3-的问题.jpg)
- [改了什么](page/05-改了什么.jpg)
- [每个按钮是干什么的、怎么用](page/06-每个按钮是干什么的-怎么用.jpg)
- [各客户端](page/07-各客户端.jpg)
- [需要你选的](page/08-需要你选的.jpg)
- [性能要点](page/09-性能要点.jpg)
- [拿不准的地方](page/10-拿不准的地方.jpg)

## 单张图

| 图 | 内容 |
|---|---|
| [v3-accounts.jpg](v3-accounts.jpg)、[v4-accounts.jpg](v4-accounts.jpg)、[v4-accounts-n.jpg](v4-accounts-n.jpg) | 竖屏：v3 / 新设计 / 按钮编号 |
| [v3-dialogs.jpg](v3-dialogs.jpg) | v3 退出确认、选择登录方式 |
| [v4-states.jpg](v4-states.jpg) | 新设计：状态一览、读不出 Cookie 的提醒、退出确认、登录方式（待选 K2 选 B 时）、提示条 |
| [v3-wide.jpg](v3-wide.jpg)、[v4-wide.jpg](v4-wide.jpg) | 1280×800 |
| [v3-land.jpg](v3-land.jpg)、[v4-land.jpg](v4-land.jpg) | 手机横屏 852×393 |

## 确认的改动

| 编号 | 类型 | 内容 | 对应问题 |
|---|---|---|---|
| c1 | 修改 | 点平台一行都进它的页面（看状态、改 Cookie、核验）；退出只用行尾的退出按钮，先确认 | A1 |
| c2 | 修改 | 状态写具体，颜色区分正常、提醒、失效、未设置 | A2、A7 |
| c3 | 修改 | 标题改“平台账号”，分“国内平台”“海外平台”，顶部一句说明 | A3、A6 |
| c4 | 修改 | 顺序：哔哩哔哩、斗鱼、虎牙、抖音、快手、YY、网易 CC；Twitch、SOOP | A4 |
| c5 | 修改 | 文字统一：“未设置”“SOOP”；登录方式改错字 | A5 |
| c6 | 增强 | 网易 CC 一行（UPGRADES C-22，已批准） | — |
| c7 | 增强 | 本机读不出已存的 Cookie 时顶部提醒，状态写明 | — |
| c8 | 保留 | 平台图标、名字、退出按钮的样子和位置，退出确认的文字和按钮，同一时间只处理一个退出 | — |

## 按钮的作用和用法

| 编号 | 控件 | 怎么用 |
|---|---|---|
| 1 | 返回 | 回到上一页 |
| 2 | 平台一行（已登录） | 进该平台的页面：看状态、换 Cookie、重新核验、退出（A12.2） |
| 3 | 退出登录 | 只有已保存 Cookie 的平台有；先确认，再删除这个平台的 Cookie（斗鱼连续期凭据一起删） |
| 4 | 平台一行（未设置） | 进该平台的 Cookie 页；哔哩哔哩进扫码登录（待选 K2） |
| 5 | 网易 CC（新） | 同 4；状态写明“已保存，暂未用于请求” |

## 各客户端

| 客户端 | 怎么做 |
|---|---|
| Android 手机 | 竖屏如图；横屏同宽屏的一栏 |
| 宽屏（平板、Windows、Linux、iPad、macOS） | 同一个列表，一栏最宽 720 居中；悬停高亮；退出按钮悬停显示“退出登录” |
| 电视 | 不在本任务（A17.9 的账号设置：哔哩哔哩扫码、手机扫码填 Cookie）；状态文字和平台顺序照本页 |
| 苹果平台差异 | 同宽屏；iOS 上哔哩哔哩也给网页登录（同 Android） |

## 待选

- K1 页面标题：建议 A“平台账号”；B 照 v3“三方认证”。
- K2 哔哩哔哩没登录时点它：建议 A 直接进扫码页，网页登录和填写 Cookie 放在扫码页下面；B 照 v3 先弹“选择登录方式”（改错字）。
- K3 退出全部账号（v4 现在有）：建议 A 不要；B 标题栏菜单里放。

## 拿不准的地方

- v3 设置页的入口文字是“三方认证 / 管理主流平台的绑定授权”，如果 K1 选 A，入口在 A11.4（平台显示与授权）跟着改名；这条我没法改别的任务，记在报告里。
- CC 的 Cookie 现在还不用于请求，状态写“暂未用于请求”；等 C-22 验证后改成正常状态。

## 实现和验证

**实现**（详见 [record.md](record.md)；2026-10-01，开发提交 `587ccc3c7`“feat(ui): U.10a/U.10b platform accounts, login and cookie pages per the confirmed design”（登记表写的就是它，和 A12.2 同一个提交），合并提交 `59248e0b9`“Merge U.9 and U.10: IPTV management and accounts”）

| 编号 | 做到 | 现在的代码（`apps/pure_live/lib/features/account/` 省略前缀） |
|---|---|---|
| c1 | ✅ | `account_list_view.dart:97` 的 `_open`：点任何一行都进该平台的页面（`RoutePath.kSettingsAccount` 加平台 id，或平台自己的路由）；哔哩哔哩没存 Cookie 时直接进 `RoutePath.kBiliBiliQRLogin`（K2 A）；退出只用行尾按钮（`:213-218`），先 `confirmSignOut`（`account_widgets.dart:200`） |
| c2 | ✅ | `account_state.dart:115` 的 `accountStatus`、颜色 `AccountTone`（`:8`）和 `accountToneColor`（`account_widgets.dart:10`）：正常主色加粗、提醒黄、失效红、未设置和核验中灰；状态不限行数（`account_list_view.dart:195-206`）。各平台的文字见记录的状态表 |
| c3 | ✅ | 标题 `account_title`“平台账号”（`account_list_view.dart:167`）；两组 `account_group_domestic`、`account_group_overseas`（`:163-164`）；顶部说明 `account_intro`（`:155-162`） |
| c4 | ✅ | `account_platforms.dart:87-141` 的 `accountPlatforms`：哔哩哔哩、斗鱼、虎牙、抖音、快手、YY、网易CC；Twitch、SOOP（`overseas: true`） |
| c5 | ✅（偏差 4） | 没存时一律“未设置”；SOOP、网易CC 用账号页自己的名字键（`AccountPlatform.nameKey`，`account_platforms.dart:58-62`）；“请选择登陆方式”对话框随 K2 A 去掉 |
| c6 | ✅ | `account_platforms.dart:117-122`（`usedByRequests: false`）；状态“已保存，暂未用于请求（登录后加入弹幕待验证）”（黄，`account_state.dart:171-173`） |
| c7 | ✅ | 读不出时提醒卡 `AccountNotice`（`account_widgets.dart:70`）代替顶部说明（`account_list_view.dart:151-153`），行写“无法在本机读取已保存的 Cookie，请重新填写”（`account_state.dart:123`），也有退出按钮 |
| c8 | ✅ | 一行 `_tile`（`account_list_view.dart:184-223`）：`PlatformLogo` 24、名字 15、状态 12，退出图标 18（`error` 80%）、点击区 48、悬停“退出登录”；同一平台退出进行中行尾转圈且不能再点（`_signOut` `:116-129`）；哔哩哔哩启动核验失效提示“哔哩哔哩登录已失效，请重新登录”并退出（`:86-91`） |
| K3 | ✅ | 标题栏没有菜单；`AccountActions.signOutAll` 和三条只有它用的文字删除 |

- 偏差（记录“偏差和原因”）：①斗鱼“登录态已失效”现在也有退出按钮（规则是“存了 Cookie 就有退出”，设计图的状态一览里也有）；②记录写“标题居中由页面自己设”，后来 D-011（`e320e0e72`）统一成照 3.x 实际运行的位置，现在是普通 `AppBar` 的默认位置（Android 靠左）；③`AppNavigator.toBiliBiliLogin`（`routes/app_navigator.dart:165`）改为直接打开扫码页；④账号页的“SOOP”“网易CC”当时和平台列表的“Soop”“网易CC”写法不同，A07.9 的收尾（`6d90f6649`）统一成“SOOP”“网易CC”。
- 后来的变化（以现在的代码为准）：A02.1（`914784264`）列表行改用共用组件；A02.2（`fc5bcdd46`）确认框换成 `showAppConfirmDialog` 一套（`account_widgets.dart:176`）；A07.9 收尾（`8f6a925b6`）让 A12.2 的页内退出也用这里的 `confirmSignOut`。
- 新文字：`account_title`、`account_site_soop`、`account_site_cc`、`account_status_saved`；改 `account_intro`、`account_unreadable_notice`；删 v4 自加的 `account_sign_out_all`、`account_sign_out_all_confirm`、`account_signed_out_all`。没有新设置，Cookie 存储（`LiveStore.secrets`）、`bilibiliUid`、`douyuCookieSavedAt` 照旧（D-018）。
- 门禁：`account` 直接写的颜色和图标 25 → 0（A12.1、A12.2 合计），`tools/gate/ui_baseline.json` 去掉这一项。
- 设置里的入口：记录写“改名由 A11.4 做”；实际入口在设置 → 账号和标签 → “平台账号”（`features/settings/settings_catalog.dart:555-561`，A11.1 做的，搜索关键词里留着“三方认证”）。

**验证**

- 自动测试：`apps/pure_live/test/features/account/account_page_test.dart`（现在 22 个）中本任务 6 个，分组 `U.10a platform accounts`（`:208-332`）：两组九个平台的顺序、名字、各状态文字和颜色、不截断、退出按钮和箭头、没有标题栏菜单；点平台进页面、哔哩哔哩没登录直接进扫码页；列表退出（3.x 文字、取消、确认、提示）；哔哩哔哩启动核验失效自动退出；读不出的提醒和退出按钮；1280 宽一栏 ≤720 居中。另有 `:703` 的平台名统一测试（A07.9）。
- 真机：**记录里没有 K90 结果**，也没有 `verify.md`。[S02.3 记录](../../../S-质量和验证/S02-真机验证/S02.3-K90验证主流程/record.md)写明“账号页没在真机上看”。登记表已是“完成”，不符合 PROCESS 3.2（问题记在[子分类页](../README.md)“已知问题”）。要看的：设置 → 账号和标签 → 平台账号，两组九行和状态；哔哩哔哩没登录点它直接进扫码页；存了 Cookie 的平台点行尾退出、确认后变“未设置”。建议随 [S02.6](../../../S-质量和验证/S02-真机验证/S02.6-K90补验/README.md)（哔哩哔哩登录）和 [K02.1](../../../K-账号和登录/K02-登录状态/K02.1-Cookie和密码加密存储验证/README.md)（读不出 Cookie 的提醒要在 Keystore 出问题时才出现）一起看。
- 留下的问题和去向：横屏手机顶栏 56 高（同组的备份等页是 48）→ 建议并入 A04.1；电脑上 Esc 不返回 → A05.1；网易CC 的 Cookie 接上请求 → UPGRADES C-22（未排）；哔哩哔哩多账号 → [V01.2](../../../V-需求和反馈/V01-新功能提议/V01.2-哔哩哔哩多账号/README.md) 提议。
