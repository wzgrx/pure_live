# K02.2 加密存储失败时提示；扫码登录出错不再卡在“核验中”；退出哔哩哔哩时清网页 Cookie

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能
- 来源：2026-10-07 docs v2 J、K、L、N 组核对：Keystore 加密失败时保存 Cookie 没有任何提示（`cookie_editor.dart:234-239` 只有 `finally`）；扫码登录出错时页面停在“核验中”（`bilibili_qr_login.dart:136-159`）；退出哔哩哔哩时不清 WebView 的 Cookie（3.x 清，`bilibili_account_service.dart:200`）
- 相关：加密存储本身 [J02.1](../../../J-设置和数据/J02-存储和加密/J02.1-存储和迁移/README.md)（`SecretStore`、`AndroidKeystoreCipher`）；真机上的加密存储验证 [K02.1](../K02.1-Cookie和密码加密存储验证/README.md)；账号页和登录方式 [K01.1](../../K01-账号和登录方式/K01.1-账号与登录/README.md)；界面 A12（账号、登录）；决定 D-013（哔哩哔哩打码昵称做登录引导）、D-018
- 任务书：[brief.md](brief.md)

## 目标

1. **保存失败要说**：手机的加密存储（Android Keystore）偶尔会出错（厂商系统、刚刷机、锁屏方式变了）。现在在账号页粘贴 Cookie 点保存、或者扫码 / 网页登录成功后保存时如果加密失败，什么提示都没有：编辑框看起来像没反应，联网核验那一行可能一直转圈，用户以为保存了。做完以后：提示“登录信息没能保存：这台设备的加密存储出错，请重试”，编辑框保留输入，状态回到保存前。
2. **扫码登录不卡住**：手机上确认登录后，应用在“核验中”这一步如果出错（核验以外的异常，例如上面的加密失败），页面一直停在“核验中”，二维码也不会再刷新，只能退出重来。做完以后：显示失败和原因，可以点“刷新二维码”重来。网页登录（短信、密码）同样不再卡在转圈。
3. **退出哔哩哔哩时清网页登录**：在账号页退出哔哩哔哩后，应用内网页（网页登录页、以后的网页内容）里还留着哔哩哔哩的登录，下次打开网页登录会被自动登回去（4.x 只在打开网页登录页时先清一次）。做完以后：退出时同时清掉 WebView 里哔哩哔哩域名的 Cookie。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11`） | 现在（文件:行） | 要做到 |
|---|---|---|---|
| Cookie 存哪 | Hive 明文（没有加密，不会因为加密失败） | `packages/live_store/lib/src/secrets.dart:152-196` `SecretStore.writeAll`：先 `_cipher.seal`（`:166-169`），失败就抛，数据库不写；Android 是 `AndroidKeystoreCipher.seal`（`apps/pure_live/lib/platform/secret_cipher.dart:28-32`，通道返回空时 `StateError`，原生异常是 `PlatformException`） | 失败时界面提示，数据不变 |
| 粘贴 Cookie 保存 | — | `apps/pure_live/lib/features/account/cookie_editor.dart:219-240` `_save`：`try { if (await widget.onSave()) _markSaved(); } finally { … _busy = false }`（`:234-239`），异常抛到区域外，没有提示；`platform_cookie_view.dart:95-125` 的 `_save` 联网核验时先把状态设成“核验中”（`:105`），`_actions.save` 抛错后状态不回去；斗鱼 `douyu_cookie_view.dart:194` 同一个编辑框 | 编辑框捕获保存失败：提示、保留输入、核验状态还原 |
| 扫码登录 | 3.x 的扫码页 `lib/modules/auth/…`（Cookie 明文保存，不会在保存时失败） | `apps/pure_live/lib/features/account/bilibili_qr_login.dart`：`_poll` 收到“已确认”→ `_key = null`、`_set(verifying)`、`await _complete(...)`（`:136-145`）；`_complete`（`:214-238`）里 `_actions.save` 抛错 → 落到 `_poll` 的 `on Object`（`:151-161`）：`_failures++`、`_schedule`，下一次 `_poll` 因为 `_key == null` 直接返回（`:119-120`），**页面停在“核验中”** | `_complete` 抛错时 `_fail(...)`（显示失败、可以刷新二维码） |
| 网页登录 | — | `bilibili_web_login.dart:79-99` `_page`：`_saving = true` 后 `await _complete(...)`（`:95`），`_complete`（`:105-127`）里保存抛错 → `setState(_saving = false)` 不执行，页面一直转圈 | 捕获、显示红条原因、`_saving` 复位 |
| 退出时清网页 Cookie | `lib/common/services/settings/bilibili_account_service.dart:152-175` `logout`：清掉账号后 `_browserCookieClearer()`（`:171`，`CookieManager.instance().deleteAllCookies()` `:200`，清全部网站），失败提示 `bilibili_logout_cleanup_failed`（`:173`） | `apps/pure_live/lib/features/account/account_services.dart:116-124` `signOut` 只删存储里的 Cookie 和 uid；WebView 里的只在打开网页登录页时清（`bilibili_web_login.dart:55`、`:67-77` `_clearCookies`，三个哔哩哔哩域名） | 退出哔哩哔哩时清这三个域名的 WebView Cookie（不像 3.x 清全部网站）；清失败只记日志 |

## 方案

- c1 编辑框：`cookie_editor.dart` `_save` 加 `on Object catch (error)`：记日志（不含 Cookie），`AppNavigator.toast(i18n('account_save_failed'))`，不调 `_markSaved`；新键 `account_save_failed`（中文“登录信息没能保存：这台设备的加密存储出错，请重试”，英文 “The sign-in could not be saved: this device's secure storage failed. Try again.”）。`platform_cookie_view.dart` 的 `_save`：`_actions.save` 抛错时把 `_check` 还原成 `previous` 再抛给编辑框（或者在这里提示，二选一，别提示两次）。斗鱼同样。
- c2 扫码：`bilibili_qr_login.dart` `_poll` 的 `confirmed` 分支把 `await _complete(...)` 包一层 `try`，异常 → `_fail('account_save_failed', notify: false)`（页面的失败画面显示这句话，“刷新二维码”照旧能用）；网页登录 `_page` 同样包一层，异常 → `_error = 'account_save_failed'`、`_saving = false`。
- c3 退出清网页 Cookie：把 `bilibili_web_login.dart:67-77` 的 `_clearCookies` 挪成共用函数（例如 `features/account/bilibili_web_cookies.dart` 的 `clearBilibiliWebCookies()`，网页登录页照用）；`AccountActions.signOut` 对哔哩哔哩调它（通过可注入的回调，测试里换掉；没有 WebView 的平台、桌面上什么都不做），失败只记日志。
- 不改：加密方式和存储格式；核验规则（拒绝的不存、核验不了的照存）；其他平台的退出；3.x 的设置键（D-018）。

## 验证

- 自动测试：`apps/pure_live/test/features/account/` 里加：假的 `SecretCipher` 在 `seal` 时抛错 → 粘贴保存有提示、编辑框保留、状态还原；扫码确认后保存抛错 → 阶段是 `failed`、错误键是 `account_save_failed`；网页登录同样；退出哔哩哔哩时清 WebView 的回调被调一次（其他平台不调）。
- 真机：加密失败在 K90 上不好造（K02.1 的步骤里看能不能用 `adb shell` 删掉 Keystore 里应用的密钥模拟）；扫码失败、退出清 Cookie 能直接看（任务书“真机验证”）。

## 留下的问题

- 加密存储“读”失败（`unreadable`，启动时打不开的登录）已有处理（J02.1、`LegacyReloginNotice`），不在本任务。
- 其他平台的网页登录（以后加的）退出时也要清自己的域名，写进 K01 的说明。
