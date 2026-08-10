import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/data/fake_auth_repository.dart';
import 'package:runiverse/features/auth/domain/auth_failure.dart';
import 'package:runiverse/features/auth/domain/auth_repository.dart';
import 'package:runiverse/features/auth/domain/auth_session.dart';
import 'package:runiverse/features/auth/domain/auth_tokens.dart';
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

  test('저장된 것이 없으면 처음 온 사람으로 본다', () async {
    final container = makeContainer();

    await container.read(authControllerProvider.notifier).restore();

    final state = container.read(authControllerProvider);
    expect(state, isA<AuthSignedOut>());
    // false여야 스플래시가 온보딩 소개로 보낸다.
    expect((state as AuthSignedOut).returning, isFalse);
  });

  test('토큰이 살아 있으면 갱신해서 로그인 상태가 된다', () async {
    final container = makeContainer();
    final controller = container.read(authControllerProvider.notifier);

    await controller.signIn(
      email: FakeAuthRepository.seedEmail,
      password: FakeAuthRepository.seedPassword,
    );
    final before = await container.read(tokenStoreProvider).read();

    await controller.restore();

    final state = container.read(authControllerProvider);
    expect(state, isA<AuthSignedIn>());
    expect((state as AuthSignedIn).isOnboarded, isTrue);

    // 회전된 토큰을 저장하지 않으면 다음 갱신이 죽는다.
    final after = await container.read(tokenStoreProvider).read();
    expect(after.refreshToken, isNot(before.refreshToken));
  });

  test('온보딩을 안 마쳤으면 그 사실이 상태에 남는다', () async {
    final container = makeContainer();
    final controller = container.read(authControllerProvider.notifier);

    await controller.signUp(email: 'new@example.com', password: 'runi123!');
    await controller.restore();

    final state = container.read(authControllerProvider);
    // 이 값이 false여야 스플래시가 프로필 등록으로 보낸다.
    expect((state as AuthSignedIn).isOnboarded, isFalse);
  });

  test('리프레시 토큰이 만료되면 토큰만 지우고 로그인 화면으로 보낸다', () async {
    final container = makeContainer();
    final store = container.read(tokenStoreProvider);

    // 가짜 저장소가 발급한 적 없는 토큰이다. 갱신이 만료로 답한다.
    await store.saveSession(
      userId: 'u-1',
      accessToken: 'stale',
      refreshToken: 'stale',
      isOnboarded: true,
    );
    await container.read(authControllerProvider.notifier).restore();

    final state = container.read(authControllerProvider);
    expect(state, isA<AuthSignedOut>());
    // 처음 온 사람이 아니다. 온보딩 소개를 다시 보여주면 안 된다.
    expect((state as AuthSignedOut).returning, isTrue);

    final stored = await store.read();
    expect(stored.refreshToken, isNull);
    // userId를 지우면 다음 실행에 소개부터 다시 본다.
    expect(stored.userId, 'u-1');
  });

  test('토큰이 없고 userId만 있으면 로그인 화면으로 보낸다', () async {
    final container = makeContainer();
    final store = container.read(tokenStoreProvider);

    await store.saveSession(
      userId: 'u-1',
      accessToken: 'a',
      refreshToken: 'r',
      isOnboarded: true,
    );
    await store.clearTokens();

    await container.read(authControllerProvider.notifier).restore();

    final state = container.read(authControllerProvider);
    expect((state as AuthSignedOut).returning, isTrue);
  });

  test('갱신이 네트워크 오류로 실패하면 아무 쪽으로도 보내지 않는다', () async {
    final container = ProviderContainer.test(
      overrides: [
        tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
        authRepositoryProvider.overrideWithValue(
          _OfflineAuthRepository(FakeAuthRepository(latency: Duration.zero)),
        ),
      ],
    );
    await container
        .read(tokenStoreProvider)
        .saveSession(
          userId: 'u-1',
          accessToken: 'a',
          refreshToken: 'r',
          isOnboarded: true,
        );

    await container.read(authControllerProvider.notifier).restore();

    // 판정에 실패한 것과 판정에 성공한 것은 다른 상태다.
    // 저장된 값을 믿고 홈에 들여보내지 않는다 — 오프라인은 허용하지 않는다.
    expect(container.read(authControllerProvider), isA<AuthUnknown>());
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

  test('씨앗 계정으로 로그인하면 온보딩을 마친 상태로 저장된다', () async {
    final container = makeContainer();

    await container
        .read(authControllerProvider.notifier)
        .signIn(
          email: FakeAuthRepository.seedEmail,
          password: FakeAuthRepository.seedPassword,
        );

    expect(
      (await container.read(tokenStoreProvider).read()).isOnboarded,
      isTrue,
    );
  });

  test('새로 가입하면 온보딩을 마치지 않은 상태로 저장된다', () async {
    final container = makeContainer();

    await container
        .read(authControllerProvider.notifier)
        .signUp(email: 'new@example.com', password: 'runi123!');

    // 이 값이 false여야 스플래시가 홈이 아니라 프로필 등록으로 보낸다.
    expect(
      (await container.read(tokenStoreProvider).read()).isOnboarded,
      isFalse,
    );
  });

  test('가짜 저장소는 발급했던 토큰만 갱신해 준다', () async {
    final repository = FakeAuthRepository(latency: Duration.zero);

    final session = await repository.signIn(
      email: FakeAuthRepository.seedEmail,
      password: FakeAuthRepository.seedPassword,
    );
    final tokens = await repository.refresh(session.refreshToken);

    // 서버가 회전시키므로 새 값이 와야 한다. 같은 값을 돌려주는 가짜를 쓰면
    // "덮어쓰기를 잊어도 통과하는" 테스트가 되어 버그를 숨긴다.
    expect(tokens.accessToken, isNot(session.accessToken));
    expect(tokens.refreshToken, isNot(session.refreshToken));
  });

  test('모르는 리프레시 토큰은 세션 만료다', () async {
    final repository = FakeAuthRepository(latency: Duration.zero);

    expect(
      () => repository.refresh('nonsense'),
      throwsA(
        isA<AuthException>().having(
          (e) => e.failure,
          'failure',
          AuthFailure.sessionExpired,
        ),
      ),
    );
  });

  test('온보딩을 마치면 상태와 저장소가 함께 켜진다', () async {
    final container = makeContainer();
    final controller = container.read(authControllerProvider.notifier);

    await controller.signUp(email: 'new@example.com', password: 'runi123!');
    // 가입 직후에는 아직 안 마친 상태다.
    expect(
      (container.read(authControllerProvider) as AuthSignedIn).isOnboarded,
      isFalse,
    );

    await controller.markOnboarded();

    // 상태만 켜고 저장소를 두면 앱을 껐다 켤 때 다시 프로필로 간다.
    expect(
      (container.read(authControllerProvider) as AuthSignedIn).isOnboarded,
      isTrue,
    );
    expect(
      (await container.read(tokenStoreProvider).read()).isOnboarded,
      isTrue,
    );
  });

  test('로그인 상태가 아니면 온보딩 완료가 상태를 만들지 않는다', () async {
    final container = makeContainer();

    await container.read(authControllerProvider.notifier).markOnboarded();

    // 로그인하지 않았는데 AuthSignedIn이 생기면 홈에 들어가진다.
    expect(container.read(authControllerProvider), isNot(isA<AuthSignedIn>()));
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

  _emailVerificationGroup();
}

/// 인증번호 발송·확인 — **상태를 바꾸지 않는 것**이 핵심이다.
void _emailVerificationGroup() {
  ProviderContainer makeContainer() => ProviderContainer.test(
    overrides: [
      tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
      authRepositoryProvider.overrideWithValue(
        FakeAuthRepository(latency: Duration.zero),
      ),
    ],
  );

  /// 저장소를 컨테이너에서 꺼낸다. 메일함을 열 수 없으니 `lastCode`가 필요하다.
  FakeAuthRepository repositoryOf(ProviderContainer container) =>
      container.read(authRepositoryProvider) as FakeAuthRepository;

  group('이메일 인증', () {
    test('인증번호를 확인해도 로그인 상태가 되지 않는다', () async {
      final container = makeContainer();
      final controller = container.read(authControllerProvider.notifier);
      final repository = repositoryOf(container);

      await controller.sendVerificationCode('new@example.com');
      final result = await controller.verifyCode(
        email: 'new@example.com',
        code: repository.lastCode!,
      );

      expect(result.ticket, isNotNull);
      expect(result.failure, isNull);
      // 인증은 신원 확인일 뿐 로그인이 아니다. 여기서 AuthSignedIn이 되면
      // 비밀번호도 정하지 않은 사람이 홈에 들어간다.
      expect(container.read(authControllerProvider), isA<AuthUnknown>());
    });

    test('확인에 실패하면 이유를 돌려주고 티켓은 없다', () async {
      final container = makeContainer();
      final controller = container.read(authControllerProvider.notifier);

      await controller.sendVerificationCode('new@example.com');
      final result = await controller.verifyCode(
        email: 'new@example.com',
        code: '000000',
      );

      expect(result.ticket, isNull);
      expect(result.failure, AuthFailure.invalidCode);
    });

    test('이미 가입된 이메일은 발송에서 막힌다', () async {
      final container = makeContainer();
      final controller = container.read(authControllerProvider.notifier);
      repositoryOf(
        container,
      ).seedAccount(email: 'taken@example.com', password: 'runi123!');

      final failure = await controller.sendVerificationCode(
        'taken@example.com',
      );

      expect(failure, AuthFailure.emailAlreadyExists);
    });

    test('발송에 성공하면 null을 돌려준다', () async {
      final container = makeContainer();

      final failure = await container
          .read(authControllerProvider.notifier)
          .sendVerificationCode('new@example.com');

      expect(failure, isNull);
      expect(container.read(authControllerProvider), isA<AuthUnknown>());
    });
  });
}

/// 갱신만 네트워크 오류로 답하는 저장소. 나머지는 [inner]에 맡긴다.
///
/// 오프라인을 흉내 내려고 만든다. **판정에 실패했을 때 앱이 어디로도 가지 않는지**를
/// 보는 것이 목적이다.
class _OfflineAuthRepository implements AuthRepository {
  _OfflineAuthRepository(this.inner);

  final AuthRepository inner;

  @override
  Future<AuthTokens> refresh(String refreshToken) =>
      throw const AuthException(AuthFailure.network);

  @override
  Future<AuthSession> signIn({
    required String email,
    required String password,
  }) => inner.signIn(email: email, password: password);

  @override
  Future<AuthSession> signUp({
    required String email,
    required String password,
  }) => inner.signUp(email: email, password: password);

  @override
  Future<void> sendVerificationCode(String email) =>
      inner.sendVerificationCode(email);

  @override
  Future<String> verifyCode({required String email, required String code}) =>
      inner.verifyCode(email: email, code: code);

  @override
  Future<void> signOut() => inner.signOut();
}
