# R04.1 启动速度：冷启动到首页可用的时间测量和优化

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：性能
- 来源：[specs/UI.md](../../../specs/UI.md) 第 9.4 节“冷启动到首帧：中端机不超过 v3 的 60%”；PLAN 第二档“K90 上跑基准、启动速度”；2026-10-02 文档整理时登记（旧编号 T14e.1）
- 旧编号：T14e.1
- 相关：启动页 A06.4（停 1 秒、可跳过）；3.x 数据迁移 J06；起播速度 [G03.1](../../../G-播放/G03-起播速度和弱网/G03.1-起播速度和弱网/README.md)（同一套打点和 3.x 对比包的思路）；任务书 [brief.md](brief.md)

## 目标

- 有数字：K90 上冷启动和温启动时，从点图标到第一帧、到首页出现、到首页第一页房间可用，各花多少；第一帧前每一步各花多少。
- 变快：按数字把第一帧前能并行的并行、能挪到第一帧后的挪走，第一帧时间比改之前少；能测到 3.x 时做到“不超过 v3 的 60%”（specs/UI.md 9.4）。
- 系统也能量：首页第一页房间出现时调用 `reportFullyDrawn`，`am start -W` 和 logcat 的“Fully drawn”能直接给出“首页可用”的时间。
- 用户感觉到的：点图标后更快看到首页和房间。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11`，文件:行） | 现在（文件:行） | 要做到 |
|---|---|---|---|
| 第一帧前做的事 | `lib/common/global/initialized.dart:51` 起的 `AppInitializer.initialize`：Hive、设置迁移、GetX 服务注册、代理、图片缓存管理器、FFmpeg 预热、`MobileManager` | `apps/pure_live/lib/app/bootstrap.dart:98-137`（图片缓存、电视检测、数据目录、打开数据库、3.x 导入的指纹检查、网络电视导入、`wire`）和 `main.dart:83-114`（日志、语言、字体、桌面窗口），都是顺序 `await` | 打点后决定并行或挪后 |
| 第一帧后做的事 | 启动页里等 | `app/startup.dart:69-91` 的 `AppStartup.start`（关注第一次检查、封面刷新、本地网络权限、哔哩哔哩登录检查 1 秒后） | 不变 |
| 启动页 | 停 1 秒，2 秒淡入 | `features/splash/splash_page.dart:33`：停 1 秒（0.4 秒淡入），离开前最多等关注检查 350 毫秒（`startup.dart:21`） | 行为不改（A06.4）；数字分开报“开 / 关启动页” |
| 首页可用的信号 | 没有 | 没有 `reportFullyDrawn` | 首页第一页房间出现时调用 |
| 测量 | 没有 | 没有 | 打点 + `am start -W` + logcat |

## 方案

- c1 打点：Dart 侧在 `main` 入口、`ensureInitialized` 后、`LiveStore.open` 前后、3.x 导入前后、`wire` 前后、`_finish` 各步前后、`runApp`、第一帧（`WidgetsBinding.instance.waitUntilFirstFrameRasterized`）、首页出现、热门第一页房间出现各记一个时间点（`Stopwatch` 从 `main` 入口起算），首页可用时写一行 `startup-timing main=0 binding=… store=… legacy=… wire=… strings=… fonts=… runApp=… firstFrame=… home=… firstPage=…` 进应用日志（info）并 `debugPrint`。
- c2 `reportFullyDrawn`：热门第一页房间出现（或启动页关闭时首页第一帧）时，经 `pure_live/app` 通道调用 Activity 的 `reportFullyDrawn()`（只调一次）。
- c3 K90 测量：冷启动（`am force-stop` 后 `am start -W`）和温启动（返回键退到后台后再 `am start -W`）各 10 次 × 开 / 关启动页；记 `TotalTime`、logcat 的 `Displayed` 和 `Fully drawn`、`startup-timing` 行。可选：v3bench 包同样测。
- c4 按数字改（候选，只做阶段 1 证明值得的）：电视检测和打开数据库并行；3.x 导入、网络电视导入挪到第一帧后（导入完成前首页的数据怎么办要写清：3.x 导入只在第一次启动有实际工作，以后只是 `stat`）；语言和字体并行；`AppLog.attach` 不等文件打开；`wire` 里同步建的东西改成用到时才建（例如录制器、平台适配器）。
- c5 同样的矩阵再测一遍，改前改后对比。

## 性能任务：测量

| 指标 | 改之前 | 目标或结果 | 怎么测 |
|---|---|---|---|
| 冷启动 `TotalTime`（到第一帧） | 待测 | 比改之前少；有 3.x 数字时 ≤3.x 的 60% | `adb shell am start -W`，10 次中位数 |
| 冷启动 `main` → 第一帧（Dart 打点） | 待测 | 比改之前少 20% 以上（以阶段 1 的数字为准再定） | `startup-timing` |
| 冷启动到首页可用（关启动页） | 待测 | 记录；Wi-Fi 下 ≤2 秒（含热门第一页网络请求） | logcat 的 `Fully drawn` |
| 冷启动到首页可用（开启动页，默认） | 待测 | 记录（≥1 秒的启动页停留是设计行为） | 同上 |
| 温启动 `TotalTime` | 待测 | 记录 | `am start -W` |

## 验证

- 自动测试：打点（单元测试断言各点只记一次、顺序对、首页可用时写一行）；`reportFullyDrawn` 只调一次（假通道）；阶段 2 每个顺序改动的测试（见任务书）。
- 真机：任务书的测量矩阵；结果和改前改后对比写进 `record.md`。

## 留下的问题

- 启动页“首页准备好就离开、不固定 1 秒”是行为变化，归 A06.4，需要维护者或用户决定。
- Windows 的启动（单实例、窗口恢复）在 X01。
