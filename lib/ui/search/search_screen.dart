import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../data/catalog.dart';

enum SearchKind { coin, stock }

/// 종목 검색 · 코인(이름·심볼) / 미국주식(티커). 두 목록은 완전히 분리된다.
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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);

    final results = _isCoin
        ? Catalog.searchCoins(_query).map((c) => (id: c.symbol, name: c.name)).toList()
        : Catalog.searchStocks(_query).map((t) => (id: t.ticker, name: t.name)).toList();
    final selected = _isCoin ? s.coinSymbols : s.stockTickers;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(_isCoin ? '코인 추가' : '미국주식 추가'),
        actions: [
          IconButton(
            tooltip: '닫기',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _controller,
              autofocus: !_isCoin,
              textCapitalization: _isCoin ? TextCapitalization.none : TextCapitalization.characters,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: _isCoin ? '코인 이름·심볼 검색' : '티커 검색 (예: TSLA)',
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
              id: r.id,
              name: r.name,
              added: selected.contains(r.id),
              onAdd: () => _isCoin ? s.addCoin(r.id) : s.addStock(r.id),
              onRemove: () => _isCoin ? s.removeCoin(r.id) : s.removeStock(r.id),
            ),
            const Divider(height: 1, indent: 20, endIndent: 20),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Text(
              _isCoin ? '업비트 원화 시세 기준이에요' : '코인은 홈의 코인 + 추가에서 이름이나 심볼로 검색해요',
              style: TextStyles.caption,
            ),
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
