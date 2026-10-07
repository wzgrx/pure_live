# Z05.1 翻译键：列出运行时拼出来的键，再清理不用的键（18 个）

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：工程
- 来源：A08.5（设置里的弹幕页）的 c3“清理翻译键”按维护者决定没做，留下 18 个没有字面引用的键（[A08.5 记录](../../../A-界面设计/A08-弹幕界面/A08.5-设置里的弹幕页/record.md)“留给以后”）；2026-10-02 `00f5edf18` 删 930 个不用的键时误删了运行时拼出来的键，定了 D-016、D-024。
- 旧编号：T00e.1
- 相关：决定 D-016（先列运行时拼出来的键）、D-024（这次不再清理，以后按 D-016）；Z05.2（会加回 3.x 平台层的键，两边互相核对）；A08.5（留下 18 个键的任务）

## 目标

1. 有一份“运行时拼出来的键”的清单，并且有测试保证这些键在两份翻译文件里都存在——以后任何人清理翻译键，测试会拦住误删。
2. 在清单的保护下，删掉确实不用的 18 个键，两份翻译文件保持有序、4 空格缩进。
3. 加一个测试检查两份文件按键名排序、4 空格缩进（现在没有，只靠人看）。

## 3.x 和现状

| 方面 | 3.x | 现在（文件:行） | 要做到 |
|---|---|---|---|
| 键的数量 | `assets/translations/zh.json`、`en.json` 各 2066 个 | 各 2545 个（`apps/pure_live/assets/translations/`） | 删掉确认不用的 |
| 字面引用检查 | 无 | `apps/pure_live/test/i18n_test.dart:22`：`lib/` 里每个 `i18n('字面键')` 都有翻译 | 保留 |
| 运行时拼出来的键 | 3.x 也有（例如 `portrait_orientation_*`），没有清单 | 19 处 `i18n('…$…')`（`log_page.dart:123`、`audience_pages.dart:196`、`settings_editors.dart:297`、`:965`、`iptv_guide_rows.dart:126`、`local_interaction.dart:172`、`:310`、`local_interaction_panel.dart:433`、`bar_parts.dart:258`、`:261`、`search_capability.dart:195`、`room_texts.dart:15`、`:120`、`:124`、`:166`、`local_style_panel.dart:288`、`:289`、`:304`、`:323`，都在 `apps/pure_live/lib/` 下）；226 处把变量传给 `i18n`（多是设置目录里写成字符串常量的键） | 清单 + 测试 |
| 18 个不用的键 | — | `danmaku_filter`、`danmaku_screen_interaction`、`danmaku_similarity_cache_duration_desc`、`danmaku_similarity_filter_desc`、`danmaku_similarity_max_cache_size_desc`、`danmaku_similarity_threshold_desc`、`live_play_danmaku_area`、`settings_app_font_desc`、`settings_block_list`、`settings_danmaku_auto_fps_desc`、`settings_danmaku_bottom_margin`、`settings_danmaku_long_press`、`settings_danmaku_tap`、`settings_danmaku_top_margin`、`settings_douyu_bots`、`settings_douyu_bots_desc`、`settings_group_danmaku_display`、`settings_repeat_window`。2026-10-07 核对：18 个都还在 zh.json 里，`apps/pure_live/lib` 和 `packages/*/lib` 里都没有用引号写出它们的地方 | 核对拼接规则后删掉 |
| 排序和缩进 | — | 两份文件现在都是有序的（碰巧），没有测试 | 加测试 |

## 方案

- c1 列运行时键（第 1 阶段）：对 19 处拼接，逐个写出“前缀 + 可能的取值”（取值来自枚举、常量表或数据，例如 `LogLevel.values`、`PortraitDisplayMode.values`、`LocalCatalog` 的 id），展开成完整键名；226 处变量传参的，找出变量的来源（字符串常量就算字面引用）。结果写成 `apps/pure_live/test/i18n_runtime_keys.dart`（或测试里的一张表），测试断言每个展开的键在 zh、en 都有（4 个不对称键除外）。
- c2 核对 18 个键（第 2 阶段）：对每个键检查它是否能被 c1 的任何拼接规则拼出来（例如 `settings_danmaku_tap` 会不会被 `settings_danmaku_$x` 拼出），是否在 `packages/*/lib`、`apps/pure_live/lib`、`apps/pure_live/test`、`integration_test` 里以字符串出现。（A08 子分类说明提到的 `shield_tab_*`、`shield_clear*`、`shield_duplicate` 已经不在翻译文件里，不用核对。）结果写进 `record.md`（每个键一行：结论和依据）。
- c3 删除（第 3 阶段）：确认不用的从两份文件删掉；加“键名有序、4 空格缩进”的测试；跑应用全部测试。

## 验证

- 自动测试：`apps/pure_live/test/i18n_test.dart` 新增两个用例（运行时键都有翻译；两份文件有序、4 空格缩进），原有 6 个照旧通过；应用全部 `flutter test` 通过。
- 真机：删除后在 K90 上中英文各走一遍设置 → 弹幕、设置 → 弹幕屏蔽、直播间的弹幕设置和屏蔽管理，没有显示成键名的文字（brief 的真机步骤）。

## 留下的问题

- 还没开始。D-024 写的是“这次不再清理”，开工前请维护者确认现在可以删（第 1 阶段的清单和测试不受影响，可以先做）。
- Z05.2 会从 3.x 加回平台层的键（96 个里的一部分），本任务的清单要包括它们；两个任务谁后做谁核对。
