// UpbitQuoteRepository: 업비트 응답 변환, 요청 파라미터, 실패 처리, fallback 병합 테스트.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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
}
