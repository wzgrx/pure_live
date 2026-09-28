import 'package:flutter/material.dart';

/// A streamer's avatar: the picture when there is one, and underneath it the
/// first character of the name on one of eight neutral tones chosen by the
/// streamer's id (principles §3.4), so a missing or failing picture still
/// tells streamers apart. The same streamer gets the same tone everywhere:
/// follows, the room, the recording center, the multiview picker.
///
/// The picture fills a circular decoration; no clip layer (principles §7.11).
class InitialAvatar extends StatelessWidget {
  /// Creates the avatar of [name], toned by [seed] (the room key).
  const new({required this.name, required this.seed, this.image, this.size = 40, super.key});

  /// Streamer's name; its first character is the initial.
  final String name;

  /// Stable id that picks the tone, such as `douyu:6979222`.
  final String seed;

  /// The picture; the initial shows while it loads and when it fails.
  final ImageProvider? image;

  /// Diameter.
  final double size;

  /// Background and initial colours on light surfaces: low-chroma tints
  /// around the hue circle, each with its initial at ≥ 7:1.
  static const List<(Color, Color)> lightTones = [
    (Color(0xFFF5D6D2), Color(0xFF5E3532)),
    (Color(0xFFEEDBC6), Color(0xFF573C1C)),
    (Color(0xFFDDE1C7), Color(0xFF41461E)),
    (Color(0xFFCBE6D6), Color(0xFF224C37)),
    (Color(0xFFC4E5E9), Color(0xFF0D4B51)),
    (Color(0xFFCDE0F5), Color(0xFF284561)),
    (Color(0xFFDFDAF3), Color(0xFF453C5F)),
    (Color(0xFFEFD5E5), Color(0xFF58354C)),
  ];

  /// The same hues for dark and pure black surfaces.
  static const List<(Color, Color)> darkTones = [
    (Color(0xFF543B39), Color(0xFFFBDCD9)),
    (Color(0xFF4F3F2E), Color(0xFFF4E1CC)),
    (Color(0xFF42452F), Color(0xFFE3E8CE)),
    (Color(0xFF32483C), Color(0xFFD2ECDD)),
    (Color(0xFF2B484B), Color(0xFFCBECF0)),
    (Color(0xFF344455), Color(0xFFD4E7FC)),
    (Color(0xFF433F53), Color(0xFFE6E0FA)),
    (Color(0xFF4F3B48), Color(0xFFF6DCEC)),
  ];

  /// Which of the eight tones [seed] gets: FNV-1a over its UTF-16 units, so
  /// it is the same on every run and platform (unlike [String.hashCode]).
  static int toneOf(String seed) {
    var hash = 0x811c9dc5;
    for (final unit in seed.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xFFFFFFFF;
    }
    return hash % lightTones.length;
  }

  /// The initial shown for [name]: its first character, upper case.
  static String initialOf(String name) {
    final trimmed = name.trim();
    return trimmed.isEmpty ? '?' : trimmed.characters.first.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tones = theme.brightness == Brightness.dark ? darkTones : lightTones;
    final (background, ink) = tones[toneOf(seed)];
    final image = this.image;
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(color: background, shape: BoxShape.circle),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: Text(
                initialOf(name),
                // Scales with the circle, not with the text size: the circle
                // is fixed, so a larger initial would spill out of it.
                textScaler: TextScaler.noScaling,
                style: theme.textTheme.titleMedium!.copyWith(color: ink, fontSize: size * 0.42, height: 1),
              ),
            ),
            if (image != null)
              DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  // A failing picture leaves the initial; nothing to report.
                  image: DecorationImage(image: image, fit: BoxFit.cover, onError: (_, _) {}),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
