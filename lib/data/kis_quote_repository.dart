// 한국투자증권 KIS Developers Open API에서 주식 시세를 받는다.
// 키(App Key·Secret)는 사용자가 앱 설정에서 넣고 기기 Keychain에만 저장한다. 서버로 보내지 않는다.
// KIS 실전 도메인은 포트 9443을 써서 Cloudflare Workers에서는 부를 수 없으므로 앱이 직접 호출한다.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../models/models.dart';
import 'catalog.dart';
import 'quote_repository.dart';

class KisCredentials {
  const KisCredentials({required this.appKey, required this.appSecret});

  final String appKey;
  final String appSecret;
}

/// 접근 토큰. 약 하루 유효하고 발급은 1분에 1번으로 제한되므로 저장해 두고 다시 쓴다.
class KisToken {
  const KisToken({required this.value, required this.expiresAt});

  final String value;
  final DateTime expiresAt;
}

/// 키·토큰 저장소. 실제 앱은 [SecureKisCredentialStore](Keychain), 테스트는 [MemoryKisCredentialStore].
abstract class KisCredentialStore {
  Future<KisCredentials?> readCredentials();
  Future<void> writeCredentials(KisCredentials credentials);
  Future<KisToken?> readToken();
  Future<void> writeToken(KisToken? token);
  Future<void> clear();
}

class SecureKisCredentialStore implements KisCredentialStore {
  SecureKisCredentialStore([FlutterSecureStorage? storage])
      : _s = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _s;

  static const _appKey = 'kis.appKey';
  static const _appSecret = 'kis.appSecret';
  static const _token = 'kis.token';
  static const _tokenExpiresAt = 'kis.tokenExpiresAt';

  @override
  Future<KisCredentials?> readCredentials() async {
    final key = await _s.read(key: _appKey);
    final secret = await _s.read(key: _appSecret);
    if (key == null || secret == null) return null;
    return KisCredentials(appKey: key, appSecret: secret);
  }

  @override
  Future<void> writeCredentials(KisCredentials c) async {
    await _s.write(key: _appKey, value: c.appKey);
    await _s.write(key: _appSecret, value: c.appSecret);
  }

  @override
  Future<KisToken?> readToken() async {
    final value = await _s.read(key: _token);
    final exp = DateTime.tryParse(await _s.read(key: _tokenExpiresAt) ?? '');
    if (value == null || exp == null) return null;
    return KisToken(value: value, expiresAt: exp);
  }

  @override
  Future<void> writeToken(KisToken? t) async {
    if (t == null) {
      await _s.delete(key: _token);
      await _s.delete(key: _tokenExpiresAt);
    } else {
      await _s.write(key: _token, value: t.value);
      await _s.write(key: _tokenExpiresAt, value: t.expiresAt.toUtc().toIso8601String());
    }
  }

  @override
  Future<void> clear() async {
    for (final k in [_appKey, _appSecret, _token, _tokenExpiresAt]) {
      await _s.delete(key: k);
    }
  }
}

class MemoryKisCredentialStore implements KisCredentialStore {
  KisCredentials? credentials;
  KisToken? token;

  @override
  Future<KisCredentials?> readCredentials() async => credentials;
  @override
  Future<void> writeCredentials(KisCredentials c) async => credentials = c;
  @override
  Future<KisToken?> readToken() async => token;
  @override
  Future<void> writeToken(KisToken? t) async => token = t;
  @override
  Future<void> clear() async {
    credentials = null;
    token = null;
  }
}

class KisApiException implements Exception {
  KisApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 주식 시세(국내·미국)만 KIS로 채우는 [QuoteRepository]. 키가 없으면 전부 [fallback]에 맡긴다.
///
/// 미국: 해외주식 현재체결가(HHDFS00000300) `last`·`rate`·`base`.
/// 국내: 주식현재가 시세(FHKST01010100) `stck_prpr`·`prdy_ctrt`.
/// 응답 필드는 KIS 문서 기준이며 실제 키로 확인한다.
class KisQuoteRepository implements QuoteRepository {
  KisQuoteRepository({
    required this.fallback,
    required this.store,
    http.Client? client,
    this.baseUrl = defaultBaseUrl,
    DateTime Function()? clock,
    this.requestGap = const Duration(milliseconds: 80),
  })  : _client = client ?? http.Client(),
        _now = clock ?? DateTime.now;

  static const defaultBaseUrl = 'https://openapi.koreainvestment.com:9443';

  final QuoteRepository fallback;
  final KisCredentialStore store;
  final String baseUrl;

  /// 종목 사이 간격. 초당 호출 한도(EGW00201) 초과를 피한다.
  final Duration requestGap;
  final http.Client _client;
  final DateTime Function() _now;

  static const _timeout = Duration(seconds: 10);

  /// 만료가 이만큼 남았으면 새로 받는다.
  static const _tokenMargin = Duration(minutes: 10);

  Future<bool> get isConnected async => await store.readCredentials() != null;

  /// 설정 화면의 "저장하고 연결 확인". 토큰 발급에 성공해야 저장한다. 실패하면 [KisApiException].
  Future<void> connect(KisCredentials c) async {
    final token = await _issueToken(c);
    await store.writeCredentials(c);
    await store.writeToken(token);
  }

  Future<void> disconnect() => store.clear();

  @override
  Future<QuoteBundle> fetch({
    required List<String> coinSymbols,
    required List<String> stockTickers,
    required List<String> currencyCodes,
    List<String> krStockCodes = const [],
  }) async {
    final creds = await store.readCredentials();
    if (creds == null || (stockTickers.isEmpty && krStockCodes.isEmpty)) {
      return fallback.fetch(
        coinSymbols: coinSymbols,
        stockTickers: stockTickers,
        currencyCodes: currencyCodes,
        krStockCodes: krStockCodes,
      );
    }
    final results = await Future.wait([
      _fetchStocks(creds, stockTickers, krStockCodes),
      fallback.fetch(
        coinSymbols: coinSymbols,
        stockTickers: const [],
        currencyCodes: currencyCodes,
      ),
    ]);
    final (stocks, krStocks) =
        results[0] as (Map<String, StockQuote>, Map<String, KrStockQuote>);
    final rest = results[1] as QuoteBundle;
    return QuoteBundle(
      coins: rest.coins,
      stocks: stocks,
      krStocks: krStocks,
      fx: rest.fx,
      issue: rest.issue,
      fetchedAt: _now(),
    );
  }

  /// 종목 하나가 실패해도 나머지는 받는다. 토큰을 못 받으면 빈 결과(앱에는 "—").
  /// 초당 호출 한도 때문에 한 종목씩 차례로 부른다.
  Future<(Map<String, StockQuote>, Map<String, KrStockQuote>)> _fetchStocks(
      KisCredentials creds, List<String> tickers, List<String> krCodes) async {
    final us = <String, StockQuote>{};
    final kr = <String, KrStockQuote>{};
    final KisToken token;
    try {
      token = await _validToken(creds);
    } catch (e) {
      debugPrint('KIS token failed: $e');
      return (us, kr);
    }
    final jobs = <(String, Future<void> Function())>[
      for (final c in krCodes)
        (c, () async {
          final q = await _domesticPrice(creds, token, c);
          if (q != null) kr[c] = q;
        }),
      for (final t in tickers)
        (t, () async {
          final q = await _overseasPrice(creds, token, _excd(t), t);
          if (q != null) us[t] = q;
        }),
    ];
    for (final (i, (id, job)) in jobs.indexed) {
      if (i > 0 && requestGap > Duration.zero) await Future<void>.delayed(requestGap);
      try {
        await job();
      } on _TokenExpired {
        await store.writeToken(null); // 다음 갱신 때 새로 받는다.
        break;
      } catch (e) {
        debugPrint('KIS $id failed: $e');
      }
    }
    return (us, kr);
  }

  Future<KisToken> _validToken(KisCredentials creds) async {
    final saved = await store.readToken();
    if (saved != null && saved.expiresAt.isAfter(_now().add(_tokenMargin))) return saved;
    final fresh = await _issueToken(creds);
    await store.writeToken(fresh);
    return fresh;
  }

  /// POST /oauth2/tokenP
  Future<KisToken> _issueToken(KisCredentials c) async {
    final uri = Uri.parse('$baseUrl/oauth2/tokenP');
    final res = await _client
        .post(
          uri,
          headers: {'content-type': 'application/json; charset=utf-8'},
          body: jsonEncode({
            'grant_type': 'client_credentials',
            'appkey': c.appKey,
            'appsecret': c.appSecret,
          }),
        )
        .timeout(_timeout);
    final body = _decode(res);
    final value = body['access_token'] as String?;
    if (res.statusCode != 200 || value == null || value.isEmpty) {
      throw KisApiException(
          (body['error_description'] ?? body['msg1'] ?? 'HTTP ${res.statusCode}').toString());
    }
    final seconds = (body['expires_in'] as num?)?.toInt() ?? 86400;
    return KisToken(value: value, expiresAt: _now().add(Duration(seconds: seconds)));
  }

  /// GET 해외주식 현재체결가 (tr_id HHDFS00000300). 가격이 비어 있으면 null.
  Future<StockQuote?> _overseasPrice(
      KisCredentials c, KisToken token, String excd, String symbol) async {
    final o = await _get(c, token, '/uapi/overseas-price/v1/quotations/price', 'HHDFS00000300',
        {'AUTH': '', 'EXCD': excd, 'SYMB': symbol});
    final last = _num(o['last']);
    if (last == null || last == 0) return null;
    final base = _num(o['base']);
    final rate = _num(o['rate']) ??
        (base == null || base == 0 ? 0.0 : (last - base) / base * 100);
    return StockQuote(priceUsd: last, changePct: rate);
  }

  /// GET 국내주식 현재가 시세 (tr_id FHKST01010100). 가격이 비어 있으면 null.
  Future<KrStockQuote?> _domesticPrice(KisCredentials c, KisToken token, String code) async {
    final o = await _get(c, token, '/uapi/domestic-stock/v1/quotations/inquire-price',
        'FHKST01010100', {'FID_COND_MRKT_DIV_CODE': 'J', 'FID_INPUT_ISCD': code});
    final price = _num(o['stck_prpr']);
    if (price == null || price == 0) return null;
    return KrStockQuote(priceKrw: price, changePct: _num(o['prdy_ctrt']) ?? 0);
  }

  /// 시세 조회 공통: 헤더를 붙여 GET하고 `output`을 돌려준다.
  Future<Map<String, dynamic>> _get(KisCredentials c, KisToken token, String path, String trId,
      Map<String, String> query) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    final res = await _client.get(uri, headers: {
      'content-type': 'application/json; charset=utf-8',
      'authorization': 'Bearer ${token.value}',
      'appkey': c.appKey,
      'appsecret': c.appSecret,
      'tr_id': trId,
      'custtype': 'P',
    }).timeout(_timeout);
    final body = _decode(res);
    final msgCd = body['msg_cd'] as String?;
    if (msgCd == 'EGW00123' || msgCd == 'EGW00121') throw _TokenExpired();
    if (res.statusCode != 200 || body['rt_cd'] != '0') {
      throw KisApiException('${body['msg_cd'] ?? res.statusCode} ${body['msg1'] ?? ''}');
    }
    return body['output'] as Map<String, dynamic>? ?? const {};
  }

  static String _excd(String ticker) => Catalog.stock(ticker).excd;

  static double? _num(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String && v.trim().isNotEmpty) return double.tryParse(v.trim().replaceAll('+', ''));
    return null;
  }

  static Map<String, dynamic> _decode(http.Response res) {
    try {
      final v = jsonDecode(utf8.decode(res.bodyBytes));
      return v is Map<String, dynamic> ? v : const {};
    } catch (_) {
      return const {};
    }
  }
}

class _TokenExpired implements Exception {}
