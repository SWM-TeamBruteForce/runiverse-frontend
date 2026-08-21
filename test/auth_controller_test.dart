import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/data/fake_auth_repository.dart';
import 'package:runiverse/features/auth/domain/auth_failure.dart';
import 'package:runiverse/features/auth/domain/auth_repository.dart';
import 'package:runiverse/features/auth/domain/auth_session.dart';
import 'package:runiverse/features/auth/domain/auth_tokens.dart';
import 'package:runiverse/features/auth/domain/current_user.dart';
import 'package:runiverse/features/auth/domain/oauth_authorization.dart';
import 'package:runiverse/features/auth/domain/oauth_provider.dart';
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
  ProviderContainer makeContainer({
    AuthRepository? repository,
    TokenStore? store,
  }) => ProviderContainer.test(
    overrides: [
      // 앱은 SecureTokenStore를 쓰는데 그것은 플랫폼 채널을 부른다.
      // 테스트에는 채널이 없다 — 순수 test()는 바인딩조차 없어 그 자리에서 죽고,
      // testWidgets()는 조용히 null을 돌려줘 **저장이 안 되는데 통과한다.**
      // 후자가 더 위험하므로 저장소를 쓰는 테스트는 반드시 이것을 갈아끼운다.
      tokenStoreProvider.overrideWithValue(store ?? InMemoryTokenStore()),
      authRepositoryProvider.overrideWithValue(
        repository ?? FakeAuthRepository(latency: Duration.zero),
      ),
    ],
  );

  /// 인증을 마친 상태를 세우고 티켓을 돌려준다.
  ///
  /// 가입은 이제 이메일이 아니라 **티켓**을 받는다. 인증 3단계를 매번 밟는 대신
  /// 티켓만 발급해 쓴다 — 여기서 보려는 것은 가입 이후의 상태 전이다.
  String ticketFor(ProviderContainer container, String email) =>
      (container.read(authRepositoryProvider) as FakeAuthRepository)
          .issueTicket(email);

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

    await controller.signUp(
      verificationTicket: ticketFor(container, 'new@example.com'),
      password: 'runi123!',
    );
    await controller.restore();

    final state = container.read(authControllerProvider);
    // 이 값이 false여야 홈이 유도 카드를 켠다.
    expect((state as AuthSignedIn).isOnboarded, isFalse);
  });

  group('/users/me', () {
    test('로그인하면 서버가 답한 내 정보가 상태에 담긴다', () async {
      final container = makeContainer();

      await container
          .read(authControllerProvider.notifier)
          .signIn(
            email: FakeAuthRepository.seedEmail,
            password: FakeAuthRepository.seedPassword,
          );

      final state = container.read(authControllerProvider) as AuthSignedIn;
      expect(state.user, isNotNull);
      expect(state.user!.userId, state.userId);
      expect(state.user!.isOnboarded, isTrue);
    });

    test('⚠️ 저장된 값이 낡았으면 자동 로그인이 서버 값으로 바로잡는다', () async {
      // 다른 기기에서 프로필을 채운 상황이다. 이 기기의 저장값은 아직 false다.
      final repository = FakeAuthRepository(latency: Duration.zero);
      repository.seedAccount(
        email: 'moved@example.com',
        password: 'runi123!',
        isOnboarded: true,
      );
      final container = makeContainer(repository: repository);
      final session = repository.issueSession(email: 'moved@example.com');
      await container
          .read(tokenStoreProvider)
          .saveSession(
            userId: session.userId,
            accessToken: session.accessToken,
            refreshToken: session.refreshToken,
            // ⚠️ 낡은 값이다. /me가 없으면 홈이 유도 카드를 헛되이 띄운다.
            isOnboarded: false,
          );

      await container.read(authControllerProvider.notifier).restore();

      final state = container.read(authControllerProvider) as AuthSignedIn;
      expect(state.isOnboarded, isTrue);
    });

    test('/me가 실패해도 로그인을 되돌리지 않는다', () async {
      // 인증은 성공했다. 부가 요청 하나가 실패했다고 로그인 화면으로 돌려보내면
      // "네트워크가 끊긴 것"과 "비밀번호가 틀린 것"이 같은 결과가 된다.
      final container = makeContainer(
        repository: _MeFailsAuthRepository(
          FakeAuthRepository(latency: Duration.zero),
        ),
      );

      final failure = await container
          .read(authControllerProvider.notifier)
          .signIn(
            email: FakeAuthRepository.seedEmail,
            password: FakeAuthRepository.seedPassword,
          );

      expect(failure, isNull);
      final state = container.read(authControllerProvider);
      expect(state, isA<AuthSignedIn>());
      // 로그인 응답으로 세운 값이 그대로 남는다.
      expect((state as AuthSignedIn).isOnboarded, isTrue);
      expect(state.user, isNull);
    });
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
        .signUp(
          verificationTicket: ticketFor(container, 'new@example.com'),
          password: 'runi123!',
        );

    expect(failure, isNull);
    expect(container.read(authControllerProvider), isA<AuthSignedIn>());
  });

  test('이미 있는 이메일로 가입하면 막힌다', () async {
    final container = makeContainer();

    final failure = await container
        .read(authControllerProvider.notifier)
        .signUp(
          // 인증은 통과했는데 그 사이 계정이 이미 있는 경우다.
          // 서버는 티켓을 먼저 소비한 뒤에 이 실패를 낸다.
          verificationTicket: ticketFor(
            container,
            FakeAuthRepository.seedEmail,
          ),
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

  group('서버가 isOnboarded를 말하지 않을 때', () {
    // 서버가 2026-08-17 로그인·가입·소셜 응답에서 이 값을 뺐다. 대신 보라는
    // `GET /users/me`는 아직 없다. 그래서 지금 실서버는 늘 이 상태다.

    /// 저장소에 [userId]로 프로필을 채운 흔적을 남긴 컨테이너.
    Future<ProviderContainer> containerRemembering(String userId) async {
      final container = makeContainer(
        repository: _SilentAboutOnboarding(
          FakeAuthRepository(latency: Duration.zero),
        ),
      );
      await container
          .read(tokenStoreProvider)
          .saveSession(
            userId: userId,
            accessToken: 'old-access',
            refreshToken: 'old-refresh',
            isOnboarded: true,
          );
      return container;
    }

    test('⚠️ 같은 사람이면 저장된 값을 지킨다', () async {
      // `false`로 떨어뜨리면 이미 프로필을 채운 사람이 로그인할 때마다
      // 폼으로 끌려간다. 관문이 닫히지 않으므로 앱을 쓸 수 없다.
      final seedUserId = FakeAuthRepository(
        latency: Duration.zero,
      ).issueSession().userId;
      final container = await containerRemembering(seedUserId);

      await container
          .read(authControllerProvider.notifier)
          .signIn(
            email: FakeAuthRepository.seedEmail,
            password: FakeAuthRepository.seedPassword,
          );

      final state = container.read(authControllerProvider);
      expect(state, isA<AuthSignedIn>());
      expect((state as AuthSignedIn).isOnboarded, isTrue);
    });

    test('⚠️ 다른 사람이면 저장된 값을 물려주지 않는다', () async {
      // 한 기기에 여러 계정이 로그인한다. `userId`를 보지 않으면 **앞사람이
      // 채웠다는 이유로** 프로필 없는 새 사람이 홈에 들어간다.
      final container = await containerRemembering('someone-else');

      await container
          .read(authControllerProvider.notifier)
          .signIn(
            email: FakeAuthRepository.seedEmail,
            password: FakeAuthRepository.seedPassword,
          );

      final state = container.read(authControllerProvider);
      expect((state as AuthSignedIn).isOnboarded, isFalse);
    });
  });

  test('새로 가입하면 온보딩을 마치지 않은 상태로 저장된다', () async {
    final container = makeContainer();

    await container
        .read(authControllerProvider.notifier)
        .signUp(
          verificationTicket: ticketFor(container, 'new@example.com'),
          password: 'runi123!',
        );

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

    await controller.signUp(
      verificationTicket: ticketFor(container, 'new@example.com'),
      password: 'runi123!',
    );
    // 가입 직후에는 아직 안 마친 상태다.
    expect(
      (container.read(authControllerProvider) as AuthSignedIn).isOnboarded,
      isFalse,
    );

    // 실제 흐름에서는 프로필 전송(`POST /users/onboarding`)이 먼저 성공한다.
    // 그것을 흉내 내지 않으면 뒤이은 `/me`가 아직 false를 답한다.
    (container.read(authRepositoryProvider) as FakeAuthRepository)
        .completeOnboarding('new@example.com');

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

  test('⚠️ /me가 isOnboarded를 안 주면 방금 켠 온보딩을 끄지 않는다', () async {
    // 2026-08-17 인증 응답이 이 필드를 빼고 왔다. 그때 `/me`를 `false`로 읽으면
    // **프로필을 방금 다 채운 사람에게 프로필 입력 시트가 즉시 다시 뜬다** —
    // `markOnboarded`가 저장소를 켠 직후 `_loadCurrentUser`가 도로 끄기 때문이다.
    final repository = _MeWithoutOnboardedFlag();
    final container = makeContainer(repository: repository);
    final controller = container.read(authControllerProvider.notifier);

    await controller.signUp(
      verificationTicket: ticketFor(container, 'new@example.com'),
      password: 'runi123!',
    );
    repository.completeOnboarding('new@example.com');

    await controller.markOnboarded();

    expect(
      (container.read(authControllerProvider) as AuthSignedIn).isOnboarded,
      isTrue,
    );
    // 저장소까지 봐야 한다. 여기가 false면 다음 실행의 첫 화면이 폼으로 간다.
    expect(
      (await container.read(tokenStoreProvider).read()).isOnboarded,
      isTrue,
    );
  });

  test('⚠️ 온보딩을 마치면 방금 입력한 닉네임이 상태에 들어온다', () async {
    // 여기가 깨지면 프로필 탭이 자리표시자만 그린다 — 방금 이름을 썼는데
    // 화면에는 안 나온다. `markOnboarded`가 `user`를 떨어뜨려서 겪었다.
    final container = makeContainer();
    final controller = container.read(authControllerProvider.notifier);
    await controller.signUp(
      verificationTicket: ticketFor(container, 'new@example.com'),
      password: 'runi123!',
    );
    expect(
      (container.read(authControllerProvider) as AuthSignedIn).user?.nickname,
      isNull,
    );

    (container.read(authRepositoryProvider) as FakeAuthRepository)
        .completeOnboarding('new@example.com');
    await controller.markOnboarded();

    // 마치는 순간이 **서버에 닉네임이 생긴 순간**이다. 그때 다시 물어야 한다.
    expect(
      (container.read(authControllerProvider) as AuthSignedIn).user?.nickname,
      isNotNull,
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

  group('/me 디바이스 캐시', () {
    test('/me가 답하면 디바이스에 남는다', () async {
      final store = InMemoryTokenStore();
      final container = makeContainer(store: store);

      await container
          .read(authControllerProvider.notifier)
          .signIn(
            email: FakeAuthRepository.seedEmail,
            password: FakeAuthRepository.seedPassword,
          );

      // 다음 실행이 이 값으로 첫 화면을 그린다.
      expect((await store.read()).nickname, isNotNull);
    });

    test('⚠️ /me가 실패해도 캐시가 화면을 채운다', () async {
      // 앱을 껐다 켠 상황을 만든다. 저장소는 그대로 두고 컨테이너만 새로 만든다.
      final store = InMemoryTokenStore();
      // ⚠️ 서버 역할은 **같은 인스턴스**여야 한다. 새로 만들면 발급한
      // 리프레시 토큰을 모르고, 갱신이 만료로 떨어져 로그아웃된다.
      final server = FakeAuthRepository(latency: Duration.zero);

      // ① 지난번 실행 — 정상적으로 로그인해 캐시까지 남겼다.
      await makeContainer(store: store, repository: server)
          .read(authControllerProvider.notifier)
          .signIn(
            email: FakeAuthRepository.seedEmail,
            password: FakeAuthRepository.seedPassword,
          );
      final cachedNickname = (await store.read()).nickname;
      expect(cachedNickname, isNotNull, reason: '전제: 지난 실행이 캐시를 남겼다');

      // ② 이번 실행 — 지하철이라 `/me`가 못 온다.
      final container = makeContainer(
        store: store,
        repository: _MeFailsAuthRepository(server),
      );
      await container.read(authControllerProvider.notifier).restore();

      // 그래도 프로필 탭이 **회색 자리표시자로 비어 있으면 안 된다.**
      final state = container.read(authControllerProvider) as AuthSignedIn;
      expect(state.user, isNotNull);
      expect(state.user!.nickname, cachedNickname);
    });

    test('캐시가 없으면 user는 null로 둔다', () async {
      final store = InMemoryTokenStore();
      final container = makeContainer(
        store: store,
        repository: _MeFailsAuthRepository(
          FakeAuthRepository(latency: Duration.zero),
        ),
      );
      final controller = container.read(authControllerProvider.notifier);

      // `/me`가 한 번도 답한 적이 없다. 토큰만 있고 캐시는 비어 있다.
      await controller.signIn(
        email: FakeAuthRepository.seedEmail,
        password: FakeAuthRepository.seedPassword,
      );
      await controller.restore();

      // 없는 값을 지어내지 않는다. 빈 껍데기를 주면 "받아왔는데 비어 있다"와
      // "아직 못 받았다"가 구별되지 않는다.
      final state = container.read(authControllerProvider) as AuthSignedIn;
      expect(state.user, isNull);
    });
  });
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
  Future<CurrentUser> fetchCurrentUser(String accessToken) =>
      inner.fetchCurrentUser(accessToken);

  @override
  Future<AuthSession> signIn({
    required String email,
    required String password,
  }) => inner.signIn(email: email, password: password);

  @override
  Future<AuthSession> signUp({
    required String verificationTicket,
    required String password,
  }) =>
      inner.signUp(verificationTicket: verificationTicket, password: password);

  @override
  Future<AuthSession> signInWithOauth({
    required OauthProvider provider,
    required OauthAuthorization authorization,
  }) => inner.signInWithOauth(provider: provider, authorization: authorization);

  @override
  Future<void> sendVerificationCode(String email) =>
      inner.sendVerificationCode(email);

  @override
  Future<String> verifyCode({required String email, required String code}) =>
      inner.verifyCode(email: email, code: code);

  @override
  Future<void> signOut() => inner.signOut();
}

/// `/me`만 네트워크 오류로 답하는 저장소. 나머지는 [inner]에 맡긴다.
///
/// **인증은 성공했는데 부가 요청 하나가 실패한 상황**을 만든다. 그때 로그인을
/// 되돌리면 "네트워크가 잠깐 끊긴 것"과 "비밀번호가 틀린 것"이 같은 결과가 된다.
class _MeFailsAuthRepository implements AuthRepository {
  _MeFailsAuthRepository(this.inner);

  final AuthRepository inner;

  @override
  Future<CurrentUser> fetchCurrentUser(String accessToken) =>
      throw const AuthException(AuthFailure.network);

  @override
  Future<AuthTokens> refresh(String refreshToken) =>
      inner.refresh(refreshToken);

  @override
  Future<AuthSession> signIn({
    required String email,
    required String password,
  }) => inner.signIn(email: email, password: password);

  @override
  Future<AuthSession> signUp({
    required String verificationTicket,
    required String password,
  }) =>
      inner.signUp(verificationTicket: verificationTicket, password: password);

  @override
  Future<AuthSession> signInWithOauth({
    required OauthProvider provider,
    required OauthAuthorization authorization,
  }) => inner.signInWithOauth(provider: provider, authorization: authorization);

  @override
  Future<void> sendVerificationCode(String email) =>
      inner.sendVerificationCode(email);

  @override
  Future<String> verifyCode({required String email, required String code}) =>
      inner.verifyCode(email: email, code: code);

  @override
  Future<void> signOut() => inner.signOut();
}

/// 서버가 `isOnboarded`를 **말하지 않고**, `/users/me`도 **없는** 상태.
///
/// 2026-08-17 이후 실서버가 정확히 이렇다 — 인증 응답에서 그 필드를 뺐는데
/// 대신 보라던 `GET /users/me`는 아직 구현되지 않았다.
///
/// 두 가지를 함께 흉내 내야 한다. `/me`만 살려두면 그 답이 상태를 덮어써서
/// **저장값을 지키는지 아닌지가 화면에 드러나지 않는다.**
class _SilentAboutOnboarding implements AuthRepository {
  _SilentAboutOnboarding(this.inner);

  final AuthRepository inner;

  /// 서버가 말하지 않은 것으로 만든다.
  AuthSession _silenced(AuthSession session) => AuthSession(
    userId: session.userId,
    accessToken: session.accessToken,
    refreshToken: session.refreshToken,
    isOnboarded: null,
  );

  @override
  Future<CurrentUser> fetchCurrentUser(String accessToken) =>
      throw const AuthException(AuthFailure.server);

  @override
  Future<AuthTokens> refresh(String refreshToken) =>
      inner.refresh(refreshToken);

  @override
  Future<AuthSession> signIn({
    required String email,
    required String password,
  }) => inner.signIn(email: email, password: password).then(_silenced);

  @override
  Future<AuthSession> signUp({
    required String verificationTicket,
    required String password,
  }) => inner
      .signUp(verificationTicket: verificationTicket, password: password)
      .then(_silenced);

  @override
  Future<AuthSession> signInWithOauth({
    required OauthProvider provider,
    required OauthAuthorization authorization,
  }) => inner
      .signInWithOauth(provider: provider, authorization: authorization)
      .then(_silenced);

  @override
  Future<void> sendVerificationCode(String email) =>
      inner.sendVerificationCode(email);

  @override
  Future<String> verifyCode({required String email, required String code}) =>
      inner.verifyCode(email: email, code: code);

  @override
  Future<void> signOut() => inner.signOut();
}

/// `/users/me`는 오는데 그 답에 `isOnboarded`만 **빠져 있는** 서버.
///
/// 위 [_SilentAboutOnboarding]과 다르다. 그쪽은 `/me` 자체가 없는 경우고,
/// 이쪽은 **200이 오는데 필드 하나가 없는** 경우다 — 답이 왔으니 앱은 그것을
/// 믿고 상태를 덮어쓰려 든다. 그 덮어쓰기가 저장값을 깨뜨리는지를 본다.
class _MeWithoutOnboardedFlag extends FakeAuthRepository {
  _MeWithoutOnboardedFlag() : super(latency: Duration.zero);

  @override
  Future<CurrentUser> fetchCurrentUser(String accessToken) async {
    final user = await super.fetchCurrentUser(accessToken);
    return CurrentUser(
      userId: user.userId,
      isOnboarded: null,
      nickname: user.nickname,
      profileImageUrl: user.profileImageUrl,
      introduction: user.introduction,
    );
  }
}
