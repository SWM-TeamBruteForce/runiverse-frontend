import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/app/app.dart';
import 'package:runiverse/core/storage/consent_store.dart';
import 'package:runiverse/core/storage/sign_in_memory_store.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/features/auth/data/fake_auth_repository.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/home/presentation/home_page.dart';
import 'package:runiverse/features/matching/data/fake_match_stream.dart';
import 'package:runiverse/features/matching/presentation/match_room_provider.dart';
import 'package:runiverse/features/onboarding/presentation/splash_page.dart';
import 'package:runiverse/features/session/data/fake_user_status_repository.dart';
import 'package:runiverse/features/session/domain/user_status.dart';
import 'package:runiverse/features/session/domain/user_status_repository.dart';
import 'package:runiverse/features/session/presentation/user_status_provider.dart';

/// 서버 상태에 따라 **앱이 어디로 여는가.**
///
/// 잘못 열면 달리던 사람이 홈에 남아 기록이 끊기거나, 쉬는 사람이 러닝 화면으로
/// 끌려간다. 스플래시가 판정하는 자리라 여기서 지킨다.
void main() {
  final startAt = DateTime(2026, 9, 15, 19);

  Future<FakeUserStatusRepository> pumpApp(
    WidgetTester tester, {
    required UserStatus status,
    UserStatusFailure? failure,
  }) async {
    final tokens = InMemoryTokenStore();
    await tokens.saveSession(
      userId: 'u-1',
      accessToken: 'a-1',
      refreshToken: 'r-1',
      isOnboarded: true,
    );

    final statuses = FakeUserStatusRepository(status: status, failure: failure);
    final auth = FakeAuthRepository(latency: Duration.zero)
      ..seedSession(accessToken: 'a-1', refreshToken: 'r-1');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStoreProvider.overrideWithValue(tokens),
          signInMemoryStoreProvider.overrideWithValue(
            InMemorySignInMemoryStore(),
          ),
          consentStoreProvider.overrideWithValue(InMemoryConsentStore()),
          userStatusRepositoryProvider.overrideWithValue(statuses),
          // 대기·확정이면 앱이 곧바로 매칭 스트림에 붙는다. 진짜를 두면
          // dio가 서버 주소를 찾다 죽는다.
          matchStreamProvider.overrideWithValue(FakeMatchStream()),
          authRepositoryProvider.overrideWithValue(auth),
        ],
        child: const RuniverseApp(),
      ),
    );
    await tester.pumpAndSettle();

    // 스플래시를 눌러 갈림길을 앞당긴다. 1.6초를 실제로 기다릴 이유가 없다.
    await tester.tap(find.byType(SplashPage));
    await tester.pumpAndSettle();
    return statuses;
  }

  testWidgets('IDLE이면 홈이다', (tester) async {
    await pumpApp(tester, status: const UserStatusIdle());

    expect(find.byType(HomePage), findsOneWidget);
    // 기본 히어로다 — 매칭 문구가 없다.
    expect(find.text(AppStrings.homeMatchCta), findsOneWidget);
    expect(find.text(AppStrings.homeMatchWaiting), findsNothing);
  });

  testWidgets('⚠️ 매칭 대기면 히어로가 흔적을 남긴다', (tester) async {
    // 방 정보는 스트림이 나르므로 아직 없다. 그래도 기본 히어로를 보여주면
    // 신청이 사라진 줄 알고 다시 누르고, 서버는 409로 막는다.
    await pumpApp(
      tester,
      status: UserStatusWaiting(runningRoomId: 1, scheduledStartAt: startAt),
    );

    expect(find.byType(HomePage), findsOneWidget);
    expect(find.text(AppStrings.homeMatchWaiting), findsOneWidget);
    expect(find.text(AppStrings.homeMatchPending), findsOneWidget);
    // ⚠️ 다시 신청하러 갈 문이 열려 있으면 안 된다.
    expect(find.text(AppStrings.homeMatchCta), findsNothing);
  });

  testWidgets('⚠️ 매칭 확정도 마찬가지다', (tester) async {
    await pumpApp(
      tester,
      status: UserStatusReady(
        runningRoomId: 1,
        isSolo: false,
        scheduledStartAt: startAt,
      ),
    );

    expect(find.text(AppStrings.homeMatchWaiting), findsOneWidget);
  });

  testWidgets('솔로 준비 중에는 기본 히어로다', (tester) async {
    // 솔로는 매칭이 아니다. 매칭 중이라고 말하면 거짓이다.
    await pumpApp(
      tester,
      status: UserStatusReady(
        runningRoomId: 1,
        isSolo: true,
        scheduledStartAt: startAt,
      ),
    );

    expect(find.text(AppStrings.homeMatchWaiting), findsNothing);
  });

  testWidgets('⚠️ 상태를 못 읽어도 홈으로 들여보낸다', (tester) async {
    // 여기서 막으면 상태 조회 하나가 앱 전체를 잠근다. 로그인은 이미 끝났다.
    await pumpApp(
      tester,
      status: const UserStatusIdle(),
      failure: UserStatusFailure.network,
    );

    expect(find.byType(HomePage), findsOneWidget);
    // 모르는 것을 "진행 중"으로 그리지 않는다.
    expect(find.text(AppStrings.homeMatchWaiting), findsNothing);
  });

  testWidgets('⚠️ 진입에 한 번은 반드시 묻는다', (tester) async {
    // 안 물으면 진행 중인 러닝을 영영 못 찾는다.
    final statuses = await pumpApp(tester, status: const UserStatusIdle());

    expect(statuses.calls, greaterThanOrEqualTo(1));
  });
}
