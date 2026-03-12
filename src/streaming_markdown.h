#ifndef STREAMING_MARKDOWN_H_
#define STREAMING_MARKDOWN_H_

#include <stddef.h>
#include <stdbool.h>
#include <stdint.h>

#if _WIN32
#define FFI_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FFI_PLUGIN_EXPORT
#endif

#ifdef __cplusplus
extern "C" {
#endif

// Returns a TSLanguage* (as opaque pointer) for tree-sitter-markdown.
FFI_PLUGIN_EXPORT const void *streaming_markdown_tree_sitter_markdown(void);
FFI_PLUGIN_EXPORT const void *streaming_markdown_tree_sitter_markdown_inline(void);

// Parse markdown text and return the full syntax tree as JSON.
// Returned string must be freed via streaming_markdown_rope_free_c_string.
FFI_PLUGIN_EXPORT const char *streaming_markdown_parse_blocks_to_json(
    const char *utf8_text);
FFI_PLUGIN_EXPORT const char *streaming_markdown_parse_inlines_to_json(
    const char *utf8_text);

// Stateful incremental parser session for append-heavy workloads.
FFI_PLUGIN_EXPORT void *streaming_markdown_incremental_create(void);
FFI_PLUGIN_EXPORT void streaming_markdown_incremental_destroy(void *handle);
FFI_PLUGIN_EXPORT bool streaming_markdown_incremental_set_text(
    void *handle, const char *utf8_text);
FFI_PLUGIN_EXPORT bool streaming_markdown_incremental_append_text(
    void *handle, const char *utf8_text);
FFI_PLUGIN_EXPORT uint32_t streaming_markdown_incremental_block_count(
    void *handle);
FFI_PLUGIN_EXPORT uint32_t streaming_markdown_incremental_inline_type_count(
    void *handle);
// Returned string must be freed via streaming_markdown_rope_free_c_string.
FFI_PLUGIN_EXPORT const char *streaming_markdown_incremental_block_nodes_json(
    void *handle, uint32_t max_nodes);

// Opaque native rope buffer.
FFI_PLUGIN_EXPORT void *streaming_markdown_rope_create(void);
FFI_PLUGIN_EXPORT void streaming_markdown_rope_destroy(void *handle);
FFI_PLUGIN_EXPORT void streaming_markdown_rope_append_utf8(
    void *handle, const char *utf8_text);
FFI_PLUGIN_EXPORT uint64_t streaming_markdown_rope_length_bytes(void *handle);
FFI_PLUGIN_EXPORT const char *streaming_markdown_rope_substring_utf8(
    void *handle, uint64_t start, uint64_t end);
FFI_PLUGIN_EXPORT void streaming_markdown_rope_free_c_string(
    const char *allocated_c_string);
FFI_PLUGIN_EXPORT void streaming_markdown_rope_clear(void *handle);

#ifdef __cplusplus
}
#endif

#endif  // STREAMING_MARKDOWN_H_
