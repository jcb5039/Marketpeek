import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../data/catalog.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../util/format.dart';
import '../../util/market_hours.dart';
import '../common.dart';
import '../currency/currency_screen.dart';
import '../search/search_screen.dart';
import '../settings/kis_connect_screen.dart';

/// 홈 · 내 목록 (빈 상태 / 일부만 고른 상태 / 전체 / 편집 모드)
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _editing = false;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final empty = s.isEmpty;
    if (empty && _editing) _editing = false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('내 목록'),
        actions: [
          if (!empty)
            TextButton(
              onPressed: () => setState(() => _editing = !_editing),
              style: TextButton.styleFrom(
                foregroundColor: _editing ? AppColors.accent : AppColors.textPrimary,
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
              ),
              child: Text(_editing ? '완료' : '편집'),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: empty
          ? const _EmptyState()
          : RefreshIndicator(
              color: AppColors.accent,
              onRefresh: s.refresh,
              child: _ListBody(state: s, editing: _editing),
            ),
    );
  }
}

class _ListBody extends StatelessWidget {
  const _ListBody({required this.state, required this.editing});

  final AppState state;
  final bool editing;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final marketLabel = usMarketStatusLabel(usMarketStatus(DateTime.now()));
    final hasCoins = s.coinSymbols.isNotEmpty;
    final hasKr = s.krStockCodes.isNotEmpty;
    final hasStocks = s.stockTickers.isNotEmpty;
    final hasFx = s.fxCode != null;
    // 편집 중에는 빈 섹션도 보여줘서 바로 추가할 수 있게 한다.
    final showCoins = hasCoins || editing;
    final showKr = hasKr || editing;
    final showStocks = hasStocks || editing;
    final showFx = hasFx || editing;
    // 증권사 미연결이면 주식 가격이 비어 있으니 첫 주식 섹션 위에 연결 안내를 한 번 띄운다.
    final needConnect = !editing && s.kis != null && !s.kisConnected && (hasKr || hasStocks);

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        if (showCoins) ...[
          SliverToBoxAdapter(
            child: SectionHeader(title: '코인', onAdd: () => _openSearch(context, SearchKind.coin)),
          ),
          _AssetList(
            ids: s.coinSymbols,
            editing: editing,
            onReorder: s.reorderCoins,
            onRemove: s.removeCoin,
            itemBuilder: (id, i) => _CoinRow(symbol: id, inWidget: i < AppState.maxWidgetItems),
          ),
        ],
        if (showKr) ...[
          if (showCoins) const _Divider(),
          if (needConnect) const SliverToBoxAdapter(child: _ConnectBanner()),
          SliverToBoxAdapter(
            child: SectionHeader(title: '국내주식', onAdd: () => _openSearch(context, SearchKind.krStock)),
          ),
          _AssetList(
            ids: s.krStockCodes,
            editing: editing,
            onReorder: s.reorderKrStocks,
            onRemove: s.removeKrStock,
            itemBuilder: (id, i) => _KrStockRow(code: id, inWidget: i < AppState.maxWidgetItems),
          ),
        ],
        if (showStocks) ...[
          if (showCoins || showKr) const _Divider(),
          if (needConnect && !showKr) const SliverToBoxAdapter(child: _ConnectBanner()),
          SliverToBoxAdapter(
            child: SectionHeader(
              title: '미국주식 · $marketLabel',
              onAdd: () => _openSearch(context, SearchKind.stock),
            ),
          ),
          _AssetList(
            ids: s.stockTickers,
            editing: editing,
            onReorder: s.reorderStocks,
            onRemove: s.removeStock,
            itemBuilder: (id, i) => _StockRow(ticker: id, inWidget: i < AppState.maxWidgetItems),
          ),
        ],
        if (showFx) ...[
          if (showCoins || showKr || showStocks) const _Divider(),
          const SliverToBoxAdapter(child: SectionHeader(title: '환율 · 위젯에 표시할 통화')),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _FxCard(state: s),
            ),
          ),
        ],
        if (!editing && !(hasCoins && hasKr && hasStocks && hasFx))
          SliverToBoxAdapter(child: _MoreSuggestions(state: s)),
        SliverToBoxAdapter(child: _Footer(state: s)),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }
}

/// 증권사 미연결 안내. 누르면 연결 화면으로 간다.
class _ConnectBanner extends StatelessWidget {
  const _ConnectBanner();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: SurfaceCard(
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute<void>(builder: (_) => const KisConnectScreen())),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: const Row(children: [
          Expanded(child: Text('증권사를 연결하면 주식 시세가 보여요', style: TextStyles.sub)),
          Text('연결하기 ›',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.accent)),
        ]),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.only(top: 12),
          child: Divider(height: 1, indent: 20, endIndent: 20),
        ),
      );
}

/// 편집 모드면 삭제·드래그 정렬을 지원하는 리스트.
class _AssetList extends StatelessWidget {
  const _AssetList({
    required this.ids,
    required this.editing,
    required this.onReorder,
    required this.onRemove,
    required this.itemBuilder,
  });

  final List<String> ids;
  final bool editing;
  final Future<void> Function(int, int) onReorder;
  final Future<void> Function(String) onRemove;
  final Widget Function(String id, int index) itemBuilder;

  @override
  Widget build(BuildContext context) {
    if (ids.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: Text('아직 없어요', style: TextStyles.caption),
        ),
      );
    }
    if (!editing) {
      return SliverList.builder(
        itemCount: ids.length,
        itemBuilder: (_, i) => itemBuilder(ids[i], i),
      );
    }
    return SliverReorderableList(
      itemCount: ids.length,
      onReorderItem: onReorder,
      itemBuilder: (context, i) {
        final id = ids[i];
        return Material(
          key: ValueKey(id),
          color: AppColors.bg,
          child: Row(
            children: [
              IconButton(
                tooltip: '$id 삭제',
                onPressed: () => onRemove(id),
                icon: const Icon(Icons.remove_circle, color: AppColors.danger),
              ),
              Expanded(child: itemBuilder(id, i)),
              ReorderableDragStartListener(
                index: i,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                  child: Icon(Icons.drag_handle, color: AppColors.textTertiary),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.title,
    required this.subtitle,
    required this.inWidget,
    required this.trailing,
  });

  final String title;
  final String subtitle;
  final bool inWidget;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(title, style: TextStyles.symbol),
                  if (inWidget) const WidgetBadge(),
                ]),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyles.sub),
              ],
            ),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: trailing),
        ],
      ),
    );
  }
}

class _CoinRow extends StatelessWidget {
  const _CoinRow({required this.symbol, required this.inWidget});

  final String symbol;
  final bool inWidget;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final q = s.quotes?.coins[symbol];
    return _Row(
      title: symbol,
      subtitle: Catalog.coin(symbol).name,
      inWidget: inWidget,
      trailing: [
        Text(q == null ? '—' : formatKrw(q.priceKrw), style: TextStyles.price),
        const SizedBox(height: 2),
        Text(
          q == null ? '' : formatPct(q.changePct),
          style: TextStyle(fontSize: 12, color: AppColors.change(q?.changePct, s.colorScheme)),
        ),
      ],
    );
  }
}

class _KrStockRow extends StatelessWidget {
  const _KrStockRow({required this.code, required this.inWidget});

  final String code;
  final bool inWidget;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final q = s.quotes?.krStocks[code];
    return _Row(
      title: Catalog.krStock(code).name,
      subtitle: code,
      inWidget: inWidget,
      trailing: [
        Text(q == null ? '—' : formatKrw(q.priceKrw), style: TextStyles.price),
        const SizedBox(height: 2),
        Text(
          q == null ? '' : formatPct(q.changePct),
          style: TextStyle(fontSize: 12, color: AppColors.change(q?.changePct, s.colorScheme)),
        ),
      ],
    );
  }
}

class _StockRow extends StatelessWidget {
  const _StockRow({required this.ticker, required this.inWidget});

  final String ticker;
  final bool inWidget;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final q = s.quotes?.stocks[ticker];
    final usdKrw = s.usdKrw;
    return _Row(
      title: ticker,
      subtitle: Catalog.stock(ticker).name,
      inWidget: inWidget,
      trailing: [
        Text(q == null ? '—' : formatUsd(q.priceUsd), style: TextStyles.price),
        const SizedBox(height: 2),
        Text(
          (q == null || usdKrw == null) ? '—' : formatKrw(stockKrw(q.priceUsd, usdKrw)),
          style: TextStyles.sub,
        ),
        Text(
          q == null ? '' : formatPct(q.changePct),
          style: TextStyle(fontSize: 12, color: AppColors.change(q?.changePct, s.colorScheme)),
        ),
      ],
    );
  }
}

class _FxCard extends StatelessWidget {
  const _FxCard({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final codes = state.fxCodes;
    if (codes.isEmpty) {
      return SurfaceCard(
        onTap: () => _openCurrency(context),
        child: const Row(children: [
          Expanded(child: Text('통화를 골라주세요', style: TextStyles.sub)),
          Text('선택 ›', style: TextStyles.sub),
        ]),
      );
    }
    return SurfaceCard(
      onTap: () => _openCurrency(context),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (i, code) in codes.indexed) ...[
                  if (i > 0) const SizedBox(height: 12),
                  _fxLine(Catalog.currency(code), state.quotes?.fx[code]),
                ],
              ],
            ),
          ),
          const Text('변경 ›', style: TextStyles.sub),
        ],
      ),
    );
  }

  Widget _fxLine(Currency c, FxQuote? q) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${c.name} ${c.code}', style: TextStyles.symbol.copyWith(fontSize: 15)),
        const SizedBox(height: 4),
        Text.rich(TextSpan(children: [
          TextSpan(
            text: q == null ? '—' : formatFxLine(c, q.rateKrw),
            style: TextStyles.sub.copyWith(color: AppColors.textPrimary),
          ),
          if (q != null)
            TextSpan(
              text: '  ${formatPct(q.changePct)}',
              style: TextStyle(fontSize: 12, color: AppColors.change(q.changePct, state.colorScheme)),
            ),
        ])),
      ],
    );
  }
}

/// "다른 것도 보고 싶다면 · 안 골라도 돼요"
class _MoreSuggestions extends StatelessWidget {
  const _MoreSuggestions({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final buttons = <Widget>[
      if (state.coinSymbols.isEmpty)
        _OutlineBox(label: '+ 코인', onTap: () => _openSearch(context, SearchKind.coin)),
      if (state.krStockCodes.isEmpty)
        _OutlineBox(label: '+ 국내주식', onTap: () => _openSearch(context, SearchKind.krStock)),
      if (state.stockTickers.isEmpty)
        _OutlineBox(label: '+ 미국주식', onTap: () => _openSearch(context, SearchKind.stock)),
      if (state.fxCode == null)
        _OutlineBox(label: '+ 환율', onTap: () => _openCurrency(context)),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text('다른 것도 보고 싶다면 · 안 골라도 돼요', style: TextStyles.caption),
          ),
          Row(
            children: [
              for (final (i, b) in buttons.indexed) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: b),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _OutlineBox extends StatelessWidget {
  const _OutlineBox({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        side: const BorderSide(color: AppColors.divider),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(vertical: 14),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      child: Text(label),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final t = state.quotes?.fetchedAt;
    final parts = [
      if (t != null) '${formatHm(t)} 갱신',
      if (state.stockTickers.isNotEmpty) '미국주식 원화는 USD/KRW 기준',
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Text(parts.join(' · '), style: TextStyles.caption),
    );
  }
}

/// 아무것도 고르지 않은 첫 화면.
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final s = AppScope.read(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.description_outlined, size: 44, color: AppColors.textTertiary),
            const SizedBox(height: 20),
            const Text('아직 추가한 항목이 없어요',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            const Text(
              '코인, 국내주식, 미국주식, 환율 중\n보고 싶은 것만 골라 추가하세요',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.5),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                PillButton(label: '코인 추가', onPressed: () => _openSearch(context, SearchKind.coin)),
                PillButton(label: '국내주식 추가', onPressed: () => _openSearch(context, SearchKind.krStock)),
                PillButton(label: '미국주식 추가', onPressed: () => _openSearch(context, SearchKind.stock)),
                PillButton(label: '환율 선택', onPressed: () => _openCurrency(context)),
              ],
            ),
            const SizedBox(height: 32),
            const Text('많이 보는 항목 바로 추가', style: TextStyles.caption),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                PillButton(label: '+ BTC', outlinedAccent: true, onPressed: () => s.addCoin('BTC')),
                PillButton(label: '+ 삼성전자', outlinedAccent: true, onPressed: () => s.addKrStock('005930')),
                PillButton(label: '+ TSLA', outlinedAccent: true, onPressed: () => s.addStock('TSLA')),
                PillButton(label: '+ 달러 USD', outlinedAccent: true, onPressed: () => s.addFx('USD')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

void _openSearch(BuildContext context, SearchKind kind) {
  Navigator.of(context).push(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => SearchScreen(kind: kind),
  ));
}

void _openCurrency(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CurrencyScreen()));
}
