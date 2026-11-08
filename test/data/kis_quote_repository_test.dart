// KisQuoteRepository: 키 없을 때 fallback, 토큰 발급·재사용·만료, 해외주식 응답 변환 테스트. 실제 KIS는 부르지 않는다.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marketpeek/data/kis_quote_repository.dart';
import 'package:marketpeek/data/quote_repository.dart';
import 'package:marketpeek/models/models.dart';

http.Response _json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

/// 요청을 기록하는 가짜 KIS 서버.
class _FakeKis {
  final requests = <http.Request>[];
  int tokenCalls = 0;
  Map<String, Map<String, dynamic>> prices = {
    'TSLA': {'rt_cd': '0', 'msg_cd': 'MCA00000', 'output': {'last': '358.2200', 'base': '343.7000', 'rate': '+4.22'}},
    'SPY': {'rt_cd': '0', 'msg_cd': 'MCA00000', 'output': {'last': '612.10', 'base': '610.00', 'rate': ''}},
    'NVDA': {'rt_cd': '0', 'msg_cd': 'MCA00000', 'output': {'last': '', 'base': '', 'rate': ''}},
  };
  Map<String, Map<String, dynamic>> krPrices = {
    '005930': {'rt_cd': '0', 'msg_cd': 'MCA00000', 'output': {'stck_prpr': '98500', 'prdy_ctrt': '-1.24'}},
  };
  http.Response Function()? tokenResponse;

  late final client = MockClient((req) async {
    requests.add(req);
    if (req.url.path == '/oauth2/tokenP') {
      tokenCalls++;
      return tokenResponse?.call() ??
          _json({'access_token': 'tok$tokenCalls', 'token_type': 'Bearer', 'expires_in': 86400});
    }
    if (req.url.path.contains('domestic-stock')) {
      final code = req.url.queryParameters['FID_INPUT_ISCD']!;
      final body = krPrices[code];
      return body == null ? _json({'rt_cd': '1', 'msg_cd': 'X', 'msg1': 'no'}, 500) : _json(body);
    }
    final symb = req.url.queryParameters['SYMB']!;
    final body = prices[symb];
    return body == null ? _json({'rt_cd': '1', 'msg_cd': 'X', 'msg1': 'no'}, 500) : _json(body);
  });
}

/// fallback이 어떤 인자로 불렸는지 기록한다.
class _RecordingFallback implements QuoteRepository {
  List<String>? lastStockTickers;
  List<String>? lastKrStockCodes;

  @override
  Future<QuoteBundle> fetch({
    required List<String> coinSymbols,
    required List<String> stockTickers,
    required List<String> currencyCodes,
    List<String> krStockCodes = const [],
  }) async {
    lastStockTickers = stockTickers;
    lastKrStockCodes = krStockCodes;
    return QuoteBundle(
      coins: const {},
      stocks: {for (final t in stockTickers) t: const StockQuote(priceUsd: 1, changePct: 0)},
      fx: const {'USD': FxQuote(rateKrw: 1342, changePct: 0.1)},
      issue: null,
      fetchedAt: DateTime(2026, 11, 8),
    );
  }
}

void main() {
  final now = DateTime(2026, 11, 8, 15);
  const creds = KisCredentials(appKey: 'key', appSecret: 'secret');

  KisQuoteRepository repo(_FakeKis kis, KisCredentialStore store, QuoteRepository fallback) =>
      KisQuoteRepository(
        fallback: fallback,
        store: store,
        client: kis.client,
        clock: () => now,
        requestGap: Duration.zero,
      );

  test('키가 없으면 주식도 fallback에 맡기고 KIS는 부르지 않는다', () async {
    final kis = _FakeKis();
    final fallback = _RecordingFallback();
    final b = await repo(kis, MemoryKisCredentialStore(), fallback)
        .fetch(coinSymbols: const [], stockTickers: const ['TSLA'], currencyCodes: const []);
    expect(fallback.lastStockTickers, ['TSLA']);
    expect(b.stocks['TSLA']!.priceUsd, 1);
    expect(kis.requests, isEmpty);
  });

  test('키가 있으면 KIS로 주식을 받고, 환율은 fallback에서 (주식 없이) 받는다', () async {
    final kis = _FakeKis();
    final store = MemoryKisCredentialStore()..credentials = creds;
    final fallback = _RecordingFallback();
    final b = await repo(kis, store, fallback).fetch(
      coinSymbols: const [],
      stockTickers: const ['TSLA', 'SPY', 'NVDA', 'AAPL'],
      currencyCodes: const ['USD'],
    );

    expect(fallback.lastStockTickers, isEmpty);
    expect(b.fx['USD']!.rateKrw, 1342);
    expect(b.stocks['TSLA']!.priceUsd, 358.22);
    expect(b.stocks['TSLA']!.changePct, 4.22);
    // rate가 비어 있으면 base로 계산한다.
    expect(b.stocks['SPY']!.changePct, closeTo((612.10 - 610) / 610 * 100, 1e-9));
    // 가격이 비었거나(NVDA) 실패한(AAPL) 종목은 빠진다.
    expect(b.stocks.containsKey('NVDA'), isFalse);
    expect(b.stocks.containsKey('AAPL'), isFalse);

    final spy = kis.requests.firstWhere((r) => r.url.queryParameters['SYMB'] == 'SPY');
    expect(spy.url.queryParameters['EXCD'], 'AMS');
    expect(spy.headers['tr_id'], 'HHDFS00000300');
    expect(spy.headers['authorization'], 'Bearer tok1');
    expect(spy.url.port, 9443);
    expect(store.token!.value, 'tok1');
  });

  test('국내주식은 주식현재가 시세(FHKST01010100)로 받는다', () async {
    final kis = _FakeKis();
    final store = MemoryKisCredentialStore()..credentials = creds;
    final fallback = _RecordingFallback();
    final b = await repo(kis, store, fallback).fetch(
      coinSymbols: const [],
      stockTickers: const [],
      currencyCodes: const [],
      krStockCodes: const ['005930', '999999'],
    );
    expect(b.krStocks['005930']!.priceKrw, 98500);
    expect(b.krStocks['005930']!.changePct, -1.24);
    expect(b.krStocks.containsKey('999999'), isFalse);
    expect(fallback.lastKrStockCodes, isEmpty);

    final req = kis.requests.firstWhere((r) => r.url.path.contains('domestic-stock'));
    expect(req.url.path, '/uapi/domestic-stock/v1/quotations/inquire-price');
    expect(req.url.queryParameters['FID_COND_MRKT_DIV_CODE'], 'J');
    expect(req.headers['tr_id'], 'FHKST01010100');
  });

  test('키가 없으면 국내주식도 fallback에 맡긴다', () async {
    final kis = _FakeKis();
    final fallback = _RecordingFallback();
    await repo(kis, MemoryKisCredentialStore(), fallback).fetch(
      coinSymbols: const [],
      stockTickers: const [],
      currencyCodes: const [],
      krStockCodes: const ['005930'],
    );
    expect(fallback.lastKrStockCodes, ['005930']);
    expect(kis.requests, isEmpty);
  });

  test('저장된 토큰이 아직 유효하면 다시 발급받지 않는다', () async {
    final kis = _FakeKis();
    final store = MemoryKisCredentialStore()
      ..credentials = creds
      ..token = KisToken(value: 'saved', expiresAt: now.add(const Duration(hours: 5)));
    await repo(kis, store, _RecordingFallback())
        .fetch(coinSymbols: const [], stockTickers: const ['TSLA'], currencyCodes: const []);
    expect(kis.tokenCalls, 0);
    expect(kis.requests.single.headers['authorization'], 'Bearer saved');
  });

  test('곧 만료될 토큰은 새로 받는다', () async {
    final kis = _FakeKis();
    final store = MemoryKisCredentialStore()
      ..credentials = creds
      ..token = KisToken(value: 'old', expiresAt: now.add(const Duration(minutes: 3)));
    await repo(kis, store, _RecordingFallback())
        .fetch(coinSymbols: const [], stockTickers: const ['TSLA'], currencyCodes: const []);
    expect(kis.tokenCalls, 1);
    expect(store.token!.value, 'tok1');
  });

  test('토큰 만료 응답이면 저장된 토큰을 지운다', () async {
    final kis = _FakeKis()
      ..prices['TSLA'] = {'rt_cd': '1', 'msg_cd': 'EGW00123', 'msg1': '기간이 만료된 token 입니다.'};
    final store = MemoryKisCredentialStore()
      ..credentials = creds
      ..token = KisToken(value: 'saved', expiresAt: now.add(const Duration(hours: 5)));
    final b = await repo(kis, store, _RecordingFallback())
        .fetch(coinSymbols: const [], stockTickers: const ['TSLA'], currencyCodes: const []);
    expect(b.stocks, isEmpty);
    expect(store.token, isNull);
  });

  test('연결 확인: 토큰 발급이 실패하면 예외를 던지고 키를 저장하지 않는다', () async {
    final kis = _FakeKis()
      ..tokenResponse = () => _json({'error_code': 'EGW00103', 'error_description': '유효하지 않은 AppKey입니다.'}, 403);
    final store = MemoryKisCredentialStore();
    await expectLater(
      repo(kis, store, _RecordingFallback()).connect(creds),
      throwsA(isA<KisApiException>().having((e) => e.message, 'message', contains('AppKey'))),
    );
    expect(store.credentials, isNull);
  });

  test('연결 확인: 성공하면 키와 토큰을 저장한다', () async {
    final kis = _FakeKis();
    final store = MemoryKisCredentialStore();
    await repo(kis, store, _RecordingFallback()).connect(creds);
    expect(store.credentials!.appKey, 'key');
    expect(store.token!.value, 'tok1');
    final body = jsonDecode(kis.requests.single.body) as Map<String, dynamic>;
    expect(body, {'grant_type': 'client_credentials', 'appkey': 'key', 'appsecret': 'secret'});
  });
}
