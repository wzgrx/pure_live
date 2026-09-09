# 空快照页面的失败恢复与导航保留（2026-09-10）

代码提交 **42dd533b6767dae84bfda2e8221b0bb741168daf**，父提交 3aa23de72933d72bdbd52065bbe309257eceaf4c。

## 问题与范围

在[分类目录生命周期修订](AREA_TAXONOMY_OWNERSHIP_AUDIT_2026_09_10.md)后继续实际错误路径测试：空分类下拉遇到网络错误或 LoginRequired，控制器正确记录失败，但 BasePageView 先处理错误/登录状态，替换整份 TabBarView，横向导航再次消失。

来源为 **fork-regression**：9a384339 引入的 preserveContentWhenEmpty 合同仅在普通空状态路径生效，错误/登录分支优先返回完整状态页。本轮修复这个分支顺序与错误呈现组合；普通未启用保留的页面，以及尚未发布数据快照的首次失败，继续使用完整状态页。

本轮唯一生产修改为 `lib/common/base/base_page_view.dart`，没有改网络错误分类、登录行为、分页控制器、数据库、站点接口或设备配置。

## 处理

- 对明确启用 preserveContentWhenEmpty 且 totalCount 已发布的空内容，保留 contentBuilder 挂载，将失败提示移入已有的有界、可滚动提示区，仍最多占半个视口。
- 复用同一组默认错误/登录状态构造与原有回调，保留 errorBuilder / notLoginBuilder 扩展点；错误信息仍完整显示，未用隐藏错误来保留导航。
- 初始 totalCount 为 null 时仍呈现完整失败状态；非空列表的既有行内错误行为保持。恢复成功后提示区收起，正文使用同一个 ScrollPosition。
- 页面自管刷新时不新建 EasyRefresh，保留 wrapMobileRefresh=false 的责任边界。已核对直接调用点为分类页和关注页；不将共用组件测试冒充整个关注页 GUI 测试。
- 扩展实际重试按钮测试时发现：保留空正文后，按钮触发的请求等待期间没有进度反馈。将既有顶部进度条的“有正文”条件扩展到已发布的保留空快照；提示消失后请求仍有可见反馈，完成后进度条消失。

## 验证

扩展[共用页布局测试](../test/base_page_layout_test.dart)与[分类真实手势测试](../test/area_tab_refresh_test.dart)，本批新增 15 项，未增加线上请求。

| 新增范围 | 数量 | 实际断言 |
| --- | ---: | --- |
| 中英文 × 320/900 宽度 × 错误/登录状态 | 8 | 两倍字体，提示占高最多一半，错误重试/登录入口可滚动到达；正文及 ScrollPosition 保留，提示恢复后收起 |
| 尚无已发布快照的错误/登录 | 2 | 保留开关开启也不虚构正文；继续完整状态页 |
| 自定义错误/登录状态与子页自管刷新 | 2 | 调用者按钮实际触发；错误文本原样传给 builder；没有额外 EasyRefresh，唯一挂载位置 |
| 空分类网络/登录失败后继续横滑并恢复 | 2 | 真实下拉失败，TabBarView 和控制器仍在；可横滑到下一类，再实际下拉成功，请求计数与失败标志回写正确 |
| 实际重试按钮等待响应 | 1 | 可控 Future 延迟响应，真实按钮启动第 3 次目录请求；等待时正文保留并出现 LinearProgressIndicator，完成后进度条消失且仍选中空分类 |

默认登录入口验证可达，原导航回调保持；没有在 Widget 中启动真实账号设置页或执行登录。自定义登录动作有实际点击证据。

初轮 49 项中 37 PASS / 12 FAIL，失败均为保留内容/导航被替换；修订后 49/49。加入自管刷新覆盖后联合 196/196 与严格分析通过。随后新增实际等待反馈用例取得 49 PASS / 1 FAIL，明确缺少 LinearProgressIndicator，补齐可见进度后进行最终联合复验。所有失败与成功日志在 `local-artifacts/retained-page-recovery-20260910/` 按时间戳独立保留。

## 交付边界

本批未执行 ADB、手机前台、Root/LSP/MT、构建、安装、发布或上游合并。Android f5aab636 与 Windows 2fb471d3 均未包含本批及最近分类修订；下一份累计候选需纳入后再验证。移动/桌面宽度 Widget 结果与真实 Android、Windows 原生 GUI 结果分开记录。

仍需继续刷新与用户选中竞态、各页面大字体卡片、真实设备及平台/录制全链路验收。宏观 20 PASS / 32 RUN / 10 NR（42 组未闭环）、8 组参考平台未注册保持；没有提前标记完整验收或发布 3.2.0。

## 最终验证与资源

最终 **8 文件 197/197、三个改动文件严格分析 No issues found**。除两份新增测试覆盖外，还包括目录控制器、小红书应用、搜索布局、分类切换/分页、关注下拉刷新。记录 `20260909T215325342Z-retained-page-final-verified.json` 为 passed；测试日志 `20260909T215153898Z-final-verified.log`，分析日志 `20260909T215153898Z-analyze.log`。

提交前对账的输入 SHA：

- base_page_view.dart：`EA30CE9F746F9D136FEA5727499E2D2E254311093B7DC86A5FAD51FE0582EEE6`
- base_page_layout_test.dart：`615FCFE44E18F9DA3C6BF375C848C52A2036BC303A086F304372B60892F89FA4`
- area_tab_refresh_test.dart：`CECB95BFAE3039982CBB47BFADB098E53E0C9C3CD65CFC89346CB51FB285D594`

资源守卫下串行执行，缓存保留。最终轮 91.321 秒，监测峰值 CPU 13.44%、工作集 10,380,668,928 B，结束活跃重型进程 0；这些是验证任务资源，不是应用性能改善幅度。记录 sourceCommit 为运行时父提交，sourceFiles 保存当时修订字节。

撤销本批生产文件即可回退呈现行为，不涉及用户配置或数据库回滚。全目标继续按[剩余验收](ACCEPTANCE_STATUS_3_2_0.md)推进。
