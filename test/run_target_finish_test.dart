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
import 'package:runiverse/features/session/presentation/run_session_page.dart';
import 'package:runiverse/features/session/presentation/run_session_provider.dart';
import 'package:runiverse/features/session/presentation/running_connection_provider.dart';
import 'package:runiverse/features/session/presentation/user_status_provider.dart';

/// 목표에 닿았을 때 **누가 끝내는가.**
///
/// ## ⚠️ 1.1.0 에서 주인이 바뀌었다
///
/// 예전에는 앱이 잰 거리가 목표를 넘으면 **앱이** `RUNNING_FINISH` 를 보냈다.
/// 이제는 **서버**가 끝낸다(가이드 3.1) — 서버는 정지 구간과 오염 좌표를 뺀
/// 확정 거리로 판단하므로, **앱 기준으로 넘었어도 아직 모자랄 수 있다.**
///
/// 그래서 둘을 함께 봐야 한다. 앱이 안 보내는 것만 확인하고 끝내면, 서버가
/// 보낸 종료를 받을 길이 없어 **러닝이 끝났는데 화면이 영영 남는다.**
void main() {
  const target = 200;

  late _FinishChannel channel;
  late FakeLocationRepository location;
  late FakeTrackRepository track;
  late DateTime clock;

  Future<ProviderContainer> makeContainer() async {
    clock = DateTime(2026, 9, 19, 7);
    channel = _FinishChannel();
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
        userStatusRepositoryProvider.overrideWithValue(
          FakeUserStatusRepository(),
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

  /// 좌표를 흘리고 화면까지 반영시킨다. 스트림이 컨트롤러에 닿는 데 한 번,
  /// 다시 그리는 데 한 번이 필요하다.
  Future<void> emit(WidgetTester tester, GeoPoint p) async {
    location.emit(p);
    await tester.pump();
    await tester.pump();
  }

  /// 세션이 아는 거리. **끝난 뒤에도 읽어야 한다** — 목표에 닿으면 상태가
  /// `RunFinished`로 넘어가므로, 달리는 중만 보면 0이 나온다.
  int distanceOf(ProviderContainer container) =>
      switch (container.read(runSessionControllerProvider)) {
        RunRunning(:final metrics) ||
        RunPaused(:final metrics) ||
        RunFinished(:final metrics) => metrics.distanceMeters.round(),
        _ => 0,
      };

  /// 목표가 있는 매칭 방에서 달리는 화면을 세운다.
  ///
  /// [since]를 주면 **앱을 껐다 켜서 이어 붙은 러닝**이다. 그때 로컬 누적은
  /// 0부터 다시 시작하고, 서버가 아는 거리는 스냅샷이 와야 채워진다.
  Future<ProviderContainer> pumpRunning(
    WidgetTester tester, {
    int? targetMeters = target,
    DateTime? since,
  }) async {
    final container = await makeContainer();
    addTearDown(container.dispose);

    await container
        .read(runningConnectionProvider.notifier)
        .openMatched(1, targetDistanceMeters: targetMeters);

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
    session.start(since: since);
    await tester.pump();

    return container;
  }

  /// 종료가 채널까지 닿기를 기다린다.
  ///
  /// ⚠️ `RunningConnectionController.finish`는 **남은 좌표를 먼저 보내고**
  /// 채널을 부른다(`drain` → `RUNNING_FINISH`). 둘 다 비동기라 프레임 두 번으로는
  /// 아직 안 닿는다.
  /// [count]번째 종료까지 기다린다. 보류 뒤 다시 보내는 길은 둘째를 본다.
  Future<void> settleFinish(WidgetTester tester, {int count = 1}) async {
    // `drain`이 배치 사이에 300ms를 쉬므로 여러 박자가 필요하다.
    for (var i = 0; i < 12 && channel.finishes.length < count; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  /// 달리는 중에 끝내면 1초 타이머가 남아 flutter_test가 죽는다.
  ///
  /// ⚠️ **위젯만 걷어내는 것으로는 부족하다.** 컨테이너를 테스트가 들고 있어
  /// `UncontrolledProviderScope`가 그것을 버리지 않는다 — 세션 타이머가 그대로
  /// 돌고, 정리는 `addTearDown`이라 검사보다 늦다. 세션을 직접 접는다.
  Future<void> unmount(WidgetTester tester, ProviderContainer container) async {
    container.read(runSessionControllerProvider.notifier).reset();
    // ⚠️ 연결도 닫는다. 끝나지 않은 러닝에는 **좌표 전송 10초 타이머**가
    // 살아 있고, 그것 하나로도 flutter_test가 죽는다.
    await container.read(runningConnectionProvider.notifier).close();
    await tester.pumpWidget(const SizedBox());
  }

  /// 종료 버튼을 끝까지 길게 누른다.
  ///
  /// ⚠️ **1.1.0부터 종료는 사용자만 보낸다.** 예전에는 목표를 넘기면 앱이
  /// 알아서 보냈고 이 그물도 그것에 기댔다.
  Future<void> holdFinish(WidgetTester tester) async {
    // ⚠️ **요약 화면이 기본 뷰포트(600×800)에서 2px 넘친다.** 이 PR 과 무관한
    // 레이아웃 문제인데, 렌더 예외는 테스트를 죽인다. 세로만 늘려 둔다.
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final button = find.bySemanticsLabel(AppStrings.runFinishHold);
    final gesture = await tester.startGesture(tester.getCenter(button));
    // 길게 누르기가 끝까지 차도록 넉넉히 민다.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    await gesture.up();
    await settleFinish(tester);
    await tester.pumpAndSettle();
  }

  testWidgets('⚠️ 목표에 닿아도 앱은 보내지 않는다', (tester) async {
    // ⚠️ **1.1.0 에서 뒤집힌 약속이다.** 서버가 확정 거리로 판단하므로
    // 앱 기준으로 넘었다고 끝내면 **모자란 러닝이 완주로 올라간다.**
    final container = await pumpRunning(tester);

    for (var i = 1; i <= 10; i++) {
      await emit(tester, north(60.0 * i));
    }

    expect(
      distanceOf(container),
      greaterThanOrEqualTo(target),
      reason: '목표를 넘겨야 판정이 의미가 있다',
    );
    await settleFinish(tester);
    expect(channel.finishes, isEmpty);
    await unmount(tester, container);
  });

  testWidgets('⚠️ 목표를 넘어도 좌표를 계속 보낸다', (tester) async {
    // 가이드 3.1 — 로컬 거리가 목표를 넘었어도 수집·전송을 이어 가며 종료
    // 확정을 기다린다. 멈추면 **서버가 확정할 거리가 모자란 채로 남는다.**
    final container = await pumpRunning(tester);

    for (var i = 1; i <= 10; i++) {
      await emit(tester, north(60.0 * i));
    }
    await settleFinish(tester);

    final state = container.read(runSessionControllerProvider);
    expect(state, isA<RunRunning>(), reason: '세션이 살아 있어야 좌표가 쌓인다');
    await unmount(tester, container);
  });

  testWidgets('⚠️ 매칭 첫 진입은 시작 확인을 기다리지 않는다 — 1.1.1 2절', (tester) async {
    // 복구로 붙은 방은 서버가 좌표를 이미 받았을 수 있어 첫 확인을 기다린다
    // (`TrackRecorder.bind`). **매칭 첫 진입은 그 자리가 아니다** — 서버에
    // 아무것도 없는 것이 확실하다.
    //
    // 여기서도 기다리면 신호 없는 곳에서 시작한 러닝의 첫 구간이 **메모리에만
    // 남아** 앱이 걷어내질 때 사라진다. 이 채널은 시작 확인을 흘리지 않으므로
    // (`serverNumbers`가 빈 스트림이다) 기다린다면 좌표가 영영 안 나간다.
    // ⚠️ **좌표 둘만 넣는다.** 셋을 넘기면 `TrackRecorder.holdLimit`(30초)에
    // 닿아 기다리기를 포기하므로, 기다렸는지 안 기다렸는지 가릴 수 없다 —
    // 이 그물은 좌표 사이가 10초다.
    final container = await pumpRunning(tester);

    await emit(tester, north(30));
    await emit(tester, north(60));

    expect(await track.count(1), greaterThan(0), reason: '저장소에 남아야 한다');
    await unmount(tester, container);
  });

  group('⚠️ 서버가 끝내면 따라간다 — 1.1.0 가이드 3.1', () {
    // ⚠️ **앱이 안 보내는 것만 고치면 반쪽이다.** 서버가 보낸 종료를 받을
    // 길이 없으면 러닝이 끝났는데 화면이 영영 남는다.

    testWidgets('요약으로 간다', (tester) async {
      final container = await pumpRunning(tester);

      channel.finished_.add(null);
      await tester.pumpAndSettle();

      expect(find.byType(RunSessionPage, skipOffstage: false), findsNothing);
      await unmount(tester, container);
    });

    testWidgets('⚠️ 종료를 되받아 보내지 않는다', (tester) async {
      // 서버가 이미 끝냈다. 또 보내면 같은 방에 종료가 두 번 간다.
      final container = await pumpRunning(tester);

      channel.finished_.add(null);
      await tester.pumpAndSettle();

      expect(channel.finishes, isEmpty);
      await unmount(tester, container);
    });

    testWidgets('⚠️ 세션의 시계를 멈춘다', (tester) async {
      // 화면만 옮기고 세션을 두면 **1초 타이머가 계속 돈다.**
      final container = await pumpRunning(tester);

      channel.finished_.add(null);
      await tester.pumpAndSettle();

      expect(
        container.read(runSessionControllerProvider),
        isNot(isA<RunRunning>()),
      );
      await unmount(tester, container);
    });
  });

  /// 서버가 **구간 번호를 이유로** 좌표를 거부했다 — 1.1.1 3절.
  ///
  /// ## ⚠️ 말해 주지 않으면 러닝이 저절로 끝난 것처럼 보인다
  ///
  /// 이 경우는 앱이 끝낸다. 더 달려도 아무것도 안 남기 때문인데, 사용자에게는
  /// **달리던 화면이 갑자기 요약으로 넘어간 것**으로만 보인다. 끝내는 것과
  /// 알리는 것이 한 몸이라 둘을 한 자리에서 본다.
  group('⚠️ 구간 번호가 거부되면 — 1.1.1 3절', () {
    testWidgets('조기 종료를 보내고 요약으로 간다', (tester) async {
      final container = await pumpRunning(tester);

      channel.errors_.add(WsErrorCode.pauseSegmentDecreased);
      await settleFinish(tester);
      await tester.pumpAndSettle();

      expect(channel.finishes, [true]);
      expect(find.byType(RunSessionPage, skipOffstage: false), findsNothing);
      await unmount(tester, container);
    });

    testWidgets('⚠️ 왜 끝났는지 말해 준다', (tester) async {
      final container = await pumpRunning(tester);

      channel.errors_.add(WsErrorCode.pauseSegmentDecreased);
      await settleFinish(tester);
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.runTrackRejected), findsOneWidget);
      await unmount(tester, container);
    });

    testWidgets('저장 실패만으로는 끝내지 않는다', (tester) async {
      // 그쪽은 다시 보내면 들어간다. 러닝은 계속돼야 한다.
      final container = await pumpRunning(tester);

      channel.errors_.add(WsErrorCode.runningTrackUnavailable);
      await settleFinish(tester);
      await tester.pumpAndSettle();

      expect(channel.finishes, isEmpty);
      expect(find.byType(RunSessionPage), findsOneWidget);
      await unmount(tester, container);
    });
  });

  testWidgets('목표가 없는 솔로는 스스로 끝내지 않는다', (tester) async {
    // 솔로에는 목표가 없다. 끝내는 것은 사용자의 몫이다.
    final container = await pumpRunning(tester, targetMeters: null);

    for (var i = 1; i <= 10; i++) {
      await emit(tester, north(60.0 * i));
    }

    await settleFinish(tester);
    expect(distanceOf(container), greaterThan(target));
    expect(channel.finishes, isEmpty);
    await unmount(tester, container);
  });
  group('⚠️ 종료가 보류되면 러닝이 이어진다 — 1.1.0 가이드 3.2', () {
    // ⚠️ **예전에는 요청만 던지고 곧바로 요약으로 넘어갔다.**
    //
    // 1.1.0 서버는 `RUNNING_GOAL_PENDING` 으로 "확정 거리가 모자라다"고 답할
    // 수 있다. 앱이 잰 거리는 목표를 넘었어도 서버는 정지 구간과 오염 좌표를
    // 뺀 값으로 센다 — 먼저 넘어가 버리면 **러닝이 뒤에서 계속 도는 채로
    // 요약 화면이 뜬다.**

    testWidgets('화면이 러닝에 남는다', (tester) async {
      final container = await pumpRunning(tester);
      channel.outcome = const FinishGoalPending(40);

      await holdFinish(tester);

      expect(find.byType(RunSessionPage), findsOneWidget);
      await unmount(tester, container);
    });

    testWidgets('⚠️ 남은 거리를 말해 준다', (tester) async {
      final container = await pumpRunning(tester);
      channel.outcome = const FinishGoalPending(40);

      await holdFinish(tester);

      expect(find.text(AppStrings.runGoalPendingBody(40)), findsOneWidget);
      await unmount(tester, container);
    });

    testWidgets('⚠️ 세션의 시계가 멈추지 않는다', (tester) async {
      // 답을 받기 전에 세션을 접으면 **멀쩡한 러닝의 시간이 멈춘다.**
      final container = await pumpRunning(tester);
      channel.outcome = const FinishGoalPending(40);

      await holdFinish(tester);

      final state = container.read(runSessionControllerProvider);
      expect(state, isA<RunRunning>());
      await unmount(tester, container);
    });

    testWidgets('⚠️ 보류 뒤에도 좌표가 계속 나간다', (tester) async {
      // ⚠️ **가이드 3.2 가 "좌표 수집·전송 유지"라고 적은 그 자리다.**
      //
      // 전송기를 `TrackSender.stop` 으로 세웠더니 `resumeTimer` 가 첫 줄에서
      // 돌아섰다 — `stop` 이 방 번호를 지우기 때문이다. **러닝은 이어지는데
      // 좌표가 조용히 안 나갔고**, 그러면 서버가 확정할 거리가 영영 모자란다.
      final container = await pumpRunning(tester);
      channel.outcome = const FinishGoalPending(40);

      await holdFinish(tester);
      channel.locations.clear();

      for (var i = 1; i <= 6; i++) {
        await emit(tester, north(30.0 * i));
      }
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(seconds: 4));
      }

      expect(channel.locations, isNotEmpty);
      await unmount(tester, container);
    });

    testWidgets('확정이면 요약으로 간다', (tester) async {
      // 보류를 넣는 쪽만 보면 **확정 경로가 깨져도 모른다.**
      final container = await pumpRunning(tester);

      await holdFinish(tester);

      expect(find.byType(RunSessionPage, skipOffstage: false), findsNothing);
      await unmount(tester, container);
    });
  });

  group('⚠️ 복구 중이라 거리를 모를 때', () {
    // ⚠️ **`forced` 를 로컬 거리로 판정한다**(가이드 3.2). 그런데 앱을 껐다
    // 켜면 로컬 누적은 0부터 다시 시작하고, 서버가 아는 거리는 스냅샷이
    // 와야 채워진다 — 그 사이에 종료를 누르면 **3.8km 를 뛴 사람이 `forced=true`
    // 로 나간다.** 서버는 이 값과 자기 확정 거리를 함께 보고 제재를 정한다.
    //
    // 모를 때는 모자라다고 단정하지 않는다. 정말 모자라면 서버가 보류로
    // 되돌려 보내고(가이드 3.3), 그때 사용자가 고른다 — 되돌릴 수 있는 쪽이다.

    /// 복구 직후, 아직 스냅샷이 오지 않은 화면.
    Future<ProviderContainer> pumpResumed(WidgetTester tester) =>
        pumpRunning(tester, since: DateTime(2026, 9, 19, 6, 30));

    testWidgets('⚠️ 스냅샷을 못 받았으면 조기 종료로 보내지 않는다', (tester) async {
      final container = await pumpResumed(tester);
      expect(distanceOf(container), lessThan(target), reason: '복구 직후라 로컬은 0이다');

      await holdFinish(tester);

      expect(channel.finishes, [false]);
      await unmount(tester, container);
    });

    testWidgets('스냅샷을 받은 뒤에는 그 거리로 판정한다', (tester) async {
      // 모를 때만 봐준다. 서버가 아는 거리도 모자라면 조기 종료가 맞다.
      final container = await pumpResumed(tester);
      container.read(runSessionControllerProvider.notifier).seedDistance(10);
      await tester.pump();

      await holdFinish(tester);

      expect(channel.finishes, [true]);
      await unmount(tester, container);
    });
  });

  group('⚠️ 보류를 받으면 고르게 한다 — 1.1.0 가이드 3.3', () {
    // ⚠️ **스낵바로는 못 묻는다.** 가이드가 "계속 달리거나 종료할 수
    // 있도록 안내"하라고 정했다 — 고를 것이 있으면 사라지는 알림으로는
    // 모자라고, 종료는 **사용자가 다시 확인해야** 나간다.

    /// 보류 안내가 떠 있는 화면까지 세운다.
    ///
    /// ⚠️ **목표를 넘겨 놓고 끝낸다.** 보류는 `forced=false` 요청에만 오는
    /// 답이다(가이드 3.2) — 화면 거리가 목표에 모자라면 `forced=true` 로 나가고,
    /// 그때는 서버가 보류로 되돌리지 않는다.
    Future<ProviderContainer> pumpPending(WidgetTester tester) async {
      final container = await pumpRunning(tester);
      for (var i = 1; i <= 10; i++) {
        await emit(tester, north(60.0 * i));
      }
      expect(distanceOf(container), greaterThanOrEqualTo(target));

      channel.outcome = const FinishGoalPending(40);
      await holdFinish(tester);
      expect(channel.finishes, [false], reason: '목표를 넘겼으니 조기 종료가 아니다');

      // 다음 요청은 확정으로 답한다 — `종료하기` 가 눌리는 경로를 본다.
      channel.outcome = const FinishConfirmed();
      return container;
    }

    testWidgets('창으로 띄운다', (tester) async {
      final container = await pumpPending(tester);

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text(AppStrings.runGoalPendingTitle), findsOneWidget);
      await unmount(tester, container);
    });

    testWidgets('⚠️ `계속 달리기` 는 종료를 보내지 않는다', (tester) async {
      final container = await pumpPending(tester);
      final before = channel.finishes.length;

      await tester.tap(
        find.widgetWithText(TextButton, AppStrings.runGoalPendingKeep),
      );
      await tester.pumpAndSettle();

      expect(channel.finishes.length, before, reason: '고르지 않은 것을 보내면 안 된다');
      expect(find.byType(RunSessionPage), findsOneWidget);
      expect(find.byType(AlertDialog, skipOffstage: false), findsNothing);
      await unmount(tester, container);
    });

    testWidgets('⚠️ `종료하기` 는 `forced=true` 로 다시 보낸다', (tester) async {
      // 보류는 `forced=false` 요청에만 온다. 같은 값으로 또 보내면 **같은
      // 답이 돌아와** 영영 끝나지 않는다.
      final container = await pumpPending(tester);

      await tester.tap(
        find.widgetWithText(TextButton, AppStrings.runGoalPendingFinish),
      );
      await settleFinish(tester, count: 2);
      await tester.pumpAndSettle();

      expect(channel.finishes, [false, true]);
      expect(
        find.byType(RunSessionPage, skipOffstage: false),
        findsNothing,
        reason: '확정이면 요약으로 간다',
      );
      await unmount(tester, container);
    });

    testWidgets('⚠️ 서버가 끝내면 창을 닫고 간다', (tester) async {
      // ⚠️ 창이 열린 동안에도 `RUNNING_FINISHED` 가 온다(가이드 3.3).
      //
      // 닫는 일은 `Navigator` 가 한다 — 이 창은 러닝 페이지에 매달린 **페이지
      // 없는 경로**라 요약으로 교체될 때 함께 걷힌다. 그래서 이 그물은 코드
      // 한 줄이 아니라 **그 성질**을 지킨다. 요약으로 가는 방식을 `push` 로
      // 바꾸면(페이지가 남는다) 창도 남고, 이 그물이 그때 깨진다.
      final container = await pumpPending(tester);

      channel.finished_.add(null);
      await tester.pumpAndSettle();

      // ⚠️ `skipOffstage: false` — 기본값으로 찾으면 **가려진 것도 없는
      // 것으로 읽힌다.** 요약을 그 위에 얹기만 해도 그물이 통과했다.
      expect(find.byType(AlertDialog, skipOffstage: false), findsNothing);
      expect(find.byType(RunSessionPage, skipOffstage: false), findsNothing);
      await unmount(tester, container);
    });

    testWidgets('⚠️ 서버가 끝낸 뒤에는 종료가 더 나가지 않는다', (tester) async {
      // 가이드 3.3 — "뒤늦게 확인 버튼을 눌러 중복 종료 요청을 보내지 않도록".
      final container = await pumpPending(tester);

      channel.finished_.add(null);
      await tester.pumpAndSettle();

      expect(channel.finishes, [false], reason: '처음 보낸 하나뿐이어야 한다');
      await unmount(tester, container);
    });
  });

  testWidgets('⚠️ 목표의 80%를 넘겨도 `forced=true` 다', (tester) async {
    // ⚠️ **가이드 3.2 가 가른 선은 목표 전체다.** 80%(`_safeRatio`)는
    // 제재 선이지 완주 선이 아니다. 80%로 가르면 85%에서 멈춘 사람이
    // `forced=false` 로 나가 **끝낼 뜻이 분명한데 보류로 되돌아온다.**
    final container = await pumpRunning(tester);

    // 80%(160m)는 넘기고 목표(200m)는 못 채운 자리에 선다.
    //
    // ⚠️ **좌표를 센 만큼 거리가 늘지 않는다.** 세션이 걸러내고 다듬으므로
    // 20m 씩 흘리며 선을 넘는 순간 멈춘다 — 몇 개가 필요한지 적어 두면
    // 걸러내는 방식이 바뀔 때 이 그물이 엉뚱한 이유로 깨진다.
    for (var i = 1; i <= 40 && distanceOf(container) <= 160; i++) {
      await emit(tester, north(20.0 * i));
    }
    expect(distanceOf(container), inInclusiveRange(161, 199));

    await holdFinish(tester);

    expect(channel.finishes, [true]);
    await unmount(tester, container);
  });
}

/// `RUNNING_FINISH`가 몇 번, 어떤 `forced`로 나갔는지 센다.
class _FinishChannel implements RunningChannel {
  final finishes = <bool>[];

  @override
  Stream<WsConnectionState> get states => const Stream.empty();

  @override
  WsConnectionState get state => WsConnectionState.connected;

  /// 서버가 거절한 것을 손으로 흘려보낸다.
  final errors_ = StreamController<WsErrorCode>.broadcast();

  @override
  Stream<WsErrorCode> get errors => errors_.stream;

  @override
  Stream<RunProgress> get progress => const Stream.empty();

  @override
  Stream<RunCombo> get combos => const Stream.empty();

  final finished_ = StreamController<void>.broadcast();

  @override
  Stream<void> get finished => finished_.stream;

  @override
  Stream<RunSnapshot> get snapshots => const Stream.empty();

  @override
  Stream<RunNumbers> get serverNumbers => const Stream.empty();

  @override
  Future<void> start(int runningRoomId) async {}

  /// 배치마다 좌표 수를 적는다. **보류 뒤에도 계속 나가는지** 보려고 센다.
  final locations = <int>[];

  @override
  bool sendLocations(List<TrackPoint> points) {
    if (points.isNotEmpty) locations.add(points.length);
    return true;
  }

  /// 무엇으로 답할지. 보류를 흉내 내려면 [FinishGoalPending] 을 넣는다.
  FinishOutcome outcome = const FinishConfirmed();

  @override
  bool pause() => true;

  @override
  bool resume() => true;

  @override
  Future<FinishOutcome> finish({bool forced = false}) async {
    finishes.add(forced);
    return outcome;
  }

  @override
  Future<void> close() async {}
}
