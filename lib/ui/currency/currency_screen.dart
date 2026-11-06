import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../data/catalog.dart';
import '../../models/models.dart';
import '../../util/format.dart';

/// 환율 통화 선택. 고른 통화가 환율 위젯에 나온다.
/// 미국주식 원화 환산은 이 선택과 관계없이 항상 USD/KRW를 쓴다.
class CurrencyScreen extends StatelessWidget {
  const CurrencyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
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
              '고른 통화의 원화 환율이 환율 위젯에 나와요. 미국주식 원화 가격은 항상 USD/KRW로 계산해요.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.5),
            ),
          ),
          Material(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: RadioGroup<String>(
              groupValue: s.fxCode,
              onChanged: (code) => s.setFx(code),
              child: Column(
                children: [
                  for (final (i, c) in Catalog.currencies.indexed) ...[
                    if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                    RadioListTile<String>(
                      value: c.code,
                      // 이미 고른 통화를 다시 누르면 선택이 풀린다(onChanged(null)).
                      toggleable: true,
                      controlAffinity: ListTileControlAffinity.trailing,
                      title: Text('${c.name} ${c.code}',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      subtitle: _subtitle(s.quotes?.fx[c.code]?.rateKrw, s.quotes?.fx[c.code]?.changePct, c, s.colorScheme),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (s.fxCode != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: TextButton(
                onPressed: () => s.setFx(null),
                style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
                child: const Text('환율 위젯 표시 안 함'),
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
