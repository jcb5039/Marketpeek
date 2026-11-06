// MarketPeek 서버(Cloudflare Worker, server/)에서 미국주식·환율·AI 이슈를 받아온다. 코인은 다루지 않는다.
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/models.dart';
import 'quote_repository.dart';

/// `GET {baseUrl}/quotes?stocks=TSLA,NVDA&fx=USD,JPY` 응답을 [QuoteBundle]로 바꾼다.
///
/// 서버는 캐시된 값만 내려주며 API 키는 서버에만 있다. 코인은 [UpbitQuoteRepository]가 채운다.
class ServerQuoteRepository implements QuoteRepository {
  ServerQuoteRepository({required this.baseUrl, http.Client? client})
      : _client = client ?? http.Client();

  /// 예: https://marketpeek-api.<계정>.workers.dev
  final String baseUrl;
  final http.Client _client;

  static const _timeout = Duration(seconds: 10);

  @override
  Future<QuoteBundle> fetch({
    required List<String> coinSymbols,
    required List<String> stockTickers,
    required List<String> currencyCodes,
  }) async {
    final fxCodes = {...currencyCodes, 'USD'}; // 미국주식 원화 환산용 USD는 항상 받는다.
    final uri = Uri.parse(baseUrl).replace(
      path: '/quotes',
      queryParameters: {
        'stocks': stockTickers.join(','),
        'fx': fxCodes.join(','),
      },
    );
    final res = await _client.get(uri).timeout(_timeout);
    if (res.statusCode != 200) {
      throw http.ClientException('Server ${res.statusCode}: ${res.body}', uri);
    }
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final stocks = (body['stocks'] as Map<String, dynamic>? ?? {});
    final fx = (body['fx'] as Map<String, dynamic>? ?? {});
    final issue = body['issue'] as Map<String, dynamic>?;

    return QuoteBundle(
      coins: const {},
      stocks: {
        for (final e in stocks.entries)
          e.key: StockQuote(
            priceUsd: _num(e.value, 'priceUsd'),
            changePct: _num(e.value, 'changePct'),
          ),
      },
      fx: {
        for (final e in fx.entries)
          e.key: FxQuote(
            rateKrw: _num(e.value, 'rateKrw'),
            changePct: _num(e.value, 'changePct'),
          ),
      },
      issue: issue == null
          ? null
          : MarketIssue(
              text: issue['text'] as String,
              shortText: issue['shortText'] as String,
              generatedAt: DateTime.parse(issue['generatedAt'] as String),
            ),
      fetchedAt: DateTime.now(),
    );
  }

  static double _num(dynamic obj, String key) =>
      ((obj as Map<String, dynamic>)[key] as num).toDouble();
}
