# A01.5 液体玻璃：首页底栏可选的悬浮毛玻璃（设置开关，默认关）

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：界面
- 来源：用户 2026-10-14：“增加液体玻璃设计（增加开关，可以关闭打开）”；用户给的 Compose / Liquid Glass 资料评估结论：留在 Flutter，液体玻璃只做成开关
- 相关：[UI.md](../../../specs/UI.md) 第 9.3 节（性能约束，这里是唯一的例外）；首页布局 [A06](../../A06-首页和全局/README.md)；设置项在 设置 → 外观
- 任务书：[brief.md](brief.md)；记录：[record.md](record.md)；真机：[verify.md](verify.md)

## 用户看得到的

- 设置 → 外观 → “液体玻璃”，默认关；关着时首页和以前完全一样。
- 打开后（手机宽度，首页有 2 个以上入口时）：首页底栏变成离左右和底部各 12 的胶囊（高 68、圆角 34），半透明、把后面的页面模糊掉，上沿和左上有一道高光、右下有一道弱反光，下面一层浅阴影；页面一直延伸到屏幕底，滚到底时最后一行停在胶囊上面。
- 内存 4 GB 及以下（或读不到）的安卓机：同样的胶囊，但不模糊，只是更不透明的底色（模糊每帧都要重画后面的内容，低端机滚动会掉帧）。
- 宽屏侧栏、直播间、视频上方都不用玻璃（UI.md §9.3：视频上方不模糊）。

## 代码

| 文件 | 内容 |
|---|---|
| `packages/live_ui/lib/src/widgets/glass.dart` | `GlassSurface`（`BackdropFilter` 模糊 24 + 上浅下深的 `surfaceContainer` 半透明渐变 + `_GlassRimPainter` 高光边 + 浅阴影；`blur: false` 不模糊）、`GlassMetrics`（模糊 24、胶囊高 68、圆角 34、边距 12、遮住的高度 80）、`GlassBarInset` 和 `EdgeInsets.withGlassBar` |
| `apps/pure_live/lib/features/home/home_views.dart` | `HomeMobileView(glass:, glassBlur:)`：开着时 `Scaffold(extendBody: true)`，底栏是 `GlassSurface` 里透明背景的 `NavigationBar`（高 68），页面外面套 `GlassBarInset(安全区 + 80)` |
| `apps/pure_live/lib/features/home/home_page.dart` | 读 `Settings.liquidGlass`，`liquidGlassBlurs` 决定模糊不模糊 |
| `apps/pure_live/lib/app/bootstrap.dart` | `deviceMemoryBytes`（启动时读一次 `/proc/meminfo`）、`liquidGlassBlurs` |
| `room_grid.dart`、`favorite_page.dart`、`area_card.dart`、`recorder_page.dart` | 首页四个入口的列表底部加上 `GlassBarInset`（没有玻璃底栏时是 0，不变） |
| `packages/live_store/lib/src/settings/settings.dart` | `liquidGlass`（theme 分节，默认 false） |
| `apps/pure_live/lib/features/settings/settings_catalog.dart` | 外观里的开关，图标 `AppIcons.liquidGlass`（水滴） |

小窗避开底栏的距离（`inAppMiniBottomClearance` 的 80）不用改：胶囊 68 + 边距 12 正好 80。

## 不做的

- 真正的折射（透过玻璃的画面弯曲）要片段着色器读背景，Flutter 现在只在 Impeller 上支持、代价更大，先不做。
- 顶部栏、弹窗、面板不加玻璃：顶部栏下面滚动的内容少，看不出效果；面板在视频上方。
