import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/app/app.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/widgets/v2/app_tab_bar.dart';
import 'package:runiverse/features/matching/data/fake_match_repository.dart';
import 'package:runiverse/features/matching/presentation/match_register_provider.dart';
import 'package:runiverse/features/record/data/fake_run_record_repository.dart';
import 'package:runiverse/features/record/presentation/record_provider.dart';
import 'package:runiverse/core/analytics/analytics.dart';
import 'package:runiverse/core/analytics/fake_analytics.dart';
import 'package:runiverse/core/storage/body_profile_provider.dart';
import 'package:runiverse/core/storage/body_profile_store.dart';
import 'package:runiverse/core/storage/sign_in_memory_store.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/data/fake_auth_repository.dart';
import 'package:runiverse/features/auth/data/fake_oauth_code_source.dart';
import 'package:runiverse/features/auth/domain/auth_failure.dart';
import 'package:runiverse/features/auth/domain/oauth_provider.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/auth/presentation/auth_state.dart';
import 'package:runiverse/features/session/data/fake_location_repository.dart';
import 'package:runiverse/features/session/data/fake_step_repository.dart';
import 'package:runiverse/features/session/data/fake_user_status_repository.dart';
import 'package:runiverse/features/session/domain/location_repository.dart';
import 'package:runiverse/features/session/domain/permission_access.dart';
import 'package:runiverse/features/session/presentation/run_session_provider.dart';
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

  group('screen_view', () {
    // ⚠️ **이 묶음이 실제 결함을 잡아 만들어졌다.**
    //
    // 처음에는 `FirebaseAnalyticsObserver` 를 라우터와 탭 브랜치 넷에 꽂았는데,
    // 기기에서 보니 **탭을 다시 눌러도 아무것도 안 찍혔다.**
    // `StatefulShellRoute.indexedStack` 은 탭을 바꿔도 라우트를 밀어 넣지 않아
    // 관찰자가 불리지 않는다. 게다가 첫 방문은 루트·브랜치 관찰자가 각자 적어
    // **두 번** 찍혔다.
    //
    // 눈으로도 다른 테스트로도 드러나지 않는 종류라 여기서 센다.
    Future<void> pumpApp(WidgetTester tester) async {
      analytics = FakeAnalytics();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            analyticsProvider.overrideWithValue(analytics),
            matchRepositoryProvider.overrideWithValue(FakeMatchRepository()),
            // 기록 탭이 들어서면서 목록을 받아온다. 진짜를 두면 dio 가 서버
            // 주소를 찾다 죽는다 — 테스트에는 주소가 없다.
            runRecordRepositoryProvider.overrideWithValue(
              FakeRunRecordRepository(),
            ),
            userStatusRepositoryProvider.overrideWithValue(
              FakeUserStatusRepository(),
            ),
          ],
          child: const RuniverseApp(initialLocation: AppRoutes.home),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> tapTab(WidgetTester tester, String label) async {
      // ⚠️ **탭 바 안에서 찾는다.** 기록 탭으로 가면 그 화면의 제목도
      // `기록` 이라 라벨이 둘이 되어 `tap()` 이 어느 쪽인지 모른다고 멈춘다.
      await tester.tap(
        find.descendant(
          of: find.byType(AppTabBarV2),
          matching: find.bySemanticsLabel(label),
        ),
      );
      await tester.pumpAndSettle();
    }

    List<String> screens() => [
      for (final e in analytics.events)
        if (e.$1 == 'screen_view') e.$2!['name']! as String,
    ];

    testWidgets('첫 화면이 한 번 남는다', (tester) async {
      await pumpApp(tester);

      // ⚠️ **두 번이 아니다.** 관찰자를 겹쳐 꽂았을 때는 두 번이었다.
      expect(screens(), ['home']);
    });

    testWidgets('⚠️ 탭을 다시 눌러도 남는다', (tester) async {
      // 관찰자 방식에서 통째로 빠지던 자리다. 이게 빠지면 탭 사이 이동을
      // 셀 수 없어 **어느 탭에서 머무는지**를 못 본다.
      await pumpApp(tester);

      await tapTab(tester, AppStrings.tabRecord);
      await tapTab(tester, AppStrings.tabHome);
      await tapTab(tester, AppStrings.tabRecord);

      expect(screens(), ['home', 'record', 'home', 'record']);
    });

    testWidgets('같은 화면이 연달아 남지는 않는다', (tester) async {
      await pumpApp(tester);

      await tapTab(tester, AppStrings.tabRecord);
      await tapTab(tester, AppStrings.tabRecord);

      expect(screens(), ['home', 'record']);
    });
  });

  group('user_id', () {
    // 로그인 성공 자리가 아니라 **로그인 상태**를 듣는다. 앱을 다시 켜 자동
    // 로그인된 사람은 로그인 성공을 거치지 않는다.
    Future<ProviderContainer> pumpApp(WidgetTester tester) async {
      analytics = FakeAnalytics();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            analyticsProvider.overrideWithValue(analytics),
            tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
            signInMemoryStoreProvider.overrideWithValue(
              InMemorySignInMemoryStore(),
            ),
            // 로그인·로그아웃이 신체 정보를 읽고 지운다. 진짜는 플랫폼 채널을 부른다.
            bodyProfileStoreProvider.overrideWithValue(
              InMemoryBodyProfileStore(),
            ),
            authRepositoryProvider.overrideWithValue(
              FakeAuthRepository(latency: Duration.zero),
            ),
            matchRepositoryProvider.overrideWithValue(FakeMatchRepository()),
            runRecordRepositoryProvider.overrideWithValue(
              FakeRunRecordRepository(),
            ),
            userStatusRepositoryProvider.overrideWithValue(
              FakeUserStatusRepository(),
            ),
          ],
          child: const RuniverseApp(initialLocation: AppRoutes.home),
        ),
      );
      await tester.pumpAndSettle();
      return ProviderScope.containerOf(
        tester.element(find.byType(RuniverseApp)),
      );
    }

    testWidgets('로그인하면 걸고, 로그아웃하면 뗀다', (tester) async {
      final container = await pumpApp(tester);
      final repository =
          container.read(authRepositoryProvider) as FakeAuthRepository;
      repository.seedAccount(email: 'a@b.com', password: 'runi123!');

      // ⚠️ `runAsync` 로 감싼다. 가짜 저장소의 지연(`Future.delayed`)은 위젯
      // 테스트의 가짜 시계에서 저절로 흐르지 않아, 그냥 기다리면 영영 멈춘다.
      final controller = container.read(authControllerProvider.notifier);
      await tester.runAsync(
        () => controller.signIn(email: 'a@b.com', password: 'runi123!'),
      );
      await tester.pump();
      final signedIn = container.read(authControllerProvider) as AuthSignedIn;

      await tester.runAsync(controller.signOut);
      await tester.pump();

      expect(analytics.userIds, [signedIn.userId, null]);
    });

    testWidgets('⚠️ 로그인 여부를 아직 모르면 아무것도 걸지 않는다', (tester) async {
      // 앱이 막 뜬 순간이다. 여기서 `null` 을 걸면 이전 실행의 회원 ID 를
      // 쓸데없이 한 번 떼고 다시 거는 셈이다.
      await pumpApp(tester);

      expect(analytics.userIds, isEmpty);
    });
  });

  group('permission_result', () {
    // 러닝 준비가 묻는 순서대로 남는가 — 위치, 알림, 신체 활동.
    Future<List<String>> prepare({
      LocationAccess location = LocationAccess.granted,
      PermissionAccess? notification = PermissionAccess.granted,
      bool activity = true,
    }) async {
      analytics = FakeAnalytics();
      final container = ProviderContainer.test(
        overrides: [
          analyticsProvider.overrideWithValue(analytics),
          locationRepositoryProvider.overrideWithValue(
            FakeLocationRepository(
              access: location,
              notification: notification,
            ),
          ),
          stepRepositoryProvider.overrideWithValue(
            FakeStepRepository(granted: activity),
          ),
        ],
      );
      await container.read(runSessionControllerProvider.notifier).prepare();
      // 걸음 권한은 기다리지 않고 묻는다. 한 바퀴 돌려 마저 남게 한다.
      await Future<void>.delayed(Duration.zero);
      return [
        for (final e in analytics.events)
          if (e.$1 == 'permission_result')
            '${e.$2!['permission']}:${e.$2!['result']}',
      ];
    }

    test('허용하면 셋 다 남는다', () async {
      expect(await prepare(), [
        'location:granted',
        'notification:granted',
        'activity:granted',
      ]);
    });

    test('⚠️ 위치를 거절하면 위치만 남는다', () async {
      // 러닝이 거기서 멈춘다. 알림·걸음은 묻지도 않았다.
      expect(await prepare(location: LocationAccess.deniedForever), [
        'location:denied_forever',
      ]);
    });

    test('기기 위치 기능이 꺼져 있으면 권한과 따로 센다', () async {
      expect(await prepare(location: LocationAccess.serviceDisabled), [
        'location:service_disabled',
      ]);
    });

    test('걸음을 거절해도 남는다', () async {
      expect(await prepare(activity: false), [
        'location:granted',
        'notification:granted',
        'activity:denied',
      ]);
    });

    test('알림을 묻지 않는 플랫폼에서는 알림이 남지 않는다', () async {
      expect(await prepare(notification: null), [
        'location:granted',
        'activity:granted',
      ]);
    });
  });
}
