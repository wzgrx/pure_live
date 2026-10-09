# A11.6 从子页面返回后列表回到原来的位置（设置和同类页面）：任务书

## 背景

- 来源：用户 2026-10-09：“2.设置打开子功能，返回上级以后，设置界面会回到最上面，还需要用户手动继续下滑到原位置，顺便看看还没有这种问题，全部修复”。
- 现象：设置里往下翻、点开一页、返回，设置回到最上面。
- 为什么现在做：第一档，用户每天在用的地方。

## 目标和验收

1. 手机一栏：设置总览往下翻 → 打开任一页 → 返回（左上角返回、系统返回）：总览停在原来的位置。
2. 搜索结果往下翻 → 点一个会打开别的页的结果 → 返回：结果停在原来的位置；换一个搜索词从顶上开始。
3. 两层：总览 → 一页（例如视频）→ 它的子页（竖屏直播适配）→ 返回 → 返回：每一层都在原来的位置。
4. 宽屏两栏（1280×800、横屏手机 852×393）：左栏总览、右栏的页在打开子页和路由页（备份）后都不动。
5. 跨 840（转屏、分屏改宽度）：总览和打开的页都在原来的位置。
6. 清点其他同类页面：首页关注、热门、分区、搜索结果、观看记录、分区房间 → 直播间 → 返回；录制中心、账号和数据页、本地互动设置页、弹幕和屏蔽页；电视只在顺手时看。每一页写清保留还是丢、为什么，丢的修掉。
7. 用一个共用的做法，不加新包。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`、`docs/specs/UI.md`、`docs/DECISIONS.md`、[A11 README](../README.md)。
2. `apps/pure_live/lib/features/settings/settings_page.dart`、`settings_section_view.dart`、`settings_tiles.dart`；`apps/pure_live/lib/routes/app_navigator.dart`、`app_router.dart`；`apps/pure_live/lib/features/home/home_page.dart`。

## 范围

- 可以改：上面的设置文件；`packages/live_ui/lib/src/widgets/scrolling.dart`；丢位置的页面的列表（只加位置记忆，不改样子）；对应测试；`docs/specs/UI.md` 第 5.3 节；本文件夹、登记表。
- 不能改：直播间的菜单、弹层和旧弹窗（A07.23 同时在改 `room_menu_button.dart` 等）；路由表；翻译文件的已有键（D-024）；版本号。

## 方案和阶段

| 阶段 | 做什么 | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | 设置总览、搜索结果回到原位（手机一栏、宽屏两栏、跨 840） | `settings_page.dart`、`scrolling.dart` | 改之前失败的测试改后通过 |
| 2 | 首页标签（热门、分区、录制中心）切回来回到原位；其余页面清点、补守护测试 | `room_grid.dart`、`platform_areas_view.dart`、`recorder_page.dart` | 同上；清点表写进 `record.md` |

## 测试

- 新 `apps/pure_live/test/features/settings/settings_scroll_position_test.dart`（手机和宽屏两种宽度）。
- 各页现有的测试文件里加一条“A11.6”：`popular_test.dart`、`areas_test.dart`、`recorder_centre_test.dart`、`favorite_test.dart`、`history_page_test.dart`、`search_test.dart`、`account_page_test.dart`；`packages/live_ui/test/scrolling_test.dart`。
- 能做到的都要在改之前失败。

## 真机验证（维护者在 K90 上做）

见 [verify.md](verify.md)。

## 环境和提交

- `source ~/tools/purelive-env.sh`；新工作区先 `bash tools/ffmpeg_kit/fetch.sh android`、`linux`。
- 提交信息以 `[A11.6]` 开头（英文）；不推 master。

## 报告

根因（文件和行）；清点表（页面、保留还是丢、原因、修没修）；共用的做法；改了哪些文件；测试；门禁；真机上要看的；可能冲突的文件。
