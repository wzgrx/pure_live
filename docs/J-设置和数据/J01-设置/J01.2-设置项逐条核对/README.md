# J01.2 设置项逐条核对：218 个设置的默认值、取值范围和生效位置对照 3.x

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能（核对；发现不一致时改注册表或开修复任务）
- 来源：清点（[inventory/FEATURES.md](../../../inventory/FEATURES.md) 第 15 节“默认值（留给 J01.2）”）；V03.3（2026-10-03）把标题从“设置项核对”改成现在这样：读取检查已经做完，剩下默认值、范围、生效位置
- 旧编号：T09a.7
- 相关：J01.1（设置页）、J02.1（注册表）；决定 D-018；V03.3 [功能清点和已批准升级核对](../../../V-需求和反馈/V03-审查和调研/V03.3-功能清点和已批准升级核对/README.md)；任务书 [brief.md](brief.md)

## 目标

每一个设置都能回答三个问题，并且答案和 3.x 一样（或者是写明了依据的确认改动）：

1. **默认值**：没改过这个设置的用户（新装的，或者从 3.x 覆盖安装但没碰过它的）得到的值。
2. **取值范围**：滑块、数字框、可选值的上下限；存进来的值越界或类型不对时修成什么。
3. **生效位置**：哪个文件、哪一行读它，改了以后什么时候生效（立即、下次进房、重启）。

做完以后有一张逐条的对照表（本文件夹 `settings.md`），有表驱动的测试守住默认值；不一致的要么在这个任务里改掉（注册表的默认值或范围写错），要么开修复任务（行为不对），要么写进 DECISIONS（有意的改动）。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11`） | 现在 | 要做到 |
|---|---|---|---|
| 设置的数量 | 23 个控制器（`lib/common/services/settings/`）、录制 `lib/recorder/consts/recorder_keys.dart`、本地互动 `lib/modules/live_play/widgets/local_interaction/local_interaction_controller.dart` | 218 个（`packages/live_store/lib/src/settings/settings.dart`，`Settings.all` `:1413`），198 个沿用 3.x 键名，20 个新加 | 每个都在对照表里有一行 |
| 默认值 | `hive*('键', 默认值)`，172 个；默认值有字面量也有常量和表达式 | 注册表 `defaultValue:` | 172 个里 106 个字面相同、2 个写法不同意思一样（已核对，V03.3）；**64 个要展开 3.x 的常量或表达式再比**；另 46 个（20 新加、19 录制、7 常量键）单独查 |
| 范围 | 散在控制器和页面里（例如 `_boundedDouble`、对话框的校验、`normalizeAutoSyncHours`） | `IntSetting`/`DoubleSetting` 的 `min`/`max`（`setting.dart:113`、`:150` 夹紧），`StringSetting` 的可选值 | 每个数值设置的范围和 3.x 一样；页面上滑块和数字框的范围和注册表一样 |
| 生效位置 | 控制器的 `ever`、各页面直接读 | 清点第 15 节“读取”：210 个在设置页外有读取，4 个只在设置页里读（就是功能本身），4 个没人读（`videoPlayerKey` 和 3.x 也不读的 3 个） | 对照表每行写读取的文件:行和生效时机；“有人读”不等于“行为对”，抽查行为 |

## 方案

- c1 **出表**：写一个只读脚本（建议 `tools/docs/settings_audit.py`，不进门禁），从 `settings.dart` 取每个设置的键、类型、默认值、`min`/`max`/可选值、`section`、`scope`；从 `git archive v3.2.11 lib` 取 `hive*('键', 默认值)`（括号按层次配对，跨行也算）和录制、常量键的默认值；在 `apps/pure_live/lib`、`packages/*/lib`（不含测试）里找 `Settings.<名字>` 的读取位置。输出本文件夹的 `settings.md`（每个设置一行：键、类型、v4 默认、3.x 默认、v4 范围、3.x 范围、读取位置、结论）。
- c2 **展开 64 个常量**：逐个读 3.x 的常量定义（例如 `danmaku_settings_controller.dart:7-31`、`theme_settings_controller.dart:8-13`、`font_settings_controller.dart`、`player_consts.dart`），把值写进表；表达式类的（`_initialRefreshRateMode()`、`_getInitPageSize()`、`HomeMenu.values...`、`AppConsts.supportSites`）写清它在 3.x 新装时的结果。
- c3 **核对 46 个**：20 个新加的写清默认值的依据（哪个任务、哪个已批准升级）；19 个录制设置对 3.x `recorder/consts/recorder_config.dart`；7 个常量键（`historyLimit`、`room_card_mobile_config`、`room_card_desktop_config`、`autoSyncHoursInterval`、`downloadDirectoryPath`、`downloadDirectoryDecisionMade`、`remote_sync_device_id`）对 3.x 读写它们的地方。
- c4 **范围**：每个数值设置对照 3.x 的校验，以及设置页对应行（`settings_catalog.dart` 的 `slider`/`number` 参数）的范围，三者一致。
- c5 **生效位置**：表里写读取位置；抽查“改了是否立即生效”与 3.x 一致（立即 / 下次进房 / 重启）；顺带核对每个设置在设置页目录里有没有登记（`SettingsEntry.settings`），没登记的不计“已修改”、不随“恢复本页默认”。
- c6 **处理不一致**：注册表的默认值或范围写错的，在本任务里改（改默认值要在表里写依据，3.x 的键名不动）；行为不对的开修复任务到对应组；有意的改动写进 DECISIONS。
- c7 **守住**：加表驱动测试 `packages/live_store/test/settings_defaults_test.dart`：每个沿用 3.x 的设置，默认值等于表里的 3.x 默认值（确认改动的列出例外和决定编号）。

## 结果

逐条的对照表：[settings.md](settings.md)（`python3 tools/docs/settings_audit.py` 生成，手写的部分在 `tools/docs/settings_audit_notes.py`）。详细见 [record.md](record.md)。

- **数量**：现在是 219 个（A08.6 加了 `showChatGifts`）。198 个沿用 3.x 的键，21 个 v4 新加。3.x 的默认值：脚本直接取到 166 个（`hive*` 的字面值或同一文件的常量 157 个，录制的 `RecorderConfig` 9 个；常量键 `historyLimitKey`、`autoSyncHoursIntervalKey` 和 `RecorderKeys.*` 也解开了，所以和清点第 15 节的“172 / 64 / 46”分法不同），手工展开 32 个（3.x 的表达式、别的文件的常量、不经 `hive*` 读写的键，每个写了 3.x 的文件:行）。
- **结论**：198 个一样；3 个确认改动；14 个不一样，已改；4 个不一样，开了 J01.3。

| 结论 | 设置 | 3.x | 改之前的 v4 | 现在 | 依据 |
|---|---|---|---|---|---|
| 确认改动 | `hotAreasList` | 34 个平台 | 35 个（多 Kick） | 不变 | UPGRADES X-1 |
| 确认改动 | `themeColorSwitch` | `FF2196F3` | `FF2E6FE0` | 不变 | A11.2 C-3 |
| 确认改动 | `page_default_size` | 手机 12、宽屏 20（启动时算） | 0 = 界面按宽度定（结果一样） | 不变 | J02.1 有意差异；3.x 读到 0 时取第一个可选条数，也是 12 或 20 |
| 已改（范围） | `danmakuSpeed`、`danmakuFontSize`、`danmakuFontWeight` | 20～400、10～30、100～900 | 不限 | 同 3.x | 3.x 启动和导入时都夹（`danmaku_settings_controller.dart:118-120`），设置页滑块也是这个范围 |
| 已改（范围） | `repeatedDanmakuWindowSeconds` | 1～30 | ≥ 1 | 1～30 | 3.x 导入时夹，滑块 1～30 |
| 已改（范围） | 小窗弹幕 8 个：字号、粗细、速度、透明度、区域、条数、间隔、帧率 | 8～24、100～900、20～400、0.1～1、0.1～1、1～20、0.05～2、15～240 | 不限，或透明度、区域 0～1，条数 ≥ 1 | 同 3.x | 3.x 导入时夹（`:272-291`），3.x 和 v4 的滑块也是这个范围 |
| 已改（范围） | `windows_pip_width`、`windows_pip_height` | 0～16384 | 不限 | 0～16384 | `window_size_controller.dart:308`（只有 Windows 用） |
| 开 J01.3 | `historyLimit`、`videoFitIndex`、`proxyPort`、`appProxyPort` | 越界回到默认值 | 夹到一端 | 不变 | 要给 `IntSetting` 加参数（不在本任务可改的范围）；同时做弹幕粗细取整到整百 |

- 改范围只影响存着越界值的人（3.x 的数据、备份、手改）：读出来和 3.x 一样被夹住。没有改任何默认值，所以不用上真机。
- **目录登记**：`SettingsEntry.settings` 现在没有使用方（设置页没有“已修改”计数，“恢复本页默认”用各页自己的清单 `pipDanmakuSettings`、`portraitSettings`、`kernelSettings`）。照“打开一页的行登记那一页的设置”（例如“平台显示”登记 `hotAreasList`），屏蔽页入口 `video_block_list` 补登记了在屏蔽页上设置的 5 个过滤设置。其余没登记的 72 个都是本机记录、没有界面的（3.x 也没有），或在自己的页面上设置（网络电视、录制、本地互动、日志、电视界面、直播间里的状态）。
- **生效时机抽查**（和 3.x 一样）：弹幕外观、竖屏、卡片、字体和主题改了立即生效（界面 `watchSetting`）；刷新间隔改了立即重排定时器（`favorite_controller.dart` 的 `_settingChanged`，3.x 是 `ever`）；直播间的重复和相似过滤改了立即重建过滤器（`room_controller.dart` 监听 `_filterSettings`）；代理每个请求都读（3.x 改了重建 dio，效果一样）；画质、硬解、音量在进房时读（3.x 同样）；录制设置在下一次录制开始时读（3.x 的 `RecorderConfig` 同样）。
- **没人读的**：`autoRefreshTime`、`enableRotateScreen`、`m3uDirectory` 3.x 也不读；`videoPlayerKey` 只为备份往返（J02.1）。`defaultMobileVolume` 只有多画面读，直播间手机音量固定 1，和 3.x 一样（G05 说明）。
- **测试**：新增 `packages/live_store/test/settings_defaults_test.dart`（4 个用例：每个设置要么沿用 3.x 要么登记为新加；沿用的默认值等于 3.x 的，3 个确认改动列为例外；新加的默认值等于来源任务的；76 个数值设置的范围逐个列出）；`stores_test.dart` 加 1 个（14 个改了范围的设置存越界值，读出、重新打开、按 3.x 数据导入都被夹住）；`settings_page_test.dart` 加 1 个（屏蔽页入口登记的设置）。

## 验证

- 自动测试：新的 `settings_defaults_test.dart`；`packages/live_store` 和 `apps/pure_live` 的全部测试照常通过。
- 真机：不需要单独上机；改了默认值的设置，在对应组的真机清单里补一条（例如弹幕默认值改了就在 CHECKLIST 第 2 节看一次）。

## 留下的问题

- 越界值的修法和 3.x 不同的 4 个设置、弹幕粗细取整：J01.3（第三档）。
- 无其他。
