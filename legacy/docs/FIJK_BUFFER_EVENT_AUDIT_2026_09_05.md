# Android IJK 缓冲事件审计

## 修改前根因与来源

基线 `465e91eb`，上游只读核对 `c6c9bd70` 的 FijkAdapter，不合并，不操作手机。
上游与本仓库均只订阅 `FijkValue`；`FijkState.started` 无条件发布 `loading=false`。
插件收到原生 `freeze` 消息时只更新 `isBuffering` 并发送独立的
`onBufferStateUpdate`，并不变更 `FijkValue`。因此缓冲开始/结束事件丢在适配器边界，
管理器的缓冲超时观察与界面加载提示均收不到真实状态。来源 `upstream-existing`，
可追溯至 `2cd462e49`，不是本轮原生 WUP 凭据改动产生。

另有相邻合同：同一 native player 重置后插件 `_buffering` 未清零；直接改用它作唯一
来源状态会把上一条直播的缓冲继承给下一条直播。`setDataSource` 的 finally 和延迟快照
也会把真实缓冲再次覆盖为 false。必须先添加真实 MethodChannel/EventChannel 驱动的
回归，覆盖缓冲中尺寸更新、早于 open 完成、主动暂停、换源和释放，再适配这些边界。

方案限定在 FijkAdapter 的源事件域：订阅原生缓冲流，按当前来源与状态发布去重的
loading，不把原生 started 等同于数据充足。缓冲持续由已有有界恢复处理；短暂缓冲
恢复不重开播放器，不增加轮询或主动换源。对 Windows media_kit 不改事件合同。

参考：[IJK 原生缓冲事件](https://github.com/bilibili/ijkplayer/blob/master/ijkmedia/ijkplayer/android/ijkplayer_jni.c)
将 buffering start/end 与播放状态作为独立消息发送。源码合同缺口不等于已证明所有用户
卡顿都源自 IJK；默认 media_kit 路径和系统纹理呈现仍需独立验收。

## 确定性复现与实现

`test/fijk_buffering_event_test.dart` 通过原生通道驱动仓库实际 FijkPlayer 和 FijkAdapter，
不是直接调用一个判断函数。修改前 7 项中 5 项失败：独立 freeze 事件遗漏、缓冲时尺寸/
rendering 事件清掉 loading、open 提前到来的缓冲被 finally 覆盖、暂停恢复丢失缓冲状态、
已经 started 又被 open 收尾降成 ready。红测 `20260905T022928731Z-quality-focused.json`；
之前 `20260905T022750762Z` 只停在测试文件格式门禁，不计入产品失败证据。

实现将缓冲观察限定到单个源，不修改插件共享的 `isBuffering` 状态；换源/softStop 清理
局部状态并屏蔽旧源，暂停时隐藏加载但保留尚未解除的源缓冲，恢复时再按实情展示。
尺寸和 rendering 更新不覆盖缓冲，重复状态去重；dispose 取消订阅，真实源恢复继续
交给管理器的同一条有界恢复路径。

修复后 **7/7 通道回归通过**，和缓存预算、管理器恢复、音频模式合计 **87/87**：
`20260905T023153548Z-quality-focused.json`，66.124 秒，测试并发 12，退出后活跃重型进程 0。
本批新增测试在前一批 807 项完整门禁之后，因此不把前一批静态分析/全量通过直接记在
本批新源码上；本批执行定向编译和测试，未再次启动 flutter analyze。

回滚此独立适配器提交即可撤销该事件修复，不影响虎牙凭据、Windows 原生缓冲和画面比例。
本轮无 APK 构建、无手机操作；通道模拟验证的是原生消息到应用的合同，不是 IJK 实际解码
或者全部 Android 音画帧间隔验收。
