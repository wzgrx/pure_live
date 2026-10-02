# D03.2 飞行弹幕里的表情图片

- 状态：以登记表为准，见[子分类页](../../../A-界面设计/A08-弹幕界面/README.md)和 [STATUS.md](../../../STATUS.md)
- 档位：可以以后；规模：中
- 功能点：F-DM-16（见 [inventory/FEATURES.md](../../../inventory/FEATURES.md)）
- 涉及代码：`apps/pure_live/lib/shared/danmaku/`（`emotes.dart` 的表已有）
- 依赖：D03.1
- 来源：S02.1 第 8 节“留给后续”
- 评审页：随 D03.1 的设计
- 记录：[records/F.2c.md](../../../TASKS.md)（开发后）

## 要做的

| 功能点 | v3 | v4 现在 | 要做到 |
|---|---|---|---|
| F-DM-16 | flame_barrage 的表情图集，飞行弹幕里表情是图片（`core/emoji/models/unified_emoji_model.dart:4`） | 聊天列表有图片（S02.1），飞行弹幕仍是文字 | 飞行弹幕里表情显示成图片；纯文字模式（D05.1）时去掉 |

## 测试和验证

- 组件测试：带表情码的弹幕画出图片；读不出图片时显示表情码。
- K90：快手、哔哩哔哩带表情的弹幕；profile 模式看帧时间。

## 经过

| 日期 | 内容 |
|---|---|
| 2026-10-02 | 建立（第 1 版清点） |
