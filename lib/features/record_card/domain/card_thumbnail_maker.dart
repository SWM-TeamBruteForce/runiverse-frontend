import 'package:runiverse/features/profile/domain/picked_image.dart';

/// 자른 9:16 한 장에서 **작은 사본**을 만든다.
///
/// ## 왜 앱이 만드나
///
/// 서버에 썸네일 파생본이 없다(`card_photo_key` 원본 하나뿐). 달력 한 화면에
/// 썸네일이 최대 31장, 분기 보기에서는 92장까지 걸려 원본을 내리면 쓸 만하지
/// 않다. 앱이 이미 9:16으로 자르므로 **여기서 한 번 더 줄이는 것이 가장 싸다**
/// — 서버가 Lambda 같은 이미지 파이프라인을 세우지 않아도 된다
/// (`docs/notes/2026-11-16-record-card-backend-questions.md` 4번).
abstract interface class CardThumbnailMaker {
  /// 썸네일 상한. 서버가 정한 값이다(연동 가이드 3절).
  static const maxBytes = 1024 * 1024;

  /// 긴 변 길이. 9:16이라 **긴 변은 세로**다.
  static const longEdge = 320;

  /// 짧은 변. `320 × 9 / 16`이다.
  static const shortEdge = 180;

  /// [croppedPath]에서 썸네일을 만든다. **크기와 형식을 함께 준다** —
  /// 9-1이 `thumbnailFileSizeBytes`를 요구하고(연동 가이드 3절), 경로만
  /// 주면 화면 쪽이 `dart:io`로 파일을 재야 한다.
  ///
  /// ## ⚠️ 실패하면 던지지 않고 `null`이다
  ///
  /// 그때는 저장이 **크롭본을 썸네일 자리에 넣는다**(1MB 이하일 때). 여기서
  /// 던지면 사진 한 장 때문에 카드가 아예 안 만들어진다.
  Future<PickedImage?> make(String croppedPath);
}
