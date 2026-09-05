# 应用内小窗入口与控件生命周期审计

## 范围、来源与根因

基线 `7a5add213b7c1ea2ec718121fe663b91b4fce5e6`，固定 Flutter 3.47.0。
只读核实 [上游 #851](https://github.com/liuchuancong/pure_live/issues/851) 的报告：Android 3.1.2，应用内小窗关闭按钮数秒后消失，报告没有附带日志或截图。

1. **隐藏后重新唤出：本仓库已有修复。** 上游冻结提交 `c6c9bd70` 的画面点击直接进入房间；本仓库 `7c3275b4` 已加入“隐藏时第一次点击只唤出控件”。当前关闭按钮使用 Obx + IgnorePointer，透明时不会误触关闭。本轮保留这套语义，不重复重写。
2. **小窗入口：确定性复现的共享兼容问题。** `Get.overlayContext` 只取 Navigator Overlay 的第一个子 Element（当前是 `_Theater`）。Flutter 3.47.0 的 `Overlay.maybeOf` 从 OverlayEntry 内部的 inherited marker 解析所属 Overlay，此上下文尚在 marker 外。`FloatingOverlay.open` 调用 `Overlay.of` 因而抛出 `No Overlay widget found`，既有“open 未成功则释放”分支尚未执行就异常退出。
   - 冻结上游的 getter 和 `.fvmrc` 与本仓库相同，分类为 `upstream-existing` 的框架兼容缺陷；不是网络/CDN/虎牙服务器问题。
   - 第一轮三个真实 PlayerManager/FloatingOverlay Widget 场景都在相同栈失败：`FloatingOverlay.open → Overlay.of → Get.overlayContext`。不是用一个近似按钮模拟入口。
   - 该复现发生于固定 SDK 下的 Widget 环境；尚未证明每个带全局对话框包装的实际客户端都必现。
3. **关闭后的控件计时器：邻接回归已复现。** 小窗隐藏计时器原来只在再次显示或 manager.dispose 时取消，closeAppFloating 没有取消；关闭后旧 timer 仍修改共享 isHovered。关闭后推进虚拟时间的断言在 `app-floating-controls-red4.log` 中得到 expected true / actual false。本次在 closeAppFloating 入口立即取消并清空 timer；不将此生命周期缺口当成 #851 的已证实用户根因。

## 设计

- Get getter 按公共 `Overlay.maybeOf` 合同寻找属于目标 Navigator Overlay 的可用上下文；找到即停止，不缓存 Element，不依赖 `_Theater` 或其他框架私有类型名称，也不误选嵌套 Navigator 的 Overlay。
- 小窗只使用这个已验证的上下文；去掉 Navigator 自身 context 的兜底，它位于目标 Overlay 之外，可能误挂到祖先 Overlay。没有可用入口时仍走现有释放路径。
- 触控显隐策略使用 Flutter `defaultTargetPlatform`（原生 API 分支保持 dart:io），使 Android/iOS 真实控件路径能在 Widget 测试中覆盖。
- 保留三秒自动隐藏、点击唤出、播放/暂停、关闭和已有画面几何，不改解码、线路、缓冲、弹幕或系统 PiP 实现。

## 验证进展

- 第一轮红测：`local-artifacts/app-floating-controls-red.log`，39 通过/3 失败，记录 `20260905T210022556Z-quality-focused.json`；三个入口异常成立。
- 中间夹具修正单独记账：补齐测试设置的 portraitPipFollowSource；移除 GetRoot 尚未挂载时调用全局 getter 的无效前置断言；异步释放要推进测试虚拟帧，避免测试自身等待从未 pump 的帧。中间结果不当作新的产品故障。
- 夹具中广播订阅取消涉及真实事件循环，最终清理使用带两秒超时的 tester.runAsync；不改生产取消逻辑。平台选择使用标准 TargetPlatformVariant，在 Flutter 检查不变量之前恢复平台，而非过晚的 addTearDown。
- 最终六组 **63/63** 通过，记录 `20260905T211633514Z-quality-focused.json`，145.133 秒，结束活跃重型进程 0。覆盖真实应用内小窗的 Android/iOS 触控显隐与关闭、旧 timer 取消、OverlayEntry 插入、bottomSheet 返回、嵌套导航下根 Overlay/dialog 归属，以及音频、来源交接、返回优先级、悬停和 Windows PiP 快照相邻回归。
- 一次 analyze（61.2 秒）无错误，有一条新增测试的冗余 foundation import 提示；已删除重复 import，未为该非行为整理重复全量分析。最终测试通过不等同于手机/桌面截图、解码画面和长时间运行验收。
- 最终日志 `local-artifacts/app-floating-controls-final.log`；等待其他项目 Java 构建结束后按重型互斥执行。没有手机操作或上游合并。正式 3.2.0、Android 安装包和真实客户端验收仍未完成。

## 回滚与相邻风险

改动集中于 `extension_navigation.dart` 的 getter、PlayerManager 小窗入口/显隐生命周期和相关测试。getter 也被 bottomSheet、dialog、snackbar 使用，需要一并验证上下文归属和返回行为。保持原 getter 的导航根选择，针对同一根因恢复旧实现即可回滚；避免通过全局 Overlay 叠加或反复重建播放器回避异常。
