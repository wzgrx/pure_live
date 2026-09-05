# PiP 状态观察生命周期审计（2026-09-06）

## 来源与范围

- 维护分支基线 `717ba21321fd2ee023cf74eadab0c96499f0faf9`。
- 分类 `upstream-existing`：本地 floating 6.0.0 快照 `91d3d047` 已含周期异步查询；
  `879813f5` 仅把 10 ms 改为 100 ms。冻结 Pure Live 上游 `c6c9bd70` 同样保留此模式。
- 只读对照 [floating 源码](https://github.com/wrbl606/floating/blob/main/lib/src/floating.dart)、
  [Dart 广播流生命周期](https://api.dart.dev/dart-async/StreamController/StreamController.broadcast.html)
  和 [Timer.periodic 合同](https://api.dart.dev/dart-async/Timer/Timer.periodic.html)。
  周期计时器不等待 async 回调完成；资源应由订阅生命周期拥有，而非 getter 拥有。
- 不合并上游、不操作手机，不更改视频比例、解码器、播放器源、原生 Surface 或 PiP 尺寸。

## 首个错误状态

1. `pipStatusStream` getter 即启动计时器，尚无订阅者也查询系统。
2. 最后订阅取消后，`asBroadcastStream` 未停止计时器；退出监听后仍有每秒约十次查询。
3. 异步系统查询超过 100 ms 时后续查询继续发起，返回顺序不再等同状态采样顺序。
4. 旧监听期间发起的回复可在新监听建立后交给新页面，使过期 enabled 状态被视为当前状态。
5. 异常在 async Timer 中抛出而不是受控结束观察，调用端也没有显式错误处理。

这些是具体的观察生命周期和额外开销问题，尚未证明是历史固定抖音房间黑屏的唯一根因。
历史日志最早的停止仍发生在进入 PiP 前，保持 [原始失败记录](ANDROID_PIP_RETURN_FAILURE_2026_09_05.md)
中的证据边界。

## 设计合同与验证

采用广播控制器的 onListen/onCancel 管理查询；单次查询结束后才安排下一次，订阅代次
撤销旧结果；不通过扩大延时或强制刷新画面改变表现。暂停的订阅仍按 Dart 广播流语义处理，
最后取消才停止，恢复监听可再次启动。

定向测试使用真实 Floating 与模拟 MethodChannel，不启动 Android 或 ADB。

- 第一轮测试夹具直接 await 取消订阅，在 Widget 假时钟中停等；核对并结束本次
  flutter_tester，门禁返回 79。此项不计产品复现。改用取消后 pump 驱动假时钟，生产代码未变。
- 红测 `20260905T165223037Z-quality-focused.json`：未订阅的 200 ms 内查询 2 次，
  全部取消后的 200 ms 内仍查询 2 次；300 ms 延迟夹具累积 3 个并发查询，旧 enabled
  到达新监听。修复目标分别为 0、0、1、旧结果被丢弃；剩余监听与重新订阅需保持正常。
- 异常不伪装成 disabled，也不向 PiPSwitcher 推送使布局回退的错误快照；保留最后正确状态，
  每段连续失败仅记录一次诊断，下一次成功后解除错误记录锁存。失败查询同样不重叠。
- 保留广播流，reset 不再为已经监听过的单订阅底层流新建包装；测试覆盖 reset 后再次订阅。
- 最终四组 **42/42** 通过（含上述真实插件测试、播放器音频/模式回归与 Windows PiP
  几何/呈现策略），记录 `20260905T165550363Z-quality-focused.json`，101.811 秒。
  本轮一次 analyze 无诊断，45.6 秒；结束活跃重型进程 0，缓存保留。
- 质量门禁 source_commit 是补丁前 HEAD，执行对象包含本次工作树；最终提交保存相同实现。
  FFmpeg 本地前置 bundle 校验通过，测试 build hook 在线取 SHA 未取得时自行跳过复核的
  提示保留；这不是新的发布二进制验收。3.2.0 发布状态保持未验收完成。

## 邻接审查与边界

当前 PlayerManager 初始化就订阅、仅 dispose 取消；原生播放器 idle hard-dispose 后是否
仍应保留订阅，需要下一步按真实管理器生命周期核验。此批只证明最后一个订阅取消后
插件不再查询，不把它夸大为应用退出房间立刻零查询或已测 CPU 降幅。
另有 enablePip 的异步状态确认/渲染等待缺少关闭后的结果所有权检查，仍单独追踪。
未更改 Kotlin、依赖版本、包名与签名；不是正式包构建或真实 Android Surface 验收。

后续补证：[管理器所有权审计](PIP_MANAGER_OWNERSHIP_AUDIT_2026_09_06.md) 已以真实管理器
四项红测锁定上述残留订阅和进入异步竞争，再修复关闭即撤销、warm re-entry 重新观察及
系统状态优先级。本节原始证据不回写为当时已覆盖；仍保留历史黑屏和系统动画证据边界。
