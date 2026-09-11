# Windows 多画面渲染目标审计（2026-09-11）

## 范围与基线

- 基线：`64196c3c3963306194052c3a18826254e1b5f3b2`。
- 对应验收组：A3-08 的多画面布局切换、聚焦晋升和 Windows 多路渲染资源。
- 修改前仓库审计：`local-artifacts/repository-audits/20260911T232152169Z-focused.json`。

本批先从源码、既有 TODO、真实布局约束和播放器输出策略复现根因；使用确定性 Widget/控制器替身验证，没有操作手机、启动真实平台网络、原生多路解码、构建应用或发布候选。

## 修改前问题

1. 每格 `VideoControllerConfiguration.width/height` 只在创建播放器时按当时布局计算。`setLayout` 刻意保留前 N 个播放器，页面也没有调用 `VideoController.setSize`，所以布局切换、窗口缩放和全屏不会更新已有格子的原生纹理。
2. 聚焦布局以四宫格尺寸创建播放器。小格晋升为大画面后继续上采样小纹理，画面会偏糊；原大画面降为小格后继续保留较大输出，又会浪费 Windows 共享渲染线程和 GPU 资源。
3. 页面使用 `GlobalKey` 无重建搬移格子，这正确保留播放会话，却也使固定构造尺寸持续存在；源码 TODO 已明确记录该缺口。
4. 主播放器已有一套私有的 Windows viewport 防抖协商器，多画面没有复用，两个视频入口的纹理策略因此分裂。

## 修订

- 将主播放器既有逻辑提取为共享 `VideoOutputViewportSizer`，主播放器继续使用同一物理像素、源尺寸、偶数纹理和不超过解码源的策略。
- Windows 多画面每个实际 `Video` 都接入共享协商器；`LayoutBuilder` 读取该格真实可见尺寸并结合 DPR 与播放器发布的源宽高计算目标，不再依赖整屏平均值猜测聚焦布局。
- 180 ms 防抖合并窗口拖动和快速布局变化。格子经 `GlobalKey` 晋升/降级时，两个保留中的输出分别收到新的大/小目标，无需重建播放器、重取直播地址或扰动音频焦点。
- 输出 identity 隔离控制器替换的迟到完成，新输出首次挂载强制重申尺寸；格子退出时取消待执行计时器和宽高订阅。
- Android/Web 对固定宽高本就采用平台自身表面语义，本批保持非 Windows 页面路径不变。

## 验证

最终统一质量记录：`local-artifacts/build-records/20260911T153841149Z-quality-focused.json`；最终仓库审计：`local-artifacts/repository-audits/20260911T233855375Z-focused.json`。

- 新增 `video_output_viewport_sizer_test.dart` **5/5 PASS**：覆盖物理像素首发、窗口变化合并、源几何更新、带 GlobalKey 的大/小格晋升交换、新输出强制重挂和退出取消。
- 多画面控制器、会话型输入、房间选择、全屏表面、主播放器几何与输出尺寸联合结果：**89/89 PASS**。
- 全库 `flutter analyze` 最终结果：**No issues found**。
- 质量任务中的实际 ADB 命令为 **0**；本批没有原生视频实例、真实直播流、安装包或版本变更。

## 当前边界

A3-08 保持 `RUN`。源码和确定性 Widget 已证明布局/晋升会发布正确目标，但仍需下一 Windows 候选使用真实多路纹理观察清晰度、GPU/CPU、窗口拖动与真全屏；Android 的系统返回、方向恢复和真实多路连续性继续累计验证。宏观状态保持 **20 PASS / 33 RUN / 9 NR，共 42 组未闭环**。
