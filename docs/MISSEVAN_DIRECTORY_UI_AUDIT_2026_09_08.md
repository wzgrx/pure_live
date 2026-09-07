# 猫耳 FM 原生目录分页与界面衔接（2026-09-08）

起点 `60ab5a285353066c06ff3db6d467e4295b6aa4b7`；延续[暂存适配审计](MISSEVAN_STAGED_ADAPTER_AUDIT_2026_09_08.md)。
**本批完成分页衔接代码，不等于平台全部接入：Sites注册、配置迁移、播放/录制headers与原生验收仍待完成，未注册数仍15。**
本批没有重启、ADB、手机输入、Root/LSP/MT、APK构建、版本提升、上游合并或发布。

## 第一个不兼容状态与设计

上一批实际HTTP已证明猫耳 `pagination.pagesize=20` 但Datas可有22条，过滤已下播房间后也可能剩0条且仍有后页。
当前维护分支 `ServerRemotePageController` 按所需条目数提前退出逐行循环，然后推进网络页，未保存该响应剩余条目；
`ServerFixedPageController` 则按固定每页大小计算全局offset。因此不能直接把猫耳的原生页塞进任一旧路径。
这是新平台与既有分页假设的接入冲突，尚未作为用户可见猫耳平台部署；不宣称其他已上线平台的所有分页问题都已修复。

处置：新增可选 `LiveSiteDirectoryPager` / `LiveDirectoryPage`，明确携带原生page和hasMore。
猫耳桥接保留其原始分页证据；热门及分类binding仅在适配器实现此接口时选择 `LiveDirectoryController`。
没有该能力的已有平台保持原来的remote/fixed/all等路由，未重写所有分页器。

## 保持的行为合同

- 每个页签独立维护已获取条目池、房间身份集合、原生下一页和结束标志；整份响应保留后才切UI页，额外推荐条目不裁剪。
- Android式连续列表追加、Windows式分页/回看/自定义页大小共用该池。桌面12/20/80/320条模式无需重新请求已缓存原生页；不擅自限制用户已配置的正整数页大小为200以内。
- 终止以服务器hasMore为依据，过滤空页、重复页或不足20条均不是下播/末页证明；服务器结束后仍先消费已缓存尾部。
- 断网预检失败会结束刷新指示器，保留原可见卡片，不发出目录请求；避免提前return后刷新状态悬挂。
- 中途请求失败保留已成功卡片及网络游标，下一次加载补齐同一不完整UI页，重试同一个失败原生页，不跳到下一页。错误不会伪装成noMore。
- 刷新、改页大小与关闭用代次和CancelToken隔离目录请求响应；刷新合并后等待旧操作结束再启动新操作，旧目录结果不重新填回界面。该证据范围是目录请求，不外推为所有系统连接回调均已验收。
- 每次操作最多20个原生请求；达到请求预算后明确提示继续加载，保留hasMore。单响应上限1000条，池/身份集合上限20,000条；容量超限不部分消费该页，不虚构总条数，提示刷新。此上限是明确的本地浏览窗口边界，不声称无限缓存。
- 分类控制器tag在新能力路径加入areaType，避免catalog/tag相同数字ID复用同一控制器；旧平台tag不变。分类名称通过copyWith加入，不修改源响应共享对象。
- 英中文新增请求预算与缓存上限文案，未新增依赖。

## 验证与失败保留

验证由资源守卫串行执行，Flutter3.47.0/Dart3.13.0，保留增量缓存；其他任务Java活跃时排队，未结束它们。

1. 首轮四文件52/52通过；9文件analyze有1条if花括号风格info，整体记录 `20260907T170354992Z-native-directory-integration.json` 保持failed。275.935秒，结束活跃重型进程0。
2. 补充自定义320条与实际BasePageView Widget测试。第二轮53通过、1失败，记录 `20260907T170624834Z-native-directory-integration.json`：Widget内容/重试断言通过，但卸载后EasyRefresh的0ms ballistic-layout Timer尚未排空，框架终止断言失败。保留原始日志；保留完整刷新组件与卸载后无异常断言，没有加入生产延时。
3. 加入断网预检结束指示器测试后，第三轮54通过、1失败，记录 `20260907T171454950Z-native-directory-integration.json` 保留同一个Widget Timer失败。进一步查固定依赖easy_refresh3.5.1源码，回调已有mounted检查；Flutter测试绑定仅在pump传入非null duration时才推进FakeAsync时钟。测试最终显式 `pump(Duration.zero)` 排空0ms事件，保留卸载后无异常断言，而非继续累加实际等待或修改生产组件。
4. 最终四文件 **55/55通过**（新目录控制器17、猫耳合同28、TwitCasting分页4、既有刷新6）。包含实际BasePageView的内容保留、重试和卸载后无异常断言；记录 `20260907T171906941Z-native-directory-integration.json` 的unit=0；analyze仅有新增离线测试helper的super-parameter风格info，原记录仍为failed。helper采用等价super参数语法后只重跑分析，最终9文件analyze无诊断（49.5秒），记录 `20260907T172337065Z-native-directory-style.json` succeeded；含资源守卫全过程96.625秒、结束活跃重型进程0。

测试范围包含：22条响应的第21/22条、空后页、跨页去重、服务器已结束仍有本地尾部、桌面回看/改页大小、失败原生页及不完整UI页续载、预算/容量边界、刷新替换、重复刷新合并、在途改页大小、关闭后的晚响应、错误页码重试、真实热门/分类binding选择、分类原响应隔离。
`missevan_adapter_test.dart`还覆盖实际站点桥接：第一页全部被下播过滤后hasMore仍true，第二页保留有效房间并正确结束，CancelToken原样传入。
相邻TwitCasting分页与既有transactional刷新测试保持，不把这些自动化结果描述为Android/Windows原生验收。

原始日志位于忽略目录 `local-artifacts/missevan-directory-20260908/`。本批未重复公网探针；之前的匿名HTTP/FFprobe证据继续作为外部合同来源。

## 下一步与回滚

1. 平台注册/第6代目录迁移、链接与搜索能力声明、热度能力、统一播放/录制headers及StreamResolverService联测。
2. 分类收藏当前仍有按areaId单字段比较的旧路径：`FavoriteRoomController.isFavoriteArea`与分类页按钮。加入新命名空间前应另做房间平台/分类类型/分类ID共同身份的回归，不能把本批控制器tag修订当作收藏身份已修复。
3. 原生分页长时缓存/末页重访与缓存上限提示持续性继续补证；基础系统网络检测回调沿用原有BaseController，不把目录响应代次测试外推为连接状态回调隔离证明。
4. 原生短录、严格完整解码、正常停止与签名续租、纯音轨及16×16视频/封面表现；随后才开放入口并更新平台计数。
5. Android待安装候选仍b5f39c2b，最新已验证安装仍80b7431c；切换窗口未收到确认，本批保持手机状态。

回滚本批接口、控制器与路由选择即可恢复原路线；没有迁移已保存配置或修改用户分类收藏。
