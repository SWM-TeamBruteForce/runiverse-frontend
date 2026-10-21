import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/app/app.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/storage/sign_in_memory_store.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/app_update/data/fake_app_version_repository.dart';
import 'package:runiverse/features/app_update/presentation/app_version_provider.dart';
import 'package:runiverse/features/auth/data/fake_auth_repository.dart';
import 'package:runiverse/features/auth/domain/current_user.dart';
import 'package:runiverse/features/auth/domain/login_type.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/auth/presentation/auth_state.dart';
import 'package:runiverse/features/matching/data/fake_match_repository.dart';
import 'package:runiverse/features/matching/presentation/match_register_provider.dart';
import 'package:runiverse/features/profile/data/fake_profile_repository.dart';
import 'package:runiverse/features/profile/domain/nickname_change_failure.dart';
import 'package:runiverse/features/profile/presentation/profile_provider.dart';
import 'package:runiverse/features/session/data/fake_user_status_repository.dart';
import 'package:runiverse/features/session/presentation/user_status_provider.dart';

/// 닉네임을 바꾸면 **홈이 부르는 이름도 따라오는가.**
///
/// ## ⚠️ 이름의 출처가 화면마다 다르다
///
/// 프로필 탭은 [profileSummaryControllerProvider]를 보고, 홈은
/// [AuthSignedIn.user]를 본다(`home_page.dart`). 바꾼 값을 앞의 것에만
/// 넣으면 **프로필은 즉시 바뀌는데 홈은 앱을 다시 켤 때까지 옛 이름**이다 —
/// 저장소를 고쳐도 지금 떠 있는 상태는 모른다.
void main() {
  // 반환형을 적지 않는다. `Override`는 flutter_riverpod이 내보내지 않는 타입이라
  // 손으로 쓸 수가 없고, 추론은 된다.
  fakes({
    FakeProfileRepository? profile,
    LoginType? loginType = LoginType.local,
  }) => [
    tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
    signInMemoryStoreProvider.overrideWithValue(InMemorySignInMemoryStore()),
    // 로그인하면 셸이 유저 상태를 묻는다. 진짜를 두면 dio가 서버 주소를
    // 찾다 죽는다.
    userStatusRepositoryProvider.overrideWithValue(FakeUserStatusRepository()),
    // 홈의 매칭 버튼이 등록 화면을 띄울 수 있어야 한다. 같은 이유로 가짜다.
    matchRepositoryProvider.overrideWithValue(FakeMatchRepository()),
    authRepositoryProvider.overrideWithValue(
      FakeAuthRepository(latency: Duration.zero, loginType: loginType),
    ),
    profileRepositoryProvider.overrideWithValue(
      profile ?? FakeProfileRepository(),
    ),
  ];

  ProviderContainer makeContainer({
    FakeProfileRepository? profile,
    LoginType? loginType = LoginType.local,
  }) => ProviderContainer.test(
    overrides: fakes(profile: profile, loginType: loginType),
  );

  /// 로그인해서 `/me`까지 받아 둔다. 그 응답이 홈이 부르는 이름의 첫 출처다.
  Future<AuthSignedIn> signIn(ProviderContainer container) async {
    await container
        .read(authControllerProvider.notifier)
        .signIn(
          email: FakeAuthRepository.seedEmail,
          password: FakeAuthRepository.seedPassword,
        );
    return container.read(authControllerProvider) as AuthSignedIn;
  }

  AuthSignedIn signedIn(ProviderContainer container) =>
      container.read(authControllerProvider) as AuthSignedIn;

  test('⚠️ 닉네임을 바꾸면 홈이 부르는 이름도 바뀐다', () async {
    final container = makeContainer();
    final before = await signIn(container);
    // 가짜 서버가 이메일에서 지어낸 이름. 홈이 지금 부르는 값이다.
    expect(before.user?.nickname, '러너-test');

    final failure = await container
        .read(profileSummaryControllerProvider.notifier)
        .changeNickname('새이름');

    expect(failure, isNull);
    // 고치기 전에는 여기가 `러너-test`였다 — 프로필 탭만 바뀌고 홈은 그대로.
    expect(signedIn(container).user?.nickname, '새이름');
  });

  test('⚠️ 이름만 갈고 계정 정보는 남긴다', () async {
    // 새 [CurrentUser]를 만들면서 필드를 빠뜨리면 **설정 화면의 이메일과
    // 비밀번호 메뉴가 사라진다** — 그쪽은 `user`의 `email`·`loginType`을 읽는다.
    final container = makeContainer();
    await signIn(container);

    await container
        .read(profileSummaryControllerProvider.notifier)
        .changeNickname('새이름');

    final user = signedIn(container).user;
    expect(user?.email, FakeAuthRepository.seedEmail);
    expect(user?.loginType, LoginType.local);
    expect(user?.userId, isNotNull);
  });

  test('바꾸지 못했으면 그대로 둔다', () async {
    final container = makeContainer(
      profile: FakeProfileRepository(
        nicknameFailure: NicknameChangeFailure.taken,
      ),
    );
    await signIn(container);

    final failure = await container
        .read(profileSummaryControllerProvider.notifier)
        .changeNickname('남의이름');

    expect(failure, NicknameChangeFailure.taken);
    // 서버가 안 받아준 이름을 화면에 걸면, 앱을 다시 켤 때 되돌아간다.
    expect(signedIn(container).user?.nickname, '러너-test');
  });

  testWidgets('⚠️ 홈이 그 자리에서 새 이름을 부른다', (tester) async {
    // 위 셋은 상태만 본다. 보고된 증상은 **화면**이라, 홈이 그 상태를 실제로
    // 다시 그리는지까지 한 번 본다 — 홈은 `authControllerProvider`를 watch 한다.
    //
    // ⚠️ **여기서는 로그인 과정을 밟지 않는다.** `testWidgets`의 시계는
    // 가짜라서 `signIn`이 기다리는 타이머가 영영 깨어나지 않는다(테스트가
    // 5분을 버티다 "did not complete"로 끝났다). 다른 화면 테스트들처럼
    // 로그인한 상태를 처음부터 세워 둔다. 컨트롤러는 진짜 그대로다 —
    // `build()`만 덮으므로 `applyNickname`은 실제 코드가 돈다.
    final container = ProviderContainer.test(
      overrides: [
        // 스플래시가 **토큰 복원보다 먼저** 앱 버전을 확인한다. 진짜를 두면
        // dio가 서버 주소를 찾다 죽고, 판정을 못 받은 화면은 넘어가지 않는다.
        appVersionRepositoryProvider.overrideWithValue(
          FakeAppVersionRepository(),
        ),
        ...fakes(),
        authControllerProvider.overrideWith(
          () => _SignedIn(
            const AuthSignedIn(
              'u-1',
              isOnboarded: true,
              user: CurrentUser(
                userId: 'u-1',
                isOnboarded: true,
                nickname: '러너-test',
              ),
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const RuniverseApp(initialLocation: AppRoutes.home),
      ),
    );
    // ⚠️ `pumpAndSettle`을 쓰지 않는다. 홈은 1초마다 도는 시계를 달고 있어
    // **영영 가라앉지 않는다.** 프레임 몇 장만 보낸다.
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('러너-test님'), findsOneWidget);

    await container
        .read(profileSummaryControllerProvider.notifier)
        .changeNickname('새이름');
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('새이름님'), findsOneWidget);
    // 앱을 다시 켜야 바뀌던 것이 이 줄이다.
    expect(find.textContaining('러너-test'), findsNothing);
  });

  test('로그인 상태가 아니면 아무 일도 하지 않는다', () async {
    // 프로필 탭에 닿으려면 로그인해야 하지만, 상태를 만들어 내는 길을
    // 열어 두면 로그인하지 않은 사람이 홈에 들어간다.
    final container = makeContainer();

    await container
        .read(profileSummaryControllerProvider.notifier)
        .changeNickname('새이름');

    expect(container.read(authControllerProvider), isNot(isA<AuthSignedIn>()));
  });
}

/// 로그인한 상태로 시작하는 컨트롤러. **`build()`만 덮는다** — 나머지는
/// 진짜 [AuthController]라서 `applyNickname`은 실제 코드가 돈다.
class _SignedIn extends AuthController {
  _SignedIn(this.initial);

  final AuthState initial;

  @override
  AuthState build() => initial;
}
