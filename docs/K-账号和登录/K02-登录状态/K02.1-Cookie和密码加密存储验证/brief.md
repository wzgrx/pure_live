# K02.1 Cookie 和密码加密存储在真机上验证：任务书

## 背景

- 来源：J02.1 把 Cookie、斗鱼续期凭据、WebDAV 密码从 3.x 的明文改成加密存储（`secrets` 表 + 平台的 `SecretCipher`），I01.1 接上 Android Keystore 的实现；之后一直没有在真机上看过。功能清点 F-AND-05“没验证”；CHECKLIST 第 4 节第 6 条“扫码登录；杀掉应用重开……重开后仍是登录状态（Keystore 解密正常）”还空着。
- 现象：没有用户报告。风险是两种：Keystore 在某些系统上出错（加密失败时保存 Cookie 没有任何提示，见 J02 已知问题）；以及“换手机或重装后要重新登录”的提示从没人见过。
- 为什么现在做：第二档；规模小，和 [S02.6](../../../S-质量和验证/S02-真机验证/S02.6-K90补验/README.md) 第 3 阶段（网页登录、登录后画质）同一次上机最省事。
- 已经做过的：J02.1（`d2fbe3072`）、K01.1（`e5ae55fbf`）、A12.1、A12.2（账号页按设计重做）；单元测试覆盖了加密、换设备读不出、账号页提示。

## 目标和验收

1. 库文件里是密文：`secrets` 表每行是二进制（12 字节 IV + 密文），`settings`、`webdav_profiles`、`meta` 表里没有 Cookie 和密码；对 `pure_live.db`（以及存在时的 `-wal`、`-journal`）全文搜 Cookie 的值、WebDAV 密码，**0 处**。
2. 打开“本地日志”并操作一遍后，日志目录里搜同样的值 **0 处**。
3. 杀掉应用（`am force-stop`）再打开：账号页哔哩哔哩是“已登录：名字”，YY、斗鱼仍是保存的状态；进一个哔哩哔哩直播间，聊天里是完整昵称（不是“观***”）。
4. 模拟换安装（卸载重装后把旧库放回去）：账号页顶部出现“{names}的 Cookie 无法在本机读取（换了设备或重装后会这样），请重新填写。”，对应平台的行是“无法在本机读取已保存的 Cookie，请重新填写”；行尾“退出”能清掉这一条；重新扫码登录后恢复正常。WebDAV 页对这个服务器的表现（预期：密码为空，连接时报“账号或密码错误”）记下来。
5. 整个过程 `adb logcat` 里没有 Keystore 相关的异常（`KeyStoreException`、`AEADBadTagException` 只应出现在第 4 步之后、且只在读旧库时）；有的话记下机型和堆栈。
6. 结果写进新建的 `verify.md`，截图在 `verify/`（Cookie、账号名、uid 遮住）；登记表的状态由维护者改。

## 现状（读代码得出，写文件:行）

- 加密：`apps/pure_live/lib/platform/secret_cipher.dart:20`（`AndroidKeystoreCipher`，通道 `pure_live/secret_cipher`）→ 原生 `apps/pure_live/android/app/src/main/kotlin/com/mystyle/purelive/AppChannelsPlugin.kt:147-187`（`SecretCipherChannel`：别名 `pure_live.secrets.v1`，AES/GCM/NoPadding，256 位，IV 12 字节放在前面，密钥名作附加数据）。
- 存储：`packages/live_store/lib/src/secrets.dart`：`load`（`:55`，打开时逐个解密，失败的进 `unreadable` `:133`）、`writeAll`（`:152`，先全部加密再一个事务写）；名字 `cookie/<平台>`、`cookie/douyu.ltp0`、`cookie/douyu.did`、`webdav/<服务器名>`（`:21-35`）。表 `secrets (ref TEXT, sealed BLOB)`（`database.dart:52`）；`webdav_profiles` 没有密码列（`:53`）。
- 库的位置：`getApplicationSupportDirectory()/pure_live.db`，测试包是 `/data/user/0/com.mystyle.purelive.v4dev/files/pure_live.db`（`app/data_root.dart:21-27`）。日志：`files/logs/`（`main.dart:89`），写文件前按名字遮掉 Cookie、`Authorization` 等（`app/app_log.dart:103-120`）。
- 账号页的提示：`features/account/account_state.dart:123`（行状态 `account_status_unreadable`）、列表顶部 `account_unreadable_notice`（`account_list_view.dart`）；`AccountActions.unreadable`（`account_services.dart:84`）；“退出”对解不开的也能用（`account_state.dart:187` 的 `accountStored`）。
- 已知没提示的路径：保存时加密失败（`cookie_editor.dart:234-239` 只有 `finally`；扫码 `bilibili_qr_login.dart:136-159`）。本任务只观察 K90 上会不会出现。

## 3.x 基线

- 3.x 明文存 Cookie（`git show v3.2.11:lib/common/services/settings/cookie_settings_controller.dart:10-35`）和 WebDAV 密码（`web_dav_controller.dart:17-26`、`:62-65`），所以 3.x 没有“解不开”的情况；`allowBackup` 3.x 和 4.x 都是 `false`，系统备份不会带走数据。
- 要保留的：重开仍登录（3.x 的体验）。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 10 节真机验证、第 14 节）、`docs/DECISIONS.md` 的 D-019。
2. 本文件夹的 `README.md`；`docs/K-账号和登录/K02-登录状态/README.md`；`docs/J-设置和数据/J02-存储和加密/README.md`（代码地图、已知问题）。
3. `docs/S-质量和验证/S02-真机验证/CHECKLIST.md` 第 4 节第 6～8 条。

## 范围

- 可以改：本文件夹（`verify.md`、`verify/`、`record.md`）。不改代码；发现问题开任务（报告里写）。
- 不能改：用户手机上的正式包 `com.mystyle.purelive` 和它的数据（D-019：不读、不复制、不卸载）；任何代码、设置键；版本号、`assets/version.json`、`assets/releases.json`；签名配置。**不把任何 Cookie、账号、uid、WebDAV 地址写进仓库**，截图要遮住；读出来的库文件只放本机临时目录，用完删掉。

## 方案和阶段

| 阶段 | 做什么（对应 README 的 c 编号） | 用到什么 | 怎么算做完 |
|---|---|---|---|
| 1 | c1、c2、c3：准备、查密文和日志、杀掉重开 | K90、debug 测试包、维护者的哔哩哔哩测试账号 | 验收 1～3 |
| 2 | c4、c5：模拟换安装，写结论 | 同上 | 验收 4～6 |

## 测试

- 不新增测试（已有：`packages/live_store/test/stores_test.dart` 的 Cookie 加密和换设备读不出；`apps/pure_live/test/features/account/account_page_test.dart:317` 的提示）。
- 发现问题时，开的任务里要求先写失败的测试（例如“`FakeCipher` 加密抛错时保存 Cookie 要提示”，`packages/live_store/test/support.dart` 的 `FakeCipher` 可以改成抛错）。

## 真机验证（维护者在 K90 上做）

准备：`source ~/tools/purelive-env.sh`；`cd apps/pure_live && flutter build apk --debug`（debug 构建才能 `run-as`）；所有命令带 `-s 192.168.1.2:5555`，包名只用 `com.mystyle.purelive.v4dev`；每次点按前确认前台是测试包。下面 `P=com.mystyle.purelive.v4dev`。

| 步骤 | 期望 |
|---|---|
| 1. `adb install -r build/app/outputs/flutter-apk/app-debug.apk`；`adb shell pm clear $P`；打开应用 | 首次启动正常（没有 3.x 数据，什么都不导入） |
| 2. 设置 → 平台显示与授权 → 平台账号 → 哔哩哔哩，扫码登录（维护者的测试账号） | 回到列表显示“已登录：名字” |
| 3. YY 粘贴 `foo=bar; test=1` 保存；斗鱼粘贴 `dy_did=fake-did; LTP0=fake-ltp0; acf_auth=fake` 保存 | YY“已保存”；斗鱼显示会话说明，续期组里 LTP0、dy_did 已填 |
| 4. 备份与恢复 → WebDAV → 添加：名称“验证”、地址 `https://dav.example.com/dav/`、账号 `user`、密码 `k02-check-pass`，保存（连不上没关系） | 列表里有“验证” |
| 5. 设置 → 数据 → 日志管理，打开本地日志；进一个哔哩哔哩直播间待 30 秒；退出 | 日志页有当次的记录 |
| 6. `adb shell am force-stop $P`；`adb exec-out run-as $P cat files/pure_live.db > k02.db`（有 `files/pure_live.db-wal`、`-journal` 也一起取）；`python3 -c "import sqlite3;db=sqlite3.connect('k02.db');print(db.execute('select ref, length(sealed), typeof(sealed) from secrets').fetchall())"` | `cookie/bilibili`、`cookie/yy`、`cookie/douyu`、`cookie/douyu.ltp0`、`cookie/douyu.did`、`webdav/验证` 都在，类型 `blob`，长度大于明文 + 28 |
| 7. `grep -c 'k02-check-pass\|fake-ltp0\|SESSDATA' k02.db k02.db-wal 2>/dev/null`；再取日志：`adb exec-out run-as $P sh -c 'cat files/logs/*' | grep -c 'SESSDATA=[^*]\|k02-check-pass\|fake-ltp0'` | 都是 0（`SESSDATA` 的名字可以出现在日志里，后面的值必须被遮掉） |
| 8. `sqlite3 k02.db ".schema webdav_profiles"`；`select key from settings where key like '%ookie%'` | 没有密码列；`settings` 里没有 Cookie |
| 9. 打开应用 → 平台账号 | 哔哩哔哩仍“已登录：名字”，YY、斗鱼状态同第 3 步 |
| 10. 进一个弹幕多的哔哩哔哩直播间 | 聊天里是完整昵称，没有“登录后可看到完整昵称”的提示 |
| 11. 模拟换安装：`adb shell am force-stop $P`；保存 `k02.db`（第 6 步已取）；`adb uninstall $P`；`adb install build/app/outputs/flutter-apk/app-debug.apk`；`adb shell run-as $P mkdir -p files`；`adb push k02.db /data/local/tmp/k02.db && adb shell chmod 644 /data/local/tmp/k02.db && adb shell run-as $P cp /data/local/tmp/k02.db files/pure_live.db && adb shell rm /data/local/tmp/k02.db`；打开应用 | 启动正常；关注等非密钥数据都在（如果第 1～5 步加过） |
| 12. 平台账号 | 顶部“哔哩哔哩、YY、斗鱼的 Cookie 无法在本机读取（换了设备或重装后会这样），请重新填写。”（名字按实际）；三行都是“无法在本机读取已保存的 Cookie，请重新填写”；1 秒后没有“登录已失效”的误报 |
| 13. 点 YY 行尾“退出”并确认 | YY 变成“未设置”，顶部提示里不再有 YY |
| 14. WebDAV 页选“验证”（或编辑它） | 记下实际表现（预期密码为空、连接报“账号或密码错误”） |
| 15. 重新扫码登录哔哩哔哩 | “已登录：名字”；顶部提示里不再有哔哩哔哩 |
| 16. 全程开着 `adb logcat -v time | grep -i -E 'keystore|AEADBadTag|secret_cipher'` | 第 11 步以前没有异常；第 11 步以后只有读旧库时的解密失败 |
| 17. 收尾：退出所有账号、删掉“验证”服务器，删除本机的 `k02.db*` | 测试包里不留维护者的登录 |

## 风险和注意

- **认错包**：K90 上同时装着用户的 3.x（正式包）。所有命令只用 `$P`；第 11 步的 `adb uninstall` 一定带 `.v4dev`，写错一个字就会卸掉用户的 3.x 并丢掉它的数据。执行前把命令读两遍。
- 第 11 步卸载会删掉测试包的全部数据和它在 Keystore 里的密钥，这是预期的。
- 扫码登录会让哔哩哔哩记一次新的登录设备；用测试账号，做完退出。
- profile 构建不能 `run-as`，一定用 debug 构建。

## 环境和提交

- `source ~/tools/purelive-env.sh`；根目录先 `bash tools/ffmpeg_kit/fetch.sh`、`flutter pub get`。
- 分支 `ai/K02.1` 或本机工作区；提交信息以 `[K02.1]` 开头（英文）；只提交本文件夹的 `verify.md`、`verify/`、`record.md`；不推 master。
- 提交前：`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”（做到第几步；测试包里还登录着什么账号，要记得收尾）、更新登记表的 `next`、`branch`。

## 报告（中文，简洁）

17 步各自通过与否（不通过的写现象）；库和日志里明文的搜索结果；Keystore 有没有出过错；“换安装”后的提示截图（遮住账号）；发现的问题和建议开的任务（例如保存失败的提示、退出时清 WebView 的 Cookie）。
