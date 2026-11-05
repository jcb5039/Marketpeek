import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:marketpeek/data/catalog.dart';
import 'package:marketpeek/data/quote_repository.dart';
import 'package:marketpeek/main.dart';
import 'package:marketpeek/state/app_state.dart';
import 'package:marketpeek/util/format.dart';
import 'package:marketpeek/util/market_hours.dart';
import 'package:marketpeek/widget_bridge/widget_sync.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoopSync extends WidgetSync {
  @override
  Future<void> push(AppState state) async {}
}

Future<AppState> _state() async {
  final s = AppState(repository: MockQuoteRepository(), widgetSync: _NoopSync());
  await s.load();
  return s;
}

void main() {
  setUpAll(() => initializeDateFormatting('ko_KR'));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('가격 표시 기준 (기획서 6장)', () {
    test('코인 원화가', () {
      expect(formatKrw(100000000), '100,000,000원');
      expect(formatKrw(3500), '3,500원');
      expect(formatPct(2.5), '+2.50%');
      expect(formatPct(-1.2), '-1.20%');
    });

    test('미국주식은 USD/KRW로 원화 환산', () {
      expect(formatUsd(450), r'$450.00');
      expect(formatKrw(stockKrw(450, 1430)), '643,500원');
    });

    test('환율은 통화별 기준 단위로 표기', () {
      expect(formatFxLine(Catalog.currency('USD'), 1430.5), '1 USD = 1,430.50원');
      expect(formatFxLine(Catalog.currency('JPY'), 950), '100 JPY = 950원');
    });
  });

  test('위젯용 짧은 원화 표기', () {
    expect(formatKrwShort(100000000), '1억');
    expect(formatKrwShort(123456789), '1.23억');
    expect(formatKrwShort(5200000), '520만');
    expect(formatKrwShort(643725), '64.4만');
    expect(formatKrwShort(3500), '3,500');
  });

  group('미국장 상태', () {
    test('서머타임 중 정규장', () {
      // 2026-07-15(수) 10:00 EDT = 14:00 UTC
      expect(usMarketStatus(DateTime.utc(2026, 7, 15, 14)), UsMarketStatus.open);
      expect(usMarketStatus(DateTime.utc(2026, 7, 15, 20, 1)), UsMarketStatus.closed);
    });

    test('표준시 중 정규장 / 주말', () {
      // 2026-11-05(목) 09:30 EST = 14:30 UTC
      expect(usMarketStatus(DateTime.utc(2026, 11, 5, 14, 30)), UsMarketStatus.open);
      expect(usMarketStatus(DateTime.utc(2026, 11, 5, 14, 29)), UsMarketStatus.closed);
      expect(usMarketStatus(DateTime.utc(2026, 11, 7, 15)), UsMarketStatus.closed);
    });
  });

  group('위젯 스냅샷', () {
    test('위젯 종목 수만큼만, 목록 순서대로 담긴다', () async {
      final s = await _state();
      await s.addCoin('BTC');
      await s.addCoin('XRP');
      await s.addCoin('ETH');
      await s.updateSettings(coinWidgetCount: 2);
      await s.reorderCoins(2, 0); // ETH를 맨 앞으로

      final snap = WidgetSync.buildSnapshot(s);
      final coins = snap['coins'] as List;
      expect(coins.map((c) => c['symbol']), ['ETH', 'BTC']);
    });

    test('미국주식 원화는 선택 통화와 무관하게 USD/KRW', () async {
      final s = await _state();
      await s.addStock('TSLA');
      await s.setFx('JPY');

      final snap = WidgetSync.buildSnapshot(s);
      expect((snap['stocks'] as List).first['priceKrw'], formatKrw(stockKrw(450, 1430.5)));
      expect((snap['fx'] as Map)['code'], 'JPY');
      expect((snap['fx'] as Map)['rate'], '950원');
    });

    test('시세가 없는 종목은 null로 전달', () async {
      final s = await _state();
      await s.addStock('AAPL');
      final stock = (WidgetSync.buildSnapshot(s)['stocks'] as List).first;
      expect(stock['priceUsd'], isNull);
      expect(stock['priceKrw'], isNull);
    });
  });

  testWidgets('빈 상태에서 빠른 추가', (tester) async {
    final s = AppState(repository: MockQuoteRepository(), widgetSync: _NoopSync());
    await tester.pumpWidget(MarketPeekApp(state: s));
    await tester.runAsync(s.load);
    await tester.pumpAndSettle();

    expect(find.text('아직 추가한 항목이 없어요'), findsOneWidget);
    await tester.tap(find.text('+ BTC'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();

    expect(find.text('BTC'), findsOneWidget);
    expect(find.text('100,000,000원'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });
}
