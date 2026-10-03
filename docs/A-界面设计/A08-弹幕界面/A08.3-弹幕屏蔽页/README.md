# A08.3 弹幕屏蔽页：设计（第 1 版，已定稿并实现）

- 状态：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)（登记为完成，2026-10-01；K90 上没有记录，见“实现和验证”）
- 旧编号：U.12d、T06b.1（见 [MAPPING.md](../../../MAPPING.md)）
- 范围：设置里的弹幕屏蔽页（有内容、空、重复关键词、删除撤销）
- 对应：[inventory/UI.md](../../../inventory/UI.md#a083)（A08.3-01）、[inventory/UI_FILES.md](../../../inventory/UI_FILES.md#a083)；跨任务约定“A08.1 → A08.3：用 A08.1 屏蔽管理的同一个组件（选择 E4）”；相关决定 D-003（M1、M2 按建议 A）
- 评审页：claude.ai 私有页面；源文件 [page.json](page.json)，效果图源文件 [src/gen.py](src/gen.py)（新设计的组件代码照抄 [A08.1/src/gen.py](../A08.1-弹幕列表和弹幕设置页/src/gen.py) 的 `v4_block`，公用部分 [src/skit.py](src/skit.py)）；按章节导出在 [page/](page/01-说明.jpg)
- 图片：v3 按 `v3.2.11` 代码还原（文字取自 `assets/translations/zh.json`）；关键词和用户名是示例
- **和 A08.1 联动**：组件在 A08.1 评审；那边改了这里跟着改（E4 选了 A，所以这一页就是那个组件加一个顶栏）
- 记录：[record.md](record.md)

## 界面清点表

| 编号 | 界面 | 从哪打开 | 形态 | 状态 |
|---|---|---|---|---|
| A08.3-01 | 弹幕关键词屏蔽页（`DanmuShieldPage`） | 设置 → 视频“弹幕关键词过滤”（`modules/settings/pages/video_settings_page.dart:288-293`） | 竖屏、横屏、宽屏 | 有关键词、空、重复（v3 无反应）、空着点添加（提示条“请输入关键字”） |
| 新 | 已屏蔽用户、平台弹幕过滤、相似弹幕过滤 | 同一页（A08.1 组件） | 同上 | 用户空、相似过滤开 / 关 |
| 新 | 删除后的提示条 | 点 × | 全部 | “已移除“…” · 撤销” |

## 3.x 的样子和问题

### 3.x 的样子

文件 `git show v3.2.11:lib/modules/shield/danmu_shield_page.dart`（132 行）、`danmu_shield_controller.dart`（29 行）；入口 `lib/modules/settings/pages/video_settings_page.dart:288-293`。

- 顶栏“弹幕关键词屏蔽”居中（`:14`）。
- 内边距 16：输入框（`surfaceContainerLow` 底、圆角 14、无边框，聚焦时主色 1.5；提示“请输入关键字”；最多 40 字，下面计数；框里右边文字按钮 `Remix.add_line` 18 +“添加”600）；回车也能添加（`:19-47`）。
- 24 → “已添加 {count} 个关键词（点击可移除）”14 号粗主色（`:49-61`）。
- 关键词：`Wrap` 间距 10，每个小标签主色 6% 底、15% 描边、圆角 10，13 号 500 + `Remix.close_line` 14；点整个标签就删除（最小 48×48）（`:76-125`）。
- 空：`EmptyView`（`Remix.discuss_line`、“暂无屏蔽关键词”、“添加关键词后，包含该内容的弹幕将被自动过滤”）（`:65-74`）。
- 空着点添加：提示“请输入关键字”；重复：`addShieldList` 不加也不提示，输入框照样清空（`danmu_shield_controller.dart:6-15`）。
- 没有宽度分支、没有最大宽度；没有快捷键（回车提交除外）。

### 问题

| 编号 | 问题 | 位置 |
|---|---|---|
| D1 | 设置里只能管关键词，用户和两个过滤只在直播间里 | `danmu_shield_page.dart:13-130`、`live_play/pages/keyword_block_page.dart` |
| D2 | 同一份关键词两种样子、两种删法 | `danmu_shield_page.dart:76-125`、`keyword_block_page.dart:246-274` |
| D3 | 点整个标签就删，没有撤销 | `danmu_shield_page.dart:87-89` |
| D4 | 重复关键词没反应还清空 | `danmu_shield_controller.dart:6-15`、`favorite_room_controller.dart:446-455` |
| D5 | 三个名字：弹幕关键词过滤 / 弹幕关键词屏蔽 / 屏蔽管理 | `video_settings_page.dart:288-293`、`:14`、`live_play_controller.dart:73` |
| D6 | 输入和添加的样子和直播间不同 | `danmu_shield_page.dart:19-47` |
| D7 | 宽屏拉满 | `danmu_shield_page.dart:15-18` |

### 设计时 v4 的偏差（实现时已改掉）

页面叫“弹幕屏蔽”，两个标签页“关键词（N）”“用户（N）”，每页输入框、“清空”（确认、可撤销）、删除可撤销、重复提示；没有平台弹幕过滤和相似弹幕过滤。设置入口叫“屏蔽词和屏蔽用户”（`settings_catalog.dart:887-894`）。

## 各版的经过

| 版 | 内容 | 用户意见 |
|---|---|---|
| 第 1 版 | 用 A08.1 组件单独成页，两处待选 | 用户确认；M1、M2 按建议 A（D-003） |

## 对比页（按章节导出）

- [说明](page/01-说明.jpg)
- [对比：竖屏](page/02-对比-竖屏.jpg)
- [各种状态](page/03-各种状态.jpg)
- [横屏和宽屏](page/04-横屏和宽屏.jpg)
- [v3 的问题](page/05-v3-的问题.jpg)
- [改了什么](page/06-改了什么.jpg)
- [每个按钮是干什么的、怎么用](page/07-每个按钮是干什么的-怎么用.jpg)
- [各客户端](page/08-各客户端.jpg)
- [需要你选的](page/09-需要你选的.jpg)
- [性能要点](page/10-性能要点.jpg)

## 单张图

| 图 | 内容 |
|---|---|
| [v3-shield.jpg](v3-shield.jpg)、[v4-shield.jpg](v4-shield.jpg)、[v4-shield-n.jpg](v4-shield-n.jpg) | 竖屏 / 编号 |
| [v4-shield-full.jpg](v4-shield-full.jpg)、[v4-shield-full-n.jpg](v4-shield-full-n.jpg) | 完整内容（相似过滤打开） |
| [v3-shield-states.jpg](v3-shield-states.jpg)、[v4-shield-states.jpg](v4-shield-states.jpg) | 空、重复、删除撤销 |
| [v3-shield-land.jpg](v3-shield-land.jpg)、[v4-shield-land.jpg](v4-shield-land.jpg) | 手机横屏 852×393 |
| [v3-shield-wide.jpg](v3-shield-wide.jpg)、[v4-shield-wide.jpg](v4-shield-wide.jpg) | 宽屏 1280×800 |

## 确认的改动

| 编号 | 类型 | 内容 | 对应问题 |
|---|---|---|---|
| c1 | 保留 | 入口位置、添加（回车）、40 字、列表和条数、空状态和提示文字 | — |
| c2 | 修改 | 整页换成 A08.1 屏蔽管理组件：关键词 → 用户 → 平台过滤 → 相似过滤 | D1、D2、D6 |
| c3 | 修改 | 只有 × 删除，可撤销 | D3 |
| c4 | 增强 | 重复关键词提示，不清空 | D4 |
| c5 | 修改 | 页面和入口叫“弹幕屏蔽”（M1） | D5 |
| c6 | 修改 | 最宽 720 | D7 |

新文字同 A08.1（“‘{词}’已经在屏蔽列表里”“已移除‘{词}’”“撤销”），另加入口副标题“关键词、屏蔽用户、平台和相似弹幕过滤”；页面标题用 v4 已有的 `shield_title`“弹幕屏蔽”。

## 按钮的作用和用法

| 编号 | 控件 | 怎么用 |
|---|---|---|
| 1 | 返回 | 回到设置 |
| 2 | 关键词输入框 | 最多 40 字，回车也能加 |
| 3 | 添加 | 加入关键词 |
| 4 | 关键词的 × | 删除，可撤销 |
| 5 | 已屏蔽用户的 × | 取消屏蔽，可撤销 |
| 6 | 过滤斗鱼疑似自动弹幕 | 开关 |
| 7 | 启用相似弹幕过滤 | 开关；关着时滑块变灰 |

## 各客户端

| 客户端 | 怎么做 |
|---|---|
| Android 手机 | 竖屏如图；横屏同一页最宽 720 |
| 宽屏（平板、Windows、Linux、iPad、macOS） | 最宽 720 居中；悬停 × 有说明，回车添加 |
| 电视 | A17.9 / A17.4：pure_live_TV 的“弹幕关键词屏蔽”（`danmaku_shield_section.dart`）和播放设置侧面板，换成同一组件的电视样式 |
| 苹果平台差异 | 无 |

## 待选和决定

（这两处在 docs v1 改编号时被误换成了任务编号 Q01.1、E05.1，原文是 M1、M2，这里改回；`M` 只是选项的序号，不是旧的模块编号。）

- M1 名字：A 页面和入口都叫“弹幕屏蔽”；B 照 v3 入口“弹幕关键词过滤”、页面“弹幕关键词屏蔽”。**用了 A**（D-003）：页面标题用已有的 `shield_title`“弹幕屏蔽”，入口的两条文字 `settings_block_list`“弹幕屏蔽”、`settings_block_list_desc`“关键词、屏蔽用户、平台和相似弹幕过滤”。
- M2 清空：A 不要（照 A08.1 组件，v3 也没有）；B 两节加“清空”（v4 现在有），直播间标签同时加。**用了 A**：v4 原来两个标签页各有的“清空”随整页替换去掉。

### 设计时拿不准的地方和后来的结论

1. 设置入口在 A11.3（设置 → 视频 / 播放）的范围，改名要在那边一起改（已写进报告，待记入 TASKS 第 7 节）。
2. v4 现在可以带参数直接打开“用户”标签页（`route.arguments == BlockKind.user`）；换成一页以后，从别处跳过来时滚到“已屏蔽用户”一节。

结论：第 1 条只改了入口用的两条翻译文字，没有改 A11.3 的代码（入口现在在 `apps/pure_live/lib/features/settings/settings_catalog.dart:903`，路由 `RoutePath.kSettingsDanmuShield` = `/shield`）；第 2 条做成 `DanmakuBlockManager(showUsers:)`，带 `BlockKind.user` 打开时读完列表滚到“已屏蔽用户”。

### 需要改工具的地方

- 无。

## 实现和验证

- 实现：c1～c6、M1、M2 都做了（逐条见 [record.md](record.md)）。`apps/pure_live/lib/features/shield/shield_page.dart`（47 行）的 `ShieldPage`（`:21`）只剩顶栏（窗口高 <480 时 48 高，`:30-32`）和 `DanmakuBlockManager`（`shared/danmaku/block_manager.dart:29`）：卡片区 720 + 24、居中，滚动区是整个窗口宽（`:33-43`）。直播间“屏蔽管理”标签和这一页同一个组件、同一份存储。v4 原来的两个标签页 `block_list_tab.dart` 删掉。
- 对共用组件的改动（记录“对共用组件的改动”）：撤销放回原来的位置（新函数 `restoreBlockEntry`，`block_manager.dart:392`；直播间标签也一起变）；`showUsers` 滚到“已屏蔽用户”；整页从 `ListView` 换成 `SingleChildScrollView` + `Column`（四组内容很短，没有懒加载的必要）。
- 偏差：v4 原来“用户”标签页能手动输入用户名加屏蔽，A08.1 组件没有这个输入框（屏蔽用户在直播间长按弹幕时加，v3 也是这样），随设计去掉。
- 新文字：改了 `settings_block_list`、`settings_block_list_desc` 两条；v4 原来两个标签页用的 `shield_tab_*`、`shield_clear*`、`shield_duplicate` 等现在没地方用，留在翻译文件里（D-024：这次不清理）。没有新设置。
- 门禁：`shield` 直接写的颜色和图标 6 → 0（`tools/gate/ui_baseline.json` 去掉这一项）。
- 提交：`5ba728803`（`feat(shield): the settings page uses the room's block manager (U.12d)`，登记表写的是这个）；合并 `6f13ced71`（2026-10-02，和 A15.1、A15.2、A09.10 一起）。
- 后来的变化：D02.1 在组件顶上加了打码昵称清理后的一次性说明（`block_manager.dart:90`）。
- 自动测试：`apps/pure_live/test/features/shield/shield_page_test.dart`（现在 7 个用例声明）：一页四组的顺序、两节的空说明、相似过滤关着时滑块变灰、没有“清空”、输入框和“添加”的位置、40 字；空着添加提示、回车添加、重复提示不清空；点词本身不删、× 的点击区 48、撤销放回原位（关键词和用户）；带 `BlockKind.user` 打开时滚到“已屏蔽用户”；852×393 和 1280×800 最宽 720 居中、横屏顶栏 48。照实改的旧断言见记录。`live_play_tabs_test.dart` 13 个照旧通过。
- 真机：记录里没有 K90 结果，也没有 `verify.md`（登记表的问题见[子分类页](../README.md)“已知问题”）。要看的：设置 → 视频 → 弹幕屏蔽打开这一页；加词、重复提示、删除后 4 秒内撤销回到原位；从直播间加的词和屏蔽的用户这里能看到（[CHECKLIST](../../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 2 节第 4 条）。
- 留下的问题：电脑上 Esc 不返回（`ShieldPage` 没有 `EscapeBack`）→ A05.1；电视的弹幕屏蔽 → A17.9、A17.4。
