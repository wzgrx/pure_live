# E01.8 虎牙播放 UA 跟到 7100004；斗鱼 5 分钟有效的 ws 线路加 expire=0

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：上游对照 [W01.3](../../../W-上游借鉴/W01-定期对照/W01.3-2026-10-08上游对照/README.md)：上游 pure_live `a858550bb`（2026-10-07，“对齐 simple_live —— UA 升至 7100004/2.40.0，斗鱼 ws 线 expire=0 补丁”）
- 相关：虎牙 [E01.3](../E01.3-虎牙/README.md)、斗鱼 [E01.2](../E01.2-斗鱼/README.md)；平台巡检 [E07.1](../../E07-平台巡检/E07.1-平台巡检工具/README.md)

## 目标

- 虎牙：拉流用的 HYSDK UA 跟上上游（和 simple_live）现在用的版本，免得虎牙哪天拒绝旧版本时整个虎牙播不了。上游没有写现象，这一条是预防；但虎牙是每天都看的平台、改动只有一行，所以排第二档。
- 斗鱼：匿名（或部分海外）会话拿到的 `expire=300&fcdn=ws` 线路 5 分钟就失效，4.x 现在靠到期前续期接上；上游加 `&expire=0` 让 CDN 按默认时长签发，可以少很多次续期（每次续期都是一次换流）。

## 3.x 和现状

| 方面 | 3.x | 现在（文件:行） | 要做到 |
|---|---|---|---|
| 虎牙内置 UA | `HYSDK(Windows,30000002)_APP(pc_exe&7090000&official)_SDK(trans&2.35.0.5996)` | 同 3.x：`packages/live_core/lib/src/sites/huya/huya_api.dart:236` | `pc_exe&7100004`、`SDK(trans&2.40.0.6448)`（上游 `lib/shared/platforms/huya/huya_request_params.dart:15`） |
| 虎牙远端 UA | 启动时从上游仓库读 `assets/play_config.json` 的 `huya.user_agent`（3.x `getHuYaUA`） | 同：`huya_site.dart:117-120`（镜像地址）、`:402-405`（读到就用它，`apps/pure_live/lib/app/bootstrap.dart:392` 启动时读）；上游的这个文件 2026-10-08 还是 `7090000` | 远端的版本比内置旧时用内置的（按 `pc_exe&<数字>` 比较），或者改读自己仓库的配置（要维护者定） |
| 斗鱼 5 分钟线路 | 没有处理 | `packages/live_core/lib/src/sites/douyu/douyu_api.dart:623-627`（`statedLifetime` 读 `expire`）、`:634` 起的 `lease`：按 `expire` 秒算租约，到期前 45 秒（`:159-161`）续期换流 | 地址同时有 `expire=300` 和 `fcdn=ws` 时把 `expire=300` 换成 `expire=0`（上游是在后面追加 `&expire=0`；4.x 的 `statedLifetime` 只看第一个 `expire`，追加的话租约还是 5 分钟，所以要替换） |

## 方案

- c1（虎牙）：`HuyaApi.hysdkUserAgent` 改成新版本；`loadPlayUserAgent` 读到的远端 UA 如果是 HYSDK 格式且 `pc_exe&` 后的版本号比内置的小，用内置的。测试：远端旧、远端新、远端不是 HYSDK 格式三种。
- c2（斗鱼）：先用 E07 的巡检工具（或 `tools/live_cli`）在真实接口上确认：匿名拿一条 `expire=300&fcdn=ws` 的地址，换成 `expire=0` 后 CDN 照样给流、5 分钟后连接不被断。确认了再改 `DouyuApi.answer`（或线路构造处）替换参数；不认就只记录、不改。测试：`expire=300&fcdn=ws` 换成 `expire=0`、租约为空；别的 CDN 和 `expire` 不动。
- 先写改之前会失败的测试再改（PROCESS 第 8 节）。

## 验证

- 自动测试：`packages/live_core/test` 里虎牙 UA 的选择、斗鱼参数替换各加用例。
- 真机（K90）：虎牙、斗鱼各进两个直播间，看 10 分钟以上不断流；斗鱼匿名时日志里不再每 5 分钟续期一次（c2 做了的话）。

## 留下的问题

- 虎牙 UA 由上游仓库的文件远程决定（上游改它会直接改变 4.x 的行为），要不要换成本仓库的 `assets/`，维护者定。
