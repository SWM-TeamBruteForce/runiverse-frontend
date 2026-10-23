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
  /// **서버가 409 `ALREADY_ONBOARDED`로 답해도 성공으로 친다.** 서버가 이미 했다고
  /// 하면 그게 사실이고 뒤처진 것은 로컬 플래그다. 호출자마다 이 예외를 성공으로
  /// 번역하게 두면 언젠가 한 곳을 빠뜨린다.
  ///
  /// ⚠️ **409가 늘 그 뜻은 아니다.** 닉네임이 겹쳐도 409가 온다 —
  /// 구현체가 `code`로 가른다.
  Future<void> submit(OnboardingProfile profile);

  /// 그 닉네임을 쓸 수 있는가.
  ///
  /// ## 왜 [submit] 전에 따로 묻는가
  ///
  /// 닉네임은 **첫 질문**이고 제출은 다섯 개를 다 채운 뒤다. 제출 때 겹친 것을
  /// 알면 네 질문을 지나 다시 첫 칸으로 돌아와야 한다. 여기서 먼저 막으면
  /// 고칠 자리에 서 있는 채로 알게 된다.
  ///
  /// **판정을 못 하면 던진다.** `false`로 뭉뚱그리면 "이미 있는 이름"과
  /// "물어보지 못했다"가 같은 결과가 되고, 화면은 멀쩡한 이름을 거절하게 된다.
  Future<bool> isNicknameAvailable(String nickname);
}
