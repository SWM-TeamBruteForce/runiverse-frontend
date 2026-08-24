import 'package:runiverse/features/profile/domain/profile_summary.dart';

/// 프로필 요약을 가져온다.
///
/// [userId]를 **인자로 받는다.** 저장소에서 꺼내 쓰면 남의 프로필을 열어도
/// 내 것이 나온다 — 본인·타인이 같은 화면을 쓰기 때문에 여기서 갈려야 한다.
abstract interface class ProfileRepository {
  Future<ProfileSummary> fetch(String userId);

  /// 닉네임을 바꾸고 **서버가 확정한 값**을 돌려준다.
  ///
  /// `userId`를 받지 않는다. 서버 경로가 `me`라 본인 것만 바꿀 수 있고,
  /// 인자를 두면 남의 이름도 바꿀 수 있는 것처럼 읽힌다.
  ///
  /// 돌려받은 값을 그대로 쓴다. 보낸 값을 화면에 쓰면 서버가 다듬은 경우
  /// (앞뒤 공백 등) 화면과 서버가 갈라진다.
  Future<String> changeNickname(String nickname);

  /// 그 이름을 쓸 수 있는가. **물어보지 못했으면 `null`.**
  ///
  /// ⚠️ `false`와 `null`을 갈라야 한다. 묶으면 네트워크가 잠깐 끊긴 것 때문에
  /// 쓸 수 있는 이름이 거절된다.
  ///
  /// ## 온보딩에도 같은 것이 있다
  ///
  /// `OnboardingRepository.isNicknameAvailable`과 같은 API를 부른다.
  /// 그쪽을 가져다 쓰지 않는 이유는 **presentation이 다른 feature의
  /// presentation을 import할 수 없어서**다(provider가 거기 있다).
  /// 겹치는 것은 경로 한 줄과 응답 파싱뿐이고, 규칙은 [NicknameRule]을
  /// 함께 보는 것으로 맞춘다.
  Future<bool?> isNicknameAvailable(String nickname);

  /// 소개글·신체 정보를 바꾼다. **준 것만 보낸다** — 서버가 부분 수정이라
  /// 생략한 필드는 지금 값이 그대로 남는다.
  ///
  /// ## `null`과 빈 문자열이 다르다
  ///
  /// [introduction]이 `null`이면 **보내지 않는다**(그대로 둔다). `''`이면
  /// **지운다** — 서버가 빈 문자열을 삭제로 읽는다. 나머지 셋은 온보딩에서
  /// 필수라 지우는 개념이 없어 `null`은 언제나 "안 보냄"이다.
  ///
  /// ⚠️ **성별과 평균 페이스는 받지 않는다.** 성별은 화면에 내지 않기로 했고
  /// (기능정의서 `SETTING-PERSONAL-001`), 페이스는 서버가 러닝 기록으로
  /// 갱신한다. 인자로 두면 바꿀 수 있는 값처럼 읽힌다.
  Future<void> updateProfile({
    String? introduction,
    DateTime? birthday,
    double? weightKg,
    double? heightCm,
  });
}
