import 'dart:async';
import 'dart:developer';

import 'package:bonsoir/bonsoir.dart';

/// A device found over mDNS: 3.x's TXT record (`id`, `name`, `platform`,
/// `version`, `ip`) and the service's address and port.
typedef MdnsPeer = ({String id, String name, String platform, String version, String ip, int port});

/// mDNS announce and discovery of the sync service, the way 3.x devices find
/// each other (`_purelive-sync._tcp`, bonsoir).
abstract interface class MdnsPeers {
  /// Announces this device as [name] on [port] with [attributes] and reports
  /// other devices to [found] (several times as they resolve) and [lost].
  Future<void> start({
    required String name,
    required int port,
    required Map<String, String> attributes,
    required void Function(MdnsPeer peer) found,
    required void Function(String id) lost,
  });

  /// Stops announcing and listening.
  Future<void> stop();
}

/// [MdnsPeers] with bonsoir (3.x's `RemoteSyncService` discovery and
/// broadcast).
final class BonsoirPeers implements MdnsPeers {
  /// 3.x's service type.
  static const String serviceType = '_purelive-sync._tcp';

  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _events;
  final Map<String, String> _idsByService = {};

  @override
  Future<void> start({
    required String name,
    required int port,
    required Map<String, String> attributes,
    required void Function(MdnsPeer peer) found,
    required void Function(String id) lost,
  }) async {
    await stop();
    final ownId = attributes['id'] ?? '';
    try {
      final discovery = _discovery = BonsoirDiscovery(type: serviceType, printLogs: false);
      await discovery.initialize();
      _events = discovery.eventStream?.listen((event) {
        final service = event.service;
        if (service == null) return;
        switch (event) {
          case BonsoirDiscoveryServiceFoundEvent():
            _report(service, ownId, found);
            try {
              unawaited(Future.sync(() => discovery.serviceResolver.resolveService(service)).catchError((Object _) {}));
            } on Object {
              // The TXT record already carries the address.
            }
          case BonsoirDiscoveryServiceResolvedEvent() || BonsoirDiscoveryServiceUpdatedEvent():
            _report(service, ownId, found);
          case BonsoirDiscoveryServiceLostEvent():
            final id = service.attributes['id']?.trim() ?? _idsByService.remove(service.name);
            if (id != null && id.isNotEmpty) lost(id);
          default:
            break;
        }
      });
      await discovery.start();
    } on Object catch (error) {
      log('mDNS discovery failed', name: 'RemoteSync', error: error);
    }
    try {
      final broadcast = _broadcast = BonsoirBroadcast(
        service: BonsoirService(name: name, type: serviceType, port: port, attributes: attributes),
        printLogs: false,
      );
      await broadcast.initialize();
      await broadcast.start();
    } on Object catch (error) {
      log('mDNS announce failed', name: 'RemoteSync', error: error);
    }
  }

  void _report(BonsoirService service, String ownId, void Function(MdnsPeer peer) found) {
    final attributes = service.attributes;
    final id = attributes['id']?.trim() ?? '';
    if (id.isEmpty || id == ownId) return;
    _idsByService[service.name] = id;
    final ipv4 = service.hostAddresses.where((address) => RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(address));
    final ip = ipv4.firstOrNull ?? attributes['ip']?.trim() ?? '';
    final name = attributes['name']?.trim() ?? '';
    found((
      id: id,
      name: name.isEmpty ? service.name : name,
      platform: attributes['platform'] ?? '',
      version: attributes['version'] ?? '',
      ip: ip,
      port: service.port,
    ));
  }

  @override
  Future<void> stop() async {
    await _events?.cancel();
    _events = null;
    final discovery = _discovery;
    final broadcast = _broadcast;
    _discovery = null;
    _broadcast = null;
    _idsByService.clear();
    for (final action in [discovery?.stop, broadcast?.stop]) {
      try {
        await action?.call();
      } on Object {
        // Already stopped.
      }
    }
  }
}
