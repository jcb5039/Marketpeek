import '../models/models.dart';

/// 검색·선택 가능한 종목/통화 목록.
/// 실제 서비스에서는 서버(업비트 마켓 목록, Finnhub 심볼 검색)로 대체한다.
class Catalog {
  static const coins = <Coin>[
    Coin(symbol: 'BTC', name: '비트코인'),
    Coin(symbol: 'ETH', name: '이더리움'),
    Coin(symbol: 'XRP', name: '리플'),
    Coin(symbol: 'SOL', name: '솔라나'),
    Coin(symbol: 'DOGE', name: '도지코인'),
    Coin(symbol: 'ADA', name: '에이다'),
    Coin(symbol: 'USDT', name: '테더'),
    Coin(symbol: 'AVAX', name: '아발란체'),
  ];

  /// 검색어 없을 때 보여줄 인기 코인.
  static const popularCoinSymbols = ['BTC', 'ETH', 'XRP', 'SOL'];

  static const stocks = <UsStock>[
    UsStock(ticker: 'AAPL', name: '애플'),
    UsStock(ticker: 'AMZN', name: '아마존'),
    UsStock(ticker: 'AMD', name: 'AMD'),
    UsStock(ticker: 'ABNB', name: '에어비앤비'),
    UsStock(ticker: 'TSLA', name: '테슬라'),
    UsStock(ticker: 'NVDA', name: '엔비디아'),
    UsStock(ticker: 'MSFT', name: '마이크로소프트'),
    UsStock(ticker: 'GOOGL', name: '알파벳'),
    UsStock(ticker: 'META', name: '메타'),
    UsStock(ticker: 'QQQ', name: '인베스코 QQQ'),
    UsStock(ticker: 'SPY', name: 'SPDR S&P 500'),
  ];

  static const popularStockTickers = ['TSLA', 'NVDA', 'AAPL', 'MSFT'];

  static const currencies = <Currency>[
    Currency(code: 'USD', name: '미국 달러'),
    Currency(code: 'JPY', name: '일본 엔', unit: 100),
    Currency(code: 'EUR', name: '유로'),
    Currency(code: 'THB', name: '태국 바트'),
    Currency(code: 'CNY', name: '중국 위안'),
  ];

  static Coin coin(String symbol) =>
      coins.firstWhere((c) => c.symbol == symbol);
  static UsStock stock(String ticker) =>
      stocks.firstWhere((s) => s.ticker == ticker);
  static Currency currency(String code) =>
      currencies.firstWhere((c) => c.code == code);

  static List<Coin> searchCoins(String q) {
    final query = q.trim().toLowerCase();
    if (query.isEmpty) {
      return popularCoinSymbols.map(coin).toList();
    }
    return coins
        .where((c) =>
            c.symbol.toLowerCase().contains(query) || c.name.contains(query))
        .toList();
  }

  static List<UsStock> searchStocks(String q) {
    final query = q.trim().toLowerCase();
    if (query.isEmpty) {
      return popularStockTickers.map(stock).toList();
    }
    // 기획서: 미국주식은 티커 검색. 티커 앞부분 일치를 먼저 보여준다.
    final hits = stocks
        .where((s) => s.ticker.toLowerCase().startsWith(query))
        .toList()
      ..sort((a, b) => a.ticker.compareTo(b.ticker));
    return hits;
  }
}
