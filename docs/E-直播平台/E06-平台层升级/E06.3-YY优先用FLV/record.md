# E06.3 YY 优先用 FLV：记录

- 日期：2026-10-08
- 执行者：Claude
- 分支和提交：本机工作区（接在 E05.3、C01.4 后面，从 master `820129343` 开始），提交 `[E06.3]`
- 任务书：[brief.md](brief.md)；设计或说明：[README.md](README.md)

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| c1 | 做了 | `app/platforms.dart` 加编译常量 `yyFlvFirst`（默认开，`--dart-define=YY_FLV_FIRST=false` 可临时关掉，真机上对比延迟用；不进设置页），YY 那一行传 `flvFirst: yyFlvFirst` |
| c2 | 做了 | `packages/live_record/lib/src/resolver.dart` 的 `_resolveLive` 找上次画质时改用 `_previousIndex`：原样找不到、平台是 YY、id 以 `YyApi.mobileHlsPrefix` 开头时，用 `YyApi.flvQualityId` 在平台给的画质列表（最好的在前）里换算再找。其他平台、其他 id 不变 |
| c3 | 做了 | 核对 `defaultQualityIndex`（见下表），用 E02.1 的样本跑了一遍直播间进房 |
| c4 | 待真机 | 15 分钟续签、换线、延迟、首帧要在 K90 上看 |

## 根因

- `apps/pure_live/lib/app/platforms.dart:160`（改之前）建 `YySite(http, cookies: cookies)` 没传 `flvFirst`，平台层默认 `false`（`packages/live_core/lib/src/sites/yy/yy_site.dart:36`），所以一直是移动 HLS 先。
- `YyApi.flvQualityId`（`yy_api.dart:756`）写好了但没人调用；录制按 id 找上次画质在 `resolver.dart:238-240`（改之前）只按原样比 `selectionId`，FLV 列表里没有 `mobile-hls:…`，找不到就退回按偏好排的第一档。

## 默认档（c3）

直播间按名字选档的规则（`shared/rooms/play_quality.dart` 的 `defaultQualityIndex`：名字相同优先，否则按 3.x 五档的相对位置）不变。YY 的 FLV 档名在 3.x 五个偏好下选到：

| 偏好 | 两档频道（高清、流畅） | 三档频道（蓝光、高清、流畅） | 改之前（高清 · 720p、流畅 · 360p） |
|---|---|---|---|
| 原画（默认） | 高清 | 蓝光 | 高清 · 720p |
| 蓝光8M | 高清 | 高清 | 高清 · 720p |
| 蓝光4M | 流畅 | 高清 | 流畅 · 360p |
| 超清 | 流畅 | 流畅 | 流畅 · 360p |
| 流畅 | 流畅（名字相同） | 流畅（名字相同） | 流畅 · 360p |

两档频道和改之前一样；三档频道默认偏好“原画”选到最好的“蓝光”。“蓝光8M”在三档频道落到“高清”（相对位置规则，和其他平台一致，没有改）。

## 改了哪些文件

- `apps/pure_live/lib/app/platforms.dart`：`yyFlvFirst` 常量和 YY 那一行。
- `packages/live_record/lib/src/resolver.dart`：`_previousIndex`。
- 测试：`apps/pure_live/test/platforms_test.dart`、`apps/pure_live/test/features/live_play/live_play_controller_test.dart`、新文件 `packages/live_record/test/yy_quality_id_test.dart`。

## 新设置、翻译键、门禁基线

- 无（`YY_FLV_FIRST` 是编译常量，不是设置）。

## 测试

- 新增 6 个：
  - `platforms_test.dart`“E06.3: YY lists the FLV qualities first…”——改之前失败（`flvFirst` 是假的）。
  - `yy_quality_id_test.dart` 3 个：存 `mobile-hls:4000`、偏好“流畅”时录“高清”（第一档）；存 `mobile-hls:1200` 时录“流畅”（最后一档）——这两个改之前失败；FLV 的 id、没有 id、不认识的 `mobile-hls:999` 照旧（改之前也通过）。画质列表用 E02.1 录的 `S05-detail-live`、`S06-streams-g1`（stream-manager 的“高清”“流畅”），地址是脚本给的（录下的样本只有一档的线路）。
  - `live_play_controller_test.dart` 2 个：YY 直播间用 `S05-detail-live`、`S06-streams-g1`、`S06-streams-g2`、`S06-streams-g2-l10` 进房，清晰度“高清”“流畅”，默认第一档，两条 FLV 线路，不提示；五个偏好在两档和三档 FLV 列表上的结果（上表）。
- `packages/live_record` 64 个、`apps/pure_live` 918 个全部通过；`packages/live_core` 没改；format、`dart analyze --fatal-infos` 无问题。

## 真机上要看的

- brief“真机验证”1～5：清晰度是“蓝光”“高清”“流畅”（看频道），线路每档两条；和 YY 官网对比延迟；播放 15 分钟不断流（10 分钟签名到期前续签，不出重连提示）；录制后“再录一次”清晰度一致；断网 10 秒恢复后继续播放。
- 性能测量（首帧、延迟）的“改之前”要用 `--dart-define=YY_FLV_FIRST=false` 打一个包对比。
- 已有的 YY 录制任务（存着 `mobile-hls:4000`）启动恢复时应该录最好的一档。

## K90 复查（2026-10-08，master a3b799737）

- YY“小颖儿”：清晰度菜单“高清、流畅”（两档频道），每档两条线路 ✓；“获取直链”显示线路 1 是 `https://tx-flv-web.yy.com/live/…`，确实是 FLV ✓。
- 和 YY 官网比延迟、连续播 15 分钟、录制“再录一次”的清晰度、断网恢复：没看。

## K90 复查（2026-10-08）

- 补充：YY 录制“再录一次”的清晰度一致（高清），录到的是 FLV 线路（H01.6 复查的 MP4 为 H.264+AAC）✓。
