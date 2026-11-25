import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:runiverse/features/profile/domain/picked_image.dart';
import 'package:runiverse/features/record_card/domain/card_thumbnail_maker.dart';

/// `flutter_image_compress`로 줄이는 [CardThumbnailMaker].
///
/// ## ⚠️ 받는 것은 **이미 9:16으로 자른** 한 장이다
///
/// 비율을 다시 맞추지 않는다 — `UiImageCropper`가 끝냈다. 여기서는 **크기만**
/// 줄인다. `minWidth`·`minHeight`는 플러그인에게 "이보다 작게 줄이지 말라"는
/// 뜻이라, 9:16에 그대로 주면 긴 변이 320px에 맞는다.
///
/// ## ⚠️ 던지지 않는다
///
/// 썸네일이 없으면 달력이 원본을 쓴다. 느리지만 **보인다** — 사진 한 장
/// 때문에 카드가 아예 안 만들어지는 것이 더 나쁘다.
class CompressedCardThumbnailMaker implements CardThumbnailMaker {
  const CompressedCardThumbnailMaker();

  @override
  Future<PickedImage?> make(String croppedPath) async {
    try {
      final bytes = await FlutterImageCompress.compressWithFile(
        croppedPath,
        minWidth: CardThumbnailMaker.shortEdge,
        minHeight: CardThumbnailMaker.longEdge,
        quality: 80,
        // 자른 파일은 `dart:ui`가 만든 것이라 회전 정보가 없다. 켜 두면
        // 플러그인이 없는 각도를 찾다가 느려질 뿐이다.
        autoCorrectionAngle: false,
        keepExif: false,
        format: CompressFormat.jpeg,
      );
      if (bytes == null) return null;

      final name =
          'runiverse_card_thumb_'
          '${DateTime.now().microsecondsSinceEpoch}';
      final file = File('${Directory.systemTemp.path}/$name.jpg');
      await file.writeAsBytes(bytes, flush: true);
      // 바이트 수를 여기서 준다 — 방금 쓴 길이라 다시 잴 일이 없다.
      return PickedImage.validated(path: file.path, sizeBytes: bytes.length);
    } on Object {
      return null;
    }
  }
}
