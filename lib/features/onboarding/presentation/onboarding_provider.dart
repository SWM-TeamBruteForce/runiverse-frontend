import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/onboarding/data/http_onboarding_repository.dart';
import 'package:runiverse/features/onboarding/domain/onboarding_repository.dart';

/// 누가 프로필 전송에 답할 것인가.
///
/// ⚠️ **이 파일은 `presentation`에 있으면서 `data`를 import한다.** 의존 방향
/// (`presentation → domain ← data`)의 예외인데, 구현체를 고르는 일은 어딘가에서
/// 반드시 해야 하고 그 자리가 여기다 — `auth_provider.dart`와 같은 규칙이다.
/// 화면 파일은 여전히 `data`를 모른다.
///
/// 위젯 테스트는 이것을 `FakeOnboardingRepository`로 갈아끼운다.
final onboardingRepositoryProvider = Provider<OnboardingRepository>(
  (ref) => HttpOnboardingRepository(
    ref.watch(dioProvider),
    ref.watch(tokenStoreProvider),
    ref.watch(authRepositoryProvider),
  ),
);
