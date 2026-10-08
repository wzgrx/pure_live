# K01.2 哔哩哔哩多账号：记录

- 日期：2026-10-09
- 执行者：Claude（Opus 5.5）
- 分支和提交：本机工作区 `worktree-agent-a985670228f08341b`，一个提交（`[K01.2]`：V01.2 的评估和设计、登记、代码、测试、文档），没有推送、没有合并
- 任务书：[brief.md](brief.md)；说明：[README.md](README.md)；设计选择：[V01.2 README](../../../V-需求和反馈/V01-新功能提议/V01.2-哔哩哔哩多账号/README.md) 文末 S1～S17

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| 验收 1 核验过的登录记进名册、加密、同 uid 更新、最多 5 个 | 做了 | 核验不了（没网）的不记：没有 uid，分不清是谁（V01.2 S4） |
| 验收 2 账号页“已记住的账号”：当前、切换、删除、添加 | 做了 | 放在哔哩哔哩账号页，不是提议初稿说的“账号总览一行展开”（S6：总览是 A12.1 确认过的样子，不动） |
| 验收 3 切换后 Cookie、uid、直播间重连、重新核验、失效的退出并忘掉 | 做了 | |
| 验收 4 退出 = 忘掉，一个账号时和以前一样 | 做了 | 一个账号的用户唯一看得到的变化：哔哩哔哩账号页多一组（当前账号一行、“添加账号”一行） |
| 验收 5 备份、设备同步和当前 Cookie 走同一条路；收到的加进名册 | 做了 | 收到时“加进”而不是“替换”（S13：预览承诺“其他账号不变”） |
| 验收 6 Keystore 出错什么都不变、Cookie 不进日志、没有真实数据 | 做了 | 记进名册失败只记日志、不影响登录本身（登录已经存好了） |
| 提议 c5 的效果图和评审页 | 没做 | D-036 授权维护者定（S16）；布局用 widget 测试固定，真机截图在 verify.md 里补 |
| 提议的“头像” | 没做 | 用名字的第一个字（S11：核验接口不回头像，上游的头像字段也一直是空的） |

## 根因（为什么原来换账号会丢掉旧登录）

- 一个平台只有一份 Cookie：`packages/live_store/lib/src/secrets.dart` 的 `SecretRefs.cookie(site)`；`AccountActions.save`（`apps/pure_live/lib/features/account/account_services.dart`）直接覆盖，旧的就没了。新功能，不是 bug，没有“改之前会失败”的测试；行为测试见下。

## 改了哪些文件

- `packages/live_store/lib/src/accounts.dart`（新）：`SavedAccount`、`AccountRoster`。
- `packages/live_store/lib/src/secrets.dart`：`SecretRefs.account`、`accountsOf`、`accountPrefix`；`SecretStore.refs`。
- `packages/live_store/lib/src/live_store.dart`、`lib/live_store.dart`：`LiveStore.accounts`，导出。
- `packages/live_store/lib/src/backup/backup_service.dart`：带账号时写 `<平台>Accounts`；恢复时 `merge`。
- `packages/live_store/lib/src/legacy/legacy_snapshot.dart`：`savedAccounts`、`accountsSuffix`，读 `cookie` 分区里的名册。
- `apps/pure_live/lib/features/account/account_services.dart`：`rememberBilibili`（替换 `rememberBilibiliUid`）、`bilibiliAccounts`、`isCurrentBilibili`、`bilibiliCurrentUnremembered`、`switchBilibili`、`forgetBilibili`；`signOut` 忘掉当前账号；`storeBilibiliLogin` 传名字。
- `apps/pure_live/lib/features/account/bilibili_accounts.dart`（新）：`BilibiliAccountsGroup`、`savedAccountName`。
- `apps/pure_live/lib/features/account/platform_cookie_view.dart`：名册一组、`_switchTo`、`_forget`、`_addAccount`、`_reloadStored`；调用改名。
- `apps/pure_live/lib/features/account/cookie_editor.dart`：`CookieEditorScaffold.accounts`（状态卡下面）、`storedRevision`。
- `apps/pure_live/lib/features/account/account_list_view.dart`：没登录但有记住的账号时进账号页；调用改名。
- `apps/pure_live/lib/app/startup.dart`：调用改名，传名字。
- `apps/pure_live/lib/shared/backup/backup_data.dart`：`accountEntriesIn`（预览的账号数量）；`sync_parts.dart`：勾选框的账号数量用它。
- `apps/pure_live/assets/translations/zh.json`、`en.json`。
- 测试：`packages/live_store/test/accounts_test.dart`（新）、`apps/pure_live/test/features/account/account_page_test.dart`、`apps/pure_live/test/shared/shared_test.dart`、`apps/pure_live/test/shared/sync_parts_test.dart`、`apps/pure_live/test/features/remote_receiver/remote_sync_test.dart`。
- 文档：V01.2 README（评估结论和设计 S1～S17、经过）；本文件夹 README、brief、record、verify；K、K01、J02、J03、J05、A12 的说明；`docs/inventory/OWNERS.toml`（`accounts.dart` 归 K01）；`docs/tasks.toml`（V01.2 改“已确认”、`to = ["K01.2"]`；新登记 K01.2，“待真机”）；`python3 tools/docs/docs.py`、`tools/docs/owners.py` 生成的文件。

## 新设置、翻译键、门禁基线

- 没有新设置（名册在加密的秘密里，不是设置；V01.2 S1）；3.x 的键不变（D-018）。
- 新存储：秘密 `account/<平台>/<uid>`（值是 JSON：`name`、`cookie`、`usedAt` 秒，整体加密）；备份 `cookie` 分区的 `bilibiliAccounts`（列表：`uid`、`name`、`cookie`、`usedAt`），只在带账号时有。
- 新翻译键（zh、en 都加，按键名排序）：`account_add`（添加账号）、`account_add_full`（已记住 {count} 个，再添加会删掉最久没用的那个）、`account_add_hint`（扫码登录另一个账号，现在的账号会留在这里）、`account_current`（当前账号）、`account_forget`（删除这个账号）、`account_forget_confirm`、`account_forget_title`（删除账号）、`account_forgotten`（已删除“{name}”）、`account_saved_accounts`（已记住的账号）、`account_saved_accounts_note`、`account_switch`（切换）、`account_switch_confirm`、`account_switch_confirm_unremembered`、`account_switch_title`（切换账号）、`account_switched`（已切换到“{name}”）、`account_uid`（UID {uid}）。没有删改旧键。
- 门禁基线没动；`account` 目录没有直接写颜色和图标（颜色取主题，图标 `AppIcons.add`、`AppIcons.delete`）。

## 测试

- 新增 21 个：`accounts_test.dart` 9 个（加密存和顺序、同 uid 更新、没变不写；上限 5；切换一次写入并记住离开的；删除；Keystore 出错名册和当前 Cookie 都不变；本机打不开的条目；只有带账号的备份有名册；恢复加进名册、没名册的文件不动名册；坏条目跳过）；`account_page_test.dart` 9 个（一个账号和以前一样：记入、当前、退出就忘、总览照旧进扫码；切换：先问、Cookie 和 uid、`cookieChanges`、页面重新核验、Cookie 框不算改动、离开的能切回、点整行也能切换；切到失效的退出并忘掉；没登录时总览进账号页、删除先问；添加账号走扫码页回来；满 5 个的提示；切换时 Keystore 出错什么都不变；横屏 852×393 加 1.3 倍字号、宽屏 1280 放得下、按钮点得到）；`sync_parts_test.dart` 1 个（名册只随“账号 Cookie”一类，数量只算一次，收到加进名册）；`remote_sync_test.dart` 1 个（真 HTTP：“同步账号 Cookie”关着时不出设备、没勾“账号 Cookie”不带、勾了加进对方名册）；`shared_test.dart` 的启动核验测试加了 2 条断言（记入、失效时忘掉）。
- 改了 0 个已有测试的期望（`account_page_test.dart` 的假核验多认一个 `SESSDATA=bob`（Bob，uid 7），测试替身多一个 `accounts` 参数）。
- `dart test`（live_store）71 个全过；`flutter test test/features/account/` 39 个全过；`test/features/remote_receiver/`、`test/shared/sync_parts_test.dart`、`test/shared/shared_test.dart` 全过；两个包 `dart analyze --fatal-infos` 无问题。
- 门禁：见下面“门禁”。

## 门禁

- `bash tools/gate/gate.sh --all`（日志在本机临时目录，不进仓库）：`gate: passed (all, 14 members)`；依赖、FFmpeg 包、依赖方向、样本隐私、界面结构、文档、归属、每个成员的格式、分析、测试都过。

## 真机上要看的

**要两个真实的哔哩哔哩账号**（维护者自己的测试账号）和一台能扫码的手机；K90 上用测试包按 [verify.md](verify.md) 的 17 步做，设备同步那几步要第二台 4.x。截图遮住 Cookie、名字和 UID。重点：

1. 只有一个账号时：扫码登录、退出和以前一样；哔哩哔哩账号页多了“已记住的账号”一组（当前账号一行、“添加账号”一行），退出后这组消失、总览点“哔哩哔哩”照旧进扫码。
2. “添加账号”扫第二个账号后两行都在；切换先问，切换后状态卡核验成正确的名字。
3. 开着一个哔哩哔哩直播间时切换：弹幕重连，昵称是新账号能看到的完整昵称（D-013），没有“登录可能失效”的提示。
4. 杀掉重开后名册和当前账号都还在（Keystore）。
5. 删除、退出当前账号：删掉的、退出的都从名册消失，另一个还在、能切换；没登录但记着账号时总览点“哔哩哔哩”进账号页。
6. 横屏、大字号、深色模式下这一组不被截断、按钮点得到。
7. 设备同步：“同步账号 Cookie”关着、或者没勾“账号 Cookie”时对方的名册和登录不变；都打开时对方多出这些账号，原来的还在。本地备份文件里没有 `bilibiliAccounts`。

## 可能冲突的文件

- `platform_cookie_view.dart`、`cookie_editor.dart`（A12.2 的后续、A04.1 顶栏）；`account_services.dart`（K02 的后续）；`backup_service.dart`、`legacy_snapshot.dart`（J03、J06）；翻译文件。
