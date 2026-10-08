# K01.2 哔哩哔哩多账号：记住登录过的账号，在哔哩哔哩账号页一键切换（接 V01.2）

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能
- 来源：新功能提议 [V01.2](../../../V-需求和反馈/V01-新功能提议/V01.2-哔哩哔哩多账号/README.md)（D-036 同意做）；上游 pure_live_TV `6ba16c55`（电视版的哔哩哔哩账号名册）
- 相关：决定 D-036、D-003（设计由维护者选，V01.2 README 文末 S1～S17）、D-018（3.x 的键不变）、D-013（访客打码昵称，靠登录）；登录和退出 [K01.1](../K01.1-账号与登录/README.md)；加密存储 [K02.1](../../K02-登录状态/K02.1-Cookie和密码加密存储验证/README.md)、保存失败的提示 [K02.2](../../K02-登录状态/K02.2-加密存储失败时提示/README.md)；设备同步勾选内容 [J05.1](../../../J-设置和数据/J05-设备同步/J05.1-同步前勾选内容/README.md)；界面 [A12.1](../../../A-界面设计/A12-账号和数据界面/A12.1-账号总览/README.md)、[A12.2](../../../A-界面设计/A12-账号和数据界面/A12.2-登录和Cookie/README.md)；任务书 [brief.md](brief.md)、记录 [record.md](record.md)、真机 [verify.md](verify.md)

## 目标

有大号、小号，或者几个人共用一台设备的用户，换哔哩哔哩账号不用再退出、重新扫码或粘贴 Cookie：登录过的账号会记在哔哩哔哩账号页的“已记住的账号”里（最多 5 个），点“切换”就换过去，正在看的直播间用新账号重连弹幕（看到这个账号能看到的完整昵称，D-013）。只有一个账号的用户用起来和以前一样：退出就忘掉，备份不带，同步只在“同步账号 Cookie”打开时带。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11:lib/`） | 改之前（`apps/pure_live/lib/`、`packages/live_store/`） | 要做到 |
|---|---|---|---|
| 账号数量 | 每个平台一份 Cookie（`cookie_settings_controller.dart:10`，明文） | 同，加密存在 `cookie/bilibili`（`secrets.dart`），uid 在设置 `bilibiliUid` | 当前账号不变；另外记住核验过的账号，每个一条加密秘密 |
| 换账号 | 退出再登录，或粘贴另一份 Cookie | 同 3.x；换了以后旧的 Cookie 就没了 | 账号页点“切换”；离开的账号留着，可以切回 |
| 退出 | 清 Cookie 和 uid | `AccountActions.signOut` 清 Cookie、uid、WebView 的哔哩哔哩 Cookie | 同时从名册删掉这个账号（本机不留它的 Cookie） |
| 备份、同步 | 带账号的备份写 `cookie` 分区 | 本地、WebDAV 备份不带；设备同步“同步账号 Cookie”打开、勾着“账号 Cookie”（J05.1）才带 | 名册放在同一个 `cookie` 分区（`bilibiliAccounts`），走同一条路；收到的加进名册 |

## 结果

- c1 存储（`packages/live_store/lib/src/accounts.dart`，新）：`SavedAccount`（uid、名字、Cookie、最后使用时间）；`AccountRoster`（`LiveStore.accounts`）：`of`（最近用的在前）、`find`、`remember`（新账号或新 Cookie 记成“现在用的”，没变不写，超过 `limit` = 5 时忘掉最久没用的其他账号，顺带删掉本机打不开的旧条目）、`switchTo`（把那个账号的 Cookie 写成当前 Cookie，和名册一次写入；可以顺带记住正在离开的账号）、`forget`、`forgetting`（给退出用：和删 Cookie 同一次写入）、`merge`（收到的名册：同 uid 替换，其余不动，不忘正在用的）。每个账号一条秘密 `account/<平台>/<uid>`（`SecretRefs.account`），名字和 Cookie 都在密文里；`SecretStore.refs` 列出能打开的秘密名。
- c2 记进名册（`apps/pure_live/lib/features/account/account_services.dart`）：`rememberBilibiliUid` 改成 `rememberBilibili(uid, name:)`：记 uid，同时把当前 Cookie 以这个 uid 和名字记进名册；加密存储出错只记日志（不含 Cookie），登录本身照样有效。五个调用处（扫码和网页登录的 `storeBilibiliLogin`、`platform_cookie_view.dart` 的 `_save` 和 `_verify`、`account_list_view.dart` 的 `_check`、`app/startup.dart` 的 `verifyBilibiliLogin`）都传上名字。
- c3 切换和删除（`account_services.dart`）：`bilibiliAccounts`、`isCurrentBilibili`（Cookie 相同，或 uid 是当前核验过的 uid）、`bilibiliCurrentUnremembered`、`switchBilibili`（先写 `bilibiliUid` 再一次写入 Cookie 和名册；失败时 uid 写回原来的再抛出）、`forgetBilibili`；`signOut(bilibili)` 在删 Cookie 的同一次写入里忘掉当前账号。
- c4 界面（`features/account/bilibili_accounts.dart`，新；`platform_cookie_view.dart`；`cookie_editor.dart`）：哔哩哔哩账号页的状态卡下面一组“已记住的账号”（有登录或有记住的账号时才有）：每行名字的第一个字、名字（没有名字时“UID n”）、“UID n · 当前账号”（主色）或“UID n”；不是当前的行尾“切换”和删除（红色图标），点整行也是切换；最后一行“添加账号”（满了写“已记住 5 个，再添加会删掉最久没用的那个”）；组下面一句说明。切换先问（“切换账号”），成功后提示“已切换到“X””，Cookie 框换成新的（不算没保存的改动，`CookieEditorScaffold.storedRevision`）、重新核验；平台说新账号没登录 → 提示“哔哩哔哩登录已失效，请重新登录”、退出并忘掉它。删除先问（“删除账号”，红色“删除”）。“添加账号”进扫码页，回来后页面换成新登录。加密存储出错时提示 K02.2 的那句话，什么都不变。
- c5 账号总览（`account_list_view.dart` 的 `_open`）：行的样子不变；哔哩哔哩没登录但有记住的账号时，点它进哔哩哔哩账号页（原来直接进扫码；什么都没记住时照旧进扫码）。
- c6 备份和同步：`BackupService.exportAll(includeSensitiveData: true)` 在 `cookie` 分区写 `<平台>Accounts`（`bilibiliAccounts`：uid、名字、Cookie、最后使用的秒数）；不带账号时什么都不写（本地、WebDAV 备份照旧不带）。`LegacySnapshot.savedAccounts` 读它（坏条目跳过）；`restoreAll` 写完当前 Cookie 后 `merge`。设备同步：发送、被拉取都随“同步账号 Cookie”；J05.1 的“账号 Cookie”一类就是整个 `cookie` 分区，名册跟着它，不勾就不带。预览里“写入 N 项账号信息（其他账号不变）”和勾选框里的数量用 `accountEntriesIn`（`shared/backup/backup_data.dart`）：Cookie 加上名册里不是当前 Cookie 的账号。3.x 和旧 4.x 不认识这个键，忽略。
- 不做：方向键锁码和电视的启动解锁（V01.2 S15）；真头像（S11）；其他平台（S17）；后台核验其他账号（S8）。

## 验证

- 自动测试：见 [record.md](record.md)“测试”。
- 真机：[verify.md](verify.md)，**要两个真实的哔哩哔哩账号**；待真机。

## 留下的问题

- 用户想改的时候：退出时保留在名册里（S5）、在账号总览里直接切换（S6）、上限（`AccountRoster.limit`）都是一处改动。
- 电视的启动解锁（A17.2）开工时，在 `SavedAccount` 上加锁码即可。
