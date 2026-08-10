import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/extensions/app_colors.dart';
import 'package:runiverse/core/theme/tokens/app_radius.dart';
import 'package:runiverse/core/theme/tokens/app_spacing.dart';
import 'package:runiverse/core/theme/tokens/app_typography.dart';
import 'package:runiverse/core/widgets/app_button.dart';

/// 프로필을 아직 안 채운 사람에게 보이는 카드 (S05).
///
/// ## `EmptyStateCard`와 다르게 생겨야 한다
///
/// 빈 상태 카드는 **없다는 사실을 담담하게** 알린다. 이 카드는 **행동을 요구한다.**
/// 같은 회색으로 그리면 "등록된 대회가 없어요" 옆에 묻혀 아무도 누르지 않는다.
/// 그래서 primary 테두리와 옅은 배경을 줘 화면에서 유일하게 튀게 만든다.
///
/// ## ⚠️ 버튼은 secondary다
///
/// `AppButtonVariant.primary`는 **화면당 하나**고(`app_button.dart`), 홈에서는
/// 히어로의 '지금 매칭하기'가 그것이다. 여기까지 primary로 만들면 무엇을 눌러야
/// 하는지가 흐려진다. 강조는 **카드 자체**가 낸다.
///
/// ## 왜 정본에 없는데 만드는가
///
/// 온보딩을 마치지 않은 사람을 앱 진입 시 프로필 폼으로 밀어 넣던 것을 그만두면서,
/// 대신 만날 자리가 필요해졌다. 사유는 `docs/implementation-notes.md` §9-3-2에 있다.
class ProfilePromptCard extends StatelessWidget {
  const ProfilePromptCard({required this.onTap, super.key});

  /// 누르면 프로필 등록으로. **`push`로 여는 것이 호출자의 책임이다** —
  /// 강제가 아니므로 뒤로가기로 나올 수 있어야 한다.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.space4),
      decoration: BoxDecoration(
        // 채우지 않고 옅게 깐다. 채우면 히어로의 primary 버튼과 무게가 겹친다.
        color: colors.primaryMuted,
        borderRadius: AppRadius.lg,
        border: Border.all(color: colors.primary),
      ),
      child: Row(
        children: [
          // EmptyStateCard와 같은 규격(원 40 · 글리프 20)이되 색만 다르다.
          Container(
            width: AppSpacing.space8,
            height: AppSpacing.space8,
            decoration: BoxDecoration(
              color: colors.bgSurface,
              borderRadius: AppRadius.full,
            ),
            child: Icon(
              LucideIcons.user,
              size: AppSpacing.space5,
              color: colors.primary,
            ),
          ),
          const SizedBox(width: AppSpacing.space3),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  AppStrings.homeProfilePromptTitle,
                  style: AppTypography.body.copyWith(color: colors.textPrimary),
                ),
                const SizedBox(height: AppSpacing.space0),
                Text(
                  AppStrings.homeProfilePromptBody,
                  style: AppTypography.caption.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.space3),

          AppButton(
            label: AppStrings.homeProfilePromptCta,
            variant: AppButtonVariant.secondary,
            size: AppButtonSize.md,
            expand: false,
            onPressed: onTap,
          ),
        ],
      ),
    );
  }
}
