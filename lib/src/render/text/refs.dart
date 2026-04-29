part of '../view.dart';

extension _StreamingMarkdownReferenceParsing on StreamingMarkdownRenderView {
  Map<String, String> _extractLinkReferences(List<MarkdownRenderNode> nodes) {
    final Map<String, String> references = <String, String>{};
    for (final MarkdownRenderNode node in nodes) {
      if (node.type != 'link_reference_definition') {
        continue;
      }
      final String raw = _normalizedRaw(node.raw);
      for (final RegExpMatch match in RegExp(
        r'^\s*\[([^\]]+)\]:\s*(\S+)',
        multiLine: true,
      ).allMatches(raw)) {
        final String name = _normalizeReferenceKey(match.group(1)!);
        final String url = _stripEnclosingAngles(match.group(2)!);
        if (name.isNotEmpty && url.isNotEmpty) {
          references[name] = url;
        }
      }
    }
    return references;
  }

  Map<String, int> _extractFootnoteNumbers(List<MarkdownRenderNode> nodes) {
    final Map<String, int> numbers = <String, int>{};
    for (final MarkdownRenderNode node in nodes) {
      for (final _FootnoteDefinition definition
          in _parseFootnoteDefinitions(node.raw)) {
        final String key = _normalizeFootnoteKey(definition.id);
        if (key.isEmpty || numbers.containsKey(key)) {
          continue;
        }
        numbers[key] = numbers.length + 1;
      }
    }
    return numbers;
  }
}
