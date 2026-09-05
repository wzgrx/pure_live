# 2026-09-06 新增 Issue 初审与后续核验

当前应用提交 `6a8c007d0d17f5fdeffae40222f231db831e1348`。通过 GitHub API 只读查询：维护仓库当前 open Issues 为 0；上游最新报告包含 #853、#852、#851。本次没有合并上游、评论或关闭 Issue。

| Issue | 当前证据 | 处置与下一步 |
| --- | --- | --- |
| [#853 Windows 斗鱼原画动态画面模糊](https://github.com/liuchuancong/pure_live/issues/853) | 报告为 3.1.2，没有房间号、码率或日志。当前代码已按服务端 multirates 顺序构造画质，不把 rate 数字当码率排序；getPlayUrl 传递所选 rate。但 resolvePlayUrlAtRaw 仍直接把请求的 selectionId 当 appliedQualityData，尚未在此链路核实服务器实际返回档位 | `not-reproduced`；不能把“请求原画”当“实际拿到原画”。下轮检查响应 rate/码流参数与 UI 提交点，用有响应证据的低/高档对照区分服务端降档、错误标注和呈现问题。现有解析回归通过不证明此 Issue 已修复 |
| [#852 ColorOS 14 二级页侧滑返回卡住](https://github.com/liuchuancong/pure_live/issues/852) | 报告明确系统手势失败、页面左上角返回正常，直播页例外；无日志，且没有证据证明本地最新分支相同。设备描述不足以直接归因厂商或全局导航 | `not-reproduced`；先沿设置/搜索/关于路由的返回、预测返回与过渡动画路径检查，建立系统返回与按钮返回对照，保留直播页特有 PopScope 的区别。不移除全部返回动画或全局替换系统通道 |
| [#851 小窗关闭按钮几秒后消失](https://github.com/liuchuancong/pure_live/issues/851) | 复核报告无日志/截图；本仓库已有隐藏时第一次点击唤出控件的修复，上游冻结代码仍直接导航。真实 FloatingOverlay Widget 检查另发现当前 SDK 的 Get.overlayContext 入口异常及旧隐藏 timer 未随关闭取消 | 原点击唤出机制按 `already-fixed` 跟踪；新入口/计时器缺陷独立修复并验证，见 [小窗审计](APP_FLOATING_OVERLAY_AUDIT_2026_09_06.md)。保留真实设备与用户报告一一对应的证据边界 |
| [#850 颜色透明度/ARGB 编辑](https://github.com/liuchuancong/pure_live/issues/850) | 已有 09-05 审计、统一颜色选择器实现和 `app_color_picker_dialog_test.dart`；本次全 test 目录回归仍通过。主题 RGB 与具备透明度场景的 ARGB 合同已区分 | 沿用既有修复，不重复引入第二套选择器。历史设备证据见 `ISSUE_AUDIT_2026_09_05.md`，本轮没有新增手机采样 |

本表是最新报告与代码之间的初步映射，不是全部 Issue 关闭结论。优先级按用户影响与可复现性推进；已覆盖问题沿用有效证据，未复现问题保留具体下一步，避免继续无依据改变正常播放路径。
