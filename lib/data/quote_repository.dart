import '../models/models.dart';

/// 시세 공급원. 코인=업비트, 주식=한국투자증권(사용자 키, 기기에서 직접), 환율·이슈=우리 서버.
/// 우리 API 키는 앱에 넣지 않는다 (사용자 본인 증권사 키만 기기 Keychain에 저장).
abstract class QuoteRepository {
  /// [stockTickers]는 미국주식, [krStockCodes]는 국내주식(6자리 코드).
  Future<QuoteBundle> fetch({
    required List<String> coinSymbols,
    required List<String> stockTickers,
    required List<String> currencyCodes,
    List<String> krStockCodes = const [],
  });
}

class QuoteBundle {
  const QuoteBundle({
    required this.coins,
    required this.stocks,
    required this.fx,
    required this.issue,
    required this.fetchedAt,
    this.krStocks = const {},
  });

  final Map<String, CoinQuote> coins;

  /// 미국주식 (티커 → 시세)
  final Map<String, StockQuote> stocks;

  /// 국내주식 (종목코드 → 시세)
  final Map<String, KrStockQuote> krStocks;

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

  static const _krStocks = {
    '005930': KrStockQuote(priceKrw: 98500, changePct: 1.24),
    '000660': KrStockQuote(priceKrw: 412000, changePct: -0.72),
    '035420': KrStockQuote(priceKrw: 231500, changePct: 0.43),
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
    List<String> krStockCodes = const [],
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
      krStocks: {
        for (final c in krStockCodes)
          if (_krStocks[c] != null) c: _krStocks[c]!,
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
