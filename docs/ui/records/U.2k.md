# U.2k 本地互动

- 日期：2026-10-01
- 设计：[docs/ui/compare/U.2k/README.md](../compare/U.2k/README.md)（第 1 版，用户已确认；待选 K1～K4 都按 A）；计划书 [UI_PLAN.md](../UI_PLAN.md) 第 3、5、7、8、9 节
- 范围：v4 原来没有这个功能，这次照 v3（`widgets/local_interaction/*`、`settings/pages/local_interaction_settings_page.dart`、页面里的礼物特效）把逻辑和界面一起做：弹幕列表下的输入框、全屏输入框组件（交给 U.2c 放进下栏）、本地互动面板、本地弹幕样式、礼物特效、列表里的本地弹幕行、设置里的“本地用户与互动”页
- 改动的目录：`apps/pure_live/lib/features/live_play/`（新目录 `local_interaction/`，逻辑在其中的 `logic/`）、`apps/pure_live/lib/shared/danmaku/danmaku_overlay.dart`（飞过的本地弹幕用本地样式）、`apps/pure_live/lib/routes/`（加一条路由）、`packages/live_store`（只加设置）、`packages/live_ui`（只加图标和画面颜色）、应用资源（emoji 子集字体和 OFL 许可）、翻译文件、文档
- 没有改原生部分，没有构建 APK；没有往手机安装

## 逐条对照

| 编号 | 要求 | 做到 | 说明 |
|---|---|---|---|
| c1 | 功能、数据、默认值、范围、存储键照 v3 | ✅ | 见下面“v3 的每一项在哪”；3.x 的 `localInteraction.*` 照旧读写（见“设置”） |
| c2 | 面板照 U.2f：竖屏画面下方，横屏和宽屏右侧 360，同一个面板；全屏从四宫格菜单打开 | ✅（全屏入口待 U.2c） | `RoomPanelKind.localInteraction`，放法和录制面板相同；菜单第三组“本地互动体验”已打开。全屏下栏的四宫格菜单是 U.2c 加的，它用同一个 `RoomMenuButton`，就会有这一项；面板在全屏时已经放在右侧（`_withSidePanel`） |
| c3 | 身份卡 → 发送框 → 礼物 → 加体验币 → 我的资料 → 画面上 → 记录；标题旁“设置 ›” | ✅ | `local_interaction_panel.dart`；“设置 ›”走路由 `RoutePath.kLocalInteraction` |
| c4 | 样式各尺寸同一个面板，预览固定在顶上；从面板进是下一页（左上角返回）；设置页也进这一页 | ✅ | `local_style_panel.dart` 的 `LocalDanmakuStylePanel`；星形直接打开时没有返回（`RoomPanelKind.localStyle`）；设置页没有画面，按 UI_PLAN §7 在竖屏从底部、宽屏从右侧打开同一个面板 |
| c5 | 不适用的项变灰不消失并写明条件；“恢复默认”文字按钮；“清爽（默认）” | ✅ | 描边、阴影、固定停留时间三组变灰（不透明度 0.38、滑块和色块不可点），条件写在组里；描边组的条件“打开‘描边’后可调”是照阴影组补的（设计图默认描边开着，没画） |
| c6 | 三个输入框同一个组件、同样的发送表现（K1 A） | ✅ | `LocalDanmakuComposer`，`place` 为 `chat`、`panel`、`video`；发出即进列表、飞过（“飞过”开着时），不弹提示 |
| K1 | 画面弹幕关着时提示一次 | ✅ | 每个直播间第一次提示“画面弹幕已关闭，只加到了弹幕列表”（条件同 v3：显示弹幕关或隐藏弹幕） |
| c7 | 统一叫“本地弹幕”；提示、开关改名 | ✅ | 改了已有键的文字（`local_message_hint`、`local_overlay_message`、`_desc`），U.2c 用这个组件，提示自然跟着改 |
| c8 | 面板里也有“显示本地礼物特效” | ✅ | |
| c9 | 礼物特效在画面中间（全屏开着面板时避开面板）、单独图层、两行字、实心外圈、两档、减少动态效果时不缩放 | ✅（有一处偏差） | `local_gift_effect.dart`，放在 `RoomPlayer` 的图层里，只有这一层随特效重建；偏差：缩放曲线用减速（`easeOutCubic`，420 毫秒），不用 v3 的回弹，照 UI_PLAN §8.6“不回弹” |
| c10 | 列表里“本地”标签和徽章胶囊（含 Lv.N）；礼物不重复名字；飞过的礼物文字缩短；长按照 v3 | ✅ | `local_chat_line.dart`，接在 `ChatLineView` 最前面（一个 `if`）；长按面板对本地弹幕不显示“屏蔽此用户” |
| c11 | 余额不够的礼物变淡、仍可点；价钱前加币图标 | ✅ | 不够时提示“体验币余额不足” |
| c12 | 体验币和等级统一写法；记录两处都能看能清空，标条数 | ✅ | “用户等级 Lv.1 · 1000 电池”；设置页没有平台用通用包“本地等级 Lv.1 · 1000 本地体验币” |
| c13 | 全屏输入框焦点边框浅蓝；输入时控制栏不隐藏 | ✅（接线待 U.2c） | 浅蓝 = 用户主题色在深色主题下的主色（`localVideoFocusColor`）；组件的 `onHold` 在获得 / 失去焦点时通知，U.2c 接到下栏的 `onMenu` 上即可 |
| c14 | 窄屏收成星形按钮，点开后输入行在下栏上方、贴键盘，发出或点别处收起 | ✅（放进下栏待 U.2c） | 组件自己判断：中间宽度小于 180 时是星形按钮；点开的输入行是透明遮罩上的一行（最宽 520），离底边 64 或键盘上方 8，自动弹键盘 |
| c15 | 设置页按用途分组，入口说明在总开关下面并补上输入框 | ✅ | `local_interaction_settings_page.dart`，内容最宽 720 |
| c16 | 礼物和徽章用应用自带的 emoji 子集字体（K4 A） | ✅（有平台差异） | 见“emoji 字体” |
| K2 | 新装默认开 | ✅ | 默认值照 v3 |
| K3 | 从面板进样式是面板里的下一页 | ✅ | |

各客户端：

| 客户端 | 做到 |
|---|---|
| 手机竖屏 | 输入框在弹幕列表最下面；面板和样式在画面下方，标题栏下拉关闭 |
| 横屏全屏 | 面板在右侧 360；礼物特效在没被挡的画面中间；输入框组件给 U.2c |
| 宽屏 | 输入框在聊天栏最下面；面板盖在聊天栏上；回车发送、Esc 关面板（页面原有的返回顺序）、悬停显示“本地弹幕样式”“发送本地弹幕” |
| 电视 | 不适用 |
| 苹果 | 输入行贴键盘（按 `viewInsets`）；emoji 用系统字体（见下） |

## v3 的每一项在哪

| v3 | v4 |
|---|---|
| `local_interaction_controller.dart` 数据（模板、颜色、字体、位置、头衔、34 个资源包、8 个平台的礼物和通用礼物、等级、昵称规则） | `local_interaction/logic/local_catalog.dart` |
| `local_interaction_controller.dart` 状态和操作（Hive 值、`createChat`、`sendGift`、`recharge`、`applyDanmakuPreset`、`buildDanmakuStyle`） | `local_interaction/logic/local_interaction.dart`（`LocalInteraction`，在设置存储上） |
| `live_play_controller.dart` 的 `emitLocalMessage`、`localGiftEffect`；`local_message_delivery_queue.dart`（2 秒延迟） | `local_interaction/logic/local_room_session.dart`（K1 A 不再延迟，队列不需要了）；`logic/room_controller.dart` 新增 `addLocal` |
| `danmaku_list_view.dart:386-436` 输入框 | `local_interaction/local_composer.dart`（`LocalComposerBelow` 接在 `danmaku/chat_panel.dart` 的列表标签里） |
| `video_controller_panel.dart:1584-1750` 全屏输入框 | 同上，`LocalDanmakuComposer.onVideo` |
| `local_interaction_sheet.dart` | `local_interaction/local_interaction_panel.dart` |
| `local_danmaku_style_editor.dart` | `local_interaction/local_style_panel.dart` |
| `pages/live_play_page.dart:47-92` 礼物特效 | `local_interaction/local_gift_effect.dart`（接在 `player/player_view.dart`） |
| `danmaku_list_view.dart:504-519` 本地弹幕在列表里 | `local_interaction/local_chat_line.dart`（接在 `danmaku/chat_list.dart`） |
| `video_controller.dart:183-223` 飞过的本地弹幕 | `shared/danmaku/danmaku_overlay.dart` 的 `_addLocal` |
| `live_play_menu_button.dart:145-166`、`:203-204` 菜单项 | `buttons/room_menu_button.dart` 第三组 |
| `settings/pages/local_interaction_settings_page.dart` | `local_interaction/local_interaction_settings_page.dart`，路由 `/local_interaction` |

## 给别的任务的接口

- **U.2c（全屏下栏）**：中间放 `LocalDanmakuComposer.onVideo(onHold: onMenu)`（`local_interaction/local_composer.dart`）。它在直播间里自己找到本直播间的会话（`LocalRoomScope`），本地互动关着时什么都不画；宽度够时是输入框（最宽 420），中间宽度小于 `localComposerCollapseWidth`（180）时自己收成星形按钮。`onHold(true/false)` 在输入框获得 / 失去焦点、星形的输入行打开 / 关闭时调用，接到下栏已有的 `onMenu` 就能让控制栏不自动隐藏。是否留位置用 `localInteractionAvailable(ref)`（`local_interaction_scope.dart`）。四宫格菜单用 `RoomMenuButton` 就有第三组。
- **U.2e（弹幕列表行）**：本地弹幕的行在 `ChatLineView.build` 最前面接了一个分支（`message.isLocal` 时画 `LocalChatLine`，聊天行保留长按、右键、双击）；长按面板里“屏蔽此用户”对本地弹幕不显示（一处条件）。冲突时保留这两处即可。
- **U.6d（设置总览）**：入口跳 `RoutePath.kLocalInteraction`（`LocalInteractionSettingsPage`）。
- U.2b（竖屏全屏）的输入框用同一个组件。

## 设置（`packages/live_store`，只做添加）

- `Settings.localInteraction`：29 个设置，键就是 3.x 的 `localInteraction.*`，默认值和范围照 v3（滑块范围作为存储的上下限，位置、字体、头衔是选项）。
- 3.x 导入时这些键原来存在 `legacy_values`；注册以后，新导入直接读进设置，已经存在 `legacy_values` 里的由 `LegacyMigration.adoptLegacyValues` 接过来（录制启动时会跑，`localInteractionProvider` 创建时也跑一次，只处理一次）。
- v4 备份带上它们（`localInteraction` 一节，3.x 不认识这一节会忽略）；3.x 的备份本来就没有它们。
- 原有测试 `migration_test` 里“`localInteraction.coins` 留在 `legacy_values`”改成“读进设置”，原因：这次把这些键注册成设置了（EXTRA 要求照旧读写，不改键名）。

## emoji 字体（K4 A）

- `apps/pure_live/assets/fonts/emoji/NotoColorEmoji-Subset.ttf`（56 KB，设计用的 `emoji.woff2` 转成 TrueType，Noto Color Emoji 2.057 的 40 个 emoji，COLRv1）、`OFL.txt`（google/fonts 里 Noto Color Emoji 的 OFL 1.1 原文，没有保留字体名）、`NOTICE.txt`（来源说明）；`pubspec.yaml` 字体族 `PureLiveEmoji`，许可在第一次用到本地互动时登记到“许可”页。
- 用法：`localEmojiStyle` 把它放在回退字体的第一位，所以只有 emoji 用它，中文和数字照旧；`localEmojiText` 去掉子集里没有的 U+FE0F。
- **平台差异**：iOS、macOS 不用它（CoreText 不画 COLRv1），用系统 emoji。Android、Linux（FreeType）能画；**Windows 走 DirectWrite，COLRv1 要 Windows 11**，Windows 10 上可能是空白——请在 Windows 上看一眼面板里的礼物；如果有问题，把 `local_interaction_scope.dart` 的 `_bundledEmoji` 里加上 Windows 即可退回系统 emoji。测试环境（Linux）截图里彩色 emoji 正常。

## 门禁

- `check_ui_structure.py` 通过：`live_play` 直接写的颜色和图标仍是 **9**（新代码的图标全部走 `AppIcons`，颜色走主题角色、`OnVideoColors` 和数据里的整数色值），基线不用改；没有新增跨功能引用；`logic/` 三个文件都不引 material。
- `live_ui` 新增 `AppIcons` 18 个（全是 v3 在这些位置用的 Material 图标）和 `OnVideoColors` 6 个（输入框描边、预览台渐变及其图标和角标、横幅暗端和描边）。

## 新增的文字

中英各新增 12 条（`local_clear_history_short`、`local_danmaku_custom`、`local_danmaku_needs_fixed/shadow/stroke`、`local_danmaku_preset_default`、`local_danmaku_style_desc`、`local_group_interaction/on_video/profile_mine`、`local_history_count`、`local_overlay_off_hint`），改了 6 条已有文字（`local_message_hint`、`local_overlay_message`、`local_overlay_message_desc`、`local_gift_effects_desc`、`local_interaction_enable_desc`、`local_interaction_room_entry_desc`，照设计图）。其余都用 v3 已有的键。

## 测试

- `apps/pure_live/test/features/live_play/local_interaction_test.dart` 15 个：
  - 逻辑：资料库（6 个模板的值、12/7 种颜色、4 字体、3 位置、4 头衔、34 个资源包、8 个平台各 3 个礼物且各一个大特效、通用 4 个、等级、昵称规则）；3.x 键和默认值、发弹幕的名字和徽章、礼物扣币加经验和名字不重复、余额不够、加币、记录最多 30 条、改样式变自定义、恢复默认、写回 3.x 键。
  - 竖屏：输入框在最下面、星形 / 输入 / 发送的顺序和图标、提示文字、48 高；空的不发；发出即显示（“本地”标签、徽章胶囊、飞过）、没有提示；画面弹幕关着时只提示一次；总开关关着时没有输入框和菜单项；长按本地弹幕（复制“名字: 内容”、屏蔽关键词、没有屏蔽用户，附录 A 第 6 条）；菜单第三组和图标、面板在画面下方、标题栏、内容顺序、身份卡文字、余额不够变淡、币图标、“画面上”和记录、返回键先关面板（附录 A 第 7 条）；送礼（余额不足提示、横幅在画面中间、两行字、3 秒后消失）；关掉礼物特效没有横幅。
  - 样式：面板里的下一页有返回、预览不随滚动、各组顺序、默认状态的变灰和条件、打开阴影后可调、恢复默认、返回回到面板；星形直接打开没有返回。
  - 宽屏：输入框在聊天栏最下面、面板右侧 360 整高；画面上的输入框最宽 420、窄于 180 收成星形、焦点通知 `onHold`、发出、星形的输入行在下栏上方且发出后收起。
  - 设置页：五组顺序、入口说明在总开关下、体验币与等级、四个开关和样式的顺序、资源包切换预览、记录条数和清空、加币、进同一个样式面板、关掉总开关只剩第一组。
  - 飞过的本地弹幕：顶部固定的停留到时间再消失。
- 改了的原有测试：`live_play_popups_test` 右上角菜单的顺序加上第三组（原注释写“v4 还没有本地互动”）；`home_test` 路由表加 `/local_interaction`；`live_store` 的 `migration_test` 见上，`backup_test` 新增 1 个（接管 3.x 值、范围修正、备份带上）；`live_ui` 的图标对照表加 18 个。
- 结果：`apps/pure_live` 全部 293 个通过（这次之前 278 个）；`live_store` 33 个、`live_ui` 45 个通过；三处 analyze 无问题；`check_ui_structure.py` 通过。

## 没做的、留给别人的

- 全屏下栏里放输入框和四宫格菜单：U.2c（接口见上）。竖屏全屏下栏上方的一行：U.2b。
- 设置总览里的入口：U.6d。
- 本地礼物行在列表里没有长按菜单（v4 的礼物行本来就没有；v3 的礼物和弹幕是同一种卡片，可以长按）。
