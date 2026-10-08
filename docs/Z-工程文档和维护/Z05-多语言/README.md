# Z05 多语言

中文和英文两套界面文字：翻译文件、读取和回退规则、键名的检查、运行时拼出来的键，以及平台层（`live_core` 等纯 Dart 包）给界面的中文文字怎么跟着界面语言变。

## 范围

- 包括：
  - `apps/pure_live/assets/translations/zh.json`、`en.json`（各 2545 个键，按键名排序、4 空格缩进）。
  - `apps/pure_live/lib/i18n/i18n.dart`：`AppLanguage`、`AppStrings`、全局的 `i18n`、`i18nOr`、`i18nExists`。
  - `packages/live_ui/lib/src/scope.dart` 的 `LiveUiStrings`（共用组件自己的几句文字，中英两份，由应用按 3.x 的键填）。
  - 翻译相关的测试 `apps/pure_live/test/i18n_test.dart`。
  - 清理不用的键的规矩（D-016、D-024）和运行时拼出来的键的清单（Z05.1）。
  - 平台层给界面的中文文字（公告、目录说明、分区名、画质名、弹幕系统提示）在英文界面下的处理（Z05.2）。
- 不包括（归哪里）：
  - 每个界面任务自己新加的文字：在那个任务里加（zh、en 都加，D-005），本子分类只管规则和检查。
  - 中文文字写得好不好（说明文字要让用户看得懂）→ 各界面任务和 [specs/UPGRADES.md](../../specs/UPGRADES.md) 的“说明文字”原则。
  - 设置里“语言”这一行的界面 → A11.2。
  - 电视界面的 `tv_` 键（现在 86 个，X03.1 加了其中 69 个）→ A17；用的是同一套文件。

## 现状：做到哪、怎么工作的

- 读取：启动时按设置 `language`（3.x 的键名和取值）选语言，没有存就看系统语言，再不行用中文（`AppLanguage.resolve`，`i18n.dart:41`）；`AppStrings.load`（`:69`）从资源读 JSON；`tr`（`:96`）把 `{name}` 占位换成参数。某个键在当前语言里没有时，依次回退到中文、英文、键名本身（`:56-60`）。全局 `i18n(key)`（`:156`）在文字加载前返回键名；`i18nOr`（`:159`）没有这个键时用给的默认文字；`i18nExists`（`:163`）。名字和参数照 3.x 的 `plugins/locale_helper.dart`，页面移植时可以一行一行对上。
- 两份文件有 4 个键不对称，是从 3.x 带来的：`count_wan`、`videofit_scaleDown` 只有中文，`count_k`、`double_click_to_exit` 只有英文（`i18n_test.dart:14-20` 固定了这一点）。
- 键的来源：3.x 的 2066 个键（`git show v3.2.11:assets/translations/zh.json`）+ 4.x 新加的；2026-10-02 `00f5edf18`（F.5a 第 6 条）删了 930 个“代码里没有字面引用”的键，结果误删了运行时拼出来的键：`portrait_orientation_*`（`b67399a09` 补回）、刷新率三档的说明（`584da6662` 补回，4.0.0 构建号 5000 里刷新率对话框显示成键名，5001 的发布说明写了“修了刷新率对话框里显示成键名的三条说明”）。由此定了 D-016（清理前先列出运行时拼出来的键）和 D-024（这次不再清理）。
- 运行时拼出来的键：`apps/pure_live/lib` 里 `i18n('…$…')` 这种写法 19 处（例如 `features/backup/log_page.dart:123` 的 `settings_log_level_${level.name}`、`features/settings/settings_editors.dart:965` 的 `settings_refresh_rate_short_$value`、`shared/rooms/room_texts.dart:15` 的 `site_<平台>`、`:120` 的 `room_mark_<限制>`、`features/live_play/player/bar_parts.dart:258` 的 `portrait_fullscreen_display_<模式>`、`features/live_play/local_interaction/` 的 `local_title_`、`local_danmaku_preset_`、`local_danmaku_placement_`、`local_danmaku_font_`）；另有 226 处把变量传给 `i18n`（设置目录 `settings_catalog.dart` 里的标题、说明键写成字符串常量，再由 `settings_model.dart:266` 等处翻译；平台的 `directoryNoticeKey` 从 `live_core` 来）。
- 平台层的中文：`packages/live_core` 不依赖翻译（ENGINEERING 第 4 节），公告、受限说明、我们翻译的分区名写成中文常量（例如 `packages/live_core/lib/src/sites/chzzk/chzzk_api.dart:252-260`），英文界面下照样显示中文；3.x 的平台适配器直接调 `i18n`（22 个文件、96 个键），跟界面语言。只有目录说明已经有键机制（`LiveDirectoryNotice`，`packages/live_core/lib/src/live_site.dart:412-415`）。Z05.2 起，应用用 `apps/pure_live/lib/shared/rooms/platform_texts.dart` 的“适配器常量 → 键”表在显示时换成界面语言（公告、分区名、画质名、弹幕系统提示），平台层仍写中文。
- 完成度：两种语言都能切换，D-005 的规则在合并审查里查（PROCESS 第 8 节第 4 条）；Z05.1 的测试守着运行时拼出来的键、表里的键、没人用的键和文件排序（删 18 个键等 D-024）；Z05.2 待真机，带参数的弹幕行和画质名留给以后。

## 代码地图

| 文件 | 职责 |
|---|---|
| `apps/pure_live/assets/translations/zh.json`、`en.json` | 全部界面文字，各 2545 个键（`pubspec.yaml:103-104` 声明为资源） |
| `apps/pure_live/lib/i18n/i18n.dart`（163 行） | `AppLanguage`（`:8`，3.x 的语言名和文件名）、`AppStrings`（`:61`，读取、回退、占位）、`currentStrings`（`:149`）、`i18n`（`:156`）、`i18nOr`（`:159`）、`i18nExists`（`:163`） |
| `packages/live_ui/lib/src/scope.dart` | `LiveUiStrings`（`:9`，`zh` `:49`、`en` `:67`）：共用组件（状态页、对话框按钮等）的文字 |
| `apps/pure_live/lib/shared/rooms/room_texts.dart` | 平台名、房间标记、播放错误的文字（运行时拼键最多的地方） |
| `packages/live_core/lib/src/live_site.dart:412` | `LiveDirectoryNotice`：平台层只给键、应用翻译的现成做法 |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `apps/pure_live/test/i18n_test.dart`（6 个） | 两份文件只差那 4 个键；`lib/` 里每个 `i18n('字面键')` 都有翻译（`:22`，拼出来的键看不到）；目录说明和人数说明不是字段名；`{name}` 占位和回退；语言的选择顺序；共用组件的文字来自 3.x 的键 |
| （没有） | 键名排序和 4 空格缩进没有测试（现在两份文件碰巧都是有序的）；运行时拼出来的键没有清单和测试 |

## 3.x 基线

- `git show v3.2.11:lib/plugins/locale_helper.dart`：`i18n`（`:3`）、`i18nOr`（`:10`），底层是 easy_localization；文件 `assets/translations/zh.json`、`en.json` 各 2066 个键。
- 3.x 的平台适配器直接调 `i18n`（例如 `lib/core/site/chzzk/chzzk_site.dart:246` 的 `chzzk_time_machine_notice`），平台文字跟界面语言。
- 要保留的：设置 `language` 的键名和取值（D-018）；3.x 的翻译键名能沿用的都沿用（页面移植时一一对上）；两份文件那 4 个不对称的键（3.x 的行为，测试固定）。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 18 个键已经没有字面引用（A08.5 换掉旧弹幕目录行留下的）。A08 子分类说明还写着 A08.3 留下了 `shield_tab_*`、`shield_clear*`、`shield_duplicate`，2026-10-07 核对：它们已经不在翻译文件里（现在只有 `shield_removed`、`shield_title`） | 清单在 [A08.5 记录](../../A-界面设计/A08-弹幕界面/A08.5-设置里的弹幕页/record.md)“留给以后” | 翻译文件里有不用的键 | D-024 这次不清理；Z05.1 按 D-016 先列运行时键再删 |
| 运行时拼出来的键没有清单，`i18n_test.dart:22` 的检查看不到它们 | 19 处 `i18n('…$…')`，见“现状” | 再清理时还会误删（2026-10-02 已经发生两次） | Z05.1 已加清单和测试（`test/i18n_runtime_keys.dart`） |
| 键名排序、缩进没有自动检查；AGENTS.md 和 PROCESS 第 8 节第 4 条要求“按键名排序、4 空格缩进” | `apps/pure_live/test/i18n_test.dart` | 合并时只能靠人看 | Z05.1 已加测试 |
| 英文界面下平台层给的公告、分区名、画质名、弹幕系统提示还是中文 | `packages/live_core/lib/src/sites/*/`、`packages/live_danmaku/lib/src/sites/` | 和 3.x 不一致（3.x 跟界面语言）；UPGRADES 20-10 等 6 条的余项 | Z05.2 已做（待真机）；带参数的弹幕行（礼物、订阅、置顶）和带编号的画质名没做，见 Z05.2 记录 |
| Z05.2 的旧任务书写“`check_ui_structure.py` 检查翻译键排序和硬编码文字”，实际不检查 | 旧版 `Z05.2/brief.md` 的“测试”一节 | 执行者会以为门禁守着 | v2 任务书已改正 |

## 相关决定和规范

- D-005：用户看得到的文字一律中文，zh、en 都加；代码、注释、提交信息用英文。
- D-016：清理翻译键前先列出运行时拼出来的键（4.0.0 里刷新率说明被误删）。
- D-024：翻译键这次不再清理；以后按 D-016 先列清单。
- D-018：3.x 的设置键名和含义不变（`language` 设置）。
- ENGINEERING 第 4 节（多语言：应用自带的翻译文件；`live_core` 不依赖翻译）；PROCESS 第 8 节第 4 条（合并审查查翻译）。

## 测试和验证

- `cd apps/pure_live && flutter test test/i18n_test.dart`；门禁 `--all` 跑全部。
- 真机：设置 → 语言切到 English 走一遍主要页面（S02 的 CHECKLIST 没有专门一节；Z05.2 的任务书写了英文界面的真机步骤）。

## 路线

1. Z05.1（第三档，小，三个阶段）：列出运行时拼出来的键 → 核对 18 个键 → 删除并跑全部测试；顺手加“键名有序、4 空格缩进”和“运行时键都有翻译”的测试。D-024 说“这次不再清理”，开工前请维护者确认现在可以清。
2. Z05.2（第三档，大，三个阶段）：英文界面下平台层的文字按界面语言显示。和 Z05.1 互相影响：Z05.2 加回的 3.x 键要在 Z05.1 的清单里标成“在用”，谁后做谁核对。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [Z 工程文档和维护](../README.md)。

- 代码：`apps/pure_live/assets/translations/`
- 进度：`█████████████████░░░` 84%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| Z05.1 | 翻译键：列出运行时拼出来的键，再清理不用的键（18 个） | 工程 | 待确认 | 2026-10-08 | 675c3b191 | [设计或说明](Z05.1-翻译键/README.md)、[任务书](Z05.1-翻译键/brief.md)、[记录](Z05.1-翻译键/record.md) |
| Z05.2 | 英文界面下平台层给的文字还是中文：公告、目录说明、分区名、画质名（3.x 在平台层用翻译键；UPGRADES 20-10、25-7、25-8、26-6、29-6、30-10） | 功能 | 待真机 | 2026-10-08 | 9d13632b7 | [设计或说明](Z05.2-英文界面里平台给的中文/README.md)、[任务书](Z05.2-英文界面里平台给的中文/brief.md)、[记录](Z05.2-英文界面里平台给的中文/record.md) |

## 还没完成的

- **Z05.1 翻译键：列出运行时拼出来的键，再清理不用的键（18 个）**（待确认，第三档，规模 小）
  - 阶段：✓ 列出拼接键 → ✓ 核对 18 个键 → 删除并跑全部测试
  - 接着做：维护者决定 D-024 是否解除；解除后从两份翻译文件和 test/i18n_runtime_keys.dart 的 keptUnusedKeys 删 18 个键
  - 说明：21 条拼键规则（227 个键）和 3 张键表有测试守着；没人用的键必须登记在 keptUnusedKeys（18 个 + 9 个 3.x 键）

<!-- docs:生成结束 -->
