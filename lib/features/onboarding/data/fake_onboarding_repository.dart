import 'package:runiverse/features/onboarding/domain/onboarding_failure.dart';
import 'package:runiverse/features/onboarding/domain/onboarding_profile.dart';
import 'package:runiverse/features/onboarding/domain/onboarding_repository.dart';

/// 서버 없이 화면을 돌려보기 위한 가짜 저장소.
///
/// 테스트가 쓴다 — `HttpOnboardingRepository`는 실제 HTTP를 부르므로 위젯 테스트에서
/// 쓸 수 없다.
///
/// ⚠️ **`testWidgets` 안에서 `pumpWidget` 전에 [submit]을 기다리면 테스트가 멈춘다.**
/// 가짜 시간 위에서 도는데 [latency]의 타이머를 진행시킬 `pump`가 아직 없기 때문이다.
/// 미리 상태를 만들어야 하면 [submitted]에 직접 넣는다.
class FakeOnboardingRepository implements OnboardingRepository {
  FakeOnboardingRepository({
    this.latency = const Duration(milliseconds: 600),
    this.failWith,
  });

  /// 응답이 즉시 오면 로딩 표시가 화면에 뜨는지 확인할 수 없다.
  /// 테스트에서는 [Duration.zero]를 넣어 기다리지 않는다.
  final Duration latency;

  /// 실패를 흉내 낼 때 넣는다. `null`이면 성공한다.
  final OnboardingFailure? failWith;

  /// 전송된 프로필. 무엇이 넘어갔는지 테스트가 확인한다.
  OnboardingProfile? submitted;

  @override
  Future<void> submit(OnboardingProfile profile) async {
    await Future<void>.delayed(latency);
    final failure = failWith;
    if (failure != null) throw OnboardingException(failure);
    submitted = profile;
  }
}
