# G01.3 映客默认播 HEVC：记录

- 日期：2026-10-08
- 执行者：Claude（Opus 5.5）
- 分支和提交：本机工作区，`3217162ce`
- 任务书：[brief.md](brief.md)；设计或说明：[README.md](README.md)

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| c1 | 做了 | `LivePlayQuality.codec`（可选，`withPlaybackUnconfirmed` 带上）；类本来就没有重写 `==`/`hashCode`，`selectionId` 不变 |
| c2 | 只做了映客 | 同时有另一个 AI 在改国内平台的适配器，这次限定只改映客；17LIVE、百度、快手的编码提示没填（行为同以前：没有提示就不跳过），见“停在哪” |
| c3 | 做了 | 跳过之后按位置选；位置正好又落在 HEVC 档时取最近的非 HEVC 档（同样近取更好的一档），任务书没写这一步，补上是为了“只在手动选时播 HEVC”在任何列表下都成立 |
| 验收 1 | 映客做到 | 17LIVE、百度、快手要等它们填了编码提示才生效 |
| 验收 2～6 | 做到 | |

## 根因

- 默认档先按名字找（`apps/pure_live/lib/shared/rooms/play_quality.dart:9-10`，3.x `_setDefaultResolution` 的规则），偏好默认“原画”；映客的“原画”只有即构的 HEVC 线路（`inke_api.dart:169`）。“优先 H.264”只在平台里把 H.264 档排前面（`inke_site.dart:350`），名字一匹配就把排序绕过去了；清晰度本身也不知道自己的编码（编码只在解析后的线路上，`LivePlayLine.codec`），选档时没法判断。

## 改了哪些文件

- `packages/live_core/lib/src/live_area.dart`：`LivePlayQuality` 加 `codec`。
- `packages/live_core/lib/src/sites/inke/inke_api.dart`：`flv` 填 `avc`（网宿 H.264 转码，线路也是 `avc`，`:628`），`original` 填 `hevc`（REG-INKE-002：录到和探测过的即构线路都是 `codecInfo=8192`）。
- `apps/pure_live/lib/shared/rooms/play_quality.dart`：`defaultQualityIndex(…, {preferH264})`。
- `apps/pure_live/lib/features/live_play/logic/room_controller.dart`、`apps/pure_live/lib/features/multiview/logic/multiview_controller.dart`：传 `Settings.preferH264`。

## 新设置、翻译键、门禁基线

- 无。

## 测试

- 新增 6 个：`live_play_controller_test.dart`“with 优先 H.264 the name match skips an HEVC quality (G01.3)”和“G01.3: the starting quality of an Inke-like room”一组 3 个（开着默认打开 FLV、关着按名字选原画、手动选原画照播）；`multiview_controller_test.dart` 一个（开着跳过、关着照旧）；`live_site_test.dart` 一个（编码提示不进 `selectionId`，标记未确认时带上）。改了 1 个：`inke_site_test.dart` 断言两档的编码提示。
- 改之前：新增的全部失败（先是没有 `codec`/`preferH264` 参数编译失败；加了字段后多画面用例、映客清晰度断言失败）；原有偏好规则用例（`:317`）没改，照样通过。
- 全部通过：`packages/live_core` 3643 个，`apps/pure_live` 897 个；所有成员 `dart analyze --fatal-infos` 无问题。

## 录制选档（任务书“留下的问题”）

- 有同样的问题，而且更直接：`packages/live_record/lib/src/resolver.dart:296-324` `orderQualities` 先按 `sort` 从大到小排（映客“原画”`sort: 1`、FLV `0`），再按名字找偏好（录制默认“原画”），不看“优先 H.264”。所以录映客默认录的是 HEVC 的“原画”。录制是直接存流，HEVC 本身能录，但 FLV 里的 codec 12 不是标准写法，别的播放器可能放不了。建议另开 H 组任务（这次不改 `packages/live_record`）。

## 真机上要看的

- 设置 → 视频“优先 H.264 编码”开、播放偏好“原画”；进一个主播开了原画的映客直播间：清晰度显示 FLV，菜单里“原画”带 HEVC 标记、没选中。
- 手动选“原画”：换成 HEVC 线路播（硬解或自动软解）。
- 关掉“优先 H.264”，重新进同一个直播间：默认“原画”。
- 多画面里加同一个映客房间：开着时是 FLV。
- 17LIVE 这次没填编码提示，任务书第 4 步暂时不用看。

## 停在哪（没做完时写）

- 做完的阶段：1（映客部分）。
- 没做的：17LIVE（`seventeenlive_api.dart:774`，`h264QualityId` 那档 `avc`）、百度（`baidulive_api.dart:1307`，`variant.codec`）、快手（`kuaishou_api.dart:347`，`hevcOnly` → `hevc`）的编码提示，各一行；等改国内平台的那项工作合并后补上，选档规则不用再改。
