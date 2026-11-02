import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/core/utils/kst_time.dart';
import 'package:runiverse/features/auth/domain/token_refresher.dart';
import 'package:runiverse/features/matching/data/slot_board_dto.dart';
import 'package:runiverse/features/matching/domain/invite_failure.dart';
import 'package:runiverse/features/matching/domain/match_failure.dart';
import 'package:runiverse/features/matching/domain/match_repository.dart';
import 'package:runiverse/features/matching/domain/slot_board.dart';
import 'package:runiverse/features/matching/domain/slot_load_failure.dart';

/// 진짜 서버를 부르는 [MatchRepository]. **여기가 응답 형식을 아는 유일한 곳이다.**
///
/// 401이면 한 번만 갱신하고 다시 부른다 — 다른 저장소와 같은 규칙이다.
/// 갱신은 반드시 [TokenRefresher]를 거친다(`docs/implementation-notes.md` 9-6).
class HttpMatchRepository implements MatchRepository {
  HttpMatchRepository(this._dio, this._store, this._refresher);

  final Dio _dio;
  final TokenStore _store;
  final TokenRefresher _refresher;

  /// ⚠️ **2026-10-28에 `/running-matches`에서 바뀌었다**(BE PR #112). 서버가
  /// 옛 주소를 남기지 않고 지워서 호환이 없다 — 옛 주소로 보내면 404다.
  static const _path = '/api/v1/match-rooms';

  /// 나가기. ⚠️ **주소와 방식이 함께 바뀌었다** — `DELETE /running-matches`
  /// 였다. 주소만 고치고 `DELETE`로 보내면 405다.
  static const _leavePath = '$_path/leave';

  @override
  Future<SlotBoard> slots() async {
    // ⚠️ **`_authorized`를 쓰지 않는다.** 그쪽은 `MatchException`을 던지는데,
    // 조회는 자기 갈래를 갖는다(아래 [_loadExceptionOf]). 401 한 번 갱신은
    // 여기서 직접 한다.
    final stored = await _store.read();
    var token = stored.accessToken;
    if (token == null) {
      throw const SlotLoadException(SlotLoadFailure.sessionExpired);
    }

    Future<Response<Map<String, dynamic>>> call(String accessToken) =>
        _dio.get<Map<String, dynamic>>(
          '$_path/slots',
          // ⚠️ **쿼리를 하나도 보내지 않는다.** 거리는 명세가 받지 않고(판
          // 전체가 온다), `date`는 오늘뿐이라 보내면 형식이 틀렸을 때 400을
          // 자초한다. 생략하면 서버가 오늘로 읽는다.
          options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
        );

    try {
      Response<Map<String, dynamic>> response;
      try {
        response = await call(token);
      } on DioException catch (error) {
        if (error.response?.statusCode != 401) rethrow;
        token = await _refreshed();
        response = await call(token);
      }
      return slotBoardFromJson(response.data);
    } on DioException catch (error) {
      throw SlotLoadException(_loadExceptionOf(error));
    } on MatchException catch (error) {
      // ⚠️ `_refreshed`가 신청용 갈래로 던진다. 그대로 새어 나가면 화면이
      // 조회 실패를 **신청 실패로 읽어** 스낵바를 띄우고 바로 지운다.
      throw SlotLoadException(
        error.failure == MatchFailure.sessionExpired
            ? SlotLoadFailure.sessionExpired
            : SlotLoadFailure.network,
      );
    }
  }

  @override
  Future<int> apply({required String slotRaw, required int meters}) =>
      _authorized((token) async {
        final response = await _dio.post<Map<String, dynamic>>(
          _path,
          // ⚠️ 서버가 준 문자열·미터값을 그대로 돌려보낸다. 다시 조립하지도,
          // `TargetDistance`를 거치지도 않는다.
          data: {'scheduledStartAt': slotRaw, 'targetDistanceMeters': meters},
          options: Options(headers: {'Authorization': 'Bearer $token'}),
        );
        final roomId = response.data?['runningRoomId'];
        // 방 번호가 없으면 신청은 됐는데 스트림에 붙을 수 없다. 조용히 넘기면
        // 신청해 놓고 아무 소식도 못 받는 상태가 된다.
        if (roomId is! int) throw const MatchException(MatchFailure.unknown);
        // 이 번호가 신청·러닝·결과 조회를 잇는 유일한 고리다. 남겨두면 "어느 방에
        // 배정됐나"를 로그만으로 따라갈 수 있다 — 같은 조건으로 신청한 두 사람이
        // 한 방에 묶였는지도 이 한 줄로 갈린다.
        debugPrint('[match] 방에 배정됐다 · $roomId');
        return roomId;
      });

  @override
  Future<void> cancel() => _authorized((token) async {
    await _dio.post<void>(
      _leavePath,
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
  });

  @override
  Future<int> createInviteRoom({
    required String scheduledStartAt,
    required int meters,
  }) => _invited((token) async {
    final response = await _dio.post<Map<String, dynamic>>(
      _invitePath,
      data: {
        'scheduledStartAt': scheduledStartAt,
        'targetDistanceMeters': meters,
      },
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    final roomId = response.data?['runningRoomId'];
    // 방은 열렸는데 스트림에 붙을 수 없다. 조용히 넘기면 방을 만들어 놓고
    // 아무 소식도 못 받는 상태가 된다 — `apply`와 같은 판단이다.
    if (roomId is! int) throw const InviteException(InviteFailure.unknown);
    debugPrint('[invite] 초대 방을 열었다 · $roomId');
    return roomId;
  });

  @override
  Future<void> invite({required int roomId, required String inviteeId}) =>
      _invited((token) async {
        await _dio.post<void>(
          '$_path/$roomId/invitations',
          // ⚠️ 한 명만 보낸다. 배열이 아니다.
          data: {'inviteeId': inviteeId},
          options: Options(headers: {'Authorization': 'Bearer $token'}),
        );
      });

  @override
  Future<int> acceptInvitation(int roomId) => _invited((token) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '$_path/$roomId/invitations/accept',
      // ⚠️ **본문이 없다.** 받는 사람은 토큰 주체다.
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    final accepted = response.data?['runningRoomId'];
    if (accepted is! int) throw const InviteException(InviteFailure.unknown);
    return accepted;
  });

  @override
  Future<void> declineInvitation(int roomId) => _invited((token) async {
    await _dio.post<void>(
      '$_path/$roomId/invitations/decline',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
  });

  /// 초대 방 개설 경로. **매칭 신청(`POST $_path`)과 다른 자리다.**
  static const _invitePath = '$_path/invite';

  /// 초대 요청에서 실패 갈래를 읽는다. **테스트가 직접 부른다.**
  ///
  /// ⚠️ **[exceptionOf]를 쓰지 않는다.** 저쪽은 404를
  /// `MatchFailure.nothingToCancel`로 묶어서, 그대로 쓰면 초대 실패에
  /// "취소할 활성 신청이 없어요"가 뜬다. `_loadExceptionOf`가 같은 이유로
  /// 따로 있는 것과 같은 판단이다.
  ///
  /// **서버 문구를 그대로 들고 온다** — 명세가 그러라고 한다.
  static InviteException inviteExceptionOf(DioException error) {
    if (error.type != DioExceptionType.badResponse) {
      return const InviteException(InviteFailure.network);
    }

    final response = error.response;
    final body = response?.data;
    final code = body is Map ? body['code'] : null;
    final message = body is Map && body['message'] is String
        ? body['message'] as String
        : null;

    final status = response?.statusCode;
    if (status == 401) {
      return const InviteException(InviteFailure.sessionExpired);
    }
    // ⚠️ 방 없음·초대 방 아님·내가 참가자 아님을 서버가 구분하지 않는다.
    if (status == 404) {
      return InviteException(InviteFailure.notFound, message: message);
    }
    if (status != null && status >= 500) {
      return const InviteException(InviteFailure.network);
    }

    return InviteException(switch (code) {
      'RUNNING_INVITATION_CLOSED' => InviteFailure.closed,
      'NOT_FRIEND' => InviteFailure.notFriend,
      'INVITEE_ALREADY_IN_ROOM' => InviteFailure.alreadyInRoom,
      'INVITEE_IN_MATCHING' => InviteFailure.inMatching,
      'INVITEE_RUNNING' => InviteFailure.running,
      'INVITE_COUNT_EXCEEDED' => InviteFailure.countExceeded,
      'RUNNING_INVITATION_NOT_PENDING' => InviteFailure.notPending,
      'RUNNING_ROOM_FULL' => InviteFailure.roomFull,
      'INVITE_START_AT_OUT_OF_RANGE' => InviteFailure.startAtOutOfRange,
      'RUNNING_ALREADY_IN_PROGRESS' => InviteFailure.alreadyInProgress,
      'ONBOARDING_NOT_COMPLETED' => InviteFailure.onboardingNotCompleted,
      'INVALID_REQUEST' => InviteFailure.invalidRequest,
      _ => InviteFailure.unknown,
    }, message: message);
  }

  /// [_authorized]와 같은 일을 하되 [InviteException]으로 던진다.
  Future<T> _invited<T>(Future<T> Function(String accessToken) call) async {
    final stored = await _store.read();
    final accessToken = stored.accessToken;
    if (accessToken == null) {
      throw const InviteException(InviteFailure.sessionExpired);
    }

    try {
      return await call(accessToken);
    } on DioException catch (error) {
      if (error.response?.statusCode != 401) throw inviteExceptionOf(error);
      try {
        return await call(await _refreshed());
      } on DioException catch (retried) {
        throw inviteExceptionOf(retried);
      } on MatchException {
        // `_refreshed`가 신청용 갈래로 던진다. 초대 쪽으로 옮긴다.
        throw const InviteException(InviteFailure.sessionExpired);
      }
    } on MatchException {
      throw const InviteException(InviteFailure.sessionExpired);
    }
  }

  /// 응답에서 실패 갈래를 읽는다. **테스트가 직접 부른다.**
  static MatchException exceptionOf(DioException error) {
    if (error.type != DioExceptionType.badResponse) {
      return const MatchException(MatchFailure.network);
    }

    final response = error.response;
    final body = response?.data;
    final code = body is Map ? body['code'] : null;

    if (response?.statusCode == 401) {
      return const MatchException(MatchFailure.sessionExpired);
    }
    if (response?.statusCode == 404) {
      return const MatchException(MatchFailure.nothingToCancel);
    }

    return switch (code) {
      'MATCH_SLOT_CLOSED' => const MatchException(MatchFailure.slotClosed),
      'MATCH_COOLDOWN' => MatchException(
        MatchFailure.cooldown,
        cooldownUntil: body is Map ? _dateOrNull(body['cooldownUntil']) : null,
      ),
      'MATCH_ALREADY_IN_PROGRESS' || 'RUNNING_ALREADY_IN_PROGRESS' =>
        const MatchException(MatchFailure.alreadyInProgress),
      'MATCH_ALREADY_STARTED' => const MatchException(
        MatchFailure.alreadyStarted,
      ),
      'ONBOARDING_NOT_COMPLETED' => const MatchException(
        MatchFailure.onboardingNotCompleted,
      ),
      'INVALID_REQUEST' => const MatchException(MatchFailure.invalidRequest),
      _ => const MatchException(MatchFailure.unknown),
    };
  }

  /// 조회 실패를 읽는다. **[exceptionOf]를 쓰지 않는다** — 저쪽은 404를
  /// `nothingToCancel`로 묶어서, 그대로 쓰면 목록을 못 받은 사람에게
  /// "취소할 활성 신청이 없어요"가 뜬다.
  static SlotLoadFailure _loadExceptionOf(DioException error) {
    if (error.type != DioExceptionType.badResponse) {
      return SlotLoadFailure.network;
    }

    final status = error.response?.statusCode ?? 0;
    if (status == 401) return SlotLoadFailure.sessionExpired;
    // 5xx는 사용자가 할 일이 네트워크 실패와 같다 — 다시 눌러보는 것뿐이다.
    if (status >= 500) return SlotLoadFailure.network;

    final body = error.response?.data;
    if (body is Map && body['code'] == 'INVALID_REQUEST') {
      // 앱은 거리 셋만 보내고 날짜는 안 보낸다. 여기 오면 **앱 규칙이 서버와
      // 어긋났다는 신호**라 남긴다. 화면에는 일반 실패로만 보인다.
      debugPrint('[match] 슬롯 조회를 서버가 거절했다 · ${body['message']}');
      return SlotLoadFailure.invalidRequest;
    }
    return SlotLoadFailure.unknown;
  }

  /// 서버는 시간대 없는 한국 시각을 준다. [KstTime]이 그것을 기기 시각으로
  /// 옮긴다 — 기기가 한국이 아니어도 남은 시간이 맞는다.
  static DateTime? _dateOrNull(Object? value) => KstTime.parse(value);

  Future<T> _authorized<T>(Future<T> Function(String accessToken) call) async {
    final stored = await _store.read();
    final accessToken = stored.accessToken;
    if (accessToken == null) {
      throw const MatchException(MatchFailure.sessionExpired);
    }

    try {
      return await call(accessToken);
    } on DioException catch (error) {
      if (error.response?.statusCode != 401) throw exceptionOf(error);
      try {
        return await call(await _refreshed());
      } on DioException catch (retried) {
        throw exceptionOf(retried);
      }
    }
  }

  Future<String> _refreshed() async {
    final accessToken = await _refresher.refresh();
    if (accessToken == null) {
      throw const MatchException(MatchFailure.sessionExpired);
    }
    return accessToken;
  }
}
