import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/network/ws_client.dart';
import 'package:runiverse/core/network/ws_message.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/domain/token_refresher.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/session/data/fake_running_room_repository.dart';
import 'package:runiverse/features/session/data/fake_track_repository.dart';
import 'package:runiverse/features/session/data/http_running_room_repository.dart';
import 'package:runiverse/features/session/domain/run_progress.dart';
import 'package:runiverse/features/session/domain/run_snapshot.dart';
import 'package:runiverse/features/session/domain/running_channel.dart';
import 'package:runiverse/features/session/domain/running_room.dart';
import 'package:runiverse/features/session/domain/track_point.dart';
import 'package:runiverse/features/session/presentation/run_session_provider.dart';
import 'package:runiverse/features/session/presentation/running_connection_provider.dart';

/// 아직 시작하지 않은 방을 **서버에서 없애기**(`DELETE /running-matches`).
///
/// 솔로 방은 만들어지는 순간 `READY`다. 앱을 껐다 켜면 준비 화면이 복구되는데,
/// 거기서 그냥 나가면 방이 서버에 남아 **이후 매칭 신청이 전부 409로 막힌다.**
void main() {
  group('저장소', () {
    late _CannedAdapter api;

    Future<HttpRunningRoomRepository> repositoryReturning({
      int status = 204,
      Map<String, dynamic> body = const {},
    }) async {
      api = _CannedAdapter(body, status: status);
      final store = InMemoryTokenStore();
      await store.saveSession(
        userId: 'u-1',
        accessToken: 'a-1',
        refreshToken: 'r-1',
        isOnboarded: true,
      );
      return HttpRunningRoomRepository(
        Dio(BaseOptions(baseUrl: 'http://test.invalid'))
          ..httpClientAdapter = api,
        store,
        _NoRefresher(),
      );
    }

    test('DELETE /api/v1/running-matches로 나간다', () async {
      final repository = await repositoryReturning();

      await repository.cancelPending();

      expect(api.method, 'DELETE');
      expect(api.path, '/api/v1/running-matches');
    });

    test('⚠️ 404는 실패가 아니다', () async {
      // 다른 기기에서 이미 취소했거나 서버가 방을 닫은 뒤다. 부른 쪽이
      // 원하던 상태이므로 조용히 돌아간다.
      final repository = await repositoryReturning(status: 404);

      await expectLater(repository.cancelPending(), completes);
    });

    test('⚠️ 409는 이미 시작한 방이다', () async {
      // 앱이 상태를 늦게 알고 있다는 신호다. 취소를 다시 시도할 것이 아니라
      // 상태를 다시 읽어야 한다.
      final repository = await repositoryReturning(
        status: 409,
        body: const {'code': 'MATCH_ALREADY_STARTED'},
      );

      await expectLater(
        repository.cancelPending(),
        throwsA(
          isA<RunningRoomException>().having(
            (e) => e.failure,
            'failure',
            RunningRoomFailure.alreadyRunning,
          ),
        ),
      );
    });
  });

  group('연결 컨트롤러', () {
    late _TrackedChannel channel;
    late FakeRunningRoomRepository room;

    Future<ProviderContainer> makeContainer() async {
      final tokens = InMemoryTokenStore();
      await tokens.saveSession(
        userId: 'u-1',
        accessToken: 'a-1',
        refreshToken: 'r-1',
        isOnboarded: true,
      );
      channel = _TrackedChannel();
      room = FakeRunningRoomRepository(roomId: 77);
      return ProviderContainer.test(
        overrides: [
          tokenStoreProvider.overrideWithValue(tokens),
          trackRepositoryProvider.overrideWithValue(FakeTrackRepository()),
          runningRoomRepositoryProvider.overrideWithValue(room),
          runningChannelFactoryProvider.overrideWithValue((_) => channel),
        ],
      );
    }

    test('서버에 취소를 보내고 연결도 내려놓는다', () async {
      final container = await makeContainer();
      final connection = container.read(runningConnectionProvider.notifier);
      await connection.reopen(77, matched: false);

      final ok = await connection.cancelPending();

      expect(ok, isTrue);
      expect(room.cancels, 1);
      expect(channel.closed, isTrue);
      expect(container.read(runningConnectionProvider).room, isNull);
    });

    test('⚠️ 취소가 실패해도 던지지 않는다', () async {
      // 준비 화면에 사용자를 가둘 이유가 없다. 남은 방은 다음 시작의 409
      // 정리 경로가 다시 맡는다.
      final container = await makeContainer();
      final connection = container.read(runningConnectionProvider.notifier);
      room.cancelFailure = RunningRoomFailure.network;

      final ok = await connection.cancelPending();

      expect(ok, isFalse);
    });
  });
}

/// 갱신하지 않는다. 이 테스트는 401을 만들지 않는다.
class _NoRefresher implements TokenRefresher {
  @override
  Future<String?> refresh() async => null;

  @override
  void Function()? get onExpired => null;
}

class _CannedAdapter implements HttpClientAdapter {
  _CannedAdapter(this.body, {this.status = 200});

  final Map<String, dynamic> body;
  final int status;
  String? path;
  String? method;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    path = options.path;
    method = options.method;
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _TrackedChannel implements RunningChannel {
  var closed = false;

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
  Future<bool> finish({bool forced = false}) async => true;

  @override
  Future<void> close() async {
    closed = true;
  }
}
