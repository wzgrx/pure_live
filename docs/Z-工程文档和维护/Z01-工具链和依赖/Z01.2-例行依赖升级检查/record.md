# Z01.2 例行依赖升级检查：记录

## 2026-10-08

- `GITHUB_TOKEN=$(gh auth token) dart run tools/check_latest/bin/check_latest.dart`：59 项，8 项落后，查询全部成功。
- 升了 6 个 pub 包（都在原约束内，只改 `pubspec.lock`）：url_launcher 6.3.2 → 6.3.3、drift 2.35.1 → 2.35.2、connectivity_plus 7.3.1 → 7.3.2、hive_ce 2.20.1 → 2.20.2、share_plus 13.3.0 → 13.3.1、material_ui 1.5.0 → 1.6.0。`tools/gate/gate.sh --all` 通过（14 个成员）。
- 没升：Flutter 3.47.5 → 3.47.6、Gradle 9.8.0 → 9.8.1（工具链，要换本机 SDK；当时有多个代理在用同一个 SDK 跑测试，下次一并升，改 `toolchain.env` 后跑门禁和一次 APK 构建）。
- 下次：2026-11 上旬。
