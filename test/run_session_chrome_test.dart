import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/app/app.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/network/ws_client.dart';
import 'package:runiverse/core/network/ws_message.dart';
import 'package:runiverse/core/storage/body_profile_provider.dart';
import 'package:runiverse/core/storage/body_profile_store.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/session/data/fake_location_repository.dart';
import 'package:runiverse/features/session/data/fake_step_repository.dart';
import 'package:runiverse/features/session/data/fake_running_room_repository.dart';
import 'package:runiverse/features/session/data/fake_track_repository.dart';
import 'package:runiverse/features/session/data/fake_user_status_repository.dart';
import 'package:runiverse/features/session/domain/run_progress.dart';
import 'package:runiverse/features/session/domain/run_snapshot.dart';
import 'package:runiverse/features/session/domain/party_board.dart';
import 'package:runiverse/features/session/domain/running_channel.dart';
import 'package:runiverse/features/session/domain/track_point.dart';
import 'package:runiverse/features/session/presentation/party_provider.dart';
import 'package:runiverse/features/session/presentation/run_session_provider.dart';
import 'package:runiverse/features/session/presentation/running_connection_provider.dart';
import 'package:runiverse/features/session/presentation/user_status_provider.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/widgets/page_indicator.dart';
import 'package:runiverse/core/widgets/run_map_view.dart';
import 'package:runiverse/core/widgets/v2/surface_card.dart';
import 'package:runiverse/features/session/domain/pace_calculator.dart';
import 'package:runiverse/features/session/domain/finish_outcome.dart';

/// 러닝 중 화면의 **틀** — 어느 장이 먼저 서고, 제목이 그 장을 가리키는가.
///
/// ## ⚠️ 이 화면에는 위젯 그물이 없었다
///
/// `run_session_test`는 전부 provider 테스트다. 장 순서를 바꿔도 1,100개가
/// 그대로 통과했다 — **화면을 지나는 것이 하나도 없었다.**
///
/// ## ⚠️ 실시간 기록은 **가운데** 장이다
///
/// 왼쪽이 내 GPS, 오른쪽이 파티원 비교다(2026-10-12 요청). 시안(`158:3493`)은
/// 기록을 **첫째**에 두었으므로 **일부러 벗어난 것**이다 — 모르고 보면
/// "시안대로 되돌리는" 수정을 부른다.
///
/// 그래서 지도가 0번이고 `initialPage: 1`이다. 예전에 같은 모양이었다가
/// 기록 장에서 **둘째 점이 켜진** 적이 있다. `_page`의 초기값이 0인데 실제로는
/// 1번 장이 떠서였다 — `onPageChanged`는 처음에 불리지 않는다. 점이 거짓말을
/// 하는 그 자리를 아래 `가운데 점이 켜진다`가 지킨다.
void main() {
  late _FinishChannel channel;
  late FakeLocationRepository location;

  Future<ProviderContainer> makeContainer() async {
    channel = _FinishChannel();
    location = FakeLocationRepository();

    final tokens = InMemoryTokenStore();
    await tokens.saveSession(
      userId: 'u-1',
      accessToken: 'a-1',
      refreshToken: 'r-1',
      isOnboarded: true,
    );

    return ProviderContainer.test(
      overrides: [
        tokenStoreProvider.overrideWithValue(tokens),
        locationRepositoryProvider.overrideWithValue(location),
        trackRepositoryProvider.overrideWithValue(FakeTrackRepository()),
        bodyProfileStoreProvider.overrideWithValue(InMemoryBodyProfileStore()),
        stepRepositoryProvider.overrideWithValue(FakeStepRepository()),
        userStatusRepositoryProvider.overrideWithValue(
          FakeUserStatusRepository(),
        ),
        runningRoomRepositoryProvider.overrideWithValue(
          FakeRunningRoomRepository(roomId: 1),
        ),
        runningChannelFactoryProvider.overrideWithValue((_) => channel),
      ],
    );
  }

  /// 혼자 달리는 화면을 세운다. 파티원 장이 없어 점은 둘이다.
  Future<ProviderContainer> pumpSolo(WidgetTester tester) async {
    final container = await makeContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const RuniverseApp(initialLocation: AppRoutes.runSession),
      ),
    );
    await tester.pump();

    // ⚠️ **세션을 돌리지 않는다.** `prepare()`·`start()` 는 1초 티커와 10초
    // 전송 타이머를 세우는데, `testWidgets` 는 **teardown 보다 먼저** 남은
    // 타이머를 검사해 거부한다. 이 그물이 보는 장 순서·제목·점은 세션 상태와
    // 무관하다 — `PageView` 는 어느 상태에서도 그려진다.
    return container;
  }

  /// 파티원이 있는 화면을 세운다. 점은 셋이다.
  ///
  /// `hasParty` 는 방이 매칭이거나 파티원 줄이 있을 때 참이다. 방 쪽은 연결을
  /// 돌려야 세워지므로(타이머가 선다) **명단으로 만든다.**
  Future<ProviderContainer> pumpMatched(WidgetTester tester) async {
    final container = await makeContainer();
    addTearDown(container.dispose);
    container.read(partyProvider.notifier).setRoster(const [
      PartyMember(userId: 'u-1', nickname: '나'),
      PartyMember(userId: 'u-2', nickname: '옆사람'),
    ], myUserId: 'u-1');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const RuniverseApp(initialLocation: AppRoutes.runSession),
      ),
    );
    await tester.pump();
    return container;
  }

  /// 왼쪽 장으로. **손가락을 오른쪽으로** 민다.
  Future<void> swipeToLeftPage(WidgetTester tester) async {
    await tester.drag(find.byType(PageView), const Offset(500, 0));
    await tester.pumpAndSettle();
  }

  /// 오른쪽 장으로. **손가락을 왼쪽으로** 민다.
  Future<void> swipeToRightPage(WidgetTester tester) async {
    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    await tester.pumpAndSettle();
  }

  testWidgets('⚠️ 시작 장이 실시간 기록이다', (tester) async {
    await pumpSolo(tester);

    expect(find.text(AppStrings.runPageLive), findsOneWidget);
    expect(find.text(AppStrings.runPageMap), findsNothing);
  });

  testWidgets('⚠️ 시작 장에서 가운데 점이 켜진다', (tester) async {
    // ⚠️ **이 그물이 실제 결함을 잡아 만들어졌다.** `_page` 를 0으로 두면
    // 기록 장이 떠 있는데 **첫째 점**이 켜져 점이 거짓말을 한다.
    await pumpSolo(tester);

    final indicator = tester.widget<PageIndicator>(find.byType(PageIndicator));
    expect(indicator.currentIndex, 1);
    expect(indicator.count, 2, reason: '혼자면 파티원 장이 없다');
  });

  group('⚠️ 장의 좌우 — 2026-10-12 요청', () {
    testWidgets('왼쪽은 내 GPS 다', (tester) async {
      await pumpSolo(tester);

      await swipeToLeftPage(tester);

      expect(find.text(AppStrings.runPageMap), findsOneWidget);
      expect(find.byType(RunMapView), findsOneWidget);
    });

    testWidgets('⚠️ 혼자 뛸 때도 GPS 는 왼쪽이다', (tester) async {
      // 파티원 장이 없다고 순서를 바꾸면, 매칭과 솔로에서 **같은 손짓이 다른
      // 화면**을 연다.
      await pumpSolo(tester);

      await swipeToRightPage(tester);

      expect(
        find.text(AppStrings.runPageMap),
        findsNothing,
        reason: '오른쪽이 아니다',
      );
      expect(
        find.text(AppStrings.runPageLive),
        findsOneWidget,
        reason: '끝이라 그대로',
      );
    });

    testWidgets('매칭이면 오른쪽이 파티원 비교다', (tester) async {
      await pumpMatched(tester);

      await swipeToRightPage(tester);

      expect(find.text(AppStrings.runPageParty), findsOneWidget);
    });

    testWidgets('매칭이어도 왼쪽은 내 GPS 다', (tester) async {
      await pumpMatched(tester);

      await swipeToLeftPage(tester);

      expect(find.text(AppStrings.runPageMap), findsOneWidget);
    });

    testWidgets('매칭이면 점이 셋이고 가운데가 켜진다', (tester) async {
      await pumpMatched(tester);

      final indicator = tester.widget<PageIndicator>(
        find.byType(PageIndicator),
      );
      expect(indicator.count, 3);
      expect(indicator.currentIndex, 1);
    });
  });

  group('⚠️ 실시간 기록 장 — 시안 158:3493', () {
    testWidgets('네 수치가 카드 위에 선다', (tester) async {
      // 시안이 2×2 를 **카드**로 그린다. 예전에는 면 없는 글자라 네 값이
      // 배경에 떠 있었다.
      await pumpSolo(tester);

      expect(find.byType(SurfaceCard), findsNWidgets(4));
    });

    testWidgets('⚠️ 시간 칸이 `경과 시간` 이다', (tester) async {
      // 중지 시트는 `시간` 을 쓴다. 거기는 좁고 여기는 카드라 넉넉하다.
      await pumpSolo(tester);

      expect(find.text(AppStrings.runElapsedLabel), findsOneWidget);
    });

    testWidgets('⚠️ 수치 글자는 자릿수가 흔들리지 않는다', (tester) async {
      // 초마다 바뀌는 값이다. tabular 를 안 주면 자릿수가 바뀔 때 숫자가
      // 좌우로 흔들린다. v1 `metricHero`·`metricMd` 에는 들어 있던 것이라
      // **옮기면서 조용히 잃기 쉬운 자리**다.
      await pumpSolo(tester);

      final pace = tester.widget<Text>(find.text(PaceCalculator.format(null)));
      expect(
        pace.style!.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
    });
  });

  group('⚠️ 내 GPS 장 — 시안 158:3545', () {
    /// 지도 장으로 넘긴다. **왼쪽 장이라 손가락은 오른쪽으로.**
    Future<void> toMap(WidgetTester tester) async => swipeToLeftPage(tester);

    testWidgets('지도 아래에 칸이 둘이다', (tester) async {
      // ⚠️ **넷이 아니라 둘이다.** 실시간 기록 장에 넷이 있는데 여기에 또
      // 넷을 두면 같은 값을 두 번 그리는 화면이 된다.
      await pumpSolo(tester);
      await toMap(tester);

      expect(find.byType(SurfaceCard), findsNWidgets(2));
      expect(find.text(AppStrings.runPaceLabel), findsOneWidget);
      expect(find.text(AppStrings.runDistanceLabel), findsOneWidget);
    });

    testWidgets('⚠️ 케이던스·칼로리는 여기 없다', (tester) async {
      await pumpSolo(tester);
      await toMap(tester);

      expect(find.text(AppStrings.runCadenceLabel), findsNothing);
      expect(find.text(AppStrings.runCaloriesLabel), findsNothing);
    });
  });
}

class _FinishChannel implements RunningChannel {
  final finishes = <bool>[];

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
  Future<void> start(int runningRoomId) async {}

  @override
  bool sendLocations(List<TrackPoint> points) => true;

  @override
  bool pause() => true;

  @override
  bool resume() => true;

  @override
  Future<FinishOutcome> finish({bool forced = false}) async {
    finishes.add(forced);
    return const FinishConfirmed();
  }

  @override
  Future<void> close() async {}
}
