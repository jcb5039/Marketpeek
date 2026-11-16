import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/catalog.dart';
import '../data/kis_quote_repository.dart';
import '../data/quote_repository.dart';
import '../models/models.dart';
import '../util/format.dart';
import '../widget_bridge/live_activity.dart';
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
    this.kis,
  })  : _repo = repository,
        _widgetSync = widgetSync ?? WidgetSync();

  final QuoteRepository _repo;

  /// 검색용 전체 코인 목록을 받아오는 함수 (업비트 원화 마켓). 없으면 기본 목록만 쓴다.
  final Future<List<Coin>> Function()? coinListLoader;
  final WidgetSync _widgetSync;

  /// 한국투자증권 연결 (주식 시세). 없으면 설정에 연결 항목이 안 보인다.
  final KisQuoteRepository? kis;

  /// 설정에서 증권사 키를 넣었는지.
  bool kisConnected = false;
  SharedPreferences? _prefs;

  // 관심 목록 — 코인·국내주식·미국주식은 완전히 분리된 목록이다.
  List<String> coinSymbols = [];
  List<String> stockTickers = []; // 미국주식 티커
  List<String> krStockCodes = []; // 국내주식 6자리 코드

  /// 고른 환율 통화 (고른 순서). 위젯 편집(자유 구성)에서는 이 통화들만 고를 수 있다.
  List<String> fxCodes = [];

  /// 환율 위젯에 표시할 통화 = 첫 번째로 고른 통화. 없으면 null.
  String? get fxCode => fxCodes.isEmpty ? null : fxCodes.first;

  // 표시 설정
  int coinWidgetCount = 2;
  int stockWidgetCount = 1;
  bool showStockKrw = true;
  bool showMarketStatus = true;
  bool showUpdatedAt = true;
  ChangeColorScheme colorScheme = ChangeColorScheme.korean;

  QuoteBundle? quotes;
  bool loading = false;

  /// 잠금화면 라이브 액티비티를 켰는지. 켜져 있으면 앱이 화면에 있는 동안 [liveInterval]마다 새로 받는다.
  bool liveActivityOn = false;
  static const liveInterval = Duration(seconds: 30);
  final LiveActivity _live = LiveActivity();
  Timer? _liveTimer;

  /// 잠금화면 직사각형 위젯에 넣을 수 있는 최대 종목 수.
  /// 3개면 위젯이 공간에 따라 제목·갱신 시각 줄을 생략할 수 있다.
  static const maxWidgetRows = 3;

  /// 위젯 스냅샷에 담는 코인·미국주식 최대 개수(홈 목록 앞에서부터).
  /// 위젯마다 "위젯 편집"에서 종목을 고르고, 잠금화면 사각형은 그 종목부터 여러 줄을 보여준다.
  static const maxWidgetItems = 6;

  bool get isEmpty =>
      coinSymbols.isEmpty && stockTickers.isEmpty && krStockCodes.isEmpty && fxCode == null;

  double? get usdKrw => quotes?.fx['USD']?.rateKrw;

  Future<void> load() async {
    final p = _prefs = await SharedPreferences.getInstance();
    coinSymbols = p.getStringList('coins') ?? [];
    stockTickers = p.getStringList('stocks') ?? [];
    krStockCodes = p.getStringList('krStocks') ?? [];
    // 예전 버전은 통화 하나만 'fx'에 저장했다.
    final legacyFx = p.getString('fx');
    fxCodes = p.getStringList('fxList') ?? [?legacyFx];
    coinWidgetCount = p.getInt('coinWidgetCount') ?? 2;
    stockWidgetCount = p.getInt('stockWidgetCount') ?? 1;
    showStockKrw = p.getBool('showStockKrw') ?? true;
    showMarketStatus = p.getBool('showMarketStatus') ?? true;
    showUpdatedAt = p.getBool('showUpdatedAt') ?? true;
    colorScheme = ChangeColorScheme.values.byName(
        p.getString('colorScheme') ?? ChangeColorScheme.korean.name);
    _loadCachedCoinList(p);
    kisConnected = await kis?.isConnected ?? false;
    notifyListeners();
    liveActivityOn = p.getBool('liveActivity') ?? false;
    // 목록을 먼저 받아야 업비트 시세 요청에서 상장폐지 코인을 걸러낼 수 있다.
    await _refreshCoinList(p);
    await refresh();
    // 8시간이 지나 iOS가 끝냈으면 앱을 열 때 다시 띄운다.
    if (liveActivityOn && !await _live.isActive()) {
      await _live.start(_liveRows(), colorScheme.name);
    }
    _syncLiveTimer();
  }

  /// 앱이 백그라운드에서 돌아왔을 때 (main.dart AppLifecycleListener).
  /// 시세를 새로 받고, 새 설치·8시간 종료 등으로 라이브 액티비티가 사라졌으면 다시 띄운다.
  /// 처음 켤 때는 [load]가 같은 일을 한다.
  Future<void> onResume() async {
    if (_prefs == null) return; // 아직 load 전
    await refresh();
    if (liveActivityOn && !await _live.isActive()) {
      await _live.start(_liveRows(), colorScheme.name);
    }
  }

  // ── 잠금화면 라이브 액티비티 ─────────────────────────────
  /// 켜기에 성공하면 true. 아이폰 설정에서 실시간 현황을 껐으면 false.
  Future<bool> setLiveActivity(bool on) async {
    if (on) {
      liveActivityOn = await _live.start(_liveRows(), colorScheme.name);
    } else {
      await _live.end();
      liveActivityOn = false;
    }
    await _prefs?.setBool('liveActivity', liveActivityOn);
    _syncLiveTimer();
    notifyListeners();
    return liveActivityOn;
  }

  void _syncLiveTimer() {
    _liveTimer?.cancel();
    _liveTimer = liveActivityOn ? Timer.periodic(liveInterval, (_) => refresh(pushWidgets: false)) : null;
  }

  /// 첫 코인 · 첫 미국주식 · USD.
  List<LiveRow> _liveRows() {
    final q = quotes;
    return [
      if (coinSymbols.isNotEmpty)
        () {
          final s = coinSymbols.first;
          final c = q?.coins[s];
          return LiveRow(
              id: 'coin:$s', symbol: s, price: c == null ? '—' : formatKrwShort(c.priceKrw), change: c?.changePct);
        }(),
      if (stockTickers.isNotEmpty)
        () {
          final t = stockTickers.first;
          final st = q?.stocks[t];
          return LiveRow(
              id: 'stock:$t', symbol: t, price: st == null ? '—' : formatUsd(st.priceUsd), change: st?.changePct);
        }(),
      () {
        final usd = q?.fx['USD'];
        return LiveRow(
            id: 'fx:USD', symbol: 'USD', price: usd == null ? '—' : formatFxRate(usd.rateKrw), change: usd?.changePct);
      }(),
    ];
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    super.dispose();
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

  /// [pushWidgets]가 false면 위젯을 다시 그리지 않는다. 라이브 액티비티 30초 갱신용:
  /// 위젯을 다시 그리면 위젯도 동시에 KIS를 불러 초당 한도(EGW00201)에 서로 걸린다.
  Future<void> refresh({bool pushWidgets = true}) async {
    loading = true;
    notifyListeners();
    try {
      final fresh = await _repo.fetch(
        coinSymbols: coinSymbols,
        stockTickers: stockTickers,
        krStockCodes: krStockCodes,
        // 환율 선택 화면에서 비교할 수 있게 지원 통화는 모두 받아둔다.
        currencyCodes: [for (final c in Catalog.currencies) c.code],
      );
      quotes = _keepPrevious(fresh, quotes);
    } finally {
      loading = false;
      notifyListeners();
    }
    if (pushWidgets) await _pushWidgets();
    if (liveActivityOn) await _live.update(_liveRows(), colorScheme.name);
  }

  /// 이번에 못 받은 종목(일시적 실패)은 "—" 대신 직전 값을 유지한다.
  static QuoteBundle _keepPrevious(QuoteBundle fresh, QuoteBundle? old) {
    if (old == null) return fresh;
    return QuoteBundle(
      coins: {...old.coins, ...fresh.coins},
      stocks: {...old.stocks, ...fresh.stocks},
      krStocks: {...old.krStocks, ...fresh.krStocks},
      fx: {...old.fx, ...fresh.fx},
      issue: fresh.issue ?? old.issue,
      fetchedAt: fresh.fetchedAt,
    );
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

  // ── 국내주식 목록 ───────────────────────────────────────
  Future<void> addKrStock(String code) async {
    if (krStockCodes.contains(code)) return;
    krStockCodes = [...krStockCodes, code];
    await _saveAndRefresh();
  }

  Future<void> removeKrStock(String code) async {
    krStockCodes = krStockCodes.where((c) => c != code).toList();
    await _saveAndRefresh(fetch: false);
  }

  Future<void> reorderKrStocks(int oldIndex, int newIndex) async {
    krStockCodes = _reorder(krStockCodes, oldIndex, newIndex);
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
  Future<void> addFx(String code) async {
    if (fxCodes.contains(code)) return;
    fxCodes = [...fxCodes, code];
    await _saveAndRefresh();
  }

  Future<void> removeFx(String code) async {
    fxCodes = fxCodes.where((c) => c != code).toList();
    await _saveAndRefresh(fetch: false);
  }

  /// 환율 화면에서 통화를 누를 때: 고른 통화면 빼고, 아니면 추가한다.
  Future<void> toggleFx(String code) =>
      fxCodes.contains(code) ? removeFx(code) : addFx(code);

  Future<void> clearFx() async {
    fxCodes = [];
    await _saveAndRefresh(fetch: false);
  }

  // ── 증권사 연결 ─────────────────────────────────────────
  /// 토큰 발급에 성공해야 저장된다. 실패하면 [KisApiException]을 그대로 던진다.
  Future<void> connectKis(KisCredentials credentials) async {
    final k = kis;
    if (k == null) return;
    await k.connect(credentials);
    kisConnected = true;
    notifyListeners();
    await refresh();
  }

  Future<void> disconnectKis() async {
    await kis?.disconnect();
    kisConnected = false;
    notifyListeners();
    await refresh();
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
      await p.setStringList('krStocks', krStockCodes);
      await p.setStringList('fxList', fxCodes);
      await p.remove('fx');
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
