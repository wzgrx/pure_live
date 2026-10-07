# G02.3 断网时播放器不提示“正在重连”、报“解码失败”、网络恢复后不自己接上

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能
- 来源：S02.5 清单 1A-06（2026-10-08 K90 真机，[记录](../../../S-质量和验证/S02-真机验证/S02.5-4.0.0构建号5001/record.md)）
- 相关：A07.10-7（“正在重连（第 N 次）”和“换线路”的设计）、[G02.2](../G02.2-缓冲状态对账/README.md)（缓冲状态对账）、G03.1（弱网）

## 目标

播放中网络断了：画面上很快出现“正在重连（第 1 次）”和“换线路”；一直连不上时报“网络已断开”一类的真实原因（不是“解码失败”）；网络回来后自己接上，提示消失。

## 3.x 和现状

| 方面 | 现在（K90 实测，哔哩哔哩“德云色”房间） | 要做到 |
|---|---|---|
| 断网 10 秒、25 秒 | 画面中间只有转圈，没有“正在重连（第 1 次）”和“换线路” | 出现“正在重连（第 1 次）”和“换线路”（A07.10-7） |
| 断网约 40 秒 | “播放已中断 · 当前播放器解码失败”（翻译键 `error_codec`），并自动换到线路2 | 原因写对（网络断开） |
| 恢复网络 30 秒 | 仍是“播放已中断”，要手动点“重试” | 自己接上 |
| 弹幕 | 列表里“与弹幕服务器断开连接，正在尝试重连”，恢复后“连接正常”——弹幕这边是好的 | — |

断网方法（只断测试包，不影响手机其他应用）：`adb shell cmd connectivity set-chain3-enabled true`，`adb shell cmd connectivity set-package-networking-enabled false com.mystyle.purelive.v4dev`；恢复时把 `false` 换成 `true`，最后 `set-chain3-enabled false`。

## 方案

- c1 查“正在重连”为什么没出现：`apps/pure_live/lib/features/live_play/logic/reconnect_watch.dart` 只认会话自己的恢复（`PlaybackState.recovery`）；断网时 mpv 先进入缓冲，会话是不是一直没把它当成失败（`packages/live_media`、`packages/live_player` 的卡顿判定和超时），所以只有转圈。
- c2 失败原因：断网导致的读流失败（mpv 的 `end-file` 原因、HTTP 连接错误）不能归成解码失败；找到把它映射成 `error_codec` 的地方，按原因分类。
- c3 网络恢复后自动接上：会话放弃以后，监听网络恢复（`connectivity_plus` 已在依赖里）后自动重试一次；或者放弃前的重试轮次覆盖到网络回来。
- 先写失败的测试：用假引擎模拟“读流失败 → 一直失败 → 网络恢复”，断言状态依次是重连第 1 次、第 2 次……、失败原因、恢复后播放。

## 验证

- 自动测试：`packages/live_media/test/`、`apps/pure_live/test/features/live_play/` 的恢复测试。
- 真机：照上面的断网方法重做 S02.5 的 1A-06。

## 留下的问题

- 无。
