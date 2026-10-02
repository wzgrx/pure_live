# A07.16 京东直播间用平台给的模糊图作背景：任务书

## 背景

- 来源：已批准升级 28-3（`docs/specs/UPGRADES.md`）：“进房后封面用列表卡片的封面，模糊图只作背景”。平台层在 E02.9 做完（`JdLiveRoom.background`），界面部分一直写“直播间设计没有背景图的位置 → 未排”；V03.3（2026-10-03）开了本任务。
- 现象：从关注页进一个京东直播间（应用刚启动、还没在推荐里见过这张卡片），竖屏全屏的“沉浸背景”只有渐变，没有画面；纯音频时也只有深色底。3.x 在同样情况下背景是平台给的模糊画面。
- 为什么现在做：第三档；只影响京东一个平台，但 3.x 有、v4 没有。
- 已经做过的：E02.9（平台层 28-2、28-3）；A07.2（沉浸背景 `AmbientBackdrop`）；C01.2 / A07.7（纯音频、恢复中的暗封面）。

## 目标和验收

1. 京东直播间，竖屏全屏（画面模式“沉浸背景”“平衡填充”）、横屏全屏和宽屏里的竖屏流两边、纯音频、恢复中，背景用 `JdLiveRoom.background`（有的话）；没有时照旧“封面 → 头像 → 渐变”。
2. 其他平台的背景完全不变。
3. 卡片、关注、观看历史的封面不变（仍只用卡片封面）。
4. 先出图、发评审页，用户确认（或按 D-003 用建议）后再写代码；README 写明定稿。
5. 新测试通过；门禁通过。

## 现状（读代码得出，写文件:行）

- 平台层：`packages/live_core/lib/src/sites/jdlive/jdlive_api.dart:86-88` 的 `JdLiveRoom.background`（`:480` 从播放接口的 `blurredImg` 取）；`:84` 的 `cover` 只用卡片的 `indexImage`；`jdlive_site.dart:333` 的 `getRoomDetail` 返回的 `LiveRoom.data` 是 `JdLiveRoom`（`jdlive_api.dart:593`：`data: withData ? room : null`；刷新用的 `getRoomDetailForRefresh` 不带 data）。
- 沉浸背景：`apps/pure_live/lib/features/live_play/player/player_view.dart:494-497` 的 `_cover`（`room.cover`，空则 `room.avatar`），`:522` `AmbientBackdrop(cover: _cover)`。
- `packages/live_ui/lib/src/widgets/ambient_backdrop.dart:17-49`：渐变底、封面按 `ambientCoverDecodeWidth`（24）解码放大 1.14 倍、15% 黑罩。
- 纯音频、恢复中：`apps/pure_live/lib/features/live_play/player/player_status.dart:321`、`:351` 的 `_DimmedCover(url: room.cover)`（`:451` 定义）。
- 换台预览：`apps/pure_live/lib/features/live_play/player/room_swipe.dart:237` 用下一个房间的封面（列表里的房间，没有 `data`），不在本任务范围。
- 应用里没有任何地方读 `JdLiveRoom`。

## 3.x 基线

- `git show v3.2.11:lib/core/site/jdlive/jd_live_api.dart`：卡片封面 `indexImage`（`:234`），播放接口封面 `blurredImg`（`:264`），`enrich`（`:49-60`）只在详情封面为空时用卡片的，所以进房后封面就是模糊图。
- `git show v3.2.11:lib/modules/live_play/widgets/layout/live_play_content.dart`：`:521-526` 背景按 `resolvePortraitFullscreenBackgroundUrl`（`:606-617`：详情封面 → 房间封面 → 详情头像 → 房间头像），京东拿到模糊图；`:623-671` 的 `PortraitFullscreenPresentation` 画背景。
- 要保留的：京东直播间的背景是平台的模糊画面（3.x 的观感）。不保留的：模糊图当卡片封面（28-3 已改）。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 4.1 节界面任务设计、第 5 节、第 8 节、第 14 节）。
2. `docs/specs/ENGINEERING.md`；`docs/specs/UI.md` 第 3 节。
3. 本文件夹的 `README.md`；`docs/A-界面设计/A07-直播间界面/A07.2-竖屏流和竖屏全屏/README.md`（沉浸背景的设计和 Q6）；`docs/E-直播平台/E02-其他国内平台/E02.9-京东直播/record.md`（问题 4、升级落地 28-3）。

## 范围

- 可以改：`apps/pure_live/lib/features/live_play/logic/`（加取背景的函数）、`player/player_view.dart`（`_cover`）、`player/player_status.dart`（`_DimmedCover` 的地址）；对应测试；本文件夹（`page.json`、`src/`、效果图）。
- 不能改：`packages/live_core` 的京东解析和 `LiveRoom` 模型（按 X1 建议 A，不加字段）；`AmbientBackdrop` 的样子；卡片和列表的封面；其他平台；版本号、`assets/version.json`、`assets/releases.json`；签名配置；3.x 的设置键名和含义。

## 方案和阶段

| 阶段 | 做什么（对应 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | 出图：3.x 还原、v4 现在（见过卡片、没见过卡片）、v4 改后；评审页 | `src/`、`page.json`、`page/`、README | 用户确认或按 D-003 定稿，登记表改“已确认” |
| 2 | c1、c2：`roomBackdropOf(room)`（`room.data` 是 `JdLiveRoom` 且 `background` 不空时返回它，否则封面、头像），沉浸背景和暗封面都用它 | `logic/`、`player_view.dart`、`player_status.dart`、测试 | 验收 1～3、5 |

## 测试

- 改之前会失败：`apps/pure_live/test/features/live_play/live_play_layouts_test.dart` 加用例“京东竖屏全屏、房间没有封面、`data` 是带 `background` 的 `JdLiveRoom`：`ambient-backdrop-cover` 的地址是 background”（现在没有封面图）。
- 加：有封面时也用 background（X2 建议 A）；其他平台的房间 `data` 不是 `JdLiveRoom` 时用封面；纯音频（`live-play-audio-cover`）用 background。
- `JdLiveRoom` 用 `fixtures/jdlive/S02-play-live` 的播放接口样本（`JdLiveApi.play`）构造，不访问真实平台；定时器至少 1 秒。
- `apps/pure_live` 跑 `flutter analyze`、全部 `flutter test`、`dart format --output=none --set-exit-if-changed .`；`python3 tools/gate/check_ui_structure.py`。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 关注一个正在直播的京东直播间；杀掉应用重开；从关注页直接进 | 竖屏全屏背景是模糊的直播画面（不是纯渐变） |
| 2. 双击进横屏全屏 | 画面两边是同样的模糊背景 |
| 3. 菜单 → 纯音频 | 中间的暗封面是模糊画面 |
| 4. 从推荐 → 京东进另一个直播间 | 同样是模糊画面；关注页、观看历史里这张卡片的封面仍是清楚的卡片封面 |
| 5. 进一个哔哩哔哩竖屏直播间 | 背景和改之前一样（房间封面） |

## 风险和注意

- `getRoomDetailForRefresh` 不带 `data`：刷新后 `room.data` 可能变空，要确认直播间刷新时保留原来的 `data`（`room_controller.dart` 的刷新合并），否则背景会在刷新后跳回封面。
- 模糊图地址可能过期：加载失败时 `AmbientBackdrop` 已经回落到渐变，不用另外处理。
- 可能冲突的文件：`player_view.dart`、`player_status.dart`（A07 的其他界面任务也常改）。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 效果图工具：`tools/ui/mock/README.md`（每台机器准备一次），`python3 tools/ui/mock/render.py docs/A-界面设计/A07-直播间界面/A07.16-京东直播间模糊背景/src/`，评审页 `python3 tools/ui/mock/page.py docs/A-界面设计/A07-直播间界面/A07.16-京东直播间模糊背景/page.json`。
- 分支 `ai/A07.16` 或本机工作区；提交信息以 `[A07.16]` 开头（英文）；不推 master。
- 提交前：`dart format --output=none --set-exit-if-changed .`、`flutter analyze`、`flutter test`；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”、更新登记表的 `done`、`next`、`branch`。

## 报告（中文，简洁）

评审结果和定稿的改动；每条验收做到没有；测试数量；改了哪些文件；要在真机上看的；可能冲突的文件。
