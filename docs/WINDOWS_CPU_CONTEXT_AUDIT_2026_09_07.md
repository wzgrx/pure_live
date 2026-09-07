# Windows 空闲 CPU 对照诊断（2026-09-07）

## 目的与结论

针对 [上一轮虎牙退出后的约2.3% CPU](WINDOWS_PLAY_RECORD_AUDIT_2026_09_07.md)，复用 fadd5bdb Windows Debug，先区分业务活动、观察条件和窗口可见性。本轮没有应用修复、构建或发布；**根因仍未证明，性能项目保持 RUN**。

新的确定事实是：独立空关注页面在一段60秒可见状态采样中约 **0.958%**，同一实例最小化后约 **0.045%**，恢复同一页面后约 **0.924%**。因此下一步应优先比较 Windows 原生消息/渲染路径及可见性条件，不直接添加业务刷新延时。此处空关注页与上一轮有缩略图的热门页不同，不能把0.958%说成已把2.3%优化下降。

## 控制条件与实际样本

同一候选目录、独立 `--instance=cpu_fadd5bdb`、空插件偏好文件，未读取主资料、播放直播或录制。三次应用运行串行，前次正常退出后才启动下次。所有 CPU 百分比均由进程累计 CPU 秒数差除以实际墙钟秒数与24逻辑核计算。

| 顺序 | 进程与窗口条件 | 采样结果 | 解释边界 |
| --- | --- | --- | --- |
| 1 | PID76248，窗口观察前，首次启动稳定后的20秒 | 0.01626% | 当时没有固定可见/遮挡状态，不能当作所有后续样本的严格基线 |
| 2 | 同PID，get_window与仅截图后20秒 | 0.97345% | 窗口观察与窗口可见性共同变化，非单变量归因 |
| 3 | 同PID，不再观察，随后20秒 | 1.03222% | 增量CPU主要在TID35956（4.34375秒）与63496（0.640625秒） |
| 4 | 同PID，无障碍文本观察后20秒 | 1.00192% | 文本观察前后没有明显进一步升高；此段CPU profiler开启 |
| 5 | 正常退出后，同exe/配置重启PID63028，15秒等待后20秒，未重新选择该窗口 | 0.91396% | 没有复现第一段低值，不能确认“仅观察工具导致” |
| 6 | 再退出后，将exe字节不变复制为 `pure_live_cpu_probe.exe`，PID43332，15秒等待后20秒，未选择窗口 | 0.90747% | 改名没有消除高值；不是修复或替换交付文件 |
| 7 | 同PID，继续不选择/抓取该窗口，60.385秒 | 均值0.9579%，P95 1.1318%，13/13响应 | 排除仅短启动峰值的解释 |
| 8 | 同PID，实际点击最小化后20.190秒 | 0.04514% | 可见性相关下降，不代表业务功能完整验收 |
| 9 | 同PID，通过窗口激活恢复并截图，20.149秒 | 0.92397% | 同实例可见→最小化→恢复出现可重复方向变化 |

复制exe SHA-256 **BC49A263FF1947B48165484663C3D67918502C0AC64ACF61EE4FEAB40C73FE7B** 与原exe一致。没有修改压缩包或APK。操作仅通过Computer Use；没有改系统刷新率、Windows设置或停止其他工具服务。

## 源码与剖析范围

- `HomePage` 当前只把选中页面交给布局，没有发现把所有首页页面塞入永久运行的IndexedStack；`PopularController` 的加载/预热为有界定时任务，销毁时取消。
- `AppStatusView` 的默认加载动画由加载子树持有并在销毁时释放；本次截图为空状态而非加载状态。Windows runner的 `ForceRedraw` 只在初始化安排首帧，未见本项目新增无限重绘循环。以上是局部审查，不是完整排除所有业务性能问题。
- 本地Dart VM Service按实际已安装 `vm_service 15.3.0` 契约取样，调用地址由该进程stdout读取，只在本机访问。CPU profiler原值false，两次临时启用后均恢复false。
- 两段main isolate CPU采样均返回sampleCount=0，**未取得可归因的Dart热栈**，不能把0样本当作CPU为0。单实例管道isolate第一段有78样本，主要是Win32包装与sleep相关调用，未据此改插件。
- Timeline线程元数据把忙线程35956标记为 `io.flutter.ui`；抓取末20秒窗口未出现所筛选的Frame/BUILD/LAYOUT/PAINT事件，主要有GC类事件。这只支持继续检查原生消息工作，不足以认定具体函数或消息根因。
- Flutter官方仓库的 [#183262](https://github.com/flutter/flutter/issues/183262) 有Windows空模板CPU偏高及WM_NULL的用户报告，所用Flutter为3.41.2；当前项目3.47.0且本轮最小化时CPU下降，不能认定同一根因。没有照搬报告中的消息循环延时。GitHub匿名API取评论遇限流，仅把已读取的Issue正文作为线索。

## 验收方法修订与下一步

后续性能记录必须分开标明：窗口可见/最小化/遮挡、观察工具是否曾连接、是否正抓取截图/无障碍树、是否启用CPU profiler，以及页面内容和距启动时间。第一段低值与后续观察关联只是初始假设，已由重复样本修正；不作为“观察工具故障”或“应用已修复”的结论。

下一步在同一固定SDK构建一个不带业务插件的最小Windows runner，对照可见/最小化及Debug/Release；如最小样本复现，再测消息种类/调用栈；如不复现，再逐层缩小本项目插件和页面。保留播放、长录、签名续接、多平台及发布验收的原范围，不用此诊断替代它们。

证据目录 `local-artifacts/windows-cpu-fadd5bdb-20260907/`：三组进程、CPU窗口JSON、60秒CSV/summary、VM flags与采样、timeline及摘要、stdout/stderr、清理result。三PID76248/63028/43332均正常退出后查询消失；采样会话全部终止。没有手机操作、模块改动或应用数据删除。

## 后续：无业务插件的 Debug / Release 最小程序

在本地忽略目录 `local-artifacts/windows-minimal-probe-20260907/` 新建隔离项目，使用相同 Flutter **3.47.0**（framework `4cf24164269a5ebf0c16a028a00727d0e77bbb05`，engine `5f77625673248ee5846fbcaf5d3e1a3878386fd7`，Dart 3.13.0）。固定 SDK 的 `create --empty --platforms=windows --no-pub` 生成 Windows runner；离线解析依赖后串行 `build windows --debug/--release --no-pub`，两次均在仓库重型资源守卫内。没有改产品工程或依赖锁文件。

最小程序仅保留以下静态页面，无业务定时器、播放器、网络请求或插件；生成的普通插件和 FFI 插件列表均为空，`RegisterPlugins` 函数体为空。默认 Windows runner 保持生成内容，未添加消息延时。

```dart
import 'package:flutter/material.dart';

void main() => runApp(const IdleProbe());

class IdleProbe extends StatelessWidget {
  const IdleProbe({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(body: Center(child: Text('Static Flutter idle probe'))),
  );
}
```

Debug / Release 构建前后核对 Dart、pubspec/lock、runner 和生成插件清单共7个文件的 SHA-256，均未变化。两种配置及此前 Pure Live Debug 的 stderr 均记录 Impeller OpenGLESSDF 后端。本轮未开启 VM CPU profiler，未连续抓取主比较样本的截图/无障碍树，也未修改显示设置。

| 构建 | 守卫及构建记录耗时 | Flutter 构建耗时 | 结束活跃重型进程 | exe SHA-256 |
| --- | ---: | ---: | ---: | --- |
| Debug | 129.041秒 | 58.0秒 | 0 | `50AC799D2715E12B041D0A1C38ABAAD7542B37458BFA8D8A89CE6ED3C164B2CD` |
| Release | 87.534秒 | 59.5秒 | 0 | `E5C956F18F21A062AD3350FD04458959AE8FB7DE4E3514F32DB4D561669C6201` |

上述是**隔离诊断程序**的构建结果，不是 Pure Live 新候选或全量测试。两次开始曾等待其他项目 Java 工作，遵守排队且未结束其进程；本任务的构建与 CPU 采样没有重叠。采样使用已有 `tool/sample_windows_runtime.ps1`，24逻辑核归一化、排除首个基线、间隔5秒；每段60秒、13次响应检查。显示元数据仍为 RTX5090 Laptop、3840×2400@200Hz，另有 Oray 虚拟显示驱动；GPU未采样。

| 程序/PID | 窗口条件 | 实际秒数 | CPU均值 | CPU P95 | 响应 |
| --- | --- | ---: | ---: | ---: | --- |
| 最小Debug / 70004 | 静态页可见 | 60.413 | 0.2426% | 0.3123% | 13/13 |
| 同PID | 已确认最小化 | 60.620 | 0.0132% | 0.0276% | 13/13 |
| 同PID | 恢复静态页 | 60.447 | 0.2878% | 0.4820% | 13/13 |
| 最小Release / 56164 | 静态页可见 | 60.490 | 0.3060% | 0.4044% | 13/13 |
| 同PID | 已确认最小化 | 60.637 | 0.0067% | 0.0172% | 13/13 |
| 同PID | 恢复静态页 | 60.531 | 0.3078% | 0.3779% | 13/13 |

Release恢复段工作集114.8164→114.8477 MiB、private bytes379.6680→379.6406 MiB。这是短期静态模板采样，不是产品长时内存稳定性结论。

观察例外保留：Debug恢复采样结束后首次截图返回 `no monitor found for window`，重新选取并激活同窗口后恢复；未由此宣称整段遮挡状态完全受控。Release第一次坐标最小化后的截图仍显示遮挡画面，没有得到明确最小化状态，该60.564秒样本（CPU0.0098%）**排除在上表之外**。随后重新观察无障碍树，操作其实际“最小化”按钮，工具明确返回 `window is minimized`，才进行上表的确认样本。Debug最小化亦得到该明确状态。可见/恢复阶段采样前截图核对静态文字；未通过持续截图保证用户桌面每一刻的遮挡状态。

### 推论边界与下一步

- **确定**：无业务插件的模板在Debug与Release都出现可见性相关CPU差异；“全部来自Pure Live业务代码”或“全部只是Debug开销”均不足以解释这组模板观测。
- **尚未确定**：该约0.24–0.31%的负载是否是引擎缺陷、图形/显示环境、观察条件或其他原生路径；也未解释Pure Live空关注页约0.96%以及热门页约2.3%的额外负载。短串行样本不支持据此判断Release比Debug更慢。
- 下一步优先构建并测量**当前Pure Live自身Release候选**的相同空页面/可见性组合，区分产品与模板差额，并继续播放后资源回落验收。仍有异常时，在隔离runner中测量消息种类或原生调用栈；保持产品消息循环和系统设置原状，避免无根因延时补丁。长录、平台能力和最终发布仍按原范围继续。

本地证据包含 `build-probe.ps1`、两种构建JSON/log、SDK身份、源文件/engine/exe哈希、7项同源检查、7组CSV/summary、`observation-context.json`及进程启动/退出记录。Debug和Release按标题栏正常关闭后，PID70004/56164均查询消失。两次构建及全部采样命令已取得exit0；没有手机、MT、LSP或Root操作，没有改变应用版本、正式候选ZIP/APK、用户数据或发布状态。
