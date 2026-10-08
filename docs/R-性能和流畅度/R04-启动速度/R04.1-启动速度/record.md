# R04.1 记录：启动速度——阶段 1 的打点和 `reportFullyDrawn`

- 日期：2026-10-08
- 执行者：Claude（本机工作区，分支 `worktree-agent-a181fd89d52eb7f5c`，基于 master `67afa77da`；不推送）
- 任务书：[brief.md](brief.md)；说明：[README.md](README.md)
- 范围：阶段 1“测量”的第 1、2 条（打点代码、`reportFullyDrawn`）。第 3、4 条（K90 上测数字、可选的 v3bench）由维护者在真机上做，见文末“测量计划”。

## 逐条对照

| 条 | 做了没有 | 说明 |
|---|---|---|
| 1 打点 | 做了 | 冷启动时首页第一屏内容出现后写一行 `startup-timing …`，进应用日志（info，标签 `startup`）并 `debugPrint`；温启动（进程还在，Activity 重建后 Dart 重新跑 `main`，或同一进程里 Dart 重启）不写 |
| 2 `reportFullyDrawn` | 做了 | `pure_live/app` 通道加 `reportFullyDrawn`；首页第一屏内容出现时调用一次（规则见下） |
| 3 现状表 | 部分（开启动页的冷启动 10 次，见“现状表”） | 关启动页、温启动和修正后的 `Fully drawn` 待测 |
| 4 v3bench（可选） | 没做（真机） | 见“测量计划” |

### 偏差和原因

1. **日志行比任务书的例子多几个字段。** 任务书的例子从 `binding` 开始；这次加了 `tab`（首页第一个页签）、`content`（第一屏是什么）、`process`（进程启动 → `main`）和 `total`（进程启动 → 首页第一屏）。进程启动时间由原生给（`Process.getStartElapsedRealtime()`），这样不用另外跑 `am start -W` 也能看到 `main` 之前花了多少。`runApp` 之前的字段名和含义和任务书一样。
2. **首页默认的第一个页签是关注，不是热门。** `Settings.savedMenuIds` 的默认值是 `['favorites', 'popular', 'areas', 'record']`（`packages/live_store/lib/src/settings/settings.dart:95-99`），任务书按“热门第一页”写的。所以“首页第一屏内容”按第一个页签分别定义（下一节），`tab=` 写出实际是哪个页签。要量“热门第一页”时在设置里把热门排到第一个。
3. **地区、录制中心、电视界面在首页第一帧时算“可用”。** 任务书的范围只允许改 `features/popular/`，地区页（`features/areas/`）和电视首页（`tv/`）不能加信号；它们在首页第一帧时报告（`content=home`）。地区页的分类是网络请求，之后才出来，这一点数字里不包含；以后要量再开任务。
4. **Kotlin 没有在本机编译。** 这次的要求是不构建安装包、不碰手机；Kotlin 的改动只有通道里两个分支和一个静态标记（见下），维护者构建 profile 包时会编译到。
5. **没写 `tools/perf/startup_timing.py`**（任务书里是“可以新建”）。一行就是 `键=值`，汇总可以先用文末的 `awk`；10 次以上的汇总需要时再加脚本。

## “首页第一屏内容”的规则（`reportFullyDrawn` 和 `firstPage`）

每个 `main` 只算第一次（`StartupTiming.firstContent`，`apps/pure_live/lib/app/startup.dart:310`），之后再刷新、换页签、换平台都不再调用：

| 首页第一个页签 | 什么时候算 | `content=` |
|---|---|---|
| 热门（`popular`） | 当前平台的第一批房间画出来的那一帧之后（第一块数据到了就算，不等整页）；第一次请求失败时是错误状态画出来，平台回答了但没有房间时是空状态，平台列表为空时是“没有平台”的空页 | `rooms`、`error`、`empty` |
| 关注（`favorites`） | 本地存的关注读出来、画出来之后（之后的“第一次检查开播状态”是网络，不等） | `rooms`，没有关注或读取失败时 `empty` |
| 地区（`areas`）、录制中心（`record`） | 首页第一帧 | `home` |
| 电视界面（`tab=tv`） | 首页第一帧 | `home` |

- 开着启动页时：首页的路由在启动页离开（`AppNavigator.offAllNamed(RoutePath.kInitial)`）后才建，热门的请求也是那时才发，所以内容一定在启动页离开之后；关注在启动页期间已经读好，首页第一帧就算。
- 关着启动页时：首页是第一个路由，第一帧就是首页。
- 规则写在 `StartupTiming` 的文档注释里（`apps/pure_live/lib/app/startup.dart:222-243`），热门的部分在 `popular_page.dart:158-173`、`:255-280`，首页部分在 `app.dart:111-154`。
- 启动失败（显示失败原因页、点重试）的那次不写日志行（数字里含失败页和重试），但首页出来时仍然 `reportFullyDrawn`。
- 没有 Activity 的引擎（例如媒体服务先起了引擎）问不到原生：算温启动，不写日志行。

## 日志行

```text
startup-timing cold=true splash=on tab=popular content=rooms process=180 binding=12 imageCache=1 tvDetect=8 dataRoot=3 store=45 legacy=6 wire=30 log=4 strings=20 fonts=2 desktop=0 runApp=131 firstFrame=260 home=1420 firstPage=1980 total=2160
```

| 字段 | 含义（毫秒） | 记在哪 |
|---|---|---|
| `cold` | 只有冷启动才写，所以总是 `true` | 原生 `startupInfo` |
| `splash` | 启动页开（`on`）还是关（`off`） | `main.dart:50-52` |
| `tab`、`content` | 见上一节 | `firstContent` 的参数 |
| `process` | 进程启动 → `main` 入口：原生量的进程年龄减去这次通道调用的中点（误差最多是调用时间的一半） | `startup.dart:183`（`processToMainMs`）、`:338`（`askAndroidProcess`） |
| `binding` … `desktop` | 这一步自己的耗时：`binding`（`main` 到 `ensureInitialized`）、`imageCache`、`tvDetect`、`dataRoot`（命令行、数据目录、加密）、`store`（`LiveStore.open`）、`legacy`（3.x 导入，副窗口为 0）、`wire`、`log`（插件钩子、日志文件）、`strings`、`fonts`、`desktop` | `bootstrap.dart:248-284`、`main.dart:97-131` |
| `runApp` … `firstPage` | 从 `main` 入口起的累计时间：调用 `runApp`、第一帧光栅化完（开启动页时是启动页的第一帧）、首页第一帧、首页第一屏内容 | `main.dart:52`、`:63-65`、`app.dart:136-139`、`startup.dart:313` |
| `total` | 进程启动 → 首页第一屏内容（`process + firstPage`），和 logcat 的 `Fully drawn` 应该接近 | 同上 |

量不到的字段写 `-`（例如电脑上没有 `process`）。

## 改了哪些文件

- `apps/pure_live/lib/app/startup.dart`：`startupSteps`、`startupMarks`（`:153`、`:171`）、`StartupProcess`、`processToMainMs`、`formatStartupTiming`（`:178-221`）、`StartupTiming`（`:244`：`begin`、`step`、`mark`、`askProcess`、`abandon`、`firstContent`、`askAndroidProcess`）、`followsFirstContent`（`:373`）。
- `apps/pure_live/lib/main.dart`：`main` 第一行 `StartupTiming.begin()`（`:26`）；`_launch` 失败时 `abandon`（`:46`）、`splash` 和 `runApp`（`:50-52`）、第一帧（`:63-65`）；`_finish` 的 `log`、`strings`、`fonts`、`desktop`（`:105`、`:112`、`:121`、`:131`）。
- `apps/pure_live/lib/app/bootstrap.dart`：`AppBootstrap.start` 的 `binding`（同时问原生）到 `wire`（`:250-284`）。
- `apps/pure_live/lib/app/app.dart`：`_watchHome`、`_homeShown`（`:111-154`）：路由到了首页记 `home`，按第一个页签报告（热门由热门页自己报）。
- `apps/pure_live/lib/features/popular/popular_page.dart`：首页里的热门页第一次加载时等第一屏内容（`:104`、`:146`、`:158-173`），`popularContentOf`、`popularFirstContent`（`:258`、`:267`）。
- `apps/pure_live/android/app/src/main/kotlin/com/mystyle/purelive/MainActivity.kt`：`pure_live/app` 通道加 `startupInfo`（`cold`：进程里第一次问时为真，静态 `AtomicBoolean` `coldStartTaken`，`:107`；`sinceProcessStart`：`SystemClock.elapsedRealtime() - Process.getStartElapsedRealtime()`）和 `reportFullyDrawn`（`:266-275`）。
- 测试：`apps/pure_live/test/startup_timing_test.dart`（新）、`apps/pure_live/test/features/popular/popular_test.dart`（加 1 个）。
- 文档：本记录；`docs/tasks.toml`（R04.1 开发中，`done = 1`）。

行为不变：启动页的停留和样子、3.x 导入、语言、字体、启动失败页的代码都没动；打点只是读时钟、记数字。问原生的调用不等（`askProcess` 不 `await`），第一帧前只多了一次异步的通道消息。

## 新设置、翻译键、门禁基线

- 没有。

## 测试

新增 11 个，全部通过：

- `test/startup_timing_test.dart`（10 个，假时钟、假原生）：
  - `startup timing writes one line with every mark`：一行、字段齐全且按顺序、步骤非负、累计值递增、`process` 和 `total`；
  - `home first content counts once: one line, fully drawn reported once`：再调用（刷新、换页签）不再写、不再报；
  - `a warm start (not the process's first main) reports fully drawn but writes no line`；
  - `a failed launch (the failure page and a retry) writes no line`；
  - `a step or mark recorded again keeps its first time; Android is asked when nobody asked`；
  - `a failing fully-drawn call still writes the line`；
  - `formatStartupTiming: order, missing values as -, total from the process start`；
  - `processToMainMs: the process age less the middle of the call, never below zero`；
  - `home follows as home: drawn once the stored follows show`（整个应用，关注是首页）；
  - `home with the splash page on, home reports only after the splash page leaves`（启动页 0.9 秒时没报，离开后报一次）。
- `test/features/popular/popular_test.dart`：`R04.1: home reports fully drawn once, when the first rooms show; a refresh does not again`（假平台先卡住：首页出来、请求发出但房间没到时没报；房间到了报一次、写一行 `tab=popular content=rooms`；点“刷新”再来一遍不再报）。
- `bash tools/gate/gate.sh --all`：通过（`gate: passed`）。

## 真机上怎么看数字（K90）

```bash
adb -s 192.168.1.2:5555 logcat -c
adb -s 192.168.1.2:5555 logcat | grep -E "startup-timing|Fully drawn|Displayed"
# 另一个窗口，冷启动一次：
adb -s 192.168.1.2:5555 shell am force-stop com.mystyle.purelive.v4dev
adb -s 192.168.1.2:5555 shell am start -W -n com.mystyle.purelive.v4dev/com.mystyle.purelive.MainActivity
```

- `am start -W` 的 `TotalTime`：点图标（启动意图）到第一帧（系统启动画面换成应用的第一帧）。
- logcat 的 `ActivityTaskManager: Displayed …: +XXXms`：同上，系统记的第一帧。
- logcat 的 `Fully drawn com.mystyle.purelive.v4dev/com.mystyle.purelive.MainActivity: +XXXms`：启动意图到首页第一屏内容（我们调用 `reportFullyDrawn` 后的那一帧）。
- `startup-timing` 行（logcat 里是 `flutter` 标签的 `I/flutter`；应用的“日志”页也有，标签 `startup`）：`process` 是进程启动到 `main`，`runApp` 之前每一步的耗时，之后是从 `main` 起的累计；`total` 应该略小于 `Fully drawn`（`Fully drawn` 还含进程启动前系统的准备和最后一帧）。
- 温启动（返回键退到后台再 `am start -W`）：应用把自己移到后台而不是关掉 Activity，引擎也是缓存的，`main` 不会再跑，所以没有 `startup-timing` 行，也没有 `Fully drawn`，只有 `TotalTime`。

## 测量计划（阶段 1 第 3、4 条，维护者在 K90 上做）

1. 构建 profile 包（`com.mystyle.purelive.v4dev`，这个分支合并后的提交），装到 K90；设置里把热门排到首页第一个（量任务书说的“热门第一页”）；Wi-Fi、亮度 50%、开机 10 分钟以上、不充电、关后台应用；记电量、温度（`adb shell dumpsys battery`）。
2. 冷启动、开启动页（默认）10 次：每次 `am force-stop` → `am start -W`，等首页房间出来再下一次；记 `TotalTime`、`Displayed`、`Fully drawn`、`startup-timing`。
3. 设置里关掉启动页，重复第 2 步；`Fully drawn` 应该比开着时少约 1 秒。
4. 温启动 10 次（返回键退到后台 → `am start -W`），开 / 关启动页各一组：只记 `TotalTime`，确认没有 `startup-timing` 行。
5. 首页第一个页签改回关注（默认），冷启动开启动页再测 10 次（`tab=favorites`），看默认设置下的数字。
6. 汇总：每组 `TotalTime`、`Fully drawn` 的中位数和 P90，`startup-timing` 各字段的中位数，写进本记录的“现状表”；找出 ≥50 毫秒、能并行或挪到第一帧后的步骤，作为阶段 2 的依据。字段中位数可以这样算（`log.txt` 是抓下来的 logcat）：

   ```bash
   grep -o 'startup-timing.*' log.txt | tr ' ' '\n' | grep '=' | awk -F= '$2 ~ /^[0-9]+$/ {v[$1]=v[$1]" "$2} END {for (k in v) print k, v[k]}' | while read k rest; do echo "$k $(echo $rest | tr ' ' '\n' | sort -n | awk '{a[NR]=$1} END {print a[int((NR+1)/2)]}')"; done
   ```

7. （可选，第 4 条）v3bench 包：任务书“3.x 基线”的做法，冷启动、温启动各 10 次只有 `TotalTime`（3.x 没有 `Fully drawn`，首页出现用录屏数帧）；测完卸载。做不了写原因。
8. 第 6 步之后再看 `firstFrame`：开启动页时它是启动页的第一帧，关启动页时是首页的第一帧；阶段 2 的目标“`main` → 第一帧少 20%”用关启动页的那组。

## 现状表（K90，2026-10-08）

设备：Redmi K90 Pro Max，开机约 106 小时，电量 80%，电池 33 ℃；profile 包（提交 `9569981c7`），首页第一个标签是“关注”（2 个在播），开启动页。命令：`am force-stop` 后隔 3 秒 `am start -W`，等 9 秒读日志，连续 10 次。

| 项 | 中位数 | P90 |
|---|---:|---:|
| `TotalTime`（am start -W） | 367 ms | 383 ms |
| process（进程启动 → `main`） | 238 ms | 261 ms |
| tvDetect | 21 ms | 22 ms |
| store | 17 ms | 19 ms |
| strings | 13 ms | 15 ms |
| legacy | 2 ms | 2 ms |
| binding、imageCache、dataRoot、wire、log、fonts、desktop | 0 ms | 0 ms |
| runApp（`main` 起累计） | 56 ms | 58 ms |
| firstFrame（`main` 起累计） | 74 ms | 78 ms |
| home = firstPage（`main` 起累计，关注从本地读出） | 1087 ms | 1091 ms |
| total（进程启动 → 首页第一屏） | 1322 ms | 1349 ms |

看法：

- `main` 到第一帧只有约 74 ms，各步都不到 25 ms，没有“单段 ≥50 毫秒”的 Dart 步骤；进程启动到 `main` 的约 238 ms 是 Flutter 引擎和 Dart VM 的启动，应用代码改不到。
- 第一帧到首页的约 1 秒是启动页停留（A06.4 定的 1 秒，不在本任务范围）。
- **`Fully drawn` 原来不准**：日志里 `Fully drawn … +360ms` 和 `TotalTime` 一样，而首页约 1.3 秒才出现。原因：`FlutterActivity.onFlutterUiDisplayed()` 在 API 29 以上第一帧就调 `reportFullyDrawn()`（Flutter 3.47.6 `FlutterActivity.java:1443-1453`），Android 一次启动只记第一次，我们在首页内容出现时的上报被忽略。已在 `MainActivity.kt` 把 `onFlutterUiDisplayed` 覆盖成空，只留应用自己的上报；装新包后重测。
- 原始数据：10 行 `startup-timing` 都是 `cold=true splash=on tab=favorites content=rooms`。

## 停在哪

- 做完的：阶段 1 的代码（第 1、2 条），测试和门禁通过；没有推送、没有合并。
- 下一步：合并后在 K90 上按上面的测量计划测，填现状表（阶段 1 第 3 条，第 4 条可选），然后按数字决定阶段 2 做哪些。
- 要维护者决定的：地区页首页时要不要也等分类出来（需要改 `features/areas/`，不在本任务范围）；量的时候首页第一个页签用热门还是默认的关注（建议两组都量）。
