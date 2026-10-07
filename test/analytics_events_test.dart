import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/analytics/analytics.dart';
import 'package:runiverse/core/analytics/fake_analytics.dart';
import 'package:runiverse/core/storage/sign_in_memory_store.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/data/fake_auth_repository.dart';
import 'package:runiverse/features/auth/data/fake_oauth_code_source.dart';
import 'package:runiverse/features/auth/domain/auth_failure.dart';
import 'package:runiverse/features/auth/domain/oauth_provider.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/session/data/fake_user_status_repository.dart';
import 'package:runiverse/features/session/presentation/user_status_provider.dart';

/// GA 이벤트 — **성공한 시점에만 남는가.**
///
/// ## 왜 이것만 따로 보나
///
/// 이벤트를 잘못 남겨도 **화면은 멀쩡하고 서버 요청도 그대로다.** 눈으로도
/// 다른 테스트로도 드러나지 않고, 몇 주 뒤 지표가 이상하다는 말로 돌아온다.
/// 그래서 적어 두고 세는 수밖에 없다([FakeAnalytics]).
///
/// 노션 GA 도입 문서가 못 박은 규칙이 하나다 — **버튼 탭이 아니라 성공한
/// 시점.** 탭으로 세면 실패한 시도까지 섞여 전환율이 부풀려진다.
void main() {
  late FakeAnalytics analytics;

  ProviderContainer makeContainer({FakeOauthCodeSource? codeSource}) {
    analytics = FakeAnalytics();
    return ProviderContainer.test(
      overrides: [
        analyticsProvider.overrideWithValue(analytics),
        // 저장소는 플랫폼 채널을 부른다. 테스트에는 채널이 없다.
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
        oauthCodeSourceProvider.overrideWith(
          (ref, provider) => codeSource ?? FakeOauthCodeSource(),
        ),
      ],
    );
  }

  group('login', () {
    test('로그인에 성공하면 수단과 함께 한 번 남는다', () async {
      final container = makeContainer();

      await container
          .read(authControllerProvider.notifier)
          .signInWithOauth(OauthProvider.kakao);

      expect(analytics.countOf('login'), 1);
      expect(analytics.paramsOf('login'), {'method': 'kakao'});
    });

    test('⚠️ 인가를 취소하면 남지 않는다', () async {
      // 버튼은 눌렸지만 세션은 서지 않았다. 여기서 남기면 **취소한 사람이
      // 로그인한 것으로 세어진다.**
      final container = makeContainer(
        codeSource: FakeOauthCodeSource(failure: AuthFailure.oauthCancelled),
      );

      await container
          .read(authControllerProvider.notifier)
          .signInWithOauth(OauthProvider.kakao);

      expect(analytics.events, isEmpty);
    });

    test('⚠️ 서버가 거절하면 남지 않는다', () async {
      final container = makeContainer(
        codeSource: FakeOauthCodeSource(failure: AuthFailure.oauthFailed),
      );

      await container
          .read(authControllerProvider.notifier)
          .signInWithOauth(OauthProvider.kakao);

      expect(analytics.events, isEmpty);
    });

    test('⚠️ 비밀번호가 틀리면 남지 않는다', () async {
      // ⚠️ **이 테스트가 핵심이다.** 위의 두 소셜 실패는 인가 단계에서
      // 끝나 `_authenticate` 에 **들어가지도 않는다** — 로그를 그 안쪽 어디로
      // 옮겨도 걸리지 않는다. 실제로 "시도 시점"으로 옮겨 보고 알았다.
      //
      // 이메일은 다르다. 서버까지 가서 거절당하므로, 로그가 `call()` 앞에 있으면
      // **틀린 비밀번호를 친 사람이 로그인한 것으로 세어진다.**
      final container = makeContainer();
      final repository =
          container.read(authRepositoryProvider) as FakeAuthRepository;
      repository.seedAccount(email: 'a@b.com', password: 'runi123!');

      await container
          .read(authControllerProvider.notifier)
          .signIn(email: 'a@b.com', password: 'wrong123!');

      expect(analytics.events, isEmpty);
    });

    test('이메일 로그인은 수단이 email이다', () async {
      final container = makeContainer();
      final repository =
          container.read(authRepositoryProvider) as FakeAuthRepository;
      repository.seedAccount(email: 'a@b.com', password: 'runi123!');

      await container
          .read(authControllerProvider.notifier)
          .signIn(email: 'a@b.com', password: 'runi123!');

      expect(analytics.paramsOf('login'), {'method': 'email'});
    });
  });
}
