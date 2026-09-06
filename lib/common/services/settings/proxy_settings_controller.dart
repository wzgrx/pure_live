import 'package:pure_live/common/index.dart';
import 'package:pure_live/core/common/http_client.dart';
import 'package:pure_live/core/common/proxy_routing.dart';

class ProxySettingsController extends GetxController {
  final RxBool enableProxy = hiveBool('enableProxy', false);
  final RxString proxyHost = hiveString('proxyHost', '');
  final RxInt proxyPort = hiveInt('proxyPort', 7897);

  // app proxy settings
  final RxBool enableAppProxy = hiveBool('enableAppProxy', false);
  final RxString appProxyHost = hiveString('appProxyHost', '');
  final RxInt appProxyPort = hiveInt('appProxyPort', 7897);
  @override
  void onInit() {
    super.onInit();

    final normalizedAppHost = normalizeProxyHost(appProxyHost.v);
    if (normalizedAppHost != appProxyHost.v) appProxyHost.v = normalizedAppHost;
    final normalizedPlayerHost = normalizeProxyHost(proxyHost.v);
    if (normalizedPlayerHost != proxyHost.v) proxyHost.v = normalizedPlayerHost;

    ever<bool>(enableAppProxy, (_) => _refreshDioConnections());
    ever<String>(appProxyHost, (_) => _refreshDioConnections());
    ever<int>(appProxyPort, (_) => _refreshDioConnections());
  }

  void _refreshDioConnections() {
    try {
      HttpClient.instance.rebuildDio();
    } catch (_) {}
  }

  Map<String, dynamic> toJson() {
    return {
      'enableProxy': enableProxy.v,
      'proxyHost': normalizeProxyHost(proxyHost.v),
      'proxyPort': proxyPort.v,
      'enableAppProxy': enableAppProxy.v,
      'appProxyHost': normalizeProxyHost(appProxyHost.v),
      'appProxyPort': appProxyPort.v,
    };
  }

  /// Parse the complete section without notifying observers or persisting values.
  static Map<String, dynamic> parseConfig(Map<String, dynamic> json) {
    return {
      'enableProxy': (json['enableProxy'] ?? false) as bool,
      'proxyHost': normalizeProxyHost((json['proxyHost'] ?? '').toString()),
      'proxyPort': (json['proxyPort'] ?? 1080) as int,
      'enableAppProxy': (json['enableAppProxy'] ?? false) as bool,
      'appProxyHost': normalizeProxyHost((json['appProxyHost'] ?? '').toString()),
      'appProxyPort': (json['appProxyPort'] ?? 1080) as int,
    };
  }

  void fromJson(Map<String, dynamic> json) {
    final parsed = parseConfig(json);
    enableProxy.v = parsed['enableProxy'];
    proxyHost.v = parsed['proxyHost'];
    proxyPort.v = parsed['proxyPort'];
    enableAppProxy.v = parsed['enableAppProxy'];
    appProxyHost.v = parsed['appProxyHost'];
    appProxyPort.v = parsed['appProxyPort'];
  }

  static Map<String, dynamic> extractConfig(Map<String, dynamic>? rootConfig) {
    final proxy = rootConfig?['proxy'] as Map<String, dynamic>? ?? {};
    return {
      'enableProxy': proxy['enableProxy'] ?? false,
      'proxyHost': proxy['proxyHost'] ?? '',
      'proxyPort': proxy['proxyPort'] ?? 7897,
      'enableAppProxy': proxy['enableAppProxy'] ?? false,
      'appProxyHost': proxy['appProxyHost'] ?? '',
      'appProxyPort': proxy['appProxyPort'] ?? 7897,
    };
  }

  static Map<String, dynamic> mergeConfig(Map<String, dynamic> rootConfig, Map<String, dynamic> updateFields) {
    final proxy = Map<String, dynamic>.from(rootConfig['proxy'] ?? {});
    updateFields.forEach((k, v) => proxy[k] = v);
    rootConfig['proxy'] = proxy;
    return rootConfig;
  }
}
