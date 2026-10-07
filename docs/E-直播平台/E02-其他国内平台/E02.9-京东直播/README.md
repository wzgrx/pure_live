# E02.9 京东直播

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：3.x 平台逐个重构（D-001）；之后的升级落地（2026-09-29，UPGRADES 28-1～28-7，28-3 部分完成，28-7 受阻）记在 [record.md](record.md)；聊天由 D01.25 接上（同时改了房间公告）
- 旧编号：M4.28、M4.U.28、T02b.9
- 相关：模型 [E05.1](../../E05-平台框架和模型/E05.1-基础模型与接口/README.md)、[E05.2](../../E05-平台框架和模型/E05.2-模型扩展/README.md)（占位值规则 X-2 的例子“JD Live”）；链接 [E04.1](../../E04-链接解析和分享口令/E04.1-平台框架与链接解析/README.md)；聊天 [D01.25](../../../D-弹幕/D01-平台弹幕协议/D01.25-京东直播弹幕/README.md)；直播间模糊背景 [A07.16](../../../A-界面设计/A07-直播间界面/A07.16-京东直播间模糊背景/README.md)（28-3 余下）；回放点播的播放在 G02.1；决定 D-001、D-017、D-018
- 代码：`packages/live_core/lib/src/sites/jdlive/`（`jdlive_api.dart` 791 行解析，`jdlive_site.dart` 438 行请求编排）；样本 `fixtures/jdlive/`（ls 共 17 项：15 组接口录制，另有 `legacy_expected.dart` 补出 3.x 冻结输出和弹幕样本目录 `danmaku/`）；应用在 `apps/pure_live/lib/app/platforms.dart:180` 建 `JdLiveSite(http)`

## 目标

把 3.x 的京东直播适配器（`lib/core/site/jdlive/` 三个文件共 727 行）重构进 `live_core`。京东直播是带货直播：精选列表和不要签名的播放接口能用，带标题和店铺名的详情接口要 h5st 签名，所以名字只能来自本次运行里见过的列表卡片。修掉 3.x 的 18 个问题（精选列表常常只有一页、重启后刷新关注把店铺名变成占位“JD Live”、进房后封面变成模糊背景、缓存没有上限等）。

## 平台接口要点

| 功能 | 接口（`api.m.jd.com/api?appid=h5-live&functionId=…`，`apiHeaders`：iOS Safari UA、`Origin`、`Referer: https://lives.jd.com/`，不跟随跳转、不带 Cookie；每次调用一个 20 秒期限） | 位置 |
|---|---|---|
| 分类 | 一个分类、一个分区“精选直播购物”（`areaType: official`），不发请求；目录说明键 `jdlive_directory_scope` | `jdlive_site.dart:85`、`:211` |
| 精选列表 | `liveListWithTabToM`，`body={"tabId":1,"currentCount":…,"page":…}`；第 1 页开一个带首页时刻的序列，之后带上一页的 `currentCount`；只取 `templateType` 1 的直播，运营位跳过；“这一页有直播而且 `currentCount` 往前走了”才有下一页，同一序列里列过的场次不再列出，一页全是列过的也结束（28-1，实测 7 页约 200 场）；目录、推荐和每个搜索词各用各的序列 | `jdlive_site.dart:156-188`、`:218`、`:232`、`:241`、`:432` |
| 搜索 | 场次号（5～18 位数字）或房间链接直接查播放接口；其他关键词在这个词自己的精选序列里按场次号、店铺账号、店铺名、标题筛选（最多 32 个序列） | `jdlive_site.dart:18`、`:249`、`:259` |
| 详情 | `getImmediatePlayToM`（不要签名），只有状态、背景图和地址；店铺名、标题、头像、封面用本次运行见过的卡片补（最多 2000 个），没见过时留空（28-2），`mergeFrom` 保留关注里存下的；进房和录制在直播中时再下载 HLS 媒体列表并校验（以 `#EXTM3U` 开头、引用同一主机、1～1000 个，2 个请求），刷新、开播状态 1 个；状态 3 是回放；`secret` 1 是受限类型 `appOnly`（仍是直播中） | `jdlive_site.dart:15`、`:140`、`:305`、`:320`、`:333-349` |
| 画质和线路 | 两档 `HLS（推荐）`（id `hls`）和 `FLV 原始线路`（id `flv`），地址必须是 `https` 的 `*.jdcloud.com/live/` 下、流名相同；FLV 坏了用 `pcVideoUrl`，一个坏地址只让那一档不可用（28-4），一个地址都没有是 `unplayable`；线路带 `JdLiveApi.mediaHeaders`（28-5）；回放一档“原画”（id `replay`），是 `discover.300hu.com` 上的整场录像（不预先下载），拿不到录像标 `unplayable` | `jdlive_site.dart:370`、`:387-408` |
| 链接 | `lives.jd.com/#/<场次号>` 等 | `jdlive_site.dart:426` |

聊天（`liveauth` 鉴权后的 WebSocket）归 [D01.25](../../../D-弹幕/D01-平台弹幕协议/D01.25-京东直播弹幕/README.md)：进房时给 `JdLiveDanmakuArgs`；连上后报正在观看人数（`audience.dart` 的京东改为 `roomRealtime`）。

## 3.x 和现状

| 方面 | 3.x（`~/ref/v3ref/lib/core/site/jdlive/`） | 现在（`packages/live_core/lib/src/sites/jdlive/`） | 说明 |
|---|---|---|---|
| 精选翻页 | `jd_live_api.dart:244` 本页至少 30 场才有下一页，平台每页直播数不固定，常常只有一页 | 有直播且 `currentCount` 前进就继续 | 28-1 |
| 名字 | `jd_live_api.dart:260-263` 没见过的房间写占位 `JD Live`，重启后刷新关注把存下的名字覆盖掉 | 留空，`mergeFrom` 保留存下的值，界面显示平台名 | 28-2（E05.2 占位值规则） |
| 封面 | `jd_live_api.dart:264` 进房后封面换成 `blurredImg` 并随关注存下 | 封面只用卡片的 `indexImage`，模糊图放 `JdLiveRoom.background` | 28-3 |
| 地址校验 | `jd_live_api.dart:253-257` 缺 FLV 或 HLS、流名不同，整个房间（含刷新）失败 | 只让那一档不可用 | 28-4 |
| 媒体请求头 | 3.x 播放层没有京东分支，播放和录制不带 | 线路带 UA、`Origin`、`Referer` | 28-5 |
| 回放 | 状态 3 显示未开播 | 回放，有录像就播放（点播），没有标 `unplayable` | 统一原则 |
| 仅限 App | `secret` 1 混在状态里（状态“未知”） | 受限类型 `appOnly`，与状态无关；取流报 `StreamUnavailable` | 统一原则 |
| 缓存 | `jd_live_site.dart:28-29` 两个 Map 没有上限 | 卡片 2000、搜索序列 32 | 3.x 问题 3 |
| 错误 | 9 种 `JdLiveFailure`，开播状态把“仅限 App”“暂停”“未知”都报 `access` | `NeedsLogin`、`StreamUnavailable`、`ApiChanged` 分开 | 3.x 问题 7、10 |
| 聊天 | `EmptyDanmaku` | `packages/live_danmaku/lib/src/sites/jdlive.dart`（D01.25） | 新增 |

## 结果

- 首次重构（2026-09-28，提交 `9d36d0852`）：18 个 3.x 问题、9 条有意差异见 record.md；补录了同一时刻的精选、播放接口和 HLS 媒体列表。
- 升级落地（2026-09-29，`c315d897e`）：28-1～28-5 完成（28-3 平台层），28-6 聊天交给 D01.25，28-7 受阻；回放、`appOnly`、`unplayable` 按统一原则；列表坏条目只跳过这一条；7 个新样本（`S05-*`）。画质 id、身份不变，没有设置项。
- D01.25 接聊天时把房间公告 `JdLiveApi.chatNotice` 改成“列表里的人数是累计观看；直播中连上弹幕后，显示的是正在观看的人数。”（`jdlive_api.dart:270`；提交 `9efd7ecde`，2026-09-30）。
- 测试：`packages/live_core/test/sites/jdlive_api_test.dart` 29 个 `test(` 写法、`jdlive_site_test.dart` 30 个（record.md 按实际用例统计 57 个：27 + 30）；聊天 `packages/live_danmaku/test/sites/jdlive_test.dart` 32 个。

## 验证

- 自动测试：样本逐键对照 3.x 冻结输出（列表 38 种、播放接口 31 种修改逐一对照，变了的写明编号）；精选翻页、占位名字不覆盖、封面不换、坏地址只少一档、媒体列表校验；回放录像和不可播放的回放；仅限 App 是直播中；28-7 的证据（回放列表没有店铺名、不含在播的那场）；测试时钟注入为录制时刻，`tools/timeshift/run.sh 30 1825` 全部通过。
- 真实接口：2026-09-28 20:04～20:15 UTC 直连、匿名，两次把精选翻到空页（7 页 200 场）、请求了 13 个播放接口、一场回放录像（1.45 MB、约 9,500 个分片）和网页端脚本列出的全部 `functionId`。不用代理。
- 真机：没有在 K90 上专门看过（[FEATURES.md](../../../inventory/FEATURES.md) 第 14 节京东直播一行“播放：完成”“弹幕：新增”，备注“28-7 标题和店铺名受阻；28-3 直播间模糊背景 → A07.16”）。

## 留下的问题

- 28-3（UPGRADES，部分完成）：平台层封面只用列表卡片的封面，模糊图在 `JdLiveRoom.background`；直播间用它作背景没做（直播间设计没有背景图的位置）→ [A07.16](../../../A-界面设计/A07-直播间界面/A07.16-京东直播间模糊背景/README.md)。
- 28-7（UPGRADES，受阻）：`liveDetailToM` 等带名字的接口要 h5st 签名；不要签名的 `livePlayBackToM` 没有店铺名、不含正在直播的场次。直接粘贴链接进房时没有名字，界面显示平台名。没有任务管。
- 3.x 存下的占位值（`nick`、`title` 等于 `JD Live`，`userId` 等于房间号，`avatar` 等于封面）不会自己清掉：record.md“数据清理建议”给 J02.1 的可选清理没有做（`packages/live_store/lib/src/legacy/` 里没有京东的清理规则），覆盖安装时的核对在 J06.1；没有任务专门管。
- `secret` 为 1 的真实样本、回放录像在别的主机上、状态 3 刚结束录像还没生成、`livingLiveId` 的含义都没见过。
- 开播时间不提供（精选卡片和播放接口都没有，只有结束的场次能从录像地址看出）。
- 回放画质名“原画”、两档画质名、公告是平台层给的中文，英文界面仍显示中文 → [Z05.2](../../../Z-工程文档和维护/Z05-多语言/Z05.2-英文界面里平台给的中文/README.md)。
