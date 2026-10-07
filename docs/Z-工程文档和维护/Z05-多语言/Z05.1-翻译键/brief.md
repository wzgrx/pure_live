# Z05.1 翻译键：任务书

## 背景

- 来源：A08.5 的 c3“清理翻译键”按维护者决定没做，18 个键没有字面引用了（[A08.5 记录](../../../A-界面设计/A08-弹幕界面/A08.5-设置里的弹幕页/record.md)“留给以后”）。登记时的旧编号 T00e.1。
- 教训：2026-10-02 `00f5edf18`（F.5a 第 6 条）按“代码里没有字面引用”删了 930 个键，误删了两组运行时拼出来的键：`portrait_orientation_*`（竖屏诊断信息显示成键名，`b67399a09` 补回）、刷新率三档的说明 `refresh_rate_*_desc`（4.0.0 构建号 5000 的刷新率对话框显示成键名，`584da6662` 补回）。于是定了 D-016（先列运行时拼出来的键）、D-024（这次不再清理，以后按 D-016）。
- 为什么现在做：第三档；不删键不影响用户，但没有运行时键的清单和测试，下一次清理还会出同样的事。**D-024 说“这次不再清理”，第 3 阶段（删除）开工前请维护者确认**；第 1、2 阶段只加测试和清单，随时可以做。
- 已经做过的：`apps/pure_live/test/i18n_test.dart:22` 的“每个字面 `i18n('…')` 键都有翻译”测试（`00f5edf18` 加的）。

## 目标和验收

1. 运行时拼出来的键有一份清单（测试代码里的表），每个展开后的键在 zh.json、en.json 都存在，有测试守着（`count_wan`、`videofit_scaleDown`、`count_k`、`double_click_to_exit` 四个不对称键照 `i18n_test.dart:14-20` 例外）。
2. `record.md` 里 18 个键每个一行：能不能被拼出来、在哪里以字符串出现、结论。
3. （维护者确认后）确认不用的键从两份文件删掉，两份文件仍然只差那 4 个键。
4. 新测试：两份文件按键名排序、4 空格缩进、文件末尾换行和现在一致。
5. 应用全部测试和门禁通过。

## 现状（读代码得出，写文件:行）

- 翻译：`apps/pure_live/lib/i18n/i18n.dart:156` `i18n`、`:159` `i18nOr`、`:163` `i18nExists`；文件 `apps/pure_live/assets/translations/zh.json`、`en.json` 各 2545 个键，现在都有序。
- 现有测试 `apps/pure_live/test/i18n_test.dart`：`:14` 两份文件只差 4 个键；`:22` 正则 `\bi18n\(\s*'([A-Za-z0-9_.]+)'` 扫 `lib/` 的字面键；`:35` 目录说明不是字段名；`:45` 读取和占位；`:60` 语言选择；`:70` 共用组件的文字。
- 运行时拼出来的键（`apps/pure_live/lib/` 下，2026-10-07 `grep -rnE "i18n(Or|Exists)?\(\s*'[^']*\\$" lib`）：
  - `features/backup/log_page.dart:123` `settings_log_level_${level.name}`；
  - `features/settings/audience_pages.dart:196` `audience_${id}_detail`（`i18nOr`，没有时空）；
  - `features/settings/settings_editors.dart:297` `settings_twitch_language_$code`（`i18nOr`，没有时用代码）、`:965` `settings_refresh_rate_short_$value`；
  - `features/live_play/logic/iptv_guide_rows.dart:126` `live_play_weekday_${day.weekday}`；
  - `features/live_play/local_interaction/logic/local_interaction.dart:172` `local_title_$title`、`:310` `local_danmaku_preset_$preset`；`local_interaction_panel.dart:433` `local_title_$id`；`local_style_panel.dart:288`、`:289` `local_danmaku_preset_${preset.id}`、`:304` `local_danmaku_placement_$id`、`:323` `local_danmaku_font_$id`；
  - `features/live_play/player/bar_parts.dart:258` `portrait_fullscreen_display_${mode.name}`、`:261` 同上加 `_desc`；
  - `features/search/search_capability.dart:195` `${note}_short`；
  - `shared/rooms/room_texts.dart:15` `site_<平台>`（`i18nOr`）、`:120` `room_mark_<限制>`、`:124` 同上加 `_hint`、`:166` `error_${type.name}`（`i18nOr`，没有时 `error_unknown`）。
- 变量传参 226 处（`grep -rnE "i18n(Or)?\(\s*[a-zA-Z_]" lib`），主要是：设置目录 `features/settings/settings_catalog.dart` 里标题和说明写成字符串常量，由 `settings_model.dart:266`、`:270`、`:275` 翻译；`i18n(cond ? 'a' : 'b')` 这种三元式；`live_core` 平台的 `directoryNoticeKey`（`packages/live_core/lib/src/live_site.dart:414`）。
- 18 个键：清单见本文件夹 `README.md`“3.x 和现状”表；2026-10-07 核对都还在 zh.json，`lib/` 和 `packages/*/lib` 里没有用引号写出的地方。

## 3.x 基线

- `git show v3.2.11:lib/plugins/locale_helper.dart`（easy_localization 的 `i18n`、`i18nOr`）；3.x 文件各 2066 个键，3.x 自己也有拼键（例如 `portrait_orientation_*`），没有清单。
- 要保留：3.x 的键名能沿用的不改名；4 个不对称键不动（3.x 的行为，`i18n_test.dart:14` 固定）。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节、第 8 节第 4 条、第 14 节）、`docs/DECISIONS.md` 的 D-005、D-016、D-024。
2. 本文件夹的 `README.md`；`docs/Z-工程文档和维护/Z05-多语言/README.md`；`apps/pure_live/test/i18n_test.dart`；`apps/pure_live/lib/i18n/i18n.dart`。
3. `docs/Z-工程文档和维护/Z05-多语言/Z05.2-英文界面里平台给的中文/README.md`（它会加回的键）。

## 范围

- 可以改：`apps/pure_live/assets/translations/zh.json`、`en.json`（只删确认不用的键，不改值）；`apps/pure_live/test/i18n_test.dart`（加用例），可以新建 `apps/pure_live/test/i18n_runtime_keys.dart` 放清单；本文件夹的文档。
- 不能改：任何 `lib/` 代码（清单要跟着代码走，不为了好列清单改代码）；4 个不对称键；3.x 的设置键名和含义；版本号、`assets/version.json`、`assets/releases.json`；签名配置。

## 方案和阶段

| 阶段 | 做什么（对应 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 列出拼接键 | c1：19 处拼接逐个展开（取值来自 `LogLevel.values`、`PortraitDisplayMode.values`、`LocalCatalog` 的 id、`SiteIds.supported`、`LiveRestriction.values`、`PlayerException` 的类型等，测试里直接用这些枚举和常量展开，不手抄）；226 处变量传参确认来源 | `test/i18n_test.dart` 或 `test/i18n_runtime_keys.dart` | 新测试“运行时键都有翻译”通过；同时加“有序、4 空格”测试 |
| 2 核对 18 个键 | c2：每个键能不能被拼出来、在哪里以字符串出现（含 `test/`、`integration_test/`、`packages/`） | `record.md` | 每个键有结论和依据 |
| 3 删除并跑全部测试 | c3：维护者确认后删除 | 两份翻译文件 | 两份文件仍只差 4 个键；应用全部 `flutter test` 通过 |

每个阶段都要能单独合并（门禁通过）。

## 测试

- 改之前会失败的：故意从 zh.json 删掉 `settings_log_level_debug`（或任一个运行时键）时，新测试“运行时键都有翻译”失败，现有的 `:22` 测试不失败——在 `record.md` 写明这个验证做过（不提交这个删除）。
- 新用例（`apps/pure_live/test/i18n_test.dart`）：
  - `runtime keys built from enums and tables are translated`：用枚举和常量表展开全部拼接键，断言 zh、en 都有；
  - `translation files are sorted by key and indented with four spaces`：读原文，断言键的顺序等于排序后的顺序、每个键行以 4 个空格开头、`jsonEncode` 回去（`JsonEncoder.withIndent('    ')`）和原文一致。
- 测试不访问网络；定时器至少 1 秒（这里不用定时器）。

## 真机验证（维护者在 K90 上做，第 3 阶段合并后）

| 步骤 | 期望 |
|---|---|
| 1. 设置 → 弹幕，从上滑到底；设置 → 弹幕屏蔽 | 每一行都是中文，没有 `danmaku_`、`settings_` 开头的键名 |
| 2. 进直播间 → 弹幕设置标签、屏蔽管理标签 | 同上 |
| 3. 设置 → 通用 → 日志，切换日志级别；设置 → 显示 → 刷新率 | 级别名、刷新率三档和说明都是文字 |
| 4. 设置 → 语言 → English，重复 1～3 | 都是英文，没有键名 |
| 5. 切回简体中文 | 恢复 |

## 风险和注意

- 拼接的取值有的来自数据（例如 `audience_${id}_detail` 的平台 id、`local_title_$title` 的头衔）：用 `i18nOr` 的地方本来就允许没有翻译，清单里标“可选”，测试只断言“有翻译的那些在两份文件里同时存在”。
- 删键是不可逆的小风险，但合并前全部测试都过、真机看一遍就够；不要在同一个提交里顺手删别的键。
- 可能冲突的文件：两份翻译文件（几乎所有界面任务都会改），合并时两边都保留、重新排序；新排序测试会帮忙发现顺序错。

## 环境和提交

- `source ~/tools/purelive-env.sh`；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 分支 `ai/Z05.1` 或本机工作区；提交信息以 `[Z05.1]` 开头（英文）；不推 master。
- 提交前：`apps/pure_live` 跑 `dart format --output=none --set-exit-if-changed .`、`flutter analyze`、全部 `flutter test`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”（展开到哪一处拼接、核对到第几个键）、更新登记表的 `done`、`next`、`branch`。

## 报告（中文，简洁）

运行时键的规则数和展开后的键数；18 个键各自的结论；删了哪些（或等维护者确认）；新测试数量和“改之前会失败”的验证；可能冲突的文件；需要维护者决定的（D-024 是否解除）。
