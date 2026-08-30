#include "include/animated_streaming_markdown/animated_streaming_markdown_plugin.h"

#include <windows.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <string>

namespace {

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) return std::wstring();
  const int size = MultiByteToWideChar(CP_UTF8, 0, value.data(),
                                       static_cast<int>(value.size()), nullptr, 0);
  std::wstring result(size, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.data(),
                      static_cast<int>(value.size()), result.data(), size);
  return result;
}

HGLOBAL GlobalCopy(const void* data, size_t size) {
  HGLOBAL handle = GlobalAlloc(GMEM_MOVEABLE, size);
  if (handle == nullptr) return nullptr;
  void* destination = GlobalLock(handle);
  if (destination == nullptr) {
    GlobalFree(handle);
    return nullptr;
  }
  memcpy(destination, data, size);
  GlobalUnlock(handle);
  return handle;
}

bool WriteClipboard(const std::string& plain, const std::string& html) {
  const std::wstring wide_plain = Utf8ToWide(plain);
  const size_t wide_size = (wide_plain.size() + 1) * sizeof(wchar_t);
  if (!OpenClipboard(nullptr)) return false;
  EmptyClipboard();
  const UINT html_format = RegisterClipboardFormat(L"HTML Format");
  HGLOBAL text_handle = GlobalCopy(wide_plain.c_str(), wide_size);
  HGLOBAL html_handle = GlobalCopy(html.data(), html.size() + 1);
  bool success = text_handle != nullptr && html_handle != nullptr;
  if (success) {
    success = SetClipboardData(CF_UNICODETEXT, text_handle) != nullptr;
    if (success) success = SetClipboardData(html_format, html_handle) != nullptr;
  }
  if (!success) {
    if (text_handle != nullptr) GlobalFree(text_handle);
    if (html_handle != nullptr) GlobalFree(html_handle);
  }
  CloseClipboard();
  return success;
}

class AnimatedStreamingMarkdownPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar) {
    auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
        registrar->messenger(), "animated_streaming_markdown/clipboard",
        &flutter::StandardMethodCodec::GetInstance());
    auto plugin = std::make_unique<AnimatedStreamingMarkdownPlugin>();
    channel->SetMethodCallHandler(
        [plugin_pointer = plugin.get()](const auto& call, auto result) {
          plugin_pointer->HandleMethodCall(call, std::move(result));
        });
    registrar->AddPlugin(std::move(plugin));
  }

 private:
  void HandleMethodCall(const flutter::MethodCall<flutter::EncodableValue>& call,
                        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    if (call.method_name() != "writeRichText") {
      result->NotImplemented();
      return;
    }
    const auto* arguments = std::get_if<flutter::EncodableMap>(call.arguments());
    if (arguments == nullptr) {
      result->Error("invalid_arguments", "Clipboard payload is missing.");
      return;
    }
    const auto plain = arguments->find(flutter::EncodableValue("plainText"));
    const auto html = arguments->find(flutter::EncodableValue("htmlText"));
    if (plain == arguments->end() || html == arguments->end()) {
      result->Error("invalid_arguments", "Clipboard payload is incomplete.");
      return;
    }
    const auto* plain_text = std::get_if<std::string>(&plain->second);
    const auto* html_text = std::get_if<std::string>(&html->second);
    if (plain_text == nullptr || html_text == nullptr ||
        !WriteClipboard(*plain_text, *html_text)) {
      result->Error("clipboard_failed", "Windows rejected the rich clipboard payload.");
      return;
    }
    result->Success();
  }
};

}  // namespace

void AnimatedStreamingMarkdownPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  AnimatedStreamingMarkdownPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
