import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Wall-clock time for rules that measure how long something took or how
/// long the app was away (F-APP-03); tests replace it.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);
