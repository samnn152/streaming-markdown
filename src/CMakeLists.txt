# The Flutter tooling requires that developers have CMake 3.10 or later.
cmake_minimum_required(VERSION 3.10)

project(animated_streaming_markdown_library VERSION 0.0.1 LANGUAGES C CXX)

add_library(animated_streaming_markdown SHARED
  "../packages/tree-sitter/lib/src/lib.c"
  "../packages/tree-sitter-markdown/tree-sitter-markdown/src/parser.c"
  "../packages/tree-sitter-markdown/tree-sitter-markdown/src/scanner.c"
  "../packages/tree-sitter-markdown/tree-sitter-markdown-inline/src/parser.c"
  "../packages/tree-sitter-markdown/tree-sitter-markdown-inline/src/scanner.c"
  "streaming_markdown.c"
  "streaming_markdown_incremental.cpp"
  "streaming_markdown_rope.cpp"
  "streaming_markdown_ts_parser.cpp"
)

set_target_properties(animated_streaming_markdown PROPERTIES
  PUBLIC_HEADER streaming_markdown.h
  OUTPUT_NAME "animated_streaming_markdown"
)

target_compile_definitions(animated_streaming_markdown PUBLIC DART_SHARED_LIB)
target_compile_features(animated_streaming_markdown PRIVATE cxx_std_17)
target_include_directories(animated_streaming_markdown PRIVATE
  "../packages/tree-sitter/lib/include"
)

if (ANDROID)
  # Support Android 15 16k page size.
  target_link_options(animated_streaming_markdown PRIVATE "-Wl,-z,max-page-size=16384")
endif()
