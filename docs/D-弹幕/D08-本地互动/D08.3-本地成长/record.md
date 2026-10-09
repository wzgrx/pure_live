# D08.3 本地成长：记录

- 日期：2026-10-09
- 执行者：Claude（本机工作区，没有推送、没有合并）
- 分支和提交：工作区分支 `worktree-agent-ad660eeba49f36244`，提交 `[D08.3] …`（阶段 1 规则和计时、阶段 2 身份卡和设置页、文档）；起点 master `b190e75ed`（含 A08.10～A08.15、D08.1、D08.2）
- 任务书：[brief.md](brief.md)；设计和每条选择的理由：[README.md](README.md)“方案”c1～c5、“定稿的选择”g1～g15（维护者按 D-003 定）；来源：V03.6 第 2.2 节 P5、第 4 节 E7、第 5.4 节

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| 1 新开关“本地成长”（`localInteraction.growthEnabled`，默认开）；关掉时和 3.x 一样 | 做了 | 关掉时送礼照旧加经验，不提示升级、不记 `level`（g11） |
| 2 播放中每满 10 分钟 +10 经验 +20 币（每天最多 300 经验）；每天第一次进直播间 +20 +100；发本地弹幕 +1（每天 50） | 做了 | 看直播到 300 经验以后币也不再给（g6）；应用内小窗在播也计（g1） |
| 3 公式不变；身份卡进度条和“还差 N 经验到 Lv.M”；每 10 级一个段名 | 做了 | 段名 10 个，Lv.90 以后一直是“至尊”（g12）；设置页也有同一条进度（g14） |
| 4 升级短提示“升到 Lv.N”、记录里一条 `level` | 做了 | 提示写成“本地等级升到 Lv.N”（直播间里一眼看出是本地的）；记录里照 D08.1 的写法“升到 Lv.N”；一次涨几级只记一条（g10） |
| 5 “+500/+2000/+10000”在身份卡的“更多”里 | 做了 | 写成“+500 电池”这样带直播间币名；设置页的那一排按钮不动（g13、g14） |
| 6 后台不计；离开直播间结算；跨日清零 | 做了 | 结算 = 播放器停下或释放时写盘（g1、g3）；“清零”是读的时候按日期判断，不用零点跑任何东西（g5） |
| 7 规则数字是 `LocalCatalog` 的常量，有单元测试 | 做了 | — |

## 根因

- 新功能。3.x（`v3.2.11:lib/modules/live_play/widgets/local_interaction/local_interaction_controller.dart:832-836`、`:876-884`）和 4.x 现在（`logic/local_interaction.dart` 的 `sendGift`、`recharge`）经验只来自送礼、币只来自按钮，等级只有 `Lv.N`：P5 说的“没有养成感”。

## 存储和迁移

- 新设置 `localInteraction.growthEnabled`（`BoolSetting`，默认 `true`）和 `localInteraction.growthDay`（`StringSetting`，默认 `''`），都在 `localInteraction` 一节、`SettingScope.synced`：完整备份的 `localInteraction` 一节里有，设备同步属于“设置”一类，和币、经验一起走；3.x 读备份时不认识，忽略。D-018：没有改任何 3.x 的键。
- `growthDay` 是 JSON：`{"day":"2026-10-09","watchedMs":1500000,"watchExp":20,"checkedIn":true,"chatExp":3}`（`LocalGrowthDay`）。不是今天的读成“今天什么都没得”，坏的读成没有；没有迁移要做（老用户第一次进直播间就是今天的第一次签到）。
- 升级记进 D08.1 的 `local_events`（`kind = level`，`count` = 升到的等级，带直播间），表结构不变。
- 写盘：签到、每条弹幕的 +1、每满 10 分钟各一次（和币、经验同一次 `setAll`）；看直播的零头只在停下时写（暂停、退到后台、播放器停下或释放、关掉开关、换了一天）。一小时最多 6 次。

## 改了哪些文件

- `apps/pure_live/lib/features/live_play/local_interaction/logic/local_catalog.dart`：规则常量、`levelStep`、`progressFor`（`LocalLevelProgress`）、`tierKeys`、`tierKeyFor`。
- `apps/pure_live/lib/features/live_play/local_interaction/logic/local_growth.dart`（新）：`LocalGrowthDay`、`LocalWatchTime`、`LocalTimerFactory`。
- `apps/pure_live/lib/features/live_play/local_interaction/logic/local_interaction.dart`：`growthEnabled`、`growing`、`now`、`today`、`checkIn`、`watched`、`settleWatch`、`rewardChat`、`_grow`、`_recordLevel`（送礼也记）、`levelLabel`、`nextLevelLabel`、`growthTodayLine`。
- `apps/pure_live/lib/features/live_play/local_interaction/logic/local_room_session.dart`：进房签到、发弹幕 +1、升级提示（`announceLocalLevel`）、`LocalRoomWatch`（每个 `PlaybackSession` 一个，`Expando` 找回）。
- `apps/pure_live/lib/features/live_play/local_interaction/local_interaction_panel.dart`：身份卡的“更多”（`AppMenuButton`）和 `LocalLevelBar`；面板去掉单独的加币一行。
- `apps/pure_live/lib/features/live_play/local_interaction/local_interaction_settings_page.dart`：进度和开关。
- `packages/live_store/lib/src/settings/settings.dart`：两个新设置，加进 `Settings.all`。
- `packages/live_ui/lib/src/icons/app_icons.dart`：`localGrowth`（`trending_up_rounded`）。
- 翻译（zh、en，按键名排序）18 个：`local_growth`、`local_growth_desc`、`local_growth_checked_in`、`local_growth_not_checked_in`、`local_growth_watch`、`local_growth_chat`、`local_level_next`、`local_level_up`、`local_level_tier_0`～`local_level_tier_9`。没有删键（D-024）。
- 测试：新 `apps/pure_live/test/features/live_play/local_growth_test.dart`、`packages/live_store/test/local_growth_test.dart`；改 `local_interaction_test.dart`（进房签到后是 1100 电池；加币在“更多”里）、`local_interaction_support.dart`（可以换一个带假时钟的 `LocalInteraction`）、`test/shared/sync_parts_test.dart`、`packages/live_store/test/settings_defaults_test.dart`（`newInV4`）、`packages/live_ui/test/design_system_test.dart`（图标对照）、`test/i18n_runtime_keys.dart`（`local_experience_coins` 留着不用，D-024）。
- 文档：本文件夹 README（g1～g15、实现）、本记录；D08 子分类 README（代码地图、已知问题、测试）；A08.2 README“实现和验证”补一条；`tools/docs/settings_audit_notes.py` 和生成的 J01.2 `settings.md`；`docs/tasks.toml`。
- 没改：`room_controller.dart`、`live_play_page.dart`（播放器从 `room.session` 拿到）、`super_chats.dart` 和各平台适配器、等级公式、3.x 键的含义、版本号。

## 测试

- `apps/pure_live/test/features/live_play/local_growth_test.dart`（28 个）：
  - 规则 3 个：常量的数字（V03.6 第 5.4 节）、公式照 3.x、按钮还是 500/2000/10000；进度和段名（Lv.1、9、10、19、20、89、90、99、100、500）；段名和“还差 N 经验到 Lv.M”的文字。
  - 当天的计数 2 个：JSON 往返、别的日子读成没有、坏的读成没有；本机日期、23:59:59 和 00:00、年底。
  - 计时 2 个（假时钟、假定时器）：计时才起每分钟一次的定时器、停下交出剩下的并结算、停着不跑；超过 5 分钟的间隔只算 5 分钟、时钟往回调不算。
  - 观看 6 个：9 分钟不给、10 分钟 +10 +20、停下时把零头存下；暂停前后的分钟累加、暂停本身不算；**一小时写 6 次、不是每分钟**（停下再写 1 次）；每天 300 经验到顶；跨零点每天各算各的；比存着的日子还早的时间扔掉、今天照常算。
  - 签到和弹幕 3 个：一天一次、23:59 → 00:00 又能签到；弹幕 +1、每天 50、第二天又有；恢复同一天的备份不会再签到。
  - 等级 1 个：升一级记一条 `level`（带直播间）、大礼物连升三级也只记一条。
  - 直播间 3 个（整个直播间页、假时钟）：进房签到；**播放 10 分钟 +10 +20；暂停不计；画中画（inactive）计；退到后台马上停、马上存、在后台 20 分钟不计；回到前台接着计**；关掉开关停；同一天再签到不给；发弹幕 +1、升到 Lv.2 提示“本地等级升到 Lv.2”并进记录；播放器停下（离开直播间）把零头存下、同一个播放器还是同一个 `LocalRoomWatch`。
  - 界面 6 个：身份卡在竖屏、横屏、竖屏 2 倍字、横屏 2 倍字：“Lv.3 · 新人”“还差 119 经验到 Lv.4”、进度条的值、“今天已签到 · 看直播 +0/300 · 弹幕 +1/50”、都在卡片和面板里、不溢出；“更多”里三个“+N 电池”，点 +2000 只加币、记一条“币”；设置页 1 倍和 2 倍字：进度在“体验币与等级”下面、“今天还没签到”、开关默认开、关掉后“今天……”那一行没了、进度还在。
  - 开关 2 个：默认开；关着时不签到、看直播不计、弹幕不加，送礼照 3.x 加经验、升级不记；关掉时已经看的分钟存下；本地互动关着也什么都不计。
- `packages/live_store/test/local_growth_test.dart`（3 个）：键、默认值、一节、synced；完整备份带开关、计数、币、经验，恢复到另一台；D08.3 以前的备份恢复后开关开着、计数空。`settings_defaults_test.dart`：`newInV4` 加了两个键。
- `test/shared/sync_parts_test.dart` 新增 1 个：本地成长跟“设置”一类走；不勾设置时这台的不变。
- 跑过：`local_growth_test.dart`、`local_interaction_test.dart`、`local_history_test.dart`、`local_phrases_test.dart`、`local_plus_one_test.dart`、`test/features/live_play/`、`test/features/settings/`、`test/shared/`，`packages/live_store` 的设置、备份、成长测试，`packages/live_ui` 的 `design_system_test.dart`。

## 门禁

- 2026-10-09 本机 `bash tools/gate/gate.sh --all`（提交 `e4898cdca`，D08.3 的全部代码提交）：`gate: passed (all, 14 members)`。第一次跑在 `apps/pure_live test` 停下：`i18n_test.dart` 的“每个键都用到”发现 `local_experience_coins`（面板里那一行加币按钮的标题）没人用了；D-024 不删键，加进 `test/i18n_runtime_keys.dart` 的 `keptUnusedKeys`，重跑通过。

## 真机上要看的

K90（`com.mystyle.purelive.v4dev`，每次点按前确认前台是测试包；不碰 3.x 和正式包）：

1. 今天第一次进一个在播的直播间 → 右上角菜单 → 本地互动体验：身份卡比进房前多 100 币、20 经验；下面一行“Lv.N · 新人”“还差 … 经验到 Lv.N+1”、进度条、“今天已签到 · 看直播 +0/300 · 弹幕 +0/50”。退出再进同一个或别的直播间：不再加。
2. 发一条本地弹幕：经验 +1，“弹幕 +1/50”。
3. 前台播放 10 分钟（看着屏幕，别锁屏）：经验 +10、币 +20，“看直播 +10/300”。
4. 暂停 10 分钟：不加。
5. 播放时上滑回桌面进系统画中画，在画中画里播 10 分钟：加一次。
6. 关掉画中画（或关掉“离开应用时自动画中画”）退到后台 10 分钟（开着“后台播放”也一样）：不加；回来接着算。
7. 离开直播间让它进应用内小窗，在首页等页面看 10 分钟：加一次；关掉小窗后不再加。
8. 身份卡右上角 ⋮：三项“+500 电池”“+2000 电池”“+10000 电池”（斗鱼是“鱼翅”这类，按直播间）；点一个只加币；记录“币”里多一条。
9. 把经验加到快升级（送一个大礼物）：提示“本地等级升到 Lv.N”，记录“全部”里一条“升到 Lv.N · 主播名”。
10. 设置 → 本地用户与互动：“体验币与等级”下面同一条进度；开关“本地成长”默认开；关掉：直播间身份卡没有“今天……”那一行，进房、看直播、发弹幕都不加，送礼照旧加经验、不提示升级。
11. 23:55 左右进直播间播到 00:05 以后：第二天的签到在下一分钟加上，“看直播”从 +0 开始。
12. 系统字体调到最大：身份卡和设置页的进度、“还差…”换行、不溢出；横屏面板在右边同样。
13. 设备同步（J05）只勾“设置”从另一台发过来：币、经验、开关、今天的计数跟着来。
14. 耗电：播放 30 分钟，看系统的电池用量里测试包没有比改之前明显多（计时每分钟一次，只写几次盘）。
