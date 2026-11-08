import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../data/catalog.dart';
import '../state/app_state.dart';
import '../util/format.dart';

/// Flutter 앱 → iOS 잠금화면 위젯 데이터 전달.
///
/// App Group UserDefaults의 [snapshotKey]에 JSON 한 덩어리를 쓰고 위젯 4종의
/// 타임라인을 다시 불러오게 한다. 스키마는 ios/MarketPeekWidget/Snapshot.swift와
/// 반드시 맞춰야 한다 (schemaVersion을 올리고 양쪽을 같이 고칠 것).
class WidgetSync {
  static const appGroupId = 'group.com.yoonhyukju.marketpeek';
  static const snapshotKey = 'snapshot';
  static const schemaVersion = 5;

  /// WidgetKit `kind` 값. Swift 쪽 위젯 정의와 일치해야 한다.
  static const widgetKinds = [
    'CoinWidget',
    'StockWidget',
    'FxWidget',
    'IssueWidget',
    'MixWidget',
  ];

  bool _initialized = false;

  bool get _supported => !kIsWeb && Platform.isIOS;

  Future<void> push(AppState state) async {
    if (!_supported) return;
    if (!_initialized) {
      await HomeWidget.setAppGroupId(appGroupId);
      _initialized = true;
    }
    final json = jsonEncode(buildSnapshot(state));
    await HomeWidget.saveWidgetData<String>(snapshotKey, json);
    for (final kind in widgetKinds) {
      await HomeWidget.updateWidget(iOSName: kind);
    }
  }

  /// 위젯이 그대로 그릴 수 있게 표시 문자열까지 만들어 넘긴다.
  /// 등락률 원값(changePct)은 색상 결정용으로 함께 보낸다.
  @visibleForTesting
  static Map<String, dynamic> buildSnapshot(AppState s) {
    final q = s.quotes;
    final usdKrw = s.usdKrw;

    final coins = [
      for (final sym in s.coinSymbols.take(AppState.maxWidgetItems))
        {
          'symbol': sym,
          'name': Catalog.coin(sym).name,
          'price': q?.coins[sym] == null
              ? null
              : formatKrw(q!.coins[sym]!.priceKrw),
          'priceShort': q?.coins[sym] == null
              ? null
              : formatKrwShort(q!.coins[sym]!.priceKrw),
          'change': q?.coins[sym]?.changePct,
        },
    ];

    final stocks = [
      for (final t in s.stockTickers.take(AppState.maxWidgetItems))
        () {
          final sq = q?.stocks[t];
          return {
            'ticker': t,
            'name': Catalog.stock(t).name,
            'priceUsd': sq == null ? null : formatUsd(sq.priceUsd),
            'priceKrw': (sq == null || usdKrw == null)
                ? null
                : formatKrw(stockKrw(sq.priceUsd, usdKrw)),
            'priceKrwShort': (sq == null || usdKrw == null)
                ? null
                : formatKrwShort(stockKrw(sq.priceUsd, usdKrw)),
            'change': sq?.changePct,
          };
        }(),
    ];

    Map<String, dynamic> fxJson(String code) {
      final c = Catalog.currency(code);
      final fq = q?.fx[code];
      return {
        'code': c.code,
        'name': c.name,
        'unit': c.unit,
        'rate': fq == null ? null : formatFxRate(fq.rateKrw),
        'change': fq?.changePct,
      };
    }

    final code = s.fxCode;

    final issue = q?.issue;

    return {
      'schemaVersion': schemaVersion,
      'updatedAt': q?.fetchedAt.toUtc().toIso8601String(),
      'settings': {
        'colorScheme': s.colorScheme.name,
        'showStockKrw': s.showStockKrw,
        'showMarketStatus': s.showMarketStatus,
        'showUpdatedAt': s.showUpdatedAt,
        // v4: 사각형 위젯 한 칸에 보일 개수. 위젯이 고른 시작 위치부터 이만큼 보여준다.
        'coinRows': s.coinWidgetCount,
        'stockRows': s.stockWidgetCount,
      },
      'coins': coins,
      'stocks': stocks,
      'fx': code == null ? null : fxJson(code),
      // v5: 앱에서 고른 통화 전체 (고른 순서). 자유 구성 위젯이 칸마다 이 중에서 고른다.
      'fxList': [for (final c in s.fxCodes) fxJson(c)],
      'issue': issue == null
          ? null
          : {
              'text': issue.text,
              'short': issue.shortText,
              'generatedAt': issue.generatedAt.toUtc().toIso8601String(),
            },
    };
  }
}
