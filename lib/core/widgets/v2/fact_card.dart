import 'package:flutter/widgets.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/core/widgets/v2/surface_card.dart';

/// 라벨 위, 값 아래의 수치 카드.
///
/// 대기방과 출발 대기실이 `시작 시간`·`목표 거리`를 같은 모양으로 그린다
/// (`158:3425`·`158:3462`). 러닝 요약도 같은 꼴이다.
///
/// ⚠️ **값에는 숫자와 단위만 넣는다.** 라벨이 이미 무엇인지 말하고 있어서,
/// 값에 다시 `시작`·`목표`를 붙이면 같은 말이 두 번 나온다.
class FactCard extends StatelessWidget {
  const FactCard({required this.label, required this.value, super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return SurfaceCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.space5),
      child: Column(
        children: [
          Text(
            label,
            style: AppTypographyV2.body13.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.space2),
          Text(
            value,
            style: AppTypographyV2.body02.copyWith(color: colors.textPrimary),
          ),
        ],
      ),
    );
  }
}
