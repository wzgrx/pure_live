/// Shared classification of Huya credential and transport refresh policies.
abstract final class HuyaTransportPolicy {
  static bool hasShortTransportLease(String url) {
    final uri = Uri.tryParse(url);
    final host = uri?.host.toLowerCase() ?? '';
    final path = uri?.path.toLowerCase() ?? '';
    final isHuya = host == 'huya.com' || host.endsWith('.huya.com');
    if (!isHuya || (!path.endsWith('.flv') && !path.endsWith('.m3u8'))) return false;
    // The native WUP FLV connection outlives its credential in long-read probes.
    // Refresh the next credential without restarting a healthy current stream.
    return !hasNativeFlvCredential(url);
  }

  static bool hasNativeFlvCredential(String url) {
    final uri = Uri.tryParse(url);
    final host = uri?.host.toLowerCase() ?? '';
    if (host != 'huya.com' && !host.endsWith('.huya.com')) return false;
    return (uri?.path.toLowerCase().endsWith('.flv') ?? false) &&
        uri!.queryParameters['ctype'] == 'huya_pc_exe' &&
        uri.queryParameters['t'] == '100';
  }
}
