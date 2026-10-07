# E01.6 国内五大平台巡检和修复（持续）：任务书

> 这是持续任务：每一轮照本任务书做一遍，结果追加到本文件夹的 `record.md`（每轮一节，标题写日期）。

## 背景

- 来源：docs v0 登记的持续任务（旧编号 T02a.6）。哔哩哔哩、斗鱼、虎牙、抖音、快手是用户每天用的平台（[FEATURES.md](../../../inventory/FEATURES.md) 第 14 节：五个平台的播放和弹幕都“K90 看过”），平台改接口、加风控后用户直接看到“打不开”“搜不到”“分区空白”。
- 现象（上一轮发现的，说明为什么要定期做）：2026-09-30～10-01 的人工检查（“国内平台完善”，哔哩哔哩是提交 `81733c1e6`）当场发现三处已经失效：
  1. 哔哩哔哩分区页对游客每一页都报风控：3.x 和 E01.1 用的 `second/getList`（WBI 签名加 `w_webid`）现在一律回 -352，续签重试一次后仍是 -352 → 先用不签名的 `room/v1/area/getRoomList`（`packages/live_core/lib/src/sites/bilibili/bilibili_site.dart:247-266`），失败时（限流除外）再退回签名接口；
  2. 虎牙搜索房间、搜索主播全部 `HTTP 403 Not allowed`（不带 User-Agent 被拒）→ 搜索带移动端 UA（`huya_site.dart:262-268` 的 `_searchHeaders`），`packages/live_net/lib/src/io_http.dart:29-36` 也保留 dart:io 默认 UA；
  3. 抖音游戏直播间详情没有分区 → `douyin_api.dart` 的 `_detailArea`。
- 为什么现在做：第一档。上一轮已经过去一周，4.0.0 已发布（2026-10-02）。
- 已经做过的：五个平台各自 record.md 的“真实环境检查”（[E01.1](../E01.1-哔哩哔哩/record.md) 第 177 行起，其余同名节）是本任务的基准；那次的临时程序没进仓库。巡检工具在 [E07.1](../../E07-平台巡检/E07.1-平台巡检工具/brief.md)（第一档，未开始）：本任务优先用它的 `patrol` 命令，它还没做好时照本任务书写临时程序。

## 目标和验收

1. 检查清单：E07 子分类文件夹的 `CHECKS.md` 里五大平台这五行写全（检查项 P1～P13 的对象：关键词、在播房间怎么挑、固定的未开播房间、不存在的房间号、平台特有的情况、判定标准）；E07.1 还没建 `CHECKS.md` 时由本任务先建，格式照 [E07.1 的任务书](../../E07-平台巡检/E07.1-平台巡检工具/brief.md)“第 1 阶段”。维护者看过。
2. 结果：本文件夹 `record.md` 新加一节“<日期> 第 N 轮”，五个平台各一张表 `| 检查项 | 结果 | 说明 |`（结果只能是正常 / 失败 / 没测到 / 不支持），写明日期时间（UTC）、直连、匿名、每个平台联网用时；用了工具的把报告存到本文件夹 `runs/<日期>.md`。
3. 每个失效项都有：根因（文件:行）、脱敏后的新样本（`fixtures/<平台>/S<nn>-<情况>/`）、改之前会失败的测试、修复提交；修复后重跑这一项，结果写进同一张表（“失败 → 已修”）。
4. 没修的失效项写明原因（要登录、要签名而拿不到、平台下线了这个功能），开到对应任务（弹幕到 D01.2～D01.6，界面到 A/C/I 组），并请维护者在登记表 `note` 写一句。
5. 每轮复查上一轮修过的三处（哔哩哔哩分区、虎牙搜索、抖音游戏分区），表里单独一行。
6. 门禁通过；修复合并后维护者在 K90 上进对应平台的一个直播间确认能播。

## 现状（读代码得出，写文件:行）

- 适配器在 `packages/live_core/lib/src/sites/{bilibili,douyu,huya,douyin,kuaishou}/`，应用在 `apps/pure_live/lib/app/platforms.dart:141-150` 建：哔哩哔哩带 `storedUid`，斗鱼带续期 `StoreDouyuLogin` 和 `forceRenewal`，虎牙、快手带 `preferH264`。巡检时不经过应用：`BilibiliSite(IoLiveHttp(), cookies: MemoryCookieVault())` 这样自己建（`IoLiveHttp` 在 `packages/live_net/lib/src/io_http.dart:17`，`MemoryCookieVault` 在 `cookies.dart:15`）。
- 要调的公共接口：`LiveSite` 的 `getRecommendRooms`、`getCategories`、`getCategoryRooms`、`searchRooms`、`searchAnchors`、`getRoomDetail`（`packages/live_core/lib/src/live_site.dart:30-46`）；扩展 `discoverPlayQualities`（`:468`）、`resolvePlayUrls`（`:421`）；线路 `LivePlayLine`（`play_line.dart:41`：地址、请求头、格式、编码、线路编号、租期 `PlayLease` `:18`）；错误 `SiteError` 9 种（`site_error.dart:9-112`）；链接 `roomIdFromUrl`、`needsResolving`/`resolveUrl`（哔哩哔哩 `bilibili_site.dart:600-625`、斗鱼 `douyu_site.dart:527-555`、虎牙 `huya_site.dart:813-829`、抖音 `douyin_site.dart:761-804`、快手 `kuaishou_site.dart:433`）。
- 弹幕连接（`--danmaku` 或临时程序里连）：`packages/live_danmaku/lib/src/sites/{bilibili,douyu,huya,douyin,kuaishou}.dart`，应用的表 `platforms.dart:202-211`（抖音的 `DouyinDanmakuArgs` 由 `DouyinSite.danmakuArgs` 给，`douyin_site.dart:604`；快手用 `http`）。
- 各平台最容易坏的地方：

| 平台 | 位置 | 风险 | 上一轮的情况 |
|---|---|---|---|
| 哔哩哔哩 | `bilibili_site.dart:92`（`_buvid`，`finger/spi`）、`:118`（`_keys`，WBI 密钥）、`:136`（`_accessId`，`w_webid`）、`:167-184`（签名请求和 -352 续签）；`:247-266`（分区：先不签名的 `getRoomList`）；`:415-468`（`getRoomPlayInfo`，游客请求 400 实际给 250；轮播走 `getRoundPlayVideo`）；`:498`（弹幕凭据最多 4 次） | 风控码 -352、-412；WBI 算法变；`getRoomList` 也被签名 | 分区失效 → 已修 |
| 斗鱼 | `douyu_site.dart:202-257`（`betard`、靓号读房间页 `window.room_id`、别名 302）；`:367`（`_play`：`getEncryption` 描述符 + `getH5PlayV1` 签名）、`:413`（`_descriptorFor`）；`:472-506`（续期） | 签名算法、描述符格式；`betard` 对靓号的回答 | 正常 |
| 虎牙 | `huya_site.dart:286`（`_profile`，`profileRoom`，约 30 秒公共缓存）；`:645`（`_sign`，AntiCode）、`:750`（`_fetchToken`，WUP `getCdnTokenInfoEx`，解析 `huya_api.dart:927-929`）；`:774-784`（匿名登录拿 uid）；`:237-268`（搜索和 UA） | AntiCode 参数、WUP 结构、搜索拦截 | 搜索 403 → 已修 |
| 抖音 | `douyin_site.dart:171`（`_bootstrap`，首页取 `ttwid`）；`douyin_sign.dart`（a_bogus 等签名）；`:222-283`（分区签名，遇到滑块退到不签名的 `webcast.amemv.com`）；`:528`（`_enter`）、`:550`（房间页）、`:560`（reflow） | 签名被拒、滑块、页面结构 | 游戏直播间没分区 → 已修 |
| 快手 | `kuaishou_site.dart:24`（`misc2` 上报地址）、`:105`（`_ensureSession`，游客会话 30 分钟）、`:123`（`_reportDevice`）；`kuaishou_api.dart:219-221`（`isLiving` 决定开播、`errorType` 22 是不存在）、`:603-608`；`:174`、`:803`（`result` 2 限流、10 风控） | 游客门禁、页面结构、限流 | 正常（2.5 秒间隔没被限流） |

## 3.x 基线

- 3.x 没有巡检，靠 issue。3.x 的接口用法在 `lib/core/site/<平台>/`（`git show v3.2.11:lib/core/site/bilibili/bilibili_site.dart` 等），只用来对照接口原来的样子；修复以 4.x 当前代码为准。
- 不能改变用户看得到的行为（清晰度名称和 id、房间身份、关注分组），除非失效本身就是这些；改了要在 record.md 写明并引用决定。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节分阶段、第 8 节合并审查、第 14 节规则）。
2. `docs/specs/ENGINEERING.md`；`fixtures/README.md`（样本格式和脱敏规则；它写的 `tools/live_cli fixture capture` 在 master 上还没有，录样本时手工按它的格式写 `body.*` 和 `meta.json`，并按“手工补录”一条脱敏）。
3. 本文件夹的 `README.md`；五个平台 record.md 的“真实环境检查”“修好的问题”两节：[E01.1](../E01.1-哔哩哔哩/record.md)、[E01.2](../E01.2-斗鱼/record.md)、[E01.3](../E01.3-虎牙/record.md)、[E01.4](../E01.4-抖音/record.md)、[E01.5](../E01.5-快手/record.md)。
4. [E07.1 的任务书](../../E07-平台巡检/E07.1-平台巡检工具/brief.md)（检查项 P1～P13 和判定标准、报告格式、隐私过滤）。

## 范围

- 可以改：`packages/live_core/lib/src/sites/{bilibili,douyu,huya,douyin,kuaishou}/`、对应的 `packages/live_core/test/sites/*_test.dart`、`fixtures/{bilibili,douyu,huya,douyin,kuaishou}/` 下新加的样本；连接凭据（哔哩哔哩 `getDanmuInfo`、抖音签名、快手 feed 参数）失效时可以改 `packages/live_danmaku/lib/src/sites/<平台>.dart` 和它的测试；`docs/E-直播平台/E07-平台巡检/CHECKS.md` 的五大平台五行；本文件夹的 `record.md`、`runs/`。
- 不能改：`live_core` 的公共模型和接口（`live_room.dart`、`live_site.dart`、`sites.dart`）——需要改时停下写进报告；其他平台；应用和界面；`tools/live_cli`（工具的问题报给 E07.1）；版本号、`assets/version.json`、`assets/releases.json`；签名配置；3.x 的设置键名和含义；已有样本的 `expected.json`（3.x 冻结输出）。
- 不把任何 Cookie、账号、设备号、客户端地址写进仓库（门禁 `fixture privacy` 必须通过）。

## 方案和阶段

| 阶段 | 做什么 | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 写巡检清单 | 五个平台各列（E07.1 的 P1～P13）：推荐第 1、2 页；分类；一个热门分区第 1、2 页；搜索房间和主播（关键词“英雄联盟”“王者荣耀”；虎牙、抖音只搜直播中，抖音不搜主播）；详情：推荐里取 3 个在播房间，加固定的未开播房间、不存在的房间、平台特有的情况（哔哩哔哩短号 6、一个轮播房间；斗鱼靓号 1 和别名 `lpl`/`LPL`、轮播 93976；虎牙字母别名 `lpl`、一个回放房间；抖音用 `web_rid` 进房、一个游戏直播间；快手大小写不同的 `kpl704668133`）；每个在播房间的清晰度和每条线路开头 64 KB（FLV 头、TS 同步字节 0x47、fMP4 `ftyp`、m3u8 `#EXTM3U`）；租期；链接（各平台一个房间链接、一个要请求的链接：`b23.tv`、斗鱼和虎牙的别名页、`v.douyin.com`）；两个房间各 60 秒弹幕（就绪时间、聊天条数、人数次数、有没有重连）。每行写判定标准 | `docs/E-直播平台/E07-平台巡检/CHECKS.md` | 五行齐全、每项有判定标准；维护者看过 |
| 2 逐个平台跑一遍 | 有工具：`dart run tools/live_cli/bin/live_cli.dart patrol bilibili douyu huya douyin kuaishou --danmaku 60 --out docs/E-直播平台/E01-国内五大平台/E01.6-国内五大平台巡检和修复/runs/<日期>.md`。没有工具：在 scratchpad 写临时 Dart 程序（`dart run`，依赖本仓库的 `live_core`、`live_net`、`live_danmaku`），检查项和判定照 `CHECKS.md`。匿名、只读、直连、不发言；快手请求间隔 2.5 秒；每个平台联网合计不超过 10 分钟 | `record.md`（本轮一节）、`runs/` | 五张结果表写完；失效项列出根因线索（文件:行） |
| 3 修复失效的 | 每个失效项：录样本并脱敏 → 写改之前会失败的测试 → 改适配器 → 跑本平台测试 → 重跑这一项真实接口；一个平台一个提交 | 对应平台的 `sites/<平台>/`、测试、样本 | 失效项都修好或写明原因开到别的任务；门禁通过 |

每个阶段都能单独合并：阶段 1、2 只有文档；阶段 3 每个平台的修复各自合并。没有失效时阶段 3 写“本轮无失效”即完成。

## 测试

- 修 bug：先写改之前会失败的测试，用新录的样本（`Fixture.load('<平台>', 'S<nn>-<情况>')`，`packages/live_core/test/sites/fixture.dart`）；用例名写失效现象，例如 `'area page: getRoomList answers 30 rooms for guests'`。
- 平台回答变了导致旧样本的期望不再成立时：旧样本和它的测试保留（它记录的是当时的回答），新样本单独测。
- 测试里的定时器至少 1 秒；不访问真实平台（D-017）；用到样本时间的把“现在”固定成录制时间。
- 每个修复的平台跑：`cd packages/live_core && dart test test/sites/<平台>_api_test.dart test/sites/<平台>_site_test.dart`；改了弹幕的再跑 `packages/live_danmaku/test/sites/<平台>_test.dart`。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 装合并后的测试包，热门 → 每个修过的平台进一个直播间 | 几秒内出画面和声音，标题、人数、开播时长正确 |
| 2. 修过分区或搜索的平台：分区 → 一个分区往下翻两页；搜索“英雄联盟” | 列表正常，不重复，不报错 |
| 3. 修过链接的平台：把一个房间链接（含短链）粘进搜索框提交 | 直接进房 |
| 4. 修过弹幕凭据的平台：停留 1 分钟 | 弹幕列表和画面都有弹幕，没有反复重连 |

## 风险和注意

- 真实接口受时段影响（凌晨在播房间少、聊天少），结果表写明时间；拿不到在播房间的项写“没测到”，不算正常。
- 别连续高频请求：哔哩哔哩游客容易触发 -352，遇到就停这个平台、换时间再跑，不重试刷接口。
- 修复不能改变用户已存的数据：清晰度 id、房间身份（`SiteIds.caseInsensitiveRoomIds`，`packages/live_core/lib/src/sites.dart:223`）、关注分组的规则不变。
- 和 [E07.1](../../E07-平台巡检/E07.1-平台巡检工具/brief.md) 同时做时，`CHECKS.md` 的格式以 E07.1 为准；同一平台的适配器同时只给一个执行者改（D01.x 的弹幕任务也会碰 `live_danmaku/lib/src/sites/<平台>.dart`；E06.2 不改这五个平台的适配器）。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 分支 `ai/E01.6` 或本机工作区；提交信息以 `[E01.6]` 开头（英文）；不推 master。
- 提交前：改过的包跑 `dart format --output=none --set-exit-if-changed .`、`dart analyze`、`dart test`；`python3 tools/gate/check_fixtures.py`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”（哪个平台跑完、哪些失效项修了）、更新登记表的 `done`、`next`、`branch`。一轮做完后 `done` 回到 0、`next` 写下一轮的日期（持续任务）。

## 报告（中文，简洁）

每个平台：正常几项、失败几项、修好几项；每个失效的根因（文件:行）；新样本；测试数量；改了哪些文件；要在真机上看的；没修的和去向；下一轮建议的时间。
