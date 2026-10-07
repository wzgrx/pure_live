# G01.4 Steam 选清晰度实际仍是自适应：用档位限定 HLS 变体：任务书

## 背景

- 来源：2026-10-07 docs v2 核对。E 组指出 UPGRADES 27-7（“按播放列表里的档位提供可选画质”）写“完成”不对，G 组复核：各档都返回同一个主列表（`packages/live_core/lib/src/sites/steambroadcast/steambroadcast_site.dart:440-448`），`SteamBroadcastVariant.selectIn` 只有测试调用。维护者登记为本任务，27-7 改“部分完成”。
- 现象（有代理时）：Steam 直播间清晰度菜单选“480p”，画面还是播放器自己挑的（多半是最高档），流量不变；选“1080p60”在网差时会自动掉档。菜单显示的档名和实际不一致。
- 为什么现在做：第三档（海外平台、要代理）；规模小（约 2 小时）。
- 已经做过的：27-7 的列表部分（E03.14，变体解析、档名、`appliedQualityData`）；niconico 限定变体（G01.1 的 `NiconicoRecipeOpener`）。

## 目标和验收

1. Steam 直播间选具体档位（例如 720p）：mpv 拿到的主列表只有这个变体（和它的音频组），实际分辨率是 720p（播放器调试信息或 `video-params`）。
2. 换档：画面换成新档（同 G01.1 的换清晰度流程，旧画面不先黑）。
3. “自适应 HLS”：照旧把完整主列表交给 mpv。
4. 主列表刷新、CDN 换主机后（恢复时重新取的回答），仍限定同一个 `id` 的变体（按最近的 `BANDWIDTH`）；找不到时报错，会话按现有规则换线路或提示，不静默回到自适应。
5. 复制直链、投屏给的仍是主列表地址（行为不变）。
6. 其他平台的路由不变（`plan_test.dart` 现有的路由用例照样通过）；测试和门禁通过。

## 现状（读代码得出，写文件:行）

- 平台：`steambroadcast_site.dart`：`_offered`（`:431-435`）按 `selectionId` 找档；`_resolution`（`:440-448`）`LivePlayUrlResolution.lines([SteamBroadcastApi.line(data.master!, codec: …)], appliedQualityData: '${offered.selectionId}')`；`getPlayQualities`（`:453-454`）；`resolvePlayUrlsRaw`（`:466-471`）。`steambroadcast_api.dart`：`SteamBroadcastVariant`（`:49-113`），`selectIn`（`:82-95`，按 `id` 和最近 `BANDWIDTH` 选，找不到抛 `FormatException`）；`line`（`:1029-1030`）；自适应档 `quality`（`:440`）。
- 解析结果：`packages/live_core/lib/src/live_site.dart:80-175` `LivePlayUrlResolution`：`lines`、`owned`、`withSourcePolicies`（`:126` 起，按线路地址的 `sourceQueryPolicies`）。
- 播放层：`packages/live_media/lib/src/source.dart`：`MediaRoute`（`:88-127`）、`PlaybackPlan.queryPolicyFor`（`:204`）；`input.dart:112-160` `MediaOpener.open`：按路由开，`hlsRelay` 时 `relay.openHls(line, recipe: HlsRelayRecipe(queryPolicy: …))`（`:150`）。中继：`relay/hls_relay.dart:18-38` `HlsRelayRecipe({cookies, restore, queryPolicy, master})`，`master` 改写线路自己的主列表；niconico 的写法 `inputs/recipes.dart:22-50`（`HlsMasterSelection.fromMaster(…).rewrite(source, text)`）。`HlsMasterSelection`：`packages/live_core/lib/src/hls_master.dart:10`。
- 复制直链、投屏：直播间 `StreamUse.copy` / `StreamUse.cast`（`features/live_play/dialogs/` 的取流面板）直接用解析结果的地址，不经过 `MediaOpener`。
- 测试：`packages/live_core/test/sites/steambroadcast_site_test.dart:774-800`；样本 `fixtures/steambroadcast/S09-master-live`（变体 `/3500000/video.m3u8` 等）；`packages/live_media/test/relay_test.dart`（niconico 变体选择）、`plan_test.dart`（路由）。

## 3.x 基线

- 3.x Steam 只有“自适应 HLS”（`lib/core/site/steambroadcast/`），没有档位；档位是 27-7 的已批准升级。
- 3.x 的 niconico 用 `HlsMasterSelection`（`RESOLUTION`、`BANDWIDTH`，0 个或多个匹配算失败）限定变体，4.x 照搬在 `recipes.dart:22-50`；本任务照同样的方式。
- 要保留：自适应档的行为；Steam 不要请求头、没有租期（`steambroadcast_api.dart:1024-1027`）。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节、第 8 节、第 14 节）。
2. `docs/specs/ENGINEERING.md`（第 4 节分层：`live_media` 依赖 `live_core`，不能反过来）；`docs/specs/UPGRADES.md` 的 27-7。
3. 本文件夹的 `README.md`；`docs/G-播放/G01-引擎/README.md`（取流管线和中继）；`docs/E-直播平台/E03-海外平台/E03.14-Steam直播/README.md`。

## 范围

- 可以改：`packages/live_core`（`hls_master.dart` 加接口、`live_site.dart` 的 `LivePlayUrlResolution` 加可选字段、Steam 适配器）；`packages/live_media`（`source.dart`、`input.dart`，只为“HLS + 选择器 → 中继改写主列表”）；对应测试；`docs/specs/UPGRADES.md` 的 27-7（完成后改回“完成（G01.4）”）；本文件夹。
- 不能改：其他平台的解析结果和路由；自适应档；复制直链、投屏、录制；`live_player` 的会话（换清晰度流程）；版本号、`assets/version.json`、`assets/releases.json`；签名配置。

## 方案和阶段

| 阶段 | 做什么（对应 README 的 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | c1：`HlsVariantSelector` 接口、`SteamBroadcastVariant implements` 它；`LivePlayUrlResolution` 加 `sourceVariantSelectors`（默认空，`lines(...)` 加可选参数或新工厂，只加不改），Steam 变体档填上。c2：`PlaybackPlan.variantSelectorFor`、`MediaRoute.of(…, variantSelector:)`（HLS 且有选择器 → `hlsRelay`）、`MediaOpener` 组 `HlsRelayRecipe(master: …)`（可以和 `queryPolicy` 同时有）。c4：完成后改 UPGRADES 27-7 | 见“可以改” | 验收 1～6 |

只有一个阶段（规模小）。

## 测试

- 改之前会失败：`packages/live_media/test/relay_test.dart` 加“a Steam variant's line serves the master with that variant only (G01.4)”：本机回环上放 `S09-master-live` 的主列表，按 720p 的选择器开，取中继给出的主列表，只有一条 `#EXT-X-STREAM-INF`（指向 `/3500000/video.m3u8` 那个变体）和它的 `#EXT-X-MEDIA` 音频。
- `plan_test.dart`：HLS 线路有选择器 → `MediaRoute.hlsRelay`；没有 → `direct`（现有用例不改）。
- `steambroadcast_site_test.dart:774`：解析结果里这条线路有选择器，`selectIn` 选中的路径同现在；自适应档没有选择器。
- CDN 换主机：用另一个主机名的同一份主列表，选择器仍选中同一个变体；变体消失时开中继报错（`FormatException` 被会话当作打开失败）。
- 测试里的定时器至少 1 秒（D-017）；不访问真实平台（用 `fixtures/`）。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 开着代理进一个在播的 Steam 直播间（推荐 → Steam），清晰度选“480p” | 画面明显变糊；长按画面或播放器调试信息里分辨率是 854×480 左右 |
| 2. 换成“1080p60”（有的话） | 画面变清楚，帧率 60 |
| 3. 换回“自适应 HLS” | 恢复播放器自选 |
| 4. 菜单 → 获取直链 | 复制到的仍是 `master.m3u8` 地址 |

## 风险和注意

- 改写后的主列表里的相对地址：`HlsMasterSelection.rewrite` 会把变体和音频地址写成绝对地址（niconico 已验证），Steam 的音频组在主列表的 `#EXT-X-MEDIA` 里（变体本身没有音频，`steambroadcast_api.dart:44-46`），不能丢。
- 中继多一层：mpv 的 HLS 请求经本机转发；Steam 没有请求头和租期，中继只改主列表、媒体列表和分片原样转发，开销很小。
- 恢复时重新取的主列表可能主机不同：选择器按 `id` 和带宽找，不按地址。
- 可能冲突的文件：`live_site.dart`（C01.4、G01.3 也改 `live_core` 的清晰度相关代码）；`source.dart`、`input.dart`（G02.2、G03.1 改播放层）。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 分支 `ai/G01.4` 或本机工作区；提交信息以 `[G01.4]` 开头（英文）；不推 master。
- 提交前：改过的包（`packages/live_core`、`packages/live_media`）跑 `dart format --output=none --set-exit-if-changed .`、`dart analyze`、`dart test`；`apps/pure_live` 跑全部 `flutter test`；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”、更新登记表的 `next`、`branch`。

## 报告（中文，简洁）

每条验收做到没有；新加的接口和字段；测试数量（改之前失败几个）；改了哪些文件；录制 Steam 时有没有同样的问题；要在真机上看的；可能冲突的文件。
