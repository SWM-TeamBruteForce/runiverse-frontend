import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/extensions/app_colors.dart';
import 'package:runiverse/core/theme/tokens/app_radius.dart';
import 'package:runiverse/core/theme/tokens/app_spacing.dart';
import 'package:runiverse/core/theme/tokens/app_typography.dart';
import 'package:runiverse/core/widgets/app_button.dart';

/// 프로필이 없는 사람을 막아서는 관문.
///
/// ## ⚠️ 닫히지 않는다
///
/// 스크림 · 드래그 · 뒤로가기 **어느 것으로도 닫히지 않는다.** 프로필 없이는
/// 매칭도 기록도 돌아가지 않아 앱을 쓸 수 없기 때문이다 — 안내가 아니라 관문이다.
///
/// 나가는 문은 [onStart] 하나뿐이고, 그 끝에서 프로필을 채우면 관문이 사라진다.
/// **닫히지 않는다는 것을 문구가 먼저 밝힌다** — 닫으려다 안 되는 것과 처음부터
/// 알고 있는 것은 다르다.
///
/// ## 왜 `core/widgets`에 있는가
///
/// 홈(S05)과 프로필 탭(S22) **두 feature가 함께 쓴다.** 어느 한쪽의
/// `presentation`에 두면 다른 쪽이 그것을 import해야 하고, 그것은
/// 금지된 방향이다(CLAUDE.md). 색·문구는 전부 토큰이라 여기 두는 데 무리가 없다.
///
/// ## 부르는 쪽의 책임
///
/// **언제 띄울지는 화면이 정한다.** 이 함수는 `isOnboarded`를 보지 않는다 —
/// 보게 하면 `core`가 인증 상태를 알아야 하고, 그것도 금지된 방향이다.
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
    // 스크림을 눌러도, 끌어내려도 닫히지 않는다.
    isDismissible: false,
    enableDrag: false,
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

    // 안드로이드 뒤로가기도 막는다. `isDismissible`만으로는 뒤로가기가 통과한다.
    return PopScope(
      canPop: false,
      child: SafeArea(
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
            AppSpacing.space6,
            AppSpacing.space5,
            AppSpacing.space5,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ⚠️ 끌어내리는 손잡이를 두지 않는다. 끌리지 않는데 손잡이가
              // 있으면 **고장 난 것처럼** 읽힌다.
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
            ],
          ),
        ),
      ),
    );
  }
}
