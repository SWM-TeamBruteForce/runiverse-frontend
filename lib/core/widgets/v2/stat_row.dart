import 'package:flutter/material.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';

/// 라벨 위, 값 아래로 선 수치 몇 개 — 시안 `158:3796`.
///
/// 기록 탭 맨 위의 `주간 누적 거리 · 누적 시간 · 누적 경사`가 이것이다.
///
/// ## ⚠️ [FactRowV2]와 다른 것이다
///
/// 그쪽은 **면이 깔린 패널**이고 가운데 정렬이다. 이쪽은 배경 없이 글자만
/// 왼쪽으로 선다. 같은 부품으로 합치면 둘 다 어정쩡해진다.
///
/// ## 모르는 값을 지어내지 않는다
///
/// 누적 경사는 서버가 `null`을 줄 수 있다. `RecordSummary`가 **하나라도
/// 모르면 합계를 통째로 `null`로** 두므로(아는 것만 더하면 실제보다 작다),
/// 이 부품은 받은 글자를 그대로 그리기만 한다 — 부르는 쪽이 `--`를 넣는다.
class StatRowV2 extends StatelessWidget {
  const StatRowV2({required this.stats, super.key});

  final List<Stat> stats;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final stat in stats)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stat.label,
                  style: AppTypographyV2.body12.copyWith(
                    color: colors.textTertiary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.space2),
                Text(
                  stat.value,
                  style: AppTypographyV2.body02.copyWith(
                    color: colors.textStrong,
                    // 숫자가 갱신되며 자릿수가 바뀐다. 안 주면 칸이 흔들린다.
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 라벨 하나와 값 하나.
class Stat {
  const Stat({required this.label, required this.value});

  final String label;

  /// **모르면 지어내지 않는다.** 부르는 쪽이 `--`를 넣는다.
  final String value;
}
