import 'package:runiverse/features/onboarding/domain/onboarding_profile.dart';

/// 프로필 등록을 서버에 반영한다.
///
/// 화면은 이 타입에만 기대고, 실제로 누가 답하는지 모른다.
///
/// 실패는 전부 `OnboardingException`으로 던진다. 구현체는 자기 사정(HTTP 상태 코드,
/// 소켓 예외 등)을 밖으로 흘리지 않는다 — 흘리면 화면이 dio를 알아야 한다.
abstract interface class OnboardingRepository {
  /// 성공하면 그냥 돌아온다.
  ///
  /// **서버가 409 `ALREADY_ONBOARD`로 답해도 성공으로 친다.** 서버가 이미 했다고
  /// 하면 그게 사실이고 뒤처진 것은 로컬 플래그다. 호출자마다 이 예외를 성공으로
  /// 번역하게 두면 언젠가 한 곳을 빠뜨린다.
  Future<void> submit(OnboardingProfile profile);
}
