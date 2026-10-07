# J01.2 设置项逐条核对：任务书

## 背景

- 来源：功能清点 [inventory/FEATURES.md](../../../inventory/FEATURES.md) 第 15 节“默认值（留给 J01.2）”；V03.3（2026-10-03）重做了读取检查，把本任务的标题改成“218 个设置的默认值、取值范围和生效位置对照 3.x”。
- 现象：没有现象报告。风险是“悄悄变了”：4.x 的设置注册表是 J02.1 一次性照 3.x 抄的，64 个默认值在 3.x 里是常量或表达式，当时没有展开核对；新装用户（以及从没改过某个设置的老用户）可能得到和 3.x 不一样的默认行为，而没有任何测试会发现。
- 为什么现在做：第二档。覆盖安装 3.x 的用户改过的设置会被迁移（J06），没改过的就吃 4.x 的默认值，所以默认值和 3.x 一致是 D-018“含义不变”的一部分。
- 已经做过的：J02.1（注册表，`d2fbe3072`）、J01.1（设置页，`9a90cbf6c`）、V03.3（读取检查和默认值初比：172 个 `hive*` 设置里 106 个字面相同、2 个写法不同意思一样、64 个是常量或表达式）。

## 目标和验收

1. 本文件夹有 `settings.md`：218 个设置每个一行，列出键、类型、v4 默认值、3.x 默认值（常量已展开成值）、v4 范围（`min`/`max` 或可选值）、3.x 范围、设置页里的范围（滑块或数字框的参数）、读取位置（文件:行，设置页以外的）、生效时机、结论（一样 / 确认过的改动〔写任务或决定编号〕/ 不一样〔写处理〕）。
2. 64 个常量或表达式全部展开（清单见“现状”），每个有 3.x 的文件:行。
3. 46 个非 `hive*` 的设置（20 个新加、19 个录制、7 个常量键）每个有结论。
4. “不一样”的处理完：注册表写错的在本任务里改（`settings.dart` 的 `defaultValue`、`min`、`max`，键名不动）；行为不对的已在登记表的对应组开了任务（报告里列编号，登记表由维护者改）；有意的改动写进报告，请维护者加进 DECISIONS。
5. 新测试 `packages/live_store/test/settings_defaults_test.dart`：每个沿用 3.x 的设置，`Settings.xxx.defaultValue` 等于表里的 3.x 默认值；确认过的改动作为例外列出并注明编号。
6. 每个设置在设置页目录里有没有登记（`SettingsEntry.settings`）写在表里；应该登记而没登记的补上（只改 `settings_catalog.dart` 里的 `settings:` 参数，不改界面）。
7. `packages/live_store`、`apps/pure_live` 全部测试和门禁通过。

## 现状（读代码得出，写文件:行）

- 注册表：`packages/live_store/lib/src/settings/settings.dart`（1592 行），`Settings.all` `:1413`，`byKey` `:1591`；类型和修复 `setting.dart`（`IntSetting` `:86` 夹紧 `:113`，`DoubleSetting` `:121` 夹紧 `:150`，`StringSetting` `:158`）。
- 读设置：界面 `watchSetting`（`apps/pure_live/lib/app/services.dart:143`），逻辑 `store.settings.get/watch`；写 `writeSetting`（`features/settings/settings_tiles.dart:16`）。
- 设置页目录 `features/settings/settings_catalog.dart:321` 起，129 行；滑块和数字框的范围写在每行的参数里（例如 `..slider(... min:, max:, divisions:)`）。
- **64 个要展开的 3.x 默认值**（V03.3 的脚本结果，2026-10-07 复跑一致；位置是 `git show v3.2.11:lib/<路径>` 的行号）：
  - `common/services/settings/app_settings_controller.dart`：`refreshRateMode`（:53，`_initialRefreshRateMode()` :36-40）、`realOnlinePlatforms`（:55）、`savedMenuIds`（:69）。
  - `favorite_room_controller.dart`：`hotAreasList`（:20，`AppConsts.supportSites`）、`preferPlatform`（:24）。
  - `theme_settings_controller.dart`：`themeMode`、`themeColorSwitch`、`language`、`crossAxisSpacing`、`mainAxisSpacing`、`loadingStyle`（:17-23；常量在 :8-13）。
  - `font_settings_controller.dart`：`textScaleFactor`、`fontSizeBodySmall`、`fontSizeBodyMedium`、`fontSizeBodyLarge`、`fontSizeTitleMedium`、`fontSizeTitleLarge`（:39-44）。
  - `player_settings_controller.dart`：`videoPlayerKey`（:34）、`preferResolution`（:36）、`preferResolutionCellular`（:37）、`portraitLayoutMode`（:58）、`portraitFullscreenPolicy`（:59）、`portraitFullscreenDisplayMode`（:63）、`portraitDanmakuMode`（:68）。
  - `danmaku_settings_controller.dart`（常量 :7-31）：`noEmojiMode`（:59）、`danmakuTopArea`、`danmakuArea`、`danmakuBottomArea`、`danmakuSpeed`、`danmakuFontSize`、`danmakuFontWeight`、`danmakuFontBorder`、`danmakuOpacity`（:60-67）、`danmakuFps`、`danmakuAutoFps`（:70-71）、`enablePipDanmaku`、`pipDanmakuAutoScale`（:79-80）、`pipDanmaNoEmojiMode`、`pipDanmakuUseOriginalColor`、`pipDanmakuColor`、`pipDanmakuFontSize`、`pipDanmakuFontWeight`、`pipDanmakuSpeed`、`pipDanmakuOpacity`、`pipDanmakuArea`、`pipDanmakuMaxVisibleCount`、`pipDanmakuEmitInterval`、`pipDanmakuFps`、`pipDanmakuAutoFps`（:83-94）、`filterDouyuSuspectedAutomatedMessages`（:99）、`enableDanmakuSimilarityFilter`（:105）。
  - `room_card_settings_controller.dart`：`room_card_mobile_preset`、`room_card_desktop_preset`（:251-252）。
  - `page_settings_controller.dart`：`page_default_size`（:17，`_getInitPageSize()`）。
  - `refresh_config_controller.dart`：`autoRefreshInterval`、`maxConcurrentRefresh`、`thumbnailRefreshInterval`（:27-30）。
  - `proxy_settings_controller.dart`：`proxyPort`（:13）、`appProxyPort`（:18）。
  - `window_size_controller.dart`：`window_width`、`window_height`（:103-104）。
  - `exit_settings_controller.dart`：`exitChoose`（:24）、`autoShutDownTime`（:25）。
  - `modules/live_play/widgets/local_interaction/local_interaction_controller.dart`：`localInteraction.previewPlatform`（:93）。
- 46 个非 `hive*`：新加的 20 个（清点第 15 节“数量”逐个列了来源任务）；录制 19 个（`segmentTime`、`maxTaskCount`、`autoReconnect`、`maxCacheMB`、`enableCacheLimit`、`recordSavePath`、`default_quality`、`max_retry_count`、`retry_delay`、`enable_polling`、`live_check_interval`、`enable_backoff`、`max_check_interval`、`auto_start_on_boot`、`recorder_prefer_best_stream`、`recorder_rw_timeout`、`recorder_thread_queue_size`、`recorder_folder_naming_strategy`、`recorder_record_danmaku`，3.x 默认值在 `lib/recorder/consts/recorder_config.dart`，键在 `recorder_keys.dart`）；常量键 7 个（`historyLimit`、`room_card_mobile_config`、`room_card_desktop_config`、`autoSyncHoursInterval`〔3.x `iptv_settings_controller.dart:7`〕、`downloadDirectoryPath`、`downloadDirectoryDecisionMade`、`remote_sync_device_id`）。
- 已知要特别看的：`refreshRateMode`（v4 `settings.dart:64` 写 `'powerSaving'`；3.x 新装时由 `enableHighRefreshRate` 推出；迁移时的换算在 `legacy/legacy_snapshot.dart:409-411`）；`page_default_size`（v4 `:718` 默认 0 = 界面按宽度决定，`appearance_pages.dart:1009`；3.x 读回 v4 备份里的 0 会怎样）；`themeColorSwitch`（确认改动：品牌蓝，A11.2 C-3，`live_store.dart:154-162` 迁移一次）。

## 3.x 基线

- 默认值：上面的 3.x 文件:行；`hive*` 的定义在 `lib/common/services/utils/hive_rx.dart`；box 是 `app_settings`（`lib/common/utils/hive_pref_util.dart:41-44`）。
- 范围：3.x 的范围散在控制器（例如弹幕上下留白 `_boundedDouble` 0～300 像素、`iptv_settings_controller.dart:15-17` 的 `normalizeAutoSyncHours`）和设置页的对话框里（`lib/modules/settings/pages/*.dart`、`lib/modules/live_play/pages/danmaku_settings_page.dart`），要逐个找。
- 要保留：键名、含义、3.x 备份里的分区和字段（`section`、`backupKey`）——本任务不改任何键名。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节、第 8 节、第 14 节）。
2. `docs/specs/ENGINEERING.md`。
3. 本文件夹的 `README.md`；`docs/J-设置和数据/J01-设置/README.md`；`docs/inventory/FEATURES.md` 第 15 节；`docs/J-设置和数据/J02-存储和加密/J02.1-存储和迁移/record.md`（“做法”“有意差异”）；`docs/J-设置和数据/J01-设置/J01.1-设置/record.md`（“live_store 的改动”）。
4. 代码：`packages/live_store/lib/src/settings/` 三个文件；`apps/pure_live/lib/features/settings/settings_catalog.dart`。

## 范围

- 可以改：`packages/live_store/lib/src/settings/settings.dart`（只改 `defaultValue`、`min`、`max`、可选值，且每处在 `settings.md` 写依据）；`apps/pure_live/lib/features/settings/settings_catalog.dart`（只改 `settings:` 登记和滑块、数字框的范围参数，让它和注册表一致）；`packages/live_store/test/`（新测试）；`tools/docs/settings_audit.py`（新脚本，只读）；本文件夹（`settings.md`、`record.md`）。
- 不能改：任何键名、`section`、`backupKey`、`scope`（D-018）；设置页的界面（A11）；读设置的功能代码（行为不对的开任务，不在这里修）；`legacy/` 的迁移规则（J06）；其他组的界面和逻辑；版本号、`assets/version.json`、`assets/releases.json`；签名配置。

## 方案和阶段

| 阶段 | 做什么（对应 README 的 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | c1 出表：脚本取 v4 的 218 个设置和 3.x 的默认值、读取位置，生成 `settings.md` 初稿 | `tools/docs/settings_audit.py`、`settings.md` | 表有 218 行；脚本的数字和清点第 15 节一致（172 / 106 / 2 / 64 / 46） |
| 2 | c2、c3 展开 64 个常量、核对 46 个非 `hive*` 的默认值 | `settings.md` | 每行有 3.x 默认值（值和文件:行）和结论 |
| 3 | c4、c5 范围和生效位置：注册表、3.x、设置页三处的范围；读取位置和生效时机；目录登记 | `settings.md` | 每个数值设置三处范围都写了；“不一样”的行都有处理意见 |
| 4 | c6、c7 处理：改注册表和目录里写错的；加表驱动测试；列出要开的任务和要加的决定 | `settings.dart`、`settings_catalog.dart`、`settings_defaults_test.dart`、`record.md` | 验收 4～7 |

每个阶段都要能单独合并（门禁通过）。阶段 1～3 只有文档和脚本，没有行为变化。

## 测试

- 新增 `packages/live_store/test/settings_defaults_test.dart`：一张 `{键: 3.x 默认值}` 的表（从 `settings.md` 生成或手写），逐个断言 `Settings.byKey(键)!.defaultValue == 值`；例外表写决定编号（例如 `themeColorSwitch` → A11.2 C-3）。
- 改了范围的设置：在 `stores_test.dart` 加越界值读出后夹紧的用例。
- 改了默认值的设置：先写一个改之前会失败的断言（就是上面的表驱动测试里的那一行）。
- 测试不访问真实平台；没有定时器。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 清掉测试包数据（`adb shell pm clear com.mystyle.purelive.v4dev`）后打开，进设置逐页看改过默认值的那几项 | 显示的值和 `settings.md` 的 v4 默认值一致 |
| 2. 对每个改了默认值的设置，照它的功能走一遍（例如弹幕默认值改了就进一个弹幕多的直播间看） | 行为和 3.x 新装时一致 |

没有改默认值时跳过真机。

## 风险和注意

- 改默认值会影响所有没改过这个设置的 4.x 用户（包括已经装了 4.0.0 的），报告里要写清楚影响谁；拿不准的不改，列给维护者决定。
- 3.x 的表达式默认值依赖运行环境（屏幕宽度、平台、旧开关），写结论时说明是哪种环境下的值（Android 手机为准）。
- 脚本只读，不要用它去改 `settings.dart`（容易破坏格式）；改动手写。
- 可能冲突的文件：`settings.dart`（新设置的任务都会加行，例如 A08.6 的礼物开关、V01 的提议实现）、`settings_catalog.dart`（A08.6、A04.1）。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 3.x 代码：`git show v3.2.11:lib/...` 或本机只读副本 `~/ref/v3ref/lib/`。
- 分支 `ai/J01.2` 或本机工作区；提交信息以 `[J01.2]` 开头（英文）；不推 master。
- 提交前：`packages/live_store` 跑 `dart format --output=none --set-exit-if-changed .`、`dart analyze`、`dart test`；改了 `apps/pure_live` 时跑 `flutter analyze` 和全部 `flutter test`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”（`settings.md` 核到第几行）、更新登记表的 `done`、`next`、`branch`（登记表现在没有写阶段，开工时按上表补上四个阶段）。

## 报告（中文，简洁）

四个数字（一样、确认过的改动、不一样已改、不一样待处理）；改了哪些设置的默认值或范围（每个写 3.x 值、原 v4 值、新值、依据）；要开的任务（组、标题、原因）；要加的决定；测试数量；要在真机上看的；可能冲突的文件。
