# T07b.2 热门

- 日期：2026-10-01
- 设计：[docs/T07/T07b/T07b.2/README.md](README.md)（用户已确认；B1～B3 按 A）；卡片见 [T07d.1 记录](../../T07d/T07d.1/record.md)
- 改动的目录：`apps/pure_live/lib/features/popular/`、`apps/pure_live/lib/shared/rooms/`（共用的整页 `RoomFeedView` 和翻页栏）、翻译文件。顶栏左右的菜单和搜索按钮是 T07 的（`MenuButton`、`CommonAppBarActions`），照原样放着

## 逐条对照

| 编号 | 内容 | 做到 | 说明 |
|---|---|---|---|
| c1 | 标签在标题位置、左右滑动、小号卡片网格、菜单和搜索菜单、下拉刷新和自动加载、电脑翻页栏和 ← →、回到顶部 / 底部、流量提示、刷新进度条、15 秒回来刷新、首选平台、预取下一个 | ✅ | v4 之前把标签放在“热门”标题下面一行，这次照 v3 放回标题位置。翻页栏挪到 `shared/rooms/paging.dart`，键名改为 `pager-*` |
| c2 | 标签末尾 ⌄ 打开“全部平台”：图标 + 名字，当前打勾，点了切过去并关闭；“平台显示”；竖屏底部、宽屏右侧 | ✅ | `PlatformPicker` + `showAdaptivePanel`：窗口宽 600 起在右侧（宽 360、整高），否则从底部升起（可下拉关闭）；✕、返回键、Esc、点外面关闭；说明“N 个平台，点一个直接切过去；在“平台显示”里可以隐藏和排序” |
| c3 | 平台全关：“没有要显示的平台”“在“平台显示”里选择要在热门页显示的平台”，按钮“平台显示” | ✅ | 顶栏照常（菜单、搜索） |
| c4 | 没有直播的说明 | ✅ | 手机“……也可以下拉刷新”，电脑“……也可以点下面的刷新”；按钮“刷新”。另有 v4 的“已隐藏 N 个暂时不能播放的直播”（UPGRADES 统一原则）时，第一个按钮“显示”、第二个文字按钮“刷新”（T01c.1 C1） |
| c5 | 出错按原因写一句话，标题“网络请求失败”和“重试” | ✅ | `describeLoadError` 的文字；需要登录（含风控）是“需要登录账号”“前往登录”（登录图标） |
| c6 | 平台说明放带 ⓘ 的浅色条，最多两行 | ✅ | `NoticeBar`，点一下展开全文（v4 原有的展开保留） |
| c7 | 第一次加载静态骨架 | ✅ | 列数和行高同真卡 |
| c8 | 列数按公式 | ✅ | 测试固定：393×852 两列、852×393 四列、1280×800 五列，网格边距 6 |
| c9 | 按页面自己的宽度排版 | ✅（有偏差） | 网格列数只用页面的 `LayoutBuilder` 宽度；“是否用电脑翻页栏”照 v3 看窗口宽 >680 且不是手机系统（这是输入方式的判断，不是排版）；顶栏要不要菜单按钮仍用 T07 的 680 分界（外壳的事，T07 在改） |

选择：B1 全部平台面板 ✅；B2 静态骨架 ✅；B3 电脑翻页栏、触屏自动加载 ✅。

## v3 文件 → v4 文件

| v3 | v4 |
|---|---|
| `modules/popular/popular_page.dart` | `features/popular/popular_page.dart`（标签、⌄、全部平台面板） |
| `modules/popular/popular_grid_view.dart`、`common/base/base_page_view.dart`、`base_page_view_extension.dart` | `features/popular/popular_grid.dart`（只配文字）+ `shared/rooms/room_grid.dart` 的 `RoomFeedView` |
| `common/base/desktop_components.dart` | `shared/rooms/paging.dart` |
| `modules/popular/popular_controller.dart` | `features/popular/popular_catalog.dart`、`popular_page.dart`（照旧） |

## 新设置项

无。

## 门禁

`popular` 直接写的颜色和图标 26 → 0。

## 测试

`test/features/popular/popular_test.dart` 新增：全部平台面板（竖屏底部、打勾、点了切过去；宽屏右侧 360、✕ 关闭）、三种尺寸的列数和边距、空状态文字和刷新。照实改：标题位置不再是“热门”而是平台标签；翻页栏键名；卡片类型 `LiveRoomCard`；长按对话框的“虎牙 · 房间号 7”。`home_test.dart`（T07 的目录）里两处“AppBar 里有‘热门’”改为“热门页在”，原因同上。

## 没做的和原因

- 电视（T18b.1）不在这次。
