# 分区目录原生失败与列表所有权修订（2026-09-08）

## 原生复现

复用已核验 Windows Debug `f92aa1a7842ec2148aaee50458ff0280975aa1cb` / 3.1.8+4121，在 `windows-f92aa1a7/app` 解压目录以 `--instance=acceptance_f92aa1a7_20260908` 启动。提前创建独立 `PLUGIN_SUPPORT/shared_preferences.json={}`，避免迁入主实例插件偏好；本轮没有手机、MT 或 LSP 操作。

实际点击热门 → 猫耳：首屏 20 项、下一页与 20→40 每页数量切换可见，第二页的余量推荐卡片保留。随后进入分区 → 猫耳，虽然六张分类卡片显示，仍出现只读列表追加异常提示。截图直接显示于工具记录，本地文本证据为 `local-artifacts/candidates/windows-f92aa1a7/native-ui-evidence.json`；该候选此路径判定 FAIL，不因出现卡片而记 PASS。

界面自动化先遇一次过期无障碍索引，重新观察后改用当前截图坐标，未盲目重放。旧独立实例通过退出确认正常退出，PID 27088 后续查询已不存在。未开始播放、录制或删除数据。

## 根因及来源

1. `AppLiveCategory.fromLiveCategory` 将平台的 `children` 原列表交给会修改它的 UI。猫耳接口返回 `List.unmodifiable`，桌面 `processLocalPaging → children.assignAll` 因追加立即异常；固定长度列表同样失败。
2. 仓库 Get 扩展的 `assignAll` 只会清空 RxList，对普通 List 实际仅 `addAll`。其他平台返回可变列表时不抛错，而是把当前页重复追加到全量分类，污染平台缓存并让视图与分页列表不一致。
3. `ServerAllPageController.goToPage` 仍用首次加载分类的长度限页。切到更长分类后，即使界面显示存在后页，页码导航也会被错误拒绝。

冻结上游 `c6c9bd70aedc503c003110dae10a83ad0bb891d8`、merge base `527fea1b40885e3621d53c9646b523dd8522290c` 与当前分支均有列表别名和普通 List 的 assignAll 路径；冻结上游的导航也使用首次 `_rawAllData.length`。分类为 **upstream-existing**，新增猫耳只读响应使既有契约缺陷显性暴露，不是平台网络漂移。未同步或合并上游。

## 修订

- AppLiveCategory 构造时取得独立、可变的列表副本；UI 不修改平台返回列表。条目对象无需深复制，本路径只读条目字段。
- 当前分类视图明确清空后添加本页数据，不修改全局 Get 扩展语义；全量备份仍由 `_serverRawBackup` 保存。
- 基类增加当前本地条目数量 getter，默认继续读取原缓存；分类控制器投影当前分类计数。沿用原在途请求及分页守卫，不通过重取接口修补切页。
- 不修改分类身份、用户收藏、序列化版本、平台接口或播放器/录制状态。

## 分层验证

- 红测：7 个新增场景加既有分类切换，共 2 通过 / 6 失败。失败包括原生同路径异常、可变列表由 5 项变 7 项、固定长度异常以及切长分类后仍停在第一页。记录 `20260907T184500092Z-area-category-paging.json`；原日志保留 `local-artifacts/area-category-native-20260908/unit-red.log`。该红测记录的 command 描述沿用了旧脚本文字，实际执行范围以 checks 脚本当时输出和 unit-red.log 为准。
- 修订后：上述断言保留，分类、原生页控制器、收藏身份、猫耳适配及事务刷新共 **77/77** 通过；3 文件 analyze 无诊断（65 秒）。记录 `20260907T184850112Z-area-category-paging.json`。
- 覆盖 mutable / unmodifiable / fixed-length、重复投影、三页往返、修改页大小、刷新重用平台缓存、短/长/空分类切换和移动端完整列表。
- 原生复验需使用新构建；本节的测试通过不替代新候选实际 UI。当前 Android 7aaecb8e 与 Windows f92aa1a7 均不含本修订。

## 保留范围

猫耳图标在方形分类封面中显示了上下多状态图案，仍待核对资源展示契约；不是本次列表异常的根因。分类收藏、实际播放/搜索说明、新候选原生重试、Android 补证继续。历史 W1-01 保持 RUN，42 个历史未闭环大项与 14 组未注册平台不因本批变更而减少。

回滚点为业务修改前 `bc4efed0`；若回退本修订，应同时恢复两处控制器及关联测试，不丢弃原生失败证据。
