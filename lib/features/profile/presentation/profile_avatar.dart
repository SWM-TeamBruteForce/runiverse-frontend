import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/extensions/app_colors.dart';
import 'package:runiverse/core/theme/tokens/app_spacing.dart';
import 'package:runiverse/features/profile/domain/profile_image_failure.dart';
import 'package:runiverse/features/profile/presentation/profile_image_provider.dart';
import 'package:runiverse/features/profile/presentation/profile_image_state.dart';
import 'package:runiverse/features/profile/presentation/profile_photo_sheet.dart';

/// 프로필 사진. **누르면 바꿀 수 있다.**
///
/// ## 이니셜을 쓰지 않는다
///
/// 닉네임에서 글자를 뽑는 규칙(앞 2글자? 숫자는?)이 필요해지고, 그 규칙은 사진이
/// 붙는 순간 버려진다. 홈의 유도 카드와 **같은 글리프**를 써서 같은 사람을
/// 가리킨다는 것을 보인다.
///
/// ## 불러오는 동안에도 기본 아이콘을 그린다
///
/// 회전 표시를 넣지 않는다. **대부분은 사진을 올린 적이 없는 사람**이라,
/// 탭을 열 때마다 도는 표시가 떴다가 결국 같은 기본 아이콘으로 끝난다.
class ProfileAvatar extends ConsumerStatefulWidget {
  const ProfileAvatar({super.key});

  static const size = 88.0;

  @override
  ConsumerState<ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends ConsumerState<ProfileAvatar> {
  @override
  void initState() {
    super.initState();
    // 화면이 열릴 때 묻는다. 컨트롤러가 스스로 부르지 않는 이유는
    // **열람 주소가 만료되는 값**이어서다 — 언제 필요한지는 화면이 안다.
    ref.read(profileImageControllerProvider.notifier).load();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final state = ref.watch(profileImageControllerProvider);
    final ready = state is ProfileImageReady ? state : null;
    final url = ready?.url;

    return Semantics(
      button: true,
      label: AppStrings.profilePhotoChangeLabel,
      child: GestureDetector(
        // 도는 동안 또 누르면 요청이 겹친다. 뒤에 끝난 것이 이기는데,
        // 어느 쪽이 뒤인지는 알 수 없다.
        onTap: (ready?.busy ?? false) ? null : () => _open(url != null),
        child: Container(
          width: ProfileAvatar.size,
          height: ProfileAvatar.size,
          decoration: BoxDecoration(
            color: colors.bgElevated,
            shape: BoxShape.circle,
            border: Border.all(color: colors.borderDefault),
          ),
          child: ClipOval(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (url == null)
                  Icon(
                    LucideIcons.user,
                    size: AppSpacing.space8,
                    color: colors.textTertiary,
                  )
                else
                  Image.network(
                    url,
                    fit: BoxFit.cover,
                    // ⚠️ presigned 주소는 만료된다. 만료된 뒤에는 403이 오는데,
                    // 그때 깨진 이미지 아이콘을 두면 앱이 고장 난 것처럼 보인다.
                    // 기본 아이콘으로 조용히 돌아간다.
                    errorBuilder: (context, _, _) => Icon(
                      LucideIcons.user,
                      size: AppSpacing.space8,
                      color: colors.textTertiary,
                    ),
                  ),

                if (ready?.busy ?? false)
                  ColoredBox(
                    color: colors.bgScrim,
                    child: const Center(
                      child: SizedBox(
                        width: AppSpacing.space5,
                        height: AppSpacing.space5,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 시트를 띄우고 고른 것을 실행한다.
  Future<void> _open(bool hasPhoto) async {
    final action = await showProfilePhotoSheet(context, hasPhoto: hasPhoto);
    // 취소했다. 아무 일도 일어나지 않는다.
    if (action == null || !mounted) return;

    final controller = ref.read(profileImageControllerProvider.notifier);
    final failure = switch (action) {
      ProfilePhotoAction.pick => await controller.change(),
      ProfilePhotoAction.reset => await controller.remove(),
    };
    // 앨범을 다녀오는 사이에 화면이 사라졌을 수 있다.
    if (failure == null || !mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_messageOf(failure))));
  }

  /// 실패 이유를 화면 문구로 옮긴다.
  ///
  /// **앞의 셋만 갈라 말한다.** 나머지는 사용자가 할 수 있는 일이
  /// "다시 해보기" 하나라서, 어디서 막혔는지 말해도 쓸 데가 없다.
  static String _messageOf(ProfileImageFailure failure) => switch (failure) {
    ProfileImageFailure.unsupportedFormat => AppStrings.profilePhotoUnsupported,
    ProfileImageFailure.tooLarge => AppStrings.profilePhotoTooLarge,
    ProfileImageFailure.sessionExpired => AppStrings.profileSubmitExpired,
    _ => AppStrings.profilePhotoFailed,
  };
}
