# G01.3 映客默认播 HEVC：按名字选“原画”绕过了“优先 H.264”

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能
- 来源：2026-10-07 docs v2 核对：E 组（[E02 说明](../../../E-直播平台/E02-其他国内平台/README.md)“已知问题”：映客默认 HEVC，`play_quality.dart:7`）、G 组复核属实（[G01 说明](../README.md)“已知问题”：`play_quality.dart:9`；映客的“原画”只有即构的 HEVC 线路，`inke_api.dart:165-169`）
- 相关：已批准升级 14-5（映客 HEVC 作“原画”，默认仍 H.264）、22-3 和统一原则“默认编码”（[specs/UPGRADES.md](../../../specs/UPGRADES.md)）；“优先 H.264”的默认值由 [G01.2](../G01.2-高通硬解评估/README.md) 在 K90 上定，和本任务无先后；映客适配器 [E02.5](../../../E-直播平台/E02-其他国内平台/E02.5-映客/README.md)；进房选清晰度 [C01](../../../C-直播间/C01-进房和房间逻辑/README.md)；多画面 [N01](../../../N-多画面和投屏/N01-多画面/README.md)；决定 D-001、D-018
- 任务书：[brief.md](brief.md)

## 目标

设置“优先 H.264 编码”开着（默认）时，进映客直播间默认播 H.264 的 FLV，HEVC 的“原画”只有用户自己在清晰度菜单里选才播。现在默认清晰度是“原画”，按名字一找就找到映客那个只有 HEVC 线路的“原画”，“优先 H.264”对映客等于没开；K90 上 HEVC 硬解不稳时会先失败、再退到软解，起播慢。

同一个根因还会影响别的“按编码排清晰度”的平台：17LIVE（“优先 H.264”时 H.264 转码排第一，后面的“原画”可能是 HEVC）、百度（同一档 H.264 在 H.265 前）、快手（只有 HEVC 的档排后面）。只要哪一档的名字正好等于偏好（“原画”“超清”……）而它是 HEVC，就会被选中。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11`） | 现在（文件:行） | 要做到 |
|---|---|---|---|
| 映客的清晰度 | 只有 `FLV`（网宿的 H.264 转码）一档 | `InkeApi.flv`、`InkeApi.original`（`packages/live_core/lib/src/sites/inke/inke_api.dart:161-169`，“原画”是即构 FLV、HEVC，codec id 12）；`InkeSite.getPlayQualities`（`inke_site.dart:345-351`）：“优先 H.264”开 → `[FLV, 原画]`，关 → `[原画, FLV]` | 不变 |
| 默认选哪档 | `lib/modules/live_play/controllers/player_controller.dart:611` `_setDefaultResolution`：先按名字找，找不到按 5 个名字的相对位置 | `apps/pure_live/lib/shared/rooms/play_quality.dart:7-16` `defaultQualityIndex`：同 3.x，名字完全相同就用（`:9-10`）；偏好 `preferResolution` 默认“原画”（`packages/live_store/lib/src/settings/settings.dart:270-275`）。直播间 `apps/pure_live/lib/features/live_play/logic/room_controller.dart:434`、多画面 `features/multiview/logic/multiview_controller.dart:544` 调它 | “优先 H.264”开时，名字匹配跳过 HEVC 档（还有非 HEVC 档可选时），退到按位置选（第一档，也就是平台排在前面的 H.264） |
| 清晰度知不知道编码 | 不知道 | `LivePlayQuality`（`packages/live_core/lib/src/live_area.dart:134-160`）没有编码；编码在线路上（`LivePlayLine.codec`，`play_line.dart:63-64`），要解析地址后才知道；映客线路 `inke_api.dart:624-641`（FLV `avc`、即构按 `codecInfo=8192` 判 `hevc`） | 清晰度上加一个可选的编码提示（只加不改），由知道的平台填 |
| “优先 H.264”设置 | 3.x 没有 | `Settings.preferH264` 默认开（`settings.dart:293`），注释“H.264 qualities first so HEVC is only played when chosen by hand” | 名副其实 |

## 方案

- c1 `packages/live_core/lib/src/live_area.dart`：`LivePlayQuality` 加可选字段 `String? codec`（`avc`、`hevc`；只是提示，不参与 `selectionId` 和相等判断），文档注释写明“平台在不解析地址时就知道这一档的编码才填”。
- c2 平台填编码：映客 `InkeApi.original` 填 `hevc`、`InkeApi.flv` 填 `avc`；17LIVE（`seventeenlive_api.dart:823-832`，`h264QualityId` 那档 `avc`，其他按样本里的编码填，不知道的不填）；百度（`baidulive_api.dart:1303-1310`，`variant.codec` 已有）；快手（`kuaishou_api.dart:673-705` 的 `hevcOnly` → `hevc`）。只填确定的。
- c3 `play_quality.dart`：`defaultQualityIndex(qualities, preferred, {bool preferH264 = false})`：名字匹配时，`preferH264` 为真、匹配到的档 `codec == 'hevc'`、列表里还有不是 `hevc` 的档 → 当作没匹配到，走按位置的规则；其余照旧。两个调用处传 `store.settings.get(Settings.preferH264)`。
- 不改：各平台的排序规则；“优先 H.264”的默认值（G01.2 定）；清晰度菜单的名字和 HEVC 标记（A07.6）；录制选清晰度（`packages/live_record` 有自己的规则，另看，见“留下的问题”）。

## 验证

- 自动测试：`apps/pure_live/test/features/live_play/live_play_controller_test.dart:317` 的“starting quality follows 3.x's preference rules”加 HEVC 的几种情况；`packages/live_core/test/sites/inke_site_test.dart`、`seventeenlive_site_test.dart`、`baidulive_site_test.dart`、`kuaishou_api_test.dart` 断言编码提示；直播间用例：映客房间、偏好“原画”、“优先 H.264”开 → 打开的是 FLV。
- 真机：K90 上进映客直播间看默认清晰度（任务书“真机验证”）；做之前“未开始”。

## 留下的问题

- 录制选清晰度（`RecordStreamResolver`）是否有同样的问题没有核对，写进本任务记录；有的话另开 H 组任务。
- “优先 H.264”默认开还是关、HEVC 硬解在 K90 上稳不稳由 G01.2 定；结论变了不影响本任务的规则（规则只在开着时生效）。
