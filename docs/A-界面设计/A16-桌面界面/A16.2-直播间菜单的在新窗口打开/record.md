# A16.2 直播间菜单的“在新窗口打开”：记录

## 2026-10-08

### 逐条对照（brief“目标和验收”）

| 条 | 做了没有 | 说明 |
|---|---|---|
| 1 跟桌面外壳和设置走 | 做了 | `roomMenuGroups` 的 `windows` 改名 `newWindow`；`RoomMenuButton` 不再收 `windows`，打开菜单时用 `DesktopWindow.offersNewWindow(settings)` 算（`room_menu_button.dart`）；`RoomHeader` 的 `windows` 字段、`live_play_page.dart` 和 `player_controls.dart` 的传参、`PlayerPlatform.windows` 都删了（没有别的用处） |
| 2 文字和图标 | 做了 | 加回 `open_in_new_window`“在新窗口打开” / “Open in new window”；图标 `AppIcons.newWindow`，A01.3 已经把它改成首页菜单 `newPlayerWindow` 的同一个字形（`add_to_photos_outlined`），所以没换名字（换成 `newPlayerWindow` 会让 `newWindow` 没人用，门禁第 4 条不过）；位置不变 |
| 3 点了开新窗口 | 做了 | 调 `DesktopWindow.openNewWindow(room: room)`，失败提示由它给一次，菜单不再重复提示 |
| 4 删 `launchNewWindow` | 做了 | `app/launch_args.dart` 删掉；全仓库只有菜单调用过；`startWindowProcess` 不变 |
| 5 Android、电视没有这一项 | 做了 | 没有桌面外壳时 `newWindowLauncher` 是 null，`offersNewWindow` 为假 |
| 6 测试、门禁 | 做了 | 见下 |

- `open_room_in_new_window` 现在没人用，按 D-024 不删，加进 `test/i18n_runtime_keys.dart` 的 `keptUnusedKeys`（Z05.1 的“不用的键”多了这一个）。

### 测试

- `live_play_popups_test.dart`“room menu: the new window follows the desktop shell and the setting (A16.1 c12, A16.2)”：有启动器时菜单有“在新窗口打开”、图标和首页菜单同一个、在“在哔哩哔哩打开”后面；点了用这个直播间开新窗口；关掉“新建独立播放窗口”后再开菜单没有这一项。改之前编译不过（`roomMenuGroups` 没有 `newWindow`），旧行为下也会失败（菜单看的是 `TargetPlatform.windows`）。
- `live_play_popups_test.dart`、`room_switch_test.dart` 里 `roomMenuGroups` 的参数名改了，期望不变。

## 真机上要看的

- K90：进一个直播间，点右上角四宫格（竖屏应用栏和横屏全屏控制层各一次）：没有“在新窗口打开”，其他项和分组不变。
- Windows 的 2～4 步归 X01.1。
