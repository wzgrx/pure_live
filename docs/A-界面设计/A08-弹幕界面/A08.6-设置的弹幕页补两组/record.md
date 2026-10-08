# A08.6 设置的弹幕页补上“弹幕列表”“小窗弹幕”两组：记录

- 日期：2026-10-08
- 执行者：Claude（本机工作区，没有推送）
- 分支和提交：本机工作区分支，提交 `[A08.6] …`
- 任务书：[brief.md](brief.md)；设计或说明：[README.md](README.md)（G1～G3 都用建议 A，G3 的顺序取 3.x 的，见 README“结论”）

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| c1 | 做了 | 两组挪到 `shared/danmaku/`：`chat_list_settings.dart`（`ChatListStyle` 一起挪，只剩这一份；`ChatListSettings`；`danmakuListAndPipGroups()` 给出两组和它们的标题）、`pip_danmaku_settings.dart`（`PipDanmakuSettings` 原样搬过来）。直播间的 `RoomDanmakuSettings` 改成用它们，样子、顺序、规则不变（已有测试没改断言照样通过） |
| c2 | 做了 | 设置 → 弹幕：`DanmakuSettingsContent` 之后依次是“弹幕列表”“小窗弹幕”“更多”（G2 A：完整一组）；搜索里加了“弹幕 › 弹幕列表”的两行（列表样式、显示礼物） |
| c3 | 做了 | G1 A：新设置 `showChatGifts`（`danmaku` 一节、默认开、随备份走）；直播间控制器 `showGifts` 读设置，并监听它：在设置里关掉，已打开的直播间马上去掉礼物行、不再收新的礼物行；打开后新的礼物行照常出现 |
| c4 | 做了 | G3 A：设置的“小窗弹幕”页正文换成同一个 `PipDanmakuSettings`，上面的说明和预览、宽屏左预览右设置都保留；末尾保留这一页自己的“恢复默认”。顺序是 3.x 的（A08.1 c9），所以直播间不变，设置页从 A11.3 c14 的分组变成 3.x 顺序 |
| c5 | 保留 | 两组的内容、范围、单位、变灰和收起规则不变 |

## 根因

- 两组写在 `features/live_play/danmaku/danmaku_settings_panel.dart`（`RoomDanmakuSettings` 的 `extra`、`PipDanmakuSettings`），`features/settings` 按门禁不能引用别的功能目录；`ChatListStyle` 也在 `features/live_play/danmaku/chat_list.dart:24`。
- “在聊天列表显示礼物”是直播间控制器存在 meta 的 `live_play.showGifts`（`room_controller.dart:207`），进房时读一次（`:336`），没有监听，设置页改不了也通知不到打开着的直播间。

## 改了哪些文件

- `packages/live_store/lib/src/settings/settings.dart`（`showChatGifts`，加进 `Settings.all`）、`lib/src/live_store.dart`（`legacyShowGiftsKey`、`_adoptGiftSwitch`：打开存储时接管一次）
- `apps/pure_live/lib/shared/danmaku/chat_list_settings.dart`（新）、`pip_danmaku_settings.dart`（新）
- `apps/pure_live/lib/features/live_play/danmaku/danmaku_settings_panel.dart`、`chat_list.dart`、`logic/room_controller.dart`
- `apps/pure_live/lib/features/settings/danmaku_page.dart`、`playback_tiles.dart`（`PipDanmakuPage` 正文、去掉不再用的 `highlight`）、`settings_section_view.dart`、`settings_catalog.dart`（搜索行）
- 测试：`packages/live_store/test/chat_gifts_test.dart`（新）；`apps/pure_live/test/features/settings/settings_danmaku_test.dart`、`settings_playback_test.dart`、`test/features/live_play/live_play_more_test.dart`、`live_play_more_page_test.dart`

## 新设置、翻译键、门禁基线

- 新设置：`showChatGifts`（布尔，默认 `true`，`danmaku` 一节，随备份走）。接管：`LiveStore` 打开时（和 `_upgradeThemeColor` 同一处）读 meta `live_play.showGifts`：是 `0` 且还没有存这个设置时写成关；不管是什么都删掉这条 meta，所以只做一次，之后不再读。
- 新翻译键：无（都用已有的键）。
- 门禁基线：`tools/gate/ui_baseline.json` 没变。

## 测试

- 新增 6 个：`chat_gifts_test.dart` 3 个（默认值和备份、meta 的 `0` 接管一次后删掉、`1` 只删 meta）；`settings_danmaku_test.dart` 2 个（两组在页上，列表样式、礼物、小窗开关都写同一个设置，关小窗其余收起；竖屏 393×852 滑到两组在“更多”之前）；`live_play_more_test.dart` 1 个（设置在别处改了，打开着的直播间马上去掉 / 恢复礼物行）。
- 改了 6 个：`settings_danmaku_test.dart` 第一个用例的顺序加上“弹幕列表、小窗弹幕”，搜索用例加“礼物”“列表样式”；`settings_playback_test.dart` 小窗弹幕页 3 个用例改成同一个组件的键和 3.x 顺序（“恢复默认”仍在最后）；两个礼物用例的“记住了”从查 meta 改成查设置（存储方式本身改了）。
- 改之前失败：app 10 个（含上面改的断言）、live_store 3 个（编译不过）。
- 全部通过：`packages/live_store` 全部、`apps/pure_live` 全部 `flutter test`；`dart analyze --fatal-infos`、格式、`check_ui_structure.py`、`docs.py --check`。

## 真机上要看的

1. 设置 → 弹幕，滑到最后：“流畅度”之后是“弹幕列表”“小窗弹幕”，最后“更多”。
2. 在这里把列表样式换成“卡片”、关掉“在聊天列表显示礼物”，进一个有礼物的哔哩哔哩直播间：聊天列表是卡片样式，没有礼物行。
3. 直播间开着时（宽屏旁边或应用内小窗），在设置里打开礼物开关：直播间马上开始显示新的礼物行。
4. 小窗弹幕：关掉“小窗显示弹幕”，其余各项收起；进小窗时没有弹幕。
5. 横屏或平板宽 ≥840 打开设置 → 弹幕：在右栏，内容不超过 720 宽。
6. 设置 → 小窗弹幕：上面说明和预览照旧，下面各项和直播间“弹幕设置”里的“小窗弹幕”一组完全一样（3.x 顺序），最后“恢复默认”。
7. 老用户：之前在直播间关过礼物开关的，升级后第一次打开设置 → 弹幕，礼物开关是关的。

## 可能和别的任务冲突的文件

- `features/live_play/logic/room_controller.dart`（C01.4、E06.2 也改它）；`features/settings/playback_tiles.dart`、`settings_catalog.dart`（A04.1）；`shared/danmaku/pip_danmaku_settings.dart`（A08.7 接着改颜色行）。
