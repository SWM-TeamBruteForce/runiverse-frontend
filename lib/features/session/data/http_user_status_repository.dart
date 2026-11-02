import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/core/utils/kst_time.dart';
import 'package:runiverse/features/auth/domain/token_refresher.dart';
import 'package:runiverse/features/session/domain/user_status.dart';
import 'package:runiverse/features/session/domain/user_status_repository.dart';

/// 진짜 서버를 부르는 [UserStatusRepository]. **여기가 응답 형식을 아는 유일한 곳이다.**
///
/// 401이면 한 번만 갱신하고 다시 부른다 — 다른 저장소와 같은 규칙이다.
/// 갱신은 반드시 [TokenRefresher]를 거친다(`docs/implementation-notes.md` 9-6).
class HttpUserStatusRepository implements UserStatusRepository {
  HttpUserStatusRepository(this._dio, this._store, this._refresher);

  final Dio _dio;
  final TokenStore _store;
  final TokenRefresher _refresher;

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

    // ⚠️ **`SOLO`만 보고 갈랐던 자리다**(2026-10-29까지). `INVITE`가 계약에만
    // 있고 내려오지 않던 시절의 코드인데, 초대 방이 생기면서 그 값이 실제로
    // 오기 시작했다 — 그때 초대 방이 `isSolo: false`로 읽혀 **매칭 방 화면이
    // 떴다.** 셋을 셋으로 읽는다.
    //
    // ⚠️ **모르는 값은 매칭으로 접는다. 던지지 않는다.**
    //
    // 던지면 상태 조회가 실패하고, 그러면 홈이 아무것도 못 그리고 방 스트림도
    // 안 열린다 — **방에 들어가 있는 사람이 방에 못 들어간다.** 서버가 네 번째
    // 값을 내리는 날이나 옛 서버가 키를 빼는 날 그렇게 된다.
    //
    // 문구가 틀리는 쪽이 닿을 수 없는 쪽보다 낫고, 매칭이 압도적으로 많다 —
    // `RoomInfo.type`을 nullable로 둔 것과 같은 판단이다. 대신 로그를 남겨
    // 계약이 어긋난 것을 쫓을 수 있게 한다.
    final wire = body?['type'];
    final type = RoomType.of(wire);
    if (type == null) {
      debugPrint('[status] 모르는 방 유형을 매칭으로 읽었다 · $wire');
    }

    final target = body?['targetDistanceMeters'];
    final targetMeters = target is int ? target : null;

    return switch (status) {
      // ⚠️ 솔로는 모집 단계 없이 태어나므로 여기 오지 않는다. 매칭과 초대
      // 둘뿐이고, 마감 경계만 다르다(매칭 10분 전 · 초대 1분 전).
      'WAITING' => UserStatusWaiting(
        runningRoomId: roomId,
        type: type ?? RoomType.match,
        scheduledStartAt: startAt,
        targetDistanceMeters: targetMeters,
        cooldownUntil: cooldownUntil,
      ),
      'READY' => UserStatusReady(
        runningRoomId: roomId,
        type: type ?? RoomType.match,
        scheduledStartAt: startAt,
        targetDistanceMeters: targetMeters,
        cooldownUntil: cooldownUntil,
      ),
      'RUNNING' => UserStatusRunning(
        runningRoomId: roomId,
        type: type ?? RoomType.match,
        scheduledStartAt: startAt,
        targetDistanceMeters: targetMeters,
        cooldownUntil: cooldownUntil,
      ),
      _ => throw const UserStatusException(UserStatusFailure.unknown),
    };
  }

  /// 서버는 시간대 없는 한국 시각을 준다. [KstTime]이 그것을 기기 시각으로
  /// 옮긴다 — 기기가 한국이 아니어도 남은 시간이 맞는다.
  static DateTime? _dateOrNull(Object? value) => KstTime.parse(value);

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
        return await call(await _refreshed());
      } on DioException catch (retried) {
        throw UserStatusException(_failureOf(retried));
      }
    }
  }

  Future<String> _refreshed() async {
    final accessToken = await _refresher.refresh();
    if (accessToken == null) {
      throw const UserStatusException(UserStatusFailure.sessionExpired);
    }
    return accessToken;
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
