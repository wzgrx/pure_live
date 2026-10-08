# E01.8 虎牙 UA 和斗鱼 expire：记录

- 日期：2026-10-08
- 执行者：Claude
- 分支和提交：本机工作区（`[E01.8]` 提交）
- 设计或说明：[README.md](README.md)（没有任务书）；上游参考 `a858550bb`（remote `upstream`）

## 先在真实接口上看（直连、匿名）

临时程序放在 `tools/live_cli/bin/` 下，用完删掉，没有提交。地址只看主机、路径开头和 `expire`、`fcdn` 两个参数。

### 虎牙

- 推荐前 6 个房间（257085、31311340、825290、525701、158731、27599671）最高档的 30 条线路（al、tx、txdirect、hs 的 FLV 和 HLS），旧 UA（7090000）和新 UA（7100004）各请求一次：全部 HTTP 200，FLV 读满 64 KB、HLS 是播放列表，两种 UA 没有差别。
- 新 UA 连续读 257085“流畅”的 al、tx 两条 FLV 630 秒（到点自己断开），各 35.8 MB，中间没有断。
- 结论：虎牙现在不拒旧 UA，这次改动是预防（和 README 一致）。上游仓库的 `assets/play_config.json`（`upstream/master`，2026-10-08）还是 7090000。

### 斗鱼

- 推荐前 15 个房间直连：原画档的线路都是 `expire=300`，CDN 只有 `fcdn=hw`（18 条）和 `fcdn=hs`（5 条）；低档（高清等）是 `expire=0`。**没有一条 `fcdn=ws`**。
- 经本机代理（海外出口）再拉 10 个房间：一样，只有 hw、hs。
- 24422 原画档把 `cdn` 依次指定成 `ws-h5`、`ws`、`tct-h5`、`ali-h5`、`akm-h5`、`hs-h5`、`hw-h5`、空：服务器只回 hw 或 hs，都是 `expire=300`。这个会话拿不到 ws 线路，所以上游补丁针对的情况在这里复现不了。
- 在拿得到的 hw 线路上试了三种写法（24422 原画，每种单独签一次，同时读 400 秒）：

| 写法 | 结果 |
|---|---|
| 原样（`expire=300`） | HTTP 200，读到 300 秒时被 CDN 断开（80.5 MB） |
| 后面追加 `&expire=0`（上游的写法） | HTTP 200，同样在 300 秒被断开（80.6 MB） |
| 把 `expire=300` 换成 `expire=0`（README 方案 c2 的写法） | HTTP 403（`expire` 在签名里） |

- 结论：在 hw 线路上，追加 `expire=0` 不延长有效期，替换会直接 403；ws 线路拿不到，确认不了上游的说法。按 README c2“不认就只记录、不改”，斗鱼不改代码，继续靠租约到期前续期接上。

## 根因

- 虎牙：`packages/live_core/lib/src/sites/huya/huya_api.dart` 的 `hysdkUserAgent` 还是 3.x 的 `pc_exe&7090000`、`SDK(trans&2.35.0.5996)`；`HuyaApi.playUserAgent` 读到上游 `play_config.json` 的 UA 就直接用，那边也是旧版本，所以只改内置值不够，启动后照样被换回旧的。
- 斗鱼：没有需要修的地方（见上）。

## 改了哪些文件

- `packages/live_core/lib/src/sites/huya/huya_api.dart`：`hysdkUserAgent` 改成 `HYSDK(Windows,30000002)_APP(pc_exe&7100004&official)_SDK(trans&2.40.0.6448)`（上游 `a858550bb`，同 simple_live）；`playUserAgent` 读到的远端 UA 如果以 `HYSDK(` 开头、`pc_exe&<数字>&` 的版本号比内置的小，返回 null（站点就用内置的）；版本一样或更新、不是 HYSDK 格式、没有版本号的照旧用远端的（保留原来“远端决定”的行为）。WUP 取令牌和留言板也用这个常量，一起跟到新版本。
- `packages/live_core/lib/src/sites/huya/huya_site.dart`：`playUserAgent` 的注释。
- 测试：`huya_api_test.dart`（新常量；远端旧、相同、更新、`HYSDK(custom)`、非 HYSDK 五种）、`huya_site_test.dart`（远端给 7090000 时 `loadPlayUserAgent` 和媒体请求用内置的）、`douyu_api_test.dart`（`expire=300` 后面追加 `expire=0` 时租约仍按 300 秒，记下实测结论，免得以后照上游补丁加上却以为少了续期）。

## 新设置、翻译键、门禁基线

- 没有。

## 测试

- 先写的失败测试：`huya_api_test.dart` 新用例改之前失败（常量还是 7090000）。
- `packages/live_core` 全部 3660 个通过；`dart analyze --fatal-infos` 无问题；格式检查通过。

## 巡检

- 改之前 `patrol huya douyu`（直连）：两个平台 P1～P12 全部正常，P13 没测（没加弹幕秒数）。斗鱼 P11“3/3 条有租期，最短 4 分钟后续期”；虎牙 P10 三个房间 16 条线路全部能读。
- 改之后 `patrol huya douyu --danmaku 30`（2026-10-08 03:00～03:01 UTC，直连）：斗鱼正常 13、虎牙正常 13，失败 0。虎牙 P10 257085、825290、52035 共 16 条线路（FLV 8、HLS 8）用新 UA 全部能读；斗鱼结果和改之前相同（9263298 没有流，是平台状态，E01.7 已处理）。

## 留下的问题

- 虎牙 UA 仍然由上游仓库的 `play_config.json` 决定（上游改成更新的版本会直接生效；改旧了现在不再降级）；要不要改读本仓库的 `assets/`，维护者定（README 已列）。
- 斗鱼 ws 线路：哪天在真实会话里看到 `fcdn=ws`（日志、巡检或用户反馈），再按上面的表测一次追加和替换，认了再做。

## 真机上要看的

- 不需要专门看：虎牙只是请求头里的版本号，巡检和 10 分钟连续读流已经确认能播；斗鱼没有改代码。K90 平时看虎牙时如果出现 403 或进房就失败，先查这个 UA。
