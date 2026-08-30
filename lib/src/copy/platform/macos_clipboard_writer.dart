import 'clipboard_writer_interface.dart';

class MacosClipboardWriter extends PlainTextClipboardWriter {
  const MacosClipboardWriter();

  @override
  Future<void> writeRichText({
    required String plainText,
    required String htmlText,
  }) {
    return markdownClipboardChannel.invokeMethod<void>('writeRichText', {
      'plainText': plainText,
      'htmlText': htmlText,
    });
  }
}
