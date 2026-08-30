import 'package:flutter/services.dart';

const MethodChannel markdownClipboardChannel = MethodChannel(
  'animated_streaming_markdown/clipboard',
);

abstract class MarkdownClipboardWriter {
  const MarkdownClipboardWriter();

  Future<void> writePlainText(String text);

  Future<void> writeRichText({
    required String plainText,
    required String htmlText,
  });
}

abstract class PlainTextClipboardWriter implements MarkdownClipboardWriter {
  const PlainTextClipboardWriter();

  @override
  Future<void> writePlainText(String text) {
    return Clipboard.setData(ClipboardData(text: text));
  }
}
