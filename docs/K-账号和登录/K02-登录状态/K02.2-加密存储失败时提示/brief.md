# K02.2 加密存储失败时提示；扫码登录出错不再卡在“核验中”；退出哔哩哔哩时清网页 Cookie：任务书

## 背景

- 来源：2026-10-07 docs v2 J、K、L、N 组核对（读代码发现，没有用户报告）。维护者登记为本任务。
- 现象：
  1. 设置 → 账号 → 某个平台，粘贴 Cookie 点保存：如果这台手机的 Keystore 出错，什么也不发生（没有提示、编辑框没变化）；联网核验的那一行可能停在“核验中”。用户以为存上了，进直播间才发现没登录。
  2. 哔哩哔哩扫码登录：手机上点了确认，应用显示“核验中”，之后如果保存出错，页面永远停在“核验中”，二维码不再刷新。网页登录（短信、密码）出同样的错时一直转圈。
  3. 账号页退出哔哩哔哩后，应用内网页里的哔哩哔哩登录还在。
- 为什么现在做：第二档；保存失败时静默是数据丢失类的问题。规模小（约 1.5 小时）。
- 已经做过的：加密存储（J02.1）；账号页和三种登录（K01.1、A12）；网页登录页打开时先清哔哩哔哩的 WebView Cookie（`bilibili_web_login.dart:55`）。

## 目标和验收

1. 保存 Cookie 时加密失败（`SecretCipher.seal` 抛错）：提示条“登录信息没能保存：这台设备的加密存储出错，请重试”；编辑框保留输入，“未保存”的状态不变；联网核验的状态回到保存前；存储里原来的值不变。
2. 扫码确认后保存失败：页面显示失败（同一句话），“刷新二维码”能重新开始；不会停在“核验中”。
3. 网页登录保存失败：红条显示同一句话，可以重试，不再一直转圈。
4. 账号页退出哔哩哔哩：存储里的 Cookie 和 uid 清掉（同现在），WebView 里 `www.bilibili.com`、`passport.bilibili.com`、`m.bilibili.com` 的 Cookie 也清掉；清 WebView 失败只记日志，不影响退出。其他平台退出不碰 WebView。
5. 正常保存、正常扫码、正常退出的行为和文字不变（现有 `account_page_test.dart` 照样通过）。
6. 新翻译键只有 `account_save_failed`（中英文）；测试和门禁通过。

## 现状（读代码得出，写文件:行）

- 存储：`packages/live_store/lib/src/secrets.dart:152-196`：`writeAll` → `_writeAll` 先逐个 `_cipher.seal`（`:166-169`），任何一个抛错整批不写；`setCookie`（`:199`）。Android：`apps/pure_live/lib/platform/secret_cipher.dart:28-32`（`AndroidKeystoreCipher.seal`，返回空 → `StateError`；原生失败 → `PlatformException`）。
- 账号动作：`apps/pure_live/lib/features/account/account_services.dart`：`save`（`:101-105`）、`signOut`（`:116-124`，`writeAll` 置空、清 `bilibiliUid`、斗鱼保存时间）、斗鱼 `saveDouyu`（`:136-147`）。
- 编辑框：`features/account/cookie_editor.dart:219-240` `_save`（`:234-239` 只有 `try/finally`）、`_signOut`（`:242` 起）。用它的：`platform_cookie_view.dart:163`（`_save` `:95-125`：联网时先 `setState(() => _check = const AccountChecking())`（`:105`），核验后 `await _actions.save(...)`（`:113`））、`douyu_cookie_view.dart:194`。
- 扫码：`features/account/bilibili_qr_login.dart`：`BilibiliQrPhase`（`:17-40`）、`load`（`:90-110`）、`_poll`（`:118-161`：`confirmed` 分支 `:136-145`，`on Object` `:151-161`）、`_fail`（`:163-169`）；页面的 `_complete`（`:214-238`，`_actions.save` 在 `:225`）。
- 网页登录：`features/account/bilibili_web_login.dart`：`_cleared = _clearCookies()`（`:55`）、`_domains`（`:61-65`）、`_clearCookies`（`:67-77`）、`_page`（`:79-100`）、`_complete`（`:105-127`，`actions.save` `:117`）。
- 文字：`apps/pure_live/assets/translations/zh.json` 的 `account_saved_signed_in`（`:30`）、`account_saved_unverified`（`:31`）、`qr_*`（`:1326-1340`）；没有“保存失败”的键。
- 测试：`apps/pure_live/test/features/account/account_page_test.dart`；假的加密 `FakeCipher`（`apps/pure_live/test/support.dart` 或 `packages/live_store/test/support.dart`）。

## 3.x 基线

- 3.x Cookie 明文存在 Hive，没有加密失败这一说；扫码、网页登录保存不会失败。
- 退出：`git show v3.2.11:lib/common/services/settings/bilibili_account_service.dart`：`logout`（`:152-175`）清账号后 `_browserCookieClearer()`（`:171`），默认 `CookieManager.instance().deleteAllCookies()`（`:200`，所有网站）；失败提示 `bilibili_logout_cleanup_failed`（`:173`）。
- 要保留：核验规则（平台说没登录的不存、核验不了的照存并标“暂时无法核验”）；退出后清 uid（3.x `_clearLocalAccountState`）。只清哔哩哔哩的域名是有意的缩小（不影响别的网站的网页登录）。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节、第 8 节、第 14 节）。
2. `docs/specs/ENGINEERING.md`（不在日志里写 Cookie）；`docs/DECISIONS.md` 的 D-005（文字用中文）、D-018。
3. 本文件夹的 `README.md`；`docs/K-账号和登录/K02-登录状态/README.md`；`docs/K-账号和登录/K02-登录状态/K02.1-Cookie和密码加密存储验证/brief.md`；`docs/J-设置和数据/J02-存储和加密/J02.1-存储和迁移/README.md`。

## 范围

- 可以改：`apps/pure_live/lib/features/account/`（`cookie_editor.dart`、`platform_cookie_view.dart`、`douyu_cookie_view.dart`、`bilibili_qr_login.dart`、`bilibili_web_login.dart`、`account_services.dart`，新文件放共用的清 Cookie 函数）；两个翻译文件（只加 `account_save_failed`）；`apps/pure_live/test/features/account/`；本文件夹。
- 不能改：`SecretStore`、`SecretCipher` 的行为和存储格式（J02.1）；核验规则；账号页的布局和其他文字（A12）；设置键名（D-018）；版本号、`assets/version.json`、`assets/releases.json`；签名配置。日志和测试里不写真实 Cookie。

## 方案和阶段

| 阶段 | 做什么（对应 README 的 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | c1 编辑框和两个平台页的保存失败；c2 扫码和网页登录的保存失败；c3 退出哔哩哔哩时清 WebView（`AccountActions` 加可注入的 `clearWebCookies` 回调，默认调共用的 `clearBilibiliWebCookies()`；只在 Android / 有 WebView 的平台） | 见“可以改” | 验收 1～6 |

只有一个阶段（规模小）。

## 测试

- 改之前会失败（都放 `account_page_test.dart` 或新文件 `account_save_failure_test.dart`）：
  - “a failed save says so and keeps the input (K02.2)”：`LiveStore.memory(cipher: _FailingCipher())`（`seal` 抛 `PlatformException`），离线保存一个合法 Cookie → 出现“登录信息没能保存……”，输入框还是原文，`store.secrets.cookieFor(...)` 仍为 null；联网核验路径：核验通过后保存失败，状态行回到之前（不是“核验中”）。
  - “a QR login whose save fails can start over”：假 `qrPoll` 回答 `confirmed`，保存抛错 → `phase == failed`、`errorKey == 'account_save_failed'`；点“刷新二维码”→ `loading` → `waiting`。
  - “signing out of Bilibili clears its web cookies; other platforms do not”：注入的回调计数 1 / 0。
- 网页登录（WebView）不好在测试里跑：把 `_page` 里“拿到 Cookie 后”的部分抽成可测的函数，测保存失败时返回错误键、`_saving` 复位。
- 测试里的定时器至少 1 秒（D-017）（扫码轮询的 `interval` 用 1 秒以上）；不访问真实平台。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 设置 → 账号 → 哔哩哔哩 → 扫码登录，用另一台手机的哔哩哔哩扫码确认 | 照常登录，提示“已保存，已登录：<名字>”（回归） |
| 2. 账号页退出哔哩哔哩；再打开“网页登录” | 网页是未登录的登录页（不会自动登回去） |
| 3. （能造出来时）用 K02.1 里的方法让 Keystore 出错（例如 `adb shell cmd keystore2` 删掉应用的密钥，或换锁屏方式后再试），粘贴 Cookie 保存 | 提示“登录信息没能保存：这台设备的加密存储出错，请重试”；编辑框保留；造不出来写“跳过：无法模拟” |

## 风险和注意

- 编辑框和平台页别提示两次：约定由编辑框统一提示（`onSave` 抛出），平台页只负责还原核验状态。
- 扫码 `_fail` 的 `notify` 参数：页面本身显示失败画面时不再弹提示条（`notify: false`），和现在拒绝时的做法一样。
- `CookieManager`（flutter_inappwebview）在没有 WebView 的环境（测试、Windows 没装 WebView2）会抛：回调里捕获，只记日志。
- 可能冲突的文件：`features/account/`（A12 系列界面任务、K02.1 修问题时）。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 分支 `ai/K02.2` 或本机工作区；提交信息以 `[K02.2]` 开头（英文）；不推 master。
- 提交前：`apps/pure_live` 跑 `dart format --output=none --set-exit-if-changed .`、`flutter analyze`、全部 `flutter test`（含 `i18n_test.dart`）；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”、更新登记表的 `next`、`branch`。

## 报告（中文，简洁）

每条验收做到没有；新翻译键；测试数量（改之前失败几个）；改了哪些文件；Keystore 出错在真机上能不能造；可能冲突的文件。
