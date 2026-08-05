import 'package:flutter/material.dart';
import 'package:runiverse/core/theme/extensions/app_colors.dart';
import 'package:runiverse/core/theme/tokens/app_radius.dart';
import 'package:runiverse/core/theme/tokens/app_spacing.dart';
import 'package:runiverse/core/theme/tokens/app_typography.dart';

/// 카드 자리에 들어가는 빈 상태 — 와이어프레임_최종 C4.
///
/// 규격은 `아이콘(스트로크) + 1줄 메시지 + 선택적 한 줄`이다.
/// [ComingSoonPage]가 화면 전체를 채우는 형태라면 이쪽은 **목록의 한 칸**이다.
/// 그래서 세로로 크게 쌓지 않고 가로로 눕힌다 — 빈 칸이 화면을 차지할수록
/// "고장 났나"로 읽힌다.
///
/// ⚠️ 아이콘은 **Lucide만** 쓴다. `Icons.*`(Material)를 넘기지 않는다.
/// 이모지도 쓰지 않는다(`docs/implementation-notes.md` §3-5).
class EmptyStateCard extends StatelessWidget {
  const EmptyStateCard({
    required this.icon,
    required this.message,
    this.hint,
    super.key,
  });

  /// Lucide 아이콘.
  final IconData icon;

  /// 한 줄 메시지. 무엇이 없는지 담담하게 말한다.
  final String message;

  /// 무엇을 하면 채워지는지. 없으면 메시지만 나온다.
  ///
  /// 빈 화면은 사과할 자리가 아니라 다음 행동을 알려줄 자리다.
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final hint = this.hint;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.space4),
      decoration: BoxDecoration(
        color: colors.bgSurface,
        borderRadius: AppRadius.lg,
        border: Border.all(color: colors.borderDefault),
      ),
      child: Row(
        children: [
          // 스케일 값을 크기로 쓴다. space8 = 40(원), space5 = 20(글리프).
          Container(
            width: AppSpacing.space8,
            height: AppSpacing.space8,
            decoration: BoxDecoration(
              color: colors.bgElevated,
              borderRadius: AppRadius.full,
            ),
            child: Icon(
              icon,
              size: AppSpacing.space5,
              color: colors.textTertiary,
            ),
          ),
          const SizedBox(width: AppSpacing.space3),

          // 메시지가 길어지면 줄바꿈되도록 남은 폭을 전부 준다.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  message,
                  style: AppTypography.body.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
                if (hint != null) ...[
                  const SizedBox(height: AppSpacing.space0),
                  Text(
                    hint,
                    style: AppTypography.caption.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
