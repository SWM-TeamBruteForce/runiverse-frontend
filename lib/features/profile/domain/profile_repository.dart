import 'package:runiverse/features/profile/domain/profile_summary.dart';

/// 프로필 요약을 가져온다.
///
/// [userId]를 **인자로 받는다.** 저장소에서 꺼내 쓰면 남의 프로필을 열어도
/// 내 것이 나온다 — 본인·타인이 같은 화면을 쓰기 때문에 여기서 갈려야 한다.
abstract interface class ProfileRepository {
  Future<ProfileSummary> fetch(String userId);

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
