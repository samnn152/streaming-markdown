#include "streaming_markdown.h"

#include "../packages/tree-sitter-markdown/tree-sitter-markdown/bindings/c/tree-sitter/tree-sitter-markdown.h"
#include "../packages/tree-sitter-markdown/tree-sitter-markdown-inline/bindings/c/tree-sitter/tree-sitter-markdown-inline.h"

const void *streaming_markdown_tree_sitter_markdown(void) {
  return tree_sitter_markdown();
}

const void *streaming_markdown_tree_sitter_markdown_inline(void) {
  return tree_sitter_markdown_inline();
}
