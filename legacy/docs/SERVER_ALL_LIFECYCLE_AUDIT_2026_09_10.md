# 全量目录分页的页面退出收尾审计（2026-09-10）

## 范围与根因

审计起点为 aadfa704，版本保持 3.1.8+4121。针对 [ServerAllPageController](../lib/common/base/server_all_page_controller.dart) 及三个生产派生类：分类目录、分类房间、热门列表。没有合并上游、变更发布版本或安装手机应用。

最短复现：启动目录加载，服务 Future 保持未完成；通过 Get 的 onDelete 删除控制器，再完成成功或失败响应。旧实现继续写入缓存、列表、总数和 loading 标志，调用已释放刷新控制器的完成接口，或进入错误呈现。另一条路径在连通性检查返回 false（页面已经关闭）后仍错误地执行 finishRefreshControllers(fail)。

只保护公共父类还不够：

- [分类目录](../lib/modules/areas/areas_list_controller.dart) 在 await 后先修改全局 AreaPicMapper/Hive 图片缓存、分类快照和选中索引，随后才返回父类。
- [分类房间](../lib/modules/area_rooms/area_rooms_controller.dart) 先修改响应行的 area，或把特殊异常写成 notLogin。
- [热门列表](../lib/modules/popular/popular_grid_controller.dart) 在迟到响应后重新读取 SettingsService 并排序。

来源归类为 **upstream-existing**：本地冻结上游 c6c9bd70 与基线 527fea1b 的公共分页实现均具有上述无关闭检查的发布/收尾结构；冻结上游的三个派生实现同样在 await 后执行副作用。分类缓存与房间标签/登录写入还可追溯至 6fcb357a、913a075f、586ca532。当前分支的分类身份恢复没有替代生命周期检查。此次仅本地读取已存在提交，没有 fetch 或同步上游。

## 处理

公共分页在连通性和服务响应返回后检查 isClosed；用临时结果承接服务返回，仅存活页面才能写入快照。关闭页面的 catch/finally 不再呈现错误或更新 Rx 标志。分页、页大小、刷新、加载更多和本地投影入口亦保护关闭状态。

三个派生类分别在异步返回、实际副作用之前检查页面状态；分类房间的特殊错误分支也受保护。正常分类图片持久化、标签更新、登录分类、热门排序与分页策略保留。

这是**结果归属隔离，不是网络取消**。底层 API 仍为普通 Future，没有取消协议；活动 Future 保持可观察，终态时释放 _activeLoad，排队刷新在关闭后不启动第二次请求。未通过提前清空句柄假装请求结束，也未清理其他页面或全局缓存。

## 验证与证据

[新增生命周期测试](../test/server_all_page_lifecycle_test.dart) 使用真实控制器和真实 Get onDelete；直接调用 onClose 不会设置 isClosed，因此不作为退出模拟。只替换原生连通性 IO，保留 BaseController 的实际请求归属检查。错误拦截记录是否调用呈现入口，同时运行真实错误标志逻辑；不在测试宿主中弹出全局 Toast。

- 初始 18 项：1 PASS / 17 FAIL，正常页面正例通过，晚到成功/失败、连通性收尾、关闭后分页及各派生副作用有直接反例。
- 修订后同批 18/18 通过。
- 再补齐存活分类/图片缓存正例、存活房间标签与两种登录错误正例；热门测试直接调用生产 fetch hook，防止父类吞掉晚到错误而掩盖设置访问。最终新增 23 项。
- 与分类真实手势、分类切换/分页、CC 目录、事务刷新、热门观众排序、分类图片合同联合 **8 文件 72/72** 通过。

新增测试区分 mobile/desktop 分页语义，但运行于本机 Flutter 测试宿主；不是 Android 或 Windows 原生验收。分类图片正例检查实际 Hive 内存盒写入，负例检查页面及同一共享缓存均不变化。分类房间负例同时检查返回对象未被晚到路径修改。

证据目录：`local-artifacts/server-all-lifecycle-20260910/`；时间戳日志保留红测、绿测和最终阶段。资源/输入 SHA 记录位于 `local-artifacts/build-records/`。

## 剩余工作与回滚

本批不修改共享 BasePageScrollAndStateBone、ServerFixed/Remote 的行为。相邻分类房间 Fixed/Remote 也存在 await 后标签与登录状态写入，后续需连同各自的请求代次合同复现审计；本批通过不覆盖它们或整个应用生命周期。

后续原生场景：Android 优先，在分类/热门/分类房间加载时退出，再进入其他页；验证不出现旧页提示、旧目录图片覆盖或异常，当前页面继续正常刷新。桌面验证同流程及缓存分页。仍需覆盖真实导航触发的控制器删除时机与长时间网络等待；不以本机用例代替这些证据。

Android 152cf151 与 Windows 2fb471d3 归档保持，本批修订尚未进入候选。保留原 61 场景计划，不把新增代码测试算作原生通过。宏观仍为 20 PASS / 32 RUN / 10 NR，42 组未完成，8 组参考平台未注册，3.2.0 交付条件尚未满足。

回滚只需撤销本批四个生产文件的生命周期检查，无数据库迁移、用户设置变更或二进制补丁。本轮未调用 ADB/MT/LSP；上一轮工具连接预检与本批源码证据分开记录。

## 最终输入与门禁记录

代码提交 **dfab7d4113d9fac8fee7e8c3dba085e251ceab38**。最终八文件 72/72、五个改动文件严格分析 No issues found；记录 `20260909T222701972Z-server-all-lifecycle-final.json`，日志 `20260909T222550389Z-final.log` 和同时间戳 analyze.log。71.454 秒，峰值 CPU 8.86%、工作集 10,815,475,712 B、结束活跃重型进程 0。提交前逐项重算五份输入 SHA，与资源记录一致。

最终测试文件 SHA-256：`42874196B759F3ADF018C29F04236F09331F4F42AD7CD6D5B816510A5FA3B004`。运行时父提交为 aadfa704，记录中的 sourceFiles 对应已格式化后的实际修订输入；通过后的源文件未再修改。

补充全 lib 调用者清单由受守卫保护的 git grep 完成，仅上述三个派生类；`20260909T222808980Z-server-all-inventory.json` 与 callers.txt 留证。初次定位命令传入未展开的 Windows 通配路径，返回路径错误及部分结果；最终清单是纠正路径后的成功结果，不以初次失败输出作完整性证明。
