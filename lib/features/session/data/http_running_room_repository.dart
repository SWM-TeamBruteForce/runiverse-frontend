import 'package:dio/dio.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/domain/token_refresher.dart';
import 'package:runiverse/features/session/domain/running_room.dart';
import 'package:runiverse/features/session/domain/running_room_repository.dart';

/// 진짜 서버를 부르는 [RunningRoomRepository].
///
/// 401이면 **한 번만** 갱신하고 다시 부른다 — 다른 저장소와 같은 규칙이다.
///
/// ## ⚠️ 갱신을 직접 부르지 않는다
///
/// 러닝을 시작하면 이 호출과 WebSocket 핸드셰이크가 **같은 만료 토큰으로 거의
/// 동시에** 나간다. 양쪽이 각자 갱신하면 두 번째가 이미 회전된 리프레시 토큰을
/// 보내게 되고, 서버가 그것을 탈취로 보고 **잘못 없는 사용자를 로그아웃시킨다**
/// (`docs/implementation-notes.md` 9-6). [TokenRefresher]가 둘을 한 줄로 모은다.
class HttpRunningRoomRepository implements RunningRoomRepository {
  HttpRunningRoomRepository(this._dio, this._store, this._refresher);

  final Dio _dio;
  final TokenStore _store;
  final TokenRefresher _refresher;

  static const _soloPath = '/api/v1/running-rooms/solo';

  @override
  Future<RunningRoom> openSolo() async {
    final stored = await _store.read();
    final accessToken = stored.accessToken;
    if (accessToken == null) {
      throw const RunningRoomException(RunningRoomFailure.sessionExpired);
    }

    try {
      return await _post(accessToken);
    } on DioException catch (error) {
      if (error.response?.statusCode != 401) {
        throw RunningRoomException(_failureOf(error));
      }
      try {
        return await _post(await _refreshed());
      } on DioException catch (retried) {
        throw RunningRoomException(_failureOf(retried));
      }
    }
  }

  Future<RunningRoom> _post(String accessToken) async {
    final response = await _dio.post<Map<String, dynamic>>(
      _soloPath,
      options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
    );
    final id = response.data?['runningRoomId'];
    // 201인데 몸통이 다르다. 방 번호가 없으면 WS에 연결할 수 없다.
    if (id is! int) {
      throw const RunningRoomException(RunningRoomFailure.unknown);
    }
    return RunningRoom(id);
  }

  /// 갱신된 액세스 토큰. 못 받으면 세션이 끝난 것으로 본다.
  ///
  /// 저장과 회전 처리는 [TokenRefresher]가 한다 — 여기서 또 하면 두 곳이
  /// 갈릴 자리가 생긴다.
  Future<String> _refreshed() async {
    final accessToken = await _refresher.refresh();
    if (accessToken == null) {
      throw const RunningRoomException(RunningRoomFailure.sessionExpired);
    }
    return accessToken;
  }

  RunningRoomFailure _failureOf(DioException error) {
    if (error.type != DioExceptionType.badResponse) {
      return RunningRoomFailure.network;
    }
    final status = error.response?.statusCode ?? 0;
    if (status == 409) {
      // 코드를 확인한다. 모르는 409를 "이미 달리는 중"이라고 하면 사용자가
      // 있지도 않은 러닝을 찾아 헤맨다.
      final data = error.response?.data;
      final code = data is Map ? data['code'] : null;
      return code == 'RUNNING_ALREADY_IN_PROGRESS'
          ? RunningRoomFailure.alreadyRunning
          : RunningRoomFailure.unknown;
    }
    if (status == 401) return RunningRoomFailure.sessionExpired;
    if (status >= 500) return RunningRoomFailure.server;
    return RunningRoomFailure.unknown;
  }
}
