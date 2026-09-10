# 会话型输入的直链与投屏入口审计（2026-09-10）

## 范围与来源

起点 `c8ae84c78355aa2ecc1817265c7f3404c6135e59`，3.1.8+4121；本轮补齐 3.2.0 平台扩展的共用消费者，不变更版本、不合并上游。分类为维护分支的 `fork-regression` 接线缺口：`86994582` 增加了公开输入配方，直链流仍保留 `18237494` 时的旧接口调用。尚未注册的会话型平台在这一入口没有完整能力处理，不宣称已经在现有 19 个平台的真机上复现。

第一个错误状态在 `ToolBoxDirectLinkFlow.run`：选择画质之后直接调用 `getPlayUrls`，跳过 `LivePlayUrlResolver`。因此 richer resolver 的会话配方、空结果或错误都可能被旧 URL 返回值覆盖；旧接口为空时又会给出通用解析失败。播放器菜单/控制栏经 `LiveUrlTool` → `KnownRoomLinkDialog`，工具箱经 `ToolBoxController`，均共用此流程。

## 修改

- 改用 `resolvePlayUrls`，普通站点仍由扩展方法调用旧接口并规范化 URL；有 richer resolver 时以它为准，不回退到旧 URL。
- 会话配方是有效播放源，但它没有独立于本应用会话的导出地址。给出中英文的应用内播放/录制提示，不打开线路列表、不复制、不进入 DLNA 接收端。
- 本入口只检查公开配方，不启动 WebSocket、seat、Cookie 容器或私有中继，也不从当前播放器提取 native-only 地址。
- 保持原动作作用域：退出、取消和网络超时后不弹出迟到提示、不继续导出；正常复制仍等待系统确认，投屏仍等待其子界面结束。
- 未改播放器播放、录制器、媒体引擎或多画面实现；主播放能力未被直链能力判断关闭。

## 验证

修改前同一个生产 flow + richer resolver 替身的 copy/cast 两项均失败：调用轨迹实际为 `detail, qualities, urls`，期望为 `detail, qualities, resolve`。记录 `local-artifacts/build-records/20260910T055353688Z-owned-export-repro.json`，退出码 1，69.52 秒，共享峰值 CPU 9.76%、工作集 11333992448 B，终态活跃重型进程 0。预期失败保留。

最终五个测试文件 **78/78 PASS**，五个修改/新增上下文的 Dart 文件 `dart analyze --fatal-infos` **No issues found**；固定 Flutter 3.47.0、`--no-pub --concurrency=12`，没有重解析依赖。记录 `local-artifacts/build-records/20260910T055730860Z-owned-export-regression.json`。耗时 176.93 秒（含编译/分析/资源守卫），共享峰值 CPU 9.58%、工作集 11572129792 B，终态活跃重型进程 0。实际命令、源码基线和逐文件 SHA-256 见记录；双语 JSON 另行解析和核对，最终来源散列见 `local-artifacts/owned-export-20260910/evidence.json`。

新增范围为 8 项流程测试和 6 项 Widget 测试：会话源复制/投屏、richer URL 优先与规范化、空结果、错误、取消选择、取消/超时后的迟到配方；中英文 320×480/2 倍文字下的工具箱与已知房间入口收尾。Widget 的通知是回调断言与语言文件读取，不是原生 Toast 截图或真实电视投屏证据。

## 剩余与回滚

- `MultiviewController.resolveStreamForSite` 仍以 `resolution.urls.isEmpty` 判断失败，`MultiviewStreamSource` 与每格播放器契约仍只承载 URL。下一步接入每格 owned source 的创建、换画质、取消、释放与恢复；不得用一个共享 seat/私有 URI 跨格复用，也不把提示代替多画面播放功能。
- niconico 的目录/分享/导航、完整 Site 适配和注册、真实网络长录、Android/Windows GUI 验收继续。
- 本轮没有手机操作、安装、构建或发布。Android 候选仍 `152cf151`（61 场景 not-run），Windows 仍 `2fb471d3`，均不包含本轮变更。
- 19 直播站点 + IPTV、8 组未注册、历史 62 组中的 42 组未闭环保持；这不是全目标完成率。
- 回滚只撤回本批 direct-link flow、对应文案和测试，不删除之前已经完成的播放/录制输入归属实现。
