# G01.2 高通硬解评估：定“优先 H.264”的默认值

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：验证
- 来源：已批准升级的统一原则“默认编码”（“设置加‘优先 H.264’，默认开；在高通真机上验证硬解后再评估默认值”）和 22-3（TikTok）；G01.1 记录把它留给了 G02.1（“‘优先 H.264’默认值在高通真机硬解验证后再定”），G02.1 和 S02.3 都没做。V03.3 核对时发现没有任务管它。
- 相关：G01.1（`PlaybackPlan.of` 的排序、HEVC FLV 改写）、G02.1（`DecoderFallback` 硬解失败转软解）、J02.1（设置 `preferH264`）、A11.3（设置页“优先 H.264 编码”）；升级 8-8、14-5、22-3、29-8、30-2、33-2

## 目标

用数据决定“优先 H.264”默认开还是关：在 K90（高通平台）上看 HEVC 线路能不能稳定硬解、画质和耗电比 H.264 好多少；结论写进 DECISIONS，需要时改默认值。用户看到的变化：如果改成默认关，HEVC 档会排在前面，同样码率画质更好、流量更省。

## 3.x 和现状

| 方面 | 3.x（文件:行） | 现在（文件:行） | 要做到 |
|---|---|---|---|
| 编码选择 | 3.x 没有“优先 H.264”，按平台给的顺序，HEVC FLV 只认 `.17app.co`（`player/core/flv_legacy_hevc_relay.dart:76`） | `packages/live_store/lib/src/settings/settings.dart:293` 的 `preferH264`（默认 `true`）；`packages/live_media/lib/src/source.dart:151-171` 的 `PlaybackPlan.of(preferH264:)` 把 `codec == 'hevc'` 的线路排到后面；直播间 `apps/pure_live/lib/features/live_play/logic/room_controller.dart:517`、多画面 `features/multiview/logic/multiview_controller.dart:636` 传设置 | 有数据支撑的默认值 |
| 硬解 | 多引擎降级（fijk、exo、fvp） | `packages/live_player/lib/src/mpv_options.dart:88-99`：硬解是 `auto-safe`（兼容模式 `mediacodec`）；`packages/live_media/lib/src/fallback.dart:73` 的 `DecoderFallback` 解码类错误时转软解（`session.dart:100` 的第 4 步） | 知道 K90 上 HEVC 硬解是否稳定、失败时回退是否无感 |
| 平台给 HEVC 的 | — | 线路带 `codec: 'hevc'` 的：虎牙、快手、抖音、映客（14-5）、酷狗（29-8）、百度（30-2）、TikTok（22-3）、17LIVE（33-2）；Twitch 按 `codecs` 请求（8-8，应用还没传，见 E06.2） | 逐平台有结论 |

## 方案

- c1 在 K90 上，“优先 H.264”关掉，逐个平台进有 HEVC 档的直播间（每个平台 2 个房间），记：实际是不是硬解（mpv 日志里的 `hwdec`）、首帧时间、15 分钟内的掉帧和卡顿、有没有触发 `DecoderFallback`、手机温度和耗电（`adb shell dumpsys batterystats` 或 `dumpsys thermalservice`）。同样的房间、同样时长，开着“优先 H.264”再测一遍 H.264 档。
- c2 日志里看不出用的是哪种解码时，在 `packages/live_player` 的诊断日志里加一行读 mpv 的 `hwdec-current`（只打日志，不加界面）。
- c3 按数据定默认值：HEVC 硬解在所有测的平台都稳定、画质或流量明显更好 → 默认关；有平台失败或发热明显 → 保持默认开。写进 `docs/DECISIONS.md`（新编号），更新升级表统一原则和 22-3 的状态。
- c4 改默认值时只改 `settings.dart:293` 的 `defaultValue`（`preferH264` 是 v4 新加的设置，没有 3.x 键，可以改），并改 `packages/live_store/test/` 里默认值的断言。

## 性能任务：测量

| 指标 | 改之前 | 目标或结果 | 怎么测 |
|---|---|---|---|
| HEVC 是否硬解 | 不知道 | 每个平台写“硬解 / 软解 / 回退” | `adb logcat` 里 mpv 的 `hwdec` 日志（或 c2 的 `hwdec-current`） |
| 首帧时间 | 待测 | HEVC 不比 H.264 慢 500 毫秒以上 | 进房到首帧（会话日志），各 5 次取中位数 |
| 15 分钟掉帧 | 待测 | HEVC 不多于 H.264 | `adb shell dumpsys gfxinfo com.mystyle.purelive.v4dev` 的 janky frames |
| 耗电和温度 | 待测 | HEVC 不高于 H.264 | 同一亮度、同一房间各播 15 分钟，`dumpsys battery` 电量差和 `dumpsys thermalservice` 温度 |

## 验证

- 自动测试：只有 c2、c4 改代码时才加：`hwdec-current` 的日志在 `packages/live_player/test/` 里用假引擎断言；默认值改了的话 `packages/live_store/test/stores_test.dart` 的默认值断言跟着改。
- 真机：本任务就是在 K90 上测，数据写进 `record.md`。

## 留下的问题

- Twitch 按引擎能力请求 HEVC/AV1 的应用接线在 E06.2（阶段“Twitch”），本任务的结论（K90 能硬解哪些编码）是它的输入。
- 只测了高通（K90）；联发科、Exynos 的设备没有，结论在 DECISIONS 里写明适用范围。
