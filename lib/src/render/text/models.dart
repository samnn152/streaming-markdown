part of '../view.dart';

class _ParsedList {
  const _ParsedList({required this.items});

  final List<_ParsedListItem> items;
}

class _ParsedListItem {
  const _ParsedListItem({
    required this.level,
    required this.ordered,
    required this.order,
    required this.taskState,
    required this.text,
    required this.stableKey,
  });

  final int level;
  final bool ordered;
  final int order;
  final bool? taskState;
  final String text;
  final String stableKey;
}

class _ParsedTable {
  const _ParsedTable({required this.headers, required this.rows});

  final List<String> headers;
  final List<List<String>> rows;
}

class _CalloutData {
  const _CalloutData({
    required this.kind,
    required this.title,
    required this.body,
  });

  final String kind;
  final String title;
  final String body;
}

class _DelimitedMatch {
  const _DelimitedMatch({required this.inner, required this.end});

  final String inner;
  final int end;
}

class _InlineImageMatch {
  const _InlineImageMatch({
    required this.alt,
    required this.url,
    required this.end,
  });

  final String alt;
  final String url;
  final int end;
}

class _InlineLinkMatch {
  const _InlineLinkMatch({
    required this.label,
    required this.url,
    required this.end,
  });

  final String label;
  final String url;
  final int end;
}

class _FootnoteReferenceMatch {
  const _FootnoteReferenceMatch({required this.id, required this.end});

  final String id;
  final int end;
}

class _FootnoteDefinition {
  const _FootnoteDefinition({required this.id, required this.body});

  final String id;
  final String body;
}

int? _footnoteNumberForId(Map<String, int> footnoteNumbers, String id) {
  return footnoteNumbers[_normalizeFootnoteKey(id)];
}

String _normalizeFootnoteKey(String key) {
  return key.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
}

class _InlineStyle {
  const _InlineStyle({
    this.bold = false,
    this.italic = false,
    this.strikethrough = false,
    this.code = false,
  });

  final bool bold;
  final bool italic;
  final bool strikethrough;
  final bool code;

  _InlineStyle copyWith({
    bool? bold,
    bool? italic,
    bool? strikethrough,
    bool? code,
  }) {
    return _InlineStyle(
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      strikethrough: strikethrough ?? this.strikethrough,
      code: code ?? this.code,
    );
  }
}

class _InlineToken {
  const _InlineToken.text({
    required this.text,
    required this.style,
    required this.sourceMarkdown,
    this.linkUrl,
  })  : altText = '',
        imageUrl = null,
        footnoteReferenceId = null;

  const _InlineToken.image({
    required this.altText,
    required this.imageUrl,
    required this.sourceMarkdown,
  })  : text = '',
        style = const _InlineStyle(),
        linkUrl = null,
        footnoteReferenceId = null;

  const _InlineToken.footnote({
    required this.footnoteReferenceId,
    required this.sourceMarkdown,
  })  : text = '',
        style = const _InlineStyle(),
        linkUrl = null,
        altText = '',
        imageUrl = null;

  final String text;
  final _InlineStyle style;
  final String? linkUrl;
  final String altText;
  final String? imageUrl;
  final String? footnoteReferenceId;
  final String sourceMarkdown;

  bool get isImage => imageUrl != null;
  bool get isFootnoteReference => footnoteReferenceId != null;

  _InlineToken withLink(String url, {required String sourceMarkdown}) {
    if (isImage || isFootnoteReference) {
      return this;
    }
    return _InlineToken.text(
      text: text,
      style: style,
      linkUrl: url,
      sourceMarkdown: sourceMarkdown,
    );
  }
}
