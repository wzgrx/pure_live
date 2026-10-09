# D08.6 平台体验资源包的图标和资源跟上现在的平台：记录

- 日期：2026-10-09
- 执行者：Claude
- 分支和提交：工作区分支 `worktree-agent-a5c97785f427a843a`，代码 `e4cfcaa48`，文档在其后一个提交
- 任务书：[brief.md](brief.md)；说明：[README.md](README.md)

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| 1 每个平台一个包 | 做了：35 个，按 `SiteIds.supported` 的顺序，补 Kick | — |
| 2 画平台图标 | 做了：选择片、预览、身份卡、列表徽章胶囊、礼物横幅、记录（`LocalPackBadge`） | 礼物格、飘屏、预览的礼物片画的是礼物，照旧是礼物 emoji（本地礼物没有图片） |
| 3 颜色一个来源 | 做了：`PlatformLogos.colors`（live_ui），资源包和礼物行都读它 | 13 个颜色改成图标的颜色（README 的表），其余不变 |
| 4 各平台的币和礼物 | 做了：19 个平台（README 的表） | YY、映客、LiveMe 等没有调研结果的照旧通用（p9、留下的问题） |
| 5 礼物 id 不改 | 做了：3.x 的 28 个 id、价格、名字的键不变 | — |
| 6 档位和座驾 | 做了：每个新平台小、中、大各一个，大的都指定座驾 | — |
| 7 翻译 | 做了：86 个新键，zh、en 都加，没有删键 | — |

## 根因

- 资源包是 3.x 的一张表（`logic/local_catalog.dart` 改之前的 `packs` `:367-402`、`_platformGifts`、`badgeKeyFor`）：34 个包，徽章是 emoji 或两个字母，8 个平台有自己的币和礼物。4.x 后来加了 Kick（`SiteIds.kick`）、平台图标（`PlatformLogos`，35 个）、各平台的礼物体系和单位（D07、V03.5），这张表没有跟着改：设置页、面板、列表、横幅画的仍是 `pack.badge` 的 emoji，Kick 落到通用包，其余 26 个平台用通用的币和礼物。
- 颜色：应用里没有别的平台颜色表，`gift_line.dart` 的贵重礼物颜色也读资源包的 `accent`；3.x 的值有 8 个和 4.x 的平台图标不是一个色相（哔哩哔哩 00AEEC 蓝 / 图标粉，CC FF4D7D 粉 / 图标蓝，YY 橙 / 图标黄，映客粉 / 图标青，克拉克拉紫 / 图标珊瑚，LiveMe 紫 / 图标黄，BIGO 紫 / 图标青，FC2 粉 / 图标橙）。图标主色用 ffmpeg 把每张图缩到 48×48 取样（去掉灰、白、黑）得到。

## 改了哪些文件

- `packages/live_ui/lib/src/icons/platform_logo.dart`：`PlatformLogos.colors`、`colorOf`。
- `apps/pure_live/lib/features/live_play/local_interaction/logic/local_catalog.dart`：`LocalPlatformPack.badgeKey`；`_pack` 读 `PlatformLogos.colorOf`；35 个包；19 个平台的礼物；`platformsWithGifts`；`badgeKeyFor` 读包。
- `…/logic/local_interaction.dart`：`LocalProfile.platform`（存进消息数据）、`badgeWords`；`profileFor` 写平台。
- `…/local_interaction/local_pack_badge.dart`（新）：`LocalPackBadge`。
- `…/local_interaction_settings_page.dart`（选择片、预览）、`…/local_interaction_panel.dart`（身份卡、记录每条）、`…/local_chat_line.dart`（徽章胶囊，`ChatChip.leading`）、`…/local_gift_effect.dart`（横幅第二行）。
- `…/effects/local_gift_vehicle.dart`：`_byGift` 改公开的 `named`，加 19 个大礼物。
- `apps/pure_live/lib/features/live_play/danmaku/gift_line.dart`：`giftPlatformInk` 读 `PlatformLogos.colorOf`。
- `apps/pure_live/assets/fonts/emoji/NotoColorEmoji-Subset.ttf`（40 → 74 个 emoji，55 KB → 101 KB）、`NOTICE.txt`。
- `apps/pure_live/assets/translations/zh.json`、`en.json`。
- 测试：见下。

## 新设置、翻译键、门禁基线

- 没有新设置；3.x 的键不变。
- 翻译键 86 个：币 14 个（`local_currency_ac_coin`…`local_currency_star_coin`）、等级 7 个（`local_level_fans`、`gifter`、`member`、`noble`、`sub`、`user`、`wealth`）、徽章 8 个（`local_badge_family`、`fan_club`、`fans`、`guard`、`medal`、`member`、`premium`、`sub`）、礼物 57 个（`local_gift_<id>`）。`local_badge_*`、`local_level_*`、`local_currency_*` 是拼出来的键，`test/i18n_runtime_keys.dart` 的规则改成从包里取。
- 消息数据多一个 `platform`（本地弹幕和礼物；礼物以前就有）。

## 测试

- 新增 `apps/pure_live/test/features/live_play/local_platform_packs_test.dart` 11 个：
  - 每个平台有包、顺序、颜色等于 `PlatformLogos.colorOf`、都有图标；
  - 3.x 的 8 个平台的键和 28 个礼物 id、价格不变，所有礼物 `giftById` 找得到、id 不重复；
  - 有自己礼物的平台各小、中、大一个，大的都在 `LocalGiftVehicle.named` 里，没有礼物体系的用通用 4 个；
  - 每个礼物和徽章的 emoji 都在自带字体的 cmap 里；
  - `LocalPackBadge`：35 个图标，通用包是 ✨；
  - D08.6 以前的消息（没有 `platform`）照旧是“📺 舰队等级 Lv.1”，新的是图标 + “订阅徽章 Lv.2”；
  - 设置页 1 倍、2 倍字：除了选中的都有图标，选 Kick 后预览是 Kick 图标、“订阅等级 Lv.1 · 1000 Kicks”、Kick 的 3 个礼物，不溢出；
  - Kick 直播间竖屏、横屏：身份卡图标和“Kick · 订阅等级 Lv.1 · 1100 Kicks”、Kick 的礼物格、送一个后横幅里有图标；
  - 记录：3.x 的 `castle`、`bili_voyage` 和 `douyu_super_rocket` 照样显示名字和各自平台的图标，能“再发一次”。
- 改了：`local_interaction_test.dart` 3 处（包的个数、列表和横幅的徽章是图标 + 字）；`packages/live_ui/test/widgets_test.dart` 加 1 个（每个图标有颜色）；`local_interaction_support.dart`、`live_play_support.dart` 加 `platform` 参数（默认哔哩哔哩）；`i18n_runtime_keys.dart`。
- 全部通过：`apps/pure_live/test/features/live_play/`、`test/features/settings`、`test/shared`、`test/i18n_test.dart`、`packages/live_ui/test/widgets_test.dart`；门禁见下。
- 主机截图（测试里换上文泉驿字体看过，没有提交）：设置页 1 倍、2 倍字的选择片和六间房预览；CHZZK 直播间竖屏、横屏的身份卡和横幅。

## 门禁

- `tools/gate/gate.sh --all`：见提交说明（日志在会话的临时目录）。

## 真机上要看的

1. 设置 → 本地用户与互动 → 平台体验资源包：每个选择片前是平台图标（和首页卡片、搜索里的一样），选中的是勾；一共 35 个，有 Kick。
2. 点 Kick、六间房、CHZZK：预览卡左上是图标；第二行“订阅等级 Lv.1 · 1000 Kicks”“财富等级 Lv.1 · 1000 六币”“订阅等级 Lv.1 · 1000 奶酪”；礼物各 3 个；底色和图标是一个颜色。系统字体调到最大再看一次，不溢出。
3. 进一个哔哩哔哩直播间，打开“本地互动体验”面板：身份卡左边是哔哩哔哩图标（圆角方块，不再是圆形的 📺），底色是粉色；礼物仍是辣条、小电视、大航海。
4. 发一条本地弹幕、送一个礼物：列表里的徽章胶囊是“小图标 舰队等级 Lv.1”；礼物横幅第二行是“小图标 舰队等级 Lv.1 · 听众”。
5. 进 Kick（或 CHZZK、六间房、酷狗）直播间：面板的币名、礼物是这个平台的；送大礼物（送订阅 2000 要先在“更多”里加币）有座驾（飞机）。横屏全屏再看一遍面板和横幅。
6. 面板的“本地互动记录”：每条时间前有平台图标；更新前送过的礼物（例如大航海、城堡）照样显示名字，能“再发一次”。
7. 更新前发过的本地弹幕被“之前发的”放回时：徽章用现在的平台图标（放回按现在的身份重新生成）。
