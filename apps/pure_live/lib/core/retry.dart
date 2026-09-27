import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';

/// The app's retry policy for providers (principles §4: an error is
/// explained in place, soon). Only a network failure is worth another try,
/// twice at most (after 1 s and 2 s); anything else — a missing room, a
/// changed platform API, an unsupported platform — shows at once. Riverpod
/// would otherwise retry every error ten times with back-off, about 40 s of
/// spinner before the page can say what went wrong.
Duration? networkRetry(int count, Object error) =>
    count < 2 && (error is NetworkFailure || error is TransportFailure) ? Duration(seconds: 1 << count) : null;
