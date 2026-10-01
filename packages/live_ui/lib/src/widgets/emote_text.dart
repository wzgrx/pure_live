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

/// An emote picture (CHZZK emoticons, YouTube channel emoji, the bundled
/// lists of the Chinese platforms), with the text it stands for, shown
/// while it loads or when it fails.
@immutable
final class ChatEmoteSegment extends ChatSegment {
  /// Creates the emote.
  const new({required this.url, this.alt = '', this.asset = ''});

  /// Picture address; the fallback of [asset].
  final String url;

  /// The text the picture stands for (`:smile:`).
  final String alt;

  /// A picture bundled with the app (`assets/emo/images/…`), shown before
  /// [url]; empty for none.
  final String asset;

  @override
  bool operator ==(Object other) =>
      other is ChatEmoteSegment && other.url == url && other.alt == alt && other.asset == asset;

  @override
  int get hashCode => Object.hash(url, alt, asset);
}

/// A chat message with emote pictures inline, each as tall as
/// [emoteScale] × the font size and centred on the line (UPGRADES B-12,
/// B-13: the picture instead of its code). A bundled picture comes first;
/// when it cannot be loaded the address is used, and the code is shown while
/// a picture loads or when neither works.
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
              ChatEmoteSegment(:final url, :final alt, :final asset) when url.trim().isEmpty && asset.trim().isEmpty =>
                TextSpan(text: alt),
              ChatEmoteSegment(:final url, :final alt, :final asset) => WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Semantics(
                  label: alt,
                  child: SizedBox(
                    height: height,
                    child: _picture(context, url.trim(), asset.trim(), alt, height, effective),
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

  Widget _picture(BuildContext context, String url, String asset, String alt, double height, TextStyle style) {
    final cacheWidth = (height * 2 * MediaQuery.devicePixelRatioOf(context)).round();
    Widget code() => Text(alt, style: style);
    Widget network() => url.isEmpty
        ? code()
        : LiveNetworkImage(
            url: url,
            fit: BoxFit.contain,
            memCacheWidth: cacheWidth,
            placeholder: (_) => code(),
            error: (_) => code(),
          );
    if (asset.isEmpty) return network();
    return Image.asset(
      asset,
      fit: BoxFit.contain,
      cacheWidth: cacheWidth,
      excludeFromSemantics: true,
      errorBuilder: (_, _, _) => network(),
    );
  }
}
