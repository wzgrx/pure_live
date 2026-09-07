import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/core/interface/live_site.dart';
import 'package:pure_live/model/live_play_quality.dart';

class ToolBoxTestSite extends LiveSite {
  final room = LiveRoom(roomId: '123', platform: 'bilibili');
  List<LivePlayQuality> qualities = [LivePlayQuality(quality: 'HD', id: 1), LivePlayQuality(quality: 'SD', id: 2)];
  List<String> urls = ['https://cdn.example/a.flv', 'https://cdn.example/b.flv'];
  final calls = <String>[];
  LivePlayQuality? requestedQuality;
  Future<LiveRoom>? detailReply;
  Future<List<LivePlayQuality>>? qualityReply;
  Future<List<String>>? urlReply;
  @override
  Future<LiveRoom> getRoomDetail({required String roomId, required String platform}) {
    calls.add('detail');
    return detailReply ?? Future.value(room);
  }

  @override
  Future<List<LivePlayQuality>> getPlayQualites({required LiveRoom detail}) {
    calls.add('qualities');
    return qualityReply ?? Future.value(qualities);
  }

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) {
    calls.add('urls');
    requestedQuality = quality;
    return urlReply ?? Future.value(urls);
  }
}
