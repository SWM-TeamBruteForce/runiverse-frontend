import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/widgets/v2/app_icon.dart';
import 'package:runiverse/features/profile/domain/pending_photo.dart';
import 'package:runiverse/features/profile/domain/profile_image_failure.dart';
import 'package:runiverse/features/profile/presentation/background_image_provider.dart';
import 'package:runiverse/features/profile/presentation/profile_image_state.dart';
import 'package:runiverse/features/profile/presentation/profile_photo_sheet.dart';

/// 편집 화면에서 배경을 고르는 자리. **프로필 화면의 커버와 같은 모양이다** —
/// 같은 비율(2:1)로 화면 폭을 다 쓰고, 아바타가 아래변에 걸친다.
///
/// ⚠️ **둥근 모서리도 좌우 여백도 없다.** 넣으면 "카드에 담긴 미리보기"가 되어
/// 프로필 화면의 커버와 다른 물건으로 보인다. 바꾸는 자리와 보이는 자리가
/// 닮아야 무엇을 바꾸는지 안다.
///
/// ## ⚠️ 고르기만 한다. 올리지 않는다
///
/// 프로필 사진과 같은 규칙이다 — 고른 것은 [PendingPhoto]로 화면이 들고 있다가
/// **저장 버튼이 보낸다.** 배경만 즉시 올리면 한 화면에 규칙이 둘이 되고,
/// 사용자는 무엇이 이미 갔는지 알 수 없다.
class BackgroundPicker extends ConsumerWidget {
  const BackgroundPicker({
    required this.onPending,
    required this.onFailure,
    this.pending,
    super.key,
  });

  /// 아직 안 보낸 변경. 있으면 **그것이 지금 화면의 배경이다.**
  final PendingPhoto? pending;

  /// 고른 것을 밖으로 알린다. **취소하면 부르지 않는다.**
  final ValueChanged<PendingPhoto> onPending;

  /// 고르지 못한 이유. **화면이 문구를 띄운다.**
  ///
  /// ⚠️ 삼키면 미리보기도 안 바뀌고 문구도 안 떠서, 사용자는 같은 사진을 다시
  /// 고른다. 프로필 사진은 이미 같은 자리에서 말해 준다.
  final ValueChanged<ProfileImageFailure> onFailure;

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
      label: AppStrings.profileEditBackground,
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
          child: ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: colors.bgElevated),
                // ⚠️ **`cover`다 — 커버와 같아야 한다.** 다르면
                // 고르는 자리와 보이는 자리가 다른 그림을 준다(`ProfileCover`).
                if (picked != null)
                  // 막 고른 사진. 아직 올라가지 않았으니 주소가 없다.
                  _DraggableCover(
                    picked: picked,
                    // 도는 동안 옮기면 올라가는 것과 화면이 갈린다.
                    enabled: !(ready?.busy ?? false),
                    onPending: onPending,
                  )
                else if (url != null)
                  Image.network(
                    url,
                    fit: BoxFit.cover,
                    // ⚠️ 여기서는 다시 받지 않는다. 커버가 이미 그 일을 하고,
                    // 두 군데서 부르면 "한 번만"이 두 번이 된다.
                    errorBuilder: (context, error, stack) =>
                        const SizedBox.shrink(),
                  ),

                // ⚠️ **누를 수 있다고 말하는 자리다.** 없으면 그냥 사각형이라
                // 아무도 누르지 않는다 — 아바타가 카메라 배지로 같은 일을 한다.
                // 사진 위에 얹히므로 **어두운 동그라미**에 담는다.
                //
                // ⚠️ **글자가 없다**(2026-10-22 요청). 그래서 낭독기가 읽을 것은
                // 바깥 [Semantics] 라벨뿐이다 — 그것을 지우면 눈으로만 쓸 수
                // 있는 버튼이 된다.
                Align(
                  alignment: Alignment.bottomRight,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.space3),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.coverScrim,
                        borderRadius: AppRadius.full,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.space2),
                        child: AppIcon(
                          AppIcons.camera,
                          size: AppSpacing.space5,
                          color: colors.textPrimary,
                        ),
                      ),
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
        final failure = picked.failure;
        if (failure != null) {
          onFailure(failure);
          return;
        }
        final image = picked.image;
        // 취소는 실패가 아니다. 둘 다 `null`이면 아무 일도 없었던 것이다.
        if (image != null) onPending(PhotoPicked(image));
      case ProfilePhotoAction.reset:
        onPending(const PhotoRemoved());
    }
  }
}

/// 막 고른 사진. **위아래로 끌어 보일 부분을 고른다.**
///
/// 저장하면 이 위치대로 잘려 올라간다(`BackgroundImageController.apply`).
/// 이미 올라간 사진은 원본이 없어 옮길 수 없다 — 다시 골라야 한다.
///
/// ## 손가락을 따라 움직인다
///
/// 끈 거리를 **넘친 높이**로 나눠 위치로 바꾼다. 칸 높이로 나누면 긴 사진일수록
/// 사진이 손가락보다 빨리 움직인다. 넘친 높이를 알려면 사진 크기가 필요해서,
/// 사진을 한 번 읽어 크기만 받는다.
///
/// 칸보다 납작한 사진은 위아래로 넘치지 않아 끌 것이 없다.
class _DraggableCover extends StatefulWidget {
  const _DraggableCover({
    required this.picked,
    required this.enabled,
    required this.onPending,
  });

  final PhotoPicked picked;
  final bool enabled;
  final ValueChanged<PendingPhoto> onPending;

  @override
  State<_DraggableCover> createState() => _DraggableCoverState();
}

class _DraggableCoverState extends State<_DraggableCover> {
  ImageStream? _stream;
  late final _listener = ImageStreamListener(_onImage);

  /// 사진의 픽셀 크기. 읽기 전에는 `null`이고, 그동안은 끌 수 없다.
  Size? _imageSize;

  /// 끄는 동안 마지막으로 보낸 위치. 끌지 않을 때는 `null`이다.
  double? _dragging;

  ImageProvider get _provider => FileImage(File(widget.picked.image.path));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(_DraggableCover old) {
    super.didUpdateWidget(old);
    if (old.picked.image.path != widget.picked.image.path) {
      _imageSize = null;
      _resolve();
    }
  }

  void _resolve() {
    final stream = _provider.resolve(createLocalImageConfiguration(context));
    if (stream.key == _stream?.key) return;
    _stream?.removeListener(_listener);
    _stream = stream..addListener(_listener);
  }

  void _onImage(ImageInfo info, bool synchronousCall) {
    final size = Size(
      info.image.width.toDouble(),
      info.image.height.toDouble(),
    );
    // ⚠️ 받은 쪽이 놓아야 한다. 크기만 읽고 바로 놓는다.
    info.dispose();
    if (!mounted) return;
    setState(() => _imageSize = size);
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final alignY = widget.picked.alignY;
    final image = Image.file(
      File(widget.picked.image.path),
      fit: BoxFit.cover,
      alignment: Alignment(0, alignY),
    );

    return LayoutBuilder(
      builder: (context, box) {
        final overflow = _overflow(box.biggest);
        if (!widget.enabled || overflow <= 0) return image;

        return GestureDetector(
          onVerticalDragUpdate: (details) {
            // ⚠️ **방금 보낸 값에서 이어 간다.** 한 프레임에 끌기가 여러 번
            // 오면 화면이 아직 다시 그려지지 않아 [alignY]가 옛 값이다 —
            // 그 값에서 셈하면 끈 거리가 사라진다.
            final from = _dragging ?? widget.picked.alignY;
            // 아래로 끌면 사진이 내려가 **윗부분**이 보인다.
            final next = (from - details.delta.dy / (overflow / 2)).clamp(
              -1.0,
              1.0,
            );
            if (next == from) return;
            _dragging = next;
            widget.onPending(PhotoPicked(widget.picked.image, alignY: next));
          },
          onVerticalDragEnd: (_) => _dragging = null,
          onVerticalDragCancel: () => _dragging = null,
          child: image,
        );
      },
    );
  }

  /// 칸 폭에 맞췄을 때 **위아래로 넘치는 높이**. 모르거나 넘치지 않으면 0이다.
  double _overflow(Size box) {
    final size = _imageSize;
    if (size == null || size.width == 0) return 0;
    return box.width * size.height / size.width - box.height;
  }
}
