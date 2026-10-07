# K03 第三方认证

第三方认证和云账号。

3.x 的“云端账号”（Firebase：邮箱和 GitHub 登录、上传下载云端配置、管理员管理用户）在 4.x 里停用了。这个子分类管停用后的去向：三个旧路由落到说明页，引导用户改用 WebDAV、设备同步、备份文件，以及以后如果要恢复某种云端同步时从哪里开始。说明页的样子归 A12.3。

## 范围

- 包括：
  - `apps/pure_live/lib/features/auth/auth_page.dart`（119 行）：`AuthPage`，接住 3.x 的三个路由 `RoutePath.kSignIn`、`kMine`、`kUserManage`，说明云端账号已停用、旧的云端配置怎么搬（用 3.x 下载后导出备份，再在 4.x 里恢复），并给出 WebDAV、设备同步、备份与恢复、平台账号四个入口。
  - 和 3.x 云端账号有关的数据：没有。3.x 的 Firebase 登录状态、云端配置不在本地 Hive 里，迁移时没有可导的东西（J06）。
- 不包括（归哪里）：
  - 说明页的样子 → [A12.3](../../A-界面设计/A12-账号和数据界面/A12.3-云账号停用说明/README.md)。
  - 替代方式：备份文件 → J03；WebDAV → J04；设备同步 → J05。
  - 各直播平台的账号（哔哩哔哩、斗鱼……）→ K01、K02；它们和“云端账号”是两回事，说明页里专门写了这一点。
  - 以后的新云端功能（多设备同步、账号体系）→ 先进 V01 提议。

## 现状：做到哪、怎么工作的

- 用户看得到的：从旧链接、3.x 用户习惯的入口（3.x 备份页的“云端备份”、“我的”）进来时，看到一页说明：“云端账号已停用”，为什么、旧配置怎么搬，以及四个按钮（WebDAV、设备同步、备份与恢复、平台账号）。4.x 的界面里没有任何地方再链接这三个路由（备份页的云端账号块 A12.4 去掉了，只剩说明页给旧链接兜底）。
- 内部怎么工作：`AuthPage(route:)` 不读任何数据，按钮调用 `AppNavigator.toNamed` 进对应路由；没有网络请求。
- 完成度：K01.1（`e5ae55fbf`）做了说明页；I01.1 去掉了 Firebase 依赖（I01.1 记录的问题 10：Firebase 依赖 Google 服务，很多国内手机上用不了）；A12.3 按设计定稿。功能点 F-ACC-08“不做”。

## 代码地图

| 文件 | 职责 |
|---|---|
| `apps/pure_live/lib/features/auth/auth_page.dart`（119 行） | `AuthPage`（`:22`）：说明块（`auth-retired`）、四个入口；路由由 `routes/` 注册到 `kSignIn`、`kMine`、`kUserManage` |
| `apps/pure_live/lib/routes/route_path.dart` | 三个路由常量（3.x 的名字不变） |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `apps/pure_live/test/features/account/account_page_test.dart` | 三个旧路由都显示停用说明、点 WebDAV 进对应路由（`:651`）；宽屏和横屏最宽 720（`:692`） |

## 3.x 基线

- `git show v3.2.11:lib/modules/auth/`（13 个文件约 3400 行）：`auth_controller.dart`（Firebase 登录状态）、`sign_in_page.dart`、`mine_page.dart`（预览云端配置、上传、下载覆盖本机、退出）、`user_manage_page.dart` 和 `user_management_actions.dart`（管理员：上传权限、升降管理员、删除用户）、`utils/firebase_manager.dart`、`components/firebase_email_auth.dart`；`lib/firebase_options.dart`。登录后本机没有关注时自动下载云端配置。
- 3.x 备份页的“云端备份”块（`lib/modules/backup/backup_page.dart`）进 `kMine` / `kSignIn`。
- 不保留：整个云端账号（用户决定，F-ACC-08）。保留：三个路由的名字（旧链接不至于打不开）。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 3.x 云端上的配置只能先用 3.x 下载、导出备份，再在 4.x 恢复 | — | 已经覆盖安装 4.x 的用户拿不回云端配置（除非另找设备装 3.x） | 不做（说明页写明了办法）；用户反馈多时进 V01 评估 |
| 没有任何云端同步 | — | 多设备之间只能手动（WebDAV、设备同步、文件） | 不做；WebDAV 定时备份、选择同步内容（V01.6）是现有的提议方向 |

## 相关决定和规范

- 用户决定不恢复 Firebase 云端账号（I01.1、A12.3；清点 F-ACC-08“不做”）；D-004（只做 Android；Firebase 依赖的 Google 服务在很多国内手机上用不了，是去掉它的原因之一，I01.1 记录）。

## 测试和验证

- 自动测试：`cd apps/pure_live && flutter test test/features/account/account_page_test.dart`（云账号的两个用例）。
- 真机：不需要单独验证；A12.3 的界面在 S03.1 统一验证时看一眼。

## 路线

无登记的任务。以后如果用户要“多设备自动同步”或“账号体系”，先在 V01 写提议（参考：WebDAV 定时备份、设备同步选择内容 V01.6、上游的做法），确认后再在本组登记实现任务。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [K 账号和登录](../README.md)。

- 代码：`features/auth/`
- 进度：还没有任务


还没有任务。

<!-- docs:生成结束 -->
