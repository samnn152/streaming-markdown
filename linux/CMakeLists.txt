cmake_minimum_required(VERSION 3.10)

set(PROJECT_NAME "streaming_markdown")
project(${PROJECT_NAME} LANGUAGES CXX)

add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../src" "${CMAKE_CURRENT_BINARY_DIR}/shared")

set(streaming_markdown_bundled_libraries
  $<TARGET_FILE:streaming_markdown>
  PARENT_SCOPE
)
