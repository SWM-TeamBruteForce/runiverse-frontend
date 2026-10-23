import 'package:runiverse/features/profile/domain/picked_image.dart';

/// 내 프로필 사진을 다루는 통로.
///
/// ## 왜 `userId`를 받지 않는가
///
/// 서버 경로는 `/users/{userId}/profile-image`지만, 앱이 다루는 것은 **언제나 내
/// 사진**이다(서버도 `@SelfOnly`로 막는다). 화면이 `userId`를 들고 다니면
/// **어디선가 남의 것을 넘길 수 있는 모양**이 되는데, 그렇게 부를 수 있는 API가 아니다.
/// 구현체가 토큰과 함께 저장소에서 읽는다.
///
/// 남의 프로필(S20)이 생기면 그때 조회용 메서드를 따로 연다 — 조회만 인증이
/// 필요 없어서, 같은 메서드에 `userId?`를 얹으면 권한이 다른 둘이 한 이름에 섞인다.
abstract interface class ProfileImageRepository {
  /// 지금 사진의 열람 주소. 사진을 올린 적이 없으면 `null`.
  ///
  /// ⚠️ **돌려주는 주소는 만료된다.** presigned URL이라 오래 들고 있으면 403이
  /// 되고, 화면에는 깨진 이미지로 보인다. 캐시하지 말고 화면이 열릴 때 다시 묻는다.
  Future<String?> fetchUrl();

  /// 올린다. 세 단계(발급 → S3 → 확정)를 구현체가 묶는다.
  ///
  /// 새 주소를 돌려주지 않는다 — 확정 응답에 오는 것은 주소가 아니라 키다.
  /// 주소가 필요하면 [fetchUrl]을 다시 부른다.
  Future<void> upload(PickedImage image);

  /// 지운다. 기본 이미지로 돌아간다.
  Future<void> remove();
}
