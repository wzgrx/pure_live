# E06.3 YY 优先用 FLV：任务书

## 背景

- 来源：已批准升级 6-1（`docs/specs/UPGRADES.md`）：“FLV 优先：先用修好的 FLV 接口，移动 HLS 兜底”，落地方式“等播放能按有效期续签后切到 FLV 优先”。V03.3（2026-10-03）核对：平台层开关 `YySite.flvFirst` 在 E02.1 做好了，播放按租期续签在 G01.1、G02.1 做好了，只差应用打开它。
- 现象：YY 直播间的清晰度只有“高清 · 720p”“流畅 · 360p”（移动 HLS），延迟是 HLS 的延迟；FLV 只在移动 HLS 失败时顶上。
- 为什么现在做：第二档；改动小，用户能感觉到延迟变低、多一档“蓝光”。
- 已经做过的：E02.1（`flvFirst`、6-4 每档两条 CDN）；G02.1（租期预取、`LineFallback` 换线）。

## 目标和验收

1. 应用里 YY 的适配器 `flvFirst` 为真：进 YY 直播间，清晰度列表是平台的档名（“蓝光”“高清”“流畅”，看频道），线路是 FLV，每档两条。
2. 移动 HLS 只在 FLV 没有流或请求失败时出现（`YySite` 已有的双向兜底，不改）。
3. 录制任务里存的 `mobile-hls:4000` / `mobile-hls:1200` 在 FLV 列表里换算到第一档 / 最后一档，“再录一次”和启动恢复选对档位。
4. 播放 15 分钟以上不断流（签名 10 分钟到期前续签）。
5. 测试和门禁通过。

## 现状（读代码得出，写文件:行）

- 应用：`apps/pure_live/lib/app/platforms.dart:160`：`SiteIds.yy: () => YySite(http, cookies: cookies),`，没有 `flvFirst`。
- 平台层：`packages/live_core/lib/src/sites/yy/yy_site.dart:36` 构造参数 `flvFirst`（默认 `false`）；`:47` 字段说明；`:399-407` 取画质时按它排两条路线的先后。
- 画质 id 换算：`packages/live_core/lib/src/sites/yy/yy_api.dart:748-764` 的 `YyApi.flvQualityId(id, qualities)`：`mobile-hls:4000` → FLV 第一档，`mobile-hls:1200` → 最后一档，其他原样；没有调用方。
- 租期：`yy_api.dart:766-781` 的 `YyApi.lease`（`t` 是签名到期秒数，提前 `leaseLead` 续）；播放会话在 `refreshAt` 预取：`packages/live_player/lib/src/session.dart:28` 附近的说明。
- 录制按 id 选档：`packages/live_record/lib/src/resolver.dart:234-236`（`previousQualityId` 在 `ordered` 里按 `selectionId` 找，找不到是 -1，退回按 `preferredQuality` 排的顺序）；任务字段 `packages/live_record/lib/src/task.dart:140` 的 `selectedQualityId`。
- 直播间选默认档按名字：`apps/pure_live/lib/shared/rooms/play_quality.dart:7` 的 `defaultQualityIndex`（名字相同优先，否则按 3.x 五档的相对位置）。

## 3.x 基线

- `git show v3.2.11:lib/core/site/yy/yy_site.dart`：`:437-445` 先 stream-manager（`:291` 请求），失败退移动 HLS（`:395-424`，画质名 `:415` 的“流畅”“高清”，id `mobile-hls:<rate>`）。3.x 的 stream-manager 请求从没成功过（E02.1 记录“问题 1”），所以 3.x 用户看到的是移动 HLS；本任务让 3.x 本来的设计生效（已批准）。
- 3.x 只存全局画质名，没有 YY 的画质 id：迁移用不到换算，换算只给 v4 自己的录制任务。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节、第 8 节、第 14 节）。
2. `docs/specs/ENGINEERING.md`。
3. 本文件夹的 `README.md`；`docs/E-直播平台/E02-其他国内平台/E02.1-YY直播/record.md`（6-1、6-4、“画质 id”和“设置项”两段）；`docs/specs/UPGRADES.md` 的 6-1、6-4。

## 范围

- 可以改：`apps/pure_live/lib/app/platforms.dart`（只改 YY 那一行，必要时加一个常量）；`packages/live_record/lib/src/resolver.dart`（YY 旧 id 的换算）；对应的测试 `apps/pure_live/test/platforms_test.dart`、`packages/live_record/test/`。
- 不能改：`packages/live_core` 的 YY 解析（平台层已完成，有问题另开任务）；其他平台；设置页（`flvFirst` 不进设置）；版本号、`assets/version.json`、`assets/releases.json`；签名配置；3.x 的设置键名和含义。

## 方案和阶段

| 阶段 | 做什么（对应 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | c1 打开 `flvFirst`；c3 核对默认档 | `app/platforms.dart`、`test/platforms_test.dart` | 测试断言 YY 适配器 `flvFirst` 为真；用 E02.1 的样本跑一遍直播间进房测试，默认档按名字选对 |
| 2 | c2 录制任务旧 id 换算 | `packages/live_record/lib/src/resolver.dart`、`packages/live_record/test/` | 新测试：任务存 `mobile-hls:4000`，平台给 FLV 三档时选第一档；`mobile-hls:1200` 选最后一档；其他平台不受影响 |

## 测试

- 改之前会失败的测试：`platforms_test.dart` 里“YY 用 FLV 优先”——现在 `flvFirst` 是假的。
- `packages/live_record`：用 E02.1 录的样本：stream-manager 的 `fixtures/yy/S06-streams-g1`～`S06-streams-g3`（FLV）和移动 HLS 的 `fixtures/yy/S07-mobile-hls`造一个 `YySite(flvFirst: true)`，任务带 `selectedQualityId: 'mobile-hls:4000'`，断言选中的是 `qualities.first`。
- 测试里的定时器至少 1 秒；不访问真实平台。
- 改过的包跑 `dart format --output=none --set-exit-if-changed .`、`dart analyze`、`dart test`；`apps/pure_live` 跑全部 `flutter test`。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 热门 → YY，进一个直播间，打开清晰度菜单 | 档名是“蓝光”“高清”“流畅”（看频道），线路菜单每档两条 |
| 2. 同一频道开着 YY 官网（电脑或另一台手机），对比画面延迟 | 比改之前（移动 HLS）明显更低 |
| 3. 播放 15 分钟不动 | 不断流、不黑屏；`adb logcat` 里看到续签（会话的刷新）而没有重连提示 |
| 4. 在这个直播间开始录制，停止后在录制中心“再录一次” | 两次录的清晰度一致 |
| 5. 找一个移动 HLS 也有的频道，断网 10 秒再恢复 | 重连后继续播放（可能换到另一条线路） |

## 风险和注意

- FLV 地址 10 分钟到期，续签失败时会话会走重连；第 3 步就是看这个。
- 改 `resolver.dart` 时不要改其他平台按 id 选档的行为；换算只对 `SiteIds.yy` 且 id 以 `YyApi.mobileHlsPrefix` 开头时生效。
- 可能冲突的文件：`app/platforms.dart`（E06.2 也要在这里给 Twitch、FC2 传参数）；合并时两边都保留。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 分支 `ai/E06.3` 或本机工作区；提交信息以 `[E06.3]` 开头（英文）；不推 master。
- 提交前：改过的包跑 `dart format --output=none --set-exit-if-changed .`、analyze、测试；`apps/pure_live` 跑全部 `flutter test`；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”、更新登记表的 `done`、`next`、`branch`。

## 报告（中文，简洁）

每条做到没有；测试数量；改了哪些文件；YY 默认档在 3.x 偏好下选到哪一档；要在真机上看的；可能冲突的文件（`app/platforms.dart`）。
