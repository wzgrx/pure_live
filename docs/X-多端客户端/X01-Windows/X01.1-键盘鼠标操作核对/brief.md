# X01.1 键盘鼠标操作核对：任务书

## 背景

- 来源：清点。[specs/UI.md](../../../specs/UI.md) 第 5.4 节要求“v3 的快捷键全保留：空格和媒体键暂停、R 刷新、↑↓ 音量、Esc 依次关弹层、退全屏、返回”“右键等于长按；直播间滚轮调音量；控制层随鼠标移动显示、静止后隐藏；悬停显示按钮名称”，附录 A 第 13、14、16 条把它们列为必须保留的习惯。登记时的旧编号 T17b.1。
- 现象：读代码发现一处和 3.x 不同——在直播间普通状态（不全屏、没有面板）按 Esc，3.x 离开直播间，4.x 什么都不做（`apps/pure_live/lib/features/live_play/live_play_page.dart:662-673` 的 `_back()` 没有这一支）。其他项大多已经有代码，但没有在 Windows 上实际按过，也没有逐项的测试。
- 为什么现在做：第三档，等 Windows 开工（[D-004](../../../DECISIONS.md)）。前提是 [X01.3](../X01.3-Windows安装包和自动更新/README.md) 第一阶段让应用能在 Windows 上构建运行；第 1～2 阶段（读代码、写测试、修 Esc）不需要 Windows，可以提前做。
- 已经做过的：C01.1（`0249e830e`）加了直播间快捷键；A07.11 的 F.1d 加了媒体键；A16.1 加了标题栏按钮的名称和键盘焦点框。

## 目标和验收

1. 本文件夹 `README.md` 的对照表补全到每个页面：首页、热门、分区、分区房间、搜索、关注、历史、直播间（普通、全屏、窗口内全屏、宽屏分栏、桌面小窗）、多画面、录制中心、设置；每一项写 3.x 的文件:行、4.x 的文件:行、结论（一致 / 确认过的改动 / 缺）。
2. 直播间普通状态按 Esc 离开直播间（回到上一页）；全屏、窗口内全屏、面板、详情、桌面小窗时 Esc 的行为不变。
3. 3.x 有、4.x 缺的键鼠操作全部补上（只补 3.x 有的，不新增）。
4. 直播间的 F 键（3.x 没有）写进 README 的“需要维护者决定的”，不擅自删除。
5. 每个快捷键和鼠标操作都有 widget 测试（Windows 平台、1280×800），断言按键之后的结果。
6. 在 Windows 主机上按“真机验证”表逐条按过，结果写进 `verify.md`。

## 现状（读代码得出，写文件:行）

- 直播间快捷键：`apps/pure_live/lib/features/live_play/live_play_page.dart:737-753`（`CallbackShortcuts`）：Esc → `_back`、F → 全屏、空格 → `togglePlayPause`、↑↓ → `setVolume(±0.05, save: true)`、R → `controller.load()`、媒体键。`_back()`（`:662-673`）顺序：桌面小窗回直播间 → 关面板 → 退全屏 → 关详情；`_poppable`（`:639-640`）为真时没有动作——**根因线索**：3.x 显式 `Navigator.maybePop`，4.x 的 Esc 被 `CallbackShortcuts` 接住后没有交给返回。
- 鼠标：滚轮音量 `features/live_play/player/player_gestures.dart:223`；小窗滚轮 `features/live_play/mini/mini_player.dart:199`；悬停 `features/live_play/player/player_view.dart:798`（`onHover` → `_touch()`，`:399`）；右键 `packages/live_ui/lib/src/widgets/live_room_card.dart:129`、`:692`，`features/live_play/danmaku/chat_list.dart:615`、`:706`，`features/multiview/widgets/cell_view.dart:84`。
- 标签：`packages/live_ui/lib/src/widgets/scrollable_tab_bar.dart:145`（滚轮）；←→ 翻页 `features/favorite/favorite_page.dart:512`、`features/areas/platform_areas_view.dart:246`、`shared/rooms/room_grid.dart:585`；搜索平台行竖滚轮横向滚（`features/search/search_widgets.dart:83`，3.x 要按 Shift）。
- 多画面 Esc：`features/multiview/multiview_page.dart:380`。设置页查找：`features/settings/settings_page.dart:237-239`。
- 已有测试：`test/features/live_play/live_play_layouts_test.dart:309`、`:457`（Esc 退全屏、退窗口内全屏）、`test/features/live_play/room_extras_test.dart:466`（媒体键）；没有“普通状态 Esc 离开”的测试。

## 3.x 基线

- `git show v3.2.11:lib/modules/live_play/widgets/keyboard/video_keyboard.dart`：`:20-46` `_handleEscape`，`:55-80` 快捷键表，`:91-101` `resolveEscapePresentationAction`（画中画不管 → 全屏 → 窗口内全屏 → 返回）。
- `lib/modules/live_play/widgets/video_player/video_controller_panel.dart:952`（滚轮音量）、`lib/modules/live_play/widgets/layout/control_hover_region.dart:5`（悬停区）、`lib/common/widgets/scrollable_tab_bar.dart:92`、`:149`（标签滚轮）、`lib/common/base/base_page_view_extension.dart:10-15`（←→）、`lib/common/widgets/room_card.dart:1078`、`lib/modules/live_play/widgets/danmaku/danmaku_list_view.dart:501`、`lib/modules/multiview/multiview_page.dart:164`、`:984`。
- 要保留：附录 A 第 1 条（桌面单击只显示控制层）、第 3 条（双击全屏、全屏中先退出）、第 7 条（Esc 链）、第 13、14、16 条。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节分阶段、第 8 节合并审查、第 14 节规则）。
2. `docs/specs/ENGINEERING.md`；`docs/specs/UI.md` 第 5.4 节和附录 A。
3. 本文件夹的 `README.md`；`docs/A-界面设计/A16-桌面界面/A16.1-桌面窗口/README.md`（标题栏按钮的键盘焦点）；`apps/pure_live/lib/features/live_play/live_play_page.dart`（`_back`、`_poppable`、快捷键）；`apps/pure_live/test/features/live_play/live_play_layouts_test.dart`（怎么在测试里切桌面平台）。

## 范围

- 可以改：`apps/pure_live/lib/features/live_play/live_play_page.dart`（快捷键和 `_back`）；缺快捷键的页面文件（只加按键处理）；`packages/live_ui/lib/src/widgets/scrollable_tab_bar.dart`（只在滚轮行为和 3.x 不一致时）；`apps/pure_live/test/` 下对应的测试；本文件夹的文档。
- 不能改：其他组的界面和逻辑（直播间的布局、面板）；版本号、`assets/version.json`、`assets/releases.json`；签名配置；3.x 的设置键名和含义；Android 的返回（`PopScope`、预测返回手势，A07、O06 的）；不新增 3.x 没有的快捷键。

## 方案和阶段

| 阶段 | 做什么（对应 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | 列清单（c1）：每个页面的键鼠操作，3.x 和 4.x 对照；F 键的依据（c3） | 本文件夹 `README.md` | 表里每一项都有两边的文件:行和结论 |
| 2 | 修直播间 Esc（c2），补缺的操作（c4），每项加测试（c5） | `live_play_page.dart`、缺按键的页面、`test/features/**` | 改之前“普通状态 Esc 离开直播间”的测试失败、改之后通过；全部 `flutter test` 通过 |
| 3 | Windows 上实际按一遍（c6） | `verify.md` | 表里每一步都有结果；发现的问题修掉或开新任务 |

每个阶段都要能单独合并（门禁通过、不留半截功能）。第 1、2 阶段可以在 WSL 上做完先合并。

## 测试

- 修 bug：先写 `test/features/live_play/live_play_layouts_test.dart` 的新用例“Esc in the plain room leaves it (3.x VideoKeyboard)”：`platform: TargetPlatform.windows`、1280×800 打开直播间，`sendKeyEvent(LogicalKeyboardKey.escape)`，断言回到上一页；改之前失败。
- 要加的：直播间每个快捷键各一个断言（空格切换暂停、R 重新加载、↑↓ 房间音量 ±0.05 并保存、F 进出全屏、媒体键）；滚轮在画面上调音量、在小窗上调音量；鼠标悬停显示控制层、静止 N 秒后隐藏；房间卡片、聊天列表、多画面格子右键打开菜单；标签栏滚轮和 ←→。
- 桌面布局：Windows 1280×800、Linux 1280×800 各跑一遍（用现有测试的 `platform:` 参数）。
- 测试里的定时器至少 1 秒；不访问真实平台（用假的平台和 `fixtures/`）。

## 真机验证（维护者在 Windows 主机上做）

| 步骤 | 期望 |
|---|---|
| 1. 打开任意直播间（普通状态），按空格两次 | 暂停、继续；画面中间暂停时有 ▶ |
| 2. 按 ↑ 三次、↓ 一次 | 音量条显示，音量 +10%；离开再进同一直播间音量还在 |
| 3. 按 R | 重新加载当前线路 |
| 4. 按 F，再按 Esc | 进入全屏；Esc 退出全屏，留在直播间 |
| 5. 点窗口内全屏按钮，再按 Esc | 退出窗口内全屏 |
| 6. 普通状态按 Esc | 离开直播间回到上一页 |
| 7. 画面上滚动滚轮 | 音量跟着变 |
| 8. 鼠标在画面上移动，再停住不动 | 控制层出现，停住几秒后消失；鼠标停在控制条上时不消失 |
| 9. 关注页、分区页按 ←→ | 切换标签页 |
| 10. 首页标签栏上滚动滚轮 | 标签横向滚动 |
| 11. 房间卡片、聊天列表里的一条弹幕、多画面格子上点右键 | 分别打开卡片菜单、弹幕操作、格子菜单（和长按一样） |
| 12. 开着中文输入法时在直播间按空格 | 仍然暂停（输入法不吃掉空格） |
| 13. 用键盘 Tab 走一遍标题栏和直播间控制条 | 焦点框只在用键盘时出现，顺序和视觉一致 |

## 风险和注意

- `_back()` 也被 Android 的返回链用（`PopScope` 的 `onPopInvokedWithResult`，`live_play_page.dart:732-735`）：Esc 离开直播间要只在 Esc 的路径上 `maybePop`，不能让 Android 返回键在普通状态下返回两次。
- 文本输入框（本地弹幕输入、搜索框）有焦点时，空格、R、F、↑↓ 不能被直播间吃掉：核对 `CallbackShortcuts` 和输入框的焦点优先级。
- A07 组可能同时在改 `live_play_page.dart`（冲突文件）；开工前看 STATUS 里 A07 有没有在开发中的任务。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- Windows 主机：`C:\Users\123\claude-work\pure_live` 拉取分支，`C:\Users\123\claude-work\flutter\bin\flutter.bat build windows --release`（在 `apps\pure_live` 里），运行 `build\windows\x64\runner\Release\pure_live.exe`；PowerShell 里设备参数写全 `--device-id=windows`。不碰 `D:\Soft` 下的 3.x。
- 分支 `ai/X01.1` 或本机工作区；提交信息以 `[X01.1]` 开头（英文）；不推 master。
- 提交前：`apps/pure_live` 跑 `dart format --output=none --set-exit-if-changed .`、`flutter analyze`、全部 `flutter test`；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”（对照表做到哪个页面、哪些测试已加）、更新登记表的 `done`、`next`、`branch`。

## 报告（中文，简洁）

每条验收做到没有；Esc 的根因（文件:行）；对照表里“缺”的项和怎么补的；测试数量；改了哪些文件；F 键需要维护者决定；Windows 上按下来的结果；可能冲突的文件（`live_play_page.dart`）。
