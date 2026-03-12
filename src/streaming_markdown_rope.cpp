#include "streaming_markdown.h"

#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <new>
#include <string>
#include <vector>

namespace {

struct NativeRope {
  std::vector<std::string> chunks;
  std::vector<uint64_t> prefix_lengths;
  uint64_t length_bytes = 0;
};

uint64_t lower_bound_prefix(const std::vector<uint64_t> &prefix,
                            uint64_t target) {
  return static_cast<uint64_t>(
      std::lower_bound(prefix.begin(), prefix.end(), target) - prefix.begin());
}

}  // namespace

extern "C" {

void *streaming_markdown_rope_create(void) {
  return new (std::nothrow) NativeRope();
}

void streaming_markdown_rope_destroy(void *handle) {
  auto *rope = static_cast<NativeRope *>(handle);
  delete rope;
}

void streaming_markdown_rope_append_utf8(void *handle, const char *utf8_text) {
  auto *rope = static_cast<NativeRope *>(handle);
  if (rope == nullptr || utf8_text == nullptr || utf8_text[0] == '\0') {
    return;
  }

  const std::string chunk(utf8_text);
  rope->chunks.push_back(chunk);
  rope->length_bytes += static_cast<uint64_t>(chunk.size());
  rope->prefix_lengths.push_back(rope->length_bytes);
}

uint64_t streaming_markdown_rope_length_bytes(void *handle) {
  auto *rope = static_cast<NativeRope *>(handle);
  if (rope == nullptr) {
    return 0;
  }
  return rope->length_bytes;
}

const char *streaming_markdown_rope_substring_utf8(void *handle, uint64_t start,
                                                    uint64_t end) {
  auto *rope = static_cast<NativeRope *>(handle);
  if (rope == nullptr) {
    return nullptr;
  }
  if (start > end || end > rope->length_bytes) {
    return nullptr;
  }

  const uint64_t out_len = end - start;
  char *output = static_cast<char *>(std::malloc(static_cast<size_t>(out_len) + 1));
  if (output == nullptr) {
    return nullptr;
  }

  if (out_len == 0) {
    output[0] = '\0';
    return output;
  }

  uint64_t chunk_index = lower_bound_prefix(rope->prefix_lengths, start + 1);
  uint64_t cursor = start;
  uint64_t write_pos = 0;

  while (cursor < end) {
    const uint64_t chunk_start =
        chunk_index == 0 ? 0 : rope->prefix_lengths[chunk_index - 1];
    const uint64_t chunk_end = rope->prefix_lengths[chunk_index];

    const uint64_t local_start = cursor - chunk_start;
    const uint64_t local_end = (end < chunk_end ? end : chunk_end) - chunk_start;
    const uint64_t copy_len = local_end - local_start;

    const std::string &chunk = rope->chunks[chunk_index];
    std::memcpy(output + write_pos, chunk.data() + local_start,
                static_cast<size_t>(copy_len));

    write_pos += copy_len;
    cursor += copy_len;
    chunk_index++;
  }

  output[out_len] = '\0';
  return output;
}

void streaming_markdown_rope_free_c_string(const char *allocated_c_string) {
  std::free(const_cast<char *>(allocated_c_string));
}

void streaming_markdown_rope_clear(void *handle) {
  auto *rope = static_cast<NativeRope *>(handle);
  if (rope == nullptr) {
    return;
  }
  rope->chunks.clear();
  rope->prefix_lengths.clear();
  rope->length_bytes = 0;
}

}  // extern "C"
