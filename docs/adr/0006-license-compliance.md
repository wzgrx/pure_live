# 0006 许可证合规：保留 AGPL-3.0，移除不兼容组件

- 状态：已接受（部分取代 0001 中“播放内核”一项）
- 日期：2026-09-27

## 背景

本项目派生自 `liuchuancong/pure_live`，使用 AGPL-3.0。依赖诊断（[diagnosis/07-dependencies.md](../rewrite/diagnosis/07-dependencies.md)）发现发行物中有与 AGPL 不兼容或存在风险的组件：

| 组件 | 问题 |
|---|---|
| fvp 附带的 libmdk | 专有免费软件（说明写明“对开源软件、非商业软件、Flutter 免费”），不提供源码，也不是系统库 |
| syncfusion_flutter_sliders | Syncfusion 专有许可，附加限制与 AGPL 冲突 |
| mobile_scanner 的 ML Kit 模型（libbarhopper_v3） | Google 专有条款，并依赖 GMS |
| Firebase（Android 端 play-services） | GMS 专有组件 |
| fuzzywuzzy | GPL-2.0，源码未写“或更高版本” |
| cronet_http 默认的 play-services-cronet | GMS 专有，国内无 GMS 机型不可用 |

另外，发行的 libmpv、FFmpegKit 使用 `--enable-version3` 构建（LGPLv3），这与 AGPL 兼容，但发布时必须提供对应源码（FFmpeg、mpv、libplacebo、dav1d、mbedtls 的确切提交、配置参数和补丁），目前没有做到。

用户提出，改动太多时可以考虑修改协议。

## 决定

1. **保留 AGPL-3.0**。仓库包含上游作者和其他贡献者的 AGPL 代码，改协议需要全部版权人同意，不可行；而合规需要的改动量不大。
2. **播放内核只用 mpv**（全平台）。移除 fvp 和 libmdk，取代 0001 中“Android mpv 为主、fvp 备用”。连带去掉 fvp 自带的第四份 FFmpeg（libffmpeg.so 7.9 MB）、libass，以及它间接引入的 video_player_android（Exo/Media3）。Android 上的兜底改为 mpv 自身的软解回退和 mediacodec 兼容模式。
3. **移除或替换**：Syncfusion 滑块改为 Material Slider；ML Kit 扫码改为 zxing-cpp 系的开源实现；Firebase 已决定移除；fuzzywuzzy 删除，相似度过滤改为自写实现。
4. **网络栈**：不使用依赖 GMS 的 Cronet。Android 的原生网络栈要么内嵌 Cronet（不依赖 GMS，需评估体积），要么继续使用 dart:io 并自行读取系统代理；第 4 阶段实测后另写决策记录。
5. **对应源码**：每个发布（包括 `native-*` 依赖资产）附带原生库的源码包，包含上游提交、配置参数和本仓库补丁。由 CI 自动生成和上传。
6. **构建约束**：FFmpeg 永不使用 `--enable-nonfree`；Linux 的 mpv 构建显式指定 TLS 库，避免被自动加上 nonfree。
7. **持续检查**：CI 检查每个依赖的许可证，新增依赖若是专有、GPL-2.0-only 或许可证不明，门禁失败。

## 备选方案与放弃理由

- 修改协议：需要全部版权人同意，不可行。
- 为 libmdk 申请链接例外：同样需要全部版权人同意，而且 fvp 带来的体积和重复 FFmpeg 本来就是要去掉的。

## 影响

- 3.3.x（旧应用）应尽快移除 Syncfusion、fuzzywuzzy 和 13 个未使用的依赖，并在发布中附上原生库源码包。
- 设置里选择了 fvp 内核的用户，升级后自动改为 mpv。
- 宪法“已确认的决定”中播放内核一项同步修改。
