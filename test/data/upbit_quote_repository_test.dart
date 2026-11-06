// UpbitQuoteRepository: 업비트 응답 변환, 요청 파라미터, 실패 처리, fallback 병합 테스트.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marketpeek/data/catalog.dart';
import 'package:marketpeek/data/quote_repository.dart';
import 'package:marketpeek/data/upbit_quote_repository.dart';

void main() {
  Future<QuoteBundle> fetch(UpbitQuoteRepository repo, List<String> coins) =>
      repo.fetch(
        coinSymbols: coins,
        stockTickers: const ['TSLA'],
        currencyCodes: const ['USD'],
      );

  test('업비트 응답을 CoinQuote로 바꾸고 주식·환율은 fallback 값을 쓴다', () async {
    late Uri requested;
    final client = MockClient((req) async {
      requested = req.url;
      return http.Response(
        jsonEncode([
          {'market': 'KRW-BTC', 'trade_price': 102827000.0, 'signed_change_rate': 0.025},
          {'market': 'KRW-XRP', 'trade_price': 3500, 'signed_change_rate': -0.012},
        ]),
        200,
      );
    });
    final repo = UpbitQuoteRepository(fallback: MockQuoteRepository(), client: client);

    final bundle = await fetch(repo, ['BTC', 'XRP']);

    expect(requested.host, 'api.upbit.com');
    expect(requested.path, '/v1/ticker');
    expect(requested.queryParameters['markets'], 'KRW-BTC,KRW-XRP');
    expect(bundle.coins['BTC']!.priceKrw, 102827000.0);
    expect(bundle.coins['BTC']!.changePct, closeTo(2.5, 1e-9));
    expect(bundle.coins['XRP']!.priceKrw, 3500.0);
    expect(bundle.coins['XRP']!.changePct, closeTo(-1.2, 1e-9));
    expect(bundle.stocks['TSLA']!.priceUsd, 450.00);
    expect(bundle.fx['USD']!.rateKrw, 1430.50);
    expect(bundle.issue, isNotNull);
  });

  test('코인 목록이 비면 업비트를 호출하지 않는다', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return http.Response('[]', 200);
    });
    final repo = UpbitQuoteRepository(fallback: MockQuoteRepository(), client: client);

    final bundle = await fetch(repo, []);

    expect(calls, 0);
    expect(bundle.coins, isEmpty);
    expect(bundle.stocks, isNotEmpty);
  });

  test('업비트가 200이 아니면 예외를 던진다', () async {
    final client = MockClient((_) async => http.Response('error', 500));
    final repo = UpbitQuoteRepository(fallback: MockQuoteRepository(), client: client);

    expect(() => fetch(repo, ['BTC']), throwsA(isA<http.ClientException>()));
  });

  group('코인 목록', () {
    final marketAll = jsonEncode([
      {'market': 'KRW-BTC', 'korean_name': '비트코인', 'english_name': 'Bitcoin'},
      {'market': 'BTC-ETH', 'korean_name': '이더리움', 'english_name': 'Ethereum'},
      {'market': 'KRW-ETH', 'korean_name': '이더리움', 'english_name': 'Ethereum'},
      {'market': 'KRW-BTT', 'korean_name': '비트토렌트', 'english_name': 'BitTorrent'},
      {'market': 'USDT-XRP', 'korean_name': '리플', 'english_name': 'XRP'},
    ]);

    tearDown(Catalog.resetCoins);

    test('market/all에서 원화 마켓만 남기고 한글 이름을 쓴다', () async {
      late Uri requested;
      final client = MockClient((req) async {
        requested = req.url;
        return http.Response.bytes(utf8.encode(marketAll), 200);
      });
      final repo = UpbitQuoteRepository(fallback: MockQuoteRepository(), client: client);

      final coins = await repo.fetchCoinList();

      expect(requested.path, '/v1/market/all');
      expect(coins.map((c) => c.symbol), ['BTC', 'ETH', 'BTT']);
      expect(coins.first.name, '비트코인');
    });

    test('목록에 없는 코인(상장폐지 등)은 시세 요청에서 뺀다', () async {
      final tickerRequests = <Uri>[];
      final client = MockClient((req) async {
        if (req.url.path == '/v1/market/all') {
          return http.Response.bytes(utf8.encode(marketAll), 200);
        }
        tickerRequests.add(req.url);
        return http.Response(
          jsonEncode([
            {'market': 'KRW-BTC', 'trade_price': 1, 'signed_change_rate': 0},
          ]),
          200,
        );
      });
      final repo = UpbitQuoteRepository(fallback: MockQuoteRepository(), client: client);
      await repo.fetchCoinList();

      final bundle = await fetch(repo, ['BTC', 'GONE']);

      expect(tickerRequests.single.queryParameters['markets'], 'KRW-BTC');
      expect(bundle.coins.keys, ['BTC']);
    });

    test('목록에 없는 심볼은 심볼을 이름으로 쓴다', () {
      final c = Catalog.coin('UNKNOWN');
      expect(c.symbol, 'UNKNOWN');
      expect(c.name, 'UNKNOWN');
    });

    test('검색은 심볼 일치 → 앞부분 일치 → 포함 순', () async {
      final client = MockClient(
          (_) async => http.Response.bytes(utf8.encode(marketAll), 200));
      final repo = UpbitQuoteRepository(fallback: MockQuoteRepository(), client: client);
      Catalog.setCoins(await repo.fetchCoinList());

      expect(Catalog.searchCoins('btc').map((c) => c.symbol), ['BTC']);
      expect(Catalog.searchCoins('bt').map((c) => c.symbol), ['BTC', 'BTT']);
      expect(Catalog.searchCoins('비트').map((c) => c.symbol), ['BTC', 'BTT']);
      expect(Catalog.searchCoins('이더').single.name, '이더리움');
    });
  });
}
