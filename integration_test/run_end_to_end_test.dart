import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:runiverse/core/network/ws_client.dart';
import 'package:runiverse/core/network/ws_message.dart';
import 'package:runiverse/core/storage/body_profile_provider.dart';
import 'package:runiverse/core/storage/body_profile_store.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/session/data/fake_running_room_repository.dart';
import 'package:runiverse/features/session/domain/location_repository.dart';
import 'package:runiverse/features/session/domain/run_session_state.dart';
import 'package:runiverse/features/session/domain/running_channel.dart';
import 'package:runiverse/features/session/domain/track_point.dart';
import 'package:runiverse/features/session/presentation/run_session_provider.dart';
import 'package:runiverse/features/session/presentation/running_connection_provider.dart';

/// 러닝 전 구간 — **연결부터 종료까지 한 번에 이어지는가.**
///
/// ```
/// 방 생성 → WS 연결 → RUNNING_START
///   → GPS 수집 → 보정 → 로컬 SQLite 저장
///   → 10초마다 배치 전송
///   → 종료: 남은 것 전송 → RUNNING_FINISH → ack → 트랙 삭제
/// ```
///
/// ## 진짜 배선을 그대로 돌린다
///
/// `RunningConnectionController.open()`과 `finish()`를 **화면이 부르는 그대로**
/// 부른다. 순서를 손으로 흉내 내면 진짜 배선이 어긋나 있어도 통과한다 —
/// 그 어긋남이 지금까지 잡아 온 버그의 종류다.
///
/// | 진짜 | 가짜 |
/// |---|---|
/// | GPS · 칼만 보정 · SQLite · 기록기 · 전송기 · 연결 컨트롤러 | 방 생성(REST) · WS 채널 |
///
/// 서버만 가짜다. **좌표가 소켓 문턱까지 어떤 모양으로 도착하는지**가 여기서
/// 확인할 수 있는 전부이고, 그 너머는 서버가 있어야 한다.
///
/// ## 좌표는 밖에서 밀어 넣는다
///
/// ```
/// adb emu geo fix <경도> <위도> <고도> <위성수> <속도>
/// ```
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const roomId = 4242;

  /// 배치가 두 번 이상 나가도록 기다린다. 전송 주기가 10초다.
  const runFor = Duration(seconds: 25);
  const fixTimeout = Duration(seconds: 60);

  testWidgets('러닝을 시작해서 끝낼 때까지 좌표가 빠짐없이 흐른다', (tester) async {
    await tester.runAsync(() async {
      final channel = _RecordingChannel();
      final body = InMemoryBodyProfileStore();
      await body.save(weightKg: 70);

      final tokens = InMemoryTokenStore();
      await tokens.saveSession(
        userId: 'u-1',
        accessToken: 'a-1',
        refreshToken: 'r-1',
        isOnboarded: true,
      );

      final container = ProviderContainer(
        overrides: [
          // 서버만 가짜다. 나머지는 전부 진짜다.
          runningRoomRepositoryProvider.overrideWithValue(
            FakeRunningRoomRepository(roomId: roomId),
          ),
          runningChannelFactoryProvider.overrideWithValue((_) => channel),
          tokenStoreProvider.overrideWithValue(tokens),
          bodyProfileStoreProvider.overrideWithValue(body),
        ],
      );
      addTearDown(container.dispose);

      final session = container.read(runSessionControllerProvider.notifier);
      final connection = container.read(runningConnectionProvider.notifier);
      final repository = container.read(trackRepositoryProvider);

      // 지난 실행이 남긴 것을 지운다. 안 지우면 순번이 겹친다.
      await repository.clear(roomId);

      // ── 1. 출발 준비 ─────────────────────────────────────
      expect(
        await session.prepare(),
        LocationAccess.granted,
        reason: 'adb pm grant로 위치 권한을 미리 줬어야 한다',
      );

      final waitedFrom = DateTime.now();
      while (true) {
        if (container.read(runSessionControllerProvider)
            case RunPreparing(hasFix: true)) {
          break;
        }
        if (DateTime.now().difference(waitedFrom) > fixTimeout) {
          fail('첫 좌표가 안 온다. 호스트에서 `adb emu geo fix`를 밀고 있는가');
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      debugPrint('[E2E] 1. 첫 신호 · '
          '${DateTime.now().difference(waitedFrom).inSeconds}초');

      // ── 2. 연결 ──────────────────────────────────────────
      session.start();
      await connection.open();

      expect(
        container.read(runningConnectionProvider).room?.id,
        roomId,
        reason: '방을 못 열었다',
      );
      expect(channel.startedRoom, roomId, reason: 'RUNNING_START가 안 나갔다');
      debugPrint('[E2E] 2. RUNNING_START · 방 $roomId');

      // ── 3. 달린다 ────────────────────────────────────────
      await Future<void>.delayed(runFor);

      final storedWhileRunning = await repository.count(roomId);
      expect(
        storedWhileRunning,
        greaterThanOrEqualTo(10),
        reason: '$runFor 동안 1초에 하나씩이면 최소 10개는 쌓여야 한다',
      );
      expect(
        channel.batches,
        isNotEmpty,
        reason: '10초마다 보내야 하는데 한 번도 안 나갔다',
      );
      debugPrint('[E2E] 3. 저장 $storedWhileRunning개 · '
          '배치 ${channel.batches.length}회 · '
          '전송 ${channel.sent.length}개');

      // ── 4. 종료 ──────────────────────────────────────────
      session.finish();
      await connection.finish();
      debugPrint('[E2E] 4. 종료 · 순서 ${channel.order}');

      // ── 검증 ─────────────────────────────────────────────
      final sequences = channel.sent.map((p) => p.sequence).toSet().toList()
        ..sort();

      expect(
        sequences.first,
        1,
        reason: '첫 좌표부터 보내야 한다. 초반이 빠지면 거리가 짧아진다',
      );
      expect(
        sequences,
        List.generate(sequences.length, (i) => i + 1),
        reason: '보낸 순번에 구멍이 있다. 서버가 그 구간을 직선으로 잇는다',
      );

      // ⚠️ **저장한 것이 전부 나갔는가.** 마지막 배치를 안 보내고 끝내면
      // 그 구간이 빠진 기록이 확정되고 되돌릴 수 없다.
      expect(
        sequences.length,
        greaterThanOrEqualTo(storedWhileRunning),
        reason: '저장된 것보다 적게 보냈다',
      );

      expect(
        channel.order.last,
        'finish',
        reason: '좌표를 다 보내기 전에 종료를 보냈다',
      );
      expect(channel.finished, isTrue, reason: 'RUNNING_FINISH가 안 나갔다');

      // ⚠️ ack를 받았으므로 로컬 트랙이 지워져야 한다.
      expect(
        await repository.count(roomId),
        0,
        reason: '종료 확인을 받고도 로컬 트랙이 남았다',
      );

      _report(channel);
    });
  }, timeout: const Timeout(Duration(minutes: 5)));
}

void _report(_RecordingChannel channel) {
  final sent = channel.sent;
  debugPrint('[E2E] ── 전송 요약 ─────────────────────');
  debugPrint('[E2E] 배치 ${channel.batches.length}회 · 좌표 ${sent.length}개');
  debugPrint('[E2E] 배치 크기 ${channel.batches.map((b) => b.length).toList()}');
  debugPrint('[E2E] 순서 ${channel.order}');

  if (sent.isEmpty) return;
  for (final p in [...sent.take(2), ...sent.skip(sent.length - 2)]) {
    debugPrint(
      '[E2E] #${p.sequence} ${p.latitude.toStringAsFixed(6)},'
      '${p.longitude.toStringAsFixed(6)} '
      'hdg=${p.headingDegrees?.toStringAsFixed(0) ?? '--'} '
      'pace=${p.currentPaceSecondsPerKm ?? '--'} '
      'cad=${p.cadenceSpm ?? '--'} ${p.recordedAt}',
    );
  }

  int filled(Object? Function(TrackPoint) of) =>
      sent.where((p) => of(p) != null).length;
  debugPrint(
    '[E2E] 채워진 값 (${sent.length}개 중) · '
    '고도 ${filled((p) => p.altitudeMeters)} · '
    '방향 ${filled((p) => p.headingDegrees)} · '
    '케이던스 ${filled((p) => p.cadenceSpm)} · '
    '페이스 ${filled((p) => p.currentPaceSecondsPerKm)}',
  );
}

/// 서버 대신 받아 적는 채널. **보낸 순서까지 기억한다.**
class _RecordingChannel implements RunningChannel {
  final batches = <List<TrackPoint>>[];
  final order = <String>[];

  int? startedRoom;
  var finished = false;

  List<TrackPoint> get sent => [for (final b in batches) ...b];

  @override
  Stream<WsConnectionState> get states => const Stream.empty();

  @override
  WsConnectionState get state => WsConnectionState.connected;

  @override
  Stream<WsErrorCode> get errors => const Stream.empty();

  @override
  Future<void> start(int runningRoomId) async {
    startedRoom = runningRoomId;
    order.add('start');
  }

  @override
  bool sendLocations(List<TrackPoint> points) {
    if (points.isEmpty) return true;
    if (order.last != 'locations') order.add('locations');
    batches.add(points);
    return true;
  }

  @override
  Future<bool> finish({bool forced = false}) async {
    order.add('finish');
    finished = true;
    // 서버가 ack를 준 척한다. 이것이 로컬 트랙을 지워도 되는 근거다.
    return true;
  }

  @override
  Future<void> close() async {}
}
