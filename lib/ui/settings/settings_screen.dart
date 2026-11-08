import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../util/format.dart';
import 'kis_connect_screen.dart';

/// 설정 · 위젯별 표시 항목, 상승·하락 색상.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final updated = s.quotes?.fetchedAt;
    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          const _Header('위젯별 표시 항목'),
          _Group(children: [
            _CountTile(
              title: '코인 위젯 한 칸에 보일 개수',
              value: s.coinWidgetCount,
              onChanged: (v) => s.updateSettings(coinWidgetCount: v),
            ),
            _CountTile(
              title: '미국주식 위젯 한 칸에 보일 개수',
              value: s.stockWidgetCount,
              onChanged: (v) => s.updateSettings(stockWidgetCount: v),
            ),
            _Check(
              title: '미국주식 원화 가격 함께 표시',
              value: s.showStockKrw,
              onChanged: (v) => s.updateSettings(showStockKrw: v),
            ),
            _Check(
              title: '미국장 상태 표시',
              value: s.showMarketStatus,
              onChanged: (v) => s.updateSettings(showMarketStatus: v),
            ),
            _Check(
              title: '위젯에 갱신 시각 표시',
              value: s.showUpdatedAt,
              onChanged: (v) => s.updateSettings(showUpdatedAt: v),
            ),
          ]),
          if (s.kis != null) ...[
            const _Header('증권사 연결'),
            _Group(children: [
              ListTile(
                title: const Text('한국투자증권',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                subtitle: Text(s.kisConnected ? '연결됨 · 주식 시세를 받아와요' : '연결 안 됨 · 키를 넣으면 주식 시세를 받아와요',
                    style: TextStyles.caption),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: (_) => const KisConnectScreen())),
              ),
            ]),
          ],
          const _Header('상승·하락 색'),
          RadioGroup<ChangeColorScheme>(
            groupValue: s.colorScheme,
            onChanged: (v) => s.updateSettings(colorScheme: v),
            child: const _Group(children: [
              _SchemeTile(
                scheme: ChangeColorScheme.korean,
                title: '한국식',
                up: ('상승 빨강', AppColors.krUp),
                down: ('하락 파랑', AppColors.krDown),
              ),
              _SchemeTile(
                scheme: ChangeColorScheme.global,
                title: '해외식',
                up: ('상승 초록', AppColors.glUp),
                down: ('하락 빨강', AppColors.glDown),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 14, 4, 0),
            child: Text(
              '위젯은 아이폰이 정한 주기로 갱신돼서 실시간 시세와 차이가 날 수 있어요.'
              '${updated == null ? '' : ' 마지막 갱신 ${formatHm(updated)}'}',
              style: TextStyles.caption.copyWith(height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
        child: Text(text, style: TextStyles.section),
      );
}

class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final (i, c) in children.indexed) ...[
            if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
            c,
          ],
        ],
      ),
    );
  }
}

class _Check extends StatelessWidget {
  const _Check({required this.title, required this.value, required this.onChanged});

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      value: value,
      onChanged: (v) => onChanged(v ?? false),
      title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      dense: true,
    );
  }
}

class _CountTile extends StatelessWidget {
  const _CountTile({required this.title, required this.value, required this.onChanged});

  final String title;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      subtitle: Text(
        value == AppState.maxWidgetRows
            ? '3개면 제목·갱신 시각 줄이 빠질 수 있어요'
            : '홈 목록 ${AppState.maxWidgetItems}번째까지 위젯에 넣을 수 있어요. 위젯 편집에서 몇 번째부터 보일지 골라요',
        style: TextStyles.caption,
      ),
      trailing: SegmentedButton<int>(
        showSelectedIcon: false,
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: AppColors.accent,
          selectedForegroundColor: AppColors.onAccent,
          visualDensity: VisualDensity.compact,
        ),
        segments: [
          for (var n = 1; n <= AppState.maxWidgetRows; n++)
            ButtonSegment(value: n, label: Text('$n개')),
        ],
        selected: {value},
        onSelectionChanged: (v) => onChanged(v.first),
      ),
    );
  }
}

class _SchemeTile extends StatelessWidget {
  const _SchemeTile({
    required this.scheme,
    required this.title,
    required this.up,
    required this.down,
  });

  final ChangeColorScheme scheme;
  final String title;
  final (String, Color) up;
  final (String, Color) down;

  @override
  Widget build(BuildContext context) {
    return RadioListTile<ChangeColorScheme>(
      value: scheme,
      dense: true,
      controlAffinity: ListTileControlAffinity.trailing,
      title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      subtitle: Text.rich(TextSpan(children: [
        TextSpan(text: up.$1, style: TextStyle(fontSize: 11, color: up.$2)),
        const TextSpan(text: ' · ', style: TextStyles.caption),
        TextSpan(text: down.$1, style: TextStyle(fontSize: 11, color: down.$2)),
      ])),
    );
  }
}
