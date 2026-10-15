# flutter_inappwebview_linux（替身）

纯粹直播在 Linux 上不提供应用内网页（`InAppWeb.available` 在 Linux 上是 false），用这个没有原生代码的替身代替 flutter_inappwebview 的 Linux 实现，Linux 版就不用装 WPE WebKit。根 `pubspec.yaml` 的 `dependency_overrides` 指向这里（X02.1）。
