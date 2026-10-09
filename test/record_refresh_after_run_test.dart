import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/network/ws_client.dart';
import 'package:runiverse/core/network/ws_message.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/record/domain/run_detail.dart';
import 'package:runiverse/features/record/domain/run_record.dart';
import 'package:runiverse/features/record/domain/run_record_repository.dart';
import 'package:runiverse/features/record/presentation/record_provider.dart';
import 'package:runiverse/features/record/presentation/record_state.dart';
import 'package:runiverse/features/session/data/fake_running_room_repository.dart';
import 'package:runiverse/features/session/data/fake_track_repository.dart';
import 'package:runiverse/features/session/domain/run_progress.dart';
import 'package:runiverse/features/session/domain/run_snapshot.dart';
import 'package:runiverse/features/session/domain/running_channel.dart';
import 'package:runiverse/features/session/domain/track_point.dart';
import 'package:runiverse/features/session/presentation/run_session_provider.dart';
import 'package:runiverse/features/session/presentation/running_connection_provider.dart';

/// 러닝을 끝내면 기록 탭이 **그 기록을 본다.**
///
/// ## ⚠️ 기기에서야 드러난 것이다
///
/// 1.22km 를 실제로 달려 서버에 저장까지 됐는데, 기록 탭은 `러닝 0회`였다.
/// 앱을 껐다 켜야 보였다. `StatefulShellRoute.indexedStack`이 한 번 연 탭을
/// 살려 두므로 [RecordController]가 dispose되지 않고, `build`가 두 번 돌지
/// 않는다 — 아무도 다시 읽으라고 말해 주지 않았다.
///
/// ## ⚠️ "다시 불렀나"를 보지 않는다
///
/// 호출 횟수만 세면 **서버가 아직 확정하지 않은 때 불러도 통과한다.** 그때
/// 받는 것은 고치기 전과 똑같은 빈 목록이다. 그래서 저장소의 답이 중간에
/// 바뀌게 해 두고, **새 기록이 화면 상태에 들어왔는지**를 본다.
void main() {
  const roomId = 700;
  final today = DateTime(2026, 10, 4, 11, 53);

  late _GrowingRecords records;
  late _AckChannel channel;

  setUp(() {
    records = _GrowingRecords(today);
    channel = _AckChannel();
  });

  Future<ProviderContainer> make() async {
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
        trackRepositoryProvider.overrideWithValue(FakeTrackRepository()),
        runningRoomRepositoryProvider.overrideWithValue(
          FakeRunningRoomRepository(roomId: roomId),
        ),
        runningChannelFactoryProvider.overrideWithValue((_) => channel),
        runRecordRepositoryProvider.overrideWithValue(records),
        recordClockProvider.overrideWithValue(() => today),
      ],
    );
  }

  /// 기록 탭을 띄워 둔다. **구독을 들고 있어야** provider가 살아 있다 —
  /// 실제 화면에서는 숨은 탭이 그 역할을 한다.
  Future<ProviderContainer> opened() async {
    final container = await make();
    container.listen(recordControllerProvider, (_, _) {});
    await _settle();
    return container;
  }

  List<RunRecord> shown(ProviderContainer container) {
    final state = container.read(recordControllerProvider);
    return state is RecordData ? state.selectedRecords : const [];
  }

  Future<void> finishRun(ProviderContainer container) async {
    await container.read(runningConnectionProvider.notifier).open();
    await container.read(runningConnectionProvider.notifier).finish();
    await _settle();
  }

  test('달리기 전에는 오늘 기록이 없다', () async {
    final container = await opened();

    expect(shown(container), isEmpty);
  });

  test('⚠️ 러닝을 끝내면 그 기록이 보인다', () async {
    final container = await opened();
    expect(shown(container), isEmpty);

    // 서버가 기록을 확정했다.
    records.saved = true;
    await finishRun(container);

    expect(shown(container), hasLength(1));
    expect(shown(container).single.runningRoomId, roomId);
  });

  test('⚠️ 보고 있던 달을 그대로 둔다', () async {
    // 지난달을 펼쳐 둔 채 러닝을 끝냈을 때 화면이 이번 달로 튀면,
    // 사용자는 자기가 보던 자리를 잃는다.
    final container = await opened();
    await container
        .read(recordControllerProvider.notifier)
        .load(month: DateTime(2026, 9));
    await _settle();

    records.saved = true;
    await finishRun(container);

    final state = container.read(recordControllerProvider);
    expect(state, isA<RecordData>());
    expect((state as RecordData).month, DateTime(2026, 9));
  });

  test('⚠️ 연결을 내려놓는 것은 새 기록이 아니다', () async {
    // `close()`가 `finishedRoomId`를 비운다. 그 **사라짐**까지 "바뀌었다"로
    // 세면, 러닝과 무관한 정리 때마다 목록을 다시 읽는다.
    final container = await opened();
    records.saved = true;
    await finishRun(container);
    final after = records.calls;

    await container.read(runningConnectionProvider.notifier).close();
    await _settle();

    expect(records.calls, after, reason: '비워지는 것은 새 기록이 아니다');
  });

  test('⚠️ 종료 확인을 못 받으면 다시 읽지 않는다', () async {
    // ack 가 없으면 서버가 그 러닝을 확정했는지 알 수 없다. 그 상태로 읽으면
    // 빈 목록을 받아 **고치기 전과 똑같아진다.**
    final container = await opened();
    channel.acks = false;

    records.saved = true;
    await finishRun(container);

    expect(records.calls, 3, reason: '처음 읽은 세 번에서 늘면 안 된다');
  });
}

/// 앞선 마이크로태스크와 타이머를 흘려보낸다.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

/// 중간에 답이 바뀌는 저장소. [saved]가 서면 오늘 기록 하나를 준다.
class _GrowingRecords implements RunRecordRepository {
  _GrowingRecords(this._today);

  final DateTime _today;

  /// 서버가 기록을 확정했는가.
  var saved = false;

  /// `byDateRange`가 몇 번 불렸나. 한 번 읽을 때 **세 번** 나간다 — 달 ·
  /// 주간 차트 · 스트립. 한 조회로 합치면 31일 상한에 걸린다.
  var calls = 0;

  @override
  Future<List<RunRecord>> byDateRange({
    required DateTime from,
    required DateTime to,
  }) async {
    calls++;
    if (!saved) return const [];
    return [
      RunRecord(
        id: 1,
        runningRoomId: 700,
        startedAt: _today,
        distanceMeters: 1220,
        duration: const Duration(minutes: 7),
        averagePace: const Duration(seconds: 344),
        routePolyline: '',
        playerCount: 1,
      ),
    ];
  }

  @override
  Future<RunDetail> byRoom(int runningRoomId) async =>
      throw UnimplementedError();
}

/// 종료를 곧바로 확인해 주는 채널.
class _AckChannel implements RunningChannel {
  /// 서버가 `RUNNING_FINISHED`로 답하는가.
  var acks = true;

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
  Future<bool> finish({bool forced = false}) async => acks;

  @override
  Future<void> close() async {}
}
