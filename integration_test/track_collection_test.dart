import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:runiverse/features/session/domain/location_repository.dart';
import 'package:runiverse/features/session/domain/run_session_state.dart';
import 'package:runiverse/features/session/domain/track_point.dart';
import 'package:runiverse/features/session/presentation/run_session_provider.dart';

/// 좌표가 **기기의 진짜 SQLite까지** 닿는지 본다.
///
/// ## 왜 기기에서 도는 테스트가 따로 필요한가
///
/// `test/`의 것들은 Dart VM에서 돈다. 거기서는 GPS도 `sqflite`도 플랫폼 채널을
/// 못 건너가 가짜로 갈아 끼워야 하고, 그래서 **둘을 잇는 배선은 아무도 확인하지
/// 않는 상태**로 남는다. 실제로 `sqflite_common_ffi`는 `getDatabasesPath()`를
/// 부르지 않으므로 그 경로가 기기에서 되는지도 여기서만 드러난다.
///
/// ## 서버를 타지 않는다
///
/// 로그인도 방 생성도 하지 않는다. 방 번호는 [_testRoomId]를 직접
/// [TrackRecorder.bind]에 넣는다 — 그 번호가 어디서 왔는지는 이 테스트의
/// 관심사가 아니고, 서버에 방이 남아 409가 나는 것과도 무관해진다.
///
/// ## 좌표는 밖에서 밀어 넣는다
///
/// ```
/// adb emu geo fix <경도> <위도> <고도> <위성수> <속도>
/// ```
///
/// 이 테스트가 도는 동안 호스트에서 1초에 한 번씩 밀어 넣어야 한다.
/// 안 밀어 넣으면 첫 신호를 못 받고 [_fixTimeout]에서 실패한다.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// 실제 방 번호와 겹치지 않게 크게 잡는다. 서버가 이 번호를 줄 일은 없다.
  const testRoomId = 999999;

  /// 첫 좌표를 얼마나 기다리나. 에뮬레이터가 첫 fix를 물기까지 시간이 걸린다.
  const fixTimeout = Duration(seconds: 60);

  /// 달리는 시간. 1초에 하나씩 들어오므로 대략 이 초만큼 쌓인다.
  const runFor = Duration(seconds: 30);

  testWidgets('임의 좌표가 로컬 DB에 쌓인다', (tester) async {
    // ⚠️ `runAsync` 안에서 해야 한다. 밖에서는 테스트용 가짜 시계가 돌아
    // `Future.delayed`가 실제로 흐르지 않고 GPS 스트림도 오지 않는다.
    await tester.runAsync(() async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final repository = container.read(trackRepositoryProvider);
      final recorder = container.read(trackRecorderProvider);
      final controller = container.read(runSessionControllerProvider.notifier);

      // 지난 실행이 남긴 것을 지우고 시작한다. 안 지우면 순번이 겹쳐
      // 몇 개가 새로 들어왔는지 알 수 없다.
      await repository.clear(testRoomId);
      expect(await repository.count(testRoomId), 0, reason: '시작 전에 비어 있어야 한다');

      // ── 1. 권한과 구독 ────────────────────────────────────
      final access = await controller.prepare();
      expect(
        access,
        LocationAccess.granted,
        reason: 'adb pm grant로 미리 줬어야 한다',
      );

      // ── 2. 첫 신호를 기다린다 ─────────────────────────────
      final waitedFrom = DateTime.now();
      while (true) {
        // `while`은 패턴을 받지 못한다. `if`로 확인하고 빠져나온다.
        if (container.read(runSessionControllerProvider)
            case RunPreparing(hasFix: true)) {
          break;
        }
        if (DateTime.now().difference(waitedFrom) > fixTimeout) {
          fail('첫 좌표가 안 온다. 호스트에서 `adb emu geo fix`를 밀고 있는가');
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      debugPrint('[IT] 첫 신호까지 '
          '${DateTime.now().difference(waitedFrom).inSeconds}초');

      // ── 3. 달린다 ─────────────────────────────────────────
      controller.start();
      expect(
        container.read(runSessionControllerProvider),
        isA<RunRunning>(),
        reason: 'hasFix가 true여야 start()가 걸린다',
      );

      // 방을 알려준다. 이 순간까지 들어온 좌표가 한꺼번에 저장된다.
      await recorder.bind(testRoomId);

      await Future<void>.delayed(runFor);
      controller.finish();

      // 마지막 좌표의 저장이 끝나기를 기다린다. `_onPoint`가 `unawaited`로
      // 던지므로 곧바로 읽으면 몇 개가 빠져 보인다.
      await Future<void>.delayed(const Duration(seconds: 2));

      // ── 4. 쌓인 것을 본다 ─────────────────────────────────
      final points = await repository.after(testRoomId, limit: 10000);
      _report(points);

      expect(
        points.length,
        greaterThanOrEqualTo(10),
        reason: '$runFor 동안 1초에 하나씩이면 최소 10개는 들어와야 한다',
      );
      expect(recorder.pendingCount, 0, reason: 'bind 뒤에는 밀린 것이 없어야 한다');

      // 순번은 빠짐없이 이어져야 한다. 구멍은 곧 잃어버린 좌표다.
      final sequences = points.map((p) => p.sequence).toList();
      expect(
        sequences,
        List.generate(points.length, (i) => sequences.first + i),
        reason: '순번에 구멍이 있다',
      );

      // 서버가 읽을 형식 그대로 되살아나야 한다. `Z`나 마이크로초가 붙으면
      // 서버가 거절하는데, 저장할 때는 에러가 안 나서 늦게 발견된다.
      for (final point in points) {
        expect(
          TrackPoint.formatServerTime(point.recordedAt),
          matches(RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$')),
          reason: '시각 형식이 서버 명세와 다르다',
        );
      }

      // 밀어 넣은 좌표 근처여야 한다. 경도·위도를 바꿔 넣으면 여기서 걸린다.
      for (final point in points) {
        expect(point.latitude, inInclusiveRange(37.0, 38.0));
        expect(point.longitude, inInclusiveRange(126.0, 128.0));
      }

      // 뒤쪽 좌표에는 페이스가 붙어 있어야 한다. 첫 점은 직전 점이 없어
      // 비어 있을 수 있다.
      expect(
        points.skip(3).where((p) => p.currentPaceSecondsPerKm != null),
        isNotEmpty,
        reason: '페이스가 하나도 안 박혔다',
      );

      // ⚠️ **끝나고 지우지 않는다.** 격리는 시작할 때의 `clear`가 이미 맡고
      // 있고, 여기서 또 지우면 **무엇이 쌓였는지 기기에서 확인할 방법이
      // 없어진다** — DB 파일을 뽑아 눈으로 보는 것이 이 테스트의 절반이다.
    });
  }, timeout: const Timeout(Duration(minutes: 5)));
}

/// 무엇이 쌓였는지 눈으로 확인할 수 있게 찍는다.
///
/// 통과·실패만으로는 "값이 그럴듯한가"를 알 수 없다. 고도나 방향이 통째로
/// 비어 있어도 테스트는 통과하므로, 채워진 비율을 함께 남긴다.
void _report(List<TrackPoint> points) {
  debugPrint('[IT] ── 쌓인 좌표 ${points.length}개 ──────────────');
  if (points.isEmpty) return;

  debugPrint('[IT] 순번 ${points.first.sequence}~${points.last.sequence}');
  debugPrint('[IT] 시각 ${TrackPoint.formatServerTime(points.first.recordedAt)}'
      ' ~ ${TrackPoint.formatServerTime(points.last.recordedAt)}');

  for (final p in [...points.take(3), ...points.skip(points.length - 3)]) {
    debugPrint(
      '[IT] #${p.sequence} '
      '${p.latitude.toStringAsFixed(6)},${p.longitude.toStringAsFixed(6)} '
      'alt=${p.altitudeMeters} acc=${p.accuracyMeters.toStringAsFixed(1)} '
      'spd=${p.speedMetersPerSecond.toStringAsFixed(2)} '
      'hdg=${p.headingDegrees} pace=${p.currentPaceSecondsPerKm}',
    );
  }

  int filled(Object? Function(TrackPoint) of) =>
      points.where((p) => of(p) != null).length;

  debugPrint(
    '[IT] 채워진 값 (${points.length}개 중) · '
    '고도 ${filled((p) => p.altitudeMeters)} · '
    '방향 ${filled((p) => p.headingDegrees)} · '
    '케이던스 ${filled((p) => p.cadenceSpm)} · '
    '페이스 ${filled((p) => p.currentPaceSecondsPerKm)}',
  );
}
