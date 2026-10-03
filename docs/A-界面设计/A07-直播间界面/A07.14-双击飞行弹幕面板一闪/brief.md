# A07.14 双击飞行弹幕时弹幕面板会一闪再关上：任务书

## 背景

- 来源：A07.11 记录“需要维护者决定的”第 1 条（`docs/A-界面设计/A07-直播间界面/A07.11-直播间小问题合集/record.md`）。
- 现象：设置“点击画面弹幕”开着（默认开），在一条飞过的弹幕上快速点两下：弹幕面板从画面下方（横屏全屏时从右侧）滑出一截又滑回，飞行弹幕顿一下，然后才切全屏。复现：进一个弹幕多的直播间 → 等一条弹幕飞到画面中间 → 在它上面快速双击。竖屏、横屏全屏、竖屏全屏都能复现。
- 为什么做：第二档；双击全屏是高频操作（附录 A 第 3 条），3.x 和 4.0.0 双击弹幕都是直接全屏。
- 已经做过的：A07.11 c1（`df67f1147`）把单击改成立即响应，这个现象是它带出来的；A08.4（画面弹幕的点按和长按）；A07.12（弹幕面板 `RoomMessagePanel`）。

## 目标和验收

照 README“待选和决定”X1 的建议 A（维护者选 B 时本任务改“不做”，写进 DECISIONS）：

1. 点中飞行弹幕的单击：约 300 毫秒（`kDoubleTapTimeout`）后打开弹幕面板，内容和位置不变。
2. 在飞行弹幕上双击：只切全屏（或退出全屏），弹幕面板一帧也不出现，飞行弹幕不停顿。
3. 点在画面其他地方：控制层仍在同一帧显示或隐藏（A07.11 c1 不能退回）。
4. 长按飞行弹幕仍立即打开面板；控制条范围内仍不触发弹幕命中；锁定时不命中弹幕。
5. 改之前会失败的测试先写；全部测试和门禁通过。

## 现状（读代码得出，写文件:行）

`apps/pure_live/lib/features/live_play/` 省略前缀：

- `player/player_view.dart:653-656`：`onTapDown` 记下点中的弹幕 `_tapHit = _danmakuAt(...)`（`:416-438`，只在“点击画面弹幕”开着、控制条范围外、没锁定时命中，规则 `danmakuTapAllowed` `:830`）。
- `player/player_view.dart:333-366` 的 `_onTap`：
  - `:338-350`：双击窗口里、离第一下不远的第二下 → 调 `_undoTap`（撤销第一下）→ `widget.onToggleFullscreen()`；
  - `:353`：`hit != null ? _tapMessage(hit) : _tapControls()`——点中弹幕时**立即**打开面板；
  - `:357`：开 `_doubleTapWindow = Timer(kDoubleTapTimeout, _closeDoubleTap)`。
- `:389-398` 的 `_tapMessage`：`unawaited(_openMessage(message))`，返回“如果打开的还是这条消息的面板就关掉”的撤销。
- `:443-450` 的 `_openMessage`：设 `_danmakuHeld = true`（飞行弹幕停住），`await showRoomMessageActions(...)`（`danmaku/message_panel.dart:20`），关上后恢复。
- 面板动画：`live_play_page.dart:894-911` 的 `_panelLayer`（`AnimatedSwitcher`，进 220 毫秒、出 160 毫秒）。
- 根因：第一下点中弹幕就立即开面板，第二下靠“撤销”关面板，动画已经开始，所以看得见；同时 `_danmakuHeld` 来回切。

## 3.x 基线

- `git show v3.2.11:lib/modules/live_play/widgets/video_player/video_controller_panel.dart:196-249`：`onTap` 和 `onDoubleTap` 同时挂，单击等双击超时；`:213-215` 在 `onTap` 里才 `handleDanmakuPointer`；`:246-249` 双击切全屏。所以 3.x 单击弹幕慢 300 毫秒、双击弹幕直接全屏。
- 要保留的：双击全屏不带面板（3.x 的结果）；单击弹幕打开复制和屏蔽菜单（附录 A 第 6 条）；单击别处立即响应（4.x 的改进，A07.11）。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5、8、14 节）。
2. `docs/specs/ENGINEERING.md`；`docs/specs/UI.md` 附录 A 第 1～3、6 条。
3. 本文件夹的 `README.md`；`docs/A-界面设计/A07-直播间界面/A07.11-直播间小问题合集/README.md`（c1 的单击和双击）；`docs/A-界面设计/A07-直播间界面/README.md`（直播间结构）。

## 范围

- 可以改：`apps/pure_live/lib/features/live_play/player/player_view.dart`（`_onTap`、`_tapMessage` 附近）；`apps/pure_live/test/features/live_play/live_play_page_test.dart`（F.2b 组）；本文件夹。
- 不能改：控制层的单击规则（附录 A 第 1 条、D-012）；长按的行为；`danmaku/message_panel.dart` 的面板内容；`danmakuTapAllowed` 的范围；A07.15 要改的 `player/player_gestures.dart`；版本号、`assets/version.json`、`assets/releases.json`；签名配置；3.x 的设置键名和含义。

## 方案和阶段

| 阶段 | 做什么（对应 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | c1：`_onTap` 里 `hit != null` 时不立即调 `_tapMessage`，把这条消息记成“待打开”；`_closeDoubleTap` 在窗口自然结束（没有第二下）时打开它；第二下来了就清掉“待打开”、只切全屏（`_undoTap` 此时没有要撤销的面板）。没点中弹幕时照旧立即 `_tapControls()` | `player/player_view.dart`、`test/features/live_play/live_play_page_test.dart` | 验收 1～5；门禁通过 |

注意 `_closeDoubleTap` 现在在三处被调用（第二下、新的第一下之前、计时器到点），只有“计时器到点”这一种才打开面板；`dispose` 时清掉“待打开”。

## 测试

- 先改 `apps/pure_live/test/features/live_play/live_play_page_test.dart` 的“B09 c1: a tap opens the actions at once; a double tap takes them back for the fullscreen”（`:307`）：
  - 单击弹幕：`tester.tapAt(at)` 后 `pump()` 时还**没有** `live-play-message-sheet`；`pump(kDoubleTapTimeout)` 再 `pump(const Duration(seconds: 1))` 后有。
  - 双击弹幕：两下之间 `pump(const Duration(milliseconds: 100))`；之后每一帧都找不到 `live-play-message-sheet`（第二下前后各 `pump()` 一次检查），`AppBar` 消失（全屏），`overlay(tester).held` 一直是 `false`。
  - 改之前跑一次，确认会失败（现在第一下后面板立即出现）。
- 加一条：没点中弹幕的单击仍在同一帧显示控制层（`live_play_layouts_test.dart` 已有的 B09 c1 用例要照旧通过）。
- 测试里的等待用 `tester.pump`；不访问真实平台（`FakeDanmaku`）。
- 跑 `apps/pure_live` 的 `flutter analyze`、全部 `flutter test`、`dart format --output=none --set-exit-if-changed .`；`python3 tools/gate/check_ui_structure.py`。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 弹幕多的直播间，在一条飞过的弹幕上单击 | 约 0.3 秒后弹幕面板打开（复制、屏蔽此用户、屏蔽关键词） |
| 2. 在一条飞过的弹幕上快速双击 | 直接进全屏，面板没有出现、没有闪；弹幕不顿 |
| 3. 全屏里在弹幕上双击 | 直接退出全屏，没有面板 |
| 4. 在画面没有弹幕的地方单击 | 控制层立即出现或隐藏 |
| 5. 长按一条飞过的弹幕（“长按画面弹幕”开着） | 立即打开面板 |
| 6. 竖屏全屏重复 1、2 | 同上 |

## 风险和注意

- 和 A07.15 改的是相邻的代码（同在 `player/` 下的手势），依次做，不要同时开。
- 弹幕在 300 毫秒里会飞走：面板要用按下时记下的那条消息（`_tapHit`），不要在计时器到点时重新命中。
- 只点测试包；不碰 3.x（D-019）。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 分支 `ai/A07.14` 或本机工作区；提交信息以 `[A07.14]` 开头（英文）；不推 master。
- 提交前：`dart format --output=none --set-exit-if-changed .`、`flutter analyze`、全部 `flutter test`（`apps/pure_live`）；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”、更新登记表的 `next`、`branch`。

## 报告（中文，简洁）

X1 按哪个做的；每条验收做到没有；根因（文件:行）；测试数量（改之前失败的那条）；改了哪些文件；要在真机上看的；可能冲突的文件（`player/player_view.dart`）。
