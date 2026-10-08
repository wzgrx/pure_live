# A07.22 应用内小窗拖角改大小、两指缩放，设置里加“小窗大小”（接 V01.5）：记录

- 日期：2026-10-09
- 执行者：Claude（本机工作区，没有推送、没有合并）
- 分支和提交：工作区分支 `worktree-agent-a5b9f0161f6b72a30`，提交 `[A07.22] …`
- 任务书：[brief.md](brief.md)；说明：[README.md](README.md)；评估和设计：[V01.5 README](../../../V-需求和反馈/V01-新功能提议/V01.5-小窗拖角改尺寸/README.md)“评估结论和设计”S1～S13

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| 1 把手 | 做了 | 在朝屏幕中间的那个下角（`inAppMiniGripCorner`），和按钮一起出现，拖着时按钮不消失。**偏差**：只看左右移动（`inAppMiniGripExtent`），不是上游的“取移动多的方向”：小窗贴着底边时用户往左上方拉，竖直方向算“往里推”会越拉越小（V01.5 S4） |
| 2 两指 | 做了 | 画面的手势换成缩放识别器，一根手指照旧拖动位置。按钮显示的 3 秒里两指要按在按钮以外 |
| 3 范围 | 做了 | `inAppMiniScale`：长边 160～短边 × 0.9、竖屏画面宽 ≥ 120、不出可用区域；档位本身的大小总是允许 |
| 4 记住 | 做了 | 横屏画面、竖屏画面各一个倍数设置；松手时写入 |
| 5 设置 | 做了 | `MiniWindowSizeTile`：三档、默认“中”、拖过显示“自定义”、选一档清掉两个倍数、“离开直播间时小窗播放”关着时变灰；搜索能找到 |
| 6 不重建播放器 | 做了 | 只改 `Positioned` 的大小和位置；测试断言引擎和打开次数都是 1 |
| 7 默认不变 | 做了 | `inAppMiniWindowSize` 在倍数 1、“中”时直接返回 `inAppMiniSize`；原有 A07.8 的大小、位置用例一行没改照样通过 |

## 根因

- 不是 bug（新功能，3.x 没有）。改之前的大小只由屏幕决定：`apps/pure_live/lib/features/live_play/logic/mini_window.dart` 的 `inAppMiniBase`、`inAppMiniSize`；`floating_window.dart` 只记拖过的位置；画面手势只有拖动（`mini_player.dart` 的 `onPan*`）。

## 改了哪些文件

- `apps/pure_live/lib/features/live_play/logic/mini_window.dart`：`inAppMiniSize` 加 `factor`；新 `inAppMiniSizes`、`inAppMiniMinExtent`、`inAppMiniMaxFraction`、`inAppMiniMinPortraitWidth`、`inAppMiniPortrait`、`inAppMiniRoom`、`inAppMiniScale`、`inAppMiniWindowSize`、`MiniGripCorner`、`inAppMiniGripCorner`、`inAppMiniGripExtent`、`MiniResizeAnchor`、`inAppMiniResizedOffset`。
- `apps/pure_live/lib/features/live_play/mini/mini_player.dart`：`MiniPlayerSurface` 的缩放手势和把手 `_ResizeGrip`。
- `apps/pure_live/lib/features/live_play/mini/floating_window.dart`：读设置算大小、改大小的状态、松手写入。
- `apps/pure_live/lib/features/settings/playback_tiles.dart`（`MiniWindowSizeTile`）、`settings_catalog.dart`（`float_window_size`）。
- `packages/live_store/lib/src/settings/settings.dart`：三个新设置。
- `packages/live_ui/lib/src/icons/app_icons.dart`：`miniResizeBottomLeft`、`miniResizeBottomRight`、`settingsMiniSize`。
- `apps/pure_live/assets/translations/zh.json`、`en.json`。
- `docs/inventory/OWNERS.toml`（三个键归 C02，和 `floatPlay` 一样）及生成的 `OWNERS.md`；`tools/docs/settings_audit_notes.py` 及重新生成的 J01.2 `settings.md`（224 个设置）。
- 文档：本文件夹；V01.5 的 README（评估结论和设计）、brief；V01 说明；`docs/tasks.toml`。

## 新设置、翻译键、门禁基线

- 新设置（都在 `player` 一节，跟备份和设备同步；3.x 没有这些键）：
  - `floatWindowSize`：`small` / `medium` / `large`，默认 `medium`（= 原来的大小），别的值读成 `medium`。
  - `floatWindowLandscapeScale`、`floatWindowPortraitScale`：默认 1（没拖过），0.25～4。
- 翻译键（zh、en 都加，按键名排序）：`mini_window_resize`（拖动调整小窗大小）、`mini_window_size`（小窗大小）、`mini_window_size_custom`（自定义）、`mini_window_size_custom_hint`、`mini_window_size_default`（默认）、`mini_window_size_desc`、`mini_window_size_large`（大）、`mini_window_size_medium`（中）、`mini_window_size_small`（小）。
- 门禁基线不变。

## 测试

- 新增 9 个用例，改了 2 个：
  - `apps/pure_live/test/features/live_play/live_play_mini_window_test.dart` 新增 5 个：
    - 规则“三档是 c6 的 0.8、1、1.25 倍；‘中’没拖过和 c6 一模一样”（手机 176、220、275，平板“大”450；竖屏画面宽至少 120；不认识的档按“中”）。
    - 规则“拖过的倍数限在长边 160～短边 × 0.9、竖屏宽 120、可用区域内；档位本身不被裁”。
    - 规则“把手在朝中间的下角；只看左右，往外变大；往左上方拉也变大；锚点是把手对面的上角，两指是中心”。
    - 组件“拖左下角把手往左 80：300 宽，右边和底边不动；按住时按钮不消失；同一个播放器、没有重新打开；弹幕字号跟着变成 12 × 300 / 350；横屏倍数存进设置、竖屏的不变；从角落长大的仍是角落里的小窗，转成横屏后在新的右下角（改之前松手一律记成拖过的位置，转屏后停在原处，这一条会失败）；关掉再离开直播间还是 300 宽”。
    - 组件“两指张开：以中心为准变大、在屏幕内、不是单击；横屏倍数存进设置；竖屏画面的小窗还是 264 高（各记一份）；设置里换成‘小’并清掉倍数后 176 宽”。
  - `apps/pure_live/test/features/settings/settings_playback_test.dart` 新增 1 个、改 2 个：新增“‘小窗大小’默认‘中’，开关关着时变灰；选‘大’；拖过显示‘自定义’、弹窗有提示、选一档清掉两个倍数；搜索能找到”；视频页的行顺序（手机、电脑）和图标表加了这一行。
  - `packages/live_store/test/float_window_size_test.dart`（新文件）2 个：默认值、三档、范围、`player` 一节；备份往返，3.x 的备份没有它们时保持默认。
  - `packages/live_store/test/settings_defaults_test.dart`：`newInV4` 加 3 行，`ranges` 加 2 行。
- 默认值下行为不变的证据：A07.8 的应用内小窗用例（大小、位置、拖动、单击、鼠标双击、竖屏画面 149×264）一行没改照样通过。
- 门禁：见下一节。

## 门禁

- （提交后跑 `bash tools/gate/gate.sh --all`，结果补在这里）

## 真机上要看的

K90（`com.mystyle.purelive.v4dev`，每次点按前确认前台是测试包），逐条见 [verify.md](verify.md)，要点：

1. 覆盖安装后不改设置：离开直播间的小窗大小、位置和以前一样（约 220 宽，右下角、导航栏上面）。
2. 点一下出按钮，左下角有圆底箭头把手；按住往左（或左上方）拉，小窗跟手变大、右边和底边不动、画面不黑不重新缓冲；往右推变小；只上下拖不变。
3. 两指在画面上张开、捏合改大小；一根手指照旧拖动位置，单击照旧出按钮、再点回直播间。
4. 拉大以后小窗弹幕跟着变大、不出边；拉到最大（约 354 宽）时看弹幕是否比直播间里的还大、是否舒服（V01.5 S11，决定要不要跟上游钳回 1 倍）。
5. 关掉小窗再离开直播间：还是上次的大小；竖屏直播的小窗是自己的大小。
6. 设置 → 播放 →“小窗大小”：拖过显示“自定义”；选“大”约 275 宽、选“小”约 176 宽，拖过的大小清掉。
7. 横屏拿手机、旋转屏幕：小窗不出屏幕。
