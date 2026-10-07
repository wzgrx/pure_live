# V01.2 哔哩哔哩多账号：账号名册和切换（先出方案）

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能（新功能提议）
- 来源：上游 pure_live_TV `6ba16c55`（电视版加了哔哩哔哩账号名册，W01.1 2026-10-03 对照列为“可以借鉴的新功能”）；旧任务清单 T10a.4
- 旧编号：T10a.4
- 相关：决定 D-026、D-018、D-013（访客打码昵称不还原，靠登录）；账号 [K01](../../../K-账号和登录/README.md)、加密存储 [K02.1](../../../K-账号和登录/K02-登录状态/K02.1-Cookie和密码加密存储验证/README.md)；账号界面 [A12.1](../../../A-界面设计/A12-账号和数据界面/A12.1-账号总览/README.md)、[A12.2](../../../A-界面设计/A12-账号和数据界面/A12.2-登录和Cookie/README.md)；电视的启动解锁依赖它（[A17.2](../../../A-界面设计/A17-电视界面/A17.2-电视外壳/README.md) 的“开发前要知道的”）；任务书 [brief.md](brief.md)

## 目标

有两个以上哔哩哔哩账号的用户（大号、小号，或家里几个人共用一台电视或平板），现在换账号要退出再扫码，或者去 Cookie 页粘贴另一份 Cookie。提议：记住登录过的哔哩哔哩账号（名字、头像、uid），在账号页一键切换，不用重新扫码。

本文件是**评估初稿**，由执行者补完、出图、发评审页，**由用户决定做不做**（D-026）。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11:lib/`） | 4.x 现在 | 上游 pure_live_TV（`~/ref/pure_live_TV`） | 提议要做到 |
|---|---|---|---|---|
| 账号数量 | 每个平台一份 Cookie（`common/services/settings/cookie_settings_controller.dart:10` 的 `bilibiliCookie`，明文存在设置盒子里） | 同：`packages/live_store/lib/src/secrets.dart` 的 `SecretRefs.cookie(site)`（`cookie/bilibili`），加密存（Keystore）；uid 在设置 `bilibiliUid`（`settings.dart:1368`） | `lib/services/cookie_manager/bilibili/bilibili_account_roster.dart`（183 行）：名册 `BilibiliRosterAccount`（uid、名字、头像、Cookie、锁码）存在偏好里（**明文**），一个“当前账号” | 名册里每个账号的 Cookie 和当前的一样加密存 |
| 登录 | 扫码、网页登录、粘贴 Cookie | `features/account/bilibili_qr_login.dart`、`bilibili_web_login.dart`、`cookie_editor.dart`；保存走 `features/account/account_services.dart:101` 的 `AccountActions.save`（换 Cookie 时把 uid 清成 0 等验证） | 设备扫码登录，登录成功后 `recordActive` 记进名册 | 登录成功就记进名册（新账号加一条，同一 uid 更新） |
| 切换 | 退出再登录 | 同 3.x | `switchTo(uid)`：把它的 Cookie 设成当前，重新取账号信息 | 账号页列出名册，点一个“切换到这个账号”；切换后已打开的直播间弹幕重连（`room_controller.dart:309` 已经监听 `cookieChanges`） |
| 删除 | 退出 | `AccountActions.signOut`（`account_services.dart:116`） | `remove(uid)`（删当前的要先退出） | 名册里删一个；删当前的等于退出 |
| 锁 | — | — | 每个账号可设遥控器方向键的锁码，启动时要解锁（`widgets/account_lock.dart`，639 行） | **手机不做锁**（电视的启动解锁在 A17.2 单独评估） |
| 备份和同步 | 备份照 3.x 的格式 | 新建的备份照 3.x **不带账号**（`apps/pure_live/lib/shared/backup/backup_data.dart:36-38`：“3.x layout, no accounts”）；恢复的文件里带了 Cookie 时会写入，预览里算“账号 N 个”（`:231`、`:343`）；设备同步发的是同一份数据，页面上“同步账号”开关打开时才带 Cookie（`features/remote_receiver/remote_sync_service.dart:122` 的 `includeAccounts` 默认关、`:380` `exportAll(includeSensitiveData: …)`） | — | 名册跟当前 Cookie 一样：备份不带；设备同步只在“同步账号”打开时带 |

## 方案（评估初稿）

| 编号 | 改什么 | 目标组 |
|---|---|---|
| c1 | 名册存储：`live_store` 新加一类秘密 `account/bilibili/<uid>`（Cookie，加密）和一张普通表（uid、名字、头像地址、最后使用时间）；当前账号仍是 `cookie/bilibili`，3.x 的键和含义不变（D-018） | K01、J02（存储） |
| c2 | 登录成功（扫码、网页、粘贴后验证通过）时把账号写进名册；验证失败的不写 | K01 |
| c3 | 切换：把名册里那个账号的 Cookie 写成当前 Cookie、`bilibiliUid` 写成它的 uid；`cookieChanges` 触发已开直播间的弹幕重连（D01.32 已有）；切换后重新验证一次，Cookie 失效时标“已失效”、提示重新登录 | K01、K02 |
| c4 | 删除：删名册一条；删的是当前账号时等于退出 | K01 |
| c5 | 界面：账号页哔哩哔哩一行展开成“当前账号 + 其他账号 + 添加账号”；每个账号头像、名字、uid、“切换”“删除”；切换和删除前确认 | A12.1、A12.2（要出图） |
| c6 | 备份和设备同步：名册和当前 Cookie 走同一条规则（备份不带；设备同步“同步账号”打开时带上名册）；恢复带 Cookie 的旧文件时只写当前账号，不动名册 | J03、J05 |

不做：电视版的方向键锁码（手机没有这个需求；电视端开工时随 A17.2 评估）。

规模：中（存储和逻辑半天，界面出图评审半天到一天）。

## 验证（做了以后怎么验证）

- 自动测试：名册的增删改、切换后当前 Cookie 和 uid 正确、Keystore 失败时不丢名册、备份和恢复的规则；账号页的布局测试（竖屏、横屏、宽屏）。
- 真机：K90 上扫码登录两个账号，切换后进一个直播间看弹幕昵称是不是这个账号能看到的完整昵称（D-013），杀掉重开仍是切换后的账号（K02.1 的 Keystore）。

## 留下的问题

- 需要用户决定：做不做；名册里最多几个账号（建议 5 个）；名册是否跟设备同步走（建议和现在的 Cookie 一样，跟“同步账号”开关）。
- 和电视的关系：A17.2 的启动解锁依赖多账号和锁码；如果手机做了 c1～c4，电视只需要再加锁码。
