import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/widgets/v2/app_icon.dart';
import 'package:runiverse/features/profile/domain/pending_photo.dart';
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
  const ProfileAvatar({
    this.url,
    this.editable = false,
    this.pending,
    this.onPending,
    super.key,
  }) : assert(!editable || onPending != null, '누를 수 있으면 고른 것을 받을 곳이 있어야 한다');

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
  /// **눌러본 사람만** 알게 된다. 헤더의 `프로필 편집` 버튼이 그 문이다.
  final bool editable;

  /// 아직 저장하지 않은 변경. 있으면 [url] 대신 **이것을** 그린다.
  ///
  /// 고른 사진은 아직 어디에도 올라가지 않았으므로 주소가 없다. 로컬 파일을
  /// 그대로 그린다 — 안 그리면 고르고 나서 화면이 그대로라 **아무 일도 안
  /// 일어난 것처럼** 보인다.
  final PendingPhoto? pending;

  /// 고른 것을 밖으로 알린다. **취소하면 부르지 않는다.**
  ///
  /// ⚠️ **여기서 올리지 않는다.** 저장 버튼이 언제 보낼지 정하므로, 이 위젯은
  /// 무엇을 고르기로 했는지만 전한다.
  final ValueChanged<PendingPhoto>? onPending;

  static const size = 88.0;

  /// 편집 배지 지름. ⚠️ 정확한 값은 디자인 확인이 필요하다.
  static const badgeSize = AppSpacing.space6;

  @override
  ConsumerState<ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends ConsumerState<ProfileAvatar> {
  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;
    // 컨트롤러에서는 **바꾸는 중인지**만 본다. 주소는 밖에서 받는다.
    final state = ref.watch(profileImageControllerProvider);
    final ready = state is ProfileImageReady ? state : null;

    // 아직 안 보낸 변경이 있으면 **그것이 지금 화면의 사진이다.**
    final pending = widget.pending;
    final url = pending is PhotoRemoved ? null : widget.url;
    final localPath = pending is PhotoPicked ? pending.image.path : null;
    final hasPhoto = localPath != null || url != null;

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
            : () => _open(hasPhoto),
        child: Container(
          width: ProfileAvatar.size,
          height: ProfileAvatar.size,
          decoration: BoxDecoration(
            color: colors.bgElevated,
            shape: BoxShape.circle,
            // ⚠️ **`borderDefault`가 아니라 `borderStrong`이다.** 다크에서
            // `bgElevated`와 `borderDefault`가 둘 다 `neutral800`이라, 면을
            // 깐 원에 `borderDefault`를 두르면 **테두리가 면에 묻혀 사라진다.**
            // 코드에는 테두리가 있어서 눈으로만 보면 못 찾는다.
            //
            // 기록 탭의 그날 줄에서 같은 충돌을 겪었다(PR #126).
            border: Border.all(color: colors.borderStrong),
          ),
          child: ClipOval(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (localPath != null)
                  // 막 고른 사진. 아직 올라가지 않았으니 주소가 없다.
                  Image.file(
                    File(localPath),
                    fit: BoxFit.cover,
                    errorBuilder: (context, _, _) => AppIcon(
                      AppIcons.profile,
                      size: AppSpacing.space8,
                      color: colors.textTertiary,
                    ),
                  )
                else if (url == null)
                  AppIcon(
                    AppIcons.profile,
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
                    errorBuilder: (context, _, _) => AppIcon(
                      AppIcons.profile,
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
  Widget _badge(AppColorsV2 colors) => Positioned(
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
      // 카메라다. 이 자리가 뜻하는 것은 `프로필 편집`보다 좁은
      // "사진을 바꾼다"라서, 편집으로 가는 버튼과 같은 말을 하지 않는다.
      child: AppIcon(
        AppIcons.camera,
        size: AppSpacing.space4,
        color: colors.textSecondary,
      ),
    ),
  );

  /// 시트를 열고 **고른 것만** 밖으로 전한다.
  ///
  /// ⚠️ **여기서 서버를 부르지 않는다.** 보내는 시점은 저장 버튼이 정한다.
  /// 형식·크기가 맞지 않은 것만 **고르는 자리에서** 말해준다 — 저장까지
  /// 기다렸다 말하면 무엇 때문에 실패했는지 멀어진다.
  Future<void> _open(bool hasPhoto) async {
    final action = await showProfilePhotoSheet(context, hasPhoto: hasPhoto);
    // 취소했다. 아무 일도 일어나지 않는다.
    if (action == null || !mounted) return;

    if (action == ProfilePhotoAction.reset) {
      widget.onPending?.call(const PhotoRemoved());
      return;
    }

    final picked = await ref
        .read(profileImageControllerProvider.notifier)
        .pick();
    // 앨범을 다녀오는 사이에 화면이 사라졌을 수 있다.
    if (!mounted) return;

    final failure = picked.failure;
    if (failure != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_messageOf(failure))));
      return;
    }

    final image = picked.image;
    // 앨범에서 취소했다.
    if (image == null) return;

    widget.onPending?.call(PhotoPicked(image));
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
