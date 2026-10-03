# Z05.2 英文界面下平台层给的文字还是中文：任务书

## 背景

- 来源：已批准升级 20-10（CHZZK 回看公告）、25-7（PandaTV 公告）、25-8（PandaTV 分类名）、26-6（FC2 分区名）、29-6（酷狗公告）、30-10（百度公告）的余项“英文界面仍显示平台层给的中文”；V03.3（2026-10-03）开了本任务。核对时发现 3.x 的平台适配器在 22 个文件里用了 96 个翻译键，v4 的翻译文件里只剩 15 个，其余都成了 `live_core` 里的中文常量。
- 现象：设置 → 语言选 English，进一个 CHZZK 正在回看的直播间，详情里的公告是“这场直播在 CHZZK 网页上可以回看，本应用只播放实时画面。”；PandaTV 的分区卡片写“个人直播”“聊天”；FC2 的分区是中文。
- 为什么现在做：第三档；英文界面的用户少，但 3.x 是跟界面语言的（功能基线），D-005 要求用户看得到的文字 zh、en 都有。
- 已经做过的：各平台任务把开发说明式的公告改成了用户看得懂的中文（E06.1 第 6 条）；目录说明已有 `LiveDirectoryNotice` 键机制（I02.1、I03.1）。

## 目标和验收

1. `record.md` 有一张清单：`packages/*/lib` 里每个带中文的字符串常量，分类 A（说明文字）、B（我们翻译的分区名、画质名）、C（弹幕系统提示）、D（不改，写原因），A、B、C 每条写对应的翻译键（3.x 有的用 3.x 的键名）。
2. 英文界面下 A、B、C 类文字显示英文；中文界面显示和现在一字不差。
3. 关注、备份、录制任务里存下的文字和画质名不变（不迁移数据）。
4. 新加的键 zh.json、en.json 都有，按键名排序、4 空格缩进；一致性测试保证 zh 的值等于 `live_core` 的常量。
5. 测试和门禁通过。

## 现状（读代码得出，写文件:行）

- 分层：`docs/specs/ENGINEERING.md` 第 4 节：`live_core` 不依赖应用和翻译。
- 已有的键机制：`packages/live_core/lib/src/live_site.dart:412-415` 的 `LiveDirectoryNotice.directoryNoticeKey`；应用 `apps/pure_live/lib/features/popular/popular_grid.dart:17`（`i18nExists(key) ? i18n(key) : i18n(directoryNoticeKey)`）、`features/area_rooms/area_rooms_page.dart:96`（`i18nOr`）。翻译函数：`apps/pure_live/lib/i18n/i18n.dart:156` 的 `i18n`、`:159` 的 `i18nOr`、`:163` 的 `i18nExists`。
- 说明常量（举例，第 1 阶段列全）：`packages/live_core/lib/src/sites/chzzk/chzzk_api.dart:252`（`adultNotice`）、`:256`（`regionNotice`）、`:260`（`timeMachineNotice`）；`pandalive/pandalive_api.dart:198`、`:201`、`:204`、`:208`、`:212`（5 条公告，注释里写了 3.x 的键 `pandalive_chat_notice` 等）、`:218` 的 `areaNames`；`fc2live/fc2live_api.dart:287` 的 `areaNames`、`:298` 的 `noticeText`、`:435` 的 `areaName`；`kugoulive/kugoulive_api.dart:174`、`:180`；`baidulive/baidulive_api.dart:401`、`:409`；另有 TikTok、Bigo、LOOK、京东、Steam、微博、小红书、LiveMe、YouTube、Kick、17LIVE 的 `chatNotice`、`restrictedNotice` 等（`grep -n "static const String .*Notice" packages/live_core/lib/src/sites/*/*.dart`）。
- 弹幕系统提示：`packages/live_danmaku/lib/src/sites/missevan.dart:128` 起的 `pkLines`；`kick.dart:119`、`bilibili.dart:505`、`:509`、`seventeenlive.dart:319`、`:322` 等。
- 显示的地方：`apps/pure_live/lib/features/live_play/layout/room_details.dart:158`（`room.notice`）；`features/live_play/danmaku/chat_list.dart:948`（没有弹幕时显示公告或简介）；分区名在卡片、分区页、直播间信息条（`room.area`）。
- 扫描：`packages/*/lib`（不含注释）带中文的字面量 423 个、73 个文件，最多的是 `live_core/lib/src/quality_label.dart`（37，画质标准名，多数属 D 类）。

## 3.x 基线

- `git show v3.2.11:lib/core/site/chzzk/chzzk_site.dart:244-246`：`detail.notice = i18n('chzzk_adult_notice')` / `i18n('chzzk_time_machine_notice')`。
- `git show v3.2.11:lib/core/site/pandalive/pandalive_site.dart:83-86`、`:111-114`；`lib/core/site/fc2live/fc2_site.dart:78-83`（分区名 `fc2live_category_*`）、`:134-137`（公告）、`:248`（画质名 `fc2live_quality_auto`）。
- 全部键：`grep -rhoE "i18n\('[a-z0-9_]+'" lib/core/site`（在 `git archive v3.2.11 lib` 解出的目录里跑），96 个；英文在 `git show v3.2.11:assets/translations/en.json`（例如 `:1853` 的 `chzzk_time_machine_notice`）。3.x 的英文多是开发说明（“Live HLS is active…”），要按升级表“说明文字”原则改成用户看得懂的。
- 要保留的：文字跟界面语言（3.x 行为）；存下的数据不受语言影响。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节、第 8 节、第 14 节）。
2. `docs/specs/ENGINEERING.md`（第 4 节分层）；`docs/DECISIONS.md` 的 D-005、D-018。
3. 本文件夹的 `README.md`；`docs/specs/UPGRADES.md` 的统一原则“说明文字”和 20-10、25-7、25-8、26-6、29-6、30-10；`docs/Z-工程文档和维护/Z05-多语言/README.md`。

## 范围

- 可以改：`packages/live_core/lib/src/sites/*/`（只给常量加对应的键名常量或导出表，不改常量的中文值和解析逻辑）；`packages/live_danmaku/lib/src/sites/`（同上）；`apps/pure_live/lib/shared/rooms/`（新建 `platform_texts.dart`：常量 → 键的表和显示函数）；显示公告、分区名、画质名、弹幕系统提示的界面代码（只改取文字的那一处）；`apps/pure_live/assets/translations/zh.json`、`en.json`；对应测试。
- 不能改：`LiveRoom` 存下的字段和 JSON 格式；画质偏好和录制任务的画质名（J02.1 的对照）；平台原文（标题、主播名、国内平台的分区名）；版本号、`assets/version.json`、`assets/releases.json`；签名配置；3.x 的设置键名和含义。

## 方案和阶段

| 阶段 | 做什么（对应 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | c1：列清单、分类、对照 3.x 键；定做法（README c2 建议 A） | `record.md` | 验收 1；清单里 A、B、C 类每条有键名 |
| 2 | c3：A 类说明文字按界面语言 | `live_core`（键名）、`platform_texts.dart`、`room_details.dart`、`chat_list.dart`、翻译文件、测试 | 英文界面公告是英文；一致性测试通过 |
| 3 | c4：B、C 类（分区名、画质名、弹幕系统提示） | 同上，加分区、画质、弹幕显示处 | 验收 2～5 |

## 测试

- 改之前会失败：英文界面下用 `fixtures/chzzk/S06-live-detail-adult`（成人直播，公告是 `ChzzkApi.adultNotice`）和 `S06-live-detail-region`（地区限制，`regionNotice`）进直播间，详情公告是英文（现在是中文常量）。样本里没有回看中的直播，`timeMachineNotice` 只在一致性测试里覆盖。
- 一致性测试：遍历常量 → 键的表，断言每个键在 zh.json、en.json 都存在，zh 的值等于常量。
- 中文界面的已有界面测试照旧通过（文字一字不差）。
- 测试不访问真实平台，定时器至少 1 秒。改过的包跑 `dart format --output=none --set-exit-if-changed .`、`dart analyze`、`dart test`；`apps/pure_live` 跑全部 `flutter test`；`python3 tools/gate/check_ui_structure.py`（检查翻译键排序和硬编码文字）。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 设置 → 语言 → English；开着代理进 CHZZK、PandaTV、FC2 的直播间，看详情 | 公告、说明是英文 |
| 2. 分区页看 PandaTV、FC2、niconico 的分区 | 我们翻译的分区名是英文；国内平台（哔哩哔哩、斗鱼）的分区名照旧中文 |
| 3. 进猫耳 FM 一个在 PK 的直播间 | 弹幕区的 PK 提示是英文 |
| 4. 切回简体中文 | 全部恢复中文，和改之前一字不差 |
| 5. 英文界面下关注一个 PandaTV 直播间，切回中文看关注页 | 卡片上的分区名是中文（存下的数据不带语言） |

## 风险和注意

- 改了 `live_core` 常量的中文却忘了改 zh.json：一致性测试防住。
- 画质名同时用于偏好匹配（按名字）和显示：只在显示时换，匹配仍用中文标准名。
- 可能冲突的文件：`zh.json`、`en.json`（几乎所有界面任务都会改，合并时两边都保留、重新排序）；`room_details.dart`（A07 的界面任务）。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 分支 `ai/Z05.2` 或本机工作区；提交信息以 `[Z05.2]` 开头（英文）；不推 master。
- 提交前：改过的包跑 format、analyze、测试；`apps/pure_live` 跑全部 `flutter test`；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”（清单做到哪个平台、哪一类）、更新登记表的 `done`、`next`、`branch`。

## 报告（中文，简洁）

清单的数量（A、B、C、D 各多少）；做法；每个阶段做到没有；新加的翻译键数量；测试数量；改了哪些文件；要在真机上看的；需要维护者决定的（例如 3.x 的某些英文要不要沿用）。
