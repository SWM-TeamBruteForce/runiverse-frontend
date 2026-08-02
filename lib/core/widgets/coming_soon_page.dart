import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/extensions/app_colors.dart';
import 'package:runiverse/core/theme/tokens/app_radius.dart';
import 'package:runiverse/core/theme/tokens/app_spacing.dart';
import 'package:runiverse/core/theme/tokens/app_typography.dart';

/// 준비 중 화면 — 탭은 있으나 아직 만들지 않은 기능(피드·대회일정).
///
/// **탭을 숨기거나 비활성화하지 않는다.** 눌리고, 이 화면이 뜬다.
/// 없는 탭은 "이 앱엔 피드가 없다"로 읽히지만, 준비 중 화면은 "곧 생긴다"로 읽힌다.
///
/// 두 feature가 공유하므로 `features/` 안이 아니라 여기 있다.
/// 실제 화면이 생기면 라우터에서 해당 페이지로 갈아끼우면 된다.
class ComingSoonPage extends StatelessWidget {
  const ComingSoonPage({required this.featureName, super.key});

  /// 화면 상단에 표시할 기능 이름. 어느 탭에 들어왔는지 알려준다.
  final String featureName;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  featureName,
                  style: AppTypography.caption.copyWith(
                    color: colors.textTertiary,
                  ),
                ),
                const SizedBox(height: AppSpacing.space4),

                // 스케일 값을 크기로 쓴다. space10 = 64(원), space6 = 24(글리프).
                Container(
                  width: AppSpacing.space10,
                  height: AppSpacing.space10,
                  decoration: BoxDecoration(
                    color: colors.bgSurface,
                    borderRadius: AppRadius.full,
                    border: Border.all(color: colors.borderDefault),
                  ),
                  child: Icon(
                    LucideIcons.clock,
                    size: AppSpacing.space6,
                    color: colors.textTertiary,
                  ),
                ),
                const SizedBox(height: AppSpacing.space5),

                Text(
                  AppStrings.comingSoonTitle,
                  style: AppTypography.h2.copyWith(color: colors.textPrimary),
                ),
                const SizedBox(height: AppSpacing.space2),

                Text(
                  AppStrings.comingSoonBody,
                  textAlign: TextAlign.center,
                  style: AppTypography.body.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
