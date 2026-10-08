# C03.2 HyperOS 拦截“在快手打开”：跳转失败时说清楚怎么放行

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：原生
- 来源：2026-10-08 K90 S02.6 第 11 步
- 相关：[C03.1](../C03.1-直播间小项/README.md)（快手 App 跳转）

## 目标

在 HyperOS 上点“在快手打开”能跳过去；系统不让跳时，提示用户去哪里放行，而不是笼统的“请检查默认浏览器或应用设置”。

## 3.x 和现状

| 方面 | 现在 | 要做到 |
|---|---|---|
| K90 实测 | 快手直播间菜单 →“在快手打开”：快手 App 装着，什么都没打开，提示“打开直播间失败，请检查默认浏览器或应用设置”。logcat：先发 `kwai://…`，再发 `VIEW https://live.kuaishou.com/…`，两次都被系统转去 `android.app.action.CHECK_ALLOW_START_ACTIVITY`（`com.miui.securitycenter`），而这个意图解析不了（`unable to resolve Intent`），所以连“允许打开其他应用”的确认框都没弹 | 能跳，或说清楚 |
| 代码 | `apps/pure_live/lib/features/live_play/buttons/room_menu_button.dart` `openRoomExternally`：原生链接 → 网页，都失败就提示 `open_room_external_failed` | — |
| 3.x | 同样的跳转（`room_external_opener.dart:193-200`）；3.x 在这台手机上是否也被拦，没试（不碰用户的 3.x） | — |

## 方案（待定）

- 先查 HyperOS 的“打开其他应用”权限（应用信息 → 其他权限）对测试包是什么状态，手动放行后再试；如果放行后能跳，就在失败提示里加一句“小米/红米手机：设置 → 应用 → 纯粹直播 → 其他权限 → 打开其他应用”，并加按钮直接打开应用信息页。
- 如果放行后仍不行，看能否用 `Intent.FLAG_ACTIVITY_NEW_TASK` 由原生侧直接 `startActivity`（不经 url_launcher）。

## 验证

- 真机：K90 上放行前后各试一次；装了快手和没装时各试一次。
