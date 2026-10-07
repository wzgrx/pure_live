# E06.3 YY 优先用 FLV

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：已批准升级 [6-1](../../../specs/UPGRADES.md)（“FLV 优先：先用修好的 FLV 接口，移动 HLS 兜底”；落地方式“等播放能按有效期续签后切到 FLV 优先”）。V03.3 核对时发现平台层的开关早已做好、播放也能按租期续签，但应用建 `YySite` 时没打开它，状态列原来写“未排”。
- 相关：[E02.1](../../E02-其他国内平台/E02.1-YY直播/README.md)（YY 平台，[记录](../../E02-其他国内平台/E02.1-YY直播/record.md)的 6-1、6-4 和“画质 id”一节）；G01.1、G02.1（租期续签、换线）；H01（录制任务存的画质 id）；[E06.2](../E06.2-平台层新数据接到界面/README.md)（也改 `app/platforms.dart`）
- 任务书：[brief.md](brief.md)

## 目标

YY 直播默认走 stream-manager 的 FLV（延迟比移动 HLS 低，画质是平台自己的“蓝光 / 高清 / 流畅”，每档两条 CDN 线路互为备用），移动 HLS 只在 FLV 没有流或失败时顶上——这是 3.x 代码本来的设计（3.x 的 stream-manager 请求一直是坏的，用户实际拿到的是移动 HLS）。同时保证已存的 YY 画质 id（录制任务里的 `mobile-hls:4000` 之类）换到 FLV 的档位后仍然选对。

## 3.x 和现状

| 方面 | 3.x（文件:行） | 现在（文件:行） | 要做到 |
|---|---|---|---|
| 取画质的顺序 | `core/site/yy/yy_site.dart:437-445`：先问 stream-manager（`:291`），失败或没有画质才用移动 HLS（`:395-424`）；但请求是坏的，实际总是移动 HLS（“流畅 · 360p”“高清 · 720p”） | `packages/live_core/lib/src/sites/yy/yy_site.dart:36` 构造参数 `flvFirst`（默认 `false`），`:407` 按它决定先 FLV 还是先移动 HLS；应用 `apps/pure_live/lib/app/platforms.dart:160` 建 `YySite(http, cookies: cookies)`，没传 `flvFirst` | `flvFirst: true`：先 FLV，移动 HLS 兜底 |
| 续签 | 无（移动 HLS 地址没有有效期） | FLV 地址签名 10 分钟（`yy_api.dart:766-781` 的 `lease`，提前 1 分钟续）；播放会话在 `refreshAt` 预取（`packages/live_player/lib/src/session.dart:28`），G 已完成 | 播放超过 10 分钟不断流 |
| 第二条线路 | 无 | 每档 FLV 补 `line_seq` 的另一条 CDN（6-4，`YyApi.otherLines`），会话出错按 `lineId` 换线（G02.1 `LineFallback`） | 打开后每档两条线路 |
| 存下的画质 id | 3.x 只存全局画质名（原画、蓝光8M…），没有 YY 的 id | 录制任务 `RecordTask.selectedQualityId`（`packages/live_record/lib/src/task.dart:140`）可能是 `mobile-hls:4000` / `mobile-hls:1200`；`YyApi.flvQualityId`（`yy_api.dart:756`）把它们换成 FLV 的第一档 / 最后一档，但没人调用 | 打开 `flvFirst` 后旧 id 换算到对应档位 |

## 方案

- c1 `app/platforms.dart:160` 建 `YySite` 时传 `flvFirst: true`（或加一个编译常量，便于真机对比时临时关掉；不进设置页，E02.1 记录写明“不进设置页”）。
- c2 存下的画质 id 换算：录制恢复和“再录一次”拿 `selectedQualityId` 找档位时，YY 的 `mobile-hls:` 开头的 id 在 FLV 列表里找不到就用 `YyApi.flvQualityId` 换算（位置在 `packages/live_record` 的解析器里找“按 id 选画质”的那一处；直播间只按画质名记偏好，不受影响）。
- c3 清晰度名称变化（“高清 · 720p”→“高清”，有的频道多“蓝光”）对 3.x 用户的全局画质偏好（按名字匹配）有没有影响：核对 `room_controller.dart` 选默认画质的逻辑，YY 的偏好匹配不到时照旧取第一档。
- c4 真机：K90 上 YY 播放 15 分钟以上（跨过 10 分钟的签名到期），看续签是否无感；拔掉一条线路（或等它失败）看换线。

## 性能任务：测量

| 指标 | 改之前 | 目标或结果 | 怎么测 |
|---|---|---|---|
| 首帧时间（YY，同一频道） | 移动 HLS：待测 | 不比移动 HLS 慢 | 直播间进房到首帧，`adb logcat` 里会话的 `first frame` 时间，各测 5 次取中位数 |
| 延迟 | 移动 HLS：待测（HLS 一般 6～10 秒） | 比 HLS 低 | 同时开 YY 官网和本应用，对比画面里的时钟或弹幕出现时间 |

## 验证

- 自动测试：`apps/pure_live/test/platforms_test.dart` 加一条“YY 的适配器 `flvFirst` 是开的”；`packages/live_record` 加一条：任务存 `mobile-hls:4000`、平台列表是 FLV 三档时选第一档。
- 真机：待真机（brief 的真机步骤）。

## 留下的问题

- 3.x 用户的全局画质偏好按名字匹配，“高清 · 720p”这个名字以后不再出现；如果有人在 YY 上习惯选“流畅”，FLV 的“流畅”仍能匹配到（名字前缀相同），要在 c3 里确认。
