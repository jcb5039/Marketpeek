import 'dart:convert';

import 'package:flutter/services.dart' show AssetBundle;

import '../models/models.dart';

/// 검색·선택 가능한 종목/통화 목록.
/// 코인은 앱 시작 시 업비트 원화 마켓 목록으로 바뀐다([setCoins]).
/// 국내·미국주식은 앱에 넣어 둔 전체 종목 목록(assets/stocks, [loadStockAssets])을 쓴다.
/// 목록은 tool/build_stock_catalog.py로 한국투자증권 종목 마스터에서 만든다.
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

  /// 전체 목록을 읽기 전(테스트 등)에 쓰는 기본 미국주식.
  static const _defaultStocks = <UsStock>[
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
    UsStock(ticker: 'SPY', name: 'SPDR S&P 500', excd: 'AMS'), // NYSE Arca
  ];

  static List<UsStock> stocks = _defaultStocks;
  static Map<String, UsStock> _stockByTicker = {for (final s in _defaultStocks) s.ticker: s};

  static const popularStockTickers = ['TSLA', 'NVDA', 'AAPL', 'MSFT'];

  static const _defaultKrStocks = <KrStock>[
    KrStock(code: '005930', name: '삼성전자'),
    KrStock(code: '000660', name: 'SK하이닉스'),
    KrStock(code: '005380', name: '현대차'),
    KrStock(code: '035420', name: 'NAVER'),
    KrStock(code: '035720', name: '카카오'),
  ];

  static List<KrStock> krStocks = _defaultKrStocks;
  static Map<String, KrStock> _krByCode = {for (final s in _defaultKrStocks) s.code: s};

  static const popularKrStockCodes = ['005930', '000660', '005380', '035420', '035720'];

  /// assets/stocks/kr.json·us.json에서 전체 종목을 읽는다. 실패하면 기본 목록 그대로.
  static Future<void> loadStockAssets(AssetBundle bundle) async {
    try {
      final kr = jsonDecode(await bundle.loadString('assets/stocks/kr.json')) as List<dynamic>;
      setKrStocks([
        for (final r in kr.cast<List<dynamic>>())
          KrStock(code: r[0] as String, name: r[1] as String, market: r[2] as String),
      ]);
      final us = jsonDecode(await bundle.loadString('assets/stocks/us.json')) as List<dynamic>;
      setStocks([
        for (final r in us.cast<List<dynamic>>())
          UsStock(
            ticker: r[0] as String,
            name: (r[1] as String).isEmpty ? r[2] as String : r[1] as String,
            engName: r[2] as String,
            excd: r[3] as String,
          ),
      ]);
    } catch (_) {
      // 목록 파일이 없거나 깨졌으면 기본 목록으로 계속 쓴다.
    }
  }

  static void setStocks(List<UsStock> list) {
    if (list.isEmpty) return;
    stocks = List.unmodifiable(list);
    _stockByTicker = {for (final s in list) s.ticker: s};
  }

  static void setKrStocks(List<KrStock> list) {
    if (list.isEmpty) return;
    krStocks = List.unmodifiable(list);
    _krByCode = {for (final s in list) s.code: s};
  }

  /// 테스트용: 주식 목록을 기본으로 되돌린다.
  static void resetStocks() {
    stocks = _defaultStocks;
    _stockByTicker = {for (final s in _defaultStocks) s.ticker: s};
    krStocks = _defaultKrStocks;
    _krByCode = {for (final s in _defaultKrStocks) s.code: s};
  }

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
  /// 목록에 없는 티커(상장폐지 등)면 티커를 이름으로 쓴다.
  static UsStock stock(String ticker) =>
      _stockByTicker[ticker] ?? UsStock(ticker: ticker, name: ticker);
  static KrStock krStock(String code) => _krByCode[code] ?? KrStock(code: code, name: code);
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

  /// 검색 결과는 이만큼만 보여준다 (전체 목록이 1만 개가 넘어서).
  static const searchLimit = 50;

  /// 미국주식: 티커 · 한글명 · 영문명. 티커 일치 → 티커/이름 앞부분 → 포함 순.
  static List<UsStock> searchStocks(String q) {
    final query = q.trim().toLowerCase();
    if (query.isEmpty) {
      return popularStockTickers.map(stock).toList();
    }
    int? rank(UsStock s) {
      final t = s.ticker.toLowerCase();
      final eng = s.engName.toLowerCase();
      if (t == query || s.name == query) return 0;
      if (t.startsWith(query)) return 1;
      if (s.name.startsWith(query) || eng.startsWith(query)) return 2;
      if (s.name.contains(query) || eng.contains(query)) return 3;
      return null;
    }

    return _ranked(stocks, rank, (s) => s.ticker);
  }

  /// 국내주식: 종목코드 · 이름. 일치 → 앞부분 → 포함 순.
  static List<KrStock> searchKrStocks(String q) {
    final query = q.trim().toLowerCase();
    if (query.isEmpty) {
      return popularKrStockCodes.map(krStock).toList();
    }
    int? rank(KrStock s) {
      final name = s.name.toLowerCase();
      if (s.code == query || name == query) return 0;
      if (s.code.startsWith(query) || name.startsWith(query)) return 1;
      if (name.contains(query)) return 2;
      return null;
    }

    return _ranked(krStocks, rank, (s) => s.name);
  }

  static List<T> _ranked<T>(List<T> all, int? Function(T) rank, String Function(T) key) {
    final hits = <(int, T)>[];
    for (final s in all) {
      final r = rank(s);
      if (r != null) hits.add((r, s));
    }
    hits.sort((a, b) {
      final r = a.$1.compareTo(b.$1);
      return r != 0 ? r : key(a.$2).compareTo(key(b.$2));
    });
    return [for (final h in hits.take(searchLimit)) h.$2];
  }
}
