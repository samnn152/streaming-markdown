#include "include/animated_streaming_markdown/animated_streaming_markdown_plugin.h"

#include <gtk/gtk.h>

#include <cstring>
#include <string>

namespace {

struct ClipboardData {
  std::string plain;
  std::string html;
};

void ClipboardGet(GtkClipboard*, GtkSelectionData* selection_data, guint info,
                  gpointer user_data) {
  auto* data = static_cast<ClipboardData*>(user_data);
  if (info == 1) {
    gtk_selection_data_set(selection_data, gdk_atom_intern_static_string("text/html"),
                            8, reinterpret_cast<const guchar*>(data->html.data()),
                            static_cast<gint>(data->html.size()));
  } else {
    gtk_selection_data_set_text(selection_data, data->plain.c_str(), -1);
  }
}

void ClipboardClear(GtkClipboard*, gpointer user_data) {
  delete static_cast<ClipboardData*>(user_data);
}

void HandleMethodCall(FlMethodChannel*, FlMethodCall* call, gpointer) {
  g_autoptr(FlMethodResponse) response = nullptr;
  if (strcmp(fl_method_call_get_name(call), "writeRichText") != 0) {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  } else {
    FlValue* args = fl_method_call_get_args(call);
    FlValue* plain = fl_value_lookup_string(args, "plainText");
    FlValue* html = fl_value_lookup_string(args, "htmlText");
    if (plain == nullptr || html == nullptr || fl_value_get_type(plain) != FL_VALUE_TYPE_STRING ||
        fl_value_get_type(html) != FL_VALUE_TYPE_STRING) {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "invalid_arguments", "Clipboard payload is incomplete.", nullptr));
    } else {
      auto* data = new ClipboardData{fl_value_get_string(plain), fl_value_get_string(html)};
      GtkTargetEntry targets[] = {
          {const_cast<gchar*>("text/plain"), 0, 0},
          {const_cast<gchar*>("text/html"), 0, 1},
      };
      GtkClipboard* clipboard = gtk_clipboard_get(GDK_SELECTION_CLIPBOARD);
      const gboolean accepted = gtk_clipboard_set_with_data(
          clipboard, targets, 2, ClipboardGet, ClipboardClear, data);
      if (!accepted) {
        delete data;
        response = FL_METHOD_RESPONSE(fl_method_error_response_new(
            "clipboard_failed", "GTK rejected the rich clipboard payload.", nullptr));
      } else {
        response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
      }
    }
  }
  fl_method_call_respond(call, response);
}

}  // namespace

void animated_streaming_markdown_plugin_register_with_registrar(
    FlPluginRegistrar* registrar) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar),
      "animated_streaming_markdown/clipboard", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, HandleMethodCall, nullptr, nullptr);
}
