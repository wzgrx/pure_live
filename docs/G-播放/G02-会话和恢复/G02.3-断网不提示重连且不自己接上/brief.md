# G02.3 断网时播放器不提示重连、报“解码失败”、恢复后不自己接上：任务书

## 背景

- 来源：S02.5 清单 1A-06，2026-10-08 在 K90 上只断测试包的网复现（步骤见 README）。
- 为什么是第一档：网络不稳是天天会碰到的情况；现在用户看到的是转圈 40 秒、然后一个错误的原因，网络回来也不会自己好，只能手动点“重试”。
- 已经做过的：A07.10（“正在重连（第 N 次）”、“换线路”的界面）、B02（不再把缓冲当成断线）。

## 目标和验收

1. 断网后 10 秒内画面出现“正在重连（第 1 次）”和“换线路”；之后次数递增。
2. 一直连不上时，失败页的原因是网络（新文字，例如“网络已断开，恢复后会自动重连”），不是“当前播放器解码失败”。
3. 网络恢复后 10 秒内自动重新播放，提示消失；不需要点“重试”。
4. 真正的解码失败（例如设备不支持的编码）仍报“解码失败”。
5. 暂停、换清晰度、刷新时不出现“正在重连”（B02 的规则不变）。

## 现状（读代码得出，写文件:行）

- `apps/pure_live/lib/features/live_play/logic/reconnect_watch.dart:6-40`：`ReconnectWatch` 只看 `PlaybackState.recovery`。
- 失败原因翻译键 `error_codec`（`apps/pure_live/assets/translations/zh.json:489`），代码里是拼出来的键（D-016），开工先 `grep -rn "error_" apps/pure_live/lib packages --include=*.dart` 找到按原因拼键的地方。
- 恢复：`packages/live_media` 的播放会话（重试轮次、换线路、`recovery` 计数），`packages/live_player` 的 mpv 事件（`end-file` 原因、`paused-for-cache`）。

## 3.x 基线

- 3.x 断网时的行为：`git show v3.2.11:lib/player/core/player_manager.dart` 里的断线重连（开工先读，写进 record.md）。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5、8、14 节）；`docs/specs/ENGINEERING.md`。
2. 本文件夹的 `README.md`；`docs/G-播放/G02-会话和恢复/README.md`；`G02.2-缓冲状态对账/README.md`；`docs/A-界面设计/A07-直播间界面/A07.10-暂停状态/README.md`。

## 范围

- 可以改：`packages/live_media`、`packages/live_player` 的恢复和失败分类、`apps/pure_live/lib/features/live_play/logic/`、翻译文件（新键 zh、en）、测试。
- 不能改：界面样子（A07.10 已定）；清晰度、线路选择的规则。

## 方案和阶段

| 阶段 | 做什么 | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | c1、c2：断网时进入恢复、原因分类 | `live_media`、`live_player`、`reconnect_watch.dart`、翻译 | 验收 1、2、4、5 |
| 2 | c3：网络恢复后自动接上 | 会话或直播间控制器 | 验收 3 |

## 测试

- 假引擎模拟读流失败（连接错误）：断言 `recovery` 从 1 递增、`ReconnectWatch.reconnecting` 为真；超过重试轮次后失败原因是网络。
- 网络恢复事件后自动重试并进入播放。
- 解码失败仍是 `error_codec`。定时器至少 1 秒；不访问真实平台。

## 真机验证（K90）

| 步骤 | 期望 |
|---|---|
| 1. 哔哩哔哩房间播放中，只断测试包的网（README 的命令） | 10 秒内“正在重连（第 1 次）”“换线路” |
| 2. 断 60 秒 | 次数递增；最后失败原因是网络 |
| 3. 恢复网络 | 10 秒内自己接上 |
| 4. 最后 `set-chain3-enabled false` | — |

## 风险和注意

- 断网时 mpv 会先吃完缓冲（几秒到几十秒），“正在重连”的出现时间和缓冲长短有关，判定要按“卡住多久”而不是“有没有报错”。
- 和 G02.2（缓冲状态对账）改同一块，先合并先做完的那个。

## 环境和提交

- `source ~/tools/purelive-env.sh`；分支 `ai/G02.3`；提交以 `[G02.3]` 开头；不推 master。
- 提交前：改过的包 format、analyze、测试；`apps/pure_live` 全部 `flutter test`。

## 停下时

照 `docs/PROCESS.md` 第 5.2 节。

## 报告（中文，简洁）

根因（文件:行）；每条验收；测试数量；要在真机上看的。
