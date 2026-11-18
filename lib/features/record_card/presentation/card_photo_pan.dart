import 'dart:io';

import 'package:flutter/material.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/features/record_card/domain/card_photo_draft.dart';

/// 칸에 `BoxFit.cover`로 앉혔을 때 **축마다 넘치는 픽셀.**
///
/// 넘치지 않거나 크기를 모르면 0이다. 0인 축은 사진을 다 쓰고 있어 **밀 데가
/// 없다** — 부르는 쪽이 그 축의 끌기를 달지 않는 근거다.
///
/// ## ⚠️ 축이 비율에 따라 바뀐다
///
/// 커버(412:200)는 가로로 넓어 사진이 거의 다 위아래로 넘쳤다. 9:16은 세로로
/// 길어 **3:4짜리 세로 사진조차 좌우로 넘친다**(0.75 > 0.5625). 한 축만 보면
/// 끌어도 아무 일이 없는 화면이 된다.
({double x, double y}) photoOverflow({required Size box, required Size image}) {
  if (image.width <= 0 || image.height <= 0) return (x: 0, y: 0);
  if (box.width <= 0 || box.height <= 0) return (x: 0, y: 0);

  // 칸보다 납작하면 높이를 맞추고 폭이 넘친다. 아니면 폭을 맞추고 높이가 넘친다.
  if (image.width / image.height > box.width / box.height) {
    final width = box.height * image.width / image.height;
    return (x: width - box.width, y: 0);
  }
  final height = box.width * image.height / image.width;
  return (x: 0, y: height - box.height);
}

/// 9:16 칸 안에서 사진을 **넘치는 축으로** 미는 미리보기.
///
/// ## ⚠️ 보이는 것과 자르는 것이 같은 셈이어야 한다
///
/// `BoxFit.cover` + `Alignment(alignX, alignY)`로 그리고, 저장할 때
/// `CoverCrop.rect`가 같은 값으로 자른다. 여기와 거기가 갈라지면 **보던 것과
/// 다른 그림이 저장된다.**
class CardPhotoPan extends StatefulWidget {
  const CardPhotoPan({
    required this.photo,
    required this.onAlign,
    this.enabled = true,
    super.key,
  });

  /// ⚠️ **새로 고른 사진만 받는다.** 이미 올린 사진은 9:16으로 잘려 나가
  /// 틀 안에서 옮길 데가 없다 — 끌기를 달면 아무 일도 없는 제스처가 된다.
  final PickedPhoto photo;

  /// 민 위치를 밖으로 알린다. **움직인 축만** 준다.
  final void Function({double? alignX, double? alignY}) onAlign;

  /// 끌 수 있나. 넘기는 중이거나 저장 중이면 끈다.
  final bool enabled;

  @override
  State<CardPhotoPan> createState() => _CardPhotoPanState();
}

class _CardPhotoPanState extends State<CardPhotoPan> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  Size? _imageSize;

  /// ⚠️ **방금 보낸 값.** 한 프레임에 끌기가 여러 번 오면 `widget.photo`가 아직
  /// 옛 값이라, 그 값에서 셈하면 끈 거리가 사라진다.
  double? _dragging;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(CardPhotoPan old) {
    super.didUpdateWidget(old);
    if (old.photo.image.path != widget.photo.image.path) {
      _imageSize = null;
      _resolve();
    }
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  void _detach() {
    final listener = _listener;
    if (listener != null) _stream?.removeListener(listener);
    _stream = null;
    _listener = null;
  }

  void _resolve() {
    _detach();
    final listener = ImageStreamListener(_onImage, onError: _onError);
    _listener = listener;
    _stream = FileImage(
      File(widget.photo.image.path),
    ).resolve(ImageConfiguration.empty)..addListener(listener);
  }

  void _onImage(ImageInfo info, bool _) {
    final size = Size(
      info.image.width.toDouble(),
      info.image.height.toDouble(),
    );
    // ⚠️ 받은 쪽이 놓아야 한다. 크기만 읽고 바로 놓는다.
    info.dispose();
    if (!mounted) return;
    setState(() => _imageSize = size);
  }

  /// 못 읽었다. **크기를 모르는 채로 둔다** — 끌기가 안 달리고, 못 읽은 사진은
  /// `Image.file`의 `errorBuilder`가 말한다. 던지면 작성 중에 앱이 죽는다.
  void _onError(Object error, StackTrace? stack) {}

  @override
  Widget build(BuildContext context) {
    final image = Image.file(
      File(widget.photo.image.path),
      fit: BoxFit.cover,
      alignment: Alignment(widget.photo.alignX, widget.photo.alignY),
      errorBuilder: (context, _, _) => const _Unreadable(),
    );

    return LayoutBuilder(
      builder: (context, box) {
        final size = _imageSize;
        if (!widget.enabled || size == null) return image;

        final over = photoOverflow(box: box.biggest, image: size);
        // 어느 쪽으로도 넘치지 않는다 — 꼭 맞는 9:16이라 밀 데가 없다.
        if (over.x <= 0 && over.y <= 0) return image;

        return over.x >= over.y
            ? _horizontal(image, over.x)
            : _vertical(image, over.y);
      },
    );
  }

  Widget _horizontal(Widget image, double overflow) => GestureDetector(
    onHorizontalDragUpdate: (details) {
      // 왼쪽으로 끌면 사진이 밀려 **오른쪽**이 보인다.
      final from = _dragging ?? widget.photo.alignX;
      final next = (from - details.delta.dx / (overflow / 2)).clamp(-1.0, 1.0);
      if (next == from) return;
      _dragging = next;
      widget.onAlign(alignX: next);
    },
    onHorizontalDragEnd: (_) => _dragging = null,
    onHorizontalDragCancel: () => _dragging = null,
    child: image,
  );

  Widget _vertical(Widget image, double overflow) => GestureDetector(
    onVerticalDragUpdate: (details) {
      // 위로 끌면 사진이 올라가 **아랫부분**이 보인다.
      final from = _dragging ?? widget.photo.alignY;
      final next = (from - details.delta.dy / (overflow / 2)).clamp(-1.0, 1.0);
      if (next == from) return;
      _dragging = next;
      widget.onAlign(alignY: next);
    },
    onVerticalDragEnd: (_) => _dragging = null,
    onVerticalDragCancel: () => _dragging = null,
    child: image,
  );
}

/// 못 읽은 사진. **고르던 사이에 OS가 임시 폴더를 비운 자리다.**
class _Unreadable extends StatelessWidget {
  const _Unreadable();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.space4),
      child: Text(
        AppStrings.recordCardPhotoUnreadable,
        textAlign: TextAlign.center,
        style: AppTypographyV2.body18.copyWith(
          color: context.appColorsV2.textSecondary,
        ),
      ),
    ),
  );
}
