import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/core/utils/kst_time.dart';
import 'package:runiverse/features/auth/domain/auth_failure.dart';
import 'package:runiverse/features/auth/domain/auth_repository.dart';
import 'package:runiverse/features/matching/domain/match_failure.dart';
import 'package:runiverse/features/matching/domain/match_repository.dart';
import 'package:runiverse/features/matching/domain/match_slot.dart';
import 'package:runiverse/features/matching/domain/target_distance.dart';

/// 진짜 서버를 부르는 [MatchRepository]. **여기가 응답 형식을 아는 유일한 곳이다.**
///
/// 401이면 한 번만 갱신하고 다시 부른다 — 다른 저장소와 같은 규칙이다.
class HttpMatchRepository implements MatchRepository {
  HttpMatchRepository(this._dio, this._store, this._auth);

  final Dio _dio;
  final TokenStore _store;
  final AuthRepository _auth;

  static const _path = '/api/v1/running-matches';
  static const _slotsPath = '$_path/slots';

  @override
  Future<List<MatchSlot>> fetchSlots({TargetDistance? distance}) =>
      _authorized((token) async {
        final response = await _dio.get<Map<String, dynamic>>(
          _slotsPath,
          // `date`를 보내지 않는다. 오늘이 언제인지는 서버가 정한다 —
          // 기기 시계로 날짜를 조립하면 자정 근처에서 어긋난다.
          queryParameters: {
            if (distance != null) 'targetDistanceMeters': distance.meters,
          },
          options: Options(headers: {'Authorization': 'Bearer $token'}),
        );
        return slotsOf(response.data);
      });

  @override
  Future<int> apply({
    required String slotRaw,
    required TargetDistance distance,
  }) => _authorized((token) async {
    final response = await _dio.post<Map<String, dynamic>>(
      _path,
      // ⚠️ 서버가 준 문자열을 그대로 돌려보낸다. 다시 조립하지 않는다.
      data: {
        'scheduledStartAt': slotRaw,
        'targetDistanceMeters': distance.meters,
      },
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
    await _dio.delete<void>(
      _path,
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
  });

  /// 몸통에서 시간대 목록을 꺼낸다. **테스트가 직접 부른다.**
  ///
  /// 읽을 수 없는 항목은 **건너뛴다**. 슬롯 하나가 이상하다고 목록 전체를
  /// 버리면 매칭 자체를 못 하게 되는데, 한 칸이 비는 것이 그보다 가볍다.
  static List<MatchSlot> slotsOf(Map<String, dynamic>? body) {
    final slots = body?['slots'];
    if (slots is! List) return const [];

    final parsed = <MatchSlot>[];
    for (final slot in slots) {
      if (slot is! Map) continue;
      final raw = slot['scheduledStartAt'];
      if (raw is! String) continue;
      final startAt = DateTime.tryParse(raw);
      if (startAt == null) continue;
      final waiting = slot['waitingCount'];
      parsed.add(
        MatchSlot(
          raw: raw,
          startAt: startAt,
          waitingCount: waiting is int ? waiting : 0,
          // ⚠️ 없으면 잠근다. 모르는 슬롯을 열어두면 마감된 시간대를 눌러
          // 409를 맞는다 — 눌리지 않는 편이 낫다.
          selectable: slot['selectable'] == true,
        ),
      );
    }
    return parsed;
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
        return await call(await _refreshed(stored.refreshToken));
      } on DioException catch (retried) {
        throw exceptionOf(retried);
      }
    }
  }

  Future<String> _refreshed(String? refreshToken) async {
    if (refreshToken == null) {
      throw const MatchException(MatchFailure.sessionExpired);
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
      throw MatchException(
        error.failure == AuthFailure.network
            ? MatchFailure.network
            : MatchFailure.sessionExpired,
      );
    }
  }
}
