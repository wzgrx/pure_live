# 播放终态错误界面（2026-09-06）

## 问题与修复

旧 Windows 候选的长暂停恢复失败证据见 [GUI 审计](WINDOWS_DOUYU_GUI_AUDIT_2026_09_06.md)。Manager 已进入终态错误，但 VideoController 只发短时 Toast，视频区域没有持久重试入口。

- VideoPlayer 在现有 Obx 中订阅 Manager 的 `hasError`，仅在终态失败时展示提示；自动恢复中的 loading 不提前展示失败。
- `PlaybackFailureOverlay` 保留原生视频子树；半透明背景不拦截操作，居中卡片限制高度，边缘仍可操作原控制栏。小窗口/大字号内容可滚动。
- 重试调用既有 `VideoController.refresh()`：重新加载直播间详情及播放源，不重放旧 URL。按钮对进行中的回调去重，回调抛错后保留入口，销毁后回调不 setState。
- 中文/英文资源均新增明确的中断提示与重新取源说明；未展示原始播放 URL 或服务端错误详情。

## 验证

`20260906T001420759Z-quality-focused.json`：6/6 通过，179.416 秒，结束活跃重型进程 0；一次 analyze 98.7 秒无诊断。门禁基于 a451e252 加本批次工作区差异。

- 新 overlay Widget 测试 4 项：8 秒后提示持续、错误清除、视频 Element 身份保留；重复点击/刷新抛错；销毁后异常完成；240×135 且文字缩放 2 倍时无溢出、重试滚动后可点击。
- 真实 VideoController 源提交监听回归 2 项通过。
- 中英文 JSON 可解析，新增键及既有 retry 均有实际文案；`git diff --check` 通过。

## 剩余

尚需同一新源码完整回归及 Windows 新候选原生验收：斗鱼长暂停恢复、成功后的画质/线路标签、小窗往返、终态按钮实际重新进房，以及窗口响应。此 Widget 证据不替代原生播放器测试；未构建或发布 3.2.0。
