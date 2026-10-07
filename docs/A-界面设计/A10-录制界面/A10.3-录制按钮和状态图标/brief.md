# A10.3 录制按钮和录制状态图标：任务书

> 设计按建议定稿、代码已在 2026-10-02 合并（`40086fafa`），登记表状态“待真机”。这份任务书保留原来交给执行者的全部要求（旧编号 B04 的任务单 c1～c3 和验收，下面“方案和阶段”的阶段 1、2），并写清剩下的事：阶段 3 真机验证（和 H05.1 同一轮看）。

## 背景

- 来源：用户的问题 02 原话：“录制的按钮图标需要重新优化设计一下，现在这个看起来像在录制，需要重新设计一下，未录制和没有录制，让人从图标就可以明显看出来”；审查报告 A-02（[V03.1 全面审查](../../../V-需求和反馈/V03-审查和调研/V03.1-全面审查/README.md)）。
- 现象（修之前，4.0.0）：进一个没录过的直播间，顶栏关注右边的录制按钮是灰圈里一个红色实心点，看起来就像在录；开始录制后的准备几秒、断网重连、停止后合成 MP4 时，顶栏和画面左上角都是红底闪烁的“● 录制中”；录制失败时顶栏和没录一样；录制面板和录制中心的状态卡每种状态一个不相干的图标（计时器、沙漏、循环箭头、转圈、红点）；通知栏的录制小图标是圆环圆点，和“没在录”同形。
- 为什么做：第一档（用户直接提的问题，每次进直播间都看得到）；相关决定 D-003（“需要你选的”按建议 A）。
- 原任务单的约定：规模中；分组录制；A02.3 之后更好（不强制）；可以和 D02.1、A07.10、D01.32、E06.2 同时做；和 A07.13 都改顶栏按钮，建议错开；出设计：要（先出对比页和效果图，再实现；用户已授权“所有决定你选择”）。
- 已经做过的：A07.1 改动 13（录制三态，红点就是那时加的）；A07.6（录制面板和状态卡）；A10.1（录制中心用同一张状态卡，`shared/record/`）；H01.3（合并进度 `task.mergeProgress`，合成中的图形要用）。

## 目标和验收

1. c1 先出设计（产出放本文件夹：README、`src/gen.py`、效果图、编号图、`page.json`、导出的章节图）：未录、等待开播、准备中、录制中、重连中、合成中、失败七种状态，在直播间顶栏（亮背景）、画面上（暗）、全屏顶栏、录制中心、状态卡、通知图标里各是什么样。方向：
   - 未录单色无红：2dp 圆环 + 中心小实心圆，和其他图标同色；
   - 录制中红色实心圆底 + 白色圆角方块，外圈慢慢呼吸（减少动态效果时常亮），全屏顶栏有空间时右边加 `mm:ss`；
   - 红色只给真正在写文件的 running；
   - 等待开播：圆环右下角小钟；准备中、合成中：中性色环形进度；重连中：琥珀色虚线圆环；失败：设计里定（X3）。
2. c2 实现：`packages/live_ui` 的 `RecordGlyph`、`RecordingBadge` 扩成这些状态；`features/live_play/buttons/record_button.dart`、`player/recording_badge.dart`、`shared/record/record_status_card.dart`、录制中心按 `task.status` 映射，不再用 `RecordStatus.isActive` 二分；角标文字按状态写“录制中 / 重连中 / 合成中”。
3. c3 Android 通知小图标（录制）跟着新图形（单色）。
4. 只看图标就能分出“没在录”和“在录”；合成、准备时不再显示红色和“录制中”。
5. 测试：每种状态的图标、颜色和文字；减少动态效果时不呼吸。
6. （阶段 3）在 K90 上照 [verify.md](verify.md) 逐条通过，登记表改“完成”。

## 现状（读代码得出，写文件:行）

阶段 1、2 已做完，现在的代码：

- 图形：`packages/live_ui/lib/src/widgets/record_glyph.dart`（400 行）：`RecordGlyphState`（`:10`，七个值）、`RecordGlyph`（`:41`，呼吸 `breath` 2.4 秒 `:64`、转圈 `turn` 1.2 秒 `:67`；`MediaQuery.disableAnimationsOf` 时不动 `:80`）、`RecordGlyphPainter`（`:154`，各状态 `:235-298`；颜色 `:200-206`：只有录制中用 `LiveSemanticColors.recording`）、`RecordingBadge`（`:328`）。颜色 `packages/live_ui/lib/src/theme/live_colors.dart`：`OnVideoColors.onError`（`:104`）、`recording` `#D92D20`（`:173`）、`recordingHalo`（`:180`，30%）。
- 映射：`apps/pure_live/lib/shared/record/record_look.dart`（58 行）：`recordGlyphState`（`:12`，九种卡片状态 → 七种图形，排队中名额满 → 等待开播）、`recordButtonLabel`（`:25`）、`recordBadgeState`（`:39`，只认 running / reconnecting / processing）、`recordBadgeLabel`（`:47`）、`recordJoinProgress`（`:55`）。卡片状态来自 `shared/record/record_state.dart:39` 的 `recordCardState`。
- 顶栏按钮：`apps/pure_live/lib/features/live_play/buttons/record_button.dart`（217 行）：`RecordButton`（`:23`），排队中才算名额（`:93-100`），“自动录”胶囊（`:111-139`），横屏全屏录制中带时间（`:140-165`、`_RecordTime` `:178`）；放在竖屏顶栏 `features/live_play/layout/room_header.dart:106`、横屏全屏顶栏 `player/player_controls.dart:294`（`time: true`）→ `:372`、竖屏全屏第一行 `:310`；网络电视的全屏顶栏没有录制按钮（`:367`）。
- 角标：`features/live_play/player/recording_badge.dart`（102 行）的 `RoomRecordingBadge`（`:18`，`showsRecording`）；竖屏画面标题前 `player_controls.dart:447-458`（`_RecordingMark`，点了打开录制面板）、全屏控制栏下面 `player_view.dart:734-736`（横屏全屏录制中不显示，网络电视例外）、控制栏隐藏时左上角紧凑形 `player_view.dart:724`、小窗 `mini/mini_player.dart:229`。
- 状态卡：`shared/record/record_status_card.dart` 卡片头 `:265`（20 号，琥珀色只给排队和重连 `:264`），合成中按百分比重画 `:410-420`，已保存 `AppIcons.recordSaved` 绿勾 `:458`。
- 通知：`apps/pure_live/android/app/src/main/res/drawable/ic_stat_recording.xml`（实心圆挖出圆角方块），`RecorderForegroundService.kt:331`；H05.1 补做的 `ic_stat_record_stopped.xml`（`:135`）和按状态写的标题 `apps/pure_live/lib/app/recording_notice.dart:59`。
- 修之前的根因（记录）：`record_glyph.dart` 的“未录”中心是红点；`record_button.dart`、`recording_badge.dart` 用 `RecordStatus.isActive`（running、reconnecting、processing、preparing 都算）二分；失败落到“未录”分支。

## 3.x 基线

- `git show v3.2.11:lib/modules/live_play/widgets/button/record_action_button.dart:39-104`：48×48、圆角 12 的实心按钮；没有任务 `Remix.record_circle_line` 中性色、底 `surfaceContainerHighest`；有任务 `Remix.checkbox_circle_fill` 主色；running / reconnecting / preparing 是 `Remix.record_circle_fill`、`Colors.redAccent`（`_isTaskRunning` `:96-104`，3.x 也把准备中算成“录制中”）。图标和文字 `record_action_content.dart`（51 行）。
- 3.x 的未录本来就是中性色空心圈，录制中才变红——这个任务恢复的是 3.x 的“未录不红”，同时把 3.x 也没分开的准备中、重连中、合成中分开。
- 要保留的：按钮位置、点一下打开录制面板（3.x 是五个动作的对话框，A07.6 换成面板）、提示文字；录制面板和录制中心的布局。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 4.1 节界面任务、第 5 节分阶段、第 8 节合并审查、第 10 节真机验证、第 14 节规则）。
2. `docs/specs/ENGINEERING.md`；`docs/specs/UI.md` 第 3 节（同一件事一种做法）、第 8.1 节（语义色：红色只给直播和录制中）、第 9 节（动效和减少动态效果）。
3. 本文件夹的 `README.md`（设计、图形规格、实现和验证）、`record.md`、`verify.md`；`docs/A-界面设计/A07-直播间界面/A07.1-竖屏普通布局/README.md` 改动 13；`docs/A-界面设计/A07-直播间界面/A07.6-直播间弹窗/README.md`（录制面板）；`docs/A-界面设计/A10-录制界面/A10.1-录制中心/README.md`；H05.1 的 [README](../../../H-录制/H05-录制通知/H05.1-录制通知按状态写标题/README.md)。

## 范围

- 可以改（阶段 1、2 当时的范围）：`packages/live_ui`、`apps/pure_live/lib/features/live_play/buttons/`、`features/live_play/player/`、`apps/pure_live/lib/shared/record/`、`features/recorder/`、`apps/pure_live/android/app/src/main/res/`（通知图标）、翻译文件、本文件夹。
- 阶段 3 只改本文件夹（`verify.md`、`verify/`）和登记表。
- 不能改：录制面板和录制中心的布局、按钮、文字（A07.6、A10.1）；`packages/live_record` 的状态定义；`RecorderForegroundService.kt` 和 `app/recording_notice.dart`（属于 H05，X4 由维护者另做）；其他组的界面和逻辑；版本号、`assets/version.json`、`assets/releases.json`；签名配置；3.x 的设置键名和含义。

## 方案和阶段

| 阶段 | 做什么（对应 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1（已完成） | c1 出设计：14 张效果图（v3 还原、4.0.0 现状、图形规格、七状态×六处总表、竖屏、横屏、状态卡、录制中心、通知）、3 张编号图、4 张深色图、15 张章节导出图、README；X1～X3 按 A 定稿，X4 交维护者 | 本文件夹 | 设计定稿（按 D-003） |
| 2（已完成，`82f3a60b7`、`5bab804b0`，合并 `40086fafa`） | c2、c3：七种图形和三种角标；`record_look.dart` 映射；顶栏按钮、角标、状态卡、录制中心跟着任务状态；横屏全屏带时间；通知小图标 | 见“现状” | 新测试 7 个、改 2 个、删旧的 3 个；`live_ui` 100 个、`apps/pure_live` 743 个通过；debug APK 能编译 |
| 2.5（维护者补做，`79ecb5d2b`，登记为 H05.1） | X4：单个直播间的通知按状态写标题；“录制已停止”提醒换 `ic_stat_record_stopped` | `app/recording_notice.dart`、`RecorderForegroundService.kt`、`res/drawable/` | `system_surfaces_test.dart` 通过 |
| 3（待做） | 真机验证 | `verify.md`、`verify/`、`docs/tasks.toml` | `verify.md` 13 条通过；A10.3 和 H05.1 一起改“完成” |

## 测试

- 已有（阶段 2）：`packages/live_ui/test/design_system_test.dart` 4 个（`:301` 只有录制中有红色；`:362` 画面上的色调；`:377` 呼吸、转圈、减少动态效果时都不动、合成按进度不转；`:412` 角标三种状态的底色、文字和紧凑形）；`apps/pure_live/test/features/recorder/recorder_page_test.dart` 2 个（`:186` 顶栏八个房间七种状态的图形、红色、提示、合成进度、横屏带时间、角标；`:288` 九种卡片状态到图形和角标的映射）；`recorder_centre_test.dart:434`（九张卡片头）；`apps/pure_live/test/platform/system_surfaces_test.dart`（通知资源、按状态写的标题）。
- 真机发现问题要修时：先写改之前会失败的测试（例如颜色不对就在 `design_system_test.dart` 加断言）；测试里的定时器至少 1 秒（角标和时间用固定的 `now`，不跑真时钟）；不访问真实平台。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 进一个没录过的直播间（竖屏），看顶栏录制按钮 | 单色圆环加中心圆点，和右边四宫格菜单同色，没有一点红色 |
| 2. 点录制按钮 →“开始录制” | 先是灰色转圈环（准备中），画面上没有角标；开始写文件后变成红色实心圆加白色圆角方块，外圈约 2.4 秒一明一暗；画面标题前红底“录制中 00:05” |
| 3. 系统里打开“移除动画”再回来 | 光晕常亮不再变化，转圈停住 |
| 4. 录制中横屏全屏 | 顶栏按钮右边 `mm:ss` 在走；控制栏下面没有第二个“录制中”角标 |
| 5. 录制中开飞行模式 10 秒再关 | 琥珀色虚线圆环、深色底“重连中 mm:ss” |
| 6. 停止录制 | 灰色进度环、深色底“合成中 xx%”，没有红色；合成完变回单色圆环 |
| 7. 录制中心；下拉通知栏 | 卡片头同一组图形；通知小图标是实心圆挖出方块 |

完整的表（13 条，含深色主题、竖屏全屏、开播自动录的小钟、“录制已停止”提醒）和结果栏在 [verify.md](verify.md)。

## 风险和注意

- 动画节奏要用 profile 构建看（debug 构建的帧率不代表真实情况）。
- “移除动画”是系统级开关：验完关掉，否则后面别的验证看不到动效。
- 重连要断网：录制中开飞行模式会断开 adb 无线调试（`192.168.1.2:5555`），恢复后重新连接；截图在恢复后补。
- 录制会写文件：验完在录制中心删掉测试任务，不碰 3.x 和正式包的录像（D-019）。
- 文件和别的任务共用：`record_button.dart`、`player_controls.dart`、`player_view.dart`（A07.10、A07.11、A07.13、A07.14、A07.15）；`record_status_card.dart`（A07.6、A10.1、H01.3）；`live_colors.dart`（A01）。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`（录制要 FFmpeg），再 `flutter pub get`。
- 效果图（要改设计时）：`python3 docs/A-界面设计/A10-录制界面/A10.3-录制按钮和状态图标/src/gen.py && python3 tools/ui/mock/render.py docs/A-界面设计/A10-录制界面/A10.3-录制按钮和状态图标/src --annotate`；评审页 `python3 tools/ui/mock/page.py docs/A-界面设计/A10-录制界面/A10.3-录制按钮和状态图标/page.json`。
- 真机用的构建：master 上包含 `40086fafa` 和 `79ecb5d2b` 的提交（profile）；在 `verify.md` 写清提交号。
- 要改代码时：分支 `ai/A10.3` 或本机工作区；提交信息以 `[A10.3]` 开头（英文）；不推 master；提交前 `packages/live_ui` 和 `apps/pure_live` 跑 `dart format --output=none --set-exit-if-changed .`、`flutter analyze`、`flutter test`；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”、更新登记表的 `next`、`branch`；真机做到一半时把已看的写进 `verify.md`。

## 报告（中文，简洁）

`verify.md` 每条的结果和截图；不通过的现象和根因线索（文件:行，参考 README“实现和验证”表），以及归 A10.3（图形、颜色、动画）还是 H05.1（通知文字、小图标）；登记表改了什么。
