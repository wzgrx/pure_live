import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

String describe(SiteError error) => switch (error) {
  NotFound() => 'not found',
  NeedsLogin() => 'login',
  RateLimited(:final retryAfter) => 'wait ${retryAfter?.inSeconds}',
  RiskControl(:final cookieSuspect) => cookieSuspect ? 'renew cookie' : 'risk',
  RegionBlocked() => 'region',
  StreamUnavailable() => 'no stream',
  UnsupportedLink() => 'link',
  ApiChanged() => 'api',
  NetworkFailure() => 'network',
};

void main() {
  test('every SiteError kind is handled by an exhaustive switch', () {
    expect(describe(const RateLimited('kuaishou', retryAfter: Duration(seconds: 60))), 'wait 60');
    expect(describe(const RiskControl('kuaishou', cookieSuspect: true)), 'renew cookie');
    expect(const NetworkFailure('douyu').isTransient, isTrue);
    expect(const NotFound('huya', 'status 422').isTransient, isFalse);
    expect(const ApiChanged('douyin', 'enter: data missing').toString(), 'ApiChanged(douyin: enter: data missing)');
  });

  test('a page without a cursor is the last page', () {
    expect(const Page<int>([1, 2]).isLast, isTrue);
    expect(const Page<int>([1, 2], next: PageCursor('2')).isLast, isFalse);
    expect(const Page<int>.empty().items, isEmpty);
  });

  test('audience measures stay separate', () {
    const heat = Audience(popularity: 3550728);
    expect(heat.online, isNull);
    expect(heat.cumulative, isNull);
    expect(Audience.none.isEmpty, isTrue);
    expect(heat, const Audience(popularity: 3550728));
  });

  test('a line reports the confirmed quality when the server downgraded it', () {
    const original = Quality(id: '0', label: '原画', rank: 100);
    const fourM = Quality(id: '4', label: '蓝光4M', rank: 80);
    final line = StreamLine(
      url: Uri.parse('https://cdn.example.test/live/1.flv?expire=300'),
      format: StreamFormat.flv,
      lineId: 'hw-h5',
      requested: original,
      confirmed: fourM,
      lease: Lease(
        refreshAt: DateTime.utc(2026, 9, 27, 10, 4, 15),
        expiresAt: DateTime.utc(2026, 9, 27, 10, 5),
        cutsConnection: true,
      ),
    );
    expect(line.effective, fourM);
    expect(line.lease!.cutsConnection, isTrue);
    final unconfirmed = StreamLine(
      url: Uri.parse('https://tx.flv.huya.com/src/1.flv'),
      format: StreamFormat.flv,
      lineId: 'TX',
      requested: original,
    );
    expect(unconfirmed.effective, original);
  });

  test('a lease that refreshes after it expires is rejected', () {
    expect(
      () => Lease(
        refreshAt: DateTime.utc(2026, 9, 27, 11),
        expiresAt: DateTime.utc(2026, 9, 27, 10),
        cutsConnection: false,
      ),
      throwsA(isA<AssertionError>()),
    );
  });

  test('a detail exposes its card identity and state', () {
    final detail = RoomDetail(
      card: RoomCard(ref: RoomRef('douyu', '5526219'), title: '标题', anchorName: '主播', state: LiveState.live),
      link: Uri.parse('https://www.douyu.com/5526219'),
      danmakuKeys: const {'rid': '5526219'},
    );
    expect(detail.ref.key, 'douyu:5526219');
    expect(detail.state, LiveState.live);
  });
}
