# G01.2 高通硬解评估：定“优先 H.264”的默认值

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：验证
- 来源：已批准升级的统一原则“默认编码”（“设置加‘优先 H.264’，默认开；在高通真机上验证硬解后再评估默认值”）和 22-3（TikTok）；G01.1 记录把它留给了 G02.1（“‘优先 H.264’默认值在高通真机硬解验证后再定”），G02.1 和 S02.3 都没做；V03.3 核对时（2026-10-03）开了本任务。功能点 F-ROOM-04 的备注指向这里。
- 相关：G01.1（`PlaybackPlan.of` 的排序、HEVC FLV 改写）、G02.1（`DecoderFallback` 硬解失败转软解）、J02.1（设置 `preferH264`）、A11.3（设置页“优先 H.264 编码”）；升级 8-8、14-5、22-3、29-8、30-2、33-2；E06.2（Twitch 按引擎能力请求编码，要本任务的结论）；任务书 [brief.md](brief.md)

## 目标

用 K90 上的数据决定“优先 H.264”默认开还是关：HEVC 线路在高通 MediaCodec 上能不能稳定硬解、首帧和掉帧和 H.264 比怎么样、耗电和温度差多少。结论写进 DECISIONS，需要时改默认值。

用户看到的变化：如果改成默认关，HEVC 档排在前面，同码率画质更好、流量更省；如果保持默认开，用户知道为什么（DECISIONS 有依据），映客这类“原画只有 HEVC”的平台也按同一规则处理。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11`，文件:行） | 现在（文件:行） | 要做到 |
|---|---|---|---|
| 编码选择 | 没有“优先 H.264”，按平台给的顺序；HEVC FLV 只认 `.17app.co`（`lib/player/core/flv_legacy_hevc_relay.dart:76`） | `packages/live_store/lib/src/settings/settings.dart:293` 的 `preferH264`（默认 `true`）；`packages/live_media/lib/src/source.dart:156-177` 的 `PlaybackPlan.of(preferH264:)` 把 `codec == 'hevc'` 的线路排到后面；直播间 `apps/pure_live/lib/features/live_play/logic/room_controller.dart:515-519`、多画面 `features/multiview/logic/multiview_controller.dart:636` 传设置；平台层按它排画质（`apps/pure_live/lib/app/platforms.dart:139` 传给虎牙、快手、映客、TikTok、酷狗、百度、17LIVE 等） | 有数据支撑的默认值 |
| 默认清晰度 | `_setDefaultResolution` 按名字找，找不到按相对位置 | `apps/pure_live/lib/shared/rooms/play_quality.dart:7-16` 同 3.x：先按名字（默认“原画”，`settings.dart:270-273`），再按位置 | 映客的“原画”只有 HEVC（`packages/live_core/lib/src/sites/inke/inke_api.dart:165-169`），名字匹配让它绕过“优先 H.264”；要定谁优先 |
| 硬解 | 多引擎降级（fijk、exo、fvp）；fvp 曾用来绕开 17LIVE codec 12 HEVC 在高通硬解上丢帧 | `packages/live_player/lib/src/mpv_options.dart:88-99`：硬解 `auto-safe`（兼容模式 `mediacodec`），`hwdec-software-fallback=1`（`:151`）；`packages/live_media/lib/src/fallback.dart:73` 的 `DecoderFallback` 解码类错误时转软解（`session.dart:100` 的第 4 步） | 知道 K90 上 HEVC 是不是真的硬解、失败时回退是否无感 |
| 能不能看出用的哪种解码 | 3.x 的设置页显示内核 | mpv 日志级别是 `error`（media_kit 默认，`third_party/media_kit/lib/src/player/platform_player.dart:543`），`hwdec` 的选择不进日志；应用里没有读 `hwdec-current` 的地方，也没有“统计信息”面板 | 加一行诊断日志：首帧后读 `hwdec-current`、`video-codec`，定时读掉帧计数 |
| 平台给 HEVC 的 | — | 线路带 `codec: 'hevc'` 的：虎牙、快手、抖音、映客（14-5）、酷狗（29-8）、百度（30-2）、TikTok（22-3）、17LIVE（33-2）；Twitch 按 `codecs` 请求（8-8，应用还没传，E06.2） | 逐平台有结论 |

## 方案

- c1 诊断日志（只打日志，不加界面）：`MpvEngine` 在第一帧（`videoParams` 有尺寸）后读 `hwdec-current`、`video-codec`、`video-params/w`/`h`，之后每 30 秒读一次 `decoder-frame-drop-count`、`frame-drop-count`、`vo-delayed-frame-count`，交给会话的诊断回调；应用写进应用日志（`AppLog.instance.info('playback', ...)`）并 `debugPrint` 同一行。这样 profile 包在 `adb logcat -s flutter` 和日志页都能看到。
- c2 在 K90 上，“优先 H.264”关掉，逐个平台进有 HEVC 档的直播间（每个平台 2 个房间），记：`hwdec-current`（`mediacodec` 还是 `no`）、首帧时间、15 分钟内两种掉帧计数、有没有触发软解回退（日志里 `decoder` 变成 `software`）、电量差和温度。同样的房间、同样时长，打开“优先 H.264”再测 H.264 档。映客必须测（它的默认档就是 HEVC）。
- c3 按数据定默认值：HEVC 在所有测的平台都是 `mediacodec`、没有回退、掉帧和耗电不高于 H.264 → 可以改默认关；任何平台回退、明显掉帧或发热 → 保持默认开。写进 `docs/DECISIONS.md`（新编号，写明只在 K90 上测过），更新 UPGRADES 统一原则和 22-3。
- c4 改默认值时只改 `settings.dart:293` 的 `defaultValue`（4.x 新设置，没有 3.x 键，不违反 D-018），并改 `packages/live_store/test/stores_test.dart:146` 的断言。
- c5 映客和名字匹配：按 c3 的结论写建议——保持默认开时，“优先 H.264”开着的情况下按名字选默认档要跳过只有 HEVC 线路的档（落到映客的 FLV）；改成默认关时现状就对。这一条改的是 `play_quality.dart`（C、E 组的文件），本任务只写建议，由维护者开任务。

## 性能任务：测量

| 指标 | 改之前 | 目标或结果 | 怎么测 |
|---|---|---|---|
| HEVC 是否硬解 | 不知道 | 每个平台写 `mediacodec` / `no` / 回退 | c1 的日志行（`hwdec-current`） |
| 首帧时间 | 待测 | HEVC 中位数不比 H.264 慢 500 毫秒以上 | 进房到首帧：G03.1 的打点（已合并时）或应用日志的时间差，各 5 次取中位数 |
| 15 分钟掉帧 | 待测 | HEVC 的 `decoder-frame-drop-count` + `frame-drop-count` 不多于 H.264，且 <1% | c1 的日志（第 15 分钟减第 0 分钟）；不用 `dumpsys gfxinfo`（它统计普通 View 窗口，对 Flutter 画面不准，见 V03.2 调研报告 4.3 节） |
| 耗电和温度 | 待测 | HEVC 不高于 H.264 | 固定亮度 50%、音量 30%、不充电，同一房间各播 15 分钟：`adb shell dumpsys battery` 的电量差，`adb shell dumpsys thermalservice` 的皮肤温度 |

## 验证

- 自动测试：c1 的诊断在 `packages/live_player/test/` 用假引擎（读属性的函数返回 `mediacodec`、掉帧数）断言回调收到的内容；c4 改了默认值时 `stores_test.dart` 跟着改。
- 真机：本任务就是在 K90 上测，结果写进 `record.md`（表格见任务书验收第 1 条）。

## 留下的问题

- Twitch 按引擎能力请求 HEVC/AV1 的应用接线在 E06.2（阶段“Twitch”，暂停），本任务的结论（K90 能硬解哪些编码）是它的输入。
- 只测高通（K90）；联发科、Exynos 没有设备，DECISIONS 里写明适用范围；以后有设备再补。
- 映客默认档的规则（c5）需要维护者开任务。
