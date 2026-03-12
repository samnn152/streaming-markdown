import 'dart:io';

import 'package:animated_streaming_markdown/animated_streaming_markdown.dart';

void main() {
  final File specFile = File('example/assets/github_gfm_spec.md');
  if (!specFile.existsSync()) {
    stderr.writeln('Missing file: ${specFile.path}');
    exitCode = 1;
    return;
  }

  final String markdown = specFile.readAsStringSync();
  final RopeString rope = RopeString()..append(markdown);

  final MarkdownDocument basicAst = const RopeMarkdownParser().parse(rope);
  stdout.writeln('--- RopeMarkdownParser (Dart only) ---');
  stdout.writeln('blocks: ${basicAst.blocks.length}');

  if (!isStreamingMarkdownNativeLibraryAvailable) {
    stdout.writeln(
      'Native Tree-sitter library is not available in this runtime.',
    );
    return;
  }

  const TreeSitterMarkdownParser parser = TreeSitterMarkdownParser();
  final MarkdownSyntaxNode blockTree = parser.parseBlocksFromRope(rope);
  final MarkdownSyntaxNode inlineTree = parser.parseInlinesFromRope(rope);

  final Set<String> blockTypes = _collectTypes(blockTree);
  final Set<String> inlineTypes = _collectTypes(inlineTree);

  stdout.writeln('--- TreeSitterMarkdownParser ---');
  stdout.writeln('block root: ${blockTree.type}');
  stdout.writeln('block node types: ${blockTypes.length}');
  stdout.writeln('inline node types: ${inlineTypes.length}');

  final List<String> sortedInline = inlineTypes.toList()..sort();
  stdout.writeln('inline sample: ${sortedInline.take(20).join(', ')}');
}

Set<String> _collectTypes(MarkdownSyntaxNode node) {
  final Set<String> out = <String>{node.type};
  for (final MarkdownSyntaxNode child in node.children) {
    out.addAll(_collectTypes(child));
  }
  return out;
}
