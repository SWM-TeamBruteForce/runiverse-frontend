import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/storage/sign_in_memory_store.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/data/fake_auth_repository.dart';
import 'package:runiverse/features/auth/data/fake_oauth_code_source.dart';
import 'package:runiverse/features/auth/domain/auth_failure.dart';
import 'package:runiverse/features/auth/domain/login_type.dart';
import 'package:runiverse/features/auth/domain/oauth_provider.dart';
import 'package:runiverse/features/auth/domain/sign_in_method.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/auth/presentation/auth_state.dart';
import 'package:runiverse/features/session/data/fake_user_status_repository.dart';
import 'package:runiverse/features/session/presentation/user_status_provider.dart';

/// 애플 로그인 — 구글과 **같은 길을 타되 nonce 가 하나 더 간다.**
///
/// | | 카카오 | 구글 | 애플 |
/// |---|---|---|---|
/// | 앱이 받는 것 | 인가 코드 + PKCE 검증값 | ID 토큰 | ID 토큰 + nonce |
/// | 보내는 것 | `{authorizationCode, codeVerifier}` | `{idToken}` | `{idToken, nonce}` |
///
/// 서버 본문의 모양은 `http_auth_repository_oauth_test.dart`가 본다. 여기서는
/// **컨트롤러가 애플을 다른 둘과 같이 다루는가**를 본다.
///
/// 애플 SDK 는 플랫폼 채널을 부르므로 [FakeOauthCodeSource]가 그 자리를 대신한다.
void main() {
  late InMemorySignInMemoryStore memory;

  ProviderContainer makeContainer({
    FakeOauthCodeSource? codeSource,
    FakeAuthRepository? repository,
  }) {
    memory = InMemorySignInMemoryStore();
    return ProviderContainer.test(
      overrides: [
        tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
        signInMemoryStoreProvider.overrideWithValue(memory),
        userStatusRepositoryProvider.overrideWithValue(
          FakeUserStatusRepository(),
        ),
        authRepositoryProvider.overrideWithValue(
          repository ?? FakeAuthRepository(latency: Duration.zero),
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
        .signInWithOauth(OauthProvider.apple);

    expect(failure, isNull);
    expect(container.read(authControllerProvider), isA<AuthSignedIn>());
  });

  test('⚠️ 마지막 로그인 수단으로 apple 이 남는다', () async {
    // 다음에 열었을 때 어느 타일을 눌러야 하는지 보이는 자리다.
    // `google` 이 남으면 **엉뚱한 타일에 표시가 붙는다.**
    final container = makeContainer();

    await container
        .read(authControllerProvider.notifier)
        .signInWithOauth(OauthProvider.apple);

    expect(await memory.lastMethod(), SignInMethod.apple);
  });

  test('⚠️ 취소는 서버를 부르지 않는다', () async {
    // 창을 닫은 사람 때문에 요청이 나가면, 서버는 빈 토큰을 애플 공개키로
    // 확인하려 든다.
    final repository = FakeAuthRepository(latency: Duration.zero);
    final container = makeContainer(
      repository: repository,
      codeSource: FakeOauthCodeSource(failure: AuthFailure.oauthCancelled),
    );

    final failure = await container
        .read(authControllerProvider.notifier)
        .signInWithOauth(OauthProvider.apple);

    expect(failure, AuthFailure.oauthCancelled);
    expect(repository.oauthCallCount, 0, reason: '서버를 부르면 안 된다');
  });

  test('⚠️ iOS가 아니면 진짜 소스가 SDK 를 부르지 않는다', () async {
    // 안드로이드에는 타일이 없지만, 소스를 직접 부를 길이 남아 있다.
    // 거기서 애플 웹 흐름이 열리면 **번들 ID 가 아닌 토큰**이 발급돼 서버가
    // 401을 돌려준다(연동 가이드 3절).
    //
    // 가짜를 끼우지 않고 **진짜 `AppleCodeSource`를 쓴다.** 플랫폼 채널까지
    // 가면 테스트가 죽으므로, 죽지 않는 것 자체가 막혔다는 증거다.
    final container = ProviderContainer.test(
      overrides: [
        tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
        signInMemoryStoreProvider.overrideWithValue(
          InMemorySignInMemoryStore(),
        ),
        userStatusRepositoryProvider.overrideWithValue(
          FakeUserStatusRepository(),
        ),
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(latency: Duration.zero),
        ),
      ],
    );

    final failure = await container
        .read(authControllerProvider.notifier)
        .signInWithOauth(OauthProvider.apple);

    // "다시 시도해주세요"가 아니라 "쓸 수 없다"다 — 다시 눌러도 되지 않는다.
    expect(failure, AuthFailure.oauthUnavailable);
  });

  test("서버의 'APPLE'을 계정 성질로 읽는다", () async {
    // 설정 화면의 로그인 수단 행과 비밀번호 메뉴가 이 값으로 갈린다.
    // 모르는 값이면 `null` 이 되어 "확인 불가"가 뜬다.
    expect(LoginType.fromWire('APPLE'), LoginType.apple);
    expect(LoginType.apple.canChangePassword, isFalse);
  });
}
