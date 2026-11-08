// 코인 시세와 원화 마켓 코인 목록을 업비트 공개 API(키 없음)에서 받아온다. 미국주식·환율·AI 이슈는 fallback에 맡긴다.
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/models.dart';
import 'quote_repository.dart';

/// 코인만 업비트 실시세로 채우는 [QuoteRepository].
///
/// 서버(Firebase)가 붙기 전까지 주식·환율·이슈는 [fallback]이 준 값을 그대로 쓴다.
/// 업비트 호출이 실패하면 예외를 던진다. [AppState.refresh]는 실패 시 이전 값을 유지한다.
class UpbitQuoteRepository implements QuoteRepository {
  UpbitQuoteRepository({required this.fallback, http.Client? client})
      : _client = client ?? http.Client();

  final QuoteRepository fallback;
  final http.Client _client;

  static const _timeout = Duration(seconds: 10);

  /// [fetchCoinList]로 받은 원화 마켓 심볼. 받기 전이면 null.
  Set<String>? _krwSymbols;

  /// 업비트 원화(KRW) 마켓의 전체 코인 목록. 이름은 한글 이름.
  Future<List<Coin>> fetchCoinList() async {
    final uri = Uri.https('api.upbit.com', '/v1/market/all', {'isDetails': 'false'});
    final res = await _client.get(uri).timeout(_timeout);
    if (res.statusCode != 200) {
      throw http.ClientException('Upbit ${res.statusCode}: ${res.body}', uri);
    }
    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
    final coins = [
      for (final item in list.cast<Map<String, dynamic>>())
        if ((item['market'] as String).startsWith('KRW-'))
          Coin(
            symbol: (item['market'] as String).substring(4),
            name: item['korean_name'] as String,
          ),
    ];
    _krwSymbols = {for (final c in coins) c.symbol};
    return coins;
  }

  @override
  Future<QuoteBundle> fetch({
    required List<String> coinSymbols,
    required List<String> stockTickers,
    required List<String> currencyCodes,
    List<String> krStockCodes = const [],
  }) async {
    final results = await Future.wait([
      _fetchCoins(coinSymbols),
      fallback.fetch(
        coinSymbols: const [],
        stockTickers: stockTickers,
        currencyCodes: currencyCodes,
        krStockCodes: krStockCodes,
      ),
    ]);
    final coins = results[0] as Map<String, CoinQuote>;
    final rest = results[1] as QuoteBundle;
    return QuoteBundle(
      coins: coins,
      stocks: rest.stocks,
      krStocks: rest.krStocks,
      fx: rest.fx,
      issue: rest.issue,
      fetchedAt: DateTime.now(),
    );
  }

  Future<Map<String, CoinQuote>> _fetchCoins(List<String> requested) async {
    // 업비트 ticker는 없는 마켓이 하나라도 섞이면 요청 전체가 404가 된다.
    // 상장폐지된 코인이 관심목록에 남아 있어도 나머지 시세는 받도록 미리 뺀다.
    final known = _krwSymbols;
    final symbols = known == null ? requested : requested.where(known.contains).toList();
    if (symbols.isEmpty) return const {};
    final uri = Uri.https('api.upbit.com', '/v1/ticker', {
      'markets': symbols.map((s) => 'KRW-$s').join(','),
    });
    final res = await _client.get(uri).timeout(_timeout);
    if (res.statusCode != 200) {
      throw http.ClientException('Upbit ${res.statusCode}: ${res.body}', uri);
    }
    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
    return {
      for (final item in list.cast<Map<String, dynamic>>())
        (item['market'] as String).replaceFirst('KRW-', ''): CoinQuote(
          priceKrw: (item['trade_price'] as num).toDouble(),
          changePct: (item['signed_change_rate'] as num).toDouble() * 100,
        ),
    };
  }
}
