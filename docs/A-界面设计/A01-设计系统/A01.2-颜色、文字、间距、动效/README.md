# A01.2 颜色、文字、间距、动效：设计（照规范第 8 节，没有单独出图）

- 状态：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)（待真机，阶段 3/3：设计 ✓、直播间要用的部分 ✓、其余页面 ✓）
- 范围：`live_ui` 主题里的颜色角色（深浅两套、语义色、画面上的角色）、字号和字重角色、间距和圆角、动效时长；以及页面不写死这些值。
- 旧编号：U.1a、T01a.2（见 [MAPPING.md](../../../MAPPING.md)）
- 对应：[specs/UI.md](../../../specs/UI.md) 第 8.1 节（颜色）、8.2 节（文字）、8.3 节（间距、圆角、阴影）、8.6 节（动效）；[inventory/UI_FILES.md](../../../inventory/UI_FILES.md) 的 A01.2 节（3.x 文件：`main.dart`）；[inventory/V3_UI.md](../../../inventory/V3_UI.md) 第 0 节；相关决定 D-011、D-018
- 评审页：无。设计就是 [specs/UI.md](../../../specs/UI.md) 第 8 节（2026-10-01 界面重构计划书第 2 版，用户确认）；配色的两处选择（品牌蓝、纯黑）在 [A11.2](../../A11-设置界面/A11.2-外观/README.md) 的评审页里定（C-3、C-4 按 A）
- 依赖：Z02.1（搬目录，完成）；样板 [A07.1](../../A07-直播间界面/A07.1-竖屏普通布局/README.md)、[A07.6](../../A07-直播间界面/A07.6-直播间弹窗/README.md)
- 任务书：[brief.md](brief.md)（第 3 阶段“其余页面”）

## 界面清点表

没有单独的界面；是全应用共用的“角色”。按角色列，状态写现在做到哪。

| 编号 | 角色 | 用在哪 | 形态 | 状态 |
|---|---|---|---|---|
| A01.2-01 | 表面颜色角色（表面、表面容器低 / 中 / 高 / 最高、主色、主色容器、次色容器、轮廓、错误） | 全部页面、卡片、对话框、面板 | 深色、浅色、纯黑、动态取色 | 用 Material 3 `ColorScheme`；`features/`、`tv/` 已没有直接写的颜色（门禁基线 0） |
| A01.2-02 | 画面上的角色 `OnVideoColors` | 播放器控制层、状态、手势卡片、小窗、多画面 | 所有主题下黑底白字 | 完成（A07.1 起，`live_colors.dart:9`） |
| A01.2-03 | 固定语义色 `LiveSemanticColors` | “直播”标、录制、成功、警告、提醒横幅、醒目留言 | 深浅各一套 | 完成（`live_colors.dart:160`） |
| A01.2-04 | 平台给的颜色上的字 `InkOnColor` | 醒目留言卡、观众的弹幕颜色 | — | 完成（`live_colors.dart:258`，按 WCAG 对比度选） |
| A01.2-05 | 品牌蓝、纯黑 | 默认主题色、深色的纯黑 | — | 完成（A11.2：`LiveTheme.brandBlue`、`LivePureBlack`） |
| A01.2-06 | 五个字号角色（12、13、14、15、20） | 全部文字 | 用户可调 | 直播间、电视以外完成（第 3 阶段 2026-10-08）：页面、`shared/`、应用外壳和 `live_ui` 组件没有写死的字号，设置行的标题、说明、值也跟五个字号走；其他字号按最近的角色成比例（17 = 卡片标题 × 17/15 等）。直播间 54 处、画面上的 3 个组件、电视、桌面标题栏留着（见[记录](record.md)） |
| A01.2-07 | 字重只用 400 和 600、等宽数字 | 全部文字；人数、码率、时长、时钟 | — | 完成（第 3 阶段）：主题的 `titleMedium`、`titleSmall`、`labelLarge` 和文字按钮从 500 改成 600；`AppTextStyles` 的 `*Medium`、`*Bold` 删掉；页面和组件里的 500 / 700 / bold 改成 400 或 600；门禁第 5 条锁住（直播间、电视以外） |
| A01.2-08 | 间距（4 的倍数）、圆角（卡片 16、按钮 12、列表行 12、输入框 12、对话框 24、小菜单 8、面板顶角 16） | 全部 | — | 圆角常量 `AppRadii`（`packages/live_ui/lib/src/theme/metrics.dart`），主题和 `live_ui` 组件里对得上角色的都改用它；应用页面里 `BorderRadius.circular(n)` 还有 139 处（直播间另有 56 处）没换；间距没有做常量 |
| A01.2-09 | 动效时长（即时反馈 100–150、常规 150–250、页面和面板 250–350 毫秒，退出比进入快） | 全部动画 | 跟随系统“减少动态效果” | 时长常量 `AppDurations`（`instant` 100、`fast` 150、`normal` 200、`slow` 300），`live_ui` 组件的动画改用它；应用里 `Duration(milliseconds: …)` 还有 36 处（直播间另有 23 处，含计时器）没换；弹簧和阈值在 A03.2 的 `AppMotion` |

## 3.x 的样子和问题

- 样子（`lib/common/style/theme.dart`，见[子分类页](../README.md)的 3.x 基线）：Material 3，用户主题色作种子（默认 `Colors.blue`），可选动态取色；深色错误色 `#FF6347`（`:97`）；字号来自五个设置（`font_settings_controller.dart:19-33`）；去水波；标签栏、卡片 16、按钮 12 / 8、列表行 12、输入框 12、底部面板 24、对话框 24（`theme.dart:113-184`）；页面切换 `FadeForwards`（`:4-13`）。
- 问题：
  - P1 `AppTextStyles` 是全局 getter（`app_text_styles.dart:7-10` 读 `Get.theme`），页面里直接拼 `t12/t13/t14…`，和主题字号两套并存，同一角色在不同页面字号不一（[inventory/V3_UI.md](../../../inventory/V3_UI.md) 第 0 节问题 1）。
  - P2 卡片、弹幕行等处硬编码 `Colors.white`/`Colors.grey[900]`，换主题色或深色时层次不一致（`lib/common/widgets/room_card.dart:1073`、`lib/modules/live_play/widgets/danmaku/danmaku_list_view.dart:468-474`，同上问题 2；那一节写的 `:1071`、`:470` 差两行）。
  - P3 默认蓝 `Colors.blue` 上白字对比只有 3.1:1（候选 C-3）。
  - P4 主题的标题栏设置没生效（`main.dart:162-169`，D-011）。
  - P5 没有间距、圆角、时长的统一取值，各页面写数字。

## 各版的经过

| 版 | 内容 | 用户意见 |
|---|---|---|
| 规范第 8 节（2026-10-01） | 颜色角色、五个字号角色、字重 400/600、等宽数字、间距 4 的倍数、圆角表、动效三档时长 | 随界面重构计划书确认 |
| A11.2 第 1 版（2026-10-01） | C-3 品牌蓝 `#2E6FE0`、C-4 纯黑、C-7 文字大小 | C-3、C-4 按 A；C-7 定为“文字大小”为主、五个字号留在子页 |

## 对比页（按章节导出）

无（没有本任务自己的评审页；配色的对比在 [A11.2 的对比页](../../A11-设置界面/A11.2-外观/README.md)）。

## 单张图

无。

## 确认的改动

| 编号 | 类型 | 内容 | 对应问题 |
|---|---|---|---|
| c1 | 修改 | 用角色不用色值：页面只用 `ColorScheme` 角色、`OnVideoColors`、`LiveSemanticColors`；门禁禁止 `features/`、`tv/` 直接写颜色 | P2 |
| c2 | 增强 | 画面区域（播放器、全屏、多画面、画中画、小窗）在所有主题下黑底白字，控件单独一组角色：前景白、阴影、60% 黑渐变 | — |
| c3 | 保留 | 语义色固定、不随主题变：直播红 `#D92D20` 配白字（必须带“直播”二字）、录制红、成功绿、警告黄 | — |
| c4 | 修改 | 默认品牌蓝 `#2E6FE0`（fidelity，白字 4.7:1），3.x 默认蓝的用户迁移；纯黑主题默认关（A11.2 C-3、C-4） | P3 |
| c5 | 保留 | 五个字号角色对应 3.x 的五个字号设置，用户调整照旧生效；系统字体放大照常生效 | — |
| c6 | 修改 | 文字样式从 `Theme.of` 读（`context.textStyles`），跟着局部主题 | P1 |
| c7 | 修改 | 主次分明：同一处主信息和次信息至少差一档字号或字重；字重只用 400 和 600（微软雅黑没有 500）；最小 12；中文行高不低于 1.4 倍 | — |
| c8 | 增强 | 人数、码率、时长、时钟、倒计时用等宽数字（`tabular`）；人数写“1.2万”，不做滚动动画 | — |
| c9 | 修改 | 间距按 4 的倍数；圆角沿用 3.x：房间卡片跟随“卡片设置”（默认 20）、其他卡片 16、按钮 12、列表行 12、输入框 12、对话框 24、小菜单 8、面板顶角 16；阴影只用于浮层 | P5 |
| c10 | 修改 | 动效时长三档（100–150、150–250、250–350 毫秒），退出比进入快，减速曲线不回弹，页面切换沿用 `FadeForwards`，跟随系统“减少动态效果” | P5 |
| c11 | 保留 | 标题对齐照 3.x 实际运行的样子（D-011） | P4 |

## 按钮的作用和用法

无（没有可点的控件；设置主题、字号的界面在 A11.2）。

## 各客户端

| 客户端 | 怎么做 |
|---|---|
| Android 手机 | 同一套角色；动态取色在 Android 12+ |
| 宽屏（平板、Windows、Linux、iPad、macOS） | 同一套角色；Windows 默认字体微软雅黑（字重 400/600 的原因）；Windows 也有动态取色 |
| 电视 | 只有深色，用手机的深色角色加 `TvColors`（A17.1）；字号比手机大一级（[specs/UI.md](../../../specs/UI.md) 第 5.5 节） |
| 苹果平台差异 | 无（同宽屏）；字体跟系统 |

## 待选和决定

- C-3、C-4：按 A（A11.2，D-003）。
- C-7（五个字号合并成一个“文字大小”）：A11.2 定为“文字大小”为主、五个字号保留在子页。
- 间距、圆角、时长做成常量的命名和放在哪个文件：第 3 阶段定为 `packages/live_ui/lib/src/theme/metrics.dart` 的 `AppRadii`（`card`、`button`、`textButton`、`listRow`、`input`、`dialog`、`menu`、`chip`、`panelTop`、`panelSide`，都是 `BorderRadius` 常量）和 `AppDurations`（`instant`、`fast`、`normal`、`slow`），从 `live_ui.dart` 导出。间距没有做常量（规范只说“4 的倍数”，各处的数本来就是 4 的倍数）。
- 主题里的 500 字重：按 D-003 取建议（2026-10-08，第 3 阶段）：主题的 `titleMedium`、`titleSmall`、`labelLarge` 和文字按钮改成 600，`AppTextStyles` 的 `*Medium`、`*Bold` 删掉，页面用到的 11 处按位置改成 400（次要信息、标签）或 600（标题、按钮、强调）。看得见的变化：用 `t15`/`t16`、`titleMedium`、`titleSmall` 又没另设字重的字（各页的小标题等）和按钮字从 500 变 600；下拉刷新头的字、房间卡片的主播名、分区卡片的说明、多画面音量数字、历史记录“自定义”从 500 变 400。用户不满意可以推翻（改回只需改主题的三行）。

## 实现和验证（开发后补）

- 第 1 阶段“设计”：即规范第 8 节和 A11.2 的选择，没有单独的文件。
- 第 2 阶段“直播间要用的部分”（2026-10-01，随 A07.1 一起做，[A07.1 记录](../../A07-直播间界面/A07.1-竖屏普通布局/record.md)“A：设计系统里直播间要用的部分”）：`packages/live_ui/lib/src/theme/live_colors.dart` 的 `OnVideoColors`（画面上的前景白、次要白、60% 黑渐变、阴影、黄色“非默认”）、`LiveSemanticColors`（直播红 `#D92D20` 配白字、录制红、成功、警告，取归档 v4 已验算对比度的固定值）、`InkOnColor`（平台给的颜色上用深字还是浅字）、`tabular`/`regular`/`emphasis`（等宽数字、字重只用 400/600）；`ListenableSelector`（人数、时长、标题各自刷新）。测试 `packages/live_ui/test/design_system_test.dart` 的颜色角色一条。之后各任务往这两个类里加了角色（A07.7、A08.1、A10.3、A13.1、A16.1 等，见 `live_colors.dart` 的注释）。
- 品牌蓝和纯黑（2026-10-01，A11.2）：`LiveTheme.brandBlue`（`live_theme.dart:177`）、`schemeVariant: fidelity`、`LivePureBlack`（`live_colors.dart:314`）；测试 `settings_row_test.dart` 的 theme 组。
- 第 3 阶段“其余页面”（2026-10-08，[记录](record.md)）：圆角和时长常量；直播间、电视以外的字号全部来自五个角色（设置行、设置类页面标题、多画面、版本历史、关于、设备同步配对码、面板标题、标签页、提示条、二维码卡片……）；字重只留 400、600（含主题那一层）；弹幕预设色和弹幕描边移进 `LivePalettes`；门禁第 5 条锁住字号和字重，第 2 条扫到 `shared/`。开工前（2026-10-03）的数字：写死字号应用 94 处（直播间 54 处）、`live_ui` 24 处，按条件写死的 9 处；字重 w500/w700/bold 应用 16 处（不含电视；直播间 2 处）、`live_ui` 组件 4 处，主题的三个 w500 角色和 `AppTextStyles` 的 `*Medium`/`*Bold`（页面 11 处）另算；`BorderRadius.circular(n)` 178 处 18 种数；`Duration(milliseconds: …)` 应用 62 处、`live_ui` 19 处；`shared/danmaku/danmaku_color_dialog.dart:9-18` 十个弹幕预设色写在应用里。
- 验证：`packages/live_ui/test/metrics_test.dart`（主题的圆角取自常量且数值不变、时长、字重只有 400/600、设置类页面标题 / 标题栏标题 / 面板标题 / 设置行在默认字号下大小不变而五个字号调到最大时按比例变大、电视行仍大一级）、`theme_test.dart`；`apps/pure_live/test/features/version/version_page_test.dart`、`features/multiview/multiview_page_test.dart` 的 “A01.2” 两条（版本历史、关于、多画面选房在默认和最大字号下，竖屏、横屏、宽屏不溢出）；门禁 `python3 tools/gate/check_ui_structure.py` 第 5 条。真机照[任务书](brief.md)“真机验证”看。
