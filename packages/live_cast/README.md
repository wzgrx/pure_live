# live_cast

v4 的 DLNA 投屏包（纯 Dart，只用 `dart:io`，不依赖 Flutter 和其它 `live_*` 包）：SSDP 搜索局域网里的媒体渲染器、读设备描述、用 SOAP 控制 AVTransport。行为见 [spec/product.md](../../spec/product.md) F-CAST-01，决策见 [docs/adr/0027-dlna-cast.md](../../docs/adr/0027-dlna-cast.md)。

## 用法（应用）

```dart
final http = IoCastHttp();                               // 直连，不走代理
final discovery = CastDiscovery(http: http);              // 默认 4 秒，每个 IPv4 接口各发一次 M-SEARCH，1 秒后重发
await for (final device in discovery.search()) { … }     // 按 USN 去重；取消订阅即停止搜索

final renderer = DlnaRenderer(device, http: http);
await castTo(renderer, CastMedia(url: url, title: '主播 - 标题', mimeType: CastMime.flv));  // 先设源再播放
await renderer.stop();
final info = await renderer.transportInfo();              // PLAYING / STOPPED / …
```

失败都是 `CastFailure` 的子类：`CastSearchFailure`（搜索起不来）、`CastTimeoutFailure`、`CastNetworkFailure`、`CastHttpFailure`、`CastProtocolFailure`、`UpnpActionFailure`（带 UPnP 错误码，`error` 是 `UpnpError`）。

## 测试

套接字（`SsdpSocket`）和 HTTP（`CastHttp`）都可以注入，单元测试用假实现和 `fake_async`，不访问网络；`http_test.dart` 和一个套接字用例只用本机回环。`test/samples/` 里是小米电视、乐播、Kodi 风格的设备描述。
