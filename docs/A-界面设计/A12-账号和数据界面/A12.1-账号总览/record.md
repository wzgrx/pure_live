# A12.1 平台账号总览

- 日期：2026-10-01
- 设计：[docs/A-界面设计/A12-账号和数据界面/A12.1-账号总览/README.md](README.md)（第 1 版，用户已确认；待选 K1～K3 按建议 A）
- 范围：账号列表（v3“三方认证”）、列表上的退出确认、提示条。各平台自己的页面在 [A12.2](../A12.2-登录和Cookie/record.md)；设置总览里的入口改名（“三方认证 / 管理主流平台的绑定授权”→“平台账号”）由设置任务 A11.4 做，这次没有改（跨任务待同步已记）。
- 改动的目录：`apps/pure_live/lib/features/account/`、`apps/pure_live/lib/routes/app_navigator.dart`（哔哩哔哩登录入口，见下）、`packages/live_ui`（只做添加，随 A13.1 提交）、翻译文件、门禁基线、文档。
- 没有新依赖，没有改原生部分。

## 逐条对照

| 编号 | 要求 | 做到 | 说明 |
|---|---|---|---|
| c1 | 点平台一行都进它的页面；退出只用行尾的退出按钮（图标、颜色、位置照 v3），先确认 | ✅ | v3 点已登录的平台直接弹“退出登录”；现在进 A12.2 的页面。哔哩哔哩：存了 Cookie 进账号页，没存进扫码页（K2 按 A，不再弹“请选择登陆方式”） |
| c2 | 状态写具体；颜色：正常主色、提醒黄、失效红、未设置灰；可以两行，不截断 | ✅ | 文字见下表；状态不限行数；核验中用灰色（设计图如此） |
| c3 | 标题“平台账号”，分“国内平台”“海外平台”，顶部一句说明 | ✅ | K1 按 A；新键 `account_title`，设置里的旧入口文字 `third_party_auth` 没动（A11.4 改） |
| c4 | 顺序：哔哩哔哩、斗鱼、虎牙、抖音、快手、YY、网易 CC；Twitch、SOOP | ✅ | |
| c5 | 文字统一：“未设置”“SOOP”；登录方式改错字 | ✅ | 哔哩哔哩没登录也写“未设置”（v3“未登录”）；“SOOP”“网易 CC”是账号页自己的名字（`AccountPlatform.nameKey`），平台列表等处的 `site_soop`“Soop”、`site_cc`“网易CC”没有改。登录方式对话框按 K2 A 不再出现 |
| c6 | 网易 CC 一行（C-22） | ✅ | 存了 Cookie 时黄色“已保存，暂未用于请求（登录后加入弹幕待验证）” |
| c7 | 本机读不出已存的 Cookie 时顶部提醒是哪几个平台，行写“无法在本机读取……”，退出按钮可以删掉 | ✅ | 提醒卡代替顶部说明的位置；读不出的平台也显示退出按钮 |
| c8 | 图标 24、名字 15、状态 12；退出确认文字照 v3（正文 14）；同时只处理一个退出；哔哩哔哩启动核验失效时提示并退出 | ✅ | 退出确认“退出登录 / 确定退出“{name}”账号吗？/ 取消、退出登录（红底）”；进行中行尾转圈 |
| K3 | 不要“退出全部账号” | ✅ | 标题栏菜单删掉，`AccountActions.signOutAll` 和三条只有它用的文字一并删除（3.x 的 `clearAllCookies` 也没有界面入口） |

状态文字（和 A12.2 的状态卡共用 `accountStatus`）：

| 平台 | 状态 |
|---|---|
| 哔哩哔哩、抖音（问平台） | 已登录：名字 / 正在核验账号…（灰）/ 登录已失效，请重新登录或更换 Cookie（红）/ 已保存，暂时无法核验账号（网络或平台异常）（黄） |
| 斗鱼 | 登录有效，到期前自动续期 / 登录有效，预计 … 到期 / 登录态已过期，播放时自动续期（黄）/ 登录态已失效，点按重新粘贴 Cookie（红） |
| 虎牙 | 已保存 · 账号 ID … / 已保存，但没有找到账号 ID（yyuid），可能不是登录后的 Cookie（黄） |
| Twitch | 已保存 · 聊天身份 … / 已保存，但缺少 auth-token 或 login，聊天以游客身份连接（黄） |
| 快手、YY、SOOP | 已保存 |
| 网易 CC | 已保存，暂未用于请求（登录后加入弹幕待验证）（黄） |
| 任何平台 | 未设置（灰）/ 无法在本机读取已保存的 Cookie，请重新填写（红） |

### 各客户端

| 客户端 | 做到 | 说明 |
|---|---|---|
| 手机竖屏、横屏 | ✅ | 横屏同宽屏的一栏 |
| 宽屏（平板、Windows、Linux） | ✅ | 一栏最宽 720 居中；行和退出按钮有悬停高亮，退出按钮悬停显示“退出登录” |
| 电视、苹果平台 | — | 电视在 A17.9；苹果平台同宽屏 |

### 偏差和原因

1. 斗鱼“登录态已失效”（游客或过期且不能续期）在 v3 和 v4 原来都不算已登录、没有退出按钮；设计图的状态一览里它有退出按钮，现在按“存了 Cookie 就有退出”显示。
2. 标题居中由页面自己设（同 A13.1 记录的偏差 1）。
3. `AppNavigator.toBiliBiliLogin`（v3 的同名入口，v4 现在没有调用处）改为直接打开扫码页（K2 A），去掉了“请选择登陆方式”对话框。A07.7 的“去登录”可以直接用 `RoutePath.kSettingsAccount` 加平台 id（打开该平台的页面），哔哩哔哩没登录时用这个入口进扫码页。

## v3 文件 → v4 文件

| v3 | v4（`features/account/`） |
|---|---|
| `modules/account/account_page.dart` | `account_list_view.dart`（页面）、`account_state.dart`（状态）、`account_widgets.dart`（退出确认、提醒、颜色）、`account_platforms.dart`（顺序和名字） |
| `common/utils/utils.dart:447-505`、`app_navigation.dart:96-108`（选择登录方式） | 去掉（K2 A）；`routes/app_navigator.dart` 的 `toBiliBiliLogin` 直接进扫码页 |

## 设置、文字、门禁

- 没有新设置，Cookie 的存储（`LiveStore.secrets`）和 `bilibiliUid`、`douyuCookieSavedAt` 照旧。
- 文字：新加 `account_title`、`account_site_soop`、`account_site_cc`、`account_status_saved`；改 `account_intro`、`account_unreadable_notice`；删 `account_sign_out_all`、`account_sign_out_all_confirm`、`account_signed_out_all`（v4 自己加的）。
- 门禁：`account` 直接写的颜色和图标 **25 → 0**（A12.1、A12.2 合计），基线删去这一项。

## 测试

`apps/pure_live/test/features/account/account_page_test.dart` 共 21 个（原 11 个），其中本任务 6 个：两组和九个平台的顺序、名字、各状态文字和颜色、不截断、退出按钮（图标、≥48）和箭头、没有标题栏菜单；点平台进页面、哔哩哔哩没登录直接进扫码页（没有“请选择登陆方式”）；列表退出（v3 文字、取消、确认、提示）；哔哩哔哩启动核验失效自动退出；读不出的 Cookie 提醒和退出按钮；1280 宽一栏 ≤720 居中。原测试里“退出全部账号”的断言随 K3 删除，“未登录”“Soop”“Cookie 已保存在本机”按新文字改。
