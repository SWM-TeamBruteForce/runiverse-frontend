import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/extensions/app_colors.dart';
import 'package:runiverse/core/theme/tokens/app_radius.dart';
import 'package:runiverse/core/theme/tokens/app_spacing.dart';
import 'package:runiverse/core/theme/tokens/app_typography.dart';
import 'package:runiverse/core/widgets/app_button.dart';

/// 시작 방식 선택 (S02.5).
///
/// ## 카카오·애플을 지우지 않는다
///
/// 정본 와이어프레임에 셋 다 있다. 지우면 화면이 정본에서 멀어지고, 나중에 붙일 때
/// 레이아웃을 다시 잡아야 한다. **회색으로 잠그지도 않는다** — 잠긴 버튼이 둘이면
/// 앱이 미완성으로 읽힌다. 눌리고, 준비 중임을 알린다.
/// (CLAUDE.md가 피드·대회일정 탭에 정한 원칙과 같다.)
class AuthIntroPage extends StatelessWidget {
  const AuthIntroPage({super.key});

  void _notReady(BuildContext context) {
    final colors = context.appColors;

    // 이전 안내가 남아 있으면 겹쳐서 쌓인다. 하나만 띄운다.
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            AppStrings.authSocialComingSoon,
            style: AppTypography.body.copyWith(color: colors.textPrimary),
          ),
          backgroundColor: colors.bgElevated,
          behavior: SnackBarBehavior.floating,
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.md),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.space5,
            AppSpacing.space8,
            AppSpacing.space5,
            AppSpacing.space4,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                AppStrings.authIntroTitle,
                style: AppTypography.h1.copyWith(color: colors.textPrimary),
              ),
              const SizedBox(height: AppSpacing.space3),
              Text(
                AppStrings.authIntroSubtitle,
                style: AppTypography.body.copyWith(color: colors.textSecondary),
              ),

              const Spacer(),

              // 이메일이 유일하게 동작하는 길이라 primary를 준다.
              // primary는 화면당 하나다 — 나머지 둘은 secondary로 둔다.
              AppButton(
                label: AppStrings.authEmail,
                onPressed: () => context.push(AppRoutes.signIn),
              ),
              const SizedBox(height: AppSpacing.space3),
              AppButton(
                label: AppStrings.authKakao,
                variant: AppButtonVariant.secondary,
                onPressed: () => _notReady(context),
              ),
              const SizedBox(height: AppSpacing.space3),
              AppButton(
                label: AppStrings.authApple,
                variant: AppButtonVariant.secondary,
                onPressed: () => _notReady(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
