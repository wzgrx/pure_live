# 0015 v4 应用与播放层的包结构

- 状态：已接受
- 日期：2026-09-27

## 背景

第 5、6 阶段合并推进（ADR 0014）。PLAN 第 05 节列出了包和依赖方向，但有三处需要落到具体做法：

1. `live_media` 既要被命令行工具调用，又要驱动 mpv 纹理；
2. 状态管理和路由的写法；
3. 预览版的包名和多语言。

## 决定

1. **播放层拆成两个包。**
   - `live_media` 是纯 Dart：
     - 播放内核接口 `PlayerEngine` 和它的事件顺序契约；
     - 本地中继：FLV 租期拼接、HEVC 标签转写；
     - 播放会话的状态机、线路选择、恢复策略。
     `live_cli` 可以直接调用它。
   - `live_player` 是 Flutter 包：用 media_kit（`third_party/` 的自维护分支）实现 `PlayerEngine`，提供视频组件。
   理由：media_kit 带原生构建钩子，纯 Dart 工具一旦依赖它，`dart run` 也会去下载 libmpv。
2. **Riverpod 3 手写 provider，不用代码生成。** 用 `Notifier`、`AsyncNotifier` 类和 `select` 精确订阅。go_router 用普通 `GoRoute`，路径和参数由一个集中的路由表函数构造，不用 go_router_builder。代码生成只用在 drift（`live_store`）。
   理由：少一套 build_runner 流程，迭代更快；Riverpod 3 手写 provider 同样类型安全。PLAN 第 04 节列出的 riverpod_generator、riverpod_lint 暂不引入，页面多到需要时再评估。
3. **预览版标识。**
   - 应用包名 `pure_live_app`，目录 `apps/pure_live`。
   - Android `applicationId` 为 `com.mystyle.purelive.next`，`namespace` 为 `com.mystyle.purelive`；切换到正式版时只改 `applicationId`。
   - 版本号 `4.0.0-preview.N`。
4. **多语言。** 预览版只有中文，界面文字集中在应用的 `lib/l10n/` 里，不散落在页面中。加第二种语言时再引入 slang（PLAN 第 04 节）。
5. **设计令牌由脚本生成。** `live_ui` 的颜色令牌由 `packages/live_ui/tool/generate_tokens.py` 从 `spec/design/tokens.json` 生成，测试检查两者一致。

## 备选方案与放弃理由

- `live_media` 做成 Flutter 包，命令行只引用其中的纯 Dart 文件：依赖解析仍会把 media_kit 的构建钩子带进 `dart run`。
- 一开始就用 riverpod_generator、go_router_builder、slang：三套代码生成，预览版阶段收益小。

## 影响

- `tools/gate/check_deps.py` 增加 `live_player`，并把 `live_media`、`live_store` 列为纯 Dart。
- PLAN 第 05 节的包列表增加 `live_player`。
