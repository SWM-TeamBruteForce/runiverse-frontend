import 'package:runiverse/features/profile/domain/picked_image.dart';

/// 고른 사진에서 **커버 칸에 보이는 부분만** 잘라 새 한 장으로 만든다.
///
/// ## 왜 올리기 전에 자르는가
///
/// 서버는 사진 한 장만 받고, 어디가 보일지 담을 자리가 없다. 사용자가
/// 미리보기에서 옮긴 위치를 지키려면 **그 위치대로 잘라서** 올려야 한다.
///
/// ## ⚠️ 돌려주는 것은 새 [PickedImage]다
///
/// 자르면 바이트가 바뀐다. 서명은 [PickedImage.sizeBytes]로 받으므로 원래 값을
/// 들고 가면 **403**이 된다. 잘라 낸 파일을 다시 잰 값을 돌려준다.
abstract interface class ImageCropper {
  /// [image]를 [aspectRatio](폭/높이)에 맞춰 자른다. 세로 위치는 [alignY]
  /// (-1 위 · 0 가운데 · 1 아래)다.
  ///
  /// 읽지 못하면 `ProfileImageException`을 던진다. **자르지 않은 채로 올리지
  /// 않는다** — 보던 것과 다른 그림이 올라간다.
  Future<PickedImage> crop(
    PickedImage image, {
    required double aspectRatio,
    required double alignY,
  });

  /// [crop]이 만든 파일을 지운다. **올리기가 끝나면 성공이든 실패든 부른다.**
  ///
  /// 다시 저장하면 원본에서 새로 자르므로 남겨 둘 이유가 없다. 지우지 못해도
  /// 던지지 않는다 — 임시 폴더라 OS가 결국 비운다.
  Future<void> discard(PickedImage cropped);
}
