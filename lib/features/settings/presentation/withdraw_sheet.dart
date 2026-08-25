import 'package:flutter/material.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/extensions/app_colors.dart';
import 'package:runiverse/core/theme/tokens/app_radius.dart';
import 'package:runiverse/core/theme/tokens/app_spacing.dart';
import 'package:runiverse/core/theme/tokens/app_typography.dart';
import 'package:runiverse/core/widgets/app_button.dart';

/// 탈퇴를 한 번 더 묻는다. 확인하면 `true`.
///
/// ## 왜 다이얼로그가 아닌가
///
/// 로그아웃은 다이얼로그로 묻는다 — 되돌릴 수 있어서다. 탈퇴는 **되돌릴 수 없다.**
/// 무게가 다른 두 동작을 같은 모양으로 물으면, 다이얼로그를 습관적으로 넘기던
/// 손이 탈퇴도 넘긴다.
///
/// ## 사유를 받지 않는다
///
/// 기능정의서 `USR-ACCOUNT-001`의 제목은 *"탈퇴 사유 입력 후 계정 삭제"*지만
/// 본문의 입력 항목은 **Access Token과 탈퇴 확인 여부(boolean)뿐**이다.
/// 서버에 보낼 자리가 없다.
Future<bool> showWithdrawSheet(BuildContext context) async {
  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    // 잘못 눌러 열렸으면 밖을 눌러 닫을 수 있어야 한다. 막아 세우는 관문이 아니다.
    isScrollControlled: true,
    builder: (context) => const _WithdrawSheet(),
  );
  return confirmed ?? false;
}

class _WithdrawSheet extends StatelessWidget {
  const _WithdrawSheet();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.bgElevated,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        AppSpacing.space5,
        AppSpacing.space4,
        AppSpacing.space5,
        // 제스처 바에 버튼이 걸리지 않게 띄운다.
        AppSpacing.space5 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 손잡이. 아래로 쓸어 닫을 수 있다는 표시다.
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: colors.borderStrong,
                borderRadius: AppRadius.full,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.space5),
          Text(
            AppStrings.withdrawTitle,
            style: AppTypography.h2.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.space3),
          Text(
            AppStrings.withdrawBody,
            style: AppTypography.body.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.space6),
          // ⚠️ **취소가 먼저다.** 되돌릴 수 없는 쪽을 엄지 자리에 두지 않는다.
          AppButton(
            label: AppStrings.settingsCancel,
            variant: AppButtonVariant.secondary,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          const SizedBox(height: AppSpacing.space2),
          AppButton(
            label: AppStrings.withdrawConfirm,
            variant: AppButtonVariant.danger,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
  }
}
