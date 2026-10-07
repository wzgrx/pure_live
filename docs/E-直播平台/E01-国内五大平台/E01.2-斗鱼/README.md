# E01.2 斗鱼

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：3.x 平台逐个重构（D-001）；升级落地（2026-09-29，[UPGRADES](../../../specs/UPGRADES.md) 2-1，另按统一原则补开播时间、核实别名大小写）；国内平台完善（2026-10-01）和附录 C 落地（C-5～C-8，其中 C-6 改在弹幕包）。过程都记在 [record.md](record.md)
- 旧编号：M4.02、M4.U.2、T02a.2
- 相关：模型 [E05.1](../../E05-平台框架和模型/E05.1-基础模型与接口/README.md)、[E05.2](../../E05-平台框架和模型/E05.2-模型扩展/README.md)（房间身份大小写）；链接 [E04.1](../../E04-链接解析和分享口令/E04.1-平台框架与链接解析/README.md)；弹幕 [D01.3](../../../D-弹幕/D01-平台弹幕协议/D01.3-斗鱼弹幕/README.md)；租期拼接在 G 组；Cookie 和续期凭据的存储在 J02.1，Cookie 页的开关在 K01.1；巡检 [E01.6](../E01.6-国内五大平台巡检和修复/README.md)；决定 D-001、D-017、D-018（见 [DECISIONS.md](../../../DECISIONS.md)）
- 代码：`packages/live_core/lib/src/sites/douyu/`（`douyu_api.dart` 883 行解析和签名，`douyu_site.dart` 568 行请求编排）；应用里在 `apps/pure_live/lib/app/platforms.dart:142` 建 `DouyuSite`（`:68` 的 `StoreDouyuLogin` 接续期凭据）；样本 `fixtures/douyu/`（33 组接口样本，含签名向量 S07、续期向量 S12；另有 `danmaku/` 下 4 组弹幕样本归 D01.3）

## 目标

把 3.x 的斗鱼适配器（`lib/core/site/douyu/douyu_site.dart` 691 行、`douyu_utils.dart` 657 行）重构进 `live_core`：分类、分区、推荐、搜索房间和主播、详情、清晰度和逐线路取流、签名、登录续期、租期、链接都和 3.x 一样能用。同时修掉 3.x 的靓号打不开、出错时显示成未开播、HTML 实体原样显示、设备号写进日志等 16 个问题，并去掉对 GetX 全局设置的依赖（Cookie 和续期凭据改为注入）。

## 平台接口要点

| 功能 | 接口（`www.douyu.com` 除非另写） | 位置 |
|---|---|---|
| 分类 | `m.douyu.com/api/cate/list`（10 个一级、约 490 个分区）；图标为空时依次用 `smallIcon`、`pic` | `douyu_site.dart:136`、`:140` |
| 分区房间 | `/gapi/rkc/directory/mixList/2_<分区>/<页>`，每页 120 个，按 `pgcnt` 或空页判断末页 | `:149`、`:151`；`douyu_api.dart:246-249` |
| 推荐 | `/japi/weblist/apinc/allpage/6/<页>`，每页 40 个，只在空页结束 | `:157`、`:159` |
| 搜索 | `/japi/search/api/searchShow`（房间）、`/japi/search/api/searchUser`（主播）；空关键词不发请求 | `:167`、`:182` |
| 详情 | `/betard/<rid>`（Edge 114 的 UA）；不认识的数字当靓号读房间页的 `window.room_id`，非数字当别名读房间页的 302；房间号保持请求时的写法，真实房间号放在 `DouyuRoomData` | `:200-257`；`douyu_api.dart:346` |
| 签名描述符 | `/wgapi/livenc/liveweb/websec/getEncryption?did=…`：按秒比较有效期、提前 30 秒作废、最多复用 5 分钟、换设备号立即作废、并发只取一次 | `:431` |
| 取流 | `/lapi/live/getH5PlayV1/<rid>`，每个（档位、CDN）签一次，最多请求两次（第一次失败后续期，第二次强制换描述符）；`error != 0` 是房间状态，报 `StreamUnavailable` 不重试 | `:286`、`:367-405` |
| 恢复和录制 | 恢复时重新取元数据和签名（`resolvePlayUrlsForRecoveryRaw`）；录制按线路游标只签一条（`resolvePlayUrlAtRaw`） | `:306`、`:331` |
| 租期 | 地址里 `expire` 大于 0 才有租期，提前 `min(45 秒, 租期 / 4)` 续期，`cutsConnection: true`（到期 CDN 断开，新流按关键帧拼接）；打开“登录后强制续期”时 `expire=0` 的 FLV 按 5 分钟租期 | `:449`、`:454`；`DouyuApi.forcedLeaseLifetime` |
| 登录续期 | `passport.douyu.com/lapi/passport/iframe/safeAuth`，用 LTP0 和单独保存的 `dy_did`；Cookie 由 `CookieVault`、续期凭据由 `DouyuLoginStore` 注入 | `:499`、`:506`；接口 `:39` |
| 设备号 | 一个请求链只用一个 DID：登录 Cookie 有 `dy_did` 用它，否则每个适配器随机一个 | `:105`；`douyu_api.dart:698` |
| 弹幕地址 | `wss://danmuproxy.douyu.com:8506`，`DouyuDanmakuArgs` 带真实房间号 | `douyu_api.dart:157` |
| 链接 | 房间页 `/<rid>`、分享页 `/room/share/<号>`、别名经 302 解析且只请求一次 | `:527`、`:540`、`:555` |

## 3.x 和现状

| 方面 | 3.x（`lib/core/site/douyu/`） | 现在 | 说明 |
|---|---|---|---|
| 分类、分区、推荐、搜索 | `douyu_site.dart:75`、`:126`、`:446`、`:573`（3.x 末期经“v4 桥接”走归档适配器） | `douyu_site.dart:136-182` | 统一重写；桥接修过的问题（标题实体、轮播状态、别名、末页信号）保留，把热度转成数字的改动不保留（保留 `353.9万` 这样的平台文字） |
| 详情 | `:482`；靓号必失败（`betard` 只认真实房间号），出错返回“当前播放房间”的快照并标未开播 | `:257` | 靓号、别名都能打开；出错抛 `NotFound`、`RiskControl`、`ApiChanged` |
| 取流和签名 | `:157`、`:216`、`douyu_utils.dart`；所有错误一律重试，签名状态是进程级静态变量 | `:275-331` | 状态按适配器实例保存；`error != 0` 不重试；线路自带请求头（Origin、房间 Referer、UA、DID Cookie）和租期 |
| 文字 | 标题、简介里的 `&nbsp;`、`&mdash;` 原样显示；缺字段写出 `"null"` | `douyu_api.dart` 解码实体，缺失为空 | 3.x 问题 5、7 |
| 搜索里的轮播房间 | 标成未开播，而同一房间的详情是回放 | 回放 | 3.x 问题 6；斗鱼的轮播（`videoLoop`）有流可播，所以用 `replay` 不用 `carousel` |
| 登录 | `douyu_utils.dart:211-227` 空令牌（`dy_auth=`）也算登录 | 空值等于没有 | 3.x 问题 10 |
| 日志 | `douyu_utils.dart:565` 每次取流失败把设备号写进日志 | 适配器不写日志 | 3.x 问题 11 |
| 弹幕 | `getDanmaku()` `:70` | `live_danmaku/lib/src/sites/douyu.dart`（D01.3） | 下播包 `rss` 结束连接、礼物 `dgb` 上报 |

## 结果

- 首次重构（2026-09-28，提交 `dc09e6d8e`）：16 个 3.x 问题和处理见 record.md“审查发现的 v3 问题”，13 条有意差异见“与 v3 的有意差异”。保留了 3.x 的 45 秒续期提前量、两个 UA、房间号不换成规范号（避免用靓号关注的房间身份变化），没有采用上游电视版把续期结果整份替换 Cookie 的做法（会丢 LTP0）。
- 升级落地（2026-09-29，`20c9ea20e`）：UPGRADES 2-1“登录后强制续期”（`DouyuSite(forceRenewal:)`，默认关；设置项是 J02.1 的 `Settings.douyuForceRenew`，键名 `douyuForceRenew`，`platforms.dart:146` 传入，开关在 K01.1 的斗鱼 Cookie 页和设置页“平台与账号”；record.md 和 `douyu_site.dart:73` 的注释写成 `douyuForceRenewal`，和实际键名不一样）；开播时间取 `betard` 的 `room.show_time`（只在直播中）；实测别名不分大小写（`lpl`、`LPL`、`Lpl` 都到 288016），斗鱼加进 `SiteIds.caseInsensitiveRoomIds`。
- 国内平台完善（2026-10-01，`8eca75a32`）：真实接口检查全部正常（签名仍有效，13 条线路都拉到 FLV）；修了分区图标为空；弹幕礼物上报。附录 C：C-6 下播通知完成（`rss` 且 `ss@=0`），C-5 进房补醒目留言没找到网页接口。
- 测试：`packages/live_core/test/sites/douyu_api_test.dart` 45 个 `test(` 写法、`douyu_site_test.dart` 35 个（record.md 最后统计为 60、35 个用例，样本对照是循环生成的）；弹幕测试 `packages/live_danmaku/test/douyu_test.dart` 29 个 `test(` 写法（record.md 统计 45 个用例，归 D01.3）。

## 验证

- 自动测试：样本逐键对照 3.x 的冻结输出；签名向量（S07，10 组）、续期向量（S12）；描述符并发和复用、租期查询、强制续期、靓号和别名、链接、传输错误映射都有用例。
- 真实接口：2026-09-28、09-29 各用新适配器实际请求过一次（分类到取流全链路，`forceRenewal` 打开）；2026-10-01 跑了推荐、分类、分区、搜索、详情（含靓号 1 → 9617408、轮播 93976）、13 条线路、两个房间各 120 秒弹幕（record.md“真实环境检查”）。
- 真机：播放和弹幕 K90 看过（2026-10-01 两轮真机测试，[FEATURES.md](../../../inventory/FEATURES.md) 第 14 节斗鱼一行：播放、弹幕“完成，K90 看过”，登录“Cookie、续期”）；登录后强制续期要用户自己的账号，K90 上没有专门看过。

## 留下的问题

- 受限类型受阻：`betard` 有 `is_password`、`pwd`、`eticket`，但 2026-09-29 和 10-01 两次扫了推荐前 80 个房间都找不到付费房、密码房的样本，`restriction` 不填（未提供，不填 `none`）。没有任务管，找到样本时由 [E01.6](../E01.6-国内五大平台巡检和修复/README.md) 巡检补上。
- 进房补醒目留言（附录 C 的 C-5，受阻）：PC 新版直播间和手机网页的脚本里都找不到超级弹幕列表接口，醒目留言只从弹幕来。UPGRADES 写“找到接口后再做（未排）”，没有任务管；FEATURES.md 第 14 节斗鱼一行的备注也写着受阻。
- 续期提前量 45 秒够不够、强制续期的 5 分钟租期是否合适，要在关键帧拼接实测后再定（上游电视版是最多 90 秒）：record.md 写“等 G 实测”，G01.1、G02.1 都已完成，没有专门的任务管。
- 加入已下播或轮播房间时服务端会不会立刻发 `ss@=0` 的 `rss`（会的话轮播房间的弹幕会马上结束）没核实：归弹幕任务 D01.3，真机时留意（S02 的 K90 验证没有这一条）。
- 推广（`hpsc`）、粉丝牌升级（`blab`）、全站礼物广播（`spbc`）、贵宾数（`oun`/`oni`）：附录 C 的 C-7、C-8 定为不做（刷屏；贵宾数不是在线人数）。
- 分区页每页 120 个只显示前 40 个（3.x 问题 14、UPGRADES A-1）：已由分区页 I03.1 修好（按页显示整页），平台层不用改。
- 接口会变：定期巡检归 [E01.6](../E01.6-国内五大平台巡检和修复/README.md)。
