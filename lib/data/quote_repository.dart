import '../models/models.dart';

/// 시세 공급원. 기획서상 실제 구현은 Firebase 서버가 업비트·Finnhub·환율 API를
/// 수집·캐시한 값을 내려주는 구조이며 API 키는 앱에 넣지 않는다.
abstract class QuoteRepository {
  Future<QuoteBundle> fetch({
    required List<String> coinSymbols,
    required List<String> stockTickers,
    required List<String> currencyCodes,
  });
}

class QuoteBundle {
  const QuoteBundle({
    required this.coins,
    required this.stocks,
    required this.fx,
    required this.issue,
    required this.fetchedAt,
  });

  final Map<String, CoinQuote> coins;
  final Map<String, StockQuote> stocks;

  /// 통화 코드 → 환율. 미국주식 원화 환산용 USD는 선택 여부와 무관하게 항상 포함된다.
  final Map<String, FxQuote> fx;
  final MarketIssue? issue;
  final DateTime fetchedAt;
}

/// 서버 연결 전까지 쓰는 고정 예시 데이터 (기획서 6장의 예시 값).
/// 실제 시세가 아니다. AAPL처럼 값이 없는 종목은 위젯/앱에서 "—"로 표시된다.
class MockQuoteRepository implements QuoteRepository {
  static const _coins = {
    'BTC': CoinQuote(priceKrw: 100000000, changePct: 2.50),
    'ETH': CoinQuote(priceKrw: 5200000, changePct: 1.12),
    'XRP': CoinQuote(priceKrw: 3500, changePct: -1.20),
    'SOL': CoinQuote(priceKrw: 280000, changePct: 4.05),
    'DOGE': CoinQuote(priceKrw: 310, changePct: -0.64),
  };

  static const _stocks = {
    'TSLA': StockQuote(priceUsd: 450.00, changePct: 3.10),
    'NVDA': StockQuote(priceUsd: 182.40, changePct: 1.75),
    'MSFT': StockQuote(priceUsd: 512.30, changePct: -0.42),
    'AMZN': StockQuote(priceUsd: 231.10, changePct: 0.88),
  };

  static const _fx = {
    'USD': FxQuote(rateKrw: 1430.50, changePct: 0.40),
    'JPY': FxQuote(rateKrw: 950, changePct: -0.20),
    'EUR': FxQuote(rateKrw: 1560.20, changePct: 0.15),
    'THB': FxQuote(rateKrw: 42.10, changePct: -0.05),
    'CNY': FxQuote(rateKrw: 198.70, changePct: 0.08),
  };

  @override
  Future<QuoteBundle> fetch({
    required List<String> coinSymbols,
    required List<String> stockTickers,
    required List<String> currencyCodes,
  }) async {
    final now = DateTime.now();
    final issueTime = DateTime(now.year, now.month, now.day, 8);
    return QuoteBundle(
      coins: {
        for (final s in coinSymbols)
          if (_coins[s] != null) s: _coins[s]!,
      },
      stocks: {
        for (final t in stockTickers)
          if (_stocks[t] != null) t: _stocks[t]!,
      },
      fx: {
        for (final c in {...currencyCodes, 'USD'})
          if (_fx[c] != null) c: _fx[c]!,
      },
      issue: MarketIssue(
        text: 'FOMC 금리 동결, 나스닥·코인 동반 상승',
        shortText: 'FOMC 동결, 증시 상승',
        generatedAt: now.isBefore(issueTime)
            ? issueTime.subtract(const Duration(days: 1))
            : issueTime,
      ),
      fetchedAt: now,
    );
  }
}
