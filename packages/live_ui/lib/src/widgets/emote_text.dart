import 'package:flutter/material.dart';
import 'package:live_ui/src/widgets/network_image.dart';

/// A piece of a chat message: text or an emote picture.
@immutable
sealed class ChatSegment {
  const new();
}

/// Plain text.
@immutable
final class ChatTextSegment extends ChatSegment {
  /// Creates the text.
  const new(this.text);

  /// The text.
  final String text;

  @override
  bool operator ==(Object other) => other is ChatTextSegment && other.text == text;

  @override
  int get hashCode => text.hashCode;
}

/// An emote picture (CHZZK emoticons, YouTube channel emoji), with the text
/// it stands for, shown while it loads or when it fails.
@immutable
final class ChatEmoteSegment extends ChatSegment {
  /// Creates the emote.
  const new({required this.url, this.alt = ''});

  /// Picture address.
  final String url;

  /// The text the picture stands for (`:smile:`).
  final String alt;

  @override
  bool operator ==(Object other) => other is ChatEmoteSegment && other.url == url && other.alt == alt;

  @override
  int get hashCode => Object.hash(url, alt);
}

/// A chat message with emote pictures inline, each as tall as
/// [emoteScale] × the font size and centred on the line (UPGRADES B-12,
/// B-13: the picture instead of its code).
class EmoteText extends StatelessWidget {
  /// Shows [segments].
  const new(this.segments, {this.style, this.maxLines, this.overflow, this.emoteScale = 1.4, super.key});

  /// The message.
  final List<ChatSegment> segments;

  /// Text style; null takes the ambient [DefaultTextStyle].
  final TextStyle? style;

  /// Line limit.
  final int? maxLines;

  /// Overflow of [maxLines].
  final TextOverflow? overflow;

  /// Emote height relative to the font size.
  final double emoteScale;

  /// The message as plain text: emotes become their [ChatEmoteSegment.alt].
  static String plainText(List<ChatSegment> segments) => segments
      .map(
        (segment) => switch (segment) {
          ChatTextSegment(:final text) => text,
          ChatEmoteSegment(:final alt) => alt,
        },
      )
      .join();

  @override
  Widget build(BuildContext context) {
    final effective = DefaultTextStyle.of(context).style.merge(style);
    final height = (effective.fontSize ?? 14) * emoteScale;
    return Text.rich(
      TextSpan(
        children: [
          for (final segment in segments)
            switch (segment) {
              ChatTextSegment(:final text) => TextSpan(text: text),
              ChatEmoteSegment(:final url, :final alt) when url.trim().isEmpty => TextSpan(text: alt),
              ChatEmoteSegment(:final url, :final alt) => WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Semantics(
                  label: alt,
                  child: SizedBox(
                    height: height,
                    child: LiveNetworkImage(
                      url: url.trim(),
                      fit: BoxFit.contain,
                      memCacheWidth: (height * 2 * MediaQuery.devicePixelRatioOf(context)).round(),
                      placeholder: (_) => Text(alt, style: effective),
                      error: (_) => Text(alt, style: effective),
                    ),
                  ),
                ),
              ),
            },
        ],
      ),
      style: style,
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}
