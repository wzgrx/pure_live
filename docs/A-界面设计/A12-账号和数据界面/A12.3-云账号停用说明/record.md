# A12.3 云账号停用说明

- 日期：2026-10-01
- 设计：[docs/A-界面设计/A12-账号和数据界面/A12.3-云账号停用说明/README.md](README.md)（第 1 版，用户已确认；待选 X1、X2 按建议 A）
- 范围：三个旧路由 `kSignIn`、`kMine`、`kUserManage` 落到的说明页“云端账号”。备份页“云端备份”里留的“云端账号（已停用）”一行（X1 A）由 A12.4 做，这次没有改备份页。
- 改动的目录：`apps/pure_live/lib/features/auth/auth_page.dart`、`packages/live_ui`（只加图标，随 A13.1 提交）、翻译文件、门禁基线、文档。没有新依赖，没有原生改动。

## 逐条对照

| 编号 | 要求 | 做到 | 说明 |
|---|---|---|---|
| c1 | 去掉 Firebase 登录、注册、找回密码、GitHub 登录 | ✅ | I01.1 已去掉，v4 没有这些代码 |
| c2 | 去掉“我的”、用户配置中心、“管理用户” | ✅ | 同上 |
| c3 | 三个旧路由落到一个说明页：为什么停用、旧配置怎么迁移、“同步与备份”（WebDav、设备同步、备份与恢复）、“平台账号” | ✅ | 页面结构 v4 已有，这次照设计重排：停用卡（主色 5% 底、圆角 20、`cloud_off_line`）→“同步与备份”三行 →“平台账号”一行（X2 A，`accessibility_line`，说明“哔哩哔哩、斗鱼、虎牙等平台的登录，和云端账号无关”） |
| c4 | 备份页的账号行改成“云端账号（已停用）”指向说明页 | 交给 A12.4 | 设计写明在 A12.4 做；说明页的三个路由都在，A12.4 跳 `RoutePath.kMine` 即可 |
| c5 | 照 v3 设置页的写法：分组标题、分组卡片、行 | ✅ | `buildGroupTitle`、`buildModernCard`、`buildTile`；一栏最宽 720 居中 |

### 各客户端

| 客户端 | 做到 |
|---|---|
| 手机竖屏、横屏 | ✅ 横屏同宽屏的一栏 |
| 宽屏 | ✅ 一栏最宽 720 居中，行有悬停高亮 |
| 电视 | 不适用 |
| 苹果平台 | 同宽屏 |

### 偏差

- 图标走 `AppIcons`（`cloudOff`、`webDav`、`deviceSync`、`backupFiles`、`platformAccounts`）；“备份与恢复”用 v4 原来的 `save_3_line`（设计如此，统一图标在 A01.3 / A12.4 定）。
- “WebDav”的写法照 v3，说明文字也改成“WebDav 网盘”与标题一致；改不改成 WebDAV 由 A12.5 定。
- 标题居中由页面自己设（同 A13.1 记录的偏差 1）。

## v3 文件 → v4 文件

| v3（`modules/auth/`） | v4 |
|---|---|
| `sign_in_page.dart`、`components/firebase_email_auth.dart`、`mine_page.dart`、`user_manage_page.dart`、`components/user_detail_main_page.dart` | `features/auth/auth_page.dart`（说明页，三个路由共用） |

## 设置、文字、门禁、测试

- 没有设置。
- 文字：新加 `auth_platform_accounts_desc`；改 `auth_webdav_desc`；行标题用 A12.1 的 `account_title`“平台账号”。
- 门禁：`auth` 直接写的颜色和图标 **5 → 0**，基线删去这一项。
- 测试（`account_page_test.dart` 中 2 个）：三个旧路由都显示说明页；停用卡、分组和四行的顺序与图标；“平台账号”和 WebDav 两行能跳转；1280×800、852×393 一栏 ≤720 居中。原来的 1 个测试并入。
