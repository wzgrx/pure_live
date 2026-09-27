import 'package:flutter/foundation.dart';
import 'package:live_core/live_core.dart';

/// The app's own scheme (F-APP-05). `mystyle://` of 3.x is not handled: it
/// never worked there.
const deepLinkScheme = 'purelive';

/// A `purelive://` link (F-APP-05): a room or a LAN sync address.
@immutable
sealed class DeepLink {
  const new();

  /// Reads [text]; null when it is not a link of this app.
  static DeepLink? parse(String text) {
    final value = text.trim();
    if (!value.toLowerCase().startsWith('$deepLinkScheme://')) return null;
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme.toLowerCase() != deepLinkScheme) return null;
    final segments = [
      for (final segment in uri.pathSegments)
        if (segment.isNotEmpty) segment,
    ];
    // purelive://room/<platform>/<roomId>
    if (uri.host.toLowerCase() == 'room') {
      if (segments.length != 2) return null;
      try {
        return RoomDeepLink(RoomRef(segments[0].toLowerCase(), segments[1]));
      } on Object {
        // Not a valid room identity.
        return null;
      }
    }
    // purelive://<host>:<port>/sync?code=<code>, the LAN sync QR code (F-SYNC-01).
    if (uri.host.isNotEmpty && segments.length == 1 && segments.single == 'sync') return SyncDeepLink(value);
    return null;
  }
}

/// Opens a room.
final class RoomDeepLink extends DeepLink {
  /// The link to [room].
  const new(this.room);

  /// The room.
  final RoomRef room;

  @override
  bool operator ==(Object other) => other is RoomDeepLink && other.room == room;

  @override
  int get hashCode => room.hashCode;
}

/// Sends settings to a device that shows this address and code.
final class SyncDeepLink extends DeepLink {
  /// The link as scanned; the sync page reads host, port and code from it.
  const new(this.address);

  /// The scanned text.
  final String address;

  @override
  bool operator ==(Object other) => other is SyncDeepLink && other.address == address;

  @override
  int get hashCode => address.hashCode;
}

/// `purelive://room/<platform>/<roomId>` for [room].
Uri roomDeepLink(RoomRef room) => Uri(scheme: deepLinkScheme, host: 'room', pathSegments: [room.platform, room.roomId]);

/// Where the LAN sync page opens on its send tab with [address] filled in.
String syncLocation(String address) => Uri(path: '/me/backup/lan', queryParameters: {'target': address}).toString();
