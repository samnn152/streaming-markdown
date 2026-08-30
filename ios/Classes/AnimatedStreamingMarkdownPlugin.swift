import Flutter
import UIKit

public class AnimatedStreamingMarkdownPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "animated_streaming_markdown/clipboard",
      binaryMessenger: registrar.messenger()
    )
    let instance = AnimatedStreamingMarkdownPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "writeRichText",
          let arguments = call.arguments as? [String: Any],
          let plainText = arguments["plainText"] as? String,
          let htmlText = arguments["htmlText"] as? String else {
      result(FlutterMethodNotImplemented)
      return
    }
    UIPasteboard.general.setItems([[
      "public.utf8-plain-text": plainText,
      "public.html": htmlText,
    ]])
    result(nil)
  }
}
