# A09.1 房间卡片

- 日期：2026-10-01
- 设计：[docs/A-界面设计/A09-浏览界面/A09.1-房间卡片/README.md](README.md)（用户已确认；A1～A4 按 A）；计划书 [specs/UI.md](../../../specs/UI.md) 第 3、5、7、8、9 节
- 协调员补充（开工后）：分区卡片的长按也用这个对话框组件（A09.4 X3 改动）；取消关注确认按钮写“取消关注”（A02.2 D2）；状态页第一个按钮浅色实心、第二个文字按钮（A02.1 C1）；开关用 live_ui 的，不自己改样式
- 改动的目录：`packages/live_ui`（新增组件；两处只加可选字段，见下）、`apps/pure_live/lib/shared/rooms/`、翻译文件。没有改原生部分，没有构建 APK，没有往手机安装

## 新组件（放在哪）

| 组件 | 文件 | 说明 |
|---|---|---|
| `LiveRoomCard`、`RoomCardSkeleton`、`CoverChip`、`RoomRow`、`LiveRoomCardMetrics` | `packages/live_ui/lib/src/widgets/live_room_card.dart` | 新卡片。旧的 `RoomCard` 原样保留：搜索、历史、设置里的卡片预览、电视还在用它（属于 I、J、X），换过去后可删 |
| `CardDialog`、`CardDialogAction` | `packages/live_ui/lib/src/widgets/card_dialog.dart` | 卡片长按对话框（房间卡片、分区卡片共用） |
| `FollowPill` | `packages/live_ui/lib/src/widgets/follow_pill.dart` | 和 A07.1 顶栏同样子的“＋ 关注 / ✓ 已关注”；`live_play` 自己的按钮没改（别的任务目录），以后可换成它 |
| `showAdaptivePanel`、`PanelHeader` | `packages/live_ui/lib/src/widgets/adaptive_panel.dart` | 没有画面的页面的面板：竖屏底部、宽屏右侧 360（A09.2 全部平台用） |
| `GridColumns`、`WindowWidthClass` | `packages/live_ui/lib/src/theme/grid_columns.dart` | 计划书 5.3 的列数公式（房间卡片 160/180/200、2–8 列；分区卡片 110/130/150、3–10 列） |
| `RoomGridCard`、`RoomGridGeometry`、`RoomGridSkeleton`、`JumpButtons`、`NoticeBar`、`MobileDataBanner`、`RoomFeedView` | `apps/pure_live/lib/shared/rooms/room_grid.dart` | 应用侧：卡片接上设置和点按、网格几何、骨架、回到顶部/底部、整页（热门、分区房间共用） |
| `PaginationBar`、`pageSizesOf`、`usesDesktopPages`、`phonePageSize` | `apps/pure_live/lib/shared/rooms/paging.dart` | 从 `features/popular/pagination_bar.dart` 挪来（热门、关注、分区、分区房间都用） |
| `showRoomMenu`、`confirmUnfollowRoom` | `apps/pure_live/lib/shared/rooms/room_menu.dart` | 长按对话框、关注和取消关注 |
| `RoomTagPicker` | `apps/pure_live/lib/shared/rooms/room_tags_dialog.dart`（新） | 设置房间标签 / 分类（不再借用 `features/tags` 的编辑框，去掉了 shared → feature 的引用） |

live_ui 里两处改动不是纯新增，但不改已有行为：`RoomCardData` 加可选字段 `platformName`、`isOffline`；`LiveUiStrings` 加可选字段 `offline`（默认“未开播”）。`AppStatusView` 的按钮按协调员要求由文字按钮改为浅色实心（全应用的状态页都跟着变），并新增可选的第二个文字按钮。

## 逐条对照

| 编号 | 内容 | 做到 | 说明 |
|---|---|---|---|
| c1 | 卡片结构、角标位置、点按 / 长按 / 右键、卡片设置三个预设和各显示项、圆角默认 20、紧凑信息行、历史删除、核验标 | ✅ | 紧凑信息行照 v3（宽 260 / 300 / 360 起才显示人数）；删除按钮照 v3 黑底圆形 |
| c2 | 平台标“图标 + 中文名”放封面左上；“自动”= 列表混有多个平台时显示 | ✅ | `LiveRoomCard.mixedPlatforms` 由页面给；“始终显示”“隐藏”照旧。关注页“全部”传 true（A09.3 c10）；热门、分区房间是单平台不传 |
| c3 | 颜色角色；录播标两种主题都用主色 | ✅ | 浅色 `surfaceContainerLowest`（白）、深色 `surfaceContainer`；标题 `onSurface`、主播名 `onSurfaceVariant` |
| c4 | 未开播：封面压暗 + “未开播” | ✅ | 平台说未开播、封禁、轮播时（`isExplicitlyOfflineNow`）；状态未知不标。压暗是一层半透明色块 |
| c5 | 封面加载中和失败同一个占位（直播图标） | ✅ | 没有地址也是同一个 |
| c6 | 角标 12 号，人数等宽数字 | ✅ | `CoverChip`：高 22、黑 55% 底、12 号 600 |
| c7 | 受限标记在封面左下 | ✅ | 文字取 `roomMark`（付费、需登录、订阅专享、私密、仅限 App、地区受限、密码房、年龄限制、轮播、已封禁、平台已下线） |
| c8 | 第一次加载静态骨架，和真卡同尺寸 | ✅ | `RoomCardSkeleton`、`RoomGridSkeleton`（列数和行高同真卡，铺满可见区域，无动画） |
| c9 | 电脑悬停变浅灰并显示完整标题；键盘焦点主色描边 | ✅ | 悬停 `surfaceContainerHigh`；完整标题是鼠标悬停的提示（触屏长按仍是弹窗）；Tab 到卡片出 3 像素主色描边，回车进入 |
| c10 | 长按弹窗：平台图标、主播名、“平台 · 房间号”、完整标题、“分享”“设置标签”带文字；没关注时设置标签照常可点 | ✅ | 页面自带的动作（历史的“从观看记录删除”）放在这两个按钮下面一整行；历史的观看时间放在“平台 · 房间号”下一行（A09.9 保留的内容） |
| c11 | 关注按钮同 A07.1 顶栏；“已关注”先确认再取消；关注后关闭并提示 | ✅（有偏差） | 提示用已有的“已关注 {主播名}”（不是只写“已关注”）；取消后仍有“撤销”（v4 已有） |
| c12 | 关注、取消关注确认框同一种，主按钮写明动作 | ✅ | “先关注再设置标签 / 标签只能加在关注的直播间上。现在关注XX吗？ / 关注并设置标签”；“取消关注 / 确定要取消关注XX吗？ / 取消关注”（红） |
| c13 | 设置标签：写明直播间；原地新建；“确认”一直能用（名称栏有字先建再保存）；高度跟内容 | ✅ | 名称 15 字（栏内显示“2/15”和清除）、备注 40 字；空名、重名在栏下写原因；“添加”后表单清空可接着建；回车等于添加；保存中“确认”转圈；没有标签时直接展开表单 |
| c14 | 按对话框实际宽度排：内容宽 400 以上两列 | ✅ | 测试固定：横屏手机 852×393 两列且对话框不超出屏高 |
| c15 | 列数按公式；边距统一 6 | ✅ | 表里的列数逐个写进测试（含 600、740、852、1024、1280、1440、1920、2560） |

选择：A1 居中对话框 ✅；A2 保留头像 ✅；A3 标题一行 ✅；A4 图标 + 中文名 ✅。

## 和 v3 / 设计不一样的地方

1. 对话框里没有“打开直播间”“复制链接”和简介：v3 没有，设计也没有（v4 之前加的）。`showRoomMenu` 的 `onOpen` 参数留着（搜索、电视在传），对话框不用它。
2. 关注后的提示带主播名（已有文字），见 c11。
3. “＋ 新建标签”的虚线框用自绘虚线（Flutter 没有虚线边框）。

## v3 文件 → v4 文件

| v3 | v4 |
|---|---|
| `common/widgets/room_card.dart` 卡片 `:1053-1229`、角标 `:858-908`、`:1312-1411` | `packages/live_ui/lib/src/widgets/live_room_card.dart` |
| `room_card.dart` 长按 `:177-316`、关注确认 `:125-175`、`FollowButton` 和取消关注 `:1232-1310` | `packages/live_ui/lib/src/widgets/card_dialog.dart`、`follow_pill.dart`；`apps/pure_live/lib/shared/rooms/room_menu.dart` |
| `room_card.dart` 设置标签 `:318-856` | `apps/pure_live/lib/shared/rooms/room_tags_dialog.dart` |
| `room_card_layout.dart` | `LiveRoomCardMetrics`、`RoomGridGeometry` |
| 各页面的列数（`popular_grid_view.dart:16` 等） | `GridColumns` |

## 新设置项

无。卡片设置（三个预设、各显示项、圆角，手机和电脑分开）照旧读 3.x 的存储键。

## 门禁

- 这个任务只动 `shared/` 和 `live_ui`（门禁不计）；各页面的直接颜色和图标见 A09.2～A09.6 的记录，合计：popular 26 → 0、favorite 7 → 0、areas 21 → 0、area_rooms 12 → 0、hot_areas 3 → 0，`ui_baseline.json` 去掉了这五项。
- 跨功能引用：`area_rooms -> home/home_menu.dart` 没有了，已从基线删掉。`shared/rooms/room_menu.dart` 不再引用 `features/tags`。
- `logic/` 没有引用 material。

## 测试

- `packages/live_ui/test/live_room_card_test.dart`（14 个）：卡片各状态（直播、录播、未开播、受限、核验、占位）、平台标三种模式、角标位置和 12 号等宽、颜色角色深浅两套、点按 / 长按 / 右键（附录 A 第 14 条）、悬停和键盘焦点、紧凑信息行、骨架同尺寸无动画、`RoomRow`、`FollowPill`、列数表（房间、分区）、面板两种位置。
- `status_view_test.dart` +1：第二个按钮是文字按钮。
- `apps/pure_live/test/shared/shared_test.dart` 菜单两个测试重写、加 1 个：对话框结构和顺序（分享在左、关闭在关注左边）、Esc 关闭、关注后关闭并提示；没关注时先问再关注、原地新建（空名、重名的提示，“确认”先建再存）、点选取消、红色“取消关注”和撤销；横屏两列。
- 和新设计冲突、照实改的旧测试：`history_page_test.dart`（“房间号: 7”改为“房间号 7”，已关注时按钮写“已关注”）、`favorite_test.dart` 和 `shared_test.dart` 里用旧标签编辑框的步骤、`status_view_test.dart` 和 `favorite_test.dart` 里找 `TextButton` 的状态页按钮。
- live_ui 全部 60 个通过；`apps/pure_live` 全部 291 个通过（本批共新增 13 个用例，不含参数化展开）。

## 没做的和原因

1. 搜索、观看历史、设置里的卡片预览还用旧 `RoomCard`：这些是 I、J 的目录，换卡片时把 `RoomCard(...)` 换成 `RoomGridCard` / `LiveRoomCard`（历史传 `showDelete`，搜索的“全部”传 `mixedPlatforms: true`）。
2. 电视卡片（A17.3）没改。
3. 没有在真机和 profile 模式看帧时间（这次不安装）。
