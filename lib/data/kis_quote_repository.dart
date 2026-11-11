// 한국투자증권 KIS Developers Open API에서 주식 시세를 받는다.
// 키(App Key·Secret)는 사용자가 앱 설정에서 넣고 기기 Keychain에만 저장한다. 서버로 보내지 않는다.
// KIS 실전 도메인은 포트 9443을 써서 Cloudflare Workers에서는 부를 수 없으므로 앱이 직접 호출한다.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../models/models.dart';
import '../widget_bridge/widget_sync.dart';
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
  SecureKisCredentialStore([FlutterSecureStorage? storage, FlutterSecureStorage? legacy])
      : _shared = storage ?? const FlutterSecureStorage(iOptions: sharedOptions),
        _legacy = legacy ?? const FlutterSecureStorage();

  /// 위젯 확장(ios/MarketPeekWidget/LiveQuotes.swift)도 같은 키·토큰을 읽도록 App Group을
  /// Keychain 접근 그룹으로 쓴다. 잠금 상태에서 위젯을 다시 불러올 때도 읽히게 "처음 잠금 해제 후"로 둔다.
  static const sharedOptions = IOSOptions(
    groupId: WidgetSync.appGroupId,
    accessibility: KeychainAccessibility.first_unlock,
  );

  final FlutterSecureStorage _shared;

  /// 공유 그룹을 쓰기 전(앱 전용 그룹)에 저장된 항목. 처음 읽을 때 공유 그룹으로 옮긴다.
  final FlutterSecureStorage _legacy;
  Future<void>? _migration;

  /// 공유 그룹에 못 쓰는 환경(서명·entitlement 문제)이면 예전처럼 앱 전용 그룹을 쓴다.
  /// 이 경우 위젯은 주식을 직접 받지 못하고 앱이 써둔 값을 보여준다.
  bool _sharedUsable = true;
  FlutterSecureStorage get _s => _sharedUsable ? _shared : _legacy;

  static const _appKey = 'kis.appKey';
  static const _appSecret = 'kis.appSecret';
  static const _token = 'kis.token';
  static const _tokenExpiresAt = 'kis.tokenExpiresAt';
  static const _keys = [_appKey, _appSecret, _token, _tokenExpiresAt];
  static const _probe = 'kis.sharedProbe';

  Future<void> _ready() => _migration ??= _migrate();

  /// 앱 전용 그룹의 키를 공유 그룹으로 옮긴다.
  /// 접근 그룹 없이 지우면 모든 그룹의 같은 항목이 지워지므로, 읽기 → 지우기 → 공유 그룹에 쓰기 순서로 한다.
  Future<void> _migrate() async {
    try {
      await _shared.write(key: _probe, value: '1');
      await _shared.delete(key: _probe);
    } catch (e) {
      debugPrint('KIS shared keychain unavailable, using app-only keychain: $e');
      _sharedUsable = false;
      return;
    }
    try {
      if (await _shared.read(key: _appKey) != null) return;
      final old = {for (final k in _keys) k: await _legacy.read(key: k)};
      if (old[_appKey] == null) return;
      for (final k in _keys) {
        await _legacy.delete(key: k);
      }
      for (final e in old.entries) {
        if (e.value != null) await _shared.write(key: e.key, value: e.value);
      }
    } catch (e) {
      debugPrint('KIS keychain migration failed: $e');
    }
  }

  @override
  Future<KisCredentials?> readCredentials() async {
    await _ready();
    final key = await _s.read(key: _appKey);
    final secret = await _s.read(key: _appSecret);
    if (key == null || secret == null) return null;
    return KisCredentials(appKey: key, appSecret: secret);
  }

  @override
  Future<void> writeCredentials(KisCredentials c) async {
    await _ready();
    await _s.write(key: _appKey, value: c.appKey);
    await _s.write(key: _appSecret, value: c.appSecret);
  }

  @override
  Future<KisToken?> readToken() async {
    await _ready();
    final value = await _s.read(key: _token);
    final exp = DateTime.tryParse(await _s.read(key: _tokenExpiresAt) ?? '');
    if (value == null || exp == null) return null;
    return KisToken(value: value, expiresAt: exp);
  }

  @override
  Future<void> writeToken(KisToken? t) async {
    await _ready();
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
    await _ready();
    for (final k in _keys) {
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
    this.requestGap = const Duration(milliseconds: 350),
    this.rateLimitRetryDelay = const Duration(milliseconds: 1100),
  })  : _client = client ?? http.Client(),
        _now = clock ?? DateTime.now;

  static const defaultBaseUrl = 'https://openapi.koreainvestment.com:9443';

  final QuoteRepository fallback;
  final KisCredentialStore store;
  final String baseUrl;

  /// 호출 사이 간격. 초당 호출 한도(EGW00201) 초과를 피한다.
  /// 신규 신청 직후 등 한도가 낮을 때도 버티도록 초당 3건 안쪽으로 둔다.
  final Duration requestGap;

  /// 그래도 한도에 걸리면 이만큼 기다렸다 한 번 더 부른다.
  final Duration rateLimitRetryDelay;

  /// 갱신이 겹쳐도(앱 시작·당겨서 새로고침·종목 추가) KIS 호출은 한 번에 하나씩.
  /// 처음 호출할 때 만든다 (생성 시점에 만들면 그 시점의 Zone에 묶여 테스트에서 멈춘다).
  Future<void>? _queue;
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
      _serial(() => _fetchStocks(creds, stockTickers, krStockCodes)),
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
    var freshToken = false;
    try {
      final saved = await store.readToken();
      token = await _validToken(creds);
      freshToken = saved?.value != token.value;
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
      if ((i > 0 || freshToken) && requestGap > Duration.zero) {
        await Future<void>.delayed(requestGap);
      }
      try {
        try {
          await job();
        } on _RateLimited {
          await Future<void>.delayed(rateLimitRetryDelay);
          await job();
        }
      } on _TokenExpired {
        await store.writeToken(null); // 다음 갱신 때 새로 받는다.
        break;
      } catch (e) {
        debugPrint('KIS $id failed: $e');
      }
    }
    return (us, kr);
  }

  /// [job]을 앞선 KIS 호출이 끝난 뒤에 실행한다.
  Future<T> _serial<T>(Future<T> Function() job) {
    final prev = _queue;
    final result = prev == null ? job() : prev.then((_) => job());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
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
    if (msgCd == 'EGW00201') throw _RateLimited();
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

class _RateLimited implements Exception {}
