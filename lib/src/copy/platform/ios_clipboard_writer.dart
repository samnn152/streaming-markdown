import 'clipboard_writer_interface.dart';

class IosClipboardWriter extends PlainTextClipboardWriter {
  const IosClipboardWriter();

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
