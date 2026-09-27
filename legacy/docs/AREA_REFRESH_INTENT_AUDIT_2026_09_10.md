# 分类刷新中的点击意图与刷新提示归属（2026-09-10）

代码提交 **f242428e8a30a2e87b2b3acefc67776e368ec03f**，父提交 8fe3033370e12da21f4126a466b4dd45e1151d75。

## 根因与修订

承接[空页失败恢复](RETAINED_PAGE_RECOVERY_AUDIT_2026_09_10.md)，本轮检查实际刷新返回与用户选中之间的时序。

1. **点击尚在动画中，目录返回后回到旧分类。** 测试点击 Last，40 ms 时确认 TabController 仍在动画中；此时返回重排目录，结果却选中 First。TabBar 原来只经动画完成监听提交业务选择，目录恢复逻辑读取的是旧业务索引。现在显式点击通过 onTap 立即提交选择；未结束的横向拖动仍按原监听等待手势稳定，不改动画时长。
2. **本地切分类提前结束正在进行的下拉刷新。** 真实拖动启动第二次目录请求并保持响应等待，切换缓存分类后 Header 从 processing 变为 processed，而请求仍未返回。现在本地投影在已有加载任务时只发布缓存切片，不调用该任务的 finishRefresh/finishLoad；实际响应仍按原流程完成提示。
3. **连通性检查也属于活动加载。** ServerAllPageController 增加只读 hasActiveLoad，读取既有活动 Future；它包含 loadding 尚未置 true 的连通性等待阶段。没有用可见 loading 标志代替真实任务归属，也没有新增请求、重试、延时或锁。

生产改动限 areas_grid_view.dart、areas_list_controller.dart 和 server_all_page_controller.dart。processLocalPaging 默认仍完成刷新；仅 selectCategory 在已有活动加载时显式关闭本地投影的完成动作。抖音平铺入口、数据切片、页大小、分类 ID 恢复算法、页面资源释放及持久化格式保持。

来源是本分支组合的 **fork-regression**：8a1d3a52 的本地 selectCategory 调用原本会完成刷新；59417f12 已按返回时业务选择恢复分类身份，但界面的点击意图直到动画结束才写入该选择。继承的 TabBar 入口和本分支异步/本地投影语义未完整衔接。本轮未查询或合并上游。

## 实际验证

在[分类真实手势测试](../test/area_tab_refresh_test.dart)中新增 6 项：

| 覆盖 | 数量 | 关键证据 |
| --- | ---: | --- |
| 400/900 宽度，点击后目录重排 | 2 | 响应在 40 ms、动画尚未完成时返回；最终仍为 Last，显示 Last 两项数据，仅两次目录请求 |
| 400/900 宽度，被点击分类从新目录删除 | 2 | 按既有规则回退新目录首项 Replacement，而不是保留用户已离开的旧 First；数量变化后索引和切片有效 |
| 实际下拉正在等待目录响应 | 1 | 切缓存空分类不完成 Header；请求完成后 Header 恢复 inactive |
| 实际下拉正在等待连通性检查 | 1 | 此时 loadding=false、服务尚未收到新请求，但活动 Future 和 Header 仍属当前刷新；切分类不提前完成，检查/请求完成后正常结束 |

保留此前 13 项分类导航、目录替换/释放、失败恢复与真实重试测试。Fixture 只固定服务响应、连通性和 Future 完成时机；UI、分类控制器和 EasyRefresh 状态来自实际组件，不把直接调用 onRefresh 当作手势证据。

第一轮红测中两种宽度均期望 Last、实际 First。刷新提示用例初稿在释放手势后只推进一帧，尚未真正启动第二次请求；改用有上限的逐帧推进等待服务收到请求后，得到明确的 processing→processed 提前完成复现。此同步只在测试中执行，不是生产等待或额外请求。修订后 17/17 通过，再加入删除目标分类的两种宽度边界进入最终相邻回归。

证据根：`local-artifacts/area-refresh-intent-20260910/`，失败和通过日志均保留时间戳。首轮因其他 Java 重型任务排队，等待既有进程完成，未中断或重启任何其他任务。

## 边界与回滚

没有修改共用 BasePageView、搜索或关注实现，所以本轮门禁聚焦分类 UI、分类切换/分页与 CC 分类控制器，而不重复未变化的上一轮 197 项套件。单个旧断言通过不替代本批新时序证据。

未操作手机/ADB/Root/LSP/MT、未构建或发布。Android f5aab636 与 Windows 2fb471d3 尚未包含最近分类/失败恢复/本批修订，原归档保持。撤销本批三个生产文件即可回退行为，无用户数据迁移。

仍需 Android 与 Windows 原生交互、未完成拖动与目录变化的其他时序、大字号卡片及全平台播放/录制验收。宏观仍 20 PASS / 32 RUN / 10 NR（42 组未闭环），8 组参考平台未注册；没有提前发布 3.2.0。

## 最终门禁

**四文件联合 34/34、四个改动文件严格分析 No issues found**。最终资源记录 `20260909T220348420Z-area-intent-final.json` 为 passed；测试日志 `20260909T220238777Z-final.log`、分析日志 `20260909T220238777Z-analyze.log`。19 项真实分类 Widget 场景与 15 项相邻控制器合同均通过；不是全项目测试总数。

提交前核对最终输入 SHA：

- area_tab_refresh_test.dart：`C1F17FBDBA42990DCCB510F2EDE7CE2321CBC86964930E17717360798D2622AB`
- areas_grid_view.dart：`5EC204B4540C7AF34B253ACEB5CFF94DDB6EA9F5C27F9DC77C5EFA7184B1938B`
- areas_list_controller.dart：`01DB549816806E2199EEDB9FC54CCDB2F743E15168F6D624A4EDED0CE280BED7`
- server_all_page_controller.dart：`FD611752A6E4CE7FB698AB1C0E58AE05307B99A47C8038DC8E8AEE8644085DC8`

最终轮 69.542 秒，峰值 CPU 9.0%、工作集 10,604,650,496 B，结束活跃重型进程 0。通过资源守卫串行执行并保留缓存；记录 sourceCommit 为运行时父提交，sourceFiles 证明修订输入。仍按[剩余验收](ACCEPTANCE_STATUS_3_2_0.md)推进全目标。
