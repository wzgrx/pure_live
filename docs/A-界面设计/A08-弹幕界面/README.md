# A08 弹幕界面

直播间和设置里所有“看弹幕、管弹幕”的界面：画面下面（宽屏在右栏）的四个标签——弹幕列表、醒目留言、弹幕设置、屏蔽管理；长按弹幕的面板和画面上飞行弹幕的点按、长按；设置里的弹幕页和弹幕屏蔽页；本地互动（本地弹幕输入框、互动面板、本地弹幕样式、礼物特效、设置页）。

## 范围

- 包括：
  - 直播间的聊天区：`features/live_play/danmaku/` 的四个标签（`ChatPanel`）、弹幕列表的样子和各种状态（`ChatList`、`ChatLineView`、`ChatListState`）、醒目留言（`SuperChatList`、`SuperChatCard`）、弹幕设置标签和画面上的弹幕设置面板里“弹幕列表”“小窗弹幕”两组（`RoomDanmakuSettings`、`PipDanmakuSettings`）、长按弹幕面板（`RoomMessagePanel`）。
  - 弹幕的共用界面块：`shared/danmaku/` 的屏蔽管理（`DanmakuBlockManager`、`BlockChip`）、弹幕设置正文（`DanmakuSettingsContent`、`danmaku_templates.dart` 的观看模板）、面板里的设置行（`setting_rows.dart`）、小窗弹幕的颜色对话框（`danmaku_color_dialog.dart`），以及飞行弹幕层 `danmaku_overlay.dart` 里**和点按有关的部分**（`messageAt`、`held`，A08.4）。
  - 设置里的两页：弹幕页（`features/settings/danmaku_page.dart`，A08.5、A08.6）、弹幕屏蔽页（`features/shield/shield_page.dart`，A08.3）。
  - 本地互动的全部界面：`features/live_play/local_interaction/`（A08.2）。
- 不包括（归哪里）：
  - 弹幕连接和协议、昵称和粉丝牌数据 → [D01](../../D-弹幕/D01-平台弹幕协议/README.md)；过滤规则（关键词、用户、相似、打码昵称的判断）→ [D02](../../D-弹幕/D02-过滤和屏蔽/README.md)；飞行弹幕怎么排、多快、多少帧、表情图怎么画（`danmaku_overlay.dart` 的绘制）→ [D03](../../D-弹幕/D03-飞行弹幕引擎/README.md)；弹幕进来到上屏的数据流（`chat_feed.dart` 每帧最多通知一次、500 条上限、昵称对比度的算法）→ [D04](../../D-弹幕/D04-数据流和性能/README.md)；设置真正生效（帧率、字体、纯文字）→ [D05](../../D-弹幕/D05-弹幕设置生效/README.md)。A08 只管这些东西长什么样、怎么点、各状态怎么说。
  - 聊天区放在直播间的哪里（竖屏画面下方、宽屏右栏 34%、横屏全屏时没有聊天区）、画面下栏的弹幕开关和弹幕设置按钮、面板放在画面下方还是右侧 360 → [A07](../A07-直播间界面/README.md)（A07.1、A07.4、A07.5、A07.6）；长按弹幕面板的“屏蔽关键词”第二页 → A07.11 c8；面板外壳 `shared/panels/side_panel.dart` 的 `RoomSidePanel` 和它的下拉手感 → A02.2、A03.2。
  - 小窗（应用内小窗、画中画）里飞的弹幕 `features/live_play/mini/compact_danmaku.dart` → A07.8；它的设置项（“小窗弹幕”一组）在这里。
  - 设置总览里的“弹幕”“小窗弹幕”“本地互动体验”入口行、设置页的“小窗弹幕”页 `PipDanmakuPage`（`features/settings/playback_tiles.dart:604`）、视频页的“弹幕屏蔽”行 → [A11](../A11-设置界面/README.md)（A11.1、A11.3、A11.4）。
  - 多画面格子里的弹幕 → A13.2；电视直播间的弹幕设置和屏蔽 → A17.4、A17.9。
  - 本地互动的数据和规则（`local_interaction/logic/`，A08.2 和界面一起做的，3.x 的 `localInteraction.*` 设置键在 `live_store`）：只改样子的在 A08 登记；改数据、规则、存储的没有专门的功能子分类，见“已知问题”。

## 现状：做到哪、怎么工作的

- 用户看得到的（A08.1～A08.4 登记为完成，A08.5 待真机，A08.6、A08.7 未开始）：
  - **四个标签**：竖屏在画面和信息行下面，宽屏在右侧聊天栏，四个等宽 `TabLabel`“弹幕列表、醒目留言、弹幕设置、屏蔽管理”，左右滑切换（`chat_panel.dart:77-139`）；“醒目留言”带条数角标，房间详情打开期间“弹幕列表”记新弹幕数（超过 99 写“99+”，`:147-151`）；从全屏回来记住停在哪个标签（`RoomViewMemory.chatTab`，`:40-47`）。横屏全屏时没有这四个标签（照 3.x），弹幕设置走画面上的面板。
  - **弹幕列表**：默认紧凑行“用户名：内容”（名字用弹幕颜色、保证 4.5:1，否则次要色），可在弹幕设置里换成 3.x 的卡片样式（`ChatListStyle`，设置键 `danmakuListStyle`）；系统消息是居中小灰标签，礼物一行（`AppIcons.chatGift`，“在聊天列表显示礼物”可关），醒目留言在列表里也有一条彩色行（`ChatLineView` `:572-711`）。第一条弹幕之前中间写状态：连接中、还没有弹幕、连接超时 +“重新连接”、连接失败 +“重新连接”、平台不提供弹幕（`_emptyState` `:253-296`）；“显示弹幕”关闭时写明并给“开启弹幕显示”（`:384-392`）。往上翻停止跟随，右下“N 条新弹幕”（主色底、`onPrimary` 字，`:450-472`），点了回到最新。长按、右键打开长按弹幕面板，双击复制“用户名: 内容”并提示“已复制到剪贴板”（`chatCopyText` `:80`、`:352-362`）。哔哩哔哩访客或登录过期时列表顶上一条“去登录”提示（`ChatNameHintBar` `:529`，D01.32）。没开播的房间整块换成主播公告和“开播后这里显示弹幕”（`RoomNoticeState` `:930`，A07.7）。
  - **醒目留言**：新的在上；卡片头部平台色、内容第二色，字色按对比度选深浅墨（`InkOnColor.contrastOn`），没有阴影，价格前金色图标（`LiveSemanticColors.superChatGold` `#FFC107`）和“SC”小块，右侧倒计时；整个列表一个每秒的时钟（`super_chats.dart:75`）；栏窄于 280 或字体放大时头部竖排（`:227`）；内容可选中、双击复制。空时“暂无醒目留言”，平台不提供时写“{平台}的直播间没有醒目留言。”（`:88-93`，按 `LiveSite.hasSuperChats`，`packages/live_core/lib/src/live_site.dart:64`，只有哔哩哔哩、虎牙、斗鱼为真 `:70`）。
  - **弹幕设置**：标签和画面上的面板是同一份内容 `RoomDanmakuSettings`：先是共用的 `DanmakuSettingsContent`（观看模板、显示范围、样式、重复弹幕、画面弹幕交互、流畅度），后面“弹幕列表”（列表样式分段按钮、在聊天列表显示礼物）和“小窗弹幕”（3.x 的 12 项，“小窗显示弹幕”关闭时其余收起，数值带单位 px、px/s、秒）（`danmaku_settings_panel.dart:76-137`、`:143` 起）。标签里“改动立即生效”在第一组标题右边，面板里在标题栏。“统一弹幕颜色”点开是居中的颜色对话框（`showDanmakuColorDialog`，`shared/danmaku/danmaku_color_dialog.dart:66`），全屏时压在画面中间（A08.7 要改）。
  - **屏蔽管理**：一页四组，顺序是弹幕关键词屏蔽（输入框最多 40 字 + “添加”，下面是已加的词）→ 已屏蔽用户 → 平台弹幕过滤（斗鱼疑似自动弹幕）→ 相似弹幕过滤（开关 + 三个滑块，关着时变灰）（`block_manager.dart:212-388`）。词和用户都是小标签，只有 × 能删（点击区 40×48，悬停“点击移除: 词”，`BlockChip` `:402`），删除后 4 秒内可撤销且放回原位（`restoreBlockEntry` `:392`）；重复的词在输入框下面提示、不清空；两节为空时写说明。第一次打开时如果 D02.1 清理过打码昵称，顶上说一次（`_maskedNotice` `:90`）。直播间“屏蔽管理”标签和设置里的“弹幕屏蔽”页是这同一个组件、同一份存储。
  - **长按弹幕**：列表长按、画面弹幕点按或长按都打开同一个面板（`showRoomMessageActions`，`message_panel.dart:20`）：竖屏在画面下方、横屏在右侧；“复制”“屏蔽此用户”“屏蔽关键词…”（第二页输入，A07.11）；本地弹幕和打码昵称（`观***`）没有“屏蔽此用户”（`:169`，D-013）。面板开着时飞行弹幕整层停住（`DanmakuOverlay.held`），关了继续。
  - **画面弹幕的点按和长按**：设置里“点按 / 长按”两个开关（默认开）打开时，点按在按下那一刻、长按在长按时问弹幕层“这个点上是哪条”（`player_view.dart:416-440`，`DanmakuOverlayState.messageAt` `shared/danmaku/danmaku_overlay.dart:292`）；控制条显示时上下控制条范围不算（`danmakuTapAllowed` `player_view.dart:839`）；没点中照常显示或隐藏控制层。**单击**只在控制层显示着、没有暂停时才打开面板，控制层隐藏时（淡出一开始就算）单击一律只调出控制层（`_onTap` `player_view.dart:360`，D-038，A08.9）；长按不受影响。
  - **设置里的两页**：设置 → 弹幕（`DanmakuSettingsPage`，`features/settings/danmaku_page.dart:32`，路由 `/danmaku_settings`）正文就是 `DanmakuSettingsContent`，末尾“更多”一组（显示弹幕、在画面上显示飞行弹幕、YouTube 显示全部聊天、更换弹幕字体、弹幕屏蔽），最宽 720，宽屏在右栏；**没有**直播间的“弹幕列表”“小窗弹幕”两组（A08.6）。设置 → 弹幕屏蔽（`ShieldPage`，`features/shield/shield_page.dart:21`，路由 `/shield`）就是 `DanmakuBlockManager`，最宽 720 居中，带 `BlockKind.user` 打开时滚到“已屏蔽用户”。
  - **本地互动**（总开关默认开）：弹幕列表下面一行输入框（星形打开本地弹幕样式、发送按钮），全屏下栏中间也有一个（窄于 180 收成星形按钮，`local_composer.dart:26`、`:29`），发出立即进列表、飞过（不再等 2 秒）；右上角菜单第三组“本地互动体验”打开互动面板（竖屏画面下方、横屏和宽屏右侧 360）：身份卡、发送框、礼物（余额不够变淡）、加体验币、我的资料、画面上、记录；本地弹幕样式是面板的下一页，预览固定在顶上；送礼时礼物横幅在画面中间 3 秒（`LocalGiftLayer`，`player_view.dart:699`）；列表里本地弹幕有“本地”标签和徽章胶囊；设置里“本地用户与互动”页（`/local_interaction`）。礼物和徽章的 emoji 用应用自带的 Noto 子集字体（iOS、macOS 用系统 emoji）。
- 内部怎么工作：
  - 数据：`LiveRoomController`（`features/live_play/logic/room_controller.dart`）持有 `chat`（`ChatFeed`，`features/live_play/danmaku/chat_feed.dart:101`，最多 500 条，每帧最多通知一次）、`superChats`、`chatConnection`（空闲、连接中、已连接、超时、失败、平台不提供）、`showGifts`（存在 meta 的 `live_play.showGifts`，`room_controller.dart:189`）。`ChatList` 只听 `ChatFeed` 和它要显示的几项房间状态（`_RoomFacts` `chat_list.dart:499`），不随人数、音量重建；列表倒序（最新是第 0 行）、每行组件建一次（`Expando`）。
  - 设置：弹幕设置、屏蔽列表、相似过滤都在 `live_store` 的设置和 `BlockListStore` 里，直播间、设置页、多画面读同一份；`watchSetting` 只重建用到的行。
  - 点按：手势层（`player_view.dart:662-675`）→ `_danmakuAt` → `DanmakuOverlayState.messageAt`（按这一帧的位置，四周放宽 4，叠着时取后进来的）→ `_onTap`：控制层显示着且没暂停才 `_openMessage`（D-038），否则只切换控制层 → `_openMessage` 把弹幕层 `held` 置真 → `showRoomMessageActions` → 面板关闭后恢复。
  - 本地互动：`LocalInteraction`（`local_interaction/logic/local_interaction.dart:113`，29 个 3.x `localInteraction.*` 设置）、`LocalCatalog`（`logic/local_catalog.dart:154`，模板、颜色、34 个资源包、礼物）、每个直播间一个 `LocalRoomSession`（`logic/local_room_session.dart:32`，经 `LocalRoomScope` 找到）；本地弹幕经 `room_controller.dart` 的 `addLocal` 进同一个 `ChatFeed`，飞过时 `danmaku_overlay.dart` 的本地分支用本地样式（`_placeLocal` `:513`）。
- 完成度（和 3.x 对照）：
  - 一致的：四个标签和顺序、左右滑；长按 / 右键 / 双击弹幕；“N 条新弹幕”；醒目留言卡片结构、到点移除；弹幕设置的全部项和范围、3.x 观看模板；小窗弹幕 12 项；屏蔽管理全部设置项和范围；关键词 40 字；画面弹幕的点按、长按开关和控制条范围不命中；本地互动的功能、数据、默认值、存储键。
  - 确认过的改动：A08.1 c1～c17（E1～E4 按 A）、A08.2 c1～c16（K1～K4 按 A）、A08.3 c1～c6（M1、M2 按 A）、A08.4 c1～c4、A08.5 c1～c2（c3 按维护者决定不做）；都按 D-003 由维护者选建议 A。
  - 还缺：设置的弹幕页没有“弹幕列表”“小窗弹幕”两组（A08.6）；直播间小窗弹幕颜色仍是居中对话框（A08.7）；A08.5 的真机验证；A08.3、A08.4 和 A08.1 的各状态没有 K90 记录（见“已知问题”）。

## 代码地图

直播间（`apps/pure_live/lib/features/live_play/`）：

| 文件 | 职责 | 设计 |
|---|---|---|
| `danmaku/chat_panel.dart`（151 行） | `ChatPanel`（`:21`）：四个标签和 `TabBarView`（`:77-139`），“弹幕列表”的新弹幕数、“醒目留言”条数（`_counted` `:147`），记住标签（`:40-47`） | A08.1、A07.1、A07.11 |
| `danmaku/chat_list.dart`（1001） | `ChatListStyle`（`:24`）、`chatNameColor`（`:55`，名字 4.5:1）、`chatCopyText`（`:80`）、`ChatList`（`:97`，跟随、停住、“N 条新弹幕” `:450-472`、空状态 `_emptyState` `:253`、“显示弹幕”关闭 `:384`）、`ChatNameHintBar`（`:529`）、`ChatLineView`（`:572`，紧凑行、卡片、系统、提示、礼物、醒目留言、本地分支 `:609`）、`parsePlatformColor`（`:834`）、`superChatPrice`（`:842`）、`ChatListState`（`:848`，列表中间的状态）、`RoomNoticeState`（`:930`，未开播时的公告） | A08.1、A07.1、A07.7、D04.1 |
| `danmaku/chat_feed.dart`（206） | `ChatLineKind`（`:8`）、`ChatLine`（`:26`）、`ChatFeed`（`:101`，500 条、每帧最多通知一次） | D04.1（数据流，界面只读它） |
| `danmaku/super_chats.dart`（302） | `superChatRemaining`（`:14`）、`SuperChatList`（`:25`，新的在上、一个时钟 `:75`、平台不提供 `:88-93`）、`_SuperChatEmpty`（`:111`）、`SuperChatCard`（`:148`，按对比度选墨、窄栏竖排 `:227`） | A08.1 c5～c7 |
| `danmaku/danmaku_settings_panel.dart`（308） | `showRoomDanmakuSettings`（`:20`）、`RoomDanmakuSettingsPanel`（`:37`，画面上的面板）、`RoomDanmakuSettings`（`:76`，标签和面板共用：共用正文 + “弹幕列表” + “小窗弹幕”）、`PipDanmakuSettings`（`:143`，小窗弹幕 12 项，颜色对话框 `:193-209`） | A08.1 c8～c10、A07.6 |
| `danmaku/message_panel.dart`（261） | `showRoomMessageActions`（`:20`）、`RoomMessagePanel`（`:50`，复制、屏蔽此用户 `:169`、屏蔽关键词）、`_KeywordPage`（`:195`，第二页输入） | A07.6、A07.11 c8、A08.4 c3 |
| `player/player_view.dart`（879） | 画面手势接弹幕：`_onTap`（`:336`，控制层隐藏或暂停时单击不开面板，D-038）、`_danmakuAt`（`:425`）、`_openMessage`（`:452`）、弹幕层 `held`（`:494`）、点按和长按（`:662-675`）、`danmakuTapAllowed`（`:839`，控制条范围不命中）；礼物横幅层（`:708`） | A08.4 |
| `local_interaction/local_composer.dart`（451） | `LocalComposerPlace`（`:13`，列表下、面板、画面）、`localComposerCollapseWidth` 180（`:26`）、`localComposerVideoMaxWidth` 420（`:29`）、`LocalDanmakuComposer`（`:49`）、`localVideoFocusColor`（`:314`）、`LocalComposerBelow`（`:437`，接在弹幕列表下） | A08.2 c6、c13、c14 |
| `local_interaction/local_interaction_panel.dart`（575） | `LocalInteractionPanel`（`:24`）、`LocalIdentityCard`（`:151`）、礼物格（`:225`、`:263`）、`LocalRechargeRow`（`:322`）、`LocalProfileEditor`（`:368`）、`LocalHistory`（`:447`） | A08.2 c2、c3、c8、c11、c12 |
| `local_interaction/local_style_panel.dart`（755） | `LocalDanmakuStylePanel`（`:19`）、`showLocalDanmakuStyleSheet`（`:72`，设置页用）、`LocalDanmakuPreview`（`:78`）、`LocalDanmakuStyleControls`（`:257`） | A08.2 c4、c5 |
| `local_interaction/local_gift_effect.dart`（126） | `LocalGiftLayer`（`:13`，画面里单独一层）、`LocalGiftBanner`（`:54`） | A08.2 c9 |
| `local_interaction/local_chat_line.dart`（101） | `LocalChatLine`（`:11`，“本地”标签和徽章胶囊） | A08.2 c10 |
| `local_interaction/local_interaction_settings_page.dart`（357） | `LocalInteractionSettingsPage`（`:24`，内容最宽 720 `:14`） | A08.2 c15 |
| `local_interaction/local_interaction_scope.dart`（97） | `localInteractionProvider`（`:21`）、`localInteractionAvailable`（`:33`）、`LocalRoomScope`（`:36`）、emoji 字体（`_bundledEmoji` `:58`、`localEmojiStyle` `:63`、`localEmojiText` `:71`、许可登记 `:76`）、`localAccentInk`/`localGiftInk`（`:88`、`:94`） | A08.2 c16 |
| `local_interaction/logic/local_catalog.dart`（606）、`local_interaction.dart`（419）、`local_room_session.dart`（112） | 本地互动的资料库、设置和操作、每个直播间的会话（不引 material） | A08.2 c1 |
| `buttons/room_menu_button.dart`（345） | 右上角菜单第三组“本地互动体验”（`:253`） | A07.6、A08.2 |

共用（`apps/pure_live/lib/shared/danmaku/`）和设置：

| 文件 | 职责 | 设计 |
|---|---|---|
| `shared/danmaku/block_manager.dart`（467） | `blockKeywordMaxLength` 40（`:14`）、`blockUndoDuration` 4 秒（`:18`）、`DanmakuBlockManager`（`:29`，四组、重复提示 `:153`、撤销提示条 `:169`、打码昵称清理的一次性说明 `:90`）、`restoreBlockEntry`（`:392`）、`BlockChip`（`:402`） | A08.1 c11～c16、A08.3、D02.1 |
| `shared/danmaku/danmaku_settings_content.dart`（360） | `DanmakuSettingsContent`（`:48`，直播间面板、标签、设置弹幕页共用的正文）、`_Templates`（`:279`，观看模板芯片） | A07.6、A08.5 |
| `shared/danmaku/setting_rows.dart`（322） | `PanelGroupTitle`（`:11`，可带右侧说明）、`PanelCard`（`:50`）、`SettingRow`（`:76`）、`SettingSwitchRow`（`:136`）、`SettingSliderRow`（`:179`）、`SettingCounterRow`（`:268`） | A07.6、A08.1 c16 |
| `shared/danmaku/danmaku_color_dialog.dart`（168） | `danmakuColorSwatches`（`:8`，10 种）、`DanmakuColorChip`（`:26`）、`showDanmakuColorDialog`（`:66`，居中对话框：色块 + 十六进制） | A08.1 偏差 1；A08.7 要改 |
| `shared/danmaku/danmaku_overlay.dart`（1022） | 飞行弹幕层：`DanmakuOverlay`（`:151`）；本任务组只关心 `rectOf`（`:283`）、`messageAt`（`:292`）、`held`、本地弹幕 `_placeLocal`（`:513`）；整层 `IgnorePointer`（`:673`），命中由手势层来问 | D03.1（引擎）、A08.4（命中）、A08.2（本地） |
| `shared/danmaku/danmaku_settings.dart`（53）、`danmaku_templates.dart`（231）、`emotes.dart`（161）、`masked_blocks.dart`（49） | 设置到画法的换算、观看模板和 `resolvedDanmakuFps`（`danmaku_templates.dart:210`）、表情表、打码昵称判断 | D05.1、D03.2、D02.1 |
| `features/settings/danmaku_page.dart`（184） | `DanmakuSettingsPage`（`:32`，正文 + “更多” `:62`）、`_More`（`:72`）；入口 `settings_section_view.dart:129`；路由 `routes/route_path.dart:72` | A08.5 c1 |
| `features/shield/shield_page.dart`（47） | `ShieldPage`（`:21`，`DanmakuBlockManager` 加顶栏，最宽 720，矮窗口顶栏 48）；路由 `route_path.dart:68` | A08.3 |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `apps/pure_live/test/features/live_play/live_play_tabs_test.dart`（13） | A08.1：连接中 → 超时 → 重新连接；第一条前后；平台不提供；“显示弹幕”关闭和按钮；“N 条新弹幕”字色；醒目留言顺序、金色底深字、无阴影、共用时钟、窄栏竖排；设置标签分组、单位、变灰、收起；画面面板末尾两组；屏蔽管理顺序、空说明、重复、× 48、撤销；1280×800、852×393 标签在右栏 |
| `.../live_play/local_interaction_test.dart`（15） | A08.2：资料库和 3.x 键；竖屏输入框、发出即显示、画面弹幕关着时只提示一次；长按本地弹幕没有“屏蔽用户”；面板内容和顺序、余额不够、礼物横幅；样式面板；宽屏和画面上的输入框收起；设置页五组 |
| `.../live_play/live_play_page_test.dart`（12） | A08.4：点飞行弹幕出面板三项、弹幕停住、关了继续，长按同一面板；开关关时只切控制层；控制条范围不命中 |
| `.../live_play/room_popups_test.dart`（12） | 长按弹幕面板第二页“屏蔽弹幕关键词”（A07.11 c8），横屏在右侧 360 |
| `.../live_play/chat_list_follow_test.dart`（5）、`chat_feed_test.dart`（8）、`chat_names_test.dart`（3）、`chat_benchmark_test.dart`（1） | 列表跟随和停住、每帧一次、昵称 4.5:1、每秒 200 条的帧耗时（D04.1） |
| `apps/pure_live/test/shared/danmaku_overlay_test.dart`（13）、`masked_blocks_test.dart`（3）、`emotes_test.dart`（5） | 弹幕层的命中、停住、本地弹幕停留（D03.1、A08.2）；打码昵称（D02.1）；表情表 |
| `apps/pure_live/test/features/shield/shield_page_test.dart`（7） | A08.3：一页四组、空说明、变灰、没有“清空”；空着添加、回车、重复不清空；× 48 和撤销放回原位；带 `BlockKind.user` 滚到用户；852×393 和 1280×800 最宽 720 |
| `apps/pure_live/test/features/settings/settings_danmaku_test.dart`（6） | A08.5 c1：设置“弹幕”是同一组件、“更多”、右栏、搜索、路由 |
| `packages/live_core/test/` 的 `hasSuperChats` 用例、`packages/live_ui/test/` 的 `InkOnColor` 对比度用例 | A08.1 加的平台能力和选墨 |

## 3.x 基线

文件都在 `git show v3.2.11:lib/modules/live_play/` 下（另注的除外）：

- 标签：`widgets/danmaku/danmaku_tab.dart`（76 行）：`DanmakuTabView`（`:8`），房间没好时整块 `AppStatusView(loading)`（`:16`），“显示弹幕”关闭时只有一句 `danmaku_display_disabled_hint`（`:33`），`DanmakuSectionTabBar`（`:55`，`TabBar` `:65`、`TabAlignment.fill` `:68`）；标签文字在 `controllers/live_play_controller.dart:73`。
- 列表：`widgets/danmaku/danmaku_list_view.dart`（649）：`useEdgeToEdgeDanmakuList`（`:32`，宽 ≤680）、“N 条新弹幕”`FilledButton.icon`（`:361-382`，固定白字）、本地弹幕输入框（`:386-436`）、`DanmakuItem`（`:446`，白 72% 卡片 + 8 像素彩色圆点，双击复制“用户名: 内容”`:453`，长按 `:502`、双击 `:503`）；最多 500 条（`live_play_controller.dart:97`）。
- 长按：`widgets/danmaku/danmaku_message_actions.dart`（125）：`showModalBottomSheet` 带拖动条（`:10-12`），第一行“用户名: 内容”和“Lv.N”，复制、屏蔽弹幕用户、屏蔽弹幕关键词（关键词是另一个居中对话框 `:64-125`）。
- 醒目留言：`pages/super_chat_page.dart`（54）、`widgets/layout/super_chat_card.dart`（333，每张卡一个每秒计时器 `:44-69`，字色按亮度 0.55 分界 `:79-85`，阴影 `:112-126`）。
- 弹幕设置：`pages/danmaku_settings_page.dart`（648，标签里 `embedded: false, includePipSettings: true`，画面上 `embedded: true`，`widgets/video_player/video_controller_panel.dart:2206`）；小窗弹幕 `modules/settings/pages/pip_danmaku_settings_page.dart`（744，`PipDanmakuSettingsSection` `:153-321`）。
- 屏蔽：`pages/keyword_block_page.dart`（376，过滤开关在前、关键词一行一个、点 × 删、无撤销）；设置里 `modules/shield/danmu_shield_page.dart`（132，只有关键词，点整个标签就删）、`danmu_shield_controller.dart`（29）。
- 画面弹幕的点按和长按：`widgets/video_player/video_controller.dart`（1569）：每条弹幕按设置带回调（`:217-220`），命中后暂停弹幕、打开 `DanmakuMessageActions`、关了 `resume`（`:132-149`）；`video_controller_panel.dart`（2213）的 `shouldHandleVideoSurfaceTap`（`:75`，控制条范围不算，用在 `:205`、`:235`）。
- 本地互动：`widgets/local_interaction/local_interaction_controller.dart`（911，数据和默认值）、`local_interaction_sheet.dart`（221，模态底部面板）、`local_danmaku_style_editor.dart`（868，竖屏 86% 高的底部面板 / 横屏右半边对话框）、`local_message_delivery_queue.dart`（61，发送后等 2 秒）；礼物特效 `pages/live_play_page.dart:47-92`（整页中间、整页重建）；设置页 `modules/settings/pages/local_interaction_settings_page.dart`（246）。
- 必须保留的操作习惯（[specs/UI.md](../../specs/UI.md) 附录 A）：第 2 条（控制条范围内的点击不触发弹幕命中）、第 6 条（点击或长按命中的弹幕，打开复制和屏蔽菜单）、第 7 条（返回链：长按面板、互动面板先关）；另有 3.x 的双击复制、右键 = 长按、“N 条新弹幕”只有点了才恢复跟随、关键词 40 字。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 设置的弹幕页没有直播间的“弹幕列表”“小窗弹幕”两组：这两组写在 `features/live_play` 里，设置不能引用 | `features/live_play/danmaku/danmaku_settings_panel.dart:97-133`、`:143`；`features/settings/danmaku_page.dart:62` | 同一个设置两处不一样（A08.1 E1 的“完全一样”没做到） | A08.6 |
| 直播间里“统一弹幕颜色”是居中对话框，全屏时压在画面中间（全屏里最后一个） | `danmaku_settings_panel.dart:193-209`、`shared/danmaku/danmaku_color_dialog.dart:66` | 违反规范第 7 节“直播间里设置用面板”；A07.11 c8 的遗留 | A08.7 |
| 小窗弹幕的设置有两份实现、顺序不同：直播间的 `PipDanmakuSettings` 照 3.x 顺序（A08.1 c9），设置的“小窗弹幕”页是目录行、按 A11.3 c14 分组（透明度、速度、字号……在前）；3.x 两处是同一个 `PipDanmakuSettingsSection` | `features/live_play/danmaku/danmaku_settings_panel.dart:143`；`features/settings/settings_catalog.dart:1085-1234`、`playback_tiles.dart:604` | 同一组设置两处顺序不同 | A08.6 的待选 G3 |
| 两个小窗弹幕颜色选择器：直播间是 `showDanmakuColorDialog`（10 个色块 + 十六进制），设置的小窗弹幕页是 `showColorDialog`（`LiveColorPicker`） | `shared/danmaku/danmaku_color_dialog.dart:66`；`features/settings/playback_tiles.dart:510-538`（`PipColorTile`）、`settings_dialogs.dart:317`（`showColorDialog`） | 同一个设置两种选色方式 | A08.7 一起定（统一成一个面板式选择） |
| A08.3、A08.4 登记为“完成”，记录里没有 K90 结果；A08.1 的列表状态（超时、平台不提供、醒目留言卡片）只在 S02.2 冒烟里看过“四个标签、系统提示” | 各任务 `record.md`；[S02.2 记录](../../S-质量和验证/S02-真机验证/S02.2-K90冒烟/record.md) | 不符合 PROCESS 3.2“完成必须有真机结果” | 写进本单元报告；建议这些检查并入 S02.6 或改回“待真机” |
| 本地互动的礼物和徽章 emoji 是 COLRv1 字体，Windows 10 的 DirectWrite 可能画成空白 | `local_interaction/local_interaction_scope.dart:58`（`_bundledEmoji`：除 iOS、macOS 外都用自带字体） | Windows 10 上礼物图案看不见 | 没在 Windows 上看过；X01（Windows）验证，不行时让 Windows 用系统 emoji |
| 本地礼物在列表里那一行没有长按菜单（3.x 的礼物和弹幕是同一种卡片，可以长按） | `features/live_play/danmaku/chat_list.dart:609-618`（本地礼物直接返回 `LocalChatLine`） | 不能复制礼物那一行 | A08.2 记录“没做的”；没有任务管，影响小，不做 |
| 本地互动的数据和规则（`local_interaction/logic/`）没有登记在哪个功能子分类 | `features/live_play/local_interaction/logic/` | 以后改数据和规则时不知道在哪开任务 | 需要维护者决定（建议归 D 组新开子分类或并入 D05） |
| 设置的弹幕屏蔽页、弹幕页、本地互动设置页在电脑上按 Esc 不返回（没有 `EscapeBack`） | `features/shield/shield_page.dart:31`、`features/settings/danmaku_page.dart:46`、`local_interaction_settings_page.dart` | 规范 5.4 的 Esc 返回链不全 | A05.1 c3 |
| A08.5 c3（清理翻译键）没做：旧弹幕目录行用过的 18 个键现在没有字面引用；A08.3 删掉的两个标签页用的 `shield_tab_*`、`shield_clear*`、`shield_duplicate` 已被 `00f5edf18`（2026-10-02 清理不用的键）删掉，`shield_*` 现在只剩在用的 `shield_title`、`shield_removed`（2026-10-07 核对） | 键名清单在 [A08.5 记录](A08.5-设置里的弹幕页/record.md)“留给以后” | 翻译文件里有不用的键 | D-024：这次不清理；以后按 D-016 先列清单（Z05） |
| 代码注释里还用旧编号（`U.2e c8`、`U.2k-a`、`B09 c4`、`F02 c1`、`F.2b`、`UI_PLAN §7` 等），本子分类的文件里约 116 处 | `chat_panel.dart:17-18`、`:85`、`:117`、`danmaku_page.dart:21-22` 等 | 按注释找文档要先查 [MAPPING.md](../../MAPPING.md) | Z 组一次性替换（单元 2 已建议） |
| 电视直播间没有弹幕列表和醒目留言（pure_live_TV 也没有），弹幕设置和屏蔽在播放设置侧面板 | `apps/pure_live/lib/tv/room/tv_live_play_page.dart:464` | 电视上看不到聊天 | A17.4（照 pure_live_TV，不做聊天区） |

## 相关决定和规范

- D-003：A08.1 的 E1～E4、A08.2 的 K1～K4、A08.3 的 M1、M2 由维护者按建议 A 定。
- D-012（暂停后单击只切控制层）和 A07.10 的“暂停时的弹幕”设置：设置的弹幕页、直播间面板都有这一项（A08.5 c1）。
- D-013：哔哩哔哩打码昵称不能“屏蔽此用户”（`message_panel.dart:169`），已存的打码屏蔽清理后在屏蔽管理顶上说一次（D02.1）。
- D-016、D-024：翻译键这次不清理（A08.5 c3）。
- D-020：往上甩面板不关闭（长按弹幕面板、互动面板都是 `RoomSidePanel`）。
- [specs/UI.md](../../specs/UI.md)：第 3 节第 6、7、8 条（同一件事一种做法：标签和面板是同一份弹幕设置、直播间和设置页是同一个屏蔽组件）；第 7 节（面板竖屏在画面下方、横屏右侧 360；提示条带“撤销”时 4 秒）；第 8.1 节（语义色：醒目留言金色）；第 9.2、9.3 节（列表局部刷新、弹幕只描边不加模糊、醒目留言去阴影）；附录 A 第 2、6、7 条。

## 测试和验证

- 自动测试：`cd apps/pure_live && flutter test test/features/live_play/ test/features/shield/ test/features/settings/settings_danmaku_test.dart test/shared/`（上表）；平台能力和选墨在 `packages/live_core`、`packages/live_ui` 的测试里。覆盖了每个确认的改动；缺的：没有截图对照（深色主题下的卡片样式、醒目留言配色只断言颜色值）；`chat_benchmark_test.dart` 是测试环境里的帧耗时，不是 K90 的 profile 数字。
- 真机：[S02 的真机清单](../../S-质量和验证/S02-真机验证/CHECKLIST.md)第 2 节（弹幕）第 1 条（连接、断网状态）、第 4 条（屏蔽词、屏蔽用户、合并重复、斗鱼过滤）、第 5 条（上滑新消息提示、长按三项）、第 6 条（画面弹幕点按长按，A08.4）、第 7 条（醒目留言、表情图）、第 8 条（本地弹幕和礼物）；A08.5 的步骤在 [verify.md](A08.5-设置里的弹幕页/verify.md)。S02.2 冒烟（2026-10-02，`288fec0ec`）看过“四个标签、系统提示、本地弹幕输入框”，其余没有记录。

## 路线

1. 维护者按 [A08.5 的 verify.md](A08.5-设置里的弹幕页/verify.md) 在 K90 上看设置的弹幕页和录制提醒定位，通过后改“完成”。同一轮顺带补看 CHECKLIST 第 2 节第 4～8 条，给 A08.1、A08.3、A08.4 补上真机结果（登记表问题见本单元报告）。
2. A08.6：把“弹幕列表”“小窗弹幕”两组挪到 `shared/danmaku/`，设置的弹幕页末尾也显示（规模小，第二档）。先做它，A08.7 的颜色面板就只改一处。
3. A08.7：小窗弹幕颜色改成在行下面展开的色板（直播间和设置页同一个），全屏里不再有居中对话框（规模小，第二档）。
4. 以后：本地互动逻辑的归属（见“已知问题”）；Windows 上礼物 emoji（X01）；电视的弹幕设置样式（A17.4）。新想法写进 V01 提议，不直接加任务。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [A 界面设计](../README.md)。

- 代码：`features/live_play/danmaku/`、`shared/danmaku/`、`local_interaction/`
- 进度：`█████████████████░░░` 84%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| A08.1 | 弹幕列表和弹幕设置页 | 界面 | 完成 | 2026-10-01 | 05793a4c8 | [设计或说明](A08.1-弹幕列表和弹幕设置页/README.md)、[记录](A08.1-弹幕列表和弹幕设置页/record.md)、[评审页](A08.1-弹幕列表和弹幕设置页/page/01-说明.jpg) |
| A08.2 | 本地互动 | 界面 | 完成 | 2026-10-01 | e704b933a | [设计或说明](A08.2-本地互动/README.md)、[记录](A08.2-本地互动/record.md)、[评审页](A08.2-本地互动/page/01-说明.jpg) |
| A08.3 | 弹幕屏蔽页 | 界面 | 完成 | 2026-10-01 | 5ba728803 | [设计或说明](A08.3-弹幕屏蔽页/README.md)、[记录](A08.3-弹幕屏蔽页/record.md)、[评审页](A08.3-弹幕屏蔽页/page/01-说明.jpg) |
| A08.4 | 画面弹幕点按和长按：复制、屏蔽此用户、屏蔽关键词 | 功能 | 完成 | 2026-10-02 | b8462638a | [设计或说明](A08.4-画面弹幕点按和长按/README.md)、[记录](A08.4-画面弹幕点按和长按/record.md) |
| A08.5 | 设置里的弹幕页和直播间同一个组件；“录制已停止”通知定位到任务 | 功能 | 待真机 | 2026-10-02 | ec7a27261 | [设计或说明](A08.5-设置里的弹幕页/README.md)、[任务书](A08.5-设置里的弹幕页/brief.md)、[记录](A08.5-设置里的弹幕页/record.md)、[真机验证](A08.5-设置里的弹幕页/verify.md) |
| A08.6 | 设置的弹幕页补上“弹幕列表”“小窗弹幕”两组 | 界面 | 待真机 | 2026-10-08 | — | [设计或说明](A08.6-设置的弹幕页补两组/README.md)、[任务书](A08.6-设置的弹幕页补两组/brief.md)、[记录](A08.6-设置的弹幕页补两组/record.md) |
| A08.7 | 小窗弹幕的颜色选择改成面板（全屏里最后一个居中对话框） | 界面 | 未开始 | — | — | [设计或说明](A08.7-小窗弹幕颜色改成面板/README.md)、[任务书](A08.7-小窗弹幕颜色改成面板/brief.md) |
| A08.8 | 长按弹幕面板加回 3.x 的等级 Lv.N | 界面 | 未开始 | — | — | [设计或说明](A08.8-长按弹幕面板显示等级/README.md)、[任务书](A08.8-长按弹幕面板显示等级/brief.md) |
| A08.9 | 单击画面优先调出控制层：弹幕多时点画面总是打开长按弹幕面板 | 界面 | 完成 | 2026-10-08 | df901709a | [设计或说明](A08.9-单击画面优先调出控制层/README.md)、[任务书](A08.9-单击画面优先调出控制层/brief.md)、[记录](A08.9-单击画面优先调出控制层/record.md) |

## 还没完成的

- **A08.7 小窗弹幕的颜色选择改成面板（全屏里最后一个居中对话框）**（未开始，第二档，规模 小）
- **A08.8 长按弹幕面板加回 3.x 的等级 Lv.N**（未开始，第三档，规模 小）
  - 来源：D 组写文档时发现（D01 已知问题）；D-033

<!-- docs:生成结束 -->
