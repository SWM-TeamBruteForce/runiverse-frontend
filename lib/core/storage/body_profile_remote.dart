import 'package:runiverse/core/storage/body_profile_store.dart';

/// 서버가 아는 신체 정보를 읽는 곳. `GET /api/v1/users/me/profile` (명세 51번).
///
/// ## 왜 `core`에 포트만 두나
///
/// 부르는 쪽이 [BodyProfileStore]와 같은 자리다 — **러닝 화면과 프로필 편집이
/// 함께 본다.** 둘 중 한 feature에 두면 다른 쪽이 그것을 import해야 한다.
///
/// 구현은 `features/profile`에 있다. 401이면 토큰을 갱신하고 다시 부르는
/// 처리가 거기 저장소에 이미 있어서, 여기에 다시 쓰면 그 규칙이 두 벌이 된다.
/// 그래서 `ProfileRepository`가 이 포트를 함께 구현하고, **`main.dart`가
/// 연결한다** — `analyticsProvider`와 같은 모양이다.
///
/// ## 소개글은 받지 않는다
///
/// 51번 응답에는 `introduction`·`gender`도 있다. 소개글은 프로필 요약
/// (`ProfileSummary`)이 이미 들고 있고 성별은 화면에 내지 않기로 했다
/// (기능정의서 `SETTING-PERSONAL-001`). **쓰지 않는 것을 포트에 두면
/// 이 값을 누가 쓰는지가 흐려진다.**
abstract interface class BodyProfileRemote {
  /// 서버가 가진 생년월일·키·몸무게.
  ///
  /// **온보딩 전이면 셋 다 `null`이다.** 그것은 실패가 아니라 "아직 없다"다 —
  /// 실패는 던져서 알린다. 둘을 구분해야 프로필 편집이 *불러오지 못한 것*과
  /// *설정한 적 없는 것*을 다르게 다룰 수 있다.
  ///
  /// ⚠️ **키·몸무게는 서버에서 소수 한 자리로 온다**(`weightKg: 70.5`).
  /// 앱의 선택기는 정수라 반올림해 담는다 — `as int`로 읽으면 터진다.
  Future<StoredBody> fetchBody();
}
