# Y01.6 4.2.0 发布：记录

- 日期：2026-10-14
- 发布说明：[releases/v4.2.0.md](../../Y03-发布说明和README/releases/v4.2.0.md)，范围 `git log v4.1.0..master`（12 个提交：A07.24 七个、A03.4、A01.5、Z01.2 两个、4.1.0 的更新文件）。
- 真机：用户说“快速测试”，照 4.1.0 做轻量冒烟。

## 逐阶段

| 阶段 | 做了没有 | 结果 |
|---|---|---|
| 1 版本号和发布说明 | 做了 | `4.2.0+5004`，`releases/v4.2.0.md` |
| 2 构建和检查 | 做了 | `0cbb1c33d`，结果见下面“检查结果”，全部通过 |
| 3 K90 冒烟 | 做了（轻量） | 同一提交的 v4dev 测试包（4.2.0 / 5004），2026-10-14 23:55～23:59：冷启动 483 毫秒；液体玻璃浅色模式胶囊半透明、后面的文字模糊（深色在 A01.5 已看过）；小窗从全宽用把手缩小，紧凑布局没有静音；往左拖出边缘收进去，点露出的一条回来；从左边往右甩，松手约 0.1 秒离终点约 4 像素，贴到右边 16 处、没有越过。没测：画中画（A07.24 已在 K90 看过）、小窗静音和弹幕开关、位置记忆 |
| 4 标签、发布页和安装包 | 做了 | 附注标签 `v4.2.0`（“Pure Live 4.2.0 (Android), build 5004”）在 `0cbb1c33d`；发布页 https://github.com/wzgrx/pure_live/releases/tag/v4.2.0 （标题“纯粹直播 v4.2.0”，照 4.1.0），2026-10-14 16:17（UTC）上线，设为最新；三个 APK 和 `SHA256SUMS.txt`，GitHub 记的 SHA-256 和本机一致；正文是 `releases/v4.2.0.md` |
| 5 更新文件 | 做了 | `assets/version.json`（顶层和 android：4.2.0、5004、402005004、新的说明和链接）、`assets/releases.json`（最前面加 4.2.0，日期按北京时间 2026-10-15，changelog 是发布说明去掉“下载哪个”“SHA-256”）、`version_page_test.dart` 跟着改 |

## 检查结果（第 2 阶段）

| 项 | arm64-v8a | armeabi-v7a | x86_64 |
|---|---|---|---|
| 文件大小（字节） | 111497891 | 98635043 | 123212429 |
| SHA-256 | `3676873a54604631b828aa72f9558843a7f941498e8bd25640d186420ba24d54` | `aaed95bdf540981185346aae24ef9757c25cd9697a716ed44731b28efae3ac4a` | `0efd2d8931ba7fa2ecca8a3dcff9b18b22e042088abe8efc2b9a7ac9e95c9dcf` |
| `aapt2 dump badging`：包名、versionCode、versionName | `com.mystyle.purelive`、`7004`、`4.2.0`（minSdk 26） | `6004` | `9004` |
| 证书 SHA-256（`apksigner verify --print-certs`） | `1e832295a696cf8210bca063e458bad0be12dfa64939d3362ff11b8f237ff7b9`（只有 v2） | 同左 | 同左 |
| 保留的资源（四个图标） | 四个都在 | 四个都在 | 四个都在 |
| 16 KB 对齐（`zipalign -c -P 16 -v 4`） | 14 个 `.so` 全部 OK | 同左 | 同左 |

- 构建：提交 `0cbb1c33d`，2026-10-14，在单独的工作区 `release-420` 里 `flutter build apk --release --split-per-abi`（483 秒）；安装包和 `SHA256SUMS.txt` 本机留在 `~/ref/release/v4.2.0-5004/`。
- `python3 tools/release/check_version.py`：“release: 4.2.0+5004 可以发布”。
- 注意：`zipalign` 的对齐数（`4`）不能省，省了只打印用法、`grep` 会误以为没有问题。
