# A07.22 应用内小窗拖角改大小、两指缩放，设置里加“小窗大小”（接 V01.5）：任务书

## 背景

- 来源：新功能提议 V01.5（D-036 同意做）；上游 pure_live `f9e03f446`（右下角把手改大小）、`e437b5bd8`、`dc7298500`、`a25facd94`（按直播流方向各记一套），media_core `7319d2d`、`c073f52`（四边四角、看不见的触控区）。
- 现象：离开直播间后的应用内小窗手机上固定 220 宽，看不清也改不了；只能回直播间。
- 为什么现在做：第三档；D-036 路线的第四个（同屏条数 → 按住停住 → 同步选内容 → 小窗尺寸）。
- 已经做过的：V01.5 的评估和设计（`docs/V-需求和反馈/V01-新功能提议/V01.5-小窗拖角改尺寸/README.md`“评估结论和设计”S1～S13，维护者按 D-003 选）；A07.8（小窗的按钮、大小、位置）；D03.3（小窗弹幕按窗口宽度缩放，上限 2 倍）。

## 目标和验收

1. 应用内小窗朝屏幕中间的那个下角有把手（和按钮一起出现，48 触控），往外拉变大、往里推变小（只看左右），画面比例不变，把手对面的上角不动，一直在屏幕里。
2. 两指在画面上捏合、张开改大小（中心不动）；一根手指仍然拖动位置，单击、双击、鼠标悬停照旧。
3. 大小范围：长边 160～屏幕短边 × 0.9，竖屏画面宽不小于 120，不超出小窗能用的区域；“小窗大小”那一档自己的大小总是允许。
4. 改过的大小记住（横屏画面、竖屏画面各一份，存相对档位的倍数），下次出来还是这么大。
5. 设置 → 播放 →“小窗”组加“小窗大小”（小、中、大 = 0.8、1、1.25 倍），默认“中”= 原来的大小；拖过显示“自定义”；选一档清掉拖过的大小；“离开直播间时小窗播放”关着时变灰。
6. 改大小时播放器不重建、画面不透明；小窗弹幕跟着窗口宽度变（D03.3 的规则）。
7. 默认值下（没拖过、“中”）大小和位置和改之前一模一样。

## 现状（读代码得出）

- `apps/pure_live/lib/features/live_play/logic/mini_window.dart`：`inAppMiniBase`（短边 × 0.56，220～360）、`inAppMiniSize`（竖屏画面 1.2 倍高、宽至少 120）、`inAppMiniOffset`（默认右下角，始终在屏幕内）。
- `apps/pure_live/lib/features/live_play/mini/floating_window.dart`：`_FloatingWindowState` 只记拖过的位置 `_dragged`。
- `apps/pure_live/lib/features/live_play/mini/mini_player.dart`：`MiniPlayerSurface` 的画面 `GestureDetector` 用 `onTapUp` 和 `onPan*`；按钮层在它上面，隐藏时 `IgnorePointer`。

## 3.x 基线

- `git show v3.2.11:lib/player/core/player_manager.dart` 的 `:4737` `resolveAppFloatingSize`：大小固定，不能拖角，没有设置。要保留：A07.8 确认过的按钮、点按和拖动的手势、默认大小和位置。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`。
2. `docs/specs/ENGINEERING.md`；`docs/specs/UI.md` 附录 A 第 8 条。
3. V01.5 的 README（整份，尤其 S2～S10）；`docs/A-界面设计/A07-直播间界面/A07.8-小窗/README.md` 的 c2、c6、c10。

## 范围

- 可以改：上面三个文件；`apps/pure_live/lib/features/settings/playback_tiles.dart`、`settings_catalog.dart`；`packages/live_store/lib/src/settings/settings.dart`；`packages/live_ui/lib/src/icons/app_icons.dart`；翻译文件；对应测试；`docs/inventory/OWNERS.toml`、`tools/docs/settings_audit_notes.py` 和它们生成的文件。
- 不能改：系统画中画（`room_mini_window.dart`）、桌面小窗（`app/desktop/`）；小窗弹幕的规则（D03.3）；3.x 的设置键；版本号。

## 方案和阶段

| 阶段 | 做什么 | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | 大小规则、把手、两指、记住、设置行（一次合并，用户才看得到完整的功能） | 见“范围” | 测试和门禁通过；`record.md` 写好 |

## 测试

- `apps/pure_live/test/features/live_play/live_play_mini_window_test.dart`：三档和默认、范围、把手的角和方向、锚点（规则）；拖把手、两指、记住、横竖分开、档位清掉拖过的大小（组件）；原有的 A07.8 用例不改照样通过。
- `apps/pure_live/test/features/settings/settings_playback_test.dart`：设置行的位置、图标、变灰、“自定义”、选一档清掉倍数、搜索。
- `packages/live_store/test/float_window_size_test.dart`、`settings_defaults_test.dart`：默认值、范围、备份。

## 真机验证（维护者在 K90 上做）

见 [verify.md](verify.md)。

## 风险和注意

- 画面的手势从拖动识别器换成缩放识别器：一根手指的拖动、单击、双击（鼠标）都要照旧；原有用例守着。
- 把手只在按钮显示时能用；按钮显示时两指按在按钮上不会缩放。

## 环境和提交

- `source ~/tools/purelive-env.sh`；新工作区先 `bash tools/ffmpeg_kit/fetch.sh android`、`linux`。
- 提交信息以 `[A07.22]` 开头（英文）；不推 master。

## 报告（中文，简洁）

每条做到没有；测试数量；改了哪些文件；新设置和翻译键；真机上要看的；可能冲突的文件。
