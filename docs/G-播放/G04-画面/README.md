# G04 画面

播放器对“这路画面是什么形状”的判断：解码后的宽高和旋转、第一帧之前平台声明的宽高（竖屏预判）、横竖的识别和每个房间的方向选择，以及画面缩放方式（`videoFitIndex`）这个设置的取值。这些判断决定直播间用竖屏布局还是普通布局、小窗和画中画多大。

## 范围

- 包括：
  - `packages/live_player/lib/src/state.dart` 里的画面读数：`videoWidth`、`videoHeight`、`aspectRatio`（`:132`）、`isPortrait`（`:140`）、`declaredAspectRatio`（`:146`）、`expectedAspectRatio`（`:157`）、`expectsPortrait`（`:161`）；`mpv_engine.dart` 的 `displaySizeOf`（`:25-32`，带旋转的显示尺寸）。
  - 平台声明的宽高怎么带到播放：`LivePlayLine.width`、`height`、`declaredAspectRatio`（`packages/live_core`，模型归 E05，抖音的取值归 E01）——本子分类管“播放层怎么用它们”。
  - 直播间的方向选择逻辑：`features/live_play/logic/room_orientation.dart`（`RoomOrientation` 自动 / 竖屏 / 横屏、`isPortraitLayout`、`RoomOrientationChoice` 按房间记住）；“显示识别状态”角标的数据（`player/portrait_diagnostics.dart`）。
  - 画面缩放方式的取值和循环（`dialogs/player_dialogs.dart:14-58` 的 `videoFits`，3.x 的六种 `BoxFit`，设置 `videoFitIndex`）。
- 不包括（归哪里）：
  - 竖屏布局、竖屏全屏、三档面板、方向选择对话框和角标的样子 → A07.3；画面比例菜单的样子 → A07.6；全屏和横竖屏切换（屏幕方向、传感器）→ A07.4、O05.2（D-023）。
  - 小窗、画中画的尺寸和比例的使用 → A07.8、O02（它们读 `expectedAspectRatio`）。
  - 多画面格子里的画面 → N01；电视 → A17。

## 现状：做到哪、怎么工作的

- 用户看得到的：
  - 进抖音竖屏主播的直播间，第一帧之前就是竖屏布局（画面加高、下面三档面板），不再先按 16:9 排版、出画面后跳一下（G04.1）；其他平台没有声明，第一帧之前按 16:9，解码出尺寸后再按实际排版（照 3.x）。
  - 右上角菜单可以把这个房间强制当竖屏或横屏，开着“记住单个直播间方向”时下次进来照旧（`RoomOrientationChoice`，键 `portraitRoomOverrides`、`rememberPortraitRoomOverride`）。
  - 设置“显示识别状态”（`showPortraitDiagnostics`，默认关）打开时画面角上显示尺寸、比例、方向、来源（解码或平台声明）。
  - 画面比例在“适应 / 填充 / 拉伸 / 适应高度 / 适应宽度 / 不放大”六种之间切换（3.x 的顺序），所有房间共用一个设置。
- 内部怎么工作：
  1. 平台给线路时带上宽高（目前只有抖音：`DouyinApi.pictureSize` 按 3.x 的顺序取 `main` → `sdk_params` → `resolution` → `options.qualities` → 默认档，宽高 120～16384、比例 0.30～3.50 之外不算）。
  2. 会话打开源时清空解码尺寸（`session.dart:467` 的 `clearVideoSize`），状态里 `declaredAspectRatio` 取正在打开或播放的线路声明的比例（停止和空闲不算，`state.dart:146-154`）。
  3. 解码器报了尺寸（`EngineVideoSize`，`mpv_engine.dart:127-133`，`displaySizeOf` 按 `rotate` 交换宽高）后 `aspectRatio` 有值，`expectedAspectRatio` 以它为准。
  4. 直播间 `live_play_page.dart:236-241` 听 `expectsPortrait` 变化，`isPortraitLayout(choice, detected:)`（`room_orientation.dart:20`）决定布局；小窗 `mini/floating_window.dart:136`、画中画尺寸 `logic/mini_window.dart:74`、竖屏画面的 `AspectRatio`（`player/player_view.dart:530`，没有时按 9:16）都用预判。
- 完成度（和 3.x 对照）：
  - 一致：只有抖音给提示；“地址对得上才给”（4.x 按档给，天然满足）；解码为准；方向选择和记住的键名；六种缩放方式和顺序。
  - 确认过的改动：G04.1 X1 按 A（只有抖音）；3.x 的识别器（稳定计时 500 毫秒、置信度、截图探测活动区域）不搬（`portrait_stream_support.dart`，4.x 没有截图探测，D-001 下按 G02.1 的有意差异）；“记住单个直播间方向”开关立即生效（3.x 要点选项才生效，A07.3 的改动）。
  - 还缺：G04.1 没有 K90 结果（合并在 S02.3 用的构建之后）。

## 代码地图

| 文件 | 职责 |
|---|---|
| `packages/live_player/lib/src/state.dart`（214 行） | `videoWidth`、`videoHeight`（`:90`、`:93`）、`aspectRatio`（`:132`）、`isPortrait`（`:140`，不知道时当 16:9）、`declaredAspectRatio`（`:146`）、`expectedAspectRatio`（`:157`）、`expectsPortrait`（`:161`） |
| `packages/live_player/lib/src/mpv_engine.dart`（283） | `displaySizeOf`（`:25-32`，`dw`/`dh` 优先、按 `rotate` 交换）；`videoParams` → `EngineVideoSize`（`:127-133`）；打开后补发尺寸（`:188-189`） |
| `packages/live_player/lib/src/session.dart` | 打开源时 `clearVideoSize`（`:467`）；`EngineVideoSize` 写进状态（`:568-569`） |
| `packages/live_core/lib/src/play_line.dart`、`sites/douyin/douyin_api.dart` | `LivePlayLine.width`、`height`、`declaredAspectRatio`；`DouyinApi.pictureSize`（E05、E01 的文件，G04.1 加的） |
| `apps/pure_live/lib/features/live_play/logic/room_orientation.dart`（85） | `RoomOrientation`（`:7`）、`isPortraitLayout`（`:20`）、`RoomOrientationChoice`（`:30`，本次运行和记住两种） |
| `apps/pure_live/lib/features/live_play/player/portrait_diagnostics.dart`（70） | `PortraitDiagnosticsBadge`（`:14`）：“显示识别状态”的内容和来源 |
| `apps/pure_live/lib/features/live_play/dialogs/player_dialogs.dart` | `videoFits`（`:15`，3.x 的六种）、`videoFitIndexOf`（`:35`）、循环切换（`:42`）、选择对话框（`:50-58`） |
| `apps/pure_live/lib/features/live_play/live_play_page.dart`、`player/player_view.dart`、`mini/floating_window.dart`、`logic/mini_window.dart` | 用预判决定布局（`live_play_page.dart:236-241`、`:510`）、竖屏画面比例（`player_view.dart:530`）、小窗和画中画（`floating_window.dart:136`、`mini_window.dart:74`） |
| `packages/live_store/lib/src/settings/settings.dart` | `videoFitIndex`（`:264`）、`rememberPortraitRoomOverride`（`:364`）、`showPortraitDiagnostics`（`:381`）、`portraitRoomOverrides`（`:384`） |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `packages/live_player/test/session_test.dart` 的“F.1b: the line's declared size …” | 打开时用线路声明、解码覆盖、停止后不算、没声明的线路没有 |
| `packages/live_player/test/options_test.dart` | 显示尺寸和旋转（`displaySizeOf`） |
| `packages/live_core/test/` 的抖音用例（2 个） | 三个录制样本每档的宽高、别名档、未知档不填、取值顺序和范围 |
| `apps/pure_live/test/features/live_play/room_extras_test.dart`（G04.1 的 2 个） | 声明竖屏时第一帧前就是竖屏面板、解码横屏后换回 16:9；不声明时照旧 |

## 3.x 基线

- `git show v3.2.11:lib/player/core/live_stream_geometry_hint.dart`（345 行）：只有抖音给提示（`:31-37`），按正在播的地址找 sdk_key 取宽高（`:49-93`），对不上不给（`:95-98`），范围检查（`:265-277`）。
- `lib/player/core/portrait_stream_support.dart`（830 行）：`PortraitStreamDetector`（`:255`，稳定计时 500 毫秒 `:258`、置信度、截图探测活动区域 `ActiveVideoContentObservation` `:73`，可靠阈值 0.86 `:94`）——4.x 不搬，截图探测在 3.x 默认关（`player_manager.dart:313`）。
- `lib/player/core/player_manager.dart:830-857`、`:1396-1399`、`:2118`：每换一个源从“未知”开始，提示当暂定值，解码为准。
- 画面比例：`lib/modules/live_play/widgets/video_player/video_controller.dart:1518`（六种 `BoxFit` 循环）。
- 方向选择：`PortraitOrientationOverride`、`portraitOverrideForRoom`、`_sessionPortraitRoomOverrides`（键名 4.x 照旧，D-018）。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| G04.1 登记“完成”但没有 K90 结果：合并（`7b37e6f5f`）在 S02.2、S02.3 用的构建 `288fec0ec` 之后，CHECKLIST 第 1 节第 8 条结果栏是空的 | [G04.1 记录](G04.1-竖屏流的画面比例预判/record.md)“要在 K90 上看的” | 不符合 PROCESS 3.2“完成必须有真机结果” | 建议并入 S02.6（第 1 节第 8 条）；看不过的改回“待真机” |
| 只有抖音声明宽高（照 3.x）；TikTok 的 `sdk_params.resolution` 同样有，没接 | `DouyinApi.pictureSize`；TikTok 适配器 | TikTok 竖屏主播起播时跳一下 | G04.1 X1 选了 A；以后有用户反馈再开任务（要开代理在 K90 上验证） |
| 平台声明错了时（声明竖屏、实际横屏），第一帧到时再换一次布局 | `state.dart:157` | 最多跳一次，和改之前一样 | 接受 |
| 画面比例设置全局共用，不按房间记 | `player_dialogs.dart:35-58`、`settings.dart:264` | 和 3.x 一样 | 不做（3.x 行为） |
| 3.x 的截图探测（识别画面里的黑边、真实活动区域）不搬 | `portrait_stream_support.dart` | 带黑边的“伪竖屏”流仍按解码尺寸当横屏 | 不做：截图探测会让高通、ColorOS 设备丢帧（G02.1 记录），3.x 也默认关 |
| 代码注释里的旧编号（F.1b、F.1d、U.2b） | `state.dart:143`、`portrait_diagnostics.dart` 等 | 找文档先查 MAPPING | Z 组统一替换 |

## 相关决定和规范

- D-001：照 3.x；只有抖音给提示。
- D-003：G04.1 的 X1 按建议 A。
- D-018：`portraitRoomOverrides`、`rememberPortraitRoomOverride`、`videoFitIndex` 键名和含义不变。
- D-023：横屏全屏按传感器翻转（方向在 O05.2，本子分类只管画面形状的判断）。
- [specs/UI.md](../../../specs/UI.md) 第 9.3 节：视频不圆角不裁剪、画面尺寸动画只做合成层变换。

## 测试和验证

- 自动测试：`cd packages/live_player && flutter test`（声明和解码的优先级、旋转）；`cd packages/live_core && dart test`（抖音样本）；`cd apps/pure_live && flutter test test/features/live_play/room_extras_test.dart`（布局）。缺的：TikTok 等其他平台没有声明（功能本身没做）。
- 真机：[S02 的真机清单](../../../S-质量和验证/S02-真机验证/CHECKLIST.md)第 1 节第 8 条（进抖音竖屏主播，起播时不跳；横屏主播、游戏直播仍是横屏）、第 15 条（改画面比例立即生效）。

## 路线

1. 补 G04.1 的真机结果（CHECKLIST 第 1 节第 8 条，建议随 S02.6）。
2. 没有排着的任务。以后：TikTok 的宽高声明（有反馈时，E03.9 和本子分类一起做）；电视直播间的画面比例在 A17。新想法写进 V01 提议。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [G 播放](../README.md)。

- 代码：`packages/live_player`
- 进度：`████████████████████` 100%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| G04.1 | 竖屏流的画面比例预判（抖音竖屏起播不跳） | 功能 | 完成 | 2026-10-02 | 7b37e6f5f | [设计或说明](G04.1-竖屏流的画面比例预判/README.md)、[记录](G04.1-竖屏流的画面比例预判/record.md) |

<!-- docs:生成结束 -->
