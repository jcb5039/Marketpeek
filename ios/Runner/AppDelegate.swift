import ActivityKit
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
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "MarketLiveActivity") {
      LiveActivityChannel.register(messenger: registrar.messenger())
    }
  }
}

// MARK: - 잠금화면 라이브 액티비티
// Dart lib/widget_bridge/live_activity.dart가 채널 "marketpeek/live"로 시작·갱신·종료를 부른다.
// 화면은 위젯 확장(MarketPeekWidget/Widgets.swift MarketLiveActivity)이 그린다.
// 푸시(유료 계정 필요)를 쓰지 않으므로 앱이 켜져 있을 때만 값이 바뀐다.

/// 위젯 확장의 같은 이름 struct와 이름·필드가 같아야 한다 (한쪽을 바꾸면 다른 쪽도).
@available(iOS 16.1, *)
struct MarketActivityAttributes: ActivityAttributes {
  struct Row: Codable, Hashable {
    /// "coin:BTC", "stock:TSLA", "fx:USD" (아이콘 고르기용)
    var id: String
    var symbol: String
    var price: String
    var change: Double?
  }

  struct ContentState: Codable, Hashable {
    var rows: [Row]
    /// "korean" | "global" (상승·하락 색)
    var scheme: String
    var updatedAt: Date
  }
}

enum LiveActivityChannel {
  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "marketpeek/live", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard #available(iOS 16.2, *) else {
        result(false)
        return
      }
      Task { @MainActor in
        switch call.method {
        case "start": result(await LiveActivityController.start(call.arguments))
        case "update":
          await LiveActivityController.update(call.arguments)
          result(nil)
        case "end":
          await LiveActivityController.end()
          result(nil)
        case "isActive": result(LiveActivityController.isActive)
        default: result(FlutterMethodNotImplemented)
        }
      }
    }
  }
}

@available(iOS 16.2, *)
enum LiveActivityController {
  static var isActive: Bool { !Activity<MarketActivityAttributes>.activities.isEmpty }

  /// 시작되면 true. 아이폰 설정에서 실시간 현황을 껐으면 false.
  static func start(_ args: Any?) async -> Bool {
    guard ActivityAuthorizationInfo().areActivitiesEnabled, let s = state(args) else { return false }
    await end()
    do {
      _ = try Activity<MarketActivityAttributes>.request(
        attributes: MarketActivityAttributes(), content: content(s), pushType: nil)
      return true
    } catch {
      return false
    }
  }

  static func update(_ args: Any?) async {
    guard let s = state(args) else { return }
    for activity in Activity<MarketActivityAttributes>.activities {
      await activity.update(content(s))
    }
  }

  static func end() async {
    for activity in Activity<MarketActivityAttributes>.activities {
      await activity.end(nil, dismissalPolicy: .immediate)
    }
  }

  /// 15분 넘게 새 값이 없으면 iOS가 오래된 값으로 표시한다(위젯 쪽 context.isStale).
  private static func content(_ s: MarketActivityAttributes.ContentState)
    -> ActivityContent<MarketActivityAttributes.ContentState> {
    ActivityContent(state: s, staleDate: Date().addingTimeInterval(15 * 60))
  }

  private static func state(_ args: Any?) -> MarketActivityAttributes.ContentState? {
    guard let m = args as? [String: Any], let rows = m["rows"] as? [[String: Any]] else { return nil }
    return MarketActivityAttributes.ContentState(
      rows: rows.map { r in
        MarketActivityAttributes.Row(
          id: r["id"] as? String ?? "",
          symbol: r["symbol"] as? String ?? "",
          price: r["price"] as? String ?? "—",
          change: (r["change"] as? NSNumber)?.doubleValue)
      },
      scheme: m["scheme"] as? String ?? "korean",
      updatedAt: Date())
  }
}
