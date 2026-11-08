import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../data/catalog.dart';
import '../../state/app_state.dart';
import '../../util/format.dart';
import '../../util/market_hours.dart';
import '../common.dart';
import 'widget_guide_screen.dart';

/// 위젯 4종 안내. 각 카드 왼쪽은 현재 설정으로 그린 잠금화면 위젯 미리보기다.
class WidgetsScreen extends StatelessWidget {
  const WidgetsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('위젯')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 0, 4, 16),
            child: Text(
              '필요한 위젯만 골라서 잠금화면에 추가하세요. 시계 위 한 줄 칸에도 하나 더 넣을 수 있어요.\n'
              '코인·미국주식은 같은 위젯을 여러 개 놓고, 위젯을 길게 눌러 "위젯 편집"에서 몇 번째부터 보일지 고르세요.',
              style: TextStyles.sub,
            ),
          ),
          _WidgetCard(
            preview: _CoinPreview(state: s),
            title: '코인',
            description: '고른 코인의 원화 가격과 등락률',
          ),
          _WidgetCard(
            preview: _StockPreview(state: s),
            title: '미국주식',
            description: '달러·원화 가격, 등락률, 미국장 상태',
          ),
          _WidgetCard(
            preview: _FxPreview(state: s),
            title: '환율',
            description: '환율 탭에서 고른 통화의 원화 환율과 등락률',
          ),
          _IssueCard(state: s),
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 4, 4, 12),
            child: Text(
              '홈 화면에는 "자유 구성" 위젯도 있어요. 위젯을 길게 눌러 "위젯 편집"에서 칸 3개마다 코인·미국주식·환율 중 보고 싶은 것을 골라요.',
              style: TextStyles.sub,
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const WidgetGuideScreen()),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accent,
              side: const BorderSide(color: AppColors.accent),
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
            ),
            child: const Text('잠금화면에 추가하는 방법'),
          ),
        ],
      ),
    );
  }
}

class _WidgetCard extends StatelessWidget {
  const _WidgetCard({required this.preview, required this.title, required this.description});

  final Widget preview;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SurfaceCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            SizedBox(width: 92, child: preview),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyles.symbol.copyWith(fontSize: 15)),
                  const SizedBox(height: 4),
                  Text(description, style: TextStyles.sub),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IssueCard extends StatelessWidget {
  const _IssueCard({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final issue = state.quotes?.issue;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SurfaceCard(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PreviewBox(
              children: [
                const Text('✦ 어제 이슈 · AI', style: _P.label),
                Text(issue?.text ?? '매일 아침 갱신돼요', style: _P.value, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
            const SizedBox(height: 10),
            Text.rich(TextSpan(children: [
              TextSpan(text: 'AI 어제 이슈 ', style: TextStyles.symbol.copyWith(fontSize: 15)),
              const TextSpan(text: '가로형', style: TextStyles.caption),
            ])),
            const SizedBox(height: 4),
            const Text('전날 가장 큰 시장 이슈를 매일 아침 한 줄로', style: TextStyles.sub),
          ],
        ),
      ),
    );
  }
}

// ── 미리보기: iOS accessoryRectangular 위젯과 같은 정보 구성 ──────────

class _P {
  static const label = TextStyle(fontSize: 9, color: AppColors.textSecondary, fontWeight: FontWeight.w600);
  static const value = TextStyle(fontSize: 10, color: AppColors.textPrimary, fontWeight: FontWeight.w700);
  static const small = TextStyle(fontSize: 9, color: AppColors.textSecondary);
}

class _PreviewBox extends StatelessWidget {
  const _PreviewBox({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}

Widget _rowLine(String left, String right, Color rightColor) => Row(
      children: [
        Expanded(child: Text(left, style: _P.value, overflow: TextOverflow.ellipsis)),
        Text(right, style: _P.small.copyWith(color: rightColor)),
      ],
    );

class _CoinPreview extends StatelessWidget {
  const _CoinPreview({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final syms = state.coinSymbols.take(state.coinWidgetCount).toList();
    return _PreviewBox(children: [
      const Text('코인', style: _P.label),
      if (syms.isEmpty) const Text('코인을 추가하세요', style: _P.small),
      for (final sym in syms)
        _rowLine(
          sym,
          state.quotes?.coins[sym] == null ? '—' : formatPct(state.quotes!.coins[sym]!.changePct),
          AppColors.change(state.quotes?.coins[sym]?.changePct, state.colorScheme),
        ),
    ]);
  }
}

class _StockPreview extends StatelessWidget {
  const _StockPreview({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final t = state.stockTickers.isEmpty ? null : state.stockTickers.first;
    final q = t == null ? null : state.quotes?.stocks[t];
    final status = usMarketStatus(DateTime.now()) == UsMarketStatus.open ? '장중' : '장 마감';
    return _PreviewBox(children: [
      Text('미국주식 · $status', style: _P.label),
      if (t == null)
        const Text('종목을 추가하세요', style: _P.small)
      else ...[
        _rowLine(t, q == null ? '—' : formatPct(q.changePct), AppColors.change(q?.changePct, state.colorScheme)),
        Text(q == null ? '—' : formatUsd(q.priceUsd), style: _P.small),
      ],
    ]);
  }
}

class _FxPreview extends StatelessWidget {
  const _FxPreview({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final code = state.fxCode;
    if (code == null) {
      return const _PreviewBox(children: [
        Text('환율', style: _P.label),
        Text('통화를 고르세요', style: _P.small),
      ]);
    }
    final c = Catalog.currency(code);
    final q = state.quotes?.fx[code];
    return _PreviewBox(children: [
      Text('환율 · ${c.code}', style: _P.label),
      Text(q == null ? '—' : formatFxRate(q.rateKrw), style: _P.value),
      Text(q == null ? '' : formatPct(q.changePct),
          style: _P.small.copyWith(color: AppColors.change(q?.changePct, state.colorScheme))),
    ]);
  }
}
