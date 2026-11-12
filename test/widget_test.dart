import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:marketpeek/app/app_scope.dart';
import 'package:marketpeek/data/catalog.dart';
import 'package:marketpeek/data/kis_quote_repository.dart';
import 'package:marketpeek/data/quote_repository.dart';
import 'package:marketpeek/main.dart';
import 'package:marketpeek/state/app_state.dart';
import 'package:marketpeek/ui/currency/currency_screen.dart';
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
      expect(formatKrw(0.00694), '0.00694원');
      expect(formatKrw(0.5), '0.5원');
      expect(formatKrw(12.3), '12.30원');
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
    expect(formatKrwShort(0.00694), '0.00694');
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
    test('6개까지, 목록 순서대로 담고 한 칸 개수는 설정으로 보낸다', () async {
      final s = await _state();
      for (final c in Catalog.coins.take(7)) {
        await s.addCoin(c.symbol);
      }
      await s.updateSettings(coinWidgetCount: 3);
      await s.reorderCoins(2, 0); // 3번째를 맨 앞으로

      final snap = WidgetSync.buildSnapshot(s);
      final coins = (snap['coins'] as List).map((c) => c['symbol']).toList();
      expect(coins, s.coinSymbols.take(AppState.maxWidgetItems).toList());
      expect(coins.length, 6);
      expect(coins.first, Catalog.coins[2].symbol);
      expect((snap['settings'] as Map)['coinRows'], 3);
    });

    test('국내주식은 목록 순서대로 이름·원화 가격과 함께 담기고 저장된다', () async {
      final s = await _state();
      await s.addKrStock('000660');
      await s.addKrStock('005930');
      await s.addKrStock('005930'); // 중복은 무시

      final kr = WidgetSync.buildSnapshot(s)['krStocks'] as List;
      expect(kr.map((k) => k['code']), ['000660', '005930']);
      expect(kr.last['name'], '삼성전자');
      expect(kr.last['price'], formatKrw(98500)); // MockQuoteRepository 예시 값
      expect(s.isEmpty, isFalse);

      await s.removeKrStock('000660');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('krStocks'), ['005930']);
    });

    test('미국주식 원화는 선택 통화와 무관하게 USD/KRW', () async {
      final s = await _state();
      await s.addStock('TSLA');
      await s.addFx('JPY');
      await s.addFx('USD');

      final snap = WidgetSync.buildSnapshot(s);
      expect((snap['stocks'] as List).first['priceKrw'], formatKrw(stockKrw(450, 1430.5)));
      expect((snap['fx'] as Map)['code'], 'JPY');
      expect((snap['fx'] as Map)['rate'], '950원');
      // 자유 구성 위젯용: 앱에서 고른 통화만, 고른 순서대로 들어간다.
      final list = (snap['fxList'] as List).map((f) => f['code']).toList();
      expect(list, ['JPY', 'USD']);
    });

    test('v8: 위젯이 직접 받을 때 쓰는 거래소 코드·USD/KRW·서버 주소를 담는다', () async {
      final s = await _state();
      await s.addStock('TSLA');

      final snap = WidgetSync.buildSnapshot(s);
      expect(snap['schemaVersion'], 8);
      expect((snap['stocks'] as List).first['excd'], Catalog.stock('TSLA').excd);
      expect(snap['usdKrw'], 1430.5); // MockQuoteRepository 예시 값
      // 테스트는 --dart-define 없이 돌므로 서버 주소는 비어 있다.
      expect((snap['settings'] as Map).containsKey('apiBaseUrl'), isTrue);
      expect((snap['settings'] as Map)['apiBaseUrl'], isNull);
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

  group('증권사 연결 안내', () {
    Future<AppState> pumpHome(WidgetTester tester, {required bool connected}) async {
      final store = MemoryKisCredentialStore();
      if (connected) store.credentials = const KisCredentials(appKey: 'k', appSecret: 's');
      // 실제 KIS는 부르지 않는다 (연결 상태 표시만 본다).
      final kis = KisQuoteRepository(
        fallback: MockQuoteRepository(),
        store: store,
        client: MockClient((_) async => http.Response('{}', 500)),
      );
      final s = AppState(repository: kis, widgetSync: _NoopSync(), kis: kis);
      await tester.runAsync(() async {
        await s.load();
        await s.addKrStock('005930');
      });
      await tester.pumpWidget(MarketPeekApp(state: s));
      await tester.pumpAndSettle();
      return s;
    }

    testWidgets('미연결이면 주식 위에 안내를 띄우고 누르면 연결 화면으로 간다', (tester) async {
      final s = await pumpHome(tester, connected: false);
      expect(find.text('증권사를 연결하면 주식 시세가 보여요'), findsOneWidget);
      expect(WidgetSync.buildSnapshot(s)['settings']['stocksConnected'], isFalse);

      await tester.tap(find.text('연결하기 ›'));
      await tester.pumpAndSettle();
      expect(find.text('App Key'), findsOneWidget);
    });

    testWidgets('연결돼 있으면 안내가 없다', (tester) async {
      final s = await pumpHome(tester, connected: true);
      expect(find.text('증권사를 연결하면 주식 시세가 보여요'), findsNothing);
      expect(WidgetSync.buildSnapshot(s)['settings']['stocksConnected'], isTrue);
    });
  });

  testWidgets('환율: 여러 통화를 고르고, 다시 누르면 빠지고, 완료로 닫힌다', (tester) async {
    final s = AppState(repository: MockQuoteRepository(), widgetSync: _NoopSync());
    await tester.runAsync(s.load);
    await tester.pumpWidget(AppScope(
      state: s,
      child: MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: (_) => const CurrencyScreen())),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    Future<void> tapUsd() async {
      await tester.tap(find.text('미국 달러 USD'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
    }

    await tapUsd();
    expect(s.fxCodes, ['USD']);
    await tester.tap(find.text('일본 엔 JPY'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(s.fxCodes, ['USD', 'JPY']);
    await tapUsd();
    expect(s.fxCodes, ['JPY']);

    await tester.tap(find.text('완료'));
    await tester.pumpAndSettle();
    expect(find.byType(CurrencyScreen), findsNothing);
  });
}
