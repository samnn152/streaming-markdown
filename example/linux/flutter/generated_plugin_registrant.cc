//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <animated_streaming_markdown/animated_streaming_markdown_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) animated_streaming_markdown_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "AnimatedStreamingMarkdownPlugin");
  animated_streaming_markdown_plugin_register_with_registrar(animated_streaming_markdown_registrar);
}
