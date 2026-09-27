import 'package:live_core/live_core.dart';
import 'package:pure_live_app/features/multiview/multiview_controller.dart';

/// Records per-room volumes in memory (CEL-9).
final class MemoryRoomVolumes implements RoomVolumes {
  final Map<RoomRef, double> stored = {};

  @override
  Future<double?> volumeOf(RoomRef room) async => stored[room];

  @override
  Future<void> setVolume(RoomRef room, double volume) async => stored[room] = volume;
}
