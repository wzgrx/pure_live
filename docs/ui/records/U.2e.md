# U.2e 直播间的四个标签

- 日期：2026-10-01
- 设计：[docs/ui/compare/U.2e/README.md](../compare/U.2e/README.md)（第 1 版，用户 2026-10-01 确认全部设计；待选 E1～E4 按建议 A 做）
- 范围：弹幕列表、醒目留言、弹幕设置标签、屏蔽管理，以及它们的各种状态；宽屏、手机横屏（不是全屏时）用同一套标签
- 改动的目录：`apps/pure_live/lib/features/live_play/`、`apps/pure_live/lib/shared/danmaku/`（新增可复用组件）、`packages/live_core`（只加平台能力标记）、`packages/live_ui`（只做添加）、翻译文件、门禁基线、文档
- 和同时进行的任务的分工：竖屏、横屏全屏、宽屏的排法（U.2b–U.2d）不在这里改；本地互动（U.2k）的输入框、“本地”标签和徽章留给 U.2k，列表行组件留了显示标签的位置（`ChatLineView.tag`）
- 没有改原生部分，没有构建 APK，没有往手机安装

## 逐条对照

| 编号 | 内容 | 做到 | 说明 |
|---|---|---|---|
| c1 | 保留：标签和顺序、左右滑；长按 / 右键 / 双击弹幕；“N 条新弹幕”；醒目留言卡片结构和空状态；屏蔽管理全部设置项和范围 | ✅ | 本地互动输入框 v4 还没有，属于 U.2k |
| c2 | 还没有聊天弹幕时中间显示状态：连接中、还没有弹幕、连接超时 +“重新连接”、平台不提供 | ✅ | `LiveRoomController.chatConnection`（空闲、连接中、已连接、超时、失败、平台不提供）；“重新连接”调 `reconnectDanmaku()`。连接失败（不是超时）时标题用最后一条系统消息，也给“重新连接”（设计图只画了超时）。有了第一条非系统消息后照 U.2a 显示列表和居中小标签 |
| c3 | “显示弹幕”关闭时加“开启弹幕显示”按钮 | ✅ | 按钮直接打开设置 `enableDanmakuDisplay`，列表马上恢复 |
| c4 | “N 条新弹幕”用主色上的文字色 | ✅ | U.2a 时已是 `onPrimary`，加了测试 |
| c5 | 醒目留言新的在上（E2 A） | ✅ | |
| c6 | 卡片字色按对比度选（至少 4.5:1）；去阴影只留细边；整个列表共用一个每秒倒计时 | ✅ | `InkOnColor.contrastOn`（WCAG 对比度比较深浅两种墨色）；一个 `Timer.periodic` + `ValueNotifier`，每秒只重绘倒计时文字；列表只在醒目留言增减时重建。圆角用装饰（头部上圆角、内容下圆角），不裁剪 |
| c7 | 平台不提供醒目留言时写明“{平台}的直播间没有醒目留言。” | ✅ | 新的平台能力标记 `LiveSite.hasSuperChats`（见下） |
| c8 | 弹幕设置标签用 U.2f 组件；去掉标题栏和关闭；“改动立即生效”放第一节右边 | ✅ | `RoomDanmakuSettings(inTab: true)`，`PanelGroupTitle` 加了右侧说明 |
| c9 | 组件末尾“弹幕列表”“小窗弹幕”两组（E1 A，标签和画面上的面板一样） | ✅ | “弹幕列表”：列表样式（整行分段按钮）、在聊天列表显示礼物；“小窗弹幕”：v3 的 12 项一项不少（小窗显示弹幕、纯文字、自动缩放、保留平台颜色、统一弹幕颜色、字体大小 8–24、粗细、速度 20–400、透明度 10–100%、占用高度 10–100%、最大同时显示 1–20、发送间隔 0.05–2、帧率跟随和手动帧率 15–240）。“小窗显示弹幕”关闭时其余收起（v3） |
| c10 | 小窗数值带单位；统一弹幕颜色变灰不消失 | ✅ | “12.0 px”“90 px/s”“0.35 秒”；帧率跟随时手动帧率变灰并显示实际帧率（`resolvedDanmakuFps` 加了 `pip`：最低 15、省电 30，照 v3） |
| c11 | 屏蔽管理顺序：关键词 → 已屏蔽用户 → 平台过滤 → 相似过滤（E3 A） | ✅ | |
| c12 | 关键词和用户用小标签，只有 × 删除，触控区 48 | ✅ | `BlockChip`：标签本身不响应，× 的点击区 40×48；电脑悬停提示“点击移除: 词” |
| c13 | 重复关键词在输入框下面提示，不清空 | ✅ | “‘剧透’已经在屏蔽列表里” |
| c14 | 两节为空时显示说明 | ✅ | 文字用已有词条“暂无屏蔽关键词 / 添加关键词后……”“还没有屏蔽的用户；长按弹幕可屏蔽发送者” |
| c15 | 删除后提示条可撤销（4 秒） | ✅ | SnackBar 默认 4 秒，“已移除‘…’ · 撤销”，撤销重新加回（顺序排到末尾） |
| c16 | 相似过滤关闭时滑块变灰；行样式和弹幕设置组件统一 | ✅ | 弹幕设置的行组件挪到 `shared/danmaku/setting_rows.dart`，两处共用 |
| c17 | 宽屏、横屏同一套标签和内容；栏窄时条数角标 | ✅（部分） | 标签和内容不变（U.2a 的角标照旧），有测试；“信息行放不下时只留在线和时长”属于 U.2d 的排法，没有改 |

### 选择

| 编号 | 决定 | 做到 |
|---|---|---|
| E1 | A：两组放在组件末尾，标签和画面上的面板一样 | ✅ 面板里也有，有测试 |
| E2 | A：醒目留言新的在上 | ✅ |
| E3 | A：关键词、已屏蔽用户在前 | ✅ |
| E4 | A：设置里的“弹幕关键词屏蔽”页（U.12d）用同一个组件 | ✅ 做成 `shared/danmaku/block_manager.dart` 的 `DanmakuBlockManager`（`showFilters` 可关掉两组过滤，`addKeyword` 可换成直播间的“加词并去掉列表里含这个词的弹幕”）；U.12d 开发时直接用，设置页这次没有改（别的任务的目录） |

## 平台能力标记（`packages/live_core`，只做添加）

- `LiveSite.hasSuperChats`：默认按 `superChatPlatforms`（`bilibili`、`huya`、`douyu`，照 v3：哔哩哔哩、虎牙有接口和弹幕流，斗鱼从弹幕流来），各平台适配器没有改。
- 测试：三个平台为真，抖音、快手、网易 CC、Twitch、网络电视为假。

## 和设计的偏差

1. **统一弹幕颜色的选择框**：v4 的颜色对话框在 `features/settings`（别的功能目录不能引用），这里另做了一个小的 `shared/danmaku/danmaku_color_dialog.dart`（常见弹幕色 + 十六进制）。以后 U.6c 统一时可以合并。
2. **醒目留言卡片的金色图标**：用新加的语义色 `LiveSemanticColors.superChatGold`（v3 的琥珀色）。
3. **连接失败**：见 c2 说明。

## v3 文件 → v4 文件

| v3（`lib/modules/live_play/`） | v4 |
|---|---|
| `widgets/danmaku/danmaku_tab.dart` | `features/live_play/danmaku/chat_panel.dart` |
| `widgets/danmaku/danmaku_list_view.dart` | `features/live_play/danmaku/chat_list.dart`（状态：`ChatListState`、`RoomNoticeState`） |
| `pages/super_chat_page.dart`、`widgets/layout/super_chat_card.dart` | `features/live_play/danmaku/super_chats.dart` |
| `pages/danmaku_settings_page.dart`、`settings/pages/pip_danmaku_settings_page.dart`（`PipDanmakuSettingsSection`） | `features/live_play/danmaku/danmaku_settings_panel.dart`（`RoomDanmakuSettings`、`PipDanmakuSettings`）、`shared/danmaku/setting_rows.dart`、`shared/danmaku/danmaku_color_dialog.dart` |
| `pages/keyword_block_page.dart`（和 `modules/shield/danmu_shield_page.dart` 的列表） | `shared/danmaku/block_manager.dart` |
| `core/interface/live_site.dart:256-258`（`getSuperChatMessage` 默认空） | `packages/live_core/lib/src/live_site.dart`（`hasSuperChats`） |

## 新设置项

无（小窗弹幕的 12 项都是 3.x 已有的设置，键名不变）。

## 新增的文字

中英各加：`danmaku_display_disabled_title/desc`、`danmaku_display_enable`、`live_play_chat_empty/_desc`、`live_play_chat_timeout/_desc`、`live_play_chat_reconnect`、`live_play_chat_unsupported/_desc`、`super_chat_unsupported`、`keyword_already_blocked`、`pip_danmaku_interval_seconds`、`pip_danmaku_fps_follow_desc`。其余用已有词条。

## 门禁

- `live_play` 直接写的颜色和图标：U.2e、U.2g 合计 **9 → 8**（节目单的 `Icons.live_tv_rounded` 去掉），`tools/gate/ui_baseline.json` 已改为 8。新代码的颜色和图标都走 `live_ui`（新增图标见 U.2g 记录的 `AppIcons` 一节；本任务用到 `chatEmpty`、`danmakuTimeout`、`danmakuUnavailable`、`superChatPrice`、`superChatMark`、`superChatTime`、`chipRemove`、`add`）。
- 没有新增跨功能引用；`logic/` 没有引用 material。

## 测试

- 新增 `test/features/live_play/live_play_tabs_test.dart` 13 个：连接中 → 超时 → 重新连接；连上没人说话 → 第一条后显示列表和系统小标签；平台不提供弹幕；“显示弹幕”关闭和按钮；“N 条新弹幕”的字色；醒目留言新的在上、金色底用深字、没有阴影、共用时钟；抖音没有醒目留言；窄栏卡片头部竖排和倒计时格式；设置标签的“改动立即生效”、分组顺序、小窗数值单位、统一颜色变灰、小窗弹幕关闭时收起；画面上的弹幕设置面板末尾也有两组；屏蔽管理的顺序、空说明、相似过滤滑块变灰、添加、重复提示不清空、只有 × 删除（48 高）、撤销；1280×800 和 852×393 标签在右栏。
- `live_core` 新增 1 个，`live_ui` 新增 1 个（对比度选墨色）。
- 和新设计冲突、照实改了的原有断言：

| 测试 | 原断言 | 改为 | 原因 |
|---|---|---|---|
| `live_play_room_test` 弹幕列表 | 弹幕服务器连上后马上能看到系统消息小标签 | 先显示“还没有弹幕”状态，第一条弹幕后才看到列表和小标签 | c2：第一条之前在中间显示状态 |
| `live_play_room_test` 卡片样式、`live_play_more_page_test` 礼物开关 | 滚到“卡片”“在聊天列表显示礼物”后直接点 | 先 `ensureVisible` 再点 | c9：列表样式改成整行分段按钮、后面多了“小窗弹幕”，滚动停的位置变了 |

- 全部测试：`apps/pure_live` 310 个通过（含 U.2g 的新测试）；`flutter analyze` 无问题；`check_ui_structure.py` 通过。

## 没做的和原因

1. 本地互动输入框、“本地”标签和徽章：U.2k 同时在做；`ChatLineView` 加了 `tag` 参数（显示在名字前），U.2k 接上即可。
2. 宽屏信息行“放不下时只留在线和时长”：U.2d 的排法。
3. 电视：U.15d 出图。
