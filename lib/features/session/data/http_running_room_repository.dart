import 'package:dio/dio.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/domain/auth_failure.dart';
import 'package:runiverse/features/auth/domain/auth_repository.dart';
import 'package:runiverse/features/session/domain/running_room.dart';
import 'package:runiverse/features/session/domain/running_room_repository.dart';

/// 진짜 서버를 부르는 [RunningRoomRepository].
///
/// 401이면 **한 번만** 갱신하고 다시 부른다 — 다른 저장소와 같은 규칙이다.
class HttpRunningRoomRepository implements RunningRoomRepository {
  HttpRunningRoomRepository(this._dio, this._store, this._auth);

  final Dio _dio;
  final TokenStore _store;
  final AuthRepository _auth;

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
        return await _post(await _refreshed(stored.refreshToken));
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

  Future<String> _refreshed(String? refreshToken) async {
    if (refreshToken == null) {
      throw const RunningRoomException(RunningRoomFailure.sessionExpired);
    }
    try {
      final tokens = await _auth.refresh(refreshToken);
      // ⚠️ 회전된 refreshToken도 반드시 덮어쓴다. 안 하면 다음 갱신이 죽는다.
      await _store.saveTokens(
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
      );
      return tokens.accessToken;
    } on AuthException catch (error) {
      throw RunningRoomException(
        error.failure == AuthFailure.network
            ? RunningRoomFailure.network
            : RunningRoomFailure.sessionExpired,
      );
    }
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
