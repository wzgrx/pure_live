# K02.2 加密存储失败时提示；扫码登录出错不再卡在“核验中”；退出哔哩哔哩时清网页 Cookie：记录

- 日期：2026-10-08
- 执行者：Claude（Opus 5.5）
- 分支和提交：本机工作区；代码、测试和本记录一个提交（`[K02.2]`）
- 任务书：[brief.md](brief.md)；设计或说明：[README.md](README.md)

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| c1 编辑框和平台页的保存失败 | 做了 | 编辑框统一提示（`onSave` 抛出 → 记日志、提示条），平台页只把核验状态还原再抛出，不会提示两次；斗鱼用同一个编辑框 |
| c2 扫码和网页登录的保存失败 | 做了 | 两个页面原来各写一遍“核验 → 保存 → 记 uid”，合成 `storeBilibiliLogin`（`account_services.dart`），保存失败时返回错误键；扫码流程 `_poll` 再兜一层（`_complete` 抛什么都进“失败”，不再停在“核验中”）；网页登录 `_page` 同样兜一层 |
| c3 退出哔哩哔哩清 WebView | 做了 | `clearBilibiliWebCookies()`（新文件 `bilibili_web_cookies.dart`，三个域名，从网页登录页挪过来，网页登录页照用）；`AccountActions` 可注入（`bilibiliWebCookieClearerProvider`）；没有 WebView 时（`InAppWeb.available` 假：测试、Linux、没装 WebView2 的 Windows）什么都不做；失败只记日志 |
| 翻译键 | 有偏差 | 任务书要新加 `account_save_failed`，但这个键**已经有了**（“保存失败，请重试”，账号列表退出失败时用，`account_list_view.dart:125`）。不改它的意思、不删（D-024），新加 `account_secret_save_failed`（中文“登录信息没能保存：这台设备的加密存储出错，请重试”，英文 “The sign-in could not be saved: this device's secure storage failed. Try again.”） |

验收：

| 验收 | 结果 |
|---|---|
| 1. 粘贴保存时加密失败：提示、保留输入、仍是“未保存”、核验状态回到保存前、存储不变 | 自动测试过（虎牙离线、哔哩哔哩联网核验、斗鱼） |
| 2. 扫码确认后保存失败：显示失败和这句话，“重试”能重新开始，不停在“核验中” | 自动测试过（页面和流程各一个） |
| 3. 网页登录保存失败：红条显示这句话，可以重试，不再转圈 | 保存部分自动测试过（`storeBilibiliLogin` 返回错误键）；WebView 页面本身测试里跑不了，`_page` 的 `try` 保证 `_saving` 复位 |
| 4. 退出哔哩哔哩清 WebView 三个域名；清失败只记日志；其他平台不碰 | 自动测试过（注入的回调计数 1 / 0；回调抛错时照样退出） |
| 5. 正常保存、扫码、退出的行为和文字不变 | 原有账号页测试全部照旧通过 |
| 6. 新翻译键只有一个 | 是（`account_secret_save_failed`，见上） |

## 根因

- 粘贴保存：`cookie_editor.dart:234-239` 的 `_save` 只有 `try/finally`，`onSave` 抛出的加密错误（`SecretStore._writeAll` 先逐个 `seal`，`secrets.dart:166-169`；Android 上是 `PlatformException` 或 `StateError`，`secret_cipher.dart:28-32`）直接成了未处理的异步错误，界面上什么也没有；`platform_cookie_view.dart:105` 先把状态设成“核验中”，`:113` 的 `_actions.save` 抛错后 `:118` 的还原不执行，卡片停在“核验中”。
- 扫码：`bilibili_qr_login.dart:136-145` 收到“已确认”时先 `_key = null`、`_set(verifying)`，再 `await _complete(...)`；`_complete` 里 `_actions.save`（`:225`）抛错落到 `_poll` 的 `on Object`（`:151-161`），被当成一次“轮询失败”去 `_schedule`，下一次 `_poll` 因为 `_key == null` 直接返回（`:119-120`），页面永远停在“核验中”，也不会到“失败”给出重试。
- 网页登录：`bilibili_web_login.dart:95` `await _complete(...)` 抛错，后面的 `setState(_saving = false)` 不执行，遮罩一直转圈。
- 退出：`account_services.dart:116-124` `signOut` 只删存储里的 Cookie 和 uid；WebView 里的哔哩哔哩 Cookie 只在打开网页登录页时清（`bilibili_web_login.dart:55`）。3.x `bilibili_account_service.dart:152-175` 的 `logout` 退出后调 `_browserCookieClearer()`（`:171`，`CookieManager.instance().deleteAllCookies()` `:200`）。4.x 只清哔哩哔哩的三个域名（不影响别的网站的网页登录），失败只记日志（3.x 提示 `bilibili_logout_cleanup_failed`，4.x 没有这个键，不加新文字）。

## 改了哪些文件

- `apps/pure_live/lib/features/account/account_services.dart`：`bilibiliWebCookieClearerProvider`；`AccountActions(clearBilibiliWeb:)`，`signOut` 对哔哩哔哩清 WebView；`storeBilibiliLogin`（扫码和网页登录共用的“核验 → 保存 → 记 uid”，保存失败返回 `secretSaveFailedKey`）
- `apps/pure_live/lib/features/account/bilibili_web_cookies.dart`（新）：`bilibiliWebDomains`、`clearBilibiliWebCookies`
- `apps/pure_live/lib/features/account/cookie_editor.dart`：`_save` 捕获、记日志（不含 Cookie）、提示
- `apps/pure_live/lib/features/account/platform_cookie_view.dart`：保存失败时还原核验状态再抛出
- `apps/pure_live/lib/features/account/bilibili_qr_login.dart`：`_poll` 兜住 `_complete` 的异常 → `failed`；页面用 `storeBilibiliLogin`
- `apps/pure_live/lib/features/account/bilibili_web_login.dart`：用共用的清 Cookie 函数和 `storeBilibiliLogin`；`_page` 兜底复位 `_saving`
- `apps/pure_live/assets/translations/zh.json`、`en.json`：`account_secret_save_failed`
- `apps/pure_live/test/support.dart`：`FakeCipher.sealFailure`（设上后 `seal` 抛这个错）
- `apps/pure_live/test/features/account/account_page_test.dart`：新组“K02.2 save failures and sign-out”

## 新设置、翻译键、门禁基线

- 新翻译键：`account_secret_save_failed`（中英文）。没有新设置，没有门禁基线变化。

## 测试

- 新增 8 个（`account_page_test.dart`）：粘贴保存失败（虎牙）、联网核验后保存失败（哔哩哔哩，状态还原、只提示一次）、斗鱼保存失败、扫码保存失败后重试成功、扫码流程 `_complete` 抛错进“失败”且能重新开始、`storeBilibiliLogin` 保存失败返回错误键（网页登录用的那段）、退出哔哩哔哩清 WebView 而其他平台不清、清 WebView 抛错不影响退出。
- 改之前失败 7 个（最后一个“清失败不影响退出”改之前也通过，因为那时根本不清）。
- `apps/pure_live` 全部 `flutter test` 946 个通过；`dart analyze --fatal-infos` 无问题。

## 真机上要看的

- 任务书“真机验证”三步：扫码登录照常（回归）；退出哔哩哔哩后打开“网页登录”是未登录的页面；能造出 Keystore 出错时粘贴 Cookie 保存看到提示（造不出来写“跳过：无法模拟”）。
- 注意：从账号列表退出哔哩哔哩和启动时发现登录失效自动退出（`startup.dart:126`）都会清 WebView 的哔哩哔哩 Cookie（同 3.x 的 `logout`）。

## 可能冲突的文件

- `features/account/`（A12 系列界面任务）；`test/support.dart`（只加了一个字段）。
