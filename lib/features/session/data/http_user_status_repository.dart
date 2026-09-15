import 'package:dio/dio.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/domain/auth_failure.dart';
import 'package:runiverse/features/auth/domain/auth_repository.dart';
import 'package:runiverse/features/session/domain/user_status.dart';
import 'package:runiverse/features/session/domain/user_status_repository.dart';

/// 진짜 서버를 부르는 [UserStatusRepository]. **여기가 응답 형식을 아는 유일한 곳이다.**
///
/// 401이면 한 번만 갱신하고 다시 부른다 — 다른 저장소와 같은 규칙이다.
class HttpUserStatusRepository implements UserStatusRepository {
  HttpUserStatusRepository(this._dio, this._store, this._auth);

  final Dio _dio;
  final TokenStore _store;
  final AuthRepository _auth;

  static const _path = '/api/v1/users/me/status';

  /// 앱 진입에서 이것을 기다린다. `/users/me`와 같은 이유로 짧게 끊는다 —
  /// 신호가 나쁜 곳에서 스플래시에 사람을 묶어두지 않는다.
  static const _timeout = Duration(seconds: 5);

  @override
  Future<UserStatus> fetch() => _authorized((token) async {
    final response = await _dio.get<Map<String, dynamic>>(
      _path,
      options: Options(
        headers: {'Authorization': 'Bearer $token'},
        sendTimeout: _timeout,
        receiveTimeout: _timeout,
      ),
    );
    return statusOf(response.data);
  });

  /// 몸통에서 상태를 꺼낸다. **테스트가 직접 부른다.**
  ///
  /// ⚠️ **모르는 `status`는 던진다.** 서버가 값을 늘렸을 때 조용히 `IDLE`로
  /// 읽으면 러닝 중인 사람을 홈으로 보내고 기록이 끊긴다. 모르면 모른다고 한다.
  static UserStatus statusOf(Map<String, dynamic>? body) {
    final cooldownUntil = _dateOrNull(body?['cooldownUntil']);
    final status = body?['status'];

    if (status == 'IDLE') return UserStatusIdle(cooldownUntil: cooldownUntil);

    // 여기부터는 진행 중인 방이 있어야 한다. 방 번호나 시작 시각이 없으면
    // 복구할 수 없으므로 계약이 깨진 것으로 본다.
    final roomId = body?['runningRoomId'];
    final startAt = _dateOrNull(body?['scheduledStartAt']);
    if (roomId is! int || startAt == null) {
      throw const UserStatusException(UserStatusFailure.unknown);
    }

    // ⚠️ `INVITE`는 미래 예약값이라 계약에 없다. 그래서 `SOLO`만 보고 가른다.
    final isSolo = body?['type'] == 'SOLO';
    final target = body?['targetDistanceMeters'];
    final targetMeters = target is int ? target : null;

    return switch (status) {
      // WAITING은 매칭만 가능하다 — 솔로는 모집 단계 없이 태어난다.
      'WAITING' => UserStatusWaiting(
        runningRoomId: roomId,
        scheduledStartAt: startAt,
        targetDistanceMeters: targetMeters,
        cooldownUntil: cooldownUntil,
      ),
      'READY' => UserStatusReady(
        runningRoomId: roomId,
        isSolo: isSolo,
        scheduledStartAt: startAt,
        targetDistanceMeters: targetMeters,
        cooldownUntil: cooldownUntil,
      ),
      'RUNNING' => UserStatusRunning(
        runningRoomId: roomId,
        isSolo: isSolo,
        scheduledStartAt: startAt,
        targetDistanceMeters: targetMeters,
        cooldownUntil: cooldownUntil,
      ),
      _ => throw const UserStatusException(UserStatusFailure.unknown),
    };
  }

  /// 서버는 시간대 없는 한국 시각을 준다. 그대로 **로컬 시각으로** 읽는다.
  ///
  /// ⚠️ `DateTime.parse`는 `Z`가 없으면 로컬로 읽는다. 기기가 한국이면 맞고,
  /// 아니면 어긋난다 — 서버가 오프셋을 실어 주기 전까지 남는 한계다.
  static DateTime? _dateOrNull(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  Future<T> _authorized<T>(Future<T> Function(String accessToken) call) async {
    final stored = await _store.read();
    final accessToken = stored.accessToken;
    if (accessToken == null) {
      throw const UserStatusException(UserStatusFailure.sessionExpired);
    }

    try {
      return await call(accessToken);
    } on DioException catch (error) {
      if (error.response?.statusCode != 401) {
        throw UserStatusException(_failureOf(error));
      }
      try {
        return await call(await _refreshed(stored.refreshToken));
      } on DioException catch (retried) {
        throw UserStatusException(_failureOf(retried));
      }
    }
  }

  Future<String> _refreshed(String? refreshToken) async {
    if (refreshToken == null) {
      throw const UserStatusException(UserStatusFailure.sessionExpired);
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
      throw UserStatusException(
        error.failure == AuthFailure.network
            ? UserStatusFailure.network
            : UserStatusFailure.sessionExpired,
      );
    }
  }

  UserStatusFailure _failureOf(DioException error) {
    if (error.type != DioExceptionType.badResponse) {
      return UserStatusFailure.network;
    }
    return error.response?.statusCode == 401
        ? UserStatusFailure.sessionExpired
        : UserStatusFailure.unknown;
  }
}
