import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:runiverse/app/app.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/network/ws_client.dart';
import 'package:runiverse/core/network/ws_message.dart';
import 'package:runiverse/core/storage/consent_store.dart';
import 'package:runiverse/core/storage/sign_in_memory_store.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/features/app_update/data/fake_app_version_repository.dart';
import 'package:runiverse/features/app_update/presentation/app_version_provider.dart';
import 'package:runiverse/features/auth/data/fake_auth_repository.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/home/presentation/home_page.dart';
import 'package:runiverse/features/chat/data/fake_chat_repository.dart';
import 'package:runiverse/features/chat/presentation/chat_page.dart';
import 'package:runiverse/features/chat/presentation/chat_provider.dart';
import 'package:runiverse/features/matching/data/fake_match_stream.dart';
import 'package:runiverse/features/matching/domain/match_event.dart';
import 'package:runiverse/features/matching/domain/room_info.dart';
import 'package:runiverse/features/matching/presentation/match_countdown_page.dart';
import 'package:runiverse/features/matching/presentation/match_room_page.dart';
import 'package:runiverse/features/matching/presentation/match_room_provider.dart';
import 'package:runiverse/features/notification/data/fake_app_stream.dart';
import 'package:runiverse/features/notification/data/fake_notification_repository.dart';
import 'package:runiverse/features/notification/presentation/notification_provider.dart';
import 'package:runiverse/features/onboarding/presentation/splash_page.dart';
import 'package:runiverse/features/session/data/fake_location_repository.dart';
import 'package:runiverse/features/session/data/fake_step_repository.dart';
import 'package:runiverse/features/session/data/fake_track_repository.dart';
import 'package:runiverse/features/session/data/fake_user_status_repository.dart';
import 'package:runiverse/features/session/domain/finish_outcome.dart';
import 'package:runiverse/features/session/domain/run_metrics.dart';
import 'package:runiverse/features/session/domain/run_numbers.dart';
import 'package:runiverse/features/session/domain/run_progress.dart';
import 'package:runiverse/features/session/domain/run_session_state.dart';
import 'package:runiverse/features/session/domain/run_snapshot.dart';
import 'package:runiverse/features/session/domain/running_channel.dart';
import 'package:runiverse/features/session/domain/track_point.dart';
import 'package:runiverse/features/session/domain/user_status.dart';
import 'package:runiverse/features/session/presentation/run_session_page.dart';
import 'package:runiverse/features/session/presentation/run_session_provider.dart';
import 'package:runiverse/features/session/presentation/running_connection_provider.dart';
import 'package:runiverse/features/session/presentation/user_status_provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

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
  Future<FakeMatchStream> pumpHome(
    WidgetTester tester, {
    RunSessionState? session,
    bool stubChat = false,
  }) async {
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
          if (session != null)
            runSessionControllerProvider.overrideWith(() => _Session(session)),
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
          // 채팅 버튼이 보이는 순간 chatProvider가 서고, 그것이 진짜 저장소를
          // 세운다 — 서버 주소가 없는 테스트에서는 거기서 죽는다.
          chatRepositoryProvider.overrideWithValue(FakeChatRepository()),
          // 채팅 화면을 여는 테스트. 진짜 채팅 상태는 화면이 닫힐 때
          // (`ChatPage.dispose`의 `close`) 디버그 단정을 남긴다.
          if (stubChat) chatProvider.overrideWith(_StubChat.new),
          // 셸이 앱 스트림을 만들고, 로그인돼 있으면 첫
          // 페이지도 받는다. 진짜를 두면 dio가 서버 주소를 찾다 죽는다.
          appStreamProvider.overrideWithValue(FakeAppStream()),
          notificationRepositoryProvider.overrideWithValue(
            FakeNotificationRepository(),
          ),
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository(latency: Duration.zero)
              ..seedSession(accessToken: 'a-1', refreshToken: 'r-1'),
          ),
          // 출발해 러닝 화면까지 가는 테스트가 있다. 갈아 끼우지 않으면 위치·
          // 걸음 센서·DB·소켓을 진짜로 열려다 죽는다.
          locationRepositoryProvider.overrideWithValue(
            FakeLocationRepository(),
          ),
          trackRepositoryProvider.overrideWithValue(FakeTrackRepository()),
          stepRepositoryProvider.overrideWithValue(FakeStepRepository()),
          runningChannelFactoryProvider.overrideWithValue(
            (_) => _SilentChannel(),
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

  group('로비로 옮길 때 러닝', () {
    const metrics = RunMetrics(
      distanceMeters: 1200,
      elapsed: Duration(minutes: 7),
    );

    Future<RunSessionState> sessionAfterMove(
      WidgetTester tester,
      RunSessionState session,
    ) async {
      final stream = await pumpHome(tester, session: session);
      await confirm(tester, stream, inSeconds: 55);
      await tick(tester);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(find.byType(MatchRoomPage), findsOneWidget);
      return ProviderScope.containerOf(
        tester.element(find.byType(MatchRoomPage)),
      ).read(runSessionControllerProvider);
    }

    testWidgets('⚠️ 끝난 러닝은 비운다', (tester) async {
      // 요약을 닫은 것과 같다. 안 비우면 폰은 대기방인데 워치에 결과가 남는다.
      final session = await sessionAfterMove(
        tester,
        RunFinished(
          metrics: metrics,
          startedAt: DateTime(2026, 11, 4, 8),
          endedAt: DateTime(2026, 11, 4, 9),
        ),
      );

      expect(session, isA<RunIdle>());
    });

    testWidgets('⚠️ 달리는 중인 러닝은 비우지 않는다', (tester) async {
      final session = await sessionAfterMove(tester, const RunRunning(metrics));

      expect(session, isA<RunRunning>());
    });
  });

  testWidgets('⚠️ 30초 전에 다른 화면이면 카운트다운으로 직행한다', (tester) async {
    // 안내를 못 봤거나 앱이 백그라운드였을 수 있다. **그래도 출발한다.**
    final stream = await pumpHome(tester);

    await confirm(tester, stream, inSeconds: 25);
    await tick(tester);

    expect(find.byType(MatchCountdownPage), findsOneWidget);
  });

  testWidgets('⚠️ 채팅을 연 채 30초 선을 넘어도 대기방이 뒤에 남지 않는다', (tester) async {
    // 1분 전 안내로 대기방에 온 뒤 채팅을 다시 열었다. 게이트가 채팅을
    // 카운트다운으로 갈아치우면 대기방이 스택에 남고, 러닝이 시작돼 방이
    // 사라지는 순간 그 대기방이 러닝 화면을 닫는다(`MatchRoomPage._closeChat`).
    //
    // ⚠️ 두 1초 시계 중 **게이트가 먼저 울게** 시각을 맞춘다. 대기방이 먼저
    // 울면 고치기 전 코드도 통과한다. 남은 시간은 실제 시계로 재서 pump로는
    // 줄지 않으므로 `RunningReady`로 출발을 당긴다.
    final stream = await pumpHome(tester, stubChat: true);
    stream.emit(
      MatchRoomUpdated(
        room(
          RoomStatus.matched,
          at: DateTime.now().add(const Duration(seconds: 55)),
        ),
      ),
    );
    await tester.pump();
    // 게이트 시계가 지금(t0) 선다. t0+1, t0+2, ... 에 운다.
    final t0 = tester.binding.clock.now();
    Future<void> pumpTo(int ms) => tester.pump(
      t0.add(Duration(milliseconds: ms)).difference(tester.binding.clock.now()),
    );

    // t0+1 안내 → t0+3 대기방으로 옮긴다. 새 대기방 시계는 t0+4.5, 5.5, ...
    await pumpTo(1000);
    await pumpTo(3500);
    for (final ms in [3600, 3700, 3800]) {
      await pumpTo(ms);
    }
    expect(find.byType(MatchRoomPage), findsOneWidget);

    await tester.tap(find.byKey(MatchRoomPage.chatKey));
    for (final ms in [3900, 4000, 4100, 4200, 4300]) {
      await pumpTo(ms);
    }
    expect(find.byType(ChatPage), findsOneWidget);

    // t0+4.6 에 30초 선을 넘긴다. 다음에 먼저 우는 것은 게이트(t0+5)다.
    await pumpTo(4600);
    stream.emit(
      RunningReady(
        runningRoomId: 125,
        scheduledStartAt: DateTime.now().add(const Duration(seconds: 25)),
        startsInMs: 25000,
      ),
    );
    for (var ms = 4700; ms <= 5000; ms += 100) {
      await pumpTo(ms);
    }
    // 게이트가 운 직후다. 아직 아무도 넘기지 않았어야 한다 — 여기서 이미
    // 카운트다운이면 대기방이 먼저 울도록 시각이 어긋난 것이고, 그러면 이
    // 테스트는 고치기 전 코드도 통과시킨다.
    expect(find.byType(MatchCountdownPage), findsNothing);
    for (var ms = 5100; ms <= 6000; ms += 100) {
      await pumpTo(ms);
    }

    expect(find.byType(MatchCountdownPage), findsOneWidget);
    expect(find.byType(ChatPage, skipOffstage: false), findsNothing);
    expect(find.byType(MatchRoomPage, skipOffstage: false), findsNothing);
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

  /// 확정된 대기방·출발 대기실·러닝 화면에서만 화면을 켜 둔다.
  ///
  /// ⚠️ 러닝 화면은 더 이상 스스로 켜지 않는다. 여기가 깨지면 달리는 중에
  /// 화면이 꺼져도 다른 테스트는 모두 통과한다.
  group('화면 켜 두기', () {
    late _FakeWakelock wakelock;

    setUp(() {
      wakelock = _FakeWakelock();
      wakelockPlusPlatformInstance = wakelock;
    });

    tearDown(() {
      wakelockPlusPlatformInstance = WakelockPlusPlatformInterface.instance;
    });

    testWidgets('⚠️ 대기실에서 러닝으로 넘어가도 켜 둔다', (tester) async {
      // ⚠️ 러닝 화면은 스스로 켜지 않는다. 대기실이 켠 것이 바꿔치기
      // (`pushReplacement`) 뒤에도 꺼지지 않아야 달리는 중에 화면이 산다.
      final stream = await pumpHome(tester);

      // 출발 시각이 이미 됐다. 게이트가 대기실로 보내면 대기실이 바로 쏜다.
      await confirm(tester, stream, inSeconds: 0);
      await tick(tester);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.byType(RunSessionPage), findsOneWidget);
      expect(wakelock.calls, [true]);
    });

    testWidgets('⚠️ 모집 중인 대기방은 켜지 않다가 확정되는 순간 켠다', (tester) async {
      final stream = await pumpHome(tester);
      stream.emit(
        MatchRoomUpdated(
          room(
            RoomStatus.matching,
            at: DateTime.now().add(const Duration(minutes: 5)),
          ),
        ),
      );
      // 모집 중 히어로가 영원히 맴돌아 `pumpAndSettle`을 쓰지 못한다
      // (위 「모집 중에는 아무 일도 하지 않는다」와 같다).
      await tester.pump();
      GoRouter.of(
        tester.element(find.byType(HomePage)),
      ).push(AppRoutes.matchRoom);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.byType(MatchRoomPage), findsOneWidget);
      expect(wakelock.calls, isEmpty);

      stream.emit(
        MatchRoomUpdated(
          room(
            RoomStatus.matched,
            at: DateTime.now().add(const Duration(minutes: 5)),
          ),
        ),
      );
      await tester.pump();

      expect(wakelock.calls, [true]);
    });

    testWidgets('⚠️ 대기실에서 방이 사라지면 끈다', (tester) async {
      // 출발할 방이 없어 대기실에 남는다. 켜 두면 앱을 끌 때까지 화면이 안
      // 꺼진다.
      final stream = await pumpHome(tester);
      await confirm(tester, stream, inSeconds: 25);
      await tick(tester);
      expect(find.byType(MatchCountdownPage), findsOneWidget);

      stream.emit(MatchRoomUpdated(room(RoomStatus.cancelled)));
      await tester.pump();

      expect(wakelock.calls, [true, false]);
    });

    testWidgets('⚠️ 확정된 대기방에서 채팅을 열어도 켜 둔다', (tester) async {
      // 채팅도 대기방이다. 채팅을 연 채 화면이 꺼지면 위 이유로 출발이 밀린다.
      final stream = await pumpHome(tester, stubChat: true);
      await confirm(tester, stream, inSeconds: 300);
      GoRouter.of(
        tester.element(find.byType(HomePage)),
      ).push(AppRoutes.matchRoom);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(MatchRoomPage.chatKey));
      await tester.pumpAndSettle();

      expect(find.byType(ChatPage), findsOneWidget);
      expect(wakelock.calls, [true]);
    });
  });
}

/// 비어 있는 채팅. 여기서는 채팅 화면이 떠 있는지만 본다.
class _StubChat extends ChatController {
  @override
  ChatState build() => const ChatState();

  @override
  Future<void> connect(int runningRoomId, {int limit = 50}) async {}

  @override
  Future<void> reload() async {}

  @override
  void open() {}

  @override
  void close() {}
}

/// 화면 켜짐을 기기에 보내는 대신 받은 순서대로 적는다. 테스트에는 플랫폼
/// 채널이 없어 진짜를 두면 보낼 곳이 없다.
class _FakeWakelock extends WakelockPlusPlatformInterface {
  final calls = <bool>[];

  @override
  Future<void> toggle({required bool enable}) async => calls.add(enable);

  @override
  Future<bool> get enabled async => calls.isNotEmpty && calls.last;
}

/// 아무것도 보내지 않는 러닝 연결. 여기서는 러닝 화면에 닿는지만 본다.
class _SilentChannel implements RunningChannel {
  @override
  Stream<WsConnectionState> get states => const Stream.empty();

  @override
  WsConnectionState get state => WsConnectionState.connected;

  @override
  Stream<WsErrorCode> get errors => const Stream.empty();

  @override
  Stream<RunProgress> get progress => const Stream.empty();

  @override
  Stream<RunCombo> get combos => const Stream.empty();

  @override
  Stream<void> get finished => const Stream.empty();

  @override
  Stream<RunSnapshot> get snapshots => const Stream.empty();

  @override
  Stream<RunNumbers> get serverNumbers => const Stream.empty();

  @override
  Future<void> start(int runningRoomId) async {}

  @override
  bool sendLocations(List<TrackPoint> points) => true;

  @override
  bool pause() => true;

  @override
  bool resume() => true;

  @override
  Future<FinishOutcome> finish({bool forced = false}) async =>
      const FinishConfirmed();

  @override
  Future<void> close() async {}
}

/// 정해 둔 상태로 시작하는 러닝.
class _Session extends RunSessionController {
  _Session(this._initial);

  final RunSessionState _initial;

  @override
  RunSessionState build() => _initial;
}
