import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/features/profile/domain/pending_photo.dart';
import 'package:runiverse/features/profile/presentation/background_image_provider.dart';
import 'package:runiverse/features/profile/presentation/profile_image_state.dart';
import 'package:runiverse/features/profile/presentation/profile_photo_sheet.dart';

/// 편집 화면에서 배경을 고르는 자리. 커버와 같은 비율(2:1)로 미리 보여 준다.
///
/// ## ⚠️ 고르기만 한다. 올리지 않는다
///
/// 프로필 사진과 같은 규칙이다 — 고른 것은 [PendingPhoto]로 화면이 들고 있다가
/// **저장 버튼이 보낸다.** 배경만 즉시 올리면 한 화면에 규칙이 둘이 되고,
/// 사용자는 무엇이 이미 갔는지 알 수 없다.
class BackgroundPicker extends ConsumerWidget {
  const BackgroundPicker({required this.onPending, this.pending, super.key});

  /// 아직 안 보낸 변경. 있으면 **그것이 지금 화면의 배경이다.**
  final PendingPhoto? pending;

  /// 고른 것을 밖으로 알린다. **취소하면 부르지 않는다.**
  final ValueChanged<PendingPhoto> onPending;

  /// 커버와 같은 비율(시안 412×200).
  static const _aspectRatio = 412 / 200;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColorsV2;
    final state = ref.watch(backgroundImageControllerProvider);
    final ready = state is ProfileImageReady ? state : null;

    final removed = pending is PhotoRemoved;
    final picked = pending is PhotoPicked ? pending! as PhotoPicked : null;
    final url = removed ? null : ready?.url;

    return Semantics(
      button: true,
      label: AppStrings.profileBackgroundLabel,
      child: GestureDetector(
        // 도는 동안 또 누르면 요청이 겹친다.
        onTap: (ready?.busy ?? false)
            ? null
            : () => _open(
                context,
                ref,
                hasBackground: picked != null || url != null,
              ),
        child: AspectRatio(
          aspectRatio: _aspectRatio,
          child: ClipRRect(
            borderRadius: AppRadius.md,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: colors.bgElevated),
                if (picked != null)
                  // 막 고른 사진. 아직 올라가지 않았으니 주소가 없다.
                  Image.file(File(picked.image.path), fit: BoxFit.cover)
                else if (url != null)
                  Image.network(
                    url,
                    fit: BoxFit.cover,
                    // ⚠️ 여기서는 다시 받지 않는다. 커버가 이미 그 일을 하고,
                    // 두 군데서 부르면 "한 번만"이 두 번이 된다.
                    errorBuilder: (context, error, stack) =>
                        const SizedBox.shrink(),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _open(
    BuildContext context,
    WidgetRef ref, {
    required bool hasBackground,
  }) async {
    final action = await showProfilePhotoSheet(
      context,
      hasPhoto: hasBackground,
      title: AppStrings.profileBackgroundSheetTitle,
    );
    if (action == null) return;

    switch (action) {
      case ProfilePhotoAction.pick:
        final picked = await ref
            .read(backgroundImageControllerProvider.notifier)
            .pick();
        final image = picked.image;
        // 취소는 실패가 아니다. 둘 다 `null`이면 아무 일도 없었던 것이다.
        if (image != null) onPending(PhotoPicked(image));
      case ProfilePhotoAction.reset:
        onPending(const PhotoRemoved());
    }
  }
}
