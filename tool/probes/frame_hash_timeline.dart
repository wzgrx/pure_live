/// Parses FFmpeg framemd5 from one explicitly selected decoded stream.
/// This is bounded diagnostic evidence, not a compressed-packet equality test.
class FrameHashTimeline {
  FrameHashTimeline._(this.frames, this.numerator, this.denominator);
  final List<({int ticks, int size, String digest})> frames;
  final int numerator;
  final int denominator;

  factory FrameHashTimeline.parse(String text) {
    if (text.length > 4 * 1024 * 1024) throw const FormatException('Frame hash text budget');
    int? numerator;
    int? denominator;
    final frames = <({int ticks, int size, String digest})>[];
    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (line.startsWith('#tb ')) {
        final match = RegExp(r'^#tb 0:\s*(\d+)/(\d+)$').firstMatch(line);
        if (match == null || numerator != null) throw const FormatException('Frame hash time base');
        numerator = int.tryParse(match[1]!);
        denominator = int.tryParse(match[2]!);
        if (numerator == null || denominator == null || numerator <= 0 || denominator <= 0) {
          throw const FormatException('Frame hash time base range');
        }
        continue;
      }
      if (line.isEmpty || line.startsWith('#')) continue;
      final fields = line.split(',').map((value) => value.trim()).toList();
      if (fields.length != 6 || fields[0] != '0' || numerator == null || frames.length >= 100000) {
        throw const FormatException('Frame hash record shape');
      }
      final pts = int.tryParse(fields[2]);
      final size = int.tryParse(fields[4]);
      if (pts == null || size == null || size < 1 || !RegExp(r'^[a-f0-9]{32}$').hasMatch(fields[5])) {
        throw const FormatException('Frame hash record values');
      }
      frames.add((ticks: pts, size: size, digest: fields[5]));
    }
    if (frames.isEmpty) throw const FormatException('Empty frame hash stream');
    return FrameHashTimeline._(List.unmodifiable(frames), numerator!, denominator!);
  }

  Map<String, Object?> compare(FrameHashTimeline other) {
    var equal = frames.length == other.frames.length;
    int? mismatch;
    BigInt? minimum;
    BigInt? maximum;
    final leftScale = BigInt.from(numerator) * BigInt.from(other.denominator);
    final rightScale = BigInt.from(other.numerator) * BigInt.from(denominator);
    final commonDenominator = BigInt.from(denominator) * BigInt.from(other.denominator);
    for (var i = 0; i < frames.length && i < other.frames.length; i++) {
      final left = frames[i];
      final right = other.frames[i];
      if (left.size != right.size || left.digest != right.digest) {
        equal = false;
        mismatch ??= i;
      }
      // Compare exact rational ticks, not differences of rounded doubles. A
      // two-sample boundary must not become 2.0000000001 samples at long PTS.
      final delta = BigInt.from(right.ticks) * rightScale - BigInt.from(left.ticks) * leftScale;
      if (minimum == null || delta < minimum) minimum = delta;
      if (maximum == null || delta > maximum) maximum = delta;
    }
    return {
      'leftFrames': frames.length,
      'rightFrames': other.frames.length,
      'orderedContentEqual': equal,
      'firstContentMismatch':
          mismatch ?? (equal ? null : (frames.length < other.frames.length ? frames.length : other.frames.length)),
      // Only meaningful after content and order are established; an arbitrary
      // constant container start offset is distinct from an introduced step.
      'minimumOffsetSeconds': equal ? _seconds(minimum!, commonDenominator) : null,
      'maximumOffsetSeconds': equal ? _seconds(maximum!, commonDenominator) : null,
      'offsetSpreadSeconds': equal ? _seconds(maximum! - minimum!, commonDenominator) : null,
    };
  }

  static double _seconds(BigInt numerator, BigInt denominator) {
    final divisor = numerator.gcd(denominator);
    return (numerator ~/ divisor).toDouble() / (denominator ~/ divisor).toDouble();
  }
}
