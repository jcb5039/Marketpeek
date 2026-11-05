import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../common.dart';

/// 잠금화면에 위젯 추가하는 방법 (3단계 안내).
class WidgetGuideScreen extends StatelessWidget {
  const WidgetGuideScreen({super.key});

  static const _steps = [
    ('잠금화면 길게 누르기', 'Face ID로 잠금을 푼 상태에서 화면을 꾹 눌러요'),
    ('사용자화 → 잠금화면', '아래쪽 사용자화를 누르고 잠금화면을 골라요'),
    ('위젯 칸 눌러서 추가', 'MarketPeek을 찾아 코인, 미국주식, 환율, AI 이슈 중 원하는 위젯만 넣어요'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: const Text(
          '위젯',
          style: TextStyle(fontSize: 15, color: AppColors.textSecondary),
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: PrimaryButton(
          label: '확인했어요',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        children: [
          const Text(
            '잠금화면에\n위젯 추가하기',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            '처음 한 번만 하면 돼요. 이후엔 앱에서 고른 내용이 자동으로 바뀌어요.',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          for (final (i, step) in _steps.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SurfaceCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: AppColors.accent,
                      child: Text(
                        '${i + 1}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppColors.onAccent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            step.$1,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            step.$2,
                            style: TextStyles.sub.copyWith(height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 6),
          const _SlotTip(),
        ],
      ),
    );
  }
}

/// iOS 잠금화면 위젯 칸 안내. 시계 위 한 줄 칸은 놓치기 쉬워서 따로 알려준다.
class _SlotTip extends StatelessWidget {
  const _SlotTip();

  @override
  Widget build(BuildContext context) {
    const body = TextStyle(
      fontSize: 13,
      color: AppColors.textSecondary,
      height: 1.5,
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.divider),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '더 많이 보고 싶다면',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 6),
          Text(
            '• 시계 위 날짜 옆 한 줄 칸에도 위젯을 하나 더 넣을 수 있어요. AI 이슈나 환율을 추천해요.',
            style: body,
          ),
          Text(
            '• 시계 아래는 큰 위젯 2개, 또는 큰 위젯 1개 + 작은 원형 2개, 또는 원형 4개까지 들어가요.',
            style: body,
          ),
        ],
      ),
    );
  }
}
