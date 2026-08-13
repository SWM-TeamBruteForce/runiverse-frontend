import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/extensions/app_colors.dart';
import 'package:runiverse/core/theme/tokens/app_radius.dart';
import 'package:runiverse/core/theme/tokens/app_spacing.dart';
import 'package:runiverse/core/theme/tokens/app_typography.dart';
import 'package:runiverse/core/widgets/app_button.dart';

/// 프로필을 아직 안 채운 사람에게 띄우는 유도 시트 (S22).
///
/// ## 왜 카드가 아니라 시트인가
///
/// 홈에는 [ProfilePromptCard]가 있다. 홈은 **다른 볼거리가 있는 화면**이라 카드
/// 하나가 그 사이에 서면 된다. 프로필 탭은 다르다 — 값이 없으면 화면 전체가
/// 빈 상태라 카드를 하나 더 얹어도 빈 화면에 묻힌다.
///
/// ## ⚠️ 반드시 닫힌다
///
/// 스크림·드래그·`나중에` 셋 중 어느 것으로도 닫힌다. **닫히지 않는 안내는
/// 안내가 아니라 벽이다.** 강제로 채우게 하는 자리는 인증 직후의 프로필 등록이지
/// 여기가 아니다 — 여기는 이미 앱을 쓰고 있는 사람에게 권하는 자리다.
///
/// 닫혀도 막다른 길이 아니다. 헤더의 빈 상태 문구가 남아 있고, 홈의 카드도 그대로다.
Future<void> showProfilePromptSheet(
  BuildContext context, {
  required VoidCallback onStart,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: context.appColors.bgScrim,
    // 문구가 두 줄이라 기본 높이로는 CTA가 접힌다.
    isScrollControlled: true,
    builder: (context) => _PromptSheet(onStart: onStart),
  );
}

class _PromptSheet extends StatelessWidget {
  const _PromptSheet({required this.onStart});

  /// 시트를 닫은 **뒤에** 불린다. 닫기 전에 부르면 이동한 화면 위에
  /// 시트가 남아 뒤로 돌아왔을 때 다시 떠 있다.
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: colors.bgElevated,
          // 위 모서리만 둥글다. 아래는 화면 끝에 붙는다.
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.space5,
          AppSpacing.space3,
          AppSpacing.space5,
          AppSpacing.space5,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 끌어내릴 수 있다는 것을 보이는 손잡이. 없으면 스크림을 찾아
            // 누를 때까지 갇힌 것처럼 느껴진다.
            Center(
              child: Container(
                width: AppSpacing.space9,
                height: AppSpacing.space1,
                decoration: BoxDecoration(
                  color: colors.borderStrong,
                  borderRadius: AppRadius.full,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.space6),

            // 홈의 유도 카드와 **같은 글리프**다. 같은 일을 가리킨다.
            Container(
              width: AppSpacing.space9,
              height: AppSpacing.space9,
              decoration: BoxDecoration(
                color: colors.primaryMuted,
                borderRadius: AppRadius.full,
              ),
              child: Icon(
                LucideIcons.user,
                size: AppSpacing.space6,
                color: colors.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.space4),

            Text(
              AppStrings.profileSheetTitle,
              style: AppTypography.h2.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: AppSpacing.space3),
            Text(
              AppStrings.profileSheetBody,
              style: AppTypography.body.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.space7),

            AppButton(
              label: AppStrings.profileSheetCta,
              onPressed: () {
                // ⚠️ 닫고 나서 이동한다. 순서를 바꾸면 프로필 등록 화면 위에
                // 시트가 남는다.
                Navigator.of(context).pop();
                onStart();
              },
            ),
            const SizedBox(height: AppSpacing.space2),

            // 닫는 문을 **눈에 보이게** 둔다. 스크림만으로는 닫히는지 알 수 없다.
            // 가장 낮은 위계로 둬서 채우는 길과 무게가 겹치지 않게 한다.
            Align(
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  AppStrings.profileSheetDismiss,
                  style: AppTypography.caption.copyWith(
                    color: colors.textTertiary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
