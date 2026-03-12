#include "streaming_markdown.h"

#include "../packages/tree-sitter/lib/include/tree_sitter/api.h"
#include "../packages/tree-sitter-markdown/tree-sitter-markdown/bindings/c/tree-sitter/tree-sitter-markdown.h"
#include "../packages/tree-sitter-markdown/tree-sitter-markdown-inline/bindings/c/tree-sitter/tree-sitter-markdown-inline.h"

#include <cstdlib>
#include <cstring>
#include <limits>
#include <new>
#include <string>
#include <unordered_set>

namespace {

struct IncrementalSession {
  TSParser *block_parser = nullptr;
  TSParser *inline_parser = nullptr;
  TSTree *block_tree = nullptr;
  std::string text;
  TSPoint end_point{0, 0};
  std::unordered_set<std::string> inline_types;
};

void clear_trees(IncrementalSession *session) {
  if (session->block_tree != nullptr) {
    ts_tree_delete(session->block_tree);
    session->block_tree = nullptr;
  }
}

bool create_parsers(IncrementalSession *session) {
  session->block_parser = ts_parser_new();
  session->inline_parser = ts_parser_new();
  if (session->block_parser == nullptr || session->inline_parser == nullptr) {
    return false;
  }

  if (!ts_parser_set_language(session->block_parser, tree_sitter_markdown())) {
    return false;
  }
  if (!ts_parser_set_language(session->inline_parser,
                              tree_sitter_markdown_inline())) {
    return false;
  }

  return true;
}

void destroy_parsers(IncrementalSession *session) {
  if (session->block_parser != nullptr) {
    ts_parser_delete(session->block_parser);
    session->block_parser = nullptr;
  }
  if (session->inline_parser != nullptr) {
    ts_parser_delete(session->inline_parser);
    session->inline_parser = nullptr;
  }
}

TSPoint compute_end_point(const char *text, size_t length) {
  TSPoint point{0, 0};
  for (size_t i = 0; i < length; i++) {
    if (text[i] == '\n') {
      point.row += 1;
      point.column = 0;
    } else {
      point.column += 1;
    }
  }
  return point;
}

TSPoint advance_point(TSPoint start, const char *text, size_t length) {
  TSPoint point = start;
  for (size_t i = 0; i < length; i++) {
    if (text[i] == '\n') {
      point.row += 1;
      point.column = 0;
    } else {
      point.column += 1;
    }
  }
  return point;
}

bool reparse_block(IncrementalSession *session, bool use_old_tree) {
  if (session->text.size() > std::numeric_limits<uint32_t>::max()) {
    return false;
  }

  TSTree *new_tree = ts_parser_parse_string(
      session->block_parser, use_old_tree ? session->block_tree : nullptr,
      session->text.c_str(), static_cast<uint32_t>(session->text.size()));
  if (new_tree == nullptr) {
    return false;
  }

  if (session->block_tree != nullptr) {
    ts_tree_delete(session->block_tree);
  }
  session->block_tree = new_tree;
  return true;
}

void collect_types(TSNode node, std::unordered_set<std::string> *types) {
  types->insert(ts_node_type(node));
  const uint32_t child_count = ts_node_child_count(node);
  for (uint32_t i = 0; i < child_count; i++) {
    collect_types(ts_node_child(node, i), types);
  }
}

bool reparse_inline_types_full(IncrementalSession *session) {
  if (session->text.size() > std::numeric_limits<uint32_t>::max()) {
    return false;
  }

  TSTree *tree = ts_parser_parse_string(
      session->inline_parser, nullptr, session->text.c_str(),
      static_cast<uint32_t>(session->text.size()));
  if (tree == nullptr) {
    return false;
  }

  session->inline_types.clear();
  session->inline_types.reserve(128);
  collect_types(ts_tree_root_node(tree), &session->inline_types);
  ts_tree_delete(tree);
  return true;
}

bool extend_inline_types_from_chunk(IncrementalSession *session,
                                    const char *utf8_text,
                                    size_t append_len) {
  if (append_len > std::numeric_limits<uint32_t>::max()) {
    return false;
  }

  TSTree *tree = ts_parser_parse_string(
      session->inline_parser, nullptr, utf8_text,
      static_cast<uint32_t>(append_len));
  if (tree == nullptr) {
    return false;
  }

  collect_types(ts_tree_root_node(tree), &session->inline_types);
  ts_tree_delete(tree);
  return true;
}

std::string escape_json_bytes(const char *text, size_t length) {
  std::string out;
  out.reserve(length + 8);
  for (size_t i = 0; i < length; i++) {
    const unsigned char ch = static_cast<unsigned char>(text[i]);
    if (ch == '"') {
      out += "\\\"";
    } else if (ch == '\\') {
      out += "\\\\";
    } else if (ch == '\n') {
      out += "\\n";
    } else if (ch == '\r') {
      out += "\\r";
    } else if (ch == '\t') {
      out += "\\t";
    } else {
      out += static_cast<char>(ch);
    }
  }
  return out;
}

std::string escape_json(const char *text) {
  return escape_json_bytes(text, std::strlen(text));
}

void append_node(std::string &out, TSNode node, uint32_t depth,
                 const std::string &source) {
  const char *type = ts_node_type(node);
  const TSPoint start = ts_node_start_point(node);
  const TSPoint end = ts_node_end_point(node);
  const uint32_t start_byte = ts_node_start_byte(node);
  const uint32_t end_byte = ts_node_end_byte(node);

  out += "{\"type\":\"";
  out += escape_json(type);
  out += "\",\"depth\":";
  out += std::to_string(depth);
  out += ",\"startByte\":";
  out += std::to_string(start_byte);
  out += ",\"endByte\":";
  out += std::to_string(end_byte);
  out += ",\"startRow\":";
  out += std::to_string(start.row);
  out += ",\"endRow\":";
  out += std::to_string(end.row);
  out += ",\"raw\":\"";

  if (start_byte < end_byte && end_byte <= source.size()) {
    const size_t full_len = static_cast<size_t>(end_byte - start_byte);
    out += escape_json_bytes(source.data() + start_byte, full_len);
  }

  out += "\"";
  out += "}";
}

void flatten_nodes(std::string &out, TSNode node, uint32_t depth,
                   uint32_t max_nodes, uint32_t *count,
                   const std::string &source) {
  if (*count >= max_nodes) {
    return;
  }

  if (*count > 0) {
    out += ',';
  }
  append_node(out, node, depth, source);
  *count += 1;

  const uint32_t child_count = ts_node_child_count(node);
  for (uint32_t i = 0; i < child_count; i++) {
    if (*count >= max_nodes) {
      break;
    }
    flatten_nodes(out, ts_node_child(node, i), depth + 1, max_nodes, count,
                  source);
  }
}

const char *to_c_string(const std::string &text) {
  char *raw = static_cast<char *>(std::malloc(text.size() + 1));
  if (raw == nullptr) {
    return nullptr;
  }
  std::memcpy(raw, text.data(), text.size());
  raw[text.size()] = '\0';
  return raw;
}

}  // namespace

extern "C" {

void *streaming_markdown_incremental_create(void) {
  IncrementalSession *session = new (std::nothrow) IncrementalSession();
  if (session == nullptr) {
    return nullptr;
  }

  if (!create_parsers(session)) {
    destroy_parsers(session);
    delete session;
    return nullptr;
  }

  if (!reparse_block(session, false) || !reparse_inline_types_full(session)) {
    clear_trees(session);
    destroy_parsers(session);
    delete session;
    return nullptr;
  }

  return session;
}

void streaming_markdown_incremental_destroy(void *handle) {
  IncrementalSession *session = static_cast<IncrementalSession *>(handle);
  if (session == nullptr) {
    return;
  }

  clear_trees(session);
  destroy_parsers(session);
  delete session;
}

bool streaming_markdown_incremental_set_text(void *handle,
                                             const char *utf8_text) {
  IncrementalSession *session = static_cast<IncrementalSession *>(handle);
  if (session == nullptr) {
    return false;
  }

  const char *text = utf8_text == nullptr ? "" : utf8_text;
  session->text.assign(text);
  session->end_point =
      compute_end_point(session->text.c_str(), session->text.size());

  return reparse_block(session, false) && reparse_inline_types_full(session);
}

bool streaming_markdown_incremental_append_text(void *handle,
                                                const char *utf8_text) {
  IncrementalSession *session = static_cast<IncrementalSession *>(handle);
  if (session == nullptr || utf8_text == nullptr || utf8_text[0] == '\0') {
    return true;
  }

  if (session->text.size() > std::numeric_limits<uint32_t>::max()) {
    return false;
  }

  const uint32_t old_len = static_cast<uint32_t>(session->text.size());
  const size_t append_len = std::strlen(utf8_text);
  if (append_len > (std::numeric_limits<uint32_t>::max() - old_len)) {
    return false;
  }

  const TSPoint old_end = session->end_point;
  const TSPoint new_end = advance_point(old_end, utf8_text, append_len);

  TSInputEdit edit;
  edit.start_byte = old_len;
  edit.old_end_byte = old_len;
  edit.new_end_byte = old_len + static_cast<uint32_t>(append_len);
  edit.start_point = old_end;
  edit.old_end_point = old_end;
  edit.new_end_point = new_end;

  if (session->block_tree != nullptr) {
    ts_tree_edit(session->block_tree, &edit);
  }

  session->text.append(utf8_text);
  session->end_point = new_end;

  return reparse_block(session, true) &&
         extend_inline_types_from_chunk(session, utf8_text, append_len);
}

uint32_t streaming_markdown_incremental_block_count(void *handle) {
  IncrementalSession *session = static_cast<IncrementalSession *>(handle);
  if (session == nullptr || session->block_tree == nullptr) {
    return 0;
  }

  return ts_node_child_count(ts_tree_root_node(session->block_tree));
}

uint32_t streaming_markdown_incremental_inline_type_count(void *handle) {
  IncrementalSession *session = static_cast<IncrementalSession *>(handle);
  if (session == nullptr) {
    return 0;
  }

  return static_cast<uint32_t>(session->inline_types.size());
}

const char *streaming_markdown_incremental_block_nodes_json(void *handle,
                                                            uint32_t max_nodes) {
  IncrementalSession *session = static_cast<IncrementalSession *>(handle);
  if (session == nullptr || session->block_tree == nullptr || max_nodes == 0) {
    return to_c_string("[]");
  }

  const TSNode root = ts_tree_root_node(session->block_tree);
  std::string json = "[";
  uint32_t count = 0;
  flatten_nodes(json, root, 0, max_nodes, &count, session->text);
  json += "]";

  return to_c_string(json);
}

}  // extern "C"
