# A01.2 颜色、文字、间距、动效：任务书（第 3 阶段“其余页面”）

## 背景

- 来源：界面重构计划书（[specs/UI.md](../../../specs/UI.md) 第 8 节，2026-10-01 用户确认）的设计系统第一项；第 1 阶段（设计）就是规范第 8 节，第 2 阶段（直播间要用的部分）2026-10-01 随 A07.1 做完。登记表 `next`：直播间以外页面的颜色和文字角色收尾。
- 现象：用户在设置 → 外观 → 精细化字号里把“标题大”“正文”等调大后，设置类页面的标题（固定 20 号）、多画面的格子和选房、设置里的人数口径页、版本历史、关于页的名字、设备同步的配对码等不跟着变；同一种字在不同页面一个 600、一个 700、一个 500。开发者改圆角、动画时长时没有常量可用，只能抄数字。
- 为什么现在做：第二档；A05.1（对比度、字号）和 A04.1（字号上限）都要先有统一的角色。规范第 8.2 节“字重只用 400 和 600”、第 8.3 节的圆角表、第 8.6 节的三档时长现在只在文档里。
- 已经做过的：A07.1（`OnVideoColors`、`LiveSemanticColors`、`InkOnColor`、`tabular`/`regular`/`emphasis`）；A11.2（品牌蓝 `#2E6FE0` 和 fidelity、纯黑）；A02.1、A02.2（组件主题：列表行、对话框、提示条、芯片、底部面板）；A03.2（`AppMotion`：弹簧和阈值，不含时长）。门禁 `tools/gate/check_ui_structure.py` 已让 `features/`、`tv/` 的直接写的颜色和图标降到 0。

## 目标和验收

1. `live_ui` 有圆角和动效时长的常量（照 [specs/UI.md](../../../specs/UI.md) 8.3、8.6），从 `live_ui.dart` 导出；`live_ui` 自己的组件改用它们。
2. 直播间（`features/live_play/`）和电视（`tv/`）以外，页面和 `live_ui` 不再写死字号：每处字号来自主题的五个角色（`textTheme` 或 `context.textStyles`），默认设置下看起来和现在一样（像素级不变），调字号设置时跟着变。
3. 同样范围内字重只有 400 和 600（`FontWeight.w500`、`w700`、`bold`、`w800` 都改掉）。
4. `shared/danmaku/danmaku_color_dialog.dart` 的十个弹幕预设色移进 `live_ui`（例如 `LivePalettes.danmaku`），应用里不再写 `Color(0x…)`。
5. 有一个测试锁住第 2、3 条（例如扫 `apps/pure_live/lib` 除 `live_play`、`tv` 外的源码，`fontSize: <数字>` 和 `FontWeight.w500/w700/bold` 为 0），或者把检查加进门禁脚本（二选一，记录里写明）。
6. 门禁通过；`live_ui`、`apps/pure_live` 全部测试通过。

## 现状（读代码得出，写文件:行）

- 主题：`packages/live_ui/lib/src/theme/live_theme.dart:221-242`（`_textTheme`，五个字号派生全部样式）、`:244-380`（组件主题）；`text_styles.dart:19`（`AppTextStyles`）；`live_colors.dart`（角色）。
- 写死的字号（直播间、电视以外）：
  - `apps/pure_live/lib/app/desktop/title_bar.dart:53`（13）、`:96`（12）
  - `features/about/about_page.dart:114`（20）
  - `features/multiview/multiview_page.dart:731`（12）、`:759`（13）；`widgets/cell_controls.dart:218`（12）、`:227`（15）、`:236`（12）、`:443`（13）；`widgets/cell_view.dart:346`（13）；`widgets/room_picker.dart:97`（15）、`:107`（12）、`:189`（14）、`:303`（14）、`:309`（12）、`:323`（12）、`:359`（12）；`widgets/toolbar.dart:41`（14）
  - `features/remote_receiver/remote_receiver_page.dart:493`（28，配对码）
  - `features/settings/appearance_pages.dart:745`（12）、`audience_pages.dart:145`（12）、`:159`（15）、`:247`（15）、`:250`（12）、`data_tools.dart:495`（13）、`:544`（22）、`playback_tiles.dart:391`（12）、`:411`（12）、`settings_dialogs.dart:255`（13）、`settings_editors.dart:645`（13）、`:702`（12）
  - `features/version/release_history_view.dart:336`（17）、`:397`（17）
  - `shared/danmaku/setting_rows.dart:26`（13）、`:39`（13）、`:71`（15）（`danmaku_templates.dart:43-46` 的 `fontSize` 是弹幕模板的数据，不算）
  - `packages/live_ui/lib/src/widgets/`：`adaptive_panel.dart:132`（17，面板标题）、`app_chip.dart:30,49`（14）、`app_dialog.dart:377`（15）、`:390`（14）、`color_picker.dart:335`（14）、`json_tree.dart:151`（14）、`live_room_card.dart:533`（12）、`page_title.dart:38`（17）、`qr_code_widget.dart:137`（14）、`:138`（15）、`settings_page_frame.dart:22`（20，设置类页面标题）、`settings_row.dart:1137,1140`（15）、`stream_menu_button.dart:187`（14）、`:188`（12）、`:255`（13）、`tab_label.dart:43`（13）、`:55`（11）、`:107,108`（14）；画面上的 `video_state_view.dart:117`（15）、`record_glyph.dart:362`（12）、`pip_danmaku_preview.dart:193`（14）
- 字重超出 400 / 600（直播间、电视以外）：`shared/rooms/room_tags_dialog.dart:274`（w500）、`:429`（w500）；`features/multiview/widgets/toolbar.dart:41`（w500）、`cell_controls.dart:218`（w700）、`:443`（w500）、`cell_view.dart:192`（w700）、`:232`（w700）、`:280`（w500）；`features/version/markdown_text.dart:126,241,294`（bold，Markdown 的粗体）、`update_download.dart:481`（w700）；`features/areas/area_card.dart:136`（w500）；`features/backup/log_page.dart:276`（w700）。
- 圆角和时长：`BorderRadius.circular(n)` 178 处，18 种数（12 有 42 处、16 有 32、8 有 21、6 有 17……）；`Duration(milliseconds: …)` 应用 62 处、`live_ui` 19 处（200 有 12 处、150 有 11 处、500 有 7 处，其中有的是计时器不是动画）。没有常量文件；`motion.dart` 只有弹簧和阈值。
- 应用里的颜色：`apps/pure_live/lib/shared/danmaku/danmaku_color_dialog.dart:8-19`（`danmakuColorSwatches`）；`shared/danmaku/danmaku_overlay.dart:727`（弹幕描边黑，按透明度算，属于弹幕渲染，可以保留并加注释说明）。门禁不扫 `shared/`（`tools/gate/check_ui_structure.py` 的 `scan` 只看 `features/**`、`tv/**`）。

## 3.x 基线

- `lib/common/style/theme.dart:57-87`：五个字号设置派生文字主题；`:89-185` 组件主题（卡片 16、按钮 12、文字按钮 8、列表行 12、输入框 12、底部面板 24、对话框 24）。
- `lib/common/style/app_text_styles.dart`：页面用 `AppTextStyles.t13` 等（3.x 的 `modules/` 和 `common/` 里 278 处），也有写死的 `fontSize: <数字>` 52 处——3.x 本来就不全跟设置，这次是修问题（P1），不是还原。
- `lib/common/services/settings/font_settings_controller.dart:19-33`：五个字号的默认值和范围；键名不变（D-018）。
- 要保留：默认设置下每处字的大小、粗细、颜色和现在一样（用户确认过的各页设计），只是改成跟设置走。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节分阶段、第 8 节合并审查、第 14 节规则）。
2. `docs/specs/ENGINEERING.md`；`docs/specs/UI.md` 第 8 节、第 10 节。
3. 本文件夹的 `README.md`；[子分类页](../README.md)的代码地图和已知问题；`packages/live_ui/lib/src/theme/live_theme.dart`、`text_styles.dart`、`live_colors.dart`、`motion.dart`；`tools/gate/check_ui_structure.py`。

## 范围

- 可以改：`packages/live_ui/lib/`（新常量文件、组件里的字号和圆角）、`packages/live_ui/test/`；上面“现状”列出的应用文件（只换字号、字重、圆角、时长、颜色的写法）；`tools/gate/check_ui_structure.py`（如果选择把检查加进门禁）；本文件夹的 `record.md`。
- 不能改：`apps/pure_live/lib/features/live_play/`（直播间的 54 处写死字号留给直播间任务，见“风险”）、`apps/pure_live/lib/tv/`（A17）；页面的布局和外观（默认设置下不能有可见变化）；主题和字号设置的键名、默认值（D-018）；版本号、`assets/version.json`、`assets/releases.json`。

## 方案和阶段

这是登记表的第 3 阶段，分三步提交，每步能单独合并：

| 步 | 做什么 | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 3a | 常量：在 `packages/live_ui/lib/src/theme/` 加圆角（卡片 16、按钮 12、列表行 12、输入框 12、对话框 24、小菜单 8、面板顶角 16、芯片 8）和时长（快 150、常规 200、慢 300、退出用快的一档）常量（命名由执行者定，例如 `AppRadii`、`AppDurations`）；`live_ui` 的组件和 `live_theme.dart` 改用它们；弹幕预设色移进 `LivePalettes` | `live_ui/lib/src/theme/*`、`live_ui/lib/src/widgets/*`、`live_ui.dart`、`shared/danmaku/danmaku_color_dialog.dart` | `live_ui` 测试全过；数值和改之前相同（测试断言几个关键组件的圆角） |
| 3b | 字号：每处写死的字号换成主题角色。规则：等于某个角色默认值的（12、13、14、15、20）直接用那个角色；其他（11、17、22、28）用最近的角色按比例算（例如 17 = `titleMedium` × 17 / 15），保证默认设置下大小不变 | “现状”列的应用文件和 `live_ui` 组件（画面上的三处见“风险”） | 默认设置下的布局测试不变；新测试：把五个字号都调到最大时这些地方变大 |
| 3c | 字重：w500 → 400 或 600（按设计图：强调的 600，其余 400）；w700、bold → 600；Markdown 粗体也用 600。加一个扫描测试（或门禁检查）锁住 2、3 条 | “现状”列的文件；新测试或 `check_ui_structure.py` | 扫描为 0；门禁通过 |

## 测试

- 3a：`packages/live_ui/test/` 加一条：对话框圆角 24、小菜单 8、面板顶角 16、芯片 8 等取自常量且数值不变。
- 3b：至少三处页面级测试（设置类页面标题、多画面选房、版本历史）：默认字号下文字大小和改之前相同；`LiveFontSizes` 全调到最大时变大。
- 3c：扫描测试（读 `apps/pure_live/lib` 的 `.dart` 源码，跳过 `features/live_play/`、`tv/` 和注释，断言没有 `fontSize: <数字>`、`FontWeight.w500`、`w700`、`bold`），或门禁里同样的检查。
- 竖屏、横屏、宽屏各跑一个受影响页面的布局测试，确认没有溢出。测试里的定时器至少 1 秒；不访问真实平台。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 默认字号下打开设置 → 视频、关于、版本历史、多画面、设备同步配对码 | 和改之前看起来一样 |
| 2. 设置 → 外观 → 精细化字号：五个都调到最大，回到第 1 步的页面 | 标题、说明、按钮文字都变大，不截断 |
| 3. 浅色、深色、纯黑各看一遍设置页和多画面 | 颜色和改之前一样 |
| 4. Windows 上（微软雅黑）看设置页、版本历史 | 没有“发虚的半粗体”（500 已经去掉） |

## 风险和注意

- 画面上的文字（`video_state_view.dart:117`、`record_glyph.dart:362`、`pip_danmaku_preview.dart:193`）和直播间的 54 处：规范第 8.2 节只说“画面上控制层的文字随系统放大最多 1.3 倍”，没说跟不跟五个字号设置；3.x 的控制层 `lib/modules/live_play/widgets/video_player/video_controller_panel.dart` 写死 6 处、用主题 16 处。这次不动，写进记录交给直播间任务决定。
- 按比例换算会出小数字号（17 = 15 × 1.133），默认设置下仍是 17；不要四舍五入到整数，否则默认外观变。
- `live_theme.dart` 和组件文件是多个任务常改的（A02、A03、A04.1），开工前合并最新 master，按文件分批提交。
- A04.1（暂停）也会改 `settings_page_frame.dart` 和几个设置页面：同一组同时只开一个开发，A01.2 和 A04.1 不要并行。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 分支 `ai/A01.2` 或本机工作区；提交信息以 `[A01.2]` 开头（英文）；不推 master。
- 提交前：`packages/live_ui` 和 `apps/pure_live` 跑 `dart format --output=none --set-exit-if-changed .`、`flutter analyze`、`flutter test`；根目录 `python3 tools/gate/check_ui_structure.py`、`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”（3a / 3b / 3c 做到哪个文件）、更新登记表的 `done`、`next`、`branch`。

## 报告（中文，简洁）

每条验收做到没有；新常量的名字和数值；换掉的字号和字重各多少处、按比例换算的有哪几处；测试数量；改了哪些文件；直播间和画面上留下的数量；要在真机上看的；需要维护者决定的（例如门禁要不要扫 `shared/`）；可能冲突的文件。
