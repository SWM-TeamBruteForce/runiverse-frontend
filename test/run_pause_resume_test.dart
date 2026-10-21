import 'dart:async';

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
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/features/app_update/data/fake_app_version_repository.dart';
import 'package:runiverse/features/app_update/presentation/app_version_provider.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/session/data/fake_location_repository.dart';
import 'package:runiverse/features/session/data/fake_step_repository.dart';
import 'package:runiverse/features/session/data/fake_track_repository.dart';
import 'package:runiverse/features/session/data/fake_user_status_repository.dart';
import 'package:runiverse/features/session/domain/finish_outcome.dart';
import 'package:runiverse/features/session/domain/geo_point.dart';
import 'package:runiverse/features/session/domain/run_numbers.dart';
import 'package:runiverse/features/session/domain/run_progress.dart';
import 'package:runiverse/features/session/domain/run_session_state.dart';
import 'package:runiverse/features/session/domain/run_snapshot.dart';
import 'package:runiverse/features/session/domain/running_channel.dart';
import 'package:runiverse/features/session/domain/track_point.dart';
import 'package:runiverse/features/session/domain/user_status.dart';
import 'package:runiverse/features/session/domain/party_board.dart';
import 'package:runiverse/features/session/presentation/party_provider.dart';
import 'package:runiverse/features/session/presentation/run_session_provider.dart';
import 'package:runiverse/features/session/presentation/running_connection_provider.dart';
import 'package:runiverse/features/session/presentation/user_status_provider.dart';

/// 일시정지·재개를 **서버에도 알린다** — 1.1.0 가이드 2.1 · 2.4.
///
/// ## ⚠️ 1.1.0 전까지 일시정지는 이 앱 안에만 있었다
///
/// 버튼을 눌러도 나가는 메시지가 없었다. 상대 화면에서는 내가 계속 달리는
/// 것으로 보였고, 서버는 멈춘 구간을 알 길이 없어 **서 있던 시간이 그대로
/// 기록에 들어갔다.**
///
/// ## 이 파일이 지키는 것은 순서다
///
/// 메시지가 나갔는지만 보면 반쪽이다. `PAUSE` 뒤에 밀린 좌표가 닿으면
/// **서버가 일시정지를 푼다** — 새 좌표는 그 자체로 `RUNNING`의 근거다.
/// 그래서 [_PauseChannel]이 나간 순서를 통째로 적는다.
void main() {
  late _PauseChannel channel;
  late FakeLocationRepository location;
  late FakeTrackRepository track;
  late DateTime clock;

  Future<ProviderContainer> makeContainer() async {
    clock = DateTime(2026, 10, 14, 7);
    channel = _PauseChannel();
    location = FakeLocationRepository();
    track = FakeTrackRepository();

    final tokens = InMemoryTokenStore();
    await tokens.saveSession(
      userId: 'u-1',
      accessToken: 'a-1',
      refreshToken: 'r-1',
      isOnboarded: true,
    );

    return ProviderContainer.test(
      overrides: [
        // 스플래시가 **토큰 복원보다 먼저** 앱 버전을 확인한다. 진짜를 두면
        // dio가 서버 주소를 찾다 죽고, 판정을 못 받은 화면은 넘어가지 않는다.
        appVersionRepositoryProvider.overrideWithValue(
          FakeAppVersionRepository(),
        ),
        tokenStoreProvider.overrideWithValue(tokens),
        locationRepositoryProvider.overrideWithValue(location),
        trackRepositoryProvider.overrideWithValue(track),
        bodyProfileStoreProvider.overrideWithValue(InMemoryBodyProfileStore()),
        stepRepositoryProvider.overrideWithValue(FakeStepRepository()),
        // ⚠️ **달리는 중이라고 답해야 한다.** 시작 확인을 받으면 서버 상태를
        // 다시 읽는데, 기본값(`Idle`)이면 "진행 중인 것이 없다"고 보고
        // **연결을 내려놓는다.** 그러면 재전송도 `PAUSE`도 중간에 끊긴다.
        userStatusRepositoryProvider.overrideWithValue(
          FakeUserStatusRepository(
            status: UserStatusRunning(
              runningRoomId: 1,
              isSolo: false,
              scheduledStartAt: DateTime(2026, 10, 14, 7),
            ),
          ),
        ),
        runningChannelFactoryProvider.overrideWithValue((_) => channel),
      ],
    );
  }

  /// 좌표 하나. 북쪽으로 [meters]만큼 간 자리다.
  GeoPoint north(double meters) {
    clock = clock.add(const Duration(seconds: 10));
    return GeoPoint(
      latitude: 37.4979 + meters / 111320,
      longitude: 127.0276,
      recordedAt: clock,
      accuracy: 5,
    );
  }

  Future<void> emit(WidgetTester tester, GeoPoint p) async {
    location.emit(p);
    await tester.pump();
    await tester.pump();
  }

  /// 달리는 화면을 세운다.
  ///
  /// [fromServer]는 시작 확인이 싣고 올 번호다. 기본값은 "서버가 받은 좌표가
  /// 없다" — 새 러닝이 그렇다. **[makeContainer]가 채널을 새로 만들므로 여기서
  /// 넘겨야 한다.**
  Future<ProviderContainer> pumpRunning(
    WidgetTester tester, {
    RunNumbers fromServer = RunNumbers.serverZero,
  }) async {
    final container = await makeContainer();
    addTearDown(container.dispose);
    channel.fromServer = fromServer;

    await container.read(runningConnectionProvider.notifier).openMatched(1);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const RuniverseApp(initialLocation: AppRoutes.runSession),
      ),
    );
    await tester.pump();

    final session = container.read(runSessionControllerProvider.notifier);
    await session.prepare();
    await emit(tester, north(0));
    session.start();
    await tester.pump();

    // 좌표 몇 개를 쌓아 둔다. 아직 보내지 않은 것이 있어야 **흘려보내는
    // 순서**를 볼 수 있다.
    for (var i = 1; i <= 3; i++) {
      await emit(tester, north(30.0 * i));
    }
    channel.log.clear();
    return container;
  }

  /// 달리는 중에 끝내면 1초 타이머가 남아 flutter_test가 죽는다.
  Future<void> unmount(WidgetTester tester, ProviderContainer container) async {
    container.read(runSessionControllerProvider.notifier).reset();
    await container.read(runningConnectionProvider.notifier).close();
    await tester.pumpWidget(const SizedBox());
  }

  /// 일시정지 버튼을 누른다. **한 번 누르면 된다** — 되돌릴 수 있어서다.
  Future<void> tapPause(WidgetTester tester, String label) async {
    await tester.tap(find.bySemanticsLabel(label));
    // `pause`가 남은 좌표를 흘리고 알린다. `drain`이 배치 사이에 300ms를
    // 쉬므로 프레임 몇 번으로는 아직 안 닿는다.
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  /// 끊겼다 다시 붙는다. 시작 확인이 올라오고 그 뒤가 정리되기를 기다린다.
  ///
  /// ⚠️ **그냥 두면 `FakeUserStatusRepository` 의 지연 타이머가 남는다.**
  /// 시작 확인을 받으면 서버 상태를 다시 읽는데(`UserStatusController.refresh`),
  /// 그것이 끝나기 전에 위젯을 걷으면 flutter_test 가 죽는다.
  Future<void> reconnect(WidgetTester tester) async {
    channel.reconnect();
    await tester.pump();
    // ⚠️ **재전송이 끝난 뒤에야 `PAUSE`가 나간다**(가이드 2.2의 순서).
    // `drain`이 배치 사이에 300ms를 쉬므로 한 번 펌프로는 안 닿는다.
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  /// 멈춘 것이 **파티원 장까지 닿는가.**
  ///
  /// ⚠️ 문구 자체는 `run_party_view_test`가 지킨다. 여기서 보는 것은 **화면이
  /// 그 사실을 넘겨주는가**다 — 넘기지 않으면 카드는 서 있는 사람에게
  /// "곁에서 달리는 중"이라고 계속 말한다.
  group('⚠️ 멈추면 콤보가 끊긴다고 알린다', () {
    testWidgets('내 카드가 그렇게 말한다', (tester) async {
      final container = await pumpRunning(tester);
      container.read(partyProvider.notifier).setRoster(const [
        PartyMember(userId: 'u-1', nickname: '나'),
        PartyMember(userId: 'u-2', nickname: '옆사람'),
      ], myUserId: 'u-1');

      await tapPause(tester, AppStrings.runPauseCta);
      // 파티원 장으로 넘긴다. **손가락을 왼쪽으로** 민다.
      await tester.drag(find.byType(PageView), const Offset(-500, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text(AppStrings.runPartyComboPaused), findsOneWidget);
      await unmount(tester, container);
    });

    testWidgets('달리는 중에는 뜨지 않는다', (tester) async {
      final container = await pumpRunning(tester);
      container.read(partyProvider.notifier).setRoster(const [
        PartyMember(userId: 'u-1', nickname: '나'),
        PartyMember(userId: 'u-2', nickname: '옆사람'),
      ], myUserId: 'u-1');

      await tester.drag(find.byType(PageView), const Offset(-500, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text(AppStrings.runPartyComboPaused), findsNothing);
      await unmount(tester, container);
    });
  });

  group('⚠️ 멈추면 서버에도 알린다 — 가이드 2.1', () {
    testWidgets('`RUNNING_PAUSE`를 보낸다', (tester) async {
      final container = await pumpRunning(tester);

      await tapPause(tester, AppStrings.runPauseCta);

      expect(channel.log, contains('pause'));
      await unmount(tester, container);
    });

    testWidgets('⚠️ 남은 좌표를 먼저 흘려보낸다', (tester) async {
      // ⚠️ **거꾸로 하면 일시정지가 풀린다.** `PAUSE` 뒤에 밀린 좌표가 닿으면
      // 서버가 그것을 보고 `RUNNING`으로 되돌린다 — 멈췄는데 멈추지 않은
      // 것으로 기록된다.
      final container = await pumpRunning(tester);

      await tapPause(tester, AppStrings.runPauseCta);

      final sent = channel.log.indexWhere((e) => e.startsWith('locations'));
      final paused = channel.log.indexOf('pause');
      expect(sent, isNonNegative, reason: '보낼 좌표가 쌓여 있어야 의미가 있다');
      expect(paused, isNonNegative);
      expect(sent, lessThan(paused), reason: '좌표가 먼저 나가야 한다');
      await unmount(tester, container);
    });

    testWidgets('⚠️ 멈춘 동안 들어온 좌표는 쌓이지 않는다', (tester) async {
      // 세션이 [RunPaused] 동안 들어온 좌표를 통째로 버린다 — 쌓지 않으니
      // 보낼 것도 없다. 가이드 2.1 의 "GPS 수집 중단" 쪽이다.
      final container = await pumpRunning(tester);
      await tapPause(tester, AppStrings.runPauseCta);
      channel.log.clear();

      for (var i = 4; i <= 8; i++) {
        await emit(tester, north(30.0 * i));
      }
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(seconds: 4));
      }

      expect(channel.log, isEmpty);
      await unmount(tester, container);
    });

    testWidgets('⚠️ 전송기도 서 있다', (tester) async {
      // ⚠️ **위 그물로는 모자란다.** 세션이 버려서 쌓일 것이 없을 뿐,
      // 전송기가 계속 돌아도 저 그물은 통과한다 — 실제로 통과시켜 봤다.
      //
      // 전송기가 돌면 **`PAUSE` 뒤에 배치가 나가고 서버가 일시정지를 푼다.**
      // 세션을 건너뛰고 저장소에 직접 하나 넣어 그 길만 본다.
      final container = await pumpRunning(tester);
      await tapPause(tester, AppStrings.runPauseCta);
      channel.log.clear();

      await container
          .read(trackRepositoryProvider)
          .add(
            1,
            TrackPoint(
              sequence: 9000,
              pauseSegment: 1,
              latitude: 37.5,
              longitude: 127.03,
              accuracyMeters: 5,
              speedMetersPerSecond: 3,
              recordedAt: clock,
            ),
          );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(seconds: 4));
      }

      expect(channel.log, isEmpty);
      await unmount(tester, container);
    });
  });

  /// 일시정지 구간 번호 — 1.1.1 2절.
  ///
  /// ## ⚠️ 버튼 흐름에서 확인해야 하는 것
  ///
  /// "재개할 때는 올리지 않는다"는 **없는 동작**이라 순수 로직으로는 검사할
  /// 길이 없다. 올리는 길을 하나만 둬도 누가 [RunSessionController.resume]에
  /// 한 줄을 더하면 끝이다 — 그러면 멈춤 한 번이 구간 두 개가 되고, 서버는
  /// 있지도 않은 구간을 거리에서 뺀다.
  group('⚠️ 일시정지 구간 번호 — 1.1.1 2절', () {
    testWidgets('멈추기 전 좌표는 전부 0이다', (tester) async {
      final container = await pumpRunning(tester);

      expect(track.all.map((p) => p.pauseSegment), everyElement(0));

      await unmount(tester, container);
    });

    testWidgets('⚠️ 멈췄다 다시 가면 1이다 — 재개가 또 올리지 않는다', (tester) async {
      final container = await pumpRunning(tester);

      await tapPause(tester, AppStrings.runPauseCta);
      await tapPause(tester, AppStrings.runResumeCta);
      await emit(tester, north(200));

      expect(track.all.last.pauseSegment, 1, reason: '2면 재개에서도 번호를 올린 것이다');

      await unmount(tester, container);
    });

    testWidgets('두 번 멈추면 2다', (tester) async {
      final container = await pumpRunning(tester);

      await tapPause(tester, AppStrings.runPauseCta);
      await tapPause(tester, AppStrings.runResumeCta);
      await emit(tester, north(200));
      await tapPause(tester, AppStrings.runPauseCta);
      await tapPause(tester, AppStrings.runResumeCta);
      await emit(tester, north(400));

      expect(track.all.map((p) => p.pauseSegment).toList().last, 2);

      await unmount(tester, container);
    });

    testWidgets('⚠️ 누른 즉시 번호가 남는다 — 전송을 기다리지 않는다', (tester) async {
      // 좌표 전송에는 ack가 없다. 전송이 끝나기를 기다렸다 올리면 연결이
      // 끊기거나 앱이 죽을 때 **증가분이 누락된다** — 그러면 다시 달린 좌표가
      // 멈추기 전과 같은 번호를 달고 나가고, 서버는 멈춘 적이 없다고 본다.
      final container = await pumpRunning(tester);

      await tapPause(tester, AppStrings.runPauseCta);

      expect(track.numbered[1]?.pauseSegment, 1);

      await unmount(tester, container);
    });

    testWidgets('⚠️ 멈춰 있는 동안 쌓인 좌표의 번호는 바뀌지 않는다', (tester) async {
      // 과거 좌표를 재전송하면서 지금 번호로 갈아 끼우면 **경계가 사라진다.**
      final container = await pumpRunning(tester);
      final before = track.all.map((p) => p.pauseSegment).toList();

      await tapPause(tester, AppStrings.runPauseCta);

      expect(track.all.map((p) => p.pauseSegment).toList(), before);

      await unmount(tester, container);
    });
  });

  /// 서버가 아는 번호를 받아 맞춘다 — 1.1.1 2절.
  ///
  /// ## ⚠️ 러닝 중 재설치를 이 값으로만 알 수 있다
  ///
  /// 로컬 DB가 사라지면 번호가 1번·0번부터 다시 태어나는데, **서버는 이미
  /// 받은 데가 있다.** 그대로 보내면 이미 쓴 순번이라 중복으로 버려지고, 더
  /// 달려 로컬 순번이 서버를 넘어서는 순간부터는 구간 번호가 서버 값보다
  /// 작아 **배치가 통째로 거부된다**(`PAUSE_SEGMENT_DECREASED`).
  ///
  /// 재설치 여부를 앱이 판단하지 않는다. **언제나 큰 쪽을 쓰면** 멀쩡한
  /// 러닝에서는 로컬이 크므로 아무 일도 일어나지 않는다.
  group('⚠️ 서버 번호 복원 — 1.1.1 2절', () {
    testWidgets('⚠️ 서버가 앞서 있으면 그 뒤부터 매긴다', (tester) async {
      final container = await pumpRunning(
        tester,
        fromServer: const RunNumbers(nextSequence: 120, pauseSegment: 2),
      );

      expect(track.all.first.sequence, 120, reason: '1이면 서버 값을 버렸다');
      expect(track.all.first.pauseSegment, 2);

      await unmount(tester, container);
    });

    testWidgets('로컬이 앞서 있으면 그대로 간다', (tester) async {
      // 서버가 받은 좌표가 없으면 0을 준다. 0을 그대로 쓰면 **모든 러닝의
      // 첫 좌표가 0번**이 되는데, 앱은 1번부터 매긴다.
      final container = await pumpRunning(tester);

      expect(track.all.map((p) => p.sequence), [1, 2, 3]);
      expect(track.all.map((p) => p.pauseSegment), everyElement(0));

      await unmount(tester, container);
    });

    testWidgets('⚠️ 이미 저장된 좌표의 번호는 바뀌지 않는다', (tester) async {
      // 저장된 번호를 서버 값으로 갈아 끼우면 **일시정지 경계가 사라진다.**
      // 다시 붙을 때마다 오는 값이라 이 길이 열려 있으면 매번 밀린다.
      final container = await pumpRunning(tester);
      final before = [for (final p in track.all) (p.sequence, p.pauseSegment)];

      channel.fromServer = const RunNumbers(nextSequence: 500, pauseSegment: 5);
      await reconnect(tester);
      await emit(tester, north(500));

      expect([
        for (final p in track.all.take(before.length))
          (p.sequence, p.pauseSegment),
      ], before);
      expect(track.all.last.sequence, 500);
      expect(track.all.last.pauseSegment, 5);

      await unmount(tester, container);
    });
  });

  group('⚠️ 다시 가면 알리는 것이 먼저다 — 가이드 2.1', () {
    testWidgets('`RUNNING_RESUME`을 보낸다', (tester) async {
      final container = await pumpRunning(tester);
      await tapPause(tester, AppStrings.runPauseCta);
      channel.log.clear();

      await tapPause(tester, AppStrings.runResumeCta);

      expect(channel.log, contains('resume'));
      await unmount(tester, container);
    });

    testWidgets('⚠️ 좌표보다 먼저 나간다', (tester) async {
      // ⚠️ **좌표만으로도 서버는 `RUNNING`으로 돌아온다.** 그래도 알리는
      // 이유는 배치까지 **최대 10초**가 걸려서다 — 그동안 상대 화면에는
      // 내가 멈춰 있는 것으로 보인다.
      final container = await pumpRunning(tester);
      await tapPause(tester, AppStrings.runPauseCta);
      channel.log.clear();

      await tapPause(tester, AppStrings.runResumeCta);
      for (var i = 9; i <= 12; i++) {
        await emit(tester, north(30.0 * i));
      }
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(seconds: 4));
      }

      final resumed = channel.log.indexOf('resume');
      final sent = channel.log.indexWhere((e) => e.startsWith('locations'));
      expect(resumed, isNonNegative);
      expect(sent, isNonNegative, reason: '다시 쌓인 좌표가 나가야 한다');
      expect(resumed, lessThan(sent));
      await unmount(tester, container);
    });

    testWidgets('세션도 다시 달린다', (tester) async {
      final container = await pumpRunning(tester);
      await tapPause(tester, AppStrings.runPauseCta);
      expect(container.read(runSessionControllerProvider), isA<RunPaused>());

      await tapPause(tester, AppStrings.runResumeCta);

      expect(container.read(runSessionControllerProvider), isA<RunRunning>());
      await unmount(tester, container);
    });
  });

  group('⚠️ 다시 붙으면 멈춰 있다고 또 알린다 — 가이드 2.2 · 2.4', () {
    // ⚠️ **재연결은 `RUNNING_START`를 다시 보낸다.** 서버는 그것으로 참가자를
    // `RUNNING`으로 되돌린다(가이드 1.1 상태표) — 알리지 않으면 **멈춰 있는데
    // 상대 화면에서는 내가 다시 달린다.**
    //
    // `RUNNING_NOT_STARTED`로 거절당한 `PAUSE`도 같은 길로 되살아난다. 그
    // 코드가 시작을 다시 보내게 하고, 그 확인이 이 자리로 온다.

    testWidgets('멈춘 채였으면 다시 보낸다', (tester) async {
      final container = await pumpRunning(tester);
      await tapPause(tester, AppStrings.runPauseCta);
      channel.log.clear();

      await reconnect(tester);

      expect(channel.log, contains('pause'));
      await unmount(tester, container);
    });

    testWidgets('⚠️ 멈춘 적이 없으면 보내지 않는다', (tester) async {
      // 달리는 중에 끊겼다 붙었을 뿐인데 `PAUSE`가 나가면 **멀쩡한 러닝이
      // 상대 화면에서 멈춘다.**
      final container = await pumpRunning(tester);

      await reconnect(tester);

      expect(channel.log, isNot(contains('pause')));
      await unmount(tester, container);
    });

    testWidgets('⚠️ 다시 간 뒤에는 보내지 않는다', (tester) async {
      final container = await pumpRunning(tester);
      await tapPause(tester, AppStrings.runPauseCta);
      await tapPause(tester, AppStrings.runResumeCta);
      channel.log.clear();

      await reconnect(tester);

      expect(channel.log, isNot(contains('pause')));
      await unmount(tester, container);
    });

    testWidgets('⚠️ 로컬 트랙을 처음부터 다시 보낸다', (tester) async {
      // ⚠️ 좌표 전송에는 ack가 없다. **어디까지 닿았는지 알 길이 없어**
      // 명세가 전체 재전송을 정했다 — 빠진 구간이 있으면 서버가 그 자리를
      // 직선으로 이어 거리가 짧게 확정된다.
      final container = await pumpRunning(tester);
      await tester.pump(const Duration(seconds: 11)); // 한 번 보내 둔다
      channel.log.clear();
      channel.sent.clear();

      await reconnect(tester);

      expect(channel.sent, isNotEmpty, reason: '다시 보내야 한다');
      expect(channel.sent.first.first, 1, reason: '첫 좌표부터다');
      await unmount(tester, container);
    });

    testWidgets('⚠️ 좌표를 다 보낸 뒤에 멈춤을 알린다', (tester) async {
      // ⚠️ 순서가 `START` → 좌표 → `PAUSE` 다(가이드 2.2). 뒤집히면 **뒤늦게
      // 닿은 좌표가 일시정지를 풀어** 상대 화면에서 내가 다시 달린다.
      final container = await pumpRunning(tester);
      await tapPause(tester, AppStrings.runPauseCta);
      channel.log.clear();
      channel.sent.clear();

      await reconnect(tester);

      final locations = channel.log.indexWhere(
        (e) => e.startsWith('locations'),
      );
      final pause = channel.log.indexOf('pause');
      expect(locations, isNonNegative, reason: '멈춰 있어도 다시 보낸다');
      expect(pause, isNonNegative);
      expect(locations, lessThan(pause), reason: '좌표가 먼저다');
      await unmount(tester, container);
    });

    testWidgets('⚠️ 다음 러닝이 멈춤을 들고 가지 않는다', (tester) async {
      // 표식을 안 되돌리면 **다음 러닝이 붙자마자 `PAUSE`를 보낸다** — 이
      // 길을 타고서다.
      final container = await pumpRunning(tester);
      await tapPause(tester, AppStrings.runPauseCta);

      await container.read(runningConnectionProvider.notifier).close();
      await container.read(runningConnectionProvider.notifier).openMatched(2);
      await tester.pump();
      channel.log.clear();

      await reconnect(tester);

      expect(channel.log, isNot(contains('pause')));
      await unmount(tester, container);
    });
  });
}

/// 나간 것을 **순서대로** 적는 채널.
///
/// `start` · `locations:3` · `pause` · `resume` · `finish` 꼴로 쌓인다.
/// 무엇이 나갔는지만이 아니라 **무엇보다 먼저 나갔는지**를 봐야 해서다.
class _PauseChannel implements RunningChannel {
  final log = <String>[];

  final _snapshots = StreamController<RunSnapshot>.broadcast();
  final _serverNumbers = StreamController<RunNumbers>.broadcast();
  final _states = StreamController<WsConnectionState>.broadcast();

  /// 서버가 아는 번호. **시작 확인마다 이 값이 올라온다.**
  ///
  /// 기본값은 "받은 좌표가 없다"다 — 새 러닝이 그렇다. 테스트가 이것을 올려
  /// 두면 **러닝 중 앱을 다시 설치한 상황**이 된다.
  var fromServer = RunNumbers.serverZero;

  /// 배치마다 실려 나간 `sequence` 목록. **어디서부터 보냈는지**를 본다.
  final sent = <List<int>>[];

  int? _roomId;

  @override
  Stream<WsConnectionState> get states => _states.stream;

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
  Stream<RunSnapshot> get snapshots => _snapshots.stream;

  @override
  Stream<RunNumbers> get serverNumbers => _serverNumbers.stream;

  @override
  Future<void> start(int runningRoomId) async {
    _roomId = runningRoomId;
    log.add('start');
    // 진짜 서버는 `RUNNING_START`마다 `RUNNING_STARTED`로 답하고, 그 몸통에
    // 본인 기준 번호가 실려 온다(1.1.1 2절).
    _serverNumbers.add(fromServer);
  }

  /// 끊겼다 다시 붙었다. **진짜 채널은 여기서 `RUNNING_START`를 다시 보내고,
  /// 그 확인(`RUNNING_STARTED`)이 스냅샷으로 올라온다.**
  ///
  /// ⚠️ **끊김부터 알린다.** 전송기가 그 신호로 커서를 처음으로 되돌린다
  /// (가이드 2.2). 빠뜨리면 재전송이 일어나지 않아 **순서를 보는 테스트가
  /// 통과해 버린다** — 보낼 것이 없으니 `pause`만 남아서다.
  void reconnect() {
    _states.add(WsConnectionState.reconnecting);
    _states.add(WsConnectionState.connected);
    // 되감기가 먼저 끝나야 한다. 진짜도 다시 붙어 ack가 오기까지 틈이 있다.
    scheduleMicrotask(() {
      log.add('start');
      _serverNumbers.add(fromServer);
      _snapshots.add(
        RunSnapshot(
          runningRoomId: _roomId ?? 1,
          players: const [],
          combos: const RunCombo([]),
        ),
      );
    });
  }

  @override
  bool sendLocations(List<TrackPoint> points) {
    if (points.isEmpty) return true;
    log.add('locations:${points.length}');
    sent.add([for (final point in points) point.sequence]);
    return true;
  }

  @override
  bool pause() {
    log.add('pause');
    return true;
  }

  @override
  bool resume() {
    log.add('resume');
    return true;
  }

  @override
  Future<FinishOutcome> finish({bool forced = false}) async {
    log.add('finish');
    return const FinishConfirmed();
  }

  @override
  Future<void> close() async {
    log.add('close');
  }
}
