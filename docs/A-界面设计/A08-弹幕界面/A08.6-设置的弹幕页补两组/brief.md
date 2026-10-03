# A08.6 设置的弹幕页补上“弹幕列表”“小窗弹幕”两组：任务书

## 背景

- 来源：[A08.5 记录](../A08.5-设置里的弹幕页/record.md)“偏差 1”和“需要维护者决定的”第 1 条（登记表 T06e.3）。A08.1 的 E1 定了“弹幕列表”“小窗弹幕”两组放在弹幕设置组件末尾、各处一样；A08.5 把设置里的“弹幕”行换成了直播间的组件，但这两组写在 `features/live_play/` 里，设置不能引用，所以设置页少了两组。
- 现象：直播间 → 弹幕设置（标签或画面上的面板）最后是“弹幕列表”“小窗弹幕”；设置 → 弹幕最后直接是“更多”，没有这两组。设置里也就改不了“弹幕列表样式”和“在聊天列表显示礼物”。
- 为什么现在做：第二档；同一个设置在两处不一样（[specs/UI.md](../../../specs/UI.md) 第 3 节第 6 条）。规模小。
- 已经做过的：A08.1（两组和它们的规则，`05793a4c8`）、A08.5（设置的弹幕页，`10bbcabe1`）。

## 目标和验收

1. 定稿（README 的待选 G1～G3，规模小可按 D-003 用建议 A）；登记表改“已确认”。
2. “弹幕列表”组（列表样式、显示礼物）和“小窗弹幕”组挪到 `apps/pure_live/lib/shared/danmaku/`，直播间的标签和画面面板照旧显示，样子、顺序、规则一个字不变。
3. 设置 → 弹幕：`DanmakuSettingsContent` 之后依次是“弹幕列表”“小窗弹幕”（G2 A：完整一组；G2 B：一行“小窗弹幕 ›”）、“更多”。
4. “在聊天列表显示礼物”（G1 A）是一个设置：在设置页改了，已经打开的直播间立即生效；老用户在 meta 里存的选择（`live_play.showGifts` = `0`）第一次启动后照旧是关。
5. （G3 A）设置的“小窗弹幕”页正文是同一个组件，说明和预览保留。
6. 测试和门禁通过；`tools/gate/ui_baseline.json` 不增加。

## 现状（读代码得出，写文件:行）

- 设置的弹幕页：`apps/pure_live/lib/features/settings/danmaku_page.dart`：`DanmakuSettingsPage`（`:32`），正文 `DanmakuSettingsContent(hint:, extra: [PanelGroupTitle(更多), _More()])`（`:60-63`）。
- 直播间：`apps/pure_live/lib/features/live_play/danmaku/danmaku_settings_panel.dart`：`RoomDanmakuSettings`（`:76`）在 `extra` 里放“弹幕列表”（`:97-130`：`SettingRow` + `SegmentedButton<ChatListStyle>` `:107-117`，键 `danmaku-list-style`；`ListenableSelector` 读 `controller.showGifts`，`SettingSwitchRow` 键 `gifts` `:118-128`）和“小窗弹幕”（`:131-132` → `PipDanmakuSettings` `:143`，14 个 `settingKey`：`pip`、`pipNoEmoji`、`pipAutoScale`、`pipOriginalColor`、`pipColor`、`pipFontSize`、`pipFontWeight`、`pipSpeed`、`pipOpacity`、`pipArea`、`pipMaxVisible`、`pipInterval`、`pipAutoFps`、`pipFps`，`:154-293`）。
- `ChatListStyle`：`features/live_play/danmaku/chat_list.dart:24`（`compact`、`card`，存在设置 `Settings.danmakuListStyle`，`packages/live_store/lib/src/settings/settings.dart:457`）；直播间的列表在 `chat_list.dart:394` 读它。
- 礼物开关：`features/live_play/logic/room_controller.dart`：`_showGifts`（`:179`）、`showGiftsKey = 'live_play.showGifts'`（`:189`）、进房时读 meta（`:317-319`）、`setShowGifts`（`:604-610`，关掉时 `chat.removeWhere` 去掉礼物行）、收到礼物时判断（`:909`）。meta（`packages/live_store/lib/src/live_store.dart` 的 `MetaStore`）只有 `get`/`set`，没有监听。
- 设置的“小窗弹幕”页：`features/settings/playback_tiles.dart:604` 的 `PipDanmakuPage`（说明 + 预览 `PipDanmakuPreviewBinding` + `SettingsSectionView(section: pipDanmaku)`），行来自 `features/settings/settings_catalog.dart:1085-1234`；颜色是 `PipColorTile`（`playback_tiles.dart:510`）。
- 门禁：`features/` 之间不能互相引用（`tools/gate/check_ui_structure.py`，基线 `tools/gate/ui_baseline.json` 只减不增）。

## 3.x 基线

- 3.x 没有设置里的弹幕页；小窗弹幕只有一个组件 `PipDanmakuSettingsSection`（`git show v3.2.11:lib/modules/settings/pages/pip_danmaku_settings_page.dart:153`），直播间标签（`lib/modules/live_play/pages/danmaku_settings_page.dart:416-418`）和设置的“小窗弹幕”页（`pip_danmaku_settings_page.dart` 的手机排法 `:104`、电脑排法 `:145`）都用它；“小窗显示弹幕”关闭时其余收起；默认值 `lib/common/services/settings/danmaku_settings_controller.dart:17-31`（A08.1 README 有逐项）。
- 3.x 没有“弹幕列表样式”“显示礼物”（4.x 的 A07.1、B-21）。
- 要保留：小窗弹幕 12 项的键名、默认值、范围（D-018）；直播间里两组的样子和规则（A08.1 c9、c10）。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 4.1 节、第 5 节、第 8 节、第 14 节）。
2. `docs/specs/ENGINEERING.md`（第 7 节：功能目录之间不互相引用）；`docs/specs/UI.md` 第 3 节第 6 条。
3. 本文件夹的 `README.md`；`docs/A-界面设计/A08-弹幕界面/A08.1-弹幕列表和弹幕设置页/README.md`（E1、c9、c10）；`docs/A-界面设计/A08-弹幕界面/A08.5-设置里的弹幕页/README.md`、`record.md`；`docs/A-界面设计/A11-设置界面/A11.3-播放/README.md`（c13、c14 小窗弹幕页）；`docs/specs/UPGRADES.md` 的 B-21。

## 范围

- 可以改：`apps/pure_live/lib/shared/danmaku/`（新文件放两组）；`features/live_play/danmaku/danmaku_settings_panel.dart`、`chat_list.dart`（`ChatListStyle` 挪走后改引用）、`features/live_play/logic/room_controller.dart`（礼物开关改读设置）；`features/settings/danmaku_page.dart`、（G3 A 时）`playback_tiles.dart`、`settings_catalog.dart`；`packages/live_store`（G1 A：只加一个设置和一次性接管 meta）；翻译文件（只在有新文字时）；对应测试；本文件夹。
- 不能改：两组的样子、顺序、范围、默认值（除非 G3 定了新顺序）；3.x 的设置键名和含义；`DanmakuSettingsContent` 本身；其他组的界面和逻辑；版本号、`assets/version.json`、`assets/releases.json`；签名配置。

## 方案和阶段

| 阶段 | 做什么（对应 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | 定稿：G1～G3（需要时出两张图：设置弹幕页长图、宽屏右栏） | README、（出图时）`src/`、`page.json` | README 写清结论；登记表“已确认” |
| 2 | c1：两组挪到 `shared/danmaku/`（例如 `chat_list_settings.dart`、`pip_danmaku_settings.dart`），`ChatListStyle` 一起挪；直播间改用它们；c3（G1 A）：礼物开关变成设置，`room_controller` 监听它，第一次读取接管 meta | `shared/danmaku/` 新文件、`danmaku_settings_panel.dart`、`chat_list.dart`、`room_controller.dart`、`live_store` 设置 | 直播间相关的现有测试（`live_play_tabs_test.dart` 第 300、338 行起两个用例、`live_play_more_page_test.dart` 第 247 行起的礼物用例）不改断言照样通过；新加“设置里改礼物开关，打开着的直播间立即去掉礼物行”的测试 |
| 3 | c2：设置的弹幕页加两组（G2）；c4（G3 A）：设置的“小窗弹幕”页换成同一组件 | `features/settings/danmaku_page.dart`、（G3）`playback_tiles.dart`、`settings_catalog.dart` | `settings_danmaku_test.dart` 第一个用例的顺序改为 `… 流畅度, 弹幕列表, 小窗弹幕, 更多`；新增竖屏 393×852 和 1280×800 右栏的布局测试；搜索“礼物”“小窗”能找到 |

每个阶段都要能单独合并（门禁通过、不留半截功能）。

## 测试

- 改之前会失败：`apps/pure_live/test/features/settings/settings_danmaku_test.dart` 加用例“设置 → 弹幕里有‘弹幕列表样式’和‘小窗显示弹幕’”（现在没有）。
- 加：礼物开关在设置页关掉后，已经打开的直播间（测试里先 pump 一个直播间再改设置）列表里的礼物行消失；meta 里存的 `live_play.showGifts = '0'` 第一次读取后设置为关；列表样式在设置页改成“卡片”后直播间列表用卡片（`live-play-chat-card`）。
- 界面：竖屏、宽屏（右栏、最宽 720）各一个布局测试；（G3 A）设置的“小窗弹幕”页顺序和直播间一致。
- 测试里的定时器至少 1 秒；不访问真实平台。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 设置 → 弹幕，滑到最后 | “流畅度”之后是“弹幕列表”“小窗弹幕”，最后“更多” |
| 2. 在这里把列表样式换成“卡片”、关掉“在聊天列表显示礼物”，进一个有礼物的哔哩哔哩直播间 | 聊天列表是卡片样式，没有礼物行 |
| 3. 直播间开着时（宽屏或应用内小窗），在设置里再打开礼物开关 | 直播间马上开始显示新的礼物行 |
| 4. 小窗弹幕：关掉“小窗显示弹幕” | 其余各项收起；进小窗时没有弹幕 |
| 5. 横屏或平板宽 ≥840 打开设置 → 弹幕 | 在右栏，内容不超过 720 宽 |

## 风险和注意

- `ChatListStyle` 挪到 `shared/` 后，`features/live_play` 里所有引用都要改（`chat_list.dart`、`danmaku_settings_panel.dart`、测试）；别留两份枚举。
- 礼物开关从 meta 改成设置时，老用户的选择要接过来；接管只做一次，接管后删掉 meta 那一项或不再读它（写清楚在哪做，和 `LegacyMigration` 不是一回事：这是 4.x 自己的 meta）。
- `PipDanmakuSettings` 的颜色行现在打开居中对话框（`showDanmakuColorDialog`）；A08.7 要改成展开的色板。两个任务改同一个文件，**先做 A08.6，再做 A08.7**（或者一起做）。
- 可能冲突的文件：`features/settings/danmaku_page.dart`、`settings_catalog.dart`、`playback_tiles.dart`（A04.1 改设置的高度分档）；`features/live_play/logic/room_controller.dart`（C01.4、E06.2 也改它）。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 效果图（需要时）：`tools/ui/mock/README.md`；`python3 tools/ui/mock/render.py docs/A-界面设计/A08-弹幕界面/A08.6-设置的弹幕页补两组/src/`。
- 分支 `ai/A08.6` 或本机工作区；提交信息以 `[A08.6]` 开头（英文）；不推 master。
- 提交前：改过的包（`apps/pure_live`，G1 A 时还有 `packages/live_store`）跑 `dart format --output=none --set-exit-if-changed .`、`flutter analyze`、`flutter test`；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”、更新登记表的 `done`、`next`、`branch`（登记表现在没有写阶段，开工时按上表补上）。

## 报告（中文，简洁）

G1～G3 的结论；每条做到没有；测试数量（改之前失败几个）；改了哪些文件；新设置和它的默认值、接管 meta 的方式；新翻译键；要在真机上看的；可能冲突的文件。
