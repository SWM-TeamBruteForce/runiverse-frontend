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
import 'package:runiverse/features/session/domain/running_channel.dart';
import 'package:runiverse/features/session/domain/track_point.dart';
import 'package:runiverse/features/session/presentation/run_session_provider.dart';
import 'package:runiverse/features/session/presentation/running_connection_provider.dart';
import 'package:runiverse/features/session/presentation/user_status_provider.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/widgets/page_indicator.dart';
import 'package:runiverse/core/widgets/run_map_view.dart';

/// 러닝 중 화면의 **틀** — 어느 장이 먼저 서고, 제목이 그 장을 가리키는가.
///
/// ## ⚠️ 이 화면에는 위젯 그물이 없었다
///
/// `run_session_test`는 전부 provider 테스트다. 장 순서를 바꿔도 1,100개가
/// 그대로 통과했다 — **화면을 지나는 것이 하나도 없었다.**
///
/// 시안(`158:3493`)은 점 셋 중 **첫째**가 켜진 채로 실시간 기록을 보여준다.
/// 예전 코드는 지도를 0번에 두고 `initialPage: 1`로 보정해서, 기록 장에서
/// **둘째 점이 켜졌다** — 점이 거짓말을 하고 있었다.
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

  testWidgets('⚠️ 첫 장이 실시간 기록이다', (tester) async {
    await pumpSolo(tester);

    expect(find.text(AppStrings.runPageLive), findsOneWidget);
    expect(find.text(AppStrings.runPageMap), findsNothing);
  });

  testWidgets('⚠️ 첫 장에서 첫째 점이 켜진다', (tester) async {
    // 지도를 0번에 두고 `initialPage` 로 보정하면 여기가 1이 된다.
    await pumpSolo(tester);

    final indicator = tester.widget<PageIndicator>(find.byType(PageIndicator));
    expect(indicator.currentIndex, 0);
    expect(indicator.count, 2, reason: '혼자면 파티원 장이 없다');
  });

  testWidgets('옆으로 넘기면 내 GPS 다', (tester) async {
    await pumpSolo(tester);

    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.runPageMap), findsOneWidget);
    expect(find.byType(RunMapView), findsOneWidget);
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
  Stream<RunSnapshot> get snapshots => const Stream.empty();

  @override
  Future<void> start(int runningRoomId) async {}

  @override
  bool sendLocations(List<TrackPoint> points) => true;

  @override
  Future<bool> finish({bool forced = false}) async {
    finishes.add(forced);
    return true;
  }

  @override
  Future<void> close() async {}
}
