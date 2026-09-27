# 屏蔽管理布局与删除身份审计（2026-09-09）

实现提交 `3937b2523417ef5d580125f1842f1f614160d9e2`。

## 范围与根因

基线 `86d7b265cccf4274d38f5d1efccfbc7a866de8e9`；覆盖设置路由 `RoutePath.kSettingsDanmuShield` 的旧管理页，以及 `DanmakuTabView` 实际构造的 `KeywordBlockPage`。三个根因均在冻结上游 `c6c9bd70aedc503c003110dae10a83ad0bb891d8` 的对应文件中存在，归类 **upstream-existing**，没有同步或合并上游。

| 根因 | 旧状态与有效红测 | 修订 |
| --- | --- | --- |
| 旧页长关键词无水平约束 | Wrap 内紧凑 Row 的普通 Text 按全文宽度布局；en/zh、320/900 宽和 1/2 倍字体四场景向右溢出 1639/3487/1453/2907 像素 | Text 使用 Flexible，在可用宽度内全文折行，短词保持紧凑，不缩小字号或省略全文 |
| 直播页相似度标题和值竞争宽度 | Row 中两块文本都无弹性；en 320/2 的三个标题溢出，zh 同配置也发生溢出 | 全宽 Wrap 允许标签和值分行，保留实际字号、滑条范围及设置字段 |
| 删除回调保留旧索引 | 渲染 keep/selected 后，在下一帧前插入 inserted；点击旧 selected 回调却删除 keep；旧关键词、新关键词和屏蔽用户三路径均复现 | 捕获渲染值，点击时查当前列表索引；已移除目标由原存储 API 的越界检查处理为空操作 |

索引时序由确定性偏好更新模拟，不声明实机发生频率。共享 `FavoriteRoomController` 的存储接口、trim/去重规则及 schema 均未修改；两个管理页仍保留各自路由和能力，未机械合并。控制器 remove 的唯一生产调用者是旧页，已随签名一起修订。

## 验证层次

- 有效红测 `20260908T224414464Z-shield-management-red.json`：11 项中 **2 通过 / 9 失败**，无超时；三份生产源码与基线哈希相同。306.431 秒含等待，峰值 CPU 23.65%、Working Set 14,288,674,816 B；结束守卫观察到 1 个活跃重型进程，未终止其他任务。
- 首次扩展绿测 `20260908T225541056Z-shield-management-green.json`：**43 通过 / 1 失败**。原九项红断言均通过；唯一失败在新增夹具使用 `find.byType(Switch).at(1)`，窄屏懒构建时第二个开关尚未进入树，查找先发生 RangeError。原日志、测试副本、哈希保存在 green-v1 文件，不计产品缺陷；264.481 秒，结束活跃重型进程 0，尚未执行 analyze。
- 夹具修订：先滚动至实际相似度标签，再在该标签所在 Row 找 Switch；没有为测试修改生产代码或放宽原断言。
- 最终 `20260908T230501866Z-shield-management-green.json`：四文件测试 **44/44**、四份改动 Dart 文件 analyze 均通过，终端退出 0。496.170 秒含等待与分析，峰值 CPU 59.68%、Working Set 16,209,133,568 B、9 个进程，结束活跃重型进程 0。没有重复启动仍运行的测试或停止其他任务。

新增 `test/shield_management_page_test.dart` 共 15 项：四组完整长词布局/删除，两组实际双语滑条标题布局，三种列表插入后的目标身份，三种目标已移除后保护相邻项，两种页面的 trim/去重/键盘提交/删除，以及窄屏大字号真实开关与滑条触控、关闭后保留阈值。

相邻回归包括 `danmaku_message_actions_test.dart`、`danmaku_settings_controller_test.dart`、`danmaku_similarity_filter_test.dart`。使用真实 zh/en 文案和真实偏好控制器，但应用/网络初始化被隔离；既有站点资源键警告保留，不将其误判为生产缺少资源。测试覆盖的真实文件重开属于相邻动作测试，不声明新页完成生产数据库恢复演练。

原始记录、红/绿脚本、输入哈希及冻结上游源快照保存在忽略目录 `local-artifacts/shield-management-20260909/`。只执行定向回归和改动文件分析，未自动重复全量门禁。

提交前逐项核对通过的输入 SHA-256：

- `danmu_shield_page.dart`：`58360C0F18E8FD77FBC693C2951D8C24D88FAE39A990BCF89E2FB41907695E36`。
- `danmu_shield_controller.dart`：`C0B680A660A5B5BDAB8C06E3196D1172672C643185CEA77A8B0E3C4CC74A578A`。
- `keyword_block_page.dart`：`CAF64899674AB67DD5ABFF7EE986D40D140953F40ED52FFC3FB4D5491D61CF23`。
- `shield_management_page_test.dart`：`7A388F797782AC9EDFF93230C2102CDD57CB185C0786737EF10D26AC0E4C0B26`。

## 交付边界与后续

本批无 ADB/MT、安装、手机 UI、Root/LSP、构建或发布操作。Android 候选仍 bee143e2、Windows 仍 f3de664a；本批及 f35e605/ffd16158 均未进入现有候选。版本仍为 3.1.8+4121，完整验收前暂缓稳定 3.2.0。

历史 42 个宏观未闭环项不减记，A4-02 不提升为 PASS。下一累计候选需要 Android 中英文大字号/系统键盘/增删操作，以及 Windows 窄窗口、鼠标与键盘验收；仅屏蔽管理子路径的确定性修订不代表全部设置、过滤算法或原生体验完成。新页已有的两行省略策略未在本批改动，完整长词识别体验仍可另行审查。

TTing/FLEX 保持公开合同取证阶段，未注册；源级 HLS token 传递和播放/录制会话所有权另行继续，未用本次 UI 通过替代媒体链路验证。平台仍为 17 直播站点 + IPTV、10 组参考平台未注册。

回滚使用 3937b252 的独立反向提交，会恢复旧布局/旧索引缺陷；无需数据库、模块或用户数据回滚，旧候选继续保留。
