# V01.2 哔哩哔哩多账号：任务书

## 背景

- 来源：上游 pure_live_TV `6ba16c55` 给电视版加了哔哩哔哩账号名册（`lib/services/cookie_manager/bilibili/bilibili_account_roster.dart`），W01.1（2026-10-03 上游对照）列为“可以借鉴的新功能”，按 D-027 进 V01；旧任务清单 T10a.4。
- 现象：换哔哩哔哩账号要退出再扫码，或去 Cookie 页粘贴；访客看到的弹幕昵称是打码的（D-013），所以有人会在大号、小号之间来回登录。
- 为什么是第三档：新功能，要用户确认（D-026）；现在只有一个账号也能用。
- 已经做过的：本文件夹 `README.md` 的评估初稿（3.x、4.x、上游对照表，改动清单 c1～c6，不做电视的锁码）。

## 目标和验收

本任务是**提议**：做到“用户能拍板”为止，实现在目标组。

1. 评估补完：核对 README 的文件:行；读完上游的 `bilibili_account_roster.dart`、`bilibili_account_service.dart`（118 行）、`features/settings/pages/account_bilibili_page.dart`（389 行），写清借鉴哪些行为（登录即记入、同 uid 更新、切换后重取账号信息）、不借鉴哪些（明文存 Cookie、锁码）。
2. 出图：账号页哔哩哔哩一行展开后的样子（当前账号、其他账号、添加账号）、切换确认、删除确认、Cookie 失效的样子；竖屏和横屏（宽屏右栏）。
3. 评审页：`page.json`（说明、对比 4.x 现在、上游电视版、改了什么、需要你选的：做不做 / 最多几个 / 跟不跟备份），发布给用户；维护者改“待确认”。
4. 用户回复后：确认 → 建议的 DECISIONS 条目和目标组任务（K01 存储和逻辑、A12.1/A12.2 界面）；否决 → V04 的说明。
5. （阶段 2）目标组任务都完成后，本任务改“完成”。

## 现状（读代码得出，写文件:行）

- 秘密：`packages/live_store/lib/src/secrets.dart`：`SecretRefs.cookie(site)` → `cookie/bilibili`；`SecretStore` 加载时全部解开，`cookieFor` 同步读；`cookieChanges` 流（应用的 `StoreCookieVault`，`apps/pure_live/lib/app/platforms.dart:52`）。打不开的（换机、重装）当作未登录并列进 `unreadable`。
- 账号逻辑：`apps/pure_live/lib/features/account/account_services.dart`：`AccountActions.save`（`:101`，换哔哩哔哩 Cookie 时 `bilibiliUid` 清 0 等验证）、`rememberBilibiliUid`（`:110`）、`signOut`（`:116`）；平台表 `account_platforms.dart:88-95`；状态 `account_state.dart`（`AccountVerified`、`AccountRejected`）。
- 登录界面：`bilibili_qr_login.dart`（395 行）、`bilibili_web_login.dart`（230 行）、`cookie_editor.dart`（427 行）、列表 `account_list_view.dart`（224 行，监听 `cookieChanges`）。
- 换账号以后：`apps/pure_live/lib/features/live_play/logic/room_controller.dart:309` 监听 `cookieChanges`，`_onLoginChanged` 重连弹幕（D01.32 用到）。
- 备份：新备份照 3.x 不带账号（`apps/pure_live/lib/shared/backup/backup_data.dart:36-38`）；设备同步“同步账号”开关打开时带 Cookie（`features/remote_receiver/remote_sync_service.dart:122`、`:380`）。

## 3.x 基线

- `git show v3.2.11:lib/common/services/settings/cookie_settings_controller.dart`：`bilibiliCookie`（`:10`）一个平台一份，明文；3.x 没有多账号。
- 要保留：`cookie/bilibili` 仍是“当前账号”，3.x 导入的 Cookie 照旧进这里（D-018）；`bilibiliUid` 的含义不变。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 4.1 节、第 6 节）。
2. `docs/DECISIONS.md` D-013、D-018、D-026；`docs/specs/UI.md` 第 3 节。
3. 本文件夹 `README.md`；`docs/A-界面设计/A12-账号和数据界面/A12.1-账号总览/README.md`、`A12.2-登录和Cookie/README.md`（现在的样子和确认的改动）；`docs/K-账号和登录/README.md`；`docs/A-界面设计/A17-电视界面/A17.2-电视外壳/README.md`（启动解锁依赖多账号）。
4. 上游：`~/ref/pure_live_TV/lib/services/cookie_manager/bilibili/`、`lib/features/settings/pages/account_bilibili_page.dart`（只读）。

## 范围

- 可以改：本文件夹（README、`src/`、`v4-*.jpg`、`page.json`、`page/`）。
- 不能改：代码；`docs/tasks.toml`、`docs/DECISIONS.md`（维护者改）；其他组文档；版本号和发布文件。
- 不能做：把真实 Cookie、uid、头像放进效果图和仓库（图里用假名字和占位头像）。

## 方案和阶段

| 阶段 | 做什么 | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 方案和对比页 | 补完评估；出图（账号行展开、切换和删除确认、失效）；`page.json` 生成评审页并发布 | 本文件夹 | 评审页地址写进 README“经过”；报告给维护者改“待确认” |
| 2 开发 | 用户确认后由目标组任务做（K01 存储和逻辑 c1～c4、c6；A12 界面 c5）；本任务只在它们完成后改“完成” | — | 目标组任务都“完成” |

用户确认这一步不单独成阶段（登记表只有两个阶段）：评审页发出后等回复，回复后按 PROCESS 第 6 节第 3 步处理。

## 测试

- 本任务不写测试。README 的“验证”写清实现任务要加的测试（名册增删改、切换后当前 Cookie 和 uid、Keystore 失败、备份规则、账号页三种布局）。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 无（提议阶段不上机） | — |

## 风险和注意

- 安全：名册里的每个 Cookie 都是登录凭据，必须和当前 Cookie 一样加密（上游电视版是明文，不照搬）；截图打码。
- 切换后已经打开的直播间、录制任务用的是新账号：录制中途换账号要不要提示，评估里写清。
- uid 为 0（Cookie 里没有 `DedeUserID`）的账号怎么认同一个人：用验证接口返回的 uid。

## 环境和提交

- 出图：`tools/ui/mock/README.md`；`python3 tools/ui/mock/render.py docs/V-需求和反馈/V01-新功能提议/V01.2-哔哩哔哩多账号/src/`。
- 本机工作区或分支 `ai/V01.2`；提交信息以 `[V01.2]` 开头（英文）；不推 master。提交前 `python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：已写的评估和图先提交；README 末尾写“停在哪”；报告写下一步。

## 报告（中文，简洁）

评估结论（借鉴什么、不借鉴什么、规模、涉及的组）；评审页地址；需要用户选的问题；建议的 DECISIONS 条目和目标组任务。
