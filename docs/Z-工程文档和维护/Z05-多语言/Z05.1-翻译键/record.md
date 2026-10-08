# Z05.1 翻译键：记录

- 日期：2026-10-08
- 执行者：Claude
- 分支和提交：本机工作区（从 master `bbd52a2a3` 开始）
- 任务书：[brief.md](brief.md)；设计或说明：[README.md](README.md)

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| c1 列运行时键 | 做了 | 清单在 `apps/pure_live/test/i18n_runtime_keys.dart`：21 条拼键规则，展开成 227 个键（197 个在翻译文件里；没有的 30 个都属于有回退的“可选”规则：`audience_*_detail`、`popular_scope_*` 只给部分平台写了）。取值直接用代码里的枚举和表（`LogLevel.values`、`PortraitDisplayMode.values`、`LocalCatalog`、`SearchCapabilities`、`TwitchLanguagesTile.languages`、`RefreshRateTile.options()`、`SiteIds.supported` 加 `SiteIds.retired`、`PlayerErrorType.values`）；`room_mark_*` 的对照表是私有的，用“把每个键原样返回”的文字表调 `restrictionLabel`、`restrictionReason` 拿到；字号页的 5 个键在私有表里，从 `appearance_pages.dart` 源码读。brief 说 19 处，现在 `lib/` 里拼键的字面量还有 `popular_scope_*`、`local_currency_*`、`local_level_*`、`*_title`、`*_desc`（字号页），一并列入 |
| c1 变量传参 | 做了 | 226 处 `i18n(变量)` 的来源：设置目录（`settingsCatalog` 的标题、说明、分组，`SettingsArea`、`SettingsSection`、`SettingsSubpage` 的标题，`settingsGroupNotes`）、本地互动的平台包和礼物、搜索的平台说明，三张表都由测试遍历检查；其余是三元式和 switch 里的字面键，算字面引用 |
| c2 核对 18 个键 | 做了 | 见下表：18 个都不能被任何规则拼出来，`lib/`、`test/`、`integration_test/`、`packages/*/lib`、`packages/*/test`、`tools/` 里都没有出现 |
| c3 删除 | **没删，等维护者** | D-024（“翻译键这次不再清理”）没有解除，brief 写明删除前要维护者确认。现在的做法是“标记”：18 个键写进 `keptUnusedKeys`（注明 A08.5 留下、等 D-024），测试要求“没人用的键必须在这张表里”。维护者同意后：两份翻译文件删这 18 行、表里删同样 18 行，测试会核对两边一致 |
| 排序和缩进测试 | 做了 | 两份文件按键名排序、4 空格缩进、末尾一个换行（`JsonEncoder.withIndent('    ')` 重新编码后和原文一致） |

## 18 个键的核对

“拼不出来”指：没有一条规则的模板能产生它（`*_desc` 规则只产生字号页的 5 个键，`settings_app_font_desc` 等不在其中）。“3.x”指 `v3.2.11` 的 zh.json 里有没有。翻译文件是应用自带的资源，不进备份；3.x 应用用的是它自己那份，所以删除不影响 3.x 备份或其他版本。

| 键 | 3.x | 拼得出来吗 | 以字符串出现的地方 | 结论 |
|---|---|---|---|---|
| `danmaku_filter` | 有 | 否 | 无 | 不用，可删 |
| `danmaku_screen_interaction` | 有 | 否 | 无 | 不用，可删 |
| `danmaku_similarity_cache_duration_desc` | 有 | 否 | 无 | 不用，可删 |
| `danmaku_similarity_filter_desc` | 有 | 否 | 无 | 不用，可删 |
| `danmaku_similarity_max_cache_size_desc` | 有 | 否 | 无 | 不用，可删 |
| `danmaku_similarity_threshold_desc` | 有 | 否 | 无 | 不用，可删 |
| `live_play_danmaku_area` | 无 | 否（没有 `live_play_*` 规则） | 无 | 不用，可删 |
| `settings_app_font_desc` | 无 | 否 | 无 | 不用，可删 |
| `settings_block_list` | 无 | 否 | 无 | 不用，可删 |
| `settings_danmaku_auto_fps_desc` | 无 | 否 | 无 | 不用，可删 |
| `settings_danmaku_bottom_margin` | 无 | 否（没有 `settings_danmaku_*` 规则） | 无 | 不用，可删 |
| `settings_danmaku_long_press` | 无 | 否 | 无 | 不用，可删 |
| `settings_danmaku_tap` | 无 | 否 | 无 | 不用，可删 |
| `settings_danmaku_top_margin` | 无 | 否 | 无 | 不用，可删 |
| `settings_douyu_bots` | 无 | 否 | 无 | 不用，可删 |
| `settings_douyu_bots_desc` | 无 | 否 | 无 | 不用，可删 |
| `settings_group_danmaku_display` | 无 | 否 | 无 | 不用，可删 |
| `settings_repeat_window` | 无 | 否 | 无 | 不用，可删 |

## 另外发现的不用的键（不在 18 个里）

新测试一扫，还有 9 个键没人用，都是 3.x 带来的，按 D-024 留着，写进 `keptUnusedKeys` 并注明来历：`auto_close_time`（只有 `i18n_test` 读它）、`bilibili_guest_name_masked`、`dlan_title`、`double_click_to_exit` 和 `videofit_scaleDown`（3.x 的 4 个不对称键里的两个，`i18n_test` 固定）、`exit_yes`、`monitored`、`room_playback_timer`（B07 把定时器改成面板后不再用这个标题）、`user_not_found`。

## 改了哪些文件

- `apps/pure_live/test/i18n_runtime_keys.dart`（新）：拼键规则、表里的键、不是翻译键的拼接字面量、留着的不用的键、扫描函数。
- `apps/pure_live/test/i18n_test.dart`：新增 4 个用例。
- 翻译文件、`lib/` 都没改。

## 新的检查（以后谁清理翻译键都会被拦住）

| 用例 | 拦住什么 |
|---|---|
| `Z05.1: runtime keys built from enums and tables are translated` | 删了拼出来的键（两份文件都要有；可选规则只要求“有一份就两份都有”）；`lib/` 里新写了拼键的字面量却没登记规则（扫描所有 `'前缀_$x后缀'` 形式的字面量，模板必须在规则表或“不是翻译键”的表里）；规则在 `lib/` 里已经不存在 |
| `Z05.1: keys handed over through tables are translated` | 设置目录、本地互动、搜索说明三张表里的键缺翻译 |
| `Z05.1: every key is asked for, or kept on purpose` | 出现新的没人用的键（要么删、要么登记到 `keptUnusedKeys` 写明原因）；登记了却又被用上、或已经删掉的键 |
| `Z05.1: translation files are sorted by key and indented with four spaces` | 两份文件顺序乱、缩进不是 4 空格、末尾换行变了 |

“有人用”的判断：`apps/pure_live/lib`、`packages/*/lib` 里用引号写出的字符串，加上规则展开的键。所以写在常量、switch、三元式里的键都算在用。

## 测试

- “改之前会失败”的验证（没提交）：从两份文件都删掉 `settings_log_level_debug`，原有的 7 个用例全过，新用例 `runtime keys built from enums and tables are translated` 失败并指出 `settings_log_level_*: settings_log_level_debug`；恢复后全过。
- `flutter test test/i18n_test.dart`：11 个全过（原 7 个 + 新 4 个）；应用全部测试见提交前的检查。

## 真机上要看的

- 这次没删键、没改界面，不用上真机。维护者确认删除后再按 brief 的真机步骤看一遍。

## 停在哪

- 做完的阶段：第 1 阶段（列出拼接键，测试）、第 2 阶段（核对 18 个键）。
- 第 3 阶段：等维护者决定 D-024 是否解除；解除后删 18 个键只需改两份翻译文件和 `keptUnusedKeys`。
- 和 Z05.2 的核对：Z05.2 加回的键写在 `apps/pure_live/lib/shared/rooms/platform_texts.dart` 的表里（字面引用），本任务的“有人用”检查自动认得。
