# U.5c 观看记录

- 日期：2026-10-01
- 设计：[docs/ui/compare/U.5c/README.md](../compare/U.5c/README.md)（用户已确认；Z1～Z3 按 A）；卡片见 [U.4a 记录](U.4a.md)
- 改动的目录：`apps/pure_live/lib/features/history/`（`history_page.dart`、`history_limit_dialog.dart`）、`packages/live_ui`（`AppIcons`、`PageTitle`，见 [U.5a 记录](U.5a.md)）、翻译文件。没有改原生部分

## 逐条对照

| 编号 | 内容 | 做到 | 说明 |
|---|---|---|---|
| c1 | 顶栏两个按钮、下拉刷新、卡片删除按钮（先确认）、点卡片进房、长按菜单、三个对话框、最新在前、间距跟设置 | ✅ | 齿轮、垃圾桶（有记录时才有）照 v3 的图标和提示；卡片换成 U.4a 的 `LiveRoomCard`（`showDelete`，删除按钮在封面右上）；三个对话框文字和按钮照 v3。保留数量对话框恢复 v3 的整宽“应用”按钮（v4 之前改成了输入框里的 ✓） |
| c2 | 改叫“观看记录”，数量放第二行“18 / 50 条” | ✅ | live_ui `PageTitle`，靠左；不限时写“18 条 / 不限”（设计图没画这种，新文字） |
| c3 | 按今天、昨天、近 7 天、更早分组 | ✅ | v4 已有；组名主色 13 号半粗，后面是条数 |
| c4 | 顶栏“刷新”、进度线、结果提示 | ✅ | 悬停提示“刷新开播状态”；顶栏下 2 像素进度线；下拉照旧 |
| c5 | 顶栏“筛选”；筛选时清空只删筛出来的 | ✅ | 筛选框照设计：主色 2 像素边框、圆角 22、右边条数；按钮在筛选打开时换成“关闭筛选”图标。返回键和 Esc 先关筛选 |
| c6 | 改小数量时提醒删几条；直接确认也算数 | ✅ | v4 已有 |
| c7 | 空状态加说明 | ✅ | “无观看历史记录 / 看过的直播间会按观看时间出现在这里”，没有清空按钮，刷新不可点 |
| c8 | 列数按计划书 5.3 节 | ✅ | `RoomGridGeometry`：393 → 2、852×393 → 4、1280 → 6（测试固定）；组名和卡片的边距 12 / 6 |

选择：Z1 A ✅；Z2 A ✅（顺序：筛选、刷新、保留数量、清空）；Z3 A ✅。

另外：观看记录混有多个平台时，卡片设置为“自动”会在封面左上显示平台（U.4a c2，`mixedPlatforms`）；长按菜单里“从观看记录删除”的图标改用卡片删除按钮同一个（`AppIcons.delete`，一个动作一个图标）。

## v3 文件 → v4 文件

| v3 | v4 |
|---|---|
| `modules/history/history_page.dart`（页面） | `features/history/history_page.dart` |
| `history_page.dart` 的 `_HistoryLimitDialog` | `features/history/history_limit_dialog.dart` |
| `history_page.dart` 的刷新 | `features/history/history_refresh.dart`（没改） |
| （v4 新增）分组、筛选 | `features/history/history_sections.dart`（没改） |

## 新设置项

无。保留数量照旧读写 3.x 的 `historyLimit`。

## 门禁

`history` 直接写的颜色和图标 11 → 0，`ui_baseline.json` 去掉这一项。没有跨功能引用。

## 测试

`test/features/history/history_page_test.dart` 17 个（原 9 个）。新增：标题“观看记录”和第二行条数靠左、四个按钮的顺序、图标和提示、卡片带删除按钮并标平台；393×852、852×393、1280×800 的列数和边距；Esc 和返回键先关筛选；附录 A 第 14 条（右键 = 长按，菜单里有“从观看记录删除”）；空页面的说明、没有清空、刷新不可点；保留数量对话框整宽的“应用”按钮（和输入框同宽、高 48，应用后当前值和芯片跟着变）。

和新设计冲突、照实改的旧测试：标题“历史记录 (4/50)”改为“观看记录”加“4 / 50 条”（不限时“22 条 / 不限”）；`RoomCard` 改为 `LiveRoomCard`。

## 没做的

- 电视的观看记录（U.15c）没动。
- 没有在真机和 profile 模式看帧时间。
