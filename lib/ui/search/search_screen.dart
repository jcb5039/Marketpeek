import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../data/catalog.dart';

/// [stock]은 미국주식, [krStock]은 국내주식.
enum SearchKind { coin, krStock, stock }

/// 종목 검색 · 코인(이름·심볼) / 국내주식(이름·코드) / 미국주식(티커·한글명·영문명). 세 목록은 분리된다.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.kind});

  final SearchKind kind;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  String _query = '';

  bool get _isCoin => widget.kind == SearchKind.coin;

  String get _title => switch (widget.kind) {
        SearchKind.coin => '코인 추가',
        SearchKind.krStock => '국내주식 추가',
        SearchKind.stock => '미국주식 추가',
      };

  String get _hint => switch (widget.kind) {
        SearchKind.coin => '코인 이름·심볼 검색',
        SearchKind.krStock => '종목명·코드 검색 (예: 삼성전자)',
        SearchKind.stock => '티커·이름 검색 (예: TSLA, 테슬라)',
      };

  String get _footer => switch (widget.kind) {
        SearchKind.coin => '업비트 원화 시세 기준이에요',
        _ => '주식 시세는 설정 > 증권사 연결(한국투자증권)을 하면 보여요',
      };

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);

    // title: 굵게 보일 이름, sub: 아래 작은 글씨
    final results = switch (widget.kind) {
      SearchKind.coin =>
        Catalog.searchCoins(_query).map((c) => (id: c.symbol, title: c.symbol, sub: c.name)).toList(),
      SearchKind.krStock => Catalog.searchKrStocks(_query)
          .map((k) => (id: k.code, title: k.name, sub: '${k.code} · ${k.market}'))
          .toList(),
      SearchKind.stock => Catalog.searchStocks(_query)
          .map((t) => (id: t.ticker, title: t.ticker, sub: t.name))
          .toList(),
    };
    final selected = switch (widget.kind) {
      SearchKind.coin => s.coinSymbols,
      SearchKind.krStock => s.krStockCodes,
      SearchKind.stock => s.stockTickers,
    };
    Future<void> add(String id) => switch (widget.kind) {
          SearchKind.coin => s.addCoin(id),
          SearchKind.krStock => s.addKrStock(id),
          SearchKind.stock => s.addStock(id),
        };
    Future<void> remove(String id) => switch (widget.kind) {
          SearchKind.coin => s.removeCoin(id),
          SearchKind.krStock => s.removeKrStock(id),
          SearchKind.stock => s.removeStock(id),
        };

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(_title),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.accent,
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
            ),
            child: const Text('완료'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _controller,
              autofocus: !_isCoin,
              autocorrect: false,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: _hint,
                hintStyle: const TextStyle(color: AppColors.textTertiary),
                prefixIcon: const Icon(Icons.search, color: AppColors.textTertiary, size: 20),
                filled: true,
                fillColor: AppColors.surface,
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          if (_query.trim().isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Text(_isCoin ? '인기 코인' : '인기 종목', style: TextStyles.section),
            ),
          if (results.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('검색 결과가 없어요', style: TextStyles.sub),
            ),
          for (final r in results) ...[
            _ResultRow(
              id: r.title,
              name: r.sub,
              added: selected.contains(r.id),
              onAdd: () => add(r.id),
              onRemove: () => remove(r.id),
            ),
            const Divider(height: 1, indent: 20, endIndent: 20),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Text(_footer, style: TextStyles.caption),
          ),
        ],
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.id,
    required this.name,
    required this.added,
    required this.onAdd,
    required this.onRemove,
  });

  final String id;
  final String name;
  final bool added;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(id, style: TextStyles.symbol),
                const SizedBox(height: 2),
                Text(name, style: TextStyles.sub),
              ],
            ),
          ),
          added
              ? TextButton.icon(
                  onPressed: onRemove,
                  icon: const Icon(Icons.check, size: 14),
                  label: const Text('추가됨'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    backgroundColor: AppColors.surfaceHigh,
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                )
              : FilledButton(
                  onPressed: onAdd,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.onAccent,
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    minimumSize: const Size(0, 34),
                    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  child: const Text('추가'),
                ),
        ],
      ),
    );
  }
}
