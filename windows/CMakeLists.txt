cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "animated_streaming_markdown")
project(${PROJECT_NAME} LANGUAGES CXX)

add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../src" "${CMAKE_CURRENT_BINARY_DIR}/shared")

add_library(animated_streaming_markdown_plugin STATIC
  "${CMAKE_CURRENT_SOURCE_DIR}/include/animated_streaming_markdown/animated_streaming_markdown_plugin.h"
  "${CMAKE_CURRENT_SOURCE_DIR}/animated_streaming_markdown_plugin.cpp"
)
target_link_libraries(animated_streaming_markdown_plugin PRIVATE flutter_wrapper_plugin)
target_include_directories(animated_streaming_markdown_plugin PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
)

set(animated_streaming_markdown_bundled_libraries
  $<TARGET_FILE:animated_streaming_markdown>
  $<TARGET_FILE:animated_streaming_markdown_plugin>
  PARENT_SCOPE
)
