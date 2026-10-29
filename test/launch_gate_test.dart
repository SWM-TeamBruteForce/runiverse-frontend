import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/app/app.dart';
import 'package:runiverse/core/storage/consent_store.dart';
import 'package:runiverse/core/storage/sign_in_memory_store.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/features/app_update/data/fake_app_version_repository.dart';
import 'package:runiverse/features/app_update/presentation/app_version_provider.dart';
import 'package:runiverse/features/auth/data/fake_auth_repository.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/home/presentation/home_page.dart';
import 'package:runiverse/features/matching/data/fake_match_stream.dart';
import 'package:runiverse/features/matching/domain/match_event.dart';
import 'package:runiverse/features/matching/domain/room_info.dart';
import 'package:runiverse/features/matching/presentation/match_countdown_page.dart';
import 'package:runiverse/features/matching/presentation/match_room_page.dart';
import 'package:runiverse/features/matching/presentation/match_room_provider.dart';
import 'package:runiverse/features/onboarding/presentation/splash_page.dart';
import 'package:runiverse/features/session/data/fake_user_status_repository.dart';
import 'package:runiverse/features/session/domain/user_status.dart';
import 'package:runiverse/features/session/presentation/user_status_provider.dart';

/// 출발 시각이 오면 **어느 화면에 있든** 러닝으로 데려간다.
///
/// ## ⚠️ 이게 없으면 러닝을 통째로 놓친다
///
/// 카운트다운으로 들어가는 길이 대기방 화면 안에만 있었다. 신청해 두고 홈으로
/// 한 번만 나오면 **시작 시각이 지나도록 아무 일도 일어나지 않았다.** 매칭은
/// 예약이라 기다리는 동안 다른 화면을 보는 것이 자연스럽다.
void main() {
  final startAt = DateTime(2026, 10, 14, 19);

  RoomInfo room(RoomStatus status, {DateTime? at}) => RoomInfo(
    runningRoomId: 125,
    status: status,
    scheduledStartAt: at ?? startAt,
    players: const [
      RoomPlayer(userId: 'u-1', nickname: '나', isDeleted: false),
      RoomPlayer(userId: 'u-2', nickname: '러너', isDeleted: false),
    ],
  );

  /// 홈에 선 앱. 돌려주는 것으로 서버 이벤트를 민다.
  Future<FakeMatchStream> pumpHome(WidgetTester tester) async {
    final tokens = InMemoryTokenStore();
    await tokens.saveSession(
      userId: 'u-1',
      accessToken: 'a-1',
      refreshToken: 'r-1',
      isOnboarded: true,
    );
    final stream = FakeMatchStream();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // 스플래시가 **토큰 복원보다 먼저** 앱 버전을 확인한다. 진짜를 두면
          // dio가 서버 주소를 찾다 죽고, 판정을 못 받은 화면은 넘어가지 않는다.
          appVersionRepositoryProvider.overrideWithValue(
            FakeAppVersionRepository(),
          ),
          tokenStoreProvider.overrideWithValue(tokens),
          signInMemoryStoreProvider.overrideWithValue(
            InMemorySignInMemoryStore(),
          ),
          consentStoreProvider.overrideWithValue(InMemoryConsentStore()),
          userStatusRepositoryProvider.overrideWithValue(
            FakeUserStatusRepository(
              status: UserStatusWaiting(
                runningRoomId: 125,
                type: RoomType.match,
                scheduledStartAt: startAt,
              ),
            ),
          ),
          matchStreamProvider.overrideWithValue(stream),
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository(latency: Duration.zero)
              ..seedSession(accessToken: 'a-1', refreshToken: 'r-1'),
          ),
        ],
        child: const RuniverseApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SplashPage));
    await tester.pumpAndSettle();
    return stream;
  }

  /// 서버가 방을 확정했다고 알린다. [inSeconds] 뒤에 출발한다.
  Future<void> confirm(
    WidgetTester tester,
    FakeMatchStream stream, {
    required int inSeconds,
  }) async {
    stream.emit(
      MatchRoomUpdated(
        room(
          RoomStatus.matched,
          at: DateTime.now().add(Duration(seconds: inSeconds)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 게이트의 1초 시계를 한 번 돌린다.
  Future<void> tick(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  testWidgets('⚠️ 1분 전이면 홈에 있어도 로비로 옮긴다', (tester) async {
    // ⚠️ **이게 안 되면 신청해 놓고 홈에 있던 사람은 러닝을 놓친다.**
    final stream = await pumpHome(tester);
    expect(find.byType(HomePage), findsOneWidget);

    await confirm(tester, stream, inSeconds: 55);
    await tick(tester);

    // 안내가 먼저 뜬다 — 화면이 갑자기 바뀌면 앱이 튄 줄 안다.
    expect(find.text(AppStrings.matchLaunchNoticeTitle), findsOneWidget);

    // 띄워 둔 시간이 지나면 스스로 옮긴다. 누를 것은 없다.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(find.byType(MatchRoomPage), findsOneWidget);
    expect(find.text(AppStrings.matchLaunchNoticeTitle), findsNothing);
  });

  testWidgets('⚠️ 30초 전에 다른 화면이면 카운트다운으로 직행한다', (tester) async {
    // 안내를 못 봤거나 앱이 백그라운드였을 수 있다. **그래도 출발한다.**
    final stream = await pumpHome(tester);

    await confirm(tester, stream, inSeconds: 25);
    await tick(tester);

    expect(find.byType(MatchCountdownPage), findsOneWidget);
  });

  testWidgets('모집 중에는 아무 일도 하지 않는다', (tester) async {
    // 아직 확정되지 않았다. 시작 시각이 가까워도 데려갈 곳이 없다.
    final stream = await pumpHome(tester);

    stream.emit(
      MatchRoomUpdated(
        room(
          RoomStatus.matching,
          at: DateTime.now().add(const Duration(seconds: 20)),
        ),
      ),
    );
    // ⚠️ **여기서는 `tick`을 쓰지 못한다.** 그쪽이 `pumpAndSettle`을 부르는데,
    // 모집 중 히어로는 둘레 원이 **영원히 맴돌아** 화면이 잠잠해지지
    // 않는다(`home_waiting.dart`). 로비로 넘어가는 다른 테스트는 그 화면을
    // 떠나므로 `tick` 그대로 쓴다.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(HomePage), findsOneWidget);
    expect(find.text(AppStrings.matchLaunchNoticeTitle), findsNothing);
  });
}
