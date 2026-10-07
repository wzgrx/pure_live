# R01.1 基准测试和渲染开销：真机验证

- 设备：Redmi K90 Pro Max（Android 17，120 Hz，`192.168.1.2:5555`）
- 构建：
  - 第 1 部分（基准）：合并后的 master（包含合并提交 `2ec6f598e` 的任一提交），`flutter drive --profile` 现场构建的基准包，会装成 `com.mystyle.purelive.v4dev` 并覆盖手机上现有的测试包；
  - 第 2 部分（手动看）：同一提交的 debug 或 profile 测试包（`com.mystyle.purelive.v4dev`），基准跑完后重新装回。
- 日期：YYYY-MM-DD；验证人：……
- 准备：屏幕常亮、解锁、竖屏；跑基准期间不碰手机；`source ~/tools/purelive-env.sh`、`adb connect 192.168.1.2:5555`。不碰正式包 `com.mystyle.purelive` 和 3.x。截图放本文件夹的 `verify/`。

## 第 1 部分：跑基准（约 5 分钟）

```bash
cd apps/pure_live
flutter drive --profile -d 192.168.1.2:5555 \
  --driver=integration_test/perf_driver.dart \
  --target=integration_test/perf_test.dart \
  --dart-define=PERF_HZ=120
```

| 步骤 | 期望 | 结果 | 截图 |
|---|---|---|---|
| 1. 运行上面的命令 | 7 个测试通过；控制台 9 行（`hot_scroll`、`danmaku_50`、`danmaku_200`、`multiview_4`、`settings_scroll`、`room_enter_exit_20`、`cover_corners_clipOverFade`、`cover_corners_clip`、`cover_corners_decoration`），每行有帧数、build/raster 的 P90 和 P99、卡顿率、最长连续卡顿、PASS/FAIL；`apps/pure_live/build/perf/perf-<时间>.json` 生成 | | |
| 2. 打开 JSON 的 `device` | 刷新率 120、内存约等于 K90 的实际内存（读到了 `MemTotal`）、图片缓存上限 320 张 / 128 MiB | | |
| 3. 看 `hot_scroll`、`settings_scroll` | build、raster 的 P90 ≤8.33 毫秒，P99 ≤12.5 毫秒，卡顿 <1%，没有连续两帧卡顿（PASS） | | |
| 4. 看 `danmaku_50`、`danmaku_200`、`multiview_4` | 同上，raster P90 ≤5.0 毫秒；`danmaku_200` 的 build P90 ≤3 毫秒 | | |
| 5. 看 `room_enter_exit_20` 的 `extra.residentMiB` | 20 次退出后的常驻内存不是一直往上涨（允许前几次预热上升，之后平稳） | | |
| 6. 比较 `cover_corners_clipOverFade` 和 `cover_corners_decoration` 的 raster P90 | 记下差值（R01.2 用：>0.5 毫秒才改封面圆角） | | |
| 7. 把控制台的 9 行和第 5、6 步的数字追加到 [record.md](record.md) 末尾 | 有 | | |

## 第 2 部分：手动看

先重新装回平时的测试包（基准包覆盖了它）。开发者选项打开“显示刷新率”。

| 步骤 | 期望 | 结果 | 截图 |
|---|---|---|---|
| 8. 设置里打开“退出小窗播放”→ 进任一直播间 → 返回首页，右下角出现小窗 → 按住小窗拖来拖去 | 拖动时画面和松手时一样亮，不透出后面的页面；松手后停在原地；阴影不变 | | |
| 9. “加载样式”选默认 → 进一个直播间，看画面中央的加载转圈；回首页下拉刷新热门，看下拉头 | 仍是带渐变尾巴的圆环、每秒一圈、颜色跟主题，外观和以前一样 | | |
| 10. 热门 → 下拉刷新 | 下拉头转圈、顶部细进度条在走，刷新完都消失；列表尾不跟着转（列表很短、列表尾在屏幕上时也不转） | | |
| 11. 热门快速滑到底 | 列表尾转圈 + 顶部细进度条；新房间出来后都消失；停下 2 秒后右上角刷新率回落（“均衡”档时） | | |
| 12. （可选，D2）热门页快速来回滑 2 分钟，每 30 秒 `adb shell dumpsys meminfo com.mystyle.purelive.v4dev`，记 TOTAL PSS | 预热后不再增长 | | |

## 结论

- 通过：登记表 `docs/tasks.toml` 的 R01.1 改成“完成”，写日期；运行 `python3 tools/docs/docs.py`。第 6 步的数字交给 R01.2。
- 不通过：写现象和根因线索。基准某场景 FAIL：先看是 build 还是 raster 超、哪几帧最慢（JSON 的 `max`），开新任务（滚动在 A03、弹幕在 D04、多画面在 N01）；手动看的第 8～11 步不过：退回 `floating_window.dart`、`loading_styles.dart`、`room_grid.dart` 的改动。
- 顺便请维护者对记录“需要维护者决定的”四条表态。
