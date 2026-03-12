#include "streaming_markdown.h"

#include "../packages/tree-sitter/lib/include/tree_sitter/api.h"
#include "../packages/tree-sitter-markdown/tree-sitter-markdown/bindings/c/tree-sitter/tree-sitter-markdown.h"
#include "../packages/tree-sitter-markdown/tree-sitter-markdown-inline/bindings/c/tree-sitter/tree-sitter-markdown-inline.h"

#include <cstdlib>
#include <cstring>
#include <limits>
#include <string>

namespace {

std::string json_escape(const char *data, uint32_t length) {
  std::string out;
  out.reserve(length + 8);
  for (uint32_t i = 0; i < length; i++) {
    const unsigned char ch = static_cast<unsigned char>(data[i]);
    switch (ch) {
      case '"':
        out += "\\\"";
        break;
      case '\\':
        out += "\\\\";
        break;
      case '\b':
        out += "\\b";
        break;
      case '\f':
        out += "\\f";
        break;
      case '\n':
        out += "\\n";
        break;
      case '\r':
        out += "\\r";
        break;
      case '\t':
        out += "\\t";
        break;
      default:
        if (ch < 0x20) {
          static const char *kHex = "0123456789abcdef";
          out += "\\u00";
          out += kHex[(ch >> 4) & 0x0f];
          out += kHex[ch & 0x0f];
        } else {
          out += static_cast<char>(ch);
        }
        break;
    }
  }
  return out;
}

void append_uint32(std::string &out, uint32_t value) {
  out += std::to_string(value);
}

void append_node_json(std::string &out, TSNode node, const char *source,
                      uint32_t source_len) {
  const char *type = ts_node_type(node);
  const uint32_t start_byte = ts_node_start_byte(node);
  const uint32_t end_byte = ts_node_end_byte(node);
  const TSPoint start_point = ts_node_start_point(node);
  const TSPoint end_point = ts_node_end_point(node);
  const uint32_t child_count = ts_node_child_count(node);

  out += "{\"type\":\"";
  out += json_escape(type, static_cast<uint32_t>(std::strlen(type)));
  out += "\",\"startByte\":";
  append_uint32(out, start_byte);
  out += ",\"endByte\":";
  append_uint32(out, end_byte);
  out += ",\"startRow\":";
  append_uint32(out, start_point.row);
  out += ",\"startColumn\":";
  append_uint32(out, start_point.column);
  out += ",\"endRow\":";
  append_uint32(out, end_point.row);
  out += ",\"endColumn\":";
  append_uint32(out, end_point.column);

  if (child_count == 0 && end_byte >= start_byte && end_byte <= source_len) {
    out += ",\"text\":\"";
    out += json_escape(source + start_byte, end_byte - start_byte);
    out += "\"";
  }

  out += ",\"children\":[";
  for (uint32_t i = 0; i < child_count; i++) {
    if (i > 0) {
      out += ",";
    }
    append_node_json(out, ts_node_child(node, i), source, source_len);
  }
  out += "]}";
}

const char *parse_with_language(const char *utf8_text,
                                const TSLanguage *(*language_fn)(void)) {
  const char *input = utf8_text == nullptr ? "" : utf8_text;
  const size_t input_len = std::strlen(input);
  if (input_len > std::numeric_limits<uint32_t>::max()) {
    return nullptr;
  }

  TSParser *parser = ts_parser_new();
  if (parser == nullptr) {
    return nullptr;
  }

  const TSLanguage *language = language_fn();
  if (!ts_parser_set_language(parser, language)) {
    ts_parser_delete(parser);
    return nullptr;
  }

  TSTree *tree = ts_parser_parse_string(parser, nullptr, input,
                                        static_cast<uint32_t>(input_len));
  if (tree == nullptr) {
    ts_parser_delete(parser);
    return nullptr;
  }

  const TSNode root = ts_tree_root_node(tree);
  std::string json;
  append_node_json(json, root, input, static_cast<uint32_t>(input_len));

  char *result = static_cast<char *>(std::malloc(json.size() + 1));
  if (result != nullptr) {
    std::memcpy(result, json.data(), json.size());
    result[json.size()] = '\0';
  }

  ts_tree_delete(tree);
  ts_parser_delete(parser);
  return result;
}

}  // namespace

extern "C" {

const char *streaming_markdown_parse_blocks_to_json(const char *utf8_text) {
  return parse_with_language(utf8_text, tree_sitter_markdown);
}

const char *streaming_markdown_parse_inlines_to_json(const char *utf8_text) {
  return parse_with_language(utf8_text, tree_sitter_markdown_inline);
}

}  // extern "C"
