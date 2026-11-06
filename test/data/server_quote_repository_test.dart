// ServerQuoteRepository: 서버 /quotes 응답 변환, 요청 파라미터, 실패 처리 테스트.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marketpeek/data/server_quote_repository.dart';

void main() {
  test('/quotes 응답을 주식·환율·이슈로 바꾸고 USD는 항상 요청한다', () async {
    late Uri requested;
    final client = MockClient((req) async {
      requested = req.url;
      return http.Response(
        jsonEncode({
          'stocks': {
            'TSLA': {'priceUsd': 450, 'changePct': 3.1},
          },
          'fx': {
            'USD': {'rateKrw': 1430.5, 'changePct': 0.4},
            'JPY': {'rateKrw': 950, 'changePct': -0.2},
          },
          'issue': {
            'text': 'FOMC 금리 동결',
            'shortText': 'FOMC 동결',
            'generatedAt': '2026-11-05T23:00:00Z',
          },
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final repo = ServerQuoteRepository(baseUrl: 'https://api.example.dev', client: client);

    final b = await repo.fetch(
      coinSymbols: const ['BTC'],
      stockTickers: const ['TSLA', 'NVDA'],
      currencyCodes: const ['JPY'],
    );

    expect(requested.toString(), startsWith('https://api.example.dev/quotes?'));
    expect(requested.queryParameters['stocks'], 'TSLA,NVDA');
    expect(requested.queryParameters['fx']!.split(','), containsAll(['JPY', 'USD']));
    expect(b.coins, isEmpty);
    expect(b.stocks['TSLA']!.priceUsd, 450.0);
    expect(b.stocks.containsKey('NVDA'), isFalse);
    expect(b.fx['JPY']!.rateKrw, 950.0);
    expect(b.issue!.shortText, 'FOMC 동결');
    expect(b.issue!.generatedAt, DateTime.utc(2026, 11, 5, 23));
  });

  test('issue가 null이면 이슈 없음', () async {
    final client = MockClient(
      (_) async => http.Response('{"stocks":{},"fx":{},"issue":null}', 200),
    );
    final repo = ServerQuoteRepository(baseUrl: 'https://api.example.dev', client: client);
    final b = await repo.fetch(coinSymbols: const [], stockTickers: const [], currencyCodes: const []);
    expect(b.issue, isNull);
  });

  test('서버가 200이 아니면 예외', () async {
    final client = MockClient((_) async => http.Response('down', 503));
    final repo = ServerQuoteRepository(baseUrl: 'https://api.example.dev', client: client);
    expect(
      () => repo.fetch(coinSymbols: const [], stockTickers: const [], currencyCodes: const []),
      throwsA(isA<http.ClientException>()),
    );
  });
}
