# G01.3 映客默认播 HEVC：按名字选“原画”绕过了“优先 H.264”：任务书

## 背景

- 来源：2026-10-07 docs v2 核对，E 组发现、G 组复核属实（[G01 说明](../README.md)“已知问题”“映客默认播 HEVC”）。维护者登记为本任务。
- 现象：设置 → 视频“优先 H.264 编码”开（默认），播放偏好清晰度“原画”（默认）；进一个映客直播间（主播开了原画时），默认播的是“原画”——即构的 HEVC 线路，不是 H.264 的 FLV；清晰度菜单里 FLV 排在第一，却没被选中。
- 为什么现在做：第二档；规模小（约 1.5 小时）。设置的说明和行为不符；K90 上 HEVC 硬解有问题时会先失败再软解（G01.2 还没测）。
- 已经做过的：14-5（映客“原画”，E02.5）；“优先 H.264”设置和各平台的排序（J01.1、A11.3、G01.1）。

## 目标和验收

1. “优先 H.264”开、偏好“原画”：映客直播间默认打开 FLV（H.264）；17LIVE、百度、快手的 HEVC 档名字等于偏好时同样不被默认选中（有非 HEVC 档时）。
2. “优先 H.264”关：照旧按名字选（映客默认“原画”）。
3. 只有 HEVC 档的房间（例如某平台这一场只给 HEVC）：照旧选它，不会选不出来。
4. 用户在清晰度菜单里手动选“原画”：照常播 HEVC（不受影响）。
5. 现有的偏好规则用例（`live_play_controller_test.dart:317`）不改照样通过；多画面同样生效。
6. `LivePlayQuality` 只加一个可选字段，`selectionId`、相等判断、存档的清晰度编号都不变；测试和门禁通过。

## 现状（读代码得出，写文件:行）

- 选默认档：`apps/pure_live/lib/shared/rooms/play_quality.dart:7-16` `defaultQualityIndex(qualities, preferred)`：`indexWhere((q) => q.quality == preferred)`（`:9`），找到就用（`:10`）；找不到按 `['原画', '蓝光8M', '蓝光4M', '超清', '流畅']` 的相对位置（`:11-15`）。调用：直播间 `apps/pure_live/lib/features/live_play/logic/room_controller.dart:431-434`（`_preferredQuality` `:408-412` 按网络取 `preferResolution` 或 `preferResolutionCellular`）；多画面 `features/multiview/logic/multiview_controller.dart:543-544`。
- 设置：`packages/live_store/lib/src/settings/settings.dart:270-275` `preferResolution` 默认“原画”；`:286` 允许的值；`:293` `preferH264` 默认开。
- 清晰度模型：`packages/live_core/lib/src/live_area.dart:134-160` `LivePlayQuality({quality, data, id, sort, isPlaybackUnconfirmed})`，没有编码；编码在线路上 `LivePlayLine.codec`（`packages/live_core/lib/src/play_line.dart:63-64`）。
- 映客：`packages/live_core/lib/src/sites/inke/inke_api.dart:161-169`（`flv` `id: 'flv'`、`original` `quality: '原画', id: 'origin', sort: 1`）；`inke_site.dart:345-351`（排序）；线路编码 `inke_api.dart:611-641`。
- 同一根因的平台：17LIVE `packages/live_core/lib/src/sites/seventeenlive/seventeenlive_api.dart:820-832`（H.264 转码 `h264QualityId` 排第一，其余可能 HEVC，REG-17LIVE-001）；百度 `baidulive/baidulive_api.dart:1286-1310`（`ordered` 按编码排，`variant.codec`）；快手 `kuaishou/kuaishou_api.dart:345-347`、`:673-705`（`hevcOnly` 的档排后）。
- 测试：`apps/pure_live/test/features/live_play/live_play_controller_test.dart:317-324`；`packages/live_core/test/sites/inke_site_test.dart`、`seventeenlive_api_test.dart`、`baidulive_api_test.dart`、`kuaishou_api_test.dart`。

## 3.x 基线

- `git show v3.2.11:lib/modules/live_play/controllers/player_controller.dart`：`_setDefaultResolution`（`:611`），先名字后位置，4.x 照搬；3.x 映客只有 FLV 一档，没有这个问题，也没有“优先 H.264”。
- 要保留：名字和位置的规则（3.x 用户的习惯）；`preferResolution`、`preferResolutionCellular` 的键名和取值（D-018）；14-5“默认仍 H.264”的承诺。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节、第 8 节、第 14 节）。
2. `docs/specs/ENGINEERING.md`（第 4 节分层）；`docs/specs/UPGRADES.md` 统一原则“默认编码”、14-5、22-3。
3. 本文件夹的 `README.md`；`docs/G-播放/G01-引擎/README.md`；`docs/G-播放/G01-引擎/G01.2-高通硬解评估/README.md`；`docs/E-直播平台/E02-其他国内平台/E02.5-映客/README.md`。

## 范围

- 可以改：`packages/live_core/lib/src/live_area.dart`（只加字段）；映客、17LIVE、百度、快手的 `*_api.dart`（只填编码提示）；`apps/pure_live/lib/shared/rooms/play_quality.dart`；两个调用处（`room_controller.dart`、`multiview_controller.dart`，只加参数）；对应测试；本文件夹。
- 不能改：各平台的排序规则和清晰度名字；`preferH264` 的默认值（G01.2）；`selectionId`、存档的清晰度编号；录制的选档（`packages/live_record`）；清晰度菜单（A07.6）；版本号、`assets/version.json`、`assets/releases.json`；签名配置。

## 方案和阶段

| 阶段 | 做什么（对应 README 的 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | c1：`LivePlayQuality` 加 `final String? codec`（构造参数可选，`copyWith` 之类跟着带；不进 `==`/`hashCode`/`selectionId`）。c2：映客、17LIVE、百度、快手填确定的编码。c3：`defaultQualityIndex(…, {bool preferH264 = false})` 跳过 HEVC 的名字匹配（还有非 HEVC 档时）；直播间、多画面传设置 | 见“可以改” | 验收 1～6 |

只有一个阶段（规模小）。

## 测试

- 改之前会失败：`live_play_controller_test.dart` 加“with 优先 H.264 the name match skips an HEVC quality (G01.3)”：`[LivePlayQuality(quality: 'FLV', codec: 'avc'), LivePlayQuality(quality: '原画', codec: 'hevc')]`、偏好“原画”、`preferH264: true` → 0；`false` → 1；只有 `[原画 hevc]` → 0；没有编码提示的列表照旧。再加一个直播间用例：假平台给上面两档，设置默认，`engine.opens.single` 的地址是 FLV 那档的。
- 平台：`inke_site_test.dart`（两档的 `codec`）、`seventeenlive_api_test.dart`、`baidulive_api_test.dart`、`kuaishou_api_test.dart`（用现有样本断言编码提示；不知道的为 null）。
- `live_core` 的 `LivePlayQuality` 相等判断不受 `codec` 影响的小测试。
- 测试里的定时器至少 1 秒（D-017）；不访问真实平台（用 `fixtures/`）。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 设置 → 视频“优先 H.264 编码”开，播放偏好“原画”；进一个映客在播直播间（主播开了原画的） | 清晰度显示 FLV；清晰度菜单里“原画”带 HEVC 标记，没选中 |
| 2. 手动选“原画” | 换成 HEVC 线路播放（硬解或自动软解） |
| 3. 关掉“优先 H.264”，重新进同一个直播间 | 默认“原画” |
| 4. 有代理时 17LIVE 同样看一次（第 1、3 步） | 开着时默认 H.264 转码那档 |

## 风险和注意

- 编码提示必须确定才填：填错会让“优先 H.264”跳过本来是 H.264 的档；不确定就留 null（行为同现在）。
- `LivePlayQuality` 是 `const` 构造，很多平台的常量会受影响（只加可选参数，编译不受影响）。
- 进房提示“平台实际返回 xx，已按真实画质播放”（`resolveAppliedPlayQuality`）不受影响，但确认映客 FLV 时不会误报。
- 可能冲突的文件：`room_controller.dart`（C01.4、C01.5、C01.6、E05.4）；`live_area.dart`（C01.4 改清晰度命名规则）；`multiview_controller.dart`（N01.2）。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 分支 `ai/G01.3` 或本机工作区；提交信息以 `[G01.3]` 开头（英文）；不推 master。
- 提交前：改过的包（`packages/live_core`、`apps/pure_live`）跑 `dart format --output=none --set-exit-if-changed .`、analyze、测试；`apps/pure_live` 跑全部 `flutter test`；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”、更新登记表的 `next`、`branch`。

## 报告（中文，简洁）

每条验收做到没有；哪些平台填了编码提示、依据（样本、文件:行）；录制选档有没有同样的问题；测试数量（改之前失败几个）；改了哪些文件；要在真机上看的；可能冲突的文件。
