# G01.2 高通硬解评估：任务书

## 背景

- 来源：`docs/specs/UPGRADES.md` 统一原则“默认编码”和 22-3：设置“优先 H.264”默认开，“在高通真机上验证硬解后再评估默认值”（用户 2026-09-30 批准升级表）。G01.1 记录（`docs/G-播放/G01-引擎/G01.1-播放核心/record.md` “放到其他模块的部分”）把它交给 G02.1，G02.1 和 S02.3 都没做；V03.3（2026-10-03）核对时开了本任务。
- 现象：默认把 HEVC 档排在 H.264 后面，用户不手动选就看不到 HEVC；同码率下 HEVC 画质更好，但不知道 K90 上硬解是否稳定。反过来，映客默认清晰度按名字落在“原画”，而映客的“原画”只有 HEVC 线路，所以映客默认就在播 HEVC，“优先 H.264”对它没起作用（v2 文档核对时发现）。
- 为什么现在做：第二档；K90 是高通平台、随时可用（D-019）；结论也是 E06.2（Twitch 按引擎能力请求编码）的输入。
- 已经做过的：G01.1（排序、HEVC FLV 改写，`b4fb966e8`）、G02.1（`DecoderFallback` 硬解失败转软解，`4e8cd6c67`）、J02.1（设置）、A11.3（设置页）。

## 目标和验收

1. `record.md` 有一张表：平台 × 房间 × 编码（HEVC / H.264），每格写 `hwdec-current`（`mediacodec` / `no` / 回退）、首帧时间（5 次中位数）、15 分钟的 `decoder-frame-drop-count` 和 `frame-drop-count`、电量差、皮肤温度。至少 6 个平台：虎牙、快手、抖音、映客、酷狗、百度；开着代理时加 TikTok、17LIVE。每行写测试时间和房间号。
2. 诊断日志（c1）合并进 master：首帧后一行“`playback: hwdec=<值> codec=<值> <宽>x<高>`”，之后每 30 秒一行“`playback: drops decoder=<n> output=<n> delayed=<n>`”，在 `adb logcat -s flutter` 和应用日志页都能看到；不影响播放（读属性失败时不写、不报错）。
3. 根据第 1 条的数据定“优先 H.264”的默认值，写成 `docs/DECISIONS.md` 的新一条（写明只在 K90 上测过、适用范围）。
4. 默认值改了的话：`packages/live_store/lib/src/settings/settings.dart:293` 的 `defaultValue` 和 `packages/live_store/test/stores_test.dart:146` 一起改；`docs/specs/UPGRADES.md` 统一原则和 22-3 的状态改“完成（G01.2，D-xxx）”。没改也要更新 22-3（“评估过，保持默认开，见 D-xxx”）。
5. 报告里给出映客默认档的建议（c5）。
6. 测试和门禁通过。

## 现状（读代码得出，写文件:行）

- 设置：`packages/live_store/lib/src/settings/settings.dart:293` `preferH264 = BoolSetting('preferH264', section: 'player', defaultValue: true)`；硬解开关 `enableCodec`（`:289`，默认开）、兼容模式 `playerCompatMode`（`:296`）、自定义输出的 `videoHardwareDecoder`（`:308`，默认 `auto`）。
- 排序：`packages/live_media/lib/src/source.dart:156-177`：`PlaybackPlan.of(resolution, preferH264:)` 开时 `codec != 'hevc'` 的线路在前、`hevc` 的在后，其余照平台顺序。直播间 `apps/pure_live/lib/features/live_play/logic/room_controller.dart:515-519` 的 `_plan`、多画面 `features/multiview/logic/multiview_controller.dart:636` 读设置。平台层也按它排画质：`apps/pure_live/lib/app/platforms.dart:139` 的 `preferH264()` 传给虎牙（`:148`）、快手（`:150`）、映客（`:165`）、TikTok（`:174`）、酷狗（`:181`）、百度（`:182`）、17LIVE（`:185`）等。
- 默认清晰度：`apps/pure_live/lib/shared/rooms/play_quality.dart:7-16` 的 `defaultQualityIndex`：先找名字等于偏好（默认“原画”，`settings.dart:270-273`）的档（`:9`），找不到才按相对位置。映客 `packages/live_core/lib/src/sites/inke/inke_site.dart:346-351`：开着“优先 H.264”时画质是 `[InkeApi.flv, InkeApi.original]`，`InkeApi.original` 的名字就是“原画”（`inke_api.dart:169`，即构 HEVC，`codecInfo=8192`，`:611-615`），所以名字匹配选中 HEVC 档。17LIVE 的档名是“原画 · FLV”这类（`seventeenlive_api.dart:775`），不会被名字匹配命中，按位置落在第一档（H.264），不受影响。
- 硬解：`packages/live_player/lib/src/mpv_options.dart:88-99`：`preferredHardwareDecoder` 一般是 `auto-safe`，兼容模式在 Android 上是 `mediacodec`；软解是 `no`（`hwdecFor` `:99`）；`hwdec-software-fallback=1`（`:151`，第一个失败帧就离开硬解）。`MpvEngine.open`（`packages/live_player/lib/src/mpv_engine.dart:165`）每次打开设 `hwdec`。
- 回退：`packages/live_media/lib/src/fallback.dart:73` 的 `DecoderFallback`（`shouldFallback` `:93`）；`packages/live_player/lib/src/session.dart:915-929`（恢复顺序第 4 步：非音频的解码类错误改软解）；状态 `PlaybackState.decoder`。
- 看不到用的哪种解码：media_kit 的日志级别默认 `error`（`third_party/media_kit/lib/src/player/platform_player.dart:543`，`MpvEngine.create` 没改，`mpv_engine.dart:57`），mpv 选 `hwdec` 的信息不进日志；应用里没有读 `hwdec-current` 的地方，也没有播放统计面板。
- 读属性的现成写法：`packages/live_player/lib/src/frame_rate.dart:16-36` 的 `probeFrameRate(read, current:)` 和 `mpv_engine.dart:196-210` 的 `_probeFrameRate`、`_readProperty`（每次打开一个代号 `_opens`，换了打开就停）。
- 应用日志：`apps/pure_live/lib/app/app_log.dart:256` 的 `AppLog.instance.info(tag, message)`（日志页能看、能导出；写文件要“启用本地日志”）。

## 3.x 基线

- 3.x 没有“优先 H.264”，用多引擎降级处理解码问题（`git show v3.2.11:lib/player/core/engine_fallback_manager.dart`，73 行；`lib/player/adapters/fvp_adapter.dart` 等）；HEVC FLV 只认 `.17app.co`（`lib/player/core/flv_legacy_hevc_relay.dart:76`）。G02.1 记录写着：3.x 用 fvp 处理的情况（17LIVE 等 codec 12 HEVC 在高通硬解上丢帧）现在由“优先 H.264”排序、`hwdec-software-fallback` 和软解回退处理，“留待真机验证”——就是本任务。
- 默认清晰度按名字找、找不到按位置：`git show v3.2.11:lib/modules/live_play/controllers/player_controller.dart` 的 `_setDefaultResolution`（`:594`、`:613`）；3.x 的映客只有一个 FLV 档，没有这个问题。
- 设置“优先 H.264”是 4.x 新加的（已批准升级），没有 3.x 键名，改默认值不违反 D-018。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节分阶段、第 10 节真机、第 14 节规则）。
2. `docs/specs/ENGINEERING.md`（第 4 节：`live_player` 的分层）。
3. 本文件夹的 `README.md`；`docs/G-播放/G01-引擎/README.md`（已知问题：映客、Steam）；`docs/G-播放/G01-引擎/G01.1-播放核心/record.md`（选源、HEVC 改写）；`docs/G-播放/G02-会话和恢复/G02.1-播放器/record.md`（`DecoderFallback`、有意差异 1）；`docs/specs/UPGRADES.md` 的统一原则、8-8、14-5、22-3、29-8、30-2、33-2；`docs/V-需求和反馈/V03-审查和调研/V03.2-流畅度、刷新率、分辨率调研/README.md` 第 4.3 节（怎么在手机上测，`gfxinfo` 对 Flutter 不准）。

## 范围

- 可以改：`packages/live_player/lib/src/mpv_engine.dart`（只加 c1 的属性读取和回调）、`engine.dart`（如果要加一个诊断事件，只添加）、`session.dart`（只把诊断转出去）、`packages/live_player/test/`；`apps/pure_live/lib/features/live_play/logic/room_controller.dart`（只把诊断写进应用日志）；`packages/live_store/lib/src/settings/settings.dart`（只改 `preferH264` 的默认值）和 `packages/live_store/test/stores_test.dart`；`docs/DECISIONS.md`、`docs/specs/UPGRADES.md` 的相关行；本文件夹。
- 不能改：选源、选路和回退的逻辑（发现问题另开任务）；`play_quality.dart` 和映客的平台代码（c5 只写建议）；其他设置；界面（不加统计面板）；版本号、`assets/version.json`、`assets/releases.json`；签名配置；3.x 的设置键名和含义。

## 方案和阶段

| 阶段 | 做什么（对应 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | c1 诊断日志：首帧后读 `hwdec-current`、`video-codec`、`video-params/w`、`video-params/h`；之后每 30 秒（只在播放中、非纯音频）读 `decoder-frame-drop-count`、`frame-drop-count`、`vo-delayed-frame-count`；经会话交给应用，应用 `AppLog.instance.info('playback', …)` 并 `debugPrint` | `mpv_engine.dart`、`engine.dart`、`session.dart`、`room_controller.dart`、`packages/live_player/test/` | 测试通过；本机 profile 包装到 K90，`adb logcat -s flutter` 看得到两种日志行；合并进 master |
| 2 | c2 K90 逐平台测（每平台 2 个房间 × HEVC/H.264 × 15 分钟）；c3 定默认值、写 DECISIONS；c4 需要时改默认值；c5 映客的建议 | `record.md`、`DECISIONS.md`、`UPGRADES.md`；可能 `settings.dart` 和 `stores_test.dart` | 验收第 1、3、4、5 条 |

每个阶段都要能单独合并（门禁通过、不留半截功能）。

## 测试

- 阶段 1：`packages/live_player/test/` 新用例（不需要真 mpv）：
  - `mpv diagnostics read hwdec after the first frame`：把读属性的函数换成假的（照 `frame_rate_test.dart` 的写法），返回 `hwdec-current = mediacodec`、`video-codec = hevc`，断言回调收到一次，内容对；
  - `drop counters are read every 30 s while playing, not while paused or audio-only`：`fake_async` 推 95 秒，断言读了 3 次；暂停后不再读；
  - `a failing property read is silent`：读属性抛错，回调不收到、不抛出。
  - 定时器至少 1 秒；不访问真实平台。
- 阶段 2 改默认值时：`stores_test.dart:146` 的断言改成新默认值。
- 改过的包跑 `dart format --output=none --set-exit-if-changed .`、`flutter analyze`、`flutter test`；`apps/pure_live` 跑全部 `flutter test`。

## 真机验证（维护者在 K90 上做）

准备：装阶段 1 合并后的 profile 包（`com.mystyle.purelive.v4dev`）；设置 → 数据 → 日志管理打开“启用本地日志”；固定亮度 50%、音量 30%、关自动亮度、不充电；`adb -s 192.168.1.2:5555 logcat -s flutter`。

| 步骤 | 期望 |
|---|---|
| 1. 设置 → 视频 → 关掉“优先 H.264 编码”；进虎牙一个热门直播间，清晰度选带 HEVC 标记的档 | 日志出现 `playback: hwdec=mediacodec codec=hevc …`（或 `hwdec=no`，照实记）；画面正常 |
| 2. 同一房间播 15 分钟，开始和结束各记一次 `dumpsys battery` 的电量和 `dumpsys thermalservice` 的温度 | 日志每 30 秒一行掉帧计数；第 15 分钟的值减第 0 分钟写进表 |
| 3. 打开“优先 H.264”，同一房间 H.264 档同样 15 分钟 | 写进表，和第 2 步对比 |
| 4. 快手、抖音、酷狗、百度重复 1～3（开代理时 TikTok、17LIVE） | 每个平台都有结论；出现软解回退时记下日志（`decoder` 变成 `software`） |
| 5. 映客：“优先 H.264”开着（默认），进一个有“原画”档的直播间 | 记下默认选中的是哪一档、`codec`（预期是“原画”、`hevc`），这是 c5 的依据 |
| 6. 按结论改或不改默认值后，装新包，清数据冷启动进虎牙 | 清晰度菜单顺序符合新默认值 |

## 风险和注意

- 同一房间的码率随时变，对比尽量同一时段、同一档位；表里写清时间和房间。
- 耗电对比的误差大：15 分钟的电量差可能只有 1%～2%，每组至少测两次；温度受环境影响，写室温。
- 读 mpv 属性走 FFI，在主 isolate 上；只在首帧和每 30 秒读，不要每帧读（3.x 曾因每帧回调在高通设备上丢帧）。
- 只点测试包（D-019）；不碰正式包和 3.x。
- 可能冲突的文件：`session.dart`（G02.2、G03.1 都改）——阶段 1 的改动只加一个转发，尽量放在 G02.2 合并之后；`room_controller.dart`（C01.4、E06.2）。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 分支 `ai/G01.2` 或本机工作区；提交信息以 `[G01.2]` 开头（英文）；不推 master。
- 提交前：改过的包跑 format、analyze、测试；`apps/pure_live` 跑全部 `flutter test`；`python3 tools/gate/check_ui_structure.py`、`python3 tools/gate/check_deps.py`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”（测到哪个平台、哪些格子还空）、更新登记表的 `done`、`next`、`branch`。

## 报告（中文，简洁）

每个平台的结论表；定的默认值和理由（D-xxx）；诊断日志的格式；测试数量；改了哪些文件；映客默认档的建议；要在真机上再看的；需要维护者决定的（例如结论只对高通成立时要不要按芯片区分）；可能冲突的文件。
