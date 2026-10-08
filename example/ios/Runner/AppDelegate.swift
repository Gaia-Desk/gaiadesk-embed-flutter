import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Test hooks (lib/demo_hooks.dart): Dart's Platform.environment is empty
    // on iOS, so hand it the GAIADESK_* variables.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "DemoEnv") {
      FlutterMethodChannel(name: "gaiadesk_embed_example/env", binaryMessenger: registrar.messenger())
        .setMethodCallHandler { call, result in
          guard call.method == "environment" else { return result(FlutterMethodNotImplemented) }
          result(ProcessInfo.processInfo.environment.filter { $0.key.hasPrefix("GAIADESK_") })
        }
    }
  }
}
