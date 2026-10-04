import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/theme/v2/app_sizes.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/core/widgets/v2/app_icon.dart';

/// 사진 시트에서 고른 것.
enum ProfilePhotoAction {
  /// 앨범에서 새로 고른다.
  pick,

  /// 지우고 기본 이미지로 돌아간다.
  reset,
}

/// 프로필 사진 시트를 띄우고 고른 것을 돌려준다. **취소하면 `null`.**
///
/// ## 왜 편집 화면이 아니라 시트인가
///
/// 정본(S22.1 프로필 편집)에는 `프로필 사진 변경`이 닉네임·한 줄 소개와 나란히
/// 있다. 그런데 **그 둘을 고칠 API가 아직 없다.** 편집 화면을 정본대로 만들면
/// 반응하지 않는 입력칸 두 개가 놓이고, 그것은 고장으로 읽힌다.
/// 지금 실제로 되는 것만 아바타 아래에 붙인다 — 수정 API가 오면 이 시트를 그대로
/// 편집 화면 안으로 옮긴다.
///
/// ## [hasPhoto]가 항목 수를 가른다
///
/// 사진이 없는 사람에게 `기본 이미지로`를 보이면, 눌러도 아무 일이 없다.
/// 이미 기본 이미지이기 때문이다.
Future<ProfilePhotoAction?> showProfilePhotoSheet(
  BuildContext context, {
  required bool hasPhoto,
}) {
  return showModalBottomSheet<ProfilePhotoAction>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: context.appColorsV2.bgScrim,
    builder: (context) => _PhotoSheet(hasPhoto: hasPhoto),
  );
}

class _PhotoSheet extends StatelessWidget {
  const _PhotoSheet({required this.hasPhoto});

  final bool hasPhoto;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: colors.bgElevated,
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
            const SizedBox(height: AppSpacing.space4),

            Text(
              AppStrings.profilePhotoSheetTitle,
              style: AppTypographyV2.heading06.copyWith(
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.space3),

            _SheetItem(
              icon: AppIcons.photo,
              label: AppStrings.profilePhotoPick,
              onTap: () => Navigator.of(context).pop(ProfilePhotoAction.pick),
            ),
            if (hasPhoto)
              _SheetItem(
                // ⚠️ **시안 아이콘 33개에 "지우기"가 없다.** `AppIcons.close`는
                // 닫기지 지우기가 아니라 뜻이 어긋난다. 디자이너 것이 오기
                // 전까지 Lucide 로 둔다 — `record_page`의 경고 아이콘과 같다.
                lucide: LucideIcons.trash2,
                label: AppStrings.profilePhotoReset,
                onTap: () =>
                    Navigator.of(context).pop(ProfilePhotoAction.reset),
              ),
          ],
        ),
      ),
    );
  }
}

/// 시트의 한 줄.
///
/// ⚠️ **글리프를 두 가지로 받는다.** [icon]은 시안 세트([AppIcons]), [lucide]는
/// 시안에 없어 아직 Lucide 로 남은 것이다. 둘 중 하나만 준다.
class _SheetItem extends StatelessWidget {
  const _SheetItem({
    required this.label,
    required this.onTap,
    this.icon,
    this.lucide,
  }) : assert(
         (icon == null) != (lucide == null),
         '글리프는 하나만 준다 — 시안 세트가 있으면 그쪽을 쓴다',
       );

  final String? icon;
  final IconData? lucide;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.md,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.space2,
          vertical: AppSpacing.space3,
        ),
        child: Row(
          children: [
            // 손가락이 닿는 칸을 44 아래로 내리지 않는다.
            SizedBox(
              width: AppSizes.touchDefault,
              child: icon != null
                  ? AppIcon(
                      icon!,
                      size: AppSpacing.space5,
                      color: colors.textSecondary,
                    )
                  : Icon(
                      lucide,
                      size: AppSpacing.space5,
                      color: colors.textSecondary,
                    ),
            ),
            Text(
              label,
              style: AppTypographyV2.body07.copyWith(color: colors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}
