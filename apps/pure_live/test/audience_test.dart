import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:pure_live_app/core/audience.dart';

void main() {
  test('F-DSC-05: heat first by default, viewers first when preferred', () {
    const both = Audience(online: 1200, popularity: 3500000);
    expect(shownAudience(both, preferOnline: false), 3500000);
    expect(shownAudience(both, preferOnline: true), 1200);
    expect(shownAudience(const Audience(online: 80), preferOnline: false), 80);
    expect(shownAudience(const Audience(cumulative: 9), preferOnline: true), 9);
    expect(shownAudience(Audience.none, preferOnline: true), isNull);
  });
}
