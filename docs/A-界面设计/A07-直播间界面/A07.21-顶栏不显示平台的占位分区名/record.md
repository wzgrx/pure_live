# A07.21 直播间顶栏和详情不显示平台的占位分区名：记录

- 日期：2026-10-08
- 执行者：Claude
- 分支和提交：本机工作区 `ai/A07.21`（从 master `d34ad44d1` 开始）
- 设计或说明：[README.md](README.md)

## 做了什么

- `roomAreaShown`（`platform_texts.dart`）；`room_header.dart`、`room_details.dart` 用它取要显示的分区。

## 测试

- `platform_texts_test.dart` 加了 4 条断言（京东占位名隐藏、正常分区保留并去空白、别的平台同名不受影响、空值）；`test/shared/platform_texts_test.dart` 和 `test/features/live_play` 共 344 个全过。

## 真机

待 K90：京东直播间顶栏只写“京东直播”。
