# 网络故障诊断与播放恢复审计

## 范围与根因

本轮以 `6889efa5` 为基线，修订提交为 `44b63210`。范围限播放器原生错误分类、既有有界恢复链和相邻录制/弹幕错误合同；没有执行直播站点生产探针、构建安装包、操作手机或执行 Windows GUI，Computer Use 与 Astra Light 使用均为 **0 次**。

`MediaKitPlayerAdapter` 会把 mpv/FFmpeg 的错误日志交给 `PlayerErrorClassifier`，只有立即终止型诊断才会进入 `PlayerManager` 的线路、签名源、内核和延迟重试链。审查确认三个可确定复现的缺口：

1. Android/Java 常见的 `UnknownHostException: Unable to resolve host ... No address associated with hostname`、curl 的 `Could not resolve host`、`getaddrinfo`、Apple 的 `nodename nor servname` 和 Windows 的 `No such host is known` 不在传输标记中，会降级为非终止型 `native_diagnostic`。
2. `Server returned 5xx` / `HTTP error 5xx` 同样会降级为普通原生日志；源站临时错误可能等到后续卡顿看门狗才触发恢复。
3. 通用的 `failed/error opening input` 原先先于具体 DNS/5xx 标记匹配，会把组合诊断误归为源错误；反向地，宽泛的 `codec` 标记又先于精确的 `could not find codec parameters`，使应刷新输入源的错误误入解码器恢复。

## 修订

- 补齐 Android、curl、POSIX/macOS 和 Windows 常见 DNS/主机解析诊断，以及明确的网络不可用标记。
- 使用严格三位 `5xx` 模式识别 mpv/FFmpeg HTTP 服务端失败，保留 401/403/404 为源/凭据类错误。
- 调整匹配优先级：具体传输标记优先于通用输入打开文本；精确源打开/参数错误优先于宽泛解码器运行时文本。组合日志现在保留最具体的恢复原因。
- 分类仍只负责把原生终态送入既有有界状态机；没有增加无限重试、修改用户暂停意图或改变播放器恢复预算。

## 确定性证据

- 首轮有效红灯中，新增 DNS 平台语法和 HTTP 5xx 两组均失败，结果为 **11 PASS / 2 FAIL**；扩充标记后的优先级红灯再次证明带 `Error opening input` / `Failed to open input` 前缀的具体传输错误仍被误归为源错误，也是 **11 PASS / 2 FAIL**。
- 最终分类器与来源代次直接回归 **13/13 PASS**。测试还锁定 401/403/404、输入参数、解码器和传输错误之间的分层，避免用网络修订吞掉确定的凭据、协议或解码问题。
- `local-artifacts/build-records/20260913T022058092Z-quality-focused.json` 覆盖分类器、播放器恢复、MediaKit/Fijk 缓冲、弹幕连接、FFmpeg 分类、录制源解析和失败重试界面八个文件，共 **186/186 PASS**；同一门禁只执行一次全库 `flutter analyze`，结果为 **No issues found**。
- 仓库静态策略、工具夹具、接口审计和 `git diff --check` 均通过，质量门禁结束后活跃重型进程为 0。

## 验收边界

上述证据使 A7-01 从 `NR` 进入 `RUN`：DNS/超时、HTTP 服务端失败、播放端断流后的分类与有界恢复已有确定性覆盖。当前候选上的真实网络切换、应用代理开关、系统网络恢复、跨网络切换和上游实际断流仍需分别取证；本轮没有借用源码测试宣称这些原生动作完成。
