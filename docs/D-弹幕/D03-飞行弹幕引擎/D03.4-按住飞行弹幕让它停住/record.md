# D03.4 按住飞行弹幕让它停住，松手继续（接 V01.3）：记录

- 日期：2026-10-08
- 执行者：Claude（本机工作区，没有推送、没有合并）
- 分支和提交：工作区分支 `worktree-agent-aa1803a92d92a655e`，提交 `[D03.4] …`（在 `[D05.2]` 之后）
- 任务书：[brief.md](brief.md)；说明：[README.md](README.md)；设计和手势冲突分析：[V01.3 README](../../../V-需求和反馈/V01-新功能提议/V01.3-按住弹幕让它停住/README.md)“评估结论和设计”

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| 1 弹幕层钉住一条 | 做了 | `pinAt`、`unpin`、`pinnedMessage`；`_Flying._pinnedAt`，放开时 `start` 往后挪钉住的时长；钉住的最后画；它那条轨道（平台弹幕的滚动轨道）钉着时 `_place` 跳过；放开后移到列表末尾 |
| 2 开关默认关 | 做了 | `Settings.holdDanmakuOnPress`，`false`；关着时 `_onPointerDown` 第一行就返回，弹幕层不会被钉 |
| 3 按下钉、抬手放 | 做了 | 画面 `GestureDetector` 外包 `Listener`：按下 `pinAt`；同一根手指抬起、取消、移动超过 `kTouchSlop` 时 `unpin`；锁定、显示着的上下栏不钉（和点按同一个 `_flyingPoint`） |
| 4 单击、双击、长按不变 | 做了 | 这三个回调没改；`_danmakuAt` 只是把锁定和区域判断拆成 `_flyingPoint` 共用 |
| 5 设置界面和翻译 | 做了 | “画面弹幕交互”组第三个开关（`holdOnPress`），带说明；搜索条目 `danmaku_hold_on_press`；2 个翻译键 |

## 根因

- 不是 bug。改之前长按要按 500 毫秒，这期间按的那一条已经飞走约 60 像素（速度 120 像素/秒），长按点到的常常不是它；钉住以后长按正好点中按住的那一条。

## 改了哪些文件

- `apps/pure_live/lib/shared/danmaku/danmaku_overlay.dart`
- `apps/pure_live/lib/features/live_play/player/player_view.dart`
- `apps/pure_live/lib/shared/danmaku/danmaku_settings_content.dart`、`apps/pure_live/lib/features/settings/settings_catalog.dart`
- `packages/live_store/lib/src/settings/settings.dart`
- `apps/pure_live/assets/translations/zh.json`、`en.json`
- `docs/inventory/OWNERS.toml`（`holdDanmakuOnPress` 归 A08，和点按、长按开关一样）、`tools/docs/settings_audit_notes.py`；重新生成 J01.2 的 `settings.md`（221 个设置）
- 测试：见下

## 新设置、翻译键、门禁基线

- 新设置：`holdDanmakuOnPress`（`danmaku` 一节，默认 `false`，跟备份和设备同步；3.x 没有这个键）。
- 翻译键：`danmaku_hold_on_press`（按住飞行弹幕让它停住）、`danmaku_hold_on_press_desc`（手指按住画面上的一条弹幕时只停住这一条，其他照飞，松手继续）。
- 门禁基线不变。

## 测试

- 新增 5 个用例，改了 4 个：
  - `apps/pure_live/test/shared/danmaku_overlay_test.dart` 新增 2 个：“钉住的那一条 2 秒不动、另一条照飞 240 像素、`messageAt` 还找得到它；放开后 0.5 秒走 60 像素；整层停住时钉住再放开不跳；撤回后不再钉着”；“只有一条轨道时钉着它，新弹幕等 2 秒也不进（不钉时 1 秒后就能进），放开后马上进”。
  - `apps/pure_live/test/features/live_play/live_play_page_test.dart` 新增 2 个：“默认关：按住 0.3 秒它照飞”；“开了：按住它不动、别的照飞、整层不停；抬手后不再钉着，单击照旧在等双击时间过后打开它的面板，关面板后它接着飞；长按打开面板、整层停住，抬手后不再钉着；从它上面拖 40 像素就放开；双击只切全屏、面板不出”。
  - `apps/pure_live/test/features/live_play/live_play_popups_test.dart`：弹幕设置面板的逐项标题表加了这一行；在“长按”下面、有说明、默认关、点了存进设置。
  - `apps/pure_live/test/features/settings/settings_danmaku_test.dart` 新增 1 个：设置 → 弹幕有这个开关，点了是设置；搜索“按住”在“弹幕 › 画面弹幕交互”下。
  - `packages/live_store/test/danmaku_new_settings_test.dart`（D05.2 加的文件改了名，原来叫 `danmaku_on_screen_test.dart`）加 1 个：默认关、`danmaku` 一节、跟备份往返、3.x 备份没有它时保持关；`settings_defaults_test.dart` 的 `newInV4` 加一行。
- 默认值下行为不变的证据：原来的 F.2b、A07.14、A08.9 的手势用例（单击、双击、长按、暂停时单击）一行没改照样通过；新的“默认关”用例。
- 测试里遇到的坑：同一个用户的同一句话 2.5 秒（真实时间）内只过一次（`DanmakuMessageGate` 的去重），所以“开了”那个用例每次 `fly` 用不同的用户名。
- 门禁：`bash tools/gate/gate.sh --all`，结果见下一节。

## 门禁

- 2026-10-08 本机 `bash tools/gate/gate.sh --all`（D05.2 和 D03.4 两个提交的内容一起）：`gate: passed`。第一次跑时 `apps/pure_live analyze` 报了一条 `avoid_escaping_inner_quotes`（本任务新加的测试名），改成双引号后重跑通过。

## 真机上要看的

K90（`com.mystyle.purelive.v4dev`，每次点按前确认前台是测试包）：

1. 覆盖安装后先不改设置，进一个弹幕多的直播间（哔哩哔哩或斗鱼热门），手指按住一条飞过的弹幕 1 秒：它照常飞走（和装这个版本之前一样）。
2. 点画面调出控制层 → 点“弹幕设置”按钮 → “画面弹幕交互”一组：在“长按画面弹幕打开屏蔽操作”下面有“按住飞行弹幕让它停住”，下面一行说明，开关是关的。把它打开，关掉面板。
3. 竖屏（不全屏）：手指按住一条正在飞的长弹幕 2 秒：它停在手指下，其他弹幕照常从右往左飞（同一行后面的会从它下面穿过去，它在上面、看得清）；松手：它从停住的地方接着往左飞，不跳。
4. 按住一条弹幕不放，直到弹出长按面板：面板里是按住的那一条（看用户名和内容），画面上所有弹幕都停住；关掉面板后都接着飞。
5. 控制层显示时单击一条弹幕：照旧打开它的操作面板（D-038）；控制层隐藏时单击：只调出控制层，不开面板。
6. 在一条弹幕上快速双击：只切换全屏，面板一帧都不出；全屏里再双击退出全屏。
7. 横屏全屏里重复第 3、4 步；在一条弹幕上按住后上下拖（调亮度或音量）：拖动照常，那条弹幕一拖就接着飞。
8. 控制层显示时按住上栏或下栏里的弹幕位置：不钉（按的是栏）；锁定画面后按住弹幕：不钉。
9. 设置 → 弹幕 →“画面弹幕交互”：同一个开关是开的；设置页搜索“按住”能搜到。把开关关掉，回到第 1 步的行为。
