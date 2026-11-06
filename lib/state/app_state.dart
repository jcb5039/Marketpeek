import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/catalog.dart';
import '../data/quote_repository.dart';
import '../models/models.dart';
import '../widget_bridge/widget_sync.dart';

/// 앱 설정과 시세 상태. 변경될 때마다 저장하고 위젯 스냅샷을 다시 쓴다.
///
/// 앱의 역할은 "위젯에 무엇을 어떻게 보여줄지" 정하는 것이므로, 모든 변경은
/// 결국 [WidgetSync.push]로 이어진다.
class AppState extends ChangeNotifier {
  AppState({
    required QuoteRepository repository,
    WidgetSync? widgetSync,
    this.coinListLoader,
  })  : _repo = repository,
        _widgetSync = widgetSync ?? WidgetSync();

  final QuoteRepository _repo;

  /// 검색용 전체 코인 목록을 받아오는 함수 (업비트 원화 마켓). 없으면 기본 목록만 쓴다.
  final Future<List<Coin>> Function()? coinListLoader;
  final WidgetSync _widgetSync;
  SharedPreferences? _prefs;

  // 관심 목록 — 코인과 미국주식은 완전히 분리된 목록이다.
  List<String> coinSymbols = [];
  List<String> stockTickers = [];

  /// 환율 위젯에 표시할 통화. 고르지 않았으면 null.
  String? fxCode;

  // 표시 설정
  int coinWidgetCount = 2;
  int stockWidgetCount = 1;
  bool showStockKrw = true;
  bool showMarketStatus = true;
  bool showUpdatedAt = true;
  ChangeColorScheme colorScheme = ChangeColorScheme.korean;

  QuoteBundle? quotes;
  bool loading = false;

  /// 잠금화면 직사각형 위젯에 넣을 수 있는 최대 종목 수.
  /// 3개면 위젯이 공간에 따라 제목·갱신 시각 줄을 생략할 수 있다.
  static const maxWidgetRows = 3;

  /// 위젯 스냅샷에 담는 코인·미국주식 최대 개수(홈 목록 앞에서부터).
  /// 위젯마다 "위젯 편집"에서 몇 번째부터 보일지 고른다 — 사각형 2개면 1~3, 4~6번째.
  static const maxWidgetItems = 6;

  bool get isEmpty =>
      coinSymbols.isEmpty && stockTickers.isEmpty && fxCode == null;

  double? get usdKrw => quotes?.fx['USD']?.rateKrw;

  Future<void> load() async {
    final p = _prefs = await SharedPreferences.getInstance();
    coinSymbols = p.getStringList('coins') ?? [];
    stockTickers = p.getStringList('stocks') ?? [];
    fxCode = p.getString('fx');
    coinWidgetCount = p.getInt('coinWidgetCount') ?? 2;
    stockWidgetCount = p.getInt('stockWidgetCount') ?? 1;
    showStockKrw = p.getBool('showStockKrw') ?? true;
    showMarketStatus = p.getBool('showMarketStatus') ?? true;
    showUpdatedAt = p.getBool('showUpdatedAt') ?? true;
    colorScheme = ChangeColorScheme.values.byName(
        p.getString('colorScheme') ?? ChangeColorScheme.korean.name);
    _loadCachedCoinList(p);
    notifyListeners();
    // 목록을 먼저 받아야 업비트 시세 요청에서 상장폐지 코인을 걸러낼 수 있다.
    await _refreshCoinList(p);
    await refresh();
  }

  void _loadCachedCoinList(SharedPreferences p) {
    final raw = p.getString('coinCatalog');
    if (raw == null) return;
    try {
      final list = (jsonDecode(raw) as List<dynamic>).cast<Map<String, dynamic>>();
      Catalog.setCoins([
        for (final m in list) Coin(symbol: m['s'] as String, name: m['n'] as String),
      ]);
    } catch (e) {
      debugPrint('Cached coin list broken: $e');
    }
  }

  Future<void> _refreshCoinList(SharedPreferences p) async {
    final loader = coinListLoader;
    if (loader == null) return;
    try {
      final coins = await loader();
      if (coins.isEmpty) return;
      Catalog.setCoins(coins);
      await p.setString('coinCatalog',
          jsonEncode([for (final c in coins) {'s': c.symbol, 'n': c.name}]));
      notifyListeners();
    } catch (e) {
      // 목록을 못 받아도 캐시나 기본 목록으로 계속 쓴다.
      debugPrint('Coin list fetch failed: $e');
    }
  }

  Future<void> refresh() async {
    loading = true;
    notifyListeners();
    try {
      quotes = await _repo.fetch(
        coinSymbols: coinSymbols,
        stockTickers: stockTickers,
        // 환율 선택 화면에서 비교할 수 있게 지원 통화는 모두 받아둔다.
        currencyCodes: [for (final c in Catalog.currencies) c.code],
      );
    } finally {
      loading = false;
      notifyListeners();
    }
    await _pushWidgets();
  }

  // ── 코인 목록 ───────────────────────────────────────────
  Future<void> addCoin(String symbol) async {
    if (coinSymbols.contains(symbol)) return;
    coinSymbols = [...coinSymbols, symbol];
    await _saveAndRefresh();
  }

  Future<void> removeCoin(String symbol) async {
    coinSymbols = coinSymbols.where((s) => s != symbol).toList();
    await _saveAndRefresh(fetch: false);
  }

  Future<void> reorderCoins(int oldIndex, int newIndex) async {
    coinSymbols = _reorder(coinSymbols, oldIndex, newIndex);
    await _saveAndRefresh(fetch: false);
  }

  // ── 미국주식 목록 ───────────────────────────────────────
  Future<void> addStock(String ticker) async {
    if (stockTickers.contains(ticker)) return;
    stockTickers = [...stockTickers, ticker];
    await _saveAndRefresh();
  }

  Future<void> removeStock(String ticker) async {
    stockTickers = stockTickers.where((t) => t != ticker).toList();
    await _saveAndRefresh(fetch: false);
  }

  Future<void> reorderStocks(int oldIndex, int newIndex) async {
    stockTickers = _reorder(stockTickers, oldIndex, newIndex);
    await _saveAndRefresh(fetch: false);
  }

  // ── 환율 ──────────────────────────────────────────────
  Future<void> setFx(String? code) async {
    fxCode = code;
    await _saveAndRefresh();
  }

  // ── 표시 설정 ──────────────────────────────────────────
  Future<void> updateSettings({
    int? coinWidgetCount,
    int? stockWidgetCount,
    bool? showStockKrw,
    bool? showMarketStatus,
    bool? showUpdatedAt,
    ChangeColorScheme? colorScheme,
  }) async {
    this.coinWidgetCount = coinWidgetCount ?? this.coinWidgetCount;
    this.stockWidgetCount = stockWidgetCount ?? this.stockWidgetCount;
    this.showStockKrw = showStockKrw ?? this.showStockKrw;
    this.showMarketStatus = showMarketStatus ?? this.showMarketStatus;
    this.showUpdatedAt = showUpdatedAt ?? this.showUpdatedAt;
    this.colorScheme = colorScheme ?? this.colorScheme;
    await _saveAndRefresh(fetch: false);
  }

  // ── 내부 ──────────────────────────────────────────────
  Future<void> _saveAndRefresh({bool fetch = true}) async {
    notifyListeners();
    final p = _prefs;
    if (p != null) {
      await p.setStringList('coins', coinSymbols);
      await p.setStringList('stocks', stockTickers);
      if (fxCode == null) {
        await p.remove('fx');
      } else {
        await p.setString('fx', fxCode!);
      }
      await p.setInt('coinWidgetCount', coinWidgetCount);
      await p.setInt('stockWidgetCount', stockWidgetCount);
      await p.setBool('showStockKrw', showStockKrw);
      await p.setBool('showMarketStatus', showMarketStatus);
      await p.setBool('showUpdatedAt', showUpdatedAt);
      await p.setString('colorScheme', colorScheme.name);
    }
    if (fetch) {
      await refresh();
    } else {
      await _pushWidgets();
    }
  }

  Future<void> _pushWidgets() async {
    try {
      await _widgetSync.push(this);
    } catch (e) {
      // 위젯 동기화 실패가 앱 사용을 막으면 안 된다.
      debugPrint('Widget sync failed: $e');
    }
  }

  /// [newIndex]는 원래 항목을 뺀 뒤 기준의 위치다 (SliverReorderableList.onReorderItem 규약).
  static List<String> _reorder(List<String> list, int oldIndex, int newIndex) {
    final copy = [...list];
    final item = copy.removeAt(oldIndex);
    copy.insert(newIndex, item);
    return copy;
  }
}
