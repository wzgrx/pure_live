# A07.14 双击飞行弹幕时弹幕面板会一闪再关上：记录

- 日期：2026-10-08
- 执行者：Claude
- 分支和提交：本机工作区，提交 `[A07.14]`
- 任务书：[brief.md](brief.md)；设计或说明：[README.md](README.md)

## 先核对：A08.9（D-038）之后还闪不闪

- A08.9 改了单击：控制层隐藏时第一下只显示控制层，不命中弹幕。所以控制层**隐藏**时双击弹幕已经不闪（第一下显示控制层，第二下撤销并切全屏）。
- 控制层**显示**时（刚点出控制层、刚进直播间、暂停以外的 4 秒内）第一下仍立即打开弹幕面板，第二下撤销关面板再切全屏——还闪，弹幕也顿一下。原有测试“B09 c1: a tap opens the actions at once; a double tap takes them back”就是在控制层显示时测的，证实还会闪。所以照做。

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| X1 | 选 A | 按 D-003 没有回复时用建议 A |
| c1 / 验收 1 | 做了 | 点中飞行弹幕（控制层显示、没暂停时）等 `kDoubleTapTimeout`（300 毫秒）没有第二下才打开面板；打开的是按下时命中的那条 |
| 验收 2 | 做了 | 双击弹幕只切全屏（或退出），面板一帧也不出现，弹幕不停 |
| 验收 3 | 做了 | 没点中弹幕的单击照旧同一帧显示或隐藏控制层（A07.11 c1、A08.9 不变） |
| c2 / 验收 4 | 做了 | 长按、控制条范围、锁定都没改 |
| 补充 | 做了 | 第一下点中弹幕后，300 毫秒内第二下点得远（超过 `kDoubleTapSlop`，不算双击）：先打开第一下那条，再按第二下处理（和 Flutter 的单击识别一致，不丢第一下） |

## 根因

- `apps/pure_live/lib/features/live_play/player/player_view.dart` `_onTap`（改前 `:376`）：点中弹幕时 `_tapMessage` 立即打开面板（`_openMessage` 同时定住弹幕），第二下靠撤销（改前 `:411-420` 的 `_tapMessage` 返回的关面板）关掉；面板进出有 220/160 毫秒动画（`live_play_page.dart` `_panelLayer`），第二下来时已经滑出一截。

## 改了哪些文件

- `apps/pure_live/lib/features/live_play/player/player_view.dart`：新字段 `_pendingMessage`（`:221-226`）；`_onTap` 点中弹幕时记下、开双击窗口，计时器到点调 `_openPendingMessage`（`:387-398`）；远处的第二下先打开待开的（`:375-379`）；`_closeDoubleTap` 清掉待开的（`:411`）；删掉 `_tapMessage`，换成 `_openPendingMessage`（`:434-439`）。
- 没动：控制层的单击规则、长按、`message_panel.dart`、`danmakuTapAllowed`、`player_gestures.dart`。

## 新设置、翻译键、门禁基线

- 无。

## 测试

- 改了 1 个：`apps/pure_live/test/features/live_play/live_play_page_test.dart` 的“B09 c1: a tap opens the actions at once…”改成“A07.14: a tap opens the actions once a double tap is ruled out; a double tap only toggles”：单击弹幕后下一帧没有面板、300 毫秒后有且弹幕停住；双击时第二下前后和之后 1 秒每 100 毫秒都没有面板、弹幕一直没停、进了全屏。**改之前失败**（第一下后面板立即出现）。
- 原有的 A08.9（控制层隐藏时只显示控制层、暂停时只切控制层）、长按、`live_play_layouts_test.dart` 的 B09 c1（别处单击同一帧）都照旧通过。
- 全部通过：`apps/pure_live` 全量 902 个。

## 真机上要看的

| 步骤 | 期望 |
|---|---|
| 1. 弹幕多的直播间，控制层显示时在一条飞过的弹幕上单击 | 约 0.3 秒后弹幕面板打开（复制、屏蔽此用户、屏蔽关键词） |
| 2. 控制层显示时在一条飞过的弹幕上快速双击 | 直接进全屏，面板没有出现、没有闪；弹幕不顿 |
| 3. 全屏里在弹幕上双击 | 直接退出全屏，没有面板 |
| 4. 在画面没有弹幕的地方单击 | 控制层立即出现或隐藏 |
| 5. 长按一条飞过的弹幕（“长按画面弹幕”开着） | 立即打开面板 |
| 6. 竖屏全屏重复 1、2 | 同上 |
