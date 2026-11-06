import '../models/models.dart';

/// 검색·선택 가능한 종목/통화 목록.
/// 코인은 앱 시작 시 업비트 원화 마켓 목록으로 바뀐다([setCoins]). 미국주식은 아직 고정 목록.
class Catalog {
  /// 업비트 목록을 받기 전(첫 실행 + 오프라인)에 쓰는 기본 코인.
  static const _defaultCoins = <Coin>[
    Coin(symbol: 'BTC', name: '비트코인'),
    Coin(symbol: 'ETH', name: '이더리움'),
    Coin(symbol: 'XRP', name: '리플'),
    Coin(symbol: 'SOL', name: '솔라나'),
    Coin(symbol: 'DOGE', name: '도지코인'),
    Coin(symbol: 'ADA', name: '에이다'),
    Coin(symbol: 'USDT', name: '테더'),
    Coin(symbol: 'AVAX', name: '아발란체'),
  ];

  static List<Coin> coins = _defaultCoins;

  static void setCoins(List<Coin> list) {
    if (list.isNotEmpty) coins = List.unmodifiable(list);
  }

  /// 테스트용: 기본 목록으로 되돌린다.
  static void resetCoins() => coins = _defaultCoins;

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

  /// 목록에 없는 심볼(상장폐지 등)이면 심볼을 이름으로 쓴다.
  static Coin coin(String symbol) => coins.firstWhere((c) => c.symbol == symbol,
      orElse: () => Coin(symbol: symbol, name: symbol));
  static UsStock stock(String ticker) =>
      stocks.firstWhere((s) => s.ticker == ticker);
  static Currency currency(String code) =>
      currencies.firstWhere((c) => c.code == code);

  static List<Coin> searchCoins(String q) {
    final query = q.trim().toLowerCase();
    if (query.isEmpty) {
      return popularCoinSymbols.map(coin).toList();
    }
    // 심볼 완전 일치 → 심볼·이름 앞부분 일치 → 그 외 포함 순.
    int rank(Coin c) {
      final sym = c.symbol.toLowerCase();
      if (sym == query || c.name == query) return 0;
      if (sym.startsWith(query) || c.name.startsWith(query)) return 1;
      return 2;
    }

    final hits = coins
        .where((c) =>
            c.symbol.toLowerCase().contains(query) || c.name.contains(query))
        .toList();
    final ranks = {for (final c in hits) c.symbol: rank(c)};
    hits.sort((a, b) {
      final r = ranks[a.symbol]!.compareTo(ranks[b.symbol]!);
      return r != 0 ? r : a.symbol.compareTo(b.symbol);
    });
    return hits;
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
