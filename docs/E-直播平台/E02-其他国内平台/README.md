# E02 其他国内平台

国内五大平台以外的 13 个国内平台的适配器：YY、网易 CC、AcFun、猫耳 FM、映客、克拉克拉、小红书、微博、京东、酷狗、百度、六间房、LOOK。都不需要代理；能力差别很大（有的只能按房间号查、有的没有分区、有的不给弹幕），这里按平台各自能做到的给全。

## 范围

- 包括：`packages/live_core/lib/src/sites/{yy,cc,acfun,missevan,inke,kilakila,xiaohongshu,weibo,jdlive,kugoulive,baidulive,sixroom,looklive}/` 的全部代码（推荐、分类和分区、搜索、详情、清晰度和线路、链接），它们在 `apps/pure_live/lib/app/platforms.dart` 的构造（CC `:151`、YY `:160`、AcFun `:161`、猫耳 `:164`、映客 `:165`、克拉克拉 `:166`、小红书 `:167`、微博 `:169`、京东 `:180`、酷狗 `:181`、百度 `:182`、六间房 `:183`、LOOK `:184`），样本 `fixtures/<平台>/` 和测试。
- 不包括（归哪里）：
  - 弹幕协议 → [D01](../../D-弹幕/D01-平台弹幕协议/README.md)：YY D01.7、AcFun D01.10、猫耳 D01.13、克拉克拉 D01.14、京东 D01.25、酷狗 D01.26、百度 D01.27、六间房 D01.28、LOOK D01.29。网易 CC、映客、小红书、微博没有弹幕（CC 匿名加入不回应、C-22 未排；映客匿名拿不到连接地址；小红书评论要签名；微博匿名没有实时评论通道），应用不登记（`platforms.dart:190-195`），直播间照 3.x 提示一次“未接入”。
  - YY 的 FLV 优先在应用里打开 → [E06.3](../E06-平台层升级/E06.3-YY优先用FLV/README.md)；酷狗 PK“对方”标记 → [E06.2](../E06-平台层升级/E06.2-平台层新数据接到界面/README.md)；京东直播间模糊背景（28-3）→ A07.16。
  - 模型和框架 → [E05](../E05-平台框架和模型/README.md)；链接公共部分 → [E04](../E04-链接解析和分享口令/README.md)；巡检 → [E07](../E07-平台巡检/README.md)。

## 现状：做到哪、怎么工作的

- 用户看得到的（[FEATURES.md](../../inventory/FEATURES.md) 第 14 节）：

| 平台 | 播放 | 弹幕 | 搜索（`search_capability.dart`） | 分区 | 关注 | 特有的 |
|---|---|---|---|---|---|---|
| YY | 完成，K90 看过 | 完成 | 只搜直播中、主播 | 完成 | 完成 | 移动 HLS 在前，FLV 优先没打开（E06.3） |
| 网易 CC | 完成，K90 看过 | 无（C-22 未排） | 直播和未开播、主播 | 完成 | 完成 | Cookie 只存不用 |
| AcFun | 完成 | 新增 | 直播和未开播、主播 | 完成 | 完成 | 开播时间（10-3） |
| 猫耳 FM | 完成 | 新增 | 直播和未开播 | 完成 | 完成 | 音频直播；默认灰猫图当作没有封面 |
| 映客 | 完成 | 无 | 推荐里筛选 | 完成 | 完成 | “原画”只有 HEVC 线路（见已知问题） |
| 克拉克拉 | 完成 | 新增 | 直播和未开播 | 完成 | 完成 | 加密分享链接 |
| 小红书 | 完成 | 无 | 只能按房间号查 | 无（3.x 同） | 只能按场次 | 按主播关注受阻（16-5） |
| 微博 | 完成 | 无 | 只能按房间号查 | 完成 | 只能按场次 | `t.cn` 短链（18-9）；按主播关注受阻（18-10） |
| 京东 | 完成 | 新增 | 直播和未开播 | 完成 | 完成 | 标题和店铺名受阻（28-7） |
| 酷狗 | 完成 | 新增 | 直播和未开播 | 完成 | 完成 | PK 对方聊天（B-16，界面 E06.2） |
| 百度 | 完成 | 新增 | 只能按房间号查 | 完成 | 完成 | 预告房间显示未开播（A-6） |
| 六间房 | 完成 | 新增 | 直播和未开播 | 完成 | 完成 | 目录改用移动端列表（31-4） |
| LOOK | 完成 | 新增 | 按房间号查，另在推荐第 1 页按名字筛选（见已知问题） | 完成 | 完成 | |

- 内部怎么工作：和 E01 一样分 `*_api.dart`（纯解析）和 `*_site.dart`（请求编排、会话、链接）两层；几个平台用“看到过的卡片”补详情回答里没有的名字、封面（六间房 `sixroom_api.dart:157`、百度 `baidulive_api.dart:255`、LOOK `looklive_api.dart:249`、京东 `jdlive_api.dart:126`），占位名字（“JD Live”“Baidu Live”）一律留空（UPGRADES X-2）。
- 完成度（和 3.x 对照）：3.x 的功能都在，行为以 3.x 冻结输出为准（这 13 个平台的 `expected.json` 由各平台目录的 `legacy_expected.dart` 生成，见 `fixtures/README.md`“自己补的期望值”）；UPGRADES 第 6、9、10、13～16、18、28～32 节的条目在 2026-09-29 落地；弹幕：3.x 只有 YY 有，D01 给 AcFun、猫耳、克拉克拉、京东、酷狗、百度、六间房、LOOK 新增了 8 个。

## 代码地图

| 平台 | 代码（`packages/live_core/lib/src/sites/`，两个文件合计行数） | 测试 `*_api_test.dart` / `*_site_test.dart`（`test(` 写法） | 接口样本 `fixtures/<平台>/S*` | 任务 |
|---|---|---|---|---|
| YY | `yy/`（1485） | 38 / 39 | 34 | [E02.1](E02.1-YY直播/README.md) |
| 网易 CC | `cc/`（1344） | 39 / 33 | 33 | [E02.2](E02.2-网易CC/README.md) |
| AcFun | `acfun/`（1335） | 40 / 51 | 13 | [E02.3](E02.3-AcFun直播/README.md) |
| 猫耳 FM | `missevan/`（927） | 38 / 27 | 14 | [E02.4](E02.4-猫耳FM/README.md) |
| 映客 | `inke/`（1209） | 48 / 38 | 14 | [E02.5](E02.5-映客/README.md) |
| 克拉克拉 | `kilakila/`（1514） | 56 / 38 | 17 | [E02.6](E02.6-克拉克拉/README.md) |
| 小红书 | `xiaohongshu/`（931） | 45 / 46 | 4 | [E02.7](E02.7-小红书/README.md) |
| 微博 | `weibo/`（1012） | 44 / 41 | 12 | [E02.8](E02.8-微博直播/README.md) |
| 京东 | `jdlive/`（1229） | 29 / 30 | 15 | [E02.9](E02.9-京东直播/README.md) |
| 酷狗 | `kugoulive/`（1324） | 44 / 37 | 14 | [E02.10](E02.10-酷狗直播/README.md) |
| 百度 | `baidulive/`（1749） | 46 / 41 | 12 | [E02.11](E02.11-百度直播/README.md) |
| 六间房 | `sixroom/`（1555） | 24 / 30 | 26 | [E02.12](E02.12-六间房/README.md) |
| LOOK | `looklive/`（1398） | 37 / 27 | 9 | [E02.13](E02.13-LOOK直播/README.md) |

应用里和这些平台有关的：`apps/pure_live/lib/features/search/search_capability.dart:75-141`（每个平台的搜索能力和说明键）、`apps/pure_live/lib/shared/rooms/play_quality.dart:7`（按名字选默认画质）、`apps/pure_live/lib/shared/rooms/room_feed.dart:475-487`（列表翻页和去重）。

## 3.x 基线

- `git show v3.2.11:lib/core/site/<平台>/`（合计行数）：`yy/`（792）、`cc/`（542）、`acfun/`（793）、`missevan/`（534）、`inke/`（518）、`kilakila/`（913）、`xiaohongshu/`（642）、`weibo/`（631）、`jdlive/`（727）、`kugoulive/`（913）、`baidulive/`（995）、`sixroom/`（910）、`looklive/`（730）。3.x 已经不能构建，期望值由各平台的 `fixtures/<平台>/legacy_expected.dart` 把 3.x 解析代码搬出来生成。
- 3.x 里除 YY 外都是 `EmptyDanmaku`；YY 的 stream-manager 请求一直是坏的，用户实际看的是移动 HLS。
- 必须保留：清晰度名称和 id、房间身份、分区 id、3.x 的设置键名（D-018）。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| YY FLV 优先没打开 | `apps/pure_live/lib/app/platforms.dart:160` | 延迟高、少“蓝光” | [E06.3](../E06-平台层升级/E06.3-YY优先用FLV/README.md) |
| 映客默认会播 HEVC：默认画质按名字选（偏好默认“原画”），映客的“原画”只有 HEVC 线路，“优先 H.264”只在同一档里把 HEVC 排后 | `apps/pure_live/lib/shared/rooms/play_quality.dart:7`；映客画质在 `inke_api.dart` | 硬解不好的手机上可能卡；E02.5 记录给 G 组的提醒没落实 | 写进本组报告：建议在 G 组开任务（和 G01.2 的默认编码一起定）；百度在偏好靠后档时有同类风险 |
| 克拉克拉列表提前到底：适配器去重后一页全是重复时返回空页（仍说有下一页），列表把空页当到底 | `apps/pure_live/lib/shared/rooms/room_feed.dart:483`（`chunk.rooms.isNotEmpty`）；`kilakila_site.dart` | 热门第 3 页全重复时第 4 页的新主播看不到 | 写进本组报告：没有任务管，建议 I 组开任务 |
| LOOK 的搜索能力写成“只能按房间号查”，实际还会在推荐第 1 页按名字、标题筛选 | `search_capability.dart:139`（`roomLookup`）；`looklive_site.dart:225-241` | 搜索页的说明比实际少 | 写进本组报告：应改成 `showcaseSnapshot`（I05 的搜索任务） |
| 微博搜索说明（`search_scope_weibo`）仍写“开播状态进入后确认”，没提 `t.cn` 短链 | 翻译 `assets/translations/zh.json` | 说明不完整 | 写进本组报告；Z05 文字整理 |
| 3.x 存下的占位值（京东“JD Live”、酷狗旧标题和“Kugou Live”、百度“Baidu Live”）迁移时没清 | `packages/live_store/lib/src/legacy/` | 老用户的关注卡上还显示占位名，直到刷新带回真名 | 写进本组报告：J06.1 / J02.1 |
| 小红书、微博只能按场次关注（16-5、18-10 受阻：要登录或网页签名） | `xiaohongshu_site.dart`、`weibo_site.dart` | 主播下次开播关注对不上 | 受阻，不做 |
| 京东标题和店铺名（28-7 受阻：详情接口要 h5st 签名） | `jdlive_api.dart:36-41` | 从链接进房没有标题 | 受阻 |
| 网易 CC 弹幕（C-22）、YY 礼物（C-20）、YY 真实在线数（C-18） | 弹幕层 | — | 未排（C-22 要登录 Cookie） |
| 平台层给的中文（公告、画质名、分区名）在英文界面仍是中文（29-6、30-10 等） | 各 `*_api.dart` | 英文界面混中文 | [Z05.2](../../Z-工程文档和维护/Z05-多语言/Z05.2-英文界面里平台给的中文/README.md) |

## 相关决定和规范

- D-001、D-017、D-018；[specs/UPGRADES.md](../../specs/UPGRADES.md) 第 6、9、10、13～16、18、28～32 节和 X-2（占位值）、A-6（未开播显示）。

## 测试和验证

- 自动测试：`cd packages/live_core && dart test test/sites/<平台>_api_test.dart test/sites/<平台>_site_test.dart`（13 个平台 26 个文件）；样本逐键对照 3.x 冻结输出。
- 真实接口：各平台 record.md 的“真实环境检查”（2026-09-28～10-01）；以后由 [E07.1](../E07-平台巡检/E07.1-平台巡检工具/README.md) 的工具定期跑。
- 真机：只有 YY、网易 CC 的播放在 K90 上看过（2026-10-01）；[S02 的 CHECKLIST.md](../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 1 节第 1 条把 YY、CC 列进“各进一个直播间”，其余 11 个平台没有真机条目。

## 路线

1. [E06.3](../E06-平台层升级/E06.3-YY优先用FLV/README.md)：YY FLV 优先（第二档，小）。
2. [E07.1](../E07-平台巡检/E07.1-平台巡检工具/README.md)：工具做好后这 13 个平台一起巡检，失效的在这里开修复任务（标题写“接 E07.1”）。
3. 上面“已知问题”里写进报告的几条（映客默认 HEVC、克拉克拉列表到底、LOOK 搜索说明、占位值迁移）由维护者决定开到 G、I、J 组。新想法写进 V01 提议，不直接加任务。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [E 直播平台](../README.md)。

- 代码：`packages/live_core/lib/src/sites/`
- 进度：`████████████████████` 100%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| E02.1 | YY 直播 | 平台 | 完成 | 2026-09-28 | df90a0156 | [设计或说明](E02.1-YY直播/README.md)、[记录](E02.1-YY直播/record.md) |
| E02.2 | 网易 CC | 平台 | 完成 | 2026-09-28 | 480454577 | [设计或说明](E02.2-网易CC/README.md)、[记录](E02.2-网易CC/record.md) |
| E02.3 | AcFun 直播 | 平台 | 完成 | 2026-09-28 | fc70af736 | [设计或说明](E02.3-AcFun直播/README.md)、[记录](E02.3-AcFun直播/record.md) |
| E02.4 | 猫耳 FM | 平台 | 完成 | 2026-09-28 | 8674cb62f | [设计或说明](E02.4-猫耳FM/README.md)、[记录](E02.4-猫耳FM/record.md) |
| E02.5 | 映客 | 平台 | 完成 | 2026-09-28 | 656194b3f | [设计或说明](E02.5-映客/README.md)、[记录](E02.5-映客/record.md) |
| E02.6 | 克拉克拉 | 平台 | 完成 | 2026-09-28 | c50732382 | [设计或说明](E02.6-克拉克拉/README.md)、[记录](E02.6-克拉克拉/record.md) |
| E02.7 | 小红书 | 平台 | 完成 | 2026-09-28 | 3982eaa0e | [设计或说明](E02.7-小红书/README.md)、[记录](E02.7-小红书/record.md) |
| E02.8 | 微博直播 | 平台 | 完成 | 2026-09-28 | d104f69e9 | [设计或说明](E02.8-微博直播/README.md)、[记录](E02.8-微博直播/record.md) |
| E02.9 | 京东直播 | 平台 | 完成 | 2026-09-28 | 9d36d0852 | [设计或说明](E02.9-京东直播/README.md)、[记录](E02.9-京东直播/record.md) |
| E02.10 | 酷狗直播 | 平台 | 完成 | 2026-09-28 | f80083fe2 | [设计或说明](E02.10-酷狗直播/README.md)、[记录](E02.10-酷狗直播/record.md) |
| E02.11 | 百度直播 | 平台 | 完成 | 2026-09-28 | 4971f23cc | [设计或说明](E02.11-百度直播/README.md)、[记录](E02.11-百度直播/record.md) |
| E02.12 | 六间房 | 平台 | 完成 | 2026-09-28 | 98c644829 | [设计或说明](E02.12-六间房/README.md)、[记录](E02.12-六间房/record.md) |
| E02.13 | LOOK 直播 | 平台 | 完成 | 2026-09-28 | 7761b780a | [设计或说明](E02.13-LOOK直播/README.md)、[记录](E02.13-LOOK直播/record.md) |

<!-- docs:生成结束 -->
