import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/extensions/app_colors.dart';
import 'package:runiverse/core/theme/tokens/app_spacing.dart';
import 'package:runiverse/features/profile/domain/profile_image_failure.dart';
import 'package:runiverse/features/profile/presentation/profile_image_provider.dart';
import 'package:runiverse/features/profile/presentation/profile_image_state.dart';
import 'package:runiverse/features/profile/presentation/profile_provider.dart';
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
  const ProfileAvatar({this.url, this.editable = false, super.key});

  /// 지금 사진의 열람 주소. **밖에서 받는다.**
  ///
  /// 스스로 받아오지 않는 이유가 둘이다. 프로필 요약(`GET /users/{userId}`)이
  /// 이미 같은 값을 주므로 **같은 것을 두 번 받게 되고**, 무엇보다
  /// `fetchUrl()`은 저장소의 `userId`를 쓰기 때문에 **타인 프로필에서도
  /// 내 사진을 가져온다.** 누구의 사진인지는 부르는 쪽이 안다.
  ///
  /// ⚠️ 만료되는 주소다. 실패하면 기본 아이콘으로 조용히 물러선다.
  final String? url;

  /// 편집 모드인가. **`false`면 눌리지 않고 표시도 없다.**
  ///
  /// 늘 눌리게 두면 "지금 바꿀 수 있다"가 화면 어디에도 드러나지 않아
  /// **눌러본 사람만** 알게 된다. 헤더의 ✎가 그 문이다.
  final bool editable;

  static const size = 88.0;

  /// 편집 배지 지름. ⚠️ 정확한 값은 디자인 확인이 필요하다.
  static const badgeSize = AppSpacing.space6;

  @override
  ConsumerState<ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends ConsumerState<ProfileAvatar> {
  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    // 컨트롤러에서는 **바꾸는 중인지**만 본다. 주소는 밖에서 받는다.
    final state = ref.watch(profileImageControllerProvider);
    final ready = state is ProfileImageReady ? state : null;
    final url = widget.url;

    final avatar = Semantics(
      // 편집 모드가 아니면 **버튼이라고 읽히지 않아야 한다** — 눌러도 아무 일이
      // 없는 것을 버튼이라고 알리면 스크린리더 사용자만 헛걸음한다.
      button: widget.editable,
      label: widget.editable ? AppStrings.profilePhotoChangeLabel : null,
      child: GestureDetector(
        // 도는 동안 또 누르면 요청이 겹친다. 뒤에 끝난 것이 이기는데,
        // 어느 쪽이 뒤인지는 알 수 없다.
        onTap: (!widget.editable || (ready?.busy ?? false))
            ? null
            : () => _open(url != null),
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

    if (!widget.editable) return avatar;

    // 배지가 원 밖으로 조금 나가지 않도록 크기를 아바타에 맞춰 잡는다.
    return SizedBox(
      width: ProfileAvatar.size,
      height: ProfileAvatar.size,
      child: Stack(clipBehavior: Clip.none, children: [avatar, _badge(colors)]),
    );
  }

  /// 아바타 위에 얹는 작은 표시. **`ClipOval` 밖에 둔다** — 안에 두면 잘린다.
  Widget _badge(AppColors colors) => Positioned(
    right: 0,
    bottom: 0,
    child: Container(
      width: ProfileAvatar.badgeSize,
      height: ProfileAvatar.badgeSize,
      decoration: BoxDecoration(
        color: colors.bgSurface,
        shape: BoxShape.circle,
        border: Border.all(color: colors.borderDefault),
      ),
      // ✎가 아니라 카메라다. 헤더의 ✎와 같은 아이콘을 쓰면 **같은 것을 두 번
      // 그린 것처럼 보이고**, 이 자리가 뜻하는 것은 "프로필 편집"이 아니라
      // "사진을 바꾼다"로 더 좁다.
      child: Icon(
        LucideIcons.camera,
        size: AppSpacing.space4,
        color: colors.textSecondary,
      ),
    ),
  );

  Future<void> _open(bool hasPhoto) async {
    final action = await showProfilePhotoSheet(context, hasPhoto: hasPhoto);
    // 취소했다. 아무 일도 일어나지 않는다.
    if (action == null || !mounted) return;

    final controller = ref.read(profileImageControllerProvider.notifier);
    final failure = switch (action) {
      ProfilePhotoAction.pick => await controller.change(),
      ProfilePhotoAction.reset => await controller.remove(),
    };

    // **새 주소는 서버만 안다.** 다시 받지 않으면 아바타가 옛 사진을 문다.
    if (failure == null) {
      await ref.read(profileSummaryControllerProvider.notifier).reload();
    }
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
