# K01.2 哔哩哔哩多账号：任务书

## 背景

- 来源：新功能提议 [V01.2](../../../V-需求和反馈/V01-新功能提议/V01.2-哔哩哔哩多账号/README.md)，D-036 同意做（第三档）；上游 pure_live_TV `6ba16c55`（电视版的哔哩哔哩账号名册，W01.1 列为可借鉴）；旧任务清单 T10a.4。
- 现象：换哔哩哔哩账号要退出再扫码，或者去 Cookie 页粘贴另一份；访客看到的弹幕昵称是打码的（D-013），有人会在大号、小号之间来回登录。
- 为什么现在做：D-036 按 V01 路线逐个做；设计选择按 D-003 由维护者定（V01.2 README 文末 S1～S17）。
- 已经做过的：K01.1（登录方式）、K02.2（保存失败的提示、退出清网页 Cookie）、J05.1（设备同步勾选内容）。

## 目标和验收

1. 核验过的哔哩哔哩登录（扫码、网页、粘贴、账号页核验、启动核验）记进名册：uid、名字、Cookie，加密存；同 uid 更新；最多 5 个，多了忘掉最久没用的（不忘当前的）。
2. 哔哩哔哩账号页有“已记住的账号”：当前账号标出来；其他账号能切换（先问）、能删除（先问）；“添加账号”进扫码页。
3. 切换后当前 Cookie 和 `bilibiliUid` 是那个账号的，打开着的直播间重连弹幕，页面重新核验；失效的退出并忘掉；离开的账号留在名册里。
4. 退出当前账号同时忘掉它；只有一个账号时登录、退出、备份、同步和以前完全一样。
5. 名册和当前 Cookie 走同一条路：本地、WebDAV 备份不带；设备同步只在“同步账号 Cookie”打开并勾着“账号 Cookie”时带；收到的加进名册、不删本机其他的；没带名册的文件不动名册。
6. Keystore 出错时什么都不变（名册和当前 Cookie 都不变），页面提示；Cookie 不进日志；仓库里没有真实 Cookie 和账号。

## 现状（读代码得出，写文件:行）

- 当前账号：`packages/live_store/lib/src/secrets.dart` 的 `SecretRefs.cookie`、`SecretStore.writeAll`（先全部加密再一个事务写）；`bilibiliUid`（`settings.dart:1481`）。
- 登录后记 uid：`apps/pure_live/lib/features/account/account_services.dart` 的 `rememberBilibiliUid`，被 `storeBilibiliLogin`、`platform_cookie_view.dart`、`account_list_view.dart`、`app/startup.dart` 调用。
- 退出：`AccountActions.signOut`。
- 备份：`packages/live_store/lib/src/backup/backup_service.dart` 的 `exportAll`（`includeSensitiveData` 时 `cookie` 分区）、`restoreAll`；`legacy_snapshot.dart` 的 `_readSecrets`；设备同步 `remote_sync_service.dart` 的 `includeAccounts`；J05.1 的 `shared/backup/sync_parts.dart`。

## 3.x 基线

- `git show v3.2.11:lib/common/services/settings/cookie_settings_controller.dart`：一个平台一份 Cookie；`parseConfig` 只取认识的键（多一个 `bilibiliAccounts` 没有影响）。
- 要保留：`cookie/bilibili` 和 `bilibiliUid` 的含义（D-018）；3.x 导入的 Cookie 照旧是当前账号；退出确认的文字。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 6 节、第 8 节、第 14 节）。
2. `docs/specs/ENGINEERING.md`（安全）；`docs/specs/UI.md` 第 3 节、第 7 节。
3. V01.2 README（评估结论和设计）；本文件夹 `README.md`；`docs/K-账号和登录/README.md`、K01、K02 的说明。

## 范围

- 可以改：`packages/live_store/lib/src/`（新的名册、`secrets.dart`、备份的 `cookie` 分区）、`apps/pure_live/lib/features/account/`、`apps/pure_live/lib/app/startup.dart`（调用改名）、`apps/pure_live/lib/shared/backup/`（账号数量）、翻译文件、对应测试；K、V01.2、J、A12 和本文件夹的文档；`docs/tasks.toml`、`docs/inventory/OWNERS.toml`。
- 不能改：平台层（`packages/live_core`）；3.x 的设置键；备份的其他分区；设备同步的协议和配对码；版本号。

## 方案和阶段

| 阶段 | 做什么（对应 README 的 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | c1～c6（一个阶段：存储、记入、切换和删除、界面、总览入口、备份和同步） | 见 README“结果” | 自动测试全过，门禁通过 |

## 测试

- `packages/live_store/test/accounts_test.dart`：加密存、最近用的在前、同 uid 更新、没变不写；上限 5；切换一次写入并记住离开的；删除；Keystore 出错什么都不变；本机打不开的条目；备份只在带账号时有、恢复加进名册、没有名册的文件不动名册、坏条目跳过。
- `apps/pure_live/test/features/account/account_page_test.dart`：一个账号和以前一样（记入、当前、退出就忘、总览进扫码）；切换（先问、Cookie 和 uid、通知、页面重新核验、离开的可以切回）；切到失效的；没登录时总览进账号页、删除先问；添加账号；满了的提示；切换时 Keystore 出错；横屏 1.3 倍字号和宽屏。
- `apps/pure_live/test/shared/shared_test.dart`：启动核验记入、失效时忘掉。
- `apps/pure_live/test/shared/sync_parts_test.dart`、`apps/pure_live/test/features/remote_receiver/remote_sync_test.dart`：名册只随“账号 Cookie”一类和“同步账号 Cookie”走，数量只算一次，收到的加进名册。

## 真机验证（维护者在 K90 上做）

见 [verify.md](verify.md)（要两个真实的哔哩哔哩账号）。

## 风险和注意

- 名册里每一条都是登录凭据：只存加密的；测试里只用假 Cookie（`SESSDATA=fake-…`、`SESSDATA=ok` 这类）；日志只记加密存储的错误。
- 切换会让打开着的直播间重连弹幕（`cookieChanges`），和换 Cookie 一样。
- `platform_cookie_view.dart`、`cookie_editor.dart` 和 A12.2 的后续改动冲突。

## 环境和提交

- `source ~/tools/purelive-env.sh`；新工作区先 `bash tools/ffmpeg_kit/fetch.sh android`、`bash tools/ffmpeg_kit/fetch.sh linux`、`flutter pub get`。
- 提交信息以 `[K01.2]` 开头；`bash tools/gate/gate.sh --all` 通过。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节。

## 报告（中文，简洁）

每条做到没有；测试数量；改了哪些文件；翻译键；要在真机上看的。
