# D03.3 小窗和画中画的弹幕：放大后跟着变大，用弹幕字体，画表情图

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能
- 来源：2026-10-07 docs v2 核对：D 组（[D03 说明](../README.md)“已知问题”：小窗不画应用自带的表情图，`compact_danmaku.dart:190`、`:105`；不用弹幕字体，`:204-213`）；S、V、W 组（[V01.5 小窗拖角改尺寸](../../../V-需求和反馈/V01-新功能提议/V01.5-小窗拖角改尺寸/README.md) 的评估：上游 pure_live `b2cca41c7`“画中画弹幕随窗口放大成比例缩放”，缩放上限 1.0 → 2.0；这一条是现有行为的修正，不用等新功能确认，拆出来在这里做；直播间同屏 48 条的上限没有测试）
- 相关：小窗弹幕的设置和换算是 [A07.8](../../../A-界面设计/A07-直播间界面/A07.8-小窗/README.md)（c7：自动缩放时最小 10 号）、[A08.1](../../../A-界面设计/A08-弹幕界面/A08.1-弹幕列表和弹幕设置页/README.md) c9；表情图 [D03.2](../D03.2-飞行弹幕里的表情图片/README.md)；弹幕字体 F.2a（[D05.1](../../D05-弹幕设置生效/D05.1-弹幕设置生效/README.md)）；新功能提议 V01.5（拖角改尺寸本身仍在 V01）；决定 D-001、D-017、D-018
- 任务书：[brief.md](brief.md)

## 目标

应用内小窗（离开直播间时首页角落那个）、系统画中画、桌面小窗里飞的弹幕，和直播间画面上的一样好看、跟着窗口大小走：

1. 设置 → 弹幕 → 更换弹幕字体选了别的字体，小窗里的弹幕也用它（现在小窗一直是系统字体）。
2. 哔哩哔哩、斗鱼等平台的 `[笑哭]` 这类表情在小窗里是图片（现在是文字代码）；“小窗弹幕纯文字”打开时连应用自带表里的代码也去掉（现在只去掉消息自带的表情）。
3. 两指把画中画拉大、平板或桌面上小窗本来就宽时，弹幕字号、速度、轨道高跟着放大，最多到设置值的 2 倍（现在宽过 350 就不再变大，大窗口里弹幕显得很小）。
4. 直播间画面上同屏最多 48 条（3.x 的上限）有测试守着。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11`，文件:行） | 现在（文件:行） | 要做到 |
|---|---|---|---|
| 小窗弹幕的字体 | 用弹幕字体：`lib/modules/live_play/widgets/danmaku/compact_danmaku_overlay.dart:35`（`danmakuFontFamilyName`）→ `:40`、`:62` | `apps/pure_live/lib/features/live_play/mini/compact_danmaku.dart:204-213` 的 `DanmakuLook(…)` 没有 `fontFamily`；直播间用 `danmakuLookOf`（`shared/danmaku/danmaku_settings.dart:11-28`，`:25` 默认值时为 null） | 和直播间一样取 `Settings.danmakuFontFamilyName` |
| 小窗的表情图 | 同一个表情图集 `EmojiAtlas.instance`（`compact_danmaku_overlay.dart:86`），纯文字 `noEmojiMode`（`:26`、`:67`） | `DanmakuOverlay(…)`（`compact_danmaku.dart:190-215`）没有传 `emotes:`，默认 `EmoteTable.empty`（`shared/danmaku/danmaku_overlay.dart:164`）；纯文字在 `_take` 里用 `withoutEmoteCodes(text, message.emotes)` 只去掉消息自带的表情（`:105-118`），应用自带表的代码去不掉 | 传入这个平台的 `EmoteTable`（和直播间 `player/player_view.dart:226-237` 一样从 `emoteLibraryProvider` 取）；纯文字改走 `DanmakuLook.textOnly`（弹幕层自己去掉，`danmaku_overlay.dart:374` 起） |
| 随窗口缩放 | `lib/common/utils/compact_danmaku_metrics.dart:29`：`(宽 / 350).clamp(0.65, 1.0)` | `apps/pure_live/lib/features/live_play/logic/mini_window.dart:195-226` `CompactDanmakuMetrics.resolve`：`:201` 同样 `clamp(0.65, 1.0)`，轨道高 `max(字号 × 1.8, 字号 + 10)` 限在 18～44（`:208`）；最小 10 号（A07.8 c7，`:203`） | 上限放到 2.0（上游 `b2cca41c7`），轨道高上限 44 → 88；表情高按字号算（`DanmakuLook.emoteSize` 1.3 × 字号、16～48，`danmaku_overlay.dart:73`）不用改；小于 350 宽的规则不变 |
| 小窗有多宽 | 手机应用内小窗 220 宽；画中画由系统定 | 应用内小窗 220～360（`mini_window.dart:98-114`）；画中画两指能拉大；平板、桌面小窗更宽 | 宽于 350 的窗口里弹幕变大 |
| 直播间同屏上限 | 48 条 | `DanmakuOverlay.maxVisible` 默认 48（`danmaku_overlay.dart:158`、`:466`），没有测试 | 加一个测试 |

## 方案

- c1 字体（`compact_danmaku.dart`）：`build` 里读 `Settings.danmakuFontFamilyName`，和 `danmakuLookOf` 同样的规则（空或默认值 → null）传给 `DanmakuLook(fontFamily:)`；最好把这个换算从 `danmaku_settings.dart:12`、`:25` 抽成一个小函数两处共用。
- c2 表情图：`_CompactDanmakuLayerState.initState` 照 `player_view.dart:226-237` 从 `emoteLibraryProvider` 取 `tableOf(platform)`，空就 `load(platform)` 后 `setState`；`didUpdateWidget` 换了房间（平台变了）时重取。`DanmakuOverlay(emotes: _emotes)`，`DanmakuLook(textOnly: watchSetting(ref, Settings.pipDanmakuNoEmojiMode))`；`_take` 里不再自己去表情（删掉 `:105-118` 的改写，保留“去掉后为空就不发”的效果——弹幕层 `textOnly` 时整条只有表情会被丢掉，`danmaku_overlay_test.dart:266` 已测）。
- c3 放大：`mini_window.dart:201` 的上限 1.0 → `maxScale = 2.0`（常量，写注释“上游 pure_live b2cca41c7”），`:208` 轨道高上限 44 → 88；文档注释更新。`live_play_mini_window_test.dart:284-292` 的期望：360 宽时字号从 12 变成 12 × 360 / 350 ≈ 12.34（改断言并写明原因），新增 700 宽 = 2 倍、1000 宽仍是 2 倍。
- c4 48 条：`apps/pure_live/test/shared/danmaku_overlay_test.dart` 加用例：默认 `maxVisible`，一次进 60 条，多帧之后屏上远端弹幕不超过 48，本地弹幕不算在内（`:465-466` 只数 `!item.local`）。
- 不改：小窗弹幕的 12 项设置、默认值和范围（D-018）；直播间的弹幕层；帧率规则（`compactDanmakuFps`）；应用内小窗的尺寸（V01.5）。

## 验证

- 自动测试：`live_play_mini_window_test.dart`（缩放上限、字体、表情、纯文字）、`danmaku_overlay_test.dart`（48 条）；现有的 A07.8 小窗用例照样通过。
- 真机：K90 上应用内小窗、画中画两指拉大、换弹幕字体（任务书“真机验证”）；待真机。
- 2026-10-08 两个阶段都做完，见 [record.md](record.md)：缩放上限 2 倍、轨道高上限 88。

## 留下的问题

- 小窗拖角改尺寸（应用内小窗能拉大）仍是 V01.5 的新功能提议；本任务只让弹幕跟着已经能变大的窗口（画中画、平板、桌面）走。
- 多画面不传表情表、不跟帧率是 [N01.2](../../../N-多画面和投屏/N01-多画面/N01.2-多画面弹幕跟随帧率设置/README.md)；电视的弹幕层是 A17.4。
- `compactDanmakuFps` 和 `resolvedDanmakuFps(pip: true)` 两份同样的规则（D03 说明“已知问题”）不在本任务。
