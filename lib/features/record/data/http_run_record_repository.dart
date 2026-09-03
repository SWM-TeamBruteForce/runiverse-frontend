import 'package:dio/dio.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/domain/token_refresher.dart';
import 'package:flutter/foundation.dart';
import 'package:runiverse/features/record/data/room_result_dto.dart';
import 'package:runiverse/features/record/data/run_record_dto.dart';
import 'package:runiverse/features/record/domain/run_detail.dart';
import 'package:runiverse/features/record/domain/run_record.dart';
import 'package:runiverse/features/record/domain/run_record_repository.dart';

/// 진짜 서버를 부르는 [RunRecordRepository]. 19번.
///
/// 401이면 **한 번만** 갱신하고 다시 부른다 — `HttpRunningRoomRepository`와
/// 같은 규칙이고, 갱신은 반드시 [TokenRefresher]를 거친다.
///
/// ## ⚠️ 아직 서버에 없다
///
/// 19번은 `개발전`이다. 명세대로 미리 짜 두되 **화면에는 물리지 않는다** —
/// provider가 `FakeRunRecordRepository`를 쓴다. 서버가 열리면 그 한 줄만 바꾼다.
class HttpRunRecordRepository implements RunRecordRepository {
  HttpRunRecordRepository(this._dio, this._store, this._refresher);

  final Dio _dio;
  final TokenStore _store;
  final TokenRefresher _refresher;

  static const _path = '/api/v1/users/me/running-records';

  /// 캘린더 모드가 한 번에 볼 수 있는 최대 일수. 넘기면 서버가 400을 준다.
  static const maxRangeDays = 31;

  @override
  Future<List<RunRecord>> byDateRange({
    required DateTime from,
    required DateTime to,
  }) async {
    // 서버에 물어보기 전에 여기서 걸러 낸다. 400을 받고 나서야 아는 것보다
    // 낫고, 무엇보다 이건 사용자 입력이 아니라 **앱의 버그**다.
    if (from.isAfter(to)) {
      throw const RunRecordException(RunRecordFailure.invalidRequest);
    }
    if (to.difference(from).inDays >= maxRangeDays) {
      throw const RunRecordException(RunRecordFailure.invalidRequest);
    }

    final page = await _get({'from': _day(from), 'to': _day(to)});
    return page.items;
  }

  @override
  Future<RunRecordPage> recent({String? cursor, int limit = 20}) =>
      // `?cursor` — 첫 페이지면 키 자체를 빼야 한다. `null`을 실어 보내면
      // 서버가 두 모드를 섞은 요청으로 볼 수 있다.
      _get({'cursor': ?cursor, 'limit': limit});

  @override
  Future<RunDetail> byRoom(int runningRoomId) async {
    // 둘을 동시에 보낸다. 줄 세우면 왕복이 두 배가 된다.
    final responses = await Future.wait([
      _authorized(
        (token) => _dio.get<Map<String, dynamic>>(
          '/api/v1/running-rooms/$runningRoomId/results',
          options: Options(headers: {'Authorization': 'Bearer $token'}),
        ),
      ),
      _authorized(
        (token) => _dio.get<Map<String, dynamic>>(
          '/api/v1/running-rooms/$runningRoomId/split-results',
          options: Options(headers: {'Authorization': 'Bearer $token'}),
        ),
      ),
    ]);

    final detail = RoomResultDto.merge(
      results: responses[0],
      splitResults: responses[1],
    );
    debugPrint(
      '[record] 방 $runningRoomId 결과를 받았다 · $detail · '
      '1km ${detail.tableSplits.length}구간 · 50m ${detail.chartSamples.length}점',
    );
    return detail;
  }

  Future<RunRecordPage> _get(Map<String, dynamic> query) async {
    final data = await _authorized(
      (token) => _dio.get<Map<String, dynamic>>(
        _path,
        queryParameters: query,
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      ),
    );
    return RunRecordDto.pageFrom(data);
  }

  /// 토큰을 실어 보내고, **401이면 한 번만** 갱신해서 다시 부른다.
  ///
  /// 두 호출(목록·상세)이 같은 규칙을 쓰도록 여기 모았다. 각자 재시도를
  /// 적으면 한쪽만 고쳐지는 일이 생긴다.
  Future<Map<String, dynamic>> _authorized(
    Future<Response<Map<String, dynamic>>> Function(String token) send,
  ) async {
    final stored = await _store.read();
    final accessToken = stored.accessToken;
    if (accessToken == null) {
      throw const RunRecordException(RunRecordFailure.sessionExpired);
    }

    try {
      return _body(await send(accessToken));
    } on DioException catch (error) {
      if (error.response?.statusCode != 401) {
        throw RunRecordException(_failureOf(error));
      }
      try {
        return _body(await send(await _refreshed()));
      } on DioException catch (retried) {
        throw RunRecordException(_failureOf(retried));
      }
    }
  }

  static Map<String, dynamic> _body(Response<Map<String, dynamic>> response) {
    final data = response.data;
    if (data == null) {
      throw const RunRecordException(RunRecordFailure.server);
    }
    return data;
  }

  Future<String> _refreshed() async {
    final accessToken = await _refresher.refresh();
    if (accessToken == null) {
      throw const RunRecordException(RunRecordFailure.sessionExpired);
    }
    return accessToken;
  }

  /// 서버가 받는 `YYYY-MM-DD`. **KST 달력 날짜**라 시각을 붙이지 않는다.
  static String _day(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  RunRecordFailure _failureOf(DioException error) {
    if (error.type != DioExceptionType.badResponse) {
      return RunRecordFailure.network;
    }
    final status = error.response?.statusCode ?? 0;
    if (status == 400) return RunRecordFailure.invalidRequest;
    if (status == 401) return RunRecordFailure.sessionExpired;
    if (status >= 500) return RunRecordFailure.server;
    return RunRecordFailure.server;
  }
}
