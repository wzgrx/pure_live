/// PureLive's stand-in for flutter_inappwebview's Linux implementation
/// (X02.1): registers nothing, so no web view is offered on Linux.
library;

/// The class the plugin registrant calls on Linux.
abstract final class LinuxInAppWebViewPlatform {
  /// Registers nothing: the app checks `InAppWeb.available`, false on
  /// Linux, before opening a web view.
  static void registerWith() {}
}
