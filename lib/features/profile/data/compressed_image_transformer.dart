import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:runiverse/features/profile/domain/image_transformer.dart';

/// 네이티브 디코더로 바꾸는 [ImageTransformer].
///
/// ## 왜 순수 Dart가 아닌가
///
/// `image` 패키지의 `bakeOrientation`·`copyResize`는 **원본을 먼저 통째로
/// 메모리에 펼친다.** 8160×6120이면 약 190MB이고, 메모리가 적은 폰에서 그대로
/// 앱이 멈춘다. 여기 구현은 안드로이드 `BitmapFactory.inSampleSize`·iOS
/// `CGImageSourceCreateThumbnailAtIndex`로 **처음부터 작게 읽는다.**
///
/// ## `autoCorrectionAngle`이 회전을 픽셀에 적용한다
///
/// EXIF의 회전 값을 읽어 실제로 돌려서 저장한다. 이 한 가지가 "사진이 누워서
/// 보인다"의 해답이고, [ImageTransformer] 주석이 말하는 **지우기 전에** 해야
/// 하는 일이다.
///
/// ## `keepExif: false`
///
/// 결과에 EXIF를 붙이지 않는다. 다만 이것만 믿지 않는다 — 부르는 쪽이
/// `ExifStripper`를 한 번 더 거친다. 위치가 한 번 새면 되돌릴 수 없는 값이라
/// 보증을 두 겹으로 둔다.
///
/// ## 결과는 언제나 JPEG다
///
/// ⚠️ **투명한 PNG를 올리면 투명한 자리가 검게 된다.** 아바타는 원으로 잘려
/// 면 위에 놓이므로 눈에 띄는 경우가 드물고, 형식을 하나로 고정하면 서명에
/// 싣는 `Content-Type`이 갈릴 일이 없다. 갈리면 S3가 403으로 돌려보낸다.
class CompressedImageTransformer implements ImageTransformer {
  const CompressedImageTransformer();

  @override
  Future<Uint8List?> toUploadJpeg(
    String path, {
    int shortEdge = 1080,
    int quality = 85,
  }) async {
    // `minWidth`·`minHeight`는 **최소 보장**이다. 둘 다 같은 값을 주면 비율을
    // 지키며 짧은 변이 그 값이 될 때까지 줄인다 — 8160×6120이면 1440×1080이다.
    final bytes = await FlutterImageCompress.compressWithFile(
      path,
      minWidth: shortEdge,
      minHeight: shortEdge,
      quality: quality,
      autoCorrectionAngle: true,
      keepExif: false,
      format: CompressFormat.jpeg,
    );
    // 알아보지 못했다. 부르는 쪽이 원본으로 물러서지 않는다.
    return bytes;
  }
}
