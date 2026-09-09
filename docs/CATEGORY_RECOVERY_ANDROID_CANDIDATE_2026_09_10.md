# 分类与失败恢复累计 Android 候选（2026-09-10）

## 状态与输入

干净提交 **152cf1513f3c44d769349cd33262a6fffe113d5e** 已构建 Android arm64 Debug 并独立归档，**未安装、未发布**。版本保持 3.1.8+4121，不是 3.2.0 稳定版。

相对[前候选 f5aab636](SHARED_UI_ANDROID_CANDIDATE_2026_09_10.md)，只有四个生产文件有累计差异：base_page_view、server_all_page_controller、areas_grid_view、areas_list_controller。包含[空分类导航](AREA_TAB_NAVIGATION_AUDIT_2026_09_10.md)、[目录控制器归属](AREA_TAXONOMY_OWNERSHIP_AUDIT_2026_09_10.md)、[空页失败恢复](RETAINED_PAGE_RECOVERY_AUDIT_2026_09_10.md)与[刷新中点击意图](AREA_REFRESH_INTENT_AUDIT_2026_09_10.md)。

构建前核对最后 34 项分类验证记录的四份输入哈希，以及 197 项恢复验证记录中仍有效的共用页与测试哈希。较旧的 area_tab_refresh_test 输入由末次 34 项记录覆盖，不以旧哈希证明新测试。复用这些定向结果和严格分析，没有声称当前累计提交通过了完整发布门禁；重叠测试数不相加。

## 产物核验

| 项目 | 结果 |
| --- | --- |
| 包名 | com.mystyle.purelive |
| versionName / 基础 build / Manifest code | 3.1.8 / 4121 / 6121 |
| ABI / 原生库 | arm64-v8a，16 个库，ELF LOAD 最小对齐 0x4000 |
| APK 对齐 / Flutter 资源 | 16 KB 通过；1,262 项，205,973,604 B |
| APK 大小 | 288,493,053 B |
| SHA-256 | `43BE5AEAF5AE0CA2A2C60DCE78EBDCA7F633501567453764096BCEC2436D26F5` |
| 签名 | v2，单一 Android Debug 签名者 |
| 证书 SHA-256 | `1e832295a696cf8210bca063e458bad0be12dfa64939d3362ff11b8f237ff7b9` |

独立归档：`local-artifacts/candidates/android-152cf151/`，包含 APK、BUILD_METADATA、build-record、signature.log、archive-verification 和 native-handoff-plan。复制后 SHA 再次一致，前候选 f5aab636 的原归档 SHA 保持。

完整中英文翻译与版本 JSON 与源码比较一致；测试 TLS 私钥和夹具目录未入包。不是只凭文件名或版本号判断产物内容，也未将 Debug 签名作为正式发行签名。

## 当前设备只读证据

2026-09-09T22:06:29Z 核对 `192.168.1.2:5555` 为 **25102RKBEC / myron**，后续命令均显式指定该 serial。前台为 `tv.danmaku.bili/.MainActivityV2`，Pure Live 无 PID；本轮不切换前台。

已安装包仍显示 3.1.8 / 6121，lastUpdateTime 为 2026-09-07 20:39:14。设备 APK SHA `D965095AC696FC98D000E89542835F98C8A0C30DA0DF54EF4089D19571762E8D` 与已验签备份一致，故候选与当前安装包的同签名关系有字节哈希链证据；本轮没有重新下载相同旧 APK。

**本轮没有读取应用数据文件或重取状态备份。** 已安装 APK 一致不等于用户数据未变；历史 schema 6 数据与本机 schema 7 演练仅为此前证据。覆盖安装前仍须重新确认设备窗口和当前状态，取得一致且校验通过的备份。回退 APK 不等于回退数据库。

未操作 Root/LSP/MT、重启、网络切换、调试端口/授权或全局 ADB 重置。设备身份、前台与 APK 哈希证据位于 `local-artifacts/category-recovery-android-candidate-20260910/`。

## 交接与资源

交接清单从上一份实际 57 项继承，增加空分类导航、目录身份/资源归属、保留空页失败恢复、刷新点击意图四组，**共 61 项，全部 not-run、ID 唯一**。重新生成当前源码、唯一 APK SHA 和核验路径，再按序列化结果复核。它与宏观大组、已有场景存在覆盖重叠，不表示 61 个独立缺陷。

Windows 原生分类、错误恢复和鼠标/键盘操作另列待验；Windows 最新候选仍为 2fb471d3，本轮未更新。

| 阶段 | build-records 记录 | 秒 | 峰值 CPU / 工作集 B | 结束活跃重型进程 |
| --- | --- | ---: | --- | ---: |
| Android Debug | 20260909T220827821Z-build-androidarm64-debug.json | 116.353 | 62.46% / 11,290,361,856 | 0 |
| 签名/内容/归档 | 20260909T220851546Z-android-archive-152cf151.json | 9.863 | 0.72% / 9,647,472,640 | 0 |

两阶段经资源守卫串行执行，保留增量缓存；未观察到配置缓存复用或 FROM-CACHE/UP-TO-DATE。Firebase 插件 KGP 的将来兼容性提示未造成此次构建失败，也未触发依赖更新。

当前仍为 19 个直播站点 + IPTV、8 组参考平台未注册；宏观 20 PASS / 32 RUN / 10 NR，42 组未闭环。下一阶段继续本地审查与双端验证，取得明确 Pure Live 设备窗口后再执行备份、保留数据覆盖安装和原生场景，不提前发布 3.2.0。
