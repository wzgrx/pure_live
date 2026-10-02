# T14g.1 尺寸和字号适配：高度分档、分屏、折叠屏、字号上限、触控区域

- 规模：中；分组：组件；依赖：T01c.1；能否和别的任务同时做：组件组最后一个（会改很多页面）
- 出设计：不用（照调研报告和本任务单；改变手感的地方在记录里写清前后对比）
- 先读：调研报告 `docs/T14/research-2026-10-02.md` 第 3 节（D1、D3、D4）；`docs/specs/UI.md` 第 5 节（尺寸分档）
- 可以改：`packages/live_ui`、c1 列出的文件、`app/app.dart`、主要页面（只为触控区域）；其他目录不改。

## 要做的

- c1 D1：`packages/live_ui/lib/src/theme/grid_columns.dart` 加高度分档（紧凑 <480、中等、展开），按约束（`LayoutBuilder`）判断；替换这些文件里的 `MediaQuery.sizeOf(context).height < 480`：`tags_page.dart`、`version_page.dart`、`shield_page.dart`、`settings_tiles.dart`、`release_history_view.dart`、`about_page.dart`、`settings_page.dart`、`toolbox_page.dart`、`live_ui` 的 `settings_page_frame.dart`（以搜索结果为准）。竖屏分屏（约 400×420，紧凑/紧凑）不当成横屏手机；折叠屏读 `MediaQuery.displayFeatures`，铰链不压内容。
- c2 D3：在应用根（`app/app.dart:247-252`）给总体文字缩放加上限 2.0（系统字号 × 应用字号），画面控制层的 1.3 保留。
- c3 D4：主要页面加触控区域检查（`meetsGuideline(androidTapTargetGuideline)`），不达标的扩到 48 dp。

## 验收

- 报告 3.3 节 D1 列出的尺寸 × 字号组合都不溢出；字号叠加不超过 2 倍；主要页面触控区域达标。
- 测试：布局测试覆盖 360×400、400×420、400×869、821×400、673×841、841×673、1280×800、1500×1000，每个尺寸配 1.3/1.5/2.0 倍字号；触控区域检查。

## 真机上看的（写进记录，维护者在 K90 上看）

- `adb shell wm size 720x1600` 和 `adb shell wm density 320`、`540` 模拟其他机型，主要页面看一遍，测完 `wm size reset`、`wm density reset`。
- 系统字体调到最大 + 应用字号 2 倍：所有页面不截断。
- 分屏打开应用：竖屏布局正常，不出现横屏手机布局。

