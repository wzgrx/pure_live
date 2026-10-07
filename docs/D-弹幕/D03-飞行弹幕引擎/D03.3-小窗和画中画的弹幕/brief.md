# D03.3 小窗和画中画的弹幕：放大后跟着变大，用弹幕字体，画表情图：任务书

## 背景

- 来源：2026-10-07 docs v2 核对。D 组：应用内小窗和画中画的弹幕不用弹幕字体、不画应用自带的表情图（`compact_danmaku.dart:190`、`:204-213`），3.x 都有（[D03 说明](../README.md)“已知问题”）。V 组评估 [V01.5](../../../V-需求和反馈/V01-新功能提议/V01.5-小窗拖角改尺寸/README.md) 时发现：画中画两指拉大后弹幕不变大（`mini_window.dart:201` 缩放上限 1.0），上游 pure_live `b2cca41c7`（2026-10-02“画中画弹幕随窗口放大成比例缩放”）把上限放到 2.0；这是现有行为的修正，拆到本任务。另：直播间同屏 48 条的上限没有测试（S、V、W 组）。
- 现象：
  1. 设置 → 弹幕 → 更换弹幕字体换成霞鹜文楷，直播间弹幕变了，离开直播间进小窗后弹幕又是系统字体。
  2. 哔哩哔哩直播间里飘过 `[笑哭]` 的表情图，到了小窗里变成文字 `[笑哭]`；开着“小窗弹幕纯文字”时这些代码也还在。
  3. 平板上（小窗 360 宽）或把画中画拉到半屏，弹幕字还是 12 号左右，轨道稀疏。
- 为什么现在做：第二档；规模中（两个阶段各约 1.5 小时）。
- 已经做过的：A07.8（小窗和它的弹幕层，c7 最小 10 号）；D03.2（弹幕层的表情图）；D05.1（字体和纯文字在直播间生效）。

## 目标和验收

1. 小窗（应用内小窗、系统画中画、桌面小窗）弹幕用设置里的弹幕字体；默认值时用系统字体（和直播间同一规则）。
2. 小窗弹幕画应用自带的表情图（和直播间同一个 `EmoteTable`）；消息自带的表情（有 `emotes` 的平台）照旧是图片。
3. “小窗弹幕纯文字”开：所有表情（自带表和消息自带）都去掉，只剩表情的那条不上屏；关：表情是图片。
4. 自动缩放开：窗口宽 350 以下照旧（0.65～1 倍、最小 10 号）；350 以上按宽度放大，最多 2 倍（700 宽及以上 = 设置值 × 2）；速度同比；轨道高上限 88。自动缩放关：不变。
5. 直播间画面上默认最多 48 条远端弹幕同时在屏上，本地弹幕不算（有测试）。
6. 小窗弹幕的 12 项设置、默认值、范围不变（D-018）；直播间弹幕层的行为不变；测试和门禁通过。

## 现状（读代码得出，写文件:行）

- 小窗弹幕层：`apps/pure_live/lib/features/live_play/mini/compact_danmaku.dart`（220 行）：`CompactDanmakuLayer`（`:24`），`_take`（`:101-128`：纯文字时 `withoutEmoteCodes(text, message.emotes 的代码)`（`:105`），改写成新的 `LiveMessage` 时丢了 `emotes`、`style` 等字段（`:107-116`））；`build`（`:151-219`）：读 13 个设置（`:152-171`），`CompactDanmakuMetrics.resolve`（`:182`）；`DanmakuOverlay(…)`（`:190`）**没有 `emotes:`**；`DanmakuLook(…)`（`:204-213`）**没有 `fontFamily`、`textOnly`**。用在 `mini/mini_player.dart:224`（应用内小窗、画中画、桌面小窗共用）。
- 尺寸换算：`apps/pure_live/lib/features/live_play/logic/mini_window.dart:191-226` `CompactDanmakuMetrics`：`resolve`（`:199`）`scale = autoScale ? (宽 / referenceWidth).clamp(0.65, 1.0) : 1.0`（`:201`），最小 10 号（`:203`、`minimumFontSize` `:216`），轨道高 `max(size × 1.8, size + 10).clamp(18.0, 44.0)`（`:208`），`referenceWidth = 350`（`:213`）。应用内小窗宽 `inAppMiniBase` 220～360（`:98`）。
- 直播间的做法（照抄）：`features/live_play/player/player_view.dart:212` `_emotes`，`initState` 里 `ref.read(emoteLibraryProvider)`、`tableOf(platform)`、空就 `load(platform).then(setState)`（`:229-237`），传 `emotes: _emotes`（`:486`）；字体和纯文字来自 `shared/danmaku/danmaku_settings.dart:11-28` 的 `danmakuLookOf`（`:12` 读 `danmakuFontFamilyName`，`:25` 默认值 → null，`:26` `textOnly`）。
- 弹幕层：`apps/pure_live/lib/shared/danmaku/danmaku_overlay.dart`：`DanmakuLook.fontFamily`（`:63`）、`textOnly`（`:66`）、`emoteSize`（`:73`，1.3 × 字号、16～48）；`DanmakuOverlay.maxVisible` 默认 48（`:158`），只数远端（`:465-466`）；`emotes` 默认 `EmoteTable.empty`（`:164`）；切分 `chatSegments(message, widget.emotes)`（`:374`）。
- 设置：`Settings.pipDanmakuNoEmojiMode`、`pipDanmakuAutoScale`、`pipDanmakuFontSize` 等（`packages/live_store/lib/src/settings/settings.dart`，A08.1 README 有逐项）；`Settings.danmakuFontFamilyName`（`:515`）。
- 测试：`apps/pure_live/test/features/live_play/live_play_mini_window_test.dart:283-292`（c7：220 宽 10 号、三条轨道；360 宽 12 号；自己设小的照旧；关自动缩放不变；速度 × 0.65）；`apps/pure_live/test/shared/danmaku_overlay_test.dart:231`（c7 排队，每帧最多 4 条）、`:266`（字体、纯文字、表情图）。

## 3.x 基线

- `git show v3.2.11:lib/modules/live_play/widgets/danmaku/compact_danmaku_overlay.dart`（94 行）：`:25` 自动缩放、`:26` 纯文字、`:35` 弹幕字体 → `:62`；`:86` `emojiAtlas: EmojiAtlas.instance`（和直播间同一个图集）。
- `git show v3.2.11:lib/common/utils/compact_danmaku_metrics.dart:29`：`clamp(0.65, 1.0)`（上限 1.0 是 3.x 的，2.0 是上游之后的修正，属于修正不是改设计）。
- 上游：`git show b2cca41c7`（本机仓库里有）：`lib/core/utils/compact_danmaku_metrics.dart` 上限 1.0 → 2.0，行高 / 表情 / 间距上限 44/32/40 → 88/64/80。
- 要保留：小窗弹幕设置的键名、默认值、范围（D-018）；350 以下的缩放和最小 10 号（A07.8 c7）。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节、第 8 节、第 14 节）。
2. `docs/specs/ENGINEERING.md`；`docs/specs/UI.md` 第 9 节（流畅度）。
3. 本文件夹的 `README.md`；`docs/D-弹幕/D03-飞行弹幕引擎/README.md`；`docs/A-界面设计/A07-直播间界面/A07.8-小窗/README.md`（c7）；`docs/D-弹幕/D03-飞行弹幕引擎/D03.2-飞行弹幕里的表情图片/README.md`。

## 范围

- 可以改：`apps/pure_live/lib/features/live_play/mini/compact_danmaku.dart`；`features/live_play/logic/mini_window.dart`（只改 `CompactDanmakuMetrics`）；`shared/danmaku/danmaku_settings.dart`（抽字体换算）；测试 `live_play_mini_window_test.dart`、`test/shared/danmaku_overlay_test.dart`；本文件夹。
- 不能改：弹幕层 `danmaku_overlay.dart` 的行为（只加测试）；小窗弹幕设置的键名、默认值、范围；设置页（A08、A11.3）；小窗本身的尺寸和拖动（A07.8、V01.5）；多画面、电视；版本号、`assets/version.json`、`assets/releases.json`；签名配置。

## 方案和阶段

| 阶段 | 做什么（对应 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 小窗弹幕用弹幕字体、画表情图 | c1：`DanmakuLook(fontFamily:)` 用和 `danmakuLookOf` 同一个换算（抽成 `danmakuFontFamilyOf(String name)` 之类放在 `danmaku_settings.dart`）。c2：`_emotes` 照 `player_view.dart:226-237` 取和异步加载，`didUpdateWidget` 换平台时重取；`DanmakuOverlay(emotes: _emotes)`；`DanmakuLook(textOnly: pipDanmakuNoEmojiMode)`；`_take` 去掉自己的去表情和改写（`:105-118`），直接转发原消息 | `compact_danmaku.dart`、`danmaku_settings.dart`、`live_play_mini_window_test.dart` | 验收 1～3、6 |
| 2 随窗口放大（上限 2 倍）和直播间 48 条上限的测试 | c3：`CompactDanmakuMetrics` 加 `static const double maxScale = 2.0`，`:201` 用它，`:208` 上限 88，注释写上游提交；c4：`danmaku_overlay_test.dart` 加 48 条用例 | `mini_window.dart`、两个测试文件 | 验收 4、5、6 |

每个阶段都要能单独合并（门禁通过、不留半截功能）。

## 测试

- 阶段 1（改之前会失败）：`live_play_mini_window_test.dart` 加
  - “the mini danmaku uses the danmaku font (D03.3)”：设 `Settings.danmakuFontFamilyName = 'LXGW'`，pump 小窗弹幕层，发一条弹幕，读弹幕层的 `lastTextStyle?.fontFamily == 'LXGW'`（`danmaku_overlay_test.dart:266` 用的同一个状态读法）；默认值时为 null。
  - “bundled emoticons fly as pictures in the mini window; text only drops them”：给 `emoteLibraryProvider` 一个带 `[dog]` 的表（`EmoteTable.of({'[dog]': (asset: 'assets/emo/images/bilibili/dog.png', url: '')})`），发 `好[dog]`，宽度比纯文字时大 16 以上；开 `pipDanmakuNoEmojiMode`，只发 `[dog]` 不上屏。
- 阶段 2（改之前会失败）：`live_play_mini_window_test.dart:283` 的 c7 用例改为：360 宽 = `12 * 360 / 350`（`closeTo`），加 700 宽 = 24、1000 宽 = 24、轨道高 ≤ 88、速度 × 2；220 宽的三条断言不变。`danmaku_overlay_test.dart` 加“at most 48 remote danmaku on screen by default; local ones do not count”：一次发 60 条短弹幕（足够的轨道高度让它们都能进），推几帧后 `flyingCount` 的远端部分 = 48，再发 2 条本地弹幕能进。
- 测试里的定时器至少 1 秒（D-017）；不访问真实平台。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 设置 → 弹幕 → 更换弹幕字体，选一个下载的字体；设置“离开直播间时小窗播放”开，进哔哩哔哩热门直播间，返回首页 | 首页角落小窗里的弹幕是选的字体 |
| 2. 同一个小窗里等出现 `[笑哭]` 这类表情 | 是图片，大小和字差不多 |
| 3. 设置 → 小窗弹幕 →“纯文字”开 | 小窗里没有表情（代码也没有），只有表情的弹幕不出现 |
| 4. 进直播间，按画中画按钮进系统画中画，两指把画中画拉到最大 | 弹幕字明显变大、轨道变少变宽；缩回最小时字号回到 10 号左右 |
| 5. 设置 → 小窗弹幕 →“自动缩放”关，重复第 4 步 | 字号一直是设置值，不随窗口变 |

## 风险和注意

- `_take` 改成直接转发后，本地弹幕（`message.isLocal && message.style != null`）在暂停时照样飞的判断（`:103`）要留着。
- 表情图解码要时间：弹幕层对没解码完的表情会先等（D03.2），小窗刚出现时第一条可能晚一点上屏，属正常。
- 画中画里 Flutter 的窗口宽度是逻辑像素，K90 的画中画最大约屏宽的一半，可能刚好过 350；平板和桌面更明显。
- 可能冲突的文件：`compact_danmaku.dart`、`mini_window.dart`（V01.5 做拖角改尺寸时也改小窗）；`danmaku_settings.dart`（D05 后续）。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 分支 `ai/D03.3` 或本机工作区；提交信息以 `[D03.3]` 开头（英文）；不推 master。
- 提交前：`apps/pure_live` 跑 `dart format --output=none --set-exit-if-changed .`、`flutter analyze`、全部 `flutter test`；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”、更新登记表的 `done`、`next`、`branch`。

## 报告（中文，简洁）

每条验收做到没有；测试数量（改之前失败几个）；改了哪些文件；缩放上限和轨道高的最终数字；要在真机上看的；可能冲突的文件。
