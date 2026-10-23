import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/storage/sign_in_memory_store.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/data/fake_auth_repository.dart';
import 'package:runiverse/features/auth/data/fake_oauth_code_source.dart';
import 'package:runiverse/features/auth/domain/auth_failure.dart';
import 'package:runiverse/features/auth/domain/oauth_provider.dart';
import 'package:runiverse/features/auth/domain/sign_in_method.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/auth/presentation/auth_state.dart';
import 'package:runiverse/features/session/data/fake_user_status_repository.dart';
import 'package:runiverse/features/session/presentation/user_status_provider.dart';

/// 구글 로그인 — 카카오와 **같은 길을 타되 모양이 다르다.**
///
/// 서버 계약이 다르다(연동 가이드 1절).
///
/// | | 카카오 | 구글 |
/// |---|---|---|
/// | 앱이 받는 것 | 인가 코드 + PKCE 검증값 | **ID 토큰** 하나 |
/// | 보내는 것 | `{authorizationCode, codeVerifier}` | `{idToken}` |
///
/// 구글 SDK는 플랫폼 채널을 쓰므로 부를 수 없다. [FakeOauthCodeSource]가
/// 그 자리를 대신한다.
void main() {
  late InMemorySignInMemoryStore memory;

  ProviderContainer makeContainer({FakeOauthCodeSource? codeSource}) {
    memory = InMemorySignInMemoryStore();
    return ProviderContainer.test(
      overrides: [
        tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
        signInMemoryStoreProvider.overrideWithValue(memory),
        userStatusRepositoryProvider.overrideWithValue(
          FakeUserStatusRepository(),
        ),
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(latency: Duration.zero),
        ),
        oauthCodeSourceProvider.overrideWith(
          (ref, provider) => codeSource ?? FakeOauthCodeSource(),
        ),
      ],
    );
  }

  test('인가와 서버가 모두 성공하면 로그인 상태가 된다', () async {
    final container = makeContainer();

    final failure = await container
        .read(authControllerProvider.notifier)
        .signInWithOauth(OauthProvider.google);

    expect(failure, isNull);
    expect(container.read(authControllerProvider), isA<AuthSignedIn>());
  });

  test('⚠️ 마지막 로그인 수단으로 google 이 남는다', () async {
    // 다음에 열었을 때 어느 타일을 눌러야 하는지 보이는 자리다.
    // `kakao` 가 남으면 **엉뚱한 타일에 표시가 붙는다.**
    final container = makeContainer();

    await container
        .read(authControllerProvider.notifier)
        .signInWithOauth(OauthProvider.google);

    expect(await memory.lastMethod(), SignInMethod.google);
  });

  test('⚠️ 취소는 서버를 부르지 않는다', () async {
    // 창을 닫은 사람 때문에 요청이 나가면, 서버는 빈 토큰으로 구글에
    // 확인을 시도하게 된다.
    final repository = FakeAuthRepository(latency: Duration.zero);
    final container = ProviderContainer.test(
      overrides: [
        tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
        signInMemoryStoreProvider.overrideWithValue(
          InMemorySignInMemoryStore(),
        ),
        userStatusRepositoryProvider.overrideWithValue(
          FakeUserStatusRepository(),
        ),
        authRepositoryProvider.overrideWithValue(repository),
        oauthCodeSourceProvider.overrideWith(
          (ref, provider) =>
              FakeOauthCodeSource(failure: AuthFailure.oauthCancelled),
        ),
      ],
    );

    final failure = await container
        .read(authControllerProvider.notifier)
        .signInWithOauth(OauthProvider.google);

    expect(failure, AuthFailure.oauthCancelled);
    expect(repository.oauthCallCount, 0, reason: '서버를 부르면 안 된다');
  });
}
