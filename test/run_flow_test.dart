// flutter_test는 material을 재수출하지 않는다.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/app/app.dart';
import 'package:runiverse/core/network/ws_client.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/core/network/ws_message.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/widgets/app_button.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/session/data/fake_location_repository.dart';
import 'package:runiverse/features/session/data/fake_running_room_repository.dart';
import 'package:runiverse/features/session/data/fake_track_repository.dart';
import 'package:runiverse/features/session/domain/geo_point.dart';
import 'package:runiverse/features/session/domain/location_repository.dart';
import 'package:runiverse/features/session/domain/running_channel.dart';
import 'package:runiverse/features/session/domain/running_room.dart';
import 'package:runiverse/features/session/domain/track_point.dart';
import 'package:runiverse/features/session/presentation/run_session_provider.dart';
import 'package:runiverse/features/session/presentation/running_connection_provider.dart';

/// 1인 러닝 — 출발 준비부터 요약까지 화면이 실제로 이어지는가.
///
/// ## ⚠️ 러닝 중에는 `pumpAndSettle`을 쓰지 않는다
///
/// 컨트롤러가 **1초짜리 반복 타이머**를 돌리고 있어서 영원히 끝나지 않는다.
/// 필요한 만큼만 손으로 [WidgetTester.pump]한다. 끝낸 뒤에는 타이머가 멈춰
/// 다시 쓸 수 있다.
///
/// ## 지도는 테스트에서 뜨지 않는다
///
/// `RunMapView`가 `AppConfig.hasNaverMapClientId`를 먼저 본다. 테스트에는
/// `--dart-define`이 없으므로 **키가 비어 있어 폴백 위젯이 그려진다.**
/// 덕분에 네이버 지도 플러그인의 플랫폼 채널을 흉내 내지 않아도 된다.
void main() {
  final start = DateTime(2026, 8, 5, 19);
  late DateTime clock;
  late FakeLocationRepository location;
  late FakeRunningRoomRepository room;
  late FakeTrackRepository track;

  setUp(() {
    clock = start;
    location = FakeLocationRepository();
    room = FakeRunningRoomRepository();
    track = FakeTrackRepository();
  });

  Future<void> pumpRun(
    WidgetTester tester, {
    LocationAccess access = LocationAccess.granted,
  }) async {
    location = FakeLocationRepository(access: access);

    // ⚠️ **토큰이 없으면 WS에 붙지 못한다.** 갈아 끼우지 않으면 진짜
    // 보안 저장소를 읽으려 하고, 테스트에서는 비어 있어 `sessionExpired`로
    // 빠진다 — 연결까지 가보는 테스트가 조용히 무의미해진다.
    final tokens = InMemoryTokenStore();
    await tokens.saveSession(
      userId: 'u-1',
      accessToken: 'a-1',
      refreshToken: 'r-1',
      isOnboarded: true,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStoreProvider.overrideWithValue(tokens),
          locationRepositoryProvider.overrideWithValue(location),
          // 시각을 고정한다. `DateTime.now`를 그대로 두면 흐른 시간이 매번 달라진다.
          runClockProvider.overrideWithValue(() => clock),
          // ⚠️ 서버를 부르지 않는다. 갈아 끼우지 않으면 진짜 HTTP와 소켓을
          // 열려 하고, 테스트에는 주소가 없어 죽는다.
          runningRoomRepositoryProvider.overrideWithValue(room),
          // ⚠️ 갈아 끼우지 않으면 진짜 DB를 열려다 실패하고, 컨트롤러가 그
          // 실패를 삼켜 **좌표가 쌓이는지 아무도 확인하지 않는 상태**가 된다.
          trackRepositoryProvider.overrideWithValue(track),
          runningChannelFactoryProvider.overrideWithValue(
            (_) => _SilentChannel(),
          ),
        ],
        child: const RuniverseApp(initialLocation: AppRoutes.runPrepare),
      ),
    );
    await tester.pumpAndSettle();
  }

  GeoPoint point(double lat, double lon) =>
      GeoPoint(latitude: lat, longitude: lon, recordedAt: clock);

  /// 좌표를 흘려보내고 화면에 반영될 때까지 기다린다.
  ///
  /// **프레임이 두 번 필요하다.** 스트림 이벤트가 컨트롤러에 닿는 데 한 번,
  /// 바뀐 상태로 화면을 다시 그리는 데 한 번이다.
  Future<void> emit(WidgetTester tester, GeoPoint p) async {
    location.emit(p);
    await tester.pump();
    await tester.pump();
  }

  /// 출발 준비를 마치고 달리는 상태로 만든다.
  ///
  /// ⚠️ **[시작]을 누르면 곧바로 러닝이 아니라 카운트다운 3초가 먼저다.**
  /// 그 3초 동안 앱이 서버에 붙는다(설계 문서 4절).
  Future<void> startRunning(WidgetTester tester) async {
    await emit(tester, point(37.5, 127));
    await tester.tap(find.widgetWithText(AppButton, AppStrings.runStartCta));
    await tester.pump();

    // 3 · 2 · 1. 한 번에 3초를 보내면 Timer.periodic이 한 번만 돈다.
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    // 화면 전환에 필요한 만큼만 돌린다. `pumpAndSettle`은 타이머 때문에 못 쓴다.
    await tester.pump(const Duration(milliseconds: 500));
  }

  /// 달리는 중에 테스트를 끝내면 **1초짜리 반복 타이머가 남아** flutter_test가
  /// 죽는다. 앱을 걷어내면 provider가 dispose되면서 타이머와 위치 구독이 함께
  /// 끊긴다 — 실제 앱에서도 같은 경로로 정리된다.
  Future<void> unmount(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox());

  /// 중지 시트를 연다.
  Future<void> openStopSheet(WidgetTester tester) async {
    await tester.tap(find.text(AppStrings.runStopCta));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  /// 종료 버튼을 끝까지 누른다. 시트가 닫히면 성공이다.
  ///
  /// ## ⚠️ 프레임을 잘게 나눠 돌려야 한다
  ///
  /// `pump(Duration(seconds: 2))`처럼 한 번에 2초를 보내면 **티커가 한 번만
  /// 불려** `AnimationController`가 끝까지 가지 않는다. 실제로 이 방식으로
  /// 짰다가 "2초를 눌렀는데 아무 일도 없다"를 한참 쫓았다.
  ///
  /// 100ms씩 밀면서 시트가 닫히는지 본다. 최대 3초까지만 기다린다 —
  /// 그 안에 안 닫히면 버튼이 고장난 것이다.
  Future<void> holdFinish(WidgetTester tester) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.text(AppStrings.runFinishHold)),
    );
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text(AppStrings.runFinishHold).evaluate().isEmpty) break;
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  bool startEnabled(WidgetTester tester) {
    final button = tester.widget<AppButton>(
      find.widgetWithText(AppButton, AppStrings.runStartCta),
    );
    return button.onPressed != null;
  }

  group('출발 준비', () {
    testWidgets('신호를 찾는 동안에는 출발할 수 없다', (tester) async {
      // 신호 없이 출발하면 초반 거리가 통째로 빠진다.
      await pumpRun(tester);

      expect(find.text(AppStrings.runWaitingFix), findsOneWidget);
      expect(startEnabled(tester), isFalse);
    });

    testWidgets('신호가 잡히면 출발할 수 있다', (tester) async {
      await pumpRun(tester);

      await emit(tester, point(37.5, 127));

      expect(find.text(AppStrings.runFixReady), findsOneWidget);
      expect(startEnabled(tester), isTrue);
    });

    testWidgets('권한을 거절하면 이유를 보여준다', (tester) async {
      await pumpRun(tester, access: LocationAccess.denied);

      expect(find.text(AppStrings.runPermissionTitle), findsOneWidget);
    });

    testWidgets('⚠️ 위치 기능이 꺼진 경우는 권한 거절과 문구가 다르다', (tester) async {
      // 권한을 아무리 줘도 좌표가 안 나온다. "권한을 허용하세요"라고 하면
      // 사용자는 이미 허용한 권한 화면만 들여다보게 된다.
      await pumpRun(tester, access: LocationAccess.serviceDisabled);

      expect(find.text(AppStrings.runServiceDisabled), findsOneWidget);
      expect(find.text(AppStrings.runPermissionTitle), findsNothing);
    });
  });

  group('카운트다운', () {
    testWidgets('시작을 누르면 3부터 센다', (tester) async {
      await pumpRun(tester);
      await emit(tester, point(37.5, 127));

      await tester.tap(find.widgetWithText(AppButton, AppStrings.runStartCta));
      await tester.pump();

      expect(find.text('3'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('세는 동안 서버에 붙는다', (tester) async {
      // 이 3초가 연결 창이다. 사용자는 기다리는 줄 모른다.
      await pumpRun(tester);
      await emit(tester, point(37.5, 127));

      await tester.tap(find.widgetWithText(AppButton, AppStrings.runStartCta));
      await tester.pump();

      expect(room.calls, 1);
      await unmount(tester);
    });

    testWidgets('⚠️ 이전 러닝이 남아 있으면 시작하지 않는다', (tester) async {
      // 방 없이 달리면 30분을 뛰어도 서버에 기록이 남지 않는다.
      room.failure = RunningRoomFailure.alreadyRunning;
      await pumpRun(tester);
      await emit(tester, point(37.5, 127));

      await tester.tap(find.widgetWithText(AppButton, AppStrings.runStartCta));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.runAlreadyInProgress), findsOneWidget);
      expect(find.text(AppStrings.runStopCta), findsNothing);
    });

    testWidgets('⚠️ 붙고 나면 "연결하는 중" 안내가 사라진다', (tester) async {
      // `states`가 broadcast라 구독 전에 지나간 `connected`는 다시 오지 않는다.
      // 그것만 믿으면 소켓이 붙었는데도 화면이 "연결하는 중"이라고 말한다.
      await pumpRun(tester);
      await startRunning(tester);

      expect(find.text(AppStrings.runOffline), findsNothing);
      await unmount(tester);
    });

    testWidgets('⚠️ 409는 다시 시도하지 않는다', (tester) async {
      // 몇 번을 눌러도 같은 답이 온다. 재시도가 돌면 서버를 계속 두드린다.
      room.failure = RunningRoomFailure.alreadyRunning;
      await pumpRun(tester);
      await emit(tester, point(37.5, 127));
      await tester.tap(find.widgetWithText(AppButton, AppStrings.runStartCta));
      await tester.pumpAndSettle();

      // 첫 재시도가 1초 뒤다. 돌았다면 여기서 늘어난다.
      await tester.pump(const Duration(seconds: 2));

      expect(room.calls, 1);
    });
  });

  group('러닝 진행', () {
    testWidgets('출발하면 러닝 화면이 열린다', (tester) async {
      await pumpRun(tester);

      await startRunning(tester);

      expect(find.text(AppStrings.runStopCta), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('거리가 화면에 반영된다', (tester) async {
      await pumpRun(tester);
      await startRunning(tester);

      // ⚠️ **달리기 시작 뒤로 두 점이 필요하다.** 준비 중에 받은 좌표는
      // "신호가 잡혔다"는 뜻일 뿐 거리로 세지 않는다.
      await emit(tester, point(37.5, 127));
      // 약 111m 북쪽. 위도 0.001도는 어디서나 대략 111m다.
      await emit(tester, point(37.501, 127));

      expect(find.text(AppStrings.runDistanceLabel), findsOneWidget);
      // 0이 아닌 거리가 찍혀야 한다. 정확한 값은 칼만 보정이 정하므로
      // 여기서 자릿수까지 못박지 않는다.
      expect(find.text('0.00'), findsNothing);
      await unmount(tester);
    });

    testWidgets('⚠️ 달리면 좌표가 로컬에 쌓인다', (tester) async {
      // 서버가 아직 좌표를 못 받으므로, 쌓아 두지 않으면 통째로 사라진다.
      await pumpRun(tester);
      await startRunning(tester);

      await emit(tester, point(37.5, 127));
      await emit(tester, point(37.501, 127));
      // DB 쓰기는 기다리지 않고 보내므로 한 프레임 더 돌린다.
      await tester.pump();

      expect(track.all, isNotEmpty);
      expect(track.all.first.sequence, 1);
      await unmount(tester);
    });

    testWidgets('⚠️ 사람이 달리는 속도에서 진행 방향이 붙는다', (tester) async {
      // 센서가 주는 방향은 안드로이드에서 실제 방향과 무관했다. 직전 좌표로
      // 직접 계산한 값이 저장까지 닿아야 한다(`GeoPoint.bearingTo`).
      //
      // ⚠️ **속도를 실제와 맞춰야 의미가 있다.** 좌표는 1초 간격이고 6분/km면
      // 초당 2.8미터다. 최소 이동 거리를 직전 좌표 하나에 걸면 시속 36km를
      // 요구하게 되어 방향이 전부 빈다 — 그 회귀를 여기서 잡는다.
      await pumpRun(tester);
      await startRunning(tester);

      // 북쪽으로 초당 2.8미터씩. 위도 1도는 약 111,320미터다.
      const step = 2.8 / 111320;
      for (var i = 0; i < 15; i++) {
        await emit(tester, point(37.5 + i * step, 127));
      }
      await tester.pump();

      final headings = track.all
          .map((p) => p.headingDegrees)
          .whereType<double>();

      expect(headings, isNotEmpty, reason: '방향이 하나도 안 붙었다');
      expect(headings.last, closeTo(0, 5));
      await unmount(tester);
    });

    testWidgets('⚠️ 제자리에서는 방향을 지어내지 않는다', (tester) async {
      // 오차 반경 안에서 흔들리는 것은 진행이 아니다. 그 각도를 보내면
      // 서 있는 사람이 어디론가 향하는 것처럼 기록된다.
      await pumpRun(tester);
      await startRunning(tester);

      for (var i = 0; i < 10; i++) {
        await emit(tester, point(37.5, 127));
      }
      await tester.pump();

      expect(
        track.all.map((p) => p.headingDegrees).whereType<double>(),
        isEmpty,
        reason: '움직이지 않았는데 방향이 붙었다',
      );
      await unmount(tester);
    });

    testWidgets('⚠️ 좌표를 못 쌓아도 러닝은 계속된다', (tester) async {
      // 좌표 하나 때문에 달리기를 멈출 이유가 없다.
      track.failure = StateError('디스크가 가득 찼다');
      await pumpRun(tester);
      await startRunning(tester);

      await emit(tester, point(37.501, 127));
      await tester.pump();

      expect(find.text(AppStrings.runStopCta), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('⚠️ 아직 못 재는 지표는 값을 지어내지 않는다', (tester) async {
      // 케이던스와 칼로리는 잴 방법이 없다. 0으로 채우면 "0"이 측정값처럼 보인다.
      await pumpRun(tester);
      await startRunning(tester);

      expect(find.text(AppStrings.runUnavailable), findsWidgets);
      await unmount(tester);
    });
  });

  group('중지 시트', () {
    testWidgets('중지하면 계속과 종료를 고를 수 있다', (tester) async {
      await pumpRun(tester);
      await startRunning(tester);

      await openStopSheet(tester);

      expect(find.text(AppStrings.runResumeCta), findsOneWidget);
      expect(find.text(AppStrings.runFinishHold), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('⚠️ 한 번 탭으로는 끝나지 않는다', (tester) async {
      // 달리는 도중에 실수로 눌러 기록이 날아가면 되돌릴 수 없다.
      await pumpRun(tester);
      await startRunning(tester);
      await openStopSheet(tester);

      await tester.tap(find.text(AppStrings.runFinishHold));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // 요약으로 가지 않았다.
      expect(find.text(AppStrings.runSummaryTitle), findsNothing);
      await unmount(tester);
    });

    testWidgets('2초 길게 누르면 요약으로 간다', (tester) async {
      await pumpRun(tester);
      await startRunning(tester);
      await openStopSheet(tester);

      await holdFinish(tester);

      expect(find.text(AppStrings.runSummaryTitle), findsOneWidget);
    });
  });

  group('요약', () {
    /// 달리고 끝내서 요약 화면까지 간다.
    Future<void> finish(WidgetTester tester) async {
      await pumpRun(tester);
      await startRunning(tester);
      await emit(tester, point(37.5, 127));
      await emit(tester, point(37.501, 127));
      await openStopSheet(tester);
      await holdFinish(tester);
    }

    testWidgets('평균 페이스를 보여준다', (tester) async {
      // 요약에서는 **평균**을 본다. 그 순간의 페이스가 아니라 오늘 어떻게
      // 달렸는지가 궁금한 자리다.
      await finish(tester);

      expect(find.textContaining(AppStrings.runSummaryAveragePace), findsOne);
    });

    testWidgets('홈으로 돌아갈 수 있다', (tester) async {
      await finish(tester);

      expect(
        find.widgetWithText(AppButton, AppStrings.runSummaryHome),
        findsOneWidget,
      );
    });
  });
}

/// 아무것도 하지 않는 러닝 채널.
///
/// 이 테스트가 보는 것은 **화면 흐름**이지 서버 통신이 아니다.
/// WebSocket 자체는 `ws_client_test.dart`가 따로 본다.
class _SilentChannel implements RunningChannel {
  @override
  Stream<WsConnectionState> get states => const Stream.empty();

  @override
  WsConnectionState get state => WsConnectionState.connected;

  @override
  Stream<WsErrorCode> get errors => const Stream.empty();

  @override
  Future<void> start(int runningRoomId) async {}

  @override
  bool sendLocations(List<TrackPoint> points) => true;

  @override
  Future<void> close() async {}
}
