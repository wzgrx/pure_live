# C01.4 直播间清晰度显示平台实际给的档：任务书

## 背景

- 来源：H01.3 记录（`docs/H-录制/H01-录制核心/H01.3-合并进度/record.md`）“没做的”第 1 条；V03.3（2026-10-03）开了本任务。起因是 S02.2 在 K90 上发现录制把游客拿到的 720p 写成“原画”，H01.3 修了录制，直播间没改。
- 现象：哔哩哔哩游客进一个清晰度列表只有“原画”的直播间，平台实际给“超清”（编号 250）。直播间清晰度按钮显示“原画?”，同一时间在这个直播间开始录制，录制面板和通知写“超清”，并提示“平台实际返回 超清，已按真实画质录制”。
- 为什么现在做：第二档；同一路流两个说法，用户会以为录制和播放的画质不一样。
- 已经做过的：H01.3（`RecordStreamResolver.servedQuality`）、E06.1 c5（`appliedQuality`）、C01.1（升级 C-4：按平台实际给的画质显示并提示，未确认的带“?”）。

## 目标和验收

1. 确认的编号不在列表里时，直播间和多画面按平台编号命名实际画质（哔哩哔哩 250 = “超清”），不带“?”。
2. 平台没确认时照旧显示请求的名字加“?”。
3. 进房时实际档和请求不同，提示一次“平台实际返回 超清，已按真实画质播放”（`quality_limited_to`）；重连、刷新不再提示。
4. 录制的结果不变（H01.3 的 `applied_quality_test.dart` 照旧通过）。
5. 新测试通过；门禁通过。

## 现状（读代码得出，写文件:行）

- `packages/live_core/lib/src/live_site.dart:223-239` 的 `resolveAppliedPlayQuality({qualities, requested, resolution})`：`appliedId` 在 `qualities` 里 → 那一项；等于 `resolution.appliedQuality` 的编号 → 它；否则 `requested.withPlaybackUnconfirmed(unconfirmed: resolution.qualityUnconfirmed || (appliedId != null && matched == null))`。
- `packages/live_record/lib/src/resolver.dart:334-350` 的 `RecordStreamResolver.servedQuality({platform, qualities, requested, resolution})`：先调上面的函数；结果未确认、平台确认了编号且编号不在列表里时，返回 `LivePlayQuality(quality: LiveQualityLabel.normalize(platform: platform, rawLabel: '', id: id), data: id, id: id)`。
- 直播间：`apps/pure_live/lib/features/live_play/logic/room_controller.dart:462` 的 `_openQuality(index, epoch, {userChoice})`；`:491` 调 `resolveAppliedPlayQuality`；`:492-494` 找实际档在列表里的位置；`:495-497` 只在 `userChoice && playing != index` 时 `toast(i18n('quality_limited_to', …))`，然后 `_qualities[playing] = applied`；`:546` 的 `_refreshPlan`（E06.2 要改的）。
- 多画面：`apps/pure_live/lib/features/multiview/logic/multiview_controller.dart:592-593`，同样调 `resolveAppliedPlayQuality`。
- 菜单：`apps/pure_live/lib/features/live_play/buttons/stream_menu.dart:51`：未确认的名字后面加“?”。

## 3.x 基线

- `git show v3.2.11:lib/common/utils/play_quality_label.dart:6-8`：平台没确认时“未确认 · <名字>”（`quality_playback_unconfirmed`）；播放面板 `lib/modules/live_play/widgets/video_player/video_controller_panel.dart:1224`、清晰度选择 `resolution_selector/resolution_selector.dart:21` 显示它；录制 `lib/recorder/pages/recorder/recorder_controller.dart:905` 也用它。3.x 遇到列表外的编号显示“未确认 · 原画”；v4 改成按平台编号命名（H01.3 README“需要选的”A，已确认的改动），直播间跟着改是同一个决定的延续。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节、第 8 节、第 14 节）。
2. `docs/specs/ENGINEERING.md`。
3. 本文件夹的 `README.md`；`docs/H-录制/H01-录制核心/H01.3-合并进度/record.md`（“一、录制清晰度标签”）；`docs/E-直播平台/E06-平台层升级/E06.1-已批准升级的余项/record-2.md` 的 c5 和“交给界面”第 4 条；`docs/E-直播平台/E06-平台层升级/E06.2-平台层新数据接到界面/brief.md`（同一段代码）。

## 范围

- 可以改：`packages/live_core/lib/src/live_site.dart`（加函数）和测试；`packages/live_record/lib/src/resolver.dart`（`servedQuality` 改为调新函数，行为不变）；`apps/pure_live/lib/features/live_play/logic/room_controller.dart`、`apps/pure_live/lib/features/multiview/logic/multiview_controller.dart` 和对应测试。
- 不能改：清晰度菜单的样子（A07.6）；`LiveQualityLabel` 的命名表；其他平台的取流；版本号、`assets/version.json`、`assets/releases.json`；签名配置；3.x 的设置键名和含义；不加新翻译键（用已有的 `quality_limited_to`）。

## 方案和阶段

| 阶段 | 做什么（对应 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | c1：规则搬到 `live_core`，录制改调它 | `live_site.dart`、`resolver.dart`、两个包的测试 | `live_core` 新用例过；`live_record` 原有 43 个用例照旧过 |
| 2 | c2、c3：直播间和多画面用新规则，进房时提示一次 | `room_controller.dart`、`multiview_controller.dart`、应用测试 | 验收 1～3；应用全部测试过 |

## 测试

- 改之前会失败：应用测试“哔哩哔哩游客、列表只有原画、平台给 250：清晰度按钮是‘超清’”——现在是“原画?”。样本用 `fixtures/bilibili/S07-guest-qn10000`，列表只有 10000 的改写照 H01.3 的 `packages/live_record/test/applied_quality_test.dart` 的做法。
- `live_core`：新函数的 4 种情况（在列表里、不在列表里且确认、没确认、`appliedQuality`）。
- 提示只一次：进房提示一次，模拟重连后不再提示。
- 测试里的定时器至少 1 秒；不访问真实平台。改过的包跑 format、analyze、测试；`apps/pure_live` 跑全部 `flutter test`。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 不登录哔哩哔哩，进一个清晰度菜单只有“原画”的直播间 | 按钮显示“超清”（不带“?”），弹一次“平台实际返回 超清，已按真实画质播放” |
| 2. 在这个直播间开始录制 | 录制面板、通知也是“超清”，和播放一致 |
| 3. 断网 10 秒再恢复 | 重连后按钮仍是“超清”，不再弹提示 |
| 4. 登录后进同一个直播间 | 能拿到原画时按钮是“原画”，不提示 |

## 风险和注意

- `_qualities[playing]` 被替换成列表外的一项后，用户再从菜单选别的档要正常（`selectionId` 比较）。
- 可能冲突的文件：`room_controller.dart`、`multiview_controller.dart`（E06.2 的“实际清晰度”阶段也改 `_refreshPlan` 附近）。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 分支 `ai/C01.4` 或本机工作区；提交信息以 `[C01.4]` 开头（英文）；不推 master。
- 提交前：改过的包跑 `dart format --output=none --set-exit-if-changed .`、analyze、测试；`apps/pure_live` 跑全部 `flutter test`；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”、更新登记表的 `done`、`next`、`branch`。

## 报告（中文，简洁）

每条做到没有；根因；测试数量；改了哪些文件；要在真机上看的；可能冲突的文件（`room_controller.dart`）。
