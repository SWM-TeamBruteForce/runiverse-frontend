import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/data/fake_auth_repository.dart';
import 'package:runiverse/features/auth/data/fake_oauth_code_source.dart';
import 'package:runiverse/features/auth/domain/auth_failure.dart';
import 'package:runiverse/features/auth/domain/oauth_provider.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/auth/presentation/auth_state.dart';

/// 카카오 로그인 — 두 단계가 이어지는가.
///
/// ① 카카오에서 인가 코드를 받고 ② 서버에 넘긴다. 여기서 보는 것은
/// **어느 쪽이 실패했을 때 무슨 일이 일어나는가**다.
///
/// 카카오 SDK는 플랫폼 채널을 쓰므로 부를 수 없다. [FakeOauthCodeSource]가
/// 그 자리를 대신한다.
void main() {
  ProviderContainer makeContainer({
    FakeAuthRepository? repository,
    FakeOauthCodeSource? codeSource,
  }) => ProviderContainer.test(
    overrides: [
      // 저장소는 플랫폼 채널을 부른다. 테스트에는 채널이 없다.
      tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
      authRepositoryProvider.overrideWithValue(
        repository ?? FakeAuthRepository(latency: Duration.zero),
      ),
      oauthCodeSourceProvider.overrideWithValue(
        codeSource ?? FakeOauthCodeSource(),
      ),
    ],
  );

  test('인가와 서버가 모두 성공하면 로그인 상태가 된다', () async {
    final container = makeContainer();

    final failure = await container
        .read(authControllerProvider.notifier)
        .signInWithOauth(OauthProvider.kakao);

    expect(failure, isNull);
    expect(container.read(authControllerProvider), isA<AuthSignedIn>());
  });

  test('로그인에 성공하면 토큰이 저장된다', () async {
    final container = makeContainer();

    await container
        .read(authControllerProvider.notifier)
        .signInWithOauth(OauthProvider.kakao);

    final stored = await container.read(tokenStoreProvider).read();
    expect(stored.userId, isNotNull);
    expect(stored.refreshToken, isNotNull);
  });

  test('사용자가 취소하면 서버를 부르지 않는다', () async {
    final repository = FakeAuthRepository(latency: Duration.zero);
    final container = makeContainer(
      repository: repository,
      codeSource: FakeOauthCodeSource(failure: AuthFailure.oauthCancelled),
    );

    final failure = await container
        .read(authControllerProvider.notifier)
        .signInWithOauth(OauthProvider.kakao);

    expect(failure, AuthFailure.oauthCancelled);
    // ⚠️ 인가를 못 받았으면 보낼 것이 없다. 그래도 부르면 쓸모없는 요청이 나가고,
    // 서버는 빈 코드로 카카오에 교환을 시도한다.
    expect(repository.oauthCallCount, 0);
    // 취소는 로그인 상태를 건드리지 않는다.
    expect(container.read(authControllerProvider), isA<AuthUnknown>());
  });

  test('인가가 실패해도 상태는 그대로다', () async {
    final container = makeContainer(
      codeSource: FakeOauthCodeSource(failure: AuthFailure.oauthFailed),
    );

    final failure = await container
        .read(authControllerProvider.notifier)
        .signInWithOauth(OauthProvider.kakao);

    expect(failure, AuthFailure.oauthFailed);
    expect(container.read(authControllerProvider), isA<AuthUnknown>());
  });

  test('같은 이메일의 계정이 이미 있으면 막힌다', () async {
    // 서버는 로컬 계정과 이메일이 겹치면 자동 연동하지 않는다 —
    // 로그인하려는 사람이 그 계정의 주인인지 확인할 방법이 없다.
    final repository = FakeAuthRepository(latency: Duration.zero);
    repository.seedAccount(email: 'taken@example.com', password: 'runi123!');
    repository.seedOauthAccount(code: 'fake-code', email: 'taken@example.com');

    final container = makeContainer(repository: repository);

    final failure = await container
        .read(authControllerProvider.notifier)
        .signInWithOauth(OauthProvider.kakao);

    expect(failure, AuthFailure.emailAlreadyExists);
    expect(container.read(authControllerProvider), isNot(isA<AuthSignedIn>()));
  });

  test('처음 로그인하면 온보딩을 안 마친 상태다', () async {
    final container = makeContainer();

    await container
        .read(authControllerProvider.notifier)
        .signInWithOauth(OauthProvider.kakao);

    // 서버가 계정을 새로 만들었으므로 프로필이 없다.
    // 이 값이 false여야 홈의 유도 카드가 뜬다.
    final state = container.read(authControllerProvider) as AuthSignedIn;
    expect(state.isOnboarded, isFalse);
  });
}
