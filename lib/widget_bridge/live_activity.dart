import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 잠금화면 라이브 액티비티 (iOS 16.2+).
/// 네이티브는 ios/Runner/AppDelegate.swift `LiveActivityController`, 화면은 위젯 확장 `MarketLiveActivity`.
/// 푸시(유료 계정 필요)를 쓰지 않으므로 앱이 켜져 있을 때만 값이 바뀐다.
class LiveActivity {
  static const _channel = MethodChannel('marketpeek/live');

  /// 시작되면 true. 아이폰 설정에서 실시간 현황을 껐거나 지원하지 않으면 false.
  Future<bool> start(List<LiveRow> rows, String scheme) async =>
      await _call<bool>('start', _args(rows, scheme)) ?? false;

  Future<void> update(List<LiveRow> rows, String scheme) => _call<void>('update', _args(rows, scheme));

  Future<void> end() => _call<void>('end');

  /// 떠 있는지 (8시간이 지나면 iOS가 끝낸다).
  Future<bool> isActive() async => await _call<bool>('isActive') ?? false;

  Map<String, Object?> _args(List<LiveRow> rows, String scheme) =>
      {'rows': [for (final r in rows) r.toMap()], 'scheme': scheme};

  Future<T?> _call<T>(String method, [Object? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } catch (e) {
      // 테스트·안드로이드 등 채널이 없는 곳에서는 조용히 넘어간다.
      debugPrint('LiveActivity $method failed: $e');
      return null;
    }
  }
}

/// 라이브 액티비티 한 칸.
class LiveRow {
  const LiveRow({required this.id, required this.symbol, required this.price, this.change});

  /// "coin:BTC", "stock:TSLA", "fx:USD"
  final String id;
  final String symbol;
  final String price;
  final double? change;

  Map<String, Object?> toMap() => {'id': id, 'symbol': symbol, 'price': price, 'change': change};
}
