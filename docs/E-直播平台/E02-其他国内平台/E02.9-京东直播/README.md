# E02.9 京东直播

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：3.x 平台逐个重构（D-001）；之后的升级落地（2026-09-29，UPGRADES 28-1～28-7，28-7 受阻）记在 [record.md](record.md)；聊天由 D01.25 接上
- 旧编号：M4.28、M4.U.28、T02b.9
- 相关：模型 [E05.1](../../E05-平台框架和模型/README.md)、[E05.2](../../E05-平台框架和模型/README.md)（占位值规则 X-2 的例子“JD Live”）；链接 [E04.1](../../E04-链接解析和分享口令/README.md)；聊天 D01.25；回放点播在 G 组；决定 D-001、D-017、D-018
- 代码：`packages/live_core/lib/src/sites/jdlive/`（`jdlive_api.dart` 791 行解析，`jdlive_site.dart` 438 行请求编排）；样本 `fixtures/jdlive/`（17 组）

## 目标

把 3.x 的京东直播适配器（`lib/core/site/jdlive/` 三个文件共 727 行）重构进 `live_core`。京东直播是带货直播：精选列表和不要签名的播放接口能用，带标题和店铺名的详情接口要 h5st 签名，所以名字只能来自本次运行里见过的列表卡片。修掉 3.x 的 18 个问题（精选列表常常只有一页、重启后刷新关注把店铺名变成占位“JD Live”、进房后封面变成模糊背景、缓存没有上限等）。

## 平台接口要点

| 功能 | 接口（`api.m.jd.com/api?appid=h5-live&functionId=…`，`apiHeaders`：iOS Safari UA、`Origin`、`Referer: https://lives.jd.com/`，不跟随跳转、不带 Cookie） | 位置 |
|---|---|---|
| 分类 | 一个分类、一个分区“精选直播购物”（`areaType: official`），不发请求；目录说明键 `jdlive_directory_scope` | `jdlive_site.dart:85`、`:211` |
| 精选列表 | `liveListWithTabToM`，`body={"tabId":1,"currentCount":…,"page":…}`；第 1 页开一个带首页时刻的序列，之后带上一页的 `currentCount`；只取 `templateType` 1 的直播，运营位跳过；“这一页有直播而且 `currentCount` 往前走了”才有下一页（实测 7 页约 200 场） | `:218-241` |
| 搜索 | 场次号（5～18 位数字）或房间链接直接查播放接口；其他关键词在这个词自己的精选序列里按场次号、店铺账号、店铺名、标题筛选（最多 32 个序列） | `:249-259` |
| 详情 | `getImmediatePlayToM`（不要签名），只有状态、背景图和地址；店铺名、标题、头像用见过的卡片补（最多 2000 个），没见过时留空；进房和录制在直播中时再下载 HLS 媒体列表并校验（2 个请求），刷新、开播状态 1 个 | `:333-349` |
| 画质和线路 | 两档 `HLS（推荐）`（id `hls`）和 `FLV 原始线路`（id `flv`），地址必须是 `https` 的 `*.jdcloud.com/live/` 下、流名相同；FLV 坏了用 `pcVideoUrl`，一个坏地址只让那一档不可用；线路带 `JdLiveApi.mediaHeaders`；回放（状态 3）一档“原画”（id `replay`），是 `discover.300hu.com` 上的整场录像 | `:387-408` |
| 链接 | `lives.jd.com/#/<场次号>` 等 | `:426` |

## 3.x 和现状

| 方面 | 3.x（`lib/core/site/jdlive/`） | 现在 | 说明 |
|---|---|---|---|
| 精选翻页 | `jd_live_api.dart:244` 本页至少 30 场才有下一页，平台每页直播数不固定，常常只有一页 | 有直播且 `currentCount` 前进就继续 | 28-1 |
| 名字 | `:260-264` 没见过的房间写占位 `JD Live`，重启后刷新关注把存下的名字覆盖掉 | 留空，`mergeFrom` 保留存下的值，界面显示平台名 | 28-2（E05.2 占位值规则） |
| 封面 | `:264` 进房后封面换成 `blurredImg` 并随关注存下 | 封面只用卡片的 `indexImage`，模糊图放 `JdLiveRoom.background` | 28-3 |
| 地址校验 | `:253-257` 缺 FLV 或 HLS、流名不同，整个房间（含刷新）失败 | 只让那一档不可用 | 28-4 |
| 媒体请求头 | 3.x 播放层没有京东分支，播放和录制不带 | 线路带 UA、`Origin`、`Referer` | 28-5 |
| 回放 | 状态 3 显示未开播 | 回放，有录像就播放（点播），没有标 `unplayable` | 统一原则 |
| 仅限 App | `secret` 1 混在状态里 | 受限类型 `appOnly`，与状态无关 | 统一原则 |
| 缓存 | `jd_live_site.dart:28-29` 两个 Map 没有上限 | 卡片 2000、搜索序列 32 | 3.x 问题 3 |
| 错误 | 9 种 `JdLiveFailure`，开播状态把“仅限 App”“暂停”“未知”都报 `access` | `NeedsLogin`、`StreamUnavailable`、`ApiChanged` 分开 | 3.x 问题 7、10 |
| 聊天 | `EmptyDanmaku` | `live_danmaku/lib/src/sites/jdlive.dart`（D01.25） | 新增 |

## 结果

- 首次重构（2026-09-28，提交 `9d36d0852`）：18 个 3.x 问题、9 条有意差异见 record.md；补录了同一时刻的精选、播放接口和 HLS 媒体列表。
- 升级落地（2026-09-29，`c315d897e`）：28-1～28-5 完成，28-6 聊天交给 D01.25，28-7 受阻；回放、`appOnly`、`unplayable` 按统一原则；列表坏条目只跳过这一条。2026-09-30（`9efd7ecde`）房间公告说明两个观看数的含义。
- 测试：`packages/live_core/test/sites/jdlive_api_test.dart` 29 个 `test(` 写法、`jdlive_site_test.dart` 30 个；聊天 `packages/live_danmaku/test/sites/jdlive_test.dart`。

## 验证

- 自动测试：样本逐键对照 3.x 冻结输出；精选翻页、占位名字不覆盖、封面不换、坏地址只少一档、媒体列表校验（以 `#EXTM3U` 开头、引用同一主机、1～1000 个）。
- 真实接口：2026-09-28 20:04～20:15 UTC 两次把精选翻到空页（7 页）、请求了 13 个播放接口、一场回放录像（1.45 MB、约 9,500 个分片）和网页端脚本列出的全部 `functionId`。
- 真机：没有在 K90 上专门看过（[FEATURES.md](../../../inventory/FEATURES.md) 第 14 节：28-7 标题和店铺名受阻）。

## 留下的问题

- 28-7 受阻：`liveDetailToM` 等带名字的接口要 h5st 签名；不要签名的 `livePlayBackToM` 没有店铺名、不含正在直播的场次。直接粘贴链接进房时没有名字。
- 3.x 存下的占位值（`JD Live`、`userId` 等于房间号、头像等于封面）不会自己清掉，迁移时可以清（J02.1、J06.1，record.md 的“数据清理建议”）。
- `secret` 为 1 的真实样本、回放录像在别的主机上的情况没见过。
- 开播时间不提供（精选卡片和播放接口都没有）。
