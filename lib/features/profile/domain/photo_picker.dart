import 'package:runiverse/features/profile/domain/picked_image.dart';

/// 사진 한 장을 어디서 고르는가.
///
/// ## 왜 인터페이스인가
///
/// 실제 구현은 앨범을 여는 **플랫폼 채널**을 부른다. 위젯 테스트 환경에는 채널이
/// 없어 `MissingPluginException`이 난다 — `OauthCodeSource`와 같은 이유로 가른다.
abstract interface class PhotoPicker {
  /// 고른 사진. **사용자가 취소하면 `null`이다.**
  ///
  /// 취소는 실패가 아니다. 예외로 만들면 화면이 "사진을 올리지 못했어요"를
  /// 띄우게 되는데, 그 사람은 올릴 생각을 접었을 뿐이다.
  ///
  /// 형식이나 크기가 조건에 맞지 않으면 `ProfileImageException`을 던진다.
  Future<PickedImage?> pick();
}
