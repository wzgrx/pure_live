# J06.1 3.x 数据迁移的真机验证：任务书

## 背景

- 来源：J02.1、L01.2 的记录都写着“没用真实的 3.x 数据检查迁移”；功能清点 F-APP-01（首次启动导入 3.x 数据）、F-APP-02（导入 3.x 网络电视库）是“没验证”；PLAN 的风险表第一条“3.x 数据迁移出错，用户丢关注和设置”。
- 现象：没有用户报告。4.0.0（构建号 5001）已经发给用户覆盖安装 3.x；迁移代码只用 hive_ce 造出来的文件测过（`packages/live_store/test/migration_test.dart`），从没读过 3.2.11 真正写出来的 Hive 文件和网络电视库，也没在真机的 Keystore 上加密过迁移来的 Cookie。
- 为什么现在做：第一档。出错的后果是用户丢关注和设置，而且迁移按指纹只跑一次，事后修复只对还没升级的用户有效。和 [S04.1](../../../S-质量和验证/S04-覆盖安装验证/README.md)（覆盖安装本身）同一次做。
- 已经做过的：J02.1（`d2fbe3072`，迁移代码）、L01.2（`27385a999`，网络电视库迁移）、I01.1（启动时调用）、I01.3（字体）、H01.1（录制任务）、A11.2（主题色迁移）。
- **硬规则（D-019）**：不读、不复制、不导出、不覆盖用户手机（K90）上正式包 `com.mystyle.purelive` 的任何数据，手机有 root 也不行；不在 K90 上安装或卸载正式包。所有 3.x 数据都在模拟器上自己造。

## 目标和验收

1. 模拟器上：装 3.2.11、造齐“要造的数据”一节的全部数据，记下基准（截图、数量、3.x 文件的 SHA-256 清单）。
2. 路 A（模拟器覆盖安装）：用 master 构建的 x86_64 release 包 `adb install -r` 覆盖 3.2.11 成功；第一次启动不崩、不卡在启动页；“核对表”每一项结果写进 `record.md`。
3. 路 B（K90 测试包读入）：把模拟器上 3.x 的 `app_flutter/PURE_LIVE/` 放进 K90 上 debug 测试包 `com.mystyle.purelive.v4dev` 的同一位置，冷启动后核对表的“路 B 也看”一列全部通过；Cookie 在真机 Keystore 加密后，杀掉重开仍在。
4. 两条路都确认：3.x 的文件前后 SHA-256 完全一样、没有多出文件（`.lock`、`-journal` 等）；第二次启动不重复导入（数量不变、`meta` 的账本有指纹）。
5. 路 C：模拟器上 3.x 导出的完整备份，在 K90 测试包“从文件恢复”，预览数字和恢复结果正确。
6. 每个不通过项：现象、根因线索（文件:行）、一个改之前会失败的单元测试（放进 `migration_test.dart` 或 `iptv_store_test.dart`，可以把模拟器上拿到的真实文件**脱敏后**做成样本）；修复开新任务（报告里写组和标题），明显的小 bug 可以在本任务分支单独提交。
7. 登记表的阶段 `done` 按做完的阶段更新；全部通过时 F-APP-01、F-APP-02 改“完成”的依据写进报告（清点由维护者改）。

## 现状（读代码得出，写文件:行）

- 找文件：`apps/pure_live/lib/app/data_root.dart:51` 的 `legacyHiveFiles`：Android 是 `getApplicationDocumentsDirectory()/PURE_LIVE/HIVE_DB/app_settings.hive`，即 `/data/user/0/<包名>/app_flutter/PURE_LIVE/HIVE_DB/app_settings.hive`（`packages/live_store/lib/src/legacy/legacy_import.dart:29-31`）。所以测试包读的是**它自己的** `app_flutter/PURE_LIVE/`——路 B 就是利用这一点。网络电视库在同一个根下 `IPTV_CACHE/pure_live_tv/pure_live_tv.db`（`app/iptv_legacy.dart:16-25`），3.x 下载的字体在 `DOWNLOADS/fonts`（`app/fonts.dart:411`）。
- 4.x 自己的库在 `getApplicationSupportDirectory()` 即 `/data/user/0/<包名>/files/pure_live.db`（`data_root.dart:21-27`），和 3.x 的文件不在一个目录。
- 启动顺序（`app/bootstrap.dart:98-137`，只在主窗口）：打开库 → `LegacyMigration.importHiveFiles`（`:117-120`）→ `LegacyReloginNotice.record` → `LegacyIptvMigration.importDatabases`（`:125-130`）→ `wire` → 后台 `IdentityMigration.run`（`:242`）。每一步失败只记日志（`dart:developer` 的 `log`，release 里看不到），不影响启动——**所以核对只能看界面和查库**。
- 账本：`meta` 表的 `legacy.importedSources`（`legacy_import.dart:131`）、`legacy.iptvImportedSources`（`iptv_legacy.dart:106`），值是 JSON 数组，每项 `绝对路径|大小|修改时间毫秒`。
- 转换规则（`legacy/legacy_snapshot.dart`）：设置 `:181-204`；关注、历史、分区、分组、屏蔽、WebDAV `:206-264`；Cookie `:355-372`（`<平台>Cookie`，淘宝丢掉；`douyuLtp0`、`douyuDid`）；计数修复 `:383-412`；被消化的 3.x 键 `:414-420`；其他原值 `:422-446`（`recorder_tasks` 换算画质 id）。合并 `legacy_import.dart:218-280`：库里已有的优先、集合按身份合并、Cookie 最后一次写入，Keystore 失败只跳过这一次写并返回名字（启动 1 秒后提示一次 `legacy_import_relogin`，`app/startup.dart:30-46`、`:86`）。
- 已知不会清的：京东、酷狗、百度的占位值（`JD Live`、`Kugou Live`、`Baidu Live`）——`legacy_rules.dart` 只有陈旧公告一条清理（`:11-14`、`:28`）。
- 启动 1 秒后会用存下的哔哩哔哩 Cookie 核验登录（`app/startup.dart:85-90`、`:116-131`）：**平台回 -101 时会把 Cookie 删掉**。造数据时如果放的是假的哔哩哔哩 Cookie，第一次启动要断网（否则核对时它已经被删了）。

## 3.x 基线

- 3.x 的迁移：`git show v3.2.11:lib/common/global/initialized.dart:55-90`（`AppPathManager().initialize` → `Hive.initFlutter(HIVE_DB)` → `SettingsUpgradeMigration.migrate`）；`lib/common/services/utils/settings_upgrade_migration.dart:25-99`（来源指纹账本 `settingsUpgradeImportedSources`，4.x 也认）。
- 3.x 的数据根：`lib/common/global/app_path_manager.dart:20-25`（`PURE_LIVE`、`HIVE_DB`、`IPTV_CACHE`），Android 用应用文档目录（`:54`、`:62-64`）。
- 3.x 的 box 名 `app_settings`（`lib/common/utils/hive_pref_util.dart:41-44`）；关注 2.1 以后存成 JSON 字符串 `{"list": [...]}`，更早是字符串列表（`settings_upgrade_migration.dart` 的说明）。
- 必须保留：3.x 的文件只读（用户可能回退）；键名和含义（D-018）。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节、第 10 节真机验证、第 14 节）、`docs/DECISIONS.md` 的 D-006、D-018、D-019。
2. 本文件夹的 `README.md`；`docs/J-设置和数据/J06-3.x数据迁移/README.md`（现状里的流程图）；`docs/J-设置和数据/J02-存储和加密/J02.1-存储和迁移/record.md`（“3.x 数据迁移”“保留的 v3 行为”）；`docs/L-网络电视和点播/L01-网络电视/L01.2-网络电视列表持久化/record.md`（“3.x 迁移”）。
3. 代码：`packages/live_store/lib/src/legacy/` 四个文件；`apps/pure_live/lib/app/bootstrap.dart`、`data_root.dart`、`iptv_legacy.dart`、`startup.dart`。
4. `docs/S-质量和验证/S02-真机验证/CHECKLIST.md` 第 5 节第 9 条；S04.1 的 README（同一次做）。

## 范围

- 可以改：本文件夹（`record.md`、`verify/` 截图，图宽不超过 1080、每张不超过 300 KB）；发现问题时：`packages/live_store/test/`、`apps/pure_live/test/iptv_store_test.dart`（加失败的测试和脱敏样本）；明显的小 bug 修在 `packages/live_store/lib/src/legacy/`、`apps/pure_live/lib/app/iptv_legacy.dart`（单独提交，写清根因）。
- 不能改：用户手机上的正式包和它的数据（D-019）；用户 Windows 上的 `D:\Soft\PureLive`、`D:\Soft\pure_live`；迁移以外的功能代码；设置键名和含义；版本号、`assets/version.json`、`assets/releases.json`；签名配置。**不把模拟器上造的 Cookie、WebDAV 密码、任何真实账号写进仓库**（截图里也要遮住 Cookie 输入框）。

## 要造的数据（模拟器上的 3.2.11 里）

全部用 3.x 的界面造（这样 Hive 文件是 3.x 真正写的）；需要的文件先 `adb -s emulator-5554 push` 到模拟器的 `/sdcard/Download/`。

| 编号 | 数据 | 在 3.x 里怎么造 | 记下的基准 |
|---|---|---|---|
| D1 | 关注 15 个以上 | 搜索后关注：哔哩哔哩、斗鱼、虎牙、抖音（至少一个，3.x 可能按 room_id 存）、快手、YY、网易 CC 各 1～3 个；能找到的话京东、酷狗、百度各一个（看占位值）；拖动调整一次顺序 | 关注页截图（顺序）、总数 |
| D2 | 观看历史 10 个以上 | 依次进 10 个直播间（每个停几秒）；最后再进一次第一个（看“重看移到最前”） | 观看记录页截图、总数 |
| D3 | 分组 3 个 | 标签管理：建“常看”“游戏”“音乐”，把关注分进去（一个房间进两组），置顶一个 | 每组的成员 |
| D4 | 关注分区 2 个 | 分区页关注两个分区 | 名字 |
| D5 | 屏蔽 | 屏蔽词：`Test`、`test`（大小写重复，4.x 应合并成一个）、`广告`；屏蔽用户 2 个 | 列表截图 |
| D6 | 设置（至少 15 项，都改离默认值） | 主题模式深色；主题色选一个非默认色；文字缩放 1.2；首选清晰度（WLAN）改一档；静音开；屏幕常亮关；直播间弹幕设置：速度、字号、透明度、上边距 40 像素、帧率固定 30；平台显示：隐藏一个平台、调整顺序，首选平台改斗鱼；刷新间隔 15 分钟；观看记录保留 50；界面刷新率“性能”；首页菜单隐藏“录制”；应用代理开、地址 `192.168.1.10` 端口 `7897`；网络电视自定义 UA `TestUA/1.0`；本地互动的用户名改成 `tester` | 每页截图；改了哪些写成清单 |
| D7 | 账号（假的，不用真实账号） | 虎牙 Cookie `yyuid=1234567890; foo=bar`；YY `foo=bar`；快手 `foo=bar`；SOOP `foo=bar`；Twitch `auth-token=fake; login=tester`；斗鱼粘贴 `dy_did=fake-did; acf_ltkid=1; LTP0=fake-ltp0`（看 3.x 把 LTP0、DID 存下）；哔哩哔哩 `SESSDATA=fake; bili_jct=fake; DedeUserID=1` | 账号页截图（Cookie 输入框遮住） |
| D8 | WebDAV 2 个 | 添加 `测试一`（`https://dav.example.com/dav/`、`user1`、`pass1`）、`测试二`（`https://dav.example.org/`、`user2`、`pass2`），选中“测试二”（连不上没关系，只要配置存下） | 列表截图 |
| D9 | 网络电视 | 把一个 3 个频道的小 m3u（其中一个带 `catchup="append" catchup-source="?playseek=${(b)yyyyMMddHHmmss}-${(e)yyyyMMddHHmmss}"`）推到 `/sdcard/Download/` 后“本地导入”；再网络导入一个公开的小列表；导入默认节目单并选中；关注其中一个频道 | 订阅源管理截图、频道数 |
| D10 | 录制 | 录制设置：分段时长改 30 分钟；录制中心添加 1～2 个录制任务（不开始录） | 录制中心截图 |
| D11 | 字体（可选，要能连字体服务器） | 字体管理下载一个字体并设为应用字体 | 截图 |

造完后：3.x 里“导出完整备份”到 `/sdcard/Download/`（路 C 用）；**强制停止 3.x**（`adb -s emulator-5554 shell am force-stop com.mystyle.purelive`），然后记基准：

```bash
adb -s emulator-5554 root
adb -s emulator-5554 shell 'cd /data/data/com.mystyle.purelive/app_flutter/PURE_LIVE && find . -type f -exec sha256sum {} + | sort -k2' > v3-before.sha256
adb -s emulator-5554 pull /data/data/com.mystyle.purelive/app_flutter/PURE_LIVE ./v3data      # 路 B 用的原样副本
adb -s emulator-5554 pull /sdcard/Download/<导出的备份>.txt ./                                 # 路 C 用
```

`v3data/` 和备份文件里有造的假 Cookie 和 WebDAV 密码，只放在本机临时目录（scratchpad），**不进仓库**。

## 方案和阶段

| 阶段 | 做什么 | 用到什么 | 怎么算做完 |
|---|---|---|---|
| 1 准备装着 3.x 和真实数据的设备（模拟器） | 装模拟器、装 3.2.11、造 D1～D11、导出备份、记基准 | 见下面“环境” | `record.md` 里有基准清单和截图；`v3-before.sha256`、`v3data/` 在本机 |
| 2 覆盖安装 4.x | 路 A：模拟器上 `adb install -r` master 的 x86_64 release 包，第一次启动（先断网，见风险），核对表 A 列；再联网看身份迁移。路 B：K90 测试包读入 `v3data/`，核对表 B 列 | 两台设备 | 两条路都装上、启动、导入完成 |
| 3 逐项核对关注、历史、设置、账号 | 核对表逐行；查库；文件完整性；第二次启动；路 C 恢复备份 | 下面的查库脚本 | 验收 1～7 |

### 环境（阶段 1）

```bash
source ~/tools/purelive-env.sh
# 模拟器（WSL 有 /dev/kvm；用 google_apis 镜像，才能 adb root）
sdkmanager "emulator" "system-images;android-35;google_apis;x86_64"
avdmanager create avd -n pl3x -k "system-images;android-35;google_apis;x86_64" -d pixel_7
emulator -avd pl3x -no-audio -no-snapshot -gpu swiftshader_indirect &      # 有 WSLg 可以看窗口；没有就加 -no-window，用截图看
adb -s emulator-5554 wait-for-device
# 3.2.11（GitHub 发布页，和 4.x 同一个调试密钥签名）
gh release download v3.2.11 --repo wzgrx/pure_live -p 'PureLive-3.2.11-4134-debug-signed-android-x86_64-release.apk' -D <scratchpad>
adb -s emulator-5554 install <scratchpad>/PureLive-3.2.11-4134-debug-signed-android-x86_64-release.apk
```

如果 3.2.11 在 API 35 上起不来，换 `system-images;android-34;google_apis;x86_64`。3.x 弹出“有新版本”时点取消，不要让它自己升级。

### 阶段 2 的命令

```bash
# 路 A：master 的 release 包（本机没有 key.properties 时用调试密钥签名，和 3.2.11 同一个证书，D-006）
cd apps/pure_live && flutter build apk --release --split-per-abi --target-platform android-x64     # 门禁在跑时不要构建
aapt2 dump badging build/app/outputs/flutter-apk/app-x86_64-release.apk | head -1                # 包名 com.mystyle.purelive，versionCode 大于 3.2.11 的
apksigner verify --print-certs build/app/outputs/flutter-apk/app-x86_64-release.apk               # SHA-256 1e832295…（和 3.2.11 相同）
adb -s emulator-5554 shell svc wifi disable; adb -s emulator-5554 shell svc data disable          # 第一次启动断网（保住假的哔哩哔哩 Cookie）
adb -s emulator-5554 install -r build/app/outputs/flutter-apk/app-x86_64-release.apk
adb -s emulator-5554 shell am start -n com.mystyle.purelive/.MainActivity

# 路 B：K90 上的 debug 测试包（debug 构建才能 run-as）
flutter build apk --debug
adb -s 192.168.1.2:5555 install -r build/app/outputs/flutter-apk/app-debug.apk                    # 包名 com.mystyle.purelive.v4dev
adb -s 192.168.1.2:5555 shell am force-stop com.mystyle.purelive.v4dev
adb -s 192.168.1.2:5555 shell pm clear com.mystyle.purelive.v4dev                                 # 只清测试包
adb -s 192.168.1.2:5555 push ./v3data /data/local/tmp/pl3x
adb -s 192.168.1.2:5555 shell chmod -R a+rX /data/local/tmp/pl3x
adb -s 192.168.1.2:5555 shell "run-as com.mystyle.purelive.v4dev sh -c 'mkdir -p app_flutter && cp -r /data/local/tmp/pl3x app_flutter/PURE_LIVE'"
adb -s 192.168.1.2:5555 shell "run-as com.mystyle.purelive.v4dev sh -c 'cd app_flutter/PURE_LIVE && find . -type f -exec sha256sum {} + | sort -k2'" > v4dev-before.sha256
# 第一次启动前打开 K90 的飞行模式（同样为了假的哔哩哔哩 Cookie），然后：
adb -s 192.168.1.2:5555 shell am start -n com.mystyle.purelive.v4dev/com.mystyle.purelive.MainActivity
adb -s 192.168.1.2:5555 shell rm -r /data/local/tmp/pl3x                                         # 用完删掉手机上的临时副本
```

K90 上每一条命令都带 `-s 192.168.1.2:5555`，包名一律 `com.mystyle.purelive.v4dev`；点按之前确认前台是测试包（PROCESS 第 10 节）。

### 查库（阶段 3）

```bash
# 路 A（模拟器，adb root）；路 B 换成 run-as：adb -s 192.168.1.2:5555 exec-out run-as com.mystyle.purelive.v4dev cat files/pure_live.db > v4.db
adb -s emulator-5554 shell am force-stop com.mystyle.purelive
adb -s emulator-5554 pull /data/data/com.mystyle.purelive/files/pure_live.db v4.db
python3 - <<'EOF'
import sqlite3, json
db = sqlite3.connect('v4.db')
q = lambda sql: db.execute(sql).fetchall()
for t in ['follows', 'history', 'follow_areas', 'tags', 'room_tags', 'block_rules', 'settings', 'secrets',
          'webdav_profiles', 'legacy_values', 'iptv_playlists', 'iptv_channels', 'iptv_epg_sources', 'iptv_epg_mappings']:
    try: print(t, q(f'SELECT COUNT(*) FROM {t}')[0][0])
    except sqlite3.Error as e: print(t, e)
print('secrets', [r[0] for r in q('SELECT ref FROM secrets')])           # 只看名字，不打印密文
print('meta', [r[0] for r in q('SELECT key FROM meta')])
for key in ['legacy.importedSources', 'legacy.iptvImportedSources', 'webdav.current']:
    print(key, q(f"SELECT value FROM meta WHERE key = '{key}'"))
print('legacy_values', [r[0] for r in q('SELECT key FROM legacy_values')])
for r in q('SELECT position, room FROM follows ORDER BY position'):
    room = json.loads(r[1]); print(r[0], room.get('platform'), room.get('roomId'), room.get('nick'))
EOF
```

## 核对表（阶段 3；结果、截图写进 `record.md`）

| 编号 | 核对项 | 在 4.x 里怎么看 | 期望 | 路 B 也看 |
|---|---|---|---|---|
| V1 | 启动 | 覆盖安装后第一次打开 | 不崩、启动页之后进首页；没有“请重新登录”提示（Keystore 正常时） | 是 |
| V2 | 关注 | 关注页（全部）；查库 `follows` | 数量 = D1（去掉 3.x 里本来就无效的）；顺序和 D1 截图一致；名字、头像、平台都对 | 是 |
| V3 | 历史 | 观看记录页；查库 `history` | 数量 = D2（不超过保留数）；最新的在前，重看的那个在最前 | 是 |
| V4 | 分组 | 标签管理、关注页按分组 | 三个分组、顺序（置顶的在前）、成员和 D3 一样，一个房间在两组 | 是 |
| V5 | 关注分区 | 分区页的关注分区 | 两个都在 | 是 |
| V6 | 屏蔽 | 设置 → 弹幕屏蔽 | 屏蔽词是 `Test`、`广告`（`test` 合并掉，保留第一次的写法）；屏蔽用户 2 个 | 是 |
| V7 | 设置 | 逐页对照 D6 的清单；查库 `settings` 有这些键 | 每一项都是 3.x 改过的值；主题色是 3.x 选的颜色（不是品牌蓝）；上边距是 40 像素；隐藏的平台和顺序、首选平台、首页菜单照旧 | 是 |
| V8 | 账号 | 设置 → 平台账号（断网状态下先看一次） | 虎牙显示账号 ID `1234567890`；Twitch 显示聊天身份 `tester`；YY、快手、SOOP 显示已保存；斗鱼显示会话说明且 LTP0、DID 在；哔哩哔哩已保存（联网后会因 -101 被退出并提示“登录已失效”——这是正常的 3.x 行为）；查库 `secrets` 有对应的 `cookie/<平台>`、`cookie/douyu.ltp0`、`cookie/douyu.did` | 是；另外杀掉重开（`am force-stop` 后再打开）账号还在 = 真机 Keystore 解密正常 |
| V9 | WebDAV | 备份与恢复 → WebDAV | 两个服务器都在、当前是“测试二”；编辑对话框里密码有值（点眼睛能看到 `pass2`）；查库 `secrets` 有 `webdav/测试一`、`webdav/测试二`，`webdav_profiles` 没有密码列 | 是 |
| V10 | 网络电视 | 设置 → 网络电视 | 两个列表、频道数和 D9 一样；选中的节目单是默认节目单；关注的那个频道从关注页点进去能播；带回看属性的频道节目单里能点回看（有节目时） | 是 |
| V11 | 录制 | 录制设置、录制中心 | 分段时长 30；录制任务都在（画质显示正常，没有“未知画质”） | 是 |
| V12 | 本地互动 | 设置 → 本地互动体验 | 用户名 `tester` | 是 |
| V13 | 字体（做了 D11 时） | 设置 → 外观 → 字体 | 3.x 下载的字体显示已安装并在用 | 否（路 B 也可以看：字体目录随 `PURE_LIVE` 一起复制了） |
| V14 | 身份迁移 | 联网后等一会儿，查库 `follows` 里抖音那条的 `roomId` | 3.x 按场次存的抖音房间号换成主播的（web_rid），分组跟着走（`room_tags` 的键也换了） | 是 |
| V15 | 陈旧公告、占位值 | 关注卡片、直播间信息 | 没有“远端聊天尚待接入”；京东、酷狗、百度的占位名记下实际效果（预期还在，刷新后是否变成真名） | 否 |
| V16 | 3.x 文件没变 | 再跑一次 `sha256sum` 清单，和 `v3-before.sha256`（路 B 是 `v4dev-before.sha256`）`diff` | 完全一样，没有多出文件 | 是 |
| V17 | 账本、第二次启动 | 查库 `meta` 的 `legacy.importedSources`、`legacy.iptvImportedSources`；强制停止后再启动，再查一次数量 | 账本各有一条指纹；数量不变、没有重复 | 是 |
| V18 | 3.x 备份（路 C） | K90 测试包（先 `pm clear`）：备份与恢复 → 从文件恢复 → 选 3.x 导出的文件 | 预览写“3.x 版本 3”、各部分的增加数和 D1～D8 一致、账号 0 条（3.x 本地备份不带账号）；确认后关注、历史、分组、设置都在 | — |

## 测试

- 本任务不新增功能测试。每个不通过项都要有一个改之前会失败的测试：
  - 迁移规则的问题：`packages/live_store/test/migration_test.dart` 加用例；需要真实文件时，用模拟器上拿到的 `app_settings.hive` 做样本，**先脱敏**（Cookie、WebDAV 地址和密码、房间以外的个人信息换成合成值；最好用 hive_ce 按同样的结构重新写一份），放在 `packages/live_store/test/` 下，门禁的样本隐私检查要通过。
  - 网络电视库的问题：`apps/pure_live/test/iptv_store_test.dart`。
- 测试里的定时器至少 1 秒；不访问真实平台。

## 真机验证（维护者在 K90 上做）

就是上面的阶段 2、3（路 B、路 C 在 K90 上，路 A 在模拟器上）。截图放本文件夹的 `verify/`。

## 风险和注意

- **认错设备**：同时连着模拟器和 K90，每条 `adb` 命令都写 `-s`；K90 上只出现 `com.mystyle.purelive.v4dev`。在模拟器上可以 `adb root`、装卸正式包名的 3.x 和 4.x；在 K90 上绝不。
- **假 Cookie 被删**：启动 1 秒后会核验哔哩哔哩 Cookie，联网时假的会被退出（`app/startup.dart:123-126`）。第一次启动断网，先看完 V8 再联网。
- **测试包的旧数据**：路 B 前一定 `pm clear` 测试包，否则库里已有的数据优先，看不出迁移的结果；`pm clear` 也会删掉测试包在 Keystore 里的密钥，之后测试包上原来登录的账号要重新登录。
- **模拟器的 Keystore 是软件实现**，路 A 的 V8 不能代表真机——真机 Keystore 看路 B。
- **3.x 的数据目录权限**：`adb pull` 的是 root 读出来的副本；推进 K90 后由 `run-as` 用测试包的身份复制，文件属主自然是测试包，不需要 `chown`。
- 迁移只跑一次：要重来就 `pm clear`（路 B）或重新装 3.2.11 再覆盖（路 A，先卸载 4.x：模拟器上的 `adb uninstall com.mystyle.purelive`）。
- 可能冲突：无（不改代码；改代码的修复单独提交）。

## 环境和提交

- `source ~/tools/purelive-env.sh`；构建前根目录 `bash tools/ffmpeg_kit/fetch.sh`、`flutter pub get`；门禁在跑时不要构建正式包（PROCESS 第 8 节）。
- 分支 `ai/J06.1` 或本机工作区；提交信息以 `[J06.1]` 开头（英文）；不推 master。只提交 `record.md`、`verify/` 截图、（有问题时）测试和修复；`v3data/`、备份文件、`*.sha256`、`v4.db` 都留在本机临时目录。
- 提交前（改了代码时）：改过的包跑 `dart format --output=none --set-exit-if-changed .`、analyze、测试；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”（做到哪个阶段、核对表做到哪一行、模拟器和 `v3data/` 在本机哪里）、更新登记表的 `done`、`next`、`branch`。模拟器的 AVD（`pl3x`）留着，下次接着用。

## 报告（中文，简洁）

两条路 + 路 C 各自的结论；核对表每一行通过与否（不通过的写现象和根因线索）；3.x 文件是否没变；发现的问题和开的任务；新增的测试；S04.1 能直接用的结论（覆盖安装、版本号、签名）；需要维护者决定的（占位值清理、迁移报告进应用日志）。
