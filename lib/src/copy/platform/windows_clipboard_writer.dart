import 'dart:convert';

import 'clipboard_writer_interface.dart';

class WindowsClipboardWriter extends PlainTextClipboardWriter {
  const WindowsClipboardWriter();

  @override
  Future<void> writeRichText({
    required String plainText,
    required String htmlText,
  }) {
    return markdownClipboardChannel.invokeMethod<void>('writeRichText', {
      'plainText': plainText,
      'htmlText': WindowsClipboardHtmlFormatter.buildCfHtml(htmlText),
    });
  }
}

class WindowsClipboardHtmlFormatter {
  const WindowsClipboardHtmlFormatter._();

  static String buildCfHtml(String htmlFragment) {
    const String startMarker = '<!--StartFragment-->';
    const String endMarker = '<!--EndFragment-->';
    final String html =
        '<html><body>$startMarker$htmlFragment$endMarker</body></html>';
    final String placeholder = [
      'Version:0.9',
      'StartHTML:0000000000',
      'EndHTML:0000000000',
      'StartFragment:0000000000',
      'EndFragment:0000000000',
      '',
    ].join('\r\n');
    final int startHtml = _utf8Length(placeholder);
    final int startFragment =
        startHtml + _utf8Length('<html><body>$startMarker');
    final int endFragment = startFragment + _utf8Length(htmlFragment);
    final int endHtml = startHtml + _utf8Length(html);
    final String header = [
      'Version:0.9',
      'StartHTML:${_offset(startHtml)}',
      'EndHTML:${_offset(endHtml)}',
      'StartFragment:${_offset(startFragment)}',
      'EndFragment:${_offset(endFragment)}',
      '',
    ].join('\r\n');
    return '$header$html';
  }

  static int _utf8Length(String value) => utf8.encode(value).length;

  static String _offset(int value) => value.toString().padLeft(10, '0');
}
