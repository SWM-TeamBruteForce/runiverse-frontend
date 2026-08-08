import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/data/fake_auth_repository.dart';
import 'package:runiverse/features/auth/domain/auth_failure.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/auth/presentation/auth_state.dart';

/// 인증 상태 전이 — 무엇을 하면 상태가 어디로 가는가.
///
/// 화면은 보지 않는다. 여기서 확인하는 것은 **로그인/로그아웃/복원이 상태와 저장소를
/// 어떻게 바꾸는가**다.
///
/// 가짜 저장소를 지연 없이 넣는다. 지연은 화면에서 로딩을 보여주기 위한 것이지
/// 여기서 기다릴 이유가 없다.
void main() {
  ProviderContainer makeContainer() => ProviderContainer.test(
    overrides: [
      // 앱은 SecureTokenStore를 쓰는데 그것은 플랫폼 채널을 부른다.
      // 테스트에는 채널이 없다 — 순수 test()는 바인딩조차 없어 그 자리에서 죽고,
      // testWidgets()는 조용히 null을 돌려줘 **저장이 안 되는데 통과한다.**
      // 후자가 더 위험하므로 저장소를 쓰는 테스트는 반드시 이것을 갈아끼운다.
      tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
      authRepositoryProvider.overrideWithValue(
        FakeAuthRepository(latency: Duration.zero),
      ),
    ],
  );

  test('처음에는 로그인 상태를 모른다', () {
    final container = makeContainer();

    // 저장소를 아직 읽지 않았다. 이 시점에 로그아웃으로 단정하면
    // 스플래시가 저장된 세션을 무시하고 온보딩으로 보내버린다.
    expect(container.read(authControllerProvider), isA<AuthUnknown>());
  });

  test('저장된 것이 없으면 복원 결과는 로그아웃이다', () async {
    final container = makeContainer();

    await container.read(authControllerProvider.notifier).restore();

    expect(container.read(authControllerProvider), isA<AuthSignedOut>());
  });

  test('씨앗 계정으로 로그인하면 상태가 로그인으로 바뀐다', () async {
    final container = makeContainer();

    final failure = await container
        .read(authControllerProvider.notifier)
        .signIn(
          email: FakeAuthRepository.seedEmail,
          password: FakeAuthRepository.seedPassword,
        );

    expect(failure, isNull);
    expect(container.read(authControllerProvider), isA<AuthSignedIn>());
  });

  test('로그인에 성공하면 토큰이 저장된다', () async {
    final container = makeContainer();

    await container
        .read(authControllerProvider.notifier)
        .signIn(
          email: FakeAuthRepository.seedEmail,
          password: FakeAuthRepository.seedPassword,
        );

    final stored = await container.read(tokenStoreProvider).read();
    expect(stored.userId, isNotNull);
    expect(stored.accessToken, isNotNull);
    expect(stored.refreshToken, isNotNull);
  });

  test('비밀번호가 틀리면 이유를 돌려주고 상태는 그대로다', () async {
    final container = makeContainer();

    final failure = await container
        .read(authControllerProvider.notifier)
        .signIn(email: FakeAuthRepository.seedEmail, password: 'wrong123!');

    expect(failure, AuthFailure.invalidCredentials);
    // 실패했는데 로그인 상태로 바뀌면 홈으로 들어가진다.
    expect(container.read(authControllerProvider), isNot(isA<AuthSignedIn>()));
  });

  test('없는 이메일도 같은 이유를 돌려준다', () async {
    final container = makeContainer();

    final failure = await container
        .read(authControllerProvider.notifier)
        .signIn(email: 'nobody@example.com', password: 'runi123!');

    // 이유를 나누면 "이 이메일은 가입돼 있다"가 새어 나간다.
    expect(failure, AuthFailure.invalidCredentials);
  });

  test('가입하면 곧바로 로그인 상태가 된다', () async {
    final container = makeContainer();

    final failure = await container
        .read(authControllerProvider.notifier)
        .signUp(email: 'new@example.com', password: 'runi123!');

    expect(failure, isNull);
    expect(container.read(authControllerProvider), isA<AuthSignedIn>());
  });

  test('이미 있는 이메일로 가입하면 막힌다', () async {
    final container = makeContainer();

    final failure = await container
        .read(authControllerProvider.notifier)
        .signUp(
          email: FakeAuthRepository.seedEmail,
          password: FakeAuthRepository.seedPassword,
        );

    expect(failure, AuthFailure.emailAlreadyExists);
  });

  test('로그인한 뒤 복원하면 로그인 상태가 유지된다', () async {
    final container = makeContainer();
    final controller = container.read(authControllerProvider.notifier);

    await controller.signIn(
      email: FakeAuthRepository.seedEmail,
      password: FakeAuthRepository.seedPassword,
    );
    await controller.restore();

    expect(container.read(authControllerProvider), isA<AuthSignedIn>());
  });

  test('로그아웃하면 상태와 저장소가 함께 비워진다', () async {
    final container = makeContainer();
    final controller = container.read(authControllerProvider.notifier);

    await controller.signIn(
      email: FakeAuthRepository.seedEmail,
      password: FakeAuthRepository.seedPassword,
    );
    await controller.signOut();

    expect(container.read(authControllerProvider), isA<AuthSignedOut>());
    // 상태만 바꾸고 토큰을 남기면 다음 실행에서 되살아난다.
    expect((await container.read(tokenStoreProvider).read()).userId, isNull);
  });
}
