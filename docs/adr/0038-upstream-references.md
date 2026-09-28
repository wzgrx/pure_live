# 0038 上游参考仓库：电视端照 pure_live_TV 复刻，另外三个作为长期参考

- 状态：已接受（修改 ADR 0037 第 3 条中电视模式的部分）
- 日期：2026-09-28

## 背景

- 用户指定了 4 个上游仓库，要求后续全部阅读参考。它们都出自 3.x 的上游作者 liuchuancong，并且仍在更新：
  - [pure_live_TV](https://github.com/liuchuancong/pure_live_TV)：pure_live 的电视版。
    - 34 个直播平台加 IPTV，比 v4 多一个 Kick，另有哔哩哔哩音乐；
    - 功能上还有音乐模式、视频模式、壁纸和网页遥控；
    - AGPL-3.0。
  - [flame_barrage](https://github.com/liuchuancong/flame_barrage)：基于 Flame 的弹幕渲染引擎，3.x 用的是它的旧内置版；MIT。
  - [media_core](https://github.com/liuchuancong/media_core)：跨平台播放器核心，负责会话、命令串行化、恢复决策、池化、系统媒体面等；AGPL-3.0。
  - [flv_lzc](https://github.com/liuchuancong/flv_lzc)：基于 ijkplayer 的播放插件（fijkplayer 修复版），3.x 用它播 FLV 和 H.265；MIT。
- ADR 0037 原来决定电视模式保留 v4 的实现，因为 3.x 没有电视界面。但 pure_live_TV 就是和 3.x 同源的电视界面，而用户要求“所有平台都要复刻”。

## 决定

1. **电视端照 pure_live_TV 复刻**。
   - 范围：导航、各页面、直播间、设置、IPTV、焦点和按键行为、视觉，都以它为蓝本。
   - 做法同 ADR 0037 第 6 条：代码按 v4 的方式重写，修掉它的问题，不改变外观和操作习惯的增强可以同时做。
   - 由复刻的 E 组在第 0 波（基础外观）合并后进行。
   - 它有而 v4 没有的功能（音乐模式、视频模式、壁纸、网页遥控等），逐项评估后决定，记在 E 组的复刻文档里。
2. **另外三个作为长期参考，不直接依赖**：
   - 弹幕渲染仍用 live_danmaku 自己的渲染器（ADR 0020），行为和功能对齐 flame_barrage。是否改为直接依赖它，等分析文档出来后另行决定。
   - 播放仍是 live_media、live_player 加自维护的 media_kit（ADR 0002、0006、0018）。media_core 的设计和模块可以借鉴或移植。
   - v4 只用 mpv，所以 flv_lzc 只借鉴低延迟和 FLV 的经验，换算成 mpv 的选项。
3. **平台层**：pure_live_TV 的站点实现比 v4 新的地方（修复、签名、风控、Kick 等），按分析文档的行动清单逐项补到 live_core 和 live_danmaku，每个站点的规格同步更新到 spec/sites。
4. **许可证**：
   - AGPL-3.0 的两个仓库与 v4 相同，借鉴或移植代码时，在文件头和文档里注明来源仓库和提交；
   - MIT 的两个仓库，借鉴时保留版权声明；
   - 不引入与 AGPL-3.0 不兼容的代码。
5. **长期跟踪**：
   - 4 个仓库克隆在本机 `~/ref/`，做相关模块之前先 `git pull` 看新提交；
   - 分析文档放在 `docs/reference/`，写明分析时对应的提交。

## 放弃的做法

- 电视端继续保留 v4 自己设计的界面：和用户“所有平台都要复刻”的要求不符，而且上游已经有成熟的电视版。
- 把 pure_live_TV 或 media_core 整体并进来：它们的结构和 v4 的包划分不同，整体并入会带回旧问题。只按模块借鉴。

## 影响

- ADR 0037 第 3 条“电视模式整体保留 v4 的实现”改为：电视端照 pure_live_TV 复刻（本 ADR）。
- ADR 0026（电视模式）的焦点体系可以保留，界面和交互按 pure_live_TV 调整；如有冲突，以复刻为准。
- 新增 `docs/reference/`，收录 4 个仓库的分析文档。
