import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/session/data/fake_running_room_repository.dart';
import 'package:runiverse/features/session/data/fake_track_repository.dart';
import 'package:runiverse/features/session/data/fake_user_status_repository.dart';
import 'package:runiverse/features/session/domain/running_room.dart';
import 'package:runiverse/features/session/domain/user_status.dart';
import 'package:runiverse/features/session/presentation/run_session_provider.dart';
import 'package:runiverse/features/session/presentation/running_connection_provider.dart';
import 'package:runiverse/features/session/presentation/user_status_provider.dart';

/// 매칭이 걸려 있을 때의 혼자 뛰기 — **무엇이 막는지 말하고, 풀리면 풀리는가.**
///
/// 서버는 매칭이든 남은 러닝이든 같은 409(`RUNNING_ALREADY_IN_PROGRESS`)로
/// 막는다. 앱이 그걸 한 문구로 뭉뚱그리면 **매칭을 신청해 둔 사람이 있지도
/// 않은 러닝을 찾게 된다.**
///
/// 더 나빴던 것은 그 다음이다. 매칭을 취소해 서버가 풀어 줘도 앱이 들고 있던
/// 이유가 살아 있어서, 준비 화면이 들어가자마자 다시 충돌 화면을 그렸다.
void main() {
  group('막아 둔 이유', () {
    late FakeTrackRepository track;
    late FakeRunningRoomRepository rooms;
    late FakeUserStatusRepository statuses;

    setUp(() {
      track = FakeTrackRepository();
      rooms = FakeRunningRoomRepository(roomId: 700);
      statuses = FakeUserStatusRepository(
        status: UserStatusWaiting(
          runningRoomId: 12,
          scheduledStartAt: _startAt,
        ),
      );
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
          trackRepositoryProvider.overrideWithValue(track),
          runningRoomRepositoryProvider.overrideWithValue(rooms),
          userStatusRepositoryProvider.overrideWithValue(statuses),
        ],
      );
    }

    /// 매칭 중에 솔로를 눌러 409로 막힌 자리까지 간다.
    Future<ProviderContainer> blocked() async {
      // 남긴 방 번호가 없다 — 정리할 것이 없어 이유만 남는다.
      rooms.failure = RunningRoomFailure.alreadyRunning;
      final container = await make();
      await container.read(runningConnectionProvider.notifier).open();

      expect(
        container.read(runningConnectionProvider).failure,
        RunningRoomFailure.alreadyRunning,
        reason: '409로 막힌 자리를 못 만들었다',
      );
      return container;
    }

    test('⚠️ 매칭을 취소하면 막아 둔 이유도 풀린다', () async {
      // 이것이 없으면 취소한 뒤에도 준비 화면이 들어가자마자 충돌 화면이다.
      // 서버는 풀어 줬는데 앱만 막고 있는 상태라, 앱을 껐다 켜야 풀렸다.
      final container = await blocked();

      statuses.status = const UserStatusIdle();
      await container.read(userStatusProvider.notifier).refresh();
      await Future<void>.delayed(Duration.zero);

      expect(container.read(runningConnectionProvider).failure, isNull);
    });

    test('아직 매칭 중이면 막아 둔 채로 둔다', () async {
      final container = await blocked();

      // 같은 상태를 다시 읽었을 뿐이다. 풀어 줄 근거가 없다.
      await container.read(userStatusProvider.notifier).refresh();
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(runningConnectionProvider).failure,
        RunningRoomFailure.alreadyRunning,
      );
    });
  });
}

final _startAt = DateTime(2026, 10, 19, 9);
