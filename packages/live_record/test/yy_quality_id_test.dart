// E06.3: with YY's FLV first (6-1) the qualities come from stream-manager
// (ids '2', '1'), so a recording task that remembered a mobile HLS quality
// (`mobile-hls:4000`, `mobile-hls:1200`) moves to the FLV quality that
// stands for it (YyApi.flvQualityId) instead of losing its choice.
import 'package:live_core/live_core.dart';
import 'package:live_net/testing.dart';
import 'package:live_record/live_record.dart';
import 'package:test/test.dart';

const _root = '../../fixtures/yy';
const _live = '22490906';

/// YY with FLV first over the recorded answers of channel 22490906: the
/// detail and stream-manager's qualities 高清 ('2') and 流畅 ('1'); the
/// URLs are scripted (the recordings hold one gear's lines only).
final class _YyFlvFirst extends LiveSite {
  final YySite _yy = YySite(
    ReplayHttp(
      [
        for (final name in ['S05-detail-live', 'S06-streams-g1']) ReplaySample.load('$_root/$name'),
      ],
      ignoredQuery: const {'seq', 'send_time', 'sequence', 'osversion', 'width', 'height'},
    ),
    flvFirst: true,
    now: () => DateTime.utc(2026, 9, 27, 16, 56, 56),
  );

  @override
  String get id => SiteIds.yy;

  @override
  String get name => 'YY';

  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) => _yy.getRoomDetail(roomId: roomId);

  @override
  Future<List<LivePlayQuality>> getPlayQualities({required LiveRoom detail}) => _yy.getPlayQualities(detail: detail);

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async => [
    'https://cdn.example/${quality.selectionId}.flv',
  ];
}

Future<ResolvedRecordStream> _resolve(LiveSite site, {required String preferred, String? previous}) =>
    RecordStreamResolver((_) => site)
        .resolve(roomId: _live, platform: SiteIds.yy, preferredQuality: preferred, previousQualityId: previous);

void main() {
  test('a remembered mobile-hls:4000 records the best FLV quality', () async {
    // 流畅 preferred: without the move the task would fall back to 流畅.
    final stream = await _resolve(_YyFlvFirst(), preferred: '流畅', previous: 'mobile-hls:4000');
    expect((stream.quality.quality, stream.qualityCursorId), ('高清', '2'));
  });

  test('a remembered mobile-hls:1200 records the lowest FLV quality', () async {
    final stream = await _resolve(_YyFlvFirst(), preferred: '原画', previous: 'mobile-hls:1200');
    expect((stream.quality.quality, stream.qualityCursorId), ('流畅', '1'));
  });

  test('an FLV id, no id and an unknown id keep their meaning', () async {
    expect((await _resolve(_YyFlvFirst(), preferred: '原画', previous: '1')).qualityCursorId, '1');
    expect((await _resolve(_YyFlvFirst(), preferred: '原画')).qualityCursorId, '2');
    expect((await _resolve(_YyFlvFirst(), preferred: '原画', previous: 'mobile-hls:999')).qualityCursorId, '2');
  });
}
