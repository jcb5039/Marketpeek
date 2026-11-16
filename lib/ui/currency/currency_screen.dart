import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../data/catalog.dart';
import '../../models/models.dart';
import '../../util/format.dart';

/// 환율 통화 선택 (여러 개). 첫 번째로 고른 통화가 환율 위젯에 나오고,
/// 고른 통화 전체를 자유 구성 위젯에서 칸마다 고를 수 있다.
/// 미국주식 원화 환산은 이 선택과 관계없이 항상 USD/KRW를 쓴다.
class CurrencyScreen extends StatefulWidget {
  const CurrencyScreen({super.key});

  @override
  State<CurrencyScreen> createState() => _CurrencyScreenState();
}

class _CurrencyScreenState extends State<CurrencyScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final list = Catalog.searchCurrencies(_query);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: const Text('환율 통화 선택', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
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
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 4, 4, 16),
            child: Text(
              '여러 통화를 고를 수 있어요. 환율 위젯에는 처음 고른 통화가 나오고, 자유 구성 위젯에서는 고른 통화 중에 골라 넣을 수 있어요.\n'
              '미국주식 원화 가격은 항상 USD/KRW로 계산해요.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.5),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                hintText: '통화 이름·코드 검색 (예: 파운드, GBP)',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          if (list.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('찾는 통화가 없어요', style: TextStyles.caption)),
            ),
          if (list.isNotEmpty)
          Material(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final (i, c) in list.indexed) ...[
                  if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                  CheckboxListTile(
                    // 이미 고른 통화를 다시 누르면 빠진다.
                    value: s.fxCodes.contains(c.code),
                    onChanged: (_) => s.toggleFx(c.code),
                    controlAffinity: ListTileControlAffinity.trailing,
                    title: Text('${c.name} ${c.code}',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _subtitle(s.quotes?.fx[c.code]?.rateKrw, s.quotes?.fx[c.code]?.changePct, c, s.colorScheme),
                        if (s.fxCode == c.code)
                          const Text('환율 위젯에 표시',
                              style: TextStyle(fontSize: 12, color: AppColors.accent, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (s.fxCodes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: TextButton(
                onPressed: s.clearFx,
                style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
                child: const Text('환율 모두 빼기'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _subtitle(double? rate, double? pct, Currency c, ChangeColorScheme scheme) {
    // 아직 받아오지 않은 통화는 기준 단위만 안내한다.
    if (rate == null) {
      return Text('${c.unit} ${c.code} 기준', style: TextStyles.caption);
    }
    return Text.rich(TextSpan(children: [
      TextSpan(text: formatFxLine(c, rate), style: TextStyles.caption),
      TextSpan(
        text: '  ${formatPct(pct ?? 0)}',
        style: TextStyle(fontSize: 12, color: AppColors.change(pct, scheme)),
      ),
    ]));
  }
}
