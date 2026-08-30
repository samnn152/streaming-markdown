import 'clipboard_writer_interface.dart';

class LinuxClipboardWriter extends PlainTextClipboardWriter {
  const LinuxClipboardWriter();

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
