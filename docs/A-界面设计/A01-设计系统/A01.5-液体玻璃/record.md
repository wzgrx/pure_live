# A01.5 记录

## 2026-10-14

- c1～c5 做完，见 README 的代码表。
- 胶囊高 68：`NavigationBar` 在 64 时 1.3 倍字号下标签贴边，68 留出余量；68 + 12 = 80，和原来底栏高度一样，小窗的避让距离不用改。
- 测试：`home_test.dart` “A01.5: liquid glass …”（胶囊位置、页面延伸到底、`GlassBarInset` 80、1.3 倍字号不溢出、宽屏没有玻璃、关掉恢复原样）；`live_ui` `widgets_test.dart`（模糊和不模糊两种、`withGlassBar`）；`image_cache_budget_test.dart`（`liquidGlassBlurs`）；`settings_defaults_test.dart`（`liquidGlass` 默认关）。
- K90 快速测试（profile 包）：第一次装上胶囊有两倍高、图标挤在下半截。根因：`MediaQuery.removePadding` 用的是 `HomeMobileView` 自己的 context（在 Scaffold 外面），只去掉了底部，状态栏的顶部留白还在，`NavigationBar` 里的 `SafeArea` 把它加到了胶囊顶上；测试里状态栏高度是 0，所以没发现。改成同时去掉顶部，测试加上 40 的状态栏和 20 的手势区。重装后胶囊高度正确，贴着手势区上方，后面的封面和文字模糊透出来。
- 小窗弹簧（A03.4）在同一个包里顺手看了：把全宽小窗往上甩，松手 0.15 秒时离停下的位置只差约 8 像素，到顶停住、不回弹。
- 待做：c6 用 DevTools 看开关前后滑热门的帧时间（这次只做了轻量真机测试）。
