# A07.21 直播间顶栏和详情不显示平台的占位分区名（“京东直播 · JD Live”）

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：界面
- 来源：2026-10-08 K90 复查 A07.16（京东直播间）

## 目标

平台没有给分区时，顶栏和详情只写平台名，不写平台的占位名。

## 现状

- K90：京东直播间顶栏写“京东直播 · JD Live”。`JD Live` 是京东适配器的占位分区名（`packages/live_core/lib/src/sites/jdlive/jdlive_api.dart:230` `siteName`，`:581` `area: siteName`），3.x 也这样写（`v3.2.11:lib/core/site/jdlive/jd_live_api.dart:231-232`）；酷狗、百度在 3.x 存下的房间里也有同类占位名（`legacyPlaceholderNames`，J06.2/E05.4）。

## 方案

- `apps/pure_live/lib/shared/rooms/platform_texts.dart` 加 `roomAreaShown(platform, area)`：去掉首尾空白，是该平台的占位名就返回空；顶栏（`room_header.dart`）和详情（`room_details.dart`）都用它。存的数据不变。

## 验证

- 自动测试：`test/shared/platform_texts_test.dart`。
- 真机：京东直播间顶栏只写“京东直播”。
