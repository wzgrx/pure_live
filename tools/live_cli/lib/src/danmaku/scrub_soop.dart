import 'package:live_cli/src/danmaku/frame_scrub.dart';
import 'package:live_cli/src/danmaku/recorder.dart';
import 'package:live_danmaku/live_danmaku.dart';

/// SOOP (spec/sites/soop.md §11): chat senders (id, nick) get pseudonyms;
/// the viewer lists and flags (services 4, 127, …) and every other service
/// that is not decoded keep their header and lose their body. Login and
/// join packets carry only the public room and broadcaster ids.
class SoopFrameScrubber extends FrameScrubber {
  /// Creates the scrubber.
  new(super.detail, {super.seed});

  static const _kept = {0, 1, 2};

  @override
  List<int>? scrubFrame(CapturedFrame frame) => [
    for (final packet in SoopProtocol.packets(frame.bytes)) ..._packet(packet),
  ];

  List<int> _packet(SoopPacket packet) {
    if (_kept.contains(packet.service)) return SoopProtocol.packet(packet.service, packet.fields);
    if (packet.service == 5 && packet.fields.length >= 7) {
      final fields = [...packet.fields];
      final id = RegExp(r'^(.*?)(\(\d+\))?$').firstMatch(fields[2])!;
      fields[2] = '${names.secret(id.group(1)!)}${id.group(2) ?? ''}';
      fields[6] = names.person(fields[6]);
      record('chat.sender', 'person');
      return SoopProtocol.packet(5, fields);
    }
    record('service.${packet.service}', 'dropped');
    return SoopProtocol.packet(packet.service, const []);
  }
}
