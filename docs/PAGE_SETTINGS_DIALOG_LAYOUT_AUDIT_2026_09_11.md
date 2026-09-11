# 页面尺寸编辑框窄屏与大字号布局审计（2026-09-11）

## 范围与基线

- 基线：`4afb0305a9a00af3b6ca6d1f2961f842e0f4ecab`。
- 对应验收组：A2-01 的二级设置页增量。
- 检查页面：设置 → 页面设置 → 页面尺寸选项。
- 固定视口：宽屏 `900×600 / 1.0`，窄屏 `320×480 / 2.0` 英文；同时验证长设置页先滚动到入口，再打开编辑框。

## 修改前复现

新增 `test/page_settings_dialog_layout_test.dart` 后，干净基线记录
`local-artifacts/build-records/20260911T015655168Z-quality-focused.json` 为 **0 PASS / 2 FAIL**。
其中编辑框正文宽度为 320 像素时，“Current Active Options”和“Adaptive Auto”被固定横向 `Row`
放置，稳定产生 **164 像素右侧溢出**。第二项同时暴露测试夹具跨用例注册时序，未把夹具错误计作产品缺陷。

## 修订

- 当前选项标题与“自适应推荐”改用可自然换行的 `Wrap`，空间足够时仍保持两端布局。
- 自定义页大小输入区依据可用宽度和文字缩放切换横排/纵排；窄空间或大字号下输入框独占一行，“添加”保持右对齐且可点击。
- 为输入框和添加按钮增加稳定键，便于后续状态与交互回归。
- 测试先滚动到真实二级页入口，并确认窄屏下入口和编辑框“添加”动作都处于可命中区域；取消仍不修改原配置。

## 验证

最终统一质量记录：
`local-artifacts/build-records/20260911T020206624Z-quality-focused.json`。

- `test/page_settings_dialog_layout_test.dart`
- `test/settings_page_layout_test.dart`
- `test/base_page_layout_test.dart`
- `test/backup_collection_validation_test.dart`
- 合计 **45/45 PASS**。
- 全库 `flutter analyze` 执行一次，**No issues found**。
- 仓库完整性审计错误为 0；所有重型进程已结束；实际 ADB 命令为 0。

## 当前边界

A2-01 保持 `RUN`：设置首页和本页面尺寸编辑框已有确定性窄屏/大字号证据；其余二、三级设置页、
Android 与 Windows 当前候选上的触控/键鼠、系统字体、持久化和跨页面一致性仍按矩阵逐项验收。
本批未操作手机、构建候选、修改版本或发布 3.2.0。
