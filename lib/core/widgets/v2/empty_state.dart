import 'package:flutter/material.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';

/// 보여 줄 것이 없을 때 그 자리를 설명한다.
///
/// 정본 와이어프레임 `C4. 공통 빈 상태 컴포넌트` — 아이콘(스트로크) + 1줄
/// 메시지 + 선택적 CTA.
///
/// ## ⚠️ 빈 화면을 그냥 두지 않는다
///
/// 아무것도 없는 자리는 **고장과 구분되지 않는다.** 목록이 비었는지, 못
/// 받았는지, 아직 받는 중인지 사용자는 알 수 없다. 한 줄이라도 말해야 한다.
///
/// [why]는 **다음에 할 일**을 적는 자리다. "아직 친구가 없어요"만으로는 어디서
/// 친구를 만드는지 알 수 없다.
class EmptyStateV2 extends StatelessWidget {
  const EmptyStateV2({
    required this.icon,
    required this.message,
    this.why,
    this.cta,
    super.key,
  });

  final IconData icon;
  final String message;
  final String? why;
  final Widget? cta;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: colors.textTertiary),
            const SizedBox(height: AppSpacing.space4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTypographyV2.body05.copyWith(color: colors.textPrimary),
            ),
            if (why case final why?) ...[
              const SizedBox(height: AppSpacing.space2),
              Text(
                why,
                textAlign: TextAlign.center,
                style: AppTypographyV2.body07.copyWith(
                  color: colors.textTertiary,
                ),
              ),
            ],
            if (cta case final cta?) ...[
              const SizedBox(height: AppSpacing.space5),
              cta,
            ],
          ],
        ),
      ),
    );
  }
}
