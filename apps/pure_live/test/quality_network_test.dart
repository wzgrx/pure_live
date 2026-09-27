import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/core/network.dart';
import 'package:pure_live_app/features/room/playback.dart';

Quality _q(String label, int rank) => Quality(id: label, label: label, rank: rank);

void main() {
  group('live-room Q-2: the default quality', () {
    final douyu = [_q('原画', 4), _q('蓝光8M', 3), _q('蓝光4M', 2), _q('超清', 1), _q('流畅', 0)];
    final three = [_q('原画', 3), _q('高清', 2), _q('标清', 1)];

    test('a quality with the preference name wins', () {
      for (final preference in QualityPreference.values) {
        expect(preferredQuality(douyu, preference)!.label, qualityPreferenceNames[preference]);
      }
      expect(preferredQuality([_q('高清', 2), _q('蓝光 4M', 1)], QualityPreference.bluRay4M)!.label, '蓝光 4M');
    });

    test('otherwise the same relative position, rounded', () {
      expect(preferredQuality(three, QualityPreference.original)!.label, '原画');
      expect(preferredQuality(three, QualityPreference.bluRay8M)!.label, '高清', reason: '1/4 of 2 rounds to 1');
      expect(preferredQuality(three, QualityPreference.bluRay4M)!.label, '高清');
      expect(preferredQuality(three, QualityPreference.superHigh)!.label, '标清', reason: '3/4 of 2 rounds to 2');
      expect(preferredQuality(three, QualityPreference.smooth)!.label, '标清');
      expect(preferredQuality([_q('高清', 1)], QualityPreference.smooth)!.label, '高清');
      expect(preferredQuality(const [], QualityPreference.original), isNull);
    });
  });

  test('F-NEW-10: connectivity results as one network kind', () {
    expect(networkKindOf([ConnectivityResult.wifi]), NetworkKind.unmetered);
    expect(networkKindOf([ConnectivityResult.mobile]), NetworkKind.cellular);
    expect(networkKindOf([ConnectivityResult.mobile, ConnectivityResult.wifi]), NetworkKind.unmetered);
    expect(networkKindOf([ConnectivityResult.ethernet]), NetworkKind.unmetered);
    expect(networkKindOf([ConnectivityResult.vpn]), NetworkKind.unmetered);
    expect(networkKindOf([ConnectivityResult.vpn, ConnectivityResult.mobile]), NetworkKind.cellular);
    expect(networkKindOf([ConnectivityResult.none]), NetworkKind.offline);
    expect(networkKindOf(const []), NetworkKind.offline);
  });
}
