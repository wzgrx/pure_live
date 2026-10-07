# D03.2 飞行弹幕里的表情图片

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)（登记为完成，2026-10-02）；当时定的档位“可以以后”、规模中
- 类型：功能
- 来源：S02.1（真机问题修复）第 8 节“留给后续”：聊天列表里表情已经是图片，飞行弹幕仍是文字；功能清点 F-DM-16（见 [inventory/FEATURES.md](../../../inventory/FEATURES.md)）
- 旧编号：F.2c、T06c.2
- 相关：实际和 [D03.1](../D03.1-飞行弹幕渲染/README.md) 的 c1、c8 一起做完（同一个代码提交）；纯文字模式 [D05.1](../../D05-弹幕设置生效/D05.1-弹幕设置生效/README.md) c3；聊天列表的图文混排 [S02.1](../../../S-质量和验证/S02-真机验证/S02.1-真机问题修复/README.md)、C01.2；已批准升级附录 B-12（CHZZK）、B-13（YouTube）的“表情图片放界面任务”；决定 D-029（D06.1 的这一项由本任务做完）
- 记录：没有单独的 `record.md`（原来写的 `records/F.2c.md` 没有建），做法和测试记在 [D03.1 的记录](../D03.1-飞行弹幕渲染/record.md)“逐条对照”c1、c8 和“和设计不一样的地方”第 1 条

## 目标

3.x 用 flame_barrage 的表情图集，飞行弹幕里的表情代码（`[笑哭]`、虎牙的 `/{dx`）画成图片；4.x 换成自己的弹幕层后，表情只在聊天列表里是图片（S02.1），画面上飘过的是代码原文。做完以后：飞行弹幕里平台给的表情（CHZZK、YouTube、哔哩哔哩、快手在消息里带图片地址）和应用自带的五个平台表情表（哔哩哔哩、抖音、斗鱼、虎牙、快手，`apps/pure_live/assets/emo/`）都画成图片，高 1.3 × 字号；纯文字模式时去掉。

## 3.x 和现状

| 方面 | 3.x（`git show v3.2.11:lib/...`，文件:行） | 现在（文件:行） | 要做到 |
|---|---|---|---|
| 表情从哪来 | 进房时 `EmojiManager` 后台预载整套表情图集（`lib/plugins/emoji_manager.dart`；模型 `lib/core/emoji/models/unified_emoji_model.dart:4`） | 应用自带的表 `EmoteLibrary`（`apps/pure_live/lib/shared/danmaku/emotes.dart:56`，五个平台 `:65-71`，第一次显示这个平台的聊天时读）+ 消息自己带的 `LiveMessage.emotes`（平台给的地址）；`chatSegments`（`:122`）把文字切成文字段和表情段，每条消息只解析一次（`:112` 的 `Expando`，A07.11 c7） | 两种来源都认（做到） |
| 画法 | `plugins/flame_barrage/lib/src/layout/rich_parser.dart`、`mixed_layout.dart:175-221`：表情图片夹在文字里 | `DanmakuOverlayState._record`（`apps/pure_live/lib/shared/danmaku/danmaku_overlay.dart:585`）：表情段按 `emoteSize`（`:73`，1.3 × 字号，16～48）画进同一张 Picture，透明度跟弹幕（`emoteAlpha`）；图片由 `_EmoteImages`（`:861`）解码一次（96 像素高，最多留 160 张），包里的图失败再用网络地址 | 和文字一起录成 Picture（做到） |
| 还没加载完 | 预载，基本没有这种情况 | 这条弹幕在队里等图片解码完再进场（`_enter` `:451`，`_images.ready`）；解码失败显示代码原文，和聊天列表一样（`:617-621`） | 见“结果”偏差 |
| 纯文字模式 | `noEmojiMode` 时表情不画，也不显示代码（`mixed_layout.dart:175`、`:201`） | `DanmakuLook.textOnly`（`danmaku_overlay.dart:66`，读 `noEmojiMode`，`shared/danmaku/danmaku_settings.dart:26`）：`_segments`（`:373`）去掉表情段，只剩表情的弹幕不飞 | 照 3.x（做到，D05.1 c3） |

## 结果

- 实际做的：和 D03.1 一起重写弹幕层时做完（D03.1 的 c1“表情图 字号 × 1.3”、c8“纯文字模式对飞行弹幕生效”），没有单独开发。
- 偏差：表情图第一次出现要先解码，这条弹幕先在队里等（最多 5 秒的排队期限照算），解码完再进场；3.x 是进房后台预载整套。
- 提交：代码 `0451ac8c6`（D03.1、D05.1、A08.4 同一个），合并 `1071b4e25`（2026-10-02）。登记表原来写的 `cd42f89b1` 是建立功能清点的文档提交（`docs(features): Android feature inventory, plan, tasks and process`），2026-10-07 已改成 `0451ac8c6`。
- V03.3 核对（2026-10-03）：F-DM-16 由“缺失”改“完成”，依据 D03.2、D05.1 c3 和 S02.2 冒烟。

## 验证

- 自动测试：`apps/pure_live/test/shared/danmaku_overlay_test.dart` 的“c8, F.2a: the font and text-only mode; the emoticons fly as pictures”（`:266`）：带表情代码的弹幕画出图片、纯文字时不画、只剩表情的不飞；表情解析 `apps/pure_live/test/shared/emotes_test.dart`（5 个）、`packages/live_danmaku/test/emotes_test.dart`（5 个，平台给的图片）。
- 真机：[S02.2 冒烟](../../../S-质量和验证/S02-真机验证/S02.2-K90冒烟/record.md)（2026-10-02，构建 `288fec0ec`）“进直播间：画面、飞行弹幕带表情图……”通过。CHECKLIST 第 2 节第 7 条（快手、哔哩哔哩带表情的弹幕）还没填；profile 下的帧时间没看。

## 留下的问题

- 表情图在真机上的大小、和文字的对齐没有细看：CHECKLIST 第 2 节第 7 条，和 D04.1 的真机验证同一轮看。
- 第一次出现的表情要等解码，弹幕多时这一条会比别的晚进场：没有用户反馈，不做；要改时可以进房时预读这个平台的常用表情（照 3.x）。
- 网易 CC 的表情表没有打包（CC 没有弹幕，`emotes.dart:52-55`），3.x 的 CC 文件名还对不上（`netease_cc.json`，D01.1 记录）：CC 弹幕接上时再处理（附录 C-22）。
