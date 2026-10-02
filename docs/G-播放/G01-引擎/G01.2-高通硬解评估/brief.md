# G01.2 高通硬解评估：任务书

## 背景

- 来源：`docs/specs/UPGRADES.md` 统一原则“默认编码”和 22-3：设置“优先 H.264”默认开，“在高通真机上验证硬解后再评估默认值”。G01.1 记录（`docs/G-播放/G01-引擎/G01.1-播放核心/record.md` “留给后续”）把它交给 G02.1，G02.1 和 S02.3 都没做；V03.3（2026-10-03）核对时开了本任务。
- 现象：默认把 HEVC 档排在 H.264 后面，用户不手动选就看不到 HEVC；同码率下 HEVC 画质更好，但不知道 K90 上硬解是否稳定。
- 为什么现在做：第二档；K90 是高通平台、随时可用（D-019），结论也是 E06.2（Twitch 按引擎能力请求编码）的输入。
- 已经做过的：G01.1（排序、HEVC FLV 改写）、G02.1（`DecoderFallback` 硬解失败转软解）、J02.1（设置）、A11.3（设置页）。

## 目标和验收

1. `record.md` 里有一张表：平台 × 房间 × 编码，每格写“硬解 / 软解 / 回退”、首帧时间、15 分钟掉帧、电量差和温度（见 README 的测量表）。至少 6 个平台：虎牙、快手、抖音、映客、酷狗、百度；有代理时加 TikTok、17LIVE。
2. 根据数据定“优先 H.264”的默认值，写成 `docs/DECISIONS.md` 的新一条（写明只在 K90 上测过）。
3. 默认值改了的话：`packages/live_store/lib/src/settings/settings.dart:293` 的 `defaultValue` 和对应测试一起改；`docs/specs/UPGRADES.md` 统一原则和 22-3 的状态改“完成”。
4. 没改默认值也要更新 22-3 的状态（“评估过，保持默认开，原因见 D-xxx”）。

## 现状（读代码得出，写文件:行）

- 设置：`packages/live_store/lib/src/settings/settings.dart:293`：`preferH264 = BoolSetting('preferH264', section: 'player', defaultValue: true)`；硬解开关 `enableCodec`（`:289`）和 `videoHardwareDecoder`（`:308`，默认 `auto`）。
- 排序：`packages/live_media/lib/src/source.dart:151-171`：`PlaybackPlan.of(resolution, preferH264:)`，开时 `codec == 'hevc'` 的线路排到后面，其余照平台顺序。直播间 `apps/pure_live/lib/features/live_play/logic/room_controller.dart:517`、多画面 `features/multiview/logic/multiview_controller.dart:636` 读设置；平台层有的也按它排画质（`apps/pure_live/lib/app/platforms.dart:139` 的 `preferH264()` 传给虎牙、快手、映客、TikTok、酷狗、百度等适配器，`:148`～`:182`）。
- 硬解：`packages/live_player/lib/src/mpv_options.dart:88-99`：`preferredHardwareDecoder` 一般是 `auto-safe`，兼容模式在 Android 上是 `mediacodec`；软解是 `no`。
- 回退：`packages/live_media/lib/src/fallback.dart:73` 的 `DecoderFallback`；`packages/live_player/lib/src/session.dart:100` 恢复顺序第 4 步（解码类错误转软解）。
- 读帧率：`packages/live_player/lib/src/frame_rate.dart:31` 读 mpv 属性 `estimated-vf-fps`，可以照它的写法读 `hwdec-current`。

## 3.x 基线

- 3.x 没有“优先 H.264”，用多引擎降级（`git show v3.2.11:lib/player/core/player_manager.dart:213` 附近的恢复流程）；HEVC FLV 只认 `.17app.co`（`lib/player/core/flv_legacy_hevc_relay.dart:76`）。
- 设置“优先 H.264”是 v4 新加的（已批准升级），没有 3.x 键名，改默认值不违反 D-018。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节、第 10 节真机、第 14 节规则）。
2. `docs/specs/ENGINEERING.md`。
3. 本文件夹的 `README.md`；`docs/G-播放/G01-引擎/G01.1-播放核心/record.md`（选源、HEVC 改写、留给后续）；`docs/G-播放/G02-会话和恢复/G02.1-播放器/record.md`（`DecoderFallback`）；`docs/specs/UPGRADES.md` 的统一原则、8-8、14-5、22-3、29-8、30-2、33-2。

## 范围

- 可以改：`packages/live_player/lib/src/`（只加读 `hwdec-current` 的诊断日志）、`packages/live_store/lib/src/settings/settings.dart`（只改 `preferH264` 的默认值）和对应测试；`docs/DECISIONS.md`、`docs/specs/UPGRADES.md` 的相关行；本文件夹。
- 不能改：选源和回退的逻辑（发现问题另开任务）；其他设置；版本号、`assets/version.json`、`assets/releases.json`；签名配置；3.x 的设置键名和含义。

## 方案和阶段

| 阶段 | 做什么（对应 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | c1、c2：K90 上逐平台测 HEVC 和 H.264 | `record.md`；必要时 `packages/live_player` 的诊断日志和测试 | 验收第 1 条的表填满 |
| 2 | c3、c4：定默认值，写 DECISIONS，改默认值或说明为什么不改 | `DECISIONS.md`、`UPGRADES.md`；可能 `settings.dart` 和测试 | 验收第 2～4 条 |

## 测试

- 加诊断日志时：`packages/live_player/test/` 里用假引擎返回 `hwdec-current = mediacodec`，断言日志里有这一行（定时器至少 1 秒，不访问真实平台）。
- 改默认值时：`packages/live_store/test/stores_test.dart` 里 `preferH264` 的默认值断言。
- `dart format --output=none --set-exit-if-changed .`、analyze、测试；`apps/pure_live` 跑全部 `flutter test`。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 设置 → 视频 → 关掉“优先 H.264 编码”；进虎牙一个热门直播间，清晰度选带 HEVC 标记的档；`adb logcat \| grep -i -E "hwdec\|mediacodec"` | 日志显示硬解（`mediacodec`）；画面正常 |
| 2. 同一房间播 15 分钟，记掉帧（`dumpsys gfxinfo`）、电量差、温度 | 写进表 |
| 3. 打开“优先 H.264”，同一房间 H.264 档同样 15 分钟 | 写进表，和第 2 步对比 |
| 4. 对快手、抖音、映客、酷狗、百度重复 1～3（有代理时 TikTok、17LIVE） | 每个平台都有结论；出现回退时记下 `DecoderFallback` 的日志 |
| 5. 按结论改或不改默认值后，装新包，冷启动进虎牙 | 清晰度菜单的顺序符合新默认值 |

## 风险和注意

- 同一房间的码率会变，对比时尽量同一时段、同一档位；数据写清时间和房间。
- 耗电对比要关自动亮度、固定音量，手机不充电。
- 只点测试包（D-019）。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 分支 `ai/G01.2` 或本机工作区；提交信息以 `[G01.2]` 开头（英文）；不推 master。
- 提交前：改过的包跑 format、analyze、测试；`apps/pure_live` 跑全部 `flutter test`；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”（测到哪个平台）、更新登记表的 `done`、`next`、`branch`。

## 报告（中文，简洁）

每个平台的结论表；定的默认值和理由（D-xxx）；改了哪些文件；要在真机上再看的；需要维护者决定的（例如结论只对高通成立时要不要按芯片区分）。
